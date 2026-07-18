"""
SGT Patrol — YOLO26 (VisDrone) Detection Server
=================================================
Runs YOLO26 on a video file (or webcam/drone feed) and broadcasts
detection results over WebSocket to the Flutter operator app.

IMPORTANT — CPU vs GPU:
On CPU-only hardware, one inference pass can genuinely take 0.5-5+
seconds (confirmed via the SLOW inference logging below). That's a
real hardware limit, not a bug. What WAS fixable: video streaming is
now decoupled from detection, so the camera feed stays smooth and
continuous at all times, while detection runs in the background and
updates the drawn boxes whenever it finishes — even if that's a
second or two behind the current frame. This is the honest, correct
architecture for slow inference hardware: a laggy detector should
never mean a frozen video feed.

Usage:
    python detector.py --video assets/demo/patrol_demo.mp4
    python detector.py --video 0                              (webcam)
    python detector.py --video rtsp://your-drone-stream       (live feed)

The Flutter app connects to ws://localhost:8765 and receives JSON
detection events in real time.
"""

import asyncio
import websockets
import json
import cv2
import argparse
import base64
import time
import uuid
import sqlite3
from concurrent.futures import ThreadPoolExecutor
from ultralytics import YOLO
import torch

# -------------------------------------------------------------------------
# Config
# -------------------------------------------------------------------------

PORT = 8765
MIN_CONFIDENCE = 0.4          # raise this (e.g. 0.5) if you're getting noisy/low-quality detections
DETECT_EVERY_N_FRAMES = 5     # how often a NEW detection pass is kicked off — video keeps streaming regardless
INFERENCE_SIZE = 416          # lower than default 640 — smaller = faster on CPU, some accuracy tradeoff
STREAM_FPS_CAP = 20           # video send rate — independent of detection speed now
DB_PATH = 'patrol_events.db'

print(f'[SGT] CUDA (GPU) available: {torch.cuda.is_available()}')
if not torch.cuda.is_available():
    print('[SGT] Running on CPU — inference will be noticeably slower than on Kaggle\'s GPU.')

# VisDrone class names -> operator-facing labels
DETECT_CLASSES = {
    'pedestrian':      {'label': 'PERSON',  'priority': 'high',   'color': (0, 0, 255)},
    'people':          {'label': 'PERSON',  'priority': 'high',   'color': (0, 0, 255)},
    'car':             {'label': 'VEHICLE', 'priority': 'medium', 'color': (0, 165, 255)},
    'van':             {'label': 'VEHICLE', 'priority': 'medium', 'color': (0, 165, 255)},
    'truck':           {'label': 'VEHICLE', 'priority': 'medium', 'color': (0, 165, 255)},
    'bus':             {'label': 'VEHICLE', 'priority': 'medium', 'color': (0, 165, 255)},
    'motor':           {'label': 'VEHICLE', 'priority': 'medium', 'color': (0, 165, 255)},
    'bicycle':         {'label': 'VEHICLE', 'priority': 'low',    'color': (0, 165, 255)},
    'tricycle':        {'label': 'VEHICLE', 'priority': 'low',    'color': (0, 165, 255)},
    'awning-tricycle': {'label': 'VEHICLE', 'priority': 'low',    'color': (0, 165, 255)},
}

# -------------------------------------------------------------------------
# Event log (SQLite) — one persistent connection, opened once.
# -------------------------------------------------------------------------

_db_conn = None

def init_db():
    global _db_conn
    _db_conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    _db_conn.execute('''
        CREATE TABLE IF NOT EXISTS detection_events (
            id TEXT PRIMARY KEY,
            timestamp REAL,
            class_name TEXT,
            confidence INTEGER,
            bbox TEXT,
            operator_action TEXT,
            operator_response_timestamp REAL
        )
    ''')
    _db_conn.commit()
    print(f'[SGT] Event log ready at {DB_PATH}')


def log_detection(event_id, class_name, confidence, bbox):
    _db_conn.execute(
        '''INSERT INTO detection_events
           (id, timestamp, class_name, confidence, bbox, operator_action)
           VALUES (?, ?, ?, ?, ?, NULL)''',
        (event_id, time.time(), class_name, confidence, json.dumps(bbox))
    )
    _db_conn.commit()


def log_operator_response(event_id, response):
    _db_conn.execute(
        '''UPDATE detection_events
           SET operator_action = ?, operator_response_timestamp = ?
           WHERE id = ?''',
        (response, time.time(), event_id)
    )
    _db_conn.commit()
    print(f'[SGT] Logged operator response: {event_id} -> {response}')


# -------------------------------------------------------------------------
# Detector
# -------------------------------------------------------------------------

class SGTDetector:
    def __init__(self, video_src):
        print('[SGT] Loading YOLO26 (VisDrone) model...')
        self.model = YOLO('best.pt')  # rename to match your actual downloaded weights file
        print('[SGT] Model loaded')

        self.video_src = video_src
        self.clients = set()
        self.running = False
        self.last_detected = {}
        self._executor = ThreadPoolExecutor(max_workers=1)

        # Detection runs independently of the video stream. The stream
        # always draws whatever is in _cached_boxes, updated whenever a
        # background detection pass finishes — could be a frame or two
        # (or a couple seconds, on slow CPUs) behind the live picture.
        self._cached_boxes = []          # boxes to draw on every streamed frame
        self._pending_new_detections = []  # new detections to attach to the next outgoing message
        self._inference_in_flight = False

    def _should_send(self, key):
        now = time.time()
        last = self.last_detected.get(key, 0)
        if now - last < 5:
            return False
        self.last_detected[key] = now
        return True

    def _frame_to_base64(self, frame):
        _, buffer = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 60])
        return base64.b64encode(buffer).decode('utf-8')

    def _run_inference(self, frame):
        """Runs in a background thread via run_in_executor — the actual
        blocking call, kept OFF the asyncio event loop."""
        t0 = time.time()
        result = self.model(frame, verbose=False, imgsz=INFERENCE_SIZE)[0]
        elapsed = time.time() - t0
        if elapsed > 0.5:
            print(f'[SGT] SLOW inference: {elapsed:.2f}s for one frame — likely CPU-bound')
        return result

    async def _detect_async(self, frame):
        """Kicked off periodically via asyncio.create_task — does NOT
        block the main streaming loop. Updates _cached_boxes and queues
        any new (throttled) detections once inference completes."""
        self._inference_in_flight = True
        try:
            loop = asyncio.get_event_loop()
            results = await loop.run_in_executor(self._executor, self._run_inference, frame)

            boxes = []
            new_detections = []

            for box in results.boxes:
                class_id = int(box.cls[0])
                class_name = self.model.names[class_id]
                confidence = float(box.conf[0])

                if class_name not in DETECT_CLASSES:
                    continue
                if confidence < MIN_CONFIDENCE:
                    continue

                info = DETECT_CLASSES[class_name]
                x1, y1, x2, y2 = map(int, box.xyxy[0])

                boxes.append({
                    'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2,
                    'color': info['color'],
                    'label_text': f"{info['label']} {int(confidence * 100)}%",
                })

                # Throttle by LABEL (PERSON/VEHICLE), not raw class —
                # multiple vehicle subtypes in one pass share one window.
                throttle_key = info['label']
                if self._should_send(throttle_key):
                    event_id = str(uuid.uuid4())
                    bbox = [x1, y1, x2 - x1, y2 - y1]
                    log_detection(event_id, class_name, int(confidence * 100), bbox)
                    new_detections.append({
                        'id': event_id,
                        'class': class_name,
                        'label': info['label'],
                        'confidence': int(confidence * 100),
                        'priority': info['priority'],
                        'bbox': bbox,
                        'timestamp': int(time.time() * 1000),
                    })

            self._cached_boxes = boxes
            self._pending_new_detections.extend(new_detections)
        finally:
            self._inference_in_flight = False

    def _draw_cached_boxes(self, frame):
        """Cheap — just drawing, no inference. Runs every streamed frame."""
        for b in self._cached_boxes:
            x1, y1, x2, y2 = b['x1'], b['y1'], b['x2'], b['y2']
            color = b['color']
            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)

            br = 12
            cv2.line(frame, (x1, y1), (x1 + br, y1), color, 2)
            cv2.line(frame, (x1, y1), (x1, y1 + br), color, 2)
            cv2.line(frame, (x2, y1), (x2 - br, y1), color, 2)
            cv2.line(frame, (x2, y1), (x2, y1 + br), color, 2)
            cv2.line(frame, (x1, y2), (x1 + br, y2), color, 2)
            cv2.line(frame, (x1, y2), (x1, y2 - br), color, 2)
            cv2.line(frame, (x2, y2), (x2 - br, y2), color, 2)
            cv2.line(frame, (x2, y2), (x2, y2 - br), color, 2)

            label = b['label_text']
            cv2.rectangle(frame, (x1, y1 - 20), (x1 + len(label) * 8, y1), color, -1)
            cv2.putText(frame, label, (x1 + 2, y1 - 5),
                cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1)
        return frame

    async def run(self):
        self.running = True
        src = int(self.video_src) if self.video_src == '0' else self.video_src
        cap = cv2.VideoCapture(src)

        if not cap.isOpened():
            print(f'[SGT] ERROR: Could not open video: {self.video_src}')
            return

        print(f'[SGT] Detection running on: {self.video_src}')
        frame_count = 0
        min_frame_interval = 1.0 / STREAM_FPS_CAP

        while self.running:
            loop_start = time.time()
            ret, frame = cap.read()

            if not ret:
                cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                continue

            frame_count += 1

            # Kick off a NEW detection pass periodically, in the
            # background — never blocks the streaming loop below.
            if frame_count % DETECT_EVERY_N_FRAMES == 0 and not self._inference_in_flight:
                asyncio.create_task(self._detect_async(frame.copy()))

            # Streaming happens every loop iteration regardless of
            # detection speed — this is what keeps the feed smooth.
            annotated_frame = self._draw_cached_boxes(frame.copy())

            if self.clients:
                frame_b64 = self._frame_to_base64(annotated_frame)
                detections = self._pending_new_detections
                self._pending_new_detections = []  # only send new ones once

                message = json.dumps({
                    'type': 'frame',
                    'frame': frame_b64,
                    'detections': detections,
                })

                disconnected = set()
                for client in self.clients:
                    try:
                        await client.send(message)
                    except websockets.exceptions.ConnectionClosed:
                        disconnected.add(client)
                self.clients -= disconnected

            # Cap the stream rate rather than a fixed sleep — keeps
            # frame delivery steady regardless of how long the above took.
            elapsed = time.time() - loop_start
            await asyncio.sleep(max(0.0, min_frame_interval - elapsed))

        cap.release()
        print('[SGT] Detection stopped')

    def stop(self):
        self.running = False


# -------------------------------------------------------------------------
# WebSocket server
# -------------------------------------------------------------------------

detector = None

async def handle_client(websocket):
    print(f'[SGT] Client connected: {websocket.remote_address}')
    detector.clients.add(websocket)
    try:
        async for message in websocket:
            try:
                cmd = json.loads(message)
                action = cmd.get('action')

                if action == 'stop':
                    detector.stop()

                elif action == 'operator_response':
                    event_id = cmd.get('id')
                    response = cmd.get('response')
                    if event_id and response in ('confirmed', 'dismissed'):
                        log_operator_response(event_id, response)

            except json.JSONDecodeError:
                pass
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        detector.clients.discard(websocket)
        print(f'[SGT] Client disconnected: {websocket.remote_address}')


async def main(video_src):
    global detector
    init_db()
    detector = SGTDetector(video_src)

    print(f'[SGT] Starting WebSocket server on ws://localhost:{PORT}')

    async with websockets.serve(handle_client, 'localhost', PORT):
        await detector.run()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='SGT Patrol Detection Server')
    parser.add_argument('--video', default='0',
        help='Video source: path to mp4, 0 for webcam, or RTSP URL')
    args = parser.parse_args()

    try:
        asyncio.run(main(args.video))
    except KeyboardInterrupt:
        print('\n[SGT] Server stopped')
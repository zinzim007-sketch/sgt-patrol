"""
SGT Patrol — YOLOv8 Detection Server
=====================================
Runs YOLOv8 on a video file (or webcam/drone feed) and broadcasts
detection results over WebSocket to the Flutter operator app.

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
from ultralytics import YOLO

# -------------------------------------------------------------------------
# Config
# -------------------------------------------------------------------------

PORT = 8765
MIN_CONFIDENCE = 0.35

DETECT_CLASSES = {
    'person':       {'label': 'PERSON',   'priority': 'high',   'color': (0, 0, 255)},
    'car':          {'label': 'VEHICLE',  'priority': 'medium', 'color': (0, 165, 255)},
    'truck':        {'label': 'VEHICLE',  'priority': 'medium', 'color': (0, 165, 255)},
    'motorcycle':   {'label': 'VEHICLE',  'priority': 'medium', 'color': (0, 165, 255)},
    'bus':          {'label': 'VEHICLE',  'priority': 'medium', 'color': (0, 165, 255)},
    'bicycle':      {'label': 'VEHICLE',  'priority': 'medium', 'color': (0, 165, 255)},
    'dog':          {'label': 'ANIMAL',   'priority': 'low',    'color': (0, 255, 0)},
    'cat':          {'label': 'ANIMAL',   'priority': 'low',    'color': (0, 255, 0)},
    'horse':        {'label': 'ANIMAL',   'priority': 'low',    'color': (0, 255, 0)},
    'cow':          {'label': 'ANIMAL',   'priority': 'low',    'color': (0, 255, 0)},
    'sheep':        {'label': 'ANIMAL',   'priority': 'low',    'color': (0, 255, 0)},
}

# -------------------------------------------------------------------------
# Detector
# -------------------------------------------------------------------------

class SGTDetector:
    def __init__(self, video_src):
        print('[SGT] Loading YOLOv8 model...')
        
        self.model = YOLO('yolo26n-visdrone-best.pt')  
   
        print('[SGT] Model loaded')

        self.video_src = video_src
        self.clients = set()
        self.running = False
        self.last_detected = {}

    def _should_send(self, class_name):
        now = time.time()
        last = self.last_detected.get(class_name, 0)
        if now - last < 3:
            return False
        self.last_detected[class_name] = now
        return True

    def _frame_to_base64(self, frame):
        _, buffer = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 60])
        return base64.b64encode(buffer).decode('utf-8')

    async def run(self):
        self.running = True
        src = int(self.video_src) if self.video_src == '0' else self.video_src
        cap = cv2.VideoCapture(src)

        if not cap.isOpened():
            print(f'[SGT] ERROR: Could not open video: {self.video_src}')
            return

        print(f'[SGT] Detection running on: {self.video_src}')
        frame_count = 0

        while self.running:
            ret, frame = cap.read()

            if not ret:
                # Loop video for demo
                cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                continue

            frame_count += 1

            # Run detection every 3rd frame for performance
            if frame_count % 3 != 0:
                await asyncio.sleep(0.01)
                continue

            results = self.model(frame, verbose=False)[0]
            detections = []
            annotated_frame = frame.copy()

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
                color = info['color']

                # Bounding box
                cv2.rectangle(annotated_frame, (x1, y1), (x2, y2), color, 2)

                # Corner brackets
                b = 12
                cv2.line(annotated_frame, (x1, y1), (x1 + b, y1), color, 2)
                cv2.line(annotated_frame, (x1, y1), (x1, y1 + b), color, 2)
                cv2.line(annotated_frame, (x2, y1), (x2 - b, y1), color, 2)
                cv2.line(annotated_frame, (x2, y1), (x2, y1 + b), color, 2)
                cv2.line(annotated_frame, (x1, y2), (x1 + b, y2), color, 2)
                cv2.line(annotated_frame, (x1, y2), (x1, y2 - b), color, 2)
                cv2.line(annotated_frame, (x2, y2), (x2 - b, y2), color, 2)
                cv2.line(annotated_frame, (x2, y2), (x2, y2 - b), color, 2)

                # Label
                label = f"{info['label']} {int(confidence * 100)}%"
                cv2.rectangle(annotated_frame, (x1, y1 - 20),
                    (x1 + len(label) * 8, y1), color, -1)
                cv2.putText(annotated_frame, label, (x1 + 2, y1 - 5),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1)

                if self._should_send(class_name):
                    detections.append({
                        'class': class_name,
                        'label': info['label'],
                        'confidence': int(confidence * 100),
                        'priority': info['priority'],
                        'bbox': [x1, y1, x2 - x1, y2 - y1],
                        'timestamp': int(time.time() * 1000),
                    })

            if self.clients:
                frame_b64 = self._frame_to_base64(annotated_frame)
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

            await asyncio.sleep(0.03)

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
                if cmd.get('action') == 'stop':
                    detector.stop()
            except json.JSONDecodeError:
                pass
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        detector.clients.discard(websocket)
        print(f'[SGT] Client disconnected: {websocket.remote_address}')


async def main(video_src):
    global detector
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

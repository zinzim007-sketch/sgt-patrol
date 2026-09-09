#!/usr/bin/env python3
"""
gcs_web.py — web GCS + panic dispatch for ArduCopter over MAVLink.
Runs on the LAPTOP. Connects to SITL or to a MAVLink relay.

    pip install flask pymavlink
    python gcs_web.py
    open http://127.0.0.1:8080
"""

import json
import math
import threading
import time
import urllib.error
import urllib.request
from collections import deque

from flask import Flask, Response, jsonify, request
from pymavlink import mavutil

# ─── link ─────────────────────────────────────────────────────────────────────

# SITL SERIAL1:            'tcp:127.0.0.1:5762'
# Real hardware via VM:    'tcp:40.123.253.60:5760'
CONNECT = 'tcp:127.0.0.1:5760'

# --- SIMULATOR SETTINGS — review every one of these before real hardware ---
ALLOW_ARM = True                  # False on hardware: arm from the TX16S
GUIDED_PWM_RANGE = (900, 2100)    # wide open for SITL (no TX connected).
                                  # On hardware: narrow to the GUIDED detent only.
MOTOR_TEST_ENABLED = True         # False before any flight
# ---------------------------------------------------------------------------

MODE_SWITCH_CHAN = 5              # TX16S channel carrying the flight mode switch
ALT_MIN, ALT_MAX = 5.0, 60.0      # metres above home — set to your real envelope
HB_TIMEOUT = 3.0                  # seconds without a vehicle heartbeat = stale

# ─── panic dispatch ───────────────────────────────────────────────────────────

PANIC_URL      = 'https://40-123-253-60.sslip.io'
OPERATOR_TOKEN = '1F9CL6R4byPsrU7JYQaa1xwaradWYF_8'    # must match ~/panic/env on the VM

TRANSIT_ALT      = 33.0    # metres above home for the transit leg
OBSERVE_ALT      = 20.0    # metres above home once on station
STANDOFF_M       = 20.0    # horizontal distance held from the panic point
DEFAULT_APPROACH = 0.0     # bearing used if vehicle is already on the target
MAX_DISPATCH_M   = 250.0  # refuse coordinates further than this from the vehicle
ARRIVE_RADIUS_M  = 10.0    # considered "on station" inside this radius
ALERT_POLL_S     = 3.0     # how often to pull the alert list from the VM

# ─── video ────────────────────────────────────────────────────────────────────

STREAM_HOST = '40.123.253.60'
STREAM_PORT = 8889
STREAM_PATH = 'live'               # ← your MediaMTX path name
STREAM_URL  = f'http://{STREAM_HOST}:{STREAM_PORT}/{STREAM_PATH}/'

# ─── motor test ───────────────────────────────────────────────────────────────

MOTOR_TEST_MAX_PCT = 15.0         # hard ceiling on throttle percentage
MOTOR_TEST_MAX_SEC = 3.0          # hard ceiling on duration
MOTOR_COUNT        = 6            # X650 hexacopter

# ──────────────────────────────────────────────────────────────────────────────

MODES = {'STABILIZE': 0, 'ALT_HOLD': 2, 'AUTO': 3, 'GUIDED': 4,
         'LOITER': 5, 'RTL': 6, 'LAND': 9, 'BRAKE': 17}

# Commands always permitted, gate open or not — recovery must never be blocked.
RECOVERY_MODES = {'RTL', 'LAND', 'BRAKE', 'LOITER', 'ALT_HOLD'}

app = Flask(__name__)

state = {
    'connected': False, 'mode': None, 'armed': False,
    'lat': None, 'lon': None, 'rel_alt': None, 'gs': None,
    'volt': None, 'curr': None, 'sats': None, 'hdop': None,
    'batt': None, 'hdg': None,
    'mode_chan': 0, 'last_hb': 0.0,
    'msg_rate': 0.0, 'hb_rate': 0.0, 'bad_rate': 0.0, 'ack_ms': None,
}
mission = {'active': False, 'phase': 'idle', 'target': None, 'hold': None,
           'dist': None, 'abort': False, 'alert_id': None}

# Waypoint patrol-route mission (MISSION_COUNT / MISSION_ITEM_INT protocol),
# separate from the panic 'mission' dict above which tracks the dispatch
# sequencer. 'state' here is this module's own idle/uploading/ready/
# executing/error, not to be confused with the vehicle telemetry `state`
# dict above — unfortunate name collision, kept local to this block.
route_mission = {
    'state': 'idle', 'total': 0, 'current_wp': 0,
    'message': 'No mission loaded', 'error': None,
}
route_lock = threading.Lock()

# Filled by _pump() as MISSION_REQUEST_INT / MISSION_ACK arrive, drained by
# _upload_mission() running in its own thread. Kept as plain lists behind
# route_lock rather than queue.Queue so a fresh upload can clear stale
# entries left over from a previous, unrelated exchange.
_mission_request_queue = []
_mission_ack_queue = []
pending = {'alerts': [], 'error': None, 'ts': 0.0}

rates = {'count': 0, 'hb': 0, 'bad': 0, 'window': time.time()}
pending_cmd = {}                   # MAV command id -> send timestamp

messages = deque(maxlen=40)        # STATUSTEXT + COMMAND_ACK, newest first
lock = threading.Lock()
master = None
ready = threading.Event()

# Human-readable names for the MAV_RESULT enum returned in COMMAND_ACK.
ACK_RESULT = {
    0: 'ACCEPTED', 1: 'TEMPORARILY_REJECTED', 2: 'DENIED',
    3: 'UNSUPPORTED', 4: 'FAILED', 5: 'IN_PROGRESS',
    6: 'CANCELLED', 7: 'LONG_ONLY', 8: 'INT_ONLY', 9: 'UNSUPPORTED_FRAME',
}


def note(text, level='info'):
    """Record a line for the browser log panel."""
    with lock:
        messages.appendleft({'t': time.strftime('%H:%M:%S'),
                             'text': text, 'level': level})


# ─── geometry ─────────────────────────────────────────────────────────────────

def haversine(lat1, lon1, lat2, lon2):
    """Great-circle distance in metres."""
    R = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = (math.sin(dp / 2) ** 2 +
         math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2)
    return 2 * R * math.asin(math.sqrt(a))


def bearing(lat1, lon1, lat2, lon2):
    """Initial great-circle bearing in degrees from point 1 to point 2."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dl = math.radians(lon2 - lon1)
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return (math.degrees(math.atan2(y, x)) + 360) % 360


def offset_point(lat, lon, bearing_deg, dist_m):
    """Point dist_m away from (lat, lon) along bearing_deg."""
    b, d = math.radians(bearing_deg), dist_m / 6371000.0
    p1, l1 = math.radians(lat), math.radians(lon)
    p2 = math.asin(math.sin(p1) * math.cos(d) +
                   math.cos(p1) * math.sin(d) * math.cos(b))
    l2 = l1 + math.atan2(math.sin(b) * math.sin(d) * math.cos(p1),
                         math.cos(d) - math.sin(p1) * math.sin(p2))
    return math.degrees(p2), (math.degrees(l2) + 540) % 360 - 180


# ─── receive thread ───────────────────────────────────────────────────────────

def rx_loop():
    global master
    while True:
        try:
            note(f'connecting to {CONNECT}')
            master = mavutil.mavlink_connection(CONNECT, source_system=250)
            master.wait_heartbeat()
            note(f'heartbeat from system {master.target_system}', 'good')

            # Ask ArduPilot for the message groups we care about, in Hz.
            for sid, rate in ((mavutil.mavlink.MAV_DATA_STREAM_POSITION, 4),
                              (mavutil.mavlink.MAV_DATA_STREAM_EXTRA1, 4),
                              (mavutil.mavlink.MAV_DATA_STREAM_RC_CHANNELS, 4),
                              (mavutil.mavlink.MAV_DATA_STREAM_EXTENDED_STATUS, 2)):
                master.mav.request_data_stream_send(
                    master.target_system, master.target_component, sid, rate, 1)

            ready.set()
            _pump()

        except Exception as exc:
            ready.clear()
            with lock:
                state['connected'] = False
            note(f'link error: {exc}', 'bad')
            time.sleep(3)


def _pump():
    """Read messages until the link goes quiet."""
    while True:
        m = master.recv_match(blocking=True, timeout=5)
        if m is None:
            with lock:
                state['connected'] = False
            continue

        # Ignore other GCSes and components sharing the link — without this,
        # their heartbeats overwrite mode/armed and the UI flickers.
        if m.get_srcSystem() != master.target_system:
            continue

        t = m.get_type()
        if t == 'BAD_DATA':
            with lock:
                rates['bad'] += 1
            continue

        with lock:
            state['connected'] = True

            # ── link statistics ──
            rates['count'] += 1
            if t == 'HEARTBEAT':
                rates['hb'] += 1
            elapsed = time.time() - rates['window']
            if elapsed >= 2.0:
                state['msg_rate'] = rates['count'] / elapsed
                state['hb_rate'] = rates['hb'] / elapsed
                state['bad_rate'] = rates['bad'] / elapsed
                rates.update(count=0, hb=0, bad=0, window=time.time())

            # ── telemetry ──
            if t == 'HEARTBEAT':
                state['mode'] = mavutil.mode_string_v10(m)
                state['armed'] = bool(m.base_mode &
                                      mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED)
                state['last_hb'] = time.time()

            elif t == 'GLOBAL_POSITION_INT':
                state['lat'] = m.lat / 1e7          # degE7 → degrees
                state['lon'] = m.lon / 1e7
                state['rel_alt'] = m.relative_alt / 1000.0   # mm → m above home
                # hdg is centidegrees, 65535 = unknown.
                state['hdg'] = m.hdg / 100.0 if m.hdg != 65535 else None

            elif t == 'VFR_HUD':
                state['gs'] = m.groundspeed

            elif t == 'SYS_STATUS':
                state['volt'] = m.voltage_battery / 1000.0   # mV → V
                state['curr'] = (m.current_battery / 100.0
                                 if m.current_battery >= 0 else None)
                # battery_remaining is percent, -1 = unknown.
                state['batt'] = (m.battery_remaining
                                 if m.battery_remaining >= 0 else None)

            elif t == 'GPS_RAW_INT':
                state['sats'] = m.satellites_visible
                state['hdop'] = m.eph / 100.0 if m.eph < 65535 else None

            elif t == 'RC_CHANNELS':
                state['mode_chan'] = getattr(m, f'chan{MODE_SWITCH_CHAN}_raw', 0)

        # Outside the lock — note() takes it itself.
        if t == 'STATUSTEXT':
            sev = m.severity
            lvl = 'bad' if sev <= 3 else ('warn' if sev <= 5 else 'info')
            note(m.text.strip(), lvl)

        elif t == 'COMMAND_ACK':
            res = ACK_RESULT.get(m.result, str(m.result))
            lvl = 'good' if m.result == 0 else 'bad'
            sent = pending_cmd.pop(m.command, None)
            if sent is not None:
                rtt = (time.time() - sent) * 1000.0
                with lock:
                    state['ack_ms'] = rtt
                note(f'ACK cmd {m.command}: {res} ({rtt:.0f} ms)', lvl)
            else:
                note(f'ACK cmd {m.command}: {res}', lvl)

        elif t == 'MISSION_ITEM_REACHED':
            # Fired by the FC during AUTO mission execution. seq 0 is the
            # home item we upload but never "reach" in a meaningful sense,
            # so only real waypoints (seq >= 1) update progress.
            with route_lock:
                if m.seq >= 1:
                    route_mission['current_wp'] = m.seq
                    if (route_mission['state'] == 'executing'
                            and m.seq >= route_mission['total']):
                        route_mission['state'] = 'complete'
                        route_mission['message'] = 'Patrol complete'
            note(f'waypoint {m.seq} reached', 'good')

        elif t == 'MISSION_ACK':
            with route_lock:
                _mission_ack_queue.append(m.type)

        elif t == 'MISSION_REQUEST_INT' or t == 'MISSION_REQUEST':
            with route_lock:
                _mission_request_queue.append(m.seq)


def hb_loop():
    """Emit a GCS heartbeat at 1 Hz so FS_GCS_ENABLE doesn't trip on us."""
    ready.wait()
    while True:
        try:
            master.mav.heartbeat_send(
                mavutil.mavlink.MAV_TYPE_GCS,
                mavutil.mavlink.MAV_AUTOPILOT_INVALID, 0, 0, 0)
        except Exception:
            pass
        time.sleep(1)


def poll_alerts():
    """Pull pending panic alerts from the VM every few seconds."""
    while True:
        try:
            req = urllib.request.Request(
                PANIC_URL + '/alerts', headers={'X-Token': OPERATOR_TOKEN})
            with urllib.request.urlopen(req, timeout=8) as r:
                data = json.loads(r.read().decode())
            with lock:
                pending['alerts'] = [a for a in data
                                     if a.get('status') == 'pending']
                pending['error'] = None
                pending['ts'] = time.time()
        except urllib.error.HTTPError as exc:
            with lock:
                pending['error'] = (f'HTTP {exc.code} from panic server'
                                    + (' — check OPERATOR_TOKEN'
                                       if exc.code == 401 else ''))
        except Exception as exc:
            with lock:
                pending['error'] = str(exc)
        time.sleep(ALERT_POLL_S)


# ─── the gate ─────────────────────────────────────────────────────────────────

def gate():
    """
    Returns None when companion commands are permitted, else a reason string.

    NOTE: this runs on the laptop. The flight controller does not know it
    exists and does not enforce it. Real authority is the TX16S mode switch
    and the RCx_OPTION=31 motor e-stop, both enforced in the Pixhawk.
    """
    with lock:
        pwm, hb = state['mode_chan'], state['last_hb']

    if not ready.is_set():
        return 'not connected to vehicle'
    if time.time() - hb > HB_TIMEOUT:
        return 'no recent heartbeat from vehicle'
    if not (GUIDED_PWM_RANGE[0] <= pwm <= GUIDED_PWM_RANGE[1]):
        return f'mode switch not in companion position (ch{MODE_SWITCH_CHAN}={pwm})'
    return None


def snapshot():
    with lock:
        return dict(state)


def require(guided=False, armed=False):
    """Common precondition checks. Returns (message, http_status) or None."""
    if g := gate():
        return g, 403
    s = snapshot()
    if guided and s['mode'] != 'GUIDED':
        return f"vehicle in {s['mode']}, must be GUIDED", 409
    if armed and not s['armed']:
        return 'vehicle not armed', 409
    return None


# ─── senders ──────────────────────────────────────────────────────────────────

def _send_command(cmd, *params):
    """command_long with round-trip timing."""
    p = list(params) + [0.0] * (7 - len(params))
    pending_cmd[cmd] = time.time()
    master.mav.command_long_send(
        master.target_system, master.target_component, cmd, 0, *p[:7])


def _send_position(lat, lon, alt):
    """
    Type mask 0b110111111000 is an IGNORE mask, LSB first:
      bits 0-2   clear -> use x, y, z
      bits 3-8   set   -> ignore velocity and acceleration
      bits 10-11 set   -> ignore yaw and yaw rate
    Frame GLOBAL_RELATIVE_ALT_INT: alt is metres above the HOME position,
    not above terrain and not above sea level.
    """
    master.mav.set_position_target_global_int_send(
        0, master.target_system, master.target_component,
        mavutil.mavlink.MAV_FRAME_GLOBAL_RELATIVE_ALT_INT,
        0b110111111000,
        int(lat * 1e7), int(lon * 1e7), alt,
        0, 0, 0,      # velocity  (ignored)
        0, 0, 0,      # accel     (ignored)
        0, 0)         # yaw, yaw rate (ignored)


# ─── mission sequencer ────────────────────────────────────────────────────────

def wait_for(predicate, timeout, label):
    """Poll until predicate(snapshot) is true. False on abort or timeout."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if mission['abort']:
            note(f'dispatch aborted during {label}', 'warn')
            return False
        if predicate(snapshot()):
            return True
        time.sleep(0.4)
    note(f'dispatch timed out waiting for {label}', 'bad')
    return False


def run_dispatch(lat, lon, alert_id):
    """
    Ground -> transit altitude -> standoff point -> observation altitude,
    facing the panic coordinate. Never overflies the target.
    Leaving GUIDED, or any recovery command, stops it.
    """
    try:
        mission.update(active=True, abort=False, phase='planning',
                       target=[lat, lon], hold=None, dist=None,
                       alert_id=alert_id)

        # Hold point: STANDOFF_M from the target, on the side the vehicle is
        # approaching from, so the aircraft stops short rather than overflying.
        s = snapshot()
        if s['lat'] is None:
            note('dispatch aborted: no position fix', 'bad')
            return

        if haversine(s['lat'], s['lon'], lat, lon) < 5.0:
            brg = DEFAULT_APPROACH
            note(f'vehicle already at target; using fixed approach bearing '
                 f'{brg:.0f} deg', 'warn')
        else:
            brg = bearing(lat, lon, s['lat'], s['lon'])

        hold_lat, hold_lon = offset_point(lat, lon, brg, STANDOFF_M)
        look = bearing(hold_lat, hold_lon, lat, lon)
        mission['hold'] = [hold_lat, hold_lon]

        note(f'DISPATCH to {lat:.6f}, {lon:.6f} — holding {STANDOFF_M:.0f} m '
             f'out on bearing {brg:.0f} deg, facing {look:.0f} deg', 'warn')

        # 1. arm
        mission['phase'] = 'arming'
        _send_command(mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM, 1.0)
        if not wait_for(lambda s: s['armed'], 12, 'arm'):
            return

        # 2. climb to transit altitude
        mission['phase'] = 'takeoff'
        _send_command(mavutil.mavlink.MAV_CMD_NAV_TAKEOFF,
                      0, 0, 0, 0, 0, 0, TRANSIT_ALT)
        if not wait_for(lambda s: (s['rel_alt'] or 0) >= TRANSIT_ALT - 1.5,
                        90, 'takeoff'):
            return

        # 3. transit to the HOLD point, not the target
        mission['phase'] = 'transit'
        last_send = 0.0
        while True:
            if mission['abort']:
                note('dispatch aborted during transit', 'warn')
                return
            s = snapshot()
            if s['mode'] != 'GUIDED':
                note(f"dispatch stopped: vehicle left GUIDED ({s['mode']})",
                     'warn')
                return
            if s['lat'] is None:
                time.sleep(0.4)
                continue
            d = haversine(s['lat'], s['lon'], hold_lat, hold_lon)
            mission['dist'] = d
            if d <= ARRIVE_RADIUS_M:
                break
            if time.time() - last_send > 3:
                _send_position(hold_lat, hold_lon, TRANSIT_ALT)
                last_send = time.time()
            time.sleep(0.4)

        # 4. descend to observation altitude
        mission['phase'] = 'descending'
        note('at standoff point — descending to observation altitude')
        _send_position(hold_lat, hold_lon, OBSERVE_ALT)
        wait_for(lambda s: abs((s['rel_alt'] or 0) - OBSERVE_ALT) < 1.5,
                 60, 'descent')
        if mission['abort']:
            return

        # 5. point the nose at the scene
        mission['phase'] = 'orienting'
        _send_command(mavutil.mavlink.MAV_CMD_CONDITION_YAW,
                      look, 25.0, 1.0, 0.0)
        time.sleep(6)

        mission['phase'] = 'on station'
        note(f'ON STATION — {STANDOFF_M:.0f} m from scene at '
             f'{OBSERVE_ALT:.0f} m, facing it. Operator has control.', 'good')

    except Exception as exc:
        note(f'dispatch failed: {exc}', 'bad')
        mission['phase'] = 'failed'
    finally:
        mission['active'] = False


# ─── waypoint mission upload ───────────────────────────────────────────────────
#
# ArduCopter mission protocol (MAVLink "mission" microservice), matching the
# handshake the operator app previously ran itself over a raw MAVLink socket:
#
#   GCS  -- MISSION_COUNT(count) -->  FC
#   FC   -- MISSION_REQUEST_INT(seq) --> GCS      (repeated, seq 0..count-1)
#   GCS  -- MISSION_ITEM_INT(seq, ...) --> FC
#   FC   -- MISSION_ACK(type) -->  GCS             (once all items sent)
#
# seq 0 is always the home position. ArduCopter fills in home's actual
# lat/lon/alt itself — the item we send for seq 0 is a placeholder frame,
# same convention the old Dart _sendHomeWaypoint() used.
#
# MAV_MISSION_ACCEPTED = 0 (pymavlink doesn't expose a constant map for
# this the way it does for MAV_RESULT, so it's decoded inline).
MAV_MISSION_ACCEPTED = 0
MISSION_ACK_RESULT = {
    0: 'ACCEPTED', 1: 'ERROR', 2: 'UNSUPPORTED_FRAME', 3: 'UNSUPPORTED',
    4: 'NO_SPACE', 5: 'INVALID', 6: 'INVALID_PARAM1', 7: 'INVALID_PARAM2',
    8: 'INVALID_PARAM3', 9: 'INVALID_PARAM4', 10: 'INVALID_PARAM5_X',
    11: 'INVALID_PARAM6_Y', 12: 'INVALID_PARAM7', 13: 'INVALID_SEQUENCE',
    14: 'DENIED',
}


def _send_home_item():
    """seq 0 — placeholder home item; ArduCopter substitutes real home."""
    master.mav.mission_item_int_send(
        master.target_system, master.target_component,
        0,                                          # seq
        mavutil.mavlink.MAV_FRAME_GLOBAL,
        mavutil.mavlink.MAV_CMD_NAV_WAYPOINT,
        0, 1,                                       # current, autocontinue
        0, 0, 0, 0,                                 # param1-4
        0, 0, 0,                                    # x, y, z
        mavutil.mavlink.MAV_MISSION_TYPE_MISSION)


def _send_waypoint_item(seq, wp):
    """seq >= 1 — a real patrol waypoint. wp is one dict from the request body."""
    master.mav.mission_item_int_send(
        master.target_system, master.target_component,
        seq,
        mavutil.mavlink.MAV_FRAME_GLOBAL_RELATIVE_ALT,
        mavutil.mavlink.MAV_CMD_NAV_WAYPOINT,
        1 if seq == 1 else 0,                       # current (arm first item)
        1,                                          # autocontinue
        float(wp.get('hoverSeconds', 0)),            # param1: hold time (s)
        2.0,                                         # param2: accept radius (m)
        0,                                            # param3: pass radius
        float('nan'),                                 # param4: yaw, unchanged
        int(round(wp['latitude'] * 1e7)),
        int(round(wp['longitude'] * 1e7)),
        float(wp.get('altitude', 20.0)),
        mavutil.mavlink.MAV_MISSION_TYPE_MISSION)


def _upload_mission(waypoints):
    """
    Runs the full mission upload handshake. Executes in its own thread —
    mirrors run_dispatch()'s pattern of a background worker driven by
    route_mission/route_lock instead of blocking a Flask request thread.
    """
    total = len(waypoints)
    try:
        with route_lock:
            route_mission.update(state='uploading', total=total,
                                 current_wp=0, error=None,
                                 message=f'Uploading mission ({total} waypoints)...')
            _mission_request_queue.clear()
            _mission_ack_queue.clear()
        note(f'mission upload starting — {total} waypoints')

        # +1 for the home item at seq 0.
        master.mav.mission_count_send(
            master.target_system, master.target_component,
            total + 1, mavutil.mavlink.MAV_MISSION_TYPE_MISSION)

        served = set()
        deadline = time.time() + 30.0

        while time.time() < deadline:
            with route_lock:
                if mission_upload_abort['flag']:
                    route_mission.update(state='error',
                                         message='Mission upload cancelled',
                                         error='cancelled')
                    note('mission upload cancelled', 'warn')
                    return
                # Drain any pending requests.
                pending_seqs = list(_mission_request_queue)
                _mission_request_queue.clear()
                acks = list(_mission_ack_queue)
                _mission_ack_queue.clear()

            for seq in pending_seqs:
                if seq in served:
                    continue
                if seq == 0:
                    _send_home_item()
                elif 1 <= seq <= total:
                    _send_waypoint_item(seq, waypoints[seq - 1])
                else:
                    note(f'FC requested out-of-range waypoint {seq}', 'bad')
                    continue
                served.add(seq)
                with route_lock:
                    route_mission['message'] = (
                        f'Sending waypoint {seq} / {total}...')
                note(f'sent waypoint {seq}/{total}')

            if acks:
                result = acks[-1]
                if result == MAV_MISSION_ACCEPTED:
                    with route_lock:
                        route_mission.update(
                            state='ready', current_wp=0,
                            message=f'Mission ready — {total} waypoints uploaded')
                    note(f'mission accepted — {total} waypoints', 'good')
                else:
                    label = MISSION_ACK_RESULT.get(result, str(result))
                    with route_lock:
                        route_mission.update(
                            state='error', error=label,
                            message=f'Mission upload failed: {label}')
                    note(f'mission rejected: {label}', 'bad')
                return

            time.sleep(0.05)

        with route_lock:
            route_mission.update(state='error', error='timeout',
                                 message='Mission upload timed out')
        note('mission upload timed out', 'bad')

    except Exception as exc:
        with route_lock:
            route_mission.update(state='error', error=str(exc),
                                 message=f'Mission upload failed: {exc}')
        note(f'mission upload failed: {exc}', 'bad')


mission_upload_abort = {'flag': False}


# ─── endpoints ────────────────────────────────────────────────────────────────

@app.get('/api/status')
def api_status():
    s = snapshot()
    s['gate'] = gate()
    s['allow_arm'] = ALLOW_ARM
    s['motor_test'] = MOTOR_TEST_ENABLED
    s['motor_count'] = MOTOR_COUNT
    s['stream_url'] = STREAM_URL
    with lock:
        s['messages'] = list(messages)[:12]
    with route_lock:
        s['route_mission'] = dict(route_mission)
    return jsonify(s)


@app.get('/api/alerts')
def api_alerts():
    with lock:
        return jsonify(alerts=list(pending['alerts']),
                       error=pending['error'],
                       age=round(time.time() - pending['ts'], 1)
                            if pending['ts'] else None,
                       mission=dict(mission))


@app.post('/api/mode')
def api_mode():
    name = (request.json or {}).get('mode', '').upper()
    if name not in MODES:
        return jsonify(error=f'unknown mode {name!r}'), 400

    # A recovery command cancels any running dispatch.
    if name in RECOVERY_MODES and mission['active']:
        mission['abort'] = True

    # Recovery modes bypass the gate: they must work when things are wrong.
    if name not in RECOVERY_MODES:
        if g := gate():
            return jsonify(error=g), 403

    master.mav.set_mode_send(
        master.target_system,
        mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED,
        MODES[name])
    note(f'sent: mode {name}')
    return jsonify(ok=True, sent=name)


@app.post('/api/dispatch')
def api_dispatch():
    if g := gate():
        return jsonify(error=g), 403
    if mission['active']:
        return jsonify(error='a dispatch is already running'), 409

    d = request.json or {}
    try:
        lat, lon = float(d['lat']), float(d['lon'])
    except (KeyError, TypeError, ValueError):
        return jsonify(error='bad coordinates'), 400
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return jsonify(error='coordinates out of range'), 400

    s = snapshot()
    if s['mode'] != 'GUIDED':
        return jsonify(error=f"vehicle in {s['mode']}, must be GUIDED"), 409
    if s['lat'] is None:
        return jsonify(error='no position fix'), 409

    dist = haversine(s['lat'], s['lon'], lat, lon)
    if dist > MAX_DISPATCH_M:
        return jsonify(error=f'target is {dist/1000:.2f} km away, '
                             f'limit is {MAX_DISPATCH_M/1000:.1f} km'), 400

    threading.Thread(target=run_dispatch,
                     args=(lat, lon, d.get('id')), daemon=True).start()
    return jsonify(ok=True, distance_m=round(dist))


@app.post('/api/abort')
def api_abort():
    mission['abort'] = True
    master.mav.set_mode_send(
        master.target_system,
        mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED, MODES['LOITER'])
    note('ABORT — dispatch cancelled, LOITER commanded', 'warn')
    return jsonify(ok=True)


# ─── waypoint mission endpoints ────────────────────────────────────────────────

@app.get('/api/mission')
def api_mission_status():
    with route_lock:
        return jsonify(dict(route_mission))


@app.post('/api/mission')
def api_mission_upload():
    """
    Upload a patrol route. Body: {"waypoints": [{latitude, longitude,
    altitude?, hoverSeconds?, gimbalPitch?, takePhoto?}, ...]}.

    Runs the MISSION_COUNT/MISSION_ITEM_INT/MISSION_ACK handshake in a
    background thread and returns immediately — poll /api/mission or
    /api/status (route_mission field) for progress, same pattern as
    /api/dispatch + mission/.
    """
    if g := gate():
        return jsonify(error=g), 403
    with route_lock:
        if route_mission['state'] == 'uploading':
            return jsonify(error='a mission upload is already running'), 409

    d = request.json or {}
    waypoints = d.get('waypoints')
    if not isinstance(waypoints, list) or not waypoints:
        return jsonify(error='waypoints must be a non-empty list'), 400

    for i, wp in enumerate(waypoints):
        try:
            lat, lon = float(wp['latitude']), float(wp['longitude'])
        except (KeyError, TypeError, ValueError):
            return jsonify(error=f'waypoint {i}: bad or missing lat/lon'), 400
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            return jsonify(error=f'waypoint {i}: coordinates out of range'), 400

    mission_upload_abort['flag'] = False
    threading.Thread(target=_upload_mission, args=(waypoints,),
                     daemon=True).start()
    return jsonify(ok=True, count=len(waypoints))


@app.post('/api/mission/cancel')
def api_mission_cancel():
    """Cancels an in-progress upload. Does not affect a mission already
    accepted by the FC — use /api/mode or /api/abort for that."""
    mission_upload_abort['flag'] = True
    return jsonify(ok=True)


@app.post('/api/mission/start')
def api_mission_start():
    """
    Starts executing the uploaded mission. ArduCopter (unlike PX4) will
    not fly a mission unless the vehicle is armed AND in AUTO mode, so
    this sends MISSION_START then switches the mode — both are needed.
    """
    if err := require(armed=True):
        return jsonify(error=err[0]), err[1]
    with route_lock:
        if route_mission['state'] != 'ready':
            return jsonify(error=f"mission not ready "
                                 f"(state: {route_mission['state']})"), 409
        route_mission['state'] = 'executing'
        route_mission['current_wp'] = 0
        route_mission['message'] = 'Mission executing...'

    _send_command(mavutil.mavlink.MAV_CMD_MISSION_START, 0, 0)
    master.mav.set_mode_send(
        master.target_system,
        mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED, MODES['AUTO'])
    note('mission start sent — mode AUTO', 'good')
    return jsonify(ok=True)


@app.post('/api/motortest')
def api_motortest():
    """
    MAV_CMD_DO_MOTOR_TEST — bounded, disarmed-only motor spin.
    PROPS MUST BE OFF. Throttle and duration are hard-capped server-side.
    """
    if not MOTOR_TEST_ENABLED:
        return jsonify(error='motor test disabled in this build'), 403
    if g := gate():
        return jsonify(error=g), 403

    s = snapshot()
    if s['armed']:
        return jsonify(error='vehicle is ARMED — disarm before motor test'), 409
    if mission['active']:
        return jsonify(error='dispatch in progress'), 409

    d = request.json or {}
    try:
        motor = int(d['motor'])            # 1-based; 0 means all in sequence
        pct = float(d.get('throttle', 8))
        secs = float(d.get('seconds', 2))
    except (KeyError, TypeError, ValueError):
        return jsonify(error='bad parameters'), 400

    if not 0 <= motor <= MOTOR_COUNT:
        return jsonify(error=f'motor must be 0-{MOTOR_COUNT}'), 400
    pct = min(max(pct, 0.0), MOTOR_TEST_MAX_PCT)
    secs = min(max(secs, 0.5), MOTOR_TEST_MAX_SEC)

    # param1 motor instance, param2 throttle type (0 = percent),
    # param3 throttle value, param4 timeout s, param5 motor count,
    # param6 test order (0 = default)
    count = MOTOR_COUNT if motor == 0 else 0
    _send_command(mavutil.mavlink.MAV_CMD_DO_MOTOR_TEST,
                  float(motor), 0.0, pct, secs, float(count), 0.0, 0.0)

    label = 'ALL motors in sequence' if motor == 0 else f'motor {motor}'
    note(f'MOTOR TEST: {label} at {pct:.0f}% for {secs:.1f}s — '
         f'PROPS MUST BE OFF', 'warn')
    return jsonify(ok=True, motor=motor, throttle=pct, seconds=secs)


@app.post('/api/arm')
def api_arm():
    if not ALLOW_ARM:
        return jsonify(error='arming disabled in this build'), 403
    if err := require():
        return jsonify(error=err[0]), err[1]

    want = bool((request.json or {}).get('arm', True))
    _send_command(mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM,
                  1.0 if want else 0.0)
    note(f"sent: {'arm' if want else 'disarm'}")
    return jsonify(ok=True, sent='arm' if want else 'disarm')


@app.post('/api/takeoff')
def api_takeoff():
    if not ALLOW_ARM:
        return jsonify(error='takeoff disabled in this build'), 403
    if err := require(guided=True, armed=True):
        return jsonify(error=err[0]), err[1]

    try:
        alt = float((request.json or {})['alt'])
    except (KeyError, TypeError, ValueError):
        return jsonify(error='bad altitude'), 400
    if not ALT_MIN <= alt <= ALT_MAX:
        return jsonify(error=f'altitude outside {ALT_MIN}-{ALT_MAX} m'), 400

    _send_command(mavutil.mavlink.MAV_CMD_NAV_TAKEOFF, 0, 0, 0, 0, 0, 0, alt)
    note(f'sent: takeoff to {alt} m')
    return jsonify(ok=True, sent=alt)


@app.post('/api/altitude')
def api_altitude():
    """Hold current lat/lon, change height. Position snapshotted at press."""
    if err := require(guided=True, armed=True):
        return jsonify(error=err[0]), err[1]

    s = snapshot()
    if s['lat'] is None:
        return jsonify(error='no position fix'), 409
    try:
        alt = float((request.json or {})['alt'])
    except (KeyError, TypeError, ValueError):
        return jsonify(error='bad altitude'), 400
    if not ALT_MIN <= alt <= ALT_MAX:
        return jsonify(error=f'altitude outside {ALT_MIN}-{ALT_MAX} m'), 400

    _send_position(s['lat'], s['lon'], alt)
    note(f'sent: altitude {alt} m')
    return jsonify(ok=True, sent=alt)


@app.post('/api/goto')
def api_goto():
    if err := require(guided=True, armed=True):
        return jsonify(error=err[0]), err[1]

    d = request.json or {}
    try:
        lat, lon = float(d['lat']), float(d['lon'])
    except (KeyError, TypeError, ValueError):
        return jsonify(error='bad coordinates'), 400
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return jsonify(error='coordinates out of range'), 400

    alt = float(d.get('alt') or snapshot()['rel_alt'] or 20.0)
    if not ALT_MIN <= alt <= ALT_MAX:
        return jsonify(error=f'altitude outside {ALT_MIN}-{ALT_MAX} m'), 400

    # NOTE: nothing here bounds horizontal distance. The geofence in the
    # flight controller (FENCE_*) is what actually stops a bad coordinate.
    _send_position(lat, lon, alt)
    note(f'sent: goto {lat:.6f}, {lon:.6f} @ {alt} m')
    return jsonify(ok=True)


@app.post('/api/yaw')
def api_yaw():
    if err := require(guided=True, armed=True):
        return jsonify(error=err[0]), err[1]

    d = request.json or {}
    try:
        heading = float(d['heading'])
    except (KeyError, TypeError, ValueError):
        return jsonify(error='bad heading'), 400

    _send_command(mavutil.mavlink.MAV_CMD_CONDITION_YAW,
                  heading % 360,                 # target angle, degrees
                  float(d.get('rate', 25)),      # turn rate, deg/s
                  float(d.get('direction', 1)),  # 1 = CW, -1 = CCW
                  float(d.get('relative', 0)))   # 0 = absolute, 1 = offset
    note(f'sent: yaw {heading} deg')
    return jsonify(ok=True)


@app.get('/')
def index():
    return Response(PAGE, mimetype='text/html')


# ─── front end ────────────────────────────────────────────────────────────────

PAGE = r"""<!doctype html><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>3bo GCS</title>
<style>
:root{color-scheme:dark}
body{font:15px/1.4 system-ui,sans-serif;margin:0;padding:14px;
     background:#0f1116;color:#e8e8ea;max-width:780px}
.k{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));
   gap:8px;margin-bottom:10px}
.c{background:#1a1d25;padding:10px 12px;border-radius:10px}
.c b{display:block;font-size:21px;margin-top:3px;font-variant-numeric:tabular-nums}
.lbl{font-size:10.5px;color:#8b8f9a;text-transform:uppercase;letter-spacing:.06em}
#linkbar{display:flex;gap:16px;flex-wrap:wrap;font-size:12.5px;
         color:#8b8f9a;margin-bottom:14px;padding:0 2px}
#linkbar b{color:#e8e8ea;font-variant-numeric:tabular-nums}
#gate{padding:11px 13px;border-radius:10px;margin-bottom:16px;font-weight:600}
.ok{background:#153520;color:#7ee2a0}
.no{background:#3a1a1a;color:#ff9b9b}
h3{margin:18px 0 8px;font-size:11px;color:#8b8f9a;
   text-transform:uppercase;letter-spacing:.06em}
button{font:inherit;padding:11px 15px;border:0;border-radius:9px;
       background:#2b3040;color:#e8e8ea;cursor:pointer;margin:0 6px 6px 0}
button:hover:not(:disabled){background:#353c50}
button:disabled{opacity:.3;cursor:not-allowed}
.danger{background:#7a2020}.danger:hover:not(:disabled){background:#932828}
.warn{background:#7a5a12}.warn:hover:not(:disabled){background:#946d16}
.mini{padding:5px 11px;font-size:12px;margin-left:8px}
input,select{font:inherit;padding:10px;border-radius:9px;
      border:1px solid #333a48;background:#1a1d25;color:#e8e8ea}
input{width:82px}
.row{display:flex;align-items:center;gap:8px;margin-bottom:6px;flex-wrap:wrap}
#video{width:100%;aspect-ratio:16/9;border:0;border-radius:10px;
       background:#000;display:none}
#alerts{margin-bottom:10px}
.alert{background:#241419;border:1px solid #4a2028;border-radius:10px;
       padding:10px 12px;margin-bottom:8px;display:flex;
       align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap}
#mission{margin:6px 0 8px;font-weight:600;color:#e2c97e}
#motortest{display:none;background:#241f14;border:1px solid #4a3d20;
           border-radius:10px;padding:6px 14px 12px;margin-bottom:6px}
#log{margin-top:18px;font:12px/1.6 ui-monospace,monospace;
     background:#15181f;border-radius:10px;padding:10px 12px;max-height:230px;
     overflow-y:auto}
#log div{display:flex;gap:9px}
#log .t{color:#5d616c;flex:none}
.dim{color:#8b8f9a;font-size:13.5px}
.info{color:#9aa0ac}.good{color:#7ee2a0}.warn2{color:#e2c97e}.bad{color:#ff9b9b}
</style>

<div class=k>
  <div class=c><span class=lbl>Mode</span><b id=mode>—</b></div>
  <div class=c><span class=lbl>Armed</span><b id=armed>—</b></div>
  <div class=c><span class=lbl>Alt AGL</span><b id=alt>—</b></div>
  <div class=c><span class=lbl>Ground spd</span><b id=gs>—</b></div>
  <div class=c><span class=lbl>Battery</span><b id=volt>—</b></div>
  <div class=c><span class=lbl>Sats / HDOP</span><b id=sats>—</b></div>
</div>

<div id=linkbar>
  <span>msgs <b id=msgrate>—</b>/s</span>
  <span>heartbeat <b id=hbrate>—</b>/s</span>
  <span>bad <b id=badrate>—</b>/s</span>
  <span>cmd RTT <b id=ackms>—</b></span>
</div>

<div id=gate class=no>connecting…</div>

<h3>Video <button class=mini onclick="toggleVideo()">show / hide</button></h3>
<iframe id=video allow="autoplay" allowfullscreen></iframe>

<h3>Panic alerts</h3>
<div id=alerts class=dim>polling…</div>
<div id=mission></div>
<button class=danger onclick="post('/api/abort')">ABORT DISPATCH</button>

<h3>Recovery — always available</h3>
<button class=danger onclick="mode('RTL')">RTL</button>
<button class=danger onclick="mode('LAND')">LAND</button>
<button class=warn onclick="mode('BRAKE')">BRAKE</button>
<button class=warn onclick="mode('LOITER')">LOITER</button>
<button class=warn onclick="mode('ALT_HOLD')">ALT HOLD</button>

<div id=motortest>
  <h3>Motor test — PROPS MUST BE OFF</h3>
  <div class=row>
    <select id=motorSel><option value=0>All (sequence)</option></select>
    <input id=motorPct type=number value=8 min=1 max=15 step=1><span>%</span>
    <input id=motorSec type=number value=2 min=1 max=3 step=1><span>s</span>
    <button class=warn onclick="motorTest()">RUN TEST</button>
  </div>
</div>

<div id=ground style=display:none>
  <h3>Ground — simulator only</h3>
  <button class=g onclick="post('/api/arm',{arm:true})">ARM</button>
  <button class=g onclick="post('/api/arm',{arm:false})">DISARM</button>
  <button class=g onclick="takeoff()">TAKEOFF</button>
</div>

<h3>Guided — requires switch</h3>
<div class=row>
  <button class=g onclick="mode('GUIDED')">Enter GUIDED</button>
</div>
<div class=row>
  <input id=altIn type=number value=20 step=1 min=5 max=60><span>m</span>
  <button class=g onclick="post('/api/altitude',{alt:+$('altIn').value})">
    Go to altitude</button>
</div>
<div class=row>
  <input id=hdg type=number value=0 step=5><span>°</span>
  <button class=g onclick="post('/api/yaw',{heading:+$('hdg').value})">
    Yaw to heading</button>
</div>

<div id=log></div>

<script>
const $ = id => document.getElementById(id);
let local = [], videoOn = false, streamUrl = null;

function push(text, level){
  local.unshift({t:new Date().toTimeString().slice(0,8), text, level});
  local = local.slice(0,12);
}

async function post(url, body){
  try{
    const r = await fetch(url,{method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify(body||{})});
    const j = await r.json();
    push((r.ok ? '\u2192 ' : '\u2717 ') + url.replace('/api/','') +
         (r.ok ? '' : '  ' + j.error), r.ok ? 'info' : 'bad');
  }catch(e){ push('\u2717 request failed: ' + e.message, 'bad'); }
}

function mode(m){
  if((m==='RTL'||m==='LAND') && !confirm(m + ' — confirm?')) return;
  post('/api/mode',{mode:m});
}
const takeoff = () => post('/api/takeoff',{alt:+$('altIn').value});

function dispatch(lat, lon, id){
  if(!confirm('Dispatch drone to ' + lat.toFixed(5) + ', ' + lon.toFixed(5) + '?'))
    return;
  post('/api/dispatch', {lat: lat, lon: lon, id: id});
}

function motorTest(){
  const m = +$('motorSel').value;
  const label = m === 0 ? 'ALL motors in sequence' : 'motor ' + m;
  if(!confirm('Confirm PROPS ARE OFF and the aircraft is secured.\n\nRun '
              + label + ' at ' + $('motorPct').value + '% for '
              + $('motorSec').value + 's?')) return;
  post('/api/motortest', {motor: m, throttle: +$('motorPct').value,
                          seconds: +$('motorSec').value});
}

function toggleVideo(){
  const v = $('video');
  videoOn = !videoOn;
  if (videoOn && streamUrl){ v.src = streamUrl; v.style.display = 'block'; }
  else { v.src = 'about:blank'; v.style.display = 'none'; videoOn = false; }
}

const fmt = (v,d,u) => v==null ? '—' : v.toFixed(d) + ' ' + u;
const esc = t => String(t).replace(/[<>&]/g,
                 c => ({'<':'&lt;','>':'&gt;','&':'&amp;'}[c]));

setInterval(async () => {
  try{
    const s = await (await fetch('/api/status')).json();
    streamUrl = s.stream_url;

    $('mode').textContent  = s.mode || '—';
    $('armed').textContent = s.armed ? 'ARMED' : 'disarmed';
    $('armed').style.color = s.armed ? '#ff9b9b' : '#e8e8ea';
    $('alt').textContent   = fmt(s.rel_alt,1,'m');
    $('gs').textContent    = fmt(s.gs,1,'m/s');
    $('volt').textContent  = fmt(s.volt,1,'V');
    $('sats').textContent  = s.sats==null ? '—' :
        s.sats + (s.hdop!=null ? ' / ' + s.hdop.toFixed(1) : '');

    $('msgrate').textContent = s.msg_rate ? s.msg_rate.toFixed(0) : '—';
    $('hbrate').textContent  = s.hb_rate ? s.hb_rate.toFixed(1) : '—';
    $('badrate').textContent = s.bad_rate ? s.bad_rate.toFixed(1) : '0';
    $('badrate').style.color = s.bad_rate > 0.5 ? '#ff9b9b' : '#e8e8ea';
    $('ackms').textContent   = s.ack_ms != null
                               ? s.ack_ms.toFixed(0) + ' ms' : '—';

    const open = !s.gate, g = $('gate');
    g.className = open ? 'ok' : 'no';
    g.textContent = open ? 'Companion control PERMITTED by switch'
                         : 'BLOCKED — ' + s.gate;
    // Cosmetic only. The real check runs server-side in every handler.
    document.querySelectorAll('.g').forEach(b => b.disabled = !open);
    $('ground').style.display = s.allow_arm ? 'block' : 'none';

    // Motor test only shown when disarmed; server refuses it when armed.
    $('motortest').style.display =
      (s.motor_test && !s.armed && open) ? 'block' : 'none';
    const sel = $('motorSel');
    if (sel.options.length === 1 && s.motor_count){
      for (let i = 1; i <= s.motor_count; i++){
        const o = document.createElement('option');
        o.value = i; o.textContent = 'Motor ' + i;
        sel.appendChild(o);
      }
    }

    const all = [...local, ...(s.messages||[])]
      .sort((a,b) => b.t.localeCompare(a.t)).slice(0,14);
    $('log').innerHTML = all.map(m =>
      '<div><span class=t>' + m.t + '</span><span class="' +
      (m.level==='warn'?'warn2':m.level) + '">' + esc(m.text) +
      '</span></div>').join('');

    // ── panic alerts ──
    const a = await (await fetch('/api/alerts')).json();
    const box = $('alerts');
    if (a.error){
      box.className = 'bad';
      box.textContent = 'alert feed error: ' + a.error;
    } else if (!a.alerts.length){
      box.className = 'dim';
      box.textContent = 'no pending alerts';
    } else {
      box.className = '';
      box.innerHTML = a.alerts.map(x =>
        '<div class=alert><div><b>' + x.lat.toFixed(5) + ', ' +
        x.lon.toFixed(5) + '</b><br><span class=dim>accuracy \u00b1' +
        x.accuracy.toFixed(0) + ' m &middot; ' + esc(x.id) +
        '</span></div><button class=danger onclick="dispatch(' +
        x.lat + ',' + x.lon + ',\'' + esc(x.id) + '\')">DISPATCH</button></div>'
      ).join('');
    }

    const m = a.mission;
    $('mission').textContent = m.active
      ? 'MISSION: ' + m.phase +
        (m.dist != null ? '  —  ' + m.dist.toFixed(0) + ' m to go' : '')
      : (m.phase === 'on station' ? 'MISSION: on station'
         : (m.phase === 'failed' ? 'MISSION: failed' : ''));

  }catch(e){
    $('gate').className = 'no';
    $('gate').textContent = 'backend unreachable';
  }
}, 500);
</script>"""


if __name__ == '__main__':
    threading.Thread(target=rx_loop, daemon=True).start()
    threading.Thread(target=hb_loop, daemon=True).start()
    threading.Thread(target=poll_alerts, daemon=True).start()
    print(f'connecting to {CONNECT} …')
    print(f'panic feed:  {PANIC_URL}')
    print(f'video:       {STREAM_URL}')
    if not ready.wait(timeout=15):
        print('warning: no heartbeat yet — starting anyway, will keep retrying')
    app.run(host='127.0.0.1', port=8080, threaded=True)
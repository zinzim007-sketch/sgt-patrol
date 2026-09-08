import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// GcsClientProvider — connects Flutter to gcs_web.py, the laptop-side
/// Flask server that owns the real MAVLink link to the flight controller
/// and runs the panic-dispatch sequence (arm -> takeoff -> transit to
/// standoff -> descend -> orient).
///
/// This REPLACES the old ROS path for panic dispatch (mission_planner.py,
/// mavlink_bridge.py, panic_server.py / panic_server_win.py,
/// panic_ros_bridge.py). Those files are retired — the same job is done
/// here by run_dispatch() inside gcs_web.py.
///
/// This does NOT replace DroneProvider's raw MAVLink socket. Waypoint
/// mission upload (MissionProvider) still needs that socket — gcs_web.py
/// has no equivalent for uploading a patrol route. The two connections
/// run side by side against the same vehicle; see the note in
/// _connectReal() about confirming your MAVLink routing actually fans
/// out to both endpoints.
///
/// ── HARDWARE TESTING — READ BEFORE FLYING ─────────────────────────────
/// gcs_web.py ships pointed at SITL, not your Pixhawk 6C:
///   - CONNECT in gcs_web.py is 'tcp:127.0.0.1:5760' (SITL/relay). For
///     real hardware this needs to point at your actual MAVLink link
///     (telemetry radio serial port, or whatever relay/mavlink-router
///     bridges the Pi 5 <-> laptop link over the SIM7600G / Ethernet path).
///   - GUIDED_PWM_RANGE in gcs_web.py is commented "wide open for SITL
///     (no TX connected)" — on hardware this MUST be narrowed to the
///     actual GUIDED detent on your TX16S mode switch, or the software
///     gate does nothing.
///   - ALLOW_ARM, MOTOR_TEST_ENABLED — review both before connecting to
///     a real vehicle with props on.
/// None of that is something this Dart file can fix — it lives in
/// gcs_web.py's config block. This provider only talks to whatever
/// gcs_web.py is actually connected to; it has no way to know if that's
/// SITL or a real aircraft. Confirm gcs_web.py's own console output
/// ("connecting to <CONNECT> …" / heartbeat system id) matches your
/// hardware before trusting anything this provider shows.
///
/// This provider polls at 500ms, matching gcs_web.py's built-in web UI.
/// That's fine for operator situational awareness; it is NOT a
/// closed-loop control path — nothing here should be used for anything
/// time-critical. The flight controller's own failsafes (geofence,
/// RC loss, GCS loss) are the real safety net, same as gcs_web.py's own
/// gate() docstring says.
class GcsClientProvider extends ChangeNotifier {
  GcsClientProvider({this.baseUrl = 'http://127.0.0.1:8080'});

  /// Base URL of gcs_web.py. Defaults to same-machine loopback, matching
  /// gcs_web.py's own `app.run(host='127.0.0.1', port=8080)`.
  ///
  /// If the operator app runs on a phone/tablet rather than the laptop
  /// itself, 127.0.0.1 will NOT work — gcs_web.py would also need
  /// `host='0.0.0.0'` and this needs the laptop's real LAN/hotspot IP.
  /// Change this via the constructor or [setBaseUrl], not by editing
  /// gcs_web.py's own built-in page.
  String baseUrl;

  static const _pollInterval = Duration(milliseconds: 500);
  Timer? _pollTimer;
  bool _polling = false; // guards against overlapping requests if a
                          // response is slow (e.g. flaky LTE link)

  // ── connection ──
  bool isConnected = false; // reachable AND vehicle link up (mirrors
                             // gcs_web.py's `connected` field, i.e. it
                             // has a live heartbeat from the aircraft —
                             // not just "Flask responded")
  String statusMessage = 'Not connected to GCS backend';
  String? lastError;

  // ── vehicle telemetry (mirrors gcs_web.py `state`) ──
  String? mode;
  bool armed = false;
  double? latitude;
  double? longitude;
  double? relAltitude; // metres above home
  double? groundspeed; // m/s
  double? voltage;
  int? satellites;
  double? hdop;

  // ── link health ──
  double msgRate = 0.0;
  double hbRate = 0.0;
  double badRate = 0.0;
  double? ackMs;

  // ── the gate (see gcs_web.py gate()) ──
  // null == permitted. Non-null == reason companion commands are blocked.
  // This is a SOFTWARE-ONLY gate the laptop enforces; the flight
  // controller does not know it exists. Never treat gateReason == null
  // as a guarantee the vehicle will accept a command.
  String? gateReason;
  bool get isGateOpen => gateReason == null;

  bool allowArm = false;
  bool motorTestEnabled = false;
  int motorCount = 0;
  String? streamUrl;

  // ── panic alerts (from gcs_web.py polling the VM at PANIC_URL) ──
  List<PanicAlert> alerts = [];
  String? alertsError; // e.g. VM unreachable, or bad OPERATOR_TOKEN

  // ── active dispatch mission (mirrors gcs_web.py `mission`) ──
  bool missionActive = false;
  String missionPhase = 'idle';
  double? missionDistance; // metres remaining, during transit
  String? missionAlertId;

  // ── recent log lines (STATUSTEXT / COMMAND_ACK from the vehicle) ──
  List<GcsLogEntry> log = [];

  void setBaseUrl(String url) {
    baseUrl = url;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Connect / poll
  // -------------------------------------------------------------------------

  void connect() {
    _pollTimer?.cancel();
    _pollOnce(); // don't wait a full interval for first data
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    if (_polling) return; // previous request still in flight — skip a
                           // beat rather than piling up requests
    _polling = true;
    try {
      await Future.wait([_fetchStatus(), _fetchAlerts()]);
      lastError = null;
    } catch (e) {
      isConnected = false;
      statusMessage = 'GCS backend unreachable: $e';
      lastError = e.toString();
      // Also surface through alertsError so RemoteAlertPanel doesn't
      // silently collapse (its hide condition is alerts.isEmpty &&
      // alertsError == null && !missionActive — without this, "can't
      // reach gcs_web.py" and "no alerts right now" looked identical:
      // an empty sidebar either way).
      alertsError = 'gcs_web.py unreachable at $baseUrl';
    } finally {
      _polling = false;
      notifyListeners();
    }
  }

  Future<void> _fetchStatus() async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/status'))
        .timeout(const Duration(seconds: 3));
    if (res.statusCode != 200) {
      throw Exception('status ${res.statusCode}');
    }
    final s = jsonDecode(res.body) as Map<String, dynamic>;

    mode = s['mode'] as String?;
    armed = s['armed'] as bool? ?? false;
    latitude = (s['lat'] as num?)?.toDouble();
    longitude = (s['lon'] as num?)?.toDouble();
    relAltitude = (s['rel_alt'] as num?)?.toDouble();
    groundspeed = (s['gs'] as num?)?.toDouble();
    voltage = (s['volt'] as num?)?.toDouble();
    satellites = s['sats'] as int?;
    hdop = (s['hdop'] as num?)?.toDouble();

    msgRate = (s['msg_rate'] as num?)?.toDouble() ?? 0.0;
    hbRate = (s['hb_rate'] as num?)?.toDouble() ?? 0.0;
    badRate = (s['bad_rate'] as num?)?.toDouble() ?? 0.0;
    ackMs = (s['ack_ms'] as num?)?.toDouble();

    gateReason = s['gate'] as String?;
    allowArm = s['allow_arm'] as bool? ?? false;
    motorTestEnabled = s['motor_test'] as bool? ?? false;
    motorCount = s['motor_count'] as int? ?? 0;
    streamUrl = s['stream_url'] as String?;

    final msgs = (s['messages'] as List?) ?? const [];
    log = msgs
        .map((m) => GcsLogEntry(
              time: m['t'] as String? ?? '',
              text: m['text'] as String? ?? '',
              level: m['level'] as String? ?? 'info',
            ))
        .toList();

    // gcs_web.py's own `connected` flag requires a live vehicle
    // heartbeat, not just that Flask answered — keep that distinction.
    isConnected = s['connected'] as bool? ?? false;
    statusMessage = isConnected
        ? 'Connected — ${mode ?? "?"}${armed ? " (ARMED)" : ""}'
        : 'GCS backend up, no vehicle heartbeat';
  }

  Future<void> _fetchAlerts() async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/alerts'))
        .timeout(const Duration(seconds: 3));
    if (res.statusCode != 200) {
      throw Exception('alerts ${res.statusCode}');
    }
    final a = jsonDecode(res.body) as Map<String, dynamic>;

    alertsError = a['error'] as String?;
    final list = (a['alerts'] as List?) ?? const [];
    alerts = list
        .map((x) => PanicAlert(
              id: x['id'] as String? ?? '',
              lat: (x['lat'] as num).toDouble(),
              lon: (x['lon'] as num).toDouble(),
              accuracyM: (x['accuracy'] as num?)?.toDouble() ?? 0.0,
            ))
        .toList();

    final m = a['mission'] as Map<String, dynamic>? ?? const {};
    missionActive = m['active'] as bool? ?? false;
    missionPhase = m['phase'] as String? ?? 'idle';
    missionDistance = (m['dist'] as num?)?.toDouble();
    missionAlertId = m['alert_id'] as String?;
  }

  // -------------------------------------------------------------------------
  // Commands
  // -------------------------------------------------------------------------

  /// Dispatches the drone to a panic alert location. Mirrors the built-in
  /// web UI's dispatch(lat, lon, id) — same endpoint, same behaviour,
  /// including gcs_web.py's server-side MAX_DISPATCH_M distance check
  /// and the requirement that the vehicle already be in GUIDED.
  ///
  /// Returns null on success, or an error message from the server
  /// (e.g. "vehicle in LOITER, must be GUIDED", "target is 1.20 km away,
  /// limit is 0.25 km"). Caller is responsible for confirming with the
  /// operator before calling this — gcs_web.py's own UI requires a
  /// confirm() dialog for exactly this reason.
  Future<String?> dispatch(
      {required double lat, required double lon, String? id}) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/dispatch'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'lat': lat, 'lon': lon, if (id != null) 'id': id}),
          )
          .timeout(const Duration(seconds: 5));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200) {
        return body['error'] as String? ?? 'dispatch failed (${res.statusCode})';
      }
      await _pollOnce(); // refresh mission state immediately
      return null;
    } catch (e) {
      return 'dispatch request failed: $e';
    }
  }

  /// Cancels any active dispatch and commands LOITER. This is a recovery
  /// action — gcs_web.py's /api/abort bypasses the companion gate on
  /// purpose, same as RTL/LAND/BRAKE, because recovery must work even
  /// when things are wrong.
  Future<String?> abort() async {
    try {
      final res = await http
          .post(Uri.parse('$baseUrl/api/abort'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return body['error'] as String? ?? 'abort failed (${res.statusCode})';
      }
      await _pollOnce();
      return null;
    } catch (e) {
      return 'abort request failed: $e';
    }
  }

  /// Sends a flight-mode change (e.g. 'RTL', 'LAND', 'GUIDED'). Recovery
  /// modes (RTL/LAND/BRAKE/LOITER/ALT_HOLD) bypass the gate server-side;
  /// anything else is blocked unless the companion gate is open.
  Future<String?> setMode(String mode) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/mode'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'mode': mode}),
          )
          .timeout(const Duration(seconds: 5));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200) {
        return body['error'] as String? ?? 'mode change failed (${res.statusCode})';
      }
      await _pollOnce();
      return null;
    } catch (e) {
      return 'mode request failed: $e';
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

class PanicAlert {
  final String id;
  final double lat;
  final double lon;
  final double accuracyM;
  const PanicAlert(
      {required this.id,
      required this.lat,
      required this.lon,
      required this.accuracyM});
}

class GcsLogEntry {
  final String time;
  final String text;
  final String level; // 'info' | 'good' | 'warn' | 'bad'
  const GcsLogEntry({required this.time, required this.text, required this.level});
}

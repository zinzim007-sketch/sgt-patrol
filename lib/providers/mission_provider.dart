import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/patrol_route.dart';
import 'drone_provider.dart';
import 'gcs_client_provider.dart';

enum MissionState { idle, uploading, ready, executing, holding, complete, error }

class MissionProvider extends ChangeNotifier {

  MissionState state = MissionState.idle;
  String statusMessage = 'No mission loaded';
  int currentWaypoint = 0;
  int totalWaypoints = 0;

  /// True when the current hold is a panic dispatch (indefinite, only
  /// clearable by the operator via resumePatrol()) rather than a
  /// temporary investigate hold (auto-resumes after its duration).
  bool isPanicHold = false;

  bool get canUpload => state == MissionState.idle ||
      state == MissionState.error ||
      state == MissionState.complete;
  bool get canStart => state == MissionState.ready;
  bool get canStop => state == MissionState.executing;

  // -------------------------------------------------------------------------
  // Upload
  // -------------------------------------------------------------------------

  void uploadMission(PatrolRoute route, {required bool useMock, GcsClientProvider? gcs, DroneProvider? drone}) {
    if (!canUpload) return;

    state = MissionState.uploading;
    totalWaypoints = route.waypoints.length;
    statusMessage = 'Uploading mission (${route.waypoints.length} waypoints)...';
    notifyListeners();

    if (useMock || gcs == null) {
      // Mock mode is purely visual and has nothing to do with the real
      // MAVLink link — DroneProvider's mock-route helpers are kept for
      // this regardless of which backend real flight uses.
      drone?.setMockRoute(route.waypoints);
      Future.delayed(const Duration(milliseconds: 1500), () {
        state = MissionState.ready;
        statusMessage = 'Mission ready';
        notifyListeners();
      });
      return;
    }

    _uploadRealMission(route, gcs);
  }

  // -------------------------------------------------------------------------
  // Real mission upload — via gcs_web.py's /api/mission (MISSION_COUNT /
  // MISSION_ITEM_INT / MISSION_ACK handshake, run server-side).
  // -------------------------------------------------------------------------

  Timer? _uploadPollTimer;

  Future<void> _uploadRealMission(PatrolRoute route, GcsClientProvider gcs) async {
    final waypoints = route.waypoints.map((w) => w.toJson()).toList();

    final error = await gcs.uploadMission(waypoints);
    if (error != null) {
      state = MissionState.error;
      statusMessage = error;
      notifyListeners();
      print('[SGT] Mission upload rejected: $error');
      return;
    }

    statusMessage = 'Sending waypoint count...';
    notifyListeners();
    print('[SGT] Mission upload started — ${route.waypoints.length} waypoints');

    // gcs_web.py runs the handshake in a background thread and reports
    // progress through routeMissionState/routeMissionMessage, refreshed
    // by GcsClientProvider's normal 500ms status poll. Watch it here
    // until it settles rather than re-implementing the handshake client
    // side.
    _uploadPollTimer?.cancel();
    _uploadPollTimer = Timer.periodic(const Duration(milliseconds: 300), (t) {
      statusMessage = gcs.routeMissionMessage;
      currentWaypoint = gcs.routeMissionCurrentWp;

      if (gcs.routeMissionState == 'ready') {
        t.cancel();
        state = MissionState.ready;
        print('[SGT] Mission accepted by FC');
        notifyListeners();
      } else if (gcs.routeMissionState == 'error') {
        t.cancel();
        state = MissionState.error;
        print('[SGT] Mission rejected: ${gcs.routeMissionError}');
        notifyListeners();
      } else {
        notifyListeners();
      }
    });
  }

  // -------------------------------------------------------------------------
  // Start mission
  // -------------------------------------------------------------------------

  void startMission({required bool useMock, GcsClientProvider? gcs, DroneProvider? drone}) {
    if (!canStart) return;

    state = MissionState.executing;
    currentWaypoint = 0;
    statusMessage = 'Arming drone...';
    notifyListeners();

    if (useMock || gcs == null) {
      _mockDrone = drone;
      drone?.resumeMockRoute();
      _simulateProgress();
      return;
    }

    _startRealMission(gcs);
  }

  Future<void> _startRealMission(GcsClientProvider gcs) async {
    statusMessage = 'Arming...';
    notifyListeners();

    final armError = await gcs.arm();
    if (armError != null) {
      state = MissionState.error;
      statusMessage = armError;
      notifyListeners();
      print('[SGT] Arm failed: $armError');
      return;
    }

    // gcs_web.py's /api/mission/start itself requires armed=true and
    // switches the vehicle to AUTO — ArduCopter won't run a mission in
    // any other mode. Give the ARM command a moment to actually land
    // before checking, same margin the old PX4 path used.
    await Future.delayed(const Duration(seconds: 2));

    final startError = await gcs.startMission();
    if (startError != null) {
      state = MissionState.error;
      statusMessage = startError;
      notifyListeners();
      print('[SGT] Mission start failed: $startError');
      return;
    }

    statusMessage = 'Mission executing...';
    notifyListeners();
    print('[SGT] Mission start sent');
  }

  // -------------------------------------------------------------------------
  // Hold / investigate — temporary, auto-resumes
  // -------------------------------------------------------------------------

  Timer? _holdTimer;
  MissionState? _stateBeforeHold;

  /// Called when a flyby detection is already zone/time-worthy — breaks
  /// from the active route to hold over the detection's location for
  /// [duration], giving the loitering check a real window to evaluate
  /// during. Resumes the previous mission state automatically afterward
  /// unless something else (like a confirmed pattern, or a panic
  /// dispatch overriding it) changes state first.
  void holdAt({
    required double lat,
    required double lng,
    double alt = 20.0,
    Duration duration = const Duration(seconds: 15),
    required bool useMock,
    GcsClientProvider? gcs,
    DroneProvider? drone,
  }) {
    if (isPanicHold) return; // panic always takes priority
    if (state != MissionState.executing) return; // only interrupt an active patrol
    _stateBeforeHold = state;
    state = MissionState.holding;
    statusMessage = 'Investigating — holding position...';
    notifyListeners();
    print('[SGT] Holding at $lat, $lng for ${duration.inSeconds}s');

    // Map-marker cosmetics only — unrelated to which backend flies the
    // vehicle, so this stays on DroneProvider regardless of useMock.
    drone?.setFocusPoint(lat: lat, lng: lng, reason: 'Investigating');
    if (!useMock && gcs != null) {
      gcs.goTo(lat: lat, lon: lng, altMeters: alt).then((error) {
        if (error != null) print('[SGT] Hold reposition failed: $error');
      });
    }

    _holdTimer?.cancel();
    _holdTimer = Timer(duration, () {
      if (state != MissionState.holding || isPanicHold) return; // superseded by something else
      state = _stateBeforeHold ?? MissionState.executing;
      statusMessage = 'Resuming patrol...';
      drone?.clearFocus();
      notifyListeners();
      print('[SGT] Hold complete — resuming patrol');
    });
  }

  bool get isHolding => state == MissionState.holding;

  // -------------------------------------------------------------------------
  // Panic dispatch — indefinite hold, interrupts any active mission,
  // only clears when the operator explicitly resumes.
  // -------------------------------------------------------------------------

  /// Sends the drone to a panic location NOW, regardless of what it's
  /// currently doing — mid-mission, mid-investigate-hold, idle, all
  /// interrupted. Unlike holdAt(), this does NOT auto-resume — the
  /// operator must call resumePatrol() once the situation is resolved.
  void dispatchToPanic({
    required double lat,
    required double lng,
    double alt = 20.0,
    required bool useMock,
    GcsClientProvider? gcs,
    DroneProvider? drone,
  }) {
    _holdTimer?.cancel(); // cancel any in-progress investigate hold — panic overrides it
    _uploadPollTimer?.cancel(); // panic overrides an in-progress mission upload watch too

    // Only remember "what to resume" if we're not already mid-panic —
    // otherwise a second panic trigger while already responding would
    // overwrite _stateBeforeHold with 'holding', losing the real
    // original mission state.
    if (!isPanicHold) {
      _stateBeforeHold = (state == MissionState.executing || state == MissionState.holding)
          ? MissionState.executing
          : state;
    }

    isPanicHold = true;
    state = MissionState.holding;
    statusMessage = 'PANIC — drone dispatched, holding at location';
    notifyListeners();
    print('[SGT] Panic dispatch: holding at $lat, $lng indefinitely');

    drone?.setFocusPoint(lat: lat, lng: lng, reason: 'PANIC');
    if (!useMock && gcs != null) {
      // gcs_web.py's own /api/dispatch already runs the full
      // arm/transit/standoff/observe sequence for panic — that's what
      // the panic button itself calls (see remote_alert_panel.dart /
      // GcsClientProvider.dispatch()). This path is for MissionProvider
      // driving a panic hold directly, so a plain goTo is the right
      // equivalent to the old reposition() call it replaces.
      gcs.goTo(lat: lat, lon: lng, altMeters: alt).then((error) {
        if (error != null) print('[SGT] Panic reposition failed: $error');
      });
    }
  }

  /// Operator explicitly resumes the interrupted patrol after a panic
  /// dispatch is resolved. Also usable to manually end an investigate
  /// hold early.
  void resumePatrol({required bool useMock, DroneProvider? drone}) {
    if (state != MissionState.holding) return;
    isPanicHold = false;
    _holdTimer?.cancel();
    state = _stateBeforeHold ?? MissionState.executing;
    statusMessage = 'Resuming patrol...';
    drone?.clearFocus();
    notifyListeners();
    print('[SGT] Patrol manually resumed');
  }

  // -------------------------------------------------------------------------
  // Stop mission
  // -------------------------------------------------------------------------

  void stopMission({required bool useMock, GcsClientProvider? gcs, DroneProvider? drone}) {
    if (!canStop) return;

    _progressTimer?.cancel();
    state = MissionState.idle;
    statusMessage = 'Mission stopped';
    currentWaypoint = 0;
    notifyListeners();

    if (useMock) {
      drone?.pauseMockRoute();
    } else if (gcs != null) {
      gcs.setMode('RTL').then((error) {
        print('[SGT] RTH after stop: ${error ?? "sent"}');
      });
    }
  }


  // -------------------------------------------------------------------------
  // Mock progress simulation
  // -------------------------------------------------------------------------

  Timer? _progressTimer;
  int _step = 0;
  DroneProvider? _mockDrone;

  void _simulateProgress() {
    _step = 0;
    _progressTimer = Timer.periodic(const Duration(seconds: 4), (t) {
      _step++;
      if (_step == 1) {
        statusMessage = 'Drone taking off...';
      } else if (_step <= totalWaypoints + 1) {
        currentWaypoint = _step - 1;
        statusMessage = 'Patrolling: waypoint $currentWaypoint / $totalWaypoints';
      } else {
        t.cancel();
        state = MissionState.complete;
        statusMessage = 'Patrol complete';
        currentWaypoint = 0;
        _mockDrone?.pauseMockRoute();
        _mockDrone = null;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _holdTimer?.cancel();
    _uploadPollTimer?.cancel();
    super.dispose();
  }
}
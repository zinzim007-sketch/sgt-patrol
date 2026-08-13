import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dart_mavlink/mavlink.dart';
import 'package:dart_mavlink/dialects/common.dart';
import '../models/patrol_route.dart';
import 'drone_provider.dart';

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

  void uploadMission(PatrolRoute route, {required bool useMock, DroneProvider? drone}) {
    if (!canUpload) return;

    state = MissionState.uploading;
    totalWaypoints = route.waypoints.length;
    statusMessage = 'Uploading mission (${route.waypoints.length} waypoints)...';
    notifyListeners();

    if (useMock || drone == null) {
      drone?.setMockRoute(route.waypoints);
      Future.delayed(const Duration(milliseconds: 1500), () {
        state = MissionState.ready;
        statusMessage = 'Mission ready';
        notifyListeners();
      });
      return;
    }

    _uploadRealMission(route, drone);
  }

  // -------------------------------------------------------------------------
  // Real MAVLink mission upload
  // Uses DroneProvider's existing socket via callback — no double-listening
  // -------------------------------------------------------------------------

  List<PatrolWaypoint>? _pendingWaypoints;
  RawDatagramSocket? _missionSocket;
  InternetAddress? _missionHost;
  int? _missionPort;

  void _uploadRealMission(PatrolRoute route, DroneProvider drone) {
    final socket = drone.socket;
    if (socket == null) {
      state = MissionState.error;
      statusMessage = 'Drone not connected';
      notifyListeners();
      return;
    }

    _missionSocket = socket;
    _missionHost = InternetAddress(drone.px4Host);
    _missionPort = drone.px4Port;
    _pendingWaypoints = route.waypoints;

    // Register callback on DroneProvider to receive mission protocol messages
    drone.onMissionMessage = _handleMissionMessage;

    // Step 1 — tell PX4 how many waypoints (+1 for home)
    _sendMissionCount(route.waypoints.length + 1);
    statusMessage = 'Sending waypoint count to PX4...';
    notifyListeners();
    print('[SGT] Mission upload started — ${route.waypoints.length} waypoints');
  }

  void _handleMissionMessage(MavlinkFrame frame) {
    final message = frame.message;
    print('[SGT] Mission message received: ${message.runtimeType}');//debug
    final waypoints = _pendingWaypoints;
    if (waypoints == null) return;

    // PX4 requests each waypoint individually
    if (message is MissionRequestInt) {
      final seq = message.seq;
      print('[SGT] PX4 requesting waypoint $seq');
      statusMessage = 'Sending waypoint $seq / ${waypoints.length}...';
      notifyListeners();
      _sendWaypointForSeq(seq, waypoints);
    }

    // Legacy request format
    else if (message is MissionRequest) {
      final seq = message.seq;
      _sendWaypointForSeq(seq, waypoints);
    }

    // PX4 acknowledges complete mission
    else if (message is MissionAck) {
      if (message.type == mavMissionAccepted) {
        state = MissionState.ready;
        statusMessage = 'Mission ready — ${waypoints.length} waypoints uploaded';
        print('[SGT] Mission accepted by PX4');
      } else {
        state = MissionState.error;
        statusMessage = 'Mission upload failed (error: ${message.type})';
        print('[SGT] Mission rejected: ${message.type}');
      }
      notifyListeners();
    }

    // Mission item reached during execution
    else if (message is MissionItemReached) {
      print('[SGT] MissionItemReached: seq=${message.seq}'); //debug
      currentWaypoint = message.seq;
      statusMessage = 'Patrolling: waypoint $currentWaypoint / $totalWaypoints';
      notifyListeners();
      print('[SGT] Reached waypoint $currentWaypoint');

      if (currentWaypoint >= totalWaypoints) {
        state = MissionState.complete;
        statusMessage = 'Patrol complete';
        notifyListeners();
      }
    }
  }

  void _sendWaypointForSeq(int seq, List<PatrolWaypoint> waypoints) {
    if (seq == 0) {
      _sendHomeWaypoint();
    } else if (seq <= waypoints.length) {
      _sendWaypoint(seq, waypoints[seq - 1]);
    }
  }

  void _sendMissionCount(int count) {
    if (_missionSocket == null || _missionHost == null || _missionPort == null) return;
    final message = MissionCount(
      targetSystem: 1,
      targetComponent: 1,
      count: count,
      missionType: mavMissionTypeMission,
      opaqueId: 0,
    );
    final frame = MavlinkFrame.v2(0, 255, 0, message);
    _missionSocket!.send(frame.serialize(), _missionHost!, _missionPort!);
  }

  void _sendHomeWaypoint() {
    if (_missionSocket == null || _missionHost == null || _missionPort == null) return;
    final message = MissionItemInt(
      targetSystem: 1,
      targetComponent: 1,
      seq: 0,
      frame: mavFrameGlobal,
      command: mavCmdNavWaypoint,
      current: 0,
      autocontinue: 1,
      param1: 0,
      param2: 0,
      param3: 0,
      param4: 0,
      x: 0,
      y: 0,
      z: 0,
      missionType: mavMissionTypeMission,
    );
    final frame = MavlinkFrame.v2(0, 255, 0, message);
    _missionSocket!.send(frame.serialize(), _missionHost!, _missionPort!);
    print('[SGT] Sent home waypoint (seq 0)');
  }

  void _sendWaypoint(int seq, PatrolWaypoint wp) {
    if (_missionSocket == null || _missionHost == null || _missionPort == null) return;
    final message = MissionItemInt(
      targetSystem: 1,
      targetComponent: 1,
      seq: seq,
      frame: mavFrameGlobalRelativeAlt,
      command: mavCmdNavWaypoint,
      current: seq == 1 ? 1 : 0,
      autocontinue: 1,
      param1: wp.hoverSeconds.toDouble(),
      param2: 2.0,
      param3: 0,
      param4: double.nan,
      x: (wp.latitude * 1e7).toInt(),
      y: (wp.longitude * 1e7).toInt(),
      z: wp.altitude,
      missionType: mavMissionTypeMission,
    );
    final frame = MavlinkFrame.v2(0, 255, 0, message);
    _missionSocket!.send(frame.serialize(), _missionHost!, _missionPort!);
    print('[SGT] Sent waypoint $seq: ${wp.latitude}, ${wp.longitude} at ${wp.altitude}m');
  }

  // -------------------------------------------------------------------------
  // Start mission
  // -------------------------------------------------------------------------

  void startMission({required bool useMock, DroneProvider? drone}) {
    if (!canStart) return;

    state = MissionState.executing;
    currentWaypoint = 0;
    statusMessage = 'Arming drone...';
    notifyListeners();

    if (useMock || drone == null) {
      _mockDrone = drone;
      drone?.resumeMockRoute();
      _simulateProgress();
      return;
    }

    _startRealMission(drone);
  }

  void _startRealMission(DroneProvider drone) {
    final socket = drone.socket;
    if (socket == null) return;

    final host = InternetAddress(drone.px4Host);
    final port = drone.px4Port;

    // Arm drone
    drone.arm();
    statusMessage = 'Arming...';
    notifyListeners();

    // Send mission start after arming
    Future.delayed(const Duration(seconds: 2), () {
      final message = CommandLong(
        targetSystem: 1,
        targetComponent: 1,
        command: mavCmdMissionStart,
        confirmation: 0,
        param1: 0,
        param2: 0,
        param3: 0,
        param4: 0,
        param5: 0,
        param6: 0,
        param7: 0,
      );
      final frame = MavlinkFrame.v2(0, 255, 0, message);
      socket.send(frame.serialize(), host, port);
      statusMessage = 'Mission executing...';
      notifyListeners();
      print('[SGT] Mission start sent');
    });
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
    DroneProvider? drone,
  }) {
    if (isPanicHold) return; // panic always takes priority
    if (state != MissionState.executing) return; // only interrupt an active patrol
    _stateBeforeHold = state;
    state = MissionState.holding;
    statusMessage = 'Investigating — holding position...';
    notifyListeners();
    print('[SGT] Holding at $lat, $lng for ${duration.inSeconds}s');

    drone?.setFocusPoint(lat: lat, lng: lng, reason: 'Investigating');
    if (!useMock && drone != null) {
      drone.reposition(lat: lat, lng: lng, alt: alt);
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
    DroneProvider? drone,
  }) {
    _holdTimer?.cancel(); // cancel any in-progress investigate hold — panic overrides it

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
    if (!useMock && drone != null) {
      drone.reposition(lat: lat, lng: lng, alt: alt);
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

  void stopMission({required bool useMock, DroneProvider? drone}) {
    if (!canStop) return;

    _progressTimer?.cancel();
    state = MissionState.idle;
    statusMessage = 'Mission stopped';
    currentWaypoint = 0;
    notifyListeners();

    if (useMock) {
      drone?.pauseMockRoute();
    } else if (drone != null) {
      drone.onMissionMessage = null;
      drone.returnToHome((success, message) {
        print('[SGT] RTH after stop: $message');
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
    super.dispose();
  }
}
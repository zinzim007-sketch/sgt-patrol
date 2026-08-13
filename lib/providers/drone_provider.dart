import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:dart_mavlink/mavlink.dart';
import 'package:dart_mavlink/dialects/common.dart';
import '../models/patrol_route.dart';

class DroneProvider extends ChangeNotifier {

  // -------------------------------------------------------------------------
  // Mock / Real switch
  // -------------------------------------------------------------------------

  bool useMock = kIsWeb;

  // -------------------------------------------------------------------------
  // MAVLink port config
  // -------------------------------------------------------------------------

  static const _px4Host = '127.0.0.1';
  static const _listenPort = 14550;
  static const _px4ReceivePort = 18570;

  // -------------------------------------------------------------------------
  // Internal
  // -------------------------------------------------------------------------

  RawDatagramSocket? _socket;
  Timer? _heartbeatTimer;
  final _parser = MavlinkParser(MavlinkDialectCommon());

  // Mission protocol callback — registered by MissionProvider
  Function(MavlinkFrame frame)? onMissionMessage;

  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------

  bool isConnected = false;
  String statusMessage = 'Initializing...';

  double altitude = 0.0;
  int batteryLevel = 100;
  double speed = 0.0;
  double latitude = 0.0;
  double longitude = 0.0;
  int gpsSatellites = 0;
  double heading = 0.0;

  // -------------------------------------------------------------------------
  // Focus mode — re-tasking the drone toward a verified pattern location
  // -------------------------------------------------------------------------
  //
  // This is "Version A" of pattern response: the drone loiters near a
  // location that the operator has verified as a real threat. It does
  // NOT track or follow a specific individual across the frame — that
  // would need person re-identification and active flight steering,
  // which isn't built. Be upfront about that distinction if asked.

  bool isFocusing = false;
  String? focusReason;
  double? _focusLat;
  double? _focusLng;

  /// Re-task the drone toward a location — called after the operator
  /// verifies a recurring-presence pattern as a real threat. Sends a
  /// real flight command (flyTo) in real mode. For panic dispatch, use
  /// MissionProvider.dispatchToPanic() instead — that path sends
  /// reposition() (preserves mission state) rather than flyTo(), and
  /// this method is kept for the existing pattern-verification flow.
  void focusOn({required double lat, required double lng, String? reason, double alt = 20}) {
    setFocusPoint(lat: lat, lng: lng, reason: reason);
    if (useMock) return;
    flyTo(lat: lat, lng: lng, alt: alt);
  }

  /// Sets the UI-facing "focusing on X" state (drives mock-mode jitter
  /// target and status message) WITHOUT sending any flight command.
  /// Used when the actual MAVLink command is sent separately by the
  /// caller (e.g. MissionProvider.dispatchToPanic sends reposition()
  /// itself) — kept separate so callers never risk double-sending
  /// conflicting commands.
  void setFocusPoint({required double lat, required double lng, String? reason}) {
    isFocusing = true;
    focusReason = reason;
    _focusLat = lat;
    _focusLng = lng;
    statusMessage = reason != null
        ? 'Repositioning — focusing on: $reason'
        : 'Repositioning to flagged location';
    notifyListeners();
  }

  /// Return to normal patrol behaviour.
  void clearFocus() {
    isFocusing = false;
    focusReason = null;
    _focusLat = null;
    _focusLng = null;
    statusMessage = isConnected ? 'Patrol resumed' : statusMessage;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Connect
  // -------------------------------------------------------------------------

  void connect() {
    if (useMock) {
      _connectMock();
    } else {
      _connectReal();
    }
  }

  // -------------------------------------------------------------------------
  // REAL
  // -------------------------------------------------------------------------

  void _connectReal() async {
    statusMessage = 'Connecting to PX4...';
    notifyListeners();

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _listenPort,
      );
      print('[SGT] Listening on port $_listenPort, sending to $_px4ReceivePort');

      _socket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket!.receive();
          if (datagram != null) {
            _parser.parse(datagram.data);
          }
        }
      });

      _parser.stream.listen(_handleMessage);

      _sendHeartbeat();
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _sendHeartbeat(),
      );

      statusMessage = 'Waiting for PX4 heartbeat...';
      notifyListeners();

    } catch (e) {
      statusMessage = 'Failed to connect: $e';
      isConnected = false;
      notifyListeners();
      print('[SGT] Connection error: $e');
    }
  }

  void _sendHeartbeat() {
    if (_socket == null) return;
    try {
      final heartbeat = Heartbeat(
        customMode: 0,
        type: mavTypeGcs,
        autopilot: mavAutopilotInvalid,
        baseMode: 0,
        systemStatus: mavStateActive,
        mavlinkVersion: 3,
      );
      final frame = MavlinkFrame.v2(0, 255, 0, heartbeat);
      _socket!.send(
        frame.serialize(),
        InternetAddress(_px4Host),
        _px4ReceivePort,
      );
    } catch (e) {
      print('[SGT] Heartbeat error: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Handle incoming MAVLink messages
  // -------------------------------------------------------------------------

  void _handleMessage(MavlinkFrame frame) {
    final message = frame.message;

    // Forward mission protocol messages to MissionProvider
    if (message is MissionRequestInt ||
        message is MissionRequest ||
        message is MissionAck ||
        message is MissionItemReached) {
      onMissionMessage?.call(frame);
      return;
    }

    if (message is GlobalPositionInt) {
      latitude = message.lat / 1e7;
      longitude = message.lon / 1e7;
      altitude = message.relativeAlt / 1000.0;
      heading = message.hdg / 100.0;
      if (!isConnected) {
        isConnected = true;
        statusMessage = 'Connected to PX4';
        print('[SGT] Connected — receiving telemetry');
      }
      notifyListeners();
    }

    else if (message is VfrHud) {
      speed = message.groundspeed.toDouble();
      notifyListeners();
    }

    else if (message is BatteryStatus) {
      if (message.batteryRemaining >= 0) {
        batteryLevel = message.batteryRemaining;
        if (batteryLevel <= 10) {
          statusMessage = 'Low battery - returning home';
        }
      }
      notifyListeners();
    }

    else if (message is GpsRawInt) {
      gpsSatellites = message.satellitesVisible;
      notifyListeners();
    }

    else if (message is Heartbeat) {
      if (!isConnected) {
        isConnected = true;
        statusMessage = 'Connected to PX4';
        notifyListeners();
        print('[SGT] Heartbeat received');
      }
    }
  }

  // -------------------------------------------------------------------------
  // MAVLink commands
  // -------------------------------------------------------------------------

  void _sendCommand({
    required int command,
    double param1 = 0,
    double param2 = 0,
    double param3 = 0,
    double param4 = 0,
    double param5 = 0,
    double param6 = 0,
    double param7 = 0,
  }) {
    if (_socket == null) return;
    final message = CommandLong(
      targetSystem: 1,
      targetComponent: 1,
      command: command,
      confirmation: 0,
      param1: param1,
      param2: param2,
      param3: param3,
      param4: param4,
      param5: param5,
      param6: param6,
      param7: param7,
    );
    final frame = MavlinkFrame.v2(0, 255, 0, message);
    _socket!.send(
      frame.serialize(),
      InternetAddress(_px4Host),
      _px4ReceivePort,
    );
  }

  void arm() {
    if (useMock || _socket == null) return;
    print('[SGT] Sending ARM...');
    _sendCommand(
      command: mavCmdComponentArmDisarm,
      param1: 1,
      param2: 21196,
    );
  }

  void disarm() {
    if (useMock || _socket == null) return;
    _sendCommand(command: mavCmdComponentArmDisarm, param1: 0);
  }

  void takeoff({double altitude = 10.0}) {
    if (useMock || _socket == null) return;
    print('[SGT] Sending TAKEOFF to ${altitude}m...');
    _sendCommand(
      command: mavCmdDoSetMode,
      param1: 1,
      param2: 4,
      param3: 2,
    );
    Future.delayed(const Duration(milliseconds: 500), () {
      _sendCommand(command: mavCmdNavTakeoff, param7: altitude);
    });
  }

  /// Directly repositions the drone (guided mode) to a lat/lng/alt.
  /// Used by focusOn() for real flight; can also be called directly.
  void flyTo({required double lat, required double lng, required double alt}) {
    if (useMock || _socket == null) return;
    final message = SetPositionTargetGlobalInt(
      timeBootMs: 0,
      targetSystem: 1,
      targetComponent: 1,
      coordinateFrame: mavFrameGlobalRelativeAlt,
      typeMask: 0x0FF8,
      latInt: (lat * 1e7).toInt(),
      lonInt: (lng * 1e7).toInt(),
      alt: alt,
      vx: 0, vy: 0, vz: 0,
      afx: 0, afy: 0, afz: 0,
      yaw: 0, yawRate: 0,
    );
    final frame = MavlinkFrame.v2(0, 255, 0, message);
    _socket!.send(frame.serialize(), InternetAddress(_px4Host), _px4ReceivePort);
  }

  /// Temporarily repositions the drone to hold over a point WITHOUT
  /// abandoning the active mission — PX4 resumes the mission from where
  /// it left off once this completes or is cancelled. This is the
  /// mechanism behind "drone breaks from route to investigate/respond
  /// to something," used by both the temporary investigate hold and the
  /// indefinite panic hold in MissionProvider.
  /// NOT YET BENCH-TESTED — verify this actually holds mission state
  /// correctly on your PX4 version before relying on it for a demo.
  void reposition({required double lat, required double lng, required double alt}) {
    if (useMock || _socket == null) return;
    _sendCommand(
      command: mavCmdDoReposition,
      param1: -1,           // ground speed: -1 = no change
      param2: 1,             // bitmask: bit0 set = change to reposition
      param3: 0,
      param4: double.nan,    // yaw: NaN = no change
      param5: lat,
      param6: lng,
      param7: alt,
    );
    print('[SGT] Reposition (hold) command sent: $lat, $lng at ${alt}m');
  }

  void returnToHome(Function(bool success, String message) callback) {
    if (useMock) {
      statusMessage = 'Returning to home...';
      notifyListeners();
      Future.delayed(const Duration(seconds: 3), () {
        statusMessage = 'Drone landed safely';
        isConnected = false;
        _clearTelemetry();
        callback(true, 'Mock: Drone returning home');
      });
      return;
    }
    _sendCommand(command: mavCmdNavReturnToLaunch);
    statusMessage = 'Returning to home...';
    notifyListeners();
    callback(true, 'Drone returning home');
  }

  // -------------------------------------------------------------------------
  // Expose connection for MissionProvider
  // -------------------------------------------------------------------------

  RawDatagramSocket? get socket => _socket;
  String get px4Host => _px4Host;
  int get px4Port => _px4ReceivePort;

  // -------------------------------------------------------------------------
  // MOCK
  // -------------------------------------------------------------------------

  Timer? _telemetryTimer;
  final _random = Random();
  bool _takingOff = true;
  int _takeoffStep = 0;

  List<PatrolWaypoint>? _mockRoute;
  int _mockWaypointIndex = 0;

  /// Called by MissionProvider when a route is uploaded in mock mode —
  /// from here on, the mock drone actually flies these waypoints
  /// instead of jittering around a fixed point. This is what makes
  /// mock-mode testing honest: position is driven by the real uploaded
  /// route, same as real PX4 flying a real mission — not a coincidence.
  void setMockRoute(List<PatrolWaypoint> waypoints) {
    _mockRoute = waypoints;
    _mockWaypointIndex = 0;
  }
  bool _routeAdvancing = false;

  /// Called by MissionProvider when the mock mission actually starts —
  /// only from here does the drone advance along its route.
  void resumeMockRoute() => _routeAdvancing = true;

  /// Called by MissionProvider when the mission completes or is stopped —
  /// freezes the drone in its current spot instead of continuing to
  /// wander the route on a timer disconnected from the real mission state.
  void pauseMockRoute() => _routeAdvancing = false;

  void _connectMock() {
    statusMessage = 'Mock drone connected';
    isConnected = true;
    batteryLevel = 100;
    gpsSatellites = 14;
    notifyListeners();

    _takingOff = true;
    _takeoffStep = 0;

    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (_takingOff) {
        _takeoffStep++;
        altitude += 0.5;
        if (_takeoffStep >= 40) _takingOff = false;
      } else {
        if (isFocusing && _focusLat != null && _focusLng != null) {
          // Dispatched somewhere (panic/investigate/verified pattern) —
          // takes priority over the patrol route, same as a real drone
          // breaking from its mission to respond to something.
          latitude = _focusLat! + (_random.nextDouble() * 0.0002 - 0.0001);
          longitude = _focusLng! + (_random.nextDouble() * 0.0002 - 0.0001);
        } else if (_routeAdvancing && _mockRoute != null && _mockRoute!.isNotEmpty) {
          _advanceAlongMockRoute();
        } else if (_mockRoute != null && _mockRoute!.isNotEmpty) {
          // Route exists but not actively advancing (mission complete/stopped) —
          // hold current position rather than resetting or drifting.
        } else {

          // No route uploaded yet — fallback jitter so the map isn't empty
          latitude = -33.919 + (_random.nextDouble() * 0.0004 - 0.0002);
          longitude = 18.423 + (_random.nextDouble() * 0.0004 - 0.0002);
        }

        altitude = 20.0 + (_random.nextDouble() * 2 - 1);
        speed = 2 + _random.nextInt(4).toDouble();
        batteryLevel = (batteryLevel - 1).clamp(0, 100);
        gpsSatellites = 12 + _random.nextInt(4);
        if (batteryLevel <= 10) {
          statusMessage = 'Low battery - returning home';
        }
      }
      notifyListeners();
    });
  }

  /// Moves the mock drone one step toward its current target waypoint;
  /// advances to the next waypoint on arrival, looping back to the
  /// start once the route completes — same as a real patrol repeating.
  void _advanceAlongMockRoute() {
    final target = _mockRoute![_mockWaypointIndex];
    final dLat = target.latitude - latitude;
    final dLng = target.longitude - longitude;
    final dist = sqrt(dLat * dLat + dLng * dLng);

    const step = 0.00006; // tune if it moves too fast/slow for testing
    if (dist < step) {
      latitude = target.latitude;
      longitude = target.longitude;
      _mockWaypointIndex = (_mockWaypointIndex + 1) % _mockRoute!.length;
    } else {
      latitude += dLat / dist * step;
      longitude += dLng / dist * step;
    }
  }

  // -------------------------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------------------------

  void _clearTelemetry() {
    altitude = 0.0;
    speed = 0.0;
    latitude = 0.0;
    longitude = 0.0;
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _heartbeatTimer?.cancel();
    _socket?.close();
    super.dispose();
  }
}
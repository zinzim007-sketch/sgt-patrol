import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:dart_mavlink/dart_mavlink.dart';

/// DroneProvider — connects to PX4 via MAVLink and streams real telemetry.
///
/// MOCK MODE (useMock = true):
///   Generates fake telemetry for UI testing without PX4 running.
///   Used automatically on web builds since web can't open UDP sockets.
///
/// REAL MODE (useMock = false):
///   Connects to PX4 SITL (or real hardware) via MAVLink UDP.
///   Requires Flutter Windows/Mac/Linux desktop build.
///   Make sure PX4 SITL is running before connecting.

class DroneProvider extends ChangeNotifier {

  // -------------------------------------------------------------------------
  // Mock / Real switch
  // Auto-mock on web since browsers can't open UDP sockets
  // -------------------------------------------------------------------------

  bool useMock = kIsWeb;

  // -------------------------------------------------------------------------
  // MAVLink connection
  // -------------------------------------------------------------------------

  MavlinkCommunication? _comm;
  StreamSubscription? _subscription;

  static const _mavlinkHost = '127.0.0.1';
  static const _mavlinkPort = 14550;

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
  // REAL — MAVLink via dart_mavlink
  // -------------------------------------------------------------------------

  void _connectReal() async {
    statusMessage = 'Connecting to PX4...';
    notifyListeners();

    try {
      _comm = MavlinkCommunication(
        MavlinkCommunicationType.udp,
        _mavlinkHost,
        _mavlinkPort,
      );

      await _comm!.connect();

      isConnected = true;
      statusMessage = 'Connected to PX4';
      notifyListeners();

      // Listen for incoming MAVLink messages
      _subscription = _comm!.messagesStream.listen((MavlinkFrame frame) {
        _handleMessage(frame);
      }, onError: (error) {
        statusMessage = 'MAVLink error: $error';
        isConnected = false;
        notifyListeners();
      });

      print('[SGT] MAVLink connected to PX4 on $_mavlinkHost:$_mavlinkPort');

    } catch (e) {
      statusMessage = 'Failed to connect to PX4: $e';
      isConnected = false;
      notifyListeners();
      print('[SGT] MAVLink connection failed: $e');
    }
  }

  void _handleMessage(MavlinkFrame frame) {
    final message = frame.message;

    // Global position — lat, lng, altitude
    if (message is GlobalPositionInt) {
      latitude = message.lat / 1e7;
      longitude = message.lon / 1e7;
      altitude = message.relativeAlt / 1000.0;
      heading = message.hdg / 100.0;
      notifyListeners();
    }

    // VFR HUD — speed, altitude, heading
    else if (message is VfrHud) {
      speed = message.groundspeed.toDouble();
      notifyListeners();
    }

    // Battery status
    else if (message is BatteryStatus) {
      batteryLevel = message.batteryRemaining;
      if (batteryLevel <= 10) {
        statusMessage = '⚠️ Low battery — returning home';
      }
      notifyListeners();
    }

    // GPS raw — satellite count
    else if (message is GpsRawInt) {
      gpsSatellites = message.satellitesVisible;
      notifyListeners();
    }

    // Heartbeat — confirms drone is alive
    else if (message is Heartbeat) {
      if (!isConnected) {
        isConnected = true;
        statusMessage = 'Connected to PX4';
        notifyListeners();
      }
    }
  }

  // -------------------------------------------------------------------------
  // MAVLink commands
  // -------------------------------------------------------------------------

  Future<void> arm() async {
    if (useMock || _comm == null) return;
    print('[SGT] Arming...');
    _sendCommand(
      MavCmd.mavCmdComponentArmDisarm,
      param1: 1, // 1 = arm
    );
  }

  Future<void> takeoff({double altitude = 10.0}) async {
    if (useMock || _comm == null) return;
    print('[SGT] Taking off to ${altitude}m...');
    _sendCommand(
      MavCmd.mavCmdNavTakeoff,
      param7: altitude,
    );
  }

  Future<void> flyTo({
    required double lat,
    required double lng,
    required double alt,
  }) async {
    if (useMock || _comm == null) return;
    print('[SGT] Flying to $lat, $lng at ${alt}m...');

    final message = SetPositionTargetGlobalInt(
      timBootMs: 0,
      targetSystem: 1,
      targetComponent: 1,
      coordinateFrame: MavFrame.mavFrameGlobalRelativeAlt,
      typeMask: 0b0000111111111000,
      latInt: (lat * 1e7).toInt(),
      lonInt: (lng * 1e7).toInt(),
      alt: alt,
      vx: 0,
      vy: 0,
      vz: 0,
      afx: 0,
      afy: 0,
      afz: 0,
      yaw: 0,
      yawRate: 0,
    );

    final frame = MavlinkFrame.v2(0, 1, 1, message);
    _comm!.write(frame);
  }

  void _sendCommand(
    MavCmd command, {
    double param1 = 0,
    double param2 = 0,
    double param3 = 0,
    double param4 = 0,
    double param5 = 0,
    double param6 = 0,
    double param7 = 0,
  }) {
    if (_comm == null) return;

    final message = CommandLong(
      targetSystem: 1,
      targetComponent: 1,
      command: command.index,
      confirmation: 0,
      param1: param1,
      param2: param2,
      param3: param3,
      param4: param4,
      param5: param5,
      param6: param6,
      param7: param7,
    );

    final frame = MavlinkFrame.v2(0, 1, 1, message);
    _comm!.write(frame);
  }

  // -------------------------------------------------------------------------
  // Return to home
  // -------------------------------------------------------------------------

  void returnToHome(Function(bool success, String message) callback) {
    if (useMock) {
      statusMessage = 'Returning to home...';
      Future.delayed(const Duration(seconds: 3), () {
        statusMessage = 'Mock: Drone landed safely';
        isConnected = false;
        _clearTelemetry();
        notifyListeners();
        callback(true, 'Mock: Drone returning home');
      });
      notifyListeners();
      return;
    }

    _sendCommand(MavCmd.mavCmdNavReturnToLaunch);
    statusMessage = 'Returning to home...';
    notifyListeners();
    callback(true, 'Drone returning home');
  }

  // -------------------------------------------------------------------------
  // MOCK — fake telemetry for web/UI testing
  // -------------------------------------------------------------------------

  Timer? _telemetryTimer;
  final _random = Random();
  bool _takingOff = true;
  int _takeoffStep = 0;

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
        altitude = 20.0 + (_random.nextDouble() * 2 - 1);
        speed = 2 + _random.nextInt(4).toDouble();
        batteryLevel = (batteryLevel - 1).clamp(0, 100);
        latitude = -33.919 + (_random.nextDouble() * 0.0004 - 0.0002);
        longitude = 18.423 + (_random.nextDouble() * 0.0004 - 0.0002);
        gpsSatellites = 12 + _random.nextInt(4);
        if (batteryLevel <= 10) {
          statusMessage = '⚠️ Low battery — returning home';
        }
      }
      notifyListeners();
    });
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
    _subscription?.cancel();
    _comm?.close();
    super.dispose();
  }
}
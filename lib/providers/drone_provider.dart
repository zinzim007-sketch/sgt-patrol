import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:dart_mavlink/mavlink.dart';
import 'package:dart_mavlink/dialects/common.dart';

/// DroneProvider — connects to PX4 via MAVLink UDP and streams real telemetry.
///
/// PORT LAYOUT:
///   Flutter listens on 14550 — PX4 sends telemetry here
///   Flutter sends to 18570  — PX4 listens for GCS commands here
///
/// MOCK MODE: auto-enabled on web (kIsWeb = true)
/// REAL MODE: Windows desktop, PX4 SITL running in WSL

class DroneProvider extends ChangeNotifier {

  // -------------------------------------------------------------------------
  // Mock / Real switch
  // -------------------------------------------------------------------------

  bool useMock = kIsWeb;

  // -------------------------------------------------------------------------
  // MAVLink port config
  // -------------------------------------------------------------------------

  static const _px4Host = '127.0.0.1';       // WSL mirrored networking
  static const _listenPort = 14550;           // Flutter listens for PX4 telemetry
  static const _px4ReceivePort = 18570;       // PX4 listens for GCS commands

  // -------------------------------------------------------------------------
  // Internal
  // -------------------------------------------------------------------------

  RawDatagramSocket? _socket;
  Timer? _heartbeatTimer;
  final _parser = MavlinkParser(MavlinkDialectCommon());

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
  // REAL — UDP socket + dart_mavlink parser
  // -------------------------------------------------------------------------

  void _connectReal() async {
    statusMessage = 'Connecting to PX4...';
    notifyListeners();

    try {
      // Bind to listen for PX4 telemetry on port 14550
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _listenPort,
      );
      print('[SGT] Listening for PX4 telemetry on port $_listenPort');
      print('[SGT] Sending GCS commands to PX4 on port $_px4ReceivePort');

      // Listen for incoming datagrams from PX4
      _socket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket!.receive();
          if (datagram != null) {
            _parser.parse(datagram.data);
          }
        }
      });

      // Parse MAVLink messages
      _parser.stream.listen(_handleMessage);

      // Send heartbeats to PX4's GCS receive port (18570)
      // This tells PX4 a GCS is connected and allows arming
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

  // Send heartbeat TO PX4 on port 18570
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
        _px4ReceivePort, // Send to PX4's GCS port
      );
    } catch (e) {
      print('[SGT] Heartbeat error: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Handle incoming MAVLink messages from PX4
  // -------------------------------------------------------------------------

  void _handleMessage(MavlinkFrame frame) {
    final message = frame.message;

    if (message is GlobalPositionInt) {
      latitude = message.lat / 1e7;
      longitude = message.lon / 1e7;
      altitude = message.relativeAlt / 1000.0;
      heading = message.hdg / 100.0;
      if (!isConnected) {
        isConnected = true;
        statusMessage = 'Connected to PX4';
        print('[SGT] Connected — receiving position telemetry');
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
  // MAVLink commands — send to PX4 on port 18570
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
      _px4ReceivePort, // Always send commands to PX4's GCS port
    );
  }

  void arm() {
    if (useMock || _socket == null) return;
    print('[SGT] Sending ARM command...');
    _sendCommand(
      command: mavCmdComponentArmDisarm,
      param1: 1,
      param2: 21196, // Force arm in SITL
    );
  }

  void disarm() {
    if (useMock || _socket == null) return;
    print('[SGT] Sending DISARM command...');
    _sendCommand(
      command: mavCmdComponentArmDisarm,
      param1: 0,
    );
  }

  /*void takeoff({double altitude = 10.0}) {
    if (useMock || _socket == null) return;
    print('[SGT] Sending TAKEOFF command to ${altitude}m...');
    _sendCommand(
      command: mavCmdNavTakeoff,
      param7: altitude,
    );
  }*/
  void takeoff({double altitude = 10.0}) {
    if (useMock || _socket == null) return;
    print('[SGT] Setting mode to TAKEOFF...');
    
    // First set mode to auto takeoff
    _sendCommand(
      command: mavCmdDoSetMode,
      param1: 1,    // MAV_MODE_FLAG_CUSTOM_MODE_ENABLED
      param2: 4,    // PX4 auto mode
      param3: 2,    // PX4 takeoff submode
    );
    
    // Then send takeoff command
    Future.delayed(const Duration(milliseconds: 500), () {
      print('[SGT] Sending TAKEOFF to ${altitude}m...');
      _sendCommand(
        command: mavCmdNavTakeoff,
        param7: altitude,
      );
    });
  }

  void flyTo({required double lat, required double lng, required double alt}) {
    if (useMock || _socket == null) return;
    print('[SGT] Flying to $lat, $lng at ${alt}m...');
    final message = SetPositionTargetGlobalInt(
      timeBootMs: 0,
      targetSystem: 1,
      targetComponent: 1,
      coordinateFrame: mavFrameGlobalRelativeAlt,
      typeMask: 0x0FF8,
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
    final frame = MavlinkFrame.v2(0, 255, 0, message);
    _socket!.send(
      frame.serialize(),
      InternetAddress(_px4Host),
      _px4ReceivePort,
    );
  }

  // -------------------------------------------------------------------------
  // Return to home
  // -------------------------------------------------------------------------

  void returnToHome(Function(bool success, String message) callback) {
    if (useMock) {
      statusMessage = 'Returning to home...';
      notifyListeners();
      Future.delayed(const Duration(seconds: 3), () {
        statusMessage = 'Drone landed safely';
        isConnected = false;
        _clearTelemetry();
        notifyListeners();
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
  // MOCK
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
          statusMessage = 'Low battery - returning home';
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
    _heartbeatTimer?.cancel();
    _socket?.close();
    super.dispose();
  }
}
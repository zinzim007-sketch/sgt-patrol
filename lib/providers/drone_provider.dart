import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
 
/// DroneProvider — single source of truth for drone state in Flutter.
///
/// Replaces the Kotlin DroneManager. Uses ChangeNotifier so any widget
/// that calls context.watch<DroneProvider>() rebuilds automatically
/// when telemetry updates.
///
/// Mock mode is on by default (kDebugMode). Real DJI SDK wiring goes
/// in _connectReal() when you're ready for hardware.
class DroneProvider extends ChangeNotifier {
  // -------------------------------------------------------------------------
  // Mock / Real switch
  // -------------------------------------------------------------------------
 
  bool useMock = kDebugMode;
 
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
 
    // Simulate takeoff over 8 seconds
    _takingOff = true;
    _takeoffStep = 0;
 
    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (_takingOff) {
        _takeoffStep++;
        altitude += 0.5;
        if (_takeoffStep >= 40) {
          _takingOff = false;
        }
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
  // REAL — stub until DJI Flutter SDK is configured
  //
  // TODO: When ready for real hardware:
  //  1. Add DJI Flutter SDK to pubspec.yaml
  //  2. Replace this stub with real SDK initialisation
  //  3. Set useMock = false
  // -------------------------------------------------------------------------
 
  void _connectReal() {
    statusMessage = 'Error: DJI SDK not yet configured. Enable mock mode.';
    notifyListeners();
  }
 
  // -------------------------------------------------------------------------
  // Return to home
  // -------------------------------------------------------------------------
 
  void returnToHome(Function(bool success, String message) callback) {
    if (useMock) {
      statusMessage = 'Returning to home...';
      notifyListeners();
      Future.delayed(const Duration(seconds: 3), () {
        statusMessage = 'Landed safely';
        isConnected = false;
        _clearTelemetry();
        notifyListeners();
        callback(true, 'Mock: Drone landed safely');
      });
      return;
    }
    // TODO: Real DJI RTH call
    callback(false, 'Real RTH not yet implemented');
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
    super.dispose();
  }
}
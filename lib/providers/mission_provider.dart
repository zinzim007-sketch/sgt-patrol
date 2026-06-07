import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/patrol_route.dart';
 
enum MissionState { idle, uploading, ready, executing, complete, error }
 
/// MissionProvider — manages waypoint mission lifecycle.
/// Replaces the Kotlin MissionManager.
class MissionProvider extends ChangeNotifier {
 
  MissionState state = MissionState.idle;
  String statusMessage = 'No mission loaded';
  int currentWaypoint = 0;
  int totalWaypoints = 0;
 
  bool get canUpload => state == MissionState.idle || state == MissionState.error;
  bool get canStart => state == MissionState.ready;
  bool get canStop => state == MissionState.executing;
 
  // -------------------------------------------------------------------------
  // Upload
  // -------------------------------------------------------------------------
 
  void uploadMission(PatrolRoute route, {required bool useMock}) {
    if (!canUpload) return;
 
    state = MissionState.uploading;
    totalWaypoints = route.waypoints.length;
    statusMessage = 'Uploading mission (${route.waypoints.length} waypoints)...';
    notifyListeners();
 
    if (useMock) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        state = MissionState.ready;
        statusMessage = 'Mission ready';
        notifyListeners();
      });
      return;
    }
 
    // TODO: Real DJI upload
    state = MissionState.error;
    statusMessage = 'DJI SDK not configured';
    notifyListeners();
  }
 
  // -------------------------------------------------------------------------
  // Start
  // -------------------------------------------------------------------------
 
  void startMission({required bool useMock}) {
    if (!canStart) return;
 
    state = MissionState.executing;
    currentWaypoint = 0;
    statusMessage = 'Drone taking off...';
    notifyListeners();
 
    if (useMock) {
      _simulateProgress();
      return;
    }
 
    // TODO: Real DJI start
    state = MissionState.error;
    statusMessage = 'DJI SDK not configured';
    notifyListeners();
  }
 
  // -------------------------------------------------------------------------
  // Stop
  // -------------------------------------------------------------------------
 
  void stopMission({required bool useMock}) {
    if (!canStop) return;
 
    _progressTimer?.cancel();
    state = MissionState.idle;
    statusMessage = 'Mission stopped';
    currentWaypoint = 0;
    notifyListeners();
  }
 
  // -------------------------------------------------------------------------
  // Mock progress simulation
  // -------------------------------------------------------------------------
 
  Timer? _progressTimer;
  int _step = 0;
 
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
        statusMessage = '✅ Patrol complete';
        currentWaypoint = 0;
      }
      notifyListeners();
    });
  }
 
  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }
}
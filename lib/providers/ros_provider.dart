import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:roslibdart/roslibdart.dart';

/// RosProvider — connects Flutter to ROS 2 via rosbridge WebSocket.
///
/// Rosbridge runs in WSL on port 9090.
///
/// When a dispatch_drone command arrives from the Mission Planner:
///   1. Shows a critical alert in the operator dashboard
///   2. Automatically sends the drone to investigate (if GPS available)
///
/// Callbacks are wired in main.dart after all providers exist:
///   rosProvider.onDispatchDrone = (reason, confidence) => ...
///   rosProvider.onRaiseAlert = (reason, confidence) => ...

class RosProvider extends ChangeNotifier {

  static const _rosbridgeUrl = 'ws://127.0.0.1:9090';

  Ros? _ros;
  Topic? _detectionsSub;
  Topic? _commandsSub;
  Topic? _operatorPub;

  bool isConnected = false;
  String statusMessage = 'ROS 2 disconnected';

  List<Map<String, dynamic>> latestDetections = [];
  Map<String, dynamic>? latestCommand;

  // Callbacks wired by main.dart after all providers are created
  void Function(String reason, int confidence)? onDispatchDrone;
  void Function(String reason, int confidence)? onRaiseAlert;

  RosProvider() {
    print('[SGT ROS] RosProvider created');
  }

  // -------------------------------------------------------------------------
  // Connect
  // -------------------------------------------------------------------------

  Future<void> connect() async {
    print('[SGT ROS] Attempting to connect to $_rosbridgeUrl...');
    try {
      _ros = Ros(url: _rosbridgeUrl);
      _ros!.connect();

      await Future.delayed(const Duration(seconds: 1));

      isConnected = true;
      statusMessage = 'Connected to ROS 2';
      notifyListeners();
      print('[SGT ROS] Connected to rosbridge at $_rosbridgeUrl');

      await _subscribeToDetections();
      await _subscribeToCommands();
      _setupOperatorPublisher();

    } catch (e) {
      statusMessage = 'ROS 2 connection failed: $e';
      isConnected = false;
      notifyListeners();
      print('[SGT ROS] Connection error: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Subscribe to /safeguard/detections
  // -------------------------------------------------------------------------

  Future<void> _subscribeToDetections() async {
    _detectionsSub = Topic(
      ros: _ros!,
      name: '/safeguard/detections',
      type: 'std_msgs/String',
      reconnectOnClose: true,
      queueLength: 10,
      queueSize: 10,
    );

    await _detectionsSub!.subscribe(_onDetection);
    print('[SGT ROS] Subscribed to /safeguard/detections');
  }

  Future<void> _onDetection(Map<String, dynamic> message) async {
    try {
      final data = message['data'] as String;
      final detections = jsonDecode(data) as List<dynamic>;
      latestDetections = detections.cast<Map<String, dynamic>>();
      notifyListeners();
    } catch (e) {
      print('[SGT ROS] Detection parse error: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Subscribe to /safeguard/commands
  // -------------------------------------------------------------------------

  Future<void> _subscribeToCommands() async {
    _commandsSub = Topic(
      ros: _ros!,
      name: '/safeguard/commands',
      type: 'std_msgs/String',
      reconnectOnClose: true,
      queueLength: 10,
      queueSize: 10,
    );

    await _commandsSub!.subscribe(_onCommand);
    print('[SGT ROS] Subscribed to /safeguard/commands');
  }

  // Throttle — don't fire the same action more than once per 10 seconds
  final Map<String, DateTime> _lastFired = {};

  Future<void> _onCommand(Map<String, dynamic> message) async {
    try {
      final data = message['data'] as String;
      final command = jsonDecode(data) as Map<String, dynamic>;
      latestCommand = command;
      notifyListeners();

      final action = command['action'] as String;
      final reason = command['reason'] as String? ?? 'Unknown';
      final confidence = command['confidence'] as int? ?? 0;

      // Throttle per action type
      final now = DateTime.now();
      final last = _lastFired[action];
      if (last != null && now.difference(last).inSeconds < 10) return;
      _lastFired[action] = now;

      print('[SGT ROS] Command: $action ($reason $confidence%)');

      switch (action) {
        case 'dispatch_drone':
          // Trigger critical alert + autonomous drone dispatch
          onDispatchDrone?.call(reason, confidence);
          break;
        case 'raise_alert':
          // Trigger alert in dashboard
          onRaiseAlert?.call(reason, confidence);
          break;
      }

    } catch (e) {
      print('[SGT ROS] Command parse error: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Publish operator actions to /safeguard/operator
  // -------------------------------------------------------------------------

  void _setupOperatorPublisher() {
    _operatorPub = Topic(
      ros: _ros!,
      name: '/safeguard/operator',
      type: 'std_msgs/String',
    );
  }

  Future<void> publishOperatorAction(
    String action, {
    String? alertId,
    String? reason,
  }) async {
    if (!isConnected || _operatorPub == null) return;

    final message = {
      'action': action,
      'alert_id': alertId,
      'reason': reason,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    await _operatorPub!.publish({'data': jsonEncode(message)});
    print('[SGT ROS] Operator action: $action');
  }

  // -------------------------------------------------------------------------
  // Disconnect
  // -------------------------------------------------------------------------

  void disconnect() {
    _detectionsSub?.unsubscribe();
    _commandsSub?.unsubscribe();
    _ros?.close();
    isConnected = false;
    statusMessage = 'ROS 2 disconnected';
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
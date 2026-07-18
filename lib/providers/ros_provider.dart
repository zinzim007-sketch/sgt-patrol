import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:roslibdart/roslibdart.dart';

/// RosProvider — connects Flutter to ROS 2 via rosbridge WebSocket.
///
/// Rosbridge runs in WSL on port 9090.
/// Subscribes to /safeguard/detections and /safeguard/commands.
/// Publishes operator actions to /safeguard/operator.

class RosProvider extends ChangeNotifier {

  static const _rosbridgeUrl = 'ws://127.0.0.1:9090';
  RosProvider() {
    print('[SGT ROS] RosProvider created');
  }
  Ros? _ros;
  Topic? _detectionsSub;
  Topic? _commandsSub;
  Topic? _operatorPub;

  bool isConnected = false;
  String statusMessage = 'ROS 2 disconnected';

  List<Map<String, dynamic>> latestDetections = [];
  Map<String, dynamic>? latestCommand;

  // -------------------------------------------------------------------------
  // Connect
  // -------------------------------------------------------------------------

  Future<void> connect() async {
    print('[SGT ROS] Attempting to connect to $_rosbridgeUrl...');
  
    try {
      _ros = Ros(url: _rosbridgeUrl);
      _ros!.connect();

      // Give rosbridge a moment to connect
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

  Future<void> _onCommand(Map<String, dynamic> message) async {
    try {
      final data = message['data'] as String;
      latestCommand = jsonDecode(data) as Map<String, dynamic>;
      notifyListeners();
      print('[SGT ROS] Command: ${latestCommand?['action']}');
    } catch (e) {
      print('[SGT ROS] Command parse error: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Publish operator actions
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
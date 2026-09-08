import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class GeminiProvider extends ChangeNotifier {
  static const _wsUrl = 'ws://localhost:8767';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  bool isConnected = false;
  String statusMessage = 'Gemini AI ready';

  String sceneStatus = 'NORMAL';
  String activityLevel = 'LOW';
  int peopleCount = 0;
  int vehicleCount = 0;
  String interaction = 'NONE';
  String concern = 'NONE';
  String riskLevel = 'LOW';
  double confidence = 0.0;
  String summary = 'Waiting for Gemini scene assessment...';

  DateTime? lastUpdate;

  void connect() {
    if (isConnected) return;

    try {
      statusMessage = 'Connecting to Gemini AI...';
      notifyListeners();

      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: (error) {
          isConnected = false;
          statusMessage = 'Gemini connection error';
          notifyListeners();
        },
        onDone: () {
          isConnected = false;
          statusMessage = 'Gemini AI disconnected';
          notifyListeners();
        },
      );

      isConnected = true;
      statusMessage = 'Gemini AI live';
      notifyListeners();
    } catch (_) {
      isConnected = false;
      statusMessage = 'Could not connect to Gemini bridge';
      notifyListeners();
    }
  }

  void disconnect() {
    _subscription?.cancel();
    _channel?.sink.close();
    _subscription = null;
    _channel = null;
    isConnected = false;
    statusMessage = 'Gemini AI stopped';
    notifyListeners();
  }

  void _onMessage(dynamic message) {
    try {
      final decoded = jsonDecode(message as String);

      // The bridge may send an informational/status message.
      if (decoded is! Map<String, dynamic>) return;

      if (decoded['type'] == 'status') {
        statusMessage = decoded['message'] as String? ?? statusMessage;
        notifyListeners();
        return;
      }

      // Accept either the intelligence object directly or an envelope.
      final Map<String, dynamic> data =
          decoded['intelligence'] is Map
              ? Map<String, dynamic>.from(decoded['intelligence'] as Map)
              : decoded;

      if (data['scene_status'] != null) {
        sceneStatus = data['scene_status'].toString().toUpperCase();
      }

      if (data['activity_level'] != null) {
        activityLevel = data['activity_level'].toString().toUpperCase();
      }

      if (data['people_count'] != null) {
        peopleCount = _toInt(data['people_count']);
      }

      if (data['vehicle_count'] != null) {
        vehicleCount = _toInt(data['vehicle_count']);
      }

      if (data['interaction'] != null) {
        interaction = data['interaction'].toString().toUpperCase();
      }

      if (data['concern'] != null) {
        concern = data['concern'].toString().toUpperCase();
      }

      if (data['risk_level'] != null) {
        riskLevel = data['risk_level'].toString().toUpperCase();
      }

      if (data['confidence'] != null) {
        confidence = _toDouble(data['confidence']).clamp(0.0, 1.0);
      }

      if (data['summary'] != null) {
        summary = data['summary'].toString();
      }

      lastUpdate = DateTime.now();
      statusMessage = 'Gemini AI live';
      notifyListeners();
    } catch (_) {
      // Ignore malformed messages so one bad packet cannot break the UI.
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/detection_alert.dart';
import '../models/alert_engine.dart';
import '../models/site_config.dart';

class DetectionProvider extends ChangeNotifier {

  static const _wsUrl = 'ws://localhost:8765';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  bool isConnected = false;
  bool isDetecting = false;
  String statusMessage = 'Detection ready';
  String? currentFrameBase64;

  // Active site config — swap per client deployment
  SiteConfig siteConfig = SiteConfig.demo;
  late AlertEngine _engine;

  DetectionProvider() {
    _engine = AlertEngine(siteConfig: siteConfig);
  }

  void setSiteConfig(SiteConfig config) {
    siteConfig = config;
    _engine = AlertEngine(siteConfig: config);
    notifyListeners();
  }

  final List<DetectionAlert> alerts = [];

  // Only alerts that need operator attention (watch, alert, critical)
  List<DetectionAlert> get activeAlerts =>
      alerts.where((a) => !a.dismissed && a.requiresAttention).toList();

  // Only critical alerts
  List<DetectionAlert> get criticalAlerts =>
      alerts.where((a) => !a.dismissed && a.isCritical).toList();

  int get unreadCount => activeAlerts.length;
  bool get hasCritical => criticalAlerts.isNotEmpty;

  // -------------------------------------------------------------------------
  // Panic button trigger
  // -------------------------------------------------------------------------

  void triggerPanic({double? lat, double? lng}) {
    final result = _engine.evaluate(
      detectionClass: DetectionClass.person,
      latitude: lat,
      longitude: lng,
      scenario: ScenarioTrigger.panicButton,
    );

    final now = DateTime.now();
    alerts.insert(0, DetectionAlert(
      id: 'panic_${now.millisecondsSinceEpoch}',
      label: 'PANIC',
      className: 'panic',
      confidence: 100,
      timestamp: now,
      engineResult: result,
      latitude: lat,
      longitude: lng,
    ));
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Connect to Python detection server
  // -------------------------------------------------------------------------

  void connect({double? lat, double? lng}) {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      isConnected = true;
      isDetecting = true;
      statusMessage = 'Detection active';
      notifyListeners();

      _subscription = _channel!.stream.listen(
        (message) => _onMessage(message, lat: lat, lng: lng),
        onError: (error) {
          statusMessage = 'Connection error — is detector.py running?';
          isConnected = false;
          isDetecting = false;
          notifyListeners();
        },
        onDone: () {
          statusMessage = 'Detection server disconnected';
          isConnected = false;
          isDetecting = false;
          notifyListeners();
        },
      );
    } catch (e) {
      statusMessage = 'Could not connect — run detector.py first';
      isConnected = false;
      isDetecting = false;
      notifyListeners();
    }
  }

  void disconnect() {
    _channel?.sink.add(jsonEncode({'action': 'stop'}));
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    isConnected = false;
    isDetecting = false;
    currentFrameBase64 = null;
    statusMessage = 'Detection stopped';
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Handle incoming WebSocket messages
  // -------------------------------------------------------------------------

  final Map<String, DateTime> _lastAlerted = {};

  void _onMessage(dynamic message, {double? lat, double? lng}) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;

      if (data['type'] == 'frame') {
        currentFrameBase64 = data['frame'] as String?;

        final detections = data['detections'] as List<dynamic>? ?? [];
        for (final det in detections) {
          _handleDetection(det as Map<String, dynamic>, lat: lat, lng: lng);
        }

        notifyListeners();
      }
    } catch (_) {}
  }

  void _handleDetection(
    Map<String, dynamic> det, {
    double? lat,
    double? lng,
  }) {
    final className = det['class'] as String;
    final now = DateTime.now();

    // Throttle per class
    final last = _lastAlerted[className];
    if (last != null && now.difference(last).inSeconds < 5) return;
    _lastAlerted[className] = now;

    // Map YOLO class to DetectionClass
    final detClass = _mapClass(className);

    // Run through alert engine
    final result = _engine.evaluate(
      detectionClass: detClass,
      latitude: lat,
      longitude: lng,
    );

    // Skip logging level alerts from appearing in the active panel
    // They still get added to the full alerts list for history
    final alert = DetectionAlert(
      id: '${className}_${now.millisecondsSinceEpoch}',
      label: det['label'] as String,
      className: className,
      confidence: det['confidence'] as int,
      timestamp: now,
      engineResult: result,
      latitude: lat,
      longitude: lng,
    );

    alerts.insert(0, alert);
    if (alerts.length > 100) alerts.removeLast();
  }

  DetectionClass _mapClass(String className) {
    switch (className) {
      case 'person': return DetectionClass.person;
      case 'car':
      case 'truck':
      case 'motorcycle':
      case 'bus':
      case 'bicycle': return DetectionClass.vehicle;
      case 'dog':
      case 'cat':
      case 'horse':
      case 'cow':
      case 'sheep': return DetectionClass.animal;
      case 'fire': return DetectionClass.fire;
      case 'smoke': return DetectionClass.smoke;
      default: return DetectionClass.unknown;
    }
  }

  // -------------------------------------------------------------------------
  // Alert actions
  // -------------------------------------------------------------------------

  void dismissAlert(String id) {
    try {
      alerts.firstWhere((a) => a.id == id).dismissed = true;
      notifyListeners();
    } catch (_) {}
  }

  void markReportedToAuthorities(String id) {
    try {
      alerts.firstWhere((a) => a.id == id).reportedToAuthorities = true;
      notifyListeners();
    } catch (_) {}
  }

  void markDroneDispatched(String id) {
    try {
      alerts.firstWhere((a) => a.id == id).droneDispatched = true;
      notifyListeners();
    } catch (_) {}
  }

  void operatorEscalate(String id, {double? lat, double? lng}) {
    try {
      final alert = alerts.firstWhere((a) => a.id == id);
      final result = _engine.evaluate(
        detectionClass: _mapClass(alert.className),
        latitude: lat,
        longitude: lng,
        scenario: ScenarioTrigger.operatorFlagged,
      );
      final escalated = DetectionAlert(
        id: 'escalated_${DateTime.now().millisecondsSinceEpoch}',
        label: alert.label,
        className: alert.className,
        confidence: alert.confidence,
        timestamp: DateTime.now(),
        engineResult: result,
        latitude: lat,
        longitude: lng,
      );
      alert.dismissed = true;
      alerts.insert(0, escalated);
      notifyListeners();
    } catch (_) {}
  }

  void clearAllAlerts() {
    alerts.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

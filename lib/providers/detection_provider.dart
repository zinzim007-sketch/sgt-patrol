import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/detection_alert.dart';
import '../models/alert_engine.dart';
import '../models/site_config.dart';
import '../models/feedback_stats.dart';
import '../services/feedback_storage_service.dart';

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

  // Feedback learning — confirm/dismiss history per zone+class, persisted
  // locally so AlertEngine's adaptive downgrading survives app restarts.
  final FeedbackStorageService _feedbackStorage = FeedbackStorageService();
  FeedbackStats _feedbackStats = FeedbackStats();

  /// Wire this in app setup to connect pattern-verification to the
  /// drone, e.g.:
  ///   detectionProvider.onFocusRequested = (lat, lng, reason) =>
  ///       droneProvider.focusOn(lat: lat, lng: lng, reason: reason);
  /// Left null-safe on purpose — if it's never wired, verifyThreat()
  /// still logs the confirmation, it just won't move the drone.
  void Function(double lat, double lng, String reason)? onFocusRequested;
  void Function(double lat, double lng)? onInvestigateRequested;

  /// Wire this in main.dart to mission.dispatchToPanic(). Fired from
  /// triggerPanic() whenever a real GPS fix is available, so panic
  /// gets the "interrupt anything, hold indefinitely" behavior instead
  /// of onFocusRequested's re-tasking (which doesn't override an
  /// active mission the same way).
  void Function(double lat, double lng)? onPanicDispatchRequested;

  /// Live drone position lookup — wire this in main.dart, e.g.:
  ///   detectionProvider.getDronePosition =
  ///       () => (lat: drone.latitude, lng: drone.longitude);
  /// Called fresh for every incoming detection batch, NOT captured once
  /// at connect() time — the drone moves during a patrol, so a snapshot
  /// taken when detection started would go stale immediately.
  ({double lat, double lng})? Function()? getDronePosition;

  DetectionProvider() {
    _engine = AlertEngine(siteConfig: siteConfig);
    _loadFeedbackStats();
  }

  Future<void> _loadFeedbackStats() async {
    _feedbackStats = await _feedbackStorage.load();
    _engine.feedbackStats = _feedbackStats;
    notifyListeners();
  }

  void setSiteConfig(SiteConfig config) {
    siteConfig = config;
    _engine = AlertEngine(siteConfig: config)..feedbackStats = _feedbackStats;
    notifyListeners();
  }

  final List<DetectionAlert> alerts = [];

  // Only alerts that need operator attention (watch, alert, critical)
  List<DetectionAlert> get activeAlerts =>
      alerts.where((a) => !a.dismissed && a.requiresAttention).toList();

  // Only critical alerts
  List<DetectionAlert> get criticalAlerts =>
      alerts.where((a) => !a.dismissed && a.isCritical).toList();

  // Recurring-presence patterns awaiting operator verification
  List<DetectionAlert> get pendingPatterns => alerts
      .where((a) => !a.dismissed && a.engineResult.isPatternCandidate)
      .toList();

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

    // Real dispatch — interrupts whatever the drone is currently doing
    // and holds indefinitely, unlike onFocusRequested's re-tasking.
    if (lat != null && lng != null) {
      onPanicDispatchRequested?.call(lat, lng);
    }

    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Loitering trigger — from detector.py's tracker (persistent track ID +
  // dwell-time threshold), NOT the zone-based "RECURRING PRESENCE — VERIFY"
  // pattern in AlertEngine._evaluatePerson (that one counts any person in
  // a zone, no identity). This is a stronger, already-confirmed signal, so
  // it auto-dispatches the drone the same way the panic button does — no
  // operator verification gate.
  // -------------------------------------------------------------------------

  // Behavioural intelligence event from detector.py.
  // These events are intentionally review-first; only the established
  // loitering path is treated as a confirmed dispatch signal.
  void triggerBehaviour({
    required String id,
    required String behaviour,
    required int confidence,
    String? reason,
  }) {
    final result = _engine.evaluate(
      detectionClass: DetectionClass.unknown,
      latitude: _currentDronePosition()?.lat,
      longitude: _currentDronePosition()?.lng,
      scenario: ScenarioTrigger.behaviouralWatch,
    );

    final alert = DetectionAlert(
      id: id,
      label: behaviour.replaceAll('_', ' ').toUpperCase(),
      className: 'behaviour',
      confidence: confidence,
      timestamp: DateTime.now(),
      engineResult: result,
      latitude: _currentDronePosition()?.lat,
      longitude: _currentDronePosition()?.lng,
    );
    alerts.insert(0, alert);
    if (alerts.length > 100) alerts.removeLast();
    notifyListeners();
  }

  void triggerLoitering({
    required String id,
    required int confidence,
    double? lat,
    double? lng,
    int? trackId,
  }) {
    final result = _engine.evaluate(
      detectionClass: DetectionClass.person,
      latitude: lat,
      longitude: lng,
      scenario: ScenarioTrigger.loiteringConfirmed,
    );

    final alert = DetectionAlert(
      id: id,
      label: 'LOITERING',
      className: 'loitering',
      confidence: confidence,
      timestamp: DateTime.now(),
      engineResult: result,
      latitude: lat,
      longitude: lng,
    );
    alerts.insert(0, alert);
    if (alerts.length > 100) alerts.removeLast();

    // Auto-dispatch — lat/lng here are the drone's live position at the
    // moment this detection arrived (see getDronePosition above), not a
    // stale snapshot. If it's null (no GPS fix yet, or callback unwired),
    // the alert still logs, it just won't move the drone.
    if (lat != null && lng != null) {
      onFocusRequested?.call(
        lat,
        lng,
        trackId != null ? 'Loitering detected (track #$trackId)' : 'Loitering detected',
      );
      alert.droneDispatched = true;
    }

    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Connect to Python detection server
  // -------------------------------------------------------------------------

  void connect() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      isConnected = true;
      isDetecting = true;
      statusMessage = 'Detection active';
      notifyListeners();

      _subscription = _channel!.stream.listen(
        _onMessage,
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

  /// (0.0, 0.0) is DroneProvider's uninitialized default, not a real
  /// position anywhere near South Africa — treat it as "no fix yet"
  /// rather than a valid coordinate to dispatch the drone to.
  ({double lat, double lng})? _currentDronePosition() {
    final pos = getDronePosition?.call();
    if (pos == null) return null;
    if (pos.lat == 0.0 && pos.lng == 0.0) return null;
    return pos;
  }

  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;

      if (data['type'] == 'frame') {
        currentFrameBase64 = data['frame'] as String?;

        // Read live, once per batch of detections in this message —
        // not captured once back at connect() time.
        final pos = _currentDronePosition();

        final detections = data['detections'] as List<dynamic>? ?? [];
        for (final det in detections) {
          _handleDetection(det as Map<String, dynamic>, lat: pos?.lat, lng: pos?.lng);
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

    // Behavioural intelligence events are handled separately from ordinary
    // object detections so they don't fall through the normal class rules.
    if (className == 'behaviour') {
      triggerBehaviour(
        id: det['id'] as String? ?? 'behaviour_${DateTime.now().millisecondsSinceEpoch}',
        behaviour: det['behaviour'] as String? ?? 'unusual_activity',
        confidence: det['confidence'] as int? ?? 0,
        reason: det['reason'] as String?,
      );
      return;
    }

    // Loitering is a distinct, already-confirmed behavioral event —
    // route straight to auto-dispatch instead of the normal zone/time
    // rule path below, which has no concept of tracked individuals.
    if (className == 'loitering') {
      triggerLoitering(
        id: det['id'] as String? ?? 'loiter_${DateTime.now().millisecondsSinceEpoch}',
        confidence: det['confidence'] as int? ?? 0,
        lat: lat,
        lng: lng,
        trackId: det['track_id'] as int?,
      );
      return;
    }

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

    // Use the server-generated event id when present — this is the same
    // id the event log (SQLite, in detector.py) used when it logged the
    // detection, so confirm/dismiss can be written back to the right row.
    final eventId = det['id'] as String? ?? '${className}_${now.millisecondsSinceEpoch}';

    final alert = DetectionAlert(
      id: eventId,
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
      // VisDrone classes
      case 'pedestrian':
      case 'people': return DetectionClass.person;
      case 'car':
      case 'van':
      case 'truck':
      case 'bus':
      case 'motor':
      case 'bicycle':
      case 'tricycle':
      case 'awning-tricycle': return DetectionClass.vehicle;
      case 'fire': return DetectionClass.fire;
      case 'smoke': return DetectionClass.smoke;
      default: return DetectionClass.unknown;
    }
  }

  // -------------------------------------------------------------------------
  // Alert actions
  // -------------------------------------------------------------------------

  /// Operator confirms this was a real detection worth acting on.
  /// This is the positive training signal for a normal (non-pattern) alert
  /// — feeds directly into FeedbackStats, which AlertEngine reads to
  /// adjust future alerts for this same zone+class.
  void confirmAlert(String id) {
    try {
      final alert = alerts.firstWhere((a) => a.id == id);
      alert.confirmed = true;
      alert.dismissed = true;
      _sendOperatorResponse(id, 'confirmed');
      _recordFeedback(alert, confirmed: true);
      notifyListeners();
    } catch (_) {}
  }

  /// Operator dismisses this as a false alarm. This is the negative
  /// training signal — every dismiss is a labelled example too, not
  /// just a UI action. This is what actually drives the alert
  /// downgrading over time.
  void dismissAlert(String id) {
    try {
      final alert = alerts.firstWhere((a) => a.id == id);
      alert.dismissed = true;
      _sendOperatorResponse(id, 'dismissed');
      _recordFeedback(alert, confirmed: false);
      notifyListeners();
    } catch (_) {}
  }

  void _recordFeedback(DetectionAlert alert, {required bool confirmed}) {
    final key = alert.engineResult.feedbackKey;
    if (key == null) return; // scenario/critical/animal alerts aren't tracked
    if (confirmed) {
      _feedbackStats.recordConfirm(key);
    } else {
      _feedbackStats.recordDismiss(key);
    }
    // Fire-and-forget — don't block the UI on disk I/O
    _feedbackStorage.save(_feedbackStats);
  }

  /// For pattern-candidate alerts (recurring presence / unusual vehicle
  /// frequency): operator has looked at the feed and judges this a real
  /// threat. Logs it as confirmed AND, if onFocusRequested is wired,
  /// re-tasks the drone toward the zone this pattern was seen in.
  void verifyThreat(String id) {
    try {
      final alert = alerts.firstWhere((a) => a.id == id);
      alert.confirmed = true;
      alert.dismissed = true;
      _sendOperatorResponse(id, 'confirmed');
      _recordFeedback(alert, confirmed: true);

      final result = alert.engineResult;
      if (result.isPatternCandidate &&
          result.focusLat != null &&
          result.focusLng != null) {
        onFocusRequested?.call(result.focusLat!, result.focusLng!, result.title);
      }

      notifyListeners();
    } catch (_) {}
  }

  /// For pattern-candidate alerts: operator has looked at the feed and
  /// judges this is NOT a concern (just normal frequent traffic, e.g.
  /// a busy zone or shift change). Logged as a dismissed/false-positive
  /// pattern, same as a normal dismiss.
  void notAConcern(String id) => dismissAlert(id);

  void _sendOperatorResponse(String id, String response) {
    // Best-effort — if the socket's already closed this just no-ops.
    // The event still exists in the log with operator_action = NULL,
    // which is itself useful signal (nobody reviewed it).
    try {
      _channel?.sink.add(jsonEncode({
        'action': 'operator_response',
        'id': id,
        'response': response,
      }));
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
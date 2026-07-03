import 'site_config.dart';
import 'alert_engine.dart';

/// A single detection event with full context
class DetectionAlert {
  final String id;
  final String label;
  final String className;
  final int confidence;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final AlertEngineResult engineResult;
  bool dismissed;
  bool reportedToAuthorities;
  bool droneDispatched;

  DetectionAlert({
    required this.id,
    required this.label,
    required this.className,
    required this.confidence,
    required this.timestamp,
    required this.engineResult,
    this.latitude,
    this.longitude,
    this.dismissed = false,
    this.reportedToAuthorities = false,
    this.droneDispatched = false,
  });

  AlertLevel get level => engineResult.level;
  bool get isLog => level == AlertLevel.log;
  bool get isWatch => level == AlertLevel.watch;
  bool get isAlert => level == AlertLevel.alert;
  bool get isCritical => level == AlertLevel.critical;
  bool get requiresAttention => level == AlertLevel.alert || level == AlertLevel.critical;

  String get levelLabel {
    switch (level) {
      case AlertLevel.log: return 'LOG';
      case AlertLevel.watch: return 'WATCH';
      case AlertLevel.alert: return 'ALERT';
      case AlertLevel.critical: return 'CRITICAL';
    }
  }

  String get timeString {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

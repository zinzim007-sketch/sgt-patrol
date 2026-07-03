import 'site_config.dart';

/// Detection classes from YOLOv8
enum DetectionClass {
  person,
  vehicle,
  animal,
  fire,
  smoke,
  unknown,
}

/// Scenario triggers — override zone/time rules
enum ScenarioTrigger {
  none,
  panicButton,     // Physical or in-app panic button pressed
  fireDetected,    // Fire or smoke detected
  operatorFlagged, // Operator manually escalated
}

/// Result from the alert engine
class AlertEngineResult {
  final AlertLevel level;
  final String title;
  final String description;
  final String actionLabel;   // What the operator should do
  final bool requiresImmediateAction;
  final bool showCallAuthorities;
  final bool showDispatchDrone;
  final Color levelColor;

  const AlertEngineResult({
    required this.level,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.requiresImmediateAction,
    required this.showCallAuthorities,
    required this.showDispatchDrone,
    required this.levelColor,
  });
}

// Using int instead of Flutter Color to keep this model pure Dart
// UI layer converts these to Flutter Colors
class Color {
  final int value;
  const Color(this.value);
}

/// AlertEngine — the brain of SGT Patrol's detection system.
///
/// Takes a detection event + site context and returns the appropriate
/// alert level and operator actions.
class AlertEngine {

  final SiteConfig siteConfig;

  AlertEngine({required this.siteConfig});

  // -------------------------------------------------------------------------
  // Main evaluation method
  // -------------------------------------------------------------------------

  AlertEngineResult evaluate({
    required DetectionClass detectionClass,
    required double? latitude,
    required double? longitude,
    ScenarioTrigger scenario = ScenarioTrigger.none,
    int? personCount, // How many people detected simultaneously
  }) {

    // Step 1 — Scenario triggers bypass all zone/time logic
    if (scenario != ScenarioTrigger.none) {
      return _handleScenario(scenario, detectionClass);
    }

    // Step 2 — Fire and smoke are always critical regardless of zone/time
    if (detectionClass == DetectionClass.fire ||
        detectionClass == DetectionClass.smoke) {
      return _critical(
        title: '🔥 FIRE DETECTED',
        description: 'Fire or smoke detected in patrol area. '
            'Emergency services required immediately.',
        showCallAuthorities: true,
      );
    }

    // Step 3 — Determine zone
    final zone = _getZone(latitude, longitude);
    final withinHours = siteConfig.hours.isWithinHours;

    // Step 4 — Apply rules based on detection class + zone + time + site type
    return _applyRules(
      detectionClass: detectionClass,
      zone: zone,
      withinHours: withinHours,
      personCount: personCount ?? 1,
    );
  }

  // -------------------------------------------------------------------------
  // Scenario handlers
  // -------------------------------------------------------------------------

  AlertEngineResult _handleScenario(
      ScenarioTrigger scenario, DetectionClass detectionClass) {
    switch (scenario) {
      case ScenarioTrigger.panicButton:
        return _critical(
          title: '🚨 PANIC BUTTON ACTIVATED',
          description: 'Someone has triggered the panic button. '
              'Drone dispatching to location immediately. '
              'Assess situation on live feed.',
          showCallAuthorities: true,
          showDispatchDrone: true,
        );

      case ScenarioTrigger.fireDetected:
        return _critical(
          title: '🔥 FIRE / SMOKE DETECTED',
          description: 'Fire or smoke detected. '
              'Emergency services required immediately.',
          showCallAuthorities: true,
        );

      case ScenarioTrigger.operatorFlagged:
        return AlertEngineResult(
          level: AlertLevel.critical,
          title: '⚠️ OPERATOR ESCALATED',
          description: 'Operator has flagged this as a critical situation. '
              'Awaiting your action.',
          actionLabel: 'Call authorities or stand down',
          requiresImmediateAction: true,
          showCallAuthorities: true,
          showDispatchDrone: true,
          levelColor: const Color(0xFFe74c3c),
        );

      default:
        return _log(title: 'Event', description: 'Unknown scenario');
    }
  }

  // -------------------------------------------------------------------------
  // Rule engine — zone + time + site type + detection class
  // -------------------------------------------------------------------------

  AlertEngineResult _applyRules({
    required DetectionClass detectionClass,
    required ZoneSensitivity? zone,
    required bool withinHours,
    required int personCount,
  }) {
    switch (detectionClass) {

      case DetectionClass.person:
        return _evaluatePerson(zone, withinHours, personCount);

      case DetectionClass.vehicle:
        return _evaluateVehicle(zone, withinHours);

      case DetectionClass.animal:
        // Animals are always logged only — no operator action needed
        return _log(
          title: 'Animal detected',
          description: 'Animal detected in patrol area — logged for review.',
        );

      default:
        return _log(title: 'Detection', description: 'Unknown object detected');
    }
  }

  AlertEngineResult _evaluatePerson(
      ZoneSensitivity? zone, bool withinHours, int personCount) {

    // Multiple people detected — always escalate one level
    final groupDetected = personCount >= 3;

    // Red zone — always critical regardless of time
    if (zone == ZoneSensitivity.red) {
      return _critical(
        title: '🚨 INTRUDER IN RESTRICTED ZONE',
        description: _personDesc(zone, withinHours, personCount) +
            ' This zone requires immediate response.',
        showCallAuthorities: true,
        showDispatchDrone: true,
      );
    }

    // After hours — escalate
    if (!withinHours) {
      if (zone == ZoneSensitivity.amber || groupDetected) {
        return _alert(
          title: 'Person detected after hours',
          description: _personDesc(zone, withinHours, personCount),
          showCallAuthorities: true,
        );
      }
      // Even green zone after hours is a watch
      return _watch(
        title: 'Person detected after hours',
        description: _personDesc(zone, withinHours, personCount),
      );
    }

    // Within hours
    if (zone == ZoneSensitivity.amber) {
      if (groupDetected) {
        return _alert(
          title: 'Group detected in patrol boundary',
          description: _personDesc(zone, withinHours, personCount),
          showCallAuthorities: false,
        );
      }
      return _watch(
        title: 'Person in patrol boundary',
        description: _personDesc(zone, withinHours, personCount),
      );
    }

    // Green zone during hours — log only
    return _log(
      title: 'Person detected',
      description: _personDesc(zone, withinHours, personCount),
    );
  }

  AlertEngineResult _evaluateVehicle(ZoneSensitivity? zone, bool withinHours) {

    if (zone == ZoneSensitivity.red) {
      return _alert(
        title: 'Vehicle in restricted zone',
        description: 'Vehicle detected in ${_zoneName(zone)} — '
            '${withinHours ? "during operating hours" : "outside operating hours"}. '
            'Verify if authorised.',
        showCallAuthorities: false,
      );
    }

    if (!withinHours && zone == ZoneSensitivity.amber) {
      return _alert(
        title: 'Vehicle detected after hours',
        description: 'Vehicle detected in patrol boundary outside operating hours. '
            'Verify if authorised.',
        showCallAuthorities: false,
      );
    }

    if (!withinHours) {
      return _watch(
        title: 'Vehicle detected after hours',
        description: 'Vehicle detected outside operating hours. Monitor situation.',
      );
    }

    // During hours in non-restricted zone — log only
    return _log(
      title: 'Vehicle detected',
      description: 'Vehicle detected in ${_zoneName(zone)} during operating hours.',
    );
  }

  // -------------------------------------------------------------------------
  // Helper builders
  // -------------------------------------------------------------------------

  String _personDesc(ZoneSensitivity? zone, bool withinHours, int count) {
    final countStr = count > 1 ? '$count people' : 'Person';
    final timeStr = withinHours ? 'during operating hours' : 'outside operating hours';
    final zoneStr = zone != null ? 'in ${_zoneName(zone)}' : 'in patrol area';
    final siteStr = _siteContext();
    return '$countStr detected $zoneStr $timeStr. $siteStr';
  }

  String _siteContext() {
    switch (siteConfig.siteType) {
      case SiteType.farm:
        return 'Could be a worker, visitor, or intruder — verify on feed.';
      case SiteType.campus:
        return 'Could be a student, staff, or intruder — verify on feed.';
      case SiteType.estate:
        return 'Could be a resident, visitor, or intruder — verify on feed.';
      case SiteType.commercial:
        return 'Verify if authorised personnel on feed.';
    }
  }

  String _zoneName(ZoneSensitivity? zone) {
    if (zone == null) return 'unknown area';
    // Find the zone name from config
    try {
      final z = siteConfig.zones.firstWhere((z) => z.sensitivity == zone);
      return z.name;
    } catch (_) {
      switch (zone) {
        case ZoneSensitivity.green: return 'low sensitivity area';
        case ZoneSensitivity.amber: return 'patrol boundary';
        case ZoneSensitivity.red: return 'restricted zone';
      }
    }
  }

  /// Point-in-polygon check — is the detection inside a zone?
  ZoneSensitivity? _getZone(double? lat, double? lng) {
    if (lat == null || lng == null) return null;

    // Check red zones first (highest priority)
    for (final zone in siteConfig.zones) {
      if (zone.sensitivity == ZoneSensitivity.red &&
          _pointInPolygon(lat, lng, zone.boundary)) {
        return ZoneSensitivity.red;
      }
    }
    // Then amber
    for (final zone in siteConfig.zones) {
      if (zone.sensitivity == ZoneSensitivity.amber &&
          _pointInPolygon(lat, lng, zone.boundary)) {
        return ZoneSensitivity.amber;
      }
    }
    // Then green
    for (final zone in siteConfig.zones) {
      if (zone.sensitivity == ZoneSensitivity.green &&
          _pointInPolygon(lat, lng, zone.boundary)) {
        return ZoneSensitivity.green;
      }
    }
    return null; // Outside all zones
  }

  /// Ray casting algorithm for point-in-polygon
  bool _pointInPolygon(double lat, double lng, List<ZonePoint> polygon) {
    bool inside = false;
    int j = polygon.length - 1;
    for (int i = 0; i < polygon.length; i++) {
      if ((polygon[i].longitude > lng) != (polygon[j].longitude > lng) &&
          lat < (polygon[j].latitude - polygon[i].latitude) *
              (lng - polygon[i].longitude) /
              (polygon[j].longitude - polygon[i].longitude) +
              polygon[i].latitude) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  // -------------------------------------------------------------------------
  // Result constructors
  // -------------------------------------------------------------------------

  AlertEngineResult _log({required String title, required String description}) =>
    AlertEngineResult(
      level: AlertLevel.log,
      title: title,
      description: description,
      actionLabel: 'Logged automatically',
      requiresImmediateAction: false,
      showCallAuthorities: false,
      showDispatchDrone: false,
      levelColor: const Color(0xFF4a6a8a),
    );

  AlertEngineResult _watch({required String title, required String description}) =>
    AlertEngineResult(
      level: AlertLevel.watch,
      title: title,
      description: description,
      actionLabel: 'Monitor situation on live feed',
      requiresImmediateAction: false,
      showCallAuthorities: false,
      showDispatchDrone: false,
      levelColor: const Color(0xFF2979cc),
    );

  AlertEngineResult _alert({
    required String title,
    required String description,
    required bool showCallAuthorities,
  }) =>
    AlertEngineResult(
      level: AlertLevel.alert,
      title: title,
      description: description,
      actionLabel: 'Review feed and decide action',
      requiresImmediateAction: false,
      showCallAuthorities: showCallAuthorities,
      showDispatchDrone: true,
      levelColor: const Color(0xFFf39c12),
    );

  AlertEngineResult _critical({
    required String title,
    required String description,
    bool showCallAuthorities = true,
    bool showDispatchDrone = false,
  }) =>
    AlertEngineResult(
      level: AlertLevel.critical,
      title: title,
      description: description,
      actionLabel: 'Immediate action required',
      requiresImmediateAction: true,
      showCallAuthorities: showCallAuthorities,
      showDispatchDrone: showDispatchDrone,
      levelColor: const Color(0xFFe74c3c),
    );
}

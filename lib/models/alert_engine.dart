import 'site_config.dart';

/// Detection classes from the detector
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

  /// True when this result represents a recurring-presence pattern
  /// (loitering / repeat visit) rather than a single detection. The UI
  /// should render these as a distinct "verify this pattern" card with
  /// VERIFY AS THREAT / NOT A CONCERN actions instead of plain
  /// CONFIRM / DISMISS.
  final bool isPatternCandidate;

  /// Centroid of the zone this pattern was seen in — set only when
  /// isPatternCandidate is true. Lets the operator app re-task the
  /// drone to that location if they verify it as a real threat.
  final double? focusLat;
  final double? focusLng;

  const AlertEngineResult({
    required this.level,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.requiresImmediateAction,
    required this.showCallAuthorities,
    required this.showDispatchDrone,
    required this.levelColor,
    this.isPatternCandidate = false,
    this.focusLat,
    this.focusLng,
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
///
/// Beyond static zone/time rules, this also tracks lightweight temporal
/// patterns — no ML involved, just a sliding-window count of recent
/// sightings per zone+class. This is intentionally simple: it's the
/// "rule-based temporal query" step, the first achievable version of
/// behavioural intelligence, before enough logged operator feedback
/// exists to learn these patterns instead of hand-coding them.
class AlertEngine {

  final SiteConfig siteConfig;

  AlertEngine({required this.siteConfig});

  // -------------------------------------------------------------------------
  // Temporal pattern tracking
  // -------------------------------------------------------------------------
  //
  // NOTE: this history is in-memory and per-app-session only — it resets
  // on restart and isn't shared across devices. Fine for a demo; once the
  // SQLite event log is the source of truth, these counts should be
  // computed from that log instead, so patterns survive restarts and can
  // eventually work cross-site.
  //
  // IMPORTANT HONESTY NOTE: these counters are keyed by zone + class, not
  // by individual identity. "3rd sighting in this zone" does not mean
  // "the same person" — there's no re-identification here. Frame this as
  // "unusual activity frequency in this location," not "we recognized
  // this specific person/vehicle again."

  final Map<String, List<DateTime>> _sightingHistory = {};

  static const _loiterWindow = Duration(minutes: 5);
  static const _loiterThreshold = 3; // sightings in same zone within window

  static const _repeatVisitWindow = Duration(hours: 1);
  static const _repeatVisitThreshold = 2; // vehicle sightings in same zone within window

  // Once a pattern candidate has been surfaced for a given zone+class,
  // suppress surfacing it again for this long — otherwise it fires on
  // every single qualifying detection while the person/vehicle is still
  // there (e.g. every ~5 seconds), flooding the operator with duplicates
  // of the same not-yet-reviewed pattern. The underlying sighting count
  // still keeps accumulating during the cooldown; only the "surface a
  // NEW pattern-candidate card" step is suppressed.
  final Map<String, DateTime> _patternSurfacedAt = {};
  static const _patternCooldown = Duration(minutes: 2);

  bool _shouldSurfacePattern(String key) {
    final last = _patternSurfacedAt[key];
    final now = DateTime.now();
    if (last != null && now.difference(last) < _patternCooldown) return false;
    _patternSurfacedAt[key] = now;
    return true;
  }

  /// Records a sighting for this class+zone and returns how many
  /// sightings have occurred within `window`, including this one.
  int _recordSighting(
    DetectionClass detectionClass,
    PatrolZone? zoneObj, {
    required Duration window,
  }) {
    final key = '${zoneObj?.id ?? "none"}|${detectionClass.name}';
    final now = DateTime.now();
    final history = _sightingHistory.putIfAbsent(key, () => []);
    history.add(now);
    history.removeWhere((t) => now.difference(t) > window);
    return history.length;
  }

  /// Centroid of a zone's boundary — used as the "focus here" point if
  /// the operator verifies a recurring-presence pattern as a real threat.
  ({double lat, double lng})? _zoneCentroid(PatrolZone? zoneObj) {
    if (zoneObj == null || zoneObj.boundary.isEmpty) return null;
    final lat = zoneObj.boundary.map((p) => p.latitude).reduce((a, b) => a + b) /
        zoneObj.boundary.length;
    final lng = zoneObj.boundary.map((p) => p.longitude).reduce((a, b) => a + b) /
        zoneObj.boundary.length;
    return (lat: lat, lng: lng);
  }

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

    // Step 3 — Determine zone (as an object, so we can read its
    // hoursOverride and compute a centroid, not just its sensitivity tier)
    final zoneObj = _getZoneObj(latitude, longitude);
    final withinHours = (zoneObj?.hoursOverride ?? siteConfig.hours).isWithinHours;

    // Step 4 — Apply rules based on detection class + zone + time + site type
    return _applyRules(
      detectionClass: detectionClass,
      zoneObj: zoneObj,
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
    required PatrolZone? zoneObj,
    required bool withinHours,
    required int personCount,
  }) {
    switch (detectionClass) {

      case DetectionClass.person:
        return _evaluatePerson(zoneObj, withinHours, personCount);

      case DetectionClass.vehicle:
        return _evaluateVehicle(zoneObj, withinHours);

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
      PatrolZone? zoneObj, bool withinHours, int personCount) {

    final zone = zoneObj?.sensitivity;

    // Record this sighting and check for a loitering pattern — same
    // zone, repeatedly, in a short window.
    final sightingCount =
        _recordSighting(DetectionClass.person, zoneObj, window: _loiterWindow);
    final isLoitering = sightingCount >= _loiterThreshold;

    // Multiple people detected — always escalate one level
    final groupDetected = personCount >= 3;

    // Red zone — always critical regardless of time or pattern
    if (zone == ZoneSensitivity.red) {
      return _critical(
        title: '🚨 INTRUDER IN RESTRICTED ZONE',
        description: _personDesc(zone, withinHours, personCount) +
            ' This zone requires immediate response.',
        showCallAuthorities: true,
        showDispatchDrone: true,
      );
    }

    // Loitering pattern — surfaced as a pattern candidate for operator
    // verification, not an automatic accusation. This is the "recurring
    // presence — verify" flow: AI surfaces it, human judges it, and if
    // confirmed, the app can re-task the drone toward this zone.
    if (isLoitering && _shouldSurfacePattern('loiter|${zoneObj?.id ?? "none"}')) {
      final centroid = _zoneCentroid(zoneObj);
      return AlertEngineResult(
        level: AlertLevel.alert,
        title: '⏱ RECURRING PRESENCE — VERIFY',
        description:
            '${_personDesc(zone, withinHours, personCount)} '
            'This is the ${sightingCount}th person sighting in '
            '${zoneObj != null ? "\"${zoneObj.name}\"" : "this area"} within '
            '${_loiterWindow.inMinutes} minutes. Not identity-matched — this '
            'counts any person detected here, not necessarily the same '
            'individual. Verify on feed before treating as a threat.',
        actionLabel: 'Review feed and verify',
        requiresImmediateAction: false,
        showCallAuthorities: false,
        showDispatchDrone: true,
        levelColor: const Color(0xFFf39c12),
        isPatternCandidate: true,
        focusLat: centroid?.lat,
        focusLng: centroid?.lng,
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

  AlertEngineResult _evaluateVehicle(PatrolZone? zoneObj, bool withinHours) {

    final zone = zoneObj?.sensitivity;

    // Record this sighting and check for a repeat-visit pattern — same
    // vehicle-class+zone appearing multiple times in the last hour.
    // Class-level, not per-plate — good enough for a rule-based first
    // pass; per-vehicle identity (plate OCR or visual re-ID) is a
    // separate, real ML component, not built yet.
    final visitCount =
        _recordSighting(DetectionClass.vehicle, zoneObj, window: _repeatVisitWindow);
    final isRepeatVisitor = visitCount >= _repeatVisitThreshold;

    if (zone == ZoneSensitivity.red) {
      return _alert(
        title: 'Vehicle in restricted zone',
        description: 'Vehicle detected in ${_zoneName(zoneObj)} — '
            '${withinHours ? "during operating hours" : "outside operating hours"}. '
            'Verify if authorised.',
        showCallAuthorities: false,
      );
    }

    if (isRepeatVisitor && _shouldSurfacePattern('vehicle|${zoneObj?.id ?? "none"}')) {
      final centroid = _zoneCentroid(zoneObj);
      return AlertEngineResult(
        level: AlertLevel.alert,
        title: '🔁 UNUSUAL VEHICLE FREQUENCY — VERIFY',
        description:
            'Vehicle-class activity detected in ${_zoneName(zoneObj)} for the '
            '$visitCount time in the last ${_repeatVisitWindow.inHours} hour(s). '
            'Not plate-matched — this counts any vehicle detected here, not '
            'necessarily the same one. Elevated frequency in a normally '
            'quiet zone is still worth a look — verify on feed.',
        actionLabel: 'Review feed and verify',
        requiresImmediateAction: false,
        showCallAuthorities: false,
        showDispatchDrone: true,
        levelColor: const Color(0xFFf39c12),
        isPatternCandidate: true,
        focusLat: centroid?.lat,
        focusLng: centroid?.lng,
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
      description: 'Vehicle detected in ${_zoneName(zoneObj)} during operating hours.',
    );
  }

  // -------------------------------------------------------------------------
  // Helper builders
  // -------------------------------------------------------------------------

  String _personDesc(ZoneSensitivity? zone, bool withinHours, int count) {
    final countStr = count > 1 ? '$count people' : 'Person';
    final timeStr = withinHours ? 'during operating hours' : 'outside operating hours';
    final zoneStr = zone != null ? 'in ${_zoneNameFromSensitivity(zone)}' : 'in patrol area';
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

  String _zoneName(PatrolZone? zoneObj) {
    if (zoneObj == null) return 'unknown area';
    return zoneObj.name;
  }

  String _zoneNameFromSensitivity(ZoneSensitivity zone) {
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

  /// Point-in-polygon check — is the detection inside a zone? Returns
  /// the zone object itself (not just its sensitivity) so callers can
  /// read hoursOverride, name, and boundary for a centroid.
  PatrolZone? _getZoneObj(double? lat, double? lng) {
    if (lat == null || lng == null) return null;

    for (final zone in siteConfig.zones) {
      if (zone.sensitivity == ZoneSensitivity.red &&
          _pointInPolygon(lat, lng, zone.boundary)) {
        return zone;
      }
    }
    for (final zone in siteConfig.zones) {
      if (zone.sensitivity == ZoneSensitivity.amber &&
          _pointInPolygon(lat, lng, zone.boundary)) {
        return zone;
      }
    }
    for (final zone in siteConfig.zones) {
      if (zone.sensitivity == ZoneSensitivity.green &&
          _pointInPolygon(lat, lng, zone.boundary)) {
        return zone;
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
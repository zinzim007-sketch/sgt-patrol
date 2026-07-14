/// Site types SGT Patrol is deployed on
enum SiteType { farm, campus, estate, commercial }

/// Alert levels
enum AlertLevel {
  log,      // Level 1 — record only, no notification
  watch,    // Level 2 — soft notification, operator monitors
  alert,    // Level 3 — operator reviews, decides action
  critical, // Level 4 — immediate response, no review needed
}

/// A zone on the site map
class PatrolZone {
  final String id;
  final String name;
  final ZoneSensitivity sensitivity;
  final List<ZonePoint> boundary;

  /// Optional per-zone hours override. Use this when a specific street/zone
  /// has a genuinely different rhythm than the site default — e.g. a
  /// nightlife strip that's normally busy until 1am shouldn't trigger
  /// "after hours" alerts at 9pm just because the site default closes then.
  /// Falls back to SiteConfig.hours when null.
  final SiteHours? hoursOverride;

  const PatrolZone({
    required this.id,
    required this.name,
    required this.sensitivity,
    required this.boundary,
    this.hoursOverride,
  });
}

enum ZoneSensitivity { green, amber, red }

class ZonePoint {
  final double latitude;
  final double longitude;
  const ZonePoint(this.latitude, this.longitude);
}

/// Client operating hours
class SiteHours {
  final String start; // "06:00"
  final String end;   // "18:00" — if end < start, treated as spanning midnight
  final List<int> days; // 1=Mon, 7=Sun

  const SiteHours({
    required this.start,
    required this.end,
    required this.days,
  });

  /// Is it currently within operating hours?
  bool get isWithinHours {
    final now = DateTime.now();
    if (!days.contains(now.weekday)) return false;

    final startParts = start.split(':');
    final endParts = end.split(':');

    final startMinutes = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
    final nowMinutes = now.hour * 60 + now.minute;

    if (endMinutes < startMinutes) {
      // Window spans midnight, e.g. 06:00 -> 01:00
      return nowMinutes >= startMinutes || nowMinutes <= endMinutes;
    }
    return nowMinutes >= startMinutes && nowMinutes <= endMinutes;
  }
}

/// Full site configuration for a client deployment
class SiteConfig {
  final String clientName;
  final SiteType siteType;
  final SiteHours hours;
  final List<PatrolZone> zones;

  const SiteConfig({
    required this.clientName,
    required this.siteType,
    required this.hours,
    required this.zones,
  });

  /// Default demo config — farm site
  static SiteConfig get demo => SiteConfig(
    clientName: 'Demo Farm — Cape Town',
    siteType: SiteType.farm,
    hours: const SiteHours(
      start: '06:00',
      end: '18:00',
      days: [1, 2, 3, 4, 5, 6], // Mon-Sat
    ),
    zones: [
      PatrolZone(
        id: 'green_1',
        name: 'Farmhouse & workers area',
        sensitivity: ZoneSensitivity.green,
        boundary: const [
          ZonePoint(-33.9175, 18.4225),
          ZonePoint(-33.9175, 18.4235),
          ZonePoint(-33.9185, 18.4235),
          ZonePoint(-33.9185, 18.4225),
        ],
      ),
      PatrolZone(
        id: 'amber_1',
        name: 'Farm perimeter',
        sensitivity: ZoneSensitivity.amber,
        boundary: const [
          ZonePoint(-33.918, 18.423),
          ZonePoint(-33.919, 18.424),
          ZonePoint(-33.920, 18.423),
          ZonePoint(-33.919, 18.422),
        ],
      ),
      PatrolZone(
        id: 'red_1',
        name: 'Equipment & fuel storage',
        sensitivity: ZoneSensitivity.red,
        boundary: const [
          ZonePoint(-33.9195, 18.4228),
          ZonePoint(-33.9195, 18.4232),
          ZonePoint(-33.9198, 18.4232),
          ZonePoint(-33.9198, 18.4228),
        ],
      ),
    ],
  );

  /// Campus demo config
  static SiteConfig get demoCampus => SiteConfig(
    clientName: 'Demo Campus',
    siteType: SiteType.campus,
    hours: const SiteHours(
      start: '07:00',
      end: '22:00',
      days: [1, 2, 3, 4, 5], // Mon-Fri
    ),
    zones: [
      PatrolZone(
        id: 'green_1',
        name: 'Public areas & parking',
        sensitivity: ZoneSensitivity.green,
        boundary: const [
          ZonePoint(-33.918, 18.422),
          ZonePoint(-33.918, 18.424),
          ZonePoint(-33.919, 18.424),
          ZonePoint(-33.919, 18.422),
        ],
      ),
      PatrolZone(
        id: 'amber_1',
        name: 'Campus buildings after hours',
        sensitivity: ZoneSensitivity.amber,
        boundary: const [
          ZonePoint(-33.919, 18.422),
          ZonePoint(-33.919, 18.424),
          ZonePoint(-33.920, 18.424),
          ZonePoint(-33.920, 18.422),
        ],
      ),
      PatrolZone(
        id: 'red_1',
        name: 'Server room & admin block',
        sensitivity: ZoneSensitivity.red,
        boundary: const [
          ZonePoint(-33.9195, 18.4228),
          ZonePoint(-33.9195, 18.4232),
          ZonePoint(-33.9200, 18.4232),
          ZonePoint(-33.9200, 18.4228),
        ],
      ),
    ],
  );

  /// Estate demo config
  static SiteConfig get demoEstate => SiteConfig(
    clientName: 'Demo Estate',
    siteType: SiteType.estate,
    hours: const SiteHours(
      start: '06:00',
      end: '22:00',
      days: [1, 2, 3, 4, 5, 6, 7], // Every day
    ),
    zones: [
      PatrolZone(
        id: 'green_1',
        name: 'Communal areas & driveways',
        sensitivity: ZoneSensitivity.green,
        boundary: const [
          ZonePoint(-33.918, 18.422),
          ZonePoint(-33.918, 18.424),
          ZonePoint(-33.919, 18.424),
          ZonePoint(-33.919, 18.422),
        ],
      ),
      PatrolZone(
        id: 'amber_1',
        name: 'Perimeter & gates',
        sensitivity: ZoneSensitivity.amber,
        boundary: const [
          ZonePoint(-33.919, 18.422),
          ZonePoint(-33.919, 18.424),
          ZonePoint(-33.920, 18.424),
          ZonePoint(-33.920, 18.422),
        ],
      ),
      PatrolZone(
        id: 'red_1',
        name: 'Individual properties',
        sensitivity: ZoneSensitivity.red,
        boundary: const [
          ZonePoint(-33.9195, 18.4228),
          ZonePoint(-33.9195, 18.4232),
          ZonePoint(-33.9200, 18.4232),
          ZonePoint(-33.9200, 18.4228),
        ],
      ),
    ],
  );

  /// Stellenbosch deployment config — first live site.
  ///
  /// Coordinates are centred on real Stellenbosch town (approx.
  /// -33.9346, 18.8602) — replace boundary points with your actual
  /// surveyed zone polygons before going live; these are placeholder
  /// rectangles sized for a demo, not surveyed property lines.
  ///
  /// Per-zone hoursOverride models "different streets are noisier at
  /// certain hours": the Dorp/Church Street strip runs later before
  /// anything there counts as "after hours," while the residential
  /// zone closes earlier since foot traffic there genuinely drops off
  /// sooner.
  static SiteConfig get stellenbosch => SiteConfig(
    clientName: 'Stellenbosch — Pilot Deployment',
    siteType: SiteType.commercial,
    hours: const SiteHours(
      start: '06:00',
      end: '20:00',
      days: [1, 2, 3, 4, 5, 6, 7],
    ),
    zones: [
      PatrolZone(
        id: 'green_1',
        name: 'Die Boord residential streets',
        sensitivity: ZoneSensitivity.green,
        hoursOverride: const SiteHours(
          start: '06:00',
          end: '19:00', // quiet suburb — flags earlier in the evening
          days: [1, 2, 3, 4, 5, 6, 7],
        ),
        boundary: const [
          ZonePoint(-33.9420, 18.8600),
          ZonePoint(-33.9420, 18.8650),
          ZonePoint(-33.9460, 18.8650),
          ZonePoint(-33.9460, 18.8600),
        ],
      ),
      PatrolZone(
        id: 'amber_1',
        name: 'Dorp Street & Church Street strip',
        sensitivity: ZoneSensitivity.amber,
        hoursOverride: const SiteHours(
          start: '06:00',
          end: '01:00', // nightlife strip — normal foot traffic until late
          days: [1, 2, 3, 4, 5, 6, 7],
        ),
        boundary: const [
          ZonePoint(-33.9340, 18.8595),
          ZonePoint(-33.9340, 18.8630),
          ZonePoint(-33.9355, 18.8630),
          ZonePoint(-33.9355, 18.8595),
        ],
      ),
      PatrolZone(
        id: 'amber_2',
        name: 'Student housing corridor — Bird Street',
        sensitivity: ZoneSensitivity.amber,
        hoursOverride: const SiteHours(
          start: '06:00',
          end: '23:00',
          days: [1, 2, 3, 4, 5, 6, 7],
        ),
        boundary: const [
          ZonePoint(-33.9370, 18.8660),
          ZonePoint(-33.9370, 18.8690),
          ZonePoint(-33.9385, 18.8690),
          ZonePoint(-33.9385, 18.8660),
        ],
      ),
      PatrolZone(
        id: 'red_1',
        name: 'Restricted — cash-in-transit / high-value entrances',
        sensitivity: ZoneSensitivity.red,
        boundary: const [
          ZonePoint(-33.9345, 18.8608),
          ZonePoint(-33.9345, 18.8612),
          ZonePoint(-33.9349, 18.8612),
          ZonePoint(-33.9349, 18.8608),
        ],
      ),
    ],
  );
}

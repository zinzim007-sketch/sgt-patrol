class PatrolWaypoint {
  final double latitude;
  final double longitude;
  final double altitude;
  final double gimbalPitch;
  final bool takePhoto;
  final int hoverSeconds;

  const PatrolWaypoint({
    required this.latitude,
    required this.longitude,
    this.altitude = 20.0,
    this.gimbalPitch = -45.0,
    this.takePhoto = false,
    this.hoverSeconds = 0,
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'gimbalPitch': gimbalPitch,
        'takePhoto': takePhoto,
        'hoverSeconds': hoverSeconds,
      };

  factory PatrolWaypoint.fromJson(Map<String, dynamic> json) => PatrolWaypoint(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        altitude: (json['altitude'] as num?)?.toDouble() ?? 20.0,
        gimbalPitch: (json['gimbalPitch'] as num?)?.toDouble() ?? -45.0,
        takePhoto: json['takePhoto'] as bool? ?? false,
        hoverSeconds: json['hoverSeconds'] as int? ?? 0,
      );
}

class PatrolRoute {
  final String id;
  final String name;
  final List<PatrolWaypoint> waypoints;
  final double flightSpeedMs;
  final DateTime createdAt;

  PatrolRoute({
    String? id,
    required this.name,
    required this.waypoints,
    this.flightSpeedMs = 5.0,
    DateTime? createdAt,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'waypoints': waypoints.map((w) => w.toJson()).toList(),
        'flightSpeedMs': flightSpeedMs,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PatrolRoute.fromJson(Map<String, dynamic> json) => PatrolRoute(
        id: json['id'] as String,
        name: json['name'] as String,
        waypoints: (json['waypoints'] as List)
            .map((w) => PatrolWaypoint.fromJson(w as Map<String, dynamic>))
            .toList(),
        flightSpeedMs: (json['flightSpeedMs'] as num?)?.toDouble() ?? 5.0,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );

  /// Production route — real client site coordinates (Cape Town)
  /// Used in mock mode and on real hardware
  static PatrolRoute get defaultRoute => PatrolRoute(
        id: 'default',
        name: 'Farm perimeter - north',
        waypoints: const [
          PatrolWaypoint(latitude: -33.918, longitude: 18.423),
          PatrolWaypoint(latitude: -33.919, longitude: 18.424),
          PatrolWaypoint(latitude: -33.920, longitude: 18.423),
          PatrolWaypoint(latitude: -33.919, longitude: 18.422),
        ],
      );

  /// SITL route — generates waypoints relative to drone's current GPS position
  /// Works wherever PX4 SITL spawns (Zurich by default)
  /// On real hardware use defaultRoute instead — drone will be in the right place
  static PatrolRoute relativeToPosition(double lat, double lng) {
    const offset = 0.001; // roughly 100m
    return PatrolRoute(
      id: 'auto',
      name: 'Auto patrol route',
      waypoints: [
        PatrolWaypoint(latitude: lat + offset, longitude: lng),
        PatrolWaypoint(latitude: lat + offset, longitude: lng + offset),
        PatrolWaypoint(latitude: lat, longitude: lng + offset),
        PatrolWaypoint(latitude: lat, longitude: lng),
      ],
    );
  }
}
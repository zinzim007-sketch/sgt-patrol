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
}

class PatrolRoute {
  final String name;
  final List<PatrolWaypoint> waypoints;
  final double flightSpeedMs;

  const PatrolRoute({
    required this.name,
    required this.waypoints,
    this.flightSpeedMs = 5.0,
  });

  /// Production route — real client site coordinates (Cape Town)
  /// Used in mock mode and on real hardware
  static PatrolRoute get defaultRoute => const PatrolRoute(
    name: 'Farm perimeter - north',
    waypoints: [
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
      name: 'Auto patrol route',
      waypoints: [
        PatrolWaypoint(latitude: lat + offset, longitude: lng),
        PatrolWaypoint(latitude: lat + offset, longitude: lng + offset),
        PatrolWaypoint(latitude: lat,           longitude: lng + offset),
        PatrolWaypoint(latitude: lat,           longitude: lng),
      ],
    );
  }
}
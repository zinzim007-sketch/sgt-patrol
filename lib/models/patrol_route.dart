/// PatrolWaypoint — a single GPS point in a patrol route.
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
 
/// PatrolRoute — a named list of waypoints defining a patrol path.
class PatrolRoute {
  final String name;
  final List<PatrolWaypoint> waypoints;
  final double flightSpeedMs;
 
  const PatrolRoute({
    required this.name,
    required this.waypoints,
    this.flightSpeedMs = 5.0,
  });
 
  /// Default Cape Town test route — replace with real farm coordinates
  static PatrolRoute get defaultRoute => const PatrolRoute(
    name: 'Farm perimeter — north',
    waypoints: [
      PatrolWaypoint(latitude: -33.918, longitude: 18.423),
      PatrolWaypoint(latitude: -33.919, longitude: 18.424),
      PatrolWaypoint(latitude: -33.920, longitude: 18.423),
      PatrolWaypoint(latitude: -33.919, longitude: 18.422),
    ],
  );
}
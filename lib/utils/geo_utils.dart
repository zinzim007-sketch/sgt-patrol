import 'dart:math';

/// Straight-line ("great-circle") distance between two GPS points, in
/// meters. This IS the shortest path between two points in open air —
/// true pathfinding (A*, RRT, etc.) only matters when there's something
/// to route AROUND (buildings, no-fly zones), and there's no obstacle
/// map yet. If a real site needs obstacle avoidance, that's separate,
/// larger work built on top of this, not a replacement for it.
double haversineDistanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0; // meters
  final dLat = _degToRad(lat2 - lat1);
  final dLng = _degToRad(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_degToRad(lat1)) * cos(_degToRad(lat2)) *
      sin(dLng / 2) * sin(dLng / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return earthRadius * c;
}

double _degToRad(double deg) => deg * pi / 180.0;   
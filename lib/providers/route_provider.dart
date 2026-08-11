import 'package:flutter/foundation.dart';
import '../models/patrol_route.dart';
import '../services/route_storage_service.dart';

class RouteProvider extends ChangeNotifier {
  final RouteStorageService _storage = RouteStorageService();
  List<PatrolRoute> savedRoutes = [];
  bool loaded = false;

  RouteProvider() {
    _loadFromDisk();
  }

  Future<void> _loadFromDisk() async {
    savedRoutes = await _storage.loadRoutes();
    loaded = true;
    notifyListeners();
  }

  Future<void> saveRoute(String name, List<PatrolWaypoint> waypoints) async {
    final route = PatrolRoute(name: name, waypoints: List.of(waypoints));
    savedRoutes = [...savedRoutes, route];
    notifyListeners();
    await _storage.saveRoutes(savedRoutes);
  }

  Future<void> deleteRoute(String id) async {
    savedRoutes = savedRoutes.where((r) => r.id != id).toList();
    notifyListeners();
    await _storage.saveRoutes(savedRoutes);
  }
}
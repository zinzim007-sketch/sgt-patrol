import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/patrol_route.dart';

/// Reads/writes saved patrol routes to a local JSON file.
/// Local-only, per-device storage for now — no backend yet.
/// Upgrade path: swap this class's internals for API calls later;
/// RouteProvider's interface stays the same.
class RouteStorageService {
  static const _fileName = 'patrol_routes.json';

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<PatrolRoute>> loadRoutes() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final contents = await file.readAsString();
      if (contents.trim().isEmpty) return [];
      final List<dynamic> jsonList = jsonDecode(contents) as List<dynamic>;
      return jsonList
          .map((e) => PatrolRoute.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('[SGT] Failed to load routes: $e');
      return [];
    }
  }

  Future<void> saveRoutes(List<PatrolRoute> routes) async {
    try {
      final file = await _getFile();
      final jsonList = routes.map((r) => r.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      print('[SGT] Failed to save routes: $e');
    }
  }
}
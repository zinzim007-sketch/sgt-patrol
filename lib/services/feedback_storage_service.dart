import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/feedback_stats.dart';

/// Persists operator feedback history (confirm/dismiss counts per
/// zone+class) locally, so the adaptive alert-downgrading in
/// AlertEngine survives app restarts instead of resetting to zero
/// every time — same local-only, no-backend-yet approach as
/// RouteStorageService.
class FeedbackStorageService {
  static const _fileName = 'feedback_stats.json';

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<FeedbackStats> load() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return FeedbackStats();
      final contents = await file.readAsString();
      if (contents.trim().isEmpty) return FeedbackStats();
      return FeedbackStats.fromJson(jsonDecode(contents) as Map<String, dynamic>);
    } catch (e) {
      print('[SGT] Failed to load feedback stats: $e');
      return FeedbackStats();
    }
  }

  Future<void> save(FeedbackStats stats) async {
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode(stats.toJson()));
    } catch (e) {
      print('[SGT] Failed to save feedback stats: $e');
    }
  }
}
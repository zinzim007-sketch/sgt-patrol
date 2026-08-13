/// Tracks how operators have responded to past alerts for a given
/// zone+class combination — the raw material for AlertEngine to
/// actually adapt over time, instead of firing the same static rule
/// forever. This IS the "learning" layer: lightweight and statistical,
/// not a retrained model, but it's real feedback changing real
/// decisions, not a claim with nothing behind it.
class FeedbackStats {
  final Map<String, (int confirmed, int dismissed)> _counts;

  FeedbackStats([Map<String, (int confirmed, int dismissed)>? initial])
      : _counts = initial ?? {};

  void recordConfirm(String key) {
    final (c, d) = _counts[key] ?? (0, 0);
    _counts[key] = (c + 1, d);
  }

  void recordDismiss(String key) {
    final (c, d) = _counts[key] ?? (0, 0);
    _counts[key] = (c, d + 1);
  }

  int totalSamples(String key) {
    final (c, d) = _counts[key] ?? (0, 0);
    return c + d;
  }

  /// Fraction of past alerts for this key that were dismissed as false
  /// positives. Returns 0.0 if there's no history yet.
  double dismissRate(String key) {
    final (c, d) = _counts[key] ?? (0, 0);
    final total = c + d;
    if (total == 0) return 0.0;
    return d / total;
  }

  Map<String, dynamic> toJson() => _counts.map(
        (key, value) => MapEntry(key, {'confirmed': value.$1, 'dismissed': value.$2}),
      );

  factory FeedbackStats.fromJson(Map<String, dynamic> json) {
    final counts = <String, (int confirmed, int dismissed)>{};
    json.forEach((key, value) {
      final v = value as Map<String, dynamic>;
      counts[key] = (v['confirmed'] as int? ?? 0, v['dismissed'] as int? ?? 0);
    });
    return FeedbackStats(counts);
  }
}
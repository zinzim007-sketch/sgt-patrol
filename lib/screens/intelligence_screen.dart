import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import '../theme/theme.dart';

class IntelligenceScreen extends StatefulWidget {
  const IntelligenceScreen({super.key});

  @override
  State<IntelligenceScreen> createState() => _IntelligenceScreenState();
}

class _IntelligenceScreenState extends State<IntelligenceScreen> {
  static const _url = 'http://localhost:8766/intelligence';

  Timer? _timer;
  Map<String, dynamic>? _report;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(_url));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode != 200) {
        throw Exception('Intelligence server returned ${response.statusCode}');
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw Exception('Invalid intelligence response');
      }

      if (!mounted) return;
      setState(() {
        _report = Map<String, dynamic>.from(decoded);
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Intelligence API unavailable';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final behavioural =
        report?['behavioural'] as Map<String, dynamic>? ?? {};
    final hotspots =
        (report?['hotspots'] as List?)?.cast<Map>() ?? const [];
    final episodes =
        (report?['top_episodes'] as List?)?.cast<Map>() ?? const [];
    final counts =
        (report?['class_counts'] as Map?)?.cast<String, dynamic>() ??
            const {};

    return Scaffold(
      backgroundColor: SGTColors.navyDeep,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: SGTColors.blueMuted,
          backgroundColor: SGTColors.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'BEHAVIOURAL INTELLIGENCE',
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w600,
                            color: SGTColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Patrol activity patterns',
                          style: TextStyle(
                            fontSize: 10,
                            color: SGTColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_outlined, size: 18),
                    color: SGTColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_error != null)
                _StatusCard(
                  title: 'INTELLIGENCE OFFLINE',
                  body:
                      'Start intelligence_server.py while the detector is running.',
                  icon: Icons.cloud_off_outlined,
                ),

              if (_loading && report == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),

              if (report != null) ...[
                _AssessmentCard(
                  status: '${behavioural['site_status'] ?? 'UNKNOWN'}',
                  summary:
                      '${report['intelligence_summary'] ?? 'No summary available.'}',
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        label: 'LOITERING',
                        value: '${behavioural['loitering_events'] ?? 0}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MetricCard(
                        label: 'AVG RISK',
                        value: '${behavioural['average_risk'] ?? 0}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MetricCard(
                        label: 'PEAK RISK',
                        value: '${behavioural['maximum_risk'] ?? 0}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                const _SectionTitle(
                  title: 'RECURRING HOTSPOTS',
                  subtitle: 'Repeated behavioural activity',
                ),
                const SizedBox(height: 10),

                if (hotspots.isEmpty)
                  const _EmptyCard(text: 'No recurring hotspots identified.')
                else
                  ...hotspots.take(5).toList().asMap().entries.map(
                    (entry) {
                      final index = entry.key + 1;
                      final h = entry.value;
                      return _HotspotCard(index: index, hotspot: h);
                    },
                  ),

                const SizedBox(height: 18),

                const _SectionTitle(
                  title: 'TOP EPISODES',
                  subtitle: 'Highest behavioural severity',
                ),
                const SizedBox(height: 10),

                if (episodes.isEmpty)
                  const _EmptyCard(text: 'No behavioural episodes identified.')
                else
                  ...episodes.take(5).toList().asMap().entries.map(
                    (entry) {
                      final index = entry.key + 1;
                      return _EpisodeCard(
                        index: index,
                        episode: entry.value,
                      );
                    },
                  ),

                const SizedBox(height: 18),

                const _SectionTitle(
                  title: 'DETECTION MIX',
                  subtitle: 'Events recorded in the patrol log',
                ),
                const SizedBox(height: 10),
                _DetectionMix(counts: counts),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AssessmentCard extends StatelessWidget {
  final String status;
  final String summary;

  const _AssessmentCard({
    required this.status,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final isElevated = status == 'ELEVATED' || status == 'HIGH';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SGTColors.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: isElevated ? SGTColors.warning : SGTColors.border,
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 17,
                color: isElevated ? SGTColors.warning : SGTColors.online,
              ),
              const SizedBox(width: 8),
              const Text(
                'SITE ASSESSMENT',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.2,
                  color: SGTColors.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                status,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: isElevated
                      ? SGTColors.warning
                      : SGTColors.online,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            summary,
            style: const TextStyle(
              fontSize: 11,
              height: 1.45,
              color: SGTColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;

  const _MetricCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
      decoration: BoxDecoration(
        color: SGTColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: SGTColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: SGTColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 8,
              letterSpacing: 1.0,
              color: SGTColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 1.4,
            color: SGTColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 9,
            color: SGTColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _HotspotCard extends StatelessWidget {
  final int index;
  final Map hotspot;

  const _HotspotCard({
    required this.index,
    required this.hotspot,
  });

  @override
  Widget build(BuildContext context) {
    final level = '${hotspot['level'] ?? 'LOW'}';
    final color = level == 'HIGH'
        ? SGTColors.danger
        : level == 'ELEVATED'
            ? SGTColors.warning
            : SGTColors.blueMuted;

    final centre = hotspot['approx_center_px'];
    final location = centre is List && centre.length >= 2
        ? '(${centre[0]}, ${centre[1]})'
        : 'Unknown';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: SGTColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: SGTColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Text(
            '#$index',
            style: const TextStyle(
              fontSize: 10,
              color: SGTColors.textMuted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$level HOTSPOT',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${hotspot['events'] ?? 0} events  •  avg ${hotspot['average_risk'] ?? 0}  •  peak ${hotspot['peak_risk'] ?? 0}',
                  style: const TextStyle(
                    fontSize: 9,
                    color: SGTColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            location,
            style: const TextStyle(
              fontSize: 8,
              color: SGTColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  final int index;
  final Map episode;

  const _EpisodeCard({
    required this.index,
    required this.episode,
  });

  @override
  Widget build(BuildContext context) {
    final level = '${episode['level'] ?? 'LOW'}';
    final color = level == 'HIGH'
        ? SGTColors.danger
        : level == 'ELEVATED'
            ? SGTColors.warning
            : SGTColors.blueMuted;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: SGTColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: SGTColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Text(
            '#$index',
            style: const TextStyle(
              fontSize: 10,
              color: SGTColors.textMuted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$level  •  ${episode['events'] ?? 0} events  •  ${episode['duration_s'] ?? 0}s  •  peak ${episode['peak_risk'] ?? 0}',
              style: TextStyle(
                fontSize: 9,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetectionMix extends StatelessWidget {
  final Map<String, dynamic> counts;

  const _DetectionMix({required this.counts});

  @override
  Widget build(BuildContext context) {
    final entries = counts.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SGTColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: SGTColors.border, width: 0.5),
      ),
      child: Column(
        children: entries.take(7).map((entry) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.key.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 8,
                      letterSpacing: 0.8,
                      color: SGTColors.textSecondary,
                    ),
                  ),
                ),
                Text(
                  '${entry.value}',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: SGTColors.textPrimary,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String title;
  final String body;
  final IconData icon;

  const _StatusCard({
    required this.title,
    required this.body,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SGTColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: SGTColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: SGTColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.0,
                    color: SGTColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 9,
                    color: SGTColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;

  const _EmptyCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SGTColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: SGTColors.border, width: 0.5),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 9,
          color: SGTColors.textMuted,
        ),
      ),
    );
  }
}

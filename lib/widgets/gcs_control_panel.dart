import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/theme.dart';
import '../providers/gcs_client_provider.dart';

/// GcsControlPanel — mirrors gcs_web.py's own built-in browser page
/// (127.0.0.1:8080): telemetry tiles, link health, the gate-status
/// banner, recovery mode buttons, arm/takeoff, and guided controls
/// (altitude/goto/yaw).
///
/// Lives inside the SETTINGS screen (screens/settings_screen.dart),
/// wrapped in a _SettingsCard with a warning banner above it — this was
/// deliberately kept out of the Fly-tab sidebar, which was already
/// dense before this existed, and out of the Mission tab, which is a
/// full-bleed map with no spare room. See the conversation this was
/// built from for the reasoning.
///
/// Deliberately namespaced apart from _ActionButtons' ARM/TAKEOFF
/// buttons on the Fly tab — those call DroneProvider's own raw MAVLink
/// socket (patrol-mission path). Everything in this panel calls
/// GcsClientProvider, i.e. goes through gcs_web.py. Same vehicle, two
/// independent command paths — see gcs_client_provider.dart's header
/// comment on why they coexist and the mutual-exclusion guard already
/// in RemoteAlertPanel for the dispatch-vs-local-mission case.
///
/// This panel does NOT add its own mutual-exclusion guard against
/// MissionProvider — arm/takeoff/goto here go straight to gcs_web.py's
/// own gate() and require() checks server-side, same protection the
/// browser page itself relies on. If you're driving both this panel
/// and a local patrol mission at once, that's on you, same as having
/// two browser tabs open against gcs_web.py already was.
class GcsControlPanel extends StatefulWidget {
  const GcsControlPanel({super.key});

  @override
  State<GcsControlPanel> createState() => _GcsControlPanelState();
}

class _GcsControlPanelState extends State<GcsControlPanel> {
  final _altController = TextEditingController(text: '20');
  final _headingController = TextEditingController(text: '0');
  bool _busy = false;

  @override
  void dispose() {
    _altController.dispose();
    _headingController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final err = await action();
    if (mounted) {
      setState(() => _busy = false);
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: SGTColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gcs = context.watch<GcsClientProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('GCS CONTROL',
            style: TextStyle(
                fontSize: 9, color: Color(0xFF8C98A8), letterSpacing: 1.5)),
        const SizedBox(height: 8),

        _TelemetryGrid(gcs: gcs),
        const SizedBox(height: 8),
        _LinkHealthRow(gcs: gcs),
        const SizedBox(height: 10),

        if (!gcs.isGateOpen)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: SGTColors.dangerBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF5a1a1a), width: 0.5),
            ),
            child: Text(
              'BLOCKED — ${gcs.gateReason}',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: SGTColors.danger),
            ),
          ),

        const Text('RECOVERY — ALWAYS AVAILABLE',
            style: TextStyle(
                fontSize: 9, color: Color(0xFF8C98A8), letterSpacing: 1.0)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _ModeChip(label: 'RTL', danger: true, busy: _busy,
                onTap: () => _run(() => gcs.setMode('RTL'))),
            _ModeChip(label: 'LAND', danger: true, busy: _busy,
                onTap: () => _run(() => gcs.setMode('LAND'))),
            _ModeChip(label: 'BRAKE', busy: _busy,
                onTap: () => _run(() => gcs.setMode('BRAKE'))),
            _ModeChip(label: 'LOITER', busy: _busy,
                onTap: () => _run(() => gcs.setMode('LOITER'))),
            _ModeChip(label: 'ALT HOLD', busy: _busy,
                onTap: () => _run(() => gcs.setMode('ALT_HOLD'))),
          ],
        ),
        const SizedBox(height: 12),

        const Text('GROUND',
            style: TextStyle(
                fontSize: 9, color: Color(0xFF8C98A8), letterSpacing: 1.0)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _ActionChip(
                label: gcs.armed ? 'DISARM' : 'ARM',
                enabled: !_busy && gcs.serverReachable,
                onTap: () => _run(() => gcs.armed ? gcs.disarm() : gcs.arm()),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _ActionChip(
                label: 'TAKEOFF',
                enabled: !_busy && gcs.serverReachable && gcs.armed,
                onTap: () => _run(() => gcs.takeoff(20)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        const Text('GUIDED — REQUIRES SWITCH',
            style: TextStyle(
                fontSize: 9, color: Color(0xFF8C98A8), letterSpacing: 1.0)),
        const SizedBox(height: 6),
        _ActionChip(
          label: 'ENTER GUIDED',
          enabled: !_busy && gcs.serverReachable,
          onTap: () => _run(() => gcs.setMode('GUIDED')),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _NumberField(
                controller: _altController,
                suffix: 'm',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: _ActionChip(
                label: 'GO TO ALTITUDE',
                enabled: !_busy && gcs.serverReachable && gcs.armed,
                onTap: () {
                  final alt = double.tryParse(_altController.text);
                  if (alt == null) return;
                  _run(() => gcs.goToAltitude(alt));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _NumberField(
                controller: _headingController,
                suffix: '°',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: _ActionChip(
                label: 'YAW TO HEADING',
                enabled: !_busy && gcs.serverReachable && gcs.armed,
                onTap: () {
                  final hdg = double.tryParse(_headingController.text);
                  if (hdg == null) return;
                  _run(() => gcs.yawTo(hdg));
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TelemetryGrid extends StatelessWidget {
  final GcsClientProvider gcs;
  const _TelemetryGrid({required this.gcs});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _Tile('MODE', gcs.mode ?? '—'),
      _Tile('ARMED', gcs.armed ? 'armed' : 'disarmed',
          valueColor: gcs.armed ? SGTColors.danger : null),
      _Tile('ALT AGL', gcs.relAltitude != null
          ? '${gcs.relAltitude!.toStringAsFixed(1)} m' : '—'),
      _Tile('GROUND SPD', gcs.groundspeed != null
          ? '${gcs.groundspeed!.toStringAsFixed(1)} m/s' : '—'),
      _Tile('BATTERY', gcs.voltage != null
          ? '${gcs.voltage!.toStringAsFixed(1)} V' : '—'),
      _Tile('SATS / HDOP', gcs.satellites != null
          ? '${gcs.satellites} / ${gcs.hdop?.toStringAsFixed(1) ?? "—"}' : '—'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tiles.map((t) => SizedBox(width: 100, child: t)).toList(),
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _Tile(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: SGTColors.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: SGTColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 8, color: Color(0xFF8C98A8), letterSpacing: 0.5)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? Colors.white)),
        ],
      ),
    );
  }
}

class _LinkHealthRow extends StatelessWidget {
  final GcsClientProvider gcs;
  const _LinkHealthRow({required this.gcs});

  @override
  Widget build(BuildContext context) {
    String fmt(double v) => v.toStringAsFixed(0);
    return Text(
      'msgs ${gcs.serverReachable ? fmt(gcs.msgRate) : "—"}/s   '
      'heartbeat ${gcs.serverReachable ? fmt(gcs.hbRate) : "—"}/s   '
      'bad ${gcs.badRate.toStringAsFixed(0)}/s   '
      'cmd RTT ${gcs.ackMs != null ? "${gcs.ackMs!.toStringAsFixed(0)} ms" : "—"}',
      style: const TextStyle(fontSize: 10, color: Color(0xFF6b7684)),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool danger;
  final bool busy;
  final VoidCallback onTap;
  const _ModeChip(
      {required this.label, this.danger = false, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = danger ? SGTColors.danger : SGTColors.warning;
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(busy ? 0.08 : 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(busy ? 0.4 : 1), width: 0.5),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w500,
                color: color.withOpacity(busy ? 0.4 : 1))),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _ActionChip({required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? SGTColors.blue.withOpacity(0.15) : SGTColors.surfaceRaised,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: enabled ? SGTColors.blue : SGTColors.border, width: 0.5),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w500,
                color: enabled ? SGTColors.blue : SGTColors.textMuted)),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String suffix;
  const _NumberField({required this.controller, required this.suffix});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: SGTColors.surfaceRaised,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: SGTColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 6),
              ),
            ),
          ),
          Text(suffix,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8C98A8))),
        ],
      ),
    );
  }
}

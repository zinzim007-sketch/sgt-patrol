import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/theme.dart';
import '../providers/gcs_client_provider.dart';
import '../providers/mission_provider.dart';

/// _RemoteAlertPanel — shows panic alerts from gcs_web.py (a remote phone
/// button, relayed through the VM at PANIC_URL), with a DISPATCH button
/// per alert and an ABORT for an active dispatch.
///
/// This is deliberately SEPARATE from _AlertPanel (video/ROS detections,
/// DetectionProvider) and _PanicButton (operator's own position, raw
/// MAVLink reposition via MissionProvider/DroneProvider). Those three
/// alert sources are genuinely different things with different dispatch
/// mechanics — see the conversation this was built from for why they
/// weren't merged into one path.
///
/// MUTUAL EXCLUSION: gcs_web.py's dispatch (arm -> takeoff -> standoff)
/// and MissionProvider's own mission (patrol / local panic reposition)
/// both command the same vehicle through independent MAVLink connections.
/// Nothing on the flight-controller side arbitrates between them. This
/// panel disables DISPATCH while MissionProvider reports an active local
/// mission, and shows why — but this is a software-only guard on the
/// Dart side, same caveat as gcs_web.py's own gate(): it does not stop
/// someone from using gcs_web.py's own built-in web UI at the same time.
class RemoteAlertPanel extends StatelessWidget {
  const RemoteAlertPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final gcs = context.watch<GcsClientProvider>();
    final mission = context.watch<MissionProvider>();

    final localMissionActive = mission.state == MissionState.executing ||
        mission.state == MissionState.holding;

    // Nothing to show: no alerts, no error, no active remote mission.
    // Keeps the sidebar quiet when there's nothing remote going on,
    // same as _AlertPanel collapsing when DetectionProvider has no
    // active alerts.
    if (gcs.alerts.isEmpty &&
        gcs.alertsError == null &&
        !gcs.missionActive) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('REMOTE ALERTS',
                style: TextStyle(
                    fontSize: 9,
                    color: Color(0xFF8C98A8),
                    letterSpacing: 1.5)),
            const Spacer(),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: gcs.isConnected
                    ? SGTColors.online
                    : SGTColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (gcs.alertsError != null) _RemoteAlertError(message: gcs.alertsError!),

        if (gcs.missionActive) _RemoteMissionStatus(gcs: gcs),

        if (localMissionActive && gcs.alerts.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Local mission active — remote dispatch disabled until it '
              'clears, to avoid two systems commanding the vehicle at once.',
              style: TextStyle(fontSize: 10, color: SGTColors.warning),
            ),
          ),

        ...gcs.alerts.map((a) => _RemoteAlertCard(
              alert: a,
              disabled: !gcs.isGateOpen || gcs.missionActive || localMissionActive,
              disabledReason: !gcs.isGateOpen
                  ? gcs.gateReason
                  : (gcs.missionActive
                      ? 'a remote dispatch is already running'
                      : (localMissionActive
                          ? 'local mission active'
                          : null)),
            )),

        const SizedBox(height: 4),
      ],
    );
  }
}

class _RemoteAlertError extends StatelessWidget {
  final String message;
  const _RemoteAlertError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SGTColors.dangerBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF5a1a1a), width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, size: 14, color: SGTColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Remote alert feed: $message',
                style: const TextStyle(fontSize: 11, color: SGTColors.danger)),
          ),
        ],
      ),
    );
  }
}

class _RemoteMissionStatus extends StatelessWidget {
  final GcsClientProvider gcs;
  const _RemoteMissionStatus({required this.gcs});

  @override
  Widget build(BuildContext context) {
    final dist = gcs.missionDistance;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF2a1f00),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF5a3a00), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flight, size: 14, color: SGTColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'DISPATCH: ${gcs.missionPhase}'
                  '${dist != null ? '  —  ${dist.toStringAsFixed(0)} m to go' : ''}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: SGTColors.warning),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              final err = await gcs.abort();
              if (context.mounted && err != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('Abort failed: $err'),
                      backgroundColor: SGTColors.danger),
                );
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: SGTColors.danger.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: SGTColors.danger, width: 0.5),
              ),
              child: const Text('ABORT DISPATCH',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w500,
                      color: SGTColors.danger)),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteAlertCard extends StatelessWidget {
  final PanicAlert alert;
  final bool disabled;
  final String? disabledReason;

  const _RemoteAlertCard({
    required this.alert,
    required this.disabled,
    this.disabledReason,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: SGTColors.dangerBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF5a1a1a), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: SGTColors.danger.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: SGTColors.danger, width: 0.5),
                ),
                child: const Text('PANIC',
                    style: TextStyle(
                        fontSize: 9,
                        color: SGTColors.danger,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${alert.lat.toStringAsFixed(5)}, ${alert.lon.toStringAsFixed(5)}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: SGTColors.danger),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '±${alert.accuracyM.toStringAsFixed(0)} m accuracy  ·  ${alert.id}',
            style: const TextStyle(fontSize: 10, color: Color(0xFF8C98A8)),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: disabled ? null : () => _confirmAndDispatch(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: disabled
                    ? SGTColors.surfaceRaised
                    : SGTColors.blue.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: disabled ? SGTColors.border : SGTColors.blue,
                    width: 0.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.flight,
                      size: 12,
                      color: disabled ? SGTColors.textMuted : SGTColors.blue),
                  const SizedBox(width: 6),
                  Text(
                    disabled ? 'DISPATCH — ${disabledReason ?? 'unavailable'}' : 'DISPATCH DRONE',
                    style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w500,
                        color: disabled ? SGTColors.textMuted : SGTColors.blue),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndDispatch(BuildContext context) async {
    // Mirrors gcs_web.py's own built-in UI, which requires this same
    // confirm() before calling /api/dispatch — the coordinate is
    // someone else's exact location, not a drill.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SGTColors.surfaceRaised,
        title: const Text('Confirm dispatch'),
        content: Text(
          'Dispatch drone to ${alert.lat.toStringAsFixed(5)}, '
          '${alert.lon.toStringAsFixed(5)}?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('DISPATCH',
                  style: TextStyle(color: SGTColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;

    final gcs = context.read<GcsClientProvider>();
    final err = await gcs.dispatch(lat: alert.lat, lon: alert.lon, id: alert.id);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? 'Dispatching to panic alert...'),
        backgroundColor: err != null ? SGTColors.danger : SGTColors.blue,
      ),
    );
  }
}

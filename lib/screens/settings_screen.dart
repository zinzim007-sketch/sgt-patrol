import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/theme.dart';
import '../providers/drone_provider.dart';
import '../widgets/gcs_control_panel.dart';
import 'login_screen.dart';
import '../providers/gcs_client_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<OperatorSession>();
    final drone = context.watch<DroneProvider>();

    final gcs = context.watch<GcsClientProvider>();

    return Scaffold(
      backgroundColor: SGTColors.navyDeep,
      appBar: AppBar(
        backgroundColor: SGTColors.navyDeep,
        elevation: 0,
        titleSpacing: 20,
        title: const Text(
          'SETTINGS',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.8,
            color: SGTColors.textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          const _SectionLabel('OPERATOR'),
          _SettingsCard(
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: SGTColors.navyLight,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: SGTColors.border,
                      width: 0.6,
                    ),
                  ),
                  child: const Icon(
                    Icons.person_outline,
                    size: 21,
                    color: SGTColors.blueMuted,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.operatorName ?? 'Unknown operator',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: SGTColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        session.operatorId ?? '—',
                        style: const TextStyle(
                          fontSize: 10,
                          color: SGTColors.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const _StatusDot(),
              ],
            ),
          ),

          const SizedBox(height: 24),

          const _SectionLabel('AIRCRAFT'),
          _SettingsCard(
            child: Column(
              children: [
                const _InfoRow(
                  icon: Icons.flight_outlined,
                  label: 'AIRCRAFT',
                  value: 'ARGUS-01',
                ),
                const SizedBox(height: 15),
                const _InfoRow(
                  icon: Icons.qr_code_2_outlined,
                  label: 'SERIAL NUMBER',
                  value: 'SGT-ARGUS001',
                ),
                const SizedBox(height: 15),

                _InfoRow(
                  icon: Icons.link_outlined,
                  label: 'STATUS',
                  value: gcs.isConnected ? 'CONNECTED' : 'OFFLINE',
                  valueColor:
                      gcs.isConnected ? SGTColors.online : SGTColors.danger,
                ),


    
              ],
            ),
          ),

          const SizedBox(height: 24),

          const _SectionLabel('SYSTEM'),
          _SettingsCard(
            child: Column(
              children: [
                const _InfoRow(
                  icon: Icons.security_outlined,
                  label: 'PLATFORM',
                  value: 'SAFEGUARD OS',
                ),
                const SizedBox(height: 15),
                _InfoRow(
                  icon: Icons.shield_outlined,
                  label: 'SYSTEM STATUS',
                  value: gcs.isConnected ? 'OPERATIONAL' : 'CHECK CONNECTION',
                  valueColor: gcs.isConnected
                      ? SGTColors.online
                      : SGTColors.danger,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          const _SectionLabel('GCS CONTROL'),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF2a1f00),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF5a3a00), width: 0.5),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: SGTColors.warning),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Commands below act on the real aircraft via gcs_web.py.',
                    style: TextStyle(fontSize: 10, color: SGTColors.warning),
                  ),
                ),
              ],
            ),
          ),
          // GcsControlPanel already renders its own internal "GCS
          // CONTROL" label (for the Fly-tab sidebar context it was
          // originally built for) — that's fine sitting inside this
          // card too, just a touch redundant with the _SectionLabel
          // above it. Left as-is rather than forking the widget.
          _SettingsCard(
            child: const GcsControlPanel(),
          ),

          const SizedBox(height: 30),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmSignOut(context),
              icon: const Icon(Icons.logout, size: 17),
              label: const Text(
                'SIGN OUT',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: SGTColors.textSecondary,
                side: const BorderSide(
                  color: SGTColors.borderLight,
                  width: 0.7,
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ),

          const SizedBox(height: 18),

          const Center(
            child: Text(
              'SAFEGUARD TECHNOLOGIES  •  ARGUS',
              style: TextStyle(
                fontSize: 7,
                letterSpacing: 1.2,
                color: SGTColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SGTColors.surface,
        title: const Text(
          'Sign out?',
          style: TextStyle(
            color: SGTColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: const Text(
          'You will need to authenticate again to access ARGUS operations.',
          style: TextStyle(
            color: SGTColors.textSecondary,
            fontSize: 11,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('SIGN OUT'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      context.read<OperatorSession>().signOut();
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
          color: SGTColors.blueMuted,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final Widget child;

  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: SGTColors.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: SGTColors.border,
          width: 0.6,
        ),
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: SGTColors.blueMuted),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
              color: SGTColors.textMuted,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: valueColor ?? SGTColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: SGTColors.online,
        shape: BoxShape.circle,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/theme.dart';
import '../providers/drone_provider.dart';
import '../providers/mission_provider.dart';
import '../models/patrol_route.dart';
 
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _TopBar(),
          _VideoFeed(),
          _TelemetryBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MissionCard(),
                  const SizedBox(height: 12),
                  _ActionButtons(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
 
// -------------------------------------------------------------------------
// Top bar
// -------------------------------------------------------------------------
 
class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneProvider>();
    return SafeArea(
      bottom: false,
      child: Container(
        color: SGTColors.navyDeep,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Text(
              'SGT PATROL',
              style: TextStyle(
                color: SGTColors.blueMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 2.0,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: drone.isConnected
                    ? SGTColors.onlineBg
                    : SGTColors.dangerBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: drone.isConnected
                      ? const Color(0xFF1a5c35)
                      : const Color(0xFF5a1a1a),
                  width: 0.5,
                ),
              ),
              child: Text(
                drone.isConnected ? 'LIVE' : 'OFFLINE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.0,
                  color: drone.isConnected
                      ? SGTColors.online
                      : SGTColors.danger,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
 
// -------------------------------------------------------------------------
// Video feed area
// -------------------------------------------------------------------------
 
class _VideoFeed extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneProvider>();
    return Container(
      height: 200,
      color: SGTColors.navyDeep,
      child: Stack(
        children: [
          // Placeholder — replace with DJI video texture when SDK is ready
          const Center(
            child: Text(
              'CAMERA FEED',
              style: TextStyle(
                color: SGTColors.textMuted,
                fontSize: 11,
                letterSpacing: 2.0,
              ),
            ),
          ),
          // Corner brackets
          ..._cornerBrackets(),
          // Status message
          Positioned(
            bottom: 10,
            left: 14,
            child: Text(
              drone.statusMessage,
              style: const TextStyle(
                color: SGTColors.textSecondary,
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
          ),
          // REC indicator
          if (drone.isConnected)
            Positioned(
              top: 10,
              right: 14,
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: SGTColors.danger,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'REC',
                    style: TextStyle(
                      color: SGTColors.danger,
                      fontSize: 9,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
 
  List<Widget> _cornerBrackets() {
    const color = Color(0xFF1e3a6a);
    const size = 14.0;
    const thickness = 1.0;
    const offset = 10.0;
 
    return [
      Positioned(top: offset, left: offset,
        child: _Bracket(size: size, thickness: thickness, color: color, top: true, left: true)),
      Positioned(top: offset, right: offset,
        child: _Bracket(size: size, thickness: thickness, color: color, top: true, left: false)),
      Positioned(bottom: offset, left: offset,
        child: _Bracket(size: size, thickness: thickness, color: color, top: false, left: true)),
      Positioned(bottom: offset, right: offset,
        child: _Bracket(size: size, thickness: thickness, color: color, top: false, left: false)),
    ];
  }
}
 
class _Bracket extends StatelessWidget {
  final double size, thickness;
  final Color color;
  final bool top, left;
 
  const _Bracket({
    required this.size, required this.thickness,
    required this.color, required this.top, required this.left,
  });
 
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BracketPainter(color, thickness, top, left),
      ),
    );
  }
}
 
class _BracketPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final bool top, left;
 
  _BracketPainter(this.color, this.thickness, this.top, this.left);
 
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke;
 
    final path = Path();
    if (top && left) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (top && !left) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (!top && left) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width, 0);
    }
    canvas.drawPath(path, paint);
  }
 
  @override
  bool shouldRepaint(_BracketPainter old) => false;
}
 
// -------------------------------------------------------------------------
// Telemetry bar
// -------------------------------------------------------------------------
 
class _TelemetryBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneProvider>();
 
    final cells = [
      (label: 'ALT', value: '${drone.altitude.toStringAsFixed(1)}', unit: 'm'),
      (label: 'SPD', value: '${drone.speed.toStringAsFixed(1)}', unit: 'm/s'),
      (label: 'BAT', value: '${drone.batteryLevel}', unit: '%',),
      (label: 'GPS', value: '${drone.gpsSatellites}', unit: 'sats'),
    ];
 
    return Container(
      decoration: const BoxDecoration(
        color: SGTColors.surface,
        border: Border.symmetric(
          horizontal: BorderSide(color: SGTColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: cells.map((cell) {
          final isBatLow = cell.label == 'BAT' && drone.batteryLevel <= 20;
          return Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                border: Border(
                  right: BorderSide(color: SGTColors.border, width: 0.5),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    cell.label,
                    style: const TextStyle(
                      fontSize: 9,
                      color: SGTColors.textMuted,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    cell.value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isBatLow
                          ? SGTColors.danger
                          : SGTColors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    cell.unit,
                    style: const TextStyle(
                      fontSize: 9,
                      color: SGTColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
 
// -------------------------------------------------------------------------
// Mission card
// -------------------------------------------------------------------------
 
class _MissionCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final mission = context.watch<MissionProvider>();
 
    final statusColor = switch (mission.state) {
      MissionState.ready => SGTColors.online,
      MissionState.executing => SGTColors.warning,
      MissionState.complete => SGTColors.blueMuted,
      MissionState.error => SGTColors.danger,
      _ => SGTColors.textMuted,
    };
 
    final statusLabel = switch (mission.state) {
      MissionState.idle => 'IDLE',
      MissionState.uploading => 'UPLOADING',
      MissionState.ready => 'READY',
      MissionState.executing => 'EXECUTING',
      MissionState.complete => 'COMPLETE',
      MissionState.error => 'ERROR',
    };
 
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ACTIVE MISSION',
          style: TextStyle(
            fontSize: 9,
            color: SGTColors.textMuted,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: SGTColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: SGTColors.border, width: 0.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Farm perimeter — north',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: SGTColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      mission.state == MissionState.executing
                          ? 'Waypoint ${mission.currentWaypoint} / ${mission.totalWaypoints}'
                          : '4 waypoints · 5 m/s',
                      style: const TextStyle(
                        fontSize: 11,
                        color: SGTColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: SGTColors.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor.withOpacity(0.4), width: 0.5),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: statusColor,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Mission status message
        Text(
          mission.statusMessage,
          style: const TextStyle(
            fontSize: 11,
            color: SGTColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
 
// -------------------------------------------------------------------------
// Action buttons
// -------------------------------------------------------------------------
 
class _ActionButtons extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneProvider>();
    final mission = context.watch<MissionProvider>();
 
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SGTButton(
                label: 'UPLOAD',
                icon: Icons.upload_outlined,
                enabled: drone.isConnected && mission.canUpload,
                onTap: () => mission.uploadMission(
                  PatrolRoute.defaultRoute,
                  useMock: drone.useMock,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SGTButton(
                label: 'START PATROL',
                icon: Icons.play_arrow_outlined,
                enabled: drone.isConnected && mission.canStart,
                onTap: () => mission.startMission(useMock: drone.useMock),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SGTButton(
                label: 'STOP',
                icon: Icons.stop_outlined,
                enabled: drone.isConnected && mission.canStop,
                onTap: () => mission.stopMission(useMock: drone.useMock),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _PanicButton(drone: drone),
      ],
    );
  }
}
 
class _SGTButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
 
  const _SGTButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });
 
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: enabled ? SGTColors.navyLight : SGTColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: enabled ? SGTColors.borderLight : SGTColors.border,
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 18,
              color: enabled ? SGTColors.textPrimary : SGTColors.textMuted,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.0,
                fontWeight: FontWeight.w500,
                color: enabled ? SGTColors.textPrimary : SGTColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
 
class _PanicButton extends StatelessWidget {
  final DroneProvider drone;
  const _PanicButton({required this.drone});
 
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: drone.isConnected
          ? () => drone.returnToHome((success, message) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(message)),
                );
              })
          : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: SGTColors.dangerBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF5a1a1a), width: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning_amber_outlined,
              size: 16,
              color: drone.isConnected
                  ? SGTColors.danger
                  : SGTColors.danger.withOpacity(0.4),
            ),
            const SizedBox(width: 8),
            Text(
              'PANIC — RETURN HOME',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w500,
                color: drone.isConnected
                    ? SGTColors.danger
                    : SGTColors.danger.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
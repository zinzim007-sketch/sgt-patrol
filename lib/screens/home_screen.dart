import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/theme.dart';
import '../providers/drone_provider.dart';
import '../providers/mission_provider.dart';
import '../providers/detection_provider.dart';
import '../models/patrol_route.dart';
import '../models/detection_alert.dart';
import '../models/site_config.dart';
import '../providers/gemini_provider.dart';
import '../providers/gcs_client_provider.dart';
import '../widgets/remote_alert_panel.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SGTColors.navyDeep,
      body: Column(
        children: [
            _TopBar(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Keep the existing widgets and provider actions exactly as
                  // they are. This step only changes the dashboard layout.
                  final isWide = constraints.maxWidth >= 900;

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 7,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                            child: Column(
                              children: [
                                Expanded(child: _VideoFeed()),
                                const SizedBox(height: 10),
                                _TelemetryBar(),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: SGTColors.surface,
                              border: Border(
                                left: BorderSide(
                                  color: SGTColors.border,
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const _SectionHeader(
                                    title: 'OPERATIONS',
                                    subtitle: 'Live patrol controls',
                                  ),
                                  const SizedBox(height: 16),
                                  _AlertPanel(),
                                  const SizedBox(height: 18),
                                  const RemoteAlertPanel(),
                                  const SizedBox(height: 18),
                                  _MissionCard(),
                                  const SizedBox(height: 18),
                                  _ActionButtons(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  // Keep a practical stacked layout for smaller screens.
                  return Column(
                    children: [
                      Expanded(flex: 5, child: _VideoFeed()),
                      _TelemetryBar(),
                      Expanded(
                        flex: 5,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionHeader(
                                title: 'OPERATIONS',
                                subtitle: 'Live patrol controls',
                              ),
                              const SizedBox(height: 14),
                              _AlertPanel(),
                              const SizedBox(height: 14),
                              const RemoteAlertPanel(),
                              const SizedBox(height: 14),
                              _MissionCard(),
                              const SizedBox(height: 14),
                              _ActionButtons(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  color: const Color(0xFFF3F6FA),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 10,
                  color: const Color(0xFF8C98A8),
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: SGTColors.blue,
            shape: BoxShape.circle,
          ),
        ),
      ],
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
    final detection = context.watch<DetectionProvider>();
    final gcs = context.watch<GcsClientProvider>();

    return SafeArea(
      bottom: false,
      child: Container(
        color: SGTColors.navyDeep,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Text('SGT PATROL',
              style: TextStyle(
                color: const Color(0xFFE8EDF5), fontSize: 11,
                fontWeight: FontWeight.w500, letterSpacing: 2.0)),
            const SizedBox(width: 8),
            // Site type badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: SGTColors.surfaceRaised,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: SGTColors.border, width: 0.5),
              ),
              child: Text(
                detection.siteConfig.siteType.name.toUpperCase(),
                style: const TextStyle(
                  fontSize: 8, color: const Color(0xFF8C98A8), letterSpacing: 1.0)),
            ),
            const Spacer(),
            if (!drone.useMock)
              Text(
                '${drone.latitude.toStringAsFixed(4)}, ${drone.longitude.toStringAsFixed(4)}',
                style: const TextStyle(fontSize: 9, color: const Color(0xFF8C98A8)),
              ),
            // Critical alert badge
            if (detection.hasCritical)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: SGTColors.dangerBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: SGTColors.danger, width: 0.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.crisis_alert, size: 10, color: SGTColors.danger),
                    const SizedBox(width: 4),
                    Text(
                      '${detection.criticalAlerts.length} CRITICAL',
                      style: const TextStyle(
                        fontSize: 10, color: SGTColors.danger,
                        fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                  ],
                ),
              )
            else if (detection.unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF2a1f00),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: SGTColors.warning, width: 0.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, size: 10, color: SGTColors.warning),
                    const SizedBox(width: 4),
                    Text(
                      '${detection.unreadCount} ALERT${detection.unreadCount > 1 ? 'S' : ''}',
                      style: const TextStyle(
                        fontSize: 10, color: SGTColors.warning,
                        fontWeight: FontWeight.w500, letterSpacing: 0.8)),
                  ],
                ),
              ),
            // Split into two chips on purpose: gcs_web.py being up and a
            // vehicle actually talking to it are different facts, and
            // collapsing them into one label read as "can't reach
            // gcs_web.py" when actually the server was fine and there
            // was just no aircraft powered on.
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: gcs.serverReachable ? SGTColors.onlineBg : SGTColors.dangerBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: gcs.serverReachable
                      ? const Color(0xFF1a5c35) : const Color(0xFF5a1a1a),
                  width: 0.5),
              ),
              child: Text(
                gcs.serverReachable ? 'GCS' : 'GCS OFFLINE',
                style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 1.0,
                  color: gcs.serverReachable ? SGTColors.online : SGTColors.danger)),
            ),
            if (gcs.serverReachable)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: gcs.isConnected
                      ? SGTColors.onlineBg : const Color(0xFF2a1f00),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: gcs.isConnected
                        ? const Color(0xFF1a5c35) : const Color(0xFF5a3a00),
                    width: 0.5),
                ),
                // Amber, not red: an unreachable server (chip above) is a
                // real problem to fix. No vehicle heartbeat while the
                // server IS reachable is often just "aircraft powered
                // off" — expected during ground testing, not an error.
                child: Text(
                  gcs.isConnected ? 'VEHICLE' : 'NO VEHICLE',
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 1.0,
                    color: gcs.isConnected
                        ? SGTColors.online : SGTColors.warning)),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: drone.isConnected ? SGTColors.onlineBg : SGTColors.dangerBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: drone.isConnected
                      ? const Color(0xFF1a5c35) : const Color(0xFF5a1a1a),
                  width: 0.5),
              ),
              child: Text(
                drone.isConnected ? 'LIVE' : 'OFFLINE',
                style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 1.0,
                  color: drone.isConnected ? SGTColors.online : SGTColors.danger)),

              
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------
// Video feed
// -------------------------------------------------------------------------

class _VideoFeed extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneProvider>();
    final detection = context.watch<DetectionProvider>();
    
    final gemini = context.watch<GeminiProvider>();



    return Container(
      
      color: SGTColors.navyDeep,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (detection.currentFrameBase64 != null)
            Image.memory(
              base64Decode(detection.currentFrameBase64!),
              fit: BoxFit.cover,
              gaplessPlayback: true,
            )
          else
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('CAMERA FEED',
                    style: TextStyle(
                      color: const Color(0xFF8C98A8), fontSize: 11, letterSpacing: 2.0)),
                  const SizedBox(height: 6),
                  Text(
                    detection.isDetecting
                        ? 'Connecting to detection server...'
                        : 'Run detector.py then press START DETECT',
                    style: const TextStyle(color: const Color(0xFF8C98A8), fontSize: 10)),
                ],
              ),
            ),
          Positioned(
            top: 14,
            right: 14,
            child: _GeminiPanel(gemini: gemini),
          ),
          ..._cornerBrackets(),
          Positioned(
            bottom: 10, left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: SGTColors.navyDeep.withOpacity(0.7),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                detection.isDetecting
                    ? detection.statusMessage : drone.statusMessage,
                style: const TextStyle(color: const Color(0xFFB8C1CE), fontSize: 10)),
            )),
          if (drone.isConnected)
            Positioned(
              top: 10, right: 14,
              child: Row(
                children: [
                  Container(
                    width: 7, height: 7,
                    decoration: const BoxDecoration(
                      color: SGTColors.danger, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  const Text('REC',
                    style: TextStyle(
                      color: SGTColors.danger, fontSize: 9, letterSpacing: 1.0)),
                ],
              )),
          Positioned(
            bottom: 10, right: 14,
            child: GestureDetector(
              onTap: () {
                if (detection.isDetecting) {
                  detection.disconnect();
                } else {
                  detection.connect();
                }
              },
              
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: detection.isDetecting
                      ? SGTColors.onlineBg : SGTColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: detection.isDetecting
                        ? SGTColors.online : SGTColors.border,
                    width: 0.5),
                ),
                child: Text(
                  detection.isDetecting ? 'STOP DETECT' : 'START DETECT',
                  style: TextStyle(
                    fontSize: 9, letterSpacing: 1.0,
                    color: detection.isDetecting
                        ? SGTColors.online : SGTColors.textSecondary)),
              ),
            )),
        ],
      ),
    );
  }

  List<Widget> _cornerBrackets() {
    const color = Color(0xFF1e3a6a);
    const size = 14.0;
    const offset = 10.0;
    return [
      Positioned(top: offset, left: offset,
        child: _Bracket(size: size, color: color, top: true, left: true)),
      Positioned(top: offset, right: offset,
        child: _Bracket(size: size, color: color, top: true, left: false)),
      Positioned(bottom: offset, left: offset,
        child: _Bracket(size: size, color: color, top: false, left: true)),
      Positioned(bottom: offset, right: offset,
        child: _Bracket(size: size, color: color, top: false, left: false)),
    ];
  }
}

class _Bracket extends StatelessWidget {
  final double size;
  final Color color;
  final bool top, left;
  const _Bracket({required this.size, required this.color,
    required this.top, required this.left});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size, height: size,
    child: CustomPaint(painter: _BracketPainter(color, top, left)));
}

class _BracketPainter extends CustomPainter {
  final Color color;
  final bool top, left;
  _BracketPainter(this.color, this.top, this.left);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1.0..style = PaintingStyle.stroke;
    final path = Path();
    if (top && left) {
      path.moveTo(0, size.height); path.lineTo(0, 0); path.lineTo(size.width, 0);
    } else if (top && !left) {
      path.moveTo(0, 0); path.lineTo(size.width, 0); path.lineTo(size.width, size.height);
    } else if (!top && left) {
      path.moveTo(0, 0); path.lineTo(0, size.height); path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, size.height); path.lineTo(size.width, size.height); path.lineTo(size.width, 0);
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
      (label: 'ALT', value: drone.altitude.toStringAsFixed(1), unit: 'm'),
      (label: 'SPD', value: drone.speed.toStringAsFixed(1), unit: 'm/s'),
      (label: 'BAT', value: '${drone.batteryLevel}', unit: '%'),
      (label: 'GPS', value: '${drone.gpsSatellites}', unit: 'sats'),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: SGTColors.surface,
        border: Border.symmetric(
          horizontal: BorderSide(color: SGTColors.border, width: 0.5)),
      ),
      child: Row(
        children: cells.map((cell) {
          final isBatLow = cell.label == 'BAT' && drone.batteryLevel <= 20;
          return Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: SGTColors.border, width: 0.5))),
              child: Column(
                children: [
                  Text(cell.label,
                    style: const TextStyle(
                      fontSize: 9, color: const Color(0xFF8C98A8), letterSpacing: 1.2)),
                  const SizedBox(height: 3),
                  Text(cell.value,
                    style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600,
                      color: isBatLow ? SGTColors.danger : SGTColors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()])),
                  Text(cell.unit,
                    style: const TextStyle(fontSize: 9, color: const Color(0xFF8C98A8))),
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
// Alert panel — tiered by level
// -------------------------------------------------------------------------

class _AlertPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final detection = context.watch<DetectionProvider>();
    if (detection.activeAlerts.isEmpty) return const SizedBox.shrink();

    // Split by level
    final critical = detection.activeAlerts.where((a) => a.isCritical).toList();
    final alertLevel = detection.activeAlerts.where((a) => a.isAlert).toList();
    final watch = detection.activeAlerts.where((a) => a.isWatch).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('ALERTS',
              style: TextStyle(
                fontSize: 9, color: const Color(0xFF8C98A8), letterSpacing: 1.5)),
            const Spacer(),
            GestureDetector(
              onTap: detection.clearAllAlerts,
              child: const Text('CLEAR ALL',
                style: TextStyle(
                  fontSize: 9, color: const Color(0xFF8C98A8), letterSpacing: 1.0))),
          ],
        ),
        const SizedBox(height: 8),

        // Critical first
        ...critical.map((a) => _AlertCard(alert: a)),

        // Then alert level
        ...alertLevel.map((a) => _AlertCard(alert: a)),

        // Then watch
        ...watch.map((a) => _AlertCard(alert: a)),

        const SizedBox(height: 4),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  final DetectionAlert alert;
  const _AlertCard({required this.alert});

  Color get _levelColor {
    switch (alert.level) {
      case AlertLevel.critical: return SGTColors.danger;
      case AlertLevel.alert: return SGTColors.warning;
      case AlertLevel.watch: return SGTColors.blue;
      case AlertLevel.log: return SGTColors.textMuted;
    }
  }

  Color get _levelBg {
    switch (alert.level) {
      case AlertLevel.critical: return SGTColors.dangerBg;
      case AlertLevel.alert: return const Color(0xFF2a1f00);
      case AlertLevel.watch: return const Color(0xFF0d1a2a);
      case AlertLevel.log: return SGTColors.surface;
    }
  }

  Color get _levelBorder {
    switch (alert.level) {
      case AlertLevel.critical: return const Color(0xFF5a1a1a);
      case AlertLevel.alert: return const Color(0xFF5a3a00);
      case AlertLevel.watch: return const Color(0xFF1a3a5a);
      case AlertLevel.log: return SGTColors.border;
    }
  }

  @override
  Widget build(BuildContext context) {
    final detection = context.read<DetectionProvider>();
    final drone = context.read<DroneProvider>();
    final result = alert.engineResult;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _levelBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _levelBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _levelColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: _levelColor, width: 0.5),
                ),
                child: Text(
                  alert.levelLabel,
                  style: TextStyle(
                    fontSize: 9, color: _levelColor,
                    fontWeight: FontWeight.w600, letterSpacing: 1.0)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(result.title,
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500,
                    color: _levelColor)),
              ),
              Text(alert.timeString,
                style: const TextStyle(
                  fontSize: 10, color: const Color(0xFF8C98A8),
                  fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
          const SizedBox(height: 5),

          // Description
          Text(result.description,
            style: const TextStyle(fontSize: 11, color: const Color(0xFFB8C1CE))),

          // GPS if available
          if (alert.latitude != null) ...[
            const SizedBox(height: 4),
            Text(
              'GPS: ${alert.latitude!.toStringAsFixed(5)}, ${alert.longitude!.toStringAsFixed(5)}',
              style: const TextStyle(fontSize: 10, color: const Color(0xFF8C98A8))),
          ],

          // Action label
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              result.actionLabel.toUpperCase(),
              style: TextStyle(
                fontSize: 9, color: _levelColor.withOpacity(0.7),
                letterSpacing: 1.0)),
          ),

          // Action buttons
          Row(
            children: [
              // Call authorities — only on alert/critical
              if (result.showCallAuthorities)
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      detection.markReportedToAuthorities(alert.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Authorities notified — TODO: wire up real call'),
                          backgroundColor: SGTColors.danger,
                        ));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: SGTColors.danger.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: SGTColors.danger, width: 0.5),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.local_police_outlined, size: 12, color: SGTColors.danger),
                          SizedBox(width: 6),
                          Text('CALL AUTHORITIES',
                            style: TextStyle(
                              fontSize: 10, letterSpacing: 0.8,
                              color: SGTColors.danger, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                ),

              if (result.showCallAuthorities && result.showDispatchDrone)
                const SizedBox(width: 8),

              // Dispatch drone — on alert/critical
              if (result.showDispatchDrone)
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      detection.markDroneDispatched(alert.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Drone dispatching to location — TODO: wire up flight command'),
                        ));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: SGTColors.blue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: SGTColors.blue, width: 0.5),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.flight, size: 12, color: SGTColors.blue),
                          SizedBox(width: 6),
                          Text('DISPATCH DRONE',
                            style: TextStyle(
                              fontSize: 10, letterSpacing: 0.8,
                              color: SGTColors.blue, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                ),

              // Escalate button for watch level
              if (alert.isWatch) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () => detection.operatorEscalate(
                      alert.id,
                      lat: drone.latitude,
                      lng: drone.longitude,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: SGTColors.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: SGTColors.warning, width: 0.5),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.arrow_upward, size: 12, color: SGTColors.warning),
                          SizedBox(width: 6),
                          Text('ESCALATE',
                            style: TextStyle(
                              fontSize: 10, letterSpacing: 0.8,
                              color: SGTColors.warning, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              // Pattern candidates (recurring presence / unusual vehicle
              // frequency) get a distinct verify flow instead of plain
              // confirm/dismiss — AI surfaced a pattern, human judges it.
              if (result.isPatternCandidate) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      detection.verifyThreat(alert.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Verified as threat — drone re-tasking to this zone'),
                          backgroundColor: SGTColors.danger,
                        ));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: SGTColors.danger.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: SGTColors.danger, width: 0.5),
                      ),
                      child: const Text('VERIFY AS THREAT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10, letterSpacing: 0.6, fontWeight: FontWeight.w500,
                          color: SGTColors.danger)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => detection.notAConcern(alert.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: SGTColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: SGTColors.border, width: 0.5),
                      ),
                      child: const Text('NOT A CONCERN',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10, letterSpacing: 0.6, color: const Color(0xFFB8C1CE))),
                    ),
                  ),
                ),
              ] else ...[
                // Confirm — positive training signal for a normal detection
                GestureDetector(
                  onTap: () {
                    detection.confirmAlert(alert.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Confirmed — logged for retraining')));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: SGTColors.online.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: SGTColors.online, width: 0.5),
                    ),
                    child: const Text('CONFIRM',
                      style: TextStyle(
                        fontSize: 10, letterSpacing: 0.8, fontWeight: FontWeight.w500,
                        color: SGTColors.online)),
                  ),
                ),
                const SizedBox(width: 8),

                // Dismiss — false alarm, negative training signal
                GestureDetector(
                  onTap: () => detection.dismissAlert(alert.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: SGTColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: SGTColors.border, width: 0.5),
                    ),
                    child: const Text('DISMISS',
                      style: TextStyle(
                        fontSize: 10, letterSpacing: 0.8, color: const Color(0xFFB8C1CE))),
                  ),
                ),
              ],
            ],
          ),
        ],
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
      MissionState.holding => 'INVESTIGATING',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ACTIVE MISSION',
          style: TextStyle(fontSize: 9, color: const Color(0xFF8C98A8), letterSpacing: 1.5)),
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
                    const Text('Farm perimeter — north',
                      style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: const Color(0xFFF3F6FA))),
                    const SizedBox(height: 4),
                    Text(
                      mission.state == MissionState.executing
                          ? 'Waypoint ${mission.currentWaypoint} / ${mission.totalWaypoints}'
                          : '4 waypoints · 5 m/s',
                      style: const TextStyle(fontSize: 11, color: const Color(0xFF8C98A8))),
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
                child: Text(statusLabel,
                  style: TextStyle(
                    fontSize: 10, color: statusColor,
                    letterSpacing: 0.8, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(mission.statusMessage,
          style: const TextStyle(fontSize: 11, color: const Color(0xFFB8C1CE))),
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
            Expanded(child: _SGTButton(
              label: 'UPLOAD', icon: Icons.upload_outlined,
              enabled: drone.isConnected && mission.canUpload,
              
              onTap: () => mission.uploadMission(
                              drone.useMock
                                  ? PatrolRoute.defaultRoute
                                  : PatrolRoute.relativeToPosition(drone.latitude, drone.longitude),
                              useMock: drone.useMock,
                              drone: drone,
                            ),
                
            )),
            const SizedBox(width: 8),
            Expanded(child: _SGTButton(
              label: 'START PATROL', icon: Icons.play_arrow_outlined,
              enabled: drone.isConnected && mission.canStart,
              onTap: () => mission.startMission(useMock: drone.useMock, drone: drone),
              
            )),
            const SizedBox(width: 8),
            Expanded(child: _SGTButton(
              label: 'STOP', icon: Icons.stop_outlined,
              enabled: drone.isConnected && mission.canStop,
              
              onTap: () => mission.stopMission(useMock: drone.useMock, drone: drone),
            )),
          ],
        ),
        Row(
          children: [
            Expanded(child: _SGTButton(
              label: 'ARM',
              icon: Icons.lock_open_outlined,
              enabled: drone.isConnected,
              onTap: () => drone.arm(),
            )),
            const SizedBox(width: 8),
            Expanded(child: _SGTButton(
              label: 'TAKEOFF',
              icon: Icons.flight_takeoff_outlined,
              enabled: drone.isConnected,
              onTap: () => drone.takeoff(altitude: 10.0),
            )),
          ],
        ),
        //const SizedBox(height: 8),

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

  const _SGTButton({required this.label, required this.icon,
    required this.enabled, required this.onTap});

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
            color: enabled ? SGTColors.borderLight : SGTColors.border, width: 0.5),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18,
              color: enabled ? SGTColors.textPrimary : SGTColors.textMuted),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(
              fontSize: 9, letterSpacing: 1.0, fontWeight: FontWeight.w500,
              color: enabled ? SGTColors.textPrimary : SGTColors.textMuted)),
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
    final detection = context.read<DetectionProvider>();

    return GestureDetector(
      onTap: drone.isConnected
          ? () {
              // (0.0, 0.0) means no GPS fix yet — still trigger the
              // alert, just don't dispatch to a meaningless coordinate.
              final hasFix = drone.latitude != 0.0 || drone.longitude != 0.0;

              // triggerPanic logs the alert AND, if it has a real fix,
              // fires onPanicDispatchRequested — wired in main.dart to
              // mission.dispatchToPanic(), which interrupts whatever
              // the drone is currently doing (patrol, investigate hold)
              // and holds indefinitely until the operator resumes.
              detection.triggerPanic(
                lat: hasFix ? drone.latitude : null,
                lng: hasFix ? drone.longitude : null,
              );

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(hasFix
                      ? 'Panic triggered. Drone dispatching to location'
                      : 'Panic triggered. Alert logged — no GPS fix yet, drone not dispatched'),
                  backgroundColor: SGTColors.danger,
                ));
            }
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
            Icon(Icons.crisis_alert, size: 16,
              color: drone.isConnected
                  ? SGTColors.danger : SGTColors.danger.withOpacity(0.4)),
            const SizedBox(width: 8),
            Text('PANIC - DISPATCH DRONE',
              style: TextStyle(
                fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w500,
                color: drone.isConnected
                    ? SGTColors.danger : SGTColors.danger.withOpacity(0.4))),
          ],
        ),
      ),
    );
  }
}

class _GeminiPanel extends StatelessWidget {
  final GeminiProvider gemini;

  const _GeminiPanel({
    required this.gemini,
  });

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'CONCERNING':
        return Colors.redAccent;
      case 'WATCH':
        return Colors.orangeAccent;
      default:
        return Colors.greenAccent;
    }
  }

  Color _riskColor(String risk) {
    switch (risk.toUpperCase()) {
      case 'HIGH':
        return Colors.redAccent;
      case 'MEDIUM':
        return Colors.orangeAccent;
      default:
        return Colors.greenAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(gemini.sceneStatus);
    final riskColor = _riskColor(gemini.riskLevel);

    return Container(
      width: 285,
      constraints: const BoxConstraints(
        maxHeight: 285,
      ),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xE8101828),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withOpacity(0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: gemini.isConnected
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'GEMINI AI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                gemini.isConnected ? 'LIVE' : 'OFFLINE',
                style: TextStyle(
                  color: gemini.isConnected
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              const Text(
                'SCENE',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                gemini.sceneStatus,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 7),

          Row(
            children: [
              const Text(
                'RISK',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                gemini.riskLevel,
                style: TextStyle(
                  color: riskColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              _GeminiMetric(
                label: 'PEOPLE',
                value: '${gemini.peopleCount}',
              ),
              const SizedBox(width: 18),
              _GeminiMetric(
                label: 'VEHICLES',
                value: '${gemini.vehicleCount}',
              ),
              const SizedBox(width: 18),
              _GeminiMetric(
                label: 'CONF',
                value: '${(gemini.confidence * 100).round()}%',
              ),
            ],
          ),

          if (gemini.interaction != 'NONE' ||
              gemini.concern != 'NONE') ...[
            const SizedBox(height: 10),
            Text(
              gemini.interaction != 'NONE'
                  ? gemini.interaction
                  : gemini.concern,
              style: TextStyle(
                color: riskColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],

          const SizedBox(height: 10),

          Text(
            gemini.summary,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}


class _GeminiMetric extends StatelessWidget {
  final String label;
  final String value;

  const _GeminiMetric({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 8,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
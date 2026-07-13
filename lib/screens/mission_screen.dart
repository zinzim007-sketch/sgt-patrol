import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../theme/theme.dart';
import '../providers/drone_provider.dart';
import '../providers/mission_provider.dart';
import '../models/patrol_route.dart';

class MissionScreen extends StatefulWidget {
  const MissionScreen({super.key});

  @override
  State<MissionScreen> createState() => _MissionScreenState();
}

class _MissionScreenState extends State<MissionScreen> {
  final MapController _mapController = MapController();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneProvider>();
    final mission = context.watch<MissionProvider>();

    // Use real GPS if connected, else default Cape Town
    final centerLat = drone.latitude != 0.0 ? drone.latitude : -33.919;
    final centerLng = drone.longitude != 0.0 ? drone.longitude : 18.423;

    // Get the active route
    final route = drone.useMock
        ? PatrolRoute.defaultRoute
        : PatrolRoute.relativeToPosition(drone.latitude, drone.longitude);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MISSION MAP'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: LatLng(centerLat, centerLng),
                    initialZoom: 16,
                  ),
                  children: [
                    // Satellite tile layer
                    TileLayer(
                      urlTemplate:
                          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                      userAgentPackageName: 'com.sgt.patrol',
                    ),

                    // Patrol route polygon
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: route.waypoints
                              .map((w) => LatLng(w.latitude, w.longitude))
                              .toList(),
                          color: const Color(0x2200FF88),
                          borderColor: const Color(0xFF00FF88),
                          borderStrokeWidth: 2,
                        ),
                      ],
                    ),

                    // Waypoint markers
                    MarkerLayer(
                      markers: [
                        // Patrol waypoints
                        ...route.waypoints.asMap().entries.map((e) {
                          final isCurrent = mission.state == MissionState.executing &&
                              mission.currentWaypoint == e.key + 1;
                          return Marker(
                            point: LatLng(e.value.latitude, e.value.longitude),
                            width: 24,
                            height: 24,
                            child: Container(
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? SGTColors.blue
                                    : SGTColors.blue.withOpacity(0.3),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: SGTColors.blueLight,
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '${e.key + 1}',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),

                        // Drone marker
                        if (drone.latitude != 0.0 && drone.longitude != 0.0)
                          Marker(
                            point: LatLng(drone.latitude, drone.longitude),
                            width: 32,
                            height: 32,
                            child: const Icon(
                              Icons.flight,
                              color: SGTColors.online,
                              size: 24,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                // Waypoint list overlay
                Positioned(
                  top: 12,
                  left: 12,
                  child: _WaypointList(route: route),
                ),

                // Live GPS overlay
                if (drone.isConnected)
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: SGTColors.surface.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: SGTColors.border, width: 0.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${drone.latitude.toStringAsFixed(5)}, ${drone.longitude.toStringAsFixed(5)}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: SGTColors.textSecondary,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'ALT ${drone.altitude.toStringAsFixed(1)}m',
                            style: const TextStyle(
                              fontSize: 10,
                              color: SGTColors.blueMuted,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _MissionControls(),
        ],
      ),
    );
  }
}

class _WaypointList extends StatelessWidget {
  final PatrolRoute route;
  const _WaypointList({required this.route});

  @override
  Widget build(BuildContext context) {
    final mission = context.watch<MissionProvider>();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SGTColors.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: SGTColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            route.name.toUpperCase(),
            style: const TextStyle(
              fontSize: 9,
              color: SGTColors.textMuted,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          ...route.waypoints.asMap().entries.map((e) {
            final isCurrent = mission.state == MissionState.executing &&
                mission.currentWaypoint == e.key + 1;

            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? SGTColors.blue.withOpacity(0.5)
                          : SGTColors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: isCurrent ? SGTColors.blueLight : SGTColors.blue,
                        width: isCurrent ? 1.0 : 0.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${e.key + 1}',
                        style: TextStyle(
                          fontSize: 9,
                          color: isCurrent
                              ? SGTColors.textPrimary
                              : SGTColors.blueMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${e.value.latitude.toStringAsFixed(4)}, ${e.value.longitude.toStringAsFixed(4)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: isCurrent
                          ? SGTColors.textPrimary
                          : SGTColors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (isCurrent) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.flight, size: 10, color: SGTColors.blueMuted),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _MissionControls extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneProvider>();
    final mission = context.watch<MissionProvider>();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: SGTColors.surface,
        border: Border(top: BorderSide(color: SGTColors.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mission.statusMessage,
            style: const TextStyle(fontSize: 11, color: SGTColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MissionBtn(
                  label: 'UPLOAD',
                  enabled: drone.isConnected && mission.canUpload,
                  onTap: () => mission.uploadMission(
                    drone.useMock
                        ? PatrolRoute.defaultRoute
                        : PatrolRoute.relativeToPosition(
                            drone.latitude, drone.longitude),
                    useMock: drone.useMock,
                    drone: drone,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MissionBtn(
                  label: 'START',
                  enabled: drone.isConnected && mission.canStart,
                  primary: true,
                  onTap: () => mission.startMission(
                    useMock: drone.useMock,
                    drone: drone,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MissionBtn(
                  label: 'STOP',
                  enabled: drone.isConnected && mission.canStop,
                  onTap: () => mission.stopMission(
                    useMock: drone.useMock,
                    drone: drone,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MissionBtn extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool primary;
  final VoidCallback onTap;

  const _MissionBtn({
    required this.label,
    required this.enabled,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: primary && enabled ? SGTColors.blue : SGTColors.navyLight,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: enabled ? SGTColors.borderLight : SGTColors.border,
            width: 0.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w500,
              color: enabled ? SGTColors.textPrimary : SGTColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
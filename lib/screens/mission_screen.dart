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

  // Custom waypoints drawn by operator — empty means use default route
  final List<PatrolWaypoint> _customWaypoints = [];
  bool _drawingMode = false;
  double _waypointAltitude = 20.0;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (!_drawingMode) return;
    setState(() {
      _customWaypoints.add(PatrolWaypoint(
        latitude: point.latitude,
        longitude: point.longitude,
        altitude: _waypointAltitude,
      ));
    });
  }

  void _removeWaypoint(int index) {
    setState(() {
      _customWaypoints.removeAt(index);
    });
  }

  void _clearWaypoints() {
    setState(() {
      _customWaypoints.clear();
    });
  }

  PatrolRoute get _activeRoute {
    if (_customWaypoints.isNotEmpty) {
      return PatrolRoute(
        name: 'Custom patrol route',
        waypoints: _customWaypoints,
      );
    }
    final drone = context.read<DroneProvider>();
    return drone.useMock
        ? PatrolRoute.defaultRoute
        : PatrolRoute.relativeToPosition(drone.latitude, drone.longitude);
  }

  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneProvider>();
    final mission = context.watch<MissionProvider>();

    final centerLat = drone.latitude != 0.0 ? drone.latitude : -33.919;
    final centerLng = drone.longitude != 0.0 ? drone.longitude : 18.423;
    final route = _activeRoute;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MISSION MAP'),
        actions: [
          // Drawing mode toggle
          GestureDetector(
            onTap: () => setState(() => _drawingMode = !_drawingMode),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _drawingMode ? SGTColors.blue : SGTColors.surfaceRaised,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _drawingMode ? SGTColors.blueLight : SGTColors.border,
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _drawingMode ? Icons.edit_location : Icons.edit_location_outlined,
                    size: 14,
                    color: _drawingMode ? Colors.white : SGTColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _drawingMode ? 'DRAWING' : 'DRAW',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.0,
                      color: _drawingMode ? Colors.white : SGTColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Clear waypoints
          if (_customWaypoints.isNotEmpty)
            GestureDetector(
              onTap: _clearWaypoints,
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: SGTColors.dangerBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: SGTColors.danger, width: 0.5),
                ),
                child: const Text(
                  'CLEAR',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.0,
                    color: SGTColors.danger,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Drawing mode banner
          if (_drawingMode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: SGTColors.blue.withOpacity(0.15),
              child: Row(
                children: [
                  const Icon(Icons.touch_app, size: 14, color: SGTColors.blueMuted),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Tap the map to add waypoints. Tap a waypoint number to remove it.',
                      style: TextStyle(fontSize: 10, color: SGTColors.textSecondary),
                    ),
                  ),
                  // Altitude control
                  Row(
                    children: [
                      const Text('ALT:', style: TextStyle(fontSize: 9, color: SGTColors.textMuted)),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => setState(() => _waypointAltitude = (_waypointAltitude - 5).clamp(5, 120)),
                        child: const Icon(Icons.remove_circle_outline, size: 16, color: SGTColors.blueMuted),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '${_waypointAltitude.toInt()}m',
                          style: const TextStyle(fontSize: 10, color: SGTColors.textPrimary),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _waypointAltitude = (_waypointAltitude + 5).clamp(5, 120)),
                        child: const Icon(Icons.add_circle_outline, size: 16, color: SGTColors.blueMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: LatLng(centerLat, centerLng),
                    initialZoom: 16,
                    onTap: _onMapTap,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      //urlTemplate:
                          //'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                      userAgentPackageName: 'com.sgt.patrol',
                    ),

                    // Patrol route polygon — only show when 3+ waypoints
                    if (route.waypoints.length >= 3)
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

                    // Route line — connects waypoints in order
                    if (route.waypoints.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: <LatLng>[
                              ...route.waypoints.map((w) => LatLng(w.latitude, w.longitude)),
                              // Close the loop back to first waypoint
                              if (route.waypoints.length >= 3)
                                LatLng(route.waypoints.first.latitude, route.waypoints.first.longitude),
                            ],
                            color: const Color(0xFF00FF88),
                            strokeWidth: 1.5,
                            //isDotted: _customWaypoints.isNotEmpty,
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
                          final isCustom = _customWaypoints.isNotEmpty;

                          return Marker(
                            point: LatLng(e.value.latitude, e.value.longitude),
                            width: 28,
                            height: 28,
                            child: GestureDetector(
                              onTap: isCustom
                                  ? () => _removeWaypoint(e.key)
                                  : null,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? SGTColors.blue
                                      : isCustom
                                          ? SGTColors.blue.withOpacity(0.8)
                                          : SGTColors.blue.withOpacity(0.3),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isCustom ? SGTColors.blueLight : SGTColors.blue,
                                    width: isCustom ? 1.5 : 1,
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
                  child: _WaypointList(
                    route: route,
                    isCustom: _customWaypoints.isNotEmpty,
                    onRemove: _removeWaypoint,
                  ),
                ),

                // Live GPS overlay
                if (drone.isConnected)
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
          _MissionControls(activeRoute: _activeRoute),
        ],
      ),
    );
  }
}

class _WaypointList extends StatelessWidget {
  final PatrolRoute route;
  final bool isCustom;
  final void Function(int index)? onRemove;

  const _WaypointList({
    required this.route,
    required this.isCustom,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final mission = context.watch<MissionProvider>();

    return Container(
      padding: const EdgeInsets.all(10),
      constraints: const BoxConstraints(maxWidth: 220),
      decoration: BoxDecoration(
        color: SGTColors.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: SGTColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  route.name.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9,
                    color: SGTColors.textMuted,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (isCustom)
                const Text(
                  'TAP TO REMOVE',
                  style: TextStyle(fontSize: 8, color: SGTColors.danger),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (route.waypoints.isEmpty)
            const Text(
              'Tap the map to add waypoints',
              style: TextStyle(fontSize: 9, color: SGTColors.textMuted),
            )
          else
            ...route.waypoints.asMap().entries.map((e) {
              final isCurrent = mission.state == MissionState.executing &&
                  mission.currentWaypoint == e.key + 1;

              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: isCustom ? () => onRemove?.call(e.key) : null,
                      child: Container(
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
  final PatrolRoute activeRoute;
  const _MissionControls({required this.activeRoute});

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
                  enabled: drone.isConnected && mission.canUpload && activeRoute.waypoints.isNotEmpty,
                  onTap: () => mission.uploadMission(
                    activeRoute,
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
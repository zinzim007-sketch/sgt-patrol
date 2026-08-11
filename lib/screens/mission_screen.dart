import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../theme/theme.dart';
import '../providers/drone_provider.dart';
import '../providers/mission_provider.dart';
import '../providers/route_provider.dart';
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

  // ---------------------------------------------------------------------
  // Save / load saved routes
  // ---------------------------------------------------------------------

  Future<void> _saveCurrentRoute() async {
    if (_customWaypoints.isEmpty) return;
    final nameController = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SGTColors.surface,
        title: const Text('Save patrol route'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: SGTColors.textPrimary),
          decoration: const InputDecoration(hintText: 'e.g. North fence line'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;
    if (!mounted) return;

    await context.read<RouteProvider>().saveRoute(name, _customWaypoints);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved "$name"')),
      );
    }
  }

  void _showSavedRoutesSheet() {
    final routeProvider = context.read<RouteProvider>();

    showModalBottomSheet(
      context: context,
      backgroundColor: SGTColors.surface,
      builder: (ctx) {
        return Consumer<RouteProvider>(
          builder: (ctx, provider, _) {
            final routes = provider.savedRoutes;
            if (routes.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No saved routes yet.',
                  style: TextStyle(color: SGTColors.textSecondary),
                ),
              );
            }
            return ListView(
              shrinkWrap: true,
              children: routes.map((r) {
                return ListTile(
                  title: Text(
                    r.name,
                    style: const TextStyle(color: SGTColors.textPrimary),
                  ),
                  subtitle: Text(
                    '${r.waypoints.length} waypoints',
                    style: const TextStyle(color: SGTColors.textMuted),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: SGTColors.danger),
                    onPressed: () => routeProvider.deleteRoute(r.id),
                  ),
                  onTap: () {
                    setState(() {
                      _customWaypoints
                        ..clear()
                        ..addAll(r.waypoints);
                    });
                    Navigator.pop(ctx);
                  },
                );
              }).toList(),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneProvider>();
    final mission = context.watch<MissionProvider>();

    final centerLat = drone.latitude != 0.0 ? drone.latitude : -33.919;
    final centerLng = drone.longitude != 0.0 ? drone.longitude : 18.423;
    final route = _activeRoute;

    return Scaffold(
      backgroundColor: SGTColors.navyDeep,
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            const Text(
              'MISSION PLANNER',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: drone.isConnected
                    ? SGTColors.online.withOpacity(0.10)
                    : SGTColors.surfaceRaised,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: drone.isConnected
                      ? SGTColors.online.withOpacity(0.35)
                      : SGTColors.border,
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: drone.isConnected
                          ? SGTColors.online
                          : SGTColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    drone.isConnected ? 'DRONE CONNECTED' : 'NO CONNECTION',
                    style: TextStyle(
                      fontSize: 8,
                      letterSpacing: 1.0,
                      color: drone.isConnected
                          ? SGTColors.online
                          : SGTColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          _MissionToolbarButton(
            icon: _drawingMode
                ? Icons.edit_location
                : Icons.edit_location_outlined,
            label: _drawingMode ? 'DRAWING' : 'DRAW ROUTE',
            active: _drawingMode,
            onTap: () => setState(() => _drawingMode = !_drawingMode),
          ),
          if (_customWaypoints.isNotEmpty)
            _MissionToolbarButton(
              icon: Icons.save_outlined,
              label: 'SAVE',
              onTap: _saveCurrentRoute,
            ),
          _MissionToolbarButton(
            icon: Icons.folder_open_outlined,
            label: 'LOAD',
            onTap: _showSavedRoutesSheet,
          ),
          _MissionToolbarButton(
            icon: Icons.my_location_outlined,
            label: 'TEST HOLD',
            onTap: () {
              final drone = context.read<DroneProvider>();
              if (drone.latitude == 0.0) return;
              drone.reposition(
                lat: drone.latitude + 0.0005,
                lng: drone.longitude,
                alt: 20,
              );
            },
          ),
          if (_customWaypoints.isNotEmpty)
            _MissionToolbarButton(
              icon: Icons.delete_outline,
              label: 'CLEAR',
              danger: true,
              onTap: _clearWaypoints,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_drawingMode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: SGTColors.blue.withOpacity(0.08),
                border: const Border(
                  bottom: BorderSide(
                    color: SGTColors.border,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.touch_app_outlined,
                    size: 15,
                    color: SGTColors.blueMuted,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Drawing mode active — tap the map to add waypoints. Tap a waypoint to remove it.',
                      style: TextStyle(
                        fontSize: 10,
                        color: SGTColors.textSecondary,
                      ),
                    ),
                  ),
                  const Text(
                    'ALTITUDE',
                    style: TextStyle(
                      fontSize: 8,
                      letterSpacing: 1.1,
                      color: SGTColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(
                      () => _waypointAltitude =
                          (_waypointAltitude - 5).clamp(5, 120),
                    ),
                    child: const Icon(
                      Icons.remove_circle_outline,
                      size: 17,
                      color: SGTColors.blueMuted,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '${_waypointAltitude.toInt()} m',
                      style: const TextStyle(
                        fontSize: 10,
                        color: SGTColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(
                      () => _waypointAltitude =
                          (_waypointAltitude + 5).clamp(5, 120),
                    ),
                    child: const Icon(
                      Icons.add_circle_outline,
                      size: 17,
                      color: SGTColors.blueMuted,
                    ),
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
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.sgt.patrol',
                    ),

                    if (route.waypoints.length >= 3)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: route.waypoints
                                .map((w) => LatLng(w.latitude, w.longitude))
                                .toList(),
                            color: const Color(0x16006EFF),
                            borderColor: SGTColors.blue,
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),

                    if (route.waypoints.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: <LatLng>[
                              ...route.waypoints.map(
                                (w) => LatLng(w.latitude, w.longitude),
                              ),
                              if (route.waypoints.length >= 3)
                                LatLng(
                                  route.waypoints.first.latitude,
                                  route.waypoints.first.longitude,
                                ),
                            ],
                            color: SGTColors.blue,
                            strokeWidth: 2.5,
                          ),
                        ],
                      ),

                    MarkerLayer(
                      markers: [
                        ...route.waypoints.asMap().entries.map((e) {
                          final isCurrent =
                              mission.state == MissionState.executing &&
                              mission.currentWaypoint == e.key + 1;
                          final isCustom = _customWaypoints.isNotEmpty;

                          return Marker(
                            point: LatLng(
                              e.value.latitude,
                              e.value.longitude,
                            ),
                            width: 30,
                            height: 30,
                            child: GestureDetector(
                              onTap: isCustom
                                  ? () => _removeWaypoint(e.key)
                                  : null,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? SGTColors.blue
                                      : isCustom
                                          ? SGTColors.blue.withOpacity(0.85)
                                          : SGTColors.navyDeep.withOpacity(0.82),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isCurrent
                                        ? Colors.white
                                        : SGTColors.blue,
                                    width: isCurrent ? 1.5 : 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.25),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    '${e.key + 1}',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),

                        if (drone.latitude != 0.0 &&
                            drone.longitude != 0.0)
                          Marker(
                            point: LatLng(
                              drone.latitude,
                              drone.longitude,
                            ),
                            width: 36,
                            height: 36,
                            child: Container(
                              decoration: BoxDecoration(
                                color: SGTColors.online.withOpacity(0.12),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: SGTColors.online,
                                  width: 1,
                                ),
                              ),
                              child: const Icon(
                                Icons.flight,
                                color: SGTColors.online,
                                size: 21,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                Positioned(
                  top: 16,
                  left: 16,
                  child: _WaypointList(
                    route: route,
                    isCustom: _customWaypoints.isNotEmpty,
                    onRemove: _removeWaypoint,
                  ),
                ),

                Positioned(
                  top: 16,
                  right: 16,
                  child: _MapStatusCard(
                    drone: drone,
                    mission: mission,
                  ),
                ),

                if (drone.isConnected)
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: SGTColors.navyDeep.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: SGTColors.border,
                          width: 0.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'LIVE POSITION',
                            style: TextStyle(
                              fontSize: 7,
                              letterSpacing: 1.2,
                              color: SGTColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${drone.latitude.toStringAsFixed(5)}, '
                            '${drone.longitude.toStringAsFixed(5)}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: SGTColors.textSecondary,
                              fontFeatures: [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'ALT ${drone.altitude.toStringAsFixed(1)} m',
                            style: const TextStyle(
                              fontSize: 9,
                              color: SGTColors.blueMuted,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          _MissionControls(activeRoute: route),
        ],
      ),
    );
  }
}

class _MissionToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool danger;

  const _MissionToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = danger
        ? SGTColors.danger
        : active
            ? Colors.white
            : SGTColors.textSecondary;

    final background = danger
        ? SGTColors.dangerBg
        : active
            ? SGTColors.blue
            : SGTColors.surfaceRaised;

    final border = danger
        ? SGTColors.danger.withOpacity(0.55)
        : active
            ? SGTColors.blueLight
            : SGTColors.border;

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: border, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 8,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapStatusCard extends StatelessWidget {
  final DroneProvider drone;
  final MissionProvider mission;

  const _MapStatusCard({
    required this.drone,
    required this.mission,
  });

  @override
  Widget build(BuildContext context) {
    final executing = mission.state == MissionState.executing;

    return Container(
      width: 190,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: SGTColors.navyDeep.withOpacity(0.92),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: SGTColors.border,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'PATROL ROUTE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: SGTColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: executing
                      ? SGTColors.online
                      : SGTColors.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              const Text(
                'MISSION',
                style: TextStyle(
                  fontSize: 7,
                  letterSpacing: 1.0,
                  color: SGTColors.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                executing ? 'EXECUTING' : mission.state.name.toUpperCase(),
                style: TextStyle(
                  fontSize: 8,
                  letterSpacing: 0.8,
                  color: executing
                      ? SGTColors.online
                      : SGTColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text(
                'WAYPOINT',
                style: TextStyle(
                  fontSize: 7,
                  letterSpacing: 1.0,
                  color: SGTColors.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                mission.totalWaypoints > 0
                    ? '${mission.currentWaypoint} / ${mission.totalWaypoints}'
                    : '—',
                style: const TextStyle(
                  fontSize: 9,
                  color: SGTColors.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
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
      padding: const EdgeInsets.all(11),
      constraints: const BoxConstraints(maxWidth: 235),
      decoration: BoxDecoration(
        color: SGTColors.navyDeep.withOpacity(0.92),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: SGTColors.border,
          width: 0.5,
        ),
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
                    fontSize: 8,
                    color: SGTColors.textMuted,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isCustom)
                const Text(
                  'TAP TO REMOVE',
                  style: TextStyle(
                    fontSize: 7,
                    color: SGTColors.danger,
                    letterSpacing: 0.7,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          if (route.waypoints.isEmpty)
            const Text(
              'Tap the map to add waypoints',
              style: TextStyle(
                fontSize: 9,
                color: SGTColors.textMuted,
              ),
            )
          else
            ...route.waypoints.asMap().entries.map((e) {
              final isCurrent =
                  mission.state == MissionState.executing &&
                  mission.currentWaypoint == e.key + 1;

              return Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: isCustom
                          ? () => onRemove?.call(e.key)
                          : null,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? SGTColors.blue
                              : SGTColors.blue.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isCurrent
                                ? SGTColors.blueLight
                                : SGTColors.border,
                            width: 0.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '${e.key + 1}',
                            style: TextStyle(
                              fontSize: 9,
                              color: isCurrent
                                  ? Colors.white
                                  : SGTColors.blueMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${e.value.latitude.toStringAsFixed(4)}, '
                        '${e.value.longitude.toStringAsFixed(4)}',
                        style: TextStyle(
                          fontSize: 9,
                          color: isCurrent
                              ? SGTColors.textPrimary
                              : SGTColors.textSecondary,
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                    if (isCurrent)
                      const Icon(
                        Icons.flight,
                        size: 11,
                        color: SGTColors.blueMuted,
                      ),
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
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      decoration: const BoxDecoration(
        color: SGTColors.surface,
        border: Border(
          top: BorderSide(
            color: SGTColors.border,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MISSION STATUS',
                  style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 1.2,
                    color: SGTColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  mission.statusMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: SGTColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 105,
            child: _MissionBtn(
              icon: Icons.upload_outlined,
              label: 'UPLOAD',
              enabled: drone.isConnected &&
                  mission.canUpload &&
                  activeRoute.waypoints.isNotEmpty,
              onTap: () => mission.uploadMission(
                activeRoute,
                useMock: drone.useMock,
                drone: drone,
              ),
            ),
          ),
          const SizedBox(width: 7),
          SizedBox(
            width: 105,
            child: _MissionBtn(
              icon: Icons.play_arrow,
              label: 'START',
              enabled: drone.isConnected && mission.canStart,
              primary: true,
              onTap: () => mission.startMission(
                useMock: drone.useMock,
                drone: drone,
              ),
            ),
          ),
          const SizedBox(width: 7),
          SizedBox(
            width: 105,
            child: _MissionBtn(
              icon: Icons.stop,
              label: 'STOP',
              enabled: drone.isConnected && mission.canStop,
              danger: mission.canStop,
              onTap: () => mission.stopMission(
                useMock: drone.useMock,
                drone: drone,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final bool primary;
  final bool danger;
  final VoidCallback onTap;

  const _MissionBtn({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.primary = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final background = danger && enabled
        ? SGTColors.dangerBg
        : primary && enabled
            ? SGTColors.blue
            : SGTColors.navyLight;

    final foreground = danger && enabled
        ? SGTColors.danger
        : enabled
            ? SGTColors.textPrimary
            : SGTColors.textMuted;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: danger && enabled
                ? SGTColors.danger.withOpacity(0.45)
                : enabled
                    ? SGTColors.borderLight
                    : SGTColors.border,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

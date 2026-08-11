import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../theme/theme.dart';
import '../providers/route_provider.dart';
import '../models/patrol_route.dart';

class RoutesScreen extends StatelessWidget {
  const RoutesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final routeProvider = context.watch<RouteProvider>();

    return Scaffold(
      backgroundColor: SGTColors.navyDeep,
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text(
          'ROUTES',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
        actions: [
          if (routeProvider.loaded)
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: SGTColors.online,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    'ROUTES LOADED',
                    style: TextStyle(
                      fontSize: 8,
                      letterSpacing: 1.0,
                      color: SGTColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: routeProvider.loaded
          ? _RoutesContent(routes: routeProvider.savedRoutes)
          : const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: SGTColors.blueMuted,
              ),
            ),
    );
  }
}

class _RoutesContent extends StatelessWidget {
  final List<PatrolRoute> routes;

  const _RoutesContent({required this.routes});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            wide ? 42 : 20,
            28,
            wide ? 42 : 20,
            36,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _RoutesHeader(),
                  const SizedBox(height: 26),

                  if (routes.isEmpty)
                    const _EmptyRoutes()
                  else
                    _RouteGrid(
                      routes: routes,
                      wide: wide,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RoutesHeader extends StatelessWidget {
  const _RoutesHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 1,
              color: SGTColors.blue,
            ),
            const SizedBox(width: 11),
            const Text(
              'PATROL ROUTES',
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.8,
                fontWeight: FontWeight.w600,
                color: SGTColors.blueMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Saved patrol routes.',
          style: TextStyle(
            fontSize: 30,
            height: 1.05,
            fontWeight: FontWeight.w600,
            color: SGTColors.textPrimary,
          ),
        ),
        const SizedBox(height: 9),
        const Text(
          'Manage routes saved by the operator and open the Mission Planner to use them.',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: SGTColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _RouteGrid extends StatelessWidget {
  final List<PatrolRoute> routes;
  final bool wide;

  const _RouteGrid({
    required this.routes,
    required this.wide,
  });

  @override
  Widget build(BuildContext context) {
    if (!wide) {
      return Column(
        children: routes
            .map(
              (route) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RouteCard(route: route),
              ),
            )
            .toList(),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: routes.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 540,
        mainAxisExtent: 230,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemBuilder: (context, index) {
        return _RouteCard(route: routes[index]);
      },
    );
  }
}

class _RouteCard extends StatelessWidget {
  final PatrolRoute route;

  const _RouteCard({required this.route});

  String _dateLabel(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SGTColors.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: SGTColors.border,
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  route.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: SGTColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              PopupMenuButton<String>(
                tooltip: 'Route options',
                color: SGTColors.surfaceRaised,
                icon: const Icon(
                  Icons.more_horiz,
                  size: 20,
                  color: SGTColors.textMuted,
                ),
                onSelected: (value) async {
                  if (value == 'delete') {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: SGTColors.surface,
                        title: const Text(
                          'Delete route?',
                          style: TextStyle(color: SGTColors.textPrimary),
                        ),
                        content: Text(
                          'This will permanently remove "${route.name}" from saved routes.',
                          style: const TextStyle(
                            color: SGTColors.textSecondary,
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('CANCEL'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text(
                              'DELETE',
                              style: TextStyle(color: SGTColors.danger),
                            ),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true && context.mounted) {
                      await context.read<RouteProvider>().deleteRoute(route.id);

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Deleted "${route.name}"'),
                          ),
                        );
                      }
                    }
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: SGTColors.danger,
                        ),
                        SizedBox(width: 8),
                        Text('Delete route'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 15),

          Row(
            children: [
              _RouteStat(
                label: 'WAYPOINTS',
                value: '${route.waypoints.length}',
              ),
              const SizedBox(width: 26),
              _RouteStat(
                label: 'SPEED',
                value: '${route.flightSpeedMs.toStringAsFixed(1)} m/s',
              ),
              const SizedBox(width: 26),
              _RouteStat(
                label: 'CREATED',
                value: _dateLabel(route.createdAt),
              ),
            ],
          ),

          const SizedBox(height: 15),

          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: SGTColors.navyDeep,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: SGTColors.border,
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.route_outlined,
                    size: 16,
                    color: SGTColors.blueMuted,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      route.waypoints.isEmpty
                          ? 'No waypoints'
                          : '${route.waypoints.length} waypoint route',
                      style: const TextStyle(
                        fontSize: 10,
                        color: SGTColors.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    route.waypoints.isEmpty ? '—' : 'READY',
                    style: TextStyle(
                      fontSize: 8,
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w600,
                      color: route.waypoints.isEmpty
                          ? SGTColors.textMuted
                          : SGTColors.online,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: route.waypoints.isEmpty
                      ? null
                      : () => context.go('/mission'),
                  icon: const Icon(
                    Icons.map_outlined,
                    size: 15,
                  ),
                  label: const Text(
                    'OPEN MISSION PLANNER',
                    style: TextStyle(
                      fontSize: 8,
                      letterSpacing: 0.9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SGTColors.textSecondary,
                    disabledForegroundColor: SGTColors.textMuted,
                    side: const BorderSide(
                      color: SGTColors.borderLight,
                      width: 0.5,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
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

class _RouteStat extends StatelessWidget {
  final String label;
  final String value;

  const _RouteStat({
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
            fontSize: 7,
            letterSpacing: 1.1,
            color: SGTColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: SGTColors.textSecondary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _EmptyRoutes extends StatelessWidget {
  const _EmptyRoutes();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 30,
        vertical: 58,
      ),
      decoration: BoxDecoration(
        color: SGTColors.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: SGTColors.border,
          width: 0.6,
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.route_outlined,
            size: 30,
            color: SGTColors.textMuted,
          ),
          const SizedBox(height: 16),
          const Text(
            'NO SAVED ROUTES',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
              color: SGTColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create a patrol route in Mission Planner and save it for future operations.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: SGTColors.textSecondary,
            ),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: () => context.go('/mission'),
            icon: const Icon(Icons.map_outlined, size: 15),
            label: const Text(
              'OPEN MISSION PLANNER',
              style: TextStyle(
                fontSize: 8,
                letterSpacing: 1.0,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: SGTColors.textSecondary,
              side: const BorderSide(
                color: SGTColors.borderLight,
                width: 0.5,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 11,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

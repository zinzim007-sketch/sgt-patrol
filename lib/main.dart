import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import 'theme/theme.dart';
import 'providers/drone_provider.dart';
import 'providers/mission_provider.dart';
import 'providers/detection_provider.dart';
import 'screens/home_screen.dart';
import 'screens/mission_screen.dart';



void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) {      
          final provider = DroneProvider();
          provider.useMock = false;
          provider.connect();
          return provider;
        }),
        ChangeNotifierProvider(create: (_) => MissionProvider()),
        ChangeNotifierProvider(create: (_) => DetectionProvider()),
      ],
      // _ProviderWiring connects DetectionProvider and DroneProvider
      // together once both exist — see class below.
      child: const _ProviderWiring(child: SGTPatrolApp()),
    ),
  );
}

/// Wires cross-provider callbacks once, after all providers in the tree
/// above have been created.
///
/// Specifically: when the operator verifies a recurring-presence pattern
/// (loitering / unusual vehicle frequency) as a real threat in
/// DetectionProvider, that hands off to DroneProvider.focusOn() so the
/// drone re-tasks toward that zone. Without this wiring, verifyThreat()
/// still logs the confirmation correctly — it just won't move the drone.
class _ProviderWiring extends StatefulWidget {
  final Widget child;
  const _ProviderWiring({required this.child});

  @override
  State<_ProviderWiring> createState() => _ProviderWiringState();
}

class _ProviderWiringState extends State<_ProviderWiring> {
  bool _wired = false;

  @override
  Widget build(BuildContext context) {
    if (!_wired) {
      final detection = context.read<DetectionProvider>();
      final drone = context.read<DroneProvider>();

      detection.onFocusRequested = (lat, lng, reason) {
        drone.focusOn(lat: lat, lng: lng, reason: reason);
      };

      _wired = true;
    }
    return widget.child;
  }
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
        GoRoute(path: '/mission', builder: (_, __) => const MissionScreen()),
        GoRoute(path: '/routes', builder: (_, __) => const RoutesScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      ],
    ),
  ],
);

class SGTPatrolApp extends StatelessWidget {
  const SGTPatrolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SGT Patrol',
      debugShowCheckedModeBanner: false,
      theme: SGTTheme.dark,
      routerConfig: _router,
    );
  }
}

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();

    final navItems = [
      (icon: Icons.flight, label: 'FLY', path: '/'),
      (icon: Icons.map_outlined, label: 'MISSION', path: '/mission'),
      (icon: Icons.route_outlined, label: 'ROUTES', path: '/routes'),
      (icon: Icons.settings_outlined, label: 'SETTINGS', path: '/settings'),
    ];

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: SGTColors.navyDeep,
          border: Border(top: BorderSide(color: SGTColors.border, width: 0.5)),
        ),
        child: SafeArea(
          child: Row(
            children: navItems.map((item) {
              final isActive = location == item.path;
              return Expanded(
                child: InkWell(
                  onTap: () => context.go(item.path),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(item.icon, size: 20,
                          color: isActive ? SGTColors.blueMuted : SGTColors.textMuted),
                        const SizedBox(height: 4),
                        Text(item.label,
                          style: TextStyle(
                            fontSize: 9, letterSpacing: 1.0, fontWeight: FontWeight.w500,
                            color: isActive ? SGTColors.blueMuted : SGTColors.textMuted,
                          )),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class RoutesScreen extends StatelessWidget {
  const RoutesScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Text('Routes — coming soon')),
  );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Text('Settings — coming soon')),
  );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/theme.dart';

/// Lightweight local authentication for the current prototype.
///
/// IMPORTANT:
/// This is intentionally NOT production authentication.
/// Before deployment, replace this credential map with a real backend
/// authentication service and never ship plaintext passwords in the app.
class OperatorSession extends ChangeNotifier {
  bool _authenticated = false;
  String? _operatorName;
  String? _operatorId;

  bool get isAuthenticated => _authenticated;
  String? get operatorName => _operatorName;
  String? get operatorId => _operatorId;

  void signIn({
    required String operatorId,
    required String operatorName,
  }) {
    _authenticated = true;
    _operatorId = operatorId;
    _operatorName = operatorName;
    notifyListeners();
  }

  void signOut() {
    _authenticated = false;
    _operatorId = null;
    _operatorName = null;
    notifyListeners();
  }
}

/// Prototype credentials.
///
/// Change these before sharing the app with anyone.
/// Production authentication should move to a secure backend.
const Map<String, Map<String, String>> prototypeOperators = {
  'operator01': {
    'password': 'SGT2026',
    'name': 'Operator 01',
  },
  'operator02': {
    'password': 'SGT2026',
    'name': 'Operator 02',
  },
};

class AuthGate extends StatelessWidget {
  final Widget child;

  const AuthGate({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final session = context.watch<OperatorSession>();

    if (!session.isAuthenticated) {
      return const LoginScreen();
    }

    return child;
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _operatorController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isSigningIn = false;
  String? _errorMessage;

  @override
  void dispose() {
    _operatorController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();

    final operatorId = _operatorController.text.trim().toLowerCase();
    final password = _passwordController.text;

    if (operatorId.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Enter your operator ID and password.';
      });
      return;
    }

    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });

    // Small delay keeps the interaction feeling intentional without
    // pretending that a remote server is being contacted.
    await Future<void>.delayed(const Duration(milliseconds: 350));

    if (!mounted) return;

    final account = prototypeOperators[operatorId];

    if (account == null || account['password'] != password) {
      setState(() {
        _isSigningIn = false;
        _errorMessage = 'Invalid operator ID or password.';
      });
      return;
    }

    context.read<OperatorSession>().signIn(
          operatorId: operatorId,
          operatorName: account['name']!,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SGTColors.navyDeep,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 40,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Replace assets/logo.png with the exact logo asset used
                  // by SafeGuard once it is added to the Flutter project.
                  Image.asset(
                    'assets/logo.png',
                    height: 58,
                    width: 240,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) {
                      return const Column(
                        children: [
                          Text(
                            'SAFEGUARD',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 3.0,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'TECHNOLOGIES',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2.5,
                              color: SGTColors.textMuted,
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 34),

                  const Text(
                    'ARGUS',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 7),

                  const Text(
                    'OPERATOR CONTROL SYSTEM',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.8,
                      color: SGTColors.blueMuted,
                    ),
                  ),

                  const SizedBox(height: 30),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      color: SGTColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: SGTColors.border,
                        width: 0.6,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'OPERATOR SIGN IN',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.4,
                            color: Colors.white,
                          ),
                        ),

                        const SizedBox(height: 7),

                        const Text(
                          'Authenticate to access ARGUS operations.',
                          style: TextStyle(
                            fontSize: 11,
                            color: SGTColors.textSecondary,
                          ),
                        ),

                        const SizedBox(height: 24),

                        _LoginField(
                          controller: _operatorController,
                          label: 'OPERATOR ID',
                          hint: 'Enter operator ID',
                          textInputAction: TextInputAction.next,
                          enabled: !_isSigningIn,
                        ),

                        const SizedBox(height: 16),

                        _LoginField(
                          controller: _passwordController,
                          label: 'PASSWORD',
                          hint: 'Enter password',
                          obscureText: _obscurePassword,
                          enabled: !_isSigningIn,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _signIn(),
                          suffix: IconButton(
                            onPressed: _isSigningIn
                                ? null
                                : () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                              color: SGTColors.textMuted,
                            ),
                          ),
                        ),

                        if (_errorMessage != null) ...[
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 15,
                                color: SGTColors.danger,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: SGTColors.danger,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 22),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isSigningIn ? null : _signIn,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: SGTColors.blue,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: SGTColors.navyLight,
                              disabledForegroundColor: SGTColors.textMuted,
                              padding: const EdgeInsets.symmetric(
                                vertical: 13,
                              ),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                            child: _isSigningIn
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.8,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'SIGN IN',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 22),

                        Row(
                          children: [
                            const Expanded(
                              child: Divider(
                                color: SGTColors.border,
                                height: 1,
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                'SYSTEM STATUS',
                                style: TextStyle(
                                  fontSize: 7,
                                  letterSpacing: 1.1,
                                  color: SGTColors.textMuted,
                                ),
                              ),
                            ),
                            const Expanded(
                              child: Divider(
                                color: SGTColors.border,
                                height: 1,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 6,
                              height: 6,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: SGTColors.online,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            SizedBox(width: 7),
                            Text(
                              'OPERATIONAL',
                              style: TextStyle(
                                fontSize: 8,
                                letterSpacing: 1.0,
                                color: SGTColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  const Text(
                    'ARGUS-01  •  SGT-ARGUS001',
                    style: TextStyle(
                      fontSize: 8,
                      letterSpacing: 1.0,
                      color: SGTColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscureText;
  final bool enabled;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  const _LoginField({
    required this.controller,
    required this.label,
    required this.hint,
    this.obscureText = false,
    this.enabled = true,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
            color: SGTColors.textMuted,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          obscureText: obscureText,
          enabled: enabled,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white,
          ),
          cursorColor: SGTColors.blueMuted,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              fontSize: 11,
              color: SGTColors.textMuted,
            ),
            suffixIcon: suffix,
            filled: true,
            fillColor: SGTColors.navyDeep,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 13,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: const BorderSide(
                color: SGTColors.border,
                width: 0.6,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: const BorderSide(
                color: SGTColors.blueMuted,
                width: 0.8,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: const BorderSide(
                color: SGTColors.border,
                width: 0.6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

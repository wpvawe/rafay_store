import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_text_field.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    await auth.signUp(
      name: _name.text.trim(),
      email: _email.text.trim(),
      password: _password.text,
    );
  }

  Future<void> _googleSignIn() async {
    final auth = context.read<AuthProvider>();
    await auth.signInWithGoogle();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(auth.error!), backgroundColor: Colors.red),
        );
        auth.clearError();
      });
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Banner image ────────────────────────────────────────────
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                child: Image.asset(
                  'assets/images/banner.png',
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 200,
                    color: const Color(0xFFD32F2F),
                    child: const Center(
                      child: Icon(Icons.store_rounded,
                          size: 64, color: Colors.white),
                    ),
                  ),
                ),
              ),
              // ── Form card ───────────────────────────────────────────────
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Create account',
                            style: Theme.of(context).textTheme.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Request access to Rafay Store',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),
                          AppTextField(
                            controller: _name,
                            label: 'Full name',
                            prefixIcon: Icons.person_outline,
                            textInputAction: TextInputAction.next,
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            controller: _email,
                            label: 'Email',
                            keyboardType: TextInputType.emailAddress,
                            prefixIcon: Icons.email_outlined,
                            textInputAction: TextInputAction.next,
                            validator: (v) => (v == null || !v.contains('@'))
                                ? 'Enter a valid email'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            controller: _password,
                            label: 'Password',
                            obscureText: !_showPassword,
                            prefixIcon: Icons.lock_outline,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () =>
                                  setState(() => _showPassword = !_showPassword),
                            ),
                            validator: (v) => (v == null || v.length < 6)
                                ? 'At least 6 characters'
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'An admin must approve your account before you can log in.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: auth.isBusy ? null : _submit,
                              child: auth.isBusy
                                  ? const SizedBox.square(
                                      dimension: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Sign Up'),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(child: Divider(color: Colors.grey.shade300)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text('or', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                              ),
                              Expanded(child: Divider(color: Colors.grey.shade300)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 50,
                            child: OutlinedButton.icon(
                              onPressed: auth.isBusy ? null : _googleSignIn,
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.grey.shade300),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                backgroundColor: Colors.white,
                              ),
                              icon: _GoogleLogo(),
                              label: const Text(
                                'Continue with Google',
                                style: TextStyle(
                                    color: Colors.black87, fontSize: 14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Already have an account? '),
                              TextButton(
                                onPressed: () => context.go('/login'),
                                child: const Text('Sign in'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final Paint paint = Paint()..style = PaintingStyle.fill;

    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        -0.523, 1.571, true, paint);
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        1.047, 1.571, true, paint);
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        2.618, 1.047, true, paint);
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        3.665, 1.047, true, paint);

    paint.color = Colors.white;
    canvas.drawCircle(center, radius * 0.55, paint);

    paint.color = const Color(0xFF4285F4);
    final barRect = Rect.fromLTWH(
        center.dx, center.dy - radius * 0.18, radius * 0.95, radius * 0.36);
    canvas.drawRect(barRect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

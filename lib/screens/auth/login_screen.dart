import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    await auth.signIn(email: _email.text.trim(), password: _password.text);
  }

  Future<void> _googleSignIn() async {
    final auth = context.read<AuthProvider>();
    await auth.signInWithGoogle();
  }

  Future<void> _forgotPassword() async {
    final emailCtrl = TextEditingController(text: _email.text.trim());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lock_reset_rounded, color: Color(0xFFD32F2F), size: 22),
            SizedBox(width: 8),
            Text('Reset Password'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your email and we will send a password reset link.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send Link'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final email = emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final auth = context.read<AuthProvider>();
    final ok = await auth.resetPassword(email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Password reset link sent to $email'
              : (auth.error ?? 'Failed to send reset email.'),
        ),
        backgroundColor: ok ? Colors.green.shade700 : Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (ok) auth.clearError();
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
                            'Welcome back',
                            style: Theme.of(context).textTheme.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Sign in to your account',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),
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
                                ? 'Password too short'
                                : null,
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: auth.isBusy ? null : _forgotPassword,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.grey.shade600,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Forgot password?',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
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
                                  : const Text('Sign In'),
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
                                'Sign in with Google',
                                style: TextStyle(
                                    color: Colors.black87, fontSize: 14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("Don't have an account? "),
                              TextButton(
                                onPressed: () => context.go('/signup'),
                                child: const Text('Sign up'),
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

    // Draw quadrants for Google G logo
    paint.color = const Color(0xFF4285F4); // Blue
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        -0.523, 1.571, true, paint);
    paint.color = const Color(0xFF34A853); // Green
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        1.047, 1.571, true, paint);
    paint.color = const Color(0xFFFBBC05); // Yellow
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        2.618, 1.047, true, paint);
    paint.color = const Color(0xFFEA4335); // Red
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        3.665, 1.047, true, paint);

    // White center circle
    paint.color = Colors.white;
    canvas.drawCircle(center, radius * 0.55, paint);

    // G bar
    paint.color = const Color(0xFF4285F4);
    final barRect = Rect.fromLTWH(
        center.dx, center.dy - radius * 0.18, radius * 0.95, radius * 0.36);
    canvas.drawRect(barRect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

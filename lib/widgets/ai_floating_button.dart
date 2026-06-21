import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/admin/ai_chat_screen.dart';

class AiFloatingButton extends StatefulWidget {
  const AiFloatingButton({super.key});
  @override
  State<AiFloatingButton> createState() => _AiFloatingButtonState();
}

class _AiFloatingButtonState extends State<AiFloatingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isAdmin = auth.currentUser?.isAdmin ?? false;
    if (!isAdmin) return const SizedBox.shrink();
    return ScaleTransition(
      scale: _pulseAnim,
      child: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => const AiChatScreen()),
        ),
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
        elevation: 6,
        tooltip: 'AI Assistant (Admin)',
        child: const Icon(Icons.smart_toy_rounded, size: 26),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hourglass_top_rounded,
                  size: 80, color: cs.primary),
              const SizedBox(height: 24),
              Text('Account Pending Approval',
                  style: tt.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Text(
                'Your account has been created successfully. '
                'Please wait for an admin to approve your access.',
                style: tt.bodyMedium
                    ?.copyWith(color: cs.onSurface.withValues(alpha: 0.7)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              OutlinedButton.icon(
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign Out'),
                onPressed: () =>
                    context.read<AuthProvider>().signOut(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

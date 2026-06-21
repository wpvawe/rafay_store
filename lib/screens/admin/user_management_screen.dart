import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/empty_state.dart';

class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fs = context.read<FirestoreService>();

    return Scaffold(
      appBar: AppBar(title: const Text('User Management')),
      body: StreamBuilder<List<UserModel>>(
        stream: fs.watchAllUsers(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snap.data ?? [];
          if (users.isEmpty) {
            return const EmptyState(message: 'No users found.');
          }
          final me = context.read<AuthProvider>().currentUser;
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final u = users[i];
              final isSelf = u.uid == me?.uid;
              return _UserCard(
                user: u,
                isSelf: isSelf,
                onApprove: isSelf
                    ? null
                    : () => fs.updateUserStatus(
                          uid: u.uid,
                          status: AppConstants.statusApproved,
                        ),
                onReject: isSelf
                    ? null
                    : () => fs.updateUserStatus(
                          uid: u.uid,
                          status: AppConstants.statusRejected,
                        ),
                onRoleChange: isSelf
                    ? null
                    : (role) => fs.updateUserRole(uid: u.uid, role: role),
              );
            },
          );
        },
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.isSelf,
    this.onApprove,
    this.onReject,
    this.onRoleChange,
  });

  final UserModel user;
  final bool isSelf;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final void Function(String)? onRoleChange;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue.shade50,
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(user.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 15)),
                          ),
                          if (isSelf) ...[
                            const SizedBox(width: 8),
                            const Chip(
                              label: Text('You',
                                  style: TextStyle(fontSize: 11)),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ],
                      ),
                      Text(user.email,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                _statusChip(user.status),
              ],
            ),
            const SizedBox(height: 12),
            // ── Role selector ──────────────────────────────────
            Row(
              children: [
                const Text('Role: ',
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
                if (isSelf)
                  Chip(
                    label: Text(user.role,
                        style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                  )
                else
                  DropdownButton<String>(
                    value: user.role,
                    isDense: true,
                    underline: const SizedBox(),
                    items: AppConstants.roles
                        .map((r) => DropdownMenuItem(
                              value: r,
                              child: Text(r,
                                  style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (r) {
                      if (r != null) onRoleChange?.call(r);
                    },
                  ),
                const Spacer(),
                // ── Approve/Reject buttons ──────────────────────
                if (!isSelf) ...[
                  if (user.status != AppConstants.statusApproved)
                    TextButton.icon(
                      onPressed: onApprove,
                      icon: const Icon(Icons.check_circle_outline,
                          size: 16, color: Colors.green),
                      label: const Text('Approve',
                          style: TextStyle(color: Colors.green)),
                    )
                  else
                    TextButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.block_rounded,
                          size: 16, color: Colors.red),
                      label: const Text('Revoke',
                          style: TextStyle(color: Colors.red)),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case AppConstants.statusApproved:
        bg = Colors.green.shade50;
        fg = Colors.green.shade700;
        label = 'Approved';
        break;
      case AppConstants.statusRejected:
        bg = Colors.red.shade50;
        fg = Colors.red.shade700;
        label = 'Rejected';
        break;
      default:
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade700;
        label = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

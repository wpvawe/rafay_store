import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum ContactType { whatsapp, phone }

/// Tappable button that either opens WhatsApp or dials a number.
class SupplierContactButton extends StatelessWidget {
  const SupplierContactButton({
    super.key,
    required this.number,
    required this.type,
    this.label,
  });

  final String number;
  final ContactType type;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final isWhatsApp = type == ContactType.whatsapp;
    final icon = isWhatsApp ? Icons.chat_rounded : Icons.call_rounded;
    final color = isWhatsApp ? const Color(0xFF25D366) : Colors.blueAccent;
    final display = label ?? number;

    return InkWell(
      onTap: () => _launch(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              display,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launch(BuildContext context) async {
    final cleaned = number.replaceAll(RegExp(r'\s+'), '');
    final uri = type == ContactType.whatsapp
        ? Uri.parse('https://wa.me/$cleaned')
        : Uri.parse('tel:$cleaned');

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open: $number')),
        );
      }
    }
  }
}

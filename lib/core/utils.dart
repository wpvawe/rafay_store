import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Utility helpers used across the app.
abstract final class AppUtils {
  /// Format a [DateTime] as "26 May 2026, 1:30 PM".
  static String formatDateTime(DateTime dt) =>
      DateFormat('d MMM yyyy, h:mm a').format(dt);

  /// Format a [DateTime] as "26 May 2026".
  static String formatDate(DateTime dt) =>
      DateFormat('d MMM yyyy').format(dt);

  /// Show a styled SnackBar.
  static void showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFB00020) : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Capitalise the first letter of a string.
  static String capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Returns `true` if the string is a valid E.164-ish phone number.
  static bool isValidPhone(String phone) =>
      RegExp(r'^\+?[0-9]{10,15}$').hasMatch(phone.replaceAll(' ', ''));

  /// Returns a WhatsApp deep link for a given number.
  static String whatsappUrl(String number) {
    final clean = number.replaceAll(RegExp(r'[^0-9+]'), '');
    return 'https://wa.me/$clean';
  }

  /// Returns a tel: URI for dialling.
  static String telUrl(String number) => 'tel:$number';
}

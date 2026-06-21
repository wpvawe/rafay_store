import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// Consistent text field used throughout the app.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.validator,
    this.prefixIcon,
    this.obscureText = false,
    this.onChanged,
    this.suffixIcon,
    this.textInputAction,
    this.onFieldSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType keyboardType;
  final int maxLines;
  final String? Function(String?)? validator;
  final IconData? prefixIcon;
  final bool obscureText;
  final void Function(String)? onChanged;
  final Widget? suffixIcon;
  final TextInputAction? textInputAction;
  final void Function(String)? onFieldSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      obscureText: obscureText,
      onChanged: onChanged,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      autofocus: autofocus,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}

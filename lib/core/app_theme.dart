import 'package:flutter/material.dart';
import 'theme.dart';

abstract final class AppTheme {
  static const Color primary = AppColors.primary;
  static const double radius = 12.0;
  static ThemeData light() => appTheme;
}

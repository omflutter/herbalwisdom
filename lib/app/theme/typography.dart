import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class AppTypography {
  static final textTheme = TextTheme(
    displaySmall: GoogleFonts.quicksand(fontSize: 34, fontWeight: FontWeight.w700, color: AppColors.ink),
    headlineSmall: GoogleFonts.quicksand(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.ink),
    titleMedium: GoogleFonts.quicksand(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
    bodyLarge: GoogleFonts.dosis(fontSize: 16, color: AppColors.ink),
    bodyMedium: GoogleFonts.dosis(fontSize: 14, color: AppColors.ink.withOpacity(0.86)),
    labelLarge: GoogleFonts.dosis(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary),
  );
}

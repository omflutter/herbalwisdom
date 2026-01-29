import 'package:flutter/material.dart';

/// A reusable widget for displaying user-friendly error messages throughout the app.
/// Provides a consistent error experience with an icon, title, message, and retry button.
class ErrorView extends StatelessWidget {
  /// Optional title for the error message. Defaults to "Oops! Something went wrong"
  final String? title;

  /// Optional descriptive message to help the user understand what happened
  final String? message;

  /// Callback function when user taps the retry button
  final VoidCallback onRetry;

  /// Icon to display above the error message
  final IconData icon;

  /// Color for the icon
  final Color? iconColor;

  const ErrorView({super.key, this.title, this.message, required this.onRetry, this.icon = Icons.cloud_off_outlined, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorColor = iconColor ?? theme.colorScheme.error;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Error icon
            Icon(icon, size: 64, color: errorColor.withOpacity(0.7)),
            const SizedBox(height: 24),

            // Error title
            Text(title ?? 'Oops! Something went wrong', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.center),

            // Error message (if provided)
            if (message != null) ...[const SizedBox(height: 12), Text(message!, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]), textAlign: TextAlign.center)],

            const SizedBox(height: 32),

            // Retry button
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try Again')),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Wrap a root screen with this to ask before exiting the app.
class BackExitGuard extends StatelessWidget {
  final Widget child;
  final String prompt;
  const BackExitGuard({
    super.key,
    required this.child,
    this.prompt = 'Do you want to exit the app?',
  });

  Future<bool> _confirm(BuildContext context) async {
    final theme = Theme.of(context);
    final isCupertino = theme.platform == TargetPlatform.iOS;
    if (isCupertino) {
      final r = await showCupertinoDialog<bool>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Exit'),
          content: Text(prompt),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Exit'),
            ),
          ],
        ),
      );
      return r ?? false;
    } else {
      final r = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Exit'),
          content: Text(prompt),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Exit'),
            ),
          ],
        ),
      );
      return r ?? false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () => _confirm(context),
      child: child,
    );
  }
}

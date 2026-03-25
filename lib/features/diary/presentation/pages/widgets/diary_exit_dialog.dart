import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';

Future<bool> showDiaryExitConfirmationDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.diary.exit_without_saving),
      content: Text(t.diary.exit_confirmation_hint),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(t.common.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(t.diary.exit_without_saving_confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}

import 'package:baishou/core/theme/app_theme.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class DiaryEditorContentArea extends StatelessWidget {
  final bool isPreview;
  final TextEditingController contentController;

  const DiaryEditorContentArea({
    super.key,
    required this.isPreview,
    required this.contentController,
  });

  @override
  Widget build(BuildContext context) {
    if (isPreview) {
      if (contentController.text.trim().isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Center(
            child: Text(
              t.diary.no_content_preview,
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
          ),
        );
      }
      return MarkdownBody(
        data: contentController.text,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(
            fontSize: 16,
            height: 1.6,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
          h1: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
          h2: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
          h3: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
          code: TextStyle(
            fontSize: 14,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            color: AppTheme.primary,
          ),
          codeblockDecoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          blockquoteDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: AppTheme.primary.withOpacity(0.5),
                width: 3,
              ),
            ),
          ),
          listBullet: TextStyle(
            fontSize: 16,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
          checkbox: TextStyle(color: AppTheme.primary),
        ),
      );
    }

    return TextField(
      controller: contentController,
      maxLines: null,
      minLines: 10,
      style: TextStyle(
        fontSize: 16,
        height: 1.6,
        color: Theme.of(context).textTheme.bodyLarge?.color,
      ),
      decoration: InputDecoration(
        hintText: t.diary.editor_hint,
        hintStyle: TextStyle(color: Colors.grey[400]),
        border: InputBorder.none,
      ),
    );
  }
}

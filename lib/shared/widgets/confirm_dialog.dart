import 'package:flutter/material.dart';

/// Modal dialog for generic and destructive confirmations (§7.1 #2, §7.2).
///
/// When [requiredConfirmationText] is provided, the user must type the exact
/// string (e.g. "DELETE") before the confirm button becomes enabled.
class ConfirmDialog extends StatefulWidget {
  const ConfirmDialog({
    required this.title,
    required this.message,
    super.key,
    this.cancelLabel = 'Cancel',
    this.confirmLabel = 'Confirm',
    this.isDestructive = false,
    this.requiredConfirmationText,
  });

  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final bool isDestructive;
  final String? requiredConfirmationText;

  /// Convenience method to show [ConfirmDialog] and return true if confirmed.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String cancelLabel = 'Cancel',
    String confirmLabel = 'Confirm',
    bool isDestructive = false,
    String? requiredConfirmationText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => ConfirmDialog(
        title: title,
        message: message,
        cancelLabel: cancelLabel,
        confirmLabel: confirmLabel,
        isDestructive: isDestructive,
        requiredConfirmationText: requiredConfirmationText,
      ),
    );
    return result ?? false;
  }

  @override
  State<ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<ConfirmDialog> {
  final TextEditingController _inputController = TextEditingController();

  bool get _isConfirmed {
    if (widget.requiredConfirmationText == null) return true;
    return _inputController.text.trim() == widget.requiredConfirmationText;
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDestructive = widget.isDestructive;

    final confirmButtonStyle = isDestructive
        ? FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          )
        : null;

    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(widget.message, style: theme.textTheme.bodyMedium),
            if (widget.requiredConfirmationText != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                'Type "${widget.requiredConfirmationText}" to confirm:',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _inputController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: widget.requiredConfirmationText,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (_isConfirmed) {
                    Navigator.of(context).pop(true);
                  }
                },
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          style: confirmButtonStyle,
          onPressed: _isConfirmed
              ? () => Navigator.of(context).pop(true)
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

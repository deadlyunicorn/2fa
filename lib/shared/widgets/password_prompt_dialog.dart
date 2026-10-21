import 'package:flutter/material.dart';

import 'obscured_text_field.dart';

/// Modal dialog prompting the user for a password (§7.1 #2, #9, #11, §7.2).
class PasswordPromptDialog extends StatefulWidget {
  const PasswordPromptDialog({
    super.key,
    this.title = 'Enter Password',
    this.message,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.requireNonEmpty = true,
  });

  final String title;
  final String? message;
  final String confirmLabel;
  final String cancelLabel;
  final bool requireNonEmpty;

  /// Convenience method to show [PasswordPromptDialog] and return the entered password.
  static Future<String?> show(
    BuildContext context, {
    String title = 'Enter Password',
    String? message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool requireNonEmpty = true,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => PasswordPromptDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        requireNonEmpty: requireNonEmpty,
      ),
    );
  }

  @override
  State<PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<PasswordPromptDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _controller.text;
    if (widget.requireNonEmpty && password.isEmpty) {
      setState(() {
        _errorText = 'Password cannot be empty';
      });
      return;
    }
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (widget.message != null) ...<Widget>[
              Text(
                widget.message!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],
            ObscuredTextField(
              controller: _controller,
              autofocus: true,
              labelText: 'Password',
              errorText: _errorText,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() {
                    _errorText = null;
                  });
                }
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

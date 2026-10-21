import 'package:flutter/material.dart';

/// Text field with an eye toggle to obscure or reveal sensitive text (§7.2).
class ObscuredTextField extends StatefulWidget {
  const ObscuredTextField({
    super.key,
    this.controller,
    this.labelText,
    this.hintText,
    this.errorText,
    this.helperText,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.obscureByDefault = true,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.textInputAction,
    this.prefixIcon,
    this.suffixActions,
  });

  final TextEditingController? controller;
  final String? labelText;
  final String? hintText;
  final String? errorText;
  final String? helperText;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final bool obscureByDefault;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final TextInputAction? textInputAction;
  final Widget? prefixIcon;
  final List<Widget>? suffixActions;

  @override
  State<ObscuredTextField> createState() => _ObscuredTextFieldState();
}

class _ObscuredTextFieldState extends State<ObscuredTextField> {
  late bool _obscureText;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscureByDefault;
  }

  void _toggleObscure() {
    setState(() {
      _obscureText = !_obscureText;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget suffixWidget;
    if (widget.suffixActions != null && widget.suffixActions!.isNotEmpty) {
      suffixWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
            tooltip: _obscureText ? 'Show password' : 'Hide password',
            onPressed: widget.enabled ? _toggleObscure : null,
          ),
          ...widget.suffixActions!,
        ],
      );
    } else {
      suffixWidget = IconButton(
        icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
        tooltip: _obscureText ? 'Show password' : 'Hide password',
        onPressed: widget.enabled ? _toggleObscure : null,
      );
    }

    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: _obscureText,
      enableSuggestions: false,
      autocorrect: false,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      validator: widget.validator,
      textInputAction: widget.textInputAction,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        errorText: widget.errorText,
        helperText: widget.helperText,
        prefixIcon: widget.prefixIcon,
        border: const OutlineInputBorder(),
        suffixIcon: suffixWidget,
      ),
    );
  }
}

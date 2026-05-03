import 'package:flutter/material.dart';

/// Password field with visibility toggle and desktop keyboard navigation support.
class PasswordField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final Iterable<String>? autofillHints;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const PasswordField({
    super.key,
    required this.label,
    required this.controller,
    this.autofillHints,
    this.focusNode,
    this.nextFocusNode,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white70,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: widget.controller,
          obscureText: _obscure,
          autofillHints: widget.autofillHints,
          enableSuggestions: false,
          autocorrect: false,
          focusNode: widget.focusNode,
          textInputAction: widget.textInputAction ??
              (widget.nextFocusNode != null
                  ? TextInputAction.next
                  : TextInputAction.done),
          onSubmitted: widget.onSubmitted ??
              (widget.nextFocusNode != null
                  ? (_) =>
                      FocusScope.of(context).requestFocus(widget.nextFocusNode)
                  : null),
          style: const TextStyle(color: Colors.black),
          decoration: InputDecoration(
            suffixIcon: IconButton(
              icon: Icon(
                _obscure ? Icons.visibility_off : Icons.visibility,
                color: Colors.black54,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
      ],
    );
  }
}

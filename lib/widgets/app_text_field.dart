import 'package:flutter/material.dart';

/// Custom text field widget with desktop keyboard navigation support.
class AppTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.keyboardType,
    this.autofillHints,
    this.focusNode,
    this.nextFocusNode,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white70,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          autofillHints: autofillHints,
          focusNode: focusNode,
          textInputAction:
              textInputAction ?? (nextFocusNode != null ? TextInputAction.next : TextInputAction.done),
          onSubmitted: onSubmitted ??
              (nextFocusNode != null
                  ? (_) => FocusScope.of(context).requestFocus(nextFocusNode)
                  : null),
          style: const TextStyle(color: Colors.black),
          decoration: const InputDecoration(),
        ),
      ],
    );
  }
}

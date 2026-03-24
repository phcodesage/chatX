import 'package:flutter/material.dart';

/// Custom text field widget
class AppTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;

  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.keyboardType,
    this.autofillHints,
  });
  
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white70)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          autofillHints: autofillHints,
          style: const TextStyle(color: Colors.black),
          decoration: const InputDecoration(),
        ),
      ],
    );
  }
}

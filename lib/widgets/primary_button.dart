import 'package:flutter/material.dart';

/// Primary action button.
///
/// On desktop/medium screens it uses a fixed comfortable height.
/// On compact mobile screens it scales down proportionally.
class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  const PrimaryButton({super.key, required this.text, required this.onPressed});

  static const Color primaryBtn = Color(0xFF2E2A8B);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Only apply compact scaling on small phone screens.
    final scale = size.width < 360 || size.height < 680
        ? 0.88
        : (size.width < 390 || size.height < 760) && size.width < 600
            ? 0.94
            : 1.0;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBtn,
          foregroundColor: Colors.white,
          minimumSize: Size.fromHeight(48 * scale),
          padding: EdgeInsets.symmetric(vertical: 14 * scale),
          tapTargetSize: scale < 1
              ? MaterialTapTargetSize.shrinkWrap
              : MaterialTapTargetSize.padded,
          visualDensity: scale < 1
              ? const VisualDensity(horizontal: -1, vertical: -1)
              : VisualDensity.standard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          disabledBackgroundColor: primaryBtn.withValues(alpha: 0.5),
          elevation: 0,
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

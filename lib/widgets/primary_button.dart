import 'package:flutter/material.dart';

/// Primary button widget
class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  const PrimaryButton({super.key, required this.text, required this.onPressed});

  static const Color primaryBtn = Color(0xFF2E2A8B);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final scale = size.width < 360 || size.height < 680
        ? 0.88
        : (size.width < 390 || size.height < 760)
        ? 0.94
        : 1.0;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBtn,
          foregroundColor: Colors.white,
          minimumSize: Size.fromHeight(46 * scale),
          padding: EdgeInsets.symmetric(vertical: 14 * scale),
          tapTargetSize: scale < 1
              ? MaterialTapTargetSize.shrinkWrap
              : MaterialTapTargetSize.padded,
          visualDensity: scale < 1
              ? const VisualDensity(horizontal: -1, vertical: -1)
              : VisualDensity.standard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10 * scale),
          ),
          disabledBackgroundColor: primaryBtn.withValues(alpha: 0.5),
        ),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

class ChatComposerShell extends StatelessWidget {
  const ChatComposerShell({
    super.key,
    required this.composerInset,
    required this.backgroundColor,
    required this.padding,
    required this.child,
    this.borderTopColor = const Color(0xFF3D3D3D),
    this.animationDuration = const Duration(milliseconds: 180),
    this.animationCurve = Curves.easeOutCubic,
  });

  final double composerInset;
  final Color backgroundColor;
  final EdgeInsetsGeometry padding;
  final Color borderTopColor;
  final Duration animationDuration;
  final Curve animationCurve;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final targetInset = composerInset < 0 ? 0.0 : composerInset;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: targetInset),
      duration: animationDuration,
      curve: animationCurve,
      builder: (context, animatedInset, shellChild) {
        return SafeArea(
          top: false,
          left: false,
          right: false,
          minimum: EdgeInsets.only(bottom: animatedInset),
          child: shellChild!,
        );
      },
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border(
            top: BorderSide(color: borderTopColor, width: 1),
          ),
        ),
        child: child,
      ),
    );
  }
}
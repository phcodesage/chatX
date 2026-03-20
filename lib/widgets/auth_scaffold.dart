import 'package:flutter/material.dart';
import 'app_version_text.dart';

/// Shared scaffold widget for authentication screens
class AuthScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  const AuthScaffold({super.key, required this.title, required this.child});

  static const Color blue900 = Color(0xFF1E3A8A);
  static const Color card = Color(0xFF344256);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            const Positioned.fill(
              child: RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [blue900, Color(0xFF172554)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompactHeight = constraints.maxHeight < 720;
                  final isCompactWidth = constraints.maxWidth < 380;
                  final scale = constraints.maxWidth < 360 ||
                          constraints.maxHeight < 680
                      ? 0.88
                      : (isCompactWidth || isCompactHeight)
                      ? 0.94
                      : 1.0;
                  final horizontalPadding = (isCompactWidth ? 14.0 : 20.0) * scale;
                  final verticalPadding = (isCompactHeight ? 14.0 : 24.0) * scale;
                  final cardPadding = EdgeInsets.symmetric(
                    horizontal: (isCompactWidth ? 18.0 : 24.0) * scale,
                    vertical: (isCompactWidth ? 20.0 : 28.0) * scale,
                  );
                  final baseTheme = Theme.of(context);
                  final compactVisualDensity = scale < 1
                      ? const VisualDensity(horizontal: -1, vertical: -1)
                      : baseTheme.visualDensity;
                  final scaledTheme = baseTheme.copyWith(
                    visualDensity: compactVisualDensity,
                    materialTapTargetSize: scale < 1
                        ? MaterialTapTargetSize.shrinkWrap
                        : MaterialTapTargetSize.padded,
                    iconTheme: baseTheme.iconTheme.copyWith(
                      size: (baseTheme.iconTheme.size ?? 24) * scale,
                    ),
                    inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16 * scale,
                        vertical: 14 * scale,
                      ),
                    ),
                    textButtonTheme: TextButtonThemeData(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10 * scale,
                          vertical: 8 * scale,
                        ),
                        minimumSize: Size(0, 36 * scale),
                        tapTargetSize: scale < 1
                            ? MaterialTapTargetSize.shrinkWrap
                            : MaterialTapTargetSize.padded,
                      ),
                    ),
                  );

                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      verticalPadding,
                      horizontalPadding,
                      12,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - verticalPadding * 2,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: Theme(
                              data: scaledTheme,
                              child: MediaQuery(
                                data: MediaQuery.of(context).copyWith(
                                  textScaler: TextScaler.linear(scale),
                                ),
                                child: Builder(
                                  builder: (context) => Card(
                                    color: card,
                                    elevation: 0,
                                    clipBehavior: Clip.antiAlias,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16 * scale),
                                    ),
                                    child: Padding(
                                      padding: cardPadding,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title,
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                ),
                                          ),
                                          SizedBox(
                                            height: (isCompactHeight ? 18 : 24) * scale,
                                          ),
                                          child,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: 16 * scale),
                          const AppVersionText(),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

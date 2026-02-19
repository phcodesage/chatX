import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Displays the app version at the bottom of screens.
class AppVersionText extends StatelessWidget {
  const AppVersionText({super.key});

  static Future<PackageInfo>? _cachedFuture;

  static Future<PackageInfo> _getPackageInfo() {
    _cachedFuture ??= PackageInfo.fromPlatform();
    return _cachedFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _getPackageInfo(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final info = snapshot.data!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 8),
          child: Text(
            'v${info.version}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        );
      },
    );
  }
}

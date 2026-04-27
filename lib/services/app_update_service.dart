import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../config/api_config.dart';

/// Service for checking and applying OTA app updates from the Flask backend.
class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  /// Check for updates and show dialog if a new version is available.
  /// Call this from the lobby screen's initState.
  Future<void> checkForUpdate(BuildContext context) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      final response = await http.get(
        Uri.parse(ApiConfig.appVersionUrl),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return;

      final data = json.decode(response.body);
      final serverBuild = data['build_number'] as int? ?? 0;
      final serverVersion = data['version'] as String? ?? '';
      final downloadUrl = data['download_url'] as String? ?? '';
      final forceUpdate = data['force_update'] as bool? ?? false;
      final releaseNotes = data['release_notes'] as String? ?? '';

      if (serverBuild > currentBuild && downloadUrl.isNotEmpty) {
        if (context.mounted) {
          _showUpdateDialog(
            context,
            serverVersion: serverVersion,
            releaseNotes: releaseNotes,
            downloadUrl: downloadUrl,
            forceUpdate: forceUpdate,
          );
        }
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }

  void _showUpdateDialog(
    BuildContext context, {
    required String serverVersion,
    required String releaseNotes,
    required String downloadUrl,
    required bool forceUpdate,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateDialog(
        serverVersion: serverVersion,
        releaseNotes: releaseNotes,
        downloadUrl: downloadUrl,
        forceUpdate: forceUpdate,
      ),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final String serverVersion;
  final String releaseNotes;
  final String downloadUrl;
  final bool forceUpdate;

  const _UpdateDialog({
    required this.serverVersion,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.forceUpdate,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String _statusText = '';

  Future<void> _downloadAndInstall() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _statusText = 'Downloading update...';
    });

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(widget.downloadUrl));
      final streamedResponse = await client.send(request);

      final contentLength = streamedResponse.contentLength ?? 0;
      final bytes = <int>[];
      int received = 0;

      await for (final chunk in streamedResponse.stream) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          setState(() {
            _progress = received / contentLength;
            final mb = (received / 1024 / 1024).toStringAsFixed(1);
            final totalMb = (contentLength / 1024 / 1024).toStringAsFixed(1);
            _statusText = 'Downloading... $mb / $totalMb MB';
          });
        }
      }

      client.close();

      setState(() {
        _statusText = 'Installing...';
        _progress = 1.0;
      });

      // Save APK to temp directory
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/flutter_messenger_update.apk');
      await file.writeAsBytes(bytes);

      // Open the APK for installation
      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done) {
        setState(() {
          _downloading = false;
          _statusText = 'Install failed: ${result.message}';
        });
      }
    } catch (e) {
      setState(() {
        _downloading = false;
        _statusText = 'Download failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.system_update, color: Color(0xFF7C3AED), size: 28),
            const SizedBox(width: 10),
            Text(
              'Update Available',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Version ${widget.serverVersion}',
                style: const TextStyle(
                  color: Color(0xFF7C3AED),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (widget.releaseNotes.isNotEmpty) ...[
              const Text(
                'What\'s new:',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.releaseNotes,
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 12),
            ],
            if (_downloading) ...[
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF7C3AED)),
              ),
              const SizedBox(height: 8),
              Text(
                _statusText,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ] else if (_statusText.isNotEmpty) ...[
              Text(
                _statusText,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
          ],
        ),
        actions: _downloading
            ? null
            : [
                ElevatedButton(
                  onPressed: _downloadAndInstall,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Update Now'),
                ),
              ],
      ),
    );
  }
}

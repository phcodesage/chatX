import 'package:flutter/material.dart';

/// File-type icon that exactly mirrors the web app's UI: a solid, accent-colored
/// document with a folded top-right corner and the file extension (e.g. PKG,
/// SWIF, GP) baked into the bottom in white. Base art is 40x48, scaled by [scale].
class FileTypeIcon extends StatelessWidget {
  final String fileName;
  final double scale;

  const FileTypeIcon({super.key, required this.fileName, this.scale = 1.0});

  /// Lowercase extension (no dot) of a filename, or '' if none.
  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// Accent color for a given extension — identical palette to the web app.
  static Color accentColor(String ext) {
    if (ext == 'pdf') return const Color(0xFFE2574C);
    if (['doc', 'docx', 'odt', 'rtf', 'pages'].contains(ext)) return const Color(0xFF2B7CD3);
    if (['xls', 'xlsx', 'csv', 'ods', 'numbers'].contains(ext)) return const Color(0xFF1F9D55);
    if (['ppt', 'pptx', 'odp', 'key'].contains(ext)) return const Color(0xFFE8703A);
    if (['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'tgz', 'iso', 'zst', 'lz4'].contains(ext)) return const Color(0xFFD6A200);
    if (['exe', 'msi', 'pkg', 'dmg', 'deb', 'rpm', 'apk', 'appimage', 'snap', 'bin', 'dat'].contains(ext)) return const Color(0xFF64748B);
    if (['gp', 'gp3', 'gp4', 'gp5', 'gpx', 'gp7', 'gtp', 'ptb', 'mscz', 'mscx', 'musicxml', 'mxl', 'mid', 'midi'].contains(ext)) return const Color(0xFF8B5CF6);
    if (['mp3', 'wav', 'ogg', 'aac', 'm4a', 'flac', 'wma', 'opus', 'aiff'].contains(ext)) return const Color(0xFFA855F7);
    if (['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', '3gp', 'flv', 'wmv'].contains(ext)) return const Color(0xFFEC4899);
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp', 'heic', 'tiff'].contains(ext)) return const Color(0xFF14B8A6);
    if (['js', 'ts', 'jsx', 'tsx', 'py', 'java', 'cpp', 'c', 'h', 'cs', 'go', 'rs', 'rb', 'php', 'swift', 'kt', 'html', 'htm', 'css', 'scss', 'sass', 'less', 'json', 'xml', 'yaml', 'yml', 'sh', 'bat', 'ps1', 'sql', 'md', 'vue', 'svelte'].contains(ext)) return const Color(0xFF0EA5E9);
    if (['txt', 'log', 'nfo', 'cfg', 'conf', 'ini'].contains(ext)) return const Color(0xFF94A3B8);
    return const Color(0xFF7C3AED);
  }

  @override
  Widget build(BuildContext context) {
    final String ext = extensionOf(fileName);
    final Color accent = accentColor(ext);
    final String label = ext.isEmpty ? 'FILE' : ext.toUpperCase();
    final String shown = label.length > 4 ? label.substring(0, 4) : label;

    return SizedBox(
      width: 40 * scale,
      height: 48 * scale,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          CustomPaint(
            size: Size(40 * scale, 48 * scale),
            painter: _FileDocPainter(accent),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: 7 * scale),
            child: Text(
              shown,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 8 * scale,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the document silhouette + folded corner. Coordinates match the web SVG
/// (viewBox 0 0 40 48) so the shape is pixel-faithful to the browser version.
class _FileDocPainter extends CustomPainter {
  final Color color;
  _FileDocPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final double sx = size.width / 40.0;
    final double sy = size.height / 48.0;
    final Radius r = Radius.elliptical(4 * sx, 4 * sy);

    final body = Path()
      ..moveTo(4 * sx, 6 * sy)
      ..arcToPoint(Offset(8 * sx, 2 * sy), radius: r, clockwise: true)
      ..lineTo(24 * sx, 2 * sy)
      ..lineTo(36 * sx, 14 * sy)
      ..lineTo(36 * sx, 42 * sy)
      ..arcToPoint(Offset(32 * sx, 46 * sy), radius: r, clockwise: true)
      ..lineTo(8 * sx, 46 * sy)
      ..arcToPoint(Offset(4 * sx, 42 * sy), radius: r, clockwise: true)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );

    // Folded top-right corner (white dog-ear at 40% opacity).
    final fold = Path()
      ..moveTo(24 * sx, 2 * sy)
      ..lineTo(36 * sx, 14 * sy)
      ..lineTo(28 * sx, 14 * sy)
      ..arcToPoint(Offset(24 * sx, 10 * sy), radius: r, clockwise: true)
      ..close();
    canvas.drawPath(
      fold,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _FileDocPainter oldDelegate) => oldDelegate.color != color;
}

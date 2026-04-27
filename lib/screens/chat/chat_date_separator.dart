import 'package:flutter/material.dart';

class ChatDateSeparator extends StatelessWidget {
  const ChatDateSeparator({
    super.key,
    required this.timestamp,
    required this.scale,
  });

  final String timestamp;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final formattedText = _formatTimestamp(timestamp);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 16 * scale),
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 16 * scale,
            vertical: 8 * scale,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF3D4752),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            formattedText,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13 * scale,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  static String _formatTimestamp(String timestamp) {
    try {
      final date = _parseUtcTimestamp(timestamp);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final messageDate = DateTime(date.year, date.month, date.day);

      if (messageDate == today) {
        return 'Today';
      } else if (messageDate == yesterday) {
        return 'Yesterday';
      }

      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final weekday = weekdays[date.weekday - 1];
      final month = months[date.month - 1];
      return '$weekday. $month ${date.day}, ${date.year}';
    } catch (e) {
      return timestamp;
    }
  }

  static DateTime _parseUtcTimestamp(String ts) {
    final hasTimezone = RegExp(r'[zZ]|[+-]\d{2}:?\d{2}').hasMatch(ts);
    final parsed = DateTime.parse(hasTimezone ? ts : '${ts}Z');
    return parsed.toLocal();
  }
}

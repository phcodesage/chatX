import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_messenger/models/group.dart';
import 'package:flutter_messenger/models/message.dart';

void main() {
  const brokenFileHtml = '''
<div class="file-message">
  <div class="file-info">
    <span class="file-name" title="Download Archive">Archive</span>
    <span class="file-size">122682883 bytes</span>
  </div>
</div>
''';

  group('Message.fromJson file HTML parsing', () {
    test('parses malformed file HTML without href as a file attachment', () {
      final message = Message.fromJson({
        'id': 1,
        'sender_id': 10,
        'recipient_id': 20,
        'content': brokenFileHtml,
        'message_type': 'text',
        'timestamp': '2026-03-29T12:00:00',
        'timestamp_ms': 0,
        'is_read': false,
        'status': 'sent',
        'thread_id': 'thread-1',
        'reactions': <String, dynamic>{},
        'is_deleted': false,
      });

      expect(message.messageType, 'file');
      expect(message.fileUrl, isNull);
      expect(message.fileName, 'Archive');
      expect(message.fileSize, 122682883);
    });

    test('still parses normal file links with href', () {
      const linkedFileHtml =
          '<a href="https://example.com/files/report.pdf" download="report.pdf">report.pdf</a>';

      final message = Message.fromJson({
        'id': 2,
        'sender_id': 10,
        'recipient_id': 20,
        'content': linkedFileHtml,
        'message_type': 'text',
        'timestamp': '2026-03-29T12:00:00',
        'timestamp_ms': 0,
        'is_read': false,
        'status': 'sent',
        'thread_id': 'thread-1',
        'reactions': <String, dynamic>{},
        'is_deleted': false,
      });

      expect(message.messageType, 'file');
      expect(message.fileUrl, 'https://example.com/files/report.pdf');
      expect(message.fileName, 'report.pdf');
    });
  });

  group('GroupMessage.fromJson file HTML parsing', () {
    test('parses malformed file HTML without href as a file attachment', () {
      final message = GroupMessage.fromJson({
        'id': 1,
        'message_id': 1,
        'group_id': 5,
        'sender_id': 10,
        'content': brokenFileHtml,
        'message_type': 'text',
        'timestamp': '2026-03-29T12:00:00',
        'timestamp_ms': 0,
        'reactions': <String, dynamic>{},
        'is_deleted': false,
      });

      expect(message.messageType, 'file');
      expect(message.fileUrl, isNull);
      expect(message.fileName, 'Archive');
      expect(message.fileSize, 122682883);
    });

    test('normalizes multi-emoji reactions for the same user from by_user payload', () {
      final message = GroupMessage.fromJson({
        'id': 2,
        'message_id': 2,
        'group_id': 5,
        'sender_id': 10,
        'content': 'hello',
        'message_type': 'text',
        'timestamp': '2026-03-29T12:00:00',
        'timestamp_ms': 0,
        'reactions': {
          'counts': {'😀': 1, '🔥': 1},
          'by_user': [
            {'user_id': 42, 'reaction': '😀'},
            {'user_id': 42, 'reaction': '🔥'},
          ],
        },
        'is_deleted': false,
      });

      expect(message.reactions, {
        '😀': ['42'],
        '🔥': ['42'],
      });
    });
  });
}
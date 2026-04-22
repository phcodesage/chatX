/// Model for mention preview data
class MentionPreview {
  final String summary;
  final String content;
  final bool isMention;

  MentionPreview({
    required this.summary,
    required this.content,
    required this.isMention,
  });
}

/// Utility for parsing mention markers in notification/message bodies
class MentionParser {
  /// Splts a body text into summary and content if it contains "mentioned you:"
  /// Example: "rech mentioned you: hello" -> summary: "rech mentioned you", content: "hello"
  static MentionPreview parse(String body) {
    const marker = ' mentioned you: ';
    final idx = body.indexOf(marker);
    
    if (idx <= 0) {
      return MentionPreview(
        summary: '',
        content: body,
        isMention: false,
      );
    }

    return MentionPreview(
      summary: body.substring(0, idx + marker.length - 2), // remove trailing ":"
      content: body.substring(idx + marker.length).trim(),
      isMention: true,
    );
  }
}

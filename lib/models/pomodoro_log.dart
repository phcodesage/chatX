class PomodoroLog {
  final int id;
  final String timestamp;
  final String text;
  final String type;

  PomodoroLog({
    required this.id,
    required this.timestamp,
    required this.text,
    required this.type,
  });

  factory PomodoroLog.fromJson(Map<String, dynamic> json) {
    return PomodoroLog(
      id: json['id'],
      timestamp: json['timestamp'],
      text: json['text'],
      type: json['type'] ?? 'info',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp,
      'text': text,
      'type': type,
    };
  }
}

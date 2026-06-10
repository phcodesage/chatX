class Alarm {
  final int? id;
  final String name;
  final String time24h;
  final String days;
  final bool isActive;
  final int ringTimes;

  Alarm({
    this.id,
    required this.name,
    required this.time24h,
    required this.days,
    required this.isActive,
    required this.ringTimes,
  });

  factory Alarm.fromJson(Map<String, dynamic> json) {
    return Alarm(
      id: json['id'],
      name: json['name'] ?? '',
      time24h: json['time_24h'] ?? '00:00',
      days: json['days'] ?? '',
      isActive: json['is_active'] ?? false,
      ringTimes: json['ring_times'] ?? 10,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'time_24h': time24h,
      'days': days,
      'is_active': isActive,
      'ring_times': ringTimes,
    };
  }

  Alarm copyWith({
    int? id,
    String? name,
    String? time24h,
    String? days,
    bool? isActive,
    int? ringTimes,
  }) {
    return Alarm(
      id: id ?? this.id,
      name: name ?? this.name,
      time24h: time24h ?? this.time24h,
      days: days ?? this.days,
      isActive: isActive ?? this.isActive,
      ringTimes: ringTimes ?? this.ringTimes,
    );
  }
}

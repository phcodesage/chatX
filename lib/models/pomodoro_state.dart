class PomodoroState {
  final String currentTab;
  final int totalSeconds;
  final int remaining;
  final bool isRunning;
  final bool isPaused;
  final bool isAlarming;
  final int presetPomodoro;
  final int presetShortBreak;
  final int presetLongBreak;
  final int ringsPomodoro;
  final int ringsShortBreak;
  final int ringsLongBreak;
  final DateTime updatedAt;

  PomodoroState({
    required this.currentTab,
    required this.totalSeconds,
    required this.remaining,
    required this.isRunning,
    required this.isPaused,
    required this.isAlarming,
    required this.presetPomodoro,
    required this.presetShortBreak,
    required this.presetLongBreak,
    required this.ringsPomodoro,
    required this.ringsShortBreak,
    required this.ringsLongBreak,
    required this.updatedAt,
  });

  factory PomodoroState.fromJson(Map<String, dynamic> json) {
    return PomodoroState(
      currentTab: json['current_tab'] ?? 'pomodoro',
      totalSeconds: json['total_seconds'] ?? 1500,
      remaining: json['remaining'] ?? 1500,
      isRunning: json['is_running'] ?? false,
      isPaused: json['is_paused'] ?? false,
      isAlarming: json['is_alarming'] ?? false,
      presetPomodoro: json['preset_pomodoro'] ?? 1500,
      presetShortBreak: json['preset_short_break'] ?? 300,
      presetLongBreak: json['preset_long_break'] ?? 900,
      ringsPomodoro: json['rings_pomodoro'] ?? 10,
      ringsShortBreak: json['rings_short_break'] ?? 10,
      ringsLongBreak: json['rings_long_break'] ?? 10,
      updatedAt: DateTime.parse(json['updated_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'current_tab': currentTab,
      'total_seconds': totalSeconds,
      'remaining': remaining,
      'is_running': isRunning,
      'is_paused': isPaused,
      'is_alarming': isAlarming,
      'preset_pomodoro': presetPomodoro,
      'preset_short_break': presetShortBreak,
      'preset_long_break': presetLongBreak,
      'rings_pomodoro': ringsPomodoro,
      'rings_short_break': ringsShortBreak,
      'rings_long_break': ringsLongBreak,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  PomodoroState copyWith({
    String? currentTab,
    int? totalSeconds,
    int? remaining,
    bool? isRunning,
    bool? isPaused,
    bool? isAlarming,
    int? presetPomodoro,
    int? presetShortBreak,
    int? presetLongBreak,
    int? ringsPomodoro,
    int? ringsShortBreak,
    int? ringsLongBreak,
    DateTime? updatedAt,
  }) {
    return PomodoroState(
      currentTab: currentTab ?? this.currentTab,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      remaining: remaining ?? this.remaining,
      isRunning: isRunning ?? this.isRunning,
      isPaused: isPaused ?? this.isPaused,
      isAlarming: isAlarming ?? this.isAlarming,
      presetPomodoro: presetPomodoro ?? this.presetPomodoro,
      presetShortBreak: presetShortBreak ?? this.presetShortBreak,
      presetLongBreak: presetLongBreak ?? this.presetLongBreak,
      ringsPomodoro: ringsPomodoro ?? this.ringsPomodoro,
      ringsShortBreak: ringsShortBreak ?? this.ringsShortBreak,
      ringsLongBreak: ringsLongBreak ?? this.ringsLongBreak,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

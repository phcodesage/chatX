import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/pomodoro_state.dart';
import '../models/pomodoro_log.dart';
import '../models/alarm.dart';
import 'storage_service.dart';

class PomodoroService {
  static final PomodoroService _instance = PomodoroService._internal();
  factory PomodoroService() => _instance;
  PomodoroService._internal();

  PomodoroState? _lastState;
  List<PomodoroLog> _lastLogs = [];
  List<Alarm> _lastAlarms = [];

  PomodoroState? get lastState => _lastState;
  List<PomodoroLog> get lastLogs => _lastLogs;
  List<Alarm> get lastAlarms => _lastAlarms;

  Future<Map<String, String>> _getHeaders() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Pomodoro State
  Future<PomodoroState?> getState() async {
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.pomodoroStateUrl),
        headers: await _getHeaders(),
      );
      if (response.statusCode == 200) {
        final state = PomodoroState.fromJson(json.decode(response.body));
        _lastState = state;
        // Save to local storage for persistence across restarts
        await StorageService.savePomodoroState(response.body);
        return state;
      }
    } catch (e) {
      // Error getting pomodoro state
    }
    // Fallback to local storage if API fails
    final localJson = await StorageService.getPomodoroState();
    if (localJson != null) {
      _lastState = PomodoroState.fromJson(json.decode(localJson));
    }
    return _lastState;
  }

  Future<bool> updateState(PomodoroState state) async {
    try {
      final stateJson = json.encode(state.toJson());
      // Optimistically save to local storage
      await StorageService.savePomodoroState(stateJson);
      _lastState = state;

      final response = await http.put(
        Uri.parse(ApiConfig.pomodoroStateUrl),
        headers: await _getHeaders(),
        body: stateJson,
      );
      return response.statusCode == 200;
    } catch (e) {
      // Error updating pomodoro state
    }
    return false;
  }

  // Alarms
  Future<List<Alarm>> getAlarms() async {
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.alarmsUrl),
        headers: await _getHeaders(),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final alarms = data.map((json) => Alarm.fromJson(json)).toList();
        _lastAlarms = alarms;
        return alarms;
      }
    } catch (e) {
      // Error getting alarms
    }
    return _lastAlarms;
  }

  Future<Alarm?> createAlarm(Alarm alarm) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.alarmsUrl),
        headers: await _getHeaders(),
        body: json.encode(alarm.toJson()),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return Alarm.fromJson(json.decode(response.body));
      }
    } catch (e) {
      // Error creating alarm
    }
    return null;
  }

  Future<bool> updateAlarm(Alarm alarm) async {
    try {
      final response = await http.put(
        Uri.parse(ApiConfig.getAlarmUrl(alarm.id!)),
        headers: await _getHeaders(),
        body: json.encode(alarm.toJson()),
      );
      return response.statusCode == 200;
    } catch (e) {
      // Error updating alarm
    }
    return false;
  }

  Future<bool> deleteAlarm(int alarmId) async {
    try {
      final response = await http.delete(
        Uri.parse(ApiConfig.getAlarmUrl(alarmId)),
        headers: await _getHeaders(),
      );
      return response.statusCode == 200;
    } catch (e) {
      // Error deleting alarm
    }
    return false;
  }

  Future<bool> toggleAlarm(int alarmId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.getAlarmUrl(alarmId)}/toggle'),
        headers: await _getHeaders(),
      );
      return response.statusCode == 200;
    } catch (e) {
      // Error toggling alarm
    }
    return false;
  }

  // Logs
  Future<List<PomodoroLog>> getLogs() async {
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.pomodoroLogsUrl),
        headers: await _getHeaders(),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final logs = data.map((json) => PomodoroLog.fromJson(json)).toList();
        _lastLogs = logs;
        return logs;
      }
    } catch (e) {
      // Error getting pomodoro logs
    }
    return _lastLogs;
  }

  Future<bool> addLog(String text, String type) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.pomodoroLogsUrl),
        headers: await _getHeaders(),
        body: json.encode({
          'text': text,
          'type': type,
        }),
      );
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      // Error adding pomodoro log
    }
    return false;
  }

  Future<bool> deleteLog(int logId) async {
    try {
      final response = await http.delete(
        Uri.parse(ApiConfig.getPomodoroLogUrl(logId)),
        headers: await _getHeaders(),
      );
      return response.statusCode == 200;
    } catch (e) {
      // Error deleting pomodoro log
    }
    return false;
  }

  Future<bool> updateLog(int logId, String text) async {
    try {
      final response = await http.put(
        Uri.parse(ApiConfig.getPomodoroLogUrl(logId)),
        headers: await _getHeaders(),
        body: json.encode({'text': text}),
      );
      return response.statusCode == 200;
    } catch (e) {
      // Error updating pomodoro log
    }
    return false;
  }

  Future<bool> undoLog() async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.pomodoroLogsUrl}/undo'),
        headers: await _getHeaders(),
      );
      return response.statusCode == 200;
    } catch (e) {
      // Error undoing pomodoro log
    }
    return false;
  }

  Future<bool> redoLog() async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.pomodoroLogsUrl}/redo'),
        headers: await _getHeaders(),
      );
      return response.statusCode == 200;
    } catch (e) {
      // Error redoing pomodoro log
    }
    return false;
  }

  Future<bool> clearLogs() async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.pomodoroLogsUrl}/clear'),
        headers: await _getHeaders(),
      );
      return response.statusCode == 200;
    } catch (e) {
      // Error clearing pomodoro logs
    }
    return false;
  }
}

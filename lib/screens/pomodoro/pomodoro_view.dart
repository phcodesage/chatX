import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/pomodoro_state.dart';
import '../../models/pomodoro_log.dart';
import '../../models/alarm.dart';
import '../../services/pomodoro_service.dart';
import '../../services/socket_service.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../services/alarm_notification_service.dart';
import 'alarm_dialog.dart';

class PomodoroView extends StatefulWidget {
  const PomodoroView({super.key});

  @override
  State<PomodoroView> createState() => _PomodoroViewState();
}

class _PomodoroViewState extends State<PomodoroView> with TickerProviderStateMixin {
  final PomodoroService _service = PomodoroService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _uiAudioPlayer = AudioPlayer();
  StreamSubscription? _playerCompleteSubscription;
  int _currentRingCount = 0;
  
  late TabController _tabController;
  Timer? _ticker;
  Timer? _syncTimer;
  bool _isLoading = false;

  PomodoroState? _state;
  List<PomodoroLog> _logs = [];
  List<Alarm> _alarms = [];
  int _currentRemaining = 0;
  DateTime _lastLocalUpdate = DateTime.now().subtract(const Duration(days: 1));
  int? _alarmingAlarmId;
  String _lastCheckedTimeKey = '';

  @override
  void initState() {
    super.initState();
    
    // Initial data from cache
    _state = _service.lastState;
    _logs = _service.lastLogs;
    _alarms = _service.lastAlarms;
    
    if (_state == null) {
      _state = PomodoroState(
        currentTab: 'pomodoro',
        totalSeconds: 1500,
        remaining: 1500,
        isRunning: false,
        isPaused: false,
        isAlarming: false,
        presetPomodoro: 1500,
        presetShortBreak: 300,
        presetLongBreak: 900,
        ringsPomodoro: 10,
        ringsShortBreak: 10,
        ringsLongBreak: 10,
        updatedAt: DateTime.now(),
      );
    }
    _currentRemaining = _state!.remaining;

    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        // Log internal tab navigation (spec §3 "Everything rule").
        const tabNames = ['Timer', 'Logs', 'Alarms'];
        _service.addLog('switched to ${tabNames[_tabController.index]} view', 'navigation');
        _loadAll();
      }
    });
    
    // Register Socket.IO listeners
    final socket = SocketService().socket;
    if (socket != null) {
      socket.on('pomodoro_sync', _onPomodoroSync);
      socket.on('pomodoro_logs_sync', _onPomodoroLogsSync);
      socket.on('alarms_sync', _onAlarmsSync);
    }

    // Log entering the suite (spec §3 "Everything rule"). A fresh PomodoroView
    // is created each time the user opens the alarmX tab, so this fires once
    // per entry.
    _service.addLog('entered Not Pomodoro suite', 'navigation');

    _loadAll();
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) => _syncState());
    _startClockTicker();
  }

  void _startClockTicker() {
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
        _checkAlarms();
      }
    });
  }

  void _checkAlarms() {
    if (_alarmingAlarmId != null) return; 

    final now = DateTime.now();
    final currentTimeKey = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    if (currentTimeKey == _lastCheckedTimeKey) return;
    _lastCheckedTimeKey = currentTimeKey;

    final currentDay = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][now.weekday - 1];

    for (final alarm in _alarms) {
      if (!alarm.isActive) continue;

      bool dayMatches = true;
      if (alarm.days.isNotEmpty) {
        dayMatches = alarm.days.split(',').contains(currentDay);
      }

      if (dayMatches && alarm.time24h == currentTimeKey) {
        setState(() {
          _alarmingAlarmId = alarm.id;
        });
        _playAlarm(alarm.ringTimes);
        _service.addLog('Alarm triggered: ${alarm.name}', 'alarm');
        break;
      }
    }
  }

  void _stopActiveAlarm() {
    _playClickSound();
    // Log the manual stop (spec §3 "Everything rule").
    String? stoppedName;
    for (final a in _alarms) {
      if (a.id == _alarmingAlarmId) {
        stoppedName = a.name;
        break;
      }
    }
    _service.addLog(
      'Manually stopped alarm: ${stoppedName?.isNotEmpty == true ? stoppedName : 'Unnamed Alarm'}',
      'alarm',
    );
    _playerCompleteSubscription?.cancel();
    _audioPlayer.stop();
    setState(() {
      _alarmingAlarmId = null;
    });
  }

  @override
  void dispose() {
    final socket = SocketService().socket;
    if (socket != null) {
      socket.off('pomodoro_sync', _onPomodoroSync);
      socket.off('pomodoro_logs_sync', _onPomodoroLogsSync);
      socket.off('alarms_sync', _onAlarmsSync);
    }
    _tabController.dispose();
    _ticker?.cancel();
    _syncTimer?.cancel();
    _playerCompleteSubscription?.cancel();
    _audioPlayer.dispose();
    _uiAudioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadAll({bool skipState = false}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    
    try {
      // Fetch in parallel
      final futures = await Future.wait([
        if (!skipState) _service.getState() else Future.value(_state),
        _service.getLogs(),
        _service.getAlarms(),
      ]);

      final state = futures[0] as PomodoroState?;
      final logs = futures[1] as List<PomodoroLog>;
      final alarms = futures[2] as List<Alarm>;
      
      if (mounted) {
        setState(() {
          if (!skipState && state != null) {
            // Avoid overwriting with stale server data if we have a more recent local update
            if (state.updatedAt.isAfter(_lastLocalUpdate)) {
              int remaining = state.remaining;
              if (state.isRunning && !state.isPaused) {
                final elapsed = DateTime.now().difference(state.updatedAt).inSeconds;
                remaining = (remaining - elapsed).clamp(0, state.totalSeconds);
              }

              _state = state.copyWith(remaining: remaining);
              _currentRemaining = remaining;

              if (_state!.isRunning && !_state!.isPaused && _currentRemaining > 0) {
                _initializeTimer();
              } else {
                _ticker?.cancel();
                _ticker = null;
                if (_state!.isRunning && !_state!.isPaused && _currentRemaining == 0) {
                  _onTimerComplete();
                }
              }

              if (_state!.isAlarming) {
                _playAlarm();
              } else {
                _audioPlayer.stop();
              }
            }
          }
          _logs = logs;
          _alarms = alarms;
        });
        // Sync alarms with local notification service
        AlarmNotificationService().scheduleAlarms(_alarms);
      }
    } catch (e) {
      debugPrint('Pomodoro load error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onPomodoroSync(dynamic data) {
    if (!mounted) return;
    if (data is Map<String, dynamic>) {
      final state = PomodoroState.fromJson(data);
      if (state.updatedAt.isAfter(_lastLocalUpdate)) {
        setState(() {
          int remaining = state.remaining;
          if (state.isRunning && !state.isPaused) {
            final elapsed = DateTime.now().difference(state.updatedAt).inSeconds;
            remaining = (remaining - elapsed).clamp(0, state.totalSeconds);
          }

          _state = state.copyWith(remaining: remaining);
          _currentRemaining = remaining;

          if (_state!.isRunning && !_state!.isPaused && _currentRemaining > 0) {
            if (_ticker == null || !_ticker!.isActive) {
              _initializeTimer();
            }
          } else {
            _ticker?.cancel();
            _ticker = null;
            if (_state!.isRunning && !_state!.isPaused && _currentRemaining == 0) {
              _onTimerComplete();
            }
          }

          if (_state!.isAlarming) {
            if (_audioPlayer.state != PlayerState.playing) {
              _playAlarm();
            }
          } else {
            _audioPlayer.stop();
          }
        });
      }
    }
  }

  void _onPomodoroLogsSync(dynamic _) {
    _loadLogs();
  }

  void _onAlarmsSync(dynamic _) async {
    final alarms = await _service.getAlarms();
    if (mounted) {
      setState(() {
        _alarms = alarms;
      });
      AlarmNotificationService().scheduleAlarms(_alarms);
    }
  }

  Future<void> _loadLogs() async {
    final logs = await _service.getLogs();
    if (mounted) {
      setState(() {
        _logs = logs;
      });
    }
  }

  void _initializeTimer() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentRemaining > 0) {
        setState(() {
          _currentRemaining--;
        });
      } else {
        _ticker?.cancel();
        _onTimerComplete();
      }
    });
  }

  void _onTimerComplete() async {
    _lastLocalUpdate = DateTime.now();
    setState(() {
      _state = _state!.copyWith(isRunning: false, isAlarming: true, updatedAt: _lastLocalUpdate);
    });
    await _service.updateState(_state!);
    await _service.addLog('timer "${_state!.currentTab}" completed', _state!.currentTab);
    _loadLogs(); // Only reload logs
    _playAlarm();
  }

  void _playClickSound() async {
    await _uiAudioPlayer.play(AssetSource('sounds/click/default.mp3'));
  }

  void _playAlarm([int? ringTimes]) async {
    if (_audioPlayer.state == PlayerState.playing) return;

    int targetRings = ringTimes ?? 10;
    if (ringTimes == null && _state != null) {
      if (_state!.currentTab == 'short-break') {
        targetRings = _state!.ringsShortBreak;
      } else if (_state!.currentTab == 'long-break') {
        targetRings = _state!.ringsLongBreak;
      } else {
        targetRings = _state!.ringsPomodoro;
      }
    }

    _currentRingCount = 0;
    await _audioPlayer.setReleaseMode(ReleaseMode.stop);

    _playerCompleteSubscription?.cancel();
    _playerCompleteSubscription = _audioPlayer.onPlayerComplete.listen((_) async {
      _currentRingCount++;
      if (_currentRingCount >= targetRings) {
        if (_alarmingAlarmId != null) {
          _stopActiveAlarm();
        } else if (_state != null && _state!.isAlarming) {
          _stopAlarm();
        }
      } else {
        await _audioPlayer.play(AssetSource('sounds/alarm/default.mp3'));
      }
    });

    await _audioPlayer.play(AssetSource('sounds/alarm/default.mp3'));
  }

  void _stopAlarm() async {
    _playClickSound();
    _playerCompleteSubscription?.cancel();
    await _audioPlayer.stop();
    _lastLocalUpdate = DateTime.now();
    await _service.addLog('timer "${_state?.currentTab ?? "pomodoro"}" alarm finished', _state?.currentTab ?? 'alarm');
    setState(() {
      _state = _state!.copyWith(isAlarming: false, updatedAt: _lastLocalUpdate);
    });
    await _service.updateState(_state!);
    _loadLogs(); // Only reload logs
  }

  Future<void> _syncState() async {
    if (_state != null) {
      await _service.updateState(_state!.copyWith(remaining: _currentRemaining));
    }
  }

  @override
  Widget build(BuildContext context) {

    return Container(
      color: const Color(0xFF1A1A2E),
      child: Column(
        children: [
          _buildHeader(),
          Container(
            color: const Color(0xFF1A1A2E),
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Timer'),
                Tab(text: 'Logs'),
                Tab(text: 'Alarms'),
              ],
              labelColor: const Color(0xFF00D9FF),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF00D9FF),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTimerTab(),
                _buildLogsTab(),
                _buildAlarmsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final now = DateTime.now();
    final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final timeStr = "${months[now.month-1]} ${now.day}${_getDaySuffix(now.day)} ${now.year}, ${now.hour % 12 == 0 ? 12 : now.hour % 12}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(width: 48), // Spacer to balance the 'CLOCK' badge on the right
          Expanded(
            child: Text(
              timeStr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D3A),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('CLOCK', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _getDaySuffix(int day) {
    if (day >= 11 && day <= 13) return 'th';
    switch (day % 10) {
      case 1: return 'st';
      case 2: return 'nd';
      case 3: return 'rd';
      default: return 'th';
    }
  }

  Widget _buildTimerTab() {
    if (_state == null) return const Center(child: Text('No state available', style: TextStyle(color: Colors.white)));

    final hoursNum = _currentRemaining ~/ 3600;
    final minutesNum = (_currentRemaining % 3600) ~/ 60;
    final secondsNum = _currentRemaining % 60;
    
    final hours = hoursNum.toString().padLeft(2, '0');
    final minutes = minutesNum.toString().padLeft(2, '0');
    final seconds = secondsNum.toString().padLeft(2, '0');

    Color bgColor = const Color(0xFFF06262); // Pomodoro (Coral)
    if (_state!.currentTab == 'short-break') {
      bgColor = const Color(0xFF8BC34A); // Light Green
    } else if (_state!.currentTab == 'long-break') {
      bgColor = const Color(0xFF4FC3F7); // Light Blue
    }

    return Container(
      color: bgColor, 
      width: double.infinity,
      child: Column(
        children: [
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _modeButton('Pomodoro', 'pomodoro', _state!.presetPomodoro),
              const SizedBox(width: 8),
              _modeButton('Short Break', 'short-break', _state!.presetShortBreak),
              const SizedBox(width: 8),
              _modeButton('Long Break', 'long-break', _state!.presetLongBreak),
            ],
          ),
          const Spacer(),
          const Text(
            'LET THE COUNTDOWN BEGIN!',
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5),
          ),
          const SizedBox(height: 10),
          Text(
            '$hours:$minutes:$seconds',
            style: const TextStyle(color: Colors.white, fontSize: 72, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_state!.isAlarming)
                _timerActionButton('STOP ALARM', _stopAlarm, color: Colors.yellow, textColor: Colors.black)
              else ...[
                _timerActionButton(
                  _state!.isRunning && !_state!.isPaused ? 'PAUSE' : 'PLAY',
                  () {
                    if (_state!.isRunning && !_state!.isPaused) {
                      _pauseTimer();
                    } else {
                      _startTimer();
                    }
                  },
                ),
                const SizedBox(width: 20),
                _timerActionButton('STOP', _resetTimer),
              ],
            ],
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  Widget _modeButton(String label, String tab, int duration) {
    final isSelected = _state?.currentTab == tab;
    return InkWell(
      onTap: () => _switchTab(tab, duration),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white.withOpacity(0.8),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _timerActionButton(String label, VoidCallback onPressed, {Color color = Colors.white, Color? textColor}) {
    Color effectiveTextColor = textColor ?? const Color(0xFFF06262);
    if (textColor == null && _state != null) {
      if (_state!.currentTab == 'short-break') {
        effectiveTextColor = const Color(0xFF8BC34A);
      } else if (_state!.currentTab == 'long-break') {
        effectiveTextColor = const Color(0xFF4FC3F7);
      }
    }

    return SizedBox(
      width: 130,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: effectiveTextColor,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }

  void _startTimer() async {
    _playClickSound();
    _lastLocalUpdate = DateTime.now();
    setState(() {
      _state = _state!.copyWith(isRunning: true, isPaused: false, updatedAt: _lastLocalUpdate);
      _initializeTimer();
    });
    
    AlarmNotificationService().schedulePomodoro(
      'Timer Complete!',
      'Your ${_state!.currentTab} session has finished.',
      Duration(seconds: _currentRemaining),
    );

    await _service.updateState(_state!);
    await _service.addLog('timer "${_state!.currentTab}" started', _state!.currentTab);
    _loadLogs();
  }

  void _pauseTimer() async {
    _playClickSound();
    _ticker?.cancel();
    _ticker = null;
    _lastLocalUpdate = DateTime.now();
    setState(() {
      _state = _state!.copyWith(isRunning: true, isPaused: true, remaining: _currentRemaining, updatedAt: _lastLocalUpdate);
    });
    await _service.updateState(_state!);
    await _service.addLog('Paused ${_state!.currentTab} timer at ${_currentRemaining ~/ 60}:${(_currentRemaining % 60).toString().padLeft(2, '0')}', _state!.currentTab);
    AlarmNotificationService().cancelPomodoro();
  }

  void _resetTimer() async {
    _playClickSound();
    _ticker?.cancel();
    _ticker = null;
    _lastLocalUpdate = DateTime.now();
    int preset = _state!.presetPomodoro;
    if (_state!.currentTab == 'short-break') preset = _state!.presetShortBreak;
    if (_state!.currentTab == 'long-break') preset = _state!.presetLongBreak;

    await _service.addLog('Stopped/Reset ${_state!.currentTab} timer', _state!.currentTab);

    setState(() {
      _state = _state!.copyWith(isRunning: false, isPaused: false, remaining: preset, updatedAt: _lastLocalUpdate);
      _currentRemaining = preset;
    });
    await _service.updateState(_state!);
    AlarmNotificationService().cancelPomodoro();
  }

  void _switchTab(String tab, int duration) async {
    if (_state?.currentTab == tab) return;

    if (_state != null && _state!.isRunning) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF252542),
          title: const Text('Timer is running', style: TextStyle(color: Colors.white)),
          content: const Text('Please stop the current timer before switching to another mode.', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: Color(0xFF00D9FF))),
            ),
          ],
        ),
      );
      return;
    }

    _ticker?.cancel();
    _ticker = null;
    _lastLocalUpdate = DateTime.now();
    final modeName = tab.replaceAll('-', ' ');
    setState(() {
      _state = _state!.copyWith(
        currentTab: tab,
        totalSeconds: duration,
        remaining: duration,
        isRunning: false,
        isPaused: false,
        updatedAt: _lastLocalUpdate,
      );
      _currentRemaining = duration;
    });
    await _service.updateState(_state!);
    await _service.addLog('switched to $modeName tab', tab);
    _loadLogs();
    AlarmNotificationService().cancelPomodoro();
  }

  Widget _buildLogsTab() {
    return Column(
      children: [
        Container(
          color: const Color(0xFF454558),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Text('Logs', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
              const Spacer(),
              _logActionBtn('Undo', _undoLog),
              _logActionBtn('Redo', _redoLog),
              _logActionBtn('Clear', _clearLogs),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.white,
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: _logs.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey[200]),
              itemBuilder: (context, index) {
                final log = _logs[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () => _editLog(log),
                        child: Icon(Icons.edit_note, size: 18, color: Colors.orange[400]),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _deleteLog(log.id),
                        child: Icon(Icons.delete_outline, size: 18, color: Colors.red[400]),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(color: Colors.black87, fontSize: 13, height: 1.4),
                            children: <InlineSpan>[
                              TextSpan(
                                text: '${_formatLogTimestamp(log.timestamp)} ',
                                style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w400),
                              ),
                              const TextSpan(text: '- ', style: TextStyle(color: Colors.black87)),
                              _buildLogMessageSpan(log.text),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  String _formatLogTimestamp(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp).toLocal();
      final month = dt.month.toString().padLeft(2, '0');
      final day = dt.day.toString().padLeft(2, '0');
      final year = dt.year;
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final second = dt.second.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return "$month/$day/$year ${hour.toString().padLeft(2, '0')}:$minute:$second $ampm";
    } catch (e) {
      return timestamp;
    }
  }

  static InlineSpan _buildLogMessageSpan(String text) {
    final boldKeywords = ['started', 'completed', 'alarm finished'];
    final fullBoldKeywords = [
      'switched to pomodoro tab', 
      'switched to short break tab', 
      'switched to long break tab',
    ];

    final lowerText = text.toLowerCase();
    
    for (var kw in fullBoldKeywords) {
      if (lowerText.contains(kw)) {
        return TextSpan(
          text: text,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 13),
        );
      }
    }

    for (var kw in boldKeywords) {
      if (lowerText.contains(kw)) {
        final index = lowerText.indexOf(kw);
        return TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 13),
          children: [
            TextSpan(text: text.substring(0, index)),
            TextSpan(text: text.substring(index, index + kw.length), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            TextSpan(text: text.substring(index + kw.length)),
          ],
        );
      }
    }

    return TextSpan(text: text, style: const TextStyle(color: Colors.black87, fontSize: 13));
  }

  Widget _logActionBtn(String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white70, width: 1.0),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: const Size(0, 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Future<void> _undoLog() async {
    _service.addLog('Triggered Undo action', 'action');
    final success = await _service.undoLog();
    if (success) _loadAll();
  }

  Future<void> _redoLog() async {
    _service.addLog('Triggered Redo action', 'action');
    final success = await _service.redoLog();
    if (success) _loadAll();
  }

  Future<void> _deleteLog(int logId) async {
    _service.addLog('Deleted a log entry (ID: $logId)', 'action');
    final success = await _service.deleteLog(logId);
    if (success) _loadAll();
  }

  Future<void> _editLog(PomodoroLog log) async {
    final controller = TextEditingController(text: log.text);
    final newText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF252542),
        title: const Text('Edit Log', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('SAVE', style: TextStyle(color: Color(0xFF00D9FF))),
          ),
        ],
      ),
    );

    if (newText != null && newText.isNotEmpty && newText != log.text) {
      _service.addLog('Edited log entry: "${log.text}" -> "$newText"', 'action');
      final success = await _service.updateLog(log.id, newText);
      if (success) _loadAll();
    }
  }

  Future<void> _clearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF252542),
        title: const Text('Clear Logs', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to clear all logs?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('CLEAR', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      _service.addLog('Cleared all logs', 'action');
      final success = await _service.clearLogs();
      if (success) _loadAll();
    }
  }

  Widget _buildAlarmsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _alarms.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ElevatedButton.icon(
              onPressed: () async {
                final newAlarm = await Navigator.push<Alarm>(
                  context,
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (context) => const AlarmDialog(),
                  ),
                );
                if (newAlarm != null) {
                  await _service.addLog('Created new alarm: ${newAlarm.name} at ${newAlarm.time24h}', 'alarm');
                  final created = await _service.createAlarm(newAlarm);
                  if (created != null) {
                    if (mounted) {
                      setState(() {
                        _alarms.add(created);
                      });
                      AlarmNotificationService().scheduleAlarms(_alarms);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Alarm created successfully')),
                      );
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failed to create alarm in backend. Showing locally.')),
                      );
                      setState(() {
                        _alarms.add(newAlarm);
                      });
                    }
                  }
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Alarm'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4C1D95),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          );
        }
        
        final alarm = _alarms[index - 1];
        final daysList = alarm.days.isEmpty ? [] : alarm.days.split(',');
        
        final dayColors = {
          'Sun': const Color(0xFFEF4444),
          'Mon': const Color(0xFFF97316),
          'Tue': const Color(0xFFEAB308),
          'Wed': const Color(0xFF22C55E),
          'Thu': const Color(0xFF3B82F6),
          'Fri': const Color(0xFFA855F7),
          'Sat': const Color(0xFFEC4899),
        };

        // Format time
        String formatTimeStr(String time24) {
          try {
            final parts = time24.split(':');
            int h = int.parse(parts[0]);
            int m = int.parse(parts[1]);
            String ampm = h >= 12 ? 'PM' : 'AM';
            int displayH = h % 12;
            if (displayH == 0) displayH = 12;
            String minStr = m.toString().padLeft(2, '0');
            return '${displayH.toString().padLeft(2, '0')}:$minStr $ampm ($time24)';
          } catch (_) {
            return time24;
          }
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF252542),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (daysList.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF08A).withOpacity(0.2),
                        border: Border.all(color: const Color(0xFFEAB308)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('🔔 ', style: TextStyle(fontSize: 14)),
                          Text('One-time alarm', style: TextStyle(color: Color(0xFFFDE047), fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    )
                  else
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: daysList.map((day) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: dayColors[day] ?? Colors.grey,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              day,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () async {
                          final result = await Navigator.push<Alarm>(
                            context,
                            MaterialPageRoute(
                              fullscreenDialog: true,
                              builder: (context) => AlarmDialog(alarm: alarm),
                            ),
                          );
                          if (result != null) {
                            // If this alarm was ringing, stop it since user just edited it
                            if (_alarmingAlarmId == alarm.id) {
                              _stopActiveAlarm();
                            }
                            _service.addLog('Updated alarm: ${result.name}', 'alarm');
                            final success = await _service.updateAlarm(result);
                            if (success) _loadAll();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFFEAB308)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () async {
                          if (alarm.id == null) return;
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: const Color(0xFF252542),
                              title: const Text('Delete Alarm', style: TextStyle(color: Colors.white)),
                              content: const Text('Are you sure you want to delete this alarm?', style: TextStyle(color: Colors.white70)),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
                                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('DELETE', style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          );
                          if (confirm == true && alarm.id != null) {
                            // If this alarm was ringing, stop it since user is deleting it
                            if (_alarmingAlarmId == alarm.id) {
                              _stopActiveAlarm();
                            }
                            _service.addLog('Deleted alarm: ${alarm.name}', 'alarm');
                            final success = await _service.deleteAlarm(alarm.id!);
                            if (success) _loadAll();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                alarm.name.isEmpty ? 'Unnamed Alarm' : alarm.name,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    formatTimeStr(alarm.time24h),
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  if (_alarmingAlarmId == alarm.id)
                    const Padding(
                      padding: EdgeInsets.only(left: 8.0),
                      child: Text('Ringing...', style: TextStyle(color: Color(0xFF00D9FF), fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (_alarmingAlarmId == alarm.id)
                OutlinedButton.icon(
                  onPressed: _stopActiveAlarm,
                  icon: const Icon(Icons.circle, color: Color(0xFF8B5CF6), size: 16),
                  label: Text('STOP ALARMING ${alarm.ringTimes}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.grey.withOpacity(0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                )
              else
                Row(
                  children: [
                    Switch(
                      value: alarm.isActive,
                      onChanged: (val) async {
                        if (alarm.id != null) {
                          // Optimistic UI update
                          setState(() {
                            final idx = _alarms.indexWhere((a) => a.id == alarm.id);
                            if (idx != -1) {
                              _alarms[idx] = alarm.copyWith(isActive: val);
                            }
                          });
                          await _service.addLog('Toggled alarm ${alarm.name} to ${val ? 'ON' : 'OFF'}', 'alarm');
                          final success = await _service.toggleAlarm(alarm.id!);
                          if (success) {
                            AlarmNotificationService().scheduleAlarms(_alarms);
                          } else {
                            // Revert on failure
                            _loadAll();
                          }
                        }
                      },
                      activeColor: Colors.white,
                      activeTrackColor: const Color(0xFF6366F1), // Indigo
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor: Colors.grey.withOpacity(0.5),
                    ),
                    const SizedBox(width: 8),
                    const Text('Active', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import '../../models/alarm.dart';

class AlarmDialog extends StatefulWidget {
  final Alarm? alarm;

  const AlarmDialog({super.key, this.alarm});

  @override
  State<AlarmDialog> createState() => _AlarmDialogState();
}

class _AlarmDialogState extends State<AlarmDialog> {
  late TextEditingController _nameController;
  late TimeOfDay _selectedTime;
  late List<bool> _selectedDays;
  late int _ringTimes;

  final List<String> _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.alarm?.name ?? '');
    
    if (widget.alarm != null) {
      final parts = widget.alarm!.time24h.split(':');
      _selectedTime = TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
      
      final days = widget.alarm!.days.split(',');
      _selectedDays = _dayNames.map((day) => days.contains(day)).toList();
      _ringTimes = widget.alarm!.ringTimes;
    } else {
      _selectedTime = TimeOfDay.now();
      _selectedDays = List.generate(7, (_) => false);
      _ringTimes = 10;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E), // Match pomodoro background
      appBar: AppBar(
        backgroundColor: const Color(0xFF252542),
        elevation: 0,
        title: Text(
          widget.alarm == null ? 'Add Alarm' : 'Edit Alarm',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Alarm Name', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                cursorColor: const Color(0xFF00D9FF),
                decoration: InputDecoration(
                  hintText: 'e.g. Wake up',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 18),
                  filled: true,
                  fillColor: const Color(0xFF252542),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
              ),
              const SizedBox(height: 32),
              
              const Text('Time', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 12),
              Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: _selectedTime,
                      builder: (context, child) {
                        return Theme(
                          data: ThemeData.dark().copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: Color(0xFF00D9FF),
                              onPrimary: Colors.black,
                              surface: Color(0xFF252542),
                              onSurface: Colors.white,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (time != null) setState(() => _selectedTime = time);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 40),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252542),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF00D9FF).withOpacity(0.3)),
                    ),
                    child: Text(
                      _selectedTime.format(context),
                      style: const TextStyle(color: Color(0xFF00D9FF), fontSize: 48, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              
              const Text('Repeat Days', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (index) {
                  final isSelected = _selectedDays[index];
                  return InkWell(
                    onTap: () => setState(() => _selectedDays[index] = !isSelected),
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF00D9FF) : const Color(0xFF252542),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        _dayNames[index][0],
                        style: TextStyle(
                          color: isSelected ? Colors.black : Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 40),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Ring Times', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  Text('$_ringTimes', style: const TextStyle(color: Color(0xFF00D9FF), fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: const Color(0xFF00D9FF),
                  inactiveTrackColor: const Color(0xFF252542),
                  thumbColor: const Color(0xFF00D9FF),
                  overlayColor: const Color(0xFF00D9FF).withOpacity(0.2),
                  trackHeight: 6,
                ),
                child: Slider(
                  value: _ringTimes.toDouble(),
                  min: 1,
                  max: 50,
                  divisions: 49,
                  onChanged: (val) => setState(() => _ringTimes = val.toInt()),
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  final daysStr = <String>[];
                  for (int i = 0; i < 7; i++) {
                    if (_selectedDays[i]) daysStr.add(_dayNames[i]);
                  }
                  
                  final alarm = Alarm(
                    id: widget.alarm?.id,
                    name: _nameController.text,
                    time24h: '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}',
                    days: daysStr.join(','),
                    isActive: widget.alarm?.isActive ?? true,
                    ringTimes: _ringTimes,
                  );
                  Navigator.pop(context, alarm);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D9FF),
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('SAVE ALARM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

# Not Pomodoro Design & Logic Manifest

This document serves as the ground-truth for the "Not Pomodoro" productivity suite integration within the Village/Messenger application.

## 1. Visual Theme (Timer Tab)
The background color of the timer tab must dynamically change based on the active session type:
- **Pomodoro Mode**: Coral (`#F06262`)
- **Short Break Mode**: Light Green (`#8BC34A`)
- **Long Break Mode**: Light Blue (`#4FC3F7`)
- **Clock Header**: Always uses a white background with a signature "Not Pomodoro" title and a high-precision live digital clock.

## 2. Lobby Navigation Constraints
When the user is on the `alarmX` tab (index 3) in the `LobbyScreen`:
- **Search Bar**: Must be hidden to provide a focused workspace.
- **Floating Action Buttons**: Both the AI Mini FAB and the New Chat FAB must be removed.
- **Bottom Navigation**: The "Alarm X" filter serves as the persistent entry point.

## 3. Event Logging (The "Everything" Rule)
The system must log every user interaction to the backend via `PomodoroService.addLog()`. This includes:
- **Timer Control**: Starting, pausing, and resetting the timer.
- **Mode Switching**: Moving between Pomodoro, Short Break, and Long Break.
- **Navigation**: Entering the suite and switching between internal tabs (Timer, Logs, Alarms).
- **Alarm Management**: Creating, editing, deleting, toggling, or manually stopping an alarm.
- **Log Management**: Executing Undo, Redo, Clear, Edit, or Delete actions on the activity log.

## 4. State & Data Integrity
- **Initialization**: `PomodoroState` must always be initialized with default values (presets, ring counts, etc.) if the backend returns null to prevent initialization build errors.
- **Synchronization**: The local state is synced to the backend every 60 seconds and on every major state transition.
- **Alarms**: Backend alarms are automatically synced to the device's local notification system (`flutter_local_notifications`) on load to ensure reliability even when the app is terminated.

## 5. Notification Logic
- **Background Persistence**: Timer and Alarm notifications must use `exactAllowWhileIdle` to ensure they fire even if the device enters low-power modes.
- **Sound**: Uses the custom `ringing(gain-down).mp3` asset for timer completions.

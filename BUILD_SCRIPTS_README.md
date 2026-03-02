# Flutter Build and Install Scripts

Automated scripts to build release APKs and install them to connected devices.

## Files

- `build_and_install.bat` - Windows Batch script (simple, works everywhere)
- `build_and_install.ps1` - PowerShell script (advanced features, better error handling)

## Quick Start

### Option 1: Batch Script (Recommended for simplicity)
```cmd
# Double-click build_and_install.bat or run from command prompt
build_and_install.bat
```

### Option 2: PowerShell Script (Recommended for advanced users)
```powershell
# Basic build and install
.\build_and_install.ps1

# Build with version increment
.\build_and_install.ps1 -IncrementVersion

# Build only (skip install)
.\build_and_install.ps1 -SkipInstall

# Build with custom version
.\build_and_install.ps1 -NewVersion "1.0.7+7"

# Build and start logcat immediately
.\build_and_install.ps1 -StartLogcat
```

## Features

### Both Scripts:
- ✅ Check Flutter and ADB availability
- ✅ Check for connected devices
- ✅ Clean previous build
- ✅ Get dependencies
- ✅ Build release APK
- ✅ Install to connected device
- ✅ Show APK size and build time
- ✅ Option to start logcat for debugging

### PowerShell Script Additional Features:
- ✅ Automatic version increment (patch/minor/major/build)
- ✅ Custom version setting
- ✅ Command line parameters
- ✅ Better error handling and colored output
- ✅ Build time measurement
- ✅ Skip install option

## Prerequisites

1. **Flutter SDK** - Must be in PATH
2. **Android SDK** - ADB must be in PATH
3. **Connected Device** - USB or wireless ADB

## Device Connection

### USB Connection:
1. Enable Developer Options on your device
2. Enable USB Debugging
3. Connect via USB cable
4. Accept debugging authorization on device

### Wireless ADB Connection:
1. Connect via USB first
2. Run: `adb tcpip 5555`
3. Find device IP address
4. Run: `adb connect [IP_ADDRESS]:5555`
5. Disconnect USB cable

## Usage Examples

### Quick Build and Install:
```cmd
build_and_install.bat
```

### Build with Version Increment:
```powershell
.\build_and_install.ps1 -IncrementVersion
```

### Build for Testing (No Install):
```powershell
.\build_and_install.ps1 -SkipInstall
```

### Build and Debug:
```powershell
.\build_and_install.ps1 -StartLogcat
```

## Troubleshooting

### "Flutter not found"
- Install Flutter SDK
- Add Flutter bin directory to PATH
- Restart terminal/command prompt

### "ADB not found"
- Install Android SDK
- Add platform-tools directory to PATH
- Or install ADB standalone

### "No devices found"
- Check USB connection
- Enable USB debugging
- Try: `adb kill-server && adb start-server`
- Check device authorization

### "Installation failed"
- Check device authorization
- Enable "Install from unknown sources"
- Try manual install: `adb install -r build\app\outputs\flutter-apk\app-release.apk`

## Output

The scripts will create:
- `build\app\outputs\flutter-apk\app-release.apk` - Release APK
- Console output with build status and timing
- Option to start logcat for debugging

## Version Management

The PowerShell script can automatically increment versions:

- **Patch**: 1.0.5+5 → 1.0.6+6 (bug fixes)
- **Minor**: 1.0.5+5 → 1.1.0+6 (new features)
- **Major**: 1.0.5+5 → 2.0.0+6 (breaking changes)
- **Build**: 1.0.5+5 → 1.0.5+6 (same version, new build)

## Tips

1. **Use PowerShell script** for better features and error handling
2. **Keep device connected** throughout the process
3. **Check logcat** if app crashes or behaves unexpectedly
4. **Increment version** for each release to avoid conflicts
5. **Test on device** after installation to verify functionality

## Current Project Status

This script is configured for the Flutter Messenger project and will:
- Build version 1.0.6+6 (or current version in pubspec.yaml)
- Include all current fixes for audio call UI issues
- Apply proguard rules for WebRTC optimization
- Generate ~87MB release APK
# Flutter Mobile App Integration

This folder contains documentation and examples for integrating Flutter mobile app with the Flask backend.

## Documentation

- [Auto-Translate Implementation](AUTO_TRANSLATE_IMPLEMENTATION.md) - Complete guide for implementing auto-translate feature
- [translate_example.dart](translate_example.dart) - Flutter code examples

## Quick Start

### 1. Backend Setup (Already Done)
The backend has been updated with:
- `/api/translate_message` endpoint in `app/routes/mobile_api.py`
- Updated `translate-manager.js` to support mobile API
- Mobile app detection in `base.html`

### 2. Flutter Setup

#### Step 1: Add Dependencies
```yaml
dependencies:
  webview_flutter: ^4.0.0
  shared_preferences: ^2.2.0
```

#### Step 2: Store Auth Token
When user logs in, store the token in WebView localStorage:
```dart
await webView.runJavaScript(
  "localStorage.setItem('auth_token', '$token');"
);
```

#### Step 3: Enable Mobile API Mode
```dart
await webView.runJavaScript(
  "window.useMobileApi = true;"
);
```

#### Step 4: Auto-Translate Toggle
```dart
await webView.runJavaScript(
  "if (window.TranslateManager) window.TranslateManager.toggle();"
);
```

## API Endpoints

### Translate Message
```
POST /api/translate_message
Authorization: Bearer <token>
Content-Type: application/json

{
  "text": "Hello world",
  "target_lang": "en"
}

Response:
{
  "success": true,
  "translation": "Hello world",
  "detected_language": "es",
  "target_language": "en"
}
```

## Features

- Auto-translate incoming messages
- Translate existing messages when enabled
- Support for multiple languages
- Detects source language automatically

## Troubleshooting

See [Auto-Translate Implementation](AUTO_TRANSLATE_IMPLEMENTATION.md) for troubleshooting guide.

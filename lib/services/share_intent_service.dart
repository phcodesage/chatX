import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SharedMediaItem {
  final String path;
  final String fileName;
  final String mimeType;

  /// Set when the item arrived via a Direct Share shortcut tap. Non-null means
  /// the user chose a specific chat contact in the Android share sheet — the
  /// ShareTargetScreen will pre-select that contact and send immediately.
  final int? directShareUserId;

  const SharedMediaItem({
    required this.path,
    required this.fileName,
    required this.mimeType,
    this.directShareUserId,
  });

  bool get isImage => mimeType.toLowerCase().startsWith('image/');

  bool get isVCard {
    final m = mimeType.toLowerCase();
    return m.contains('vcard') || m.contains('x-vcard') || fileName.toLowerCase().endsWith('.vcf');
  }

  static SharedMediaItem? fromDynamic(dynamic value) {
    if (value is! Map) {
      return null;
    }

    final rawPath = value['path']?.toString();
    if (rawPath == null || rawPath.isEmpty) {
      return null;
    }

    final rawName = value['fileName']?.toString();
    final fileName = (rawName != null && rawName.isNotEmpty)
        ? rawName
        : rawPath.split(Platform.pathSeparator).last;

    final mimeType =
        value['mimeType']?.toString() ?? 'application/octet-stream';

    final rawUserId = value['directShareUserId'];
    int? directShareUserId;
    if (rawUserId is int) {
      directShareUserId = rawUserId;
    } else if (rawUserId is String && rawUserId.isNotEmpty) {
      directShareUserId = int.tryParse(rawUserId);
    }

    return SharedMediaItem(
      path: rawPath,
      fileName: fileName,
      mimeType: mimeType,
      directShareUserId: directShareUserId,
    );
  }
}

class ShareIntentService {
  ShareIntentService._();

  static final ShareIntentService instance = ShareIntentService._();

  static const MethodChannel _channel = MethodChannel(
    'com.example.flutter_messenger_v2/share_target',
  );

  final StreamController<List<SharedMediaItem>> _sharedItemsController =
      StreamController<List<SharedMediaItem>>.broadcast();

  bool _initialized = false;
  List<SharedMediaItem> _pendingItems = const [];

  Stream<List<SharedMediaItem>> get sharedItemsStream =>
      _sharedItemsController.stream;

  bool get hasPendingItems => _pendingItems.isNotEmpty;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _initialized = true;
    _channel.setMethodCallHandler(_onMethodCall);

    final initialItems = await _consumeFromPlatform();
    if (initialItems.isNotEmpty) {
      _pendingItems = initialItems;
      _sharedItemsController.add(initialItems);
    }
  }

  Future<List<SharedMediaItem>> takePendingSharedItems() async {
    if (_pendingItems.isNotEmpty) {
      final items = List<SharedMediaItem>.from(_pendingItems);
      _pendingItems = const [];
      return items;
    }

    return _consumeFromPlatform();
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method != 'onSharedItems') {
      return null;
    }

    final items = _parseItems(call.arguments);
    if (items.isEmpty) {
      return null;
    }

    _pendingItems = items;
    _sharedItemsController.add(items);
    return null;
  }

  Future<List<SharedMediaItem>> _consumeFromPlatform() async {
    try {
      final response = await _channel.invokeMethod<dynamic>(
        'consumeInitialSharedItems',
      );
      return _parseItems(response);
    } catch (e) {
      debugPrint('ShareIntentService consumeInitialSharedItems failed: $e');
      return const [];
    }
  }

  List<SharedMediaItem> _parseItems(dynamic raw) {
    if (raw is! List) {
      return const [];
    }

    return raw
        .map(SharedMediaItem.fromDynamic)
        .whereType<SharedMediaItem>()
        .where((item) => File(item.path).existsSync())
        .toList(growable: false);
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SharedMediaItem {
  final String path;
  final String fileName;
  final String mimeType;

  const SharedMediaItem({
    required this.path,
    required this.fileName,
    required this.mimeType,
  });

  bool get isImage => mimeType.toLowerCase().startsWith('image/');

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

    return SharedMediaItem(
      path: rawPath,
      fileName: fileName,
      mimeType: mimeType,
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

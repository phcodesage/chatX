import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/group.dart';
import '../models/lobby_user.dart';
import '../models/message.dart';
import 'chat_cache_service.dart';
import 'group_service.dart';
import 'lobby_service.dart';
import 'message_service.dart';
import 'storage_service.dart';

/// Auto-download policy for chat media. Mirrors WhatsApp's settings:
/// either always download on any connection, only on Wi-Fi, or never.
enum AutoDownloadPolicy {
  never,
  wifiOnly,
  always,
}

/// Per-media-kind toggle group. Values match WhatsApp's split between
/// photos / audio / videos / documents so users can opt-out of large
/// files independently from small ones.
class AutoDownloadPreferences {
  const AutoDownloadPreferences({
    required this.images,
    required this.audio,
    required this.videos,
    required this.documents,
    required this.maxFileSizeBytes,
  });

  final AutoDownloadPolicy images;
  final AutoDownloadPolicy audio;
  final AutoDownloadPolicy videos;
  final AutoDownloadPolicy documents;

  /// Hard ceiling per file. Anything larger is skipped on auto-download
  /// regardless of policy. WhatsApp's default for video is 16 MB on
  /// cellular; we use a generous default of 100 MB and apply it to all
  /// kinds so a single 1 GB file can't blow up the cache.
  final int maxFileSizeBytes;

  /// Sensible defaults: every kind auto-downloads on any connection so
  /// the app behaves like a true offline-first messenger. The 100 MB cap
  /// per file still applies to keep a single huge attachment from
  /// blowing up the cache. If you want to be gentle on cellular data,
  /// switch any of these to [AutoDownloadPolicy.wifiOnly].
  static const AutoDownloadPreferences defaults = AutoDownloadPreferences(
    images: AutoDownloadPolicy.always,
    audio: AutoDownloadPolicy.always,
    videos: AutoDownloadPolicy.always,
    documents: AutoDownloadPolicy.always,
    maxFileSizeBytes: 100 * 1024 * 1024,
  );
}

/// Background service that hydrates the on-disk caches so the app
/// behaves like WhatsApp/Messenger:
///   - Every conversation's latest messages are stored in Hive.
///   - Every recent media file referenced by those messages is mirrored
///     into [DefaultCacheManager], the same store [CachedNetworkImage]
///     reads from, so images and videos open instantly and work offline.
///
/// Run [start] after the user is authenticated. The service self-throttles
/// (max one full pass at a time) and reschedules itself when the network
/// state changes (e.g. switching from cellular to Wi-Fi unblocks videos).
class MediaPreloadService {
  MediaPreloadService._();
  static final MediaPreloadService instance = MediaPreloadService._();

  static const String _prefsImagesPolicy = 'media_preload_images_policy';
  static const String _prefsAudioPolicy = 'media_preload_audio_policy';
  static const String _prefsVideosPolicy = 'media_preload_videos_policy';
  static const String _prefsDocumentsPolicy = 'media_preload_documents_policy';
  static const String _prefsMaxFileSize = 'media_preload_max_file_size';

  /// How many media files we let download in parallel. Keeps the network
  /// pipe responsive for the foreground UI.
  static const int _maxConcurrentDownloads = 3;

  final BaseCacheManager _cacheManager = DefaultCacheManager();
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  AutoDownloadPreferences _prefs = AutoDownloadPreferences.defaults;
  Future<void>? _runningPass;
  bool _started = false;
  bool _onWifi = false;
  bool _hasConnection = false;
  Timer? _rescanTimer;

  /// Latest known auto-download policy. Loaded from SharedPreferences on
  /// [start] and kept in sync when [updatePreferences] is called.
  AutoDownloadPreferences get preferences => _prefs;

  /// Begin the background sync loop. Safe to call multiple times — the
  /// first call wins and subsequent ones are no-ops.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    await _loadPreferences();

    final initial = await _connectivity.checkConnectivity();
    _applyConnectivity(initial);

    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      _applyConnectivity(results);
    });

    // Kick off the first pass immediately so cold-launch users see a
    // hydrated cache as fast as the network allows.
    unawaited(triggerSync());
  }

  Future<void> stop() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    _rescanTimer?.cancel();
    _rescanTimer = null;
    _started = false;
  }

  /// Update the user's auto-download policy and persist it. The next
  /// sync pass picks up the new policy automatically.
  Future<void> updatePreferences(AutoDownloadPreferences prefs) async {
    _prefs = prefs;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_prefsImagesPolicy, prefs.images.index);
    await sp.setInt(_prefsAudioPolicy, prefs.audio.index);
    await sp.setInt(_prefsVideosPolicy, prefs.videos.index);
    await sp.setInt(_prefsDocumentsPolicy, prefs.documents.index);
    await sp.setInt(_prefsMaxFileSize, prefs.maxFileSizeBytes);
  }

  /// Manually request a sync pass (e.g. after login).
  Future<void> triggerSync() {
    final existing = _runningPass;
    if (existing != null) return existing;
    final task = _runSyncPass();
    _runningPass = task;
    task.whenComplete(() {
      if (identical(_runningPass, task)) {
        _runningPass = null;
      }
    });
    return task;
  }

  /// Prefetch every media file referenced by [messages] into the on-disk
  /// cache, subject to the current auto-download policy. Call this after
  /// a chat screen finishes loading messages (or whenever a new message
  /// arrives) so the file is available offline on the next open.
  ///
  /// Fire-and-forget. Errors are swallowed per-file so one failed
  /// attachment doesn't block the rest.
  Future<void> prefetchMessages(Iterable<Message> messages) async {
    final tasks = <_MediaTask>[];
    for (final m in messages) {
      final task = _taskFromMessage(m);
      if (task != null) tasks.add(task);
    }
    await _runWithConcurrency<_MediaTask>(tasks, _maxConcurrentDownloads, _prefetchFile);
  }

  /// Group-chat counterpart of [prefetchMessages].
  Future<void> prefetchGroupMessages(Iterable<GroupMessage> messages) async {
    final tasks = <_MediaTask>[];
    for (final m in messages) {
      final task = _taskFromGroupMessage(m);
      if (task != null) tasks.add(task);
    }
    await _runWithConcurrency<_MediaTask>(tasks, _maxConcurrentDownloads, _prefetchFile);
  }

  Future<void> _loadPreferences() async {
    final sp = await SharedPreferences.getInstance();
    AutoDownloadPolicy resolve(String key, AutoDownloadPolicy fallback) {
      final raw = sp.getInt(key);
      if (raw == null) return fallback;
      if (raw < 0 || raw >= AutoDownloadPolicy.values.length) return fallback;
      return AutoDownloadPolicy.values[raw];
    }

    _prefs = AutoDownloadPreferences(
      images: resolve(_prefsImagesPolicy, AutoDownloadPreferences.defaults.images),
      audio: resolve(_prefsAudioPolicy, AutoDownloadPreferences.defaults.audio),
      videos: resolve(_prefsVideosPolicy, AutoDownloadPreferences.defaults.videos),
      documents: resolve(_prefsDocumentsPolicy, AutoDownloadPreferences.defaults.documents),
      maxFileSizeBytes: sp.getInt(_prefsMaxFileSize) ??
          AutoDownloadPreferences.defaults.maxFileSizeBytes,
    );
  }

  void _applyConnectivity(List<ConnectivityResult> results) {
    _hasConnection = results.isNotEmpty &&
        !results.contains(ConnectivityResult.none);
    final onWifi = results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);

    final transitionedToWifi = onWifi && !_onWifi;
    _onWifi = onWifi;

    if (!_hasConnection) return;

    // When switching from cellular to Wi-Fi, kick another pass so videos
    // and other Wi-Fi-only files get filled in retroactively.
    if (transitionedToWifi) {
      _rescanTimer?.cancel();
      _rescanTimer = Timer(const Duration(seconds: 2), () {
        unawaited(triggerSync());
      });
    }
  }

  Future<void> _runSyncPass() async {
    if (!_hasConnection) return;
    final currentUserId = await StorageService.getUserId();
    if (currentUserId == null) return;

    try {
      // 1. Hydrate the lobby (1:1 contacts) and groups lists.
      final users = await _safe(() => LobbyService.getLobbyUsers(), const <LobbyUser>[]);
      if (users.isNotEmpty) {
        await ChatCacheService.saveLobbyUsers(currentUserId, users);
      }
      final groups = await _safe(() => GroupService.getGroups(), const <Group>[]);

      // 2. Fan out per-conversation message fetches. Bound concurrency so
      //    we don't open dozens of sockets at once.
      await _runWithConcurrency<LobbyUser>(
        users,
        _maxConcurrentDownloads,
        (user) => _hydrateConversation(currentUserId, user.id),
      );

      await _runWithConcurrency<Group>(
        groups,
        _maxConcurrentDownloads,
        (group) => _hydrateGroup(group.id),
      );

      // 3. Walk every cached message and prefetch the file behind it
      //    (subject to policy + size cap).
      final messageFileTasks = <_MediaTask>[];
      for (final user in users) {
        final cached = await ChatCacheService.loadConversationMessages(
          currentUserId,
          user.id,
        );
        for (final msg in cached) {
          final task = _taskFromMessage(msg);
          if (task != null) messageFileTasks.add(task);
        }
        if (user.avatarUrl != null && user.avatarUrl!.isNotEmpty) {
          messageFileTasks.add(_MediaTask(user.avatarUrl!, _MediaKind.image, null));
        }
      }
      for (final group in groups) {
        final cached = await ChatCacheService.loadGroupMessages(group.id);
        for (final msg in cached) {
          final task = _taskFromGroupMessage(msg);
          if (task != null) messageFileTasks.add(task);
        }
        if (group.avatarUrl != null && group.avatarUrl!.isNotEmpty) {
          messageFileTasks.add(_MediaTask(group.avatarUrl!, _MediaKind.image, null));
        }
      }

      // De-dupe so we don't refetch the same URL multiple times in one pass.
      final seen = <String>{};
      final uniqueTasks = <_MediaTask>[];
      for (final task in messageFileTasks) {
        if (seen.add(task.url)) uniqueTasks.add(task);
      }

      await _runWithConcurrency<_MediaTask>(
        uniqueTasks,
        _maxConcurrentDownloads,
        _prefetchFile,
      );
    } catch (e, st) {
      debugPrint('[MediaPreloadService] sync pass failed: $e\n$st');
    }
  }

  Future<void> _hydrateConversation(int currentUserId, int otherUserId) async {
    try {
      // offlineFirst: false — we want a real network round trip so the
      // local cache mirrors the server. The result is automatically
      // saved to ChatCacheService inside MessageService.
      await MessageService.getConversationMessages(
        userId: otherUserId,
        limit: 50,
        offlineFirst: false,
      );
    } catch (e) {
      debugPrint('[MediaPreloadService] conv $otherUserId fetch failed: $e');
    }
  }

  Future<void> _hydrateGroup(int groupId) async {
    try {
      await GroupService.getMessages(groupId: groupId, limit: 50);
    } catch (e) {
      debugPrint('[MediaPreloadService] group $groupId fetch failed: $e');
    }
  }

  Future<void> _prefetchFile(_MediaTask task) async {
    try {
      // Skip if the file is already in cache to avoid re-download.
      final fromCache = await _cacheManager.getFileFromCache(task.url);
      if (fromCache != null) return;

      if (!_isPolicyAllowed(task.kind)) return;
      if (task.fileSize != null &&
          task.fileSize! > _prefs.maxFileSizeBytes) {
        return;
      }
      await _cacheManager.downloadFile(task.url);
    } catch (e) {
      // Silent: a single failed file shouldn't kill the whole pass.
      debugPrint('[MediaPreloadService] prefetch failed (${task.url}): $e');
    }
  }

  bool _isPolicyAllowed(_MediaKind kind) {
    final policy = switch (kind) {
      _MediaKind.image => _prefs.images,
      _MediaKind.audio => _prefs.audio,
      _MediaKind.video => _prefs.videos,
      _MediaKind.document => _prefs.documents,
    };
    switch (policy) {
      case AutoDownloadPolicy.never:
        return false;
      case AutoDownloadPolicy.wifiOnly:
        return _onWifi;
      case AutoDownloadPolicy.always:
        return true;
    }
  }

  _MediaTask? _taskFromMessage(Message message) {
    final url = message.fileUrl;
    if (url == null || url.isEmpty) return null;
    if (message.isDeleted) return null;
    final kind = _kindFromMessageType(message.messageType, url);
    if (kind == null) return null;
    return _MediaTask(url, kind, message.fileSize);
  }

  _MediaTask? _taskFromGroupMessage(GroupMessage message) {
    final url = message.fileUrl;
    if (url == null || url.isEmpty) return null;
    if (message.isDeleted) return null;
    final kind = _kindFromMessageType(message.messageType, url);
    if (kind == null) return null;
    return _MediaTask(url, kind, message.fileSize);
  }

  _MediaKind? _kindFromMessageType(String messageType, String url) {
    final type = messageType.toLowerCase();
    if (type == 'image' || type == 'photo') return _MediaKind.image;
    if (type == 'video') return _MediaKind.video;
    if (type == 'audio' || type == 'voice') return _MediaKind.audio;
    if (type == 'file' || type == 'document') return _MediaKind.document;
    // Fall back to the URL extension when the server didn't tag the type.
    final lower = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    if (RegExp(r'\.(png|jpe?g|gif|webp|bmp|heic)$').hasMatch(lower)) {
      return _MediaKind.image;
    }
    if (RegExp(r'\.(mp4|mov|webm|mkv|avi|m4v)$').hasMatch(lower)) {
      return _MediaKind.video;
    }
    if (RegExp(r'\.(mp3|m4a|wav|ogg|aac|opus)$').hasMatch(lower)) {
      return _MediaKind.audio;
    }
    return _MediaKind.document;
  }

  Future<T> _safe<T>(Future<T> Function() fn, T fallback) async {
    try {
      return await fn();
    } catch (e) {
      debugPrint('[MediaPreloadService] $e');
      return fallback;
    }
  }

  Future<void> _runWithConcurrency<T>(
    List<T> items,
    int limit,
    Future<void> Function(T) task,
  ) async {
    if (items.isEmpty) return;
    final iter = items.iterator;
    final workers = <Future<void>>[];
    for (var i = 0; i < limit; i++) {
      workers.add(() async {
        while (true) {
          T next;
          if (!iter.moveNext()) return;
          next = iter.current;
          await task(next);
        }
      }());
    }
    await Future.wait(workers);
  }
}

enum _MediaKind { image, audio, video, document }

class _MediaTask {
  const _MediaTask(this.url, this.kind, this.fileSize);
  final String url;
  final _MediaKind kind;
  final int? fileSize;
}

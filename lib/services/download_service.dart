import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../models/download_item.dart';
import 'app_services.dart';
import '../utils/download_paths.dart';

class DownloadService {
  DownloadService._();
  static final DownloadService instance = DownloadService._();

  final List<DownloadItem> _items = [];
  final Map<String, DownloadItem> _itemsByPath = {};
  final Map<String, DateTime> _lastCloudSync = {};
  final ValueNotifier<int> activeDownloadsCount = ValueNotifier<int>(0);
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  int _nextDownloadId = 0;

  List<DownloadItem> get items => List.unmodifiable(_items);

  static const String _kind = 'download';

  /// Initializes the DownloadService: loads download history (signed-in only).
  Future<void> initialize() async {
    await fetchHistoryFromCloud();
  }

  /// Loads download history from the encrypted cloud store. Nothing is kept
  /// on disk; guests only see downloads from the current run.
  Future<void> fetchHistoryFromCloud() async {
    final cloud = AppServices.cloud;
    if (!cloud.isSyncing) return;
    try {
      final rows = await cloud.load(_kind, limit: 100);
      final activeItems = _items
          .where((item) => item.status == DownloadStatus.downloading)
          .toList();
      _items
        ..clear()
        ..addAll(activeItems);
      for (final row in rows) {
        final item = DownloadItem.fromSupabaseMap(row);
        if (item.id.isNotEmpty && !_items.any((e) => e.id == item.id)) {
          _items.add(item);
        }
      }
      _items.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      _itemsByPath
        ..clear()
        ..addEntries(
          activeItems
              .where((item) => item.localPath.isNotEmpty)
              .map((item) => MapEntry(item.localPath, item)),
        );
      _updateActiveCount();
      revision.value++;
    } catch (e) {
      debugPrint('DownloadService.fetchHistoryFromCloud error: ${e.runtimeType}');
    }
  }

  /// Clears in-memory downloads (sign-out).
  void clearMemory() {
    _items.removeWhere((i) => i.status != DownloadStatus.downloading);
    _updateActiveCount();
    revision.value++;
  }

  /// Syncs a download's state to the encrypted cloud store.
  Future<void> _syncToCloud(DownloadItem item) async {
    final cloud = AppServices.cloud;
    if (!cloud.isSyncing) return;
    cloud.put(_kind, item.id, item.toSupabaseMap());
  }

  /// Records downloads performed by WebView2, preserving its cookies and
  /// authenticated browser context.
  void handleWebviewDownloadEvent(WebviewDownloadEvent event) {
    final now = DateTime.now();
    final path = event.resultFilePath;
    DownloadItem? item = path.isEmpty ? null : _itemsByPath[path];

    if (event.kind == WebviewDownloadEventKind.downloadStarted) {
      final filename = _filenameFromPath(path);
      item = DownloadItem(
        id: 'webview_${now.microsecondsSinceEpoch}_${_nextDownloadId++}',
        url: event.url,
        filename: filename.isEmpty
            ? downloadFilenameFromUrl(event.url)
            : filename,
        localPath: path,
        totalBytes: event.totalBytesToReceive > 0
            ? event.totalBytesToReceive
            : 0,
        status: DownloadStatus.downloading,
      );
      _items.insert(0, item);
      if (path.isNotEmpty) _itemsByPath[path] = item;
      _lastCloudSync[item.id] = now;
      unawaited(_syncToCloud(item));
    } else {
      item ??= _items.firstWhereOrNull(
        (candidate) =>
            candidate.url == event.url &&
            candidate.status == DownloadStatus.downloading,
      );
      if (item == null) return;
    }

    if (event.resultFilePath.isNotEmpty) {
      item.localPath = event.resultFilePath;
      _itemsByPath[event.resultFilePath] = item;
    }
    item.downloadedBytes = event.bytesReceived < 0 ? 0 : event.bytesReceived;
    if (event.totalBytesToReceive > 0) {
      item.totalBytes = event.totalBytesToReceive;
    }
    item.updateSpeed(item.downloadedBytes);

    if (event.kind == WebviewDownloadEventKind.downloadCompleted) {
      item.status = DownloadStatus.completed;
      item.completedAt = now;
      item.speedBytesPerSec = 0;
      _lastCloudSync.remove(item.id);
      unawaited(_syncToCloud(item));
    } else if (event.kind == WebviewDownloadEventKind.downloadProgress &&
        now.difference(_lastCloudSync[item.id] ?? DateTime(0)).inMilliseconds >=
            1500) {
      _lastCloudSync[item.id] = now;
      unawaited(_syncToCloud(item));
    }

    _updateActiveCount();
    revision.value++;
  }

  String _filenameFromPath(String path) {
    if (path.isEmpty) return '';
    return path.split(RegExp(r'[\\/]')).last;
  }

  Future<void> deleteFromHistory(String id) async {
    final item = _items.firstWhereOrNull((candidate) => candidate.id == id);
    _items.removeWhere((i) => i.id == id);
    if (item != null) {
      _itemsByPath.remove(item.localPath);
      _lastCloudSync.remove(item.id);
    }
    _updateActiveCount();
    revision.value++;
    AppServices.cloud.remove(_kind, id);
  }

  void _updateActiveCount() {
    activeDownloadsCount.value = _items
        .where((i) => i.status == DownloadStatus.downloading)
        .length;
  }
}

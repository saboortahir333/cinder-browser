import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/models/download_item.dart';
import 'package:saboor_browser/services/download_service.dart';
import 'package:saboor_browser/utils/download_paths.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

void main() {
  group('downloadFilenameFromUrl', () {
    test('uses the last path segment', () {
      expect(
        downloadFilenameFromUrl('https://example.com/a/b/file.zip'),
        'file.zip',
      );
    });

    test('percent-decodes the segment', () {
      expect(
        downloadFilenameFromUrl('https://example.com/my%20report.pdf'),
        'my report.pdf',
      );
    });

    test('ignores query strings and fragments', () {
      expect(
        downloadFilenameFromUrl('https://example.com/file.zip?token=abc#frag'),
        'file.zip',
      );
    });

    test('replaces characters Windows forbids in file names', () {
      expect(
        downloadFilenameFromUrl('https://example.com/a:b|c?d*e.zip'),
        'a_b_c',
      );
    });

    test('falls back to a timestamped name for directory-like URLs', () {
      expect(
        downloadFilenameFromUrl('https://example.com/'),
        startsWith('download_'),
      );
      expect(
        downloadFilenameFromUrl('https://example.com'),
        startsWith('download_'),
      );
    });

    test('falls back when the segment is only dots', () {
      expect(
        downloadFilenameFromUrl('https://example.com/...'),
        startsWith('download_'),
      );
    });

    test('never leaks a path separator via encoded traversal', () {
      final name = downloadFilenameFromUrl(
        'https://example.com/%2e%2e%2f%2e%2e%2fetc%2fpasswd',
      );
      expect(name.contains(Platform.pathSeparator), isFalse);
      expect(name.contains('/'), isFalse);
    });
  });

  group('uniqueDownloadFilename', () {
    late Directory temporaryDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp('saboor_dl_');
    });

    tearDown(() async {
      if (temporaryDirectory.existsSync()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('keeps the name when the destination is free', () {
      expect(
        uniqueDownloadFilename(temporaryDirectory.path, 'file.zip'),
        'file.zip',
      );
    });

    test(
      'inserts a counter before the extension when the file exists',
      () async {
        File(
          '${temporaryDirectory.path}${Platform.pathSeparator}file.zip',
        ).writeAsStringSync('x');
        expect(
          uniqueDownloadFilename(temporaryDirectory.path, 'file.zip'),
          'file (1).zip',
        );
      },
    );

    test('increments past existing duplicates', () async {
      final separator = Platform.pathSeparator;
      File(
        '${temporaryDirectory.path}${separator}file.zip',
      ).writeAsStringSync('x');
      File(
        '${temporaryDirectory.path}${separator}file (1).zip',
      ).writeAsStringSync('x');
      File(
        '${temporaryDirectory.path}${separator}file (2).zip',
      ).writeAsStringSync('x');
      expect(
        uniqueDownloadFilename(temporaryDirectory.path, 'file.zip'),
        'file (3).zip',
      );
    });

    test('handles names without an extension', () async {
      File(
        '${temporaryDirectory.path}${Platform.pathSeparator}README',
      ).writeAsStringSync('x');
      expect(
        uniqueDownloadFilename(temporaryDirectory.path, 'README'),
        'README (1)',
      );
    });
  });

  test('tracks WebView2 download start, progress, and completion', () {
    final service = DownloadService.instance;
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}webview_${DateTime.now().microsecondsSinceEpoch}.zip';
    const url = 'https://example.com/archive.zip';

    service.handleWebviewDownloadEvent(
      WebviewDownloadEvent(
        WebviewDownloadEventKind.downloadStarted,
        url,
        path,
        0,
        1024,
      ),
    );
    final item = service.items.firstWhere((item) => item.url == url);
    service.handleWebviewDownloadEvent(
      WebviewDownloadEvent(
        WebviewDownloadEventKind.downloadProgress,
        url,
        path,
        512,
        1024,
      ),
    );

    expect(item.status, DownloadStatus.downloading);
    expect(item.downloadedBytes, 512);
    expect(item.totalBytes, 1024);
    expect(item.localPath, path);
    expect(service.activeDownloadsCount.value, 1);

    service.handleWebviewDownloadEvent(
      WebviewDownloadEvent(
        WebviewDownloadEventKind.downloadCompleted,
        url,
        path,
        1024,
        1024,
      ),
    );

    expect(item.status, DownloadStatus.completed);
    expect(item.downloadedBytes, 1024);
    expect(item.completedAt, isNotNull);
    expect(service.activeDownloadsCount.value, 0);
  });
}

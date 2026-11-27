import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Memory of one process.
class ProcMem {
  const ProcMem({
    required this.pid,
    required this.name,
    required this.privateBytes,
    required this.workingSetBytes,
  });

  final int pid;
  final String name;
  final int privateBytes;
  final int workingSetBytes;

  Map<String, Object?> toJson() => {
    'pid': pid,
    'name': name,
    'privateBytes': privateBytes,
    'workingSetBytes': workingSetBytes,
  };
}

/// Memory of Cinder itself plus every WebView2 process it started.
class MemoryTree {
  const MemoryTree({required this.app, required this.children});

  final ProcMem app;
  final List<ProcMem> children;

  int get childPrivateBytes =>
      children.fold(0, (sum, p) => sum + p.privateBytes);
  int get childWorkingSetBytes =>
      children.fold(0, (sum, p) => sum + p.workingSetBytes);
  int get totalPrivateBytes => app.privateBytes + childPrivateBytes;

  Map<String, Object?> toJson() => {
    'appPrivateBytes': app.privateBytes,
    'appWorkingSetBytes': app.workingSetBytes,
    'webviewProcessCount': children.length,
    'webviewPrivateBytes': childPrivateBytes,
    'webviewWorkingSetBytes': childWorkingSetBytes,
    'totalPrivateBytes': totalPrivateBytes,
    'processes': [for (final p in children) p.toJson()],
  };
}

typedef _SnapshotC = IntPtr Function(Uint32, Uint32);
typedef _SnapshotD = int Function(int, int);
typedef _ProcEntryC = Int32 Function(IntPtr, Pointer<Uint8>);
typedef _ProcEntryD = int Function(int, Pointer<Uint8>);
typedef _OpenC = IntPtr Function(Uint32, Int32, Uint32);
typedef _OpenD = int Function(int, int, int);
typedef _CloseC = Int32 Function(IntPtr);
typedef _CloseD = int Function(int);
typedef _MemInfoC = Int32 Function(IntPtr, Pointer<Uint8>, Uint32);
typedef _MemInfoD = int Function(int, Pointer<Uint8>, int);

/// Reads process memory through the Win32 toolhelp and psapi APIs. Read-only:
/// it opens processes with PROCESS_QUERY_LIMITED_INFORMATION and never writes.
class WinMemory {
  WinMemory._();

  static const int _th32csSnapProcess = 0x00000002;
  static const int _processQueryLimitedInformation = 0x1000;
  static const int _invalidHandle = -1;

  // PROCESSENTRY32W (64-bit) layout.
  static const int _entrySize = 568;
  static const int _entryPidOffset = 8;
  static const int _entryParentOffset = 32;
  static const int _entryNameOffset = 44;
  static const int _entryNameChars = 260;

  // PROCESS_MEMORY_COUNTERS_EX layout.
  static const int _countersSize = 80;
  static const int _workingSetOffset = 16;
  static const int _privateUsageOffset = 72;

  static _SnapshotD? _snapshot;
  static _ProcEntryD? _first;
  static _ProcEntryD? _next;
  static _OpenD? _open;
  static _CloseD? _close;
  static _MemInfoD? _memInfo;

  static bool _bind() {
    if (!Platform.isWindows) return false;
    if (_snapshot != null) return true;
    try {
      final k32 = DynamicLibrary.open('kernel32.dll');
      _snapshot = k32.lookupFunction<_SnapshotC, _SnapshotD>(
        'CreateToolhelp32Snapshot',
      );
      _first = k32.lookupFunction<_ProcEntryC, _ProcEntryD>('Process32FirstW');
      _next = k32.lookupFunction<_ProcEntryC, _ProcEntryD>('Process32NextW');
      _open = k32.lookupFunction<_OpenC, _OpenD>('OpenProcess');
      _close = k32.lookupFunction<_CloseC, _CloseD>('CloseHandle');
      _memInfo = k32.lookupFunction<_MemInfoC, _MemInfoD>(
        'K32GetProcessMemoryInfo',
      );
      return true;
    } catch (_) {
      _snapshot = null;
      return false;
    }
  }

  /// Memory for this process and all of its descendants, or null when it
  /// cannot be read (not Windows, or the Win32 calls are unavailable).
  static MemoryTree? snapshot() {
    if (!_bind()) return null;
    final entries = _enumerate();
    if (entries == null) return null;

    final self = pid;
    final childrenOf = <int, List<_Entry>>{};
    for (final e in entries) {
      childrenOf.putIfAbsent(e.parent, () => []).add(e);
    }

    final descendants = <_Entry>[];
    final queue = Queue<int>()..add(self);
    final seen = <int>{self};
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      for (final child in childrenOf[current] ?? const <_Entry>[]) {
        if (seen.add(child.pid)) {
          descendants.add(child);
          queue.add(child.pid);
        }
      }
    }

    final app =
        _memoryOf(self, 'app') ??
        const ProcMem(pid: 0, name: 'app', privateBytes: 0, workingSetBytes: 0);
    final children = <ProcMem>[
      for (final d in descendants)
        if (_memoryOf(d.pid, d.name) case final mem?) mem,
    ];
    return MemoryTree(app: app, children: children);
  }

  static List<_Entry>? _enumerate() {
    final snap = _snapshot!(_th32csSnapProcess, 0);
    if (snap == _invalidHandle || snap == 0) return null;
    final buffer = calloc<Uint8>(_entrySize);
    try {
      final view = buffer.asTypedList(_entrySize);
      final data = ByteData.view(view.buffer, view.offsetInBytes, _entrySize);
      data.setUint32(0, _entrySize, Endian.little);

      final out = <_Entry>[];
      var ok = _first!(snap, buffer);
      while (ok != 0) {
        final units = <int>[];
        for (var i = 0; i < _entryNameChars; i++) {
          final u = data.getUint16(_entryNameOffset + i * 2, Endian.little);
          if (u == 0) break;
          units.add(u);
        }
        out.add(
          _Entry(
            pid: data.getUint32(_entryPidOffset, Endian.little),
            parent: data.getUint32(_entryParentOffset, Endian.little),
            name: String.fromCharCodes(units),
          ),
        );
        ok = _next!(snap, buffer);
      }
      return out;
    } finally {
      calloc.free(buffer);
      _close!(snap);
    }
  }

  static ProcMem? _memoryOf(int processId, String name) {
    final handle = _open!(_processQueryLimitedInformation, 0, processId);
    if (handle == 0) return null;
    final counters = calloc<Uint8>(_countersSize);
    try {
      final view = counters.asTypedList(_countersSize);
      ByteData.view(
        view.buffer,
        view.offsetInBytes,
        _countersSize,
      ).setUint32(0, _countersSize, Endian.little);
      if (_memInfo!(handle, counters, _countersSize) == 0) return null;
      final data = ByteData.view(
        view.buffer,
        view.offsetInBytes,
        _countersSize,
      );
      return ProcMem(
        pid: processId,
        name: name,
        privateBytes: data.getUint64(_privateUsageOffset, Endian.little),
        workingSetBytes: data.getUint64(_workingSetOffset, Endian.little),
      );
    } finally {
      calloc.free(counters);
      _close!(handle);
    }
  }
}

class _Entry {
  const _Entry({required this.pid, required this.parent, required this.name});
  final int pid;
  final int parent;
  final String name;
}

/// Compact human-readable size, e.g. `412 MB`.
String formatBytes(int bytes) {
  const mb = 1024 * 1024;
  if (bytes >= 1024 * mb)
    return '${(bytes / (1024 * mb)).toStringAsFixed(2)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(0)} MB';
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}

/// Keeps dart:convert imported for callers that serialise a [MemoryTree].
String memoryTreeToJson(MemoryTree tree) => jsonEncode(tree.toJson());

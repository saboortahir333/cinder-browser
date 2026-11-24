import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'package:saboor_browser/security/secure_storage.dart';

/// Windows Data Protection API (DPAPI) backed [SecretStore].
///
/// Each secret is encrypted with the signed-in Windows user's credentials
/// (`CryptProtectData`), so the file is useless to other Windows accounts and
/// to anything copying it off the machine. It replaces the
/// `flutter_secure_storage` plugin, whose native code needs the Visual Studio
/// ATL component to build.
///
/// Security properties:
///  * fail closed: if DPAPI is unavailable or errors, nothing is written in
///    plaintext and reads return null;
///  * `CRYPTPROTECT_UI_FORBIDDEN`: never shows a prompt that could be spoofed;
///  * per-key entropy (app + key name) separates our blobs from other DPAPI
///    users running as the same Windows account and stops blob swapping;
///  * file names are SHA-256 of the key (no path injection from key names);
///  * atomic writes (temp file + rename) so a crash cannot leave a torn blob;
///  * values and plaintext buffers are zeroed after use; nothing is logged.
class DpapiSecretStore implements SecretStore {
  DpapiSecretStore({String? directory})
    : _directory = directory ?? _defaultDirectory();

  final String? _directory;

  static const int maxValueBytes = 64 * 1024;
  static final RegExp _keyPattern = RegExp(r'^[A-Za-z0-9._\-]{1,200}$');

  /// Entropy binds each blob to its key name, so a blob copied between
  /// secret files (e.g. by malware with file access) does not decrypt as a
  /// different secret.
  static Uint8List _entropyFor(String key) =>
      Uint8List.fromList(utf8.encode('cinder.secretstore.v1|$key'));

  static const int _cryptProtectUiForbidden = 0x1;

  static String? _defaultDirectory() {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null || local.isEmpty) return null;
    return '$local${Platform.pathSeparator}Cinder${Platform.pathSeparator}secrets';
  }

  bool get isAvailable => Platform.isWindows && _directory != null;

  @override
  Future<String?> read(String key) async {
    if (!isAvailable || !_keyPattern.hasMatch(key)) return null;
    try {
      final file = File(_pathFor(key));
      if (!file.existsSync()) return null;
      final blob = await file.readAsBytes();
      if (blob.isEmpty || blob.length > maxValueBytes * 2) return null;
      final clear = _unprotect(blob, _entropyFor(key));
      if (clear == null) return null;
      try {
        return utf8.decode(clear);
      } finally {
        clear.fillRange(0, clear.length, 0);
      }
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    if (!isAvailable || !_keyPattern.hasMatch(key)) return;
    final clear = Uint8List.fromList(utf8.encode(value));
    try {
      if (clear.length > maxValueBytes) return;
      final protectedBlob = _protect(clear, _entropyFor(key));
      if (protectedBlob == null) return; // fail closed: never store plaintext
      final dir = Directory(_directory!);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final target = File(_pathFor(key));
      final temp = File('${target.path}.tmp');
      await temp.writeAsBytes(protectedBlob, flush: true);
      await temp.rename(target.path);
    } catch (error) {
      debugPrint('DpapiSecretStore.write failed: ${error.runtimeType}');
    } finally {
      clear.fillRange(0, clear.length, 0);
    }
  }

  @override
  Future<void> delete(String key) async {
    if (!isAvailable || !_keyPattern.hasMatch(key)) return;
    try {
      final file = File(_pathFor(key));
      if (file.existsSync()) {
        // Best-effort overwrite before unlinking.
        final length = file.lengthSync();
        if (length > 0 && length <= maxValueBytes * 2) {
          await file.writeAsBytes(Uint8List(length), flush: true);
        }
        await file.delete();
      }
    } catch (_) {}
  }

  String _pathFor(String key) {
    final name = sha256.convert(utf8.encode(key)).toString();
    return '$_directory${Platform.pathSeparator}$name.bin';
  }

  // -- DPAPI via FFI --------------------------------------------------------

  static final DynamicLibrary _crypt32 = DynamicLibrary.open('crypt32.dll');
  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

  static final int Function(
    Pointer<_DataBlob>,
    Pointer<Utf16>,
    Pointer<_DataBlob>,
    Pointer<Void>,
    Pointer<Void>,
    int,
    Pointer<_DataBlob>,
  )
  _cryptProtectData = _crypt32
      .lookupFunction<
        Int32 Function(
          Pointer<_DataBlob>,
          Pointer<Utf16>,
          Pointer<_DataBlob>,
          Pointer<Void>,
          Pointer<Void>,
          Uint32,
          Pointer<_DataBlob>,
        ),
        int Function(
          Pointer<_DataBlob>,
          Pointer<Utf16>,
          Pointer<_DataBlob>,
          Pointer<Void>,
          Pointer<Void>,
          int,
          Pointer<_DataBlob>,
        )
      >('CryptProtectData');

  static final int Function(
    Pointer<_DataBlob>,
    Pointer<Pointer<Utf16>>,
    Pointer<_DataBlob>,
    Pointer<Void>,
    Pointer<Void>,
    int,
    Pointer<_DataBlob>,
  )
  _cryptUnprotectData = _crypt32
      .lookupFunction<
        Int32 Function(
          Pointer<_DataBlob>,
          Pointer<Pointer<Utf16>>,
          Pointer<_DataBlob>,
          Pointer<Void>,
          Pointer<Void>,
          Uint32,
          Pointer<_DataBlob>,
        ),
        int Function(
          Pointer<_DataBlob>,
          Pointer<Pointer<Utf16>>,
          Pointer<_DataBlob>,
          Pointer<Void>,
          Pointer<Void>,
          int,
          Pointer<_DataBlob>,
        )
      >('CryptUnprotectData');

  static final Pointer<Void> Function(Pointer<Void>) _localFree = _kernel32
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('LocalFree');

  /// Fills a native DATA_BLOB with a copy of [bytes]; caller frees via
  /// [_freeInBlob].
  static Pointer<_DataBlob> _newInBlob(Uint8List bytes) {
    final blob = calloc<_DataBlob>();
    final data = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    data.asTypedList(bytes.length).setAll(0, bytes);
    blob.ref
      ..cbData = bytes.length
      ..pbData = data;
    return blob;
  }

  static void _freeInBlob(Pointer<_DataBlob> blob) {
    final length = blob.ref.cbData;
    final data = blob.ref.pbData;
    if (data != nullptr) {
      data.asTypedList(length).fillRange(0, length, 0);
      calloc.free(data);
    }
    calloc.free(blob);
  }

  static Uint8List? _protect(Uint8List clear, Uint8List entropyBytes) {
    final input = _newInBlob(clear);
    final entropy = _newInBlob(entropyBytes);
    final output = calloc<_DataBlob>();
    final description = 'Cinder secret'.toNativeUtf16();
    try {
      final ok = _cryptProtectData(
        input,
        description,
        entropy,
        nullptr,
        nullptr,
        _cryptProtectUiForbidden,
        output,
      );
      if (ok == 0) return null;
      return _takeOutBlob(output);
    } finally {
      calloc.free(description);
      _freeInBlob(input);
      _freeInBlob(entropy);
      calloc.free(output);
    }
  }

  static Uint8List? _unprotect(Uint8List blob, Uint8List entropyBytes) {
    final input = _newInBlob(blob);
    final entropy = _newInBlob(entropyBytes);
    final output = calloc<_DataBlob>();
    try {
      final ok = _cryptUnprotectData(
        input,
        nullptr,
        entropy,
        nullptr,
        nullptr,
        _cryptProtectUiForbidden,
        output,
      );
      if (ok == 0) return null;
      return _takeOutBlob(output, wipe: true);
    } finally {
      _freeInBlob(input);
      _freeInBlob(entropy);
      calloc.free(output);
    }
  }

  /// Copies a DPAPI-allocated output blob into Dart memory, wipes it
  /// (optionally) and releases it with LocalFree.
  static Uint8List _takeOutBlob(Pointer<_DataBlob> blob, {bool wipe = false}) {
    final length = blob.ref.cbData;
    final data = blob.ref.pbData;
    final copy = Uint8List.fromList(data.asTypedList(length));
    if (wipe) data.asTypedList(length).fillRange(0, length, 0);
    _localFree(data.cast<Void>());
    return copy;
  }
}

/// DATA_BLOB { DWORD cbData; BYTE *pbData; }
final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

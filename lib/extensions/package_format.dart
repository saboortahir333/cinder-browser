import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'package:saboor_browser/extensions/manifest.dart';

class PackageException implements Exception {
  const PackageException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Limits that stop zip bombs and path tricks.
class PackageLimits {
  static const int maxDownloadBytes = 100 * 1024 * 1024;
  static const int maxFiles = 5000;
  static const int maxUncompressedBytes = 250 * 1024 * 1024;
  static const int maxSingleFileBytes = 100 * 1024 * 1024;
}

/// Chrome-style 32 character extension id (letters a-p) from [bytes] (the
/// first 16 bytes of the SHA-256 of the public key).
String extensionIdFromHash(List<int> bytes) {
  final b = StringBuffer();
  for (var i = 0; i < 16; i++) {
    b
      ..writeCharCode(0x61 + ((bytes[i] >> 4) & 0xF))
      ..writeCharCode(0x61 + (bytes[i] & 0xF));
  }
  return b.toString();
}

String extensionIdFromPublicKey(List<int> spkiDer) =>
    extensionIdFromHash(sha256.convert(spkiDer).bytes);

final RegExp kExtensionId = RegExp(r'^[a-p]{32}$');

class CrxContents {
  const CrxContents({required this.id, required this.zip, required this.verified});

  /// Id derived from the developer's signing key.
  final String id;
  final Uint8List zip;
  final bool verified;
}

// ---------------------------------------------------------------------------
// Minimal protobuf / DER readers (only what CRX3 needs)
// ---------------------------------------------------------------------------

class _Field {
  _Field(this.number, this.bytes);
  final int number;
  final Uint8List bytes;
}

List<_Field> _readProto(Uint8List data) {
  final out = <_Field>[];
  var i = 0;
  int varint() {
    var shift = 0;
    var result = 0;
    while (true) {
      if (i >= data.length || shift > 56) {
        throw const PackageException('Corrupt package header.');
      }
      final b = data[i++];
      result |= (b & 0x7F) << shift;
      if (b & 0x80 == 0) return result;
      shift += 7;
    }
  }

  while (i < data.length) {
    final tag = varint();
    final wire = tag & 7;
    final number = tag >> 3;
    if (wire == 2) {
      final len = varint();
      if (len < 0 || i + len > data.length) {
        throw const PackageException('Corrupt package header.');
      }
      out.add(_Field(number, Uint8List.sublistView(data, i, i + len)));
      i += len;
    } else if (wire == 0) {
      varint();
    } else {
      throw const PackageException('Unsupported package header.');
    }
  }
  return out;
}

class _Der {
  _Der(this.data);
  final Uint8List data;
  int pos = 0;

  /// Reads one TLV and returns (tag, value bytes).
  (int, Uint8List) read() {
    if (pos + 2 > data.length) throw const PackageException('Bad public key.');
    final tag = data[pos++];
    var len = data[pos++];
    if (len & 0x80 != 0) {
      final n = len & 0x7F;
      if (n == 0 || n > 4 || pos + n > data.length) {
        throw const PackageException('Bad public key.');
      }
      len = 0;
      for (var k = 0; k < n; k++) {
        len = (len << 8) | data[pos++];
      }
    }
    if (pos + len > data.length) throw const PackageException('Bad public key.');
    final v = Uint8List.sublistView(data, pos, pos + len);
    pos += len;
    return (tag, v);
  }
}

/// Parses an RSA SubjectPublicKeyInfo into (modulus, exponent), big endian
/// with leading zeros removed.
(Uint8List, Uint8List) parseRsaSpki(Uint8List spki) {
  final top = _Der(spki);
  final (t0, seq) = top.read();
  if (t0 != 0x30) throw const PackageException('Bad public key.');
  final inner = _Der(seq);
  final (t1, algo) = inner.read();
  if (t1 != 0x30) throw const PackageException('Bad public key.');
  // rsaEncryption OID 1.2.840.113549.1.1.1
  const rsaOid = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01];
  final (oidTag, oid) = _Der(algo).read();
  if (oidTag != 0x06 || oid.length != rsaOid.length) {
    throw const PackageException('Only RSA signing keys are supported.');
  }
  for (var i = 0; i < rsaOid.length; i++) {
    if (oid[i] != rsaOid[i]) {
      throw const PackageException('Only RSA signing keys are supported.');
    }
  }
  final (t2, bits) = inner.read();
  if (t2 != 0x03 || bits.isEmpty || bits[0] != 0) {
    throw const PackageException('Bad public key.');
  }
  final keySeq = _Der(Uint8List.sublistView(bits, 1));
  final (t3, rsaKey) = keySeq.read();
  if (t3 != 0x30) throw const PackageException('Bad public key.');
  final ints = _Der(rsaKey);
  final (tn, n) = ints.read();
  final (te, e) = ints.read();
  if (tn != 0x02 || te != 0x02) throw const PackageException('Bad public key.');
  Uint8List strip(Uint8List v) {
    var s = 0;
    while (s < v.length - 1 && v[s] == 0) {
      s++;
    }
    return Uint8List.sublistView(v, s);
  }

  final modulus = strip(n);
  if (modulus.length < 128) {
    throw const PackageException('Signing key is too weak.');
  }
  return (modulus, strip(e));
}

BigInt _bigFromBytes(List<int> b) {
  var r = BigInt.zero;
  for (final x in b) {
    r = (r << 8) | BigInt.from(x);
  }
  return r;
}

/// RSASSA-PKCS1-v1_5 / SHA-256 verification (RFC 8017 §8.2.2).
///
/// The recovered block is compared byte-for-byte with the expected encoding
/// instead of being parsed, which rules out padding-forgery attacks
/// (Bleichenbacher's e=3 signature forgery).
bool rsaPkcs1Sha256Verify({
  required List<int> modulus,
  required List<int> exponent,
  required List<int> message,
  required List<int> signature,
}) {
  final k = modulus.length;
  if (k < 128 || k > 1024 || signature.length != k) return false;
  final n = _bigFromBytes(modulus);
  final e = _bigFromBytes(exponent);
  // Reject tiny/even exponents that make forgeries easy.
  if (e < BigInt.from(65537) || e.isEven || e.bitLength > 64) return false;
  final s = _bigFromBytes(signature);
  if (s >= n) return false;
  final m = s.modPow(e, n);
  final em = Uint8List(k);
  var tmp = m;
  for (var i = k - 1; i >= 0; i--) {
    em[i] = (tmp & BigInt.from(0xFF)).toInt();
    tmp >>= 8;
  }
  const prefix = [
    0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03,
    0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
  ];
  final digest = sha256.convert(message).bytes;
  final tLen = prefix.length + digest.length;
  final expected = Uint8List(k)
    ..fillRange(0, k, 0xFF)
    ..[0] = 0x00
    ..[1] = 0x01
    ..[k - tLen - 1] = 0x00
    ..setRange(k - tLen, k - digest.length, prefix)
    ..setRange(k - digest.length, k, digest);
  var diff = 0;
  for (var i = 0; i < k; i++) {
    diff |= em[i] ^ expected[i];
  }
  return diff == 0;
}

class Crx3 {
  const Crx3._();

  static final Uint8List _magic = Uint8List.fromList('Cr24'.codeUnits);

  static bool looksLikeCrx(Uint8List data) =>
      data.length > 12 &&
      data[0] == _magic[0] &&
      data[1] == _magic[1] &&
      data[2] == _magic[2] &&
      data[3] == _magic[3];

  /// Verifies a CRX3 package and returns its zip payload. Throws
  /// [PackageException] unless the developer signature is valid *and* the
  /// declared crx_id equals the hash of the signing key.
  static Future<CrxContents> open(Uint8List data) async {
    if (!looksLikeCrx(data)) {
      throw const PackageException('This is not a Chrome extension (.crx) file.');
    }
    final bd = ByteData.sublistView(data);
    final version = bd.getUint32(4, Endian.little);
    if (version != 3) {
      throw PackageException(
        'Unsupported CRX version $version (only signed CRX3 is accepted).',
      );
    }
    final headerSize = bd.getUint32(8, Endian.little);
    if (headerSize == 0 || headerSize > 1024 * 1024 || 12 + headerSize > data.length) {
      throw const PackageException('Corrupt package header.');
    }
    final headerBytes = Uint8List.sublistView(data, 12, 12 + headerSize);
    final zip = Uint8List.sublistView(data, 12 + headerSize);
    if (zip.isEmpty) throw const PackageException('The package is empty.');

    final header = _readProto(headerBytes);
    final signedHeaderData = header
        .where((f) => f.number == 10000)
        .map((f) => f.bytes)
        .toList();
    if (signedHeaderData.length != 1) {
      throw const PackageException('Package is missing its signed header.');
    }
    final signed = signedHeaderData.first;
    final crxIdField = _readProto(signed).where((f) => f.number == 1).toList();
    if (crxIdField.length != 1 || crxIdField.first.bytes.length != 16) {
      throw const PackageException('Package has an invalid id.');
    }
    final crxId = crxIdField.first.bytes;

    // Data the signatures cover.
    final prefix = Uint8List.fromList('CRX3 SignedData'.codeUnits + [0]);
    final lenBytes = ByteData(4)..setUint32(0, signed.length, Endian.little);
    final payload = BytesBuilder(copy: false)
      ..add(prefix)
      ..add(lenBytes.buffer.asUint8List())
      ..add(signed)
      ..add(zip);
    final signedPayload = payload.toBytes();

    var matchedDeveloperKey = false;
    var proofs = 0;
    for (final f in header.where((f) => f.number == 2)) {
      proofs++;
      final proof = _readProto(f.bytes);
      final key = proof.where((p) => p.number == 1).toList();
      final sig = proof.where((p) => p.number == 2).toList();
      if (key.length != 1 || sig.length != 1) {
        throw const PackageException('Corrupt package signature.');
      }
      final (n, e) = parseRsaSpki(key.first.bytes);
      final ok = rsaPkcs1Sha256Verify(
        modulus: n,
        exponent: e,
        message: signedPayload,
        signature: sig.first.bytes,
      );
      if (!ok) {
        throw const PackageException(
          'The package signature is invalid. It may be corrupted or tampered with.',
        );
      }
      final hash = sha256.convert(key.first.bytes).bytes;
      var same = true;
      for (var i = 0; i < 16; i++) {
        if (hash[i] != crxId[i]) {
          same = false;
          break;
        }
      }
      if (same) matchedDeveloperKey = true;
    }
    if (proofs == 0 || !matchedDeveloperKey) {
      throw const PackageException(
        'The package is not signed by the key its id claims.',
      );
    }
    return CrxContents(id: extensionIdFromHash(crxId), zip: zip, verified: true);
  }
}

class ExtractedPackage {
  const ExtractedPackage(this.manifestSource, this.fileCount);
  final String manifestSource;
  final int fileCount;
}

class ZipExtractor {
  const ZipExtractor._();

  /// Extracts [zip] into [destination] (must be an empty, newly created
  /// directory). Enforces path safety and size limits; returns manifest text.
  static ExtractedPackage extract(Uint8List zip, Directory destination) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zip);
    } catch (_) {
      throw const PackageException('The extension archive could not be read.');
    }
    if (archive.length > PackageLimits.maxFiles) {
      throw const PackageException('The extension contains too many files.');
    }
    final root = destination.absolute.path;
    var total = 0;
    var files = 0;
    String? manifest;

    // Some zips wrap everything in one folder; Chrome requires manifest.json
    // at the root, so we do too.
    for (final entry in archive) {
      final name = entry.name.replaceAll('\\', '/');
      if (name.startsWith('__MACOSX/')) continue;
      if (!entry.isFile) {
        continue;
      }
      if (!ExtensionManifest.isSafeRelativePath(name)) {
        throw PackageException('The extension contains an unsafe path: "$name".');
      }
      if (entry.isSymbolicLink) {
        throw const PackageException('Symbolic links are not allowed.');
      }
      if (entry.size > PackageLimits.maxSingleFileBytes) {
        throw const PackageException('A file in the extension is too large.');
      }
      total += entry.size;
      if (total > PackageLimits.maxUncompressedBytes) {
        throw const PackageException('The extension is too large once unpacked.');
      }
      final bytes = entry.readBytes();
      if (bytes == null) continue;
      if (bytes.length != entry.size && bytes.length > PackageLimits.maxSingleFileBytes) {
        throw const PackageException('A file in the extension is too large.');
      }
      final target = File('$root${Platform.pathSeparator}${name.replaceAll('/', Platform.pathSeparator)}');
      // Defence in depth: the resolved path must remain inside root.
      final resolved = target.absolute.path;
      if (!resolved.startsWith('$root${Platform.pathSeparator}')) {
        throw PackageException('The extension contains an unsafe path: "$name".');
      }
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(bytes, flush: false);
      files++;
      if (name == 'manifest.json') {
        manifest = _utf8(bytes);
      }
    }
    if (manifest == null) {
      throw const PackageException('The extension has no manifest.json at its root.');
    }
    return ExtractedPackage(manifest, files);
  }

  static String _utf8(List<int> bytes) {
    try {
      return const Utf8Decoder().convert(bytes);
    } catch (_) {
      throw const PackageException('manifest.json is not valid UTF-8.');
    }
  }
}

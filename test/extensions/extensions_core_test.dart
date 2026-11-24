import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

import 'package:saboor_browser/extensions/manifest.dart';
import 'package:saboor_browser/extensions/match_pattern.dart';
import 'package:saboor_browser/extensions/package_format.dart';
import 'package:saboor_browser/extensions/permissions.dart';

Uint8List _zip(Map<String, String> files) {
  final a = Archive();
  files.forEach((k, v) => a.addFile(ArchiveFile(k, utf8.encode(v).length, utf8.encode(v))));
  return Uint8List.fromList(ZipEncoder().encode(a));
}

const _goodManifest = '''
{"manifest_version":3,"name":"Demo","version":"1.2.3","description":"d",
 "permissions":["storage","tabs"],
 "host_permissions":["https://*.example.com/*"],
 "content_scripts":[{"matches":["https://*.example.com/*"],"js":["a.js"],"css":["a.css"],"run_at":"document_start"}],
 "action":{"default_popup":"popup.html","default_title":"Hi"}}''';

// ---- DER / protobuf encoders for building a CRX3 in tests ----
List<int> _derLen(int n) {
  if (n < 128) return [n];
  final b = <int>[];
  var v = n;
  while (v > 0) {
    b.insert(0, v & 0xFF);
    v >>= 8;
  }
  return [0x80 | b.length, ...b];
}

List<int> _tlv(int tag, List<int> v) => [tag, ..._derLen(v.length), ...v];
List<int> _int(List<int> be) {
  var v = be;
  if (v.isNotEmpty && v[0] & 0x80 != 0) v = [0, ...v];
  return _tlv(0x02, v);
}

List<int> _spki(List<int> n, List<int> e) {
  final rsaKey = _tlv(0x30, [..._int(n), ..._int(e)]);
  final algo = _tlv(0x30, [
    ..._tlv(0x06, [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]),
    0x05, 0x00,
  ]);
  return _tlv(0x30, [...algo, ..._tlv(0x03, [0, ...rsaKey])]);
}

List<int> _varint(int v) {
  final out = <int>[];
  while (v > 0x7F) {
    out.add((v & 0x7F) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}

List<int> _field(int number, List<int> bytes) => [
  ..._varint((number << 3) | 2),
  ..._varint(bytes.length),
  ...bytes,
];

class _Key {
  _Key(this.n, this.e, this.d);
  final BigInt n, e, d;
}

List<int> _bytes(BigInt v, [int? len]) {
  final out = <int>[];
  var x = v;
  while (x > BigInt.zero) {
    out.insert(0, (x & BigInt.from(255)).toInt());
    x >>= 8;
  }
  while (len != null && out.length < len) {
    out.insert(0, 0);
  }
  return out;
}

bool _isPrime(BigInt n, Random r) {
  if (n < BigInt.two) return false;
  for (final p in [2, 3, 5, 7, 11, 13, 17, 19, 23, 29]) {
    if (n == BigInt.from(p)) return true;
    if (n % BigInt.from(p) == BigInt.zero) return false;
  }
  var d = n - BigInt.one;
  var s = 0;
  while (d.isEven) {
    d >>= 1;
    s++;
  }
  for (var i = 0; i < 12; i++) {
    final a = BigInt.from(2 + r.nextInt(1 << 30));
    var x = a.modPow(d, n);
    if (x == BigInt.one || x == n - BigInt.one) continue;
    var composite = true;
    for (var j = 0; j < s - 1; j++) {
      x = x.modPow(BigInt.two, n);
      if (x == n - BigInt.one) {
        composite = false;
        break;
      }
    }
    if (composite) return false;
  }
  return true;
}

BigInt _prime(int bits, Random r) {
  while (true) {
    var c = BigInt.one << (bits - 1);
    for (var i = 0; i < bits - 1; i++) {
      if (r.nextBool()) c |= BigInt.one << i;
    }
    c |= BigInt.one;
    if (_isPrime(c, r)) return c;
  }
}

_Key? _cachedKey;
_Key _testKey() {
  if (_cachedKey != null) return _cachedKey!;
  final r = Random(42);
  final e = BigInt.from(65537);
  while (true) {
    final p = _prime(512, r), q = _prime(512, r);
    if (p == q) continue;
    final phi = (p - BigInt.one) * (q - BigInt.one);
    if (e.gcd(phi) != BigInt.one) continue;
    final n = p * q;
    if (n.bitLength != 1024) continue;
    return _cachedKey = _Key(n, e, e.modInverse(phi));
  }
}

List<int> _sign(_Key key, List<int> message) {
  const prefix = [
    0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03,
    0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
  ];
  final digest = crypto.sha256.convert(message).bytes;
  const k = 128;
  final tLen = prefix.length + digest.length;
  final em = List<int>.filled(k, 0xFF)
    ..[0] = 0
    ..[1] = 1
    ..[k - tLen - 1] = 0
    ..setRange(k - tLen, k - digest.length, prefix)
    ..setRange(k - digest.length, k, digest);
  var m = BigInt.zero;
  for (final b in em) {
    m = (m << 8) | BigInt.from(b);
  }
  return _bytes(m.modPow(key.d, key.n), k);
}

Future<Uint8List> _buildCrx(Uint8List zip, {bool tamper = false, bool wrongId = false}) async {
  final key = _testKey();
  final spki = _spki(_bytes(key.n), _bytes(key.e));
  final id = crypto.sha256.convert(spki).bytes.sublist(0, 16);
  final crxId = wrongId ? List<int>.filled(16, 7) : id;
  final signed = _field(1, crxId);
  final payload = <int>[
    ...'CRX3 SignedData'.codeUnits,
    0,
    ...(ByteData(4)..setUint32(0, signed.length, Endian.little)).buffer.asUint8List(),
    ...signed,
    ...zip,
  ];
  final sigBytes = _sign(key, payload);
  final proof = [..._field(1, spki), ..._field(2, sigBytes)];
  final header = [..._field(2, proof), ..._field(10000, signed)];
  final out = BytesBuilder()
    ..add('Cr24'.codeUnits)
    ..add((ByteData(4)..setUint32(0, 3, Endian.little)).buffer.asUint8List())
    ..add((ByteData(4)..setUint32(0, header.length, Endian.little)).buffer.asUint8List())
    ..add(header)
    ..add(tamper ? Uint8List.fromList([...zip, 0]) : zip);
  return out.toBytes();
}

void main() {
  group('MatchPattern', () {
    bool m(String p, String u) => MatchPattern.tryParse(p)!.matches(u);

    test('subdomain wildcard matches host and subdomains only', () {
      expect(m('https://*.example.com/*', 'https://example.com/'), isTrue);
      expect(m('https://*.example.com/*', 'https://a.b.example.com/x?y=1'), isTrue);
      expect(m('https://*.example.com/*', 'https://evilexample.com/'), isFalse);
      expect(m('https://*.example.com/*', 'https://example.com.evil.com/'), isFalse);
      expect(m('https://*.example.com/*', 'http://example.com/'), isFalse);
    });

    test('scheme wildcard covers http and https only', () {
      expect(m('*://example.com/*', 'http://example.com/a'), isTrue);
      expect(m('*://example.com/*', 'https://example.com/a'), isTrue);
      expect(m('*://example.com/*', 'file:///example.com/a'), isFalse);
    });

    test('paths and ports', () {
      expect(m('https://example.com/a/*', 'https://example.com/a/b'), isTrue);
      expect(m('https://example.com/a/*', 'https://example.com/b'), isFalse);
      expect(m('http://localhost:3000/*', 'http://localhost:3000/x'), isTrue);
      expect(m('http://localhost:3000/*', 'http://localhost:4000/x'), isFalse);
      expect(m('https://example.com/*', 'https://example.com:8443/x'), isTrue);
    });

    test('userinfo cannot spoof the host', () {
      expect(m('https://example.com/*', 'https://example.com@evil.com/'), isFalse);
    });

    test('<all_urls> never matches non-web schemes', () {
      expect(m('<all_urls>', 'https://a.com/'), isTrue);
      expect(m('<all_urls>', 'about:blank'), isFalse);
      expect(m('<all_urls>', 'javascript:alert(1)'), isFalse);
      expect(m('<all_urls>', 'chrome://settings'), isFalse);
    });

    test('rejects malformed patterns', () {
      for (final bad in [
        '', 'example.com', 'https://', 'https://foo*.com/*',
        'https://a.*.com/*', 'ftp://x/*', 'https://example.com', '*://*.',
        'chrome://*/*', 'https://user@example.com/*',
      ]) {
        expect(MatchPattern.tryParse(bad), isNull, reason: bad);
      }
    });

    test('JS regex agrees with Dart matching', () {
      const cases = {
        'https://*.example.com/*': ['https://example.com/', 'https://x.example.com/a?b', 'https://evilexample.com/', 'http://example.com/'],
        'https://example.com/a/*': ['https://example.com/a/b', 'https://example.com/b'],
      };
      cases.forEach((p, urls) {
        final pat = MatchPattern.tryParse(p)!;
        final re = RegExp(pat.toJsRegexSource());
        for (final u in urls) {
          expect(re.hasMatch(u), pat.matches(u), reason: '$p vs $u');
        }
      });
    });

    test('covers', () {
      final all = MatchPattern.tryParse('<all_urls>')!;
      final one = MatchPattern.tryParse('https://a.example.com/*')!;
      final sub = MatchPattern.tryParse('https://*.example.com/*')!;
      expect(all.covers(one), isTrue);
      expect(sub.covers(one), isTrue);
      expect(one.covers(sub), isFalse);
    });
  });

  group('ExtensionManifest', () {
    test('parses a valid MV3 manifest', () {
      final m = ExtensionManifest.parse(_goodManifest);
      expect(m.name, 'Demo');
      expect(m.contentScripts.single.runAt, RunAt.documentStart);
      expect(m.popup, 'popup.html');
      expect(m.actionTitle, 'Hi');
    });

    test('rejects MV2 with a helpful message', () {
      expect(
        () => ExtensionManifest.parse('{"manifest_version":2,"name":"a","version":"1"}'),
        throwsA(isA<ManifestException>().having((e) => e.message, 'msg', contains('Manifest V2'))),
      );
    });

    test('rejects path traversal and bad versions', () {
      expect(
        () => ExtensionManifest.parse(
          '{"manifest_version":3,"name":"a","version":"1","content_scripts":[{"matches":["<all_urls>"],"js":["../x.js"]}]}',
        ),
        throwsA(isA<ManifestException>()),
      );
      expect(
        () => ExtensionManifest.parse('{"manifest_version":3,"name":"a","version":"1.x"}'),
        throwsA(isA<ManifestException>()),
      );
      expect(() => ExtensionManifest.parse('[]'), throwsA(isA<ManifestException>()));
      expect(() => ExtensionManifest.parse('not json'), throwsA(isA<ManifestException>()));
    });

    test('safe relative paths', () {
      expect(ExtensionManifest.isSafeRelativePath('a/b.js'), isTrue);
      for (final bad in ['/a', '../a', 'a/../b', r'a\b', 'C:/x', 'a//b', '']) {
        expect(ExtensionManifest.isSafeRelativePath(bad), isFalse, reason: bad);
      }
    });

    test('locale placeholders', () {
      final l = LocaleMessages.parse('{"hello":{"message":"Hi there"}}');
      expect(l.resolve('__MSG_hello__!'), 'Hi there!');
      expect(l.resolve('__MSG_nope__'), '__MSG_nope__');
    });
  });

  group('PermissionPolicy', () {
    final m = ExtensionManifest.parse(_goodManifest);

    test('runs only where host access and the user allow', () {
      final g = PermissionPolicy.defaultGrants(m);
      expect(PermissionPolicy.mayRunOn(m, g, 'https://www.example.com/'), isTrue);
      expect(PermissionPolicy.mayRunOn(m, g, 'https://other.com/'), isFalse);
      expect(PermissionPolicy.mayRunOn(m, g, 'about:blank'), isFalse);

      g.siteAccess = SiteAccess.onClick;
      expect(PermissionPolicy.mayRunOn(m, g, 'https://www.example.com/'), isFalse);
      g.activeTabOrigins.add('https://www.example.com');
      expect(PermissionPolicy.mayRunOn(m, g, 'https://www.example.com/x'), isTrue);

      g.siteAccess = SiteAccess.onSpecificSites;
      g.specificSites.add('https://shop.example.com/*');
      expect(PermissionPolicy.mayRunOn(m, g, 'https://shop.example.com/'), isTrue);
      expect(PermissionPolicy.mayRunOn(m, g, 'https://www.example.com/'), isFalse);
    });

    test('never runs on the Web Store', () {
      final all = ExtensionManifest.parse(
        '{"manifest_version":3,"name":"a","version":"1","host_permissions":["<all_urls>"],'
        '"content_scripts":[{"matches":["<all_urls>"],"js":["a.js"]}]}',
      );
      final g = PermissionPolicy.defaultGrants(all);
      expect(PermissionPolicy.mayRunOn(all, g, 'https://chromewebstore.google.com/detail/x'), isFalse);
      expect(PermissionPolicy.mayRunOn(all, g, 'https://example.org/'), isTrue);
    });

    test('unknown and unsupported permissions are never active', () {
      final x = ExtensionManifest.parse(
        '{"manifest_version":3,"name":"a","version":"1","permissions":["storage","cookies","bogus"]}',
      );
      final g = PermissionPolicy.defaultGrants(x);
      expect(PermissionPolicy.hasApi(x, g, 'storage'), isTrue);
      expect(PermissionPolicy.hasApi(x, g, 'cookies'), isFalse);
      expect(PermissionPolicy.hasApi(x, g, 'bogus'), isFalse);
      expect(PermissionPolicy.isHighRisk(x), isTrue);
    });

    test('host summary', () {
      expect(PermissionPolicy.hostSummary(m), contains('example.com'));
    });
  });

  group('packages', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('cinder_ext_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('extracts a normal zip', () {
      final r = ZipExtractor.extract(
        _zip({'manifest.json': _goodManifest, 'a.js': '1', 'sub/popup.html': '<p>'}),
        tmp,
      );
      expect(r.fileCount, 3);
      expect(File('${tmp.path}/sub/popup.html').existsSync(), isTrue);
    });

    test('rejects zip-slip and missing manifest', () {
      expect(
        () => ZipExtractor.extract(_zip({'manifest.json': _goodManifest, '../evil.js': 'x'}), tmp),
        throwsA(isA<PackageException>()),
      );
      expect(
        () => ZipExtractor.extract(_zip({'a.js': '1'}), tmp),
        throwsA(isA<PackageException>()),
      );
      expect(File('${tmp.parent.path}/evil.js').existsSync(), isFalse);
    });

    test('extension id format', () {
      final id = extensionIdFromHash(List<int>.filled(16, 0xAB));
      expect(kExtensionId.hasMatch(id), isTrue);
      expect(id, 'klklklklklklklklklklklklklklklkl'.substring(0, 32));
    });

    test('CRX3: valid signature is accepted and id derived', () async {
      final zip = _zip({'manifest.json': _goodManifest});
      final crx = await _buildCrx(zip);
      final c = await Crx3.open(crx);
      expect(c.verified, isTrue);
      expect(kExtensionId.hasMatch(c.id), isTrue);
      expect(c.zip, zip);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('CRX3: tampered payload, wrong id and junk are rejected', () async {
      final zip = _zip({'manifest.json': _goodManifest});
      await expectLater(Crx3.open(await _buildCrx(zip, tamper: true)), throwsA(isA<PackageException>()));
      await expectLater(Crx3.open(await _buildCrx(zip, wrongId: true)), throwsA(isA<PackageException>()));
      await expectLater(Crx3.open(Uint8List.fromList(List.filled(64, 1))), throwsA(isA<PackageException>()));
      await expectLater(Crx3.open(zip), throwsA(isA<PackageException>()));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

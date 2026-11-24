import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/services/cloud_store.dart';

class _Keys implements VaultKeySource {
  _Keys({this.userId, this.masterKey});

  @override
  String? userId;
  @override
  Uint8List? masterKey;
  int invalidated = 0;

  @override
  Future<void> invalidateKey() async {
    invalidated++;
    masterKey = null;
  }
}

class _FakeApi implements RecordApi {
  final Map<String, RecordRow> rows = {};
  int calls = 0;
  bool failNext = false;

  String _k(String p, String kind, String id) => '$p|$kind|$id';

  @override
  Future<void> upsert(List<RecordRow> batch) async {
    calls++;
    if (failNext) {
      failNext = false;
      throw Exception('network down');
    }
    for (final r in batch) {
      rows[_k(r.profileId, r.kind, r.recordId)] = r;
    }
  }

  @override
  Future<List<RecordRow>> fetch({
    required String profileId,
    required String kind,
    required int limit,
  }) async {
    calls++;
    return rows.values
        .where((r) => r.profileId == profileId && r.kind == kind)
        .take(limit)
        .toList();
  }

  @override
  Future<void> delete({
    required String profileId,
    required String kind,
    required List<String> recordIds,
  }) async {
    calls++;
    for (final id in recordIds) {
      rows.remove(_k(profileId, kind, id));
    }
  }

  @override
  Future<void> deleteKind({
    required String profileId,
    required String kind,
  }) async {
    calls++;
    rows.removeWhere((_, r) => r.profileId == profileId && r.kind == kind);
  }
}

void main() {
  const user = 'aaaaaaaa-0000-0000-0000-000000000001';
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i));

  CloudStore store(_FakeApi api, _Keys keys, {String profile = 'default'}) =>
      CloudStore(api: api, keys: keys, profileId: profile, autoFlush: false);

  test('guest mode keeps data in memory and never touches the network', () async {
    final api = _FakeApi();
    final s = store(api, _Keys());
    expect(s.put('bookmark', 'b1', {'url': 'https://a.example'}), isTrue);
    await s.flush();
    await s.load('bookmark');
    expect(s.values('bookmark'), hasLength(1));
    expect(api.calls, 0);
    expect(s.pendingCount, 0);
  });

  test('signed-in writes reach the server only as ciphertext', () async {
    final api = _FakeApi();
    final s = store(api, _Keys(userId: user, masterKey: key));
    s.put('history', 'h1', {'url': 'https://secret.example/health', 'title': 'Clinic'});
    await s.flush();
    final row = api.rows.values.single;
    expect(row.ciphertext.contains('secret.example'), isFalse);
    expect(row.ciphertext.contains('Clinic'), isFalse);
    expect(s.pendingCount, 0);
  });

  test('a second device with the same key reads back the data', () async {
    final api = _FakeApi();
    final a = store(api, _Keys(userId: user, masterKey: key));
    a.put('session', 'main', {'tabs': ['https://x.example']});
    await a.flush();

    final b = store(api, _Keys(userId: user, masterKey: key));
    final loaded = await b.load('session');
    expect(loaded.single['tabs'], ['https://x.example']);
  });

  test('rows from another profile are not mixed in', () async {
    final api = _FakeApi();
    final work = store(api, _Keys(userId: user, masterKey: key), profile: 'work');
    work.put('bookmark', 'b', {'url': 'https://work.example'});
    await work.flush();
    final home = store(api, _Keys(userId: user, masterKey: key), profile: 'home');
    expect(await home.load('bookmark'), isEmpty);
  });

  test('ciphertext swapped between rows is discarded', () async {
    final api = _FakeApi();
    final s = store(api, _Keys(userId: user, masterKey: key));
    s.put('bookmark', 'one', {'url': 'https://one.example'});
    s.put('bookmark', 'two', {'url': 'https://two.example'});
    await s.flush();
    final one = api.rows['default|bookmark|one']!;
    final two = api.rows['default|bookmark|two']!;
    api.rows['default|bookmark|one'] = RecordRow(
      profileId: one.profileId,
      kind: one.kind,
      recordId: one.recordId,
      ciphertext: two.ciphertext,
    );
    final fresh = store(api, _Keys(userId: user, masterKey: key));
    final loaded = await fresh.load('bookmark');
    expect(loaded.map((m) => m['url']), ['https://two.example']);
  });

  test('a wrong cached key invalidates itself instead of showing garbage', () async {
    final api = _FakeApi();
    final writer = store(api, _Keys(userId: user, masterKey: key));
    writer.put('history', 'h', {'url': 'https://a.example'});
    await writer.flush();

    final wrong = _Keys(userId: user, masterKey: Uint8List(32));
    final reader = store(api, wrong);
    expect(await reader.load('history'), isEmpty);
    expect(wrong.invalidated, 1);
  });

  test('failed sync is retained and succeeds on retry', () async {
    final api = _FakeApi()..failNext = true;
    final s = store(api, _Keys(userId: user, masterKey: key));
    s.put('bookmark', 'b', {'url': 'https://a.example'});
    await s.flush();
    expect(s.pendingCount, 1);
    await s.flush();
    expect(s.pendingCount, 0);
    expect(api.rows, hasLength(1));
  });

  test('latest edit wins and removal deletes server-side', () async {
    final api = _FakeApi();
    final s = store(api, _Keys(userId: user, masterKey: key));
    s.put('bookmark', 'b', {'title': 'old'});
    s.put('bookmark', 'b', {'title': 'new'});
    expect(s.pendingCount, 1);
    await s.flush();
    expect(s.get('bookmark', 'b')!['title'], 'new');
    s.remove('bookmark', 'b');
    await s.flush();
    expect(api.rows, isEmpty);
  });

  test('oversized records and bad identifiers are rejected', () {
    final s = store(_FakeApi(), _Keys(userId: user, masterKey: key));
    expect(s.put('history', 'x', {'blob': 'a' * (CloudStore.maxRecordBytes + 1)}), isFalse);
    expect(s.put('history', '', {'a': 1}), isFalse);
    expect(() => s.put('Bad Kind!', 'x', {}), throwsArgumentError);
    expect(
      () => CloudStore(api: _FakeApi(), keys: _Keys(), profileId: '../evil'),
      throwsArgumentError,
    );
  });

  test('record ids are keyed: stable per user, unlinkable to the URL', () {
    final s1 = store(_FakeApi(), _Keys(userId: user, masterKey: key));
    final s2 = store(_FakeApi(), _Keys(userId: user, masterKey: key));
    final other = store(
      _FakeApi(),
      _Keys(userId: user, masterKey: Uint8List.fromList(List<int>.filled(32, 7))),
    );
    const url = 'https://clinic.example/results';
    final id = s1.idFor('history', url);
    expect(id, s2.idFor('history', url));
    expect(id, isNot(other.idFor('history', url)));
    expect(id, isNot(s1.idFor('bookmark', url)));
    expect(id.contains('clinic'), isFalse);
    expect(id.length, 32);
    expect(RegExp(r'^[A-Za-z0-9_-]{32}$').hasMatch(id), isTrue);
  });

  test('guest ids are the bounded natural key', () {
    final s = store(_FakeApi(), _Keys());
    expect(s.idFor('history', 'https://a.example'), 'https://a.example');
    expect(s.idFor('history', 'x' * 500).length, 128);
  });

  test('wipe clears memory and queued writes', () async {
    final api = _FakeApi();
    final s = store(api, _Keys(userId: user, masterKey: key));
    s.put('history', 'h', {'url': 'https://a.example'});
    s.wipe();
    expect(s.values('history'), isEmpty);
    expect(s.pendingCount, 0);
    await s.flush();
    expect(api.rows, isEmpty);
  });
}

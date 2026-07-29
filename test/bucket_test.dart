// Run from the albedo_flutter root:
//   DYLD_LIBRARY_PATH=macos/Classes dart test test/bucket_test.dart
//   (or: just test)

import 'dart:io';
import 'package:albedo_flutter/albedo_dart.dart';
import 'package:test/test.dart';

Bucket _openTemp(Directory dir, [String name = 'test.bucket']) =>
    Bucket.open('${dir.path}/$name');

void main() {
  late Directory tempDir;
  late Bucket bucket;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('albedo_test_');
    bucket = _openTemp(tempDir);
  });

  tearDown(() {
    bucket.close();
    tempDir.deleteSync(recursive: true);
  });

  // ── Basic sanity ──────────────────────────────────────────────────────────

  test('insert and list roundtrip', () {
    bucket.insert({'name': 'Alice', 'score': 10});
    final docs = bucket.list(Query()).toList();
    expect(docs.length, 1);
    expect(docs.first['name'], 'Alice');
  });

  test('get returns null for empty bucket', () {
    expect(bucket.get(where('name', eq: 'nobody')), isNull);
  });

  test(
    'update expressions support arithmetic, fields, unset, and pipelines',
    () {
      bucket.insert({'name': 'Alice', 'score': 10, 'legacy': true});

      final updated = bucket.updateExpression(
        where('name', eq: 'Alice'),
        UpdateProgram.pipeline([
          UpdateProgram.set({
            'score': UpdateExpression.plus([
              const UpdateExpression.field('score'),
              5,
            ]),
            'label': UpdateExpression.concat([
              const UpdateExpression.field('name'),
              ' updated',
            ]),
          }),
          UpdateProgram.unset('legacy'),
          UpdateProgram.assign({
            'status': 'updated',
            'updated_at': UpdateExpression.now,
            'fixed_at': UpdateExpression.isoDateTime(
              '2024-04-22T10:20:30.456Z',
            ),
          }),
        ]),
      );

      expect(updated, 1);
      expect(bucket.get(where('name', eq: 'Alice')), {
        '_id': isNotNull,
        'name': 'Alice',
        'score': 15,
        'label': 'Alice updated',
        'status': 'updated',
        'updated_at': isNotNull,
        'fixed_at': isNotNull,
      });
    },
  );

  // ── Transaction: commit ───────────────────────────────────────────────────

  group('tx commit', () {
    test('all inserts visible after commit', () {
      bucket.tx((tx) {
        tx.insert({'name': 'one', 'value': 1});
        tx.insert({'name': 'two', 'value': 2});
        tx.insert({'name': 'three', 'value': 3});
      });

      final docs = bucket.list(Query()).toList();
      expect(docs.length, 3);
      final names = docs.map((d) => d['name']).toSet();
      expect(names, containsAll(['one', 'two', 'three']));
    });

    test('tx delete removes matching docs', () {
      bucket.insert({'name': 'keep', 'active': true});
      bucket.insert({'name': 'gone', 'active': false});

      bucket.tx((tx) {
        tx.delete(where('active', eq: false));
      });

      final docs = bucket.list(Query()).toList();
      expect(docs.length, 1);
      expect(docs.first['name'], 'keep');
    });

    test('tx transform updates matching docs', () {
      bucket.insert({'name': 'Alice', 'score': 10});
      bucket.insert({'name': 'Bob', 'score': 20});

      bucket.tx((tx) {
        tx.transform(where('name', eq: 'Alice'), (doc) {
          return {...doc, 'score': (doc['score'] as num).toInt() + 5};
        });
      });

      expect(bucket.get(where('name', eq: 'Alice'))?['score'], 15);
      expect(bucket.get(where('name', eq: 'Bob'))?['score'], 20);
    });

    test('tx update expressions commit atomically', () {
      bucket.insert({'name': 'Alice', 'score': 10});

      bucket.tx((tx) {
        expect(
          tx.updateExpression(
            Query(),
            UpdateProgram.set({
              'score': UpdateExpression.minus([
                const UpdateExpression.field('score'),
                3,
              ]),
            }),
          ),
          1,
        );
      });

      expect(bucket.get(Query())?['score'], 7);
    });

    test('tx transform returning null deletes the document', () {
      bucket.insert({'name': 'Alice', 'active': true});
      bucket.insert({'name': 'Bob', 'active': false});

      bucket.tx((tx) {
        tx.transform(Query(), (doc) {
          return doc['active'] == false ? null : doc;
        });
      });

      final docs = bucket.list(Query()).toList();
      expect(docs.length, 1);
      expect(docs.first['name'], 'Alice');
    });

    test('tx insert + delete in one transaction', () {
      bucket.tx((tx) {
        tx.insert({'name': 'Alice', 'active': true});
        tx.insert({'name': 'Bob', 'active': false});
        tx.delete(where('active', eq: false));
      });

      final docs = bucket.list(Query()).toList();
      expect(docs.length, 1);
      expect(docs.first['name'], 'Alice');
    });

    test('tx insert + transform in one transaction', () {
      bucket.insert({'name': 'Alice', 'score': 10});

      bucket.tx((tx) {
        tx.insert({'name': 'Charlie', 'score': 30});
        tx.transform(where('name', eq: 'Alice'), (doc) {
          return {...doc, 'score': (doc['score'] as num).toInt() * 2};
        });
      });

      expect(bucket.get(where('name', eq: 'Alice'))?['score'], 20);
      expect(bucket.get(where('name', eq: 'Charlie'))?['score'], 30);
      expect(bucket.list(Query()).toList().length, 2);
    });
  });

  // ── Transaction: rollback ─────────────────────────────────────────────────

  group('tx rollback', () {
    test('exception in body rolls back inserts', () {
      expect(
        () => bucket.tx((tx) {
          tx.insert({'name': 'a'});
          tx.insert({'name': 'b'});
          throw Exception('intentional rollback');
        }),
        throwsException,
      );

      expect(bucket.list(Query()).toList(), isEmpty);
    });

    test('exception in body rolls back delete', () {
      bucket.insert({'name': 'Alice'});

      expect(
        () => bucket.tx((tx) {
          tx.delete(Query());
          throw Exception('intentional rollback');
        }),
        throwsException,
      );

      expect(bucket.list(Query()).toList().length, 1);
    });

    test('exception in body rolls back transform', () {
      bucket.insert({'name': 'Alice', 'score': 10});

      expect(
        () => bucket.tx((tx) {
          tx.transform(where('name', eq: 'Alice'), (doc) {
            return {...doc, 'score': 99};
          });
          throw Exception('intentional rollback');
        }),
        throwsException,
      );

      expect(bucket.get(where('name', eq: 'Alice'))?['score'], 10);
    });

    test('transaction is closed and unusable after rollback', () {
      Transaction? captured;
      expect(
        () => bucket.tx((tx) {
          captured = tx;
          throw Exception('rollback');
        }),
        throwsException,
      );

      expect(() => captured!.insert({'name': 'late'}), throwsStateError);
    });
  });
}

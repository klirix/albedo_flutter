import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:bson/bson.dart';
import 'package:ffi/ffi.dart';

import 'albedo_dart_bindings_generated.dart';
import "package:fixnum/src/int64.dart" as fixnum;

part 'query.dart';

const String _libName = 'albedo';

final DynamicLibrary _dylib = () {
  if (Platform.isIOS) {
    return DynamicLibrary.process();
  }
  if (Platform.isMacOS) {
    return DynamicLibrary.open('lib$_libName.dylib');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// The generated FFI bindings for the loaded native library.
final AlbedoDartBindings _bindings = AlbedoDartBindings(_dylib);

/// Normalizes a raw query input into a BSON-like map suitable for serialization.
Map<String, dynamic> _normalizeQuery(dynamic query) {
  if (query is Query) {
    return query.toMap();
  }

  if (query is Map) {
    return _cloneBsonDocument(query);
  }

  throw ArgumentError.value(
    query,
    'query',
    'Expected a Query or BSON-like Map.',
  );
}

/// Returns a cloned query document with [cursor] attached.
Map<String, dynamic> _queryWithCursor(
  dynamic query,
  Map<String, dynamic> cursor,
) {
  final queryMap = _normalizeQuery(query);
  queryMap['cursor'] = _cloneBsonDocument(cursor);
  return queryMap;
}

/// Selects how the underlying bucket file is opened.
enum BucketOpenMode { readOnly, readWrite }

/// Selects how reads interact with the write-ahead log.
enum BucketReadDurability { shared, process }

enum _BucketWriteDurabilityKind { all, periodic, manual }

/// Describes how frequently Albedo should fsync writes to disk.
class BucketWriteDurability {
  /// Flushes every write to disk.
  const BucketWriteDurability.all()
    : _kind = _BucketWriteDurabilityKind.all,
      pageCount = null;

  /// Disables automatic fsync and relies on manual [Bucket.flush] calls.
  const BucketWriteDurability.manual()
    : _kind = _BucketWriteDurabilityKind.manual,
      pageCount = null;

  /// Flushes after every [value] page writes.
  const BucketWriteDurability.periodic(int value)
    : assert(value > 0),
      pageCount = value,
      _kind = _BucketWriteDurabilityKind.periodic;

  final _BucketWriteDurabilityKind _kind;
  final int? pageCount;

  /// Converts this durability mode into the BSON shape expected by the native API.
  dynamic toBson() {
    return switch (_kind) {
      _BucketWriteDurabilityKind.all => 'all',
      _BucketWriteDurabilityKind.manual => 'manual',
      _BucketWriteDurabilityKind.periodic => {'periodic': pageCount},
    };
  }
}

/// Configures how [Bucket.open] initializes the native bucket handle.
class BucketOpenOptions {
  /// Creates a new bucket-open configuration.
  const BucketOpenOptions({
    this.buildIdIndex = false,
    this.mode = BucketOpenMode.readWrite,
    this.autoVacuum = true,
    this.pageCacheCapacity,
    this.wal = true,
    this.writeDurability = const BucketWriteDurability.periodic(100),
    this.readDurability = BucketReadDurability.shared,
  });

  final bool buildIdIndex;
  final BucketOpenMode mode;
  final bool autoVacuum;
  final int? pageCacheCapacity;
  final bool wal;
  final BucketWriteDurability writeDurability;
  final BucketReadDurability readDurability;

  /// Converts these options into the BSON document expected by the C API.
  Map<String, dynamic> toBsonDocument() {
    final document = <String, dynamic>{
      'buildIdIndex': buildIdIndex,
      'mode': switch (mode) {
        BucketOpenMode.readOnly => 'ReadOnly',
        BucketOpenMode.readWrite => 'ReadWrite',
      },
      'auto_vaccuum': autoVacuum,
      'wal': wal,
      'write_durability': writeDurability.toBson(),
      'read_durability': switch (readDurability) {
        BucketReadDurability.shared => 'shared',
        BucketReadDurability.process => 'process',
      },
    };

    if (pageCacheCapacity != null) {
      document['page_cache_capacity'] = pageCacheCapacity;
    }

    return document;
  }
}

/// The type of change represented by a [ChangeEvent].
enum ChangeOpKind { insert, update, delete }

/// A single change event delivered by [Subscription.poll].
class ChangeEvent {
  /// Monotonically increasing oplog sequence number.
  final int seqno;

  /// The type of change.
  final ChangeOpKind op;

  /// Document identifier (12-byte ObjectId).
  final dynamic docId;

  /// Unix nanoseconds when the operation was written.
  final int ts;

  /// Full document body — present on insert/update when the inline payload
  /// fits within 1 KB; `null` on delete (and large updates).
  final Map<String, dynamic>? doc;

  const ChangeEvent({
    required this.seqno,
    required this.op,
    required this.docId,
    required this.ts,
    this.doc,
  });
}

/// Thrown by [Subscription.poll] when the oplog ring wrapped and the
/// subscriber fell too far behind. Close the [Subscription] and re-subscribe
/// to resume — optionally performing a full scan first to rebuild local state.
class SubscriptionGapException implements Exception {
  @override
  String toString() =>
      'SubscriptionGapException: oplog ring wrapped — re-subscribe to resume';
}

/// A live subscription to the oplog change stream of a [Bucket].
///
/// Obtain one via [Bucket.subscribe], then call [poll] in a loop or use
/// [Bucket.subscribeStream] for a managed async stream.
class Subscription {
  final Pointer<albedo_subscription_handle> _handle;
  final Pointer<Pointer<Uint8>> _outDoc;
  bool _isClosed = false;

  Subscription._internal(this._handle) : _outDoc = malloc<Pointer<Uint8>>();

  /// The latest committed oplog sequence number seen by this subscription.
  int get seqno => _bindings.albedo_subscribe_seqno(_handle);

  /// Polls for up to [maxEvents] new change events.
  ///
  /// Returns a non-empty list on `ALBEDO_HAS_DATA`.
  /// Returns `null` when there are no new events (`ALBEDO_EOS`).
  /// Throws [SubscriptionGapException] when the subscriber fell behind
  /// (`ALBEDO_OPLOG_GAP`) — call [close] and re-subscribe to recover.
  List<ChangeEvent>? poll({int maxEvents = 64}) {
    if (_isClosed) throw StateError('Subscription is closed');

    final res = _bindings.albedo_subscribe_poll(_handle, _outDoc, maxEvents);

    if (res == albedo_result.ALBEDO_EOS) return null;
    if (res == albedo_result.ALBEDO_OPLOG_GAP) throw SubscriptionGapException();
    if (res != albedo_result.ALBEDO_HAS_DATA) {
      throw Exception('albedo_subscribe_poll returned $res');
    }

    final dataPtr = _outDoc.value;
    if (dataPtr.address == 0) return null;

    final size = dataPtr.cast<Uint32>().value;
    final batchDoc =
        BsonCodec.deserialize(BsonBinary.from(dataPtr.asTypedList(size)))
            as Map;
    final batch = (batchDoc['batch'] as List).cast<Map>();

    return batch.map((entry) {
      final opStr = entry['op'] as String;
      final op = switch (opStr) {
        'insert' => ChangeOpKind.insert,
        'update' => ChangeOpKind.update,
        'delete' => ChangeOpKind.delete,
        _ => throw Exception('Unknown subscription op: $opStr'),
      };
      final rawDoc = entry['doc'];
      return ChangeEvent(
        seqno: (entry['seqno'] as fixnum.Int64).toInt(),
        op: op,
        docId: entry['doc_id'],
        ts: (entry['ts'] as fixnum.Int64).toInt(),
        doc: rawDoc == null ? null : Map<String, dynamic>.from(rawDoc as Map),
      );
    }).toList();
  }

  /// Closes the subscription and frees its native resources.
  void close() {
    if (_isClosed) return;
    _isClosed = true;
    _bindings.albedo_subscribe_close(_handle);
    malloc.free(_outDoc);
  }
}

/// A handle to an open Albedo bucket.
class Bucket {
  final Pointer<albedo_bucket> _handle;
  bool _isClosed = false;

  Bucket._internal(this._handle);

  /// Opens the bucket at [path] using optional native [options].
  factory Bucket.open(
    String path, {
    BucketOpenOptions options = const BucketOpenOptions(),
  }) {
    final pathPtr = path.toNativeUtf8();
    final serializedOptions =
        BsonCodec.serialize(options.toBsonDocument()).byteList;
    final serializedOptionsPtr = malloc<Uint8>(serializedOptions.length);
    final out = malloc<Int64>(1);

    serializedOptionsPtr
        .asTypedList(serializedOptions.length)
        .setAll(0, serializedOptions);

    try {
      final openRes = _bindings.albedo_open_with_options(
        pathPtr.cast<Char>(),
        serializedOptionsPtr,
        out as Pointer<Pointer<albedo_bucket>>,
      );

      if (openRes != albedo_result.ALBEDO_OK) {
        throw Exception('Error opening bucket: $openRes');
      }

      return Bucket._internal(Pointer.fromAddress(out.value));
    } finally {
      malloc.free(pathPtr);
      malloc.free(serializedOptionsPtr);
      malloc.free(out);
    }
  }

  /// Opens a native list iterator for [query].
  Pointer<albedo_list_handle> _openListHandle(dynamic query) {
    final serializedQuery =
        BsonCodec.serialize(_normalizeQuery(query)).byteList;
    final serializedQueryPtr = malloc<Uint8>(serializedQuery.length);
    final out = malloc<Int64>(1);

    serializedQueryPtr
        .asTypedList(serializedQuery.length)
        .setAll(0, serializedQuery);

    try {
      final listRes = _bindings.albedo_list(
        _handle,
        serializedQueryPtr,
        out as Pointer<Pointer<albedo_list_handle>>,
      );

      if (listRes.value > 1) {
        throw Exception('Error creating list iterator: $listRes');
      }

      return Pointer.fromAddress(out.value) as Pointer<albedo_list_handle>;
    } finally {
      malloc.free(serializedQueryPtr);
      malloc.free(out);
    }
  }

  /// Reads the current document from [listHandle], or `null` at end-of-stream.
  dynamic _readListDocument(
    Pointer<albedo_list_handle> listHandle,
    Pointer<Uint64> outDoc,
  ) {
    final res = _bindings.albedo_data(
      listHandle,
      outDoc as Pointer<Pointer<Uint8>>,
    );

    if (res == albedo_result.ALBEDO_EOS || outDoc.value == 0) {
      return null;
    }

    if (res.value > 1) {
      throw Exception('Error reading next data: $res');
    }

    final dataPtr = Pointer.fromAddress(outDoc.value).cast<Uint8>();
    final size = dataPtr.cast<Uint32>().value;
    final data = dataPtr.asTypedList(size);
    return BsonCodec.deserialize(BsonBinary.from(data));
  }

  /// Exports the current cursor state for [listHandle].
  Map<String, dynamic> _exportListCursor(
    Pointer<albedo_list_handle> listHandle,
  ) {
    final outCursor = malloc<Pointer<Uint8>>();
    var cursorPtr = Pointer<Uint8>.fromAddress(0);
    var cursorSize = 0;

    try {
      final res = _bindings.albedo_list_cursor_export(listHandle, outCursor);

      if (res.value > 1) {
        throw Exception('Error exporting list cursor: $res');
      }

      cursorPtr = outCursor.value;
      if (cursorPtr.address == 0) {
        throw Exception('Error exporting list cursor: empty cursor');
      }

      cursorSize = cursorPtr.cast<Uint32>().value;
      final data = cursorPtr.asTypedList(cursorSize);
      final cursor = BsonCodec.deserialize(BsonBinary.from(data));
      return _cloneBsonDocument(Map<dynamic, dynamic>.from(cursor as Map));
    } finally {
      if (cursorPtr.address != 0 && cursorSize > 0) {
        _bindings.albedo_free(cursorPtr, cursorSize);
      }
      malloc.free(outCursor);
    }
  }

  /// Inserts [obj] into the bucket.
  void insert(dynamic obj) {
    final docBuffer = BsonCodec.serialize(obj).byteList;
    final docBufferPtr = malloc<Uint8>(docBuffer.length);
    docBufferPtr.asTypedList(docBuffer.length).setAll(0, docBuffer);

    try {
      _bindings.albedo_insert(_handle, docBufferPtr);
    } finally {
      malloc.free(docBufferPtr);
    }
  }

  /// Returns all documents matching [query] as a lazy iterable.
  Iterable<dynamic> list(Query query) {
    return listRaw(query);
  }

  /// Returns all documents matching a raw BSON-like [query] document.
  Iterable<dynamic> listRaw(dynamic query) sync* {
    final listHandle = _openListHandle(query);
    final outDoc = malloc<Uint64>(1);

    try {
      while (true) {
        final doc = _readListDocument(listHandle, outDoc);
        if (doc == null) {
          break;
        }

        yield doc;
      }
    } finally {
      malloc.free(outDoc);
      _bindings.albedo_close_iterator(listHandle);
    }
  }

  /// Streams documents matching [query], optionally resuming via exported cursors.
  Stream<dynamic> stream(
    Query query, {
    Duration pollingTimeout = const Duration(milliseconds: 50),
    bool useCursor = false,
    void Function(Map<String, dynamic> cursor)? onCursor,
  }) {
    return streamRaw(
      query,
      pollingTimeout: pollingTimeout,
      useCursor: useCursor,
      onCursor: onCursor,
    );
  }

  /// Streams documents matching a raw BSON-like [query] document.
  Stream<dynamic> streamRaw(
    dynamic query, {
    Duration pollingTimeout = const Duration(milliseconds: 50),
    bool useCursor = false,
    void Function(Map<String, dynamic> cursor)? onCursor,
  }) async* {
    if (!useCursor) {
      final listHandle = _openListHandle(query);
      final outDoc = malloc<Uint64>(1);

      try {
        while (true) {
          final doc = _readListDocument(listHandle, outDoc);
          if (doc != null) {
            yield doc;
            continue;
          }

          await Future<void>.delayed(pollingTimeout);
        }
      } finally {
        malloc.free(outDoc);
        _bindings.albedo_close_iterator(listHandle);
      }
    } else {
      var currentQuery = _normalizeQuery(query);
      while (true) {
        final listHandle = _openListHandle(currentQuery);
        final outDoc = malloc<Uint64>(1);

        try {
          while (true) {
            final doc = _readListDocument(listHandle, outDoc);
            if (doc == null) {
              final cursor = _exportListCursor(listHandle);
              currentQuery = _queryWithCursor(currentQuery, cursor);
              onCursor?.call(_cloneBsonDocument(cursor));
              break;
            }

            yield doc;
          }
        } finally {
          malloc.free(outDoc);
          _bindings.albedo_close_iterator(listHandle);
        }

        await Future<void>.delayed(pollingTimeout);
      }
    }
  }

  /// Returns the first document matching [query], or `null` if none exists.
  Map<String, dynamic>? get(Query query) {
    final listHandle = _openListHandle(query);
    final outDoc = malloc<Uint64>(1);

    try {
      final doc = _readListDocument(listHandle, outDoc);
      if (doc == null) {
        return null;
      }

      return Map<String, dynamic>.from(doc as Map);
    } finally {
      malloc.free(outDoc);
      _bindings.albedo_close_iterator(listHandle);
    }
  }

  /// Applies [updater] to each document matching [query].
  ///
  /// Returning `null` from [updater] deletes the current document.
  void update(
    Query query,
    Map<String, dynamic>? Function(Map<String, dynamic> inDoc) updater,
  ) {
    final serializedQuery = BsonCodec.serialize(query.toMap()).byteList;
    Pointer<Uint8> serializedQueryPtr = _bindings.albedo_malloc(
      serializedQuery.length,
    );
    serializedQueryPtr
        .asTypedList(serializedQuery.length)
        .setAll(0, serializedQuery);

    Pointer<Int64> out = _bindings.albedo_malloc(8).cast();
    Pointer<Uint64> outDoc = _bindings.albedo_malloc(8).cast();
    Pointer<albedo_transform_iterator> iterator = Pointer.fromAddress(0);

    try {
      final transformRes = _bindings.albedo_transform(
        _handle,
        serializedQueryPtr,
        out as Pointer<Pointer<albedo_transform_iterator>>,
      );

      if (transformRes.value > 1) {
        throw Exception('Error creating transform iterator: $transformRes');
      }

      iterator =
          Pointer.fromAddress(out.value) as Pointer<albedo_transform_iterator>;

      while (true) {
        final res = _bindings.albedo_transform_data(
          iterator,
          outDoc as Pointer<Pointer<Uint8>>,
        );

        if (res == albedo_result.ALBEDO_EOS) {
          break;
        }

        if (res.value > 1) {
          throw Exception('Error reading transform data: $res');
        }

        final dataPtr = Pointer.fromAddress(outDoc.value).cast<Uint8>();
        final size = dataPtr.cast<Uint32>().value;
        final data = dataPtr.asTypedList(size);
        final doc = BsonCodec.deserialize(BsonBinary.from(data));

        final updatedDoc = updater(Map<String, dynamic>.from(doc as Map));
        if (updatedDoc == null) {
          final applyRes = _bindings.albedo_transform_apply(
            iterator,
            Pointer<Uint8>.fromAddress(0),
          );
          if (applyRes.value > 1) {
            throw Exception('Error applying transform: $applyRes');
          }
          continue;
        }

        final updatedBuffer = BsonCodec.serialize(updatedDoc).byteList;
        final updatedPtr = _bindings.albedo_malloc(updatedBuffer.length);
        updatedPtr.asTypedList(updatedBuffer.length).setAll(0, updatedBuffer);

        try {
          final applyRes = _bindings.albedo_transform_apply(
            iterator,
            updatedPtr,
          );
          if (applyRes.value > 1) {
            throw Exception('Error applying transform: $applyRes');
          }
        } finally {
          _bindings.albedo_free(updatedPtr, updatedBuffer.length);
        }
      }
    } finally {
      if (iterator.address != 0) {
        _bindings.albedo_transform_close(iterator);
      }
      _bindings.albedo_free(serializedQueryPtr, serializedQuery.length);
      _bindings.albedo_free(out.cast(), 8);
      _bindings.albedo_free(outDoc.cast(), 8);
    }
  }

  /// Ensures an index exists at [path].
  albedo_result ensureIndex(
    String path, {
    bool unique = false,
    bool sparse = false,
    bool reverse = false,
  }) {
    final optionsByte =
        (unique ? 1 : 0) | ((sparse ? 1 : 0) << 1) | ((reverse ? 1 : 0) << 2);

    final pathPtr = path.toNativeUtf8();
    final res = _bindings.albedo_ensure_index(
      _handle,
      pathPtr.cast<Char>(),
      optionsByte,
    );
    malloc.free(pathPtr);
    return res;
  }

  /// Drops the index stored at [path].
  albedo_result dropIndex(String path) {
    final pathPtr = path.toNativeUtf8();
    final res = _bindings.albedo_drop_index(_handle, pathPtr.cast<Char>());
    malloc.free(pathPtr);
    return res;
  }

  /// Deletes all documents matching [query].
  void delete(Query query) {
    final serializedQuery = BsonCodec.serialize(query.toMap()).byteList;
    final serializedQueryPtr = malloc<Uint8>(serializedQuery.length);
    serializedQueryPtr
        .asTypedList(serializedQuery.length)
        .setAll(0, serializedQuery);

    try {
      _bindings.albedo_delete(
        _handle,
        serializedQueryPtr,
        serializedQuery.length,
      );
    } finally {
      malloc.free(serializedQueryPtr);
    }
  }

  /// Opens an oplog subscription for change events matching [query].
  ///
  /// The caller is responsible for calling [Subscription.close] when done.
  /// Use [subscribeStream] for a managed async stream that handles gaps
  /// automatically.
  Subscription subscribe(dynamic query) {
    final serializedQuery =
        BsonCodec.serialize(_normalizeQuery(query)).byteList;
    final serializedQueryPtr = malloc<Uint8>(serializedQuery.length);
    serializedQueryPtr
        .asTypedList(serializedQuery.length)
        .setAll(0, serializedQuery);

    final out = malloc<Pointer<albedo_subscription_handle>>();

    try {
      final res = _bindings.albedo_subscribe(_handle, serializedQueryPtr, out);
      if (res != albedo_result.ALBEDO_OK) {
        throw Exception('albedo_subscribe returned $res');
      }
      return Subscription._internal(out.value);
    } finally {
      malloc.free(serializedQueryPtr);
      malloc.free(out);
    }
  }

  /// Returns a stream of change events matching [query].
  ///
  /// Polls every [pollingTimeout] when no new events are available.
  /// Automatically re-subscribes when [SubscriptionGapException] is thrown,
  /// so the stream never terminates due to a gap.
  Stream<ChangeEvent> subscribeStream(
    dynamic query, {
    Duration pollingTimeout = const Duration(milliseconds: 50),
    int maxEvents = 64,
  }) async* {
    var sub = subscribe(query);
    try {
      while (true) {
        List<ChangeEvent>? events;
        print('Polling for events with seqno ${sub.seqno}...');
        try {
          events = sub.poll(maxEvents: maxEvents);
          print('Polled ${events?.length ?? 0} events with seqno ${sub.seqno}');
        } on SubscriptionGapException {
          print(
            'Error polling subscription: subscription gap detected, re-subscribing...',
          );
          sub.close();
          sub = subscribe(query);
          continue;
        } catch (e) {
          print('Error polling subscription: $e');
          await Future<void>.delayed(pollingTimeout);
          continue;
        }

        if (events == null) {
          await Future<void>.delayed(pollingTimeout);
          continue;
        }

        for (final event in events) {
          yield event;
        }
      }
    } finally {
      sub.close();
    }
  }

  /// Closes the bucket handle. Repeated calls are ignored.
  void close() {
    if (_isClosed) {
      return;
    }

    _isClosed = true;
    _bindings.albedo_close(_handle);
  }

  /// Flushes pending writes to disk when the bucket is still open.
  void flush() {
    if (_isClosed) {
      return;
    }

    _bindings.albedo_flush(_handle);
  }

  /// Returns the version of the loaded native Albedo library.
  static int version() {
    return _bindings.albedo_version();
  }
}

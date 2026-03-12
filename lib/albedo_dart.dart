import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:bson/bson.dart';
import 'package:ffi/ffi.dart';

import 'albedo_dart_bindings_generated.dart';

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

/// A handle to an open Albedo bucket.
class Bucket {
  final AlbedoBucket _handle;
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
        out as Pointer<AlbedoBucket>,
      );

      if (openRes != ALBEDO_OK) {
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
  AlbedoListHandle _openListHandle(dynamic query) {
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
        out as Pointer<AlbedoListHandle>,
      );

      if (listRes > 1) {
        throw Exception('Error creating list iterator: $listRes');
      }

      return Pointer.fromAddress(out.value) as AlbedoListHandle;
    } finally {
      malloc.free(serializedQueryPtr);
      malloc.free(out);
    }
  }

  /// Reads the current document from [listHandle], or `null` at end-of-stream.
  dynamic _readListDocument(
    AlbedoListHandle listHandle,
    Pointer<Uint64> outDoc,
  ) {
    final res = _bindings.albedo_data(
      listHandle,
      outDoc as Pointer<Pointer<Uint8>>,
    );

    if (res == ALBEDO_EOS || outDoc.value == 0) {
      return null;
    }

    if (res > 1) {
      throw Exception('Error reading next data: $res');
    }

    final dataPtr = Pointer.fromAddress(outDoc.value).cast<Uint8>();
    final size = dataPtr.cast<Uint32>().value;
    final data = dataPtr.asTypedList(size);
    return BsonCodec.deserialize(BsonBinary.from(data));
  }

  /// Exports the current cursor state for [listHandle].
  Map<String, dynamic> _exportListCursor(AlbedoListHandle listHandle) {
    final outCursor = malloc<Pointer<Uint8>>();
    var cursorPtr = Pointer<Uint8>.fromAddress(0);
    var cursorSize = 0;

    try {
      final res = _bindings.albedo_list_cursor_export(listHandle, outCursor);

      if (res > 1) {
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
    AlbedoTransformIterator iterator = Pointer.fromAddress(0);

    try {
      final transformRes = _bindings.albedo_transform(
        _handle,
        serializedQueryPtr,
        out as Pointer<AlbedoTransformIterator>,
      );

      if (transformRes > 1) {
        throw Exception('Error creating transform iterator: $transformRes');
      }

      iterator = Pointer.fromAddress(out.value) as AlbedoTransformIterator;

      while (true) {
        final res = _bindings.albedo_transform_data(
          iterator,
          outDoc as Pointer<Pointer<Uint8>>,
        );

        if (res == ALBEDO_EOS) {
          break;
        }

        if (res > 1) {
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
          if (applyRes > 1) {
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
          if (applyRes > 1) {
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
  int ensureIndex(
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
  int dropIndex(String path) {
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

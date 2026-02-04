import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:bson/bson.dart';
import 'package:ffi/ffi.dart';

import 'albedo_dart_bindings_generated.dart';

/// A very short-lived native function.
///
/// For very short-lived functions, it is fine to call them on the main isolate.
/// They will block the Dart execution while running the native function, so
/// only do this for native functions which are guaranteed to be short-lived.
// int sum(int a, int b) => _bindings.albedo_open(path, out);

/// A longer lived native function, which occupies the thread calling it.
///
/// Do not call these kind of native functions in the main isolate. They will
/// block Dart execution. This will cause dropped frames in Flutter applications.
/// Instead, call these native functions on a separate isolate.
///
/// Modify this to suit your own use case. Example use cases:
///
/// 1. Reuse a single isolate for various different kinds of requests.
/// 2. Use multiple helper isolates for parallel execution.
// Future<int> sumAsync(int a, int b) async {
//   final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
//   final int requestId = _nextSumRequestId++;
//   final _SumRequest request = _SumRequest(requestId, a, b);
//   final Completer<int> completer = Completer<int>();
//   _sumRequests[requestId] = completer;
//   helperIsolateSendPort.send(request);
//   return completer.future;
// }

const String _libName = 'albedo';

/// The dynamic library in which the symbols for [AlbedoDartBindings] can be found.
final DynamicLibrary _dylib = () {
  if (Platform.isIOS) {
    // return DynamicLibrary.open('$_libName.framework/$_libName');
    return DynamicLibrary.process();
  }
  if (Platform.isMacOS) {
    // return DynamicLibrary.open('$_libName.framework/$_libName');
    return DynamicLibrary.open("lib$_libName.dylib");
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// The bindings to the native functions in [_dylib].
final AlbedoDartBindings _bindings = AlbedoDartBindings(_dylib);

Query where(
  String field, {
  dynamic eq,
  dynamic ne,
  dynamic gt,
  dynamic lt,
  dynamic gte,
  dynamic lte,
  List<dynamic>? inn,
  (dynamic, dynamic)? between,
}) {
  return Query().where(
    field,
    eq: eq,
    ne: ne,
    gt: gt,
    lt: lt,
    gte: gte,
    lte: lte,
    oneof: inn,
    between: between,
  );
}

class Query {
  Map<String, dynamic> query = {};
  Query where(
    String field, {
    dynamic eq,
    dynamic ne,
    dynamic gt,
    dynamic lt,
    dynamic gte,
    dynamic lte,
    List<dynamic>? oneof,
    (dynamic, dynamic)? between,
  }) {
    if (query['query'] == null) {
      query['query'] = {};
    }
    if (eq != null) {
      query['query'][field] = {r'$eq': eq};
    }
    if (gt != null) {
      query['query'][field] = {r'$gt': gt};
    }
    if (ne != null) {
      query['query'][field] = {r'$ne': ne};
    }
    if (lt != null) {
      query['query'][field] = {r'$lt': lt};
    }
    if (gte != null) {
      query['query'][field] = {r'$gte': gte};
    }
    if (lte != null) {
      query['query'][field] = {r'$lte': lte};
    }
    if (oneof != null) {
      query['query'][field] = {r'$in': oneof};
    }
    if (between != null) {
      query['query'][field] = {
        r'$between': [between.$1, between.$2],
      };
    }
    return this;
  }

  Query limit(int limit) {
    assert(limit >= 0);
    if (query['sector'] == null) {
      query['sector'] = {};
    }
    query['sector']['limit'] = limit;
    return this;
  }

  Query offset(int offset) {
    assert(offset >= 0);
    if (query['sector'] == null) {
      query['sector'] = {};
    }
    query['sector']['offset'] = offset;
    return this;
  }

  Query sort({String? desc, String? asc}) {
    assert((desc == null && asc != null) || (desc != null && asc == null));
    if (query['sort'] == null) {
      query['sort'] = {};
    }
    if (desc != null) {
      query['sort']['desc'] = desc;
    } else {
      query['sort']['asc'] = asc;
    }
    return this;
  }
}

class Bucket {
  final AlbedoBucket _handle;
  // final String _path;

  const Bucket._internal(this._handle);

  factory Bucket.open(String path) {
    final out = malloc<Int64>(1);
    final res = _bindings.albedo_open(
      path.toNativeUtf8() as Pointer<Char>,
      out as Pointer<AlbedoBucket>,
    );

    return Bucket._internal(Pointer.fromAddress(out.value));
  }

  void insert(dynamic obj) {
    final docBuffer = BsonCodec.serialize(obj).byteList;
    Pointer<Uint8> docBufferPtr = malloc<Uint8>(docBuffer.length);
    docBufferPtr.asTypedList(docBuffer.length).setAll(0, docBuffer);
    _bindings.albedo_insert(_handle, docBufferPtr);
  }

  Iterable<dynamic> list(Query query) {
    return listRaw(query.query);
  }

  Iterable<dynamic> listRaw(dynamic query) sync* {
    final serializedDocc = BsonCodec.serialize(query).byteList;
    Pointer<Uint8> serializedDocPtr = malloc<Uint8>(serializedDocc.length);
    serializedDocPtr
        .asTypedList(serializedDocc.length)
        .setAll(0, serializedDocc);

    Pointer<Int64> out = malloc<Int64>(1);

    _bindings.albedo_list(
      _handle,
      serializedDocPtr,
      out as Pointer<AlbedoListHandle>,
    );

    final listHandle = Pointer.fromAddress(out.value) as AlbedoListHandle;

    Pointer<Uint64> outDoc = malloc<Uint64>(1);

    while (true) {
      final res = _bindings.albedo_data(
        listHandle,
        outDoc as Pointer<Pointer<Uint8>>,
      );
      if (res == 3) {
        break;
      }

      if (res > 1) {
        throw Exception('Error reading next data: $res');
      }

      final dataPtr = Pointer.fromAddress(outDoc.value) as Pointer<Uint8>;
      final size = dataPtr.cast<Uint32>().value;
      final data = dataPtr.asTypedList(size);
      final doc = BsonCodec.deserialize(BsonBinary.from(data));
      yield doc;
    }

    _bindings.albedo_close_iterator(listHandle);
  }

  Map<String, dynamic>? get(Query query) {
    final serializedDocc = BsonCodec.serialize(query.query).byteList;
    Pointer<Uint8> serializedDocPtr = malloc<Uint8>(serializedDocc.length);
    serializedDocPtr
        .asTypedList(serializedDocc.length)
        .setAll(0, serializedDocc);

    Pointer<Int64> out = malloc<Int64>(1);

    _bindings.albedo_list(
      _handle,
      serializedDocPtr,
      out as Pointer<AlbedoListHandle>,
    );

    final listHandle = Pointer.fromAddress(out.value) as AlbedoListHandle;

    Pointer<Uint64> outDoc = malloc<Uint64>(1);

    final res = _bindings.albedo_data(
      listHandle,
      outDoc as Pointer<Pointer<Uint8>>,
    );

    if (res == 3) {
      _bindings.albedo_close_iterator(listHandle);
      return null;
    }

    if (res > 1) {
      throw Exception('Error reading next data: $res');
    }

    final dataPtr = Pointer.fromAddress(outDoc.value) as Pointer<Uint8>;
    final size = dataPtr.cast<Uint32>().value;
    final data = dataPtr.asTypedList(size);

    final doc = BsonCodec.deserialize(BsonBinary.from(data));

    _bindings.albedo_close_iterator(listHandle);
    return doc;
  }

  void update(
    Query query,
    Map<String, dynamic> Function(Map<String, dynamic> inDoc) updater,
  ) {
    final serializedQuery = BsonCodec.serialize(query.query).byteList;
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

        final dataPtr = Pointer.fromAddress(outDoc.value) as Pointer<Uint8>;
        final size = dataPtr.cast<Uint32>().value;
        final data = dataPtr.asTypedList(size);
        final doc = BsonCodec.deserialize(BsonBinary.from(data));

        final updatedDoc = updater(doc);
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

  int dropIndex(String path) {
    final pathPtr = path.toNativeUtf8();
    final res = _bindings.albedo_drop_index(_handle, pathPtr.cast<Char>());
    malloc.free(pathPtr);
    return res;
  }

  void delete(Query query) {
    final serializedDocc = BsonCodec.serialize(query.query).byteList;
    Pointer<Uint8> serializedDocPtr = malloc<Uint8>(serializedDocc.length);
    serializedDocPtr
        .asTypedList(serializedDocc.length)
        .setAll(0, serializedDocc);

    _bindings.albedo_delete(_handle, serializedDocPtr, serializedDocc.length);
  }

  void close() {
    _bindings.albedo_close(_handle);
  }

  static int version() {
    final version = _bindings.albedo_version();
    print('Albedo version: ${version}');
    return version;
  }
}

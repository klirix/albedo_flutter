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

  // Relies on _id field to be unique
  void update(
    Query query,
    Map<String, dynamic> Function(Map<String, dynamic> inDoc) updater,
  ) {
    for (var doc in list(query)) {
      delete(where("id", eq: doc['_id']));
      final updatedDoc = updater(doc);
      insert(updatedDoc);
    }
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

// /// A request to compute `sum`.
// ///
// /// Typically sent from one isolate to another.
// class _SumRequest {
//   final int id;
//   final int a;
//   final int b;

//   const _SumRequest(this.id, this.a, this.b);
// }

// /// A response with the result of `sum`.
// ///
// /// Typically sent from one isolate to another.
// class _SumResponse {
//   final int id;
//   final int result;

//   const _SumResponse(this.id, this.result);
// }

// /// Counter to identify [_SumRequest]s and [_SumResponse]s.
// int _nextSumRequestId = 0;

// /// Mapping from [_SumRequest] `id`s to the completers corresponding to the correct future of the pending request.
// final Map<int, Completer<int>> _sumRequests = <int, Completer<int>>{};

// /// The SendPort belonging to the helper isolate.
// Future<SendPort> _helperIsolateSendPort = () async {
//   // The helper isolate is going to send us back a SendPort, which we want to
//   // wait for.
//   final Completer<SendPort> completer = Completer<SendPort>();

//   // Receive port on the main isolate to receive messages from the helper.
//   // We receive two types of messages:
//   // 1. A port to send messages on.
//   // 2. Responses to requests we sent.
//   final ReceivePort receivePort =
//       ReceivePort()..listen((dynamic data) {
//         if (data is SendPort) {
//           // The helper isolate sent us the port on which we can sent it requests.
//           completer.complete(data);
//           return;
//         }
//         if (data is _SumResponse) {
//           // The helper isolate sent us a response to a request we sent.
//           final Completer<int> completer = _sumRequests[data.id]!;
//           _sumRequests.remove(data.id);
//           completer.complete(data.result);
//           return;
//         }
//         throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
//       });

//   // Start the helper isolate.
//   await Isolate.spawn((SendPort sendPort) async {
//     final ReceivePort helperReceivePort =
//         ReceivePort()..listen((dynamic data) {
//           // On the helper isolate listen to requests and respond to them.
//           if (data is _SumRequest) {
//             final int result = _bindings.sum_long_running(data.a, data.b);
//             final _SumResponse response = _SumResponse(data.id, result);
//             sendPort.send(response);
//             return;
//           }
//           throw UnsupportedError(
//             'Unsupported message type: ${data.runtimeType}',
//           );
//         });

//     // Send the port to the main isolate on which we can receive requests.
//     sendPort.send(helperReceivePort.sendPort);
//   }, receivePort.sendPort);

//   // Wait until the helper isolate has sent us back the SendPort on which we
//   // can start sending requests.
//   return completer.future;
// }();

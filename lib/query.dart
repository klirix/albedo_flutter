part of 'albedo_dart.dart';

/// Deep-clones a BSON-like value so query mutations do not leak across calls.
dynamic _cloneBsonValue(dynamic value) {
  if (value is Map) {
    return _cloneBsonDocument(value);
  }

  if (value is List) {
    return value.map(_cloneBsonValue).toList(growable: false);
  }

  return value;
}

/// Deep-clones a BSON-like document and normalizes keys to strings.
Map<String, dynamic> _cloneBsonDocument(Map<dynamic, dynamic> document) {
  return Map<String, dynamic>.fromEntries(
    document.entries.map(
      (entry) => MapEntry('${entry.key}', _cloneBsonValue(entry.value)),
    ),
  );
}

/// Creates a new [Query] with a single filter applied to [field].
Query where(
  String field, {
  dynamic eq,
  dynamic ne,
  dynamic gt,
  dynamic lt,
  dynamic gte,
  dynamic lte,
  List<dynamic>? inn,
  List<dynamic>? oneof,
  (dynamic, dynamic)? between,
  String? startsWith,
  String? endsWith,
  bool? exists,
  bool? notExists,
}) {
  return Query().where(
    field,
    eq: eq,
    ne: ne,
    gt: gt,
    lt: lt,
    gte: gte,
    lte: lte,
    inn: inn,
    oneof: oneof,
    between: between,
    startsWith: startsWith,
    endsWith: endsWith,
    exists: exists,
    notExists: notExists,
  );
}

/// Builds a BSON query document compatible with Albedo's query parser.
class Query {
  /// Creates an empty query or clones an existing BSON-like [initial] document.
  Query([Map<String, dynamic>? initial])
    : query =
          initial == null ? <String, dynamic>{} : _cloneBsonDocument(initial);

  /// The raw BSON-like query document sent to the native layer.
  final Map<String, dynamic> query;

  /// Ensures the filter section exists and returns it.
  Map<String, dynamic> _ensureFilterSection() {
    return query.putIfAbsent('query', () => <String, dynamic>{})
        as Map<String, dynamic>;
  }

  /// Ensures the sector section exists and returns it.
  Map<String, dynamic> _ensureSectorSection() {
    return query.putIfAbsent('sector', () => <String, dynamic>{})
        as Map<String, dynamic>;
  }

  /// Ensures the sort section exists and returns it.
  Map<String, dynamic> _ensureSortSection() {
    return query.putIfAbsent('sort', () => <String, dynamic>{})
        as Map<String, dynamic>;
  }

  /// Ensures the projection section exists and returns it.
  Map<String, dynamic> _ensureProjectionSection() {
    return query.putIfAbsent('projection', () => <String, dynamic>{})
        as Map<String, dynamic>;
  }

  /// Assigns a single operator/value filter for [field].
  void _setFilter(String field, String operator, dynamic value) {
    final filterSection = _ensureFilterSection();
    filterSection[field] = {operator: value};
  }

  /// Adds or replaces the filter applied to [field].
  ///
  /// Only one operator is stored per field; if multiple parameters are supplied,
  /// the last non-null one wins.
  Query where(
    String field, {
    dynamic eq,
    dynamic ne,
    dynamic gt,
    dynamic lt,
    dynamic gte,
    dynamic lte,
    List<dynamic>? inn,
    List<dynamic>? oneof,
    (dynamic, dynamic)? between,
    String? startsWith,
    String? endsWith,
    bool? exists,
    bool? notExists,
  }) {
    final inValues = oneof ?? inn;

    if (eq != null) {
      _setFilter(field, r'$eq', eq);
    }
    if (ne != null) {
      _setFilter(field, r'$ne', ne);
    }
    if (gt != null) {
      _setFilter(field, r'$gt', gt);
    }
    if (lt != null) {
      _setFilter(field, r'$lt', lt);
    }
    if (gte != null) {
      _setFilter(field, r'$gte', gte);
    }
    if (lte != null) {
      _setFilter(field, r'$lte', lte);
    }
    if (inValues != null) {
      _setFilter(field, r'$in', List<dynamic>.from(inValues));
    }
    if (between != null) {
      _setFilter(field, r'$between', [between.$1, between.$2]);
    }
    if (startsWith != null) {
      _setFilter(field, r'$startsWith', startsWith);
    }
    if (endsWith != null) {
      _setFilter(field, r'$endsWith', endsWith);
    }
    if (exists == true) {
      _setFilter(field, r'$exists', true);
    }
    if (notExists == true) {
      _setFilter(field, r'$notExists', true);
    }

    return this;
  }

  /// Sets the maximum number of results to return.
  Query limit(int limit) {
    assert(limit >= 0);
    _ensureSectorSection()['limit'] = limit;
    return this;
  }

  /// Skips the first [offset] matching results.
  Query offset(int offset) {
    assert(offset >= 0);
    _ensureSectorSection()['offset'] = offset;
    return this;
  }

  /// Applies a single-field ascending or descending sort.
  Query sort({String? desc, String? asc}) {
    assert((desc == null && asc != null) || (desc != null && asc == null));
    final sortSection = _ensureSortSection();
    if (desc != null) {
      sortSection
        ..clear()
        ..['desc'] = desc;
    } else {
      sortSection
        ..clear()
        ..['asc'] = asc;
    }
    return this;
  }

  /// Keeps only the listed top-level fields in each result document.
  /// Replaces any previous projection (pick or omit).
  Query pick(List<String> fields) {
    assert(fields.isNotEmpty);
    _ensureProjectionSection()
      ..clear()
      ..['pick'] = List<String>.from(fields);
    return this;
  }

  /// Drops the listed top-level fields from each result document.
  /// Replaces any previous projection (pick or omit).
  Query omit(List<String> fields) {
    assert(fields.isNotEmpty);
    _ensureProjectionSection()
      ..clear()
      ..['omit'] = List<String>.from(fields);
    return this;
  }

  /// Attaches a previously exported Albedo cursor document to this query.
  Query cursor(Map<dynamic, dynamic> cursor) {
    query['cursor'] = _cloneBsonDocument(cursor);
    return this;
  }

  /// Removes any attached cursor document from this query.
  Query clearCursor() {
    query.remove('cursor');
    return this;
  }

  /// Returns a deep-cloned BSON-like document for FFI serialization.
  Map<String, dynamic> toMap() {
    return _cloneBsonDocument(query);
  }
}

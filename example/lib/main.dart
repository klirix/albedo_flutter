import 'dart:async';

import 'package:albedo_flutter/albedo_dart.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E6F5E),
        useMaterial3: true,
      ),
      home: const ExampleHomePage(),
    );
  }
}

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({super.key});

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage>
    with WidgetsBindingObserver {
  Bucket? _users;
  StreamSubscription<dynamic>? _tableWatcher;
  int _version = 0;
  int? _selectedTimestamp;
  int _ignoredWatchEvents = 0;
  bool _isClosingBucket = false;
  bool _isInitializing = true;
  bool _isWatchingTable = false;
  bool _isWorking = false;
  String _statusMessage = 'Opening example bucket...';
  List<_UserRecord> _records = const [];

  bool get _isReady => _users != null && !_isInitializing;

  _UserRecord? get _selectedRecord {
    final selectedTimestamp = _selectedTimestamp;
    if (selectedTimestamp == null) {
      return null;
    }

    for (final record in _records) {
      if (record.selectionKey == selectedTimestamp) {
        return record;
      }
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _version = Bucket.version();
    _initializeBucket();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        _users?.flush();
        break;
      case AppLifecycleState.detached:
        unawaited(_closeBucket());
        break;
      case AppLifecycleState.resumed:
        break;
    }
  }

  Query _tableQuery() {
    return Query().sort(desc: 'timestamp').limit(50);
  }

  Future<void> _initializeBucket() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final bucketPath = '${dir.path}/albedo_test.bucket';
      final users = Bucket.open(
        bucketPath,
        options: const BucketOpenOptions(autoVacuum: false),
      );
      users.ensureIndex('timestamp', reverse: true);

      if (!mounted) {
        users.close();
        return;
      }

      setState(() {
        _users = users;
        _isInitializing = false;
        _statusMessage = 'Bucket ready at ${dir.path}/albedo_test.bucket';
      });

      await _refreshTable(successMessage: 'Loaded latest documents');
      _startTableWatcher();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isInitializing = false;
        _statusMessage = 'Failed to open bucket: $error';
      });
    }
  }

  void _startTableWatcher() {
    final users = _users;
    if (users == null) {
      return;
    }

    _tableWatcher?.cancel();
    _ignoredWatchEvents = _records.length;
    _tableWatcher = users
        .stream(_tableQuery())
        .listen(
          _handleWatchedDocument,
          onError: (Object error) {
            if (!mounted) {
              return;
            }

            setState(() {
              _isWatchingTable = false;
              _statusMessage = 'Live watcher failed: $error';
            });
          },
        );

    if (mounted) {
      setState(() {
        _isWatchingTable = true;
      });
    }
  }

  void _handleWatchedDocument(dynamic doc) {
    final watchedRecord = _UserRecord.fromDocument(
      Map<String, dynamic>.from(doc as Map),
      0,
    );

    if (_ignoredWatchEvents > 0) {
      _ignoredWatchEvents -= 1;

      if (_ignoredWatchEvents == 0 && mounted) {
        setState(() {
          _statusMessage = 'Live watcher attached to table query';
        });
      }
      return;
    }

    unawaited(
      _refreshTable(
        successMessage: 'Live update received for ${watchedRecord.name}',
      ),
    );
  }

  Future<void> _refreshTable({String? successMessage}) async {
    final users = _users;
    if (users == null) {
      return;
    }

    try {
      final documents =
          users
              .list(_tableQuery())
              .map((doc) => Map<String, dynamic>.from(doc as Map))
              .toList();

      final records = <_UserRecord>[];
      for (var index = 0; index < documents.length; index++) {
        records.add(_UserRecord.fromDocument(documents[index], index));
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _records = records;
        if (_selectedTimestamp != null &&
            !records.any(
              (record) => record.selectionKey == _selectedTimestamp,
            )) {
          _selectedTimestamp = null;
        }
        if (successMessage != null) {
          _statusMessage = successMessage;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = 'Failed to refresh table: $error';
      });
    }
  }

  Future<void> _runAction(
    String label,
    void Function(Bucket) action, [
    bool refreshAfterAction = true,
  ]) async {
    final users = _users;
    if (users == null || _isWorking) {
      return;
    }

    setState(() {
      _isWorking = true;
      _statusMessage = '$label...';
    });

    try {
      action(users);
      if (refreshAfterAction) {
        await _refreshTable(successMessage: '$label complete');
      } else if (mounted) {
        setState(() {
          _statusMessage = '$label complete. Waiting for live table update...';
        });
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = '$label failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
        });
      }
    }
  }

  Map<String, dynamic> _buildSampleDocument(int offset) {
    final timestamp = DateTime.now().add(Duration(milliseconds: offset));
    return {
      'name': 'user_${timestamp.millisecondsSinceEpoch}',
      'value': _records.length + offset + 1,
      'timestamp': timestamp,
    };
  }

  Future<void> _closeBucket() async {
    if (_isClosingBucket) {
      return;
    }

    _isClosingBucket = true;

    final watcher = _tableWatcher;
    final users = _users;

    _tableWatcher = null;
    _users = null;
    _isWatchingTable = false;

    if (watcher != null) {
      await watcher.cancel();
    }

    users?.close();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_closeBucket());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedRecord = _selectedRecord;

    return Scaffold(
      appBar: AppBar(title: const Text('Albedo Example Table')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Manage example documents with native Albedo storage.',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The table below is backed by the bucket opened from the example app support directory.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _InfoChip(label: 'Version', value: _version.toString()),
                        _InfoChip(
                          label: 'Rows',
                          value: _records.length.toString(),
                        ),
                        _InfoChip(
                          label: 'Watcher',
                          value: _isWatchingTable ? 'Live' : 'Stopped',
                        ),
                        _InfoChip(
                          label: 'Selected',
                          value: selectedRecord?.name ?? 'None',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _statusMessage,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed:
                          _isReady && !_isWorking
                              ? () => _refreshTable(
                                successMessage: 'Table refreshed',
                              )
                              : null,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                    FilledButton.icon(
                      onPressed:
                          _isReady && !_isWorking
                              ? () =>
                                  _runAction('Inserted sample row', (users) {
                                    users.insert(_buildSampleDocument(0));
                                  }, false)
                              : null,
                      icon: const Icon(Icons.add),
                      label: const Text('Insert Row'),
                    ),
                    FilledButton.icon(
                      onPressed:
                          _isReady && !_isWorking
                              ? () =>
                                  _runAction('Inserted sample batch', (users) {
                                    for (var index = 0; index < 5; index++) {
                                      users.insert(_buildSampleDocument(index));
                                    }
                                  }, false)
                              : null,
                      icon: const Icon(Icons.library_add),
                      label: const Text('Insert 5 Rows'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _isReady && !_isWorking && selectedRecord != null
                              ? () =>
                                  _runAction('Renamed selected row', (users) {
                                    users.update(
                                      where(
                                        'timestamp',
                                        eq: selectedRecord.timestamp,
                                      ),
                                      (inDoc) {
                                        final currentName =
                                            '${inDoc['name'] ?? 'user'}';
                                        return {
                                          ...inDoc,
                                          'name':
                                              currentName.endsWith('_edited')
                                                  ? currentName
                                                  : '${currentName}_edited',
                                        };
                                      },
                                    );
                                  })
                              : null,
                      icon: const Icon(Icons.edit),
                      label: const Text('Rename Selected'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _isReady && !_isWorking && selectedRecord != null
                              ? () => _runAction('Incremented selected row', (
                                users,
                              ) {
                                users.update(
                                  where(
                                    'timestamp',
                                    eq: selectedRecord.timestamp,
                                  ),
                                  (inDoc) {
                                    final currentValue =
                                        (inDoc['value'] as num?)?.toInt() ?? 0;
                                    return {
                                      ...inDoc,
                                      'value': currentValue + 1,
                                    };
                                  },
                                );
                              })
                              : null,
                      icon: const Icon(Icons.exposure_plus_1),
                      label: const Text('Increment Selected'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _isReady && !_isWorking && selectedRecord != null
                              ? () =>
                                  _runAction('Deleted selected row', (users) {
                                    users.delete(
                                      where(
                                        'timestamp',
                                        eq: selectedRecord.timestamp,
                                      ),
                                    );
                                  })
                              : null,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete Selected'),
                    ),
                    TextButton.icon(
                      onPressed:
                          _isReady && !_isWorking && _records.isNotEmpty
                              ? () => _runAction('Cleared table', (users) {
                                users.delete(Query());
                              })
                              : null,
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Clear Table'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child:
                    _isInitializing
                        ? const Center(child: CircularProgressIndicator())
                        : _buildTable(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    if (_records.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.table_rows_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'No rows yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Insert one or more sample rows to populate the table.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 760),
          child: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('#')),
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Value'), numeric: true),
              DataColumn(label: Text('Timestamp')),
            ],
            rows: List<DataRow>.generate(_records.length, (index) {
              final record = _records[index];
              final isSelected = record.selectionKey == _selectedTimestamp;

              return DataRow.byIndex(
                index: index,
                selected: isSelected,
                onSelectChanged: (_) {
                  setState(() {
                    _selectedTimestamp =
                        isSelected ? null : record.selectionKey;
                    _statusMessage =
                        isSelected
                            ? 'Selection cleared'
                            : 'Selected ${record.name}';
                  });
                },
                cells: [
                  DataCell(Text('${index + 1}')),
                  DataCell(Text(record.name)),
                  DataCell(Text(record.value.toString())),
                  DataCell(Text(record.formattedTimestamp)),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    );
  }
}

class _UserRecord {
  const _UserRecord({
    required this.name,
    required this.value,
    required this.timestamp,
  });

  final String name;
  final int value;
  final DateTime timestamp;

  int get selectionKey => timestamp.millisecondsSinceEpoch;

  String get formattedTimestamp {
    final local = timestamp.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute:$second';
  }

  factory _UserRecord.fromDocument(Map<String, dynamic> document, int index) {
    final timestampValue = document['timestamp'];
    final timestamp = switch (timestampValue) {
      DateTime value => value,
      int value => DateTime.fromMillisecondsSinceEpoch(value),
      _ => DateTime.fromMillisecondsSinceEpoch(index),
    };

    return _UserRecord(
      name: '${document['name'] ?? 'user_$index'}',
      value: (document['value'] as num?)?.toInt() ?? 0,
      timestamp: timestamp,
    );
  }
}

import 'package:albedo_flutter/albedo_dart.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late int sumResult;

  late Bucket users;

  @override
  void initState() {
    super.initState();
    getApplicationSupportDirectory().then((dir) {
      users = Bucket.open('${dir.path}/albedo_test.bucket');
      users.ensureIndex("timestamp", reverse: true);
    });
    sumResult = Bucket.version();
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 25);
    const spacerSmall = SizedBox(height: 10);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Native Packages')),
        body: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                const Text(
                  'This calls a native function through FFI that is shipped as source in the package. '
                  'The native code is built as part of the Flutter Runner build.',
                  style: textStyle,
                  textAlign: TextAlign.center,
                ),
                spacerSmall,
                ElevatedButton(
                  onPressed: () {
                    // users.insert({"name": "test", "value": 1});
                    final timeNow = DateTime.now().millisecondsSinceEpoch;
                    var res = users.list(
                      Query().sort(desc: "timestamp").limit(2),
                    );

                    final delta =
                        DateTime.now().millisecondsSinceEpoch - timeNow;

                    print("docs: ${List.from(res)}, in: $delta ms");
                  },
                  child: Text("List documents"),
                ),
                ElevatedButton(
                  onPressed: () {
                    users.insert({
                      "name": "test",
                      "value": 1,
                      "timestamp": DateTime.now(),
                    });
                  },
                  child: Text("Insert garbage documents"),
                ),
                ElevatedButton(
                  onPressed: () {
                    users.update(where("name", eq: "test"), (inDoc) {
                      return {...inDoc, "name": "test2"};
                    });
                  },
                  child: Text("Transform garbage documents"),
                ),

                ElevatedButton(
                  onPressed: () {
                    users.delete(Query());
                  },
                  child: Text("Delete"),
                ),
                Text(
                  'sum(1, 2) = $sumResult',
                  style: textStyle,
                  textAlign: TextAlign.center,
                ),
                spacerSmall,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

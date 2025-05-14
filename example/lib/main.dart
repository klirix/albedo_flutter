import 'package:flutter/material.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart';

import 'package:albedo_dart/albedo_dart.dart';

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
    getApplicationDocumentsDirectory().then((dir) {
      users = Bucket.open('${dir.path}/albedo_test.bucket');
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
                    users.insert({"name": "test", "value": 1});
                    var res = users.list(
                      where("name", eq: "test")
                          .where("value", between: (4, 5))
                          .where("age", oneof: [18, 19, 20]),
                      // .limit(1),
                    );
                    print("docs: ${List.from(res)}");
                  },
                  child: Text("List documents"),
                ),
                ElevatedButton(
                  onPressed: () {
                    users.insert({"name": "test", "value": 1});
                  },
                  child: Text("Insert garbage documents"),
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

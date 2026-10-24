import 'package:flutter/material.dart';

import 'screens/home_page.dart';
import 'store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  store.load();
  runApp(TaskApp(store: store));
}

class TaskApp extends StatelessWidget {
  const TaskApp({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Task Blocks',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: Colors.teal, brightness: Brightness.dark, useMaterial3: true),
      home: HomePage(store: store),
    );
  }
}

import 'package:flutter/material.dart';

import 'reminders.dart';
import 'screens/home_page.dart';
import 'store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final reminders = Reminders();
  final store = AppStore(reminders: reminders);
  // Don't hold up loading the tasks behind the notification-permission prompt.
  Future.wait([reminders.init(), store.load()]).then((_) => reminders.schedule(store.data));
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

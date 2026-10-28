import 'dart:async';

import 'package:flutter/material.dart';

import 'home_widgets.dart';
import 'reminders.dart';
import 'screens/home_page.dart';
import 'store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final reminders = Reminders();
  final widgets = HomeWidgets();
  final store = AppStore(reminders: reminders, widgets: widgets);
  // Don't hold up loading the tasks behind the notification-permission prompt.
  Future.wait([reminders.init(), store.load()]).then((_) => reminders.schedule(store.data));
  runApp(TaskApp(store: store, widgets: widgets));
}

class TaskApp extends StatefulWidget {
  const TaskApp({super.key, required this.store, this.widgets});

  final AppStore store;
  final HomeWidgets? widgets;

  @override
  State<TaskApp> createState() => _TaskAppState();
}

class _TaskAppState extends State<TaskApp> {
  final _home = GlobalKey<HomePageState>();
  StreamSubscription<Uri?>? _clicks;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    final w = widget.widgets;
    if (w != null) {
      w.launchUri().then(_handleUri);
      _clicks = w.clicks.listen(_handleUri);
    }
    // Pick up ticks made on a widget while the app was in the background.
    _lifecycle = AppLifecycleListener(onResume: widget.store.applyWidgetTicks);
  }

  @override
  void dispose() {
    _clicks?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _handleUri(Uri? uri) {
    if (uri == null || uri.scheme != 'taskblocks') return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final home = _home.currentState;
      if (home == null) return;
      if (uri.host == 'add') home.focusAdd();
      if (uri.host == 'open' && uri.queryParameters['id'] != null) home.openTask(uri.queryParameters['id']!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return MaterialApp(
      title: 'Task Blocks',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: Colors.teal, brightness: Brightness.dark, useMaterial3: true),
      home: HomePage(key: _home, store: store),
    );
  }
}

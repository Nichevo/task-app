import 'dart:async';

import 'package:flutter/material.dart';

import 'home_widgets.dart';
import 'native.dart';
import 'reminders.dart';
import 'screens/home_page.dart';
import 'store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final reminders = Reminders();
  final widgets = HomeWidgets();
  final store = AppStore(reminders: reminders, widgets: widgets);
  reminders.onAction = store.applyPending;
  // Don't hold up loading the tasks behind the notification-permission prompt.
  Future.wait([reminders.init(), store.load()]).then((_) {
    reminders.dir = store.dirPath;
    reminders.schedule(store.data);
  });
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
    _lifecycle = AppLifecycleListener(
      // Pick up ticks made on a widget or a notification while the app was in the background.
      onResume: () {
        widget.store.applyPending();
        _takeShared();
      },
      // Save straight away rather than waiting for the usual short delay.
      onPause: widget.store.flush,
    );
    _takeShared();
  }

  @override
  void dispose() {
    _clicks?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _takeShared() async {
    final shared = await Native.takeShared();
    if (shared == null) return;
    _onHome((home) => home.addShared(shared));
  }

  void _onHome(void Function(HomePageState home) f) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final home = _home.currentState;
      if (home != null) f(home);
    });
  }

  void _handleUri(Uri? uri) {
    if (uri == null || uri.scheme != 'taskblocks') return;
    final q = uri.queryParameters;
    _onHome((home) {
      switch (uri.host) {
        case 'add':
          home.focusAdd(text: q['text'], categoryId: q['cat']);
        case 'open':
          if (q['id'] != null) home.openTask(q['id']!);
        case 'day':
          home.openCalendar(DateTime.tryParse(q['d'] ?? ''));
        case 'stats':
          home.openStats();
      }
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

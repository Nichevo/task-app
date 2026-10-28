import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../native.dart';
import '../store.dart';

/// Events in the next 14 days from the chosen calendars that aren't tasks yet and weren't dismissed.
Future<List<CalendarEvent>> upcomingEvents(AppData data) async {
  final now = DateTime.now();
  final events = await Native.events(now, now.add(const Duration(days: 14)), data.eventCalendars);
  return [
    for (final e in events)
      if (!data.dismissedEvents.contains(e.id) && data.taskForEvent(e.id) == null) e,
  ];
}

/// Upcoming calendar events, each with a button to make a task from it.
class EventsPage extends StatefulWidget {
  const EventsPage({super.key, required this.store});

  final AppStore store;

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  List<CalendarEvent>? _events;
  String? _error;
  bool _denied = false;

  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _events = null;
      _error = null;
    });
    if (!await Native.requestCalendarAccess()) {
      setState(() => _denied = true);
      return;
    }
    try {
      final now = DateTime.now();
      final all = await Native.events(now, now.add(const Duration(days: 14)), store.data.eventCalendars);
      if (mounted) setState(() => _events = all);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _makeTask(CalendarEvent e) async {
    final when = await showDialog<Duration>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(e.title),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(c, Duration.zero), child: const Text('Due when it starts')),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, const Duration(days: 1)), child: const Text('Due the day before')),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, const Duration(days: 7)), child: const Text('Due a week before')),
        ],
      ),
    );
    if (when == null) return;
    final due = e.allDay && when == Duration.zero
        ? DateTime(e.start.year, e.start.month, e.start.day, 9)
        : e.start.subtract(when);
    final title = when == Duration.zero ? e.title : 'Prepare for ${e.title}';
    store.addTask(title, due: due, eventId: e.id, notes: e.location == null ? '' : 'At ${e.location}');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final data = store.data;
    final fmt = DateFormat('EEE d MMM');
    final timeFmt = DateFormat('HH:mm');
    Widget body;
    if (_denied) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Calendar access is needed to see upcoming events. Nothing leaves the phone.',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                setState(() => _denied = false);
                _load();
              },
              child: const Text('Allow'),
            ),
          ]),
        ),
      );
    } else if (_error != null) {
      body = Center(child: Text('Could not read the calendar: $_error'));
    } else if (_events == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_events!.isEmpty) {
      body = const Center(child: Text('No events in the next 14 days.'));
    } else {
      body = ListView(children: [
        for (final e in _events!)
          Builder(builder: (context) {
            final task = data.taskForEvent(e.id);
            final dismissed = data.dismissedEvents.contains(e.id);
            return ListTile(
              leading: Icon(task != null ? Icons.check_circle : Icons.event, color: task != null ? Colors.green : null),
              title: Text(e.title, style: TextStyle(color: dismissed ? Theme.of(context).disabledColor : null)),
              subtitle: Text('${fmt.format(e.start)}${e.allDay ? '' : ', ${timeFmt.format(e.start)}'}'
                  '${e.location == null || e.location!.isEmpty ? '' : ' · ${e.location}'}'
                  '${task != null ? '\nTask: ${task.title}' : dismissed ? '\nNot suggested again' : ''}'),
              isThreeLine: task != null || dismissed,
              trailing: task != null
                  ? null
                  : Wrap(children: [
                      if (!dismissed)
                        IconButton(
                          tooltip: "Don't suggest this",
                          icon: const Icon(Icons.close),
                          onPressed: () => store.dismissEvent(e.id),
                        ),
                      FilledButton.tonal(onPressed: () => _makeTask(e), child: const Text('+ Task')),
                    ]),
            );
          }),
      ]);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upcoming events'),
        actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: ListenableBuilder(listenable: store, builder: (_, _) => body),
    );
  }
}

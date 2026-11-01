import 'package:flutter/material.dart';

import '../places.dart';
import '../store.dart';
import 'settings_page.dart' show askText;

/// Settings, Places: saved places for place reminders (Android).
class PlacesPage extends StatefulWidget {
  const PlacesPage({super.key, required this.store});

  final AppStore store;

  @override
  State<PlacesPage> createState() => _PlacesPageState();
}

class _PlacesPageState extends State<PlacesPage> {
  PlaceSetup? _setup;
  bool _adding = false;
  late final AppLifecycleListener _lifecycle;

  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _check();
    // Coming back from Android's settings pages: look again.
    _lifecycle = AppLifecycleListener(onResume: _check);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final s = await PlaceReminders.setup();
    if (s.alwaysLocation) await store.watchPlaces();
    if (mounted) setState(() => _setup = s);
  }

  Future<void> _add() async {
    final name = await askText(context, 'Name this place (you are here now)');
    if (name == null || name.trim().isEmpty || !mounted) return;
    setState(() => _adding = true);
    final p = await store.addPlaceHere(name);
    if (!mounted) return;
    setState(() => _adding = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(p == null
            ? 'Could not get your location. Check that location is on and allowed for Task Blocks.'
            : 'Saved "${p.name}". Pick it on a task under "Place reminder".')));
  }

  Future<void> _edit(Place p) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(p.name),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'rename'), child: const Text('Rename')),
          for (final r in placeRadiusOptions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, 'r$r'),
              child: Text('Radius $r m${r == p.radius ? '  ✓' : ''}'),
            ),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Delete place')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'rename') {
      final name = await askText(context, 'Rename place', initial: p.name);
      if (name != null) await store.updatePlace(p, name: name);
    } else if (choice == 'delete') {
      await store.deletePlace(p);
    } else {
      await store.updatePlace(p, radius: int.parse(choice.substring(1)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = _setup;
    final hint = TextStyle(fontSize: 12, color: Theme.of(context).hintColor);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Places')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _adding ? null : _add,
          icon: _adding
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_location_alt_outlined),
          label: const Text('Save where I am'),
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
          Text(
            'Save the places you go (home, work, the shops), then give a task "Remind me when I arrive" or '
            '"when I leave". A task with a due date reminds you on arriving that day, and each day while '
            'it is overdue; one without a date reminds you on the next arrival. The places stay on this phone; '
            'only their names go with the tasks.',
            style: hint,
          ),
          const SizedBox(height: 12),
          if (setup != null && !setup.ready)
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('One-time setup', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('So the phone can tell you when you arrive, even with the app closed:'),
                  const SizedBox(height: 8),
                  _step(setup.alwaysLocation, 'Location: "Allow all the time"', 'Open', PlaceReminders.askAlwaysLocation),
                  _step(setup.batteryUnrestricted, 'Battery: "Unrestricted" (Samsung holds alerts back otherwise)', 'Open',
                      PlaceReminders.askBatteryUnrestricted),
                ]),
              ),
            ),
          if (store.places.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('No places yet.')),
          for (final p in store.places)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.place_outlined),
              title: Text(p.name),
              subtitle: Text('Within ${p.radius} m · '
                  '${store.data.active.where((t) => t.place == p.name).length} open task(s)'),
              trailing: const Icon(Icons.more_vert),
              onTap: () => _edit(p),
            ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('On arriving, show the day\'s tasks'),
            subtitle: const Text('One notification when you arrive at any saved place, listing what is due today '
                'or overdue (once per place per day).'),
            value: store.arrivalSummary,
            onChanged: store.setArrivalSummary,
          ),
          Text('Alerts are accurate to about 100 to 200 m and can come a few minutes late.', style: hint),
        ]),
      ),
    );
  }

  Widget _step(bool done, String text, String action, Future<void> Function() onTap) => Row(children: [
        Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
        if (!done) TextButton(onPressed: () => onTap(), child: Text(action)),
      ]);
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../day_plan.dart' show describeLength, suggestDrive;
import '../geocode.dart';
import '../models.dart';
import '../places.dart';
import '../store.dart';

/// 1.12.5: where a task happens, and the driving before and after it.

/// "20 min there · 15 min after", or the estimate when none is set.
String driveSummary(AppData data, Task t) {
  String part(int? set, bool after) {
    if (set != null) return set == 0 ? 'none ${after ? 'after' : 'there'}' : '${describeLength(set)} ${after ? 'after' : 'there'}';
    final d = suggestDrive(data, t, after: after);
    if (d == null) return after ? '' : 'none there';
    return '≈${describeLength(d.minutes)} ${after ? 'back to' : 'from'} ${d.from ?? 'last stop'}';
  }

  final before = part(t.driveBefore, false), after = part(t.driveAfter, true);
  return [before, if (after.isNotEmpty) after].join(' · ');
}

/// Opens the location in the phone's maps app (Google Maps on the web otherwise).
Future<void> openInMaps(TaskWhere w) async {
  final q = w.pinned ? '${w.lat},${w.lng}' : w.name;
  await launchUrl(Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': q}),
      mode: LaunchMode.externalApplication);
}

/// Picks where [t] happens: a saved place, where the phone is now, an address search, or just a
/// name.
Future<void> pickTaskWhere(BuildContext context, AppStore store, Task t) async {
  final picked = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => _WhereSheet(store: store, task: t),
  );
  if (picked is TaskWhere) {
    store.setWhere(t, picked);
  } else if (picked == 'remove') {
    store.setWhere(t, null);
  }
}

class _WhereSheet extends StatefulWidget {
  const _WhereSheet({required this.store, required this.task});
  final AppStore store;
  final Task task;

  @override
  State<_WhereSheet> createState() => _WhereSheetState();
}

class _WhereSheetState extends State<_WhereSheet> {
  late final _text = TextEditingController(text: widget.task.where?.name ?? '');
  List<TaskWhere>? _found;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await searchAddress(_text.text);
      if (!mounted) return;
      setState(() {
        _found = r;
        if (r.isEmpty) _error = 'Nothing found. Try adding the suburb or town.';
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t search: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _here() async {
    setState(() => _busy = true);
    final p = await widget.store.whereNow();
    if (!mounted) return;
    setState(() => _busy = false);
    if (p == null) {
      setState(() => _error = 'Couldn\'t get your location. Check location access for the app.');
      return;
    }
    final name = _text.text.trim();
    Navigator.pop(context, TaskWhere(name.isEmpty ? 'Pinned spot' : name, lat: p.lat, lng: p.lng));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typed = _text.text.trim();
    final places = widget.store.places;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
            Text('Location', style: theme.textTheme.titleMedium),
            Text('Where this task happens. It\'s separate from place reminders.',
                style: TextStyle(color: theme.hintColor, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              autofocus: widget.task.where == null,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: 'Address or name',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Search for the address',
                  icon: const Icon(Icons.search),
                  onPressed: typed.isEmpty || _busy ? null : _search,
                ),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
            for (final w in _found ?? const <TaskWhere>[])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_on_outlined),
                title: Text(w.name),
                onTap: () => Navigator.pop(context, w),
              ),
            if (_found != null && _found!.isNotEmpty)
              Text('Search by OpenStreetMap', style: TextStyle(fontSize: 11, color: theme.hintColor)),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.my_location),
              title: const Text('Where I am now'),
              subtitle: typed.isEmpty ? null : Text('Named "$typed"'),
              onTap: _busy ? null : _here,
            ),
            for (final p in places)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined),
                title: Text(p.name),
                subtitle: const Text('Saved place'),
                onTap: () => Navigator.pop(context, TaskWhere(p.name, lat: p.lat, lng: p.lng)),
              ),
            if (typed.isNotEmpty && typed != widget.task.where?.name)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_location_alt_outlined),
                title: Text('Just "$typed"'),
                subtitle: const Text('No pin, so no driving time can be suggested'),
                onTap: () => Navigator.pop(context, TaskWhere(typed)),
              ),
            if (widget.task.where != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_off_outlined),
                title: const Text('Remove location'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ]),
        ),
      ),
    );
  }
}

const _driveChoices = [0, 5, 10, 15, 20, 25, 30, 40, 45, 50, 60, 75, 90, 120];

/// Sets the driving time before and after [t]'s planned times; "Suggested" works it out from
/// the distance each time.
Future<void> editDrive(BuildContext context, AppStore store, Task t) async {
  int? before = t.driveBefore, after = t.driveAfter;
  final sBefore = suggestDrive(store.data, t, after: false), sAfter = suggestDrive(store.data, t, after: true);
  String suggested(({int minutes, String? from, bool estimate})? d, bool after) => d == null
      ? (t.where?.pinned ?? false)
          ? (homePlace(store.places) == null ? 'Suggested (save a place called Home)' : 'Suggested: none')
          : 'Suggested (needs a pinned location)'
      : 'Suggested: ≈${describeLength(d.minutes)} ${after ? 'to' : 'from'} ${d.from ?? 'the last stop'}';
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        Widget pick(String label, int? value, ValueChanged<int?> on, ({int minutes, String? from, bool estimate})? s, bool isAfter) =>
            DropdownButtonFormField<int?>(
              initialValue: value,
              isExpanded: true,
              decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
              items: [
                DropdownMenuItem(value: null, child: Text(suggested(s, isAfter), overflow: TextOverflow.ellipsis)),
                for (final m in _driveChoices)
                  DropdownMenuItem(value: m, child: Text(m == 0 ? 'No driving' : describeLength(m))),
                if (value != null && !_driveChoices.contains(value))
                  DropdownMenuItem(value: value, child: Text(describeLength(value))),
              ],
              onChanged: (v) => set(() => on(v)),
            );
        return AlertDialog(
          title: const Text('Driving time'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Shown on the Day plan before and after each planned time, and counted as busy. '
              'Suggestions are rough: the distance from the previous stop that day (or Home) at town speeds.',
              style: TextStyle(fontSize: 13, color: Theme.of(c).hintColor),
            ),
            const SizedBox(height: 16),
            pick('Before (getting there)', before, (v) => before = v, sBefore, false),
            const SizedBox(height: 12),
            pick('After (moving on)', after, (v) => after = v, sAfter, true),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        );
      },
    ),
  );
  if (ok == true) store.setDrive(t, before: before, after: after);
}

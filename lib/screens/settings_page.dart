import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dropbox.dart';
import '../models.dart';
import '../native.dart';
import '../store.dart';
import '../widgets/task_colors.dart';

/// Choices for the extra reminder before a task is due, in minutes.
const remindOptions = {0: 'At due time only', 15: '15 min before', 60: '1 hour before', 1440: '1 day before', 10080: '1 week before'};

/// Asks for a line of text, e.g. a category name.
Future<String?> askText(BuildContext context, String title, {String initial = ''}) {
  final field = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: field,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.pop(c, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, field.text), child: const Text('OK')),
      ],
    ),
  );
}

/// Asks for several lines (one item per line), e.g. the steps of a template.
Future<List<String>?> askLines(BuildContext context, String title, {List<String> initial = const [], String hint = 'One step per line'}) {
  final field = TextEditingController(text: initial.join('\n'));
  return showDialog<List<String>>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: field,
        autofocus: true,
        minLines: 4,
        maxLines: 12,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(c, [for (final l in field.text.split('\n')) l.trim()].where((l) => l.isNotEmpty).toList()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Choices for how long closed tasks stay in the archive, in days (0 = forever).
const archiveKeepOptions = {0: 'Never', 30: '1 month', 90: '3 months', 180: '6 months', 365: '1 year'};

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store});

  final AppStore store;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _key = TextEditingController(text: widget.store.dropboxAppKey);
  List<DeviceCalendar>? _calendars;

  AppStore get store => widget.store;
  AppData get data => store.data;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  int get _speedIndex {
    final h = data.hoursToRed;
    var best = 0;
    for (var i = 0; i < speedSteps.length; i++) {
      if ((speedSteps[i] - h).abs() < (speedSteps[best] - h).abs()) best = i;
    }
    return best;
  }

  void _set(VoidCallback change) {
    change();
    store.changed(settings: true);
  }

  Future<void> _connect() async {
    final key = _key.text.trim();
    if (key.isEmpty) return;
    store.dropboxAppKey = key;
    final client = DropboxClient(key);
    await launchUrl(client.authorizeUrl(), mode: LaunchMode.externalApplication);
    if (!mounted) return;
    final code = await showDialog<String>(
      context: context,
      builder: (c) {
        final field = TextEditingController();
        return AlertDialog(
          title: const Text('Paste the Dropbox code'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Approve access in the browser, then copy the code Dropbox shows and paste it here.'),
            TextField(controller: field, autofocus: true, decoration: const InputDecoration(labelText: 'Code')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, field.text), child: const Text('Connect')),
          ],
        );
      },
    );
    if (code == null || code.trim().isEmpty) return;
    try {
      await store.connectDropbox(client, code);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not connect: $e')));
      }
    }
  }

  Future<void> _editCategory(TaskCategory c) async {
    final name = TextEditingController(text: c.name);
    final keywords = TextEditingController(text: c.keywords.join(', '));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Category'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          TextField(
            controller: keywords,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Keywords',
              helperText: 'Separated by commas. A new task with one of these words always goes here.',
              helperMaxLines: 2,
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    if (name.text.trim().isNotEmpty) store.renameCategory(c, name.text);
    store.setKeywords(c, keywords.text.split(','));
  }

  Future<void> _loadCalendars() async {
    if (!await Native.requestCalendarAccess()) return;
    final cals = await Native.calendars();
    if (mounted) setState(() => _calendars = cals);
  }

  Future<TimeOfDay?> _pickTime(int minutes) =>
      showTimePicker(context: context, initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60));

  static String _time(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final idx = _speedIndex;
        final connected = store.dropbox != null;
        final sample = DateTime.now();
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            _heading('Colour speed'),
            Text('Tasks go from green to red in ${describeHours(speedSteps[idx])}.'),
            Slider(
              value: idx.toDouble(),
              min: 0,
              max: (speedSteps.length - 1).toDouble(),
              divisions: speedSteps.length - 1,
              label: describeHours(speedSteps[idx]),
              onChanged: (v) => _set(() => data.hoursToRed = speedSteps[v.round()]),
            ),
            // Preview of the colour a task has at each fifth of the way to red.
            Row(children: [
              for (var i = 0; i <= 5; i++)
                Expanded(
                  child: Container(
                    height: 22,
                    color: ageColor(
                      Task(id: '', title: '', createdAt: sample.subtract(
                          Duration(minutes: (data.hoursToRed * 60 * i / 5).round()))),
                      data.hoursToRed,
                      now: sample,
                    ),
                  ),
                ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Colour by due date'),
              subtitle: const Text('Tasks with a due date turn red as the due date gets closer, '
                  'instead of by the speed above.'),
              value: data.colourByDue,
              onChanged: (v) => _set(() => data.colourByDue = v),
            ),
            const Divider(height: 40),
            _heading('List'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Only show tasks due in the next 30 days'),
              subtitle: const Text('Plus tasks with no due date and anything overdue. '
                  'Tasks due later are under "Due later" at the bottom of the list.'),
              value: data.focusNext30,
              onChanged: (v) => _set(() => data.focusNext30 = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Group by category'),
              subtitle: const Text('Show a bold heading for each category with its tasks underneath. '
                  'Tap a heading to collapse it; drag a task under another heading to move it.'),
              value: data.groupByCategory,
              onChanged: (v) => _set(() => data.groupByCategory = v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto category'),
              subtitle: const Text('For a new task with no #tag: learn from tasks already filed and from '
                  'category keywords. Everything stays on this device.'),
              trailing: DropdownButton<AutoCategory>(
                value: data.autoCategory,
                items: const [
                  DropdownMenuItem(value: AutoCategory.off, child: Text('Off')),
                  DropdownMenuItem(value: AutoCategory.suggest, child: Text('Suggest')),
                  DropdownMenuItem(value: AutoCategory.apply, child: Text('Apply')),
                ],
                onChanged: (v) => _set(() => data.autoCategory = v ?? AutoCategory.suggest),
              ),
            ),
            const Divider(height: 40),
            _heading('Reminders'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Before the due time'),
              subtitle: const Text('Default for tasks with a due date (each task can change it)'),
              trailing: DropdownButton<int>(
                value: remindOptions.containsKey(data.defaultRemindBefore) ? data.defaultRemindBefore : 0,
                items: [for (final e in remindOptions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => _set(() => data.defaultRemindBefore = v ?? 0),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Overdue tasks'),
              subtitle: Text(switch (data.overdueMode) {
                OverdueMode.off => 'No extra reminders once a task is overdue.',
                OverdueMode.daily => 'One summary a day at ${_time(data.overdueAt)} listing what is overdue.',
                OverdueMode.nudge => 'A reminder every ${data.nudgeHours} hour${data.nudgeHours == 1 ? '' : 's'} per overdue task until it is done or snoozed.',
              }),
              trailing: DropdownButton<OverdueMode>(
                value: data.overdueMode,
                items: const [
                  DropdownMenuItem(value: OverdueMode.off, child: Text('Off')),
                  DropdownMenuItem(value: OverdueMode.daily, child: Text('Daily summary')),
                  DropdownMenuItem(value: OverdueMode.nudge, child: Text('Keep nudging')),
                ],
                onChanged: (v) => _set(() => data.overdueMode = v ?? OverdueMode.off),
              ),
            ),
            if (data.overdueMode == OverdueMode.daily)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Summary time'),
                trailing: Text(_time(data.overdueAt)),
                onTap: () async {
                  final t = await _pickTime(data.overdueAt);
                  if (t != null) _set(() => data.overdueAt = t.hour * 60 + t.minute);
                },
              ),
            if (data.overdueMode == OverdueMode.nudge) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Nudge every'),
                trailing: DropdownButton<int>(
                  value: const [1, 3, 6].contains(data.nudgeHours) ? data.nudgeHours : 3,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 hour')),
                    DropdownMenuItem(value: 3, child: Text('3 hours')),
                    DropdownMenuItem(value: 6, child: Text('6 hours')),
                  ],
                  onChanged: (v) => _set(() => data.nudgeHours = v ?? 3),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Quiet hours'),
                subtitle: Text('No nudges from ${_time(data.quietStart)} to ${_time(data.quietEnd)}'),
                onTap: () async {
                  final from = await _pickTime(data.quietStart);
                  if (from == null || !mounted) return;
                  final to = await _pickTime(data.quietEnd);
                  if (to == null) return;
                  _set(() {
                    data.quietStart = from.hour * 60 + from.minute;
                    data.quietEnd = to.hour * 60 + to.minute;
                  });
                },
              ),
            ],
            Text('Every reminder has Done and Snooze buttons.', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
            const Divider(height: 40),
            Row(children: [
              Expanded(child: _heading('Categories')),
              TextButton.icon(
                onPressed: () async {
                  final name = await askText(context, 'New category');
                  if (name != null && name.trim().isNotEmpty) store.addCategory(name);
                },
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ]),
            if (data.categories.isEmpty)
              const Text('No categories yet. Add some, then pick one in each task or type #name when adding.'),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: store.moveCategory,
              children: [
                for (final (i, c) in data.categories.indexed)
                  ListTile(
                    key: ValueKey(c.id),
                    contentPadding: EdgeInsets.zero,
                    leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                    title: Text(c.name),
                    subtitle: c.keywords.isEmpty ? null : Text('Keywords: ${c.keywords.join(', ')}'),
                    onTap: () => _editCategory(c),
                    trailing: IconButton(
                      tooltip: 'Delete category (its tasks are kept)',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => store.deleteCategory(c),
                    ),
                  ),
              ],
            ),
            const Divider(height: 40),
            Row(children: [
              Expanded(child: _heading('Checklist templates')),
              TextButton.icon(
                onPressed: () async {
                  final name = await askText(context, 'Template name');
                  if (name == null || name.trim().isEmpty || !context.mounted) return;
                  final lines = await askLines(context, 'Steps for "${name.trim()}"');
                  if (lines != null && lines.isNotEmpty) store.saveTemplate(name, lines);
                },
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ]),
            if (data.templates.isEmpty)
              const Text('Save a task\'s checklist as a template from the Templates button on the task, '
                  'then add it to any task in one tap.'),
            for (final t in data.templates)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.checklist),
                title: Text(t.name),
                subtitle: Text(t.steps.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () async {
                  final lines = await askLines(context, t.name, initial: t.steps);
                  if (lines != null) store.updateTemplate(t, steps: lines);
                },
                trailing: Wrap(children: [
                  IconButton(
                    tooltip: 'Rename',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final name = await askText(context, 'Template name', initial: t.name);
                      if (name != null && name.trim().isNotEmpty) store.updateTemplate(t, name: name);
                    },
                  ),
                  IconButton(
                    tooltip: 'Delete template',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => store.deleteTemplate(t),
                  ),
                ]),
              ),
            if (Native.supported) ...[
              const Divider(height: 40),
              _heading('Calendar events'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Suggest tasks from events'),
                subtitle: const Text('Upcoming events is always in the menu. This also shows a line at the top of the '
                    'list now and then, which you can dismiss.'),
                trailing: DropdownButton<EventSuggest>(
                  value: data.eventSuggest,
                  items: const [
                    DropdownMenuItem(value: EventSuggest.off, child: Text('Only when I look')),
                    DropdownMenuItem(value: EventSuggest.daily, child: Text('Once a day')),
                    DropdownMenuItem(value: EventSuggest.weekly, child: Text('Once a week')),
                  ],
                  onChanged: (v) => _set(() => data.eventSuggest = v ?? EventSuggest.off),
                ),
              ),
              if (_calendars == null)
                TextButton.icon(
                  onPressed: _loadCalendars,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(data.eventCalendars.isEmpty ? 'Choose calendars (all for now)' : 'Choose calendars (${data.eventCalendars.length} chosen)'),
                )
              else ...[
                const Text('Calendars to take events from (none ticked = all):'),
                for (final c in _calendars!)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(c.name),
                    subtitle: Text(c.account),
                    value: data.eventCalendars.contains(c.id),
                    onChanged: (v) => _set(() => v == true ? data.eventCalendars.add(c.id) : data.eventCalendars.remove(c.id)),
                  ),
              ],
              const Divider(height: 40),
              Row(children: [
                Expanded(child: _heading('Suggestions from notifications')),
                Chip(label: const Text('Coming later'), visualDensity: VisualDensity.compact, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest),
              ]),
              Text(
                'Planned: watch notifications from a few apps you choose (deliveries, appointments, bills) and '
                'offer them as tasks. Not built yet, so these are switched off.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
              ),
              const SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Suggest tasks from notifications'),
                value: false,
                onChanged: null,
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: false,
                title: Text('Apps to watch'),
                subtitle: Text('None chosen'),
                trailing: Icon(Icons.chevron_right),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: false,
                title: Text('Look for'),
                subtitle: Text('Dates and times; appointment, due, deliver, renew, pay'),
                trailing: Icon(Icons.chevron_right),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: false,
                title: Text('Where suggestions go'),
                subtitle: Text('The same list as calendar event suggestions'),
              ),
            ],
            const Divider(height: 40),
            _heading('Archive'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Delete archived tasks after'),
              subtitle: const Text('Statistics keep counting tasks after they are deleted.'),
              trailing: DropdownButton<int>(
                value: archiveKeepOptions.containsKey(data.archiveKeepDays) ? data.archiveKeepDays : 0,
                items: [
                  for (final e in archiveKeepOptions.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => _set(() => data.archiveKeepDays = v ?? 0),
              ),
            ),
            const Divider(height: 40),
            _heading('Dropbox sync'),
            Text('Status: ${store.syncStatus}'),
            const SizedBox(height: 12),
            if (!connected) ...[
              const Text(
                'One-time setup: at dropbox.com/developers/apps create an app with '
                '"Scoped access" and "App folder". On its Permissions tab tick '
                'files.content.read and files.content.write, then copy the App key here.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _key,
                decoration: const InputDecoration(labelText: 'Dropbox app key', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _connect,
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('Connect Dropbox'),
              ),
            ] else
              Wrap(spacing: 12, children: [
                FilledButton.icon(
                  onPressed: store.syncing ? null : store.sync,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync now'),
                ),
                OutlinedButton(onPressed: store.disconnectDropbox, child: const Text('Disconnect')),
              ]),
            const SizedBox(height: 8),
            Text(
              'Your tasks are saved to Apps/<your app name>/tasks.json in Dropbox. '
              'Connect the same app key on your phone and PC to share one list.\n\n'
              'Inbox: any line written to Apps/<your app name>/inbox.txt becomes a task on the next sync '
              '(handy with email-to-Dropbox, IFTTT or Zapier). Dates and #categories in the line are read too.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
            ),
          ]),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dropbox.dart';
import '../models.dart';
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

  AppStore get store => widget.store;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  int get _speedIndex {
    final h = store.data.hoursToRed;
    var best = 0;
    for (var i = 0; i < speedSteps.length; i++) {
      if ((speedSteps[i] - h).abs() < (speedSteps[best] - h).abs()) best = i;
    }
    return best;
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
            Text('Colour speed', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Tasks go from green to red in ${describeHours(speedSteps[idx])}.'),
            Slider(
              value: idx.toDouble(),
              min: 0,
              max: (speedSteps.length - 1).toDouble(),
              divisions: speedSteps.length - 1,
              label: describeHours(speedSteps[idx]),
              onChanged: (v) {
                store.data.hoursToRed = speedSteps[v.round()];
                store.changed(settings: true);
              },
            ),
            // Preview of the colour a task has at each fifth of the way to red.
            Row(children: [
              for (var i = 0; i <= 5; i++)
                Expanded(
                  child: Container(
                    height: 22,
                    color: ageColor(
                      Task(id: '', title: '', createdAt: sample.subtract(
                          Duration(minutes: (store.data.hoursToRed * 60 * i / 5).round()))),
                      store.data.hoursToRed,
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
              value: store.data.colourByDue,
              onChanged: (v) {
                store.data.colourByDue = v;
                store.changed(settings: true);
              },
            ),
            const Divider(height: 40),
            Text('List', style: Theme.of(context).textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Only show tasks due in the next 30 days'),
              subtitle: const Text('Plus tasks with no due date and anything overdue. '
                  'Tasks due later are under "Due later" at the bottom of the list.'),
              value: store.data.focusNext30,
              onChanged: (v) {
                store.data.focusNext30 = v;
                store.changed(settings: true);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Group by category'),
              subtitle: const Text('Show a bold heading for each category with its tasks underneath. '
                  'Tap a heading to collapse it; drag a task under another heading to move it.'),
              value: store.data.groupByCategory,
              onChanged: (v) {
                store.data.groupByCategory = v;
                store.changed(settings: true);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reminders'),
              subtitle: const Text('Default for tasks with a due date (each task can change it)'),
              trailing: DropdownButton<int>(
                value: remindOptions.containsKey(store.data.defaultRemindBefore) ? store.data.defaultRemindBefore : 0,
                items: [for (final e in remindOptions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) {
                  store.data.defaultRemindBefore = v ?? 0;
                  store.changed(settings: true);
                },
              ),
            ),
            const Divider(height: 40),
            Row(children: [
              Expanded(child: Text('Categories', style: Theme.of(context).textTheme.titleMedium)),
              TextButton.icon(
                onPressed: () async {
                  final name = await askText(context, 'New category');
                  if (name != null && name.trim().isNotEmpty) store.addCategory(name);
                },
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ]),
            if (store.data.categories.isEmpty)
              const Text('No categories yet. Add some, then pick one in each task.'),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: store.moveCategory,
              children: [
                for (final (i, c) in store.data.categories.indexed)
                  ListTile(
                    key: ValueKey(c.id),
                    contentPadding: EdgeInsets.zero,
                    leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                    title: Text(c.name),
                    onTap: () async {
                      final name = await askText(context, 'Rename category', initial: c.name);
                      if (name != null && name.trim().isNotEmpty) store.renameCategory(c, name);
                    },
                    trailing: IconButton(
                      tooltip: 'Delete category (its tasks are kept)',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => store.deleteCategory(c),
                    ),
                  ),
              ],
            ),
            const Divider(height: 40),
            Text('Archive', style: Theme.of(context).textTheme.titleMedium),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Delete archived tasks after'),
              trailing: DropdownButton<int>(
                value: archiveKeepOptions.containsKey(store.data.archiveKeepDays)
                    ? store.data.archiveKeepDays
                    : 0,
                items: [
                  for (final e in archiveKeepOptions.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) {
                  store.data.archiveKeepDays = v ?? 0;
                  store.changed(settings: true);
                },
              ),
            ),
            const Divider(height: 40),
            Text('Dropbox sync', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
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
            const Text(
              'Your tasks are saved to Apps/<your app name>/tasks.json in Dropbox. '
              'Connect the same app key on your phone and PC to share one list.',
              style: TextStyle(fontSize: 12),
            ),
          ]),
        );
      },
    );
  }
}

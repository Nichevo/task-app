import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../google.dart';
import '../input_parse.dart';
import '../models.dart';
import '../store.dart';
import 'settings_page.dart';

/// Item 55: starred Gmail emails, each of which can become a task, be attached to a task, or
/// be hidden. Like Upcoming events, but for email.
class StarredPage extends StatefulWidget {
  const StarredPage({super.key, required this.store, this.loader});

  final AppStore store;

  /// Fetches the emails; tests pass their own.
  final Future<List<GmailMessage>> Function()? loader;

  @override
  State<StarredPage> createState() => _StarredPageState();
}

class _StarredPageState extends State<StarredPage> {
  List<GmailMessage>? _emails;
  String? _error;
  bool _showHidden = false;

  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = store.google;
    final loader = widget.loader ?? (g == null ? null : () => g.starred(days: store.data.starredDays));
    if (loader == null) return;
    setState(() {
      _emails = null;
      _error = null;
    });
    try {
      final all = await loader();
      if (mounted) setState(() => _emails = all);
    } on GoogleException catch (e) {
      if (e.signedOut) await store.googleSignedOut();
      if (mounted) setState(() => _error = '$e');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _makeTask(GmailMessage m) async {
    final name = TextEditingController(text: m.subject.isEmpty ? '(no subject)' : m.subject);
    final notes = TextEditingController();
    final t = await showDialog<Task>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Task from email'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Task', helperText: 'Dates and #category are read, as when typing a task',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            Text('The email (${m.sender}) is kept on the task with a link to open it in Gmail.',
                style: TextStyle(fontSize: 12, color: Theme.of(c).hintColor)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              final p = parseInput(name.text, store.data, DateTime.now());
              Navigator.pop(
                  c,
                  store.addTaskFromEmail(m,
                      title: p.title,
                      due: p.due,
                      categoryId: p.categoryId,
                      notes: notes.text.trim(),
                      box: p.box,
                      board: p.board,
                      star: p.star));
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (t != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added "${t.title}"')));
    }
  }

  Future<void> _attach(GmailMessage m) async {
    final t = await pickTask(context, store.data, title: 'Attach to which task?');
    if (t == null) return;
    store.attachEmail(t, m);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Attached to "${t.title}"')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Starred emails'),
        actions: [
          if (store.google != null || widget.loader != null)
            IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load),
          PopupMenuButton<String>(
            onSelected: (v) => setState(() => _showHidden = !_showHidden),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(value: 'hidden', checked: _showHidden, child: const Text('Show hidden emails')),
            ],
          ),
        ],
      ),
      body: ListenableBuilder(listenable: store, builder: (context, _) => _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final data = store.data;
    if (store.google == null && widget.loader == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Sign in to Google in Settings to see your starred emails here.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage(store: store)));
                if (mounted) _load();
              },
              child: const Text('Open Settings'),
            ),
          ]),
        ),
      );
    }
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    if (_emails == null) return const Center(child: CircularProgressIndicator());
    final shown = [for (final m in _emails!) if (_showHidden || !data.hiddenEmails.contains(m.id)) m];
    if (shown.isEmpty) {
      final back = data.starredDays > 0 ? 'in the last ${starredDaysOptions[data.starredDays] ?? '${data.starredDays} days'}' : '';
      return Center(child: Text('No starred emails $back.'.replaceAll(' .', '.')));
    }
    final fmt = DateFormat('EEE d MMM');
    final hint = Theme.of(context).hintColor;
    return ListView.separated(
      itemCount: shown.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final m = shown[i];
        final task = data.taskForEmail(m.id);
        final hidden = data.hiddenEmails.contains(m.id);
        final made = task != null &&
            (task.source == TaskSource.starredEmail || task.source == TaskSource.email) &&
            task.emails.first.id == m.id;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(task != null ? Icons.check_circle : Icons.star, size: 18, color: task != null ? Colors.green : Colors.amber),
              const SizedBox(width: 8),
              Expanded(child: Text(m.sender, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500))),
              if (m.date != null) Text(fmt.format(m.date!), style: TextStyle(fontSize: 12, color: hint)),
            ]),
            const SizedBox(height: 2),
            Text(m.subject.isEmpty ? '(no subject)' : m.subject,
                style: TextStyle(color: hidden ? Theme.of(context).disabledColor : null)),
            if (m.snippet.isNotEmpty)
              Text(m.snippet, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: hint)),
            const SizedBox(height: 4),
            if (task != null)
              Text(made ? 'Task: ${task.title}' : 'Attached to: ${task.title}',
                  style: const TextStyle(fontSize: 13, color: Colors.green))
            else
              Wrap(spacing: 8, children: [
                FilledButton.tonal(onPressed: () => _makeTask(m), child: const Text('Make task')),
                OutlinedButton(onPressed: () => _attach(m), child: const Text('Attach to task')),
                if (!hidden) TextButton(onPressed: () => store.hideEmail(m.id), child: const Text('Hide')),
                IconButton(
                  tooltip: 'Open in Gmail',
                  icon: const Icon(Icons.open_in_new, size: 20),
                  onPressed: () => launchUrl(AppStore.emailOf(m).link, mode: LaunchMode.externalApplication),
                ),
              ]),
          ]),
        );
      },
    );
  }
}

/// Lets the user pick an open task, with search; starred and board tasks first.
Future<Task?> pickTask(BuildContext context, AppData data, {required String title}) {
  return showDialog<Task>(
    context: context,
    builder: (c) {
      var q = '';
      return StatefulBuilder(builder: (c, setState) {
        final tasks = data.active.where((t) => q.isEmpty || t.title.toLowerCase().contains(q.toLowerCase())).toList()
          ..sort((a, b) {
            int rank(Task t) => t.starred ? 0 : t.kanban ? 1 : 2;
            return rank(a).compareTo(rank(b));
          });
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            height: 420,
            child: Column(children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search tasks'),
                onChanged: (v) => setState(() => q = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: tasks.isEmpty
                    ? const Center(child: Text('No open task matches.'))
                    : ListView(children: [
                        for (final t in tasks)
                          ListTile(
                            dense: true,
                            leading: t.starred
                                ? const Icon(Icons.star, color: Colors.amber)
                                : t.kanban
                                    ? const Icon(Icons.view_kanban_outlined)
                                    : const Icon(Icons.radio_button_unchecked),
                            title: Text(t.title),
                            subtitle: data.category(t.categoryId) == null ? null : Text(data.category(t.categoryId)!.name),
                            onTap: () => Navigator.pop(c, t),
                          ),
                      ]),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel'))],
        );
      });
    },
  );
}

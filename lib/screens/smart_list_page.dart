import 'package:flutter/material.dart';

import '../day_plan.dart' show describeLength;
import '../models.dart';
import '../smart_lists.dart';
import '../store.dart';
import '../tags.dart';
import '../task_list.dart';

/// Item 114 (11): opens the page to make or change smart list [l]. A list that isn't saved yet
/// is added on Save.
Future<void> editSmartList(BuildContext context, AppStore store, SmartList l) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SmartListPage(store: store, list: l)));

/// A new list from the chips picked above the main list (the date chip and tags).
SmartList smartListFromChips(AppStore store, QuickFilter f) {
  final l = SmartList.create('');
  l.tags.addAll(store.liveTagFilter);
  switch (f) {
    case QuickFilter.today:
      l.due = SmartDue.today.name;
    case QuickFilter.week:
      l.due = SmartDue.week.name;
    case QuickFilter.twoWeeks:
      l.due = SmartDue.twoWeeks.name;
    case QuickFilter.month:
      l.due = SmartDue.month.name;
    case QuickFilter.overdue:
      l.due = SmartDue.overdue.name;
    case QuickFilter.noDate:
      l.due = SmartDue.noDate.name;
    case QuickFilter.behind:
      l.behind = true;
    case QuickFilter.starred:
      l.starred = true;
    case QuickFilter.all:
      break;
  }
  return l;
}

class SmartListPage extends StatefulWidget {
  const SmartListPage({super.key, required this.store, required this.list});
  final AppStore store;
  final SmartList list;

  @override
  State<SmartListPage> createState() => _SmartListPageState();
}

class _SmartListPageState extends State<SmartListPage> {
  late final SmartList l = widget.list.copy();
  late final _name = TextEditingController(text: l.name);
  late final _emoji = TextEditingController(text: l.emoji);

  AppStore get store => widget.store;
  AppData get data => store.data;
  bool get _saved => data.smartList(l.id) != null;

  static const _emojis = ['📋', '🔥', '⚡', '⏳', '📅', '🏠', '💼', '📊', '🎯', '⭐', '🧪', '🚚'];

  void _save() {
    l
      ..name = _name.text.trim().isEmpty ? 'My list' : _name.text.trim()
      ..emoji = _emoji.text.trim().isEmpty ? '📋' : _emoji.text.trim();
    store.saveSmartList(l);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final matches = data.active.where((t) => !t.habit && passesSmartList(t, l, data, now)).toList();
    final hint = Theme.of(context).textTheme.bodySmall;
    final tags = tagsInUse(data);
    Widget head(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
          child: Text(text, style: Theme.of(context).textTheme.titleSmall),
        );
    Widget row(String label, Widget control) => Row(children: [Expanded(child: Text(label)), control]);

    return Scaffold(
      appBar: AppBar(
        title: Text(_saved ? 'Change list' : 'New list'),
        actions: [
          if (_saved)
            IconButton(
              tooltip: 'Delete list',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                store.deleteSmartList(l.id);
                Navigator.pop(context);
              },
            ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        Row(children: [
          SizedBox(
            width: 56,
            child: TextField(
              controller: _emoji,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22),
              decoration: const InputDecoration(labelText: 'Icon'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _name,
              autofocus: !_saved,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Client work at risk'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 4, children: [
          for (final e in _emojis)
            ChoiceChip(
              label: Text(e),
              selected: _emoji.text == e,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => _emoji.text = e),
            ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text('${matches.length} open task${matches.length == 1 ? '' : 's'} match: ${describeSmartList(l, data)}', style: hint),
        ),
        head('Category (any of)'),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final c in data.categories)
            FilterChip(
              label: Text(c.name),
              selected: l.categoryIds.contains(c.id),
              onSelected: (on) => setState(() => on ? l.categoryIds.add(c.id) : l.categoryIds.remove(c.id)),
            ),
          FilterChip(
            label: const Text('No category'),
            selected: l.categoryIds.contains(''),
            onSelected: (on) => setState(() => on ? l.categoryIds.add('') : l.categoryIds.remove('')),
          ),
        ]),
        if (tags.isNotEmpty) ...[
          head('Tag (any of)'),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final x in tags)
              FilterChip(
                label: Text('#${x.tag}'),
                selected: l.tags.any((y) => y != untaggedFilter && tagKey(y) == tagKey(x.tag)),
                onSelected: (on) => setState(() => on
                    ? l.tags.add(x.tag)
                    : l.tags.removeWhere((y) => y != untaggedFilter && tagKey(y) == tagKey(x.tag))),
              ),
          ]),
        ],
        head('Only'),
        row(
          'Due',
          DropdownButton<String?>(
            value: l.due,
            items: [
              const DropdownMenuItem(value: null, child: Text('Any time')),
              for (final d in SmartDue.values) DropdownMenuItem(value: d.name, child: Text(d.label)),
            ],
            onChanged: (v) => setState(() => l.due = v),
          ),
        ),
        row(
          'Takes at most',
          DropdownButton<int?>(
            value: l.maxMinutes,
            items: [
              const DropdownMenuItem(value: null, child: Text('Any length')),
              for (final m in smartLengths) DropdownMenuItem(value: m, child: Text(describeLength(m))),
            ],
            onChanged: (v) => setState(() => l.maxMinutes = v),
          ),
        ),
        row(
          'Matrix box',
          DropdownButton<String?>(
            value: l.box,
            items: [
              const DropdownMenuItem(value: null, child: Text('Any')),
              for (final b in MatrixBox.values) DropdownMenuItem(value: b.id, child: Text(b.label)),
            ],
            onChanged: (v) => setState(() => l.box = v),
          ),
        ),
        row(
          'Waiting on someone',
          DropdownButton<bool?>(
            value: l.waiting,
            items: const [
              DropdownMenuItem(value: null, child: Text('Either')),
              DropdownMenuItem(value: true, child: Text('Waiting')),
              DropdownMenuItem(value: false, child: Text('Not waiting')),
            ],
            onChanged: (v) => setState(() => l.waiting = v),
          ),
        ),
        if (store.places.isNotEmpty || l.place != null)
          row(
            'Place',
            DropdownButton<String?>(
              value: l.place,
              items: [
                const DropdownMenuItem(value: null, child: Text('Anywhere')),
                for (final name in {...store.places.map((p) => p.name), ?l.place}) DropdownMenuItem(value: name, child: Text(name)),
              ],
              onChanged: (v) => setState(() => l.place = v),
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Starred'),
          value: l.starred,
          onChanged: (v) => setState(() => l.starred = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Behind'),
          subtitle: const Text('Overdue, or less done than the time gone says'),
          value: l.behind,
          onChanged: (v) => setState(() => l.behind = v),
        ),
        head('Opens on'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'list', label: Text('List')),
            ButtonSegment(value: 'board', label: Text('Board')),
            ButtonSegment(value: 'matrix', label: Text('Matrix')),
          ],
          selected: {l.opens},
          onSelectionChanged: (v) => setState(() => l.opens = v.first),
        ),
        const SizedBox(height: 16),
        if (matches.isNotEmpty) ...[
          head('Shows now'),
          for (final t in matches.take(8))
            Text('• ${t.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
          if (matches.length > 8) Text('and ${matches.length - 8} more', style: hint),
        ],
      ]),
    );
  }
}

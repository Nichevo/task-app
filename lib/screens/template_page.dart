import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../store.dart';
import '../task_list.dart' show describeMinutes;

/// Item 114 F: "3 weeks before", "on the day", "2 days after".
String describeOffset(int? offset, {String label = 'due date'}) {
  if (offset == null) return 'not timed';
  if (offset == 0) return 'on the $label';
  final n = offset.abs();
  final when = offset < 0 ? 'before' : 'after';
  if (n % 7 == 0) return '${n ~/ 7} week${n == 7 ? '' : 's'} $when';
  return '$n day${n == 1 ? '' : 's'} $when';
}

/// Item 114 F: a project template: its category, tags, what its date is called, and each step's
/// length, when it starts against that date and what it comes after.
class TemplatePage extends StatefulWidget {
  const TemplatePage({super.key, required this.store, required this.template});

  final AppStore store;
  final ChecklistTemplate template;

  @override
  State<TemplatePage> createState() => _TemplatePageState();
}

class _TemplatePageState extends State<TemplatePage> {
  AppStore get store => widget.store;
  ChecklistTemplate get tpl => widget.template;

  @override
  void initState() {
    super.initState();
    // A plain checklist template becomes editable step by step.
    final specs = tpl.stepSpecs;
    if (!identical(specs, tpl.items)) {
      tpl.items
        ..clear()
        ..addAll(specs);
    }
  }

  void _changed() {
    store.templateChanged(tpl);
    setState(() {});
  }

  String get _label => tpl.dateLabel ?? 'due date';

  Future<void> _editStep(int? index) async {
    final isNew = index == null;
    final sp = isNew ? TemplateStep(title: '') : tpl.items[index];
    final title = TextEditingController(text: sp.title);
    int? days = sp.minutes == null ? sp.days : null;
    int? hours = sp.minutes == null ? null : (sp.minutes! / 60).ceil();
    var timed = sp.offset != null;
    var amount = (sp.offset ?? -7).abs();
    var weeks = amount != 0 && amount % 7 == 0;
    if (weeks) amount ~/= 7;
    var before = (sp.offset ?? -1) <= 0;
    final after = {...sp.after};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(isNew ? 'New step' : 'Step'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: title,
                autofocus: isNew,
                decoration: const InputDecoration(labelText: 'Step'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              const Text('Takes'),
              Wrap(spacing: 6, children: [
                ChoiceChip(label: const Text('Not set'), selected: days == null && hours == null, onSelected: (_) => set(() => days = hours = null)),
                for (final h in const [1, 2, 4])
                  ChoiceChip(label: Text('$h h'), selected: hours == h, onSelected: (_) => set(() => (hours, days) = (h, null))),
                for (final d in const [1, 2, 3, 5])
                  ChoiceChip(label: Text('$d d'), selected: days == d, onSelected: (_) => set(() => (days, hours) = (d, null))),
              ]),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Starts a set time from the $_label'),
                value: timed,
                onChanged: (v) => set(() => timed = v),
              ),
              if (timed)
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                  DropdownButton<int>(
                    value: amount.clamp(0, 52),
                    items: [for (var i = 0; i <= 52; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                    onChanged: (v) => set(() => amount = v ?? 0),
                  ),
                  DropdownButton<bool>(
                    value: weeks,
                    items: const [
                      DropdownMenuItem(value: false, child: Text('days')),
                      DropdownMenuItem(value: true, child: Text('weeks')),
                    ],
                    onChanged: (v) => set(() => weeks = v ?? false),
                  ),
                  DropdownButton<bool>(
                    value: before,
                    items: const [
                      DropdownMenuItem(value: true, child: Text('before')),
                      DropdownMenuItem(value: false, child: Text('after')),
                    ],
                    onChanged: (v) => set(() => before = v ?? true),
                  ),
                ]),
              if ((index ?? tpl.items.length) > 0) ...[
                const SizedBox(height: 8),
                const Text('Comes after'),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (var j = 0; j < (index ?? tpl.items.length); j++)
                    FilterChip(
                      label: Text(tpl.items[j].title, overflow: TextOverflow.ellipsis),
                      selected: after.contains(j),
                      onSelected: (v) => set(() => v ? after.add(j) : after.remove(j)),
                    ),
                ]),
              ],
            ]),
          ),
          actions: [
            if (!isNew)
              TextButton(
                onPressed: () {
                  _remove(index);
                  Navigator.pop(c, false);
                },
                child: const Text('Delete'),
              ),
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    sp
      ..title = title.text.trim()
      ..days = hours != null ? null : days
      ..minutes = hours == null ? null : hours! * 60
      ..offset = !timed ? null : (weeks ? amount * 7 : amount) * (before ? -1 : 1);
    sp.after
      ..clear()
      ..addAll(after.toList()..sort());
    if (isNew) tpl.items.add(sp);
    _changed();
  }

  void _remove(int index) {
    tpl.items.removeAt(index);
    for (final i in tpl.items) {
      final kept = [
        for (final j in i.after)
          if (j != index) j > index ? j - 1 : j,
      ];
      i.after
        ..clear()
        ..addAll(kept);
    }
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = store.data;
    final hint = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(
        title: Text('Template: ${tpl.name}'),
        actions: [
          IconButton(
            tooltip: 'Rename',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final c = TextEditingController(text: tpl.name);
              final name = await showDialog<String>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('Template name'),
                  content: TextField(controller: c, autofocus: true, onSubmitted: (v) => Navigator.pop(d, v)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save')),
                  ],
                ),
              );
              if (name != null && name.trim().isNotEmpty) {
                store.updateTemplate(tpl, name: name);
                setState(() {});
              }
            },
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          DropdownButton<String?>(
            value: data.category(tpl.categoryId) == null ? null : tpl.categoryId,
            hint: const Text('No category'),
            items: [
              const DropdownMenuItem(value: null, child: Text('No category')),
              for (final c in data.categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) {
              tpl.categoryId = v;
              _changed();
            },
          ),
          ActionChip(
            label: Text(tpl.tags.isEmpty ? 'Add tags' : tpl.tags.map((t) => '#$t').join(' ')),
            onPressed: () async {
              final c = TextEditingController(text: tpl.tags.join(' '));
              final v = await showDialog<String>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('Tags'),
                  content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'trip work')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save')),
                  ],
                ),
              );
              if (v == null) return;
              tpl.tags
                ..clear()
                ..addAll(v.split(RegExp(r'[\s,]+')).map((x) => x.replaceAll('#', '').trim()).where((x) => x.isNotEmpty));
              _changed();
            },
          ),
          ActionChip(
            label: Text('Date: $_label'),
            onPressed: () async {
              final c = TextEditingController(text: _label);
              final v = await showDialog<String>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('What is its date called?'),
                  content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'departure date')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save')),
                  ],
                ),
              );
              if (v == null) return;
              tpl.dateLabel = v.trim().isEmpty || v.trim() == 'due date' ? null : v.trim();
              _changed();
            },
          ),
        ]),
        const SizedBox(height: 8),
        Text('Steps are timed from the $_label. New from template asks for it.', style: hint),
        const SizedBox(height: 8),
        for (var i = 0; i < tpl.items.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tpl.items[i].title),
            subtitle: Text([
              if (tpl.items[i].after.isNotEmpty)
                'after ${tpl.items[i].after.where((j) => j < tpl.items.length).map((j) => tpl.items[j].title).join(', ')}',
              if (tpl.items[i].minutes != null) describeMinutes(tpl.items[i].minutes!),
              if (tpl.items[i].minutes == null && tpl.items[i].days != null) '${tpl.items[i].days} d',
            ].join(' · ')),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
              child: Text(describeOffset(tpl.items[i].offset, label: _label), style: const TextStyle(fontSize: 12)),
            ),
            onTap: () => _editStep(i),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(onPressed: () => _editStep(null), icon: const Icon(Icons.add), label: const Text('Step')),
        ),
      ]),
    );
  }
}

/// Item 114 F: New from template: a name and the template's date, then the task and its steps.
Future<Task?> newFromTemplate(BuildContext context, AppStore store, ChecklistTemplate tpl) async {
  final name = TextEditingController(text: tpl.name);
  final label = tpl.dateLabel ?? 'due date';
  final specs = tpl.stepSpecs;
  final first = specs.map((s) => s.offset).whereType<int>().fold<int?>(null, (a, b) => a == null || b < a ? b : a);
  DateTime? date = tpl.project ? DateTime.now().add(Duration(days: 7 + (first == null ? 0 : -first))) : null;
  final fmt = DateFormat('EEE d MMM');
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(c).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('New from "${tpl.name}"', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.edit_outlined)),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(label[0].toUpperCase() + label.substring(1)),
            subtitle: Text(date == null
                ? 'None'
                : '${fmt.format(date!)}${first != null && first != 0 ? ' → first step ${fmt.format(date!.add(Duration(days: first)))}' : ''}'),
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: c,
                initialDate: date ?? now,
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 5),
              );
              if (d != null) set(() => date = d);
            },
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Create task${specs.isEmpty ? '' : ' + ${specs.length} step${specs.length == 1 ? '' : 's'}'}'),
          ),
        ]),
      ),
    ),
  );
  if (ok != true || name.text.trim().isEmpty) return null;
  return store.newFromTemplate(tpl, title: name.text.trim(), date: date);
}

import 'package:flutter/material.dart';

import '../models.dart';
import '../modes.dart';
import '../store.dart';
import '../task_list.dart';
import '../widgets/mode_chip.dart';

/// Item 102: the list of focus modes, the weekly schedule, and what Everything means.
class ModesPage extends StatelessWidget {
  const ModesPage({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final data = store.data;
        final hint = TextStyle(color: Theme.of(context).hintColor, fontSize: 13);
        return Scaffold(
          appBar: AppBar(title: const Text('Focus modes')),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('New mode'),
            onPressed: () async {
              final name = await _askName(context, 'New mode', '');
              if (name == null || !context.mounted) return;
              final used = data.modes.map((m) => m.colour).toSet();
              final m = FocusMode.create(name, colour: modeColours.where((c) => !used.contains(c)).firstOrNull);
              store.addMode(m);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ModeEditPage(store: store, mode: m)));
            },
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
            Text('A mode shows only what matters right now. Nothing is moved or deleted: Everything is the whole '
                'app as it always was. Hidden tasks still get through when they are overdue, due soon or '
                'starred, as each mode says.', style: hint),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.calendar_view_week),
              title: const Text('Weekly schedule'),
              subtitle: Text(data.modeSchedule.isEmpty
                  ? 'Not set: modes change only when you pick one'
                  : _scheduleSummary(data)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ModeSchedulePage(store: store))),
            ),
            const Divider(),
            ListTile(
              leading: const CircleAvatar(
                  backgroundColor: Color(0xFF006A6A), child: Icon(Icons.all_inclusive, color: Colors.white, size: 20)),
              title: const Text('Everything'),
              subtitle: const Text('Every category and tool. Used when no mode is picked or scheduled.'),
            ),
            if (data.modes.any((m) => m.places.isNotEmpty || m.events.isNotEmpty))
              SwitchListTile(
                secondary: const Icon(Icons.help_outline),
                title: const Text('Ask before switching by place or calendar'),
                subtitle: Text(store.placeNow == null ? 'Otherwise it just switches, with Undo' : 'Now at ${store.placeNow}'),
                value: data.modeAsk,
                onChanged: (v) {
                  data.modeAsk = v;
                  store.modeChanged();
                },
              ),
            if (data.modes.isNotEmpty)
              SwitchListTile(
                secondary: const Icon(Icons.widgets_outlined),
                title: const Text('Widgets follow the mode'),
                subtitle: const Text('Home screen widgets leave out what the mode hides (urgent tasks still show). '
                    'Each widget can also have its own choice: follow the mode, always everything, or always one mode. '
                    'Add the Focus mode widget, or the quick settings tile on Android, to see and change the mode.'),
                value: data.modeWidgets,
                onChanged: (v) {
                  data.modeWidgets = v;
                  store.modeChanged();
                },
              ),
            if (data.modes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: FilledButton.icon(
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Set up Work, Home office, Weekend and Travel'),
                  onPressed: store.addStarterModes,
                ),
              ),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (o, n) => store.moveMode(o, n),
              children: [
                for (final (i, m) in data.modes.indexed)
                  ListTile(
                    key: ValueKey(m.id),
                    leading: CircleAvatar(
                        backgroundColor: Color(m.colour), child: Icon(modeIcon(m.icon), color: Colors.white, size: 20)),
                    title: Text(m.name),
                    subtitle: Text(describeMode(data, m), maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ModeEditPage(store: store, mode: m))),
                  ),
              ],
            ),
          ]),
        );
      },
    );
  }
}

String _scheduleSummary(AppData data) {
  final minutes = <String, int>{};
  for (final s in data.modeSchedule) {
    minutes[s.mode] = (minutes[s.mode] ?? 0) + s.end - s.start;
  }
  return [
    for (final e in minutes.entries)
      if (data.mode(e.key) case final m?) '${m.name} ${describeMinutes(e.value).replaceAll(' min', 'm')} a week',
  ].join(' · ');
}

Future<String?> _askName(BuildContext context, String title, String initial) async {
  final field = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: field,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Work, Weekend, Travel...'),
        onSubmitted: (v) => Navigator.pop(c, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, field.text), child: const Text('OK')),
      ],
    ),
  );
  final t = name?.trim();
  return t == null || t.isEmpty ? null : t;
}

/// Words for calendar events, comma separated; null when cancelled.
Future<List<String>?> _askWords(BuildContext context, List<String> words) async {
  final field = TextEditingController(text: words.join(', '));
  final text = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Calendar events with these words'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: field,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Flight, Trip, WFH'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        const SizedBox(height: 8),
        const Text('Separate with commas. An event whose title has one of them switches to this mode until it '
            'ends. The calendars are the ones chosen in Settings, Upcoming events (all of them if none).'),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, field.text), child: const Text('OK')),
      ],
    ),
  );
  if (text == null) return null;
  return [
    for (final w in text.split(','))
      if (w.trim().isNotEmpty) w.trim(),
  ];
}

/// Item 102: one mode's choices.
class ModeEditPage extends StatelessWidget {
  const ModeEditPage({super.key, required this.store, required this.mode});

  final AppStore store;
  final FocusMode mode;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final data = store.data;
        final m = data.mode(mode.id);
        if (m == null) return const Scaffold(body: Center(child: Text('This mode was deleted.')));
        void set(VoidCallback f) {
          f();
          store.modeChanged();
        }

        // Places and events: look again straight away.
        void setAuto(VoidCallback f) {
          set(f);
          store.checkAutoModes(force: true);
        }

        final theme = Theme.of(context);
        final hint = TextStyle(color: theme.hintColor, fontSize: 12.5);
        Widget heading(String t) => Padding(
              padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
              child: Text(t, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
            );
        Widget catRow(String id, String name) {
          final v = m.cats[id] ?? m.otherCats;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text(name)),
              SegmentedButton<CatShow>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [for (final c in CatShow.values) ButtonSegment(value: c, label: Text(c.label))],
                selected: {v},
                onSelectionChanged: (s) => set(() => m.cats[id] = s.first),
              ),
            ]),
          );
        }

        final now = DateTime.now();
        return Scaffold(
          appBar: AppBar(
            title: Text('${m.name} mode'),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'rename':
                      final n = await _askName(context, 'Rename mode', m.name);
                      if (n != null) set(() => m.name = n);
                    case 'copy':
                      final c = m.copy();
                      final copy = FocusMode.fromJson({...c.toJson(), 'id': FocusMode.create('').id, 'name': '${m.name} copy'});
                      store.addMode(copy);
                    case 'delete':
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: Text('Delete ${m.name}?'),
                          content: const Text('Its times on the weekly schedule go back to Everything. No tasks are touched.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        store.deleteMode(m);
                        if (context.mounted) Navigator.pop(context);
                      }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'copy', child: Text('Make a copy')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            heading('Look'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in modeColours)
                InkWell(
                  onTap: () => set(() => m.colour = c),
                  customBorder: const CircleBorder(),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(c),
                    child: m.colour == c ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 4, children: [
              for (final i in modeIcons)
                IconButton.filledTonal(
                  isSelected: m.icon == i,
                  onPressed: () => set(() => m.icon = i),
                  icon: Icon(modeIcon(i)),
                ),
            ]),
            heading('Categories'),
            for (final c in data.categories) catRow(c.id, c.name),
            catRow('', 'No category'),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                const Expanded(child: Text('Categories added later')),
                DropdownButton<CatShow>(
                  value: m.otherCats,
                  items: [for (final c in CatShow.values) DropdownMenuItem(value: c, child: Text(c.label))],
                  onChanged: (v) => set(() => m.otherCats = v ?? CatShow.show),
                ),
              ]),
            ),
            Text('Quiet: folded under one heading at the bottom of the list. Hide: out of sight, except when it '
                'breaks through. ${tasksInMode(data, m, now)} of ${data.tasksNotHabits.length} open tasks show.', style: hint),
            heading('Tools in this mode'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in ModeTool.values)
                FilterChip(
                  label: Text(t.label),
                  selected: m.toolOn(t),
                  onSelected: (on) => set(() => on ? m.toolsOff.remove(t.name) : m.toolsOff.add(t.name)),
                ),
            ]),
            const SizedBox(height: 4),
            Text('Tools that are on get their top bar icon when there is room; the rest are in the ⋮ menu. '
                'Off: gone from the top bar, the menu and the right-hand panel.', style: hint),
            heading('Starting point'),
            _dropdown<String?>(
              'Right-hand panel opens on',
              m.panel,
              {null: 'As set on the device', for (final v in PanelView.values) v.name: v.label},
              (v) => set(() => m.panel = v),
            ),
            _dropdown<String?>(
              'Quick filter to start with',
              m.filter,
              {null: 'Leave as it is', for (final f in QuickFilter.values) f.name: f.label},
              (v) => set(() => m.filter = v),
            ),
            _dropdown<String?>(
              'New tasks go in',
              m.newCategory,
              {null: 'As usual', '': 'No category', for (final c in data.categories) c.id: c.name},
              (v) => set(() => m.newCategory = v),
            ),
            heading('What still breaks through'),
            Text('A hidden task shows in "Still needs you" at the top of the list, and on the board and charts, when:',
                style: hint),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('It is overdue'),
              value: m.overdue,
              onChanged: (v) => set(() => m.overdue = v),
            ),
            _dropdown<DueWithin>('It is due within', m.due, {for (final d in DueWithin.values) d: d.label},
                (v) => set(() => m.due = v ?? DueWithin.today)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('It is starred'),
              value: m.starred,
              onChanged: (v) => set(() => m.starred = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('It has a time on today\'s Day plan'),
              value: m.planned,
              onChanged: (v) => set(() => m.planned = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('It has gone red'),
              subtitle: const Text('Ageing colour, or Behind on pace'),
              value: m.red,
              onChanged: (v) => set(() => m.red = v),
            ),
            Text('Any task can also be set to always show, from the menu on its page. Reminders for hidden tasks wait, and '
                'one notification lists them when the mode ends.', style: hint),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pause habits in hidden categories'),
              subtitle: const Text('No reminders, and those days don\'t break a streak'),
              value: m.pauseHabits,
              onChanged: (v) => set(() => m.pauseHabits = v),
            ),
            heading('Switch on by itself'),
            Text('Comes on at a saved place or during a calendar event, before the weekly schedule. Picking a mode '
                'by hand still wins.', style: hint),
            const SizedBox(height: 8),
            if (store.places.isEmpty && m.places.isEmpty)
              Text('No saved places on this device yet (Settings, Places).', style: hint)
            else
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final name in {...store.places.map((p) => p.name), ...m.places})
                  FilterChip(
                    avatar: const Icon(Icons.place_outlined, size: 18),
                    label: Text(name),
                    selected: m.places.contains(name),
                    onSelected: (on) => setAuto(() => on ? m.places.add(name) : m.places.remove(name)),
                  ),
              ]),
            if (m.places.isNotEmpty)
              _dropdown<String?>(
                'At these places',
                m.placeWhen,
                {
                  null: 'Any time',
                  for (final o in data.modes)
                    if (o.id != m.id) o.id: 'While the schedule says ${o.name}',
                },
                (v) => setAuto(() => m.placeWhen = v),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Calendar events with these words'),
              subtitle: Text(m.events.isEmpty ? 'None' : m.events.join(', ')),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () async {
                final words = await _askWords(context, m.events);
                if (words == null) return;
                setAuto(() => m.events
                  ..clear()
                  ..addAll(words));
              },
            ),
          ]),
        );
      },
    );
  }

  Widget _dropdown<T>(String title, T value, Map<T, String> options, ValueChanged<T?> onChanged) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(title)),
          DropdownButton<T>(
            value: options.containsKey(value) ? value : options.keys.first,
            items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: onChanged,
          ),
        ]),
      );
}

/// Item 102: the weekly schedule, painted with modes.
class ModeSchedulePage extends StatefulWidget {
  const ModeSchedulePage({super.key, required this.store});

  final AppStore store;

  @override
  State<ModeSchedulePage> createState() => _ModeSchedulePageState();
}

class _ModeSchedulePageState extends State<ModeSchedulePage> {
  /// The mode being painted ([everythingId] = rubber).
  String? _brush;

  /// The stretch being painted: day, from, to (minutes).
  (int, int, int)? _painting;

  AppStore get store => widget.store;
  AppData get data => store.data;

  static const _h = 480.0;
  static const _step = 15;

  int _minutesAt(double y) {
    final m = (y.clamp(0, _h) / _h * 24 * 60).round();
    return ((m / _step).round() * _step).clamp(0, 24 * 60);
  }

  Color _colour(String id) => Color(data.mode(id)?.colour ?? 0xFFDFE7E7);

  Future<void> _editSlot(ModeSlot s) async {
    var start = s.start, end = s.end;
    var mode = s.mode;
    String hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    final res = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(_dayNames[s.day - 1]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<String>(
              isExpanded: true,
              value: mode,
              items: [for (final m in data.modes) DropdownMenuItem(value: m.id, child: Text(m.name))],
              onChanged: (v) => setD(() => mode = v ?? mode),
            ),
            Row(children: [
              TextButton(
                onPressed: () async {
                  final t = await showTimePicker(context: c, initialTime: TimeOfDay(hour: start ~/ 60, minute: start % 60));
                  if (t != null) setD(() => start = t.hour * 60 + t.minute);
                },
                child: Text('From ${hm(start)}'),
              ),
              TextButton(
                onPressed: () async {
                  final t = await showTimePicker(
                      context: c, initialTime: TimeOfDay(hour: (end ~/ 60) % 24, minute: end % 60));
                  if (t != null) setD(() => end = t.hour == 0 && t.minute == 0 ? 24 * 60 : t.hour * 60 + t.minute);
                },
                child: Text('to ${hm(end)}'),
              ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Clear it')),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, 'ok'), child: const Text('OK')),
          ],
        ),
      ),
    );
    if (res == null) return;
    var slots = paintSchedule(data.modeSchedule, s.day, s.start, s.end, everythingId);
    if (res == 'ok' && end > start) slots = paintSchedule(slots, s.day, start, end, mode);
    store.setModeSchedule(slots);
  }

  static const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final brush = _brush ?? data.modes.firstOrNull?.id ?? everythingId;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Mode schedule'),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'clear') store.setModeSchedule([]);
                  if (v == 'starter') store.setModeSchedule(starterSchedule(data, data.modes));
                  if (v.startsWith('copy')) {
                    // Copies Monday to the other weekdays.
                    var slots = [...data.modeSchedule];
                    for (var d = DateTime.tuesday; d <= DateTime.friday; d++) {
                      slots = paintSchedule(slots, d, 0, 24 * 60, everythingId);
                      for (final s in data.modeSchedule.where((s) => s.day == DateTime.monday)) {
                        slots = paintSchedule(slots, d, s.start, s.end, s.mode);
                      }
                    }
                    store.setModeSchedule(slots);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'copy', child: Text('Copy Monday to Tuesday–Friday')),
                  if (data.modes.any((m) => m.name == 'Work'))
                    const PopupMenuItem(value: 'starter', child: Text('Start again: Work weekdays, Weekend')),
                  const PopupMenuItem(value: 'clear', child: Text('Clear the whole week')),
                ],
              ),
            ],
          ),
          body: data.modes.isEmpty
              ? const Center(child: Text('Make a mode first.'))
              : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
                  Text('Pick a mode, then press and drag down a day to paint it. Tap a stretch to change its times. '
                      'Gaps are Everything. Working hours on the Day plan: '
                      '${data.dayPlan.workStart ~/ 60}:${(data.dayPlan.workStart % 60).toString().padLeft(2, '0')}–'
                      '${data.dayPlan.workEnd ~/ 60}:${(data.dayPlan.workEnd % 60).toString().padLeft(2, '0')}.',
                      style: TextStyle(color: theme.hintColor, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final m in data.modes)
                      ChoiceChip(
                        avatar: Icon(modeIcon(m.icon), size: 18, color: Color(m.colour)),
                        label: Text(m.name),
                        selected: brush == m.id,
                        onSelected: (_) => setState(() => _brush = m.id),
                      ),
                    ChoiceChip(
                      avatar: const Icon(Icons.auto_fix_normal, size: 18),
                      label: const Text('Everything (rub out)'),
                      selected: brush == everythingId,
                      onSelected: (_) => setState(() => _brush = everythingId),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 30,
                      height: _h + 22,
                      child: Stack(children: [
                        for (var h = 0; h <= 24; h += 3)
                          Positioned(
                            top: 22 + h / 24 * _h - 7,
                            right: 2,
                            child: Text(h.toString().padLeft(2, '0'), style: TextStyle(fontSize: 10, color: theme.hintColor)),
                          ),
                      ]),
                    ),
                    for (var d = 1; d <= 7; d++) Expanded(child: _day(d, brush, theme)),
                  ]),
                ]),
        );
      },
    );
  }

  Widget _day(int day, String brush, ThemeData theme) {
    final p = _painting;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.5),
      child: Column(children: [
        SizedBox(
            height: 22,
            child: Text(_dayNames[day - 1].substring(0, 3), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
        GestureDetector(
          onVerticalDragStart: (d) {
            final m = _minutesAt(d.localPosition.dy);
            setState(() => _painting = (day, m, m));
          },
          onVerticalDragUpdate: (d) {
            final p = _painting;
            if (p == null) return;
            setState(() => _painting = (day, p.$2, _minutesAt(d.localPosition.dy)));
          },
          onVerticalDragEnd: (_) {
            final p = _painting;
            setState(() => _painting = null);
            if (p == null) return;
            final a = p.$2 < p.$3 ? p.$2 : p.$3, b = p.$2 < p.$3 ? p.$3 : p.$2;
            if (b - a < _step) return;
            store.setModeSchedule(paintSchedule(data.modeSchedule, day, a, b, brush));
          },
          child: Container(
            height: _h,
            decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
            child: Stack(children: [
              for (var h = 3; h < 24; h += 3)
                Positioned(
                    top: h / 24 * _h, left: 0, right: 0, child: Container(height: 1, color: theme.dividerColor.withValues(alpha: 0.3))),
              for (final s in data.modeSchedule.where((s) => s.day == day))
                Positioned(
                  top: s.start / (24 * 60) * _h,
                  height: (s.end - s.start) / (24 * 60) * _h,
                  left: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => _editSlot(s),
                    child: Container(
                      decoration: BoxDecoration(color: _colour(s.mode), borderRadius: BorderRadius.circular(6)),
                      alignment: Alignment.center,
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: Text(data.mode(s.mode)?.name ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ),
              if (p != null && p.$1 == day)
                Positioned(
                  top: (p.$2 < p.$3 ? p.$2 : p.$3) / (24 * 60) * _h,
                  height: ((p.$3 - p.$2).abs()) / (24 * 60) * _h,
                  left: 2,
                  right: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: brush == everythingId ? Colors.white70 : _colour(brush).withValues(alpha: 0.6),
                      border: Border.all(color: Colors.black54, width: 1.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../modes.dart';
import '../store.dart';
import '../focus_timer.dart';
import '../screens/focus_page.dart';
import '../screens/modes_page.dart';

/// Item 102: the icon for a mode's icon name.
IconData modeIcon(String name) => switch (name) {
      'work' => Icons.work_outline,
      'home' => Icons.home_outlined,
      'travel' => Icons.flight_takeoff,
      'laptop' => Icons.laptop_mac,
      'weekend' => Icons.weekend_outlined,
      'fitness' => Icons.fitness_center,
      'school' => Icons.school_outlined,
      'all' => Icons.all_inclusive,
      _ => Icons.star_outline,
    };

/// Open tasks that show in [m] (shown or quiet categories, or breaking through); all of them for
/// Everything.
int tasksInMode(AppData data, FocusMode? m, DateTime now) {
  final probe = ModeNow()..mode = m;
  return data.active.where((t) => !t.habit && probe.shows(data, t, now)).length;
}

/// "Work, Admin · Kanban, Day plan" for the switch sheet.
String describeMode(AppData data, FocusMode m) {
  final cats = [
    for (final c in data.categories)
      if (m.showFor(data, c.id) == CatShow.show) c.name,
  ];
  final tools = [
    for (final t in ModeTool.values)
      if (m.toolOn(t)) t.label,
  ];
  final catText = cats.isEmpty ? 'No categories shown' : cats.join(', ');
  final off = [
    for (final t in ModeTool.values)
      if (!m.toolOn(t)) t.label,
  ];
  final toolText = off.isEmpty
      ? 'all tools'
      : tools.isEmpty
          ? 'just the list'
          : off.length <= tools.length
              ? 'no ${off.join(', ')}'
              : tools.join(', ');
  return '$catText · $toolText';
}

/// The title of the main list: "Tasks ▾" in Everything, or the mode's coloured chip. Tapping it
/// opens the switch sheet; pressing and holding goes straight back to Everything.
class ModeTitle extends StatelessWidget {
  const ModeTitle({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final chip = _chip(context);
    // Item 102, part 4: the focus timer's countdown beside it while it runs.
    if (focusNow == null) return chip;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: chip),
      const SizedBox(width: 6),
      FocusCountdown(store: store),
    ]);
  }

  Widget _chip(BuildContext context) {
    final m = modeNow.mode;
    final until = modeNow.until;
    final now = DateTime.now();
    String? untilText;
    if (m != null && until != null) {
      final sameDay = until.year == now.year && until.month == now.month && until.day == now.day;
      untilText = sameDay
          ? 'to ${DateFormat('HH:mm').format(until)}'
          : until.difference(now).inDays < 6
              ? 'till ${DateFormat('EEE').format(until)}'
              : null;
    }
    void open() => showModeSheet(context, store);
    void longPress() {
      if (m == null) return;
      store.chooseMode(everythingId, until: modeNow.until);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('Everything until ${modeNow.until == null ? 'you change it' : DateFormat('EEE HH:mm').format(modeNow.until!)}'),
          action: SnackBarAction(label: 'Undo', onPressed: () => store.chooseMode(null)),
        ));
    }

    if (m == null) {
      return InkWell(
        onTap: open,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(modeNow.peek ? 'Tasks (peek)' : 'Tasks', overflow: TextOverflow.ellipsis, softWrap: false)),
            const Icon(Icons.arrow_drop_down),
          ]),
        ),
      );
    }
    final colour = Color(m.colour);
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: modeNow.peek ? colour.withValues(alpha: 0.45) : colour,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: open,
          onLongPress: longPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(modeIcon(m.icon), size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Flexible(
                child: Text(modeNow.peek ? '${m.name} (peek)' : m.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              if (untilText != null)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(untilText,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: const TextStyle(color: Color(0xDDFFFFFF), fontSize: 12.5)),
                  ),
                ),
              const Icon(Icons.arrow_drop_down, color: Colors.white),
            ]),
          ),
        ),
      ),
    );
  }
}

enum _Until {
  schedule('The schedule changes'),
  hour('1 hour'),
  today('End of today'),
  date('A date…'),
  forever('I change it');

  const _Until(this.label);
  final String label;
}

/// The sheet the mode chip opens: pick a mode and how long for.
Future<void> showModeSheet(BuildContext context, AppStore store) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ModeSheet(store: store),
    );

class _ModeSheet extends StatefulWidget {
  const _ModeSheet({required this.store});

  final AppStore store;

  @override
  State<_ModeSheet> createState() => _ModeSheetState();
}

class _ModeSheetState extends State<_ModeSheet> {
  _Until _until = _Until.schedule;
  late bool _everywhere = widget.store.data.modeChoice?.mode.isNotEmpty ?? false;

  AppStore get store => widget.store;
  AppData get data => store.data;

  Future<void> _pick(String id) async {
    final now = DateTime.now();
    DateTime? until;
    switch (_until) {
      case _Until.schedule:
        until = nextScheduleChange(data.modeSchedule, now);
        // Picking what the schedule already says just goes back to the schedule.
        // (Or what a place or calendar event says.)
        if (store.automaticMode == id) {
          store.chooseMode(null, everywhere: _everywhere);
          if (mounted) Navigator.pop(context);
          return;
        }
      case _Until.hour:
        until = now.add(const Duration(hours: 1));
      case _Until.today:
        until = DateTime(now.year, now.month, now.day + 1);
      case _Until.date:
        final d = await showDatePicker(
            context: context, firstDate: now, lastDate: now.add(const Duration(days: 365)), helpText: 'Until the end of');
        if (d == null) return;
        until = DateTime(d.year, d.month, d.day + 1);
      case _Until.forever:
        until = null;
    }
    store.chooseMode(id, until: until, everywhere: _everywhere);
    if (mounted) Navigator.pop(context);
  }

  String _scheduleLine(DateTime now) {
    String name(String id) => data.mode(id)?.name ?? 'Everything';
    if (!modeNow.byHand && modeNow.reason != null) {
      final until = modeNow.until;
      return '${modeNow.reason}: ${name(store.automaticMode)}'
          '${until == null ? '' : ' until ${DateFormat(until.day == now.day ? 'HH:mm' : 'EEE HH:mm').format(until)}'}.';
    }
    if (data.modeSchedule.isEmpty) return 'No schedule yet: modes change only when you pick one.';
    final nowId = scheduledAt(data.modeSchedule, now);
    final next = nextScheduleChange(data.modeSchedule, now);
    if (next == null) return 'Your schedule says ${name(nowId)}.';
    final when = next.day == now.day ? DateFormat('HH:mm').format(next) : DateFormat('EEE HH:mm').format(next);
    return 'Your schedule says ${name(nowId)} until $when, then ${name(scheduledAt(data.modeSchedule, next))}.';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final current = modeNow.mode?.id ?? everythingId;
    final theme = Theme.of(context);
    Widget row(String id, String name, String sub, IconData icon, Color colour) {
      final on = id == current;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: on ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _pick(id),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                CircleAvatar(radius: 17, backgroundColor: colour, child: Icon(icon, size: 18, color: Colors.white)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(sub, style: TextStyle(fontSize: 12, color: theme.hintColor), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                if (on)
                  Flexible(
                    flex: 0,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                          modeNow.byHand
                              ? 'Now, by hand'
                              : modeNow.reason != null
                                  ? 'Now: ${modeNow.reason}'
                                  : 'Now',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: TextStyle(color: theme.colorScheme.primary)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(18, 0, 18, 16), children: [
          Text('Mode', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(_scheduleLine(now), style: TextStyle(color: theme.hintColor)),
          if (data.modes.isEmpty) ...[
            const SizedBox(height: 12),
            const Text('Modes show only what matters right now: Work, Weekend, Travel. Hidden categories rest '
                'out of sight, but anything overdue, due today or starred still gets through.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Set up Work, Home office, Weekend and Travel'),
              onPressed: () {
                store.addStarterModes();
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ModesPage(store: store)));
              },
            ),
          ] else ...[
            const SizedBox(height: 14),
            Text('Keep it until', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final u in _Until.values)
                if (u != _Until.schedule || data.modeSchedule.isNotEmpty)
                  ChoiceChip(
                    label: Text(u.label),
                    selected: _until == u || (_until == _Until.schedule && data.modeSchedule.isEmpty && u == _Until.forever),
                    onSelected: (_) => setState(() => _until = u),
                  ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Switch my other devices too'),
              subtitle: const Text('Through Dropbox; otherwise just this device'),
              value: _everywhere,
              onChanged: (v) => setState(() => _everywhere = v),
            ),
            const SizedBox(height: 4),
            row(everythingId, 'Everything', 'The whole app · ${tasksInMode(data, null, now)} tasks', modeIcon('all'),
                const Color(0xFF006A6A)),
            for (final m in data.modes)
              row(m.id, m.name, '${describeMode(data, m)} · ${tasksInMode(data, m, now)} tasks', modeIcon(m.icon),
                  Color(m.colour)),
            if (modeNow.byHand && (data.modeSchedule.isNotEmpty || store.automaticMode != everythingId))
              TextButton.icon(
                icon: const Icon(Icons.schedule),
                label: const Text('Back to the schedule'),
                onPressed: () {
                  store.chooseMode(null, everywhere: _everywhere);
                  Navigator.pop(context);
                },
              ),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.tune),
              label: const Text('Edit modes and schedule'),
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ModesPage(store: store)));
              },
            ),
          ),
        ]),
      ),
    );
  }
}

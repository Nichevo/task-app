import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../day_plan.dart';
import '../models.dart';
import '../native.dart';
import 'focus_page.dart';
import '../store.dart';
import '../widgets/day_plan_add.dart';
import '../widgets/mode_chip.dart' show modeIcon, showModeSheet;
import '../widgets/plan_time_sheet.dart';
import '../widgets/task_colors.dart';
import '../widgets/task_where.dart' show editDrive;
import 'starred_page.dart' show pickTask;
import 'task_page.dart';

/// Item 101: the Day plan. One day as a timeline: tasks and steps with a planned time drawn as
/// blocks as tall as the time they take, the gaps kept after them, free time in working hours,
/// clashes side by side, and blocks that leave room as a band down the left with smaller things
/// on top. A week strip changes day; the "To plan" tray holds what hasn't got a time yet.
///
/// Also the Calendar page's Day mode: [onMode] then switches back to 'month' or 'week'.
class DayPlanPage extends StatefulWidget {
  const DayPlanPage({super.key, required this.store, this.initialDay, this.onMode, this.events, this.embedded = false});

  final AppStore store;
  final DateTime? initialDay;
  final ValueChanged<String>? onMode;

  /// Calendar events to show instead of reading the phone's (for tests and previews).
  final List<CalendarEvent>? events;

  /// In the Fold's side panel (1.11.2): a slimmer bar, a button to open it full size, and the
  /// tray along the bottom.
  final bool embedded;

  @override
  State<DayPlanPage> createState() => _DayPlanPageState();
}

class _DayPlanPageState extends State<DayPlanPage> {
  late DateTime _day = dayStart(widget.initialDay ?? DateTime.now());
  final _scroll = ScrollController();
  final _timelineKeys = [GlobalKey(), GlobalKey()];
  bool _trayOpen = false;

  /// The tray's category chip ('' = no category, null = all).
  String? _trayCat;

  /// Tasks in the tray opened to show their steps.
  final Set<String> _traySteps = {};

  /// The tray as shown: each opened task followed by its steps, and the "Other open tasks" heading
  /// (null) before the first of those.
  List<TrayItem?> _trayRows(List<TrayItem> tray) {
    final out = <TrayItem?>[];
    var other = false;
    for (final i in tray) {
      if (i.other && !other) {
        other = true;
        out.add(null);
      }
      out.add(i);
      if (i.step == null && _traySteps.contains(i.task.id)) out.addAll(trayStepsOf(data, i, _day, shown: tray));
    }
    return out;
  }

  Widget _trayHeading(BuildContext context, {bool card = false}) {
    final theme = Theme.of(context);
    final text = Text(card ? 'Other open tasks' : 'Also open:', style: TextStyle(fontSize: 12, color: theme.hintColor, fontWeight: FontWeight.w600));
    return card
        ? Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 6), child: text)
        : Container(
            margin: const EdgeInsets.only(right: 6, bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
            child: text,
          );
  }

  List<Widget> _trayWidgets(BuildContext context, List<TrayItem> tray, {bool card = false}) => [
        for (final i in _trayRows(tray)) i == null ? _trayHeading(context, card: card) : _trayChip(context, i, card: card),
      ];

  /// How many open steps [i] can open to (0 for a step, or a task planned in full).
  int _stepCount(TrayItem i) => i.step != null ? 0 : trayStepsOf(data, i, _day).length;

  /// The tray narrowed to [_trayCat], and chips for the categories it holds.
  List<TrayItem> _trayShown(List<TrayItem> tray) =>
      _trayCat == null ? tray : tray.where((i) => (data.category(i.task.categoryId)?.id ?? '') == _trayCat).toList();

  Widget _trayCats(List<TrayItem> tray, {EdgeInsets padding = const EdgeInsets.fromLTRB(14, 0, 14, 6)}) {
    final ids = <String>{for (final i in tray) data.category(i.task.categoryId)?.id ?? ''};
    if (ids.length < 2) return const SizedBox();
    String name(String id) => id.isEmpty ? 'No category' : data.category(id)!.name;
    return SizedBox(
      height: 38,
      child: ListView(scrollDirection: Axis.horizontal, padding: padding, children: [
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            visualDensity: VisualDensity.compact,
            label: const Text('All'),
            selected: _trayCat == null,
            onSelected: (_) => setState(() => _trayCat = null),
          ),
        ),
        for (final id in [for (final c in data.categories) if (ids.contains(c.id)) c.id, if (ids.contains('')) ''])
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              visualDensity: VisualDensity.compact,
              label: Text('${name(id)} ${tray.where((i) => (data.category(i.task.categoryId)?.id ?? '') == id).length}'),
              selected: _trayCat == id,
              onSelected: (_) => setState(() => _trayCat = _trayCat == id ? null : id),
            ),
          ),
      ]),
    );
  }

  // A block being moved (press and hold) or stretched (bottom edge), and by how far.
  PlanBlock? _moving;
  PlanBlock? _resizing;
  double _dy = 0;
  // The snap steps the drag has come to, for a tick each time it passes another (1.12.6).
  int _dragStep = 0;
  // "Moving · 09:30 – 10:15" or "Length 1 h · ends 10:30" by the block being dragged, drawn on
  // top of the day it is on.
  Widget? _dragLabel;

  // The phone's calendar events for the week shown (1.11.1), and whether reading them failed
  // (no access yet).
  late List<CalendarEvent> _events = widget.events ?? const [];
  DateTime? _eventsWeek;
  bool _eventsBlocked = false;

  // Where each block was drawn this frame, for the "comes after" lines.
  final _rects = <PlanBlock, Rect>{};

  AppStore get store => widget.store;
  AppData get data => store.data;
  DayPlanSettings get s => data.dayPlan;

  static const _top = 12.0;
  static const _gutter = 52.0;
  static const _bandBar = 58.0;
  static const _frameBar = 34.0;

  static DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    // 1.12.8: opening the Day plan in a focus mode starts from the mode's own categories.
    modeChipTweaks.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToStart());
    _loadEvents();
  }

  DateTime _monday(DateTime d) => dayStart(d).subtract(Duration(days: d.weekday - 1));

  /// Reads the week's events from the phone's calendars, once per week shown.
  Future<void> _loadEvents({bool force = false}) async {
    if (!s.showEvents || !Native.supported || widget.events != null) return;
    final monday = _monday(_day);
    if (!force && _eventsWeek == monday) return;
    _eventsWeek = monday;
    try {
      // A day over, for the second of two days side by side on a Sunday.
      final list = await Native.events(monday, monday.add(const Duration(days: 8)), data.eventCalendars);
      if (!mounted) return;
      setState(() {
        _events = list;
        _eventsBlocked = false;
      });
    } catch (e) {
      debugPrint('Day plan events: $e');
      if (mounted) setState(() => _eventsBlocked = true);
    }
  }

  Future<void> _allowCalendar() async {
    if (await Native.requestCalendarAccess()) await _loadEvents(force: true);
  }

  void _toggleEvents() {
    s.showEvents = !s.showEvents;
    store.dayPlanChanged();
    if (s.showEvents) _loadEvents(force: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double _ppm(BuildContext context) => MediaQuery.of(context).size.width >= 700 ? 1.3 : 1.5;

  /// The hours drawn: Settings' day, stretched to fit anything planned outside it.
  (int, int) _range(DayLayout l) {
    var a = s.dayStart, b = s.dayEnd;
    for (final x in l.all) {
      final st = x.start.hour * 60 + x.start.minute;
      final en = st + x.slot.minutes;
      a = min(a, st ~/ 60 * 60);
      b = max(b, min(24 * 60, (en + 59) ~/ 60 * 60));
    }
    for (final e in l.events) {
      final st = e.start.hour * 60 + e.start.minute;
      a = min(a, st ~/ 60 * 60);
      b = max(b, min(24 * 60, (st + e.minutes + 59) ~/ 60 * 60));
    }
    return (a, max(b, a + 60));
  }

  void _scrollToStart() {
    if (!_scroll.hasClients || !mounted) return;
    final l = layoutDay(data, _day, events: _events);
    final (from, _) = _range(l);
    final now = DateTime.now();
    final target = DateUtils.isSameDay(now, _day)
        ? now.hour * 60 + now.minute - 45
        : l.blocks.isNotEmpty
            ? l.blocks.first.start.hour * 60 + l.blocks.first.start.minute - 20
            : s.workStart - 20;
    _scroll.jumpTo(((target - from) * _ppm(context)).clamp(0.0, _scroll.position.maxScrollExtent));
  }

  /// The week [by] weeks from the one shown opens on its first day (Monday), or on today when
  /// today falls in it.
  DateTime _weekStart(int by) => weekStartFrom(_day, by, today: DateTime.now());

  void _goTo(DateTime d) {
    setState(() => _day = dayStart(d));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToStart());
    _loadEvents();
  }

  Color _colour(Task t) => ageColor(t, data.hoursToRed, byDue: data.colourByDue);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => LayoutBuilder(builder: (context, box) {
        final embedded = widget.embedded;
        // Two days side by side need room for both and, beside them, the tray.
        final canTwo = !embedded && box.maxWidth >= 900;
        final two = canTwo && store.dayPlanTwoDays;
        final wide = !embedded && box.maxWidth >= (two ? 1180 : 840);
        final layout = layoutDay(data, _day, events: _events);
        final next = _day.add(const Duration(days: 1));
        final layouts = [layout, if (two) layoutDay(data, next, events: _events)];
        final tray = trayFor(data, _day);
        final fmt = DateFormat(embedded ? 'EEE d MMM' : (wide ? 'EEEE d MMMM' : 'EEE d MMM'));
        return Scaffold(
          appBar: AppBar(
            primary: !embedded,
            automaticallyImplyLeading: !embedded,
            toolbarHeight: embedded ? 48 : null,
            titleTextStyle: embedded ? Theme.of(context).textTheme.titleMedium : null,
            title: Text(two
                ? 'Day plan · ${fmt.format(_day)} and ${DateFormat('EEE d').format(next)}'
                : embedded
                    ? fmt.format(_day)
                    : 'Day plan · ${fmt.format(_day)}'),
            actions: [
              IconButton(tooltip: 'Today', icon: const Icon(Icons.today), onPressed: () => _goTo(DateTime.now())),
              IconButton(tooltip: 'Plan a task', icon: const Icon(Icons.add), onPressed: _planAny),
              if (canTwo)
                IconButton(
                  tooltip: two ? 'One day' : 'Two days side by side',
                  isSelected: two,
                  icon: const Icon(Icons.view_column_outlined),
                  selectedIcon: const Icon(Icons.view_column),
                  onPressed: () {
                    store.setDayPlanTwoDays(!two);
                    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToStart());
                  },
                ),
              if (widget.onMode != null) ...[
                IconButton(
                  tooltip: 'Week view',
                  icon: const Icon(Icons.calendar_view_week),
                  onPressed: () => widget.onMode!('week'),
                ),
                IconButton(
                  tooltip: 'Month view',
                  icon: const Icon(Icons.calendar_view_month),
                  onPressed: () => widget.onMode!('month'),
                ),
              ],
              PopupMenuButton<Object>(
                tooltip: 'Show',
                icon: const Icon(Icons.filter_list),
                onSelected: (v) {
                  if (v == 'events') return _toggleEvents();
                  if (v == 'ticked') {
                    s.showTicked = !s.showTicked;
                    return store.dayPlanChanged();
                  }
                  s.show = v as DayShow;
                  store.dayPlanChanged();
                },
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(value: 'events', checked: s.showEvents, child: const Text('Calendar events')),
                  CheckedPopupMenuItem(value: 'ticked', checked: s.showTicked, child: const Text('Show ticked')),
                  const PopupMenuDivider(),
                  for (final v in DayShow.values)
                    CheckedPopupMenuItem(
                      value: v,
                      checked: s.show == v,
                      child: Text(switch (v) {
                        DayShow.both => 'Tasks and steps',
                        DayShow.tasks => 'Tasks only',
                        DayShow.steps => 'Steps only',
                      }),
                    ),
                ],
              ),
              if (embedded)
                IconButton(
                  tooltip: 'Open the Day plan',
                  icon: const Icon(Icons.open_in_full),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => DayPlanPage(store: store, initialDay: _day, events: widget.events))),
                ),
            ],
          ),
          body: Column(children: [
            _weekStrip(context),
            _summary(context, layout),
            _categoryChips(context),
            _allDayRow(context, layout),
            Expanded(
              child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(width: 300, child: _trayPanel(context, tray)),
                      const VerticalDivider(width: 1),
                      Expanded(child: _timeline(context, layouts)),
                    ])
                  : _timeline(context, layouts),
            ),
            if (!wide) _trayBar(context, tray),
          ]),
        );
      }),
    );
  }

  // --- Week strip and summary ---

  Widget _weekStrip(BuildContext context) {
    final theme = Theme.of(context);
    final monday = _day.subtract(Duration(days: _day.weekday - 1));
    final today = dayStart(DateTime.now());
    final workHours = (s.workEnd - s.workStart) / 60;
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() > 200) _goTo(_weekStart(v < 0 ? 1 : -1));
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
        child: Row(children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Week before',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _goTo(_weekStart(-1)),
          ),
          for (var i = 0; i < 7; i++)
            Expanded(child: Builder(builder: (context) {
              final d = monday.add(Duration(days: i));
              final selected = d == _day;
              final load = dayLoad(data, d, events: _events);
              final fg = selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
              final over = load > 1;
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _goTo(d),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: selected ? theme.colorScheme.primary : null,
                    border: d == today && !selected ? Border.all(color: theme.colorScheme.primary) : null,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(children: [
                    Text(DateFormat('EEE').format(d), style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.75))),
                    Text('${d.day}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: fg)),
                    const SizedBox(height: 3),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: load.clamp(0, 1).toDouble(),
                          minHeight: 4,
                          backgroundColor: fg.withValues(alpha: 0.15),
                          color: over ? const Color(0xFFD32F2F) : (selected ? theme.colorScheme.onPrimary : theme.colorScheme.primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(load == 0 ? '–' : '${(load * workHours * 2).round() / 2} h'.replaceAll('.0 h', ' h'),
                        style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.75))),
                  ]),
                ),
              );
            })),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Week after',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _goTo(_weekStart(1)),
          ),
        ]),
      ),
    );
  }

  Widget _summary(BuildContext context, DayLayout l) {
    final theme = Theme.of(context);
    Widget chip(String t, {bool strong = false, bool bad = false}) => Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: strong ? theme.colorScheme.secondaryContainer : null,
            border: Border.all(color: bad ? theme.colorScheme.error : theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(t, style: TextStyle(fontSize: 12.5, color: bad ? theme.colorScheme.error : null)),
        );
    return SizedBox(
      height: 32,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
        chip('Planned ${describeLength(l.plannedMinutes)}', strong: true),
        chip('Free ${describeLength(l.freeMinutes)}'),
        if (l.sharedMinutes > 0) chip('Shared time ${describeLength(l.sharedMinutes)}'),
        if (l.clashes > 0) chip('${l.clashes} clashing', bad: true),
        if (l.tooEarly > 0) chip('${l.tooEarly} too early', bad: true),
        if (l.events.isNotEmpty) chip('Events ${describeLength(l.eventMinutes)}'),
        if (l.hiddenMinutes > 0) chip('Hidden ${describeLength(l.hiddenMinutes)}'),
      ]),
    );
  }

  /// Item 101: categories to show, more than one at a time; remembered. 1.12.8: while a focus
  /// mode is on, only the categories it shows start selected (a chip at the front names the mode
  /// and puts its categories back after a change); changes then last until the Day plan is next
  /// opened.
  Widget _categoryChips(BuildContext context) {
    if (data.categories.isEmpty) return const SizedBox(height: 6);
    final hidden = dayPlanHidden(data);
    final mode = dayPlanMode;
    void toggle(String id) {
      toggleDayPlanCategory(data, id);
      mode == null ? store.dayPlanChanged() : setState(() {});
    }

    final changed = modeChipsChanged(data);
    return SizedBox(
      height: 44,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 4, 12, 4), children: [
        if (mode != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Tooltip(
              message: changed ? 'Show only the categories ${mode.name} shows' : 'Showing the categories ${mode.name} shows. Tap to change mode',
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(changed ? Icons.restart_alt : modeIcon(mode.icon), size: 18, color: Color(mode.colour)),
                label: Text(changed ? mode.name : '${mode.name} mode'),
                side: BorderSide(color: Color(mode.colour)),
                onPressed: changed ? () => setState(() => modeChipTweaks.remove(mode.id)) : () => showModeSheet(context, store),
              ),
            ),
          ),
        for (final c in data.categories)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              visualDensity: VisualDensity.compact,
              label: Text(c.name),
              selected: !hidden.contains(c.id),
              onSelected: (_) => toggle(c.id),
            ),
          ),
        FilterChip(
          visualDensity: VisualDensity.compact,
          label: const Text('No category'),
          selected: !hidden.contains(''),
          onSelected: (_) => toggle(''),
        ),
      ]),
    );
  }

  /// The day's all-day events, and a way to let the app read the calendar.
  Widget _allDayRow(BuildContext context, DayLayout l) {
    if (!s.showEvents) return const SizedBox();
    final theme = Theme.of(context);
    if (_eventsBlocked) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: Row(children: [
          Expanded(
            child: Text('Your calendar events can show here too.', style: TextStyle(fontSize: 12.5, color: theme.hintColor)),
          ),
          TextButton(onPressed: _allowCalendar, child: const Text('Allow calendar')),
          TextButton(onPressed: _toggleEvents, child: const Text('Not now')),
        ]),
      );
    }
    if (l.allDay.isEmpty) return const SizedBox();
    return SizedBox(
      height: 36,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 2, 12, 4), children: [
        for (final e in l.allDay)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.event, size: 16),
              label: Text(e.title),
              onPressed: () => _eventInfo(e),
            ),
          ),
      ]),
    );
  }

  /// A calendar event on the timeline: grey and striped, read-only.
  Widget _eventBlock(BuildContext context, EventBlock e, double hh) {
    final theme = Theme.of(context);
    final hm = DateFormat('HH:mm');
    final fg = theme.colorScheme.onSurfaceVariant;
    return GestureDetector(
      onTap: () => _eventInfo(e.event),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: fg.withValues(alpha: 0.6), width: 4)),
        ),
        foregroundDecoration: e.clash
            ? BoxDecoration(border: Border.all(color: const Color(0xFFD32F2F), width: 2.5), borderRadius: BorderRadius.circular(10))
            : null,
        padding: EdgeInsets.fromLTRB(8, hh < 40 ? 0 : 5, 6, 0),
        alignment: hh < 40 ? Alignment.centerLeft : Alignment.topLeft,
        child: CustomPaint(
          painter: _Hatch(fg.withValues(alpha: 0.06)),
          child: Row(crossAxisAlignment: hh < 40 ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
            Icon(Icons.event, size: 15, color: fg),
            const SizedBox(width: 5),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: e.event.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(
                    text: '${hh < 40 ? '  ' : '\n'}${hm.format(e.start)} – ${hm.format(e.end)}'
                        '${e.event.location?.isNotEmpty == true ? ' · ${e.event.location}' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ]),
                maxLines: hh < 40 ? 1 : max(1, (hh - 8) ~/ 17),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: fg),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _eventInfo(CalendarEvent e) async {
    final hm = DateFormat('HH:mm');
    final fmt = DateFormat('EEE d MMM');
    final hide = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.event),
            title: Text(e.title),
            subtitle: Text([
              e.allDay ? 'All day, ${fmt.format(e.start)}' : '${fmt.format(e.start)}, ${hm.format(e.start)} – ${hm.format(e.end)}',
              if (e.location?.isNotEmpty == true) e.location!,
              'From your calendar; change it there',
            ].join('\n')),
            isThreeLine: true,
          ),
          ListTile(
            leading: const Icon(Icons.visibility_off_outlined),
            title: const Text('Hide calendar events'),
            subtitle: const Text('Turn them back on from the filter menu or Settings'),
            onTap: () => Navigator.pop(c, true),
          ),
        ]),
      ),
    );
    if (hide == true && mounted) _toggleEvents();
  }

  // --- The timeline ---

  /// The day's timeline, or (two days side by side) both days' in one scrolling view, with
  /// the same hours drawn so they line up.
  Widget _timeline(BuildContext context, List<DayLayout> ls) {
    final theme = Theme.of(context);
    final ppm = _ppm(context);
    var (from, to) = _range(ls.first);
    for (final l in ls.skip(1)) {
      final (a, b) = _range(l);
      from = min(from, a);
      to = max(to, b);
    }
    final height = (to - from) * ppm + _top * 2;
    _rects.clear();
    final today = dayStart(DateTime.now());
    final scroll = SingleChildScrollView(
      controller: _scroll,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < ls.length; i++) ...[
          if (i > 0) Container(width: 1, height: height, color: theme.dividerColor),
          Expanded(child: _dayColumn(context, ls[i], from, to, height, _timelineKeys[i])),
        ],
      ]),
    );
    if (ls.length == 1) return scroll;
    return Column(children: [
      Row(children: [
        for (final l in ls)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(_gutter, 2, 10, 4),
              child: Text(
                '${DateFormat('EEEE d MMM').format(l.day)}${l.day == today ? ' · Today' : ''}'
                ' · ${describeLength(l.plannedMinutes)} planned',
                style: theme.textTheme.titleSmall?.copyWith(color: l.day == today ? theme.colorScheme.primary : null),
              ),
            ),
          ),
      ]),
      const Divider(height: 1),
      Expanded(child: scroll),
    ]);
  }

  /// One day's column: hour lines, free time, gaps, events, blocks, links and the now line.
  /// Drops from the tray land on this column's day.
  Widget _dayColumn(BuildContext context, DayLayout l, int from, int to, double height, GlobalKey key) {
    final theme = Theme.of(context);
    final ppm = _ppm(context);
    final day = l.day;
    double y(DateTime t) => (t.hour * 60 + t.minute - from + (DateUtils.isSameDay(t, day) ? 0 : 24 * 60)) * ppm + _top;
    double h(int minutes) => minutes * ppm;
    final now = DateTime.now();
    return DragTarget<TrayItem>(
      onAcceptWithDetails: (d) {
        final box = key.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(d.offset);
        final minutes = (local.dy - _top) / ppm + from;
        final start = snapTime(day.add(Duration(minutes: minutes.round().clamp(0, 24 * 60 - s.snap))), s.snap);
        _planDropped(d.data, start);
      },
      builder: (context, candidates, _) => Container(
        color: candidates.isNotEmpty ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25) : null,
        child: LayoutBuilder(builder: (context, box) {
            final x0 = _gutter, x1 = box.maxWidth - 10;
            final children = <Widget>[];
            _dragLabel = null;
            // Hour lines.
            for (var m = (from + 59) ~/ 60 * 60; m <= to; m += 60) {
              final top = (m - from) * ppm + _top;
              children.add(Positioned(
                left: 0,
                right: 0,
                top: top,
                child: Container(height: 1, color: theme.dividerColor.withValues(alpha: 0.35)),
              ));
              children.add(Positioned(
                left: 8,
                top: top - 8,
                child: Text('${(m ~/ 60).toString().padLeft(2, '0')}:00',
                    style: TextStyle(fontSize: 11, color: theme.hintColor)),
              ));
            }
            // Working hours shading at the edges.
            final ws = (s.workStart - from) * ppm + _top, we = (s.workEnd - from) * ppm + _top;
            if (ws > _top) {
              children.add(Positioned(left: x0, right: 10, top: 0, height: ws, child: ColoredBox(color: theme.hintColor.withValues(alpha: 0.05))));
            }
            if (we < height) {
              children.add(Positioned(left: x0, right: 10, top: we, bottom: 0, child: ColoredBox(color: theme.hintColor.withValues(alpha: 0.05))));
            }
            // Free time.
            for (final f in l.free) {
              final hh = h(f.minutes);
              final inBand = l.blocks.any((b) => b.shared && !b.hidden && b.start.isBefore(f.end) && f.start.isBefore(b.end));
              children.add(Positioned(
                left: inBand ? x0 + _bandBar + 6 : x0,
                width: x1 - x0 - (inBand ? _bandBar + 6 : 0),
                top: y(f.start) + 1,
                height: max(hh - 2, 4),
                child: CustomPaint(
                  painter: _DashedBox(theme.hintColor.withValues(alpha: 0.5)),
                  child: hh < 18
                      ? null
                      : Center(
                          child: Text(
                            f.minutes >= 30 ? 'Free ${describeLength(f.minutes)}' : describeLength(f.minutes),
                            style: TextStyle(fontSize: 12, color: theme.hintColor),
                          ),
                        ),
                ),
              ));
            }
            // Gaps after blocks.
            for (final g in l.gaps) {
              children.add(Positioned(
                left: x0,
                width: x1 - x0,
                top: y(g.start) + 1,
                height: max(h(g.minutes) - 2, 3),
                child: CustomPaint(painter: _Hatch(theme.hintColor.withValues(alpha: 0.22))),
              ));
            }
            // 1.12.5: driving there and back.
            for (final d in l.drives) {
              final hh = max(h(d.minutes) - 2, 14.0);
              children.add(Positioned(
                left: x0,
                width: x1 - x0,
                top: y(d.start) + 1,
                height: hh,
                child: _driveBlock(context, d, hh),
              ));
            }
            // Bands first, so what sits on them is drawn on top.
            for (final b in l.blocks.where((b) => b.shared && !b.hidden)) {
              children.add(_positioned(b, x0, x1, y, h, (w, hh) => _band(context, b, hh)));
            }
            // The phone's calendar events, side by side with what they clash with.
            for (final e in l.events) {
              final left = e.inBand ? x0 + _bandBar + 6 : x0;
              final colW = (x1 - left) / e.columns;
              final hh = max(h(e.minutes) - 2, 14.0);
              children.add(Positioned(
                left: left + colW * e.column,
                top: y(e.start) + 1,
                width: max(colW - (e.column + 1 < e.columns ? 4 : 0), 20.0),
                height: hh,
                child: _eventBlock(context, e, hh),
              ));
            }
            for (final b in l.blocks.where((b) => !b.shared || b.hidden)) {
              if (b.hidden) {
                children.add(_positioned(b, x0, x1, y, h, (w, hh) => _hiddenStrip(context, b, hh)));
                continue;
              }
              final left = b.inBand ? x0 + _bandBar + 6 : x0;
              final colW = (x1 - left) / b.columns;
              children.add(_positioned(b, left + colW * b.column, left + colW * (b.column + 1) - (b.column + 1 < b.columns ? 4 : 0), y, h,
                  (w, hh) => b.inside.isEmpty ? _block(context, b, hh) : _frame(context, b, hh)));
              for (final st in b.inside) {
                children.add(_positioned(st, left + colW * b.column + _frameBar + 4, left + colW * (b.column + 1) - 6, y, h,
                    (w, hh) => _block(context, st, hh)));
              }
            }
            // "Comes after" lines between blocks.
            if (l.links.isNotEmpty) {
              children.add(Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _LinkPainter(
                      [
                        for (final k in l.links)
                          if (_rects[k.from] case final a?)
                            if (_rects[k.to] case final b?) (a, b, k.tooEarly),
                      ],
                      theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ));
            }
            if (DateUtils.isSameDay(now, day)) {
              final ny = y(now);
              children.add(Positioned(
                left: x0 - 6,
                right: 0,
                top: ny - 5,
                height: 10,
                child: IgnorePointer(
                  child: Row(children: [
                    Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFD32F2F), shape: BoxShape.circle)),
                    Expanded(child: Container(height: 2, color: const Color(0xFFD32F2F))),
                  ]),
                ),
              ));
            }
            if (l.blocks.isEmpty && l.events.isEmpty) {
              children.add(Positioned(
                left: x0,
                right: 10,
                top: y(day.add(Duration(minutes: s.workStart))) + 40,
                child: Text(
                  'Nothing planned. Tap a time to add a task or step there, or drag one from the "To plan" tray.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.hintColor),
                ),
              ));
            }
            if (_dragLabel case final label?) children.add(label);
            // 1.12.8: a tap on an empty time adds something there (blocks and events take their
            // own taps first).
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _addAt(day, d.localPosition.dy, from),
              child: SizedBox(key: key, height: height, child: Stack(clipBehavior: Clip.none, children: children)),
            );
          }),
      ),
    );
  }

  /// Places [b] between [left] and [right], moved or stretched while it is being dragged. The
  /// block being dragged also gets a label (added on top of the day in [_dragLabel]) saying
  /// whether it is moving or stretching, and to what time (1.12.6).
  Widget _positioned(PlanBlock b, double left, double right, double Function(DateTime) y, double Function(int) h,
      Widget Function(double w, double h) child) {
    var top = y(b.start);
    var hh = h(b.slot.minutes);
    final moving = _isDragged(_moving, b) || (b.frame != null && _isDragged(_moving, b.frame!));
    final stretching = _isDragged(_resizing, b);
    if (moving) top += _dy;
    if (stretching) hh = max(h(s.snap), hh + _dy);
    final w = max(right - left, 20.0);
    final bh = max(hh - 2, 14.0);
    _rects[b] = Rect.fromLTWH(left, top + 1, w, bh);
    if (_isDragged(_moving, b) || stretching) {
      final rect = Rect.fromLTWH(left, top + 1, w, bh);
      _dragLabel = stretching ? _stretchLabel(b, rect) : _moveLabel(b, rect);
    }
    final widget = SizedBox(width: w, height: bh, child: child(w, bh));
    final lifted = moving || stretching;
    final own = _isDragged(_moving, b) || stretching;
    // The same widgets whether dragged or not, so the drag under the finger carries on when the
    // block lifts (swapping them would drop the gesture).
    return Positioned(
      left: left,
      top: top + 1,
      child: Material(
        elevation: lifted ? 6 : 0,
        borderRadius: BorderRadius.circular(12),
        color: Colors.transparent,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: !own
              ? const BoxDecoration()
              : BoxDecoration(
                  // Moving: an outline all round. Stretching: only the bottom edge, thick.
                  border: stretching
                      ? const Border(bottom: BorderSide(color: Color(0xFF1A1C1C), width: 4))
                      : Border.all(color: const Color(0xFF1A1C1C), width: 2),
                  borderRadius: stretching ? null : BorderRadius.circular(12),
                ),
          child: widget,
        ),
      ),
    );
  }

  /// Whether [b] is the block being dragged. The day is laid out afresh on every frame, so the
  /// same block is a new object each time: match it by its planned time instead (1.12.6; the
  /// block didn't follow the finger before).
  static bool _isDragged(PlanBlock? dragged, PlanBlock b) => dragged != null && identical(dragged.slot, b.slot);

  /// The minutes the current drag comes to, in whole snap steps.
  int get _dragMinutes => (_dy / _ppm(context) / s.snap).round() * s.snap;

  Widget _moveLabel(PlanBlock b, Rect r) {
    final start = b.start.add(Duration(minutes: _dragMinutes));
    final hm = DateFormat('HH:mm');
    return _label(r, above: true, icon: Icons.open_with,
        text: 'Moving · ${hm.format(start)} – ${hm.format(start.add(Duration(minutes: b.slot.minutes)))}');
  }

  Widget _stretchLabel(PlanBlock b, Rect r) {
    final to = max(s.snap, b.slot.minutes + _dragMinutes);
    return _label(r, above: false, icon: Icons.height,
        text: 'Length ${describeLength(to)} · ends ${DateFormat('HH:mm').format(b.start.add(Duration(minutes: to)))}');
  }

  Widget _label(Rect r, {required bool above, required IconData icon, required String text}) => Positioned(
        left: r.left + 8,
        top: above ? r.top - 30 : r.bottom + 6,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xEE1A1C1C), borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(text, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  /// Whether [b] (drawn [hh] tall) has a stretch handle.
  static bool canStretch(PlanBlock b, double hh) => !b.done && hh >= 22;

  void _startMove(PlanBlock b) {
    HapticFeedback.heavyImpact();
    setState(() {
      _moving = b;
      _resizing = null;
      _dy = 0;
      _dragStep = 0;
    });
  }

  void _startStretch(PlanBlock b) {
    HapticFeedback.lightImpact();
    setState(() {
      _resizing = b;
      _moving = null;
      _dy = 0;
      _dragStep = 0;
    });
  }

  /// Follows the finger, with a tick each time the time passes another snap step.
  void _dragTo(double dy) {
    final step = (dy / _ppm(context) / s.snap).round();
    if (step != _dragStep) {
      _dragStep = step;
      HapticFeedback.selectionClick();
    }
    setState(() => _dy = dy);
  }

  void _endDrag(PlanBlock b) {
    final minutes = _dragMinutes;
    final stretching = _resizing != null;
    setState(() {
      _moving = null;
      _resizing = null;
    });
    if (minutes == 0) return;
    stretching ? _stretch(b, minutes) : _shift(b, minutes);
  }

  void _cancelDrag() => setState(() {
        _moving = null;
        _resizing = null;
      });

  /// Taps, press-and-hold to move, and the handle along the bottom edge to stretch. The handle
  /// stretches whether it is dragged straight away or held first, so holding near the bottom
  /// never moves the block by mistake (1.12.6). 1.12.8: a tap opens the task to edit it; the ⋮
  /// on the block (or a right click) has the Day plan's own choices.
  Widget _gestures(PlanBlock b, double hh, Widget child) {
    final stretchable = canStretch(b, hh);
    final zone = stretchHandleHeight(hh);
    final active = _isDragged(_resizing, b);
    return GestureDetector(
      onTap: () => _openTask(b),
      onSecondaryTap: () => _blockMenu(b),
      onLongPressStart: (d) => stretchable && d.localPosition.dy >= hh - zone ? _startStretch(b) : _startMove(b),
      onLongPressMoveUpdate: (d) => _dragTo(d.offsetFromOrigin.dy),
      onLongPressEnd: (_) => _endDrag(b),
      onLongPressCancel: _cancelDrag,
      child: Stack(children: [
        Positioned.fill(child: child),
        if (stretchable)
          Positioned(
            left: 0,
            // Leave the tick box and ⋮ at the right tappable (side by side on a short block).
            right: hh < 72 ? 62 : 36,
            bottom: 0,
            height: zone,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (_) => _startStretch(b),
              onVerticalDragUpdate: (d) => _dragTo(_dy + d.delta.dy),
              onVerticalDragEnd: (_) => _endDrag(b),
              onVerticalDragCancel: _cancelDrag,
              child: _StretchHandle(active: active),
            ),
          ),
      ]),
    );
  }

  String _times(PlanBlock b) {
    final hm = DateFormat('HH:mm');
    return '${hm.format(b.start)} – ${hm.format(b.end)} · ${describeLength(b.slot.minutes)}';
  }

  Widget _tick(PlanBlock b) => SizedBox(
        width: 32,
        height: 32,
        child: Checkbox(
          value: b.done,
          side: const BorderSide(color: Colors.black54, width: 2),
          activeColor: Colors.black54,
          onChanged: (_) => _toggle(b),
        ),
      );

  /// 1.12.8: the Day plan's choices for [b] (focus, time, leave room, remove...), now that a tap
  /// opens the task.
  Widget _more(PlanBlock b, {double width = 28}) => SizedBox(
        width: width,
        height: 32,
        child: IconButton(
          padding: EdgeInsets.zero,
          tooltip: 'More',
          iconSize: 20,
          color: Colors.black54,
          icon: const Icon(Icons.more_vert),
          onPressed: () => _blockMenu(b),
        ),
      );

  Widget _block(BuildContext context, PlanBlock b, double hh) {
    final c = _colour(b.task);
    final step = b.step;
    final compact = hh < 52;
    const ink = Color(0xDD000000);
    final meta = [
      _times(b),
      if (step == null && b.task.steps.isNotEmpty && b.inside.isEmpty) '${b.task.stepsDone} of ${b.task.steps.length} steps',
      if (b.task.dueAt != null && b.task.dueAt!.isBefore(DateTime.now()) && b.task.closedAt == null) 'overdue',
    ].join(' · ');
    // A planned task shows its steps that have no time as a short checklist, room permitting.
    final unplanned = step != null || b.inside.isNotEmpty
        ? const <TaskStep>[]
        : b.task.steps.where((x) => !x.done && b.task.slotsOf(x).isEmpty).toList();
    final listRoom = ((hh - 64) / 26).floor();
    return _gestures(
      b,
      hh,
      Opacity(
        opacity: b.done ? 0.5 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: step != null ? BorderSide(color: Color.lerp(c, Colors.black, 0.35)!, width: 5) : BorderSide.none,
            ),
          ),
          foregroundDecoration: b.clash
              ? BoxDecoration(border: Border.all(color: const Color(0xFFD32F2F), width: 2.5), borderRadius: BorderRadius.circular(12))
              : null,
          padding: EdgeInsets.fromLTRB(10, compact ? 0 : 6, 2, 0),
          child: compact
              ? Row(children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: b.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        TextSpan(
                          text: '  ${DateFormat('HH:mm').format(b.start)}–${DateFormat('HH:mm').format(b.end)}'
                              '${step != null && b.frame == null ? ' · ${b.task.title}' : ''}',
                          style: const TextStyle(fontSize: 12, color: Color(0xAA000000)),
                        ),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: ink, decoration: TextDecoration.none),
                    ),
                  ),
                  if (b.tooEarly) const _Tag('Too early', bad: true) else if (b.clash) const _Tag('Clash'),
                  _more(b, width: 26),
                  _tick(b),
                ])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (step != null && b.frame == null)
                        Text(b.task.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xAA000000))),
                      Text(b.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: ink)),
                      Text.rich(
                        TextSpan(children: [
                          if (b.tooEarly && hh < 64)
                            const TextSpan(text: 'Too early · ', style: TextStyle(color: Color(0xFFB71C1C), fontWeight: FontWeight.w700)),
                          TextSpan(text: meta),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Color(0xAA000000)),
                      ),
                      if (b.tooEarly && hh >= 64)
                        const Padding(padding: EdgeInsets.only(top: 3), child: _Tag('Too early', bad: true))
                      else if (b.clash && hh >= 80)
                        const Padding(padding: EdgeInsets.only(top: 3), child: _Tag('Clash')),
                      if (listRoom > 0 && unplanned.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            for (final x in unplanned.take(unplanned.length > listRoom ? max(listRoom - 1, 1) : listRoom))
                              InkWell(
                                onTap: () => store.toggleStep(b.task, x),
                                child: SizedBox(
                                  height: 26,
                                  child: Row(children: [
                                    const Icon(Icons.check_box_outline_blank, size: 18, color: Colors.black54),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text(x.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                                  ]),
                                ),
                              ),
                            if (unplanned.length > listRoom)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text('+ ${unplanned.length - max(listRoom - 1, 1)} more · no times',
                                    style: const TextStyle(fontSize: 12, color: Color(0xAA000000))),
                              ),
                          ]),
                        ),
                      ],
                    ]),
                  ),
                  // Under the tick when there's room, so the name keeps its width.
                  if (hh >= 72) Column(children: [_tick(b), _more(b, width: 32)]) else ...[_more(b), _tick(b)],
                ]),
        ),
      ),
    );
  }

  /// A task whose steps are planned inside its time: a frame with its name up a strip on the
  /// left, and the steps drawn inside it.
  Widget _frame(BuildContext context, PlanBlock b, double hh) {
    final c = _colour(b.task);
    final noTime = b.task.steps.where((x) => !x.done && b.task.slotsOf(x).isEmpty).length;
    return _gestures(
      b,
      hh,
      Opacity(
        opacity: b.done ? 0.5 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.3),
            border: Border.all(color: c, width: 2),
            borderRadius: BorderRadius.circular(14),
          ),
          foregroundDecoration: b.clash
              ? BoxDecoration(border: Border.all(color: const Color(0xFFD32F2F), width: 2.5), borderRadius: BorderRadius.circular(14))
              : null,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: _frameBar - 2,
              decoration: BoxDecoration(
                color: c,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
              ),
              child: Column(children: [
                _tick(b),
                if (hh >= 90) _more(b),
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Center(
                      child: Text(
                        '${b.title} · ${b.task.stepsDone} of ${b.task.steps.length} steps',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: noTime == 0 || hh < 60
                  ? const SizedBox()
                  : Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 6, 8, 16),
                        child: Text('$noTime step${noTime == 1 ? '' : 's'} without a time',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xAA000000))),
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  /// A block that leaves room: a coloured band down the left with its name running up it.
  Widget _band(BuildContext context, PlanBlock b, double hh) {
    final c = _colour(b.task);
    return _gestures(
      b,
      hh,
      Opacity(
        opacity: b.done ? 0.5 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.16),
            border: Border.all(color: c, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: _bandBar - 2,
              color: c,
              child: Column(children: [
                _tick(b),
                if (hh >= 90) _more(b),
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Center(
                      child: Text(
                        '${b.title} · ${_times(b)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            const Expanded(
              child: Align(
                alignment: Alignment.bottomRight,
                child: Padding(padding: EdgeInsets.all(6), child: _Tag('Leaves room')),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _hiddenStrip(BuildContext context, PlanBlock b, double hh) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => _blockMenu(b),
      child: Container(
        decoration: BoxDecoration(
          color: theme.hintColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: hh < 16
            ? null
            : Text('Hidden · ${describeLength(b.slot.minutes)}',
                style: TextStyle(fontSize: 12, color: theme.hintColor), maxLines: 1),
      ),
    );
  }

  /// 1.12.5: a stretch of driving before or after a block.
  Widget _driveBlock(BuildContext context, DriveSpan d, double hh) {
    final theme = Theme.of(context);
    final w = d.block.task.where;
    final label = [
      '${d.estimate ? '≈' : ''}${describeLength(d.minutes)}',
      if (d.before) 'to ${w?.name ?? d.block.title}' else if (d.from != null) 'to ${d.from}' else 'driving',
    ].join(' ');
    return Semantics(
      label: 'Driving $label',
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => editDrive(context, store, d.block.task),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.hintColor.withValues(alpha: 0.35)),
          ),
          alignment: Alignment.centerLeft,
          child: hh < 14
              ? null
              : Row(children: [
                  Icon(Icons.directions_car_outlined, size: min(16, hh - 2), color: theme.hintColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(label,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: theme.hintColor)),
                  ),
                ]),
        ),
      ),
    );
  }

  // --- The tray ---

  Widget _trayChip(BuildContext context, TrayItem i, {bool card = false}) {
    final theme = Theme.of(context);
    final c = _colour(i.task);
    final steps = _stepCount(i);
    final open = _traySteps.contains(i.task.id);
    void toggle() => setState(() => open ? _traySteps.remove(i.task.id) : _traySteps.add(i.task.id));
    final isStep = i.step != null;
    final content = card
        ? Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: c, width: isStep && open ? 3 : 6)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(
                    [if (isStep) 'Step of ${i.task.title}', i.why, describeLength(i.minutes(data))].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                ]),
              ),
              if (steps > 0)
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                  onPressed: toggle,
                  icon: Icon(open ? Icons.expand_less : Icons.expand_more, size: 18),
                  label: Text('$steps step${steps == 1 ? '' : 's'}'),
                ),
              Icon(Icons.drag_indicator, color: theme.hintColor),
            ]),
          )
        : Container(
            margin: const EdgeInsets.only(right: 6, bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isStep ? c.withValues(alpha: 0.55) : c,
              borderRadius: BorderRadius.circular(10),
              border: i.other && !isStep ? Border.all(color: const Color(0x33000000)) : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (isStep) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.subdirectory_arrow_right, size: 14, color: Color(0xAA000000))),
              Text.rich(TextSpan(children: [
                TextSpan(text: i.title),
                TextSpan(
                    text: '  ${i.other && !isStep ? '${i.why} · ' : ''}${describeLength(i.minutes(data))}',
                    style: const TextStyle(fontSize: 11, color: Color(0xAA000000))),
              ]), style: const TextStyle(fontSize: 13, color: Color(0xDD000000))),
              if (steps > 0)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: toggle,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('$steps', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xAA000000))),
                      Icon(open ? Icons.chevron_left : Icons.chevron_right, size: 16, color: const Color(0xAA000000)),
                    ]),
                  ),
                ),
            ]),
          );
    return LongPressDraggable<TrayItem>(
      data: i,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 220,
          height: max(i.minutes(data) * _ppm(context), 30),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12)),
          child: Text(i.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: content),
      child: InkWell(onTap: () => _planTray(i), child: content),
    );
  }

  Widget _trayBar(BuildContext context, List<TrayItem> all) {
    final theme = Theme.of(context);
    final tray = _trayShown(all);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: tray.isEmpty ? null : () => setState(() => _trayOpen = !_trayOpen),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 6),
              child: Row(children: [
                Expanded(
                  child: Text(
                    all.isEmpty
                        ? 'Nothing waiting to be planned'
                        : [
                            'To plan for ${DateFormat('EEE d').format(_day)} (${all.where((i) => !i.other).length})',
                            if (all.any((i) => i.other)) '${all.where((i) => i.other).length} more open',
                          ].join(' · '),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (_trayOpen) _trayAllButton(),
                if (tray.isNotEmpty) Icon(_trayOpen ? Icons.expand_more : Icons.expand_less),
              ]),
            ),
          ),
          if (_trayOpen) _trayCats(all),
          if (tray.isNotEmpty)
            _trayOpen
                ? ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                      child: Wrap(children: _trayWidgets(context, tray)),
                    ),
                  )
                : SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                      children: _trayWidgets(context, tray),
                    ),
                  ),
        ]),
      ),
    );
  }

  /// Switches "Other open tasks" on and off (Settings, Day plan, has it too).
  Widget _trayAllButton() => IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: s.trayAll ? 'Only what\'s for this day' : 'Show all open tasks',
        isSelected: s.trayAll,
        icon: const Icon(Icons.playlist_add_check),
        selectedIcon: const Icon(Icons.playlist_add_check_circle),
        onPressed: () {
          s.trayAll = !s.trayAll;
          store.dayPlanChanged();
        },
      );

  Widget _trayPanel(BuildContext context, List<TrayItem> all) {
    final theme = Theme.of(context);
    final tray = _trayShown(all);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainer,
      child: ListView(padding: const EdgeInsets.only(top: 8, bottom: 16), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: Row(children: [
            Expanded(child: Text('To plan · drag onto a time', style: theme.textTheme.titleSmall)),
            _trayAllButton(),
          ]),
        ),
        _trayCats(all, padding: const EdgeInsets.fromLTRB(10, 0, 10, 8)),
        if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text('Nothing waiting. Switch "On the Day plan" on a task, or plan one with +.',
                style: TextStyle(color: theme.hintColor)),
          ),
        ..._trayWidgets(context, tray, card: true),
      ]),
    );
  }

  // --- Actions ---

  Future<void> _planAny() async {
    final t = await pickTask(context, data, title: 'Plan a time for');
    if (t == null || !mounted) return;
    await showPlanTimeSheet(context, store, t, day: _day);
  }

  /// 1.12.8: a tap at [dy] on [day]'s column: add a new task or step there, or plan one already
  /// in the app, starting at the time step tapped.
  Future<void> _addAt(DateTime day, double dy, int from) async {
    if (_moving != null || _resizing != null) return;
    final minutes = ((dy - _top) / _ppm(context) + from).floor();
    final snapped = (minutes ~/ s.snap * s.snap).clamp(0, 24 * 60 - s.snap);
    final start = day.add(Duration(minutes: snapped));
    final added = await showAddAtSheet(context, store, start, onExisting: (at) async {
      final t = await pickOwner(context, data, title: 'Plan at ${DateFormat('HH:mm').format(at)}', at: at);
      if (t == null || !mounted) return;
      await showPlanTimeSheet(context, store, t, start: at, day: dayStart(at));
    });
    if (added == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(added.step == null
            ? 'Added "${added.title}" at ${DateFormat('HH:mm').format(added.start)}'
            : 'Added step "${added.title}" to "${added.task.title}" at ${DateFormat('HH:mm').format(added.start)}'),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskPage(store: store, task: added.task))),
        ),
      ));
  }

  Future<void> _planTray(TrayItem i) async {
    final missed = i.missed;
    if (missed == null) {
      await showPlanTimeSheet(context, store, i.task, step: i.step, day: _day);
      return;
    }
    // A missed time: move it rather than plan another.
    final now = DateTime.now();
    final from = snapUp(now, s.snap);
    final today = DateTime(now.year, now.month, now.day);
    final sameTime = today.add(Duration(minutes: missed.start.hour * 60 + missed.start.minute));
    final todayAt = sameTime.isBefore(from) ? from : sameTime;
    final free = layoutDay(data, today, events: _events).firstFree(missed.minutes, from: from);
    final hm = DateFormat('HH:mm');
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(i.title), subtitle: Text('${i.why} · ${describeLength(missed.minutes)}')),
          ListTile(
            leading: const Icon(Icons.today),
            title: Text('Move to today, ${hm.format(todayAt)}'),
            onTap: () => Navigator.pop(c, 'today'),
          ),
          if (free != null)
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text('Next free gap, ${hm.format(free)}'),
              onTap: () => Navigator.pop(c, 'free'),
            ),
          ListTile(
            leading: const Icon(Icons.edit_calendar),
            title: const Text('Choose a time…'),
            onTap: () => Navigator.pop(c, 'choose'),
          ),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'choose') {
      await showPlanTimeSheet(context, store, i.task, slot: missed);
      return;
    }
    _moveMissed(i, choice == 'free' ? free! : todayAt);
  }

  /// Moves a missed time to [start], with Undo.
  void _moveMissed(TrayItem i, DateTime start) {
    final missed = i.missed!;
    final was = missed.start;
    store.updateSlot(i.task, missed, start: start);
    _changedSnack('Moved "${i.title}" to ${DateFormat('EEE HH:mm').format(start)}',
        () => store.updateSlot(i.task, missed, start: was));
  }

  void _planDropped(TrayItem i, DateTime start) {
    if (i.missed != null) return _moveMissed(i, start);
    final slot = store.planTime(i.task, start, i.minutes(data), step: i.step);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('Planned "${i.title}" at ${DateFormat('HH:mm').format(start)}'),
        action: SnackBarAction(label: 'Change', onPressed: () => showPlanTimeSheet(context, store, i.task, slot: slot)),
      ));
  }

  /// What comes after [b], moved later if [b] now runs into it, as Settings' "When a bar
  /// moves" says (ask, always or never). Empty when nothing is to move.
  Future<List<PlanMove>?> _pushFor(PlanBlock b, DateTime start, int minutes) async {
    if (b.shared || !start.add(Duration(minutes: minutes)).isAfter(b.end)) return const [];
    final moves = pushAfter(data, b, start, minutes);
    if (moves.isEmpty || data.ganttPush == GanttPush.never) return const [];
    if (data.ganttPush == GanttPush.always) return moves;
    final n = moves.map((m) => m.slot).toSet().length;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Move what comes after?'),
        content: Text('"${b.title}" now runs into $n planned time${n == 1 ? '' : 's'} after it. '
            'Move ${n == 1 ? 'it' : 'them'} later, keeping the gaps?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Leave them')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Move them')),
        ],
      ),
    );
    if (yes == null) return null;
    return yes ? moves : const [];
  }

  /// A band that leaves room is moving: what's planned inside it, to move with it as Settings'
  /// "When a bar moves" says (ask, always or never).
  Future<List<PlanMove>?> _bandFor(PlanBlock b, Duration d) async {
    final moves = insideBand(data, b, d);
    if (moves.isEmpty || data.ganttPush == GanttPush.never) return const [];
    if (data.ganttPush == GanttPush.always) return moves;
    final n = moves.length;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Move what\'s inside it too?'),
        content: Text('$n planned time${n == 1 ? ' is' : 's are'} inside "${b.title}". Move '
            '${n == 1 ? 'it' : 'them'} with it?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Leave them')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Move them')),
        ],
      ),
    );
    if (yes == null) return null;
    return yes ? moves : const [];
  }

  Future<void> _shift(PlanBlock b, int minutes) async {
    final d = Duration(minutes: minutes);
    final push = b.shared ? await _bandFor(b, d) : await _pushFor(b, b.start.add(d), b.slot.minutes);
    if (push == null || !mounted) return;
    final before = b.start;
    final inside = [for (final st in b.inside) (st, st.start)];
    store.updateSlot(b.task, b.slot, start: b.start.add(d));
    // A task's steps planned inside it move with it.
    for (final (st, at) in inside) {
      store.updateSlot(st.task, st.slot, start: at.add(d));
    }
    store.applyPlanMoves(push);
    _changedSnack(
      '"${b.title}" now starts ${DateFormat('HH:mm').format(before.add(d))}'
      '${push.isEmpty ? '' : b.shared ? ', with ${_moved(push).replaceFirst(' other', ' thing')} inside it' : ', and ${_moved(push)} moved later'}',
      () {
        store.applyPlanMoves(push, back: true);
        for (final (st, at) in inside) {
          store.updateSlot(st.task, st.slot, start: at);
        }
        store.updateSlot(b.task, b.slot, start: before);
      },
    );
  }

  Future<void> _stretch(PlanBlock b, int minutes) async {
    final to = max(s.snap, b.slot.minutes + minutes);
    final push = await _pushFor(b, b.start, to);
    if (push == null || !mounted) return;
    final was = b.slot.minutes;
    store.updateSlot(b.task, b.slot, minutes: to);
    store.applyPlanMoves(push);
    _changedSnack(
      '"${b.title}" now ends ${DateFormat('HH:mm').format(b.start.add(Duration(minutes: to)))}'
      '${push.isEmpty ? '' : ', and ${_moved(push)} moved later'}',
      () {
        store.applyPlanMoves(push, back: true);
        store.updateSlot(b.task, b.slot, minutes: was);
      },
    );
  }

  String _moved(List<PlanMove> moves) {
    final n = moves.map((m) => m.slot).toSet().length;
    return '$n other${n == 1 ? '' : 's'}';
  }

  void _changedSnack(String text, VoidCallback undo) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text), action: SnackBarAction(label: 'Undo', onPressed: undo)));
  }

  /// Plans [b]'s task's steps that have no time inside [b]'s own time, back to back.
  void _stepsInside(PlanBlock b) {
    final added = store.planStepsInOrder(b.task, b.start, within: b.slot.minutes);
    if (added.isEmpty) return;
    _changedSnack(
      'Planned ${added.length} step${added.length == 1 ? '' : 's'} inside "${b.title}"',
      () => store.removeSlots(b.task, added),
    );
  }

  Future<void> _toggle(PlanBlock b) async {
    final t = b.task;
    final messenger = ScaffoldMessenger.of(context);
    if (b.done) {
      if (b.step == null && t.closedAt != null) store.restore(t);
      store.untickSlot(t, b.slot);
      return;
    }
    int? index;
    Task? spawned;
    final r = store.tickSlot(t, b.slot, onComplete: (i, next) {
      index = i;
      spawned = next;
    });
    messenger.clearSnackBars();
    switch (r) {
      case SlotTick.step:
        break;
      case SlotTick.lastStep:
        if (!mounted) return;
        final yes = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('All steps ticked'),
            content: Text('Tick off "${t.title}" too?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not yet')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Tick it off')),
            ],
          ),
        );
        if (yes == true && t.closedAt == null) {
          final i = data.active.indexOf(t);
          final next = store.complete(t);
          messenger.showSnackBar(SnackBar(
            content: Text('Ticked off "${t.title}"'),
            action: SnackBarAction(label: 'Undo', onPressed: () => store.uncomplete(t, i, next)),
          ));
        }
      case SlotTick.worked:
        messenger.showSnackBar(SnackBar(
          content: const Text('Counted as worked on today. More time is planned for it later.'),
          action: SnackBarAction(label: 'Undo', onPressed: () => store.untickSlot(t, b.slot)),
        ));
      case SlotTick.done:
        messenger.showSnackBar(SnackBar(
          content: Text('Ticked off "${t.title}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              if (index != null) store.uncomplete(t, index!, spawned);
              store.untickSlot(t, b.slot);
            },
          ),
        ));
    }
  }

  /// 1.12.8: a tap on a block opens its task to edit (for a step, the task it belongs to).
  Future<void> _openTask(PlanBlock b) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskPage(store: store, task: b.task)));

  /// 1.12.8: makes a planned task a step of another one, keeping its time on the Day plan.
  Future<void> _makeStep(PlanBlock b) async {
    final parent = await pickOwner(context, data, title: 'Make "${b.task.title}" a step of', at: b.start, exclude: b.task);
    if (parent == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final (_, undo) = store.makeStep(b.task, parent);
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('"${b.task.title}" is now a step of "${parent.title}", still at ${DateFormat('HH:mm').format(b.start)}'),
        action: SnackBarAction(label: 'Undo', onPressed: undo),
      ));
  }

  Future<void> _blockMenu(PlanBlock b) async {
    final theme = Theme.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(b.title, style: theme.textTheme.titleMedium),
            subtitle: Text([
              if (b.step != null) 'Step of ${b.task.title}',
              _times(b),
              if (b.tooEarly) 'Starts before what it comes after is done',
            ].join(' · ')),
          ),
          if (!b.done)
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Start focus'),
              subtitle: const Text('The focus timer on this, full screen'),
              onTap: () => Navigator.pop(c, 'focus'),
            ),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Open the task'), onTap: () => Navigator.pop(c, 'open')),
          ListTile(leading: const Icon(Icons.schedule), title: const Text('Change the time…'), onTap: () => Navigator.pop(c, 'time')),
          if (b.step == null && !b.done && b.task.closedAt == null)
            ListTile(
              leading: const Icon(Icons.subdirectory_arrow_right),
              title: const Text('Make it a step of…'),
              subtitle: const Text('Of another task, keeping this time'),
              onTap: () => Navigator.pop(c, 'makeStep'),
            ),
          if (b.step == null && !b.done && b.task.steps.any((x) => !x.done && b.task.slotsOf(x).every((sl) => sl.doneAt != null)))
            ListTile(
              leading: const Icon(Icons.low_priority),
              title: const Text('Plan its steps inside this time'),
              subtitle: const Text('Steps without a time, in order, back to back'),
              onTap: () => Navigator.pop(c, 'steps'),
            ),
          ListTile(
            leading: Icon(b.shared ? Icons.check_box : Icons.check_box_outline_blank),
            title: const Text('Leave room for other tasks'),
            subtitle: const Text('Things planned inside it aren\'t clashes'),
            onTap: () => Navigator.pop(c, 'shared'),
          ),
          ListTile(
            leading: Icon(b.done ? Icons.undo : Icons.check),
            title: Text(b.done ? 'Untick' : 'Tick'),
            onTap: () => Navigator.pop(c, 'tick'),
          ),
          ListTile(
            leading: const Icon(Icons.event_busy),
            title: const Text('Remove this time'),
            onTap: () => Navigator.pop(c, 'remove'),
          ),
          ]),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'focus':
        startFocusOn(context, store, b.task, stepId: b.step?.id);
      case 'open':
        await _openTask(b);
      case 'makeStep':
        await _makeStep(b);
      case 'time':
        await showPlanTimeSheet(context, store, b.task, slot: b.slot);
      case 'shared':
        store.updateSlot(b.task, b.slot, shared: !b.shared);
      case 'tick':
        await _toggle(b);
      case 'steps':
        _stepsInside(b);
      case 'remove':
        store.removeSlot(b.task, b.slot);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text('Removed "${b.title}" from ${DateFormat('HH:mm').format(b.start)}'),
            action: SnackBarAction(label: 'Undo', onPressed: () => store.restoreSlot(b.task, b.slot)),
          ));
    }
  }
}

/// How tall the stretch handle along a Day plan block's bottom edge is: a thumb's worth on a long
/// block, but at most about a third of a short one so the rest can still be held to move it
/// (1.12.6).
double stretchHandleHeight(double blockHeight) => min(28.0, max(16.0, blockHeight * 0.34));

/// The grip along a planned block's bottom edge: drag it (or hold it, then drag) to change how
/// long the block is. Darker while stretching (1.12.6).
class _StretchHandle extends StatelessWidget {
  const _StretchHandle({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: active ? 0.16 : 0.07),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 2; i++)
              Container(
                width: active ? 56 : 44,
                height: 3,
                margin: const EdgeInsets.symmetric(vertical: 1.5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: active ? 0.75 : 0.42),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ]),
        ),
      );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.bad = false});
  final String text;
  final bool bad;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(color: bad ? const Color(0xFFC62828) : const Color(0xD01A1C1C), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500)),
      );
}

/// Diagonal stripes: the gap kept after a block.
class _Hatch extends CustomPainter {
  _Hatch(this.colour);
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = colour
      ..strokeWidth = 3;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)));
    for (var x = -size.height; x < size.width; x += 9) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Hatch old) => old.colour != colour;
}

/// A dashed rounded box: free time.
class _DashedBox extends CustomPainter {
  _DashedBox(this.colour);
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, min(d + 5, m.length)), p);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBox old) => old.colour != colour;
}

/// The "comes after" lines: from the bottom of each block to the top of the one that waits for
/// it, red when it starts too early.
class _LinkPainter extends CustomPainter {
  _LinkPainter(this.links, this.colour);
  final List<(Rect, Rect, bool)> links;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (a, b, early) in links) {
      final colour = early ? const Color(0xFFD32F2F) : this.colour;
      final p = Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      final Offset from, to, c1, c2;
      if (b.top - a.bottom > 12) {
        // Below it: straight down from its bottom edge to the top of the next.
        from = Offset(a.right - 22, a.bottom - 3);
        to = Offset(b.right - 22, b.top + 3);
        final mid = (from.dy + to.dy) / 2;
        c1 = Offset(from.dx, mid);
        c2 = Offset(to.dx, mid);
      } else if (b.left >= a.right - 1 || a.left >= b.right - 1) {
        // Side by side (they overlap in time): across the small space between them.
        // From its bottom edge round into the side of the one that waits.
        final right = b.left >= a.right - 1;
        from = Offset(right ? a.right - 34 : a.left + 34, a.bottom - 3);
        to = Offset(right ? b.left + 2 : b.right - 2, min(b.bottom - 8, b.top + 16));
        c1 = Offset(from.dx, max(from.dy, to.dy) + 22);
        c2 = Offset(to.dx + (right ? -26 : 26), to.dy);
      } else {
        // Waits for something that ends later in the same column: round the right-hand side.
        from = Offset(a.right - 4, a.bottom - 10);
        to = Offset(b.right - 4, b.top + 10);
        final x = min(max(a.right, b.right) + 9, size.width - 1);
        c1 = Offset(x, from.dy);
        c2 = Offset(x, to.dy);
      }
      canvas.drawPath(Path()..moveTo(from.dx, from.dy)..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, to.dx, to.dy), p);
      canvas.drawCircle(from, 3.5, Paint()..color = colour);
      var dir = to - c2;
      if (dir.distance < 0.01) dir = to - from;
      final n = dir / dir.distance;
      final side = Offset(-n.dy, n.dx);
      canvas.drawPath(
        Path()
          ..moveTo(to.dx, to.dy)
          ..lineTo(to.dx - n.dx * 9 + side.dx * 5, to.dy - n.dy * 9 + side.dy * 5)
          ..lineTo(to.dx - n.dx * 9 - side.dx * 5, to.dy - n.dy * 9 - side.dy * 5)
          ..close(),
        Paint()..color = colour,
      );
    }
  }

  @override
  bool shouldRepaint(_LinkPainter old) => true;
}

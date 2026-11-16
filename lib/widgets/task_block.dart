import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../day_plan.dart' show suggestDrive;
import '../pace.dart';
import '../task_list.dart';
import 'link_text.dart';

final dateTimeFmt = DateFormat('EEE d MMM yyyy, HH:mm');

/// Short "time added": just the time today, weekday this week, date otherwise.
String shortTime(DateTime d, [DateTime? now]) {
  now ??= DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (!d.isBefore(today)) return DateFormat('HH:mm').format(d);
  if (today.difference(d).inDays < 6) return DateFormat('EEE HH:mm').format(d);
  return DateFormat('d MMM').format(d);
}

/// A full-width coloured block. Thin by default (name + time); tap to expand.
class TaskBlock extends StatelessWidget {
  const TaskBlock({
    super.key,
    required this.task,
    required this.color,
    required this.expanded,
    required this.onTap,
    required this.onOpen,
    this.onCheck,
    this.trailing,
    this.archived = false,
    this.selected = false,
    this.lockedBy,
    this.categoryName,
    this.onStep,
    this.onSkip,
    this.stageName,
    this.boxName,
    this.onBoard,
    this.onWorked,
    this.tag,
    this.data,
    this.showCategory = true,
    this.onPlan,
  });

  /// 1.12.5: for the chips that need settings (drive time, default reminder).
  final AppData? data;

  /// 1.12.5: false when the list is already grouped by category, so the card doesn't repeat it.
  final bool showCategory;

  /// 1.12.5: "Plan time" on the opened card (Day plan).
  final VoidCallback? onPlan;

  /// Item 102: a short label after the title (why a hidden task breaks through: "Home · Overdue").
  final String? tag;

  final Task task;
  final Color color;
  final bool expanded;
  final bool archived;

  /// Outlined when it is the task open in the side pane.
  final bool selected;

  /// Title of the earlier task this one is waiting for; shown greyed with a lock.
  final String? lockedBy;

  /// Shown in the expanded details.
  final String? categoryName;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final VoidCallback? onCheck;
  final Widget? trailing;

  /// Ticks a checklist step from the expanded block.
  final ValueChanged<TaskStep>? onStep;

  /// Moves a repeating task to its next date without ticking it off.
  final VoidCallback? onSkip;

  /// The Kanban stage it is in, shown as a small label; null when not on the board.
  final String? stageName;

  /// Item 60: the matrix box it is in, shown as a small label; null when not on the matrix.
  final String? boxName;

  /// Opens the Kanban board; the "Board" button shows only for tasks on the board.
  final VoidCallback? onBoard;

  /// Item 75: ticks today as a day worked on it, without finishing it.
  final VoidCallback? onWorked;

  /// One-line notes preview on the thin block, only when there are notes.
  bool get preview => !expanded && task.notes.trim().isNotEmpty;

  Widget _badge(IconData icon, String tip, Color color) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Tooltip(message: tip, child: Icon(icon, size: 16, color: color)),
      );

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xDD000000);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Material(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
          side: selected ? const BorderSide(color: Color(0xDD000000), width: 2.5) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(3),
          onTap: onTap,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.topCenter,
            child: DefaultTextStyle(
              style: textTheme.bodyMedium!.copyWith(color: ink),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: preview ? 54 : 42,
                    child: Row(children: [
                      if (lockedBy != null)
                        Tooltip(
                          message: 'Waiting for "$lockedBy"',
                          child: const SizedBox(width: 48, child: Icon(Icons.lock_outline, color: ink)),
                        )
                      else if (onCheck != null)
                        IconButton(
                          tooltip: 'Tick off',
                          icon: const Icon(Icons.check_box_outline_blank, color: ink),
                          onPressed: onCheck,
                        )
                      else
                        const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Flexible(
                                child: Text(task.title,
                                    maxLines: expanded ? 2 : 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                              ),
                              if (tag != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                        color: const Color(0xD01A1C1C), borderRadius: BorderRadius.circular(6)),
                                    child: Text(tag!,
                                        style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                                  ),
                                ),
                              if (task.starred) _badge(Icons.star, 'Starred', const Color(0xFF8D6E00)),
                              // Item 107: the first tag, and how many more.
                              if (task.tags.isNotEmpty && !expanded)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Tooltip(
                                    message: task.tags.map((x) => '#$x').join(' '),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 110),
                                      child: Text(
                                          '#${task.tags.first}${task.tags.length > 1 ? ' +${task.tags.length - 1}' : ''}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12, color: Color(0xAA000000))),
                                    ),
                                  ),
                                ),
                              if (task.steps.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text('${task.stepsDone}/${task.steps.length}',
                                      style: const TextStyle(fontSize: 12, color: Color(0xAA000000))),
                                ),
                              if (task.emails.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Tooltip(
                                    message: '${task.emails.length} email${task.emails.length == 1 ? '' : 's'} attached',
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.mail_outline, size: 14, color: Color(0xAA000000)),
                                      if (task.emails.length > 1)
                                        Text('${task.emails.length}',
                                            style: const TextStyle(fontSize: 12, color: Color(0xAA000000))),
                                    ]),
                                  ),
                                ),
                              if (task.estimate != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Tooltip(
                                    message: 'About ${describeMinutes(task.estimate!)}',
                                    child: Text(shortMinutes(task.estimate!),
                                        style: const TextStyle(fontSize: 12, color: Color(0xAA000000))),
                                  ),
                                ),
                              if (stageName != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Tooltip(
                                    message: 'On the Kanban board',
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: const Color(0x88000000)),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(stageName!, style: const TextStyle(fontSize: 11, color: ink)),
                                    ),
                                  ),
                                ),
                              if (boxName != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Tooltip(
                                    message: 'On the matrix',
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.grid_view, size: 12, color: ink),
                                      const SizedBox(width: 2),
                                      Text(boxName!, style: const TextStyle(fontSize: 11, color: ink)),
                                    ]),
                                  ),
                                ),
                              // Item 96: less done than the time gone says, or overdue.
                              if (!archived && taskPace(task, DateTime.now()).verdict == Pace.behind)
                                _badge(Icons.hourglass_bottom, 'Behind: less done than the time gone', ink),
                              if (task.repeat != null) _badge(Icons.repeat, task.repeat!.describe(), ink),
                              if (task.isSnoozed(DateTime.now())) _badge(Icons.snooze, 'Snoozed', ink),
                            ]),
                            if (preview)
                              Text(task.notes.split('\n').first,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5, color: Color(0xAA000000))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // The opened card's time bar says when it was added.
                      if (!expanded || archived)
                        Text(shortTime(archived ? task.closedAt! : task.createdAt),
                            style: const TextStyle(fontSize: 13)),
                      trailing ?? const SizedBox(width: 12),
                    ]),
                  ),
                  if (expanded) _details(context, ink),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _details(BuildContext context, Color ink) => _Details(block: this, ink: ink);
}

/// 1.12.5: the opened card. A time bar from when it was added to its due date (with a dot for
/// each dated step), chips for what is set (next step, where, length, repeats, Day plan,
/// reminder, worked, behind...), a short step list and one row of buttons.
class _Details extends StatefulWidget {
  const _Details({required this.block, required this.ink});

  final TaskBlock block;
  final Color ink;

  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  bool _allChips = false;
  bool _ticked = false;
  bool _allSteps = false;

  static const _maxChips = 6;
  static const _firstSteps = 3;
  static const _red = Color(0xFF7A1414);

  TaskBlock get b => widget.block;
  Task get task => b.task;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final ink = widget.ink;
    final open = [for (final s in task.steps) if (!s.done) s];
    final ticked = [for (final s in task.steps) if (s.done) s];
    final chips = cardChips(task, now,
        data: b.data, category: b.showCategory ? b.categoryName : null, lockedBy: b.lockedBy, archived: b.archived);
    final shownChips = _allChips || chips.length <= _maxChips + 1 ? chips : chips.take(_maxChips).toList();
    final shownSteps = _allSteps || open.length <= _firstSteps + 1 ? open : open.take(_firstSteps).toList();
    final hidden = open.length - shownSteps.length;
    DateTime? lastDate;
    for (final s in open.skip(shownSteps.length)) {
      final d = s.dueAt ?? s.startAt;
      if (d != null && (lastDate == null || d.isAfter(lastDate))) lastDate = d;
    }
    final muted = TextStyle(fontSize: 13.5, color: ink.withValues(alpha: 0.75));

    Widget more(String text, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Align(alignment: Alignment.centerLeft, child: Text(text, style: muted)),
          ),
        );

    final buttons = <Widget>[
      if (b.onSkip != null && task.repeat != null && !b.archived)
        _button(Icons.skip_next, 'Skip', b.onSkip, ink),
      if (b.onWorked != null && !b.archived)
        _button(task.workedOn(now) ? Icons.check_circle_outline : Icons.radio_button_unchecked, 'Worked today', b.onWorked, ink),
      if (b.onBoard != null && task.kanban && !b.archived) _button(Icons.view_kanban_outlined, 'Board', b.onBoard, ink),
      if (b.onPlan != null && !b.archived) _button(Icons.schedule, 'Plan time', b.onPlan, ink),
      _button(b.archived ? Icons.info_outline : Icons.edit_outlined, b.archived ? 'Details' : 'Edit', b.onOpen, ink),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 12, 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TimeBar(task: task, now: now, ink: ink, archived: b.archived),
        if (shownChips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in shownChips) _chip(c, ink),
              if (shownChips.length < chips.length)
                ActionChip(
                  label: Text('+${chips.length - shownChips.length} more'),
                  labelStyle: TextStyle(fontSize: 12.5, color: ink),
                  backgroundColor: const Color(0x1A000000),
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _allChips = true),
                ),
            ]),
          ),
        if (task.notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LinkText(task.notes, linkColor: const Color(0xFF0D47A1)),
          ),
        if (task.steps.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (ticked.isNotEmpty)
                more('${_ticked ? '▾' : '▸'} ${ticked.length} ticked', () => setState(() => _ticked = !_ticked)),
              if (_ticked)
                for (final s in ticked) _step(s, now, ink),
              for (final s in shownSteps) _step(s, now, ink, next: identical(s, open.first)),
              if (hidden > 0)
                more(
                    '▸ $hidden more step${hidden == 1 ? '' : 's'}'
                    '${lastDate == null ? '' : ', up to ${DateFormat('EEE d MMM').format(lastDate)}'}',
                    () => setState(() => _allSteps = true)),
            ]),
          ),
        const SizedBox(height: 6),
        const Divider(height: 1, color: Color(0x26000000)),
        Row(children: [for (final w in buttons) Expanded(child: w)]),
      ]),
    );
  }

  Widget _chip(CardChip c, Color ink) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: c.warn ? const Color(0x297A1414) : const Color(0x1A000000),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(c.text,
            style: TextStyle(
                fontSize: 12.5, color: c.warn ? _red : ink, fontWeight: c.warn ? FontWeight.w600 : FontWeight.normal)),
      );

  Widget _step(TaskStep s, DateTime now, Color ink, {bool next = false}) {
    final d = s.dueAt;
    final late = !s.done && d != null && d.isBefore(now);
    return InkWell(
      onTap: b.onStep == null || b.archived ? null : () => b.onStep!(s),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Row(children: [
          Icon(s.done ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: ink),
          const SizedBox(width: 8),
          Expanded(
            child: Text(s.title,
                style: TextStyle(
                    decoration: s.done ? TextDecoration.lineThrough : null,
                    fontWeight: next ? FontWeight.w600 : null,
                    color: s.done ? const Color(0x88000000) : ink)),
          ),
          if (s.taskId != null || s.linkStepId != null) const Icon(Icons.link, size: 16, color: Color(0x88000000)),
          if (d != null && !s.done)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(shortWhen(d, now, time: false),
                  style: TextStyle(fontSize: 12, color: late ? _red : ink, fontWeight: late ? FontWeight.w700 : null)),
            ),
        ]),
      ),
    );
  }

  Widget _button(IconData icon, String label, VoidCallback? onTap, Color ink) => InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 20, color: ink),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: ink)),
          ]),
        ),
      );
}

/// "Today 07:30", "Tomorrow 09:00", "Sun 15 Nov, 07:30" (no time with [time] false, and no
/// month within the next week).
String shortWhen(DateTime d, DateTime now, {bool time = true}) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  final hm = time ? DateFormat('HH:mm').format(d) : '';
  final String date;
  if (diff == 0) {
    date = 'Today';
  } else if (diff == 1) {
    date = 'Tomorrow';
  } else if (diff == -1) {
    date = 'Yesterday';
  } else if (diff.abs() < 7) {
    date = DateFormat('EEE d').format(d);
  } else {
    date = DateFormat(d.year == now.year ? 'EEE d MMM' : 'd MMM yyyy').format(d);
  }
  if (!time) return date;
  return diff.abs() < 7 ? '$date $hm' : '$date, $hm';
}

/// "in 8 days", "today", "2 days ago"...
String daysFrom(DateTime d, DateTime now) {
  final n = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (n == 0) return 'today';
  if (n == 1) return 'tomorrow';
  if (n == -1) return 'yesterday';
  return n > 0 ? 'in $n days' : '${-n} days ago';
}

class CardChip {
  const CardChip(this.text, {this.warn = false});
  final String text;
  final bool warn;
}

/// 1.12.5: the chips on an opened card, most useful first; only what the task has.
List<CardChip> cardChips(Task t, DateTime now,
    {AppData? data, String? category, String? lockedBy, bool archived = false}) {
  final out = <CardChip>[];
  if (archived && t.closedAt != null) out.add(CardChip('Ticked off ${shortWhen(t.closedAt!, now)}'));
  // The next open step with a date.
  final dated = [
    for (final s in t.steps)
      if (!s.done && s.dueAt != null) s
  ]..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
  if (!archived && dated.isNotEmpty) {
    final s = dated.first;
    final late = s.dueAt!.isBefore(now);
    out.add(CardChip('Next: ${s.title} · ${shortWhen(s.dueAt!, now)}${late ? ' · overdue' : ''}', warn: late));
  }
  if (lockedBy != null) out.add(CardChip('After "$lockedBy"'));
  if ((t.waitingOn ?? '').isNotEmpty) out.add(CardChip('Waiting on ${t.waitingOn}'));
  final where = t.where;
  if (where != null) {
    var text = 'At ${where.name}';
    if (data != null && !archived) {
      final drive = t.driveBefore ?? suggestDrive(data, t, after: false, at: now)?.minutes;
      if (drive != null && drive > 0) text += ' · ${describeMinutes(drive)} drive';
    }
    out.add(CardChip(text));
  }
  final focused = t.focus.values.fold(0, (a, m) => a + m);
  if (t.estimate != null || focused > 0) {
    out.add(CardChip([
      if (t.estimate != null) 'Takes ${describeMinutes(t.estimate!)}',
      if (focused > 0) '${describeMinutes(focused)} worked',
    ].join(' · ')));
  }
  final r = t.repeat;
  if (r != null) {
    final d = r.describe();
    var text = 'Repeats ${d.isEmpty ? '' : d[0].toLowerCase()}${d.length > 1 ? d.substring(1) : ''}';
    if (!archived && !r.fromCompletion && t.dueAt != null) {
      final next = r.nextDue(due: t.dueAt, completedAt: t.dueAt!.isAfter(now) ? t.dueAt! : now);
      text += ', next ${DateFormat(next.year == now.year ? 'd MMM' : 'd MMM yyyy').format(next)}';
    }
    out.add(CardChip(text));
  }
  if (!archived) {
    final slot = t.slots
        .where((x) => x.doneAt == null && x.end.isAfter(now))
        .fold<TimeSlot?>(null, (a, x) => a == null || x.start.isBefore(a.start) ? x : a);
    if (slot != null) out.add(CardChip('Day plan ${shortWhen(slot.start, now)}'));
    final due = t.dueAt;
    final before = t.remindBefore ?? data?.defaultRemindBefore ?? 0;
    if (due != null && before > 0) {
      final at = due.subtract(Duration(minutes: before));
      if (at.isAfter(now)) out.add(CardChip('Reminder ${shortWhen(at, now)}'));
    }
    if (t.place != null) out.add(CardChip('Remind ${t.placeLeave ? 'leaving' : 'arriving at'} ${t.place}'));
    if (t.isSnoozed(now)) out.add(CardChip('Snoozed until ${shortWhen(t.snoozedUntil!, now)}'));
  }
  if (t.worked.isNotEmpty) {
    final last = t.worked.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
    final lastDay = DateTime.tryParse(last);
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final week = [
      for (var i = 0; i < 7; i++)
        if (t.workedOn(monday.add(Duration(days: i)))) i
    ].length;
    if (lastDay != null) {
      out.add(CardChip('Worked ${shortWhen(lastDay, now, time: false)}'
          '${week > 0 ? ' · $week day${week == 1 ? '' : 's'} this week' : ''}'));
    }
  }
  if (!archived) {
    final pace = taskPace(t, now);
    if (pace.verdict == Pace.behind && pace.done != null && pace.used != null && !pace.overdue) {
      out.add(CardChip(
          'Behind: ${(pace.done! * 100).round()}% done, ${(pace.used!.clamp(0, 1) * 100).round()}% of the time gone',
          warn: true));
    }
  }
  if (category != null) out.add(CardChip(category));
  // Item 107.
  for (final x in t.tags) {
    out.add(CardChip('#$x'));
  }
  return out;
}

/// 1.12.5: a bar from when the task was added to its due date, with a mark for now and a dot
/// for each step with a date (filled when ticked). Without a due date, just when it was added.
class TimeBar extends StatelessWidget {
  const TimeBar({super.key, required this.task, required this.now, required this.ink, this.archived = false});

  final Task task;
  final DateTime now;
  final Color ink;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    final added = task.createdAt;
    final due = task.dueAt;
    final small = TextStyle(fontSize: 12.5, color: ink);
    final bold = small.copyWith(fontWeight: FontWeight.w700);
    final addedText = Text.rich(TextSpan(children: [
      TextSpan(text: 'Added ${DateFormat('EEE d MMM').format(added)}\n'),
      TextSpan(text: daysFrom(added, now), style: bold),
    ]), style: small);
    if (due == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: addedText),
          Text('No due date', style: small),
        ]),
      );
    }
    final end = archived && task.closedAt != null ? task.closedAt! : now;
    final total = due.difference(added).inMinutes;
    double at(DateTime d) => total <= 0 ? 1 : (d.difference(added).inMinutes / total).clamp(0.0, 1.0);
    final overdue = !archived && due.isBefore(now);
    final dots = [
      for (final s in task.steps)
        if ((s.dueAt ?? s.startAt) != null) (at(s.dueAt ?? s.startAt!), s.done, !s.done && s.dueAt != null && s.dueAt!.isBefore(now))
    ];
    const red = Color(0xFF7A1414);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 16,
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            final x = at(end) * w;
            return Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: 0, right: 0, top: 6, height: 4,
                child: DecoratedBox(
                    decoration: BoxDecoration(color: const Color(0x29000000), borderRadius: BorderRadius.circular(2))),
              ),
              Positioned(
                left: 0, width: x, top: 6, height: 4,
                child: DecoratedBox(
                    decoration: BoxDecoration(color: overdue ? red : ink, borderRadius: BorderRadius.circular(2))),
              ),
              for (final (p, done, late) in dots)
                Positioned(
                  left: (p * w - 5).clamp(0.0, w - 10),
                  top: 3,
                  width: 10,
                  height: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? ink : const Color(0xFFF4F7F6),
                      border: Border.all(color: late ? red : ink, width: 2),
                    ),
                  ),
                ),
              if (!archived)
                Positioned(left: (x - 1).clamp(0.0, w - 2), top: 0, width: 2, height: 16, child: ColoredBox(color: overdue ? red : ink)),
            ]);
          }),
        ),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: addedText),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Due ${shortWhen(due, now)}\n'),
                TextSpan(
                    text: overdue ? 'overdue, ${daysFrom(due, now)}' : daysFrom(due, now),
                    style: bold.copyWith(color: overdue ? red : ink)),
              ]),
              style: small,
              textAlign: TextAlign.right,
            ),
          ),
        ]),
      ]),
    );
  }
}

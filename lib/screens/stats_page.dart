import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../models.dart';
import '../stats.dart';
import '../store.dart';

/// How things are going: done per week, on-time share, time to finish, open trend,
/// per-category totals and the streak.
class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.store});

  final AppStore store;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  /// Days back for the period picker; null = all time.
  int? _days = 30;

  /// Category for the added charts: null = all, '' = no category.
  String? _chartCategory;

  static const _periods = {7: 'Last 7 days', 30: 'Last 30 days', 365: 'Last 12 months', null: 'All time'};

  DateTime? get _from => _days == null ? null : DateTime.now().subtract(Duration(days: _days!));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final s = Stats(widget.store.data, DateTime.now());
        final from = _from;
        final done = s.doneSince(from).length;
        final onTime = s.onTimeShare(from);
        final median = s.medianTimeToFinish(from);
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(title: const Text('Statistics')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Wrap(spacing: 8, children: [
              for (final e in _periods.entries)
                ChoiceChip(label: Text(e.value), selected: _days == e.key, onSelected: (_) => setState(() => _days = e.key)),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 12, children: [
              _Tile('Done', '$done', _days == null ? 'all time' : 'in this period'),
              _Tile('On time', onTime == null ? '–' : '${(onTime * 100).round()}%', 'of tasks with a due date'),
              _Tile('Typical time to finish', median == null ? '–' : _describe(median), 'from adding to ticking off'),
              _Tile('Streak', '${s.streak} day${s.streak == 1 ? '' : 's'}', 'in a row with something done'),
              _Tile('Open now', '${s.openCount}', s.overdueCount == 0 ? 'none overdue' : '${s.overdueCount} overdue'),
            ]),
            const SizedBox(height: 24),
            Text('Done per week', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _Bars(
              values: [for (final (_, n) in s.donePerWeek()) n.toDouble()],
              labels: [for (final (d, _) in s.donePerWeek()) DateFormat('d MMM').format(d)],
              highlightLast: true,
              color: scheme.primary,
            ),
            const SizedBox(height: 24),
            Text('Open tasks over the last 30 days', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _Bars(
              values: [for (final n in s.openTrend()) n.toDouble()],
              labels: [for (var i = 29; i >= 0; i--) i % 7 == 1 ? DateFormat('d MMM').format(s.today.subtract(Duration(days: i))) : ''],
              color: scheme.tertiary,
            ),
            ..._addedCharts(context, s, from),
            ..._sources(context, s, from),
            ..._repeats(context, s, from),
            ..._timing(context, s, from),
            const SizedBox(height: 24),
            Text('By category', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            if (s.byCategory(from).isEmpty) const Text('No categories yet.'),
            for (final (name, d, o) in s.byCategory(from))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(name),
                trailing: Text('$d done · $o open'),
              ),
            const SizedBox(height: 16),
            Text(
              'Counts come from a record of every task ticked off, so they survive the archive clean-up. '
              'History starts from when this version was first used (earlier archived tasks are counted as they are now).',
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
            ),
          ]),
        );
      },
    );
  }

  Widget _heading(BuildContext context, String text, [String? note]) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: Theme.of(context).textTheme.titleMedium),
          if (note != null) Text(note, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
        ]),
      );

  static String _bucketLabel(Bucket b) => switch (b.unit) {
        BucketUnit.day => DateFormat('d MMM').format(b.start),
        BucketUnit.week => DateFormat('d MMM').format(b.start),
        BucketUnit.month => DateFormat('MMM yy').format(b.start),
      };

  /// Item 38: added per day/week, and added vs done with the open line, filtered by category.
  List<Widget> _addedCharts(BuildContext context, Stats s, DateTime? from) {
    final data = widget.store.data;
    if (_chartCategory != null && _chartCategory!.isNotEmpty && data.category(_chartCategory) == null) {
      _chartCategory = null;
    }
    final buckets = s.addedVsDone(from, categoryId: _chartCategory);
    final unit = buckets.isEmpty ? 'day' : buckets.first.unit.name;
    final labels = [
      for (final (i, b) in buckets.indexed)
        buckets.length <= 14 || i % (buckets.length / 6).ceil() == 0 ? _bucketLabel(b) : '',
    ];
    final scheme = Theme.of(context).colorScheme;
    return [
      _heading(context, 'Added per $unit'),
      if (data.categories.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            for (final (key, name) in [(null, 'All'), for (final c in data.categories) (c.id, c.name), ('', 'No category')])
              ChoiceChip(
                label: Text(name),
                visualDensity: VisualDensity.compact,
                selected: _chartCategory == key,
                onSelected: (_) => setState(() => _chartCategory = key),
              ),
          ]),
        ),
      _Bars(values: [for (final b in buckets) b.added.toDouble()], labels: labels, color: scheme.secondary),
      _heading(context, 'Added vs done', 'Bars: added and done each $unit. Line: tasks still open at the end of it.'),
      _PairChart(buckets: buckets, labels: labels, added: scheme.secondary, done: scheme.primary, open: scheme.error),
      const SizedBox(height: 6),
      Wrap(spacing: 16, children: [
        _Key(color: scheme.secondary, text: 'Added'),
        _Key(color: scheme.primary, text: 'Done'),
        _Key(color: scheme.error, text: 'Open', line: true),
      ]),
    ];
  }

  /// Item 30: where tasks came from.
  List<Widget> _sources(BuildContext context, Stats s, DateTime? from) {
    final rows = s.bySource(from);
    return [
      _heading(context, 'By source', 'Added in this period, the share of those now done, and all ticked off in it.'),
      if (rows.isEmpty) const Text('Nothing added in this period.'),
      if (rows.isNotEmpty)
        Table(
          columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(1.3), 2: FlexColumnWidth(1.6), 3: FlexColumnWidth(1.3)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            _row(context, ['Source', 'Added', 'Now done', 'Done'], header: true),
            for (final r in rows)
              _row(context, [
                TaskSource.label(r.source),
                '${r.added}',
                r.share == null ? '–' : '${(r.share! * 100).round()}%',
                '${r.done}',
              ]),
          ],
        ),
    ];
  }

  /// Item 36: each repeating series.
  List<Widget> _repeats(BuildContext context, Stats s, DateTime? from) {
    final rows = s.repeats(from);
    if (rows.isEmpty) return const [];
    return [
      _heading(context, 'Repeating tasks',
          'Missed means a whole repeat went by without a tick. Done share = done / (done + skipped + missed).'),
      Table(
        columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.4), 3: FlexColumnWidth(1.4), 4: FlexColumnWidth(1.2)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          _row(context, ['Task', 'Done', 'Skipped', 'Missed', 'Share'], header: true),
          for (final r in rows)
            _row(context, [r.name ?? '', '${r.done}', '${r.skipped}', '${r.missed}', '${(r.share * 100).round()}%']),
        ],
      ),
    ];
  }

  /// Item 36: early or late against the due date.
  List<Widget> _timing(BuildContext context, Stats s, DateTime? from) {
    final t = s.timing(from);
    final scheme = Theme.of(context).colorScheme;
    if (t.total == 0) {
      return [
        _heading(context, 'Early or late'),
        const Text('No tasks with a due date ticked off in this period since this version.'),
      ];
    }
    final m = t.medianLateMinutes!;
    final typical = m.abs() < 60
        ? 'right on time'
        : '${_describe(Duration(minutes: m.abs()))} ${m < 0 ? 'early' : 'late'}';
    String pct(int n) => '${(n * 100 / t.total).round()}%';
    final max = t.buckets.fold(0, (a, b) => a > b ? a : b);
    return [
      _heading(context, 'Early or late', 'Tasks with a due date, by the day they were ticked off.'),
      Text('Typically $typical. ${pct(t.early)} early, ${pct(t.sameDay)} on the day, ${pct(t.late)} late.'),
      const SizedBox(height: 8),
      for (final (i, n) in t.buckets.indexed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(width: 130, child: Text(Timing.labels[i], style: const TextStyle(fontSize: 13))),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: max == 0 ? 0 : (n / max).clamp(0.02, 1.0),
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: (i < 2 ? scheme.primary : i == 2 ? scheme.secondary : scheme.error).withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: 36, child: Text('$n', textAlign: TextAlign.right)),
          ]),
        ),
    ];
  }

  TableRow _row(BuildContext context, List<String> cells, {bool header = false}) => TableRow(
        decoration: header ? BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor))) : null,
        children: [
          for (final (i, c) in cells.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text(c,
                  textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                  style: header ? const TextStyle(fontWeight: FontWeight.w600, fontSize: 13) : null),
            ),
        ],
      );

  static String _describe(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inHours < 48) return '${d.inHours} hour${d.inHours == 1 ? '' : 's'}';
    if (d.inDays < 14) return '${d.inDays} days';
    return '${(d.inDays / 7).round()} weeks';
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, this.note);

  final String label, value, note;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 160,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              Text(note, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
            ]),
          ),
        ),
      );
}

/// A simple bar chart drawn with plain boxes (no chart library needed).
class _Bars extends StatelessWidget {
  const _Bars({required this.values, required this.labels, required this.color, this.highlightLast = false});

  final List<double> values;
  final List<String> labels;
  final Color color;
  final bool highlightLast;

  @override
  Widget build(BuildContext context) {
    final max = values.fold(0.0, (a, b) => a > b ? a : b);
    return SizedBox(
      height: 140,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final (i, v) in values.indexed)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (max > 0 && (values.length <= 14 || v == max))
                  Text('${v.round()}', style: const TextStyle(fontSize: 10)),
                Tooltip(
                  message: '${labels[i].isEmpty ? '' : '${labels[i]}: '}${v.round()}',
                  child: Container(
                    height: max == 0 ? 2 : 2 + 100 * v / max,
                    decoration: BoxDecoration(
                      color: highlightLast && i == values.length - 1 ? color : color.withValues(alpha: 0.55),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                  ),
                ),
                SizedBox(
                  height: 14,
                  child: values.length <= 14 || labels[i].isNotEmpty
                      ? FittedBox(child: Text(labels[i], style: const TextStyle(fontSize: 9)))
                      : null,
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.text, this.line = false});

  final Color color;
  final String text;
  final bool line;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: line ? 3 : 10, color: color),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12)),
      ]);
}

/// Paired bars (added, done) per day/week/month with a line for how many were open.
class _PairChart extends StatelessWidget {
  const _PairChart({required this.buckets, required this.labels, required this.added, required this.done, required this.open});

  final List<Bucket> buckets;
  final List<String> labels;
  final Color added, done, open;

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return Column(children: [
      SizedBox(
        height: 150,
        width: double.infinity,
        child: CustomPaint(painter: _PairPainter(buckets, added, done, open, hint)),
      ),
      SizedBox(
        height: 14,
        child: Row(children: [
          for (final l in labels)
            Expanded(child: l.isEmpty ? const SizedBox() : FittedBox(child: Text(l, style: const TextStyle(fontSize: 9)))),
        ]),
      ),
    ]);
  }
}

class _PairPainter extends CustomPainter {
  _PairPainter(this.buckets, this.added, this.done, this.open, this.hint);

  final List<Bucket> buckets;
  final Color added, done, open, hint;

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) return;
    final top = 14.0;
    final h = size.height - top;
    final maxBar = buckets.fold<int>(1, (m, b) => [m, b.added, b.done].reduce((x, y) => x > y ? x : y));
    final maxOpen = buckets.fold<int>(1, (m, b) => b.open > m ? b.open : m);
    final w = size.width / buckets.length;
    final bar = (w * 0.38).clamp(1.0, 14.0);
    final pa = Paint()..color = added.withValues(alpha: 0.75);
    final pd = Paint()..color = done.withValues(alpha: 0.85);
    for (final (i, b) in buckets.indexed) {
      final cx = w * i + w / 2;
      final ha = h * b.added / maxBar, hd = h * b.done / maxBar;
      canvas.drawRect(Rect.fromLTWH(cx - bar - 0.5, size.height - ha, bar, ha), pa);
      canvas.drawRect(Rect.fromLTWH(cx + 0.5, size.height - hd, bar, hd), pd);
    }
    // The open line uses its own scale (labelled at its highest point).
    final path = Path();
    Offset? peak;
    for (final (i, b) in buckets.indexed) {
      final p = Offset(w * i + w / 2, size.height - h * b.open / maxOpen);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      if (b.open == maxOpen) peak ??= p;
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = open
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    if (peak != null) {
      final tp = TextPainter(
        text: TextSpan(text: '$maxOpen open', style: TextStyle(fontSize: 10, color: open)),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = (peak.dx - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(x, peak.dy - tp.height - 1));
    }
    final tb = TextPainter(
      text: TextSpan(text: 'max $maxBar', style: TextStyle(fontSize: 10, color: hint)),
      textDirection: TextDirection.ltr,
    )..layout();
    tb.paint(canvas, Offset(size.width - tb.width, 0));
  }

  @override
  bool shouldRepaint(_PairPainter old) => true;
}

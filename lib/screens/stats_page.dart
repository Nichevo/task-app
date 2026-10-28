import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

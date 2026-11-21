import 'dart:math';

import 'gantt.dart' show takesHours;
import 'models.dart';

/// Item 114 B: estimates against how long things really took.

/// A task's estimate in minutes: its "How long", else a length given in hours under Takes.
int? estimateOf(Task t, AppData data) => t.estimate ?? takesHours(t.takesDays, t.takesMinutes, data);

/// The time the app recorded on [t]: focus timer minutes or its ticked Day plan blocks, whichever
/// is more (a block usually has the timer running in it, so they aren't added up).
int recordedMinutes(Task t) {
  final focus = t.focus.values.fold(0, (a, b) => a + b);
  final planned = t.slots.where((s) => s.doneAt != null).fold(0, (a, s) => a + s.minutes);
  return max(focus, planned);
}

/// How many finished tasks with both times it takes before planning allows for them.
const enoughToLearn = 10;

/// Within a category, how many it takes before that category's own figure is used.
const enoughInCategory = 5;

class EstimateMiss {
  const EstimateMiss(this.title, this.est, this.act);
  final String title;
  final int est, act;
}

class EstimateStats {
  EstimateStats({
    required this.count,
    required this.ratio,
    required this.byCategory,
    required this.misses,
  });

  /// Finished tasks with both an estimate and an actual time.
  final int count;

  /// Actual over estimated, all together (1.4 = 40% longer than guessed); null with none.
  final double? ratio;

  /// (category id, its ratio, how many).
  final List<(String?, double, int)> byCategory;

  /// The furthest over, worst first.
  final List<EstimateMiss> misses;
}

EstimateStats estimateStats(AppData data, DateTime now, {int days = 60}) {
  final from = now.subtract(Duration(days: days));
  final recs = [
    for (final r in data.done.values)
      if (r.at.isAfter(from) && (r.estMinutes ?? 0) > 0 && (r.actMinutes ?? 0) > 0) r,
  ];
  double? ratioOf(Iterable<DoneRecord> rs) {
    final est = rs.fold(0, (a, r) => a + r.estMinutes!);
    final act = rs.fold(0, (a, r) => a + r.actMinutes!);
    return est == 0 ? null : act / est;
  }

  final byCat = <String?, List<DoneRecord>>{};
  for (final r in recs) {
    (byCat[r.categoryId] ??= []).add(r);
  }
  final cats = [
    for (final e in byCat.entries) (e.key, ratioOf(e.value)!, e.value.length),
  ]..sort((a, b) => b.$3.compareTo(a.$3));
  final misses = [
    for (final r in recs)
      if (r.actMinutes! > r.estMinutes!) EstimateMiss(r.title ?? 'A task', r.estMinutes!, r.actMinutes!),
  ]..sort((a, b) => (b.act - b.est).compareTo(a.act - a.est));
  return EstimateStats(count: recs.length, ratio: ratioOf(recs), byCategory: cats, misses: misses.take(3).toList());
}

/// How much to stretch an estimate in [categoryId] when planning: that category's ratio once it
/// has [enoughInCategory] tasks, else the overall one once there are [enoughToLearn]; 1 until
/// then, or when Settings says not to. Kept between half and three times.
double estimateFactor(AppData data, String? categoryId, DateTime now) {
  if (!data.helperOn(Helper.learnEstimates) || !data.allowForEstimates) return 1;
  final s = estimateStats(data, now);
  if (s.count < enoughToLearn || s.ratio == null) return 1;
  final cat = s.byCategory.where((c) => c.$1 == categoryId && c.$3 >= enoughInCategory).firstOrNull;
  return (cat?.$2 ?? s.ratio!).clamp(0.5, 3.0);
}

/// "1.4×".
String describeRatio(double r) => '${r.toStringAsFixed(1)}×';

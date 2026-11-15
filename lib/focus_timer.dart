import 'models.dart';

/// Item 102, part 4: the focus timer. One task (or one of its steps) at a time: a focus round
/// (25 minutes), then a short break (5), with a long break (15) after every fourth round. Kept on
/// this device only; the minutes are saved on the task ([Task.focus]) and sync with it.
enum FocusPhase {
  focus('Focus'),
  shortBreak('Short break'),
  longBreak('Long break');

  const FocusPhase(this.label);
  final String label;

  bool get isBreak => this != focus;
}

class FocusTimer {
  FocusTimer({
    required this.taskId,
    this.stepId,
    this.phase = FocusPhase.focus,
    this.round = 1,
    required this.length,
    this.end,
    this.left,
    this.runFrom,
    this.carry = 0,
    this.heldBreak = false,
  });

  String taskId;

  /// The step this session is on, if any.
  String? stepId;
  FocusPhase phase;

  /// Which focus round (1, 2, ...); the long break comes after every [FocusSettings.every]th.
  int round;

  /// How long this phase is in all (grows with +5 min).
  Duration length;

  /// When the phase ends, while it runs; null while paused or waiting to start.
  DateTime? end;

  /// Time left while paused (or before the round starts).
  Duration? left;

  /// When focus time started counting towards the task (start or resume of a focus round).
  DateTime? runFrom;

  /// Seconds focused not yet saved as a whole minute.
  int carry;

  /// Waiting to start the next round after a break (or the first round).
  bool heldBreak;

  bool get running => end != null;
  bool get paused => end == null;

  Duration remaining(DateTime now) {
    final e = end;
    if (e == null) return left ?? length;
    final r = e.difference(now);
    return r.isNegative ? Duration.zero : r;
  }

  /// How far through the phase, 0 to 1.
  double progress(DateTime now) {
    final total = length.inMilliseconds;
    if (total <= 0) return 1;
    return (1 - remaining(now).inMilliseconds / total).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'task': taskId,
        if (stepId != null) 'step': stepId,
        'phase': phase.name,
        'round': round,
        'length': length.inSeconds,
        if (end != null) 'end': end!.toUtc().toIso8601String(),
        if (left != null) 'left': left!.inSeconds,
        if (runFrom != null) 'runFrom': runFrom!.toUtc().toIso8601String(),
        if (carry != 0) 'carry': carry,
        if (heldBreak) 'ready': true,
      };

  static FocusTimer? tryParse(Object? j) {
    if (j is! Map || j['task'] is! String) return null;
    DateTime? d(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
    return FocusTimer(
      taskId: j['task'] as String,
      stepId: j['step'] as String?,
      phase: FocusPhase.values.where((p) => p.name == j['phase']).firstOrNull ?? FocusPhase.focus,
      round: (j['round'] as num?)?.toInt() ?? 1,
      length: Duration(seconds: (j['length'] as num?)?.toInt() ?? 1500),
      end: d(j['end']),
      left: j['left'] is num ? Duration(seconds: (j['left'] as num).toInt()) : null,
      runFrom: d(j['runFrom']),
      carry: (j['carry'] as num?)?.toInt() ?? 0,
      heldBreak: j['ready'] == true,
    );
  }
}

/// The timer's lengths (minutes) and whether Do not disturb goes on while focusing. Synced.
class FocusSettings {
  FocusSettings({this.focus = 25, this.shortBreak = 5, this.longBreak = 15, this.every = 4, this.dnd = false});

  int focus;
  int shortBreak;
  int longBreak;
  int every;

  /// Turn on Do not disturb during focus rounds (Android; asks for access the first time).
  bool dnd;

  Duration lengthOf(FocusPhase p) => Duration(
      minutes: switch (p) {
        FocusPhase.focus => focus,
        FocusPhase.shortBreak => shortBreak,
        FocusPhase.longBreak => longBreak,
      });

  bool get isDefault => focus == 25 && shortBreak == 5 && longBreak == 15 && every == 4 && !dnd;

  Map<String, dynamic> toJson() =>
      {'focus': focus, 'short': shortBreak, 'long': longBreak, 'every': every, if (dnd) 'dnd': true};

  static FocusSettings parse(Object? j) {
    if (j is! Map) return FocusSettings();
    int n(String k, int d) => ((j[k] as num?)?.toInt() ?? d).clamp(1, 240);
    return FocusSettings(
      focus: n('focus', 25),
      shortBreak: n('short', 5),
      longBreak: n('long', 15),
      every: n('every', 4).clamp(1, 12),
      dnd: j['dnd'] == true,
    );
  }
}

/// The timer running on this device, if any (set by [AppStore]; read by the reminders, the
/// widgets and the screens, like [modeNow]).
FocusTimer? focusNow;

/// Minutes focused on [t] on [day].
int focusOn(Task t, DateTime day) => t.focus[dayKey(day)] ?? 0;

/// Minutes focused on [t] in all.
int focusTotal(Task t) => t.focus.values.fold(0, (a, b) => a + b);

/// "1 h 10" or "25 min".
String focusText(int minutes) => minutes < 60
    ? '$minutes min'
    : minutes % 60 == 0
        ? '${minutes ~/ 60} h'
        : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';

/// "15:48": minutes and seconds left.
String clockText(Duration d) {
  final s = d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  return h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}'
      : '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

/// Focus minutes per day key across [tasks] (open and finished).
Map<String, int> focusByDay(Iterable<Task> tasks) {
  final out = <String, int>{};
  for (final t in tasks) {
    t.focus.forEach((k, v) => out[k] = (out[k] ?? 0) + v);
  }
  return out;
}

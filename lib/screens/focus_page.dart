import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../focus_timer.dart';
import '../models.dart';
import '../modes.dart';
import '../native.dart';
import '../reminders.dart';
import '../store.dart';
import '../widgets/mode_chip.dart';
import '../widgets/task_colors.dart';

const _bg = Color(0xFF0F2E2E);
const _panel = Color(0xFF183B3B);
const _ring = Color(0xFF8FE05A);
const _breakRing = Color(0xFF7CC6F2);
const _soft = Color(0xFF9FD3CC);

/// Item 102, part 4: the full-screen focus timer on one task (and one of its steps).
class FocusPage extends StatefulWidget {
  const FocusPage({super.key, required this.store});

  final AppStore store;

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  late final Timer _tick;

  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!store.tickFocus()) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final f = focusNow;
        final t = f == null ? null : store.data.task(f.taskId);
        return Theme(
          data: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: _ring, brightness: Brightness.dark)),
          child: Scaffold(
            backgroundColor: _bg,
            appBar: AppBar(
              backgroundColor: _bg,
              foregroundColor: Colors.white,
              leading: IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              title: Row(children: [
                const Text('Focus'),
                if (modeNow.mode case final m?) ...[
                  const SizedBox(width: 10),
                  Flexible(child: _ModePill(mode: m, onTap: () => showModeSheet(context, store))),
                ],
              ]),
              actions: [
                IconButton(
                  tooltip: 'Timer settings',
                  icon: const Icon(Icons.tune),
                  onPressed: () => showFocusSettings(context, store),
                ),
              ],
            ),
            body: f == null || t == null ? _done(context) : _running(context, f, t),
          ),
        );
      },
    );
  }

  Widget _done(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.timer_outlined, size: 56, color: _soft),
            const SizedBox(height: 12),
            const Text('No focus session running.', style: TextStyle(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 6),
            const Text('Start one from a task (the timer button at the top of its page) or a block on the Day plan.',
                textAlign: TextAlign.center, style: TextStyle(color: _soft)),
            const SizedBox(height: 18),
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Pick a task'),
              onPressed: () => pickFocusTask(context, store, open: false),
            ),
          ]),
        ),
      );

  Widget _running(BuildContext context, FocusTimer f, Task t) {
    final now = DateTime.now();
    final s = focusLengthsNow(store.data);
    final left = f.remaining(now);
    final onBreak = f.phase.isBreak;
    final hm = DateFormat('HH:mm');
    final top = onBreak
        ? '${f.phase.label} · then round ${f.round + 1}'
        : f.heldBreak
            ? 'Ready for round ${f.round}'
            : 'Round ${f.round} of ${s.every} · long break after ${s.every}';
    final under = f.running
        ? 'of ${f.length.inMinutes} min · ends ${hm.format(f.end!)}'
        : f.heldBreak
            ? '${f.length.inMinutes} min round'
            : 'paused · ${f.length.inMinutes} min';
    final today = focusOn(t, now);
    final step = f.stepId == null ? null : t.steps.where((x) => x.id == f.stepId).firstOrNull;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Center(child: Text(top, style: const TextStyle(color: _soft, fontSize: 15))),
      const SizedBox(height: 16),
      Center(
        child: SizedBox.square(
          dimension: 250,
          child: CustomPaint(
            painter: _RingPainter(f.progress(now), onBreak ? _breakRing : _ring),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(clockText(left),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 60, fontWeight: FontWeight.w300, fontFeatures: [FontFeature.tabularFigures()])),
                Text(under, style: const TextStyle(color: _soft, fontSize: 14)),
              ]),
            ),
          ),
        ),
      ),
      const SizedBox(height: 18),
      Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 8, children: [
        if (f.heldBreak)
          _button(Icons.play_arrow, 'Start round ${f.round}', store.resumeFocus, filled: true)
        else if (f.running)
          _button(Icons.pause, 'Pause', store.pauseFocus)
        else
          _button(Icons.play_arrow, 'Resume', store.resumeFocus, filled: true),
        if (onBreak) _button(Icons.skip_next, 'Skip break', store.skipBreak),
        if (!f.heldBreak) _button(null, '+5 min', store.addFocusTime),
        _button(Icons.stop, 'Stop', () {
          store.stopFocus();
          Navigator.pop(context);
        }),
      ]),
      const SizedBox(height: 18),
      Material(
        color: ageColor(t, store.data.hoursToRed, byDue: store.data.colourByDue, now: now),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.title, style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.w600)),
                Text(
                  [
                    if (today > 0) 'focused ${focusText(today)} today',
                    if (t.estimate != null) '${focusText(focusTotal(t))} of about ${focusText(t.estimate!)}',
                    if (today == 0 && t.estimate == null) 'nothing focused yet today',
                  ].join(' · '),
                  style: const TextStyle(color: Colors.black54),
                ),
              ]),
            ),
            IconButton(
              tooltip: 'Done: tick it off',
              icon: const Icon(Icons.check_box_outline_blank, color: Colors.black54),
              onPressed: () {
                store.stopFocus();
                store.complete(t);
                Navigator.pop(context);
              },
            ),
          ]),
        ),
      ),
      if (t.steps.isNotEmpty) ...[
        const SizedBox(height: 10),
        Material(
          color: _panel,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Text('Steps · tap one to make it this session\'s', style: TextStyle(color: _soft)),
            ),
            for (final st in t.steps)
              ListTile(
                dense: true,
                leading: Checkbox(value: st.done, onChanged: (_) => store.toggleStep(t, st)),
                title: Text(
                  st.id == step?.id ? '${st.title}  ← this session' : st.title,
                  style: TextStyle(
                    color: st.done ? Colors.white54 : Colors.white,
                    fontWeight: st.id == step?.id ? FontWeight.w700 : FontWeight.w400,
                    decoration: st.done ? TextDecoration.lineThrough : null,
                  ),
                ),
                onTap: () => store.setFocusStep(st.id == f.stepId ? null : st.id),
              ),
          ]),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: _soft.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Expanded(
            child: Text(
              onBreak || !f.running
                  ? 'Reminders come as usual on a break'
                  : 'Reminders held till the break${Reminders.heldForFocus > 0 ? ' · ${Reminders.heldForFocus} waiting' : ''}',
              style: const TextStyle(color: _soft),
            ),
          ),
          if (Native.dndSupported)
            Text(s.dnd ? 'Do not disturb on' : 'Do not disturb off',
                style: TextStyle(color: s.dnd ? _ring : _soft.withValues(alpha: 0.7))),
        ]),
      ),
    ]);
  }

  Widget _button(IconData? icon, String label, VoidCallback onTap, {bool filled = false}) {
    final style = FilledButton.styleFrom(
      backgroundColor: filled ? _ring : const Color(0xFF244F4F),
      foregroundColor: filled ? Colors.black : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      textStyle: const TextStyle(fontSize: 16),
    );
    return icon == null
        ? FilledButton(style: style, onPressed: onTap, child: Text(label))
        : FilledButton.icon(style: style, onPressed: onTap, icon: Icon(icon), label: Text(label));
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({required this.mode, required this.onTap});

  final FocusMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Color(mode.colour),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.circle, size: 8, color: Colors.white),
              const SizedBox(width: 6),
              Flexible(
                child: Text(mode.name,
                    overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15)),
              ),
            ]),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.colour);

  final double progress;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 10;
    final track = Paint()
      ..color = const Color(0xFF214545)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14;
    canvas.drawCircle(c, r, track);
    // What is left of the phase, counting down clockwise from the top.
    final left = 1 - progress;
    if (left <= 0) return;
    final arc = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 14;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -pi / 2, 2 * pi * left, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.colour != colour;
}

/// Starts the timer on [t] (or [stepId]) and opens the Focus screen.
void startFocusOn(BuildContext context, AppStore store, Task t, {String? stepId}) {
  store.startFocus(t, stepId: stepId);
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => FocusPage(store: store)));
}

/// Opens the Focus screen (the running timer, or a prompt to pick a task).
void openFocus(BuildContext context, AppStore store) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FocusPage(store: store)));

/// A list of the tasks the mode shows, to pick one to focus on.
Future<void> pickFocusTask(BuildContext context, AppStore store, {bool open = true}) async {
  final now = DateTime.now();
  final tasks = store.data.active.where((t) => !t.habit && store.data.inMode(t) && !t.isSnoozed(now)).toList();
  final t = await showModalBottomSheet<Task>(
    context: context,
    showDragHandle: true,
    builder: (c) => ListView(children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text('Focus on', style: TextStyle(fontSize: 20)),
      ),
      for (final t in tasks)
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: Text(t.title),
          subtitle: focusOn(t, now) > 0 ? Text('${focusText(focusOn(t, now))} today') : null,
          onTap: () => Navigator.pop(c, t),
        ),
    ]),
  );
  if (t == null || !context.mounted) return;
  store.startFocus(t);
  if (open) openFocus(context, store);
}

/// The timer's lengths and Do not disturb. Item 108: a focus mode can have lengths of its own
/// (Work 50/10, Home 25/5); the sheet starts on the mode in force.
Future<void> showFocusSettings(BuildContext context, AppStore store) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => FocusSettingsSheet(store: store),
    );

class FocusSettingsSheet extends StatefulWidget {
  const FocusSettingsSheet({super.key, required this.store});

  final AppStore store;

  @override
  State<FocusSettingsSheet> createState() => _FocusSettingsSheetState();
}

class _FocusSettingsSheetState extends State<FocusSettingsSheet> {
  AppStore get store => widget.store;

  /// Whose lengths are shown: null = every mode, else a mode's id.
  late String? _for = modeNow.mode?.timer != null ? modeNow.mode!.id : null;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (c, _) {
          final data = store.data;
          final mode = _for == null ? null : data.mode(_for!);
          final own = mode?.timer;
          final s = own ?? data.focusSettings;
          void set(VoidCallback f) {
            f();
            mode != null ? store.modeChanged() : store.changed(settings: true);
          }

          Widget row(String label, int value, int min, int max, ValueChanged<int> on, {String unit = 'min'}) => ListTile(
                enabled: mode == null || own != null,
                title: Text(label),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: value > min && (mode == null || own != null) ? () => set(() => on(value - 1)) : null),
                  SizedBox(width: 64, child: Text('$value $unit', textAlign: TextAlign.center)),
                  IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: value < max && (mode == null || own != null) ? () => set(() => on(value + 1)) : null),
                ]),
              );
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Focus timer', style: TextStyle(fontSize: 20)),
                if (data.modes.isNotEmpty)
                  ListTile(
                    title: const Text('Round lengths for'),
                    trailing: DropdownButton<String?>(
                      value: mode?.id,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Every mode')),
                        for (final m in data.modes)
                          DropdownMenuItem(value: m.id, child: Text(m.timer == null ? m.name : '${m.name} (own)')),
                      ],
                      onChanged: (v) => setState(() => _for = v),
                    ),
                  ),
                if (mode != null)
                  SwitchListTile(
                    title: Text('Own lengths in ${mode.name}'),
                    subtitle: Text(own == null
                        ? 'Off: ${mode.name} uses the lengths for every mode'
                        : 'The timer uses these while ${mode.name} is on, from the next round or break'),
                    value: own != null,
                    onChanged: (v) => set(() => mode.timer = v
                        ? FocusSettings(
                            focus: data.focusSettings.focus,
                            shortBreak: data.focusSettings.shortBreak,
                            longBreak: data.focusSettings.longBreak,
                            every: data.focusSettings.every)
                        : null),
                  ),
                row('Focus round', s.focus, 5, 120, (v) => s.focus = v),
                row('Short break', s.shortBreak, 1, 30, (v) => s.shortBreak = v),
                row('Long break', s.longBreak, 5, 60, (v) => s.longBreak = v),
                row('Long break after', s.every, 2, 8, (v) => s.every = v, unit: 'rounds'),
                if (Native.dndSupported)
                  SwitchListTile(
                    title: const Text('Do not disturb while focusing'),
                    subtitle: const Text('Turns on in each round and off for breaks. Android asks you to allow it the first time.'),
                    value: data.focusSettings.dnd,
                    onChanged: (v) async {
                      if (v && !await Native.dndAllowed()) {
                        await Native.askDnd();
                      }
                      set(() => data.focusSettings.dnd = v);
                    },
                  ),
                const SizedBox(height: 8),
              ]),
            ),
          );
        },
      );
}

/// Item 102: the countdown beside the mode chip while the timer runs; tapping opens the timer.
class FocusCountdown extends StatefulWidget {
  const FocusCountdown({super.key, required this.store});

  final AppStore store;

  @override
  State<FocusCountdown> createState() => _FocusCountdownState();
}

class _FocusCountdownState extends State<FocusCountdown> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !widget.store.tickFocus()) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = focusNow;
    if (f == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final colour = f.phase.isBreak ? const Color(0xFF2B7FB0) : const Color(0xFF2E7D32);
    return Material(
      color: f.running ? colour : colour.withValues(alpha: 0.5),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => openFocus(context, widget.store),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(f.phase.isBreak ? Icons.free_breakfast_outlined : Icons.timer_outlined, size: 16, color: Colors.white),
            const SizedBox(width: 4),
            Text(f.heldBreak ? 'Next' : clockText(f.remaining(now)),
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
          ]),
        ),
      ),
    );
  }
}

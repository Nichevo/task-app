import 'package:flutter/material.dart';

import '../auto_plan.dart';
import '../day_plan.dart' show describeLength;
import '../models.dart';
import '../modes.dart';
import '../native.dart';
import '../store.dart';
import 'task_colors.dart';

/// Item 114 C: "What should I do now?" One pick that fits the time to the next fixed thing, the
/// focus mode and where the phone is, with Start focus, Open and Something else.
Future<void> showWhatNow(
  BuildContext context,
  AppStore store, {
  required void Function(Task t, TaskStep? step) onFocus,
  required void Function(Task t) onOpen,
}) async {
  final data = store.data;
  final now = DateTime.now();
  var events = const <CalendarEvent>[];
  if (Native.supported && data.dayPlan.showEvents) {
    try {
      events = await Native.events(DateTime(now.year, now.month, now.day), now.add(const Duration(days: 1)), data.eventCalendars);
    } catch (_) {
      // No calendar access: work meetings and planned times still count.
    }
  }
  final place = data.nowUsesPlace ? await store.placeHere() : null;
  if (!context.mounted) return;
  final advice = whatNow(data, now, events: events, place: place);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => _WhatNowSheet(store: store, advice: advice, place: place, onFocus: onFocus, onOpen: onOpen),
  );
}

class _WhatNowSheet extends StatefulWidget {
  const _WhatNowSheet({required this.store, required this.advice, this.place, required this.onFocus, required this.onOpen});

  final AppStore store;
  final NowAdvice advice;
  final String? place;
  final void Function(Task t, TaskStep? step) onFocus;
  final void Function(Task t) onOpen;

  @override
  State<_WhatNowSheet> createState() => _WhatNowSheetState();
}

class _WhatNowSheetState extends State<_WhatNowSheet> {
  int _first = 0;

  @override
  Widget build(BuildContext context) {
    final a = widget.advice;
    final picks = a.picks;
    final theme = Theme.of(context);
    final hint = TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13.5);
    final mode = modeNow.mode;
    final context0 = [
      if (a.freeMinutes != null) 'You have ${describeLength(a.freeMinutes!)} before ${a.until}' else 'Nothing else fixed today',
      if (mode != null) '${mode.name} mode',
      if (widget.place != null) 'at ${widget.place}',
    ].join(' · ');
    if (picks.isEmpty) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Text('Nothing open to suggest right now. $context0.', style: hint),
        ),
      );
    }
    final best = picks[_first % picks.length];
    final rest = [for (var i = 1; i < picks.length; i++) picks[(_first + i) % picks.length]];
    final colour = ageColor(best.task, widget.store.data.hoursToRed, byDue: widget.store.data.colourByDue);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(context0, style: hint),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(best.step == null ? best.task.title : best.task.title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xDD000000))),
              Text(
                [
                  if (best.step != null) '${best.stepLabel}: ${best.step!.title}',
                  'about ${describeLength(best.minutes)}',
                ].join(' · '),
                style: const TextStyle(fontSize: 13.5, color: Color(0xAA000000)),
              ),
              if (best.why.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final w in best.why.take(4))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(6)),
                      child: Text(w, style: const TextStyle(fontSize: 12, color: Color(0xDD000000))),
                    ),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start focus'),
              onPressed: () {
                Navigator.pop(context);
                widget.onFocus(best.task, best.step);
              },
            ),
            OutlinedButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onOpen(best.task);
              },
              child: const Text('Open'),
            ),
            if (picks.length > 1)
              TextButton(onPressed: () => setState(() => _first++), child: const Text('Something else')),
          ]),
          if (rest.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Also good right now', style: theme.textTheme.titleSmall),
            for (final p in rest)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 8,
                  backgroundColor: ageColor(p.task, widget.store.data.hoursToRed, byDue: widget.store.data.colourByDue),
                ),
                title: Text(p.step == null ? p.task.title : '${p.task.title}: ${p.step!.title}'),
                subtitle: Text([describeLength(p.minutes), ...p.why.take(2)].join(' · ')),
                onTap: () => setState(() => _first = picks.indexOf(p)),
              ),
          ],
        ]),
      ),
    );
  }
}

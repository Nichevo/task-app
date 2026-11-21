import 'package:flutter/material.dart';

import '../estimates.dart';
import '../models.dart';
import '../screens/settings_page.dart' show askText;
import '../store.dart';
import '../task_list.dart';

/// Item 114 B: "How long did it really take?" after ticking off a task with an estimate. The
/// recorded time (focus timer, ticked Day plan blocks) is picked already, so one tap saves it.
Future<void> askActualTime(BuildContext context, AppStore store, Task t) async {
  final est = estimateOf(t, store.data);
  if (est == null) return;
  final recorded = recordedMinutes(t);
  int round5(double m) => max5((m / 5).round() * 5);
  final options = <int>{round5(est / 2), est, round5(est * 1.5), est * 2, if (recorded > 0) recorded}.toList()..sort();
  var picked = recorded > 0 ? recorded : est;
  final saved = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('✓ ${t.title}', style: Theme.of(c).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  recorded > 0
                      ? 'You guessed ${describeMinutes(est)}. The timer and Day plan say about ${describeMinutes(recorded)}. '
                            'How long did it really take?'
                      : 'You guessed ${describeMinutes(est)}. How long did it really take?',
                  style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in options)
                      ChoiceChip(
                        label: Text(describeMinutes(m)),
                        selected: picked == m,
                        onSelected: (_) => setState(() => picked = m),
                      ),
                    ActionChip(
                      label: const Text('Other…'),
                      onPressed: () async {
                        final typed = await askText(c, 'Minutes (or e.g. 1.5h)', initial: '$picked');
                        final m = parseEstimate(typed ?? '');
                        if (m != null && c.mounted) Navigator.pop(c, m);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton(onPressed: () => Navigator.pop(c, picked), child: const Text('Save')),
                    const SizedBox(width: 8),
                    TextButton(onPressed: () => Navigator.pop(c), child: const Text('Skip')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  if (saved != null && saved > 0) store.setActual(t, saved);
}

int max5(int m) => m < 5 ? 5 : m;

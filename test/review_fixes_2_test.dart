import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/focus_timer.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/modes.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/tags.dart';

AppData rt(AppData d) => AppData.fromJson(jsonDecode(jsonEncode(d.toJson())));

/// Fixes from the second whole-app review (1.12.12).
void main() {
  tearDown(() {
    focusNow = null;
    modeDevice = null;
  });

  group('focus timer widget buttons', () {
    test('a pause pressed before the app moved the timer on applies at its own time', () {
      final s = AppStore();
      final t = s.addTask('Write');
      final t0 = DateTime(2026, 11, 16, 10);
      s.startFocus(t, at: t0);
      // The app opens at 10:40 and moves the timer on first (round over, break over).
      s.tickFocus(t0.add(const Duration(minutes: 40)));
      expect(focusOn(t, t0), 25);
      // Then it reads the pause pressed on the widget at 10:05.
      s.applyFocusOps([(op: 'pause', at: t0.add(const Duration(minutes: 5)), task: null, step: null)]);
      expect(focusOn(t, t0), 5);
      expect(focusNow!.phase, FocusPhase.focus);
      expect(focusNow!.round, 1);
      expect(focusNow!.running, isFalse);
      expect(focusNow!.remaining(t0), const Duration(minutes: 20));
    });

    test('a press made in the app after the timer moved on is not undone', () {
      final s = AppStore();
      final t = s.addTask('Write');
      final t0 = DateTime(2026, 11, 16, 10);
      s.startFocus(t, at: t0);
      s.tickFocus(t0.add(const Duration(minutes: 26)));
      s.pauseFocus(at: t0.add(const Duration(minutes: 27)));
      s.applyFocusOps([(op: 'stop', at: t0.add(const Duration(minutes: 5)), task: null, step: null)]);
      expect(focusOn(t, t0), 25);
      expect(focusNow, isNull);
    });
  });

  test('the tag filter is worked out once per change and still follows renames', () {
    final s = AppStore();
    final a = s.addTask('a'), b = s.addTask('b');
    s.addTag(a, 'coding');
    s.addTag(b, 'meeting');
    s.setTagFilter(['coding']);
    final f1 = s.liveTagFilter;
    expect(identical(f1, s.liveTagFilter), isTrue);
    expect(
      [
        for (final t in s.data.active)
          if (passesTagFilter(t, f1)) t.title,
      ],
      ['a'],
    );
    s.deleteTag('coding');
    expect(s.liveTagFilter, isEmpty);
    expect(s.tagKeysInUse, {'meeting'});
  });

  group('mode history with two devices', () {
    test('each device keeps its own stretch, so syncing does not keep splitting them', () {
      final a = AppStore()..deviceKey = 'phone';
      final work = FocusMode.create('Work');
      a.addMode(work);
      final b = AppStore()..deviceKey = 'ipad';
      b.data = rt(a.data);
      a.chooseMode(work.id);
      b.chooseMode(everythingId);
      for (var i = 0; i < 10; i++) {
        a.data = mergeData(a.data, rt(b.data));
        a.refreshMode();
        b.data = mergeData(b.data, rt(a.data));
        b.refreshMode();
      }
      final open = a.data.modeLog.where((l) => l.end == null).toList();
      expect(open.map((l) => l.device).toSet(), {'phone', 'ipad'});
      expect(a.data.modeLog.length, lessThanOrEqualTo(4));
    });

    test('statistics count this device only (and logs from before devices were named)', () {
      final s = AppStore();
      final work = FocusMode.create('Work');
      s.addMode(work);
      final day = DateTime(2026, 11, 16);
      s.data.modeLog
        ..clear()
        ..addAll([
          ModeLog(
            id: '1',
            mode: work.id,
            start: day.add(const Duration(hours: 9)),
            end: day.add(const Duration(hours: 10)),
            device: 'phone',
          ),
          ModeLog(
            id: '2',
            mode: work.id,
            start: day.add(const Duration(hours: 13)),
            end: day.add(const Duration(hours: 14)),
            device: 'ipad',
          ),
          ModeLog(
            id: '3',
            mode: work.id,
            start: day.add(const Duration(hours: 11)),
            end: day.add(const Duration(hours: 12)),
          ),
        ]);
      modeDevice = 'phone';
      final st = modeStats(s.data, day.add(const Duration(hours: 15)), since: day);
      expect(st.minutes[work.id], 120);
      expect(rt(s.data).modeLog.first.device, 'phone');
    });
  });

  test('finishing a step on the board ticks the steps linked to it', () {
    final s = AppStore();
    final a = s.addTask('House'), b = s.addTask('Garden');
    final pay = s.addStep(a, 'Pay');
    final fence = s.addStep(b, 'Fence paid');
    s.linkStepToStep(b, fence, pay);
    s.setOnBoard(a, true, stage: s.data.stage('next'));
    s.setStepsOnBoard(a, true);
    s.moveStepToStage(a, pay, s.data.stages.last, how: MoveHow.menu);
    expect(pay.done, isTrue);
    expect(fence.done, isTrue);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/screens/weekly_review_page.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/weekly_review.dart';
import 'package:task_blocks/work_meetings.dart';

/// Item 114 E: the weekly review screen.
void main() {
  // A Sunday a month ahead, so everything added now is old by then.
  final sun = () {
    final n = DateTime.now();
    final d = DateTime(n.year, n.month, n.day + 30);
    return DateTime(d.year, d.month, d.day + (DateTime.sunday - d.weekday + 7) % 7, 18);
  }();
  final mon = DateTime(sun.year, sun.month, sun.day + 1);

  AppStore build() {
    final s = AppStore();
    s.addTask('Send Q4 numbers').dueAt = sun.subtract(const Duration(days: 5));
    s.addTask('Fix gate latch').dueAt = sun.subtract(const Duration(days: 1));
    s.addTask('Order printer ink');
    final t = s.addTask('Tender')..dueAt = mon.add(const Duration(days: 4, hours: 17));
    s.addStep(t, 'Pricing');
    s.addTask('Report').estimate = 600;
    s.data.active.last.dueAt = DateTime(mon.year, mon.month, mon.day + 1, 17);
    s.data.workMeetings.add(WorkMeeting(title: 'Stand-up', start: mon.add(const Duration(hours: 9)), end: mon.add(const Duration(hours: 9, minutes: 30))));
    return s;
  }

  test('the piles', () {
    final s = build();
    expect(slipped(s.data, sun).map((t) => t.title), ['Send Q4 numbers', 'Fix gate latch']);
    expect(ageing(s.data, sun).map((t) => t.title), ['Order printer ink']);
    expect(stalled(s.data, sun).map((t) => t.title), ['Tender']);
    expect(nextWeekStart(sun), mon);
    final week = nextWeek(s.data, sun);
    expect(week.first.day, mon);
    expect(week.first.meetings, 1);
    expect(week[1].due, 1);
    expect(week[1].tooFull, isTrue, reason: '10 h of work due on a working day');
    expect(week.length, 5, reason: 'an empty weekend is left out');
  });

  testWidgets('one pile at a time, moving things on with undo', (tester) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = build();
    final q4 = s.data.active.first;
    await tester.pumpWidget(MaterialApp(home: WeeklyReviewPage(store: s, now: sun)));
    expect(find.text('1 of 5'), findsOneWidget);
    expect(find.textContaining('To look at: 2 slipped, 1 ageing, 1 stalled'), findsOneWidget);
    await tester.tap(find.text('Next: Slipped →'));
    await tester.pumpAndSettle();
    expect(find.text('Slipped: 2 tasks passed their date'), findsOneWidget);
    await tester.tap(find.text('Next week').first);
    await tester.pump();
    expect(q4.dueAt!.day, mon.day);
    expect(find.text('moved to next week'), findsOneWidget);
    await tester.tap(find.text('Drop').first);
    await tester.pumpAndSettle();
    expect(s.data.active.any((t) => t.title == 'Fix gate latch'), isFalse);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(s.data.active.any((t) => t.title == 'Fix gate latch'), isTrue);
    await tester.tap(find.text('Next: Ageing →'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep'));
    await tester.pump();
    await tester.tap(find.text('Next: Stalled →'));
    await tester.pumpAndSettle();
    expect(find.text('0 of 1 steps · due ${_fmt(mon.add(const Duration(days: 4)))}'), findsOneWidget);
    await tester.tap(find.text('Next: Next week →'));
    await tester.pumpAndSettle();
    expect(find.text('too full'), findsOneWidget);
    expect(find.textContaining('1 rescheduled'), findsOneWidget);
    expect(find.textContaining('1 kept'), findsOneWidget);
    expect(find.text('Finish'), findsOneWidget);
  });

  testWidgets('empty piles are skipped', (tester) async {
    final s = AppStore();
    await tester.pumpWidget(MaterialApp(home: WeeklyReviewPage(store: s, now: sun)));
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.textContaining('Nothing slipped'), findsOneWidget);
  });
}

String _fmt(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
}

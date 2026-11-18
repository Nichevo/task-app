import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/day_plan.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/work_meetings.dart';

/// A pretend photo of Outlook's Work week view: 5 columns 200 px wide from x = 80, hour labels
/// down the left, 8 AM at y = 120 and 80 px an hour. Meetings are light blue boxes on white.
class FakeScreen {
  FakeScreen({this.tilt = 0, this.centredHeadings = false, this.dayNames = const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday']});
  final double tilt;
  final bool centredHeadings;
  final List<String> dayNames;
  static const w = 1100, h = 900, colX = 80.0, colW = 200.0, top = 120.0, perHour = 80.0;
  final words = <OcrWord>[];
  late final img = RgbaImage(w, h, Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255));

  double yAt(int minute) => top + (minute - 8 * 60) / 60 * perHour;

  void word(String text, double l, double t, {double ch = 9, double hgt = 14}) {
    final dy = tilt * (l - colX);
    words.add(OcrWord(text, l, t + dy, l + text.length * ch, t + hgt + dy));
  }

  void line(String text, double l, double t) {
    var x = l;
    for (final part in text.split(' ')) {
      word(part, x, t);
      x += part.length * 9 + 6;
    }
  }

  void headings(List<int> nums) {
    for (var i = 0; i < nums.length; i++) {
      final l = colX + i * colW + (centredHeadings ? 60 : 6);
      word('${nums[i]}', l, 60, hgt: 20, ch: 12);
      word(dayNames[i], l + 30, 64);
    }
    for (var hr = 8; hr <= 16; hr++) {
      final label = hr < 12 ? '$hr' : (hr == 12 ? '12' : '${hr - 12}');
      word(label, 10, yAt(hr * 60) + 3);
      word(hr < 12 ? 'AM' : 'PM', 30, yAt(hr * 60) + 3);
    }
  }

  void box(int col, int from, int to, {(int, int, int) colour = (199, 217, 242)}) {
    final x0 = (colX + col * colW + 4).round(), x1 = (colX + (col + 1) * colW - 4).round();
    for (var x = x0; x < x1; x++) {
      final dy = tilt * (x - colX);
      for (var y = (yAt(from) + 1 + dy).round(); y < (yAt(to) - 1 + dy).round(); y++) {
        final i = (y * w + x) * 4;
        img.bytes[i] = colour.$1;
        img.bytes[i + 1] = colour.$2;
        img.bytes[i + 2] = colour.$3;
      }
    }
  }

  void meeting(int col, int from, int to, String title, {String? place}) {
    box(col, from, to);
    line(title, colX + col * colW + 14, yAt(from) + 4);
    if (place != null) line(place, colX + col * colW + 14, yAt(from) + 22);
  }
}

void img(FakeScreen s, int i, (int, int, int) c) {
  s.img.bytes[i] = c.$1;
  s.img.bytes[i + 1] = c.$2;
  s.img.bytes[i + 2] = c.$3;
}

String hm(DateTime d) => '${d.hour}:${d.minute.toString().padLeft(2, '0')}';

void main() {
  final today = DateTime(2026, 11, 17);

  FakeScreen week({double tilt = 0, bool centred = false}) {
    final s = FakeScreen(tilt: tilt, centredHeadings: centred)..headings([16, 17, 18, 19, 20]);
    for (var c = 0; c < 5; c++) {
      s.meeting(c, 9 * 60 + 30, 9 * 60 + 45, 'Standup');
    }
    s.meeting(0, 11 * 60, 12 * 60, 'Project review', place: 'Room 4');
    s.meeting(1, 13 * 60 + 30, 15 * 60, 'Budget planning', place: 'Microsoft Teams');
    s.meeting(2, 10 * 60 + 15, 10 * 60 + 45, '1:1 with Sam');
    s.meeting(4, 15 * 60, 16 * 60, 'Team catch-up');
    return s;
  }

  test('reads the dates, times and lengths of a work week', () {
    final s = week();
    final r = readWorkWeek(s.words, image: s.img, today: today);
    expect(r.problem, isNull);
    expect(r.days.first, DateTime(2026, 11, 16));
    expect(r.days.last, DateTime(2026, 11, 20));
    final got = [for (final m in r.meetings) '${m.meeting.start.day} ${hm(m.meeting.start)}-${hm(m.meeting.end)} ${m.meeting.title}'];
    expect(got, containsAll([
      '16 9:30-9:45 Standup',
      '16 11:00-12:00 Project review',
      '17 13:30-15:00 Budget planning',
      '18 10:15-10:45 1:1 with Sam',
      '20 15:00-16:00 Team catch-up',
      '20 9:30-9:45 Standup',
    ]));
    expect(r.meetings.length, 9);
    expect(r.meetings.firstWhere((m) => m.meeting.title == 'Project review').meeting.place, 'Room 4');
  });

  test('a real photo: stray numbers, the taskbar, pale boxes with a hatched bar, an all-day strip', () {
    final s = FakeScreen(tilt: 0.02)..headings([16, 17, 18, 19, 20]);
    // A note in the all-day strip, just above the first hour label.
    s.line('WFH', FakeScreen.colX + 60, FakeScreen.top - 14);
    // A pale box (as light as the background) with a dark hatched bar down its left.
    final x0 = (FakeScreen.colX + 3 * FakeScreen.colW + 6).round();
    for (var y = s.yAt(10 * 60).round() + 1; y < s.yAt(10 * 60 + 45).round(); y++) {
      for (var x = x0; x < x0 + 4; x++) {
        final dy = (0.02 * (x - FakeScreen.colX)).round();
        final i = ((y + dy) * FakeScreen.w + x) * 4;
        final dark = (y + x) % 3 != 0;
        img(s, i, dark ? (90, 105, 140) : (160, 170, 190));
      }
    }
    s.line('Daily meeting', FakeScreen.colX + 3 * FakeScreen.colW + 16, s.yAt(10 * 60) + 4);
    // The taskbar's clock and date, then keyboard keys, under the calendar.
    s.line('9:42 p.m.', 900, 820);
    s.line('17/11/2026', 900, 838);
    s.word('4', 10, 870);
    s.word('Retry', 300, 880);
    final r = readWorkWeek(s.words, image: s.img, today: today);
    expect(r.ok, true, reason: r.problem);
    final titles = [for (final m in r.meetings) m.meeting.title];
    expect(titles, isNot(contains('9:42 p.m.')));
    expect(titles, isNot(contains('Retry')));
    final wfh = r.meetings.firstWhere((m) => m.meeting.title == 'WFH').meeting;
    expect(wfh.allDay, true);
    final daily = r.meetings.firstWhere((m) => m.meeting.title == 'Daily meeting').meeting;
    expect((hm(daily.start), hm(daily.end)), ('10:00', '10:45'));
  });

  test('the hour labels that agree win over a stray number, and an hour is never one line tall', () {
    final s = FakeScreen()..headings([16, 17, 18, 19, 20]);
    s.meeting(1, 14 * 60, 15 * 60, 'Planning');
    s.word('0', 12, s.yAt(9 * 60) + 20);
    s.word('1', 12, s.yAt(9 * 60) + 36);
    final r = readWorkWeek(s.words, image: s.img, today: today);
    final m = r.meetings.single.meeting;
    expect((hm(m.start), hm(m.end)), ('14:00', '15:00'));
  });

  test('copes with a crooked photo and headings in the middle of their columns', () {
    final s = week(tilt: 0.04, centred: true);
    final r = readWorkWeek(s.words, image: s.img, today: today);
    expect(r.problem, isNull);
    final got = [for (final m in r.meetings) '${m.meeting.start.day} ${hm(m.meeting.start)}-${hm(m.meeting.end)} ${m.meeting.title}'];
    expect(got, containsAll(['17 13:30-15:00 Budget planning', '20 15:00-16:00 Team catch-up', '18 10:15-10:45 1:1 with Sam']));
  });

  test('without the pixels the end comes from the next meeting or half an hour, marked to check', () {
    final s = week();
    final r = readWorkWeek(s.words, today: today);
    final review = r.meetings.firstWhere((m) => m.meeting.title == 'Project review');
    expect(hm(review.meeting.start), '11:00');
    expect(hm(review.meeting.end), '11:30');
  });

  test('a future week is found from its day numbers; a month above the headings decides', () {
    final s = FakeScreen()..headings([30, 1, 2, 3, 4]);
    s.word('November', 300, 10);
    s.word('30', 390, 10);
    s.word('2026', 420, 10);
    s.meeting(1, 9 * 60, 10 * 60, 'Planning');
    final r = readWorkWeek(s.words, image: s.img, today: today);
    expect(r.days.first, DateTime(2026, 11, 30));
    expect(r.days[1], DateTime(2026, 12, 1));
    expect(r.meetings.single.meeting.start, DateTime(2026, 12, 1, 9));
  });

  test('all-day notes, written times and cancelled meetings', () {
    final s = FakeScreen()..headings([16, 17, 18, 19, 20]);
    s.line('Annual leave', FakeScreen.colX + 3 * FakeScreen.colW + 14, 90);
    s.meeting(0, 14 * 60, 15 * 60, 'Supplier call');
    s.line('2:05 PM - 2:50 PM', FakeScreen.colX + 14, s.yAt(14 * 60) + 22);
    s.meeting(2, 9 * 60, 10 * 60, 'Canceled: Old meeting');
    final r = readWorkWeek(s.words, image: s.img, today: today);
    final leave = r.meetings.firstWhere((m) => m.meeting.allDay);
    expect(leave.meeting.title, 'Annual leave');
    expect(leave.meeting.start, DateTime(2026, 11, 19));
    final call = r.meetings.firstWhere((m) => m.meeting.title == 'Supplier call');
    expect(hm(call.meeting.start), '14:05');
    expect(hm(call.meeting.end), '14:50');
    expect(r.skipped, 1);
    expect(r.meetings.length, 2);
  });

  test('says what is missing', () {
    expect(readWorkWeek([const OcrWord('hello', 0, 0, 40, 10)], today: today).problem, contains('day headings'));
    final s = FakeScreen();
    for (var i = 0; i < 5; i++) {
      s.word(s.dayNames[i], FakeScreen.colX + i * FakeScreen.colW, 60);
    }
    expect(readWorkWeek(s.words, today: today).problem, contains('times down the left'));
  });

  test('a new photo replaces what it covers and marks what changed', () {
    final s = week();
    final first = readWorkWeek(s.words, image: s.img, today: today);
    final rows1 = compareImport(const [], first);
    expect(rows1.every((r) => r.change == WorkChange.same && r.keep), isTrue);
    final saved = applyImport(const [], first, rows1, now: today);
    expect(saved.length, 9);

    // A week later the same week: review moved to 14:00, the 1:1 is gone, a new call.
    final s2 = FakeScreen()..headings([16, 17, 18, 19, 20]);
    for (var c = 0; c < 5; c++) {
      s2.meeting(c, 9 * 60 + 30, 9 * 60 + 45, 'Standup');
    }
    s2.meeting(0, 14 * 60, 15 * 60, 'Project review', place: 'Room 4');
    s2.meeting(1, 13 * 60 + 30, 15 * 60, 'Budget planning', place: 'Microsoft Teams');
    s2.meeting(4, 15 * 60, 16 * 60, 'Team catch-up');
    s2.meeting(3, 14 * 60, 14 * 60 + 30, 'Supplier call');
    final second = readWorkWeek(s2.words, image: s2.img, today: today);
    final rows = compareImport(saved, second);
    String ch(String t) => rows.firstWhere((r) => r.meeting.title == t).change.name;
    expect(ch('Project review'), 'moved');
    expect(ch('Supplier call'), 'added');
    expect(ch('1:1 with Sam'), 'gone');
    expect(ch('Budget planning'), 'same');
    final after = applyImport(saved, second, rows, now: today);
    expect(after.any((m) => m.title == '1:1 with Sam'), isFalse);
    expect(after.length, 9);

    // Another week's photo leaves this week alone.
    final next = second.shiftWeeks(1);
    expect(applyImport(after, next, compareImport(after, next), now: today).length, 18);
  });

  test('meetings keep their place in the saved file', () {
    final m = WorkMeeting(title: 'Standup', start: DateTime(2026, 11, 17, 9, 30), end: DateTime(2026, 11, 17, 9, 45), place: 'Teams');
    final back = WorkMeeting.tryParse(m.toJson())!;
    expect(back.title, 'Standup');
    expect(back.end, m.end);
    expect(back.place, 'Teams');
    expect(back.id, m.id);
    expect(m.toEvent().calendarId, workCalendarId);
  });

  test('a linked task is planned into the meeting, moves with it and stands in for it', () {
    final store = AppStore();
    final s1 = week();
    final r1 = readWorkWeek(s1.words, image: s1.img, today: today);
    store.importWork(r1, compareImport(const [], r1));
    final review = store.data.workMeetings.firstWhere((m) => m.title == 'Project review');
    final t = store.addTask('Prepare the review slides');
    store.linkMeeting(t, review);
    expect(t.slots.single.start, DateTime(2026, 11, 16, 11));
    expect(t.slots.single.minutes, 60);
    // On the Day plan the task's block stands for the meeting: no second block clashing with it.
    final l = layoutDay(store.data, DateTime(2026, 11, 16));
    expect(l.events.map((e) => e.event.title), isNot(contains('Project review')));
    expect(l.events.map((e) => e.event.title), contains('Standup'));

    // The next photo has it at 14:00 for an hour and a half.
    final s2 = FakeScreen()..headings([16, 17, 18, 19, 20]);
    s2.meeting(0, 14 * 60, 15 * 60 + 30, 'Project review');
    final r2 = readWorkWeek(s2.words, image: s2.img, today: today);
    store.importWork(r2, compareImport(store.data.workMeetings, r2));
    expect(t.slots.single.start, DateTime(2026, 11, 16, 14));
    expect(t.slots.single.minutes, 90);
    expect(store.data.linkedToMeeting(store.data.workMeetings.firstWhere((m) => m.title == 'Project review').id)?.$1, t);

    // Then it is gone: the task stays, without the planned time.
    final s3 = FakeScreen()..headings([16, 17, 18, 19, 20]);
    s3.meeting(1, 9 * 60, 10 * 60, 'Something else');
    final r3 = readWorkWeek(s3.words, image: s3.img, today: today);
    store.importWork(r3, compareImport(store.data.workMeetings, r3));
    expect(t.slots, isEmpty);
    expect(store.data.active, contains(t));
  });

  test('a step can be linked to a meeting, moves with it and can be unlinked', () {
    final store = AppStore();
    final s1 = week();
    final r1 = readWorkWeek(s1.words, image: s1.img, today: today);
    store.importWork(r1, compareImport(const [], r1));
    final review = store.data.workMeetings.firstWhere((m) => m.title == 'Project review');
    final t = store.addTask('AI showcase');
    store.addStep(t, 'Rehearse');
    final step = t.steps.single;
    store.linkMeeting(t, review, step: step);
    expect(t.slots.single.stepId, step.id);
    expect(t.slots.single.start, DateTime(2026, 11, 16, 11));
    expect(store.data.linkedToMeeting(review.id)?.$2.stepId, step.id);

    final s2 = FakeScreen()..headings([16, 17, 18, 19, 20]);
    s2.meeting(0, 14 * 60, 15 * 60, 'Project review');
    final r2 = readWorkWeek(s2.words, image: s2.img, today: today);
    store.importWork(r2, compareImport(store.data.workMeetings, r2));
    expect(t.slots.single.start, DateTime(2026, 11, 16, 14));
    expect(t.slots.single.stepId, step.id);

    store.unlinkMeeting(t, t.slots.single);
    expect(t.slots, isEmpty);
    expect(store.data.linkedToMeeting(review.id), isNull);
  });

  test('work meetings sync: the list changed last wins, and survive the saved file', () {
    final a = AppData(), b = AppData();
    a.workMeetings = [WorkMeeting(title: 'Old', start: DateTime(2026, 11, 16, 9), end: DateTime(2026, 11, 16, 10))];
    a.workUpdatedAt = DateTime.utc(2026, 11, 16);
    b.workMeetings = [WorkMeeting(title: 'New', start: DateTime(2026, 11, 17, 9), end: DateTime(2026, 11, 17, 10))];
    b.workUpdatedAt = DateTime.utc(2026, 11, 17);
    expect(mergeData(a, b).workMeetings.single.title, 'New');
    expect(mergeData(b, a).workMeetings.single.title, 'New');
    final back = AppData.fromJson(b.toJson());
    expect(back.workMeetings.single.title, 'New');
    expect(back.workUpdatedAt, b.workUpdatedAt);
  });
}

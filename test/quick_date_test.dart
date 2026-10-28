import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/quick_date.dart';

void main() {
  // A Wednesday afternoon.
  final now = DateTime(2026, 10, 28, 14, 0);
  QuickDate p(String s) => QuickDate.parse(s, now);

  test('tomorrow with a time', () {
    final q = p('Call bank tomorrow 5pm');
    expect(q.title, 'Call bank');
    expect(q.due, DateTime(2026, 10, 29, 17, 0));
  });

  test('weekday names and next', () {
    expect(p('Pay rent fri').due, DateTime(2026, 10, 30, 17));
    expect(p('Pay rent on Wednesday').due, DateTime(2026, 11, 4, 17));
    expect(p('Dentist next mon at 9:30am').due, DateTime(2026, 11, 9, 9, 30));
    expect(p('Dentist next mon at 9:30am').title, 'Dentist');
  });

  test('dates in several forms', () {
    expect(p('Card for Mum 25 Dec').due, DateTime(2026, 12, 25, 17));
    expect(p('Card Dec 25th').due, DateTime(2026, 12, 25, 17));
    expect(p('Renew 3/2').due, DateTime(2027, 2, 3, 17));
    expect(p('Old thing 1 jan').due, DateTime(2027, 1, 1, 17));
  });

  test('relative periods and times', () {
    expect(p('Check oil in 2 weeks').due, DateTime(2026, 11, 11, 17));
    expect(p('Bins next week').due, DateTime(2026, 11, 4, 17));
    expect(p('Call 13:00').due, DateTime(2026, 10, 29, 13));
    expect(p('Call 4pm').due, DateTime(2026, 10, 28, 16));
    expect(p('TV tonight').due, DateTime(2026, 10, 28, 20));
  });

  test('plain text has no date', () {
    final q = p('Buy 2 printer cartridges');
    expect(q.due, isNull);
    expect(q.title, 'Buy 2 printer cartridges');
  });
}

/// Picks a due date out of text typed in the add box, e.g. "Call bank tomorrow 5pm".
class QuickDate {
  const QuickDate(this.title, this.due);

  /// The text with the date words removed.
  final String title;
  final DateTime? due;

  static const _defaultHour = 17;

  static const _weekdays = {
    'mon': 1, 'monday': 1, 'tue': 2, 'tues': 2, 'tuesday': 2, 'wed': 3, 'wednesday': 3,
    'thu': 4, 'thur': 4, 'thurs': 4, 'thursday': 4, 'fri': 5, 'friday': 5,
    'sat': 6, 'saturday': 6, 'sun': 7, 'sunday': 7,
  };

  static const _months = {
    'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3, 'apr': 4, 'april': 4,
    'may': 5, 'jun': 6, 'june': 6, 'jul': 7, 'july': 7, 'aug': 8, 'august': 8,
    'sep': 9, 'sept': 9, 'september': 9, 'oct': 10, 'october': 10, 'nov': 11, 'november': 11,
    'dec': 12, 'december': 12,
  };

  static final _wd = _weekdays.keys.join('|');
  static final _mo = _months.keys.join('|');

  static final _time = RegExp(
      r'\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b|\b(?:at\s+)?([01]?\d|2[0-3]):([0-5]\d)\b',
      caseSensitive: false);
  static final _relDay = RegExp(r'\b(?:by\s+|on\s+)?(today|tonight|tomorrow|tmrw|tmr)\b', caseSensitive: false);
  static final _inN = RegExp(r'\bin\s+(\d{1,3})\s+(days?|weeks?|months?)\b', caseSensitive: false);
  static final _nextWeek = RegExp(r'\bnext\s+(week|month)\b', caseSensitive: false);
  static final _weekday = RegExp('\\b(?:by\\s+|on\\s+)?(next\\s+)?($_wd)\\b', caseSensitive: false);
  static final _dayMonth = RegExp('\\b(?:by\\s+|on\\s+)?(\\d{1,2})(?:st|nd|rd|th)?\\s+($_mo)\\b', caseSensitive: false);
  static final _monthDay = RegExp('\\b(?:by\\s+|on\\s+)?($_mo)\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b', caseSensitive: false);
  static final _numeric = RegExp(r'\b(?:by\s+|on\s+)?(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b');

  static QuickDate parse(String input, DateTime now) {
    var text = ' $input ';
    DateTime? day;
    int? hour, minute;

    RegExpMatch? take(RegExp re) {
      final m = re.firstMatch(text);
      if (m != null) text = text.replaceRange(m.start, m.end, ' ');
      return m;
    }

    final today = DateTime(now.year, now.month, now.day);

    if (take(_time) case final m?) {
      if (m.group(1) != null) {
        var h = int.parse(m.group(1)!) % 12;
        if (m.group(3)!.toLowerCase() == 'pm') h += 12;
        hour = h;
        minute = int.tryParse(m.group(2) ?? '') ?? 0;
      } else {
        hour = int.parse(m.group(4)!);
        minute = int.parse(m.group(5)!);
      }
    }

    if (take(_relDay) case final m?) {
      final w = m.group(1)!.toLowerCase();
      day = w.startsWith('to') && w != 'tomorrow' ? today : today.add(const Duration(days: 1));
      if (w == 'tonight') hour ??= 20;
    } else if (take(_inN) case final m?) {
      final n = int.parse(m.group(1)!);
      final u = m.group(2)!.toLowerCase();
      day = u.startsWith('day')
          ? DateTime(today.year, today.month, today.day + n)
          : u.startsWith('week')
              ? DateTime(today.year, today.month, today.day + 7 * n)
              : DateTime(today.year, today.month + n, today.day);
    } else if (take(_nextWeek) case final m?) {
      day = m.group(1)!.toLowerCase() == 'week'
          ? DateTime(today.year, today.month, today.day + 7)
          : DateTime(today.year, today.month + 1, today.day);
    } else if (take(_dayMonth) case final m?) {
      day = _future(today, _months[m.group(2)!.toLowerCase()]!, int.parse(m.group(1)!));
    } else if (take(_monthDay) case final m?) {
      day = _future(today, _months[m.group(1)!.toLowerCase()]!, int.parse(m.group(2)!));
    } else if (take(_numeric) case final m?) {
      // Day first (25/12), as used in the UK and Australia.
      final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!);
      if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
        final y = m.group(3);
        day = y == null ? _future(today, mo, d) : DateTime(y.length == 2 ? 2000 + int.parse(y) : int.parse(y), mo, d);
      }
    } else if (take(_weekday) case final m?) {
      final target = _weekdays[m.group(2)!.toLowerCase()]!;
      var ahead = (target - today.weekday) % 7;
      if (ahead == 0) ahead = 7;
      if (m.group(1) != null && ahead < 7) ahead += 7;
      day = today.add(Duration(days: ahead));
    }

    if (day == null && hour == null) return QuickDate(input.trim(), null);
    if (day == null) {
      // Just a time: today if it's still to come, otherwise tomorrow.
      day = today;
      if (!DateTime(day.year, day.month, day.day, hour!, minute!).isAfter(now)) {
        day = today.add(const Duration(days: 1));
      }
    }
    final due = DateTime(day.year, day.month, day.day, hour ?? _defaultHour, minute ?? 0);
    final title = text.replaceAll(RegExp(r'\s+'), ' ').trim().replaceAll(RegExp(r'\s+(by|on|at)$'), '');
    return QuickDate(title.isEmpty ? input.trim() : title, due);
  }

  /// That day and month this year, or next year if it has passed.
  static DateTime _future(DateTime today, int month, int day) {
    final d = DateTime(today.year, month, day);
    return d.isBefore(today) ? DateTime(today.year + 1, month, day) : d;
  }
}

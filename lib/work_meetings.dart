import 'dart:math';
import 'dart:typed_data';

import 'native.dart' show CalendarEvent;

/// Item 111: work meetings read from a photo of the Outlook calendar (Work week view) on a work
/// computer the app can't be installed on. Everything here is plain logic, so it can be tested
/// without a phone: the photo's words and their places come from [Native.readScreen], the
/// screens are in lib/screens/work_import_page.dart.

/// The calendar id work meetings carry as [CalendarEvent]s, so the Day plan can tell them apart.
const workCalendarId = 'work-photo';

/// A meeting (or an all-day note such as "Annual leave") read from a photo.
class WorkMeeting {
  WorkMeeting({required this.title, required this.start, required this.end, this.allDay = false, this.place});

  String title;
  DateTime start;
  DateTime end;
  bool allDay;

  /// The lines under the title: a room, "Microsoft Teams Meeting"...
  String? place;

  DateTime get day => DateTime(start.year, start.month, start.day);

  /// Stable for the same meeting, so a task made from it still finds it after a re-import.
  String get id => 'work:${start.millisecondsSinceEpoch ~/ 60000}:${_hash(title.toLowerCase())}';

  static String _hash(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h.toRadixString(36);
  }

  CalendarEvent toEvent() => CalendarEvent(
        id: id,
        calendarId: workCalendarId,
        title: title,
        start: start,
        end: allDay ? DateTime(start.year, start.month, start.day + 1) : end,
        allDay: allDay,
        location: place,
      );

  WorkMeeting copy() => WorkMeeting(title: title, start: start, end: end, allDay: allDay, place: place);

  Map<String, dynamic> toJson() => {
        't': title,
        's': start.millisecondsSinceEpoch,
        'e': end.millisecondsSinceEpoch,
        if (allDay) 'a': true,
        if (place != null && place!.isNotEmpty) 'p': place,
      };

  static WorkMeeting? tryParse(Object? j) {
    if (j is! Map || j['t'] is! String || j['s'] is! num) return null;
    final s = DateTime.fromMillisecondsSinceEpoch((j['s'] as num).toInt());
    return WorkMeeting(
      title: j['t'] as String,
      start: s,
      end: j['e'] is num ? DateTime.fromMillisecondsSinceEpoch((j['e'] as num).toInt()) : s,
      allDay: j['a'] == true,
      place: j['p'] as String?,
    );
  }
}

/// A word found in the photo and where it is, in pixels of the upright photo.
class OcrWord {
  const OcrWord(this.text, this.l, this.t, this.r, this.b);
  final String text;
  final double l, t, r, b;
  double get cx => (l + r) / 2;
  double get cy => (t + b) / 2;
  double get h => b - t;

  OcrWord shifted(double dy) => OcrWord(text, l, t + dy, r, b + dy);

  @override
  String toString() => '"$text" @(${l.round()},${t.round()})';
}

/// The photo's pixels, for finding where each meeting's coloured box starts and ends.
class RgbaImage {
  RgbaImage(this.width, this.height, this.bytes);
  final int width, height;

  /// Four bytes a pixel: red, green, blue, alpha, row by row.
  final Uint8List bytes;

  /// The colour at x, y averaged with its left and right neighbours; null off the picture.
  (double, double, double)? at(int x, int y) {
    if (y < 0 || y >= height || x < 1 || x >= width - 1) return null;
    var r = 0.0, g = 0.0, b = 0.0;
    for (var dx = -1; dx <= 1; dx++) {
      final i = (y * width + x + dx) * 4;
      r += bytes[i];
      g += bytes[i + 1];
      b += bytes[i + 2];
    }
    return (r / 3, g / 3, b / 3);
  }
}

/// A meeting as read, before it is added: the check screen can change or untick it.
class ReadMeeting {
  ReadMeeting(this.meeting, {this.check});
  final WorkMeeting meeting;

  /// Why its time may be wrong (the photo was unclear), shown on the check screen.
  String? check;
}

/// What a photo held.
class ScreenRead {
  ScreenRead({
    this.days = const [],
    this.meetings = const [],
    this.fromMinute = 0,
    this.toMinute = 24 * 60,
    this.skipped = 0,
    this.problem,
  });

  /// The dates of the columns, left to right.
  final List<DateTime> days;
  final List<ReadMeeting> meetings;

  /// The hours that could be seen: meetings from an earlier import in this window on these
  /// days are replaced (so a second photo of the evening leaves the morning alone).
  final int fromMinute, toMinute;

  /// Cancelled meetings left out.
  final int skipped;

  /// Why nothing could be read, in words for the owner.
  final String? problem;

  bool get ok => problem == null;

  /// The same photo read as [weeks] weeks later (or earlier), when the dates were guessed wrong.
  ScreenRead shiftWeeks(int weeks) {
    DateTime mv(DateTime d) => DateTime(d.year, d.month, d.day + 7 * weeks, d.hour, d.minute);
    return ScreenRead(
      days: [for (final d in days) mv(d)],
      meetings: [
        for (final m in meetings)
          ReadMeeting(
            WorkMeeting(title: m.meeting.title, start: mv(m.meeting.start), end: mv(m.meeting.end), allDay: m.meeting.allDay, place: m.meeting.place),
            check: m.check,
          ),
      ],
      fromMinute: fromMinute,
      toMinute: toMinute,
      skipped: skipped,
      problem: problem,
    );
  }
}

// --- Reading the words ---

const _weekdays = {
  'mon': 1, 'monday': 1,
  'tue': 2, 'tues': 2, 'tuesday': 2,
  'wed': 3, 'weds': 3, 'wednesday': 3,
  'thu': 4, 'thur': 4, 'thurs': 4, 'thursday': 4,
  'fri': 5, 'friday': 5,
  'sat': 6, 'saturday': 6,
  'sun': 7, 'sunday': 7,
};

const _months = {
  'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3, 'apr': 4, 'april': 4,
  'may': 5, 'jun': 6, 'june': 6, 'jul': 7, 'july': 7, 'aug': 8, 'august': 8, 'sep': 9, 'sept': 9,
  'september': 9, 'oct': 10, 'october': 10, 'nov': 11, 'november': 11, 'dec': 12, 'december': 12,
};

String _clean(String s) => s.toLowerCase().replaceAll(RegExp(r'[.,;()]'), '');

/// "Monday", "16Monday", "Mon16" or "Mon 16/11": the weekday and the day number in the word.
(int, int?)? _weekdayIn(String text) {
  final m = RegExp(r'^(\d{1,2})?([a-z]+)(\d{1,2})?(?:/\d{1,2})?$').firstMatch(_clean(text));
  if (m == null) return null;
  final w = _weekdays[m.group(2)];
  if (w == null) return null;
  final n = int.tryParse(m.group(1) ?? m.group(3) ?? '');
  return (w, n != null && n >= 1 && n <= 31 ? n : null);
}

/// A day number on its own ("16", "16/11", "11/16" is read as day 16).
int? _dayNumber(String text) {
  final m = RegExp(r'^(\d{1,2})(?:/(\d{1,2}))?$').firstMatch(_clean(text));
  if (m == null) return null;
  var n = int.parse(m.group(1)!);
  final o = int.tryParse(m.group(2) ?? '');
  if (o != null && n <= 12 && o > 12) n = o;
  return n >= 1 && n <= 31 ? n : null;
}

/// An hour label: "9 AM", "9AM", "09:00", "13", "1 PM", "12pm". Minutes from midnight, and
/// whether it said AM or PM (null when it didn't).
(int, bool?)? _hourLabel(String text) {
  final s = text.toLowerCase().replaceAll('.', '').replaceAll(' ', '');
  // Small grey labels photographed off a screen: O read for 0, I or l for 1.
  final m = RegExp(r'^([0-9oil|]{1,2})(?::?([0-5o][0-9o]))?(am|pm|a|p)?$').firstMatch(s);
  if (m == null) return null;
  int digits(String x) => int.parse(x.replaceAll('o', '0').replaceAll(RegExp(r'[il|]'), '1'));
  if (m.group(3) == null && m.group(2) == null && RegExp(r'[oil|]').hasMatch(m.group(1)!)) return null;
  var h = digits(m.group(1)!);
  final min = m.group(2) == null ? 0 : digits(m.group(2)!);
  final ap = m.group(3);
  if (h > 23) return null;
  bool? pm;
  if (ap != null) {
    if (h == 0 || h > 12) return null;
    pm = ap.startsWith('p');
    if (pm && h < 12) h += 12;
    if (!pm && h == 12) h = 0;
  }
  return (h * 60 + min, pm);
}

/// "9:30 AM - 10:00 AM", "09:30–10:00", "9:30-10am": the minutes of a time range written in a
/// meeting's box.
(int, int)? _timeRange(String text) {
  final s = text.toLowerCase().replaceAll('.', '');
  final m = RegExp(r'(\d{1,2})(?::([0-5]\d))?\s*(am|pm)?\s*[-–—]\s*(\d{1,2})(?::([0-5]\d))?\s*(am|pm)?').firstMatch(s);
  if (m == null || (m.group(2) == null && m.group(5) == null)) return null;
  int conv(String h, String? mm, String? ap, String? other) {
    var x = int.parse(h);
    final a = ap ?? other;
    if (a == 'pm' && x < 12) x += 12;
    if (a == 'am' && x == 12) x = 0;
    return x * 60 + (int.tryParse(mm ?? '') ?? 0);
  }

  final a = conv(m.group(1)!, m.group(2), m.group(3), m.group(3) == null ? m.group(6) : null);
  var b = conv(m.group(4)!, m.group(5), m.group(6), null);
  if (b <= a && m.group(6) == null && b + 12 * 60 > a) b += 12 * 60;
  if (a >= 24 * 60 || b > 24 * 60 || b <= a) return null;
  return (a, b);
}

double _median(List<double> xs) {
  final s = [...xs]..sort();
  return s.isEmpty ? 0 : s[s.length ~/ 2];
}

/// Least squares line y = a + b·x through the points.
(double, double) _fit(List<(double, double)> pts) {
  final n = pts.length;
  final mx = pts.map((p) => p.$1).reduce((a, b) => a + b) / n;
  final my = pts.map((p) => p.$2).reduce((a, b) => a + b) / n;
  var sxy = 0.0, sxx = 0.0;
  for (final (x, y) in pts) {
    sxy += (x - mx) * (y - my);
    sxx += (x - mx) * (x - mx);
  }
  final b = sxx == 0 ? 0.0 : sxy / sxx;
  return (my - b * mx, b);
}

/// Rounds to the quarter hour when within 4 minutes of one, otherwise to 5 minutes.
int snapMinutes(double m) {
  final q = (m / 15).round() * 15;
  if ((m - q).abs() <= 4) return q;
  return (m / 5).round() * 5;
}

class _Line {
  _Line(OcrWord w)
      : words = [w],
        l = w.l,
        t = w.t,
        r = w.r,
        b = w.b;
  final List<OcrWord> words;
  double l, t, r, b;
  double get cy => (t + b) / 2;
  double get h => b - t;
  void add(OcrWord w) {
    words.add(w);
    l = min(l, w.l);
    t = min(t, w.t);
    r = max(r, w.r);
    b = max(b, w.b);
  }

  String get text => words.map((w) => w.text).join(' ');
}

class _Block {
  _Block(_Line l)
      : lines = [l],
        l = l.l,
        t = l.t,
        r = l.r,
        b = l.b;
  final List<_Line> lines;
  double l, t, r, b;
  void add(_Line x) {
    lines.add(x);
    l = min(l, x.l);
    r = max(r, x.r);
    b = max(b, x.b);
  }

  double get lineH => _median([for (final x in lines) x.h]);
}

/// Words into lines: side by side on the same row and close together.
List<_Line> _lines(List<OcrWord> words) {
  final out = <_Line>[];
  for (final w in [...words]..sort((a, b) => a.l.compareTo(b.l))) {
    _Line? best;
    for (final x in out) {
      final hh = max(x.h, w.h);
      if ((x.cy - w.cy).abs() > hh * 0.5) continue;
      final gap = w.l - x.r;
      if (gap > hh * 1.3 || gap < -hh) continue;
      if (best == null || (w.l - x.r).abs() < (w.l - best.r).abs()) best = x;
    }
    if (best != null) {
      best.add(w);
    } else {
      out.add(_Line(w));
    }
  }
  out.sort((a, b) => a.t.compareTo(b.t));
  return out;
}

/// Lines into blocks of text: one under the other and lined up on the left, as in one meeting.
List<_Block> _blocks(List<_Line> lines) {
  final out = <_Block>[];
  for (final x in lines) {
    _Block? into;
    for (final bl in out.reversed) {
      final hh = max(bl.lineH, x.h);
      if ((x.l - bl.l).abs() < hh * 1.0 && x.t - bl.b < hh * 0.9 && x.t > bl.b - hh * 0.4) {
        into = bl;
        break;
      }
    }
    if (into != null) {
      into.add(x);
    } else {
      out.add(_Block(x));
    }
  }
  return out;
}

double _dist((double, double, double) a, (double, double, double) b) {
  final dr = a.$1 - b.$1, dg = a.$2 - b.$2, db = a.$3 - b.$3;
  return sqrt(dr * dr + dg * dg + db * db);
}

/// From (x, y) up or down ([dir] -1 or 1), how far the same colour goes: the last row of it.
/// The colour may drift slowly (light falls off across a photo); a few rows of something else
/// (a speck) are let through, more ends it.
int _runEnd(RgbaImage img, int x, int y, int dir, {required int limit, required int gaps}) {
  final start = img.at(x, y);
  if (start == null) return y;
  var avg = start;
  var last = y, miss = 0;
  for (var yy = y + dir; (yy - y).abs() <= limit; yy += dir) {
    final p = img.at(x, yy);
    if (p == null) break;
    if (_dist(p, avg) < 26) {
      avg = (avg.$1 * 0.85 + p.$1 * 0.15, avg.$2 * 0.85 + p.$2 * 0.15, avg.$3 * 0.85 + p.$3 * 0.15);
      last = yy;
      miss = 0;
    } else if (++miss > gaps) {
      break;
    }
  }
  return last;
}

double _lum((double, double, double) p) => p.$1 * 0.3 + p.$2 * 0.59 + p.$3 * 0.11;

/// How dark the bar is around column [x] on row [y]: the mean brightness of five pixels.
double? _barLum(RgbaImage img, int x, int y) {
  var sum = 0.0;
  for (var dx = -2; dx <= 2; dx++) {
    final p = img.at(x + dx, y);
    if (p == null) return null;
    sum += _lum(p);
  }
  return sum / 5;
}

/// From (x, y) up or down ([dir] -1 or 1) along a meeting's left bar (solid or hatched), the last
/// row it is still darker than halfway to [light]. It may drift a pixel sideways a row.
int _barEnd(RgbaImage img, int x, int y, int dir, {required int limit, required double light, required int gaps}) {
  final start = _barLum(img, x, y);
  if (start == null) return y;
  final edge = (start + light) / 2;
  var last = y, miss = 0;
  for (var yy = y + dir; (yy - y).abs() <= limit; yy += dir) {
    double? best;
    var bx = x;
    for (final dx in const [0, -1, 1]) {
      final v = _barLum(img, x + dx, yy);
      if (v != null && (best == null || v < best - 3)) {
        best = v;
        bx = x + dx;
      }
    }
    if (best == null) break;
    if (best < edge) {
      x = bx;
      last = yy;
      miss = 0;
    } else if (++miss > gaps) {
      break;
    }
  }
  return last;
}

/// The leftmost dark column just left of (and a little into) a meeting's text at row [y]: the
/// coloured bar Outlook draws down the side of a meeting. Null when there is none.
(int, double)? _leftBar(RgbaImage img, double textL, int y, double lh) {
  const lum = _lum;
  final from = (textL - lh * 2).round(), to = (textL + lh * 0.5).round();
  final ps = [for (var x = from; x <= to; x++) img.at(x, y)];
  final known = [for (final p in ps) if (p != null) lum(p)];
  if (known.isEmpty) return null;
  final light = (known..sort()).last;
  for (var i = 0; i < ps.length; i++) {
    final p = ps[i];
    if (p == null || light - lum(p) < 60) continue;
    // A bar runs on down; a letter or an icon stops within a line.
    // The darkest column of the bar, a few pixels wide.
    var x = from + i;
    for (var dx = 1; dx <= 3; dx++) {
      final q = img.at(from + i + dx, y);
      if (q != null && lum(q) < lum(img.at(x, y)!)) x = from + i + dx;
    }
    final here = img.at(x, y)!;
    final below = img.at(x, y + (lh * 0.45).round());
    if (below != null && _dist(below, here) < 30) return (x, light);
  }
  return null;
}

/// The straight line y = a + b·minutes that the most hour labels agree with (within a fifth of
/// an hour), fitted through those. Only lines with an hour at least [minHourPx] tall count.
(List<(double, double)>, double, double) _hourFit(List<(double, double)> pts, double minHourPx) {
  if (pts.length < 2) return (pts, 0, 0);
  List<(double, double)> best = const [];
  var bestErr = double.infinity;
  for (var i = 0; i < pts.length; i++) {
    for (var j = i + 1; j < pts.length; j++) {
      final dm = pts[j].$1 - pts[i].$1;
      if (dm == 0) continue;
      final b = (pts[j].$2 - pts[i].$2) / dm;
      if (b * 60 < minHourPx) continue;
      final a = pts[i].$2 - b * pts[i].$1;
      final ins = <(double, double)>[];
      var err = 0.0;
      for (final p in pts) {
        final e = (p.$2 - (a + b * p.$1)).abs();
        if (e < b * 60 * 0.2) {
          ins.add(p);
          err += e;
        }
      }
      if (ins.length > best.length || (ins.length == best.length && err < bestErr)) {
        best = ins;
        bestErr = err;
      }
    }
  }
  if (best.length < 2) return (best, 0, 0);
  final (a, b) = _fit(best);
  if (b * 60 < minHourPx) return (best, 0, 0);
  return (best, a, b);
}

/// Reads an Outlook calendar photographed in Work week (or Day, or Week) view: the column dates
/// from the headings, the hours from the labels down the left, and each meeting from where
/// its text sits (with its length from its coloured box in [image], when given).
ScreenRead readWorkWeek(List<OcrWord> words, {RgbaImage? image, DateTime? today}) {
  today ??= DateTime.now();
  today = DateTime(today.year, today.month, today.day);
  words = [for (final w in words) if (w.text.trim().isNotEmpty && w.h > 0) w];

  // 1. The day headings: the row with the most different weekday names.
  final cands = [
    for (final w in words)
      if (_weekdayIn(w.text) case final wd?) (w, wd.$1, wd.$2),
  ];
  List<(OcrWord, int, int?)> header = const [];
  for (final c in cands) {
    final hh = max(c.$1.h, 8.0);
    final row = [for (final o in cands) if ((o.$1.cy - c.$1.cy).abs() < hh * 0.9 + (o.$1.cx - c.$1.cx).abs() * 0.06) o]..sort((a, b) => a.$1.l.compareTo(b.$1.l));
    final seen = <int>{};
    final uniq = [for (final o in row) if (seen.add(o.$2)) o];
    if (uniq.length > header.length || (uniq.length == header.length && header.isNotEmpty && c.$1.cy < header.first.$1.cy)) {
      header = uniq;
    }
  }
  if (header.isEmpty) {
    return ScreenRead(problem: "Couldn't find the day headings (Monday, Tuesday…). Make sure the top of the calendar is in the photo.");
  }

  // A photo taken a little crooked: level it using the headings, which sit on one line.
  var tilt = 0.0;
  final x0 = header.first.$1.cx;
  if (header.length >= 2) {
    final (_, s) = _fit([for (final h in header) (h.$1.cx, h.$1.cy)]);
    if (s.abs() < 0.15) tilt = s;
  }
  double level(OcrWord w) => -tilt * (w.cx - x0);
  words = [for (final w in words) w.shifted(level(w))];
  header = [for (final h in header) (h.$1.shifted(level(h.$1)), h.$2, h.$3)];
  // Back from levelled to the photo's own rows, for reading its pixels.
  int rawY(double x, double y) => (y + tilt * (x - x0)).round();

  final hy = _median([for (final h in header) h.$1.cy]);
  final hh = _median([for (final h in header) h.$1.h]);
  final spacing = header.length >= 2
      ? _median([for (var i = 1; i < header.length; i++) header[i].$1.l - header[i - 1].$1.l])
      : max(header.first.$1.r - header.first.$1.l, 60.0) * 3;

  // Day numbers beside the names ("16 Monday", "Mon 16").
  final rowWords = [for (final w in words) if ((w.cy - hy).abs() < hh * 1.6) w]; // levelled by now
  final nums = <int?>[];
  final lefts = <double>[], rights = <double>[];
  var headerBottom = 0.0;
  for (final (w, _, n0) in header) {
    var n = n0;
    var left = w.l, right = w.r;
    headerBottom = max(headerBottom, w.b);
    if (n == null) {
      OcrWord? best;
      for (final o in rowWords) {
        if (_dayNumber(o.text) == null) continue;
        final dx = o.cx < w.l ? w.l - o.r : (o.l > w.r ? o.l - w.r : 0.0);
        if (dx > spacing * 0.35) continue;
        if (best == null || (o.cx - w.cx).abs() < (best.cx - w.cx).abs()) best = o;
      }
      if (best != null) {
        n = _dayNumber(best.text);
        left = min(left, best.l);
        right = max(right, best.r);
        headerBottom = max(headerBottom, best.b);
      }
    }
    nums.add(n);
    lefts.add(left);
    rights.add(right);
  }

  // 2. The hour labels down the left, under the headings: lines left of the first heading
  // that read as a time (meeting text can be there too when headings are centred).
  // The taskbar under the calendar (its date, "17/11/2026") and anything below it (the
  // keyboard, the desk) is not the calendar.
  var gridBottom = double.infinity;
  for (final w in words) {
    if (w.t > headerBottom && RegExp(r'^\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}$').hasMatch(w.text.trim())) {
      // The clock sits on the line above the date.
      gridBottom = min(gridBottom, w.t - w.h * 1.6);
    }
  }
  words = [for (final w in words) if (w.b < gridBottom + w.h * 0.6 || w.t < headerBottom) w];
  final gutterWords = <OcrWord>[];
  var labels = <(double, int, bool?, double, bool, double)>[]; // top, minutes, pm, right edge, AM/PM or ":" written, height
  for (final line in _lines([for (final w in words) if (w.cx < lefts.first && w.t > headerBottom) w])) {
    final hl = _hourLabel(line.text);
    if (hl == null) continue;
    labels.add((line.t, hl.$1, hl.$2, line.r, hl.$2 != null || line.text.contains(':'), line.h));
    gutterWords.addAll(line.words);
  }
  // A lone number is a weak sign (a key on the keyboard, a stray mark): when the labels say
  // AM and PM, only those count.
  if (labels.where((x) => x.$5).length >= 2) labels = [for (final x in labels) if (x.$5) x];
  labels.sort((a, b) => a.$1.compareTo(b.$1));
  // Labels without AM or PM in a 12-hour day: count on past noon when they start again.
  final anyAmPm = labels.any((x) => x.$3 != null);
  final pts = <(double, double)>[];
  var prev = -1;
  for (final (top, m0, pm, _, _, _) in labels) {
    var m = m0;
    if (pm == null && m < 13 * 60) {
      while (m <= prev && m + 12 * 60 < 24 * 60) {
        m += 12 * 60;
      }
      if (prev < 0 && !anyAmPm && m < 6 * 60) m += 12 * 60;
    }
    if (m <= prev) continue;
    prev = m;
    pts.add((m.toDouble(), top));
  }
  // y = a + b·minutes through the labels that agree with each other most (a misread label or
  // a stray number is left out). An hour is always several lines of text tall.
  final labelH = _median([for (final x in labels) x.$6]);
  final minHourPx = max(labelH, hh) * 2.2;
  final (fitPts, a, b) = _hourFit(pts, minHourPx);
  if (fitPts.length < 2 || b <= 0) {
    return ScreenRead(problem: "Couldn't read the times down the left side (8 AM, 9 AM…). Make sure they are in the photo.");
  }
  final hourPx = b * 60;
  double minuteAt(double y) => (y - a) / b;

  // The columns: the headings are either at the left of their column or in its middle.
  final gutterRight = labels.isEmpty ? lefts.first - spacing * 0.1 : labels.map((x) => x.$4).reduce(max);
  final centred = lefts.first - gutterRight > spacing * 0.25;
  final colL = <double>[], colR = <double>[];
  for (var i = 0; i < header.length; i++) {
    if (centred) {
      final c = (lefts[i] + rights[i]) / 2;
      colL.add(c - spacing / 2);
      colR.add(c + spacing / 2);
    } else {
      colL.add(lefts[i] - spacing * 0.08);
      colR.add(i + 1 < lefts.length ? lefts[i + 1] - spacing * 0.08 : lefts[i] + spacing * 0.92);
    }
  }

  // 3. The dates of the columns.
  final above = [for (final w in words) if (w.b <= headerBottom + hh) w];
  int? monthHint, yearHint;
  for (final w in [...above]..sort((p, q) => p.t != q.t ? p.t.compareTo(q.t) : p.l.compareTo(q.l))) {
    final c = _clean(w.text);
    monthHint ??= _months[c];
    final y = int.tryParse(c);
    if (y != null && y >= 2000 && y < 2100) yearHint ??= y;
  }
  final ref = nums.indexWhere((n) => n != null);
  final days = <DateTime>[];
  DateTime? anchor;
  final w0 = header[ref < 0 ? 0 : ref].$2;
  var bestScore = 1 << 30;
  for (var k = -200; k <= 200; k++) {
    final d = DateTime(today.year, today.month, today.day + k);
    if (d.weekday != w0) continue;
    if (ref >= 0 && d.day != nums[ref]) continue;
    // A month or year named above the headings counts for a lot, nearness to today for less.
    var score = k.abs();
    if (monthHint != null && d.month != monthHint) score += 400;
    if (yearHint != null && d.year != yearHint) score += 400;
    if (score < bestScore) {
      bestScore = score;
      anchor = d;
    }
  }
  if (anchor == null) {
    // A day number misread: fall back on the nearest such weekday.
    for (var k = 0; k <= 3; k++) {
      final d = DateTime(today.year, today.month, today.day + k);
      if (d.weekday == w0) anchor = d;
      final e = DateTime(today.year, today.month, today.day - k);
      if (anchor == null && e.weekday == w0) anchor = e;
      if (anchor != null) break;
    }
  }
  final refW = header[ref < 0 ? 0 : ref].$2;
  for (var i = 0; i < header.length; i++) {
    var off = (header[i].$2 - refW) % 7;
    if (i < (ref < 0 ? 0 : ref)) off -= 7;
    days.add(DateTime(anchor!.year, anchor.month, anchor.day + off));
  }

  // 4. The meetings: text in the columns, below the headings.
  final firstLabelTop = pts.isEmpty ? headerBottom : fitPts.first.$2;
  // Without a taskbar to go by, nothing far past the last hour that could be read.
  final lastY = a + b * (fitPts.last.$1 + 180);
  final inGrid = [
    for (final w in words)
      if (w.t > headerBottom && w.t < lastY && w.cx > colL.first && w.cx < colR.last && !gutterWords.contains(w)) w,
  ];
  final meetings = <ReadMeeting>[];
  var skipped = 0;
  for (var c = 0; c < header.length; c++) {
    final col = [for (final w in inGrid) if (w.cx >= colL[c] && w.cx < colR[c]) w];
    final blocks = _blocks(_lines(col));
    for (final bl in blocks) {
      var texts = [for (final l in bl.lines) l.text.trim()];
      if (texts.join().replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length < 2) continue;
      final day = days[c];
      // All-day notes ("Annual leave") sit in a strip under the headings, above the hours.
      if (bl.t < firstLabelTop - bl.lineH * 0.5 && bl.t < headerBottom + bl.lineH * 3) {
        meetings.add(ReadMeeting(WorkMeeting(title: texts.join(' '), start: day, end: day, allDay: true)));
        continue;
      }
      // A time written in the box is better than one worked out from where it sits.
      (int, int)? written;
      for (final t in texts) {
        written ??= _timeRange(t);
      }
      texts = [for (final t in texts) if (_timeRange(t) == null) t];
      if (texts.isEmpty) continue;
      var title = texts.first;
      final cancelled = RegExp(r'^cancell?ed\s*:?\s*', caseSensitive: false);
      if (cancelled.hasMatch(title)) {
        skipped++;
        continue;
      }
      final place = texts.length > 1 ? texts.skip(1).take(2).join(' · ') : null;
      String? check;
      int start, end;
      if (written != null) {
        (start, end) = written;
      } else {
        start = snapMinutes(minuteAt(bl.t));
        // The end: the bottom of the meeting's coloured box, read from the pixels just left
        // of its text. Failing that, the next meeting under it, or half an hour.
        final lh = bl.lineH;
        final next = blocks
            .where((o) => o.t > bl.b && (o.l - bl.l).abs() < lh * 1.5)
            .map((o) => o.t)
            .fold<double?>(null, (m, v) => m == null || v < m ? v : m);
        double? bottom;
        if (image != null) {
          // Outlook draws a dark bar down the left of each meeting: follow it when there is
          // one (a pale box can be too close to the background), else the box's own colour.
          final bar = _leftBar(image, bl.l, rawY(bl.l, bl.lines.first.cy), lh);
          final x = bar?.$1 ?? (bl.l - max(2.0, lh * 0.35)).round();
          final midY = bl.lines.first.cy;
          final y0 = rawY(x.toDouble(), midY);
          final gaps = max(2, (lh * 0.12).round());
          final upLimit = (hourPx * 0.5).round() + 4, downLimit = (hourPx * 10).round();
          final up = bar != null
              ? _barEnd(image, x, y0, -1, limit: upLimit, light: bar.$2, gaps: gaps)
              : _runEnd(image, x, y0, -1, limit: upLimit, gaps: gaps);
          final down = bar != null
              ? _barEnd(image, x, y0, 1, limit: downLimit, light: bar.$2, gaps: gaps)
              : _runEnd(image, x, y0, 1, limit: downLimit, gaps: gaps);
          final topY = up - (y0 - midY);
          // With a bar to go by, the box's top is the start (the text sits a little lower).
          if (bar != null && topY < bl.t && bl.t - topY < hourPx * 0.25) start = snapMinutes(minuteAt(topY));
          final pad = (bl.t - topY).clamp(0.0, hourPx * 0.25);
          bottom = down - (y0 - midY) + 1 + pad;
          // The same colour well above the text too: a pale box that can't be told from the
          // background, so its pixels say nothing about its end.
          if (y0 - up >= (hourPx * 0.5).round()) bottom = null;
          if (bottom != null && next != null && bottom > next + lh * 0.2) {
            bottom = next;
            check = 'Check the end time';
          }
          if (down >= image.height - 2) check = 'It runs off the photo: check the end time';
        }
        if (bottom == null || bottom - bl.t < hourPx * 0.12) {
          bottom = next != null ? min(next, bl.t + hourPx) : bl.t + hourPx * 0.5;
          check = image == null ? null : 'Check the end time';
        }
        end = snapMinutes(minuteAt(bottom));
        if (end - start < 5) {
          end = start + 15;
          check ??= 'Check the end time';
        }
      }
      start = max(0, min(start, 24 * 60 - 5));
      end = max(start + 5, min(end, 24 * 60));
      title = title.replaceAll(RegExp(r'\s+'), ' ');
      meetings.add(ReadMeeting(
        WorkMeeting(
          title: title,
          start: day.add(Duration(minutes: start)),
          end: day.add(Duration(minutes: end)),
          place: place,
        ),
        check: check,
      ));
    }
  }
  meetings.sort((x, y) => byDay(x.meeting, y.meeting));

  final double bottomY = image?.height.toDouble() ?? words.map((w) => w.b).fold<double>(0.0, (m, v) => max(m, v));
  return ScreenRead(
    days: days,
    meetings: meetings,
    fromMinute: max(0, (minuteAt(max(headerBottom, firstLabelTop - hourPx))).floor()),
    toMinute: min(24 * 60, minuteAt(bottomY).ceil()),
    skipped: skipped,
  );
}

/// By day, a day's all-day notes first, then by start.
int byDay(WorkMeeting a, WorkMeeting b) {
  final d = a.day.compareTo(b.day);
  if (d != 0) return d;
  if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
  return a.start.compareTo(b.start);
}

// --- Adding them ---

enum WorkChange { same, added, moved, gone }

/// One row of the check screen: a meeting read from the photo, or one from an earlier import
/// that the photo no longer shows ([WorkChange.gone]).
class WorkRow {
  WorkRow(this.meeting, this.change, {this.check, this.keep = true, this.was});
  final WorkMeeting meeting;

  /// The same meeting from the earlier import (for one that is the same or moved, or gone).
  final WorkMeeting? was;
  final WorkChange change;
  String? check;

  /// Ticked: added (or, for a gone one, kept).
  bool keep;
}

/// Whether [m] from an earlier import is covered by this photo, so it is replaced.
bool coveredBy(WorkMeeting m, ScreenRead read) {
  if (!read.days.any((d) => _sameDay(d, m.start))) return false;
  if (m.allDay) return true;
  final at = m.start.hour * 60 + m.start.minute;
  return at >= read.fromMinute && at < read.toMinute;
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// The check screen's rows: what the photo holds, marked new or moved against what is there
/// now, and what it no longer holds (gone, unticked so it is removed).
List<WorkRow> compareImport(List<WorkMeeting> existing, ScreenRead read) {
  final old = [for (final m in existing) if (coveredBy(m, read)) m];
  final firstTime = old.isEmpty;
  final left = [...old];
  final rows = <WorkRow>[];
  for (final r in read.meetings) {
    final m = r.meeting;
    WorkMeeting? match;
    for (final o in left) {
      if (!_sameDay(o.start, m.start) || o.allDay != m.allDay) continue;
      if (o.title.toLowerCase() != m.title.toLowerCase()) continue;
      if (match == null || (o.start.difference(m.start)).abs() < (match.start.difference(m.start)).abs()) match = o;
    }
    if (match != null) left.remove(match);
    final change = firstTime
        ? WorkChange.same
        : match == null
            ? WorkChange.added
            : (match.start == m.start && match.end == m.end ? WorkChange.same : WorkChange.moved);
    rows.add(WorkRow(m, change, check: r.check, was: match));
  }
  for (final o in left) {
    rows.add(WorkRow(o, WorkChange.gone, keep: false, was: o));
  }
  rows.sort((x, y) => byDay(x.meeting, y.meeting));
  return rows;
}

/// [existing] with the photo's meetings in: those it covers go, the ticked rows come in, and
/// anything over 90 days old is let go.
List<WorkMeeting> applyImport(List<WorkMeeting> existing, ScreenRead read, List<WorkRow> rows, {DateTime? now}) {
  final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 90));
  return [
    for (final m in existing)
      if (!coveredBy(m, read) && m.end.isAfter(cutoff)) m,
    for (final r in rows)
      if (r.keep) r.meeting,
  ]..sort((a, b) => a.start.compareTo(b.start));
}

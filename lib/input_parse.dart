import 'dart:math';

import 'models.dart';
import 'quick_date.dart';

/// Where a suggested category came from.
enum CategorySource { none, tag, keyword, learned }

/// What the app read out of a typed line: the words, a due date and a category.
class ParsedInput {
  const ParsedInput(this.title,
      {this.due, this.categoryId, this.source = CategorySource.none, this.box, this.board = false, this.star = false, this.gantt = false});

  final String title;
  final DateTime? due;
  final String? categoryId;
  final CategorySource source;

  /// Item 64: quick-add words found ("!do", "!board", "!star").
  final MatrixBox? box;
  final bool board;
  final bool star;

  /// Item 72: "!gantt".
  final bool gantt;
}

/// Item 64: the "!" words the add box understands.
enum QuickWord {
  doBox('do', 'Puts it in the matrix box', MatrixBox.doNow),
  decide('decide', 'Puts it in the matrix box', MatrixBox.decide),
  delegate('delegate', 'Puts it in the matrix box', MatrixBox.delegate),
  delete('delete', 'Puts it in the matrix box', MatrixBox.delete),
  board('board', 'Puts it on the Kanban board, in the first stage', null),
  gantt('gantt', 'Puts it on the Gantt chart', null),
  star('star', 'Stars it', null);

  const QuickWord(this.id, this.what, this.box);

  /// Saved in [AppData.quickWords]; never changes.
  final String id;
  final String what;
  final MatrixBox? box;
}

/// The word that triggers [w] (without the "!"), lower case; null when it is turned off.
/// A box's word follows the box's name unless it was set by hand.
String? quickWord(AppData data, QuickWord w) {
  final set = data.quickWords[w.id];
  if (set != null) {
    final x = set.trim().toLowerCase().replaceFirst(RegExp(r'^!+'), '');
    return x.isEmpty ? null : x;
  }
  final b = w.box;
  if (b != null) return data.boxName(b).toLowerCase().replaceAll(RegExp(r'[^\w-]'), '');
  return w.id;
}

/// Takes the "!" words out of [text]: what they asked for, and the text without them.
({String text, MatrixBox? box, bool board, bool star, bool gantt}) takeQuickWords(String text, AppData data) {
  final words = <String, QuickWord>{
    for (final w in QuickWord.values)
      if (quickWord(data, w) case final x? when x.isNotEmpty) x: w,
  };
  MatrixBox? box;
  var board = false, star = false, gantt = false;
  final out = text.replaceAllMapped(RegExp(r'(^|\s)!([\w-]+)(?=\s|$)'), (m) {
    final w = words[m.group(2)!.toLowerCase()];
    if (w == null) return m.group(0)!;
    if (w.box != null) box = w.box;
    if (w == QuickWord.board) board = true;
    if (w == QuickWord.star) star = true;
    if (w == QuickWord.gantt) gantt = true;
    return m.group(1)!;
  });
  return (text: out.replaceAll(RegExp(r'\s+'), ' ').trim(), box: box, board: board, star: star, gantt: gantt);
}

/// Reads a due date ("tomorrow 5pm"), a "#category" tag, a category keyword or, failing
/// those, a category learned from the tasks already filed, out of [text].
ParsedInput parseInput(String text, AppData data, DateTime now, {bool classify = true}) {
  final quick = takeQuickWords(text, data);
  text = quick.text.isEmpty ? text : quick.text;
  final q = QuickDate.parse(text, now);
  var title = q.title;
  String? categoryId;
  var source = CategorySource.none;

  final tag = RegExp(r'(?:^|\s)#([\w-]+)').firstMatch(title);
  if (tag != null) {
    final name = tag.group(1)!.toLowerCase();
    final cat = data.categories.where((c) => c.name.toLowerCase().replaceAll(' ', '-') == name).firstOrNull ??
        data.categories.where((c) => c.name.toLowerCase().startsWith(name)).firstOrNull;
    if (cat != null) {
      categoryId = cat.id;
      source = CategorySource.tag;
      title = title.replaceRange(tag.start, tag.end, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    }
  }

  if (categoryId == null && data.autoCategory != AutoCategory.off) {
    final lower = ' ${title.toLowerCase()} ';
    for (final c in data.categories) {
      if (c.keywords.any((k) => lower.contains(' $k ') || (k.contains(' ') && lower.contains(k)))) {
        categoryId = c.id;
        source = CategorySource.keyword;
        break;
      }
    }
  }

  if (categoryId == null && classify && data.autoCategory != AutoCategory.off) {
    categoryId = Categoriser(data).suggest(title);
    if (categoryId != null) source = CategorySource.learned;
  }

  return ParsedInput(title.isEmpty ? text.trim() : title,
      due: q.due, categoryId: categoryId, source: source, box: quick.box, board: quick.board, star: quick.star, gantt: quick.gantt);
}

/// Splits pasted or shared text into one task per line, dropping bullets and numbering.
List<String> splitLines(String text) => [
      for (final raw in text.split(RegExp(r'\r?\n')))
        raw.replaceFirst(RegExp(r'^\s*(?:[-*•▪◦]|\d+[.)]|\[[ xX]?\])\s*'), '').trim(),
    ].where((l) => l.isNotEmpty).toList();

/// Guesses a category from the words of tasks already filed, entirely on the device.
/// A plain word-count model: each category (and "no category") is scored by how often the
/// words in the new title appear in its tasks.
class Categoriser {
  Categoriser(AppData data) {
    for (final t in data.allTasks) {
      final key = t.categoryId ?? '';
      final counts = _wordCounts.putIfAbsent(key, () => {});
      for (final w in words(t.title)) {
        counts[w] = (counts[w] ?? 0) + 1;
        _totals[key] = (_totals[key] ?? 0) + 1;
        _vocab.add(w);
      }
      _docs[key] = (_docs[key] ?? 0) + 1;
    }
    _known = {for (final c in data.categories) c.id};
  }

  final _wordCounts = <String, Map<String, int>>{};
  final _totals = <String, int>{};
  final _docs = <String, int>{};
  final _vocab = <String>{};
  late final Set<String> _known;

  static const _stop = {
    'the', 'and', 'for', 'with', 'from', 'this', 'that', 'get', 'buy', 'call', 'check', 'new', 'old',
    'about', 'into', 'out', 'off', 'all', 'some', 'more', 'need', 'make', 'send', 'ask', 'book', 'find',
    'tomorrow', 'today', 'next', 'week', 'month', 'morning', 'evening', 'tonight',
  };

  static Iterable<String> words(String s) => s
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.length >= 3 && !_stop.contains(w))
      .map((w) => w.endsWith('s') && w.length > 4 ? w.substring(0, w.length - 1) : w);

  /// The best category id, or null when nothing it has seen matches.
  String? suggest(String title) {
    final ws = words(title).toList();
    if (ws.isEmpty || _docs.isEmpty) return null;
    final totalDocs = _docs.values.fold(0, (a, b) => a + b);
    String? best;
    var bestScore = double.negativeInfinity;
    for (final key in _docs.keys) {
      if (key.isNotEmpty && !_known.contains(key)) continue;
      final counts = _wordCounts[key] ?? {};
      if (key.isNotEmpty && !ws.any((w) => counts.containsKey(w))) continue;
      var score = log(_docs[key]! / totalDocs);
      final total = _totals[key] ?? 0;
      for (final w in ws) {
        score += log(((counts[w] ?? 0) + 0.5) / (total + 0.5 * _vocab.length));
      }
      if (score > bestScore) {
        bestScore = score;
        best = key;
      }
    }
    return best == null || best.isEmpty ? null : best;
  }
}

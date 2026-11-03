import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../store.dart';
import '../task_list.dart';
import 'task_page.dart';

/// Filters for [SearchPage]. Each one narrows the results; none picked means everything.
enum SearchFilter {
  open('Open'),
  done('Done'),
  starred('Starred'),
  hasDate('Has a date'),
  board('On the board'),
  matrix('On the matrix');

  const SearchFilter(this.label);
  final String label;
}

/// Item 65: searches everything on this device (open tasks, steps, emails kept on tasks and the
/// archive) and shows the results grouped, with the matching words highlighted. Words can be in
/// any order; "quoted words" must be together; accents don't matter.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.store, this.initialQuery = ''});

  final AppStore store;
  final String initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

/// The results of a search, grouped.
class SearchResults {
  SearchResults(this.tasks, this.steps, this.emails, this.archive);

  final List<Task> tasks;
  final List<(Task, TaskStep)> steps;
  final List<(Task, TaskEmail)> emails;
  final List<Task> archive;

  int get count => tasks.length + steps.length + emails.length + archive.length;
}

/// Runs a search; kept apart from the page so tests can call it.
SearchResults searchAll(AppData data, String query,
    {Set<SearchFilter> filters = const {}, String? categoryId, DateTime? now}) {
  final terms = searchTerms(query);
  bool all(String text) {
    final f = foldText(text);
    return terms.every(f.contains);
  }

  bool keep(Task t, bool archived) {
    if (filters.contains(SearchFilter.open) && !filters.contains(SearchFilter.done) && archived) return false;
    if (filters.contains(SearchFilter.done) && !filters.contains(SearchFilter.open) && !archived) return false;
    if (filters.contains(SearchFilter.starred) && !t.starred) return false;
    if (filters.contains(SearchFilter.hasDate) && t.dueAt == null) return false;
    if (filters.contains(SearchFilter.board) && !t.kanban) return false;
    if (filters.contains(SearchFilter.matrix) && t.matrixBox == null) return false;
    if (categoryId != null && t.categoryId != categoryId) return false;
    return true;
  }

  final tasks = <Task>[], archive = <Task>[];
  final steps = <(Task, TaskStep)>[];
  final emails = <(Task, TaskEmail)>[];
  if (terms.isEmpty) return SearchResults(tasks, steps, emails, archive);
  for (final t in data.active) {
    if (!keep(t, false)) continue;
    if (all(searchText(t, data))) tasks.add(t);
    for (final s in t.steps) {
      if (all(s.title)) steps.add((t, s));
    }
    for (final e in t.emails) {
      if (all('${e.subject}\n${e.from}\n${e.snippet}')) emails.add((t, e));
    }
  }
  for (final t in data.archived) {
    if (keep(t, true) && all(searchText(t, data))) archive.add(t);
  }
  archive.sort((a, b) => (b.closedAt ?? b.createdAt).compareTo(a.closedAt ?? a.createdAt));
  return SearchResults(tasks, steps, emails, archive);
}

class _SearchPageState extends State<SearchPage> {
  late final _query = TextEditingController(text: widget.initialQuery);
  final _filters = <SearchFilter>{};
  String? _categoryId;

  AppStore get store => widget.store;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _open(Task t) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskPage(store: store, task: t)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: widget.initialQuery.isEmpty,
          decoration: const InputDecoration(hintText: 'Search everything', border: InputBorder.none),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          if (_query.text.isNotEmpty)
            IconButton(tooltip: 'Clear', icon: const Icon(Icons.clear), onPressed: () => setState(_query.clear)),
        ],
      ),
      body: ListenableBuilder(listenable: store, builder: (context, _) => _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final data = store.data;
    final terms = searchTerms(_query.text);
    final r = searchAll(data, _query.text, filters: _filters, categoryId: _categoryId);
    final cat = data.category(_categoryId);
    final hint = Theme.of(context).hintColor;
    final fmt = DateFormat('EEE d MMM');

    Widget header(String name, int n) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('$name ($n)', style: Theme.of(context).textTheme.titleSmall),
        );

    return ListView(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(children: [
          PopupMenuButton<String>(
            tooltip: 'Category',
            onSelected: (v) => setState(() => _categoryId = v.isEmpty ? null : v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: '', child: Text('All categories')),
              for (final c in data.categories) PopupMenuItem(value: c.id, child: Text(c.name)),
            ],
            child: Chip(
              avatar: const Icon(Icons.label_outline, size: 18),
              label: Text(cat?.name ?? 'All categories'),
            ),
          ),
          for (final f in SearchFilter.values)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: FilterChip(
                label: Text(f.label),
                selected: _filters.contains(f),
                onSelected: (on) => setState(() => on ? _filters.add(f) : _filters.remove(f)),
              ),
            ),
        ]),
      ),
      if (terms.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Looks in task names, notes, steps, categories, "Waiting on", places, emails kept on tasks and the '
            'archive. Put words in "quotes" to find them together.',
            style: TextStyle(color: hint),
          ),
        )
      else if (r.count == 0)
        const Padding(padding: EdgeInsets.all(24), child: Text('Nothing found.'))
      else ...[
        if (r.tasks.isNotEmpty) ...[
          header('Tasks', r.tasks.length),
          for (final t in r.tasks)
            ListTile(
              leading: Icon(t.starred ? Icons.star : Icons.radio_button_unchecked,
                  color: t.starred ? Colors.amber : null),
              title: Highlighted(t.title, terms),
              subtitle: _taskDetail(t, data, terms),
              onTap: () => _open(t),
            ),
        ],
        if (r.steps.isNotEmpty) ...[
          header('Steps', r.steps.length),
          for (final (t, s) in r.steps)
            ListTile(
              leading: Icon(s.done ? Icons.check_box : Icons.check_box_outline_blank),
              title: Highlighted(s.title, terms),
              subtitle: Text('In: ${t.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _open(t),
            ),
        ],
        if (r.emails.isNotEmpty) ...[
          header('Emails', r.emails.length),
          for (final (t, e) in r.emails)
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: Highlighted(e.subject.isEmpty ? '(no subject)' : e.subject, terms),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Highlighted([e.from, if (e.date != null) fmt.format(e.date!)].join(' · '), terms,
                    style: TextStyle(fontSize: 12, color: hint)),
                if (e.snippet.isNotEmpty) Highlighted(e.snippet, terms, maxLines: 2, style: const TextStyle(fontSize: 12)),
                Text('On: ${t.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
              trailing: IconButton(
                tooltip: 'Open in Gmail',
                icon: const Icon(Icons.open_in_new, size: 20),
                onPressed: () => launchUrl(e.link, mode: LaunchMode.externalApplication),
              ),
              onTap: () => _open(t),
            ),
        ],
        if (r.archive.isNotEmpty) ...[
          header('Archive', r.archive.length),
          for (final t in r.archive)
            ListTile(
              leading: const Icon(Icons.check_circle_outline, color: Colors.green),
              title: Highlighted(t.title, terms),
              subtitle: Text(
                  [if (t.closedAt != null) 'Done ${fmt.format(t.closedAt!)}', if (data.category(t.categoryId) case final c?) c.name]
                      .join(' · ')),
              onTap: () => _open(t),
            ),
        ],
        const SizedBox(height: 24),
      ],
    ]);
  }

  /// Under a task: where the words were found, when it wasn't the name.
  Widget? _taskDetail(Task t, AppData data, List<String> terms) {
    final parts = <String>[
      if (data.category(t.categoryId) case final c?) c.name,
      if (t.waitingOn != null && t.waitingOn!.isNotEmpty) 'Waiting on ${t.waitingOn}',
      if (t.place != null && t.place!.isNotEmpty) t.place!,
    ];
    final notes = t.notes.trim();
    final noteLine = notes.isEmpty || matchRanges(notes, terms).isEmpty ? null : _around(notes, terms);
    if (parts.isEmpty && noteLine == null) return null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (parts.isNotEmpty) Highlighted(parts.join(' · '), terms, style: const TextStyle(fontSize: 12)),
      if (noteLine != null) Highlighted(noteLine, terms, maxLines: 2, style: const TextStyle(fontSize: 12)),
    ]);
  }

  /// A piece of [text] around the first match, so long notes show the part that matched.
  String _around(String text, List<String> terms) {
    final first = matchRanges(text, terms).first.$1;
    final start = first > 40 ? text.lastIndexOf(RegExp(r'\s'), first - 30) + 1 : 0;
    return (start > 0 ? '…' : '') + text.substring(start).replaceAll('\n', ' ');
  }
}

/// [text] with the search [terms] in bold on a tint.
class Highlighted extends StatelessWidget {
  const Highlighted(this.text, this.terms, {super.key, this.style, this.maxLines = 1});

  final String text;
  final List<String> terms;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final ranges = matchRanges(text, terms);
    final mark = TextStyle(
      fontWeight: FontWeight.bold,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      color: Theme.of(context).colorScheme.onPrimaryContainer,
    );
    final spans = <TextSpan>[];
    var at = 0;
    for (final (s, e) in ranges) {
      if (s > at) spans.add(TextSpan(text: text.substring(at, s)));
      spans.add(TextSpan(text: text.substring(s, e), style: mark));
      at = e;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(TextSpan(style: style, children: spans), maxLines: maxLines, overflow: TextOverflow.ellipsis);
  }
}

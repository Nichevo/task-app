import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../widgets/task_block.dart';
import 'task_page.dart';

/// Ticked-off tasks, most recently closed first, showing the close time.
class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key, required this.store, this.embedded = false, this.onOpen});

  final AppStore store;

  /// Shown as the right-hand pane of the home screen (no back button).
  final bool embedded;

  /// Opens a task; defaults to pushing a separate page.
  final ValueChanged<Task>? onOpen;

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  final _expanded = <String>{};
  String? _query; // null when the search box is closed

  bool _matches(Task t) {
    final q = _query?.trim().toLowerCase() ?? '';
    return q.isEmpty || t.title.toLowerCase().contains(q) || t.notes.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final tasks = store.data.archived.where(_matches).toList();
        final searching = _query != null;
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !widget.embedded,
            title: searching
                ? TextField(
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Search archive…', border: InputBorder.none),
                    onChanged: (v) => setState(() => _query = v),
                  )
                : Text('Archive (${tasks.length})'),
            actions: [
              IconButton(
                tooltip: searching ? 'Close search' : 'Search',
                icon: Icon(searching ? Icons.close : Icons.search),
                onPressed: () => setState(() => _query = searching ? null : ''),
              ),
            ],
          ),
          body: tasks.isEmpty
              ? Center(child: Text(searching ? 'No matching tasks.' : 'Ticked-off tasks will appear here.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: tasks.length,
                  itemBuilder: (context, i) {
                    final t = tasks[i];
                    return TaskBlock(
                      key: ValueKey(t.id),
                      task: t,
                      archived: true,
                      color: const Color(0xFFCFD8DC),
                      expanded: _expanded.contains(t.id),
                      onTap: () => setState(() =>
                          _expanded.contains(t.id) ? _expanded.remove(t.id) : _expanded.add(t.id)),
                      onOpen: () => widget.onOpen != null
                          ? widget.onOpen!(t)
                          : Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => TaskPage(store: store, task: t))),
                      trailing: IconButton(
                        tooltip: 'Move back to tasks',
                        icon: const Icon(Icons.undo, color: Color(0xDD000000)),
                        onPressed: () => store.restore(t),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

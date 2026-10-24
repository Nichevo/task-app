import 'package:flutter/material.dart';

import '../store.dart';
import '../widgets/task_block.dart';
import 'task_page.dart';

/// Ticked-off tasks, most recently closed first, showing the close time.
class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key, required this.store});

  final AppStore store;

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  final _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final tasks = store.data.archived;
        return Scaffold(
          appBar: AppBar(title: Text('Archive (${tasks.length})')),
          body: tasks.isEmpty
              ? const Center(child: Text('Ticked-off tasks will appear here.'))
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
                      onOpen: () => Navigator.of(context)
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

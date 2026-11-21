import 'package:flutter/material.dart';

import '../screens/smart_list_page.dart';
import '../smart_lists.dart';
import '../store.dart';

/// Item 114 (11): the ☰ menu: all tasks, starred, my lists and the views.
class SmartListDrawer extends StatelessWidget {
  const SmartListDrawer({
    super.key,
    required this.store,
    required this.onOpenBoard,
    required this.onOpenMatrix,
    required this.onOpenDayPlan,
    required this.onOpenGantt,
  });

  final AppStore store;
  final VoidCallback onOpenBoard;
  final VoidCallback onOpenMatrix;
  final VoidCallback onOpenDayPlan;
  final VoidCallback onOpenGantt;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final data = store.data;
        final now = DateTime.now();
        final open = data.active.where((t) => !t.habit).toList();
        final lists = data.smartLists;
        final active = store.activeSmartList;
        final label = Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2);
        void close() => Navigator.pop(context);

        void pick(SmartList? l) {
          store.setSmartList(l?.id);
          close();
          if (l?.opens == 'board') onOpenBoard();
          if (l?.opens == 'matrix') onOpenMatrix();
        }

        Widget section(String text) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(text, style: label),
            );

        return Drawer(
          child: SafeArea(
            child: ListView(padding: EdgeInsets.zero, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text('Task Blocks', style: Theme.of(context).textTheme.titleLarge),
              ),
              ListTile(
                leading: const Icon(Icons.list),
                title: const Text('All tasks'),
                trailing: Text('${open.length}'),
                selected: active == null,
                onTap: () => pick(null),
              ),
              section('MY LISTS'),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorderItem: store.moveSmartList,
                children: [
                  for (final (i, l) in lists.indexed)
                    ListTile(
                      key: ValueKey(l.id),
                      leading: Text(l.emoji, style: const TextStyle(fontSize: 20)),
                      title: Text(l.name),
                      subtitle: Text(describeSmartList(l, data), maxLines: 1, overflow: TextOverflow.ellipsis),
                      selected: active?.id == l.id,
                      trailing: ReorderableDelayedDragStartListener(
                        index: i,
                        child: Text('${open.where((t) => passesSmartList(t, l, data, now)).length}'),
                      ),
                      onTap: () => pick(l),
                      onLongPress: () {
                        close();
                        editSmartList(context, store, l);
                      },
                    ),
                ],
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('New list'),
                onTap: () {
                  close();
                  editSmartList(context, store, SmartList.create(''));
                },
              ),
              if (lists.isEmpty)
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('Add a few to start with'),
                  subtitle: const Text('Quick wins, Waiting on others, At risk, Due this week'),
                  onTap: store.addStarterSmartLists,
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Text('Long-press a list to change it', style: Theme.of(context).textTheme.bodySmall),
                ),
              section('VIEWS'),
              ListTile(
                leading: const Icon(Icons.view_day_outlined),
                title: const Text('Day plan'),
                onTap: () {
                  close();
                  onOpenDayPlan();
                },
              ),
              ListTile(
                leading: const Icon(Icons.view_kanban_outlined),
                title: const Text('Kanban board'),
                onTap: () {
                  close();
                  onOpenBoard();
                },
              ),
              ListTile(
                leading: const Icon(Icons.grid_view),
                title: const Text('Matrix'),
                onTap: () {
                  close();
                  onOpenMatrix();
                },
              ),
              ListTile(
                leading: const Icon(Icons.view_timeline_outlined),
                title: const Text('Gantt chart'),
                onTap: () {
                  close();
                  onOpenGantt();
                },
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// The smart list in use, as a chip above the list, board or matrix: tap to change it, ✕ to
/// show everything again.
class SmartListChip extends StatelessWidget {
  const SmartListChip({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final l = store.activeSmartList;
    if (l == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InputChip(
        label: Text('${l.emoji} ${l.name}'),
        selected: true,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        tooltip: describeSmartList(l, store.data),
        onPressed: () => editSmartList(context, store, l),
        onDeleted: () => store.setSmartList(null),
      ),
    );
  }
}


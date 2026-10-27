import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../csv_export.dart';
import '../models.dart';
import '../store.dart';
import '../widgets/task_block.dart';
import '../widgets/task_colors.dart';
import 'archive_page.dart';
import 'settings_page.dart';
import 'task_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});

  final AppStore store;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _expanded = <String>{};

  /// The task open for editing: beside the list on wide screens, in place of it on narrow ones.
  Task? _selected;
  late final Timer _tick;
  late final AppLifecycleListener _lifecycle;

  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    // Re-colour the blocks as they age.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
    _lifecycle = AppLifecycleListener(onResume: store.sync);
  }

  @override
  void dispose() {
    _tick.cancel();
    _lifecycle.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _add() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    store.addTask(text);
    _input.clear();
    _inputFocus.requestFocus();
  }

  void _complete(int index) {
    final t = store.data.active[index];
    store.complete(t);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('Archived "${t.title}"'),
        action: SnackBarAction(label: 'Undo', onPressed: () => store.restore(t, index)),
      ));
  }

  void _open(BuildContext context, page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  /// Wide enough (unfolded Fold, tablet, wide window) to show two panes.
  static const _twoPaneWidth = 600.0;

  void _select(Task? t) => setState(() => _selected = t);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        // Forget a selection whose task was deleted (e.g. on another device).
        final sel = _selected;
        if (sel != null && !store.data.active.contains(sel) && !store.data.archived.contains(sel)) {
          _selected = null;
        }
        return LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= _twoPaneWidth;
          final list = _listScaffold(context, wide);
          if (!wide) {
            final open = _selected;
            return PopScope(
              canPop: open == null,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) _select(null);
              },
              child: open == null
                  ? list
                  : TaskPage(key: ValueKey(open.id), store: store, task: open, onClose: () => _select(null)),
            );
          }
          final open = _selected;
          return Row(children: [
            Expanded(flex: 3, child: list),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 2,
              child: open == null
                  ? ArchivePage(store: store, embedded: true, onOpen: _select)
                  : TaskPage(key: ValueKey(open.id), store: store, task: open, onClose: () => _select(null)),
            ),
          ]);
        });
      },
    );
  }

  Widget _listScaffold(BuildContext context, bool wide) {
    final tasks = store.data.active;
    final now = DateTime.now();
    return Scaffold(
          appBar: AppBar(
            title: const Text('Tasks'),
            actions: [
              IconButton(
                tooltip: 'Archive',
                icon: Badge(
                  isLabelVisible: store.data.archived.isNotEmpty,
                  label: Text('${store.data.archived.length}'),
                  child: const Icon(Icons.inventory_2_outlined),
                ),
                // On wide screens the archive lives in the right-hand pane.
                onPressed: () => wide ? _select(null) : _open(context, ArchivePage(store: store)),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'csv') exportCsv(context, store);
                  if (v == 'sync') store.sync();
                  if (v == 'settings') _open(context, SettingsPage(store: store));
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'csv', child: Text('Export to CSV')),
                  if (store.dropbox != null)
                    const PopupMenuItem(value: 'sync', child: Text('Sync with Dropbox now')),
                  const PopupMenuItem(value: 'settings', child: Text('Settings')),
                ],
              ),
            ],
          ),
          body: Column(children: [
            Expanded(
              child: tasks.isEmpty
                  ? const Center(child: Text('No tasks. Type one below.'))
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      buildDefaultDragHandles: false,
                      itemCount: tasks.length,
                      onReorderItem: store.reorder,
                      itemBuilder: (context, i) {
                        final t = tasks[i];
                        return ReorderableDelayedDragStartListener(
                          key: ValueKey(t.id),
                          index: i,
                          child: TaskBlock(
                            task: t,
                            color: ageColor(t, store.data.hoursToRed, now),
                            selected: identical(_selected, t),
                            expanded: _expanded.contains(t.id),
                            onTap: () => setState(() =>
                                _expanded.contains(t.id) ? _expanded.remove(t.id) : _expanded.add(t.id)),
                            onOpen: () => _select(t),
                            onCheck: () => _complete(i),
                            trailing: ReorderableDragStartListener(
                              index: i,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Icon(Icons.drag_handle, color: Color(0x99000000)),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 4, 8),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _inputFocus,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Add a task…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  IconButton.filled(onPressed: _add, icon: const Icon(Icons.add)),
                ]),
              ),
            ),
          ]),
    );
  }
}

Future<void> exportCsv(BuildContext context, AppStore store) async {
  final messenger = ScaffoldMessenger.of(context);
  // BOM so Excel reads the file as UTF-8.
  final bytes = Uint8List.fromList(utf8.encode('﻿${buildCsv(store.data)}'));
  final name = 'tasks_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv';
  try {
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Export tasks',
      fileName: name,
      bytes: bytes,
      mimeType: 'text/csv',
    );
    if (saved != null) messenger.showSnackBar(SnackBar(content: Text('Exported $name')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}

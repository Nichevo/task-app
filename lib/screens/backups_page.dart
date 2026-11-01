import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../store.dart';

/// Settings, Backups: the daily backups of the last week, restoring one, and backup files.
class BackupsPage extends StatefulWidget {
  const BackupsPage({super.key, required this.store});

  final AppStore store;

  @override
  State<BackupsPage> createState() => _BackupsPageState();
}

class _BackupsPageState extends State<BackupsPage> {
  late Future<List<File>> _files = widget.store.backups();

  AppStore get store => widget.store;

  void _reload() => setState(() => _files = store.backups());

  /// "Tuesday 3 November 2026 · 42 open, 310 done" for a backup's text.
  static String _describe(String text) {
    final d = AppData.fromJson(jsonDecode(text) as Map<String, dynamic>);
    return '${d.active.length} open, ${d.archived.length} archived';
  }

  static String _title(File f) {
    final name = f.uri.pathSegments.last;
    final m = RegExp(r'tasks-(\d{4}-\d{2}-\d{2})(-before-restore)?').firstMatch(name);
    if (m == null) return name;
    final day = DateFormat('EEEE d MMMM yyyy').format(DateTime.parse(m.group(1)!));
    return m.group(2) == null ? day : '$day (before a restore)';
  }

  Future<void> _restore(String text, String what) async {
    String summary;
    try {
      summary = _describe(text);
    } catch (_) {
      _snack('That is not a Task Blocks backup.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text('$what\n$summary.\n\nEverything now in the app (tasks, archive, settings) is replaced by it, '
            'on every device that syncs. What is here now is kept as a backup first, so this can be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await store.restoreBackup(text);
      _snack('Restored. $summary.');
    } catch (e) {
      _snack('Restore failed: $e');
    }
    _reload();
  }

  Future<void> _saveFile() async {
    final name = 'task_blocks_backup_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json';
    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save a backup',
        fileName: name,
        bytes: Uint8List.fromList(utf8.encode(store.backupText())),
      );
      if (saved != null) _snack('Saved $name');
    } catch (e) {
      _snack('Could not save: $e');
    }
  }

  Future<void> _openFile() async {
    try {
      final picked = await FilePicker.pickFile(dialogTitle: 'Open a backup', type: FileType.custom, allowedExtensions: ['json']);
      if (picked == null) return;
      final text = utf8.decode(await picked.readAsBytes(), allowMalformed: true);
      await _restore(text, 'From ${picked.name}.');
    } catch (e) {
      _snack('Could not open: $e');
    }
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final hint = TextStyle(fontSize: 12, color: Theme.of(context).hintColor);
    return Scaffold(
      appBar: AppBar(title: const Text('Backups')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('The app saves a copy of everything once a day and keeps the last ${AppStore.backupDays} days on this '
            'device. Tap one to restore it.', style: hint),
        const SizedBox(height: 8),
        FutureBuilder<List<File>>(
          future: _files,
          builder: (context, snap) {
            final files = snap.data;
            if (files == null) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
            if (files.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No backups yet.'));
            return Column(children: [
              for (final f in files)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history),
                  title: Text(_title(f)),
                  trailing: const Icon(Icons.restore),
                  onTap: () async => _restore(await f.readAsString(), '${_title(f)}.'),
                ),
            ]);
          },
        ),
        const Divider(height: 32),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.save_alt),
          title: const Text('Save a backup file'),
          subtitle: const Text('Everything as one file, e.g. to keep somewhere safe or move to a new device'),
          onTap: _saveFile,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.file_open_outlined),
          title: const Text('Open a backup file'),
          subtitle: const Text('Restore from a file saved here or on another device'),
          onTap: _openFile,
        ),
      ]),
    );
  }
}

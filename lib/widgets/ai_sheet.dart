import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../ai_breakdown.dart';
import '../day_plan.dart' show describeLength;
import '../models.dart';
import '../store.dart';

/// Item 114 G: ✨ Break it down: asks the AI for steps, shows them to tick, and adds the ones
/// kept (with their lengths and links).
Future<int> showAiBreakdown(BuildContext context, AppStore store, Task t, {http.Client? client}) async {
  final added = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => _AiSheet(store: store, task: t, client: client),
  );
  return added ?? 0;
}

class _AiSheet extends StatefulWidget {
  const _AiSheet({required this.store, required this.task, this.client});
  final AppStore store;
  final Task task;
  final http.Client? client;

  @override
  State<_AiSheet> createState() => _AiSheetState();
}

class _AiSheetState extends State<_AiSheet> {
  List<AiStep>? _steps;
  final _picked = <int>{};
  String? _error;
  bool _busy = false;

  AppData get data => widget.store.data;
  String get _who => data.aiProvider == 'ollama' ? 'Ollama (${data.ollamaModel})' : 'Claude';

  @override
  void initState() {
    super.initState();
    _ask();
  }

  Future<void> _ask() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final steps = await breakDown(data, widget.task, claudeKey: widget.store.claudeKey, client: widget.client);
      if (!mounted) return;
      setState(() {
        _steps = steps;
        _picked
          ..clear()
          ..addAll([for (var i = 0; i < steps.length; i++) i]);
      });
    } on AiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13);
    final steps = _steps;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Break it down', style: theme.textTheme.titleLarge),
          Text('${widget.task.title} · asked $_who with its title, notes, category, due date and current steps', style: hint),
          const SizedBox(height: 12),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null && !_busy)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (steps != null && !_busy)
            for (var i = 0; i < steps.length; i++)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _picked.contains(i),
                onChanged: (v) => setState(() => v == true ? _picked.add(i) : _picked.remove(i)),
                title: Text(steps[i].title),
                subtitle: Text([
                  'about ${describeLength(steps[i].minutes)}',
                  if (steps[i].after.isNotEmpty) 'after ${steps[i].after.map((j) => '${j + 1}').join(', ')}',
                ].join(' · ')),
                secondary: CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
              ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            FilledButton(
              onPressed: steps == null || _picked.isEmpty || _busy
                  ? null
                  : () {
                      final n = widget.store.addAiSteps(widget.task, stepsFrom(steps, _picked, data));
                      Navigator.pop(context, n);
                    },
              child: Text('Add ${_picked.length} step${_picked.length == 1 ? '' : 's'}'),
            ),
            OutlinedButton(onPressed: _busy ? null : _ask, child: const Text('Try again')),
            TextButton(onPressed: () => Navigator.pop(context, 0), child: const Text('Cancel')),
          ]),
        ]),
      ),
    );
  }
}

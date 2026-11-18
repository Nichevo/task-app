import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../native.dart';
import '../store.dart';
import '../work_meetings.dart';
import '../widgets/day_plan_add.dart' show pickPlanItem;

/// Item 111: the blue work meetings are drawn in.
const workBlue = Color(0xFF3F6FB5);

/// Asks for a photo of the Outlook calendar, reads it and opens the check screen.
Future<void> importWorkMeetings(BuildContext context, AppStore store) async {
  final data = store.data;
  final upcoming = data.workMeetings.where((m) => m.end.isAfter(DateTime.now())).length;
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Import work meetings', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text('Take a photo of your Outlook calendar in Work week view. The app reads it on this '
              'device; the photo isn\'t kept or sent anywhere.'),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              subtitle: const Text('Point at your work screen'),
              onTap: () => Navigator.pop(c, ImageSource.camera),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose a photo or screenshot'),
              onTap: () => Navigator.pop(c, ImageSource.gallery),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0x33E0B040), borderRadius: BorderRadius.circular(10)),
            child: const Text(
              'For the best reading: straight on, the whole week and the hour labels in view. For '
              'early or late meetings, scroll Outlook and take a second photo; it only replaces the '
              'hours it shows.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          if (data.workMeetings.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '$upcoming meeting${upcoming == 1 ? '' : 's'} to come, last updated '
              '${DateFormat('EEE d MMM, HH:mm').format(data.workUpdatedAt.toLocal())}',
              style: TextStyle(fontSize: 12.5, color: Theme.of(c).hintColor),
            ),
          ],
        ]),
      ),
    ),
  );
  if (source == null || !context.mounted) return;
  await _readAndCheck(context, store, source);
}

Future<void> _readAndCheck(BuildContext context, AppStore store, ImageSource source) async {
  final messenger = ScaffoldMessenger.of(context);
  final file = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 90);
  if (file == null || !context.mounted) return;
  final nav = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Expanded(child: Text('Reading the photo…'))]),
    ),
  );
  ScreenRead read;
  try {
    read = await readPhoto(file.path);
  } catch (e) {
    nav.pop();
    messenger.showSnackBar(SnackBar(content: Text('Could not read the photo: $e')));
    return;
  }
  nav.pop();
  if (!context.mounted) return;
  if (!read.ok) {
    final again = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Couldn\'t read the calendar'),
        content: Text(read.problem!),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Try again')),
        ],
      ),
    );
    if (again == true && context.mounted) await _readAndCheck(context, store, source);
    return;
  }
  final retake = await nav.push<bool>(MaterialPageRoute(builder: (_) => WorkImportPage(store: store, read: read)));
  if (retake == true && context.mounted) await _readAndCheck(context, store, source);
}

/// The words of the last photo read and its size, for "Copy what was read" (sent to get the
/// reading fixed when it goes wrong).
(int, int, List<OcrWord>)? lastPhotoWords;

String _wordsJson() {
  final l = lastPhotoWords;
  if (l == null) return '';
  return jsonEncode({
    'w': l.$1,
    'h': l.$2,
    'words': [for (final x in l.$3) [x.text, x.l.round(), x.t.round(), x.r.round(), x.b.round()]],
  });
}

/// Reads the photo at [path]: its words on the device, then the meetings from them and its colours.
Future<ScreenRead> readPhoto(String path) async {
  final photo = await Native.readScreen(path);
  final bytes = await File(photo.path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final rgba = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final w = frame.image.width, h = frame.image.height;
  frame.image.dispose();
  // Should the decoded size differ from the one the words were read at, scale the words.
  final sx = w / photo.width, sy = h / photo.height;
  final words = [for (final x in photo.words) OcrWord(x.text, x.l * sx, x.t * sy, x.r * sx, x.b * sy)];
  lastPhotoWords = (w, h, words);
  final img = rgba == null ? null : RgbaImage(w, h, rgba.buffer.asUint8List());
  try {
    File(photo.path).deleteSync();
  } catch (_) {}
  return compute(_read, (words, img, DateTime.now()));
}

ScreenRead _read((List<OcrWord>, RgbaImage?, DateTime) a) => readWorkWeek(a.$1, image: a.$2, today: a.$3);

/// The check screen: what was read, by day, with what changed since the last photo of the same
/// days. Untick anything wrong, tap a row to correct it, then Add.
class WorkImportPage extends StatefulWidget {
  const WorkImportPage({super.key, required this.store, required this.read});
  final AppStore store;
  final ScreenRead read;

  @override
  State<WorkImportPage> createState() => _WorkImportPageState();
}

class _WorkImportPageState extends State<WorkImportPage> {
  late ScreenRead _read = widget.read;
  late List<WorkRow> _rows = compareImport(widget.store.data.workMeetings, _read);
  int _shift = 0;

  AppData get data => widget.store.data;

  void _moveWeek(int by) {
    setState(() {
      _shift += by;
      _read = widget.read.shiftWeeks(_shift);
      _rows = compareImport(data.workMeetings, _read);
    });
  }

  Future<void> _edit(WorkRow r) async {
    final m = r.meeting;
    final title = TextEditingController(text: m.title);
    var start = TimeOfDay.fromDateTime(m.start), end = TimeOfDay.fromDateTime(m.end);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Change this meeting'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Title'), autofocus: false),
            if (!m.allDay) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(context: c, initialTime: start);
                      if (t != null) set(() => start = t);
                    },
                    child: Text('Starts ${start.format(c)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(context: c, initialTime: end);
                      if (t != null) set(() => end = t);
                    },
                    child: Text('Ends ${end.format(c)}'),
                  ),
                ),
              ]),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Done')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      if (title.text.trim().isNotEmpty) m.title = title.text.trim();
      if (!m.allDay) {
        final d = m.day;
        m.start = DateTime(d.year, d.month, d.day, start.hour, start.minute);
        m.end = DateTime(d.year, d.month, d.day, end.hour, end.minute);
        if (!m.end.isAfter(m.start)) m.end = m.start.add(const Duration(minutes: 15));
      }
      r.check = null;
      r.keep = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hm = DateFormat('HH:mm');
    final adding = _rows.where((r) => r.keep && r.change != WorkChange.gone).length;
    final changes = {for (final c in WorkChange.values) c: _rows.where((r) => r.change == c).length};
    final days = _read.days;
    final range = days.isEmpty
        ? ''
        : '${DateFormat('EEE d MMM').format(days.first)} to ${DateFormat('EEE d MMM').format(days.last)}';
    final hadBefore = data.workMeetings.any((m) => coveredBy(m, _read));
    final list = <Widget>[
      Card(
        color: Color.alphaBlend(workBlue.withValues(alpha: 0.14), theme.colorScheme.surface),
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconButton(tooltip: 'A week earlier', icon: const Icon(Icons.chevron_left), onPressed: () => _moveWeek(-1)),
              Expanded(child: Text(range, textAlign: TextAlign.center, style: theme.textTheme.titleMedium)),
              IconButton(tooltip: 'A week later', icon: const Icon(Icons.chevron_right), onPressed: () => _moveWeek(1)),
            ]),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                [
                  if (hadBefore)
                    'Replaces the meetings from your last photo of these days'
                        '${_read.fromMinute > 0 || _read.toMinute < 24 * 60 ? ' (${_hhmm(_read.fromMinute)} to ${_hhmm(_read.toMinute)})' : ''}: '
                        '${changes[WorkChange.added]} new, ${changes[WorkChange.moved]} moved, ${changes[WorkChange.gone]} gone.'
                  else
                    'Wrong week? Use the arrows.',
                  if (_read.skipped > 0) '${_read.skipped} cancelled meeting${_read.skipped == 1 ? '' : 's'} left out.',
                ].join(' '),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ]),
        ),
      ),
    ];
    if (_rows.isEmpty) {
      list.add(const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No meetings found on these days. If there should be some, try a clearer, straight-on photo.'),
      ));
    }
    DateTime? lastDay;
    for (final r in _rows) {
      final m = r.meeting;
      if (lastDay == null || m.day != lastDay) {
        lastDay = m.day;
        list.add(Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
          child: Text(DateFormat('EEEE d MMMM').format(m.day), style: theme.textTheme.titleSmall?.copyWith(color: theme.hintColor)),
        ));
      }
      final linked = r.was == null ? null : data.linkedToMeeting(r.was!.id)?.$1;
      final gone = r.change == WorkChange.gone;
      list.add(Card(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        shape: r.check != null
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE6B45C), width: 1.5))
            : null,
        child: ListTile(
          onTap: gone ? null : () => _edit(r),
          leading: Checkbox(value: r.keep, onChanged: (v) => setState(() => r.keep = v ?? false)),
          title: Text(
            m.title,
            style: TextStyle(decoration: gone && !r.keep ? TextDecoration.lineThrough : null),
          ),
          subtitle: Text([
            m.allDay ? 'All day' : '${hm.format(m.start)} – ${hm.format(m.end)}',
            if (m.place != null) m.place!,
            if (r.check != null) r.check!,
            if (linked != null) gone && !r.keep ? 'Linked to "${linked.title}": its planned time goes' : 'Linked to "${linked.title}"',
          ].join(' · ')),
          trailing: switch (r.change) {
            WorkChange.added => const _Badge('New'),
            WorkChange.moved => const _Badge('Moved'),
            WorkChange.gone => const _Badge('Gone', bad: true),
            WorkChange.same => null,
          },
        ),
      ));
    }
    list.add(const SizedBox(height: 80));
    return Scaffold(
      appBar: AppBar(
        title: Text('${_rows.where((r) => r.change != WorkChange.gone).length} work meetings'),
        actions: [
          IconButton(tooltip: 'Take another photo', icon: const Icon(Icons.photo_camera_outlined), onPressed: () => Navigator.pop(context, true)),
          if (lastPhotoWords != null)
            PopupMenuButton<String>(
              onSelected: (_) async {
                await Clipboard.setData(ClipboardData(text: _wordsJson()));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied the words read from the photo, with where they are')));
                }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'copy', child: Text('Copy what was read'))],
            ),
        ],
      ),
      body: ListView(children: list),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Retake')),
            const Spacer(),
            FilledButton(
              onPressed: () {
                widget.store.importWork(_read, _rows);
                Navigator.pop(context, false);
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$adding work meeting${adding == 1 ? '' : 's'} added to your Day plan')));
              },
              child: Text(adding == 0 ? 'Save' : 'Add $adding meeting${adding == 1 ? '' : 's'}'),
            ),
          ]),
        ),
      ),
    );
  }
}

String _hhmm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.bad = false});
  final String text;
  final bool bad;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: bad ? const Color(0x33D32F2F) : Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500)),
      );
}

/// What can be done with a work meeting on the Day plan: link a task, make one, change it,
/// remove it, or import again.
Future<void> workMeetingSheet(BuildContext context, AppStore store, String meetingId) async {
  final m = store.data.workMeeting(meetingId);
  if (m == null) return;
  final hm = DateFormat('HH:mm');
  final link = store.data.linkedToMeeting(m.id);
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.work_outline, color: workBlue),
            title: Text(m.title),
            subtitle: Text([
              m.allDay
                  ? 'All day, ${DateFormat('EEE d MMM').format(m.start)}'
                  : '${DateFormat('EEE d MMM').format(m.start)}, ${hm.format(m.start)} – ${hm.format(m.end)}',
              if (m.place != null) m.place!,
              'From your photo of Outlook',
            ].join('\n')),
            isThreeLine: true,
          ),
          if (!m.allDay && link == null) ...[
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Link to a task or step…'),
              subtitle: const Text('It is planned into this meeting and moves with it'),
              onTap: () => Navigator.pop(c, 'link'),
            ),
            ListTile(
              leading: const Icon(Icons.add_task),
              title: const Text('Make a task from it'),
              onTap: () => Navigator.pop(c, 'task'),
            ),
          ],
          if (link != null)
            ListTile(
              leading: const Icon(Icons.link_off),
              title: Text('Unlink "${_linkName(link.$1, link.$2)}"'),
              subtitle: const Text('Takes the planned time off this meeting'),
              onTap: () => Navigator.pop(c, 'unlink'),
            ),
          if (!m.allDay)
            ListTile(leading: const Icon(Icons.schedule), title: const Text('Change the time or title'), onTap: () => Navigator.pop(c, 'edit')),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Remove this meeting'), onTap: () => Navigator.pop(c, 'remove')),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Import work meetings again'),
            onTap: () => Navigator.pop(c, 'import'),
          ),
        ]),
      ),
    ),
  );
  if (!context.mounted || choice == null) return;
  switch (choice) {
    case 'link':
      final p = await pickPlanItem(context, store.data, title: 'Link "${m.title}" to which task or step?', at: m.start);
      if (p == null || !context.mounted) return;
      final t = p.task;
      if (p.step != null) {
        store.linkMeeting(t, m, step: p.step);
        return;
      }
      final open = t.steps.where((x) => !x.done).toList();
      if (open.isEmpty) {
        store.linkMeeting(t, m);
        return;
      }
      // Item 113: the whole task, or one of its open steps.
      final pick = await showModalBottomSheet<Object>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            ListTile(title: Text('Link "${m.title}" to', style: Theme.of(c).textTheme.titleSmall)),
            ListTile(
              leading: const Icon(Icons.task_alt),
              title: Text(t.title),
              subtitle: const Text('The whole task'),
              onTap: () => Navigator.pop(c, t),
            ),
            for (final st in open)
              ListTile(
                leading: const Icon(Icons.subdirectory_arrow_right),
                title: Text(st.title),
                subtitle: Text('Step ${t.steps.indexOf(st) + 1} of ${t.steps.length}'),
                onTap: () => Navigator.pop(c, st),
              ),
          ]),
        ),
      );
      if (pick == null) return;
      store.linkMeeting(t, m, step: pick is TaskStep ? pick : null);
    case 'task':
      final t = store.taskFromMeeting(m);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Made "${t.title}", planned into the meeting')));
      }
    case 'unlink':
      if (link != null) store.unlinkMeeting(link.$1, link.$2);
    case 'edit':
      await _editMeeting(context, store, m);
    case 'remove':
      store.removeWorkMeeting(m);
    case 'import':
      await importWorkMeetings(context, store);
  }
}

Future<void> _editMeeting(BuildContext context, AppStore store, WorkMeeting m) async {
  final title = TextEditingController(text: m.title);
  var start = TimeOfDay.fromDateTime(m.start), end = TimeOfDay.fromDateTime(m.end);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Change this meeting'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final t = await showTimePicker(context: c, initialTime: start);
                  if (t != null) set(() => start = t);
                },
                child: Text('Starts ${start.format(c)}'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final t = await showTimePicker(context: c, initialTime: end);
                  if (t != null) set(() => end = t);
                },
                child: Text('Ends ${end.format(c)}'),
              ),
            ),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final d = m.day;
  store.updateWorkMeeting(m,
      title: title.text,
      start: DateTime(d.year, d.month, d.day, start.hour, start.minute),
      end: DateTime(d.year, d.month, d.day, end.hour, end.minute));
}

/// The linked task's title, or "step (task)" when the meeting is linked to one of its steps.
String _linkName(Task t, TimeSlot s) {
  final step = s.stepId == null ? null : t.steps.where((x) => x.id == s.stepId).firstOrNull;
  return step == null ? t.title : '${step.title} (${t.title})';
}

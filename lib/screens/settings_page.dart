import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dropbox.dart';
import '../google.dart';
import '../inbox_files.dart';
import '../input_parse.dart';
import '../location.dart';
import '../models.dart';
import '../native.dart';
import '../store.dart';
import '../task_list.dart';
import '../places.dart';
import 'about_page.dart';
import 'backups_page.dart';
import 'kanban_page.dart';
import 'places_page.dart';
import 'side_panel.dart' show PanelSettingsPage;
import '../widgets/task_colors.dart';

/// Choices for the extra reminder before a task is due, in minutes.
const remindOptions = {0: 'At due time only', 15: '15 min before', 60: '1 hour before', 1440: '1 day before', 10080: '1 week before'};

/// How far back the Starred emails page looks (days; 0 = all).
const starredDaysOptions = {7: '1 week', 30: '1 month', 91: '3 months', 0: 'All'};

/// Item 70: how often Gmail is checked for email tasks while the app is open (minutes; 0 = off).
const emailCheckOptions = {0: 'Off', 30: 'Every 30 minutes', 60: 'Every hour', 120: 'Every 2 hours'};

/// Item 60: when the "Urgent?" hint shows, in days before the due date.
const urgentDaysOptions = {0: 'Off', 1: '1 day', 2: '2 days', 3: '3 days', 7: '1 week', 14: '2 weeks'};

/// Asks for a line of text, e.g. a category name.
Future<String?> askText(BuildContext context, String title, {String initial = ''}) {
  final field = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: field,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.pop(c, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, field.text), child: const Text('OK')),
      ],
    ),
  );
}

/// Asks for several lines (one item per line), e.g. the steps of a template.
Future<List<String>?> askLines(BuildContext context, String title, {List<String> initial = const [], String hint = 'One step per line'}) {
  final field = TextEditingController(text: initial.join('\n'));
  return showDialog<List<String>>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: field,
        autofocus: true,
        minLines: 4,
        maxLines: 12,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(c, [for (final l in field.text.split('\n')) l.trim()].where((l) => l.isNotEmpty).toList()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Choices for how long closed tasks stay in the archive, in days (0 = forever).
const archiveKeepOptions = {0: 'Never', 30: '1 month', 90: '3 months', 180: '6 months', 365: '1 year'};

/// Choices for how far ahead to look in the calendar, in days.
const eventDaysOptions = {7: '1 week', 14: '2 weeks', 30: '1 month', 60: '2 months', 90: '3 months', 180: '6 months', 365: '1 year'};

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store});

  final AppStore store;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _key = TextEditingController(text: widget.store.dropboxAppKey);
  late final _gId = TextEditingController(text: widget.store.googleClientId);
  late final _gSecret = TextEditingController(text: widget.store.googleClientSecret);
  bool _gBusy = false;
  List<DeviceCalendar>? _calendars;

  AppStore get store => widget.store;
  AppData get data => store.data;

  @override
  void dispose() {
    _key.dispose();
    _gId.dispose();
    _gSecret.dispose();
    super.dispose();
  }

  int get _speedIndex {
    final h = data.hoursToRed;
    var best = 0;
    for (var i = 0; i < speedSteps.length; i++) {
      if ((speedSteps[i] - h).abs() < (speedSteps[best] - h).abs()) best = i;
    }
    return best;
  }

  void _set(VoidCallback change) {
    change();
    store.changed(settings: true);
  }

  Future<void> _connect() async {
    final key = _key.text.trim();
    if (key.isEmpty) return;
    store.dropboxAppKey = key;
    final client = DropboxClient(key);
    await launchUrl(client.authorizeUrl(), mode: LaunchMode.externalApplication);
    if (!mounted) return;
    final code = await showDialog<String>(
      context: context,
      builder: (c) {
        final field = TextEditingController();
        return AlertDialog(
          title: const Text('Paste the Dropbox code'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Approve access in the browser, then copy the code Dropbox shows and paste it here.'),
            TextField(controller: field, autofocus: true, decoration: const InputDecoration(labelText: 'Code')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, field.text), child: const Text('Connect')),
          ],
        );
      },
    );
    if (code == null || code.trim().isEmpty) return;
    try {
      await store.connectDropbox(client, code);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not connect: $e')));
      }
    }
  }

  /// Item 69: picks a device's saved settings from Dropbox and puts them on this one.
  Future<void> _restoreDevice() async {
    List<DeviceBackup> found;
    try {
      found = await store.deviceBackups();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not look: $e')));
      return;
    }
    if (!mounted) return;
    if (found.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No device settings saved in Dropbox yet. They are saved on each sync.')));
      return;
    }
    final fmt = DateFormat('d MMM HH:mm');
    final pick = await showDialog<DeviceBackup>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Restore settings from'),
        children: [
          for (final b in found)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, b),
              child: ListTile(
                title: Text('${b.device}${b.device == AppStore.deviceName ? ' (this kind of device)' : ''}'),
                subtitle: Text('Saved ${fmt.format(b.savedAt.toLocal())}: ${b.describe()}'),
              ),
            ),
        ],
      ),
    );
    if (pick == null) return;
    await store.restoreDeviceSettings(pick);
    _gId.text = store.googleClientId;
    _gSecret.text = store.googleClientSecret;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Settings from ${pick.device} restored')));
  }

  /// Item 53: Google sign-in in the browser; the answer comes back to the app by itself.
  Future<void> _connectGoogle() async {
    final id = _gId.text.trim(), secret = _gSecret.text.trim();
    if (id.isEmpty || secret.isEmpty) return;
    store.googleClientId = id;
    store.googleClientSecret = secret;
    setState(() => _gBusy = true);
    try {
      await store.connectGoogle((url) => launchUrl(url, mode: LaunchMode.externalApplication));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not sign in: $e')));
      }
    } finally {
      if (mounted) setState(() => _gBusy = false);
    }
  }

  Widget _googleSection(AppData data) {
    final g = store.google;
    final hint = TextStyle(fontSize: 12, color: Theme.of(context).hintColor);
    if (!googleSupported) {
      return Text('Google sign-in is on the phone, Windows and Mac for now; the iPad comes later.', style: hint);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (g == null) ...[
        Text(
          'One-time setup (about 10 minutes, steps in docs/GOOGLE.md on GitHub): in Google Cloud make a project, '
          'turn on the Gmail API, set up the consent screen for just you and publish it, then create an OAuth '
          'client of type "Desktop app". Copy its client ID and secret here. They stay on this device.',
          style: hint,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _gId,
          decoration: const InputDecoration(labelText: 'Client ID', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _gSecret,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Client secret', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _gBusy ? null : _connectGoogle,
          icon: _gBusy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.login),
          label: Text(_gBusy ? 'Waiting for the browser…' : 'Sign in with Google'),
        ),
        const SizedBox(height: 8),
        Text('The app asks to read emails and change their labels and stars. It cannot send or delete mail.',
            style: hint),
      ] else ...[
        Text('Signed in as ${g.email ?? 'your Google account'}'),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: store.disconnectGoogle, child: const Text('Sign out')),
      ],
      const SizedBox(height: 8),
      ..._emailTasksSection(data, hint),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Starred emails: look back'),
        subtitle: const Text('How far back the Starred emails page looks.'),
        trailing: DropdownButton<int>(
          value: starredDaysOptions.containsKey(data.starredDays) ? data.starredDays : 30,
          items: [
            for (final e in starredDaysOptions.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => _set(() => data.starredDays = v ?? 30),
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('After using a starred email'),
        subtitle: Text(data.starredAfter.label),
        trailing: PopupMenuButton<StarredAfter>(
          icon: const Icon(Icons.arrow_drop_down),
          onSelected: (v) => _set(() => data.starredAfter = v),
          itemBuilder: (_) => [for (final v in StarredAfter.values) PopupMenuItem(value: v, child: Text(v.label))],
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Line at the top of the list'),
        subtitle: const Text('"4 starred emails not yet tasks", checked when the app opens.'),
        value: data.starredLine,
        onChanged: (v) => _set(() => data.starredLine = v),
      ),
    ]);
  }

  /// Item 54: emails from allowed senders become tasks.
  List<Widget> _emailTasksSection(AppData data, TextStyle hint) {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final ignored = [for (final i in store.ignoredEmails) if (i.message.date == null || i.message.date!.isAfter(weekAgo)) i];
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Email to tasks'),
        subtitle: const Text('An email from an allowed sender whose subject starts with "Task" (or that has the '
            'label "Task") becomes a task, for example "Task: Pay council tax friday #Home". Checked when the app '
            'opens and on each sync; the email is then labelled "Tasked".'),
        value: data.emailTasks,
        onChanged: (v) {
          _set(() => data.emailTasks = v);
          if (v) store.checkEmailTasks(force: true);
        },
      ),
      if (data.emailTasks) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Also check while the app is open'),
          subtitle: const Text('Opening the app or coming back to it always checks. This is for a computer that '
              'stays open all day (this device only).'),
          trailing: DropdownButton<int>(
            value: emailCheckOptions.containsKey(store.emailCheckMinutes) ? store.emailCheckMinutes : 0,
            items: [for (final e in emailCheckOptions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => store.setEmailCheckMinutes(v ?? 0),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allowed senders'),
          subtitle: Text(data.allowedSenders.isEmpty
              ? 'None yet: no email can become a task'
              : data.allowedSenders.join(', ')),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () async {
            final lines = await askLines(context, 'Allowed senders',
                initial: data.allowedSenders,
                hint: 'One address per line. Write @example.com to allow a whole domain.');
            if (lines == null) return;
            _set(() => data.allowedSenders
              ..clear()
              ..addAll({for (final l in lines) if (l.trim().isNotEmpty) l.trim().toLowerCase()}));
          },
        ),
        Text('Emails from anyone else are never added. Gmail\'s own sender check (SPF or DKIM) must pass too, '
            'because the From line of an email can be faked.', style: hint),
        if (store.emailTasksNote != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(store.emailTasksNote!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (ignored.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('${ignored.length} ignored this week'),
            children: [
              for (final i in ignored)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(i.message.subject),
                  subtitle: Text('${i.message.from}\n${i.reason}'),
                  isThreeLine: true,
                  trailing: i.reason.startsWith('Not on')
                      ? TextButton(
                          onPressed: () => store.allowSender(i.message.address),
                          child: const Text('Allow this sender'))
                      : null,
                ),
            ],
          ),
        const SizedBox(height: 8),
      ],
    ];
  }

  Future<void> _editCategory(TaskCategory c) async {
    final name = TextEditingController(text: c.name);
    final keywords = TextEditingController(text: c.keywords.join(', '));
    final stages = data.stages;
    var board = c.boardByDefault;
    var stageId = data.stage(c.boardStage)?.id ?? stages.firstOrNull?.id;
    var steps = c.stepsOnBoard;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('Category'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 12),
              TextField(
                controller: keywords,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Keywords',
                  helperText: 'Separated by commas. A new task with one of these words always goes here.',
                  helperMaxLines: 2,
                ),
              ),
              if (stages.isNotEmpty) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('New tasks go on the board'),
                  subtitle: const Text('Also when a task is moved into this category'),
                  value: board,
                  onChanged: (v) => setInner(() => board = v),
                ),
                if (board) ...[
                  Row(children: [
                    const Text('Stage'),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: stageId,
                        items: [for (final s in stages) DropdownMenuItem(value: s.id, child: Text(s.name))],
                        onChanged: (v) => setInner(() => stageId = v),
                      ),
                    ),
                  ]),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Steps on the board too'),
                    value: steps,
                    onChanged: (v) => setInner(() => steps = v ?? false),
                  ),
                ],
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (name.text.trim().isNotEmpty) store.renameCategory(c, name.text);
    store.setKeywords(c, keywords.text.split(','));
    final turnedOn = board && !c.boardByDefault;
    store.setCategoryBoard(c, on: board, stageId: stageId, steps: steps);
    final off = store.offBoardIn(c);
    if (!turnedOn || off.isEmpty || !mounted) return;
    final all = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text('Put your ${off.length} open ${c.name} task${off.length == 1 ? '' : 's'} on the board now?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Only new ones')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Put them on')),
        ],
      ),
    );
    if (all == true) store.boardAllIn(c);
  }

  /// Item 60: the matrix box names and the "Urgent?" hint.
  List<Widget> _matrixSection(AppData data) => [
        _heading('Matrix'),
        Text('Only tasks you put on the matrix show there. Tap a box to rename it.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
        for (final b in MatrixBox.values)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.grid_view),
            title: Text(data.boxName(b)),
            subtitle: Text(b.meaning),
            onTap: () async {
              final n = await askText(context, 'Name for "${b.meaning}"', initial: data.boxName(b));
              if (n != null) store.setBoxName(b, n);
            },
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.priority_high),
          title: const Text('"Urgent?" hint'),
          subtitle: const Text('On a task in a not-urgent box when its due date is close'),
          trailing: DropdownButton<int>(
            value: urgentDaysOptions.containsKey(data.urgentDays) ? data.urgentDays : 0,
            items: [for (final e in urgentDaysOptions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => store.setUrgentDays(v ?? 0),
          ),
        ),
      ];

  /// Item 64: every word the add box understands, in one place.
  List<Widget> _quickWordsSection(AppData data) {
    final hint = TextStyle(fontSize: 12, color: Theme.of(context).hintColor);
    final cats = data.categories.map((c) => '#${c.name.toLowerCase().replaceAll(' ', '')}').join(', ');
    return [
      _heading('Quick-add words'),
      Text('Words you can type in the add box. They come off the task name.', style: hint),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.tag),
        title: const Text('#category'),
        subtitle: Text(cats.isEmpty ? 'Puts it in that category (add categories above)' : 'Puts it in that category: $cats'),
      ),
      const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.event_outlined),
        title: Text('Dates and times'),
        subtitle: Text('today, tomorrow, friday, next week, 20 nov, 3pm, in 2 days'),
      ),
      for (final w in QuickWord.values)
        Builder(builder: (context) {
          final word = quickWord(data, w);
          final what = w.box == null ? w.what : '${w.what} ${data.boxName(w.box!)}';
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bolt_outlined),
            title: Text(word == null ? 'Off' : '!$word',
                style: TextStyle(color: word == null ? Theme.of(context).disabledColor : null)),
            subtitle: Text(what),
            onTap: word == null
                ? null
                : () async {
                    final n = await askText(context, 'Word for: $what', initial: word);
                    if (n == null) return;
                    store.setQuickWord(w.id, n.trim().isEmpty ? null : n);
                  },
            trailing: Switch(
              value: word != null,
              onChanged: (on) => store.setQuickWord(w.id, on ? null : ''),
            ),
          );
        }),
    ];
  }

  Future<void> _loadCalendars() async {
    if (!await Native.requestCalendarAccess()) return;
    final cals = await Native.calendars();
    if (mounted) setState(() => _calendars = cals);
  }

  Future<TimeOfDay?> _pickTime(int minutes) =>
      showTimePicker(context: context, initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60));

  static const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  static String _time(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final idx = _speedIndex;
        final connected = store.dropbox != null;
        final sample = DateTime.now();
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            _heading('Colour speed'),
            Text('Tasks go from green to red in ${describeHours(speedSteps[idx])}.'),
            Slider(
              value: idx.toDouble(),
              min: 0,
              max: (speedSteps.length - 1).toDouble(),
              divisions: speedSteps.length - 1,
              label: describeHours(speedSteps[idx]),
              onChanged: (v) => _set(() => data.hoursToRed = speedSteps[v.round()]),
            ),
            // Preview of the colour a task has at each fifth of the way to red.
            Row(children: [
              for (var i = 0; i <= 5; i++)
                Expanded(
                  child: Container(
                    height: 22,
                    color: ageColor(
                      Task(id: '', title: '', createdAt: sample.subtract(
                          Duration(minutes: (data.hoursToRed * 60 * i / 5).round()))),
                      data.hoursToRed,
                      now: sample,
                    ),
                  ),
                ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Colour by due date'),
              subtitle: const Text('Tasks with a due date turn red as the due date gets closer, '
                  'instead of by the speed above.'),
              value: data.colourByDue,
              onChanged: (v) => _set(() => data.colourByDue = v),
            ),
            const Divider(height: 40),
            _heading('List'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sort by'),
              subtitle: Text(data.sort == ListSort.manual
                  ? 'Drag the handle on a task to move it.'
                  : 'Dragging a task switches to hand-made order, keeping the order you see.'),
              trailing: DropdownButton<ListSort>(
                value: data.sort,
                items: [
                  for (final e in sortLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => _set(() => data.sort = v ?? ListSort.due),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Starred at the top'),
              subtitle: const Text('Starred tasks come first, in the order above.'),
              value: data.starredTop,
              onChanged: (v) => _set(() => data.starredTop = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Quick filters above the list'),
              subtitle: const Text('All, Today, Next 7 days, Next 2 weeks, Next 30 days, Overdue, Starred, No date. '
                  'Each device remembers its own choice.'),
              value: data.showQuickFilters,
              onChanged: (v) => _set(() => data.showQuickFilters = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Group by category'),
              subtitle: const Text('Show a bold heading for each category with its tasks underneath. '
                  'Tap a heading to collapse it; drag a task under another heading to move it.'),
              value: data.groupByCategory,
              onChanged: (v) => _set(() => data.groupByCategory = v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto category'),
              subtitle: const Text('For a new task with no #tag: learn from tasks already filed and from '
                  'category keywords. Everything stays on this device.'),
              trailing: DropdownButton<AutoCategory>(
                value: data.autoCategory,
                items: const [
                  DropdownMenuItem(value: AutoCategory.off, child: Text('Off')),
                  DropdownMenuItem(value: AutoCategory.suggest, child: Text('Suggest')),
                  DropdownMenuItem(value: AutoCategory.apply, child: Text('Apply')),
                ],
                onChanged: (v) => _set(() => data.autoCategory = v ?? AutoCategory.suggest),
              ),
            ),
            const Divider(height: 40),
            _heading('Reminders'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Before the due time'),
              subtitle: const Text('Default for tasks with a due date (each task can change it)'),
              trailing: DropdownButton<int>(
                value: remindOptions.containsKey(data.defaultRemindBefore) ? data.defaultRemindBefore : 0,
                items: [for (final e in remindOptions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => _set(() => data.defaultRemindBefore = v ?? 0),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Overdue tasks'),
              subtitle: Text(switch (data.overdueMode) {
                OverdueMode.off => 'No extra reminders once a task is overdue.',
                OverdueMode.daily => 'One summary a day at ${_time(data.overdueAt)} listing what is overdue.',
                OverdueMode.nudge => 'A reminder every ${data.nudgeHours} hour${data.nudgeHours == 1 ? '' : 's'} per overdue task until it is done or snoozed.',
              }),
              trailing: DropdownButton<OverdueMode>(
                value: data.overdueMode,
                items: const [
                  DropdownMenuItem(value: OverdueMode.off, child: Text('Off')),
                  DropdownMenuItem(value: OverdueMode.daily, child: Text('Daily summary')),
                  DropdownMenuItem(value: OverdueMode.nudge, child: Text('Keep nudging')),
                ],
                onChanged: (v) => _set(() => data.overdueMode = v ?? OverdueMode.off),
              ),
            ),
            if (data.overdueMode == OverdueMode.daily)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Summary time'),
                trailing: Text(_time(data.overdueAt)),
                onTap: () async {
                  final t = await _pickTime(data.overdueAt);
                  if (t != null) _set(() => data.overdueAt = t.hour * 60 + t.minute);
                },
              ),
            if (data.overdueMode == OverdueMode.nudge) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Nudge every'),
                trailing: DropdownButton<int>(
                  value: const [1, 3, 6].contains(data.nudgeHours) ? data.nudgeHours : 3,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 hour')),
                    DropdownMenuItem(value: 3, child: Text('3 hours')),
                    DropdownMenuItem(value: 6, child: Text('6 hours')),
                  ],
                  onChanged: (v) => _set(() => data.nudgeHours = v ?? 3),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Quiet hours'),
                subtitle: Text('No nudges from ${_time(data.quietStart)} to ${_time(data.quietEnd)}'),
                onTap: () async {
                  final from = await _pickTime(data.quietStart);
                  if (from == null || !mounted) return;
                  final to = await _pickTime(data.quietEnd);
                  if (to == null) return;
                  _set(() {
                    data.quietStart = from.hour * 60 + from.minute;
                    data.quietEnd = to.hour * 60 + to.minute;
                  });
                },
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Weekly review'),
              subtitle: Text(data.weeklyReview
                  ? 'Every ${_weekdays[data.weeklyDay - 1]} at ${_time(data.weeklyAt)}: last week\'s added and done, '
                      'what is overdue and what is due next. Tap it to see the next 7 days.'
                  : 'A note once a week with last week\'s numbers and what is coming up.'),
              value: data.weeklyReview,
              onChanged: (v) => _set(() => data.weeklyReview = v),
            ),
            if (data.weeklyReview)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Review day and time'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButton<int>(
                    value: data.weeklyDay,
                    items: [
                      for (final (i, d) in _weekdays.indexed) DropdownMenuItem(value: i + 1, child: Text(d)),
                    ],
                    onChanged: (v) => _set(() => data.weeklyDay = v ?? DateTime.sunday),
                  ),
                  TextButton(
                    onPressed: () async {
                      final t = await _pickTime(data.weeklyAt);
                      if (t != null) _set(() => data.weeklyAt = t.hour * 60 + t.minute);
                    },
                    child: Text(_time(data.weeklyAt)),
                  ),
                ]),
              ),
            Text('Every reminder has Done and Snooze buttons.', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
            const Divider(height: 40),
            Row(children: [
              Expanded(child: _heading('Categories')),
              TextButton.icon(
                onPressed: () async {
                  final name = await askText(context, 'New category');
                  if (name != null && name.trim().isNotEmpty) store.addCategory(name);
                },
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ]),
            if (data.categories.isEmpty)
              const Text('No categories yet. Add some, then pick one in each task or type #name when adding.'),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: store.moveCategory,
              children: [
                for (final (i, c) in data.categories.indexed)
                  ListTile(
                    key: ValueKey(c.id),
                    contentPadding: EdgeInsets.zero,
                    leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                    title: Text(c.name),
                    subtitle: c.keywords.isEmpty ? null : Text('Keywords: ${c.keywords.join(', ')}'),
                    onTap: () => _editCategory(c),
                    trailing: IconButton(
                      tooltip: 'Delete category (its tasks are kept)',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => store.deleteCategory(c),
                    ),
                  ),
              ],
            ),
            const Divider(height: 40),
            ..._quickWordsSection(data),
            const Divider(height: 40),
            ..._matrixSection(data),
            const Divider(height: 40),
            Row(children: [
              Expanded(child: _heading('Checklist templates')),
              TextButton.icon(
                onPressed: () async {
                  final name = await askText(context, 'Template name');
                  if (name == null || name.trim().isEmpty || !context.mounted) return;
                  final lines = await askLines(context, 'Steps for "${name.trim()}"');
                  if (lines != null && lines.isNotEmpty) store.saveTemplate(name, lines);
                },
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ]),
            if (data.templates.isEmpty)
              const Text('Save a task\'s checklist as a template from the Templates button on the task, '
                  'then add it to any task in one tap.'),
            for (final t in data.templates)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.checklist),
                title: Text(t.name),
                subtitle: Text(t.steps.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () async {
                  final lines = await askLines(context, t.name, initial: t.steps);
                  if (lines != null) store.updateTemplate(t, steps: lines);
                },
                trailing: Wrap(children: [
                  IconButton(
                    tooltip: 'Rename',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final name = await askText(context, 'Template name', initial: t.name);
                      if (name != null && name.trim().isNotEmpty) store.updateTemplate(t, name: name);
                    },
                  ),
                  IconButton(
                    tooltip: 'Delete template',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => store.deleteTemplate(t),
                  ),
                ]),
              ),
            if (Native.supported) ...[
              const Divider(height: 40),
              _heading('Calendar events'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Suggest tasks from events'),
                subtitle: const Text('Upcoming events is always in the menu. This also shows a line at the top of the '
                    'list now and then, which you can dismiss.'),
                trailing: DropdownButton<EventSuggest>(
                  value: data.eventSuggest,
                  items: const [
                    DropdownMenuItem(value: EventSuggest.off, child: Text('Only when I look')),
                    DropdownMenuItem(value: EventSuggest.daily, child: Text('Once a day')),
                    DropdownMenuItem(value: EventSuggest.weekly, child: Text('Once a week')),
                  ],
                  onChanged: (v) => _set(() => data.eventSuggest = v ?? EventSuggest.off),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Look ahead'),
                subtitle: const Text('How far into the calendar to look for events to make tasks from.'),
                trailing: DropdownButton<int>(
                  value: data.eventDays,
                  items: [
                    for (final e in {...eventDaysOptions, data.eventDays: '${data.eventDays} days'}.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => _set(() => data.eventDays = v ?? 14),
                ),
              ),
              if (_calendars == null)
                TextButton.icon(
                  onPressed: _loadCalendars,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(data.eventCalendars.isEmpty ? 'Choose calendars (all for now)' : 'Choose calendars (${data.eventCalendars.length} chosen)'),
                )
              else ...[
                const Text('Calendars to take events from (none ticked = all):'),
                for (final c in _calendars!)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(c.name),
                    subtitle: Text(c.account),
                    value: data.eventCalendars.contains(c.id),
                    onChanged: (v) => _set(() => v == true ? data.eventCalendars.add(c.id) : data.eventCalendars.remove(c.id)),
                  ),
              ],
              const Divider(height: 40),
              Row(children: [
                Expanded(child: _heading('Suggestions from notifications')),
                Chip(label: const Text('Coming later'), visualDensity: VisualDensity.compact, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest),
              ]),
              Text(
                'Planned: watch notifications from a few apps you choose (deliveries, appointments, bills) and '
                'offer them as tasks. Not built yet, so these are switched off.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
              ),
              const SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Suggest tasks from notifications'),
                value: false,
                onChanged: null,
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: false,
                title: Text('Apps to watch'),
                subtitle: Text('None chosen'),
                trailing: Icon(Icons.chevron_right),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: false,
                title: Text('Look for'),
                subtitle: Text('Dates and times; appointment, due, deliver, renew, pay'),
                trailing: Icon(Icons.chevron_right),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: false,
                title: Text('Where suggestions go'),
                subtitle: Text('The same list as calendar event suggestions'),
              ),
            ],
            if (LocationRecorder.supported) ...[
              const Divider(height: 40),
              _heading('Location'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Record where tasks are added and done'),
                subtitle: const Text('Saves the location with each task when you add it and when you tick it off, '
                    'ready for place-based reminders later. Shown on the task page; synced with your tasks.'),
                value: store.recordLocation,
                onChanged: (v) async {
                  final ok = await store.setRecordLocation(v);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Location access was not allowed. You can allow it in the phone\'s settings.')));
                  }
                },
              ),
            ],
            if (PlaceReminders.supported)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined),
                title: const Text('Places'),
                subtitle: Text(store.places.isEmpty
                    ? 'Reminders when you arrive at or leave a place'
                    : store.places.map((p) => p.name).join(', ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlacesPage(store: store))),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.vertical_split_outlined),
              title: const Text('Right-hand panel'),
              subtitle: Text('On wide screens: starts on ${store.panelStart.label}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PanelSettingsPage(store: store))),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.view_kanban_outlined),
              title: const Text('Kanban board'),
              subtitle: Text(data.stages.map((s) => s.name).join(', ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => KanbanSettingsPage(store: store))),
            ),
            const Divider(height: 40),
            _heading('Archive'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Delete archived tasks after'),
              subtitle: const Text('Statistics keep counting tasks after they are deleted.'),
              trailing: DropdownButton<int>(
                value: archiveKeepOptions.containsKey(data.archiveKeepDays) ? data.archiveKeepDays : 0,
                items: [
                  for (final e in archiveKeepOptions.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => _set(() => data.archiveKeepDays = v ?? 0),
              ),
            ),
            const Divider(height: 40),
            _heading('Dropbox sync'),
            Text('Status: ${store.syncStatus}'),
            const SizedBox(height: 12),
            if (!connected) ...[
              const Text(
                'One-time setup: at dropbox.com/developers/apps create an app with '
                '"Scoped access" and "App folder". On its Permissions tab tick '
                'files.content.read, files.content.write and files.metadata.read, then copy the App key here.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _key,
                decoration: const InputDecoration(labelText: 'Dropbox app key', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _connect,
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('Connect Dropbox'),
              ),
            ] else
              Wrap(spacing: 12, children: [
                FilledButton.icon(
                  onPressed: store.syncing ? null : store.sync,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync now'),
                ),
                OutlinedButton(onPressed: store.disconnectDropbox, child: const Text('Disconnect')),
              ]),
            if (connected)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _restoreDevice,
                  icon: const Icon(Icons.settings_backup_restore),
                  label: const Text('Restore settings from a device'),
                ),
              ),
            if (connected)
              Text(
                'Most settings sync with your tasks. The ones kept on each device (places, list and board view choices, '
                'location recording, the Google client ID and secret) are saved to Dropbox too, in the devices folder. '
                'Sign-ins are not.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
              ),
            if (store.inboxFolderNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(store.inboxFolderNote!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (connected)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(const ClipboardData(text: inboxExample));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Example inbox file copied')));
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy an example inbox file'),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Your tasks are saved to Apps/<your app name>/tasks.json in Dropbox. '
              'Connect the same app key on your phone and PC to share one list.\n\n'
              'Inbox: any line written to Apps/<your app name>/inbox.txt becomes a task on the next sync '
              '(handy with email-to-Dropbox, IFTTT or Zapier). Dates and #categories in the line are read too.\n\n'
              'Inbox folder: tools can also drop one .json file per task into Apps/<your app name>/inbox/ '
              '(title, notes, due, category, steps, source, ref; format in docs/PUSH_TASKS.md). Each file is '
              'deleted once added; one that can\'t be read goes to inbox/failed. A repeated "ref" is never '
              'added twice.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
            ),
            const Divider(height: 40),
            _heading('Google'),
            _googleSection(data),
            const Divider(height: 40),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history),
              title: const Text('Backups'),
              subtitle: const Text('A copy every day for the last week; restore one, or save and open backup files'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BackupsPage(store: store))),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline),
              title: const Text('About Task Blocks'),
              subtitle: const Text('Version, what\'s new in each version, and the project on GitHub'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutPage())),
            ),
          ]),
        );
      },
    );
  }
}

/// What changed in each version, newest first. Shown in Settings, About and once after an
/// update as "What's new". Add the new version at the top whenever pubspec.yaml's version changes.
class Release {
  const Release(this.version, this.date, this.changes);

  final String version;
  final String date;
  final List<String> changes;
}

const releases = [
  Release('1.7.1', 'November 2026', [
    'Email to tasks (Settings, Google): an email from one of your allowed senders whose subject starts with "Task" (or that has the Gmail label "Task") becomes a task. "Task: Pay council tax friday #Home" reads the date and category.',
    'Only addresses you allow, and only when Gmail\'s own sender check passes, so a faked From line is ignored. Settings lists what was ignored this week, with "Allow this sender".',
    'Used emails get the label "Tasked" and are never added twice, even by two devices at once.',
    'Dropbox inbox folder: tools like Zapier can drop one .json file per task into Apps/<app>/inbox/ (format in docs/PUSH_TASKS.md). Needs the files.metadata.read permission on the Dropbox app.',
  ]),
  Release('1.7.0', 'November 2026', [
    'Google sign-in (Settings, Google) on the phone, Windows and Mac. Setup steps are in docs/GOOGLE.md. The app can read emails and change stars and labels, never send or delete.',
    'Starred emails (menu): your starred Gmail emails, with Make task, Attach to task and Hide on each.',
    'Tasks keep the emails they came from or were attached to, in a new Emails section with Open in Gmail. An envelope on the block shows which tasks have them.',
    'Settings: how far back to look, what happens to the star afterwards (keep, remove, or remove and label "Tasked"), and an optional line at the top of the list.',
    'CSV export adds an Emails column and a task_emails file; importing that file puts the emails back.',
  ]),
  Release('1.6.2', 'November 2026', [
    'Safer syncing between versions: if another device has a newer Task Blocks, this one keeps everything the newer version added instead of dropping it, and writes it back unchanged.',
    'A note at the top of the list says when another device has a newer version, so you know to update this one.',
    'Before an older version saves over data from a newer one, a copy is kept in Dropbox (backups folder, last 5 days).',
    'iPad and Mac: new app id. Install this version once next to the old one, connect Dropbox again and let it sync, then delete the old copy.',
  ]),
  Release('1.6.1', 'November 2026', [
    'Dragging tasks up and down works again whatever the list is sorted by. Dropping a task in a sorted list switches to hand-made order, keeping the order you saw (Undo puts the sort back).',
    'A note explains when "Starred at the top" moves a dropped task back.',
  ]),
  Release('1.6.0', 'November 2026', [
    'Kanban board: a task\'s checklist steps can be cards too (task page, "Steps on the board too"), each moving through the stages by itself.',
    'Steps start folded into a chip on their task\'s card; tap it, or "Show all steps" at the top, to unfold them. Steps in another column sit together under their task\'s name.',
    'Lanes view on wide screens: one row per task with steps, so a task and its steps read left to right.',
    'Moving a step to Done ticks it and ticking it in the checklist moves it to Done. Moving the task to Done with open steps asks what to do with them.',
    'Each step keeps its own board history; Statistics and kanban_moves.csv count step moves separately.',
  ]),
  Release('1.5.0', 'November 2026', [
    'Kanban board (menu, Kanban board): Backlog, Up next, In progress, Blocked and Done columns. Put a task on it from the task page or "Add to board" on its block.',
    'Move cards by dragging or swiping (side by side on wide screens), the arrow on each card, or Move to… with a short note.',
    'Every move is kept on the task (Board history): from and to, when, how long it sat, how, which device, and where if location recording is on.',
    'Moving to Done can tick the task off too (ask, always or never). Stages, colours and limits in Settings, Kanban board.',
    'Statistics: time in each stage, moves a week, tasks moved backwards. CSV export adds a Stage column and kanban_moves.csv.',
  ]),
  Release('1.4.2', 'November 2026', [
    'Place reminders (Android): save places where you are, then have a task remind you when you arrive or leave.',
    'Optional notification with the day\'s tasks when you arrive at a saved place.',
    'Daily backups kept for a week (Settings, Backups), with restore, and backup files to save or open.',
  ]),
  Release('1.4.1', 'November 2026', [
    'Statistics: where tasks came from, with the share of each source that got done.',
    'Statistics: repeating tasks with how often each was done, skipped or missed.',
    'Statistics: how early or late tasks get done against their due date.',
    'Statistics: charts of tasks added, and added against done with a line for what is still open, by category.',
    'Optional weekly review notification (Settings, Reminders).',
  ]),
  Release('1.4.0', 'November 2026', [
    'Skip a repeating task: moves it to its next date without ticking it off (in the block, on the task, and on its reminder).',
    'Search: the magnifying glass at the top looks through task names, notes and checklists.',
    'Sorting in Settings: hand-made order, due date, colour age, newest first, or category then due date, with starred tasks at the top.',
    'Quick filters above the list: All, Today, Next 7 days, Next 2 weeks, Next 30 days, Overdue, Starred, No date.',
    'Web links, email addresses and phone numbers in notes can be tapped.',
    'Time estimates on tasks, with the total for the tasks shown.',
    'This About page and "What\'s new" after each update.',
  ]),
  Release('1.3.5', '1 November 2026', [
    'Each task remembers where it came from (typed, widget, voice, calendar, ...).',
    'Optionally records where a task was added and ticked off.',
    'Calendar look-ahead can go up to a year.',
    'First iPad build.',
  ]),
  Release('1.3.4', '31 October 2026', ['Fixed garbled text in expanded blocks on the Mac.']),
  Release('1.3.3', '30 October 2026', ['First Mac build.']),
  Release('1.3.2', '30 October 2026', ['Every-N-weeks repeats can be set to chosen weekdays.']),
  Release('1.3.1', '29 October 2026', [
    'Fixed squashed reminder and category choices in the right-hand pane.',
    'Fixed widgets going blank for a while after folding the phone.',
  ]),
  Release('1.3.0', '28 October 2026', [
    'Statistics page and calendar view.',
    'Tasks from calendar events.',
    'Reusable checklists, which can be turned into tasks of their own.',
    'Automatic categories, and more ways to add tasks: share, paste a list, Google Assistant, photo of a list, Dropbox inbox.',
    'Overdue reminders and more home screen widgets.',
  ]),
  Release('1.0.0', '28 October 2026', [
    'Coloured task blocks that go from green to red, drag to reorder, tick off to the archive.',
    'Dropbox sync, CSV export and import.',
    'Two panes on the unfolded Fold and wide screens.',
    'Due-date reminders, swipe to tick off or delete.',
    'Categories, repeats, linked tasks, quick dates, stars, snooze and home screen widgets.',
  ]),
];

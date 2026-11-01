/// What changed in each version, newest first. Shown in Settings, About and once after an
/// update as "What's new". Add the new version at the top whenever pubspec.yaml's version changes.
class Release {
  const Release(this.version, this.date, this.changes);

  final String version;
  final String date;
  final List<String> changes;
}

const releases = [
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

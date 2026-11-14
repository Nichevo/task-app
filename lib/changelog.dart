/// What changed in each version, newest first. Shown in Settings, About and once after an
/// update as "What's new". Add the new version at the top whenever pubspec.yaml's version changes.
class Release {
  const Release(this.version, this.date, this.changes);

  final String version;
  final String date;
  final List<String> changes;
}

const releases = [
  Release('1.10.17', 'November 2026', [
    'Kanban board: new "Ring" card shading. A small ring by the menu button shows time left round the outside (dashed once overdue) and work done filling the inside like a pie. Pick it from the board\'s shading button or Settings, Kanban board, for task cards, step cards or both.',
    'Fills up now fills step cards the same way as task cards: the done part of the step in its task\'s colour, the rest pale, with the time strip along the bottom edge. A ticked step is full. A step fills from its own "how far along", so a step with none set stays pale until it is ticked.',
  ]),
  Release('1.10.16', 'November 2026', [
    'Snoozing from a reminder\'s buttons now sets the "Snoozed task" reminder straight away, so it comes when the snooze ends even if you don\'t open the app in between.',
    'iPad widgets: a snoozed task comes back at the time its snooze ends, not up to a few hours later. Snooze on a widget also reminds you at 8am, and the task returns to the widgets then without opening the app.',
    'iPad: the Done and snooze buttons on a reminder keep working right after you install a new version, before the app is opened.',
    'iPad Chart widget: "Task (burn-down)" lists only the tasks that have a burn-down, as on Android.',
  ]),
  Release('1.10.15', 'November 2026', [
    'Kanban board: a new shading button in the top bar picks the card shading right there, without going to Settings.',
    'Step cards can be shaded differently from task cards, for example On pace for tasks and Off for steps. Choose under "Step cards" on the same button, or Settings, Kanban board, "Step card shading". They follow the task cards until you pick.',
  ]),
  Release('1.10.14', 'November 2026', [
    'Snoozing a reminder (1 hour, This evening, Tomorrow, or Snooze on a widget) now reminds you again when the snooze ends. Before, the task only came back in the list without a notification.',
    'Tapping a task\'s reminder opens that task, not just the list.',
    'The daily overdue summary is worked out fresh for each day, so it no longer repeats an old list.',
    'If the saved tasks file is ever damaged, the app opens the newest backup instead of an empty list, keeps the damaged file, and tells you at the top of the list.',
    'Sync: a category, board column or checklist template added on one device is no longer lost when another device changes a setting at the same time. Collapsing a heading or grouping by category no longer counts as a settings change.',
    'Sync: when two devices save to Dropbox at the same moment, the second one now merges again instead of saving over the first. Lines in inbox.txt and files in the inbox folder are never lost or added twice.',
    'An open task page now updates when a widget, a notification or a sync changes the task, and your edits are always kept.',
    'Snoozed tasks come back on the home screen widgets when the snooze ends, without opening the app.',
    'Archived tasks are read-only, with a Move back to tasks button on the task page.',
    'Smaller fixes: device settings are saved more safely, a tick on a widget at the moment the app opens is no longer missed, deleted tasks stay deleted on a device that has not synced for months, a deleted email task is not made again from the same email, and less battery is used while event suggestions are on.',
  ]),
  Release('1.10.13', 'November 2026', [
    'Kanban board: cards now show how far a task has got and how much time is left before it is due. Pick the look in Settings, Kanban board, "Card shading": Fills up (the done part of the card in full colour, a strip along the bottom for time left), Two bars (work done and time left), On pace (one bar with a tick for time gone; the default) or Off.',
    'Each card says whether the task is behind, on pace or ahead: the work done (steps ticked, with half-done steps counting for their progress) against the time gone since it started. Overdue tasks say Overdue.',
    'Steps on the board are shaded the same way, by their own progress and their own due date.',
    'New "Behind" filter above the main list, the board and the matrix, and in search, for tasks that are overdue or have less done than the time gone. In the main list they show a small hourglass.',
  ]),
  Release('1.10.12', 'November 2026', [
    'Edit all steps: the Starts, Days of work and Progress columns (and the timeline under the steps) now show for every task, not only for tasks on the Gantt chart. Tap a step\'s start to set it, or tick several steps and tap Start.',
    'A step\'s menu on the task page now always offers "Start, days of work and progress", not only on Gantt tasks.',
  ]),
  Release('1.10.10', 'November 2026', [
    'Each task with two or more steps and a date to finish by now has its own burn-down: steps left each day against a dashed ideal line, and when it will be done at this pace. Open "Burn-down" on the task page (under the checklist) or in Edit all steps. Count steps or days of work. The task doesn\'t need to be on the Gantt chart.',
    'On the Gantt chart, zoom to one task and the burn-down strip at the bottom shows that task; "All in category" goes back.',
    'The burn-down widget can show one task: choose it when placing the widget (Android) or in the Chart widget\'s Task setting (iPad). Tapping it opens the task.',
  ]),
  Release('1.10.9', 'November 2026', [
    'The "Edit all" button above a task\'s checklist now shows as soon as the task has one step, not only from two steps up.',
  ]),
  Release('1.10.8', 'November 2026', [
    'Kanban board: moving a task no longer reshuffles the board. A task you move goes to the top of its new column and everything else stays where it was, so the card you just moved is easy to find.',
    'Kanban lanes: a task\'s row stays in the same place as you move it between stages, instead of jumping up or down the board.',
    'Prefer the old way? Settings, Kanban board, "Sort columns like the main list".',
  ]),
  Release('1.10.7', 'November 2026', [
    'iPad: email tasks from Gmail. Settings, Email tasks, connect Google as on the phone; the sign-in page opens inside the app and closes by itself.',
    'iPad: "Add a task in Task Blocks" to Siri asks what the task is, then opens the app with it ready to save. The same "Add to Task Blocks" action is in the Shortcuts app, so you can make a Share sheet shortcut (steps in the iPad guide).',
    'iPad: place reminders. Save places and give tasks "Remind me when I arrive" or "when I leave", as on the phone. The iPad needs location "Always" for this.',
  ]),
  Release('1.10.6', 'November 2026', [
    'iPad: new Calendar widget (Large and Extra large). This month on the left, with a dot on days that have tasks due; tap a day to open it. On the right, what is coming up: overdue tasks, the next two weeks and today\'s calendar events, with a circle to tick each off.',
    'iPad: Lock Screen widgets. "At a glance" shows how many tasks are open or overdue and what is due next; Quick add is a plus button that opens the app ready to type.',
    'iPad: Upcoming events and Photo of a list are now in the menu, as on Android. Upcoming events reads the iPad\'s calendars (Settings, Calendar events to choose which); Photo of a list reads the writing in a photo on the iPad itself.',
  ]),
  Release('1.10.5', 'November 2026', [
    'Matrix: moving a task into Decide no longer makes you pick a date. The date picker now has a "No date" button that puts the task in Decide without one. Pick a date as before if you want one.',
  ]),
  Release('1.10.4', 'November 2026', [
    'A task with no due date goes back to green when you tick "Worked on it today" (on an opened block, the task page\'s week of dots or the Worked today widget), then ages again from there at the usual colour speed. Unticking today puts the old colour back. Tasks with a due date are unchanged.',
  ]),
  Release('1.10.3', 'November 2026', [
    'Dragging a task into another category no longer switches the list to hand-made order: the task changes category and the list stays sorted (by due date, say), so it lands where the sort puts it. Undo puts the category back.',
    'Settings, List, "When you drag a task" lets you choose: keep the sort across categories (the new default), always switch to hand-made order (as before), or always keep the sort.',
  ]),
  Release('1.10.2', 'November 2026', [
    'Steps can come after other steps. Tap a step and choose "Comes after another step", or in Edit all steps tap the arrow beside it, or tick several and use "Chain in order". When a step moves later, the steps after it move later too, by just enough (not when Settings, Gantt chart says never). A step that starts too early is shown in red.',
    'On the Gantt chart, open out a task\'s steps to see arrows between them.',
    'Link a step to a task you already have: tap the step and choose "Link to an existing task", or use the link button in Edit all steps. Ticking that task off ticks the step. Unlink it from the same place.',
  ]),
  Release('1.10.1', 'November 2026', [
    'Gantt chart: the new Fit button (next to Day, Week, Month) zooms so everything shown fits on the screen. Pick a category from the list, or tap a category\'s heading, and it zooms to just those tasks.',
    'Zoom to one task: long-press its name on the chart (or tap the target button next to it when unfolded). Its steps open out and it fills the width.',
    'On a task\'s page, "Show on the Gantt chart" opens the chart zoomed in on that task.',
    'When nothing on the chart is near today, it now opens zoomed to fit everything instead of on an empty stretch.',
  ]),
  Release('1.10.0', 'November 2026', [
    'New Android widget: Calendar (4x3). This month on the left, with a dot on days that have tasks due; tap a day to open it. On the right, what is coming up: overdue tasks, the next two weeks and today\'s calendar events, with a box to tick each off.',
    'Every Android widget now shows a sample picture in the widget picker, so you can see what each one looks like before you place it.',
    'The Added vs done widget is now called "Stats chart: added vs done" in the picker: tasks added (blue) and done (green) each day for the last 4 weeks, with a line for how many are open.',
  ]),
  Release('1.9.9', 'November 2026', [
    'Task Blocks has its own icon: three task blocks going from green to amber to red, with the top one ticked. It is on Android (including round and themed icons), iPad, Mac, Windows and the web.',
    'Notifications use a small one-colour version of the new icon in the status bar.',
  ]),
  Release('1.9.8', 'November 2026', [
    'Edit all steps shows its timeline on the folded screen and on narrower unfolded screens too, under the steps (scroll down to it), with every step in it. It shows for Gantt tasks, or steps that have a start or days of work.',
    'Unfolded, drag the line between the list and the right-hand pane to make the pane wider or narrower. It stays that way on this device; double-tap the line to go back to the usual widths.',
    'Fixed: in a narrow task pane, "Checklist 0/3" was squeezed to one letter per line. Edit all and Templates are now icon buttons there.',
  ]),
  Release('1.9.7', 'November 2026', [
    'Edit all steps: tap "Edit all" above a task\'s checklist to see every step on one screen. Tap any start, days of work, due date, reminder, stage or progress to change that step, or tick several and change them all at once. "Move dates" shifts them a few days earlier or later.',
    '"Line up in order" gives the ticked steps dates one after another: after another step, today or a date you pick, with free days in between if you want, skipping weekends unless the task counts them. It shows where each one lands, and warns when any would end after the task is due. Undo takes back each change.',
    'Unfolded it is a table with a small Gantt chart preview under it (for Gantt tasks); folded it is a list of cards with the buttons along the bottom.',
  ]),
  Release('1.9.6', 'November 2026', [
    'iPad widgets get buttons: tick a task off (the circle before it) or snooze it until tomorrow on the Task list, Done on Focus, tick steps on Checklist and Now doing, the arrow or Next to move a board card or step on, and the circle on Worked today. The widget changes at once; the app catches up when you next open it.',
  ]),
  Release('1.9.5', 'November 2026', [
    'iPad home screen widgets: Task list, Summary, Focus, Checklist, Mini month, Kanban board, Matrix, Worked today, Chart and Quick add. Press and hold a widget, then Edit Widget, to pick what it shows (a category, a stage, a task, or one of its "Show" choices). Tapping a task opens it; tapping a title opens that page in the app.',
    'Ticking, snoozing and moving things on straight from an iPad widget come in the next version. The test widget from 1.9.4 is gone; remove it from your home screen.',
  ]),
  Release('1.9.4', 'November 2026', [
    'iPad: a first test home screen widget, "Task Blocks test". It shows how many tasks are open and the first few, to check that widgets can see your tasks when the app is installed with AltStore. The full set of iPad widgets comes next.',
  ]),
  Release('1.9.3', 'November 2026', [
    'Steps on the Gantt chart can now have their own start day, days of work and progress, shown as a thin bar under their task, filled as far as it has got (red past their due date when they will finish late). Their progress counts toward the task\'s. Tap a step row on the chart, or use "Start, days of work and progress" in the step\'s menu on the task page. A step with only a date still shows as a diamond. Split out keeps the start and days of work.',
  ]),
  Release('1.9.2', 'November 2026', [
    'Habit tracker. Turn on "Habit" on a task (or tap + on the new Habits page): it is never ticked off, you tick the days you do it. Every day, a number of times a week, or chosen days. A repeating task keeps its history when it becomes a habit.',
    'The Habits page shows each habit\'s week to tick, its streak and this month\'s score. Tap one for a month calendar (tap any day so far to change it), the last 12 months as a strip, the best streak, and Pause, which keeps the streak while you are away.',
    'Every-day habits forgive one missed day a week (switch it off per habit). An optional reminder comes only on days it isn\'t ticked yet.',
    'Habits stay out of the list apart from one "Habits today: 2 of 5" line, and off the board, matrix and Gantt chart. Achievements has a Habits section, and the Worked today widget can show your habits instead of a category.',
  ]),
  Release('1.9.1', 'November 2026', [
    'Tick the days you worked on a task without finishing it: "Worked on it today" on an opened block, or the week of dots on the task page (tap any day so far this week). Ticks show under the Gantt bar, and a board card says "3 days this week" once any are ticked. Ticking never moves a card.',
    'New Achievements page (⋮ menu, and a view in the right-hand panel): for a category and a period (last week, Monday to Sunday, unless you pick another), tasks done, steps ticked and days worked, each finished task\'s due date against when it was done, and what you worked on but didn\'t finish. Copy as text pastes it into a message.',
    'Burn-down at the foot of the Gantt chart: work left against the plan, and when it would finish at the pace of the last two weeks. It follows the chart\'s category and counts tasks and steps, or days of work.',
    'Three new 4×3 home screen widgets (Android), each for one category or all: Worked today (tap the circle to tick today, with the week as dots), Added vs done (the Statistics chart for the last 4 weeks) and Burn-down (tap to open the Gantt chart on that category).',
  ]),
  Release('1.9.0', 'November 2026', [
    'New Gantt chart. Switch "On the Gantt chart" on in a task (or type !gantt when adding it) and it shows as a bar from its start to its expected finish, grouped by category, with Day, Week and Month zoom.',
    'Tasks gain a start date and "Takes N days". Weekends are skipped unless you switch Count weekends on (the default is in Settings, Gantt chart). The expected finish is shown apart from the due date, and the bar turns red past the due flag when it will finish late. With no start, the bar counts back from the due date.',
    'A task can now come after several tasks, with a wait of some days. Arrows join them on the chart and go red when one starts too early. It stays locked until everything it waits for is ticked off.',
    'Hold a bar to drag it to new dates, or hold its right end to change how long it takes. When that makes later tasks clash, the app asks whether to move them later too (or always, or never, set in Settings). The first plan stays as a faint outline.',
    'Milestones (one-day diamonds), progress shading (from the steps ticked or set by hand), a Needs dates tray for chart tasks without dates, a Timeline view in the right-hand panel, a Gantt icon in the top bar, and the new fields in CSV export and import.',
    'Moving a card into In progress fills an empty start date (Settings, Gantt chart can switch this off).',
  ]),
  Release('1.8.6', 'November 2026', [
    'A task can now become a step of another task: ⋮ on the task page, "Make into a step of…". Nothing is lost. The step keeps the whole task (category, star, repeat, emails, place, board history, its own steps) and "Split out" brings it all back.',
    'If the task has steps of its own, you choose each time: keep them inside, add them to the new parent, or split them out as tasks of their own. Tasks that came after it now come after the parent. Undo puts everything back.',
    'Split out on an ordinary step now also keeps its calendar event link and, for a ticked step, the time it was really ticked. "Make into a linked task" now takes the step\'s date, reminder and note.',
    'New top bar: Search, Kanban, Matrix, Calendar. Kanban and Matrix show once a task is on them. The archive moved into the ⋮ menu (with its count) and Settings, Archive. Settings, Top bar icons switches any icon off on this device.',
  ]),
  Release('1.8.5', 'November 2026', [
    'Five new home screen widgets (Android). Board summary: how many tasks are in each Kanban stage, amber when over its limit; tap one to open the board there.',
    'Board stage list: the cards in one stage, switched with the arrows or the counts. The arrow on a card moves it to the next stage, saved in its board history as "Widget".',
    'Now doing: the task longest in In progress (or one you pick), with its steps to tick, Next stage and Done. Board steps: only the steps on the board, by stage, each moved on with its arrow.',
    'Matrix: the four boxes with the top tasks in each. Tap a task to open it, or a box to open the matrix there. The board and matrix widgets can show one category.',
    'Other Android apps such as Tasker can now add a task without opening Task Blocks (an "app.taskblocks.ADD_TASK" intent; the details are in docs/PUSH_TASKS.md with the code). It arrives the next time the app opens.',
    'Android: the app\'s inside names changed, so home screen widgets placed before this update stop working. Remove them and add them again once.',
  ]),
  Release('1.8.4', 'November 2026', [
    'Wide screens (the Fold unfolded, tablets, computers): the right-hand side now has a row of views instead of just the archive. Agenda (overdue, today and the next 7 days, dated steps included), Matrix, Board, Calendar, Events, Statistics and Archive.',
    'The matrix takes half the screen so its four boxes fit. The board view lists each stage with its count; tap to see its tasks, or + to put a task there.',
    'Opening a task and closing it comes back to the same view.',
    'Settings, Right-hand panel: which view it starts on (Agenda unless you change it), or reopen the last one; which views to offer; what the Statistics view shows; and what opens when you unfold the phone (the list and panel, the whole board or the whole matrix).',
  ]),
  Release('1.8.3', 'November 2026', [
    'Checklist steps can have their own date, reminder and note: tap a step. Dated steps show in the calendar with their task\'s name and get their own reminder.',
    '"Split out" turns a step into a task of its own. It takes the task\'s category, star, place, estimate, matrix box and board stage, and its date when the step has none. Undo puts it back.',
    'Upcoming events: add an event as a dated step of an existing task (the list icon), for example a fitting as a step of "Wedding".',
    'Email to tasks can also check while the app stays open (Settings, Google: every 30 minutes, hour or 2 hours). Off by default.',
    'CSV export keeps step dates.',
  ]),
  Release('1.8.2', 'November 2026', [
    'Uses less battery: reminders are only set again when a due date, name or reminder setting changes, and home screen widgets only redraw when what they show changes.',
    'Email to tasks no longer downloads the same emails again on every check.',
    'The list stops redrawing every minute while the app is in the background.',
    'Fixed a rare "could not save" error when a sync and an edit saved at the same moment.',
  ]),
  Release('1.8.1', 'November 2026', [
    'The settings kept on each device (places, list and board view choices, location recording, the Google client ID and secret) are now saved to Dropbox too, so a reinstall can get them back. Sign-ins are not copied.',
    'After a reinstall, connecting Dropbox offers "Restore" at the top of the list. Settings, Dropbox also has Restore settings from a device, to copy them from another device.',
  ]),
  Release('1.8.0', 'November 2026', [
    'Matrix (menu): put a task in Do, Decide, Delegate or Delete from its page, then drag tasks between the boxes. Only tasks you put there show. Category, date and search filters like the Kanban board.',
    'Decide asks when you\'ll do it, Delegate asks who it\'s waiting on, and Delete offers to tick it off. Rename the boxes in Settings, and turn on an "Urgent?" hint for tasks due soon.',
    'Quick-add words: !do, !decide, !delegate, !delete, !board and !star when typing a task. Settings has a new Quick-add words section listing everything the add box reads, where you can rename or switch them off.',
    'Search everything (menu): open tasks, steps, emails on tasks and the archive, grouped, with the matches highlighted and filters. Accents don\'t matter, and "quoted words" stay together.',
    'Categories can put new tasks on the Kanban board (Settings, Categories), for example Work, in the stage you pick.',
    'CSV export adds Matrix box and Waiting on columns.',
  ]),
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

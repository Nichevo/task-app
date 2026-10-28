# Improvement plan

Running list of changes from Jeff's feedback. Status: ☐ planned · ◐ in progress · ☑ done

## 1. Use the unfolded Samsung Fold screen sensibly ☑ (PR #1, merged 2026-10-28)

**Feedback:** On the Fold's inner screen the single full-width list wastes space.

**Approach (chosen by Jeff 2026-10-27; PR #1):** when the screen is wide (unfolded Fold, tablet, or a
wide Windows window) switch to two side-by-side panes:

- **Left:** the task list, exactly as now (colour blocks, drag to reorder, tick off).
- **Right:** the task you tapped, opened for editing in place (name, notes, created, due date),
  so there's no jumping to a separate page. With nothing selected, the right pane shows the archive.

Folded (cover screen) looks as it does today; "Edit / set due date" opens the task full screen,
and back/✕ returns to the list. Folding or unfolding keeps the open task. Two panes kick in at
600 dp wide, so the Fold's inner screen gets them in portrait and landscape.

![Unfolded layout](screenshots/fold.png)

Alternatives considered: a two-column grid of blocks (breaks the "blocks stretch across the
screen" design), or simply larger text/blocks (doesn't use the extra space for anything useful).

## 2. Updates install over the previous version ☑ (PR #1, merged 2026-10-28)

Every CI build used a throwaway debug key, so Android refused to update the installed app.
Release builds are now signed with one permanent key held in the repo's Actions secrets
(`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`), and each build gets a rising build
number. Without the secrets CI still builds, with a warning. A one-time uninstall is needed
when moving to the new key.

## 3. Safer Dropbox sync ☑ (PR #1, merged 2026-10-28)

Previously the newest whole file won, so edits made on two devices between syncs could be
lost. Now each task carries its own "last changed" time and the two copies are merged task
by task; deletions are remembered for 90 days so they don't come back; list order comes from
whichever device last reordered; settings from whichever last changed them.

## 4. Due date reminders ☑ (PR #1, merged 2026-10-28)

Android shows a notification when an open task reaches its due time (may be a few minutes
late, as Android batches alarms to save battery). Reminders are rebuilt after every change and
sync, so a due date set on the PC reminds you on the phone.

## 5. Swipe gestures ☑ (PR #1, merged 2026-10-28)

Swipe a block right to tick it off, left to delete it. Both show an Undo.

## 6. Colour by due date ☑ (PR #1, merged 2026-10-28)

Settings toggle (on by default): a task with a due date goes green → red between when it was
created and when it's due, instead of at the colour-speed setting.

## 7. Archive search and clean-up ☑ (PR #1, merged 2026-10-28)

Search box in the archive (matches name and notes). Settings → "Delete archived tasks after":
Never (default), 1, 3, 6 or 12 months.

---

# Round 2 ☑ (PR #2, merged 2026-10-28)

## 8. Categories ☑ (PR #2, merged 2026-10-28)

- Each task can be given a category (e.g. Home, Work, Shopping). Categories are created and renamed in Settings.
- **Grouped view** (turned on in Settings): a category heading, then that category's tasks, then the next heading,
  and so on. When it's off, the list looks as it does today.
- Tasks with no category sit in their own group at the top (or bottom).
- Headings are plain bold text (no per-category colours) and can be collapsed to hide their tasks.
- The CSV export gets a Category column.

## 9. Drag between categories ☑ (PR #2, merged 2026-10-28)

- In grouped view, dragging a task under a different heading moves it into that category as well as
  changing its order. Headings can also be dragged to reorder the categories.

## 10. Repeating tasks ☑ (PR #2, merged 2026-10-28)

- In the task, choose a repeat: daily, weekly (pick days), monthly, yearly, or every N days.
- *Proposed:* when a repeating task is ticked off, it goes to the archive as normal and a fresh copy appears
  with the next due date (and its colour starts green again).
- Both modes, chosen per task: **fixed schedule** (next due date counts from the previous due date) or
  **after completion** (counts from when it was ticked off, e.g. "water plants 7 days after last time").

## 11. Text details ☑ (PR #2, merged 2026-10-28)

- Keep the current Notes box. When a task has notes, the thin block shows a short one-line preview
  under the name (blocks without notes stay as thin as now).

## 12. Linked tasks (one after another) ☑ (PR #2, merged 2026-10-28)

- In a task, choose "Comes after…" another task. The later task stays hidden (or shown greyed with a 🔒)
  until the earlier one is ticked off, then appears and starts green.
- Shown greyed out with a 🔒 (so its details can still be edited); it becomes a normal task, starting
  green, when the earlier one is ticked off.

## 13. Focus filter on the main screen ☑ (PR #2, merged 2026-10-28)

- Settings option: show only tasks with no due date or due in the next 30 days (overdue always show);
  tasks due later are tucked away behind a "Later (n)" link.

## 14. Quick dates while typing ☑ (PR #2, merged 2026-10-28)

Typing "Call bank tomorrow 5pm", "Fri", "next week" or "25 Dec" in the add box sets the due date and
strips the words from the name (shown as a hint before you press +).

## 15. Earlier reminders ☑ (PR #2, merged 2026-10-28)

Per task (with a default in Settings): remind at the due time and optionally 1 hour / 1 day / 1 week before.

## 16. Priority star ☑ (PR #2, merged 2026-10-28)

Star a task to keep it at the top of its category/list regardless of colour.

## 17. Snooze ☑ (PR #2, merged 2026-10-28)

Hide a task until a chosen date ("Snooze until…"); it reappears then. Snoozed tasks are listed behind a
"Snoozed (n)" link.

## 18. Home screen widget (Android) ☑ (PR #2, merged 2026-10-28)

The app offers several widgets in Android's widget picker; add any of them, as many times as you like:

- **Task list:** scrolling coloured blocks in list order, with tick boxes (archive without opening the app)
  and a + button that opens straight to typing.
- **Compact:** count of open / overdue tasks and the next 3 due.
- **Quick add:** a single + icon.

When placing a list or compact widget you choose what it shows (all tasks, due soon, or one category),
so e.g. a "Work" widget and a "Home" widget can sit side by side.

## 19. CSV import ☑ (PR #2, merged 2026-10-28)

Import tasks from a CSV in the same format as the export (adds them; doesn't replace the list).

---

# Round 3 (collecting ideas, not started)

Jeff wants the full list agreed before any building starts.

## 20. Statistics page ☐

A **Statistics** page (from the ⋮ menu) to see how things are going:

- **Done per week**: a bar chart of tasks ticked off over the last 12 weeks, with this week highlighted.
- **On time**: the share of tasks with a due date that were ticked off before it.
- **Typical time to finish**: the median time from adding a task to ticking it off.
- **Open now**: open and overdue counts, and how the open count has moved over the last 30 days.
- **By category**: done and open per category.
- **Streak**: days in a row with at least one task ticked off.
- A period picker: last 7 days, 30 days, 12 months, all time.

Archive clean-up deletes old tasks, so the app keeps a small daily tally (done, on time, by category) that
survives clean-up and syncs through Dropbox. Stats count from when tasks were first archived, so history from
before this update comes from the archive as it is now.

## 21. Tasks from calendar events ☐

Look at upcoming calendar events and offer to make tasks from them:

- An **Upcoming events** page (next 14 days) lists events from the calendars you pick; each has **+ Task**,
  which creates a task named after the event, due at its start time (or a set time before, e.g. a day before
  for "prepare for…"). Events already turned into tasks show a tick.
- Nothing pops up unless you choose to. Settings → **Event suggestions**: Off (only when you open the page,
  the default), Once a day, or Once a week. When on, a single dismissible "3 events coming up" line shows at
  the top of the list; events you dismiss or turn into tasks aren't suggested again.
- **Phone only** (agreed 2026-10-28): reads the phone's calendars (Google, Samsung, Outlook accounts added to
  the phone) with permission; nothing leaves the phone. Tasks made from events sync to Windows through Dropbox.

## 22. Calendar view of tasks ☐

A month grid (switch from the list with a calendar icon):

- Each day shows coloured dots for tasks due that day (same green→red colours), overdue days marked.
- Tap a day to see its tasks below the grid; tap one to open it. Drag a task onto another day to move its due date.
- Repeating tasks show their future dates faded.
- Undated tasks aren't shown (they stay in the list).
- On the unfolded Fold: month on the left, the chosen day's tasks on the right. A week view as a second option.

## 23. Reusable subtasks (checklists) ☐

- Any task can have a **checklist** of steps. Thin blocks show progress like "2/5".
- Tick steps in the expanded block or the task page; reorder by dragging.
- **Reusable**: save a checklist as a **template** (e.g. "Packing for a trip", "Monthly bills") and add it to
  any task in one tap. Templates are managed in Settings.
- Repeating tasks start each repeat with the steps unticked.
- Ticking the last step offers to tick off the whole task.
- Steps have no dates (agreed 2026-10-28). When a step needs one, **Make into task** turns it into a full task
  (which can then have a due date, notes, category and so on). The step stays in the checklist with a link icon,
  opens that task when tapped, and ticks itself when that task is ticked off.
- CSV export lists steps in a column.

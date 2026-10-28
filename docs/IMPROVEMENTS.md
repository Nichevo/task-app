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

# Round 2 (collecting ideas, not started)

Jeff wants the full list agreed before any building starts.

## 8. Categories ☐

- Each task can be given a category (e.g. Home, Work, Shopping). Categories are created and renamed in Settings.
- **Grouped view** (turned on in Settings): a category heading, then that category's tasks, then the next heading,
  and so on. When it's off, the list looks as it does today.
- Tasks with no category sit in their own group at the top (or bottom).
- Headings are plain bold text (no per-category colours) and can be collapsed to hide their tasks.
- The CSV export gets a Category column.

## 9. Drag between categories ☐

- In grouped view, dragging a task under a different heading moves it into that category as well as
  changing its order. Headings can also be dragged to reorder the categories.

## 10. Repeating tasks ☐

- In the task, choose a repeat: daily, weekly (pick days), monthly, yearly, or every N days.
- *Proposed:* when a repeating task is ticked off, it goes to the archive as normal and a fresh copy appears
  with the next due date (and its colour starts green again).
- Both modes, chosen per task: **fixed schedule** (next due date counts from the previous due date) or
  **after completion** (counts from when it was ticked off, e.g. "water plants 7 days after last time").

## 11. Text details ☐

- Keep the current Notes box. When a task has notes, the thin block shows a short one-line preview
  under the name (blocks without notes stay as thin as now).

## 12. Linked tasks (one after another) ☐

- In a task, choose "Comes after…" another task. The later task stays hidden (or shown greyed with a 🔒)
  until the earlier one is ticked off, then appears and starts green.
- *Open question:* hidden until ready, or visible but greyed out?

## 13. Focus filter on the main screen ☐

- A setting / toggle to show only tasks that have no due date or are due soon; tasks due later are tucked
  away (still visible via a "Later (n)" link and in search).
- *Open question:* "this calendar month" or "the next 30 days"? Overdue tasks always show.

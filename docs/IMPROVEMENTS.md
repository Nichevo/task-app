# Improvement plan

Running list of changes from Jeff's feedback. Status: ☐ planned · ◐ in progress · ☑ done

## 1. Use the unfolded Samsung Fold screen sensibly ◐ (PR #1)

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

## 2. Updates install over the previous version ◐ (PR #1)

Every CI build used a throwaway debug key, so Android refused to update the installed app.
Release builds are now signed with one permanent key held in the repo's Actions secrets
(`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`), and each build gets a rising build
number. Without the secrets CI still builds, with a warning. A one-time uninstall is needed
when moving to the new key.

## 3. Safer Dropbox sync ◐ (PR #1)

Previously the newest whole file won, so edits made on two devices between syncs could be
lost. Now each task carries its own "last changed" time and the two copies are merged task
by task; deletions are remembered for 90 days so they don't come back; list order comes from
whichever device last reordered; settings from whichever last changed them.

## 4. Due date reminders ◐ (PR #1)

Android shows a notification when an open task reaches its due time (may be a few minutes
late, as Android batches alarms to save battery). Reminders are rebuilt after every change and
sync, so a due date set on the PC reminds you on the phone.

## 5. Swipe gestures ◐ (PR #1)

Swipe a block right to tick it off, left to delete it. Both show an Undo.

## 6. Colour by due date ◐ (PR #1)

Settings toggle (on by default): a task with a due date goes green → red between when it was
created and when it's due, instead of at the colour-speed setting.

## 7. Archive search and clean-up ◐ (PR #1)

Search box in the archive (matches name and notes). Settings → "Delete archived tasks after":
Never (default), 1, 3, 6 or 12 months.

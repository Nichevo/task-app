# Task Blocks

A very simple personal task list for Android and Windows (one Flutter codebase).

<p>
  <img src="docs/screenshots/list.png" width="240" alt="Task list with blocks fading from green to red">
  <img src="docs/screenshots/expanded.png" width="240" alt="A block tapped open showing created and due dates">
  <img src="docs/screenshots/task.png" width="240" alt="Editing a task and its due date">
</p>
<p>
  <img src="docs/screenshots/archive.png" width="240" alt="Archive showing when each task was closed">
  <img src="docs/screenshots/settings.png" width="240" alt="Settings: colour speed and Dropbox">
</p>

On an unfolded Fold, a tablet or a wide window, the open task sits beside the list:

<img src="docs/screenshots/fold.png" width="480" alt="Two-pane layout on an unfolded Fold">

On a wide screen such as Windows, the blocks stretch across the whole window:

<img src="docs/screenshots/windows.png" width="740" alt="Wide window layout">

- Type a task at the bottom and press Enter or **+**.
- Each task is a full-width block that starts green and turns red as it ages. Set how fast in **⋮ → Settings → Colour speed**.
- Thin blocks show the name and the time added. Tap a block to expand it and see the created date, due date and notes.
- **Edit / set due date** opens the task to rename it, add notes or set a due date.
- Drag the ≡ handle (or long-press a block) to move it up or down.
- Swipe a block right to tick it off, or left to delete it (both can be undone).
- Tick the box to move a task to the **Archive** (box icon, top right), which shows when it was closed and can be searched. The ↶ button puts it back.
- Tasks with a due date turn red as the due date approaches, and the phone shows a reminder when it's due.
- On an unfolded Fold, tablet or wide window, the open task (or the archive) shows beside the list.
- **⋮ → Export to CSV** saves every task (open and archived) with all details. **⋮ → Import from CSV** brings tasks back in (only a Task column is needed, so a spreadsheet works too).
- Type dates as you add a task, such as "Call mum tomorrow 5pm", "Bins friday" or "Report 25 Dec". The date shows as a chip you can tap ✕ on to ignore.
- Give tasks a **category**. Turn on **Settings → Group by category** to see bold, collapsible headings; drag a task under another heading to move it there.
- **Repeat** a task on a fixed schedule (every Monday, the 1st of each month) or a set time after you tick it off.
- Thin blocks show the first line of the notes, if there are any.
- **Comes after** links a task to an earlier one. It stays greyed out with a lock until the earlier task is ticked off, and you can still edit it.
- **Settings → Next 30 days only** hides tasks due later than that behind a "Due later" link. Overdue and undated tasks always show.
- **Star** a task to keep it at the top. **Snooze** hides it until a date you pick.
- Reminders can come early (15 minutes, an hour, a day or a week before), per task or as a default in Settings.
- **Checklists**: add steps inside any task; thin blocks show "2/5". Save a checklist as a **template** (Settings) and add it to other tasks in one tap. Any step can be made into a linked task of its own.
- **Statistics** (menu): done per week, on-time share, typical time to finish, open tasks over time, totals per category and your streak.
- **Calendar** (icon, top right): a month or week view with a coloured dot per task due. Tap a day to see its tasks; long-press and drop a task on another day to move it.
- **Automatic categories**: a new task gets a category from a #tag, from keywords you give each category, or by learning from tasks you've already filed. It shows as a chip you can change or drop. Settings → Auto category: Off, Suggest or Apply.
- **More ways to add tasks**: share text from any app to Task Blocks; paste a list (one task per line); "OK Google, note to self…"; take a **photo of a written list** (read on the phone); or write lines to `inbox.txt` in the app's Dropbox folder.
- **Upcoming events** (Android): make tasks from your phone's calendar events, due at the start or a day or week before. Optionally a once-a-day or once-a-week prompt.
- **Overdue reminders**: a daily summary at a set time, or nudges every 1, 3 or 6 hours with quiet hours. Every reminder has Done and Snooze buttons.
- Android home screen widgets: **Task list** (tick, snooze, +), **Summary**, **Today** (overdue, due today and today's events), **Focus** (your top task), **Checklist** (steps of one task), **Stats**, **Mini month** and **Quick add** (tap or speak, optionally straight into a category). List and summary widgets can show all tasks, due soon, starred, overdue or a category, with a light, dark or see-through background and normal or compact rows.

## Getting the app

Every push to `main` builds both apps on GitHub Actions. Open the **Actions** tab, pick the latest
"Build apps" run and download:

- **TaskBlocks-android**: unzip and open `app-release.apk` on the phone (allow "install unknown apps").
- **TaskBlocks-windows**: unzip anywhere and run `task_blocks.exe`. Keep the files in that folder together.

## Signing key (one-time)

Android only installs an update if it's signed with the same key as the installed app. The key
lives in the repo's **Settings → Secrets and variables → Actions** as `ANDROID_KEYSTORE_BASE64`
(the keystore file, base64) and `ANDROID_KEYSTORE_PASSWORD`. Keep a backup of the keystore:
if it's lost, the app has to be uninstalled and reinstalled to update.

## Dropbox sync

1. Go to https://www.dropbox.com/developers/apps and **Create app**: *Scoped access*, *App folder*, any name.
2. On the app's **Permissions** tab tick `files.content.read` and `files.content.write`, then **Submit**.
3. Copy the **App key** from the Settings tab.
4. In Task Blocks open **⋮ → Settings**, paste the key, tap **Connect Dropbox**, approve in the browser and paste the code back.
5. Do the same on the other device with the same key.

The list is stored in `Dropbox/Apps/<app name>/tasks.json`. Each change uploads after 2 seconds; the app downloads
on start and whenever it comes back to the foreground. Changes made on both devices are merged task by task; if the
same task was edited on both, the most recent edit wins.

## Building locally

```
flutter test
flutter build apk --release     # Android
flutter build windows --release # Windows (on a Windows PC)
```

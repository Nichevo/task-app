# Task Blocks on iPad

## What is set up

- An iOS target (`ios/`, bundle id `app.taskblocks`, name "Task Blocks") that runs on iPad and iPhone,
  iOS 15 or later.
- iPad uses the same two-pane layout as the unfolded Fold: the list on the left and the open task (or the
  archive) on the right, in portrait and landscape, and in Split View / Stage Manager. Below 600 points wide
  (narrow Split View, iPhone) it falls back to one pane.
- A CI job (`ios` in `.github/workflows/build.yml`) builds the app on every push and PR and attaches
  **TaskBlocks-ios** (`TaskBlocks-ios-unsigned.ipa`) to the run, next to the Android, Windows and Mac builds.

## What works on iPad

Everything the Mac and Windows apps have (list, colours, categories, repeats, checklists, statistics,
calendar view, CSV, Dropbox sync, pasted lists), plus:

- **Reminders**: due-time, earlier and overdue notifications, with Done / 1 hour / This evening / Tomorrow
  buttons (press and hold the notification).
- **Location**: the "Record where tasks are added and done" switch in Settings.

Android-only for now (they are written in Kotlin): calendar event suggestions, photo of a list, Share to
Task Blocks and voice add. Each could be added for iPad later (a share extension, EventKit for the calendar).

## Home screen widgets (item 79)

From version 1.9.5 the iPad has ten home screen widgets. Press and hold the home screen, tap **Edit** →
**Add Widget**, search for Task Blocks, and pick one. Open Task Blocks once first so it shares your tasks.

| Widget | Shows | Sizes |
| --- | --- | --- |
| Task list | Coloured tasks: all, due soon, starred, overdue or today, for one category or all | Medium, Large, Extra large |
| Summary | Open and overdue counts with the next 3 due, or done this week and your streak | Small, Medium |
| Focus | Your top task as one big block, or the board task you're doing now with its steps | Small, Medium, Large |
| Checklist | The steps of one task, or the steps on the board by stage | Medium, Large |
| Mini month | This month with dots on days with tasks due | Small, Medium, Large |
| Kanban board | How many tasks in each stage, or the cards in one stage | Small, Medium, Large |
| Matrix | The four boxes and the top tasks in each | Medium, Large, Extra large |
| Worked today | A category's tasks, or your habits, with this week's worked days | Medium, Large |
| Chart | Added vs done for 4 weeks, or the Gantt burn-down | Medium, Large |
| Quick add | Opens the app ready to type a task | Small |

Press and hold a widget, then **Edit Widget**, to choose its category, stage, task or "Show" option.
Tapping a task opens it in the app; tapping a widget's title opens that page. Ticking things off on
the widget itself comes in the next version.

The widgets redraw when you change something in the app, and every hour by themselves (iPadOS limits
how often). A change synced from another device shows after you next open the app on the iPad.

With a free Apple ID the widgets need the app group that AltStore sets up when it installs the app; it
renames it to `group.app.taskblocks.<your team id>` and the app finds the new name by itself.

## What needs the owner's Apple account

The CI build is **not signed**, because signing needs an Apple account. iPads only run signed apps. Pick one:

1. **Free Apple ID, no Mac needed: Sideloadly (Windows or Mac).** Download the `.ipa` from the CI run,
   open it in Sideloadly with the iPad plugged in, sign in with your Apple ID. On the iPad: Settings →
   General → VPN & Device Management → trust your Apple ID, and turn on Settings → Privacy & Security →
   Developer Mode. The app stops opening after **7 days** and has to be re-sent (AltStore can refresh it
   automatically over Wi-Fi).
2. **Free Apple ID with Xcode on the Mac.** Open `ios/Runner.xcworkspace` in Xcode, Runner target →
   Signing & Capabilities → Team: your Apple ID, plug in the iPad and press Run. Same 7-day limit.
3. **Apple Developer Program (US$99 a year).** Signed builds last a year and can go through TestFlight
   (install from the TestFlight app, updates arrive by themselves). Once you have the account I can make CI
   sign and upload automatically; you would add these GitHub Actions secrets (I can't set secrets):
   - `IOS_CERTIFICATE_P12_BASE64` and `IOS_CERTIFICATE_PASSWORD` (an Apple Distribution certificate),
   - `APPSTORE_API_KEY_ID`, `APPSTORE_API_ISSUER_ID`, `APPSTORE_API_KEY_P8_BASE64` (an App Store Connect API
     key with App Manager access), and the app record `app.taskblocks` created in App Store Connect.

Your data moves across through Dropbox as on the other devices: Settings → Dropbox sync, same app key.

**Changed in 1.6.2:** the bundle id (iPad and Mac) became `app.taskblocks`. The iPad and Mac see it as a new app,
so install it once alongside the old one, connect Dropbox again (same app key) and let it sync, then delete the old
copy. Later versions update in place again.

## Not tested yet

The container that writes this code can't run iOS builds; the CI job is the first real build. The first
time you install it, check: reminders arrive and their buttons work, Dropbox connect, and the two panes in
both orientations.

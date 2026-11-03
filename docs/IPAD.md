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

Android-only for now (they are written in Kotlin): home screen widgets, calendar event suggestions, photo of
a list, Share to Task Blocks and voice add. Each could be added for iPad later (WidgetKit widgets, a share
extension, EventKit for the calendar); widgets and share need a paid Apple developer account (app groups).

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

# Letting other tools push tasks into Task Blocks

Status: design only (2026-11-01). Nothing here is built yet except what is marked **exists**.

## Goal

Other tools (Zapier, IFTTT, Tasker, iOS Shortcuts, a script, an email rule, another app of the owner's) should be
able to add tasks to Task Blocks without anyone typing them, and each task should say where it came from.

## What is already in place

- **Task source (exists, PR for item 47).** Every task has a `source` string: `typed`, `widget`, `voice`,
  `share`, `paste`, `photo`, `inbox`, `calendar`, `csv`, `repeat`, `step`. It is a free string on purpose: a
  pushed task can carry any name (`zapier`, `email`, `work-tracker`) and older copies of the app keep it
  and show it with a capital letter. Statistics can group by it (item 30).
- **Dropbox inbox (exists, item 26).** Any line in `Apps/<app>/inbox.txt` becomes a task on the next sync
  (dates and `#category` in the line are read). Source `inbox`.
- **Deep link (exists, Android).** `taskblocks://add?text=...&cat=...&src=...` opens the app with the add box
  filled in. Used by the quick-add widget; Tasker can call it too, but the user still has to press Add.

## Options

| | How a tool sends a task | Works with | Effort | Notes |
|---|---|---|---|---|
| A. Dropbox inbox folder (JSON) | Writes a small `.json` file into `Apps/<app>/inbox/` | Zapier, IFTTT, Make, scripts, anything with Dropbox | Small | No server. Picked up on next sync (app open or resume). |
| B. Android "add task" intent | Sends an intent / opens a link with `silent=1` | Tasker, Automate, MacroDroid, other Android apps | Small | Instant, phone only, no network needed. |
| C. iOS Shortcuts action | URL scheme now; App Intent later | iOS Shortcuts, Siri | Small / medium | URL scheme opens the app; an App Intent can add without opening. |
| D. Small web endpoint | HTTPS POST with a secret token | Any webhook (GitHub, forms, Home Assistant, email services) | Medium | A Cloudflare Worker that just writes option A's file into Dropbox. Needs a Dropbox token stored in the worker. |
| E. Email | Label an email in Gmail | Gmail | Medium | Already planned as item 34; it is one more source (`email`). |

## Recommendation

1. **Build A first.** It reuses Dropbox sync, needs no server, and covers Zapier/IFTTT/Make, which between
   them reach almost every other service. A folder of one-file-per-task fixes a race the current
   `inbox.txt` has (a line appended between the app reading the file and clearing it is lost): the app only
   deletes the files it has read.
2. **Add B** for instant phone automations (Tasker etc.), with the same fields as A.
3. **Add D only if** a tool can't write to Dropbox but can call a webhook. It is a thin wrapper around A,
   so the app side doesn't change.

## Task file format (options A, B, D)

One task per file, UTF-8 JSON, any file name ending in `.json` (tools should use something unique, such as a
timestamp plus a random number). Only `title` is required.

```json
{
  "title": "Renew car insurance",
  "notes": "Quote from the broker email",
  "due": "2026-11-20T09:00:00Z",
  "category": "Admin",
  "starred": false,
  "steps": ["Get quotes", "Pay"],
  "source": "zapier",
  "ref": "zap-7731-msg-1842",
  "url": "https://mail.google.com/..."
}
```

- `due`: ISO 8601 date or date-time. A plain date means 9am that day. If missing, the title is read for
  dates like typed tasks are ("tomorrow 5pm").
- `category`: matched by name; created if missing (same as CSV import). If missing, auto-category applies.
- `source`: short lower-case name of the tool. Defaults to `inbox`.
- `ref`: the tool's own id for the item. The app keeps it on the task (`sourceRef`) and ignores a second
  file with the same `source` + `ref`, so a tool that retries doesn't make duplicates.
- `url`: added to the notes as a tappable link.
- Unknown fields are ignored, so the format can grow.

A file can also hold a list (`[ {...}, {...} ]`) for tools that batch.

### Later: updating and completing

Files could carry `"op": "complete"` or `"op": "update"` with `source` + `ref` to tick off or change a task
that came from the same tool (for example, close a task when a support ticket is closed). Not needed for
the first version.

## App changes needed for A

- `Task.sourceRef` (string, optional), saved and synced like `source`.
- In `AppStore.sync`, after the merge: list `inbox/` in Dropbox, download each `.json`, add the tasks
  (skipping known `source` + `ref`), then delete just those files. Bad files are moved to `inbox/failed/`
  with a note rather than retried forever.
- Settings → Dropbox shows the folder path and a copyable example file.
- Keep `inbox.txt` working as it is.

## Security

- Dropbox "App folder" access means tools can only write inside the app's own folder.
- Each tool connects its own Dropbox login (Zapier/IFTTT do this themselves); no token is shared with the app.
- For option D the worker holds one Dropbox token and checks a long random secret in the request header;
  rotating the secret only needs a change in the worker and in the tools that call it.
- Pushed text is only ever shown as text (never run), and links in notes open in the browser.

## Open questions for the owner

1. Which tools do you want to push from first? (That decides whether A alone is enough.)
2. Should pushed tasks be added straight away, or wait in a "Suggestions" list like calendar events?
3. Do you want "complete" / "update" from outside tools, or only "add"?

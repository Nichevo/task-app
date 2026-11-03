# Google sign-in (items 53 and 55)

Task Blocks reads your Gmail straight from the app. There is no server in between, and nothing leaves your
devices except what already syncs through Dropbox (a task's emails: subject, sender, date, a short snippet and
the Gmail id). Sign-in works on the phone, Windows and Mac. The iPad comes later.

The permission asked for is `gmail.modify`. The app uses it only to read emails and change their labels and stars.
Google describes this permission as "Read, compose, and send emails", because `gmail.modify` covers sending too,
but Task Blocks never sends or deletes mail. There is no narrower Gmail permission that allows changing labels and
stars.

## One-time setup (about 10 minutes)

Google needs an "OAuth client" that belongs to you. You make it once and type its ID and secret into each
device.

1. Go to <https://console.cloud.google.com/>, sign in with the Gmail account you want to use, and create a new
   project (for example "Task Blocks").
2. **APIs & Services → Library**: search for **Gmail API** and press **Enable**.
3. **APIs & Services → OAuth consent screen** (in newer consoles: **Google Auth Platform → Branding /
   Audience**):
   - User type **External**, app name "Task Blocks", your address as the support and developer contact.
   - **Branding**: Google won't let you publish without these. They come from the repo's own GitHub Pages site
     (see "Home page and privacy policy" below):
     - Application home page: `https://nichevo.github.io/task-app/`
     - Application privacy policy link: `https://nichevo.github.io/task-app/privacy.html`
     - Terms of service: leave empty.
     - Authorized domains: `nichevo.github.io`
   - **Data access / Scopes**: add `https://www.googleapis.com/auth/gmail.modify`.
   - **Audience / Test users**: add your own Gmail address.
   - **Publish the app** (Publishing status → **In production**). See "Staying signed in" below for why.
     You don't need Google's verification, because only you use it.
4. **APIs & Services → Credentials → Create credentials → OAuth client ID**: application type **Desktop app**,
   name "Task Blocks". Copy the **Client ID** and **Client secret**.
5. In Task Blocks: **Settings → Google**, paste the client ID and secret, then press **Sign in with Google**.
   The browser opens Google's page. Because the app is your own and unverified, Google shows "Google hasn't
   verified this app". Press **Advanced → Go to Task Blocks (unsafe)**, then allow access. The page then says
   "Signed in" and you can go back to the app.

Do the last step on each device. The client ID and secret aren't synced with your tasks, but they are saved in
Dropbox's devices folder, so another device or a reinstall can take them with Settings → Dropbox → **Restore
settings from a device**. You still sign in on each device.

## Staying signed in

While the consent screen is left in **Testing**, Google ends the sign-in after 7 days, and the app asks you to
sign in again. Publishing it (**In production**) avoids that. An unverified app that is in production still
works for up to 100 users and shows the "hasn't verified" screen once at sign-in. If Google changes these rules,
Task Blocks shows "Google signed this device out" and Settings offers Sign in again. Nothing is lost.

## Home page and privacy policy

The two pages Google asks for live in this repo as `docs/index.html` and `docs/privacy.html`. To put them online
(once): on GitHub open the repo's **Settings → Pages**, set **Source** to "Deploy from a branch", branch **main**,
folder **/docs**, and press **Save**. After a minute or two they are at the addresses above. If you change what the
app does with Gmail, update `docs/privacy.html` to match.

## How sign-in works

The installed-app flow with PKCE: the app starts a tiny web page on this device only (127.0.0.1, on a random
port), opens Google in the browser, and Google sends the browser back to that page with a one-time code. The app
swaps the code for a refresh token, which stays on the device (device_settings.json, like the Dropbox sign-in).
Sign out in Settings removes it here and revokes it at Google.

## Email to tasks (item 54)

Settings → Google → **Email to tasks** (off until you turn it on), then **Allowed senders**: one address per line,
for example your work and personal addresses. `@example.com` allows a whole domain, only if you write it that way.

An email becomes a task only when all of these are true:

- it is from an allowed address,
- Gmail's own sender check passed for that address's domain (SPF or DKIM in the Authentication-Results header),
  because the From line of an email can be faked. Emails you sent from the signed-in account itself count as
  checked,
- its subject starts with the word **Task** ("Task: Pay council tax friday #Home", "task - ring the vet"), or it
  has the Gmail label **Task**.

Anything else you email yourself stays an ordinary email. The word Task comes off the title, and dates and
`#category` are read as when typing. The task's source is "Email" and the email is kept in its Emails section.
Gmail then labels the email **Tasked** (and takes the Task label off), so it isn't picked up again; the Gmail id
is also kept on the task, so two devices never both add it.

The app checks emails from the last 14 days when it opens, when it comes back to the front, and on each Dropbox
sync. **Also check while the app is open** (off by default) adds a check every 30 minutes, hour or 2 hours while
it stays on screen, for a computer left open all day. Settings shows "N ignored this week" with each email and why (not on the list, or failed the sender
check), plus **Allow this sender**.

## Starred emails page

Menu → **Starred emails** lists your starred emails, newest first, going back as far as Settings → Google →
**Starred emails: look back** says (1 week, 1 month, 3 months or all). Each email has:

- **Make task**: the add box filled in from the subject. Dates and `#category` in it are read, as when typing
  a task. The email is kept on the task, and the task's source is "Starred email".
- **Attach to task**: pick an open task (with search). The email goes into that task's **Emails** section,
  with an Open in Gmail button. The main list shows a small envelope on tasks with emails.
- **Hide**: it stops showing (the ⋮ menu has "Show hidden emails").

Settings → Google → **After using a starred email** sets what happens to the star: keep it (the default),
remove it, or remove it and add the label "Tasked". **Line at the top of the list** (off by default) shows
"N starred emails not yet tasks" when the app opens.

Export to CSV writes the emails kept on tasks to a third file, `task_emails_<date>.csv`. Importing that file
puts them back on their tasks, matched by task name and created time.

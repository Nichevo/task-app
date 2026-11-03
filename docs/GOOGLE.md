# Google sign-in (items 53 and 55)

Task Blocks reads your Gmail straight from the app. There is no server in between, and nothing leaves your
devices except what already syncs through Dropbox (a task's emails: subject, sender, date, a short snippet and
the Gmail id). Sign-in works on the phone, Windows and Mac. The iPad comes later.

The permission asked for is `gmail.modify`. That lets the app read emails and change their labels and stars.
It can't send or delete mail.

## One-time setup (about 10 minutes)

Google needs an "OAuth client" that belongs to you. You make it once and type its ID and secret into each
device.

1. Go to <https://console.cloud.google.com/>, sign in with the Gmail account you want to use, and create a new
   project (for example "Task Blocks").
2. **APIs & Services → Library**: search for **Gmail API** and press **Enable**.
3. **APIs & Services → OAuth consent screen** (in newer consoles: **Google Auth Platform → Branding /
   Audience**):
   - User type **External**, app name "Task Blocks", your address as the support and developer contact.
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

Do the last step on each device. The client ID and secret stay on that device and are never synced.

## Staying signed in

While the consent screen is left in **Testing**, Google ends the sign-in after 7 days, and the app asks you to
sign in again. Publishing it (**In production**) avoids that. An unverified app that is in production still
works for up to 100 users and shows the "hasn't verified" screen once at sign-in. If Google changes these rules,
Task Blocks shows "Google signed this device out" and Settings offers Sign in again. Nothing is lost.

## How sign-in works

The installed-app flow with PKCE: the app starts a tiny web page on this device only (127.0.0.1, on a random
port), opens Google in the browser, and Google sends the browser back to that page with a one-time code. The app
swaps the code for a refresh token, which stays on the device (device_settings.json, like the Dropbox sign-in).
Sign out in Settings removes it here and revokes it at Google.

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

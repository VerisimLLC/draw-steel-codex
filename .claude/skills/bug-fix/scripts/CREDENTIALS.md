# bug-fix credentials

**There is no Firebase key here, and there should never be one.** The bug system is
reached through `/api/bugs/*` on the internal-dashboards Worker, which holds the Firebase
service account as a Worker secret and exposes only the bug system. This machine needs
the shared team password and nothing else.

Check what is configured at any time:

```bash
python .claude/skills/bug-fix/scripts/check-credentials.py
```

It prints one line per credential -- resolved or missing, and where from -- and never
prints a secret value.

## What the Worker will and will not do

`/api/bugs/*` (see `internal-dashboards/worker/bugs.js`) can touch exactly six paths, all
keyed by a report id the caller names:

| | Path | |
|---|---|---|
| read | `/BugReports/{reportId}` | a novel report |
| read | `/BugReportsArchive/{reportId}` | a processed report |
| read | `/BugReportTriage/issues/{threadId}` | its Discord-thread issue node |
| read | `/Tickets/{uid}/{reportId}/reportId` | does this report have a ticket |
| read | `/games/{gameid}/storage` | which backend the reporter's game is on |
| write | `/GameDetails/{gameid}/chat/{guid}` | one "Codex Team" chat line |

It cannot be pointed at an arbitrary path, it does not enumerate the database, and the
single write appends one record at a fresh guid, so it cannot overwrite anything. The
`allowGameEntry` consent gate is checked **in the Worker**, which means it is no longer
something a caller on this side can skip.

## The credentials

### 1. Dashboard team password -- REQUIRED

**Env:** `$BUG_TICKETS_PASSWORD`, or config `ticketsPassword`.

Usually needs **no setup at all**: the scripts read `TICKETS_PASSWORD` out of
`internal-dashboards/wrangler.jsonc` in the dmhub repo, searching
`$INTERNAL_DASHBOARDS_WRANGLER`, then config `dmhubRepo`, then every ancestor of the
working directory. Running from inside the dmhub checkout finds it by itself. Set config
`dmhubRepo` to that checkout's path when running from somewhere else.

The same password gates `/api/tickets/*`, so one login covers reading a report, posting a
ticket message, and closing a ticket.

Without it: nothing works.

### 2. Discord webhook(s) -- needed to close a bug out

**Config keys:** `discordWebhook` (default channel, `#user-feedback`) and
`channels.bug.webhook` (`#bugs`).

A webhook is bound to one channel, so routing bug threads to `#bugs` and everything else
to `#user-feedback` takes one webhook each. Create them in Discord: *channel > Edit
Channel > Integrations > Webhooks > New Webhook > Copy Webhook URL*.

Without them: `bug-close-out.py` cannot post the "Fixed and Closed" reply. The ticket half
still runs.

### 3. Discord bot token -- optional, closeout thread archiving only

**Env:** `$DISCORD_BOT_TOKEN`, or config `discordBotToken`.

Webhook tokens cannot touch `/channels`, so archiving a thread needs a real bot in the
guild with **Manage Threads** on both forum channels. Create it at the
[Discord developer portal](https://discord.com/developers/applications) > *Bot > Reset
Token*, then invite it with that permission.

Without it: closeout still posts the reply, then reports that the archive step was
skipped. That is a note, not a failure.

### 4. Worker ADMIN_SECRET -- optional, only for a DurableObjects game

**Env:** `$DMHUB_ADMIN_SECRET` (release) / `$DMHUB_ADMIN_SECRET_STAGING` (staging), or a
file in the credentials directory: `admin-secret.txt` (falling back to
`MCDM_CLOUDFLARE_SECRET.txt`) for release, `admin-secret-staging.txt` for staging.

When a reporter's game is on the DurableObjects backend, the Worker resolves and
authorises the send but hands the actual write back here, because it needs an admin
WebSocket to the *game-server* Worker -- a different service, with its own secret, which
the dashboard has no business holding. A Firebase-backed game is written by the dashboard
and needs nothing on this machine.

The value is whatever `wrangler secret put ADMIN_SECRET` last set in
`cloudflare-game-server/`; wrangler cannot read a secret back, so it has to be saved here
when it is set.

Without it: `send-game-chat.py` cannot finish a send into a DurableObjects game.
Everything else works.

## The credentials directory

Optional now -- it holds only the Discord settings and any admin-secret files. The first
of these that contains a `bug-report-config.json` wins:

| Order | Location |
|---|---|
| 1 | `$BUG_REPORT_CONFIG` -- a full path to the config **file** |
| 2 | `$DMHUB_ADMIN_DIR/bug-report-config.json` -- a **directory** holding it |
| 3 | `~/.dmhub/bug-report-config.json` |
| 4 | `D:\dev\dmhub-admin\bug-report-config.json` (the historical admin checkout) |
| 5 | `C:\dev\dmhub-admin\bug-report-config.json` |
| 6 | `~/dev/dmhub-admin/bug-report-config.json` |
| 7 | next to these scripts -- **only** for a private checkout; `.gitignore`d |

To set one up:

```bash
mkdir -p ~/.dmhub
cp .claude/skills/bug-fix/scripts/bug-report-config.example.json ~/.dmhub/bug-report-config.json
```

## Python dependencies

```bash
pip install -r .claude/skills/bug-fix/scripts/requirements.txt
```

`requests` plus `websockets` (the latter only for the DurableObjects chat path). No
`firebase-admin`.

## Pointing at a different dashboard

`$BUG_DASHBOARD_URL` overrides the dashboard base url -- that is how you test a Worker
change before deploying it:

```bash
cd internal-dashboards && npm run build && npx wrangler dev --local-protocol https
```

then run the scripts with `BUG_DASHBOARD_URL=https://127.0.0.1:8787`. It must be **https**:
the auth cookie is `Secure`, so a plain-http dev server silently drops it and every call
comes back 401.

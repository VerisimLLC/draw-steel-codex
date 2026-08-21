# bug-fix credentials

These scripts are checked into a source repo, so **no secret may ever be stored next to
them**. Every credential lives in a separate **credentials directory** outside the repo.

Check what is configured on this machine at any time:

```bash
python .claude/skills/bug-fix/scripts/check-credentials.py
```

It prints one line per credential -- resolved or missing, and where from -- and never
prints a secret value.

## Where the credentials directory is

The first of these that contains a `bug-report-config.json` wins:

| Order | Location |
|---|---|
| 1 | `$BUG_REPORT_CONFIG` -- a full path to the config **file** |
| 2 | `$DMHUB_ADMIN_DIR/bug-report-config.json` -- a **directory** holding it |
| 3 | `~/.dmhub/bug-report-config.json` |
| 4 | `D:\dev\dmhub-admin\bug-report-config.json` (the historical admin checkout) |
| 5 | `C:\dev\dmhub-admin\bug-report-config.json` |
| 6 | `~/dev/dmhub-admin/bug-report-config.json` |
| 7 | next to these scripts -- **only** for a private checkout; `.gitignore`d |

To set one up from scratch:

```bash
mkdir -p ~/.dmhub
cp .claude/skills/bug-fix/scripts/bug-report-config.example.json ~/.dmhub/bug-report-config.json
```

then fill it in and drop the files below beside it.

## The credentials

### 1. Firebase service-account key -- REQUIRED

**File:** `mcdm-key.json` in the credentials directory (or an absolute path in the
config's `keyPath`).

Every step needs this: reports live in the MCDM Realtime Database at `/BugReports` and
`/BugReportsArchive`, and the service account is what reads them (and what writes a
chat line for `send-game-chat.py`, bypassing RTDB rules).

Get it from the [Firebase console](https://console.firebase.google.com/) for project
**mcdm-385cf**: *Project settings > Service accounts > Generate new private key*. Save
the downloaded JSON as `mcdm-key.json` in the credentials directory. Never commit it.

Without it: nothing works -- not even loading a report.

### 2. Discord webhook(s) -- needed to close a bug out

**Config keys:** `discordWebhook` (default channel, `#user-feedback`) and
`channels.bug.webhook` (`#bugs`).

A webhook is bound to one channel, so routing bug threads to `#bugs` and everything
else to `#user-feedback` takes one webhook each. Create them in Discord:
*channel > Edit Channel > Integrations > Webhooks > New Webhook > Copy Webhook URL*.

Without them: `bug-close-out.py` cannot post the "Fixed and Closed" reply.

### 3. Discord bot token -- optional, closeout thread archiving only

**Env:** `$DISCORD_BOT_TOKEN`, or config `discordBotToken`.

Webhook tokens cannot touch `/channels`, so archiving a thread (so it drops off the
forum's active list) needs a real bot: a bot in the guild with **Manage Threads** on
both forum channels. Create it at the
[Discord developer portal](https://discord.com/developers/applications) >
*Bot > Reset Token*, then invite it with that permission.

Without it: closeout still posts the reply, then reports that the archive step was
skipped. That is a note, not a failure.

### 4. Dashboard tickets password -- needed for the ticket half of closeout

**Env:** `$BUG_TICKETS_PASSWORD`, or config `ticketsPassword`.

Gates the internal dashboard's `/api/tickets/*` endpoints, which post the developer
message onto the reporter's ticket and close it. It normally needs **no** setup: the
scripts read `TICKETS_PASSWORD` straight out of `internal-dashboards/wrangler.jsonc`
in the dmhub repo, searching `$INTERNAL_DASHBOARDS_WRANGLER`, then config `dmhubRepo`,
then every ancestor of the working directory. Set config `dmhubRepo` to the dmhub
checkout path if the scripts run from somewhere else.

Without it: closeout skips steps 1+2 and only does the Discord half.

### 5. Worker ADMIN_SECRET -- optional, only to message a player in-game

**Env:** `$DMHUB_ADMIN_SECRET` (release) / `$DMHUB_ADMIN_SECRET_STAGING` (staging), or a
file in the credentials directory: `admin-secret.txt` (falling back to
`MCDM_CLOUDFLARE_SECRET.txt`) for release, `admin-secret-staging.txt` for staging.

`send-game-chat.py` authenticates an admin WebSocket to the game-server Worker with it
when the target game is on the DurableObjects backend. Firebase-backed games use the
service-account key instead and need nothing here.

The value is whatever `wrangler secret put ADMIN_SECRET` last set (in
`cloudflare-game-server/`); wrangler cannot read a secret back, so it has to be saved
here at the time it is set.

Without it: `send-game-chat.py` refuses for DurableObjects games. Everything else works.

## Python dependencies

```bash
pip install -r .claude/skills/bug-fix/scripts/requirements.txt
```

`websockets` is only imported on the DurableObjects path of `send-game-chat.py`.

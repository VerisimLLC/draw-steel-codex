# bug-fix credentials

**One credential: the shared team password.** There is no Firebase key here and no
Discord secret either, and there should never be. The bug system is reached through
`/api/bugs/*` on the internal-dashboards Worker, which holds those credentials as Worker
secrets, exposes only the bug system, and makes the Discord calls on your behalf. The
only other thing a developer might need is `ADMIN_SECRET`, and only for chat sends into
a DurableObjects game.

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

Plus two Discord actions, both scoped to one thread: post an embed into it, and archive it.

It cannot be pointed at an arbitrary path, it does not enumerate the database, and the
single write appends one record at a fresh guid, so it cannot overwrite anything. The
`allowGameEntry` consent gate is checked **in the Worker**, which means it is no longer
something a caller on this side can skip.

## The credentials

### 1. Dashboard team password -- REQUIRED, and the only one you supply

Put it on a single line in **`~/.dmhub/tickets-password.txt`**:

```bash
mkdir -p ~/.dmhub
printf '%s' 'THE-PASSWORD' > ~/.dmhub/tickets-password.txt
```

(Creating it in an editor keeps it out of your shell history.) It is the same password
as the Tickets dashboard login -- ask a teammate if you do not have it.

That is the whole setup. Anyone who knows the password can use the skill; nothing else
needs configuring, and no other credential goes on your machine.

Resolution order, first hit wins:

1. `$BUG_TICKETS_PASSWORD`
2. `$BUG_TICKETS_PASSWORD_FILE`, or `tickets-password.txt` in the credentials directory
3. `"ticketsPassword"` in `bug-report-config.json`
4. `TICKETS_PASSWORD` read out of `internal-dashboards/wrangler.jsonc`

**Do not rely on 4.** `internal-dashboards` is a separate private repo, gitignored by the
dmhub parent, so a fresh dmhub clone does not contain it -- that path only works for
whoever has that checkout sitting inside the repo. It is a convenience, not the mechanism.

If the password is missing, every script exits with the setup instructions above. If one
is found but rejected, the message names the file or env var it came from so you know
which to fix.

### 2 + 3. Discord -- held by the dashboard, not by you

**Nothing to configure locally.** The webhooks and the bot token are Worker secrets, and
the dashboard makes the Discord calls on your behalf via `/api/bugs/discord-reply` and
`/api/bugs/discord-archive`. A bot token handed to a client is a bot token you no longer
control -- it can be kept, copied and used from anywhere, forever, outside any audit
path -- so it stays on the Worker, which also makes every use loggable.

`check-credentials.py` reports whether the *deployment* has them; that is a property of
the Worker, not of your machine. To set or rotate them:

```bash
cd internal-dashboards
npx wrangler secret put DISCORD_WEBHOOKS   # JSON map: {"default":"https://...","bug":"https://..."}
npx wrangler secret put DISCORD_BOT_TOKEN  # archiving only
```

Pipe from a file rather than pasting, so the value never reaches your shell history.

- **Webhooks** route by the thread's `channelKey`, which the Worker reads from the issue
  registry -- a caller cannot post into the wrong forum by claiming a different one.
  Absent (pre-split threads) falls back to `default`. Create them in Discord: *channel >
  Edit Channel > Integrations > Webhooks*. Without them, closeout does the ticket half only.
- **Bot token** is archive-only: a webhook token cannot touch `/channels/{id}`, where
  thread state lives, so archiving needs a real bot in the guild with **Manage Threads**
  on both forums ([developer portal](https://discord.com/developers/applications) > *Bot >
  Reset Token*). Without it, closeout still posts the reply and reports the archive step
  as skipped -- a note, not a failure.

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

Optional now -- with Discord moved to the Worker it holds only the admin-secret files
(and a `dmhubRepo` pointer, if the scripts run from outside the dmhub checkout). The first
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

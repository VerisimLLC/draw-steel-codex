# Player Tags (EotW) -- Design Brief

Status: **LOCKED 2026-11-18** after the critique round. Ledger rows marked SUPERSEDED are kept
for history only.
Started: 2026-11-18 (an earlier discussion on another machine was lost; this brief starts fresh).

## 1. Frame

**Problem.** EotW players have no lasting, visible record of what they have achieved
as players (not heroes). Player Tags are account-level badges earned by doing things
(first win, 10 wins, top contributor to a town building, ...), which the player can
choose to show beside their name across EotW.

**Who it serves.**
- *Players (set-and-forget pole):* earn tags automatically, get told when it happens,
  pick one to show. No bookkeeping.
- *Designers/admins (power pole):* add a new tag (name, look, how it is earned) quickly,
  without a bespoke code change per tag.

**Done looks like.** A designer adds a tag in one file and deploys; players who meet it
earn it (with a visible "you earned X" moment); a player picks a tag; other players see
it next to that player's name on the main EotW surfaces.

**Standing constraints.**
- All durable per-account EotW state lives in the Blackbottom City (Cloudflare Durable
  Object, `cloudflare-game-server` repo, not this repo). Clients cannot write City
  tables directly; they send `Request` actions validated against identity.
- No player profile, titles, badges or cosmetics exist today -- greenfield.

## 2. Decision map

| # | Category | Status |
|---|---|---|
| 1 | Authority: who decides a tag is earned, where earned tags are stored | decided |
| 2 | Tag definition: registry shape, how definitions reach the City | decided |
| 3 | Rule vocabulary + counters at launch (wins, plays, projects...) | decided |
| 4 | Retroactivity: do existing players get tags for past deeds? | decided |
| 5 | Selection: one tag shown or several; where the picker lives | decided |
| 6 | Display: which surfaces show the tag; live lookup vs snapshot in records | decided |
| 7 | Earn moment: notification / feedback when a tag is earned | decided |
| 8 | Visual form: text chip, icon, color tiers; legibility at 13-17pt | decided |
| 9 | Copy: tag names, descriptions, earn strings | decided |
| 10 | States: late joiner, offline City, tag definition removed/renamed, revoked | decided (sections 7, 8) |
| 11 | Moderation: admin grant/revoke | decided (sections 7, 8) |
| 12 | Phasing / out of scope | decided (section 7) |

## 3. Decision ledger

| Date | Decision | Rationale |
|---|---|---|
| 2026-11-18 | **Authority: City awards, Lua defines.** Tag definitions (name, look, rule) are authored in codex Lua; the City keeps per-account counters, evaluates rules when it records results, and stores earned + selected tags. | One entry per new tag once counters exist; no new cheat surface beyond today's client-supplied results; awards can fire for offline players (e.g. top builder at project completion). Cost: new condition *kinds* need server work in `cloudflare-game-server`. |
| 2026-11-18 | SUPERSEDED (see "Tag file bundled") -- **Definitions: one Lua file the City reads; no publish button.** Adding or changing a tag = edit the file and deploy. | Single source of truth, no forgotten sync step. |
| 2026-11-18 | **Rule vocabulary: threshold + named events.** A rule is either `{counter=X, atLeast=N}` or `{event=X, ...params}`. Launch counters: `wins`, `defeats`, `encountersPlayed`, `practiceWins`, `projectPoints`, `hallEntries`; launch events: `projectTopBuilder`, `projectCapstone` (per project). Defaults (not contested): counters are per account across all heroes; Deadly Mode counts the same. | Trivial to parse on the server; a tag on an existing counter is one line. Composable `all`/`any` conditions rejected for launch: needs a matching evaluator in two languages and no current tag idea requires it. |
| 2026-11-18 | **Retroactivity: backfill exact data.** (Sources corrected in section 8: counts come from `city_outcomes` per distinct gameid, and `defeats`/`encountersPlayed` ARE backfilled.) One-time server migration seeds `wins` (from `city_completions`), `practiceWins`, `projectPoints` (from `city_project_rolls`), `hallEntries`, and `projectTopBuilder`/`projectCapstone` for already-completed projects, then evaluates every account once. `defeats` and `encountersPlayed` start at 0 (no exact per-account record exists). | Launch reads as recognition, not a reset; Forge builders keep their credit. Start-fresh rejected: early players could never earn completed-project tags. |
| 2026-11-18 | **Selection: one tag shown.** (Auto-pick superseded by "No automatic tags".) Exactly one chosen tag beside the name (or none). A player who has never picked gets their first earned tag shown automatically; later earns never change an existing pick. | Name lines are tight (chat, hero-card "Controlled by", ~120px friends row); one look per player on every surface. Up-to-three and "+N" rejected: inconsistent looks / clutter. |
| 2026-11-18 | **Picker lives in the Hero's Guild** (`EotwRoster.GuildPanel`, `EotwRoster.lua:2925`). Exact form (button beside Create/Recruit, header line, or section) decided with display/visuals. | User direction: the Guild is the player's "who I am in town" place. A click-a-name player card was not chosen as the picker; whether one exists for *viewing* others' tags is part of round 6. |
| 2026-11-18 | SUPERSEDED (see "Transport: stamp tag beside name") -- **Transport: live lookup.** The City publishes one small `userid -> chosen tag id` map in its document; every surface resolves the tag by userid against the Lua tag list. No existing record format changes. | Always current; works for old Hall/chat records that already carry userids. Snapshot-at-write rejected: new field on every record type and pre-launch history shows nothing. |
| 2026-11-18 | **Launch surfaces: all of them.** Town/game chat, party list + party view bylines, chat presence line; social rail friend rows; own tag in the Guild; Tribute to the Builders, Hall of Heroes "Played by", Town Hall petitions; hero card player line (town and in-game) and hero sheet owner chip. | User direction. In-game surfaces carry a transport caveat (see Open questions). |
| 2026-11-18 | **Earn moment: banner + unseen dot.** The City keeps each account's unseen tags. Next time the player is in town, a banner shows the tag, its name, how it was earned, and a "Show this tag" button. The Guild picker marks unseen tags with a dot until viewed. No chat broadcast. | Works for tags earned offline (project completion) and for wins recorded on return to town. Chat announce rejected for now (noise); quiet dot-only rejected (most players would never notice). |
| 2026-11-18 | **Look: a badge with the name.** (Color model superseded by "Named badge styles".) A small bordered, colored panel holding the tag name; no icon. Each tag defines its own fill and border color in the Lua file. Tight surfaces truncate the name, never drop the badge. | User direction. The name text carries the meaning, so color is never the only signal; text color must meet contrast against each tag's fill (check at authoring). |
| 2026-11-18 | **Unearned tags: dimmed in your own picker, never selectable or shown to others.** The City rejects selecting a tag the account has not earned. | Dimmed entries give players goals to chase; a tag beside a name must always mean it was earned. |
| 2026-11-18 | **Launch list edits:** "First Victory" renamed **Hero of Blackbottom** (id `hero-of-blackbottom`); **Final Hammer removed**. With no tag using it, the `projectCapstone` event drops out of Phase 1 server work (add it back when a tag needs it). | User direction. |
| 2026-11-18 | SUPERSEDED (see "No automatic tags") -- **Critique: failure tags never auto-show.** Tags get an `autoShow` flag (default true); Undaunted sets `autoShow = false`, so it can be picked but is never picked for you. | A new player who loses 5 times before winning would otherwise wear a public mark of failure. |
| 2026-11-18 | **No automatic tags.** A tag is shown only after the player selects it; everyone starts with no tag, and earning never changes what is shown. The banner's **Show This Tag** button is the quick path. The `autoShow` flag is dropped. | User direction: showing a tag is always the player's choice. Also removes the Undaunted problem at the root. Supersedes the auto-pick part of "Selection: one tag shown". |
| 2026-11-18 | **Early-tier names signed: Wayfarer** (5 encounters played) **and Bricklayer** (100 project points; replaces the proposed "Hod Carrier"). | User direction. |
| 2026-11-18 | **No Proving Pits tags for now.** Danger Seeker is removed and the `practiceWins` counter drops out of Phase 1 (no backfill, no server work). | User direction. Also sidesteps the open question about where the practice/series City code lives. |
| 2026-11-18 | **Temple and Challenge tags added:** Pilgrim, Hand of Saint Llewellyn (top builder of `restore-temple`), Keeper of the Rite, Challenger, Glutton for Punishment, Deathdefier. A 1-rite tag was proposed and removed; "Templewright" was renamed Hand of Saint Llewellyn. A tag for having your own hero raised was rejected (rewards a death; confusable with the hero title "Back From the Grave"). | User direction. |
| 2026-11-18 | **Vocabulary extension for these tags.** New counters: `challengeWins` and `deadlyWins` count *distinct encounters/series parts* won in that mode, backfilled exactly from the `key!challenge` / `key!deadly` completions; `ritesAided` increments when a Rite of Return the account rolled on raises a hero owned by *another* account (backfill from rite roll records if they keep the roller; otherwise starts at 0). A counter rule may take an optional `project` filter (`projectPoints` scoped to one project). | Challenge "completion" means per encounter, matching how the City already keys it. Own-hero rites excluded so a player cannot farm it on their own graves. Deadly Mode exists only on the Great Forge siege today, so Deathdefier is earnable only there until more encounters get it. |
| 2026-11-18 | **Critique: named badge styles.** A small set of badge styles (bronze, silver, gold, ember, slate, teal, violet, copper) registered once in DefaultStyles with fill/border/text per theme; each tag names a style. Rank also shown by border weight, not hue alone. | Per-tag hex bypassed the theme (STYLE_GUIDE:43-44), failed contrast on light/custom schemes, and was not color-blind safe. |
| 2026-11-18 | **Critique: early tiers added** -- one for plays (5 encounters) and one for project points (100). Names unsigned (section 6). Hiding event tags until earned, and progress counts on locked tags, were offered and NOT chosen. | Closes the dead zone between the first win and 10 wins / 25 plays / 1,000 points. |
| 2026-11-18 | **Critique: tag file bundled into the City at server deploy.** The codex Lua tag file stays the single source, in a strict plain-data form (one returned table of strings/numbers/booleans, no comments inside entries, with a `version` field), bundled into the City worker when the server deploys. Clients draw the tag list from the City (returned with `list-heroes`), so client and server never disagree; the City rejects rule kinds it does not know. | Supersedes "City reads the deployed Lua file": avoids live Lua parsing, dev/staging/release copy ambiguity, deploy-order invisible tags, and CodeMod write access becoming tag-granting access. Cost: a tag change needs a server deploy as well as (or instead of) a codex deploy. |
| 2026-11-18 | **Critique: transport -- stamp tag beside name.** The City adds the player's *current* tag next to `name` wherever it already stamps names: presence, chat messages, party/game records, and `list-hall` / `list-project-builders` responses. Chat lines keep the tag they had when sent. In-game surfaces read it from the game record. | Supersedes the global userid->tag map, which grows with every account and re-broadcasts to everyone on each change. Still current on live surfaces and lists; also settles in-game lookup. |
| 2026-11-18 | **Critique: anti-forgery.** A win counts toward tags only if the City's own game record shows that hero claimed in that `gameid`; Hall of Heroes players are cross-checked against the game's party; counted wins are capped per account per day. Sanctioned accounts' outcomes do not count. | A public badge gives forged wins a payoff they never had before. |
| 2026-11-18 | **Critique: not adopted** -- unseen dot on the town map's Guild button, and clicking your own badge to open the picker. | User did not choose them; the banner and Guild dot carry discovery. Revisit if players miss tags. |

## 4. Open questions

- **How the bundled tag file reaches the worker build** (git submodule, copy step, or fetch at
  build time) -- an implementation-planning detail for the server repo.
- *Resolved:* how the City reads the Lua file (bundled; see ledger). In-game lookup (tag
  stamped on the game record; see ledger).

## 6. Launch tags and UI copy (signed 2026-11-18)

| id | Name | Rule | Description (shown in Guild + banner) | Badge style |
|---|---|---|---|---|
| `hero-of-blackbottom` | Hero of Blackbottom | `wins >= 1` | Won your first encounter. | bronze |
| `wayfarer` | Wayfarer | `encountersPlayed >= 5` | Played 5 encounters. | teal |
| `bricklayer` | Bricklayer | `projectPoints >= 100` | Put 100 points into town projects. | copper |
| `seasoned` | Seasoned | `wins >= 10` | Won 10 encounters. | silver |
| `legend` | Legend | `wins >= 50` | Won 50 encounters. | gold |
| `undaunted` | Undaunted | `defeats >= 5` | Fell in 5 encounters and kept coming back. | slate |
| `regular` | Regular | `encountersPlayed >= 25` | Played 25 encounters. | teal || `builder` | Builder | `projectPoints >= 1000` | Put 1,000 points into town projects. | copper |
| `forgewright` | Forgewright | event `projectTopBuilder`, `build-great-forge` | Contributed the most to building the Great Forge. | ember |
| `pilgrim` | Pilgrim | `projectPoints >= 100`, `project = "restore-temple"` | Put 100 points into restoring the Temple of Saint Llewellyn. | silver |
| `hand-of-saint-llewellyn` | Hand of Saint Llewellyn | event `projectTopBuilder`, `restore-temple` | Contributed the most to restoring the Temple of Saint Llewellyn. | gold |
| `keeper-of-the-rite` | Keeper of the Rite | `ritesAided >= 5` | Helped raise 5 fallen heroes. | gold |
| `challenger` | Challenger | `challengeWins >= 1` | Won an encounter in Challenge Mode. | ember |
| `glutton-for-punishment` | Glutton for Punishment | `challengeWins >= 10` | Won 10 different encounters in Challenge Mode. | ember |
| `deathdefier` | Deathdefier | `deadlyWins >= 1` | Won an encounter in Deadly Mode. | slate |

UI strings:
- Guild button: **Tags**
- Picker heading: **Your Tags**; subline: **Choose the tag shown beside your name.**
- Picker "none" option: **Show no tag**
- Locked tag (not yet earned): shown dimmed with its description in YOUR picker only; cannot be selected (decided 2026-11-18)
- Earn banner: title **Tag Earned**, body **{description}**, button **Show This Tag**, dismiss **Later**
- Empty picker: **You have not earned any tags yet. Win encounters and help build the town to earn them.**

## 7. Proposed: states, moderation, phasing (UNSIGNED -- rounds 10-12)

**States (round 10)**
- *Tag renamed or recolored in the Lua file:* ids are permanent, so the change shows everywhere on next deploy (live lookup).
- *Tag removed from the file:* the City keeps the earned record but nobody sees it; a player who had it chosen shows no tag (no automatic replacement).
- *Threshold raised:* players who already earned it keep it.
- *City not reachable / map not loaded yet, or a tag id this client does not know:* the name shows with no badge -- no placeholder, no error.
- *Late joiner / new party member:* covered by the live map.

**Moderation (round 11)**
- Admin-only City actions `admin-grant-tag` and `admin-revoke-tag` (via `CITY_ADMINS`), to fix bugged or forged awards.
- Rule kind `{manual = true}`: tags that only an admin can grant (e.g. Playtester, Encounter Author). No admin UI at launch; called from the existing admin/moderation tooling.

**Phasing (round 12)**
- *Phase 1:* server work (counters, backfill, evaluation in `record-outcome` / `project-roll` / `hall-record`, tag map, unseen list, select action, admin grant/revoke); codex tag file; Guild picker; earn banner; badges on all town surfaces.
- *Phase 2:* in-game surfaces (hero cards and hero sheet inside an encounter), once in-game lookup is settled.
- *Out of scope, with reasons:* chat announcements (noise), composable rules (two-language evaluator), icons on badges (user chose name-only), showing several tags (tight name lines), a click-a-name player card (no viewing surface needed yet; revisit if players ask "how did they get that?").

## 8. Critique round (2026-11-18)

Three critics (UX/Hodent, server systems, accessibility). Corrections that do not change a
signed decision are folded in here; findings that would change a decision are listed as
proposals until the user rules on them.

**Folded (corrections and missing specification)**
- *Counting unit is the game, not the hero.* `record-outcome` is sent once per hero
  (`EncounterOfTheWeek.md:1598`), so 3 heroes = 3 wins if counted naively. Counters
  increment once per new (userid, gameid). This supersedes the backfill sources in the
  ledger: backfill `wins`, `defeats`, `encountersPlayed` from `city_outcomes` (PK userid,
  heroid, gameid; md:1579) as distinct gameids. `city_completions` is NOT exact (PK userid,
  heroid, encounter; Deadly writes 3 rows; md:6100, 1196). `defeats` and `encountersPlayed`
  ARE backfillable (defeat survivors send `result = "defeat"`).
- *"Played" means* a distinct gameid with a recorded outcome. Abandoned games and practice
  games do not count.
- *(Moot -- Proving Pits tags deferred.)* *`practiceWins` counts distinct encounters* (`city_practice_wins` PK userid, encounter;
  md:3079). Danger Seeker copy becomes "Won 5 different practice encounters." Confirm the
  practice/series City source exists in `cloudflare-game-server` (md:3431 says it is in no
  local repo).
- *`projectPoints`* counts credited points (overflow past the goal excluded) from rolls AND
  siege defense (`city_siege_wins`, md:1200-1205).
- *`projectTopBuilder`* is awarded inside the transaction that completes the project, once
  per (project, completion number), to every player tied for the top, ranked on rolls +
  siege points. Idempotent.
- *Server actions needed:* `select-tag`, earned/unseen/counters returned on `list-heroes`
  (or `list-my-tags`), `mark-tags-seen`, the one-time migration, `dev-reset-account`
  clearing tags, admin grant/revoke, and admin counter correction (revoking without
  fixing the counter would re-award on the next evaluation).
- *Chat uses a text form of the badge.* Chat lines are one rich-text label
  (`Codex Titlescreen/EncounterOfTheWeek.lua:7824-7840`), so a bordered panel cannot sit
  inline. Chat renders `[Name]` in the tag's color at reduced size, like the Discord tag
  (:7826). (Earlier chat anchor :7329 was wrong.)
- *Hero card player line is 9pt, fixed height, no wrap* (`EotwHeroCard.lua:341-347`): it
  gets a compact badge variant sized in em, not the full padded badge.
- *Width rule:* the badge is capped (about 40% of the name line) with its own ellipsis, so
  neither the name nor the badge collapses to one letter. Check at Font Size 80/100/140.
- *Every badge has a tooltip* with full name + description; the Guild picker is the
  non-hover path to the same text.
- *Earn banner behavior:* does not block input; several earns at once (e.g. backfill at
  launch) group into one banner "{n} Tags Earned"; Esc = Later, Enter = Show This Tag;
  unseen state clears only when the player acts. Never opens over another dialog.
- *Locked tags:* only the badge dims; the description stays readable (`@fgMuted`) and the
  row says **Locked** so lock state is not shown by opacity alone.
- *Error states:* a failed select keeps the old badge and shows
  **Couldn't change your tag. Try again.** A revoked tag that was chosen falls back to
  no tag.
- *Sanctioned accounts:* outcomes they send do not count toward tags while sanctioned
  (they can still send `record-outcome`, md:2531).

**Proposals** -- ruled 2026-11-18; see the "Critique:" rows in the decision ledger.

## 9. Implementation notes (built 2026-11-18, not deployed)

**Where it lives**
- Codex: `Codex Titlescreen/EotwPlayerTagDefs.lua` (the tag list, data only) and
  `Codex Titlescreen/EotwPlayerTags.lua` (client: badge, inline text form, Guild picker,
  earn banner). Both registered in the Codex Titlescreen CodeMod. Strings in
  `EotwTextTown.lua` (`tags.*`).
- Server (`D:\DMHub\cloudflare-game-server`): `src/player-tags.ts` (rules),
  `src/lua-table.ts` (reads the codex file), `scripts/gen-player-tags.ts`
  (`npm run gen-player-tags` writes `src/player-tags.data.json`), City actions in
  `city-core.ts` / `city.ts`, the name-tag hook in `lobby.ts`.

**How it differs from the design, and why**
- *Counters are derived, not stored.* The City computes them from outcomes, completions,
  project rolls, siege wins and rites whenever it evaluates an account (list-heroes for the
  caller). So the backfill needs no migration, and repairing bad data repairs its counters.
  Only earned tags (seen/revoked) and each account's choice are stored.
- *Anti-forgery is the daily cap only:* at most 10 games per UTC day count toward each game
  counter. The cross-check of a win against the City's game record was NOT built: the City
  drops a party record when its game ends, so nothing is left to check against later. Doing
  it needs the City to keep party membership per game (open question).
- *Banned accounts earn nothing while banned* (instead of excluding outcomes recorded during
  a ban).
- *projectPoints counts roll totals plus siege points* (overflow included), the same numbers
  the Tribute to the Builders ranks by.
- *Badge styles live in EotwPlayerTags.STYLES,* not DefaultStyles: EotW screens use their own
  fixed dark palette. Rarest styles (gold, ember) get a 2px border.
- *Earn banner:* each tag is announced once per machine (preference `eotw:announcedtags`);
  the Guild dot stays until the picker is opened.
- *Tribute defender rows* show the badge too (2026-11-20), and the Deadly victors' names
  carry the text form.
- *Dropped (2026-11-20, user direction): the hero sheet owner chip and badges inside
  encounters.* Tags are for shared social places in town. The hero sheet is about a hero,
  and inside an encounter only the party sees each other, after seeing their tags in the
  party view. This supersedes the in-game part of "Launch surfaces: all of them" and
  Phase 2.

**To ship:** deploy the server (staging first) and the codex together. Until the server is
deployed, list-heroes has no `tags`: the Guild picker lists every tag as locked and selecting
fails with "Couldn't change your tag. Try again."

## 10. Public goals and the playtest tag (2026-11-21, user direction)

- Only **Hero of Blackbottom, Wayfarer, Bricklayer, Seasoned and Regular** appear, locked,
  in everyone's tag list as goals. Every other tag has `hidden = true` in the tag file: it
  stays out of the list until the player earns it. (Supersedes "unearned tags dimmed in your
  own picker" for those tags.)
- **Founding Hero** (`founding-hero`, violet, hidden): finished any encounter (win or defeat)
  before the playtest ends. Counter rules for wins/defeats/encountersPlayed can now take
  `before = "YYYY-MM-DD"` (UTC). Existing players get it from their recorded games.
- **Open:** the playtest end date. The tag file holds a PLACEHOLDER (`2026-12-31`); set it
  before deploying.

## 5. Evidence appendix (current state, 2026-11-18)

**Per-account state and trust**
- City is authoritative; doc read-only to clients; `Request` validated against identity:
  `Definitions/lobbies.lua:3,7`, `Definitions/LuaLobbyConnection.lua:11,20`.
- Account `unlocks` (dangerRooms, market, practiceWins, openParts, greatForge) come back
  from `list-heroes`: `Codex Titlescreen/EotwRoster.lua:117-119, 409-475, 1236`. Closest
  existing per-account record.
- Outcome facts are client-supplied: `record-outcome` (`EotwRoster.lua:887-889`),
  `hall-record` from host (`EncounterOfTheWeek/EncounterOfTheWeek.lua:2740-2772`),
  `project-roll` totals (`EotwDowntime.lua:1176-1186`). A modified client can already
  forge wins/points; the City only checks ownership/alive/Downtime charge.
- Admin actions exist via `CITY_ADMINS` (`EncounterOfTheWeek/EncounterOfTheWeek.md:899,1038,2229`).

**Stats tracked today**
- Per hero: `city_completions` (md:5820), adventure log `list-outcomes`, Graveyard deaths.
- Per account: `city_practice_wins` only (md:2822). **No per-account wins/plays counter.**
- Hall of Heroes entries list player userids per game (`EncounterOfTheWeek.lua:2752-2769`)
  -- wins per account are derivable from it.
- Victory/defeat path: `CheckEncounterOutcome` (5706) -> `AutoAwardVictories` (1948) ->
  `RecordHallOfHeroes` (1994/2740, host only, skips practice); `Series.NoteOutcome` (3138)
  -> `RecordPendingOutcomes` (2406) on every client; town `ApplyOutcome`
  (`EotwRoster.lua:870`, success 890-913).

**Projects**
- `build-great-forge`: community, 10000 points, two stages (`EotwDowntime.lua:444-483`).
- Per-player tally exists: `list-project-builders` returns builders ranked by points
  with `cornerstone`/`capstone` (`EotwDowntime.lua:3076-3107, 3166-3191`). Completion
  happens inside the `project-roll` transaction (md:3907).

**Where player names render (tag display candidates)**
- Social rail friends row, name + `SourceIcons` after it (`EotwSocialRail.lua:616, ~580-629`).
- Party list byline (`EncounterOfTheWeek.lua:5292`), party view byline (5885-5895),
  hero card "Controlled by" (5697).
- Town/game chat `"<b>name:</b> body"` (`EncounterOfTheWeek.lua:7329-7341`); Discord
  bridge already appends an inline tag after the name (:7331).
- Hall of Heroes "Played by" (`EotwRoster.lua:3648-3690`, names snapshotted at write).
- Tribute to the Builders leaderboard (`EotwDowntime.lua:3076`) -- most room.
- Town Hall petitions byline (`EotwTownHall.lua:802`); hero sheet owner chip
  (`EotwHeroSheet.lua:3971`); hero card player line (`EotwHeroCard.lua:38-51`).
- City stamps `name` server-side on presence, games, chat, hall, builders -- a `tag`
  beside `name` is the natural transport.
- No public per-user profile field; `storage="account"` settings are private.

**Reusable visuals**
- `multiselectChip*` ("tag pills"), `DefaultStyles.md:141-156`; overflow chip spec
  `STYLE_GUIDE.md:55,70,131`; EotW chips `eotwStatChip`, `eotwsOwnerChipText`, `HammerChip`.

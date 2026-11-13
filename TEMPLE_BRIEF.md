# Blackbottom Temple and Undying Ancestries -- Design Brief

Status: **LOCKED; BUILT 2026-11-12, NOT RUN.** Server and codex code are written but untested: this Mac has no Node or Lua, the two new Lua files are not registered with the CodeMod (the DMHub bridge was unavailable), and nothing is deployed. Build notes: the UI text says "Adun" because `tests/uitext_check.lua` rejects non-ASCII text values (C7's escape works in code but not in text files); rites roll 2d10 + Presence or Reason, +2 if trained in Religion *(chosen during the build)*; the built Temple's art is still the Construction still until the chapel image is uploaded as an asset.

## Framing

**Problem.** In Encounter of the Week (EotW) a hero who dies is buried: the City marks them
fallen and they go to the Graveyard. The only way back is David's **Awaken** button
(commit 429ca7e5, 2026-11-11), which instantly and freely returns a Hakaan, Revenant or
Vampire. Every other hero is gone for good. Separately,
two ancestries (Revenant, Hakaan) have a rules feature that stops them dying outright, and
neither is automated.

**For whom.**
- *Set-and-forget player*: lost a hero they liked and wants a clear way to get them back that costs something.
- *Invested player / town builder*: wants death to stay meaningful and the cost to sit in the town economy (Downtime, projects), not be a button.
- *Director outside EotW* (Revenant/Hakaan part only): wants the ancestry rule to work without bookkeeping.

**Done looks like.**
1. A Temple location in Blackbottom where you can return a fallen hero to your roster for a cost.
2. Revenant "Tough But Withered" and Hakaan "Doomsight" put the hero in an inert state at -winded instead of killing them, and they come back on their own later (Revenant: unless fire damage hits the inert body).

**Inherited constraints.**
- The City (the server, `cloudflare-game-server`, not in this repo) is the authority on fallen heroes: it refuses `put-hero` on a fallen hero. Resurrection **needs a new City action**; the Lua side cannot do it alone.
- In Draw Steel, Wealth is a count, not a currency. The EotW Market treats it as a purchase limit that never goes down.
- Death is decided **at the encounter's conclusion** (`OutcomesFor`, `EncounterOfTheWeek/EncounterOfTheWeek.lua:2286`): a hero who is `IsDead()` then is buried. A hero saved before then lives.

## Decision ledger

| Date | Decision | Why |
|---|---|---|
| 2026-11-11 | **A. Cost = project points.** The Temple opens a "Rite of Return" project for one fallen hero; Downtime rolled into it pays the cost. | The server already checks project points (`project-roll`), so the cost can't be faked; it costs time, the town's real currency. |
| 2026-11-11 | **B1. Anyone in town can contribute.** The fallen hero's owner starts the rite; any player's living hero can roll Downtime into it. | A player who lost their only hero isn't stuck; raising the dead becomes a town act. |
| 2026-11-11 | **B2. Goal = 30 x the hero's level.** | About 2 rolls at level 1, 11 at level 5, 21 at level 10: cheap early, a real undertaking for veterans. |
| 2026-11-11 | **B3. The hero returns with everything** (level, XP, Victories, items, Wealth) **plus the *Back From the Grave* title unlocked.** | Draw Steel awards that title for being restored to life, so the mark is a story, not a penalty. Note: the title carries the Revenant's inert clause, so category E applies to raised heroes too. |
| 2026-11-11 | **B4. The grave stays, marked as opened** ("rose on <date>"). | Keeps the town's history and shows that rites work. |
| 2026-11-11 | **B5. No time limit.** Any grave can be raised at any time. | EotW players come and go; a deadline mostly punishes people who were away. |
| 2026-11-11 | **B6. A hero can be raised again; each later rite doubles the goal** (30, then 60, then 120 x level). | Death stays meaningful without becoming a hard wall. Needs a per-hero rite count on the City record. |
| 2026-11-11 | **C1. The town builds the Temple** as a community project ("Restore the Temple"), with a ruined-site scene until it's done, following the Hall / Town Hall / Training Grounds pattern. | A shared town goal; graves wait meanwhile (B5), so nobody loses the chance. |
| 2026-11-11 | **E0. No inert state.** Undying heroes (Revenant, Hakaan, *Back From the Grave*) die normally; a Lua Script behavior on a death trigger stamps them to come back later. | The user's call: the hero still dies, so every existing death path (Hero Death, kill triggers, outcomes) keeps working unchanged. |
| 2026-11-11 | **E1. Outside EotW the return is entirely up to the Director.** No automation. | Only EotW needs the timer; a Director already controls story time. |
| 2026-11-11 | **F1. In EotW an undying hero returns after 12 real-life hours.** | The user's call: the wait is the cost, measured in real time. |
| 2026-11-11 | **F2. Undying heroes are buried with a countdown and rise on the City's clock.** The grave reads "Rises in 11h 40m"; at 12 hours the City raises the hero through the same return path as a rite (no project); they come back with everything. | One return path on the server for both; the server clock can't be cheated. |
| 2026-11-11 | **E2. Fire makes a Revenant's death final only if the killing blow was fire.** Hakaan ignore fire. | Simplest rule; the corpse already records the killing damage type (`_tmp_lastdamagetype`, `AbilityRemoveCreature.lua:163`). |
| 2026-11-12 | **B7. No raising into a full roster.** A rite can't be started without a free roster slot (4 to 9; see the critique, which corrected an earlier '12'), and the Temple says to dismiss a hero to make room. If the roster fills while a rite is under way, or when an undying hero's countdown ends, the hero waits in the grave as "Ready to rise: dismiss a hero to make room" and rises as soon as a slot opens. | The user's call: the 12-hero limit holds, and the player is told why. (The waiting state is how this applies to an undying countdown, which can't be blocked from starting.) |
| 2026-11-12 | **H1. Ship everything in one release:** the undying return, countdown graves, Restore the Temple, and Rites of Return. | The user's call. |
| 2026-11-12 | **C3. Restore the Temple costs 6000 project points.** | It undoes permanent death, a gameplay power on the scale of the Training Grounds (6000), not the Town Hall (4000, votes and petitions). |
| 2026-11-12 | **C4. Two stages, walls first.** Up to 50%, Rebuilding: Might/Agility with Architecture, Mechanics, Religion. Then Reconsecration: Presence/Intuition with Religion, Lead, History. (Order and Intuition: the user's calls, 2026-11-12.) | Same shape as the Great Forge; rolls change character halfway. |
| 2026-11-12 | **C5. Art: the site reuses the Construction still; the built Temple gets a placeholder** until real art of known provenance arrives. | Nothing blocks on art. |
| 2026-11-12 | **C6. Hidden by default** (`defaultHidden`); an admin shows it per server. | The eotw-building skill's rollout rule. |
| 2026-11-12 | **C7. The Temple of Adûn**; while it's rebuilt, the site is "the Ruined Temple of Adûn". In Lua the name is written `"Ad\u{00FB}n"` so the source stays ASCII (the codex already escapes characters this way, e.g. `EotwHeroSheet.lua:1853`). | Adûn (Creation, Life, Love, Protection) teaches that hard work is honesty, which fits a resurrection earned with Downtime labour. Draw Steel has no single god of life or death, and its Death-domain gods are evil. |
| 2026-11-12 | **C5a. The built Temple's scene art is supplied by the user**: a painted chapel interior with pews, a red carpet, an apse and a statue (2000x1125, 16:9; source at the time of the brief: the session image `images/1.jpg`). It replaces the placeholder from C5. The site still uses the Construction still. | Real art in hand. Credited to **Czepeku** (`CreatorCredit.RegisterArt`). The statue is fine as it is: the art sets a mood and isn't a portrait of Adûn (user, 2026-11-12). |
| 2026-11-12 | **C9. The Temple is Saint Llewellyn the Valiant's** (supersedes C7, Adûn). The built Temple is "the Temple of Saint Llewellyn"; while it is being rebuilt the site is "the Destroyed Temple". | The user's call. Llewellyn (Life, Protection; a saint of Cavall) died defending his fallen horse, and Cavall raised them both: a saint who rose from death, for the place that raises the fallen. The name is plain ASCII, so the text files can use it as is. |
| 2026-11-12 | **C8. Map spot: a placeholder near the Graveyard** (Graveyard is x 0.89, y 0.86; the Temple starts at x 0.80, y 0.78) and gets adjusted in the app. | Keeps the dead and the place that raises them together; the exact spot depends on the map art. |
| 2026-11-12 | **R1. Extend David's Awaken instead of building a second path** (supersedes C2's "no Graveyard button", and F2's automatic rise). The Awaken button on the Graveyard's "Your Fallen" tab stays and the owner presses it. It unlocks 12 real hours after death and shows the countdown until then. It needs a free roster slot. It is refused for fire-killed Revenants and doomed Hakaan. Vampires stay eligible. | David's button and its `awaken-hero` server action already exist. An owner-pressed rise never grabs a freed slot on its own. |
| 2026-11-12 | **R2. Graves stay** on both paths (awakened or raised) and read "Rose on <date>". This changes `awaken-hero`, which deletes the grave today. | Keeps B4 consistent across both paths. |
| 2026-11-12 | **R3. A rite grants no title** (supersedes B3). *Back From the Grave* stays a normal title, earned by its own prerequisite. | The rules award it for dying to your greatest foe (`ClaudeRefHeroes.lua:32400`). Granting it on every raise would make heroes undying and B6 pointless. |
| 2026-11-12 | **R4. An awakened undying hero returns with Stamina equal to their recovery value**, Recoveries as stored. A rite returns the hero at full Stamina. | The rules text; dying is never better than a respite. |
| 2026-11-12 | **R5. No death trigger** (supersedes E0's Lua Script). When the encounter ends, one shared function reports `killedByFire` (from a persisted `killingDamageType`) and `doomed` with each death. The server decides eligibility (ancestry or title, not doomed, not fire for Revenant and the title) and records `diedAt`. | The trigger could be sent to another client while Hero Death despawns the token. Outside EotW the stamp did nothing anyway (E1). |
| 2026-11-12 | **R6. No rite floor and no contribution cap.** The goal stays 30 x level (doubled per earlier rite), and any account may fund any share. | The user's call, made knowing that early raises are cheap and alts can fund them. Revisit with live data. |
| 2026-11-11 | **C2. Rites start at the Temple only.** The Temple lists your fallen heroes and every open rite in town. No button on the Graveyard. | One place, one path. |

## The design (as decided)

Everything here follows from the ledger and the accepted critique fixes. *(proposed)* marks an engineering choice still open for review.

### 1. Undying heroes: Awaken, extended (R1, R2, R4, R5)
- **Who is undying:** Hakaan (unless doomed), Revenant, Vampire, and any hero holding *Back From the Grave*. A Revenant or title holder whose killing blow was fire is not. The server decides from the hero summary plus the outcome's `killedByFire` and `doomed`.
- **At the encounter's end,** `OutcomesFor` (`EncounterOfTheWeek.lua:2286`) adds `killedByFire`, `doomed` and `undying` to each death, using one shared helper. `killingDamageType` is written in `TakeDamage`'s death branch and persists on the token.
- **The City** records `diedAt` with the grave (clamped to the game's start time and now, so an absent player's late `record-outcome` doesn't delay the clock *(proposed)*).
- **The Graveyard's "Your Fallen" tab** keeps David's Awaken button. Before 12 hours it is disabled and reads "Can awaken in 11h 40m (around 9:40 PM)". Without a free slot it reads "No free hero slot: expand the Guild, or dismiss a hero (permanent)". A fire-killed or doomed hero gets no button, only a reason line.
- **`awaken-hero`** enforces the same rules, keeps the grave (`openedAt`, reason `awaken`), and returns the hero inactive. The client sets Stamina to the recovery value on the next promote-then-push.
- **Outside EotW** nothing is automated; the Director decides (E1).

### 2. Raising by rite (City)
- A new `city_rites` subsystem with `start-rite`, `rite-roll` and `list-rites`. It reuses the Downtime-spend and roll-log helpers from `applyProjectRoll`.
- Only the owner starts a rite. Any player's living hero can roll into it (B1).
- **Goal:** 30 x level, doubled for each earlier rite (B2, B6). No floor and no per-account cap (R6).
- **Completion** raises the hero once the owner has a free slot. Otherwise it waits as "Complete: waiting for a free slot", closed to rolls, and the owner presses **Rise** when a slot is free. The hero returns inactive at full Stamina, the grave is kept, and `riteCount` goes up. The owner's roster and graveyard revs are bumped.
- **A deleted or scrubbed fallen hero** cancels their rite; its points go to Restore the Temple.

### 3. Restore the Temple (community project)
- Built by David's eotw-building recipe: `restore-temple`, 6000 points, two stages (C4), `defaultHidden`, unlocking `temple`.
- The site uses the Construction still. The built scene is the user's chapel art (C5a). The node goes near the Graveyard (C8).

### 4. The Temple of Adûn (built panel)
- **Your fallen:** each grave with its rite cost in plain terms ("Goal 300: level 5, about 11 rolls"; "Second rite: goal doubled"). Begin the Rite of Return asks for confirmation first. Undying heroes say "Can awaken at the Graveyard" instead, and doomed heroes say "Beyond return".
- **Rites under way:** yours first, then closest to done. Each card shows portrait, name, owner and percent. "Show all" appears after 5.
- **Empty states:** "None of your heroes lie in the Graveyard" and "No rites under way".

### 5. Feedback
- **The outcome screen** gives each fallen hero a state line: can awaken in 12h / can be raised at the Temple of Adûn / restore the Temple to raise them (only when the project is visible) / beyond return / fire ended their undeath.
- **Town entry** plays a "returned from the grave" banner for any rite completed while the owner was away, naming contributors. The roster card shows "Returned" until seen.
- **Accessibility:** a "Yours" text tag, disabled reasons as visible text, state labels plus icons, and absolute times next to countdowns.

## Decision map

| # | Category | Decision(s) | Status |
|---|---|---|---|
| A | Cost of resurrection | Project points, Wealth, both, or a choice | **decided** |
| B | Rite rules | Who can start it, time limit, what the hero comes back with (Stamina, a lasting mark like the *Back From the Grave* title), what happens to the grave | **decided** |
| C | Temple as a place | Always open, or built by a town project like the Hall / Town Hall / Training Grounds; scene art; map position | **decided** (art and map position: open) |
| D | Server | Shape of the new City action (`resurrect-hero`?) and who builds it | open |
| E | Undying (engine) | Inert state or die-and-return; fire rule; non-EotW behavior | **decided** |
| F | Undying in EotW | When and how the hero returns | **decided** |
| G | Copy | Location label/title/tagline, Temple panel strings, inert condition text | open |
| H | Phasing | One release or staged | **decided** |

## Verified engine reality

**Death**
- Heroes die at Stamina <= -(winded value): `character:IsDead()` `Draw Steel Core Rules/MCDMCreature.lua:2796`, threshold `:2758`. There is no Dead condition; `dead` is a GoblinScript symbol (`:1982`).
- The death transition in `TakeDamage` (`MCDMCreature.lua:6887`) fires `zerohitpoints` (`:6901`) and `creaturedeath` (`:6976`). `SetStaminaDirect` (`:7095`) fires the same events.
- EotW **Hero Death** is a compendium global rule (`creaturedeath`, mandatory local) that despawns the hero into a corpse and re-checks `target.dead` before removing, so a hero healed in time is spared. The "Recovery on Death" rule (`heroic-resources.yaml`) is the one existing in-combat un-die path.
- `CorpseComponent:Respawn` (`DMHub Game Rules/AbilityRemoveCreature.lua:627`) returns a despawned token to the map but does not restore Stamina; nothing calls it today.
- `ActivatedAbilitySetStaminaBehavior` (`DMHub Game Rules/ActivatedAbility.lua:162`) sets Stamina; the Beastheart companion revive uses it.

**Fallen heroes and the town**
- Burial: `OutcomesFor` -> local `eotw:pendingOutcomes` -> `ApplyOutcome` (`Codex Titlescreen/EotwRoster.lua:856`) -> City `record-outcome {died=true}`, which marks the hero fallen and digs a grave.
- Graveyard: `EotwRoster.ShowGraveyard` (`EotwRoster.lua:3139`), `list-graveyard`. Each grave holds `heroid`, `userid`, `at` and an epitaph (name, portrait, level, ancestry, class, encounter, owner). `list-heroes {includeFallen}` already exists.
- Locations are rows in `CITY_LOCATIONS` (`Codex Titlescreen/EncounterOfTheWeek.lua:357`), opened by the `OpenLocation` chain (`:10559`). Built-later locations use the City project + `EotwRoster.XBuilt()` pattern (`EotwRoster.lua:480-527`).

**Economy**
- Wealth: custom attribute, base 1 (`draw-steel-data/objectTables/customAttributes/wealth.yaml`), raised by features and modifiers. The Market reads it as a purchase limit (`EotwMarket.lua:151-162`). Nothing lowers it today.
- Project points are server-authoritative: `project-roll` spends one Downtime and adds points atomically (`EotwDowntime.lua:1118-1170`). Player-scope projects (e.g. `find-arcane-market`) already unlock things on completion.

**Revenant / Hakaan**
- Revenant *Tough But Withered* (`draw-steel-data/objectTables/races/revenant.yaml:111-200`): the immunities and the fire weakness work; the inert clause is a `losehitpoints` trigger with **no behaviors** (a stub). The *Back From the Grave* title copies the same stub.
- Hakaan *Doomsight* (`races/hakaan.yaml:268-281`): the same mechanic (rubble, can't regain Stamina, 12 hours, recovery value), no fire clause, also unimplemented.
- Fire while inert: `losehitpoints` carries `damagetype` (`MCDMCreature.lua:6676-6706`), so "fire damage while inert" can be a trigger condition. There is no stored damage history.
- Time: no rules-level clock. Durations in hours become rounds (`ActivatedAbility.lua:299`) and only advance in combat. The candidate hooks for "12 hours" are respite or rest completion (`creature:Rest`, `Draw Steel Respite/RSPSession.lua:689`) or a Director action.
- Rules precedent: Conduit *Minor Miracle* (resurrect during a respite, at least half the remains, died within 24 hours) is text-only.

## Out of scope / rejected

- **Wealth as the price** (2026-11-11): Wealth is a count that never goes down and caps Market purchases. Spending it would be harsh at Wealth 1 and would need a new lasting modifier.

## Building recipe

David's **`eotw-building`** skill (`dmhubclient/.claude/skills/eotw-building/SKILL.md`, on origin as of 2026-11-12) is the recipe for the Temple *building* (C1). It covers the City project in `city-core.ts`, the `EotwDowntime.PROJECTS` entry, the construction panel, `EotwRoster.TempleBuilt()`, the map node, scenes and reveal, the `EotwTextTemple.lua` text file, and the `EncounterOfTheWeek.md` section. Its model is the Great Forge. The Temple is the "(b) a panel of its own" case: the built Temple's panel (fallen heroes, open rites) is this brief's design, and the skill says to write it into `EncounterOfTheWeek.md` before building.

The skill's step-1 questions that this brief has not answered yet: the site's name, project points (existing buildings: Hall 1000, Town Hall 4000, Training Grounds 6000, Great Forge 10000), stages, characteristics and skills per stage, who builds it with the heroes, art, and map spot. It recommends hidden by default.

The skill does **not** cover the Rites of Return (per-fallen-hero projects whose goal is 30 x level, doubled per earlier rite) or countdown graves. Those need City work beyond its recipe: a goal computed per hero rather than `baseGoal`/`goalStep`, a `raise` path, and graves with `risesAt`.

## Open questions

- What happens to a rite's points if the fallen hero is dismissed or scrubbed by moderation while it's under way?
- Copy: every string is drafted as a placeholder in `EotwTextTemple.lua` during the build (the recipe's step 2) and signed off then.

- The City lives in `~/Documents/GitHub/dmhubclient/cloudflare-game-server/` (`src/city-core.ts`), so this session can build both sides. Server deploys go to staging only; a release deploy always needs the user's OK (per the eotw-building skill).

## Critique round (2026-11-12)

Three critics (UX/accessibility, Draw Steel rules plus economy, technical feasibility) attacked the brief. The fixes below are **accepted** because they correct facts or fill gaps without changing a user decision. The items under "Needs the user's call" would change a ledger decision.

### Accepted (fact corrections and gaps)
- **Roster** is 4 slots base, +1 per Expand the Guild, max 9 (`EotwRoster.lua:77-80`, `city-core.ts:2587`), not 12. Dismissal is permanent, so the copy leads with "Expand the Guild" and mentions dismissal second, with its warning.
- **A rite is a new City subsystem**, not a project entry: project ids are fixed (`city-core.ts:2787`), goals come from the definition (`:2581`), and there is no town-wide query (`:2753`). Budget a `city_rites` table with `start-rite`, `rite-roll` and `list-rites` that reuses the Downtime-spend and roll-log helpers from `applyProjectRoll`.
- **Killing damage type** becomes a persisted `killingDamageType`, written in `TakeDamage`'s death branch (`MCDMCreature.lua:~6887`). `_tmp_lastdamagetype` doesn't sync and gets cleared. A death through `SetStaminaDirect` counts as not fire.
- **The stored record is not pristine.** Survivors' wounds are pushed home (`HeroWounds`, `EncounterOfTheWeek.lua:2302`), so a raise must set the hero's Stamina explicitly (see the open call on return Stamina). Use the promote-then-push pattern (`EotwRoster.lua:1059-1090`).
- **Rising is settled by one server function**, `settleRises(owner, now)`, called on the owner's `list-heroes`, on `delete-hero`, on rite completion and on `record-outcome`, with roster and graveyard revs bumped for the *owner*. `list-graveyard` computes the countdown without writing. The client schedules a Refresh at `risesAt`.
- **The server decides who is undying.** The client reports only `killedByFire` and `doomed`.
- **Doomed Hakaan are beyond return**, by the rules text ("can't be returned to life by any means", `ClaudeRefHeroes.lua:3946`). No countdown and no rite. The grave reads "Beyond return".
- **Undying deaths carry `undying = true`** in the outcome, so analytics, difficulty and the Hall can count them apart.
- **Feedback and discoverability.** Each fallen hero gets a state line on the outcome screen and on the grave: will rise / can be raised at the Temple / restore the Temple to raise them (only when the project is visible) / beyond return / fire ended their undeath. Town entry plays a "returned from the grave" banner naming contributors, and the roster card gets a "Returned" badge until seen.
- **States:** an empty Temple ("None of your heroes lie in the Graveyard", "No rites under way"); a rite whose goal is met but has no free slot closes to further rolls ("Complete: waiting for a free slot").
- **Rites list:** yours first, then closest to done. Each card shows portrait, hero name, owner and percent. "Show all" appears after 5. Contributors are credited on the risen hero's sheet.
- **Cost readability:** "Goal 300 (level 5, about 11 rolls)", "Second rite: goal doubled", and a confirmation before starting.
- **Accessibility:** a "Yours" text tag (not just a background colour), disabled reasons as visible text (not hover-only), state labels plus icons, and countdowns that also give an absolute time.
- **Vocabulary:** players *raise* (a rite), heroes *rise*, and a grave reads "Rose on <date>". Category G drops "inert".
- **Series:** the undying decision is made in the part where the hero died. A rise is not a respite and doesn't close a part.
- **Stranded points:** if a grave can no longer be raised (the hero is deleted or scrubbed), the rite's points go to Restore the Temple. Deleting a fallen hero cancels their rite.

### Needs the user's call
All five were decided 2026-11-12 (ledger R1-R6).

1. **David's Awaken button** vs F1/F2/C2/B4: replace it, extend it, or keep it.
2. ***Back From the Grave* (B3):** the rules award it for dying to your greatest foe, not for being raised (`ClaudeRefHeroes.lua:32400`). A raised hero who held it would become undying, which makes B6's doubling cost pointless.
3. **Return Stamina for undying heroes:** the rules say they return with Stamina equal to their recovery value, but the stored record would give them back their pre-fight state (a free respite).
4. **The death-trigger Lua Script (E0):** the death trigger may never get to run its script. A non-local trigger is relayed to another client while Hero Death despawns the token, and a cast on an invalid token returns silently (`TriggeredAbility.lua:2348`). Since the stamp does nothing outside EotW (E1), a check in `OutcomesFor` does the same job reliably.
5. **Rite cost floor and alts:** nearly every death is at level 1 or 2 (16 XP per level, about 1 Victory a week), so 30 x level is about 30-60 points, which a town pays in a day. Alt accounts can also funnel Downtime.

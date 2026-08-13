# Internal-Marking Content Sweep -- Report (v3, full coverage)

Session date: 2026-08-12. Executor: fresh Claude session per
[sweep-spec.md](sweep-spec.md). References: `Draw_Steel_Heroes_v1.01b.pdf`,
`Summoner v1.0.pdf`, `The Beastheart v1.0.pdf` (all fully extracted and
searchable), plus `monster-reference.md`. **No YAML written yet.** v1 proposed
buckets; James ruled the category questions in-session (v2); v3 folds
Beastheart + Summoner in against their own books, so the DEFERRED bucket is
gone and every live feature is classified. Remaining gates before write-back:
the 10 unsure rows and 11 manual-verify rows. Meeting one-pager:
[sweep-meeting-summary.md](sweep-meeting-summary.md).

Full per-entry record: [sweep-inventory.csv](sweep-inventory.csv) (3,937 rows).

## James's rulings (2026-08-12, in-session)

1. **Ability grants**: a feature granting a clearly-book ability (Signature or
   Heroic categorization -- heroic resource cost/choice) is INTERNAL; the
   ability card is the display. This includes grants whose feature description
   is just the ability's flavor line (the "Righteous Judgment" class -- 158
   such features were hiding in v1's confident-book). Feature/perk-shaped
   grants (respite rituals like Revitalizing Ritual, perks like Summon
   Familiar, item transform maneuvers) stay VISIBLE. A sig/heroic grant that
   also carries extra rules modifiers is feature-shaped -> visible (e.g.
   Troubadour Drama, drake traits).
2. **Empty-desc hero features surfaced by the trigger drawer / routines
   section** (`triggerdisplay`/`routine` modifiers): INTERNAL -- they match
   book triggered actions and already display in the drawer. Trigger-only
   features with no display modifier show NOWHERE else and stay visible
   (mostly Domain Piety / Growing Ferocity resource-gain triggers). Monster
   trait features stay VISIBLE regardless (they are the statblock trait
   source).
3. **Bookkeeping grants are internal**: Recoveries carriers, characteristic
   increases (Statistics box shows the result), features that only grant a
   skill or language (Skills & Languages section shows it).
4. **coreMechanic = 3**: Tactician Mark, Censor Judgment, **Talent Clarity
   (Strain)** -- the strain rules live in Clarity's description and the tac
   panel currently drops Clarity via resource curation, so strain prose is
   invisible on the play surface today. All three features are pinned
   confident-book in the sweep.
5. **Complication features are always VISIBLE**: the sheet never renders the
   complication's `benefit:`/`drawback:` fields (only the compendium/builder
   Render does), so the feature rows are the sheet's only representation.
   Context: 173 of 214 complication features are benefit/drawback-named and
   165 of those carry their text in the description -- they were always going
   to show; only 7 empty-desc carriers were ever at risk and are now visible.

These mirror the tac panel's existing runtime curation
(FeatureCache.lua: ability grants -> action bar/drawer/routines,
characteristic-only -> Statistics box, resource grants -> resource boxes,
skill/language -> Skills section), so the data flag now matches the runtime
heuristics and extends them to the sheet's Features tab.

## Bucket counts (final pending the two small lists)

| Bucket | Count | v1 | Meaning |
|---|---|---|---|
| confident-book | 2,582 | 2,676 | stays visible; nothing written |
| confident-internal | 944 | 148 | gets the `Hidden` tag (2026-08-13 pivot: tags replace the internal boolean) |
| unsure | 10 | 19 | James rules individually (below) |
| skipped-hidden | 401 | 401 | hidden top-level objects |
| **total** | **3,937** | | |

The v1 ability-carrier bucket (292) is dissolved per ruling 1, and the v1/v2
deferred bucket (401) is classified against the Summoner/Beastheart books.

## Internal breakdown (944)

| Category | n |
|---|---|
| Signature/Heroic ability grants (ability card is the display) | 474 |
| Summoner/Beastheart system wiring (modsummoner/modcompanion, Summon Cost, Summoner Buffs) | 127 |
| Characteristic increases + concretions | 93 |
| Monster statblock stat carriers (attribute / immunity / free-strike) | 71 |
| Skill/language grants | 43 |
| Empty-desc hero features shown in trigger drawer / routines | 42 |
| Standard-action + global rule-engine carriers (globalrulemods) | 37 |
| Recoveries + base-resource carriers | 12 |
| Item mechanical carriers (empty-desc gear mechanics) | 11 |
| Hidden/basic-attack support ability carriers | 10 |
| Placeholder names, Mark: riders, Cackletongue, misc mechanical | 24 |

## Unsure (10) -- individual rulings needed

Display+plumbing split suspects (same book text on two structurally
different features in one object -- confirm which copy is the display):

1-2. classes / Conduit -- **Nature's Bounty** x2
3-4. monsters / Rival Talent E2 -- **Precognitive Shift** x2
5. subclasses / Prowler (Beastheart) -- **Supersniffer**
6. monsters / Bear (companion) -- **Strong Like Bear**
7. monsters / Spider (companion) -- **Web Slinger**

Suppress wrappers / oddballs:

8. classes / Summoner -- **Summoner Strike**: suppress-abilities wrapper
   carrying book text (force-route rule 3).
9. globalrulemods / **Dying**: suppress wrapper holding the book's dying
   rules text; all its siblings went internal.
10. subclasses / Spark (Beastheart) -- **Pyre**: empty desc,
    powertabletrigger only, no display path verified.

## Manual-verify list (11) -- low-confidence internal flips

Per James: small enough to verify by hand.

| # | Where | Feature | Why flagged |
|---|---|---|---|
| 1 | subclasses / Chronopathy | Again | internal via trigger-drawer rule; name unverifiable in book text |
| 2 | subclasses / Green | The Breath of Dawn Remembered | same |
| 3 | subclasses / Telekinesis | Repel | same |
| 4 | subclasses / College of Black Ash | Cinderstorm | sig/heroic grant with 320-char description -- confirm the ability card holds the full text |
| 5 | subclasses / College of Caustic Alchemy | Sticky Bomb | same, 345 chars |
| 6 | subclasses / College of Caustic Alchemy | One Vial Makes You Better | same, 458 chars |
| 7 | subclasses / College of Caustic Alchemy | One Vial Makes You Faster | same, 348 chars |
| 8 | subclasses / Duelist | Fight Choreography | same, 317 chars |
| 9 | monsters / Guest Star | Free Strikes | hidden/basic-attack carrier on a monster |
| 10 | monsters / Sprite Dandeknight | Magic Strike | same |
| 11 | monsters / War Dog Lesser Hypokrite | New Feature | same (grants "Disguise") |

## coreMechanic (3) + write-back work items

- **Tactician Mark** -- consolidate: the Mark feature, ability, and four
  internal rider fragments spread the rules text across surfaces; fold the
  kept-at-hand rules into the pinned feature at write-back.
- **Censor Judgment** -- description field is EMPTY in data; backfill from the
  book so the pinned card has text.
- **Talent Clarity (Strain)** -- flag Clarity as-is (card titled "Clarity",
  holding clarity + strain rules). James confirmed; splitting a separate
  Strain feature was considered and not chosen.

## Next steps

1. James: rule the 10 unsure, eyeball the 11 manual-verify rows (David
   sanity-check meeting first -- see sweep-meeting-summary.md).
2. Write-back (2026-08-13 pivot: tag form) -- `tags: {Hidden: true}` on the
   944 (minus any manual reversals) and `tags: {Core Feature: true}` on the
   3 core mechanics, in data/ (its own repo); YAML-parse-check every
   touched file; commit there per its conventions; no push without asking.
   Includes the Judgment desc backfill + Mark consolidation copy (copy needs
   sign-off per house rule).
3. Reload Codex, confirm clean console, spot-probe marked/unmarked features
   via execute_lua.
4. GPT Sol adversarial audit lane (James launches separately).
5. (DONE in v3) Beastheart + Summoner classified against their own PDFs.

# Internal Feature Flag -- Sweep Summary (for David)

One-page sanity check of the internal-marking content sweep, 2026-08-12.
Full detail: sweep-report.md; per-entry list: sweep-inventory.csv (3,937 rows).

## The principle

`internal: true` marks a feature that exists only to make the hero/monster
WORK in the app -- the player-facing text lives somewhere better. It makes
explicit in data what the tac panel already curates at runtime, extends the
same behavior to the sheet's Features tab, and feeds the companion monster
builder. Default is book/visible; internal is always the deliberate act.
Nothing has been written back yet.

Coverage: every CharacterFeature in the content repo, verified against the
Heroes v1.01b, Summoner v1.0, and Beastheart v1.0 PDFs plus
monster-reference.md (Book Two).

## Marked internal: 944

| Why | n |
|---|---|
| **Ability-grant wrappers** -- feature's only job is granting a Signature/Heroic ability; the ability card / action bar is the display. Showing the feature row double-lists every class ability. | 474 |
| **Summoner/Beastheart wiring** -- modsummoner/modcompanion carriers, Summon Cost / Summoner Buffs rows; consumed by the summoner UI, no book-facing text. | 127 |
| **Level-up bookkeeping** -- characteristic increases (Statistics box shows the result), Recoveries carriers (vitals box). | 105 |
| **Monster statblock stat carriers** -- Hover / Stability / Climb Speed / immunity / free-strike damage type setters; the statblock header line is the display. | 71 |
| **Skill & language grants** -- Skills & Languages section shows the outcome. | 43 |
| **Trigger-drawer duplicates** -- empty-desc hero features whose triggered ability already displays in the trigger drawer / routines section. | 42 |
| **Engine rules plumbing** -- globalrulemods (Opportunity Attack, Fall Damage, Surges, Malice...) and standard-action carriers (Heal, Grab, Free Strikes). | 37 |
| **Named plumbing** -- "Mark: X" rider fragments, Cackletongue Trigger, "Custom Modification"/"New Feature" placeholders, empty-desc item mechanics (item card shows the item text), hidden support abilities. | 45 |

## Kept visible: 2,582

- **Anything carrying real description text** -- default rule; ~1,500 matched
  the books verbatim, the rest are homebrew/paraphrase and visible by policy.
- **All monster traits** -- characterFeatures are the statblock's trait
  source; only stat/wiring carriers were marked, never traits.
- **Feature/perk-shaped ability grants** -- respite rituals (Revitalizing
  Ritual), perks (Summon Familiar), item actions: the feature is the book
  object, the embedded ability is incidental.
- **Ability grants that also carry rules modifiers** (Troubadour Drama, drake
  traits) -- feature-shaped, so the row stays.
- **All complication features** including "X - Benefit"/"X - Drawback" rows --
  the sheet never renders the complication's benefit/drawback fields, so
  these rows are the only sheet-side display.
- **Trigger-only features with no drawer display** (Domain Piety, Growing
  Ferocity) -- they show nowhere else.
- **Choice concretions with self-describing names** (Ward of Excellent
  Protection: Fire, Master of Reels: Agility, craft-skill picks).
- **coreMechanic pins (3)**: Tactician Mark, Censor Judgment, Talent Clarity
  (Strain) -- stateless kept-at-hand rules prose, pinned on sheet + panel.
  Write-back fixes: backfill Judgment's empty description, consolidate
  Mark's scattered text, surface Strain (currently invisible in play).

## Open before write-back

- 10 unsure rows (mostly same-text-on-two-features display/plumbing splits:
  Nature's Bounty, Precognitive Shift, Supersniffer, Strong Like Bear,
  Web Slinger; plus Summoner Strike suppress wrapper, Spark "Pyre", and the
  Dying rules feature).
- 11 manual-verify rows (3 unverifiable trigger names, 5 long-description
  ability grants, 3 monster hidden-ability carriers).

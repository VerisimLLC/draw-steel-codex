# Internal-Marking Content Sweep -- Session Spec

Self-contained spec for the sweep session. Parent brief:
docs/feature-metadata-incremental/brief.md (LOCKED 2026-08-12). Executor:
a fresh Claude session (decided 2026-08-12); a GPT Sol lane audits the
result afterwards (separate task, not this spec).

## Objective

Classify every existing feature in the content data repo as a BOOK feature
or an INTERNAL (plumbing) feature, write `internal: true` onto confirmed
internal features only, and set `coreMechanic: true` on exactly one
qualifying feature per qualifying class. Produce a review report for James
BEFORE any write-back.

This unblocks the draw-steel-companion monster builder (it consumes the
internal flag) and the codex display work (chunks 2+).

## The distinction

- **Book feature**: appears as a feature in the published books; would sit
  on someone's paper character sheet. Shows on sheet/panel.
- **Internal feature**: exists only to make the hero/monster WORK in the
  app -- trigger carriers (e.g. Gnoll Cackletongue's custom trigger
  holder), "Mark: *" style rider fragments, suppress-other-abilities
  wrappers, mechanical carriers with no book-facing text. Hidden on
  sheet/panel once chunk 2 ships.

A single book concept is often split across one display feature plus one
or more plumbing features; the plumbing gets marked internal, the one
carrying the book description does not.

## Field semantics (shipped in chunk 1, commit 45407a53)

- `internal: true` on the feature YAML object. Absent = book feature.
  NEVER write `internal: false`.
- `coreMechanic: true` -- same opt-in-only rule.
- Both live on `__typeName: CharacterFeature` objects (and are legal on
  subtypes, but this sweep only sets them on CharacterFeature).

## Scope

All feature-bearing content in the data repo (D:\draw-steel-codex\data,
its own git repo -- see project_data_repo_sync memory for workflow):

- objectTables: classes, subclasses, races (ancestries), kits, feats
  (perks), complications, titles, careers, cultureaspects, backgrounds,
  tbl-gear (item features), featureprefabs, globalrulemods.
- monsters/ (every monster's characterFeatures list).

Skills/languages tables carry no features to classify. This sweep is
BROADER than the later tag sweep (which is hero-only): monsters are IN
scope here.

## Classification policy (ratified; do not re-derive)

1. Default = book feature. Marking internal is the deliberate act.
2. Compare against the book references:
   - Monsters: D:\draw-steel-codex\monster-reference.md (complete Book
     Two stat blocks).
   - Heroes: reference to be supplied by James at session start -- ASK
     FOR IT before classifying hero content. Partial fallback:
     memory draw-steel-rules.md.
3. **Force-route rule (binding)**: any feature whose description is
   non-trivial text appearing verbatim/near-verbatim in a book goes to
   the UNSURE bucket regardless of how plumbing-like its structure is.
   Trigger carriers often HOLD the book text a player needs; those must
   never be auto-marked internal.
4. Name-fragment heuristics ("Mark: X", "X - Trigger", empty-description
   mechanical carriers, suppress wrappers) support confident-internal
   ONLY when rule 3 does not fire.
5. Choice rows (CharacterFeatureChoice etc.) are never marked; only
   concrete CharacterFeatures.
6. When a book feature was split into display + plumbing parts, verify
   the display part exists and is NOT being marked before marking the
   plumbing part internal.

## Core mechanic flags (same sweep, one pass)

Policy: ONE per qualifying class, the BASE mechanic only. Qualifying =
signature rules prose a player keeps at hand with NO state to manage.
Stateful mechanics (Fury Rage table, Troubadour routines, Null field,
Elementalist persistent magic, Beastheart ferocity, Summoner companions)
keep their bespoke widgets and are NOT flagged. Confirmed candidates:
Tactician's Mark, Censor's Judgment. Do a per-class read of the remaining
classes; expect 3-6 total. Subclass features and doctrine riders (e.g.
"Mark: See Your Enemies Driven Before You") are NEVER flagged -- they
render as normal features. Propose the final list to James in the report;
do not write coreMechanic until he confirms the list.

## Process

1. Ask James for the Heroes book reference if not already provided.
2. Sweep and classify into three buckets: confident-internal /
   confident-book / unsure. Record per-entry: file, feature name, guid,
   bucket, one-line reason.
3. Write the report to
   docs/feature-metadata-incremental/sweep-report.md: bucket counts,
   the FULL unsure list, a random sample (~30) of confident-internal
   with reasons, the proposed coreMechanic list.
4. STOP. James reviews the unsure list + samples and rules.
5. Write-back only after his sign-off: edit the YAML in data/, commit in
   the data repo per its conventions (do not push without asking).
6. Update the parent brief + project memory
   (project_feature_metadata_incremental.md) with counts and commit ids.

## Verification after write-back

- YAML parse check over every touched file.
- Reload the Codex over the MCP bridge (or HTTP fallback: POST
  localhost:19876/reload) and confirm a clean console.
- Spot-probe via execute_lua: a marked feature reads internal == true on
  the live table; an unmarked one reads false.

## Out of scope for this session

- Mode tags (separate hero-only sweep, later chunk).
- Any display work (chunks 2+).
- The Sol audit lane (James launches separately after write-back).

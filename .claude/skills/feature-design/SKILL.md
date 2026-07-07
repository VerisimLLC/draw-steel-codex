---
name: feature-design
description: >-
  The house design loop for draw-steel-codex / DMHub features: frame the
  problem, gather evidence (current-state audit, community asks, competitor
  precedent, engine capability check), map every decision the feature needs,
  work through options with the person driving the design ONE CATEGORY AT A
  TIME under the Celia Hodent lens, and assemble a DECIDED design brief. Use
  this EVERY time you start designing or reworking a surface -- "lets design
  X", "start thinking about X", "what should X look like", "how should we
  approach X", a new panel/system/feature, a standalone Hodent-pillar or
  current-state audit of an existing surface, or a design-check on one open
  question. Do NOT use for: executing an already-signed-off design, diagnosing
  a malfunction (debug-discipline), pure understand/explain questions, or
  single-value tweaks.
---

# Feature Design Loop

Design is a dialogue, not a deliverable: the person driving the design decides;
you structure the decision. The failure modes this loop prevents are (1)
designing against imagined engine capabilities, (2) a wall of twelve questions
at once, (3) decisions made in chat and then lost, and (4) whole decision
categories (idle states, sync model, accessibility) never surfacing until
implementation trips over them. The back-and-forth is the process -- do not try
to shortcut it; try to make every round count.

## Scale to fit

- **Full loop** (all phases): a new feature, panel, system, or rework.
- **Compressed** (phases 3-5 only, one message): a small, well-bounded design
  decision or a design-check on one open question -- map the decisions it
  actually contains, propose options with a recommendation per decision, wait
  for sign-off.

## Phase 1: Frame

One short section, agreed before anything else:
- The problem in one sentence, and for WHOM. This app commonly serves two
  persona poles: the **power user / director** (wants control, density, speed)
  and the **set-and-forget user** (wants it to just work). Say which decisions
  serve which pole.
- Why now, and what "done" looks like.
- Constraints inherited from standing decisions -- check for prior "do not
  re-litigate" decisions BEFORE proposing something already rejected.

## Phase 2: Evidence before opinions

Cheap to gather, expensive to skip. Delegate to parallel agents where the
work is reading, keep synthesis yourself:

1. **Current-state audit** -- what the live app actually does today (read the
   real panel code, screenshot the running app over the MCP bridge). Do not
   trust descriptions, including community descriptions, over the code.
2. **Engine capability check** -- verify what the engine actually supports
   for each mechanism you might design around. Anchor every claim to
   file:line or a live bridge probe. Dormant systems are common in this
   engine (things registered but never called) -- finding one converts
   "build from scratch" into "surface existing system".
3. **User evidence** -- community requests (e.g. Discord feature-request
   threads and vote counts) and real field pain. Users' words beat inferred
   needs.
4. **Precedent scan** (when the feature has competitors) -- what Foundry /
   Roll20 / dedicated tools do; what is loved, what is missing everywhere
   (a genuine market gap is worth calling out explicitly).

Write findings into the brief's evidence appendix as you go.

## Phase 3: The decision map

Enumerate EVERY decision the feature requires before debating any of them.
This checklist is the "don't miss anything" net -- walk it item by item and
write down which apply:

- **Data model**: where does state live -- game-scoped shared document,
  per-user setting (`storage="preference"`), game setting (`storage="game"`),
  asset field, token property? Who writes it, who reads it, what syncs?
- **Audience**: DM-only, player-facing, or split? What does each role see?
- **Surface**: dock panel (fixed 364x470, tabbed, never widens),
  LaunchablePanel (floating, non-blocking), character sheet tab, Compendium
  editor, Settings, context menu, chat? Compact vs expanded allocation?
- **Controls**: what does the user actually manipulate; drag paths need a
  non-drag alternative; hover-only affordances need an always-visible or
  mode-gated form.
- **States**: idle, empty/first-run, loading, error, mid-session join
  (late joiner!), multi-client simultaneous edits, hot-reload survival.
- **Copy**: every user-facing string is a decision to sign off explicitly.
  Never invent strings silently.
- **Accessibility**: color never the only signifier, no drag-only or
  hover-only paths, visual parity for any audio-only signal (HoH), and
  loudness/suddenness safety when the feature involves audio.
- **Performance**: rebuild patterns (signature-gated, build-once grids),
  vscroll costs, monitor fan-out.
- **Regression surface**: what does today's UI do that this replaces?
  Relocating a capability is acceptable, but silent ABSENCE of one is a
  regression. List every capability of the old surface and where it lands in
  the new one.
- **Phasing**: what ships now vs later; what is explicitly out of scope or
  rejected (record WHY -- rejected-with-reasons prevents re-litigation).

## Phase 4: Options, one category at a time

Work ONE category per round, concise. A wall of a dozen questions at once is
the fast path to a shallow answer. Per decision category:

- Present 2-3 GENUINELY distinct options (not one real option plus straw
  men). Include the option's failure mode, not just its pitch.
- Assess against the Hodent lens (below) -- a small scorecard table when the
  tradeoff is real, a sentence when it is one-sided.
- Give a recommendation and say why. The person driving the design picks;
  their pick may differ from the recommendation -- record it and move on
  without relitigating.
- **Record every decision in a running decision ledger** (date + decision +
  one-line rationale) inside the brief as it happens. Chat is where decisions
  are made; the brief is where they survive.

For UI, ground options visually: a theme-grounded mockup using the REAL
DefaultStyles tokens, shown in dock context, beats prose. (A clickable mockup
where every string is a data-attribute key that exports to a copy manifest
makes the copy decisions concrete and reviewable.)

## Phase 5: The brief

Assemble a **DECIDED brief, not a discovery doc**. Structure that has worked:
framing/goals/personas/pillars; the decided design (everything is a settled
decision unless listed under Open questions); phasing; verified engine
reality with anchors; explicit OUT-of-scope/rejected list with reasons;
open questions; evidence appendix. Plus a copy manifest for signed strings.

The brief is the SINGLE SOURCE OF TRUTH: supersede and rewrite rather than
accrete; archive the old version with a DO-NOT-ACTION banner. Companion
artifacts (one-pager, mockup) must be marked stale or re-synced whenever the
brief moves.

## Phase 6: Critique round, then lock

Before locking the brief, spawn 2-3 independent critique agents with distinct
lenses -- Hodent/UX, a domain expert for the feature (e.g. "VTT director
running a real session"), and accessibility. Ask each to attack the brief:
what breaks, what is missing, what a real user trips over. Fold real findings
back (as proposals where they change decisions). Then get sign-off -> the
brief is locked and implementation begins.

## The Hodent lens (assessment reference)

Celia Hodent's Gamer's Brain framework: weigh every option against usability
AND engage-ability -- a feature that is usable but joyless loses the
set-and-forget user; delightful but confusing loses everyone.

**Usability pillars:**
- Signs & feedback -- every action gets a visible/audible response; system
  state is always perceivable (e.g. now playing, edit mode active, whose
  turn it is, saving/synced).
- Clarity -- perceivable at a glance; no decoding required at real render
  size (glyph legibility at 14-18px is a recurring failure here).
- Form follows function -- things that do different things look different
  (e.g. broadcast-to-table vs local preview); things that are the same look
  the same across surfaces.
- Consistency -- with the rest of the app's vocabulary, glyphs, and
  interaction grammar; one name per concept everywhere.
- Minimum workload -- fewest clicks/decisions for the common case; do not
  make the user manage state the app can manage.
- Error prevention & recovery -- confirm destructive acts, make misclicks
  cheap (edit modes for risky controls), undo where possible.
- Flexibility/accessibility -- multiple paths (drag AND menu), personal
  levels, HoH-visible state, color-blind-safe signifiers.

**Engage-ability pillars:**
- Motivation -- does it serve the user's actual goal in the moment (run the
  session, build a character, prep an encounter, set the mood) rather than
  administer the tool?
- Emotion -- does it feel good: responsive, polished, a little delightful;
  no jank (fades, transitions, layout shift).
- Flow -- does it keep the DM in the game? Anything that forces a mid-session
  context switch (blocking modals, buried controls) breaks flow; prep
  belongs in prep surfaces, performance in perform surfaces.

When scoring options, name the pillar a tradeoff touches -- "option B wins
minimum-workload but loses form-follows-function" is the shape of a useful
assessment.

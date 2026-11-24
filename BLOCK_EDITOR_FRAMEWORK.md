# Block editors across the codex: framework design brief

Status: **DRAFT.** D1-D10 and Q1 decided (see the ledger). States decided too. Still open: copy, accessibility, performance and regression surface (section 6). This is the single source of truth for taking the block
design (the ability editor and class builder prototypes in `ui-mockup/`) to every content
editor, and for how a block is registered. Decisions are recorded in the ledger at the end as
they are made.

Visual proposal (design canvas):
https://claude.ai/artifact/EVBBnZeXhqhkUtQ63guRYr. It has 10 artboards:
- which editors get blocks
- the registration anatomy
- mockups of the Subclass, Title, Perk, Complication, Ancestry, Kit, Ongoing effect and
  Treasure editors

> **Revised 2026-11-24** after the coding review in [`BLOCK_EDITOR_CODING_PLAN.md`](BLOCK_EDITOR_CODING_PLAN.md).
> D1 (where a modifier's block lives), Q2 (claims replace first match), Q1 (author-chosen combining),
> the choice registry, the feature layer and the roll-option storage changed; see the last rows of the
> decision ledger. Where a section below disagrees with the ledger, the ledger wins.

## 1. Frame

- **Problem:** content is authored through hand-built forms, one per behaviour and modifier,
  so authors have to know the engine. The block prototypes fix that, but only for abilities
  and classes, and only as one-off code.
- **Who it's for:**
  - The **set-and-forget author**, a designer making a title or perk, wants to read and write
    plain sentences.
  - The **power author**, a developer porting a class, still needs every engine field. "More
    settings" and the old form keep that path.
- **Done means:**
  - Every feature-bearing editor uses the same blocks, from one registry.
  - A new behaviour or modifier gets a block by declaring it on its own registration. No
    editor changes.
  - The old form stays reachable as the fallback.
- **Standing decisions carried in from earlier work:**
  - Logic is the early-exit wrapper.
  - Roll options say "Offered when" (`displayCondition`) and "Automatically selected"
    (`activationCondition`, `1` when always).
  - Test pickers lead with Combine and are then ordered by use.
  - Hover text says what a block does, with no counts and no notes.
  - One-off blocks go in a Unique group.
  - The old Modify Power Roll editor stays as a backup.
  - Prototypes only: no engine edits until a design is signed off.

## 2. Evidence (anchors in the codex)

### Where blocks plug in
Almost every content editor ends in four shared pieces:

| Piece | Code | Used by |
|---|---|---|
| A. Feature list | `ClassLevel:CreateEditor`, `Draw Steel UI/DSClassEditor.lua:906` | classes, subclasses, and every one-list record: titles (`Titles.lua:238`), perks (`Feat.lua:279`), complications, creature templates, ancestries (`RaceEditor.lua:352`), careers, kits, culture aspects, global rules, feature prefabs |
| B. One feature | `CharacterFeature:EditorPanel`, `DMHub Game Rules/CharacterFeature.lua:432` | ongoing effects, condition riders, conditions, environmental keywords, monster traits; item features via `ListEditor` (`:1332`) |
| C. Modifier forms | `CharacterModifier.TypeInfo[id].createEditor`, dispatched at `CharacterFeature.lua:562-594` | everything in A and B; 62 types |
| D. Ability behaviours | `ActivatedAbilityBehavior:EditorItems`, 96 overrides | abilities everywhere: kits, items, monsters, malice, standard abilities |

How much each editor would gain:

| Benefit | Editors |
|---|---|
| High | subclasses (45 records, 791 modifiers), ongoing effects (1,057 / 1,502), condition riders (103 / 118), complications (100 / 208), creature templates (36 / 277), titles (63 / 168), ancestries (12 / 138), perks (55 / 42), the importer ability tables (207 abilities) |
| Medium | careers (mostly choices), global rules, kits (a stat form plus a list), culture aspects, conditions, treasures (a form plus features and an ability), monsters (a stat block plus features and abilities), monster traits |
| Stay as forms | cultures, deities and domains, downtime activities, reference tables (skills, languages, resources...). Montage tests and negotiators are already retired. |

### What registration provides today
- **Behaviours.** `ActivatedAbility.RegisterType{...}` stores its args table as given
  (`ActivatedAbility.lua:672-698`), so **extra keys survive**. 99 types are registered. Each
  behaviour's editor is imperative `EditorItems` on its class, with no field schema. `canHaveDC`
  is declared but never read.
- **Modifiers.** `CharacterModifier.RegisterType(id, text)` stores only `{id, text}`
  (`CharacterModifier.lua:108`). Behaviour lives in the untyped table `TypeInfo[id]`
  (`:433`), which takes about 60 hook keys and is open to more.
- **Metadata is split across four places and three keys:**
  - the registration (by id);
  - `BEHAVIOR_METADATA` and `MODIFIER_METADATA`, local tables in the new ability editor's
    pickers (by id; `AbilityEditorBehaviorPicker.lua:45`, `AbilityEditorModifierPicker.lua:71`);
  - `GoblinScriptProse.behaviourProse` (by **typeName**: 41 templates,
    `DMHub Utils/GoblinScriptProse.lua:2174`);
  - `TypeInfo.autoDescribe` (8 modifier types).
- **Formula slot docs already have a shape:** `gui.GoblinScriptInput{documentation={help,
  output, subject, symbols, examples}}`, with 147 call sites.
- **Field schema precedent:** `PuzzleField` (`DocumentSystem/PuzzleFramework.lua:12-22`) with
  `FieldControl` (`RichPuzzle.lua:859`). Its types are text, multiline, number, toggle,
  choice, image and custom, with `visible()` predicates. MapScript `params` is a second
  example.
- **No compile or read-back layer exists:** today's editors write straight into the record.
- **Cards never use generated prose:** Draw Steel cards show only authored text.

### The prototypes
- **Ability editor:** a block's parts are spread over four `switch` statements (render,
  compile, prose, import) plus a one-off importer.
- **Class builder:** keeps each block in one object (`SENT`: label, desc, group, make,
  render, prose, compile), but has no read-back.
- Both prove the user-facing design. Neither is the registry.

## 3. Decision map

| # | Decision | Options | Recommendation |
|---|---|---|---|
| D1 | **Where a block is declared** | (a) a `block = {...}` key on the type's existing registration; (b) a separate block table keyed by id, like today's picker metadata; (c) data files (JSON/YAML) read by Lua and the prototypes | **(a)**. One place per type, found where the behaviour is written, and it survives re-registration. (b) repeats today's split. (c) cannot hold prose and read-back functions. |
| D2 | **How slots bind to the record** | (a) declarative: each slot names a `field`, so saving and reading back come free; (b) each block writes `compile`/`parse` functions; (c) (a) by default, with `read`/`write` overrides | **(c)**. Most types map field-for-field. The rest (power modifier's activation, nested choices) need code, and only there. |
| D3 | **Prose** | (a) the sentence template is the prose, with slot words filled in; (b) a `prose(record, words)` function per block; (c) (a) by default, (b) when the template can't say it | **(c)**. Formula slots use the existing GoblinScript-to-English renderer. Verb agreement comes from `{take|takes}` in the template, so one sentence works for "you" and "the target". The 41 `behaviourProse` templates move onto their blocks. |
| D4 | **Fields no slot claims** | (a) drop them; (b) keep them untouched and show "Advanced editor (N)", which opens today's form; (c) refuse to show the block | **(b)**. Round-trip safety, plus the old editor as the backup you asked for. |
| D5 | **Types with no block yet** | (a) hide them; (b) a grey generic block named from the registration that opens its form | **(b)**. This is what the ability editor does now. Adding `block` later upgrades the type everywhere. |
| D6 | **Editors as hosts** | (a) each editor builds its own page around a shared stack widget; (b) `BlockEditor.RegisterHost{record, header, stacks}` declares fixed rows and stacks, and the framework builds the page | **(b)** for the feature-list editors (A, B). Bespoke editors (items, monsters) mount the shared stack widget inside their own form. |
| D7 | **Point of view** | per block; or per host ("you" for features, "the creature" for effects, "the target" in abilities) | **Per host.** The same block reads right in every editor. |
| D8 | **Block families** | modifier, choice (`CharacterChoice.RegisterChoice`), step (behaviours), logic wrappers, recipes | Hosts list the families they accept. The shelf, search and Unique group are built from the registry. |
| D9 | **The prototypes during the transition** | hand-kept copies; or a generator that exports the Lua registry to JSON for the HTML prototypes | **Generator**, so the prototypes test the real registrations. |
| D10 | **Phasing** | see section 5 | |

The remaining categories (states, copy, accessibility, performance, regression surface) are
listed in section 6 and will be worked one at a time after D1-D3.

## 4. Proposed registration API (follows the D1-D5 recommendations)

```lua
-- Modifiers: RegisterType gains an optional third argument; the same table is merged into TypeInfo.
CharacterModifier.RegisterType("attribute", "Modify Attribute", {
    block = {
        label    = "Change a stat",                     -- shelf tile and search
        group    = "stats",                             -- shelf group
        desc     = "Raise, lower or set one of the hero's numbers.",  -- hover text
        sentence = "Your {attribute} {operation} {value}",
        slots = {
            attribute = Block.Choice{ field = "attribute", from = "attributes" },
            operation = Block.Choice{ field = "operation", options = {
                { "add", "increases by" }, { "set", "becomes" },
                { "max", "is at least" },  { "min", "is at most" } } },
            value     = Block.Formula{ field = "value", output = "number",
                docs = { help = "How much to change it by.",
                         examples = { { "Level", "Your level." } } } },
        },
        -- optional: prose(record, words), read(record) -> slot values, write(values, record),
        --           check(record, report), children = { field = "...", families = {...} }
    },
})

-- Behaviours: the same `block` key on the existing registration table.
ActivatedAbility.RegisterType{
    id = "fall", text = "Fall",
    createBehavior = function() return ActivatedAbilityFallBehavior.new{} end,
    block = {
        label = "Fall", group = "move",
        desc  = "Makes the targets fall if nothing is holding them up.",
        sentence = "{applyto} {fall|falls}{stopFlying}",
        slots = {
            applyto    = Block.Who{ field = "applyto" },
            stopFlying = Block.Toggle{ field = "stopFlying", on = ", stopping flight first", off = "" },
        },
    },
}

-- Editors: declare a host; the framework builds header rows, stacks, shelf, status and preview.
BlockEditor.RegisterHost{
    id = "title", record = "Title",
    header = { "echelon", "prerequisite" },
    stacks = { { field = "modifierInfo", families = { "modifier", "choice" } } },
    pointOfView = "you",
}
```

**Slot types** reuse the `PuzzleField` vocabulary and add the block-specific ones:

| Slot type | What it is |
|---|---|
| Text | free text |
| Number | a plain number |
| Toggle | on or off |
| Choice | one of a list, either `options` or `from` a table |
| Many | several of a list |
| Formula | a number or formula, with docs (the GoblinScriptInput shape) |
| Test | a Logic test chip, with a context that sets which tests it offers |
| Ref | a compendium search: effect, ability, item or condition |
| Who | a creature role |
| Blocks | a list of child blocks, for wrappers and choice options |

**Read-back is free for declared fields.** Opening a saved record fills each slot from its
`field`. Anything unclaimed is shown as "Advanced editor (N)" and saved back unchanged (D4).

**Worked examples from the Block Copy sheet** (each kind of row as a declaration, using the real
field names): `ui-mockup/block-copy/REGISTRY_EXAMPLES.md`.

## 4a. Slot mapping, worked through (D2)

A slot is one underlined word or chip in a block. **Mapping** says where its value lives in
the saved record. There are three levels. Most types only need the first.

### Level 1: a slot names a field

```lua
value = Block.Formula{ field = "value" }
```

- **Reading:** opening a saved record puts `record.value` in the slot.
- **Saving:** writes the slot back to `record.value`.

That is all. The attribute modifier, and most behaviours (`applyto`, `stopFlying`,
`damageType`...), need nothing else. A `field` can be a path into a nested table, such as
`field = "momentaryEffect.name"`.

### Level 2: a slot converts its value

The record stores the value in a different shape from the one the slot shows. A slot can name
a built-in **form**, or give `get`/`set`:

```lua
-- Keywords are stored as a set ({ Weapon = true }); the slot shows a list ("Weapon").
keywords = Block.Many{ field = "keywords", from = "abilityKeywords", form = "set" },

-- A small custom conversion: the slot shows a whole number, the record stores text.
radius = Block.Number{ field = "radius",
    get = function(stored) return tonumber(stored) or 1 end,
    set = function(value) return tostring(value) end },
```

- **Built-in forms:**
  - `set`: a table of `true` values.
  - `list`: an array.
  - `csv`: comma-separated text.
  - `bool01`: `1`/`0`.
- **When to use get/set:** when one slot maps to one field, but needs converting.

### Level 3: the block reads and writes the record itself

Some blocks don't map slot-for-field: one slot sets several fields, or several fields make one
slot. For these the block gives `read(record)`, which returns the slot values, and
`write(values, record)`. The roll modifier's **Automatically selected** line is the real
example:

```lua
-- "Automatically selected" is one slot, but the engine stores it across three fields.
read = function(rec)
    local v = { offer = rec.displayCondition }
    if rec.resourceCostType and rec.resourceCostType ~= "none" then
        v.selected = "cost"; v.costN = rec.resourceCostAmount; v.costRes = rec.resourceCostType
    elseif rec.activationCondition == true or rec.activationCondition == "1" then
        v.selected = "always"
    elseif rec.activationCondition == false or rec.activationCondition == "" then
        v.selected = "never"
    elseif rec.activationCondition == rec.displayCondition then
        v.selected = "always"          -- the same test written twice: offered already decides it
    else
        v.selected = "when"; v.tick = rec.activationCondition
    end
    if type(rec.activationAfterRoll) == "string" then
        return nil                     -- after-the-roll options: the block can't show these
    end
    return v
end,
write = function(v, rec)
    rec.displayCondition    = v.offer or ""
    rec.activationCondition = (v.selected == "when" and v.tick)
                           or (v.selected == "never" and false) or "1"
    if v.selected == "cost" then rec.resourceCostType = v.costRes; rec.resourceCostAmount = v.costN end
end,
```

### Rules every level follows

1. **Unclaimed fields are kept.** Any field no slot (or `read`) claims is copied through
   unchanged on save and counted in "Advanced editor (N)", which opens today's form.
2. **`read` may refuse.** If `read` returns `nil` (as above, for after-the-roll options), the
   record opens as the grey generic block with today's form. Nothing is lost or guessed.
3. **Round trip is tested, not trusted.** Saving a block you didn't touch must give back the
   same record. A registry check runs every compendium record of each type through
   `read`→`write` and lists any that change, the same way the prototype polls did (45/45,
   60/60, 1,148/1,148).
   - This is how a type earns its block.
   - It also caught a real case: Berserker's *Primordial Strength* stores the same test in
     both `displayCondition` and `activationCondition`. That reads as "Offered when [the
     target is an object] / Automatically selected always". Saving it unchanged must keep
     both fields as they were, so the check compares field by field, not by meaning.

## 4b. Writing prose (D3)

Prose is the book wording, shown on the card and in the preview. There are three levels, and
again most types only need the first.

### Level 1: the sentence is the prose

The block's `sentence` is filled in with each slot's words:
- a Choice uses its option label;
- a Formula is turned into English by the existing GoblinScript renderer, so `Might*2` reads
  "twice your Might";
- a Ref uses the compendium name;
- a Test uses its book wording;
- a Who uses the host's point of view.

`{take|takes}` picks the verb that agrees with the subject: "you take", "the target takes".

```lua
sentence = "{applyto} {take|takes} {amount} {damageType} damage",
-- ability host:  "The target takes 2d6 + Might fire damage."
-- effect host:   "The creature takes 5 fire damage."
```

### Level 2: separate book wording

When the block's words are fine for editing but the book says it differently, give a `prose`
template next to the `sentence`:

```lua
sentence = "Your {attribute} {operation} {value}",                  -- in the editor
prose    = "Your {attribute} maximum {operation} {value}",          -- on the card, for Stamina
```

### Level 3: a prose function

For wording that depends on the values (a sign, a count, a list), the block gives
`prose(record, w)`. `w` is a small helper so the function never builds English by hand:

| Helper | Gives |
|---|---|
| `w.slot("amount")` | the slot's words, the same as the template would use |
| `w.subject()` / `w.verb("gain", "gains")` | "you" / "the creature"; the agreeing verb |
| `w.formula(text)` | a formula in English ("twice your Might") |
| `w.count(n, "square", "squares")` | "1 square", "3 squares" |
| `w.list({...}, "and")` | "acid, cold and fire" |
| `w.test(node)` | a test's book wording ("the target is winded") |

Return a string, or `nil` to fall back to the template.

Real example, the resistance modifier: one record can hold a list of entries, and each entry is
immunity, or weakness when its number is negative.

```lua
prose = function(rec, w)
    local immune, weak = {}, {}
    for _, e in ipairs(rec.resistances or {}) do
        local n = tonumber(e.dr)
        if n and n < 0 then weak[#weak+1] = { e.damageType, w.formula(-n) }
        else immune[#immune+1] = { e.damageType, w.formula(e.dr) } end
    end
    local parts = {}
    -- Entries with the same amount share one phrase: "acid, cold and fire immunity equal to twice your Might".
    for amount, types in pairs(w.groupBy(immune, 2, 1)) do
        parts[#parts+1] = w.list(types, "and") .. " immunity " .. amount
    end
    for amount, types in pairs(w.groupBy(weak, 2, 1)) do
        parts[#parts+1] = w.list(types, "and") .. " weakness " .. amount
    end
    return w.subject() .. " " .. w.verb("have", "has") .. " " .. w.list(parts, "and") .. "."
end,
```

A record with acid and fire entries at `Might*2` reads: "You have acid and fire immunity equal to
twice your Might."

Berserker's *Chaos Incarnate* is stored differently: 7 separate resistance modifiers, one damage
type each, all `Might*2`. Each one alone reads "You have acid immunity equal to twice your
Might." They are not merged (Q1, decided): for the book's single sentence, the author writes it in the
feature's text.

### Where today's prose goes

- **`GoblinScriptProse.behaviourProse`:** the 41 templates (keyed by typeName) move onto their
  behaviours' `block.prose`. `RenderBehaviour` keeps its fallback chain, so anything not yet
  moved still reads the same.
- **`autoDescribe`:** the 8 modifier types that have it become `block.prose`. The old hook
  calls the new one until it is removed.

## 5. Phasing (proposal)

1. **Registry and host framework, plus the modifier blocks the class builder already has.**
   Hosts: the A editors (titles, perks, complications, ancestries, careers, creature
   templates, global rules), then subclasses and classes.
2. **One-feature hosts (B):** ongoing effects, condition riders, conditions, monster traits.
3. **Ability behaviour blocks (D):** the 22 built blocks first, then the long tail. The
   `behaviourProse` templates move onto their blocks.
4. **Shared stack inside bespoke editors:** kits, treasures, monsters.

## 6. Still to decide (after D1-D3)

- ~~**Q1:** should a feature's prose merge neighbouring blocks that read alike?~~ **Decided:
  no** (see the ledger). Each block reads as its own sentence. An author who wants the book's
  combined sentence writes it in the feature's text, which replaces the generated wording.

- ~~**States**~~: decided (see the ledger and section 6a).
- **Copy:** in review. The manifest is the "Block Copy" sheet,
  https://claude.ai/artifact/UAaxnYmKrca6f8Rh3BezgR (source CSV and scripts in
  `ui-mockup/block-copy/`). It has 184 rows:
  - 99 ability behaviours;
  - 61 modifier types;
  - 5 choice and Logic blocks;
  - 10 ability-editor blocks that have no engine type of their own.

  Columns: label, hover text, block sentence, book prose, group, status, engine name, the new
  editor's own description, and notes. 28 engine types already have blocks (15 behaviours, 13
  modifiers); 125 still need wording (78 behaviours, 47 modifiers).
- ~~**Q2: one type, several blocks**~~ **Decided** (see the ledger). Some types already appear as more than one block:
  - `attribute` is Change a stat, Movement type, You ignore / can't... and Raise a
    characteristic;
  - `power` is Edge or bane on rolls, Rolls against you, Extra damage, Change the outcome and
    Change potency.

  So a type's `block` needs to allow a list of blocks, each with a `match(record)` that says
  which block reads a given saved record.
- **Accessibility:**
  - every drag needs a click path;
  - colour is never the only signal, since groups also have names;
  - keyboard order.
- **Performance:** a stack with 30+ blocks (Chaos Incarnate has 7 resistances), and
  rebuild-on-change.
- **Regression surface:** list every capability of today's forms and where it lands. "More
  settings" is the catch-all.

## 6b. Power roll modifiers: what the blocks cover (Q3, decided)

The `power` modifier ("Modify Power Rolls", `Draw Steel Core Rules/MCDModifyPowerRolls.lua`)
can do far more than the five roll blocks show. The compendium has 1,394 power modifiers.
**727 (52%) can be shown fully by today's five blocks.** The rest would open in the advanced
editor.

| What the modifier does | Records | A block today? |
|---|---:|---|
| edge, bane, double edge, double bane | 623 | yes: Edge or bane on rolls; Rolls against you |
| extra damage, with a damage type | 200 | yes: Extra damage |
| fires a trigger when chosen ("Edit Trigger") | 136 | **no** |
| halve, double or remove the damage (multiplier) | 87 | **no** |
| add text to a tier | 77 | **no** |
| a characteristic, for tests ("tests using Might") | 73 | **no** |
| change the damage type | 62 | **no** |
| change potency | 58 | yes: Change potency |
| fixed outcome (tier 3, not tier 1, tier up or down...) | 67 | yes: Change the outcome |
| change the target | 41 | **no** |
| remove or ignore edges and banes, edge to bane | 48 | **no** (the modtypes exist; the block doesn't offer them) |
| replace text in a tier | 37 | **no** |
| only when the roll has an edge or bane, or has surges (`rollRequirement`) | 32 | **no** |
| characteristic adjustments | 32 | **no** |
| gain surges (can be kept; surge damage type) | 29 | **no** |
| a trigger that runs before the ability | 28 | **no** |
| also applies to free strikes | 27 | **no** |
| +1 / +2 / +3 / -1... to the roll | 18 | **no** |
| append to or replace the roll | 26 | **no** |
| other rolls: all rolls, project, opposed, resistance, fishing | 97 | **no** (only ability rolls, tests and rolls against you) |
| arm an effect; roll twice; suppress effects; shields; after-the-roll | about 40 | **no** |

Decided: add these to the `power` type's block list (rows marked Proposed in the Block Copy sheet).
1. **Gain surges:** "You gain [2] surges [that can be kept]".
2. **Change the damage:** "The damage is [halved / doubled / removed]", and "[fire] damage
   becomes [cold]".
3. **Change a tier's text:** "Tier [3] also [adds: ...] / [replaces '...' with '...']".
4. **Also trigger:** "When chosen, also [a triggered ability]", using the Ability slot.
5. **Wider existing blocks:**
   - Edge or bane adds remove, ignore and conversion options, and +1/+2/+3 to the roll.
   - Its roll choice adds all rolls, opposed tests, resistance rolls and project rolls.
   - Tests can name a characteristic.
6. **Two more Offered when tests and a toggle:** "The roll has an edge / a bane / surges", which
   is `rollRequirement`; and "also on free strikes".

With these, **about 1,215 (87%)** are shown fully. These stay in the advanced editor:
- change target (41);
- adjustments (32);
- trigger-before (28);
- arm effect (20);
- the after-roll and other rare fields.

## 6a. States (decided)

| State | What the author sees | Copy |
|---|---|---|
| Empty stack | Only the add button; no instructions or hint text | "+ add a feature" (block stacks inside a feature: "+ add a block") |
| A record that can't be read back | A grey block holding the record, with a button to the old form; no reason given | "Make changes in the advanced editor" |
| Two people saved the same record | Last save wins, as today; the second saver is told and chooses | "Someone else saved this while you were editing." Buttons "Reload theirs" / "Keep mine" |
| A block whose type no longer exists | A grey block that keeps its saved data; flagged in Status | "Unknown block ([id])" |

The empty stack still counts in Status as "doesn't do anything yet", as the class builder does
today. "Advanced editor" is the name for today's form everywhere (it replaces "More settings
(N)" from D4, which now reads "Advanced editor (N)").

## Decision ledger

| Date | Decision | Why |
|---|---|---|
| 2026-11-23 | **D1: a block is declared with a `block = {...}` key on the type's existing registration** (`ActivatedAbility.RegisterType`, `CharacterModifier.RegisterType`/`TypeInfo`, `CharacterChoice.RegisterChoice`) | Use what already exists: one place per type, beside the code that runs it. Separate tables would repeat today's split metadata. |
| 2026-11-23 | **D2: slots name the field they save to.** A slot can convert with a `form` or `get`/`set`; a block writes `read`/`write` only when slots and fields don't line up. | Most types map field-for-field and get saving and read-back for free. Code is needed only for the hard cases (roll options). |
| 2026-11-23 | **D3: the sentence is the prose.** An optional `prose` template covers different book wording; a `prose(record, w)` function covers value-dependent wording. | One declaration gives both the block and the card. The `behaviourProse` templates and `autoDescribe` move onto their blocks. |
| 2026-11-23 | **D4: unclaimed fields are kept unchanged** and shown as "Advanced editor (N)", which opens today's form. `read` may refuse a record it can't show. | Round-trip safety. The old editor stays as the backup. |
| 2026-11-23 | **D5: a type with no block appears as a grey generic block** named from its registration, opening its current form. | Nothing disappears. Adding `block` later upgrades it everywhere. |
| 2026-11-23 | **D6: editors register a host** (`BlockEditor.RegisterHost{record, header, stacks}`). Bespoke editors (items, monsters) embed the shared stack in their own form. | One framework builds the feature-list editors; no per-editor block code. |
| 2026-11-23 | **D7: point of view is set per host** ("you" in features, "the creature" in effects, "the target" in abilities). | The same block reads correctly in every editor. |
| 2026-11-23 | **D8: block families** are modifier, choice, step, logic and recipe. Each host lists the families it accepts; the shelf, search and Unique group are built from the registry. | One shelf system, filtered per editor. |
| 2026-11-23 | **D9: a script exports the Lua registry to JSON for the HTML prototypes.** | The prototypes test the real registrations, not hand copies. |
| 2026-11-23 | **D10: phasing.** (1) Registry plus the one-list editors, then subclasses and classes; (2) one-feature editors; (3) ability steps; (4) the shared stack in kits, treasures and monsters. | Biggest reach first, through the shared pieces A and B. |
| 2026-11-23 | **Q1: similar statements are not merged.** Each block is its own sentence; an author writes a combined sentence in the feature text. | Keeps prose predictable, with no hidden rewriting. The author stays in control. |
| 2026-11-23 | **States** (section 6a): an empty stack shows only "+ add a feature"; a record blocks can't show says "Make changes in the advanced editor"; on a conflicting save, last save wins with "Reload theirs / Keep mine"; a removed type shows "Unknown block (id)" and keeps its data. | No directions or justifications in the UI. The author gets the action, not an explanation. Nothing is silently changed or lost. |
| 2026-11-23 | **Q2: one type, several blocks.** A registration may give `blocks = { ... }`, a list; each block has a `match(record)`, and the first that matches opens a saved record (specific blocks first, a catch-all last). A record no block matches opens in the advanced editor. | `attribute` is 4 blocks and `power` is 5 today. Shared lines (Offered when / Automatically selected) are one included group. See `ui-mockup/block-copy/REGISTRY_EXAMPLES.md` sections 4-5. |
| 2026-11-23 | **Q3: power roll blocks widened.** New blocks: Gain surges, Change the damage, Change a tier's text, Also trigger. Edge or bane on rolls gains remove, ignore and convert options, +1/+2/+3, more roll types and tests by characteristic. The shared lines gain "the roll has an edge / a bane / surges" and "also on free strikes". | Raises fully shown power modifiers from 727 to about 1,215 of 1,394. Change target, adjustments, trigger-before and arm effect stay in the advanced editor for now. |
| 2026-11-24 | **Performance:** the framework redraws only the block that changed, and is tested against the largest real features. | Agreed. |
| 2026-11-24 | **Defaults adopted to cut review load** (the reviewer can reopen any of them): change target stays in the advanced editor; accessibility rules for every editor (every drag has a click path, colour is never the only signal, keyboard order runs left to right through the slots); "what we might lose" is checked per editor when its phase starts. Wording for the remaining types is drafted by Claude, and the reviewer checks it rather than writing it. | The reviewer asked for fewer separate things to review. |
| 2026-11-24 | **D1 corrected: a modifier's block goes inside its `TypeInfo` table**, not as a third argument to `CharacterModifier.RegisterType`. Ability behaviours keep `block` on `ActivatedAbility.RegisterType` as decided. | Every modifier type calls `RegisterType(id, text)` and then assigns a whole new `TypeInfo.<id> = {...}` table (e.g. `power`: `MCDModifyPowerRolls.lua:179`, `:481`), which would wipe anything added at registration. `RegisterType` needs no change. (`BLOCK_EDITOR_CODING_PLAN.md` section 2.2.) |
| 2026-11-24 | **Q2 replaced: blocks claim fields.** Each block lists the record fields it claims. A saved record opens as the block that claims its fields; when several blocks of one type match (e.g. a `power` record with an edge, extra damage and surges), it opens as one combined block. Fields no block claims still go to "Advanced editor (N)". | "First match wins" would open a combined power record as just "Edge" and push the rest to the advanced editor. Agreed by the owner. |
| 2026-11-24 | **Q1 refined: combining is the author's choice, declared on the type.** Nothing merges on its own, but a type may declare `combine = { shared, key, conflict }` and its blocks `part = {...}`, so the author can press Combine (class builder, section 27 of the proposal). The editor knows no type by name. | The prototype's combined roll change was editor code in nine places; it becomes a registration hook. |
| 2026-11-24 | **The choice registry moves to the rules layer.** `CharacterChoice.RegisterChoice` moves from `Draw Steel UI/DSClassEditor.lua:3-7` to `DMHub Game Rules/Class.lua`, with a public accessor and a `create(ctx)` per choice. The seven built-in choices (including perks) are registered through it. | Today the registry is file-local to the class editor and the built-ins are hard-coded, so no other editor can read it. Agreed by the owner; it is the one change that touches today's class editor. |
| 2026-11-24 | **Hosts have a feature layer.** A class level holds features; modifiers live in `feature.modifiers`, and choices sit beside the feature. Hosts declare that layer explicitly. | The decided API assumed one level of stacks. |
| 2026-11-24 | **"Automatically selected" is stored as the engine stores it:** always = `true`, never = `false`, when = a formula. Read with `try_get`, since imported records may lack the field. | The earlier sketch saved "never" as always and "always" as `"1"` (`MCDModifyPowerRolls.lua:721`, `:1921`). |
| 2026-11-24 | **Saved modifiers with the exact same "Only if" condition reopen as one Logic block**; any difference in the condition text keeps them separate. | Agreed by the owner. |
| 2026-11-24 | **"Only if" is offered only on types that honour it.** Each modifier block declares `supportsFilter`; types that don't honour `filterCondition` either gain support or don't allow Logic around them, decided per type from `MODIFIER_FILTER_AUDIT.md`. | Some types skip the central filter (`Creature.lua:6593`, `CharacterModifier.lua:4311`). |
| 2026-11-24 | **The editor UI lives in a new `Block Editor` mod**, loaded after Draw Steel Core Rules. `Block.lua` (declarations, no `gui`) sits in `DMHub Utils`, so it loads before `CharacterModifier.lua`. The UI files may not name any modifier, behaviour or choice id; a CI grep checks it. | Keeps the "no type names in the editor" rule easy to police. The new mod must be created and ordered in the cloud. |
| 2026-11-24 | **Round trip by construction:** only slots the author changed are written; an unchanged block writes nothing. | A record opened and saved without edits stays identical, as well as passing the round-trip test. |

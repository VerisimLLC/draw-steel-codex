# Block editors across the codex: framework design brief

Status: **DRAFT.** D1-D10 and Q1 decided (see the ledger). Still open: the later rounds in section 6 (states, copy, accessibility, performance, regression surface). This is the single source of truth for taking the block
design (the ability editor and class builder prototypes in `ui-mockup/`) to every content
editor, and for how a block is registered. Decisions are recorded in the ledger at the end as
they are made.

Visual proposal (design canvas):
https://claude.ai/artifact/EVBBnZeXhqhkUtQ63guRYr. It has 10 artboards:
- which editors get blocks
- the registration anatomy
- mockups of the Subclass, Title, Perk, Complication, Ancestry, Kit, Ongoing effect and
  Treasure editors

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
| D4 | **Fields no slot claims** | (a) drop them; (b) keep them untouched and show "More settings (N)", which opens today's form; (c) refuse to show the block | **(b)**. Round-trip safety, plus the old editor as the backup you asked for. |
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
`field`. Anything unclaimed is shown as "More settings (N)" and saved back unchanged (D4).

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
   unchanged on save and counted in "More settings (N)", which opens today's form.
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

- **States:** an empty stack, a record that fails to read back, two authors editing at
  once.
- **Copy:** the label, description and sentence for each of the 161 types. A copy manifest
  will be generated from the registry.
- **Accessibility:**
  - every drag needs a click path;
  - colour is never the only signal, since groups also have names;
  - keyboard order.
- **Performance:** a stack with 30+ blocks (Chaos Incarnate has 7 resistances), and
  rebuild-on-change.
- **Regression surface:** list every capability of today's forms and where it lands. "More
  settings" is the catch-all.

## Decision ledger

| Date | Decision | Why |
|---|---|---|
| 2026-11-23 | **D1: a block is declared with a `block = {...}` key on the type's existing registration** (`ActivatedAbility.RegisterType`, `CharacterModifier.RegisterType`/`TypeInfo`, `CharacterChoice.RegisterChoice`) | Use what already exists: one place per type, beside the code that runs it. Separate tables would repeat today's split metadata. |
| 2026-11-23 | **D2: slots name the field they save to.** A slot can convert with a `form` or `get`/`set`; a block writes `read`/`write` only when slots and fields don't line up. | Most types map field-for-field and get saving and read-back for free. Code is needed only for the hard cases (roll options). |
| 2026-11-23 | **D3: the sentence is the prose.** An optional `prose` template covers different book wording; a `prose(record, w)` function covers value-dependent wording. | One declaration gives both the block and the card. The `behaviourProse` templates and `autoDescribe` move onto their blocks. |
| 2026-11-23 | **D4: unclaimed fields are kept unchanged** and shown as "More settings (N)", which opens today's form. `read` may refuse a record it can't show. | Round-trip safety. The old editor stays as the backup. |
| 2026-11-23 | **D5: a type with no block appears as a grey generic block** named from its registration, opening its current form. | Nothing disappears. Adding `block` later upgrades it everywhere. |
| 2026-11-23 | **D6: editors register a host** (`BlockEditor.RegisterHost{record, header, stacks}`). Bespoke editors (items, monsters) embed the shared stack in their own form. | One framework builds the feature-list editors; no per-editor block code. |
| 2026-11-23 | **D7: point of view is set per host** ("you" in features, "the creature" in effects, "the target" in abilities). | The same block reads correctly in every editor. |
| 2026-11-23 | **D8: block families** are modifier, choice, step, logic and recipe. Each host lists the families it accepts; the shelf, search and Unique group are built from the registry. | One shelf system, filtered per editor. |
| 2026-11-23 | **D9: a script exports the Lua registry to JSON for the HTML prototypes.** | The prototypes test the real registrations, not hand copies. |
| 2026-11-23 | **D10: phasing.** (1) Registry plus the one-list editors, then subclasses and classes; (2) one-feature editors; (3) ability steps; (4) the shared stack in kits, treasures and monsters. | Biggest reach first, through the shared pieces A and B. |
| 2026-11-23 | **Q1: similar statements are not merged.** Each block is its own sentence; an author writes a combined sentence in the feature text. | Keeps prose predictable, with no hidden rewriting. The author stays in control. |

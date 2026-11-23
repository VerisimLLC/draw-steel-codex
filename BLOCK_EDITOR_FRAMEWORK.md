# Block editors across the codex: framework design brief

Status: **DRAFT, decisions open.** This is the single source of truth for taking the block
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

## 5. Phasing (proposal)

1. **Registry and host framework, plus the modifier blocks the class builder already has.**
   Hosts: the A editors (titles, perks, complications, ancestries, careers, creature
   templates, global rules), then subclasses and classes.
2. **One-feature hosts (B):** ongoing effects, condition riders, conditions, monster traits.
3. **Ability behaviour blocks (D):** the 22 built blocks first, then the long tail. The
   `behaviourProse` templates move onto their blocks.
4. **Shared stack inside bespoke editors:** kits, treasures, monsters.

## 6. Still to decide (after D1-D3)

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
| (none yet) | | |

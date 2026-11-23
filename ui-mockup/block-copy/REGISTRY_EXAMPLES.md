# The block list in code

This page shows what the rows of the **Block Copy** sheet
(https://claude.ai/artifact/UAaxnYmKrca6f8Rh3BezgR) would look like as code, under the decided
design in `BLOCK_EDITOR_FRAMEWORK.md`. A block is declared on its type's existing registration
(D1). Slots name the fields they save to (D2). The sentence is the prose (D3).

Everything here is a **proposal**. None of it is in the codex yet, and the `Block` and
`BlockEditor` names don't exist until the framework is built. The record field names are the
real ones, checked in the code and in the compendium data.

## How a sheet row becomes code

| Sheet column | Key in the declaration |
|---|---|
| Kind | which registration it sits on: `CharacterModifier.RegisterType`, `ActivatedAbility.RegisterType` or `CharacterChoice.RegisterChoice` |
| Engine id | the registration's `id` (already there) |
| Label | `label` |
| Hover text | `desc` |
| Block sentence | `sentence`, with `{slot}` where each underlined word goes |
| Book prose | `prose` (only when it differs from the sentence), or a `prose()` function |
| Shelf group | `group` |
| Status | nothing in code; "Needs wording" means the type has no `block` yet |
| Engine name | the registration's `text` (already there) |

## 1. A simple row: "Fall" (ability step)

The sheet row is: Fall | Makes the targets fall if nothing is holding them up... | (needs a
sentence).

The registration already exists in `Draw Steel Ability Behaviors/AbilityFall.lua`. The `block`
table is the only new part:

```lua
ActivatedAbility.RegisterType{
    id = 'fall',
    text = 'Fall',
    createBehavior = function() return ActivatedAbilityFallBehavior.new{} end,

    block = {
        label    = "Fall",
        group    = "move",
        desc     = "Makes the targets fall if nothing is holding them up, using the normal falling rules.",
        sentence = "{applyto} {fall|falls}{stopFlying}",
        slots = {
            applyto    = Block.Who{ field = "applyto" },                    -- "The target", "You"
            stopFlying = Block.Toggle{ field = "stopFlying",                 -- the class's real field
                on = ", stopping flight first", off = "" },
        },
    },
}
```

- **Reading and saving:** free. Each slot names its field (Level 1).
- **Prose:** free. "The target falls, stopping flight first."
- **Everything else is unchanged.** Fields this block doesn't show (the filter and so on) are
  kept and reached through **Advanced editor**.

## 2. A row with a formula: "Deal damage" (ability step)

```lua
ActivatedAbility.RegisterType{
    id = 'damage',
    text = 'Damage',
    createBehavior = function() return ActivatedAbilityDamageBehavior.new{} end,

    block = {
        label    = "Deal damage",
        group    = "harm",
        desc     = "Deal damage to each target, or to you.",
        sentence = "Deal {roll} {damageType} damage to {applyto}",
        prose    = "{applyto} {take|takes} {roll} {damageType} damage",
        slots = {
            roll       = Block.Formula{ field = "roll", output = "roll",
                docs = { help = "How much damage is dealt. Can use dice.",
                         examples = { { "2d6 + Might", "2d6 plus your Might." } } } },
            damageType = Block.Choice{ field = "damageType", from = "damageTypes" },
            applyto    = Block.Who{ field = "applyto" },
        },
    },
}
```

- **The formula slot's `docs`** are the shape `gui.GoblinScriptInput{documentation=...}` already
  uses, so the formula box and the GoblinScript reference show them unchanged.
- **The prose differs from the sentence.** The sentence reads well while editing ("Deal 2d6 fire
  damage to the target"); the card reads like the book ("The target takes 2d6 fire damage").

## 3. A row that needs Level 2 and 3: "Immunity or weakness" (modifier)

The record stores entries in a list, and a weakness is stored as a negative number. Two slots
need to work that out, so the block reads and writes the record itself.

```lua
CharacterModifier.RegisterType("resistance", "Damage Immunity", {
    block = {
        label    = "Immunity or weakness",
        group    = "def",
        desc     = "Damage immunity or weakness of a type.",
        sentence = "You have {damageType} {kind} {amount}",
        slots = {
            damageType = Block.Choice{ from = "damageTypes" },
            kind       = Block.Choice{ options = { { "immunity", "immunity" }, { "weakness", "weakness" } } },
            amount     = Block.Formula{ output = "number" },
        },
        -- One block shows one entry. A record with several entries is shown as several blocks
        -- of the same feature, so read refuses anything else.
        read = function(rec)
            local list = rec.resistances or {}
            if #list ~= 1 or list[1].apply ~= "Damage Reduction" then return nil end
            local e = list[1]
            local neg = tostring(e.dr):match("^%-%((.*)%)$") or (tonumber(e.dr) and tonumber(e.dr) < 0 and tostring(-tonumber(e.dr)))
            return { damageType = e.damageType, kind = neg and "weakness" or "immunity", amount = neg or e.dr }
        end,
        write = function(v, rec)
            local dr = v.kind == "weakness" and ("-(" .. v.amount .. ")") or v.amount
            rec.resistances = { ResistanceEntry.new{ apply = "Damage Reduction", damageType = v.damageType, dr = dr } }
        end,
    },
})
```

- **`RegisterType` gains an optional third argument.** Today it stores only `{id, text}`. The
  new table is merged into `TypeInfo[id]`, so the existing hooks (`init`, `createEditor`, ...)
  keep working beside `block`.
- **`read` returning `nil`** means that record opens as "Make changes in the advanced editor"
  (states, decided). Nothing is guessed.
- **`autoDescribe` goes away.** This type has one today. It becomes the block's prose, and the
  old hook calls the block until it is removed.

## 4. Several rows, one type: the `attribute` modifier (Q2)

Four rows of the sheet all save as `attribute`:
- Change a stat
- Movement type
- You ignore / can't...
- Raise a characteristic

A type can list several blocks. Each has a `match(record)` that says whether a saved record is
"one of mine", and the first match opens it.

```lua
CharacterModifier.RegisterType("attribute", "Modify Attribute", {
    blocks = {
        {   key = "moveType", label = "Movement type", group = "stats",
            desc = "A movement type: fly, climb, swim or burrow.",
            sentence = "You can {attribute}",
            match = function(rec) return Block.IsMoveTypeAttribute(rec.attribute) end,
            slots = { attribute = Block.Choice{ field = "attribute", from = "moveTypes" } },
            -- The engine stores the movement type as an attribute set to 1.
            write = function(v, rec) rec.attribute = v.attribute; rec.value = 1 end,
        },
        {   key = "flag", label = "You ignore / can't...", group = "stats",
            desc = "A special rule the hero follows, such as Ignore Difficult Terrain.",
            sentence = "You have {attribute}",
            match = function(rec) return Block.IsFlagAttribute(rec.attribute) end,
            slots = { attribute = Block.Choice{ field = "attribute", from = "customFlags" } },
            write = function(v, rec) rec.attribute = v.attribute; rec.value = 1 end,
        },
        {   key = "stat", label = "Change a stat", group = "stats",          -- the catch-all: last
            desc = "Raise, lower or set one of the hero's numbers: Stamina, speed, stability, a characteristic...",
            sentence = "Your {attribute} {op} {value}",
            slots = {
                attribute = Block.Choice{ field = "attribute", from = "attributes" },
                op        = Block.Choice{ options = {
                    { "add", "increases by" }, { "sub", "decreases by" }, { "max", "increases to" },
                    { "set", "is" }, { "min", "can't go above" } } },
                value     = Block.Formula{ output = "number" },
            },
            -- "decreases by 3" is stored as operation add with value -(3), so op and value are worked out together.
            read = function(rec)
                local op, v = rec.operation or "add", tostring(rec.value)
                local inner = op == "add" and v:match("^%-%((.*)%)$")
                return { attribute = rec.attribute, op = inner and "sub" or op, value = inner or v }
            end,
            write = function(v, rec)
                rec.attribute = v.attribute
                rec.operation = (v.op == "sub" and "add") or v.op
                rec.value = v.op == "sub" and ("-(" .. v.value .. ")") or v.value
            end,
        },
    },
})
```

- **Order matters.** The specific blocks come first, and the catch-all ("Change a stat") is last.
- **One record, one block.** A record no `match` accepts opens in the advanced editor.
- **"Raise a characteristic"** is a choice (the player picks), so it is declared on the choice
  registry (section 6), even though it saves an `attribute`.

## 5. Shared lines: the five `power` rows

Edge or bane on rolls, Rolls against you, Extra damage, Change the outcome and Change potency
all save as `power`. They also share the **Offered when** and **Automatically selected** lines.
Those lines are declared once, as a slot group, and every roll block includes them:

```lua
-- Defined once by the framework (or in MCDModifyPowerRolls.lua), used by every roll block.
-- Its read/write are the ones in the brief (section 4a, Level 3).
local RollOptions = Block.Group{
    lines = {
        "Offered when {offer}",
        "Automatically selected {selected}{tick}{cost}",
    },
    slots = {
        offer    = Block.Test{ context = "offer" },     -- displayCondition; empty = every matching roll
        selected = Block.Choice{ options = { { "always", "always" }, { "when", "when" },
                       { "never", "never (the player chooses)" }, { "cost", "always, and it costs" } } },
        tick     = Block.Test{ context = "tick", showIf = function(v) return v.selected == "when" end },
        cost     = Block.Cost{ showIf = function(v) return v.selected == "cost" end },
    },
    read = RollOptionsRead, write = RollOptionsWrite,
}

CharacterModifier.RegisterType("power", "Modify Power Rolls", {
    blocks = {
        {   key = "edge", label = "Edge or bane on rolls", group = "rolls",
            desc = "An edge or bane on tests (by skill) or on ability rolls (by keyword).",
            sentence = "You have {modtype} on {rollType}",
            match = function(rec) return Block.OneOf(rec.modtype, "edge", "double_edge", "bane", "double_bane") end,
            slots = {
                -- The ids come from the list the old form's dropdown already uses; nothing is retyped.
                modtype  = Block.Choice{ field = "modtype",
                               from  = ActivatedAbilityPowerRollBehavior.s_modificationTypes,
                               only  = { "edge", "double_edge", "bane", "double_bane" },
                               words = { edge = "an edge", double_edge = "a double edge", bane = "a bane", double_bane = "a double bane" } },
                rollType = Block.Choice{ field = "rollType", options = { { "test_power_roll", "tests" }, { "ability_power_roll", "ability rolls" } } },
            },
            includes = { RollOptions },
        },
        {   key = "damage", label = "Extra damage", group = "rolls",
            desc = "Your abilities deal extra damage, optionally only with some keywords or a damage type.",
            sentence = "Your {keywords} abilities deal {damageModifier} extra {damageModifierType} damage",
            match = function(rec) return (rec.modtype or "none") == "none" and (rec.damageModifier or "") ~= "" end,
            slots = {
                keywords           = Block.Many{ field = "keywords", from = "abilityKeywords", form = "set" },
                damageModifier     = Block.Formula{ field = "damageModifier", output = "number" },
                damageModifierType = Block.Choice{ field = "damageModifierType", from = "damageTypes", empty = "(untyped)" },
            },
            includes = { RollOptions },
        },
        -- ...Change the outcome, Change potency and Rolls against you follow the same pattern.
    },
})
```

- **The same two lines in every roll block** come from one declaration, so a fix to "Automatically
  selected" lands in all five at once.
- **`form = "set"`** is the Level 2 conversion: keywords are stored as `{ Weapon = true }` and shown
  as a list.

### Setting up a Choice slot

A Choice slot needs two things for each option: the **id** the record stores, and the **words**
the author and the card see. There are three ways to supply them, in order of preference:

1. **Point at the list the old form already uses.** Most dropdowns in today's editors read from
   a `{ id, text }` table in the code. `from = <that table>` reuses it as it is. For example,
   the roll modifier's dropdown is `ActivatedAbilityPowerRollBehavior.s_modificationTypes`
   (`Draw Steel Core Rules/MCDMAbilityRollBehavior.lua:2479`).
   - `only = { ... }` keeps the ids this block offers.
   - `words = { id = "..." }` changes how an option reads in the sentence ("Edge" becomes "an
     edge").
   - The ids are never typed fresh, so they can't be misspelled.
2. **Point at a compendium table** with a name: `from = "damageTypes"`, `"conditions"`,
   `"skills"`, `"attributes"`, `"ongoingEffects"`... The framework reads it with
   `dmhub.GetTable`, so options added to the compendium appear without a code change.
3. **Type the pairs** as `{ "id", "words" }`, only when no list exists. To find the id, open a
   saved record (the YAML, or "Show saved fields" in the prototypes) or read the old form's
   `change` handler, which shows the value it writes.

Three checks catch mistakes, so an author never has to get an id right by luck:
- **At load:** every id named in `only` or `words` must exist in the `from` list, or the
  developer log names the block and the id.
- **The round-trip check:** a saved value that isn't one of a slot's options is reported for
  that type.
- **In the editor:** an unknown saved value is never changed. It shows as itself (for example
  `edge_bane`) and is kept on save, or the block's `match` passes the record to another block or
  to the advanced editor.

## 6. Choice rows: "Choose a perk", "Raise a characteristic"

Choices already have a registry, `CharacterChoice.RegisterChoice{ id, text, type }`
(`Draw Steel UI/DSClassEditor.lua:5`). Skills, languages, deities, domains and companions use
it.

**Finding:** the perk choice (`CharacterFeatChoice`) is not registered. It is hard-coded in the
class editor's add menu (`DSClassEditor.lua:1053`). Under this design it gets a registration
like the others, so every host's shelf finds it:

```lua
CharacterChoice.RegisterChoice{
    id = "feat",
    text = "Choice of a Perk",
    type = CharacterFeatChoice,

    block = {
        label    = "Choose a perk",
        group    = "skill",
        desc     = "The player picks perks from the groups you name.",
        sentence = "You gain {numChoices} {tag} perk of your choice",
        prose = function(rec, w)
            return "You gain " .. w.count(rec.numChoices or 1, w.list(w.slot("tag"), "or") .. " perk",
                w.list(w.slot("tag"), "or") .. " perks") .. " of your choice."
        end,
        slots = {
            numChoices = Block.Number{ field = "numChoices", default = 1 },
            -- Stored as "feat,exploration perk,intrigue perk"; shown as the groups' names.
            tag = Block.Many{ field = "tag", from = "perkGroups", form = "csv",
                get = function(list) return Block.Without(list, "feat") end,
                set = function(list) return Block.With(list, "feat", 1) end },
        },
    },
}
```

## 7. Wrappers: "Logic"

Logic has no engine type of its own: it writes `filterCondition` onto every block inside it.
It is declared with the framework's own blocks:

```lua
BlockEditor.RegisterWrapper{
    key = "onlyIf", label = "Logic", group = "if",
    desc = "The blocks inside apply only while something is true.",
    sentence = "Only if {cond}",
    slots = { cond = Block.Test{ context = "you", required = true } },
    children = { families = { "modifier" } },
    -- Each child's filterCondition becomes "(its own) and (this test)".
    wrap = function(v, childRecord) Block.AndFilter(childRecord, "filterCondition", v.cond) end,
}
```

## 8. A row with no wording yet ("Needs wording")

Nothing is written. The registration that exists today is enough for the type to show on the
shelf as a grey block named from its `text`, with "Make changes in the advanced editor" (D5).
Filling in its sheet row and adding `block = {...}` upgrades it in every editor at once.

## 9. An editor using the blocks: the Title host

```lua
BlockEditor.RegisterHost{
    id          = "title",
    record      = "Title",                               -- the RegisterGameType name
    pointOfView = "you",
    header = {
        { field = "echelon",      label = "Echelon",     slot = Block.Choice{ options = { "1", "2", "3", "4" } } },
        { field = "prerequisite", label = "Earned when", slot = Block.Text{} },
    },
    stacks = {
        { field = "modifierInfo", families = { "modifier", "choice", "logic" } },
    },
}
```

- **The framework builds the page:** the two header rows, the stack, the shelf (only the families
  listed), Status, the book preview, and the advanced-editor fallback.
- **The ongoing effect host** would be the same with `pointOfView = "the creature"` and no
  choices; the **kit host** adds its stat fields as fixed blocks in `header`.

## What the framework itself provides (one file, written once)

| Part | What it is |
|---|---|
| `Block.Text / Number / Toggle / Choice / Many / Formula / Test / Ref / Who / Cost / Group` | the slot types |
| forms `set`, `list`, `csv`, `bool01` | the Level 2 conversions |
| the prose helper `w` | `slot`, `subject`, `verb`, `formula`, `count`, `list`, `test` |
| a round-trip check | for each type, runs every compendium record through `read`, then `write`, and lists any record that changes |
| `BlockEditor.RegisterHost`, `RegisterWrapper` | editors and wrappers |
| a registry export | writes the registry to JSON for the HTML prototypes (D9) |
| the copy export | writes the Block Copy sheet straight from the registry, so the sheet and the code can't drift |

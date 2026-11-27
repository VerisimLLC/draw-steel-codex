local mod = dmhub.GetModLoading()

--[[
 Block: the data behind the block editors (the "Simple" editors for abilities,
 triggered abilities, classes, ...). Design: BLOCK_EDITOR_IMPLEMENTATION_PLAN.md
 section 2, and the decision ledger in BLOCK_EDITOR_FRAMEWORK.md.

 This file holds registries only. It has no gui and loads before the game
 rules, so a rules file can declare a block beside the game type it describes:

     Block.RegisterGroup{ id = "harm", text = "Harm", color = "#a8343f", glyph = "sword" }
     Block.RegisterBlock{ id = "damage", family = "step", group = "harm", label = "Deal damage",
                          sentence = { "Deal ", { slot = "amount" }, " damage." },
                          slots = { amount = { kind = "number", default = 2 } } }

 The editor UI (the Block Editor mod) only reads these. Three rules hold for
 every registry:

  * Entries are keyed by id, and registering an id again replaces the entry,
    so reloading a file is safe.
  * Lists are built when asked for (Block.All), not at load, so entries from
    mods that load later are included. The editor calls Block.Gather() when
    it opens.
  * A bad registration is reported with dmhub.Error and skipped; it never
    throws, so one mistake cannot stop a rules file loading.
]]

--- One part of a block's sentence: plain text, a slot the author can change, or
--- text with a look: {text = "Then", bold = true}, {text = "Flavor:", style = "aside"}.
--- @alias BlockSentencePart string|{slot: string}|{text: string, bold?: boolean, style?: string}

--- A value in a block's sentence that the author can change.
--- @class BlockSlot
--- @field kind string which control edits it: "number", "choice", "stat", "test", "text", "formula", "many" (a list of chips), ...
--- @field default any the value a new block starts with; a list of option ids for "many"
--- @field options? {id: string, text: string}[]|fun(): {id: string, text: string}[] the choices of a "choice" or "many" slot, or the suggestions of a "formula"; a function is asked each time, for lists read from data tables
--- @field style? string how its word looks: "formula" draws it in the mono font
--- @field empty? string shown faintly when the value reads as nothing (an optional part: "+ duration")
--- @field amount? boolean a "formula" slot that holds an amount: its picker lists the kinds of amount (a number, a stat, a stat with math, more as you level, depends on a test), and each number, stat and sign is changed on the block
--- @field dice? boolean an amount that may be a dice roll: the picker adds "A dice roll"
--- @field names? string[] extra names an amount can be based on, beside the stats and Level ("Recovery Value")
--- @field kinds? {name: string, example: string, value: string}[] the kinds a "formula" slot's picker lists when they are not the GoblinScript amounts (a tier's "3 + M"): one entry per kind, never one per value

--- A colour group: what kind of block this is. Colours are fixed (never theme tokens).
--- @class BlockGroup
--- @field id string
--- @field text string the group's name on the shelf
--- @field color string literal hex, at least 5:1 under white text
--- @field glyph? string a Phosphor icon name ("sword" draws phosphor/sword.png); none for header lines
--- @field order? number position on the shelf, low first
--- @field desc? string what the group is used for
--- @field stub? boolean

--- A block: one sentence with slots, shown on the shelf and in a stack.
--- @class BlockDecl
--- @field id string
--- @field family string what kind of thing it is ("step", "modifier", "choice", "gain", "logic", ...)
--- @field group string a BlockGroup id
--- @field label string its name on the shelf
--- @field desc? string hover text on the shelf
--- @field sentence BlockSentencePart[]
--- @field slots? table<string, BlockSlot> by the slot ids the sentence names
--- @field fits? string[] the kinds of list it may go in ("step", "tier"); any list when absent
--- @field order? number position within its group, low first
--- @field bodies? BlockBody[] lists of blocks it holds (a power roll's tiers, a wrapper's steps)
--- @field tag? string a small label drawn before the sentence ("Text" for card text the game does not apply)
--- @field italic? boolean draws the sentence in italics
--- @field capitalize? boolean capitalises the sentence's first letter (one that starts with a slot)
--- @field shelf? boolean false keeps it off the shelf (it only arrives by reading a record)
--- @field claims? string[] the behaviour typeNames this block may read (others are never offered to it)
--- @field read? fun(behavior: table, ctx: BlockContext): table|nil, table<string, BlockInstance[]>|nil the block's slot values for a saved behaviour, and the lists in its bodies; nil when it cannot show this one (it then opens as an Advanced block)
--- @field write? fun(values: table, saved: table|nil, ctx: BlockContext, bodies: table<string, BlockInstance[]>): table a behaviour for the values and bodies; saved is a copy of the behaviour it was read from (keep every field the block does not claim), nil for a new block
--- @field tier? BlockTierInfo set on a block that shows one part of a power roll tier
--- @field stub? boolean a placeholder with no record reading or writing yet
--- @field unread? boolean holds saved words or data no block reads yet, kept as written (counted by /blockroundtrip as not read)

--- A list of blocks inside a block. A power roll has one per tier; a wrapper has one.
--- @class BlockBody
--- @field id string
--- @field fits string the kind of list it is ("step", "tier"): only blocks that fit it go in
--- @field max? integer the most blocks it holds (1 for a part of a tier that saves as one segment); no limit when absent
--- @field label? string drawn beside the list ("11 or lower"); a body with no label is drawn as an inset list
--- @field sublabel? string a smaller second line under the label ("tier 1")

--- A fixed row on a host's page: a sentence like a block's, whose values live
--- in the record's own fields (model.values), not in a block.
--- @class BlockHeaderRow
--- @field id string
--- @field sentence BlockSentencePart[]
--- @field slots? table<string, BlockSlot>
--- @field when? fun(values: table): boolean shows the row only while this is true (a count only once there is a limit)

--- One section of a host's page (plan section 6).
--- @class BlockHostSection
--- @field id string
--- @field title string
--- @field optional? boolean marked "optional" in its header
--- @field rows? BlockHeaderRow[] fixed rows, drawn as one coloured group
--- @field summary? fun(model: table): string|nil a line under the rows that says what they add up to
--- @field addText? string a dashed "add" row, for a list that is empty until the author adds to it
--- @field stack? string the model field holding this section's list of blocks ("blocks")
--- @field fits? string the kind of list the stack is ("step")
--- @field stackAddText? string the "add" row under the stack

--- A book-style card, as a host describes it from a model.
--- @class BlockCard
--- @field title string
--- @field flavor? string
--- @field rows? {left: string, right: string, leftIcon?: string, rightIcon?: string, bold?: boolean}[] two-column lines under the title
--- @field roll? string the power roll line ("Power Roll + Might:")
--- @field tiers? {parts: (string|{chip: string})[]}[] one per tier; a chip is a shaded characteristic letter
--- @field effect? {label: string, text: string}

--- One of the record's own fields as a header slot: how it reads and writes.
--- @class BlockField
--- @field read fun(record: table): any the slot value
--- @field write fun(record: table, value: any, original: any) sets the record's fields for a value; original is the value read when opened, so a writer can keep the saved spelling
--- @field touches string[] the record fields it reads and writes
--- @field changed? fun(values: table, previous: any) called when the author changes this slot, to adjust the slots that depend on it in the same undo step (a ranged distance needs a range above 1)

--- One line in a host's checks.
--- @class BlockCheck
--- @field severity string "success", "warning" or "danger"
--- @field text string

--- An editor for one kind of record (plan section 6).
--- @class BlockHost
--- @field id string
--- @field tableName? string the data table its records are rows of, when they are rows (an ability lives inside its class instead)
--- @field claims fun(record: table): boolean whether this host edits the record
--- @field title? string the window's title ("Edit Ability")
--- @field header? string[] the fixed "what it is" rows
--- @field sections? BlockHostSection[] the page's sections, in order
--- @field kindChoice? {label: string, field: string, options: {id: string, text: string}[]} a switch at the top of the page ("This is an ability / a triggered ability")
--- @field toolbar? {label: string, field: string, options: {id: string, text: string}[]} a dropdown in the title bar ("Belongs to")
--- @field shelfSections? {title: string, fits: string}[] the shelf's sections: each lists the blocks that fit one kind of list
--- @field templates? {label: string, items: string[]} pills that start a new record from a template ("Start from:")
--- @field card? fun(model: table, record?: table): BlockCard the book-style card for the side panel; record is the one opened, when there is one
--- @field checks? fun(model: table, record?: table): BlockCheck[] problems and notes about the record
--- @field demo? table a ready-made model, opened when the editor has no record (developers)
--- @field fields? table<string, BlockField> the record's own fields, by the header slot that shows them
--- @field stepsField? string the record field holding its list of steps ("behaviors")
--- @field advancedBlock? string the block a step opens as when no block reads it
--- @field related? {tableName: string, field: string, label: string} records shown as pills beside this one
--- @field upload? fun(record: table): boolean|nil uploads a record the editor has just written into (an ability: the class or subclass that holds it); false or an error keeps the change waiting to retry. Without it the window cannot save
--- @field locate? fun(record: table): table|nil the record's current version in the game's tables, which an upload from elsewhere replaces; lets an open editor notice other people's changes
--- @field records? fun(): {record: table, where: string}[] every record this host edits, for /blockroundtrip and for /blockeditor by name (developers)
--- @field stepName? fun(step: table): string how a step no block reads is named on its Advanced block; its typeName split into words when absent
--- @field order? number
--- @field stub? boolean

--- A way to gain a heroic resource (plan section 11).
--- @class BlockGainEvent
--- @field id string the editor's own id; saved data never holds it
--- @field trigger string the engine trigger it saves as
--- @field base? string a condition joined to the line's test
--- @field you string "you <you>"
--- @field other? string "you or an ally <other>"
--- @field words? table<string, string> how a test on one of the trigger's values reads
--- @field menu? boolean whether it is in the short menu
--- @field order? number

--- A stat offered in every stat menu and formula.
--- @class BlockStat
--- @field id string
--- @field words string how it reads in a sentence ("Might")
--- @field kind string "characteristic", "number", ...
--- @field order? number
--- @field stub? boolean

--- A test offered in the test picker.
--- @class BlockTest
--- @field id string
--- @field prose string how it reads in a sentence ("you are winded")
--- @field toScript fun(values: table): string the GoblinScript it saves as
--- @field fromAst? fun(ast: table): table|nil reads it back from a parsed formula (not a regex)
--- @field order? number
--- @field stub? boolean

--- Wording for an engine trigger.
--- @class BlockTrigger
--- @field id string the engine trigger's id
--- @field words string
--- @field order? number

--- How a tier block maps to the tier grammar's segments (BlockTiers.lua).
--- @class BlockTierInfo
--- @field kinds string[] the segment kinds it shows (rule ids, "todo", "empty")
--- @field accepts? fun(values: table): boolean whether it shows a segment of one of its kinds (two blocks can split a kind)
--- @field from? fun(values: table): table the block's values for a segment's values; the segment's values as they are when absent
--- @field words? fun(values: table): string the tier words for edited values; absent, the values are the rule's own and its compile writes them

--- What a block's read and write are given (BERecordCache builds it).
--- @class BlockContext
--- @field host BlockHost
--- @field record table the record whose steps these are (a nested ability for its own steps)
--- @field forced? boolean every piece is being saved as if edited (the round-trip test)
--- @field OpenSteps fun(behaviors: table[]|nil, record: table): BlockInstance[] reads a nested list of steps (an ability inside a step) as blocks
--- @field SaveSteps fun(instances: BlockInstance[], saved: table[]|nil, record: table): table[], boolean writes them back; true when the list is untouched (keep the saved one)

--- A grouping the editor shows as a block holding steps (Only if, Strained,
--- a mode), read from a field every behaviour has. Neighbouring steps with the
--- same key share one wrapper block; outer wrappers have a lower order.
--- @class BlockWrapper
--- @field id string
--- @field order? number
--- @field block string the BlockDecl drawn for it, with one body
--- @field body? string that body's id ("steps")
--- @field key fun(behavior: table, ctx: BlockContext): string|nil what a saved behaviour groups by, nil when it is not wrapped
--- @field values fun(key: string, ctx: BlockContext): table the wrapper block's values for a key
--- @field keyOf fun(values: table, ctx: BlockContext): string|nil the key a wrapper block's values stand for
--- @field apply fun(behavior: table, key: string|nil, ctx: BlockContext) sets the behaviour's field so key() gives this key (nil: not wrapped)

--- A ready-made feature: several blocks added together.
--- @class BlockRecipe
--- @field id string
--- @field order? number

--- One run of a rendered sentence: its text, and the slot it shows (nil for plain text).
--- @class BlockSentenceRun
--- @field text string
--- @field slot? string
--- @field bold? boolean
--- @field style? string "formula" (a slot's style) or "aside" (a text part's)

--- A block placed in a record's model: which block it is and its slot values.
--- @class BlockInstance
--- @field block string a BlockDecl id
--- @field values table<string, any> by slot id
--- @field bodies? table<string, BlockInstance[]> by BlockBody id, for a block that holds others
--- @field uid? string the editor's id for this placed block, unique within its record
--- @field src? integer the position of the saved behaviour it was read from (BERecordCache)
--- @field openSignature? string its values and bodies as opened (Block.InstanceSignature), so an unchanged block writes back what it was read from
--- @field openContext? table<string, string> the wrapper keys it was opened inside, by wrapper id
--- @field saved? table what a block's read keeps to write an unchanged piece back as it was (a tier segment)

--- @class Block
Block = {}

--- The registries, in the order Block.Kinds lists them.
local KINDS = { "group", "host", "gainEvent", "stat", "test", "trigger", "wrapper", "recipe", "block" }

--kind -> id -> entry.
--- @type table<string, table<string, table>>
local g_entries = {}
--kind -> id -> when it was first registered, so re-registering keeps its place.
--- @type table<string, table<string, number>>
local g_sequence = {}
--kind -> the ordered list Block.All returned last; cleared by any registration.
--- @type table<string, table[]>
local g_lists = {}
--sources that declare entries elsewhere (see Block.RegisterSource), by id.
--- @type table<string, {id: string, kind: string, gather: fun(): table[]}>
local g_sources = {}
local g_nextSequence = 1

for _, kind in ipairs(KINDS) do
    g_entries[kind] = {}
    g_sequence[kind] = {}
end

--- Reports a bad registration in the log, without throwing.
--- @param message string
local function Report(message)
    dmhub.Error("Block: " .. message)
end

--- Checks an entry has its required fields of the right type.
--- @param kind string
--- @param entry any
--- @param required table<string, string> field name -> Lua type name
--- @return boolean
local function Validate(kind, entry, required)
    if type(entry) ~= "table" then
        Report(string.format("Register %s was given a %s, not a table", kind, type(entry)))
        return false
    end
    if type(entry.id) ~= "string" or entry.id == "" then
        Report(string.format("a %s registration has no id", kind))
        return false
    end
    for field, typeName in pairs(required) do
        if type(entry[field]) ~= typeName then
            Report(string.format("%s '%s' needs %s (a %s); got %s", kind, entry.id, field, typeName, type(entry[field])))
            return false
        end
    end
    return true
end

--- Stores an entry, replacing any entry with the same id.
--- @param kind string
--- @param entry table
local function Store(kind, entry)
    if g_sequence[kind][entry.id] == nil then
        g_sequence[kind][entry.id] = g_nextSequence
        g_nextSequence = g_nextSequence + 1
    end
    g_entries[kind][entry.id] = entry
    g_lists = {}
end

--- The names of the registries, for tools and tests.
--- @return string[]
function Block.Kinds()
    local result = {}
    for i, kind in ipairs(KINDS) do
        result[i] = kind
    end
    return result
end

--- @param entry BlockGroup
function Block.RegisterGroup(entry)
    if Validate("group", entry, { text = "string", color = "string" }) then
        Store("group", entry)
    end
end

--- @param entry BlockHost
function Block.RegisterHost(entry)
    if Validate("host", entry, { claims = "function" }) then
        Store("host", entry)
    end
end

--- @param entry BlockGainEvent
function Block.RegisterGainEvent(entry)
    if Validate("gainEvent", entry, { trigger = "string", you = "string" }) then
        Store("gainEvent", entry)
    end
end

--- @param entry BlockStat
function Block.RegisterStat(entry)
    if Validate("stat", entry, { words = "string", kind = "string" }) then
        Store("stat", entry)
    end
end

--- @param entry BlockTest
function Block.RegisterTest(entry)
    if Validate("test", entry, { prose = "string", toScript = "function" }) then
        Store("test", entry)
    end
end

--- @param entry BlockTrigger
function Block.RegisterTrigger(entry)
    if Validate("trigger", entry, { words = "string" }) then
        Store("trigger", entry)
    end
end

--- @param entry BlockWrapper
function Block.RegisterWrapper(entry)
    if Validate("wrapper", entry, { block = "string", key = "function", values = "function", keyOf = "function", apply = "function" }) then
        Store("wrapper", entry)
    end
end

--- @param entry BlockRecipe
function Block.RegisterRecipe(entry)
    if Validate("recipe", entry, {}) then
        Store("recipe", entry)
    end
end

--- Checks a block's sentence only names slots the block declares.
--- @param entry BlockDecl
--- @return boolean
local function ValidateSentence(entry)
    for i, part in ipairs(entry.sentence) do
        if type(part) == "table" and part.slot == nil and type(part.text) == "string" then
            --styled text: nothing to check.
        elseif type(part) == "table" then
            local slot = part.slot
            if type(slot) ~= "string" or entry.slots == nil or type(entry.slots[slot]) ~= "table" then
                Report(string.format("block '%s': sentence part %d names a slot it does not declare", entry.id, i))
                return false
            end
            if type(entry.slots[slot].kind) ~= "string" then
                Report(string.format("block '%s': slot '%s' has no kind", entry.id, slot))
                return false
            end
        elseif type(part) ~= "string" then
            Report(string.format("block '%s': sentence part %d is a %s, not text or a slot", entry.id, i, type(part)))
            return false
        end
    end
    return true
end

--- Registers a block that is not tied to one modifier or behaviour type.
--- @param entry BlockDecl
function Block.RegisterBlock(entry)
    if Validate("block", entry, { family = "string", group = "string", label = "string", sentence = "table" }) and ValidateSentence(entry) then
        Store("block", entry)
    end
end

--- Registers a place other than this file's registries that declares entries,
--- read each time the lists are gathered: for entries that come from game data
--- known only once the rules have loaded (the Draw Steel characteristics, from
--- creature.attributeIds, are the stat source in MCDMAbilityBlocks.lua).
--- @param source {id: string, kind: string, gather: fun(): table[]}
function Block.RegisterSource(source)
    if not Validate("source", source, { kind = "string", gather = "function" }) then
        return
    end
    if g_entries[source.kind] == nil then
        Report(string.format("source '%s' is for an unknown registry '%s'", source.id, tostring(source.kind)))
        return
    end
    g_sources[source.id] = source
    g_lists = {}
end

--- Forgets the gathered lists, so the next Block.All reads every source again.
--- The editor calls this when it opens.
function Block.Gather()
    g_lists = {}
end

--- The entries of a registry plus what its sources declare, by id. A source's
--- entry never replaces a direct registration with the same id, unless that
--- registration is a stub (the stubs stand in until the real ones are declared).
--- @param kind string
--- @return table<string, table>
local function Collect(kind)
    local result = {}
    for _, source in pairs(g_sources) do
        if source.kind == kind then
            local ok, declared = pcall(source.gather)
            if not ok then
                Report(string.format("source '%s' failed: %s", source.id, tostring(declared)))
            elseif type(declared) == "table" then
                for _, entry in ipairs(declared) do
                    if type(entry) == "table" and type(entry.id) == "string" then
                        result[entry.id] = entry
                    end
                end
            end
        end
    end
    for id, entry in pairs(g_entries[kind]) do
        local declared = result[id]
        if not (entry.stub and declared ~= nil and not declared.stub) then
            result[id] = entry
        end
    end
    return result
end

--Registries whose entries are alternatives in one list (a stat menu): once a
--real entry is declared, the stub entries leave the list (Block.Get still
--finds them, for the stub demo).
local STUBS_GIVE_WAY = { stat = true, test = true }

--- Every entry of a registry, ordered by `order` (absent = 1000) and then by
--- when it was first registered. Do not change the list returned: it is kept.
--- @param kind string one of Block.Kinds()
--- @return table[]
function Block.All(kind)
    local list = g_lists[kind]
    if list ~= nil then
        return list
    end
    list = {}
    if g_entries[kind] == nil then
        Report(string.format("no registry named '%s'", tostring(kind)))
        return list
    end
    local collected = Collect(kind)
    local hasReal = false
    if STUBS_GIVE_WAY[kind] then
        for _, entry in pairs(collected) do
            if not entry.stub then
                hasReal = true
                break
            end
        end
    end
    for _, entry in pairs(collected) do
        if not (hasReal and entry.stub) then
            list[#list + 1] = entry
        end
    end
    local sequence = g_sequence[kind]
    table.sort(list, function(a, b)
        local orderA, orderB = a.order or 1000, b.order or 1000
        if orderA ~= orderB then
            return orderA < orderB
        end
        local seqA, seqB = sequence[a.id] or math.huge, sequence[b.id] or math.huge
        if seqA ~= seqB then
            return seqA < seqB
        end
        return a.id < b.id
    end)
    g_lists[kind] = list
    return list
end

--- One entry of a registry, or nil.
--- @param kind string one of Block.Kinds()
--- @param id string
--- @return table|nil
function Block.Get(kind, id)
    local entries = g_entries[kind]
    if entries == nil then
        Report(string.format("no registry named '%s'", tostring(kind)))
        return nil
    end
    local entry = entries[id]
    if entry ~= nil then
        return entry
    end
    --not registered directly: it may come from a source.
    for _, candidate in ipairs(Block.All(kind)) do
        if candidate.id == id then
            return candidate
        end
    end
    return nil
end

--- @param id string
--- @return BlockGroup|nil
function Block.GetGroup(id)
    return Block.Get("group", id) --[[@as BlockGroup|nil]]
end

--- @param id string
--- @return BlockDecl|nil
function Block.GetBlock(id)
    return Block.Get("block", id) --[[@as BlockDecl|nil]]
end

--- The host that edits a record, or nil when no registered host claims it.
--- @param record table
--- @return BlockHost|nil
function Block.FindHost(record)
    for _, host in ipairs(Block.All("host")) do
        --- @cast host BlockHost
        local ok, claimed = pcall(host.claims, record)
        if not ok then
            Report(string.format("host '%s' claims failed: %s", host.id, tostring(claimed)))
        elseif claimed then
            return host
        end
    end
    return nil
end

--- A new instance of a block with every slot at its default.
--- @param blockId string
--- @return BlockInstance|nil
function Block.Instantiate(blockId)
    local decl = Block.GetBlock(blockId)
    if decl == nil then
        Report(string.format("no block '%s' to instantiate", tostring(blockId)))
        return nil
    end
    local values = {}
    for slotId, slot in pairs(decl.slots or {}) do
        --a list default is copied, so two blocks never share one table.
        if type(slot.default) == "table" then
            local copy = {}
            for i, item in ipairs(slot.default) do
                copy[i] = item
            end
            values[slotId] = copy
        else
            values[slotId] = slot.default
        end
    end
    local instance = { block = blockId, values = values }
    if decl.bodies ~= nil then
        instance.bodies = {}
        for _, body in ipairs(decl.bodies) do
            instance.bodies[body.id] = {}
        end
    end
    return instance
end

--- A stable string for a plain value: tables by sorted keys, so two equal
--- values always give the same string.
--- @param value any
--- @return string
local function Signature(value)
    if type(value) ~= "table" then
        return type(value) .. ":" .. tostring(value)
    end
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for i, key in ipairs(keys) do
        parts[i] = tostring(key) .. "=" .. Signature(value[key])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

--- How an ongoing effect duration reads in a block's sentence, by duration id
--- ("eoe" -> "until the end of the encounter"). A game system fills it beside
--- its durations; a duration with no words shows its option's name.
--- @type table<string, string>
Block.DurationWords = {}

--- A record's value for a field as the game reads it: the saved value, or the
--- type's own default when nothing is saved (ActivatedAbilityBehavior.damageType
--- is "force", so an unsaved damage type is force, not untyped). Nil when neither.
--- @param record table
--- @param fieldName string|nil
--- @return any
function Block.FieldValue(record, fieldName)
    if fieldName == nil then
        return nil
    end
    local value = rawget(record, fieldName)
    if value == nil then
        --a game-typed record raises on a field its type does not declare.
        pcall(function() value = record[fieldName] end)
    end
    return value
end

--- A stable string for a plain value (tables by sorted keys).
--- @param value any
--- @return string
function Block.ValueSignature(value)
    return Signature(value)
end

--- What a placed block shows: its block, values and (in order) the blocks in
--- its bodies. Editor bookkeeping (uid, src, saved, ...) is left out, so two
--- signatures differ only when the author changed something.
--- @param instance BlockInstance
--- @return string
function Block.InstanceSignature(instance)
    local bodies = {}
    for bodyId, list in pairs(instance.bodies or {}) do
        local items = {}
        for i, inner in ipairs(list) do
            items[i] = Block.InstanceSignature(inner)
        end
        bodies[bodyId] = "[" .. table.concat(items, ";") .. "]"
    end
    return tostring(instance.block) .. "|" .. Signature(instance.values or {}) .. "|" .. Signature(bodies)
end

--- Whether a placed block (and everything inside it) is as it was opened.
--- @param instance BlockInstance
--- @return boolean
function Block.InstanceUnchanged(instance)
    return instance.openSignature ~= nil and instance.openSignature == Block.InstanceSignature(instance)
end

--- A slot's options, asking for them when they are a function.
--- @param slot BlockSlot
--- @return {id: string, text: string}[]
function Block.SlotOptions(slot)
    local options = slot.options
    if type(options) == "function" then
        local ok, result = pcall(options)
        if ok and type(result) == "table" then
            return result
        end
        Report("a slot's options failed: " .. tostring(result))
        return {}
    end
    return options or {}
end

--- How a slot's value reads in the sentence: a choice's text, a stat's or a
--- test's words, otherwise the value itself.
--- @param decl BlockDecl
--- @param slotId string
--- @param value any
--- @return string
function Block.SlotText(decl, slotId, value)
    local slot = decl.slots ~= nil and decl.slots[slotId] or nil
    if slot == nil then
        return tostring(value)
    end
    if slot.kind == "many" and type(value) == "table" then
        local texts = {}
        for i, item in ipairs(value) do
            texts[i] = Block.SlotText(decl, slotId, item)
        end
        return table.concat(texts, ", ")
    end
    if slot.kind == "choice" or slot.kind == "many" or slot.kind == "formula" then
        for _, option in ipairs(Block.SlotOptions(slot)) do
            if option.id == value then
                return option.text
            end
        end
    elseif slot.kind == "stat" then
        local stat = Block.Get("stat", tostring(value)) --[[@as BlockStat|nil]]
        if stat ~= nil then
            return stat.words
        end
    elseif slot.kind == "test" then
        local test = Block.Get("test", tostring(value)) --[[@as BlockTest|nil]]
        if test ~= nil then
            return test.prose
        end
    end
    if value == nil then
        return "..."
    end
    return tostring(value)
end

--- A block's sentence as runs of text, each marked with the slot it shows, for
--- the UI to turn into clickable words (and for plain prose: join the texts).
--- Works for a host's header rows too: it only reads `sentence` and `slots`.
--- @param decl BlockDecl|BlockHeaderRow
--- @param values? table<string, any> slot values; a slot's default when absent
--- @return BlockSentenceRun[]
function Block.Sentence(decl, values)
    --- @cast decl BlockDecl
    local runs = {}
    for _, part in ipairs(decl.sentence) do
        if type(part) == "table" and part.slot ~= nil then
            local slotId = part.slot
            local value = values ~= nil and values[slotId] or nil
            local slot = decl.slots ~= nil and decl.slots[slotId] or nil
            if value == nil and slot ~= nil then
                value = slot.default
            end
            runs[#runs + 1] = { text = Block.SlotText(decl, slotId, value), slot = slotId, style = slot ~= nil and slot.style or nil }
        elseif type(part) == "table" then
            runs[#runs + 1] = { text = tostring(part.text), bold = part.bold, style = part.style }
        else
            runs[#runs + 1] = { text = part }
        end
    end
    if decl.capitalize and runs[1] ~= nil then
        runs[1].text = string.upper(string.sub(runs[1].text, 1, 1)) .. string.sub(runs[1].text, 2)
    end
    return runs
end

--- A block's sentence as plain text.
--- @param decl BlockDecl
--- @param values? table<string, any>
--- @return string
function Block.SentenceText(decl, values)
    local texts = {}
    for i, run in ipairs(Block.Sentence(decl, values)) do
        texts[i] = run.text
    end
    return table.concat(texts)
end

----------------------------------------------------------------------------
-- The shared colour groups (plan section 13): literal hex, each at least 5:1
-- under white text, with a Phosphor glyph the codex ships (phosphor/<glyph>.png).
-- A meaning the plan gives two glyphs or colours is two groups here.
----------------------------------------------------------------------------

Block.RegisterGroup{ id = "stats", text = "Stats", color = "#3c5fa8", glyph = "gauge", order = 10, desc = "Change a stat, characteristics, speed." }
Block.RegisterGroup{ id = "movement", text = "Movement", color = "#3c5fa8", glyph = "footprints-fill", order = 20, desc = "Move a creature." }
Block.RegisterGroup{ id = "rolls", text = "Rolls and roll changes", color = "#7d4aa3", glyph = "dice-six", order = 30, desc = "Power roll, edges and banes, change the roll." }
Block.RegisterGroup{ id = "defences", text = "Defences", color = "#2f6f6a", glyph = "shield", order = 40, desc = "Immunity, weakness, condition immunity." }
Block.RegisterGroup{ id = "abilities", text = "Abilities", color = "#8b5434", glyph = "lightning", order = 50, desc = "Gain an ability, use a new ability." }
Block.RegisterGroup{ id = "areas", text = "Areas", color = "#8b5434", glyph = "polygon", order = 60, desc = "Auras, summons." }
Block.RegisterGroup{ id = "skills", text = "Skills, perks and languages", color = "#5d6a1c", glyph = "book-open", order = 70, desc = "Skills, perks, languages." }
Block.RegisterGroup{ id = "resources", text = "Class and resources", color = "#8a6a20", glyph = "coin", order = 80, desc = "Resources, gains, kits, reminders." }
Block.RegisterGroup{ id = "logic", text = "Logic", color = "#a8501d", glyph = "arrow-elbow-right-down-bold", order = 90, desc = "Only if, choose one when used, remember." }
Block.RegisterGroup{ id = "choices", text = "Choices", color = "#3d7a3a", glyph = "list-bullets", order = 100, desc = "The player picks." }
Block.RegisterGroup{ id = "harm", text = "Harm", color = "#a8343f", glyph = "sword", order = 110, desc = "Damage." }
Block.RegisterGroup{ id = "conditions", text = "Conditions", color = "#8e3f86", glyph = "lock-simple", order = 120, desc = "Apply a condition, forced movement." }
Block.RegisterGroup{ id = "effects", text = "Effects", color = "#2b6f86", glyph = "sparkle", order = 130, desc = "Ongoing effects." }
Block.RegisterGroup{ id = "help", text = "Help", color = "#277057", glyph = "heart", order = 140, desc = "Heal, end effects, temporary Stamina." }
Block.RegisterGroup{ id = "potency", text = "Potency", color = "#2c7391", glyph = "magnifying-glass-bold", order = 150, desc = "Potency checks." }
Block.RegisterGroup{ id = "tests", text = "Tests", color = "#4d6a8a", glyph = "check-square", order = 160, desc = "Test blocks." }
Block.RegisterGroup{ id = "numbers", text = "Numbers", color = "#357a4d", glyph = "plus-minus", order = 170, desc = "Value pieces." }
Block.RegisterGroup{ id = "growing", text = "Growing tables", color = "#8f3a2e", glyph = "stack-plus", order = 180, desc = "Rows unlocked by resource and level." }
Block.RegisterGroup{ id = "recipes", text = "Your recipes", color = "#7a4f8f", glyph = "star", order = 190, desc = "Saved features." }
Block.RegisterGroup{ id = "display", text = "Display", color = "#6b6258", glyph = "eye", order = 200, desc = "Card text the game does not apply." }
Block.RegisterGroup{ id = "scripts", text = "Scripts", color = "#55524c", glyph = "code", order = 210, desc = "Scripts." }
Block.RegisterGroup{ id = "unique", text = "Unique", color = "#6a5a3c", glyph = "diamond", order = 220, desc = "One-offs." }
Block.RegisterGroup{ id = "advanced", text = "Advanced", color = "#5b564e", glyph = "gear-six-fill", order = 230, desc = "Records no block shows." }
--Header lines never move and have no glyph.
Block.RegisterGroup{ id = "header", text = "Header lines", color = "#8c6a24", order = 240, desc = "Fixed \"what it is\" lines." }

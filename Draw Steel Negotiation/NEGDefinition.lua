local mod = dmhub.GetModLoading()

--- One motivation or pitfall on a prepared negotiation: which of the twelve it
--- is, and what it means to this NPC. The catalog carries no description of
--- its own - what the trait means here is the Director's to write.
--- @class NEGTrait
--- @field id string row identity, so a row survives its trait changing
--- @field trait string a NEGRules.traits id
--- @field note string this NPC's take on it
NEGTrait = RegisterGameType("NEGTrait")

NEGTrait.trait = ""
NEGTrait.note = ""

--- @param args nil|table
--- @return NEGTrait
function NEGTrait.CreateNew(args)
    args = args or {}
    args.id = args.id or dmhub.GenerateGuid()
    return NEGTrait.new(args)
end

--- A prepared, reusable negotiation. A run copies one wholesale and never
--- writes back to it.
--- @class NEGDefinition
--- @field id string
--- @field name string what the negotiation is called
--- @field npcName string who the heroes are facing
--- @field portraitid string the NPC's picture, from the Avatar library
--- @field languageId string the NPC's native language
--- @field attitudeId string a NEGRules.attitudes id
--- @field interest number starting interest
--- @field patience number starting patience, before the language bonus
--- @field impression number the Renown needed to sway them
--- @field summary string
--- @field motivations NEGTrait[]
--- @field pitfalls NEGTrait[]
--- @field offers string[] six entries, index = interest + 1
--- @field showInterest boolean whether the table sees the interest scale
--- @field showPatience boolean whether the table sees the patience scale
--- @field folderId string
NEGDefinition = RegisterGameType("NEGDefinition")

NEGDefinition.name = "New Negotiation"
NEGDefinition.npcName = ""
NEGDefinition.portraitid = ""
NEGDefinition.languageId = ""
NEGDefinition.attitudeId = "neutral"
NEGDefinition.summary = ""
NEGDefinition.folderId = ""
NEGDefinition.impression = NEGConstants.impressionDefault

--- Declared on the type so the scales read correctly before anyone has
--- touched them.
NEGDefinition.interest = 2
NEGDefinition.patience = 3

--- The table sees nothing by default. Revealing a scale is a deliberate act.
NEGDefinition.showInterest = false
NEGDefinition.showPatience = false

--- Declared on the type so a document mutation can read them as plain fields.
--- A registered instance inside a shared document sometimes arrives as a plain
--- table, and a :try_get() on one of those raises mid-transaction and strands
--- the document. Every writer below copies before assigning, so nothing ever
--- writes into these shared defaults.
NEGDefinition.motivations = {}
NEGDefinition.pitfalls = {}
NEGDefinition.offers = {}

--- Six empty offers, one per interest score, kept dense so the array
--- serializes as an array however few of them the Director fills in.
--- @return string[]
local function EmptyOffers()
    local offers = {}
    for _ = NEGConstants.scaleMin, NEGConstants.scaleMax do
        offers[#offers + 1] = ""
    end
    return offers
end

--- @param args nil|table
--- @return NEGDefinition
function NEGDefinition.CreateNew(args)
    args = args or {}
    args.id = args.id or dmhub.GenerateGuid()
    args.motivations = args.motivations or {}
    args.pitfalls = args.pitfalls or {}
    args.offers = args.offers or EmptyOffers()
    return NEGDefinition.new(args)
end

--- @return string
function NEGDefinition:GetID()
    return self:try_get("id") or ""
end

--- The offer written for an interest score.
--- @param interest number
--- @return string
function NEGDefinition:GetOffer(interest)
    local offers = self:try_get("offers", {})
    return offers[interest + 1] or ""
end

--- Every trait this negotiation has already spent, on either side.
--- @return table<string, boolean>
function NEGDefinition:UsedTraits()
    local used = {}
    for _, kind in ipairs({ "motivations", "pitfalls" }) do
        for _, row in ipairs(self:try_get(kind, {})) do
            local trait = row:try_get("trait", "")
            if trait ~= "" then
                used[trait] = true
            end
        end
    end
    return used
end

--- Whether this negotiation carries what the rules ask for. Advisory: the
--- editor marks a shortfall, nothing blocks on it.
--- @return boolean
function NEGDefinition:IsConfigured()
    if trim(self:try_get("npcName", "")) == "" then
        return false
    end
    if #self:try_get("motivations", {}) < NEGConstants.motivationsExpected then
        return false
    end
    if #self:try_get("pitfalls", {}) < NEGConstants.pitfallsExpected then
        return false
    end
    return true
end

mod:RegisterDocumentForCheckpointBackups(NEGConstants.libraryDoc)

--- @return LuaCodeModDocumentSnapshot
function NEGDefinition.Doc()
    return mod:GetDocumentSnapshot(NEGConstants.libraryDoc)
end

--- @return string monitorGame path for the library
function NEGDefinition.DocPath()
    return mod:GetDocumentPath(NEGConstants.libraryDoc)
end

--- Mutate the library inside one document change.
--- @param description string
--- @param fn fun(definitions: table<string, NEGDefinition>)
function NEGDefinition.Mutate(description, fn)
    local doc = NEGDefinition.Doc()
    doc:BeginChange()
    if doc.data.definitions == nil then
        doc.data.definitions = {}
    end
    fn(doc.data.definitions)
    doc:CompleteChange(description)
end

--- @return table<string, NEGDefinition>
local function Definitions()
    local doc = NEGDefinition.Doc()
    if doc == nil or doc.data == nil then
        return {}
    end
    return doc.data.definitions or {}
end

--- @return NEGDefinition[] sorted by name, then id
function NEGDefinition.GetAll()
    local result = {}
    for id, def in pairs(Definitions()) do
        def.id = id
        result[#result + 1] = def
    end
    table.sort(result, function(a, b)
        local an, bn = string.lower(a.name or ""), string.lower(b.name or "")
        if an == bn then
            return a:GetID() < b:GetID()
        end
        return an < bn
    end)
    return result
end

--- @param id string
--- @return NEGDefinition|nil
function NEGDefinition.GetByID(id)
    if id == nil or id == "" then
        return nil
    end
    return Definitions()[id]
end

--- Folders exist only in the library document, so an empty one can still be
--- named and kept.
--- @return {id: string, name: string}[] sorted by name
function NEGDefinition.GetFolders()
    local doc = NEGDefinition.Doc()
    local folders = doc ~= nil and doc.data ~= nil and doc.data.folders or {}

    local result = {}
    for id, folder in pairs(folders) do
        result[#result + 1] = { id = id, name = folder.name or "" }
    end
    table.sort(result, function(a, b)
        local an, bn = string.lower(a.name), string.lower(b.name)
        if an == bn then
            return a.id < b.id
        end
        return an < bn
    end)
    return result
end

--- @param description string
--- @param fn fun(folders: table)
local function MutateFolders(description, fn)
    local doc = NEGDefinition.Doc()
    doc:BeginChange()
    if doc.data.folders == nil then
        doc.data.folders = {}
    end
    fn(doc.data.folders)
    doc:CompleteChange(description)
end

--- @return string id of the new folder
function NEGDefinition.CreateFolder()
    local id = dmhub.GenerateGuid()
    MutateFolders("New negotiation folder", function(folders)
        folders[id] = { id = id, name = "New Folder" }
    end)
    return id
end

--- @param id string
--- @param name string
function NEGDefinition.RenameFolder(id, name)
    MutateFolders("Rename negotiation folder", function(folders)
        local folder = folders[id]
        if folder ~= nil and folder.name ~= name then
            folder.name = name
        end
    end)
end

--- Negotiations in a folder are the reason to keep it, so an occupied folder
--- stays. Emptying it is the Director's decision, not a side effect.
--- @param id string
--- @return boolean whether it went
function NEGDefinition.DeleteFolder(id)
    for _, def in ipairs(NEGDefinition.GetAll()) do
        if def:try_get("folderId", "") == id then
            return false
        end
    end

    MutateFolders("Delete negotiation folder", function(folders)
        folders[id] = nil
    end)
    return true
end

--- @param defid string
--- @param folderId string empty for the root
function NEGDefinition.SetFolder(defid, folderId)
    NEGDefinition.Mutate("Move negotiation", function(defs)
        local def = defs[defid]
        if def ~= nil then
            def.folderId = folderId or ""
        end
    end)
end

--- @param name nil|string
--- @return string id
function NEGDefinition.CreateInLibrary(name)
    local attitude = NEGRules.AttitudeById(NEGDefinition.attitudeId)
    local def = NEGDefinition.CreateNew{
        name = name or "New Negotiation",
        interest = attitude ~= nil and attitude.interest or NEGDefinition.interest,
        patience = attitude ~= nil and attitude.patience or NEGDefinition.patience,
    }
    NEGDefinition.Mutate("Create negotiation", function(defs)
        defs[def:GetID()] = def
    end)
    return def:GetID()
end

--- @param id string
--- @return string|nil id of the copy
function NEGDefinition.Duplicate(id)
    local source = NEGDefinition.GetByID(id)
    if source == nil then
        return nil
    end
    local copy = DeepCopy(source)
    copy.id = dmhub.GenerateGuid()
    copy.name = string.format("%s (copy)", source.name or "Negotiation")
    NEGDefinition.Mutate("Duplicate negotiation", function(defs)
        defs[copy.id] = copy
    end)
    return copy.id
end

--- @param id string
function NEGDefinition.Delete(id)
    NEGDefinition.Mutate("Delete negotiation", function(defs)
        defs[id] = nil
    end)
end

--- Write one plain field. Scales and impression arrive already clamped by
--- their controls; this does not second-guess them.
--- @param id string
--- @param key string
--- @param value any
function NEGDefinition.SetField(id, key, value)
    NEGDefinition.Mutate(string.format("Set negotiation %s", key), function(defs)
        local def = defs[id]
        if def ~= nil and def[key] ~= value then
            def[key] = value
        end
    end)
end

--- Picking an attitude is picking its opening numbers. Both stay editable
--- afterwards - the rules leave the Director free to adjust either.
--- @param id string
--- @param attitudeId string
function NEGDefinition.ApplyAttitude(id, attitudeId)
    local attitude = NEGRules.AttitudeById(attitudeId)
    if attitude == nil then
        return
    end

    NEGDefinition.Mutate("Set negotiation attitude", function(defs)
        local def = defs[id]
        if def == nil then
            return
        end
        def.attitudeId = attitudeId
        def.interest = attitude.interest
        def.patience = attitude.patience
    end)
end

--- @param id string
--- @param interest number
--- @param text string
function NEGDefinition.SetOffer(id, interest, text)
    NEGDefinition.Mutate("Write negotiation offer", function(defs)
        local def = defs[id]
        if def == nil then
            return
        end

        local offers = EmptyOffers()
        for i, existing in ipairs(def.offers) do
            offers[i] = existing
        end
        offers[interest + 1] = text
        def.offers = offers
    end)
end

--- The first trait the negotiation has not spent, so a new row lands on
--- something usable rather than blank.
--- @param def NEGDefinition
--- @return string
local function FirstFreeTrait(def)
    local used = def:UsedTraits()
    for _, trait in ipairs(NEGRules.traits) do
        if used[trait.id] ~= true then
            return trait.id
        end
    end
    return ""
end

--- @param id string
--- @param kind string "motivations" or "pitfalls"
function NEGDefinition.AddTrait(id, kind)
    --Which trait is free is worked out here, outside the transaction, because
    --answering it means reading the definition through its accessors.
    local def = NEGDefinition.GetByID(id)
    if def == nil then
        return
    end

    local free = FirstFreeTrait(def)
    if free == "" then
        return
    end

    local row = NEGTrait.CreateNew{ trait = free }

    NEGDefinition.Mutate("Add negotiation trait", function(defs)
        local target = defs[id]
        if target == nil then
            return
        end
        local rows = {}
        for i, existing in ipairs(target[kind]) do
            rows[i] = existing
        end
        rows[#rows + 1] = row
        target[kind] = rows
    end)
end

--- @param id string
--- @param kind string
--- @param rowId string
function NEGDefinition.RemoveTrait(id, kind, rowId)
    NEGDefinition.Mutate("Remove negotiation trait", function(defs)
        local def = defs[id]
        if def == nil then
            return
        end
        local rows = {}
        for _, row in ipairs(def[kind]) do
            if row.id ~= rowId then
                rows[#rows + 1] = row
            end
        end
        def[kind] = rows
    end)
end

--- @param id string
--- @param kind string
--- @param rowId string
--- @param key string "trait" or "note"
--- @param value any
function NEGDefinition.SetTraitField(id, kind, rowId, key, value)
    NEGDefinition.Mutate("Edit negotiation trait", function(defs)
        local def = defs[id]
        if def == nil then
            return
        end
        for _, row in ipairs(def[kind]) do
            if row.id == rowId then
                if row[key] ~= value then
                    row[key] = value
                end
                return
            end
        end
    end)
end

--- "Foo" -> "Foo (2)", "Foo (2)" -> "Foo (3)", the way a file system would.
--- @param name string
--- @return string
local function UniqueName(name)
    local taken = {}
    for _, def in ipairs(NEGDefinition.GetAll()) do
        taken[string.lower(def.name or "")] = true
    end

    if not taken[string.lower(name)] then
        return name
    end

    local base, n = string.match(name, "^(.-)%s*%((%d+)%)$")
    if base == nil then
        base, n = name, 1
    end

    local counter = tonumber(n) or 1
    while true do
        counter = counter + 1
        local candidate = string.format("%s (%d)", base, counter)
        if not taken[string.lower(candidate)] then
            return candidate
        end
    end
end

--- A filled-in example, so a Director can see the shape rather than infer it.
--- @return string
function NEGDefinition.BuildImportTemplate()
    local names = {}
    for _, trait in ipairs(NEGRules.traits) do
        names[#names + 1] = trait.id
    end

    local attitudes = {}
    for _, attitude in ipairs(NEGRules.attitudes) do
        attitudes[#attitudes + 1] = attitude.id
    end

    local lines = {
        "{",
        "  \"name\": \"Zola and the Clock\",",
        "  \"npc\": \"Zola Honeycut\",",
        "  \"language\": \"Hyrallic\",",
        string.format("  \"attitude\": \"%s\",", attitudes[2] or "suspicious"),
        "  \"interest\": 2,",
        "  \"patience\": 4,",
        "  \"impression\": 3,",
        "  \"summary\": \"What the heroes want, and why the NPC is torn.\",",
        "  \"motivations\": [",
        "    { \"trait\": \"benevolence\", \"note\": \"What this means to the NPC.\" }",
        "  ],",
        "  \"pitfalls\": [",
        "    { \"trait\": \"higherauthority\", \"note\": \"What this means to the NPC.\" }",
        "  ],",
        "  \"offers\": {",
        "    \"0\": \"No, and...\",",
        "    \"1\": \"No.\",",
        "    \"2\": \"No, but...\",",
        "    \"3\": \"Yes, but...\",",
        "    \"4\": \"Yes.\",",
        "    \"5\": \"Yes, and...\"",
        "  }",
        "}",
        "",
        string.format("traits:    %s", table.concat(names, ", ")),
        string.format("attitudes: %s", table.concat(attitudes, ", ")),
        "language:  a language name, or its id. Any language every hero already",
        "           knows is not a valid native language and is ignored.",
        "interest:  1-4 at the start. patience: 1-5. impression: 1 and up.",
    }

    return table.concat(lines, "\n")
end

--- Read one side's traits, dropping anything unknown or already spent.
--- @param entries any
--- @param kind string for the skip message
--- @param used table<string, boolean> mutated as traits are taken
--- @param messages string[]
--- @return NEGTrait[]
local function ImportTraits(entries, kind, used, messages)
    local rows = {}
    if type(entries) ~= "table" then
        return rows
    end

    for _, entry in ipairs(entries) do
        local raw = entry
        if type(entry) == "table" then
            raw = entry.trait or entry.name or entry.id
        end

        local traitId = NEGRules.ResolveTrait(raw)
        if traitId == nil then
            messages[#messages + 1] = string.format("Skipped unknown %s \"%s\".",
                kind, tostring(raw))
        elseif used[traitId] then
            messages[#messages + 1] = string.format("Skipped %s \"%s\": already used.",
                kind, NEGRules.TraitName(traitId))
        else
            local note = ""
            if type(entry) == "table" and type(entry.note) == "string" then
                note = entry.note
            end

            used[traitId] = true
            rows[#rows + 1] = NEGTrait.CreateNew{
                trait = traitId,
                note = note,
            }
        end
    end

    return rows
end

--- Turn pasted JSON into a negotiation at the root of the library. Nothing
--- that fails stops anything else: a bad trait costs that trait, and the
--- negotiation still lands.
--- @param text string
--- @return {ok: boolean, defid: string|nil, name: string|nil, messages: string[]}
function NEGDefinition.ImportFromJson(text)
    local messages = {}

    if type(text) ~= "string" or trim(text) == "" then
        return { ok = false, messages = { "Nothing to import." } }
    end

    --FromJson reports success even for malformed input, so the shape is what
    --gets checked rather than the flag it hands back.
    local parsed = dmhub.FromJson(text)
    local data = type(parsed) == "table" and parsed.result or nil
    if type(data) ~= "table" then
        return { ok = false, messages = { "That is not valid JSON." } }
    end

    if type(data.name) ~= "string" or trim(data.name) == "" then
        return { ok = false, messages = { "No negotiation name found. Is this the right JSON?" } }
    end

    local name = UniqueName(trim(data.name))
    if name ~= trim(data.name) then
        messages[#messages + 1] = string.format("Renamed to \"%s\": that name was taken.", name)
    end

    local attitudeId = NEGRules.ResolveAttitude(data.attitude) or NEGDefinition.attitudeId

    --The type default has to name a real attitude, and does; falling back to
    --the catalog's first entry keeps the import from reading off a nil if it
    --ever stops doing so.
    local attitude = NEGRules.AttitudeById(attitudeId) or NEGRules.attitudes[1]
    attitudeId = attitude.id

    if data.attitude ~= nil and NEGRules.ResolveAttitude(data.attitude) == nil then
        messages[#messages + 1] = string.format("Unknown attitude \"%s\"; used %s.",
            tostring(data.attitude), attitude.text)
    end

    local def = NEGDefinition.CreateNew{
        name = name,
        npcName = cond(type(data.npc) == "string", data.npc, ""),
        summary = cond(type(data.summary) == "string", data.summary, ""),
        attitudeId = attitudeId,
        interest = NEGConstants.Clamp(data.interest or attitude.interest,
            NEGConstants.startInterestMin, NEGConstants.startInterestMax),
        patience = NEGConstants.Clamp(data.patience or attitude.patience,
            NEGConstants.startPatienceMin, NEGConstants.startPatienceMax),
        impression = NEGConstants.Clamp(data.impression or NEGConstants.impressionDefault,
            NEGConstants.impressionMin, NEGConstants.impressionMax),
    }

    if type(data.language) == "string" and trim(data.language) ~= "" then
        local needle = string.lower(trim(data.language))
        local matched = nil
        for _, option in ipairs(NEGRules.LanguageOptions()) do
            if string.lower(option.id) == needle or string.lower(option.text) == needle then
                matched = option.id
            end
        end
        if matched ~= nil then
            def.languageId = matched
        else
            messages[#messages + 1] = string.format(
                "Skipped language \"%s\": not a language an NPC can natively speak here.",
                tostring(data.language))
        end
    end

    local used = {}
    def.motivations = ImportTraits(data.motivations, "motivation", used, messages)
    def.pitfalls = ImportTraits(data.pitfalls, "pitfall", used, messages)

    if type(data.offers) == "table" then
        local offers = EmptyOffers()
        for interest = NEGConstants.scaleMin, NEGConstants.scaleMax do
            local value = data.offers[tostring(interest)] or data.offers[interest]
            if type(value) == "string" then
                offers[interest + 1] = value
            end
        end
        def.offers = offers
    end

    if #def.motivations < NEGConstants.motivationsExpected then
        messages[#messages + 1] = "Fewer than two motivations; the rules ask for at least two."
    end
    if #def.pitfalls < NEGConstants.pitfallsExpected then
        messages[#messages + 1] = "No pitfalls; the rules ask for at least one."
    end

    NEGDefinition.Mutate("Import negotiation", function(defs)
        defs[def:GetID()] = def
    end)

    return { ok = true, defid = def:GetID(), name = name, messages = messages }
end

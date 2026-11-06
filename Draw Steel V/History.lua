local mod = dmhub.GetModLoading()

--History: the record of what changed the table, which replaces the Action Log.
--This file is the store: one shared document per map, written at the source of
--each event and read by the tray. It never reads chat. The design and the costs
--behind these choices are in docs/action-log-design (BUILD-PLAN.md, PROBE-0.1.md).
--
--The document holds:
--  entries:    {[key] = json string}, one per event. The key starts with the time,
--              so sorting the keys sorts the events without parsing any of them.
--  encounters: {[combat guid] = time of its first entry}, for retention.
--
--Each entry is a JSON string, not a table, on purpose. BeginChange and
--CompleteChange copy and compare every value in the document, so nested entries
--cost 670 ms a write at 300 entries; a string is one value, which costs 4 ms.
--The document is not registered for checkpoints: Revert Turn must not erase it.

--- One event in History. Stored as JSON, so plain data only: no game types, no tokens.
--- @class HistoryEntry
--- @field id string Unique id. A second write with the same id and t replaces the first.
--- @field t number Server time in milliseconds when it happened; sets its place in the list.
--- @field kind string What sort of event this is, e.g. "action".
--- @field map string Id of the map it happened on.
--- @field encounter? string Guid of the combat it happened in; nil out of combat.
--- @field round? integer The combat round.
--- @field turn? integer Running turn number within the combat.
--- @field owner? HistoryCreature Whose turn it was; nil between turns.
--- @field actor? HistoryCreature Who acted.
--- @field targets? HistoryCreature[] Who it was aimed at.
--- @field ability? {name: string, icon: string|nil, action: string|nil} What was used.
--- @field roll? {total: number, low: number|nil, high: number|nil, edges: number, banes: number, tier: number} The power roll.

History = {
    --Entries kept per map, oldest culled first. Why 500: PROBE-0.1.md.
    hardCap = 500,
}

--Off by default until the last stage of the build; on for a whole game at once,
--so every client records and shows the same thing. No editor: it has no place in
--Settings until the switch-over. Turn it on with
--dmhub.SetSettingValue("historyenabled", true).
local g_enabledSetting = setting{
    id = "historyenabled",
    storage = "game",
    default = false,
}

--- True if History is on in this game. Cheap enough to ask every frame.
--- @return boolean
function History.Enabled()
    return g_enabledSetting:Get() == true
end

--- The document id for a map's History.
--- @param mapid string
--- @return string
function History.DocId(mapid)
    return "history-" .. mapid
end

--- The path to monitor for changes to a map's History (monitorGame on a panel).
--- @param mapid string
--- @return string
function History.DocPath(mapid)
    return mod:GetDocumentPath(History.DocId(mapid))
end

--Zero-padded so that keys sort as text in time order.
local function KeyPrefix(t)
    return string.format("%013d", math.floor(t))
end

local function EntryKey(entry)
    return KeyPrefix(entry.t) .. "-" .. entry.id
end

--Drops everything from before the previous encounter, then enough of the oldest
--entries to fit the hard cap. Out-of-combat entries between encounters go with
--the older encounter, so what stays is this encounter, the last, and between.
local function Cull(data)
    local encounters = data.encounters
    local entries = data.entries

    local starts = {}
    for id, t in pairs(encounters) do
        starts[#starts + 1] = {id = id, t = t}
    end
    if #starts > 2 then
        table.sort(starts, function(a, b) return a.t > b.t end)
        local keepFrom = KeyPrefix(starts[2].t)
        for i = 3, #starts do
            encounters[starts[i].id] = nil
        end
        for key in pairs(entries) do
            if key < keepFrom then
                entries[key] = nil
            end
        end
    end

    local keys = {}
    for key in pairs(entries) do
        keys[#keys + 1] = key
    end
    if #keys > History.hardCap then
        table.sort(keys)
        for i = 1, #keys - History.hardCap do
            entries[keys[i]] = nil
        end
    end
end

local function Write(entry)
    local packed = dmhub.ToRawJson(entry)
    local doc = mod:GetDocumentSnapshot(History.DocId(entry.map))
    doc:BeginChange()
    local data = doc.data
    if type(data.entries) ~= "table" then
        data.entries = {}
    end
    if type(data.encounters) ~= "table" then
        data.encounters = {}
    end
    data.entries[EntryKey(entry)] = packed
    if entry.encounter ~= nil and data.encounters[entry.encounter] == nil then
        data.encounters[entry.encounter] = entry.t
    end
    Cull(data)
    doc:CompleteChange("History", {undoable = false})
end

--- Adds an entry to its map's History. Fills in id and t if they are missing. Whoever
--- calls this is the one client that writes the entry: call it from code that runs on
--- exactly one client. Safe from hot combat code: it can fail, the game carries on.
--- @param entry HistoryEntry
--- @return boolean written
function History.Write(entry)
    if mod.unloaded or not History.Enabled() then
        return false
    end
    entry.id = entry.id or dmhub.GenerateGuid()
    entry.t = entry.t or dmhub.serverTimeMilliseconds
    local ok, err = pcall(Write, entry)
    if not ok then
        dmhub.Debug(string.format("History: failed to write entry: %s", tostring(err)))
    end
    return ok
end

--- A map's entry keys, oldest first. Parses nothing, so it is cheap: fetch the
--- entries you are about to show with History.Entry.
--- @param mapid string
--- @return string[]
function History.Keys(mapid)
    local keys = {}
    local entries = mod:GetDocumentSnapshot(History.DocId(mapid)).data.entries
    if type(entries) == "table" then
        for key in pairs(entries) do
            keys[#keys + 1] = key
        end
        table.sort(keys)
    end
    return keys
end

--Parsed entries by key, with the string each came from: an entry rewritten under
--the same key must not show its old self. Entries that left the document stay here
--until the map changes, which is a few hundred small tables at worst.
local g_parsed = {}
local g_parsedMap = nil

--- One entry, parsed on first use. Nil if the key is gone or the entry is unreadable.
--- @param mapid string
--- @param key string
--- @return HistoryEntry|nil
function History.Entry(mapid, key)
    if g_parsedMap ~= mapid then
        g_parsed = {}
        g_parsedMap = mapid
    end
    local entries = mod:GetDocumentSnapshot(History.DocId(mapid)).data.entries
    local raw = type(entries) == "table" and entries[key] or nil
    if raw == nil then
        return nil
    end
    local parsed = g_parsed[key]
    if parsed == nil or parsed.raw ~= raw then
        local ok, decoded = pcall(dmhub.FromJson, raw)
        if not ok or not decoded.success then
            return nil
        end
        parsed = {raw = raw, entry = decoded.result}
        g_parsed[key] = parsed
    end
    return parsed.entry
end

--- Empties a map's History, for everyone.
--- @param mapid string
function History.Clear(mapid)
    local doc = mod:GetDocumentSnapshot(History.DocId(mapid))
    doc:BeginChange()
    doc.data.entries = nil
    doc.data.encounters = nil
    doc:CompleteChange("Clear History", {undoable = false})
end

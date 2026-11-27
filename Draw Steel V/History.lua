local mod = dmhub.GetModLoading()

--History's words are in HistoryText.lua, which loads before this file.
local T = UIText.T

--History: the record of what changed the table, which replaces the Action Log.
--This file is the store: one shared document per map, written at the source of
--each event and read by the tray. It never reads chat. The design behind these
--choices is in docs/action-log-design.
--
--The document holds:
--  entries:    {[key] = json string}, one per event. The key starts with the time,
--              so sorting the keys sorts the events without parsing any of them.
--  encounters: {[combat guid] = time of its first entry}, for retention.
--  hovers:     {[id] = text}, the roll dialog's hover text for each modifier an entry
--              names, stored once however many entries name it.
--  hoverused:  {[id] = time of the last entry written with it}, for retention.
--
--Each entry is a JSON string, not a table, on purpose. BeginChange and
--CompleteChange copy and compare every value in the document, so nested entries
--make each write slow once there are a few hundred; a string is one value, and cheap.
--The document is not registered for checkpoints: Revert Turn must not erase it.

--- One event in History. Stored as JSON, so plain data only: no game types, no tokens.
--- @class HistoryEntry
--- @field id string Unique id. A second write with the same id and t replaces the first.
--- @field t number Server time in milliseconds when it happened; sets its place in the list.
--- @field kind string What sort of event this is, e.g. "action".
--- @field map string Id of the map it happened on.
--- @field encounter? string Guid of the combat it happened in; nil out of combat.
--- @field mode? string Out of combat: the game mode's id when it was not Exploration, e.g. "respite".
--- @field round? integer The combat round.
--- @field turn? integer Running turn number within the combat.
--- @field owner? HistoryCreature Whose turn it was; nil between turns.
--- @field actor? HistoryCreature Who acted.
--- @field targets? HistoryCreature[] Who it was aimed at.
--- @field ability? {name: string, icon: string|nil, action: string|nil, free: boolean|nil, area: boolean|nil, villainaction: string|nil, triggertext: string|nil} What was used; triggertext is a triggered action's Trigger line; villainaction is the stat block slot, "Villain Action 1"; the tag reads only "Villain Action".
--- @field player? string On an action: the player who used it. Nil means the Director.
--- @field roll? {total: number, low: number|nil, high: number|nil, edges: number, banes: number, tier: number, natural: number|nil, characteristic: {name: string, value: number}|nil, bonus: number|nil, sources: HistoryEdgeSource[]|nil, hidden: boolean|nil, revealed: boolean|nil, overridden: {by: string|nil, dicetier: number}|nil} The power roll. overridden: someone chose the tier after the dice landed. hidden: the players could not see it; revealed: the Director has since shown it to them. natural is the dice; bonus is what the total adds past the dice, the characteristic and an edge or bane; sources are what gave it its edges and banes.
--- @field rolltriggers? {name: string, who: HistoryCreature|nil, targets: table[]}[] On an action: triggered actions used from its roll dialog, each target with delta (damage it changed) or edges, banes and tiers.
--- @field when? "before"|"after" On an automatic trigger: whether it came before or after its action's roll; nil when that action rolls nothing.
--- @field cause? string On an automatic trigger or a minions line: id of the cast behind it. On a test or table line: the ability that asked for the roll, whose row it goes under.
--- @field landedby? HistoryCreature On an automatic trigger: the creature that fell on its target.
--- @field aliases? string[] On an action: ids of casts inside it that have no row of their own.
--- @field family? string On a line (kind "line"): "damage", "heal", "temporarystamina",
--- "condition", "ended", "save", "persistence", "encounterend", "threshold", "minions",
--- "resource", "malice", "globalresource", "moved", "test", "dice", "drawsteel",
--- "respite", "levelup", "montagetest", "montagethreat", "montageend", "montagecounter",
--- "negotiation", "downtime", "table", "award", "staminaset", "reinforcements", "reveal", "reverted",
--- "strained", "captain" or "note" (a note card posted outside any action: name is its title, causetext its detail).
--- @field spoilerkey? string On a reveal line: the spoilered modifier's key (PowerRollSpoilers.Key); the Director's eye on it hides or shows the line.
--- @field arrivals? {who: HistoryCreature, name: string, count: integer}[] On a reinforcements line: who arrived, counted by stat block name.
--- @field byplayer? boolean On a line: a player made this change by hand; it turns the Director's badge gold.
--- @field counter? string On a montagecounter line: "successes" or "failures".
--- @field sub? string On a negotiation line: "began", "argument", "pitfall", "read", "reveal", "adjust" or "ended". On a downtime line: "milestone" or "completed". On an award line: "victories", "item", "title", "renown" or "wealth".
--- @field raw? boolean On a negotiation line: the Director was showing the numbers on the stage.
--- @field playercause? string On a negotiation line: the cause text players read when raw is false.
--- @field directoronly? boolean On a negotiation line: players get no line.
--- @field hiddenfromplayers? boolean The Director chose Hide from players: players get no row.
--- @field reverted? string Revert Turn or Turn Rewind undid this: the revertkey of the line that says so. The row fades, tagged Reverted, and drops out of the totals.
--- @field revertkey? string On a reverted line: the key its reverted rows carry.
--- @field wholeturn? boolean On a reverted line: Revert Turn undid the whole turn, so the turn redone after it starts afresh under its own heading.
--- @field trait? string On a negotiation line: the motivation or pitfall it is about.
--- @field text? string On a negotiation argument: what the Hero said.
--- @field cue? string On a negotiation argument: the stage's cue for how it landed.
--- @field which? string On a negotiation adjust line: "interest" or "patience".
--- @field limit? number On a montagecounter line: how many the montage needs.
--- @field level? integer On a levelup line: the Level reached.
--- @field heroesFirst? boolean On a drawsteel line: the heroes go first.
--- @field rolled? number On a drawsteel line: the Draw Steel die, when one was rolled.
--- @field total? number On a test or dice line: what the roll came to. On a table line: what the dice came to, before any override.
--- @field dice? number[] On a dice or table line: each die as it landed.
--- @field result? string On a table line: the row's full text (the row picked, after an override).
--- @field overridden? string On a table line: the roll dialog's override message, when the result was overridden.
--- @field project? string On a table line: the downtime project whose event the Director rolled.
--- @field quantity? number On an item award line: how many.
--- @field tier? integer On a dice line from the Power Roll tile: its tier.
--- @field edges? integer On a dice line: edges on the roll.
--- @field banes? integer On a dice line: banes on the roll.
--- @field roller? string On a dice or table line with no creature: who rolled ("Director" for the Director).
--- @field moved? table On a moved line: what happened; see the moved field of HistoryCreature.
--- @field amount? number On a resource line (or a heal with its Recovery): the change, negative when spent.
--- @field resourceid? string On a resource line or a Recovery heal: the resource, for Undo.
--- @field refreshtype? string On a resource line or a Recovery heal: how it refreshes, for Undo.
--- @field undone? boolean On a resource line or a Recovery heal: Undo was pressed.
--- @field undoneby? string On an undone line: the claim of the client that gives the resource back.
--- @field quiet? boolean On a Malice line: it counts in the round heading but shows no line.
--- @field strained? boolean On a strained line: it became strained, or stopped being.
--- @field squad? string On a captain line: the squad it now leads.
--- @field provoker? HistoryCreature On a free strike for moving away: who moved away.
--- @field costs? table<string, {amount: number, style: string, icon: string|nil}> On an action: resources it spent; icon is a heroic resource's.
--- @field gains? table<string, {amount: number, style: string, icon: string|nil}> On an action: resources it gave its user, shaped like costs.
--- @field state? string On a threshold line: "winded", "dying" or "killed".
--- @field killed? integer On a minions line: how many died.
--- @field left? integer On a minions line: how many of the squad are left.
--- @field each? number On a minions line: one minion's Stamina.
--- @field damage? number On a minions line: the damage behind the deaths.
--- @field mk? string On a minions line: the squad's Monster Knowledge key. On a non-Hero's staminaset or temporarystamina line, a damage line with soaked (and a row target's pool or soaked): its key, "" when Monster Info can't learn it; players see the numbers only when its Stamina bar would show them the number.
--- @field recovered? string On a heal line: "winded" or "dying" if the heal ended it.
--- @field name? string On a condition, save, persistence or test line: what it is about (a test: "Might test"). On a table line: the table. On an item or title award line: the item or title. On a reinforcements line: the wave. On a reveal line: the modifier.
--- @field names? string[] On an ended line: what ended.
--- @field ended? {who: HistoryCreature, names: string[], hidden: table<string, boolean>|nil}[] On an encounter's closing line: what ended, by creature.
--- @field secret? boolean On a condition line: an effect hidden from enemies, on a creature off the heroes' side. Players don't see the line.
--- @field hidden? table<string, boolean> On an ended line: names players may not see.
--- @field secretroll? boolean For a player only: the roll was hidden from players, so it was taken out (History.Entry).
--- @field privacy? {hidden: boolean, tower: boolean|nil, userid: string|nil, cause: string|nil, revealed: boolean|nil} On a test, dice, table or save line: a roll not everyone saw. GM only reaches its roller and the Director; a Dice Tower roll's result only the Director. cause is the line under it without the result; the Director's eye sets revealed.
--- @field icon? string On a condition line: its icon.
--- @field iscondition? boolean On a condition line: a condition, not some other effect.
--- @field ref? string On a condition line: the ongoing effect's instance id (see History.IsActive).
--- @field cid? string On a condition line: the condition's id, when it is a bare condition.
--- @field start? HistoryStart On a lone trigger's line in the tray: the target's start it shows.
--- @field duration? string On a condition line: "save ends", "EoT" or "EoE".
--- @field passed? boolean On a save line: whether it was made.
--- @field who? HistoryCreature On a line: who it happened to.
--- @field causetext? string On a line: the small text under it.
--- @field trigger? string On a resource line an automatic trigger wrote: the trigger's name.
--- @field triggerby? HistoryCreature On such a line: whose trigger it is.
--- @field messages? string[] On an action or automatic trigger: notes its author typed on its steps, as written.
--- @field taken? number On a damage line: what landed.
--- @field healed? number On a heal line: what was regained.
--- @field soaked? number On a damage line: how much of it temporary Stamina took.
--- @field damagetype? string On a damage line: the type, if it has one.
--- @field before? number On a temporary Stamina line: the pool before. On a victories, renown or wealth award line: the score before. On a staminaset line: Stamina before.
--- @field after? number On a temporary Stamina line: the pool after. On a victories, renown or wealth award line: the score after. On a staminaset line: Stamina after.

History = {
    --Entries kept per map, oldest culled first: room for two big encounters while each
    --write stays cheap.
    hardCap = 500,
    --Entries kept across every map in the game. Each client downloads every map's History
    --when it joins, so the maps written longest ago are cleared past this.
    gameCap = 1000,
    --An encounter counts towards dropping older ones only once it has this many entries,
    --so a combat started by mistake and ended at once does not cost the last real fight.
    minEncounterEntries = 5,
    --Set by the tray: runs when the setting changes.
    --- @type nil|function
    OnEnabledChanged = nil,
}

--History records in every game and is what everyone sees. A player who prefers the old
--Action Log can bring it back for themselves; History keeps recording meanwhile, so turning
--it back on loses nothing.
local g_oldLogSetting = setting{
    id = "history:useoldlog",
    description = T("history.settings.use_old_log_name"),
    help = T("history.settings.use_old_log_help"),
    editor = "check",
    default = false,
    storage = "preference",
    section = "general",
    onchange = function()
        if History.OnEnabledChanged ~= nil then
            History.OnEnabledChanged()
        end
    end,
}

--The Director's way out: with this off nothing is recorded and everyone sees the old Action
--Log, so a problem in a live game can be stopped without a code change.
local g_recordSetting = setting{
    id = "history:record",
    description = T("history.settings.record_name"),
    help = T("history.settings.record_help"),
    editor = "check",
    default = true,
    storage = "game",
    section = "game",
    classes = {"dmonly"},
    onchange = function()
        if History.OnEnabledChanged ~= nil then
            History.OnEnabledChanged()
        end
    end,
}

--- A whole number as %d writes it, for a number in History's words: an entry read back
--- from JSON can hold 3.0, which tostring (and so UIText.T) would show as "3.0".
--- @param n number
--- @return string
function History.Int(n)
    return string.format("%d", n)
end

--- True if a game system layered on these rules says History can't describe its play
--- (Crows: no winded, Armor Defense, Wounds). Its module sets
--- `GameSystem.historyNotSupported = true`; that game then keeps the old Action Log.
--- @return boolean
function History.NotSupported()
    return rawget(GameSystem, "historyNotSupported") == true
end

--- True unless the game system doesn't support History or the Director turned Record
--- History off: then nothing is recorded.
--- @return boolean
function History.Enabled()
    return not History.NotSupported() and g_recordSetting:Get() ~= false
end

--- True if this user sees the old Action Log: their own choice, or History not recording
--- in this game.
--- @return boolean
function History.UsingOldLog()
    return not History.Enabled() or g_oldLogSetting:Get() == true
end

--- The id History files an entry under when there is no map at all (nothing a token is on,
--- no current map): one game-wide record, offered in the map switcher as "Table".
History.NO_MAP = "game"

--- The map History is following: the current map, or the game-wide record when there is none.
--- @return string
function History.CurrentMap()
    return game.currentMapId or History.NO_MAP
end

--- The document id for a map's History.
--- @param mapid string
--- @return string
function History.DocId(mapid)
    return "history-" .. mapid
end

--- One roll source as text, so two lists can be compared: equal keys mean the same thing,
--- with the same owner, doing the same to the roll.
--- @param source HistoryEdgeSource
--- @return string
function History.SourceKey(source)
    local flags = {}
    for _, flag in ipairs({"ignore", "hand", "autosuccess", "autofailure", "nottierthree", "nottierone"}) do
        flags[#flags + 1] = source[flag] and flag or ""
    end
    return string.format("%s|%s|%d|%d|%d|%d|%d|%d|%s", source.name or "", source.who ~= nil and source.who.id or "",
        source.edges or 0, source.banes or 0, source.removedEdges or 0, source.removedBanes or 0, source.tiers or 0,
        source.bonus or 0, table.concat(flags, ","))
end

--- The path to monitor for changes to a map's History (monitorGame on a panel).
--- @param mapid string
--- @return string
function History.DocPath(mapid)
    return mod:GetDocumentPath(History.DocId(mapid))
end

--Zero-padded so that keys sort as text in time order.
local function KeyPrefix(stamp)
    return string.format("%013d", math.floor(stamp))
end

local function EntryKey(entry)
    return KeyPrefix(entry.t) .. "-" .. entry.id
end

--Drops everything from before the previous encounter, then enough of the oldest
--entries to fit the hard cap. Out-of-combat entries between encounters go with
--the older encounter, so what stays is this encounter, the last, and between.
local function Cull(data)
    local encounters = data.encounters or {}
    local entries = data.entries

    --counts: entries written per encounter. One with no count is from before counts were
    --kept, and counts as a real encounter.
    local counts = data.counts or {}
    local starts = {}
    for id, firstStamp in pairs(encounters) do
        if counts[id] == nil or counts[id] >= History.minEncounterEntries then
            starts[#starts + 1] = {id = id, t = firstStamp}
        end
    end
    if #starts > 2 then
        table.sort(starts, function(left, right) return left.t > right.t end)
        local keepFrom = KeyPrefix(starts[2].t)
        for id, firstStamp in pairs(encounters) do
            if firstStamp < starts[2].t then
                encounters[id] = nil
                counts[id] = nil
            end
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

--A short id for a hover text; equal texts get equal ids, so each is stored once.
--The "h" matters: an all-digit id is a number key to the document, which then saves the
--whole hovers table as a list and loses every other text.
local function TextHash(text)
    local hash = 5381
    for i = 1, #text do
        hash = (hash * 33 + string.byte(text, i)) % 4294967296
    end
    return string.format("h%08x", hash)
end

--Moves each roll dialog hover text in an entry (a hovertext field anywhere in it) into the
--map's shared hovers, leaving its id in hover. used keeps the time each id was last
--written, so CullHoverTexts can drop texts no kept entry points at.
local function StoreHoverTexts(node, hovers, used, stamp)
    for _, value in pairs(node) do
        if type(value) == "table" then
            StoreHoverTexts(value, hovers, used, stamp)
        end
    end
    local text = node.hovertext
    if type(text) == "string" then
        local id = TextHash(text)
        while hovers[id] ~= nil and hovers[id] ~= text do
            id = id .. "x"
        end
        hovers[id] = text
        used[id] = math.max(used[id] or 0, stamp)
        node.hovertext = nil
        node.hover = id
    end
end

--Drops the hover texts that only entries older than every kept one used.
local function CullHoverTexts(data)
    local oldest = nil
    for key in pairs(data.entries) do
        if oldest == nil or key < oldest then
            oldest = key
        end
    end
    local keepFrom = oldest ~= nil and tonumber(string.sub(oldest, 1, 13)) or math.huge
    if type(data.hoverused) ~= "table" or type(data.hovers) ~= "table" then
        return
    end
    for id, lastUsed in pairs(data.hoverused) do
        if lastUsed < keepFrom then
            data.hoverused[id] = nil
            data.hovers[id] = nil
        end
    end
end

--Writes every entry waiting for one map, in one change to its document.
--A client still syncing a game reads an existing document as new and empty, and a write to
--it then replaces the whole document in the cloud. So a document that reads as new is only
--written once the game has been entered (EnterGame, or a reload made while in a game).
local g_gameEntered = dmhub.inGame == true
dmhub.RegisterEventHandler("EnterGame", function()
    g_gameEntered = true
end)

--Which maps have History, when each was last written and how many entries it keeps, so the
--game-wide cap and deleted maps can be found without opening every map's document. Each map
--is its own root key: two clients writing different maps never send the same key.
local INDEX_DOC = "history-index"

local function NoteMapInIndex(mapid, entries)
    local count = 0
    for _ in pairs(entries) do
        count = count + 1
    end
    local doc = mod:GetDocumentSnapshot(INDEX_DOC)
    if not g_gameEntered and doc.isnew then
        return
    end
    doc:BeginChange()
    doc.data[mapid] = {t = dmhub.serverTimeMilliseconds, n = count}
    doc:CompleteChange("History index", {undoable = false})
end

local function WriteEntries(mapid, list)
    local doc = mod:GetDocumentSnapshot(History.DocId(mapid))
    doc:BeginChange()
    local data = doc.data
    if type(data.entries) ~= "table" then
        data.entries = {}
    end
    --the other root tables are made only when something goes in them: a new document sends
    --each root key whole, so an empty one from this client would wipe another client's.
    local hovers, hoverused = data.hovers, data.hoverused
    --a list here is a table saved before ids had their "h" (see TextHash): start it again.
    local hoversUsable = type(hovers) == "table" and type(hoverused) == "table" and hovers[1] == nil
    if not hoversUsable then
        hovers, hoverused = {}, {}
    end
    for _, entry in ipairs(list) do
        StoreHoverTexts(entry, hovers, hoverused, entry.t)
        local key = EntryKey(entry)
        local isNew = data.entries[key] == nil
        data.entries[key] = dmhub.ToRawJson(entry)
        if entry.encounter ~= nil then
            if type(data.encounters) ~= "table" then
                data.encounters = {}
            end
            if type(data.counts) ~= "table" then
                data.counts = {}
            end
            if data.encounters[entry.encounter] == nil then
                data.encounters[entry.encounter] = entry.t
                --an encounter new to this map starts its count at zero; an older one has none.
                data.counts[entry.encounter] = 0
            end
            --a rewrite of an entry (an Undo, a reveal) is not another entry.
            if isNew and data.counts[entry.encounter] ~= nil then
                data.counts[entry.encounter] = data.counts[entry.encounter] + 1
            end
        end
    end
    if not hoversUsable and (next(hovers) ~= nil or data.hovers ~= nil) then
        data.hovers = hovers
        data.hoverused = hoverused
    end
    Cull(data)
    CullHoverTexts(data)
    doc:CompleteChange("History", {undoable = false})
    NoteMapInIndex(mapid, data.entries)
end

--Entries waiting for the next frame, so an aura that hits eight creatures is one
--write, not eight. Nothing here touches the document from inside a hit.
local g_waiting = {}

local Flush

--When this client last checked the game-wide budget; it checks at most once a minute.
local g_lastBudgetCheck = 0
local BUDGET_CHECK_MS = 60000

--Clears the History of maps that no longer exist, then, past History.gameCap entries across
--the game, of the maps written longest ago. The map just written, the one being looked at
--and the game-wide record are never cleared.
local KeepWithinBudget = function(justWritten)
    local now = dmhub.serverTimeMilliseconds
    if now - g_lastBudgetCheck < BUDGET_CHECK_MS or not g_gameEntered or #game.maps == 0 then
        return
    end
    g_lastBudgetCheck = now
    local index = mod:GetDocumentSnapshot(INDEX_DOC)
    local rows = {}
    local total = 0
    local gone = {}
    for mapid, row in pairs(index.data) do
        if type(row) == "table" and type(row.n) == "number" then
            if mapid ~= History.NO_MAP and game.GetMap(mapid) == nil then
                gone[#gone + 1] = mapid
            else
                rows[#rows + 1] = {map = mapid, t = row.t or 0, n = row.n}
                total = total + row.n
            end
        end
    end
    local keep = {[justWritten] = true, [History.NO_MAP] = true, [History.CurrentMap()] = true}
    table.sort(rows, function(a, b) return a.t < b.t end)
    for _, row in ipairs(rows) do
        if total <= History.gameCap then
            break
        end
        if not keep[row.map] then
            gone[#gone + 1] = row.map
            total = total - row.n
        end
    end
    if #gone == 0 then
        return
    end
    for _, mapid in ipairs(gone) do
        History.Clear(mapid)
    end
    index:BeginChange()
    for _, mapid in ipairs(gone) do
        index.data[mapid] = nil
    end
    index:CompleteChange("History index", {undoable = false})
end

--Writes what is waiting, by map. A map whose document can't be trusted yet keeps its
--entries for the next try.
Flush = function()
    local waiting = g_waiting
    g_waiting = {}
    if mod.unloaded then
        return
    end
    if not dmhub.inGame then
        --out of a game there is nowhere to write; the next game must be entered afresh.
        g_gameEntered = false
        return
    end
    local byMap = {}
    for _, entry in ipairs(waiting) do
        byMap[entry.map] = byMap[entry.map] or {}
        table.insert(byMap[entry.map], entry)
    end
    for mapid, list in pairs(byMap) do
        if not g_gameEntered and mod:GetDocumentSnapshot(History.DocId(mapid)).isnew then
            for _, entry in ipairs(list) do
                g_waiting[#g_waiting + 1] = entry
            end
        else
            local ok, err = pcall(WriteEntries, mapid, list)
            if not ok then
                dmhub.Debug(string.format("History: failed to write entries: %s", tostring(err)))
            end
        end
    end
    if #g_waiting > 0 then
        dmhub.Schedule(0.5, Flush)
    end
    for mapid in pairs(byMap) do
        local ok, err = pcall(KeepWithinBudget, mapid)
        if not ok then
            dmhub.Debug(string.format("History: failed to check the budget: %s", tostring(err)))
        end
        break
    end
end

--The last stamp History.Write gave an entry on this client.
local g_lastStamp = 0

--- Adds an entry to its map's History on the next frame. Fills in id and t if they are
--- missing. Whoever calls this is the one client that writes the entry: call it from
--- code that runs on exactly one client. Safe from hot combat code: it can fail, the
--- game carries on.
--- @param entry HistoryEntry
--- @return boolean accepted
function History.Write(entry)
    if mod.unloaded or not History.Enabled() then
        return false
    end
    entry.id = entry.id or dmhub.GenerateGuid()
    --a token on no map (a Hero away from the table) files under the map being looked at, and
    --with no map at all, under the game-wide record.
    entry.map = entry.map or History.CurrentMap()
    --entries sort by their stamp, so two written in the same millisecond would fall in a
    --random order: each new stamp is at least one past the last this client gave out.
    if entry.t == nil then
        local now = dmhub.serverTimeMilliseconds
        if now <= g_lastStamp then
            now = g_lastStamp + 1
        end
        g_lastStamp = now
        entry.t = now
    end
    g_waiting[#g_waiting + 1] = entry
    if #g_waiting == 1 then
        dmhub.Schedule(0.01, Flush)
    end
    return true
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

--Parsed entries by map, then key, with the string each came from: an entry rewritten
--under the same key must not show its old self. Kept per map so the rail badge, which
--reads every map, does not throw away the open window's map. A few hundred small tables
--a map at worst.
--- @type table<string, table<string, {raw: string, entry: HistoryEntry|nil, staminaKeys: string[]|nil, stamina: string|nil}>>
local g_parsed = {}
--Whether the entries in g_parsed were cut down for a player (History.Entry).
local g_parsedForPlayers = nil

--A list of names without the ones in hidden; nil when none are left.
local function WithoutHidden(names, hidden)
    if names == nil or hidden == nil then
        return names
    end
    local kept = {}
    for _, name in ipairs(names) do
        if not hidden[name] then
            kept[#kept + 1] = name
        end
    end
    return #kept > 0 and kept or nil
end

--Drops the hover text ids from roll sources or damage parts, and from the modifiers a
--surge part names as where its surges came from.
local function WithoutHovers(list)
    for _, item in ipairs(list or {}) do
        item.hover = nil
        for _, field in ipairs({"freefrom", "gainedfrom"}) do
            for _, source in ipairs(item[field] or {}) do
                if type(source) == "table" then
                    source.hover = nil
                end
            end
        end
    end
end

--True when players may read this creature's Stamina numbers, as its Stamina bar shows them:
--the game shows enemy Stamina values, or Monster Info has revealed it exactly. mk is the key
--the entry kept ("" for a creature Monster Info can't learn about).
local function StaminaKnown(mk)
    if dmhub.GetSettingValue("enemystambardisplay") == "val" then
        return true
    end
    if mk == "" then
        return false
    end
    local ok, known = pcall(function()
        local knowledge = MonsterKnowledge.StaminaKnowledge(mk, nil)
        return knowledge.visible and knowledge.tier >= 3
    end)
    return ok and known == true
end

--The Monster Knowledge keys of the monsters an entry has Stamina numbers for, or nil.
local function StaminaKeys(entry)
    local keys = nil
    if (entry.family == "staminaset" or entry.family == "temporarystamina" or entry.family == "damage") and entry.mk ~= nil then
        keys = {entry.mk}
    end
    for _, who in ipairs(entry.targets or {}) do
        if (who.pool ~= nil or who.soaked ~= nil) and who.mk ~= nil then
            keys = keys or {}
            keys[#keys + 1] = who.mk
        end
    end
    return keys
end

--What players know of those monsters' Stamina, as a string: a player's parsed entry is cut
--again when it changes.
local function StaminaSignature(keys)
    local parts = {}
    for _, mk in ipairs(keys) do
        parts[#parts + 1] = tostring(StaminaKnown(mk))
    end
    return table.concat(parts, ",")
end

--- True when players may see the Malice pool's changes: in an Encounter of the Week game,
--- whose pool strip shows everyone the Malice total. Elsewhere players see only a Malice
--- ability's banner (its name and cost), which the cost on its action's row matches.
--- @return boolean
function History.PlayersSeeMalice()
    local eotw = rawget(_G, "EncounterOfTheWeekGame")
    local ok, result = pcall(function()
        return eotw ~= nil and eotw.IsEotwGame()
    end)
    return ok and result == true
end

--Makes every creature players could not see nameless and faceless wherever else an entry
--names it: who it collided with, who provoked, whose modifier it was.
--- @param node table
--- @param depth integer
local function MaskUnseen(node, depth)
    if depth > 8 then
        return
    end
    for _, value in pairs(node) do
        if type(value) == "table" then
            if value.unseen ~= nil and value.name ~= nil then
                value.secret = true
                value.img = ""
            end
            MaskUnseen(value, depth + 1)
        end
    end
end

--- True when a roll hidden from players is shown to them anyway: a hero's roll made inside
--- another action (a forced or granted strike). At the table that hero's player rolls it in
--- the open, whichever client rolled the dice.
--- @param entry HistoryEntry
--- @return boolean
function History.RollAlwaysShown(entry)
    return entry.cause ~= nil and entry.actor ~= nil and entry.actor.hero == true
end

--Cuts an entry down to what players may see: no more than they saw live. Done once as
--it is parsed, so no view can show more by mistake. Nil when nothing of it is left to show.
--- @param entry HistoryEntry
--- @return HistoryEntry|nil
local function ForPlayers(entry)
    if entry.hiddenfromplayers then
        return nil
    end
    --Malice lines show players no more than the table does (History.PlayersSeeMalice).
    if entry.family == "malice" and not History.PlayersSeeMalice() then
        return nil
    end
    --a creature players could not see on the map (HistoryCreature.unseen): no line about it,
    --off the target lists, and nameless and faceless where it acted or owned the turn. An
    --ability that reveals a Hidden user clears its actor's unseen as it is recorded, so only
    --a hidden token, a trigger or a remainhidden ability loses the name.
    if entry.kind == "line" and entry.who ~= nil and entry.who.unseen ~= nil then
        return nil
    end
    local actor, owner = entry.actor, entry.owner
    if actor ~= nil and actor.unseen ~= nil then
        actor.secret = true
        actor.img = ""
    end
    if owner ~= nil and owner.unseen ~= nil then
        owner.secret = true
        owner.img = ""
    end
    if entry.targets ~= nil then
        local kept = {}
        for _, who in ipairs(entry.targets) do
            if who.unseen == nil then
                kept[#kept + 1] = who
            end
        end
        entry.targets = kept
    end
    for _, item in ipairs(entry.rolltriggers or {}) do
        local kept = {}
        for _, who in ipairs(item.targets or {}) do
            if who.unseen == nil then
                kept[#kept + 1] = who
            end
        end
        item.targets = kept
    end
    if entry.ended ~= nil then
        local kept = {}
        for _, item in ipairs(entry.ended) do
            if item.who == nil or item.who.unseen == nil then
                kept[#kept + 1] = item
            end
        end
        entry.ended = kept
    end
    --the actor keeps its name unless it stayed unseen (above): it was revealed as it acted.
    entry.actor = nil
    MaskUnseen(entry, 1)
    entry.actor = actor
    --a monster's Stamina numbers, only once players know its Stamina (Monster Info).
    if (entry.family == "staminaset" or entry.family == "temporarystamina") and entry.mk ~= nil
        and not StaminaKnown(entry.mk) then
        return nil
    end
    --a monster's temporary Stamina soak shows its pool, so it goes the same way.
    if entry.family == "damage" and entry.mk ~= nil and not StaminaKnown(entry.mk) then
        entry.soaked = nil
    end
    for _, who in ipairs(entry.targets or {}) do
        if who.mk ~= nil and not StaminaKnown(who.mk) then
            who.pool = nil
            who.soaked = nil
        end
    end
    --effects hidden from enemies, on a creature off the heroes' side.
    if entry.family == "condition" and entry.secret then
        return nil
    end
    if entry.family == "ended" then
        entry.names = WithoutHidden(entry.names, entry.hidden)
        if entry.names == nil then
            return nil
        end
    end
    if entry.ended ~= nil then
        local kept = {}
        for _, item in ipairs(entry.ended) do
            local names = WithoutHidden(item.names, item.hidden)
            if names ~= nil then
                item.names = names
                kept[#kept + 1] = item
            end
        end
        entry.ended = kept
    end
    --a negotiation line: the Director's own corrections never reach players, and the
    --meters read as numbers only if the Director was showing them on the stage.
    if entry.family == "negotiation" then
        if entry.directoronly then
            return nil
        end
        if not entry.raw then
            entry.causetext = entry.playercause
        end
    end
    --a test or dice line rolled out of players' sight, as the chat shows it.
    local privacy = entry.privacy
    if privacy ~= nil and privacy.hidden and not privacy.revealed then
        if not privacy.tower and privacy.userid ~= dmhub.userid then
            return nil
        elseif privacy.tower then
            entry.roll = nil
            entry.dice = nil
            entry.total = nil
            entry.tier = nil
            entry.result = nil
            entry.overridden = nil
            entry.secretroll = true
            entry.causetext = privacy.cause
        end
    end
    local hiddenRoll = entry.roll ~= nil and entry.roll.hidden and not entry.roll.revealed and not History.RollAlwaysShown(entry)
    if hiddenRoll then
        entry.roll = nil
        entry.secretroll = true
        --the triggers used from its roll dialog were out of sight too.
        entry.rolltriggers = nil
    end
    --the roll dialog behind a monster's roll was the Director's: players never saw its hovers.
    --An action keeps its roller in actor; a test or dice line, in who.
    local roller = entry.actor
    if roller == nil and (entry.family == "test" or entry.family == "dice" or entry.family == "table") then
        roller = entry.who
    end
    local monster = roller ~= nil and not roller.hero
    if monster and entry.roll ~= nil then
        WithoutHovers(entry.roll.sources)
    end
    for _, who in ipairs(entry.targets or {}) do
        if who.conds ~= nil then
            local kept = {}
            for _, condition in ipairs(who.conds) do
                if not condition.secret then
                    kept[#kept + 1] = condition
                end
            end
            who.conds = #kept > 0 and kept or nil
        end
        who.ended = WithoutHidden(who.ended, who.endedhidden)
        if hiddenRoll then
            --the tier, its own roll and what made its damage all come from the roll.
            who.tier = nil
            who.roll = nil
            who.sources = nil
            who.parts = nil
        elseif monster then
            WithoutHovers(who.sources)
            WithoutHovers(who.roll ~= nil and who.roll.sources or nil)
            WithoutHovers(who.parts)
        end
    end
    return entry
end

--- One entry, parsed on first use. Nil if the key is gone or the entry is unreadable.
--- @param mapid string
--- @param key string
--- @return HistoryEntry|nil
function History.Entry(mapid, key)
    --the Codex's usual Director check: looking through a token's eyes changes nothing here.
    local forPlayers = not dmhub.isDM
    if g_parsedForPlayers ~= forPlayers then
        g_parsed = {}
        g_parsedForPlayers = forPlayers
    end
    local parsedMap = g_parsed[mapid]
    if parsedMap == nil then
        parsedMap = {}
        g_parsed[mapid] = parsedMap
    end
    local entries = mod:GetDocumentSnapshot(History.DocId(mapid)).data.entries
    local raw = type(entries) == "table" and entries[key] or nil
    if raw == nil then
        return nil
    end
    local parsed = parsedMap[key]
    --a player's cut depends on what Monster Info has revealed since: cut again if that changed.
    local stale = parsed ~= nil and parsed.staminaKeys ~= nil and parsed.stamina ~= StaminaSignature(parsed.staminaKeys)
    if parsed == nil or parsed.raw ~= raw or stale then
        local ok, decoded = pcall(dmhub.FromJson, raw)
        if not ok or not decoded.success then
            return nil
        end
        local entry = decoded.result
        local staminaKeys, stamina = nil, nil
        if forPlayers then
            --read before the cut, which takes the numbers out.
            staminaKeys = StaminaKeys(entry)
            stamina = staminaKeys ~= nil and StaminaSignature(staminaKeys) or nil
            entry = ForPlayers(entry)
        end
        parsed = {raw = raw, entry = entry, staminaKeys = staminaKeys, stamina = stamina}
        parsedMap[key] = parsed
    end
    return parsed.entry
end

--- A modifier's roll dialog hover text, by the id its source keeps in hover. Spoiler markup
--- is kept: format it for the viewer. Nil when the text is gone or was never recorded.
--- @param mapid string
--- @param id string
--- @return string|nil
function History.HoverText(mapid, id)
    local hovers = mod:GetDocumentSnapshot(History.DocId(mapid)).data.hovers
    local text = type(hovers) == "table" and hovers[id] or nil
    return type(text) == "string" and text or nil
end

--Active: a condition or effect a row started that is still on. Several rows can
--name the same one (it was renewed, or applied again after it ended), so only the newest
--of them can be Active. The tray notes every start in time order before it draws.
--- @class HistoryStart
--- @field name string
--- @field icon? string
--- @field ref? string An ongoing effect's instance id.
--- @field cid? string A bare condition's id.

--Newest start by creature and what it is: {[key] = the start's table}.
--- @type table<string, HistoryStart>
local g_newestStart = {}

local function StartKey(whoid, start)
    return string.format("%s|%s", whoid, start.ref or start.cid or start.name)
end

--- Forgets the starts noted so far, before the tray notes them again.
function History.ClearStarts()
    g_newestStart = {}
end

--- Notes that a row started a condition or effect on a creature; later notes win.
--- @param whoid string Token id.
--- @param start HistoryStart
function History.NoteStart(whoid, start)
    g_newestStart[StartKey(whoid, start)] = start
end

--Whether the creature has it now: an effect by its instance, a condition by its id, and
--rows from before either was saved by name.
local function StillHas(creature, start)
    if start.ref ~= nil then
        for _, instance in ipairs(creature:try_get("ongoingEffects", {})) do
            if instance.id == start.ref then
                return not instance:Expired()
            end
        end
        return false
    end
    if start.cid ~= nil then
        return creature:try_get("inflictedConditions", {})[start.cid] ~= nil
    end
    local effects = GetTableCached(CharacterOngoingEffect.tableName)
    for _, instance in ipairs(creature:try_get("ongoingEffects", {})) do
        local info = effects[instance.ongoingEffectid]
        if info ~= nil and info.name == start.name and not instance:Expired() then
            return true
        end
    end
    local conditions = GetTableCached(CharacterCondition.tableName)
    for conditionid in pairs(creature:try_get("inflictedConditions", {})) do
        local info = conditions[conditionid]
        if info ~= nil and info.name == start.name then
            return true
        end
    end
    return false
end

--- Whether a start a row recorded is still on: it is the newest row naming it and the
--- creature has it now. A live read, so call it when a row is drawn, not every frame.
--- @param whoid string Token id.
--- @param start HistoryStart
--- @return boolean
function History.IsActive(whoid, start)
    if g_newestStart[StartKey(whoid, start)] ~= start then
        return false
    end
    local token = dmhub.GetTokenById(whoid)
    if token == nil or token.properties == nil then
        return false
    end
    return StillHas(token.properties, start)
end

--- The first of a creature's starts in a row that is still on, for its Active tag.
--- @param who HistoryCreature
--- @return HistoryStart|nil
function History.ActiveStart(who)
    for _, start in ipairs(who.conds or {}) do
        if History.IsActive(who.id, start) then
            return start
        end
    end
    return nil
end

--- Rewrites an entry that is already in History, for a change to what it says.
--- @param entry HistoryEntry
function History.Rewrite(entry)
    History.Write(entry)
end

--What other clients may have set on a stored entry since this client wrote its copy: the
--Director's Hide and reveal eye, a revert, an Undo.
local function KeepOthersChanges(entry, stored)
    entry.hiddenfromplayers = stored.hiddenfromplayers
    entry.reverted = stored.reverted
    entry.undone = stored.undone
    entry.undoneby = stored.undoneby
    for _, field in ipairs({"roll", "privacy"}) do
        local mine, theirs = entry[field], stored[field]
        if type(mine) == "table" and type(theirs) == "table" then
            mine.revealed = theirs.revealed
        end
    end
end

--- Rewrites an entry from the copy capture kept while it happened (a fall that landed after
--- its row was written, a Recovery joining its heal). What it says comes from that copy; what
--- other clients have set on it since is kept. An entry deleted or culled meanwhile stays gone.
--- @param entry HistoryEntry
function History.RewriteCaptured(entry)
    for _, waiting in ipairs(g_waiting) do
        if waiting == entry then
            --not written yet: the write already waiting carries the change.
            return
        end
    end
    local stored = History.Stored(entry)
    if stored == nil then
        return
    end
    KeepOthersChanges(entry, stored)
    History.Write(entry)
end

--Entry ids rewritten with nothing on this client's screen changing. The tray keeps their
--built rows and open card instead of rebuilding them (which flickers), then clears the id.
--- @type table<string, boolean>
History.quiet = {}

--- Rewrites an entry whose change shows nothing new to the client making it (the Director
--- flipping a roll's reveal eye), so the tray does not rebuild it here.
--- @param entry HistoryEntry
function History.RewriteQuietly(entry)
    History.Write(entry)
    History.quiet[entry.id] = true
end

--- An entry's key in its map's History.
--- @param entry HistoryEntry
--- @return string
function History.KeyOf(entry)
    return EntryKey(entry)
end

--- The entry as it is stored, read afresh: the copy to change and write back. A player's
--- own copy (History.Entry) has parts cut out, and writing it would cut them for everyone.
--- Nil if the entry is gone or unreadable.
--- @param entry HistoryEntry
--- @return HistoryEntry|nil
function History.Stored(entry)
    local entries = mod:GetDocumentSnapshot(History.DocId(entry.map)).data.entries
    local raw = type(entries) == "table" and entries[EntryKey(entry)] or nil
    if raw == nil then
        return nil
    end
    local ok, decoded = pcall(dmhub.FromJson, raw)
    if not ok or not decoded.success then
        return nil
    end
    return decoded.result
end

--- An entry this client just wrote, as this client may show it: for a player, a copy cut
--- down the way History.Entry cuts it. Nil when nothing of it is left to show.
--- @param entry HistoryEntry
--- @return HistoryEntry|nil
function History.ForViewer(entry)
    if dmhub.isDM then
        return entry
    end
    local ok, decoded = pcall(dmhub.FromJson, dmhub.ToRawJson(entry))
    if not ok or not decoded.success then
        return nil
    end
    return ForPlayers(decoded.result)
end

--- Removes entries from a map's History, for everyone (the Director's Delete entry).
--- @param mapid string
--- @param entries HistoryEntry[]
function History.Delete(mapid, entries)
    local doc = mod:GetDocumentSnapshot(History.DocId(mapid))
    doc:BeginChange()
    if type(doc.data.entries) == "table" then
        for _, entry in ipairs(entries) do
            doc.data.entries[EntryKey(entry)] = nil
        end
    end
    doc:CompleteChange("Delete History entry", {undoable = false})
end

--- Hides entries from players, or shows them again (the Director's Hide from players /
--- Reveal to players). The Director still sees them.
--- @param entries HistoryEntry[]
--- @param hidden boolean
function History.SetHiddenFromPlayers(entries, hidden)
    for _, entry in ipairs(entries) do
        entry.hiddenfromplayers = hidden or nil
        --set on the stored entry, so nothing another client set since is lost.
        local stored = History.Stored(entry)
        if stored ~= nil then
            stored.hiddenfromplayers = hidden or nil
            History.Rewrite(stored)
        end
    end
end

--- Marks what a revert undid. With turn (Revert Turn), every entry of that turn
--- takes reverted = key. Without it (Turn Rewind), entries stamped after since do, and
--- entries key marked before that lose it again (rolling forward). Revert Turn goes by the
--- turn rather than the time because each client stamps with its own estimate of server
--- time, and a player's can run behind the Director's checkpoint. The revert's line is
--- written afresh at the end while anything stays reverted, and removed when nothing does.
--- Reads the stored entries, not this client's copy, which for a player has parts cut out
--- (ForPlayers) and must never be written back.
--- @param mapid string
--- @param since number server ms the restored checkpoint was taken
--- @param key string the same key for every step of one Turn Rewind turn; a new one per Revert Turn
--- @param line HistoryEntry the Turn reverted line, without id or t
--- @param turn? {encounter: string, round: integer, turn: integer} Revert Turn: the turn undone
--- @param held? table<string, boolean> Turn Rewind: the keys History held when the point gone
--- back to was recorded (History.HeldKeys). What came after is what isn't in it, so a
--- client's clock running behind can't hide an entry; without it, the stamps are used.
function History.SetReverted(mapid, since, key, line, turn, held)
    local doc = mod:GetDocumentSnapshot(History.DocId(mapid))
    local entries = doc.data.entries
    if type(entries) ~= "table" then
        return
    end
    local changed = {}
    local oldLines = {}
    local anyReverted = false
    for entryKey, raw in pairs(entries) do
        --keys start with the 13-digit stamp: an entry at or before since only matters if
        --this revert key marked it, and then its text holds the key.
        local stamp = tonumber(string.sub(entryKey, 1, 13)) or 0
        if turn ~= nil or held ~= nil or stamp > since or string.find(raw, key, 1, true) ~= nil then
            local ok, decoded = pcall(dmhub.FromJson, raw)
            if ok and decoded.success then
                local stored = decoded.result
                if stored.family == "reverted" then
                    if stored.revertkey == key then
                        oldLines[#oldLines + 1] = entryKey
                    end
                elseif turn ~= nil then
                    if stored.reverted == nil and stored.encounter == turn.encounter and stored.round == turn.round and stored.turn == turn.turn then
                        stored.reverted = key
                        changed[entryKey] = stored
                        anyReverted = true
                    end
                else
                    --came before the point: in what History held then, or (without that) stamped
                    --no later than it.
                    local before
                    if held ~= nil then
                        before = held[entryKey] == true
                    else
                        before = stored.t <= since
                    end
                    if stored.reverted == key then
                        if before then
                            stored.reverted = nil
                            changed[entryKey] = stored
                        else
                            anyReverted = true
                        end
                    elseif stored.reverted == nil and not before then
                        stored.reverted = key
                        changed[entryKey] = stored
                        anyReverted = true
                    end
                end
            end
        end
    end
    if next(changed) == nil and #oldLines == 0 and not anyReverted then
        return
    end
    doc:BeginChange()
    for entryKey, stored in pairs(changed) do
        doc.data.entries[entryKey] = dmhub.ToRawJson(stored)
    end
    for _, entryKey in ipairs(oldLines) do
        doc.data.entries[entryKey] = nil
    end
    doc:CompleteChange("History revert", {undoable = false})
    if anyReverted then
        line.revertkey = key
        History.Write(line)
    end
end

--- The keys of every entry this client knows of on a map, written or still waiting to be:
--- what was already there at a moment, for Turn Rewind to tell what came after it.
--- @param mapid string
--- @return table<string, boolean>
function History.HeldKeys(mapid)
    local held = {}
    for _, key in ipairs(History.Keys(mapid)) do
        held[key] = true
    end
    for _, entry in ipairs(g_waiting) do
        if entry.map == mapid then
            held[EntryKey(entry)] = true
        end
    end
    return held
end

--- Empties a map's History, for everyone.
--- @param mapid string
function History.Clear(mapid)
    local doc = mod:GetDocumentSnapshot(History.DocId(mapid))
    doc:BeginChange()
    doc.data.entries = nil
    doc.data.encounters = nil
    doc.data.counts = nil
    doc.data.hovers = nil
    doc.data.hoverused = nil
    doc:CompleteChange("Clear History", {undoable = false})
end

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
--  hovers:     {[id] = text}, the roll dialog's hover text for each modifier an entry
--              names, stored once however many entries name it (2.3d).
--  hoverused:  {[id] = time of the last entry written with it}, for retention.
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
--- @field mode? string Out of combat: the game mode's id when it was not Exploration, e.g. "respite".
--- @field round? integer The combat round.
--- @field turn? integer Running turn number within the combat.
--- @field owner? HistoryCreature Whose turn it was; nil between turns.
--- @field actor? HistoryCreature Who acted.
--- @field targets? HistoryCreature[] Who it was aimed at.
--- @field ability? {name: string, icon: string|nil, action: string|nil, free: boolean|nil, area: boolean|nil, villainaction: string|nil} What was used; villainaction is the stat block slot, "Villain Action 1"; the tag reads only "Villain Action" (L90).
--- @field player? string On an action: the player who used it. Nil means the Director.
--- @field roll? {total: number, low: number|nil, high: number|nil, edges: number, banes: number, tier: number, natural: number|nil, characteristic: {name: string, value: number}|nil, bonus: number|nil, sources: HistoryEdgeSource[]|nil, hidden: boolean|nil, revealed: boolean|nil, overridden: {by: string|nil, dicetier: number}|nil} The power roll. overridden: someone chose the tier after the dice landed (L91-L93). hidden: the players could not see it; revealed: the Director has since shown it to them. natural is the dice; bonus is what the total adds past the dice, the characteristic and an edge or bane; sources are what gave it its edges and banes.
--- @field cause? string On an automatic trigger or a minions line: id of the cast behind it. On a test or table line: the ability that asked for the roll, whose row it goes under.
--- @field landedby? HistoryCreature On an automatic trigger: the creature that fell on its target.
--- @field aliases? string[] On an action: ids of casts inside it that have no row of their own.
--- @field family? string On a line (kind "line"): "damage", "heal", "temporarystamina",
--- "condition", "ended", "save", "persistence", "encounterend", "threshold", "minions",
--- "resource", "malice", "globalresource", "moved", "test", "dice", "drawsteel",
--- "respite", "levelup", "montagetest", "montagethreat", "montageend", "montagecounter",
--- "negotiation", "downtime", "table", "award", "staminaset" or "reinforcements".
--- @field arrivals? {who: HistoryCreature, name: string, count: integer}[] On a reinforcements line: who arrived, counted by stat block name (L89).
--- @field byplayer? boolean On a line: a player made this change by hand (L87); it turns the Director's badge gold.
--- @field counter? string On a montagecounter line: "successes" or "failures".
--- @field sub? string On a negotiation line: "began", "argument", "pitfall", "read", "reveal", "adjust" or "ended". On a downtime line: "milestone" or "completed". On an award line: "victories", "item", "title", "renown" or "wealth".
--- @field raw? boolean On a negotiation line: the Director was showing the numbers on the stage.
--- @field playercause? string On a negotiation line: the cause text players read when raw is false.
--- @field directoronly? boolean On a negotiation line: players get no line.
--- @field hiddenfromplayers? boolean The Director chose Hide from players (L41): players get no row.
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
--- @field project? string On a table line: the downtime project whose event the Director rolled (L77).
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
--- @field quiet? boolean On a Malice line: it counts in the round heading but shows no line.
--- @field costs? table<string, {amount: number, style: string}> On an action: resources it spent.
--- @field state? string On a threshold line: "winded", "dying" or "killed".
--- @field killed? integer On a minions line: how many died.
--- @field left? integer On a minions line: how many of the squad are left.
--- @field recovered? string On a heal line: "winded" or "dying" if the heal ended it.
--- @field name? string On a condition, save, persistence or test line: what it is about (a test: "Might test"). On a table line: the table. On an item or title award line: the item or title. On a reinforcements line: the wave.
--- @field names? string[] On an ended line: what ended.
--- @field ended? {who: HistoryCreature, names: string[], hidden: table<string, boolean>|nil}[] On an encounter's closing line: what ended, by creature.
--- @field secret? boolean On a condition line: an effect hidden from enemies, on a creature off the heroes' side. Players don't see the line.
--- @field hidden? table<string, boolean> On an ended line: names players may not see.
--- @field secretroll? boolean For a player only: the roll was hidden from players, so it was taken out (History.Entry).
--- @field privacy? {hidden: boolean, tower: boolean|nil, userid: string|nil, cause: string|nil, revealed: boolean|nil} On a test or dice line: a roll not everyone saw (L79, L80). GM only reaches its roller and the Director; a Dice Tower roll's result only the Director. cause is the line under it without the result; the Director's eye sets revealed.
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
    --Entries kept per map, oldest culled first. Why 500: PROBE-0.1.md.
    hardCap = 500,
    --An encounter counts towards dropping older ones only once it has this many entries,
    --so a combat started by mistake and ended at once does not cost the last real fight.
    minEncounterEntries = 5,
    --Set by the tray: runs when the setting changes.
    --- @type nil|function
    OnEnabledChanged = nil,
}

--Off by default until the last stage of the build; on for a whole game at once,
--so every client records and shows the same thing. No editor: it has no place in
--Settings until the switch-over. Turn it on with
--dmhub.SetSettingValue("historyenabled", true).
local g_enabledSetting = setting{
    id = "historyenabled",
    storage = "game",
    default = false,
    onchange = function()
        if History.OnEnabledChanged ~= nil then
            History.OnEnabledChanged()
        end
    end,
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

    --counts: entries written per encounter. One with no count is from before counts were
    --kept, and counts as a real encounter.
    local counts = data.counts or {}
    local starts = {}
    for id, t in pairs(encounters) do
        if counts[id] == nil or counts[id] >= History.minEncounterEntries then
            starts[#starts + 1] = {id = id, t = t}
        end
    end
    if #starts > 2 then
        table.sort(starts, function(a, b) return a.t > b.t end)
        local keepFrom = KeyPrefix(starts[2].t)
        for id, t in pairs(encounters) do
            if t < starts[2].t then
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
    local h = 5381
    for i = 1, #text do
        h = (h * 33 + string.byte(text, i)) % 4294967296
    end
    return string.format("h%08x", h)
end

--Moves each roll dialog hover text in an entry (a hovertext field anywhere in it) into the
--map's shared hovers, leaving its id in hover. used keeps the time each id was last
--written, so Cull can drop texts no kept entry points at.
local function StoreHoverTexts(node, hovers, used, t)
    for _, value in pairs(node) do
        if type(value) == "table" then
            StoreHoverTexts(value, hovers, used, t)
        end
    end
    local text = node.hovertext
    if type(text) == "string" then
        local id = TextHash(text)
        while hovers[id] ~= nil and hovers[id] ~= text do
            id = id .. "x"
        end
        hovers[id] = text
        used[id] = math.max(used[id] or 0, t)
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
    for id, t in pairs(data.hoverused) do
        if t < keepFrom then
            data.hoverused[id] = nil
            data.hovers[id] = nil
        end
    end
end

--Writes every entry waiting for one map, in one change to its document.
local function WriteEntries(mapid, list)
    local doc = mod:GetDocumentSnapshot(History.DocId(mapid))
    doc:BeginChange()
    local data = doc.data
    if type(data.entries) ~= "table" then
        data.entries = {}
    end
    if type(data.encounters) ~= "table" then
        data.encounters = {}
    end
    if type(data.counts) ~= "table" then
        data.counts = {}
    end
    --a list here is a table saved before ids had their "h" (see TextHash): start it again.
    if type(data.hovers) ~= "table" or type(data.hoverused) ~= "table" or data.hovers[1] ~= nil then
        data.hovers = {}
        data.hoverused = {}
    end
    for _, entry in ipairs(list) do
        StoreHoverTexts(entry, data.hovers, data.hoverused, entry.t)
        local key = EntryKey(entry)
        local isNew = data.entries[key] == nil
        data.entries[key] = dmhub.ToRawJson(entry)
        if entry.encounter ~= nil then
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
    Cull(data)
    CullHoverTexts(data)
    doc:CompleteChange("History", {undoable = false})
end

--Entries waiting for the next frame, so an aura that hits eight creatures is one
--write, not eight. Nothing here touches the document from inside a hit.
local g_waiting = {}

local function Flush()
    local waiting = g_waiting
    g_waiting = {}
    if mod.unloaded then
        return
    end
    local byMap = {}
    for _, entry in ipairs(waiting) do
        byMap[entry.map] = byMap[entry.map] or {}
        table.insert(byMap[entry.map], entry)
    end
    for mapid, list in pairs(byMap) do
        local ok, err = pcall(WriteEntries, mapid, list)
        if not ok then
            dmhub.Debug(string.format("History: failed to write entries: %s", tostring(err)))
        end
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
--- @type table<string, table<string, {raw: string, entry: HistoryEntry|nil}>>
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

--Drops the hover text ids from roll sources or damage parts.
local function WithoutHovers(list)
    for _, item in ipairs(list or {}) do
        item.hover = nil
    end
end

--Cuts an entry down to what players may see (2.4, REVIEW.md B5: players see what they
--saw live). Done once as it is parsed, so no view can show more by mistake. Nil when
--nothing of it is left to show.
--- @param entry HistoryEntry
--- @return HistoryEntry|nil
local function ForPlayers(entry)
    if entry.hiddenfromplayers then
        return nil
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
    --meters read as numbers only if the Director was showing them on the stage (5.1f).
    if entry.family == "negotiation" then
        if entry.directoronly then
            return nil
        end
        if not entry.raw then
            entry.causetext = entry.playercause
        end
    end
    --a test or dice line rolled out of players' sight, as the chat shows it (L79).
    local privacy = entry.privacy
    if privacy ~= nil and privacy.hidden and not privacy.revealed then
        if not privacy.tower and privacy.userid ~= dmhub.userid then
            return nil
        elseif privacy.tower then
            entry.roll = nil
            entry.dice = nil
            entry.total = nil
            entry.tier = nil
            entry.secretroll = true
            entry.causetext = privacy.cause
        end
    end
    local hiddenRoll = entry.roll ~= nil and entry.roll.hidden and not entry.roll.revealed
    if hiddenRoll then
        entry.roll = nil
        entry.secretroll = true
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
    if parsed == nil or parsed.raw ~= raw then
        local ok, decoded = pcall(dmhub.FromJson, raw)
        if not ok or not decoded.success then
            return nil
        end
        local entry = decoded.result
        if forPlayers then
            entry = ForPlayers(entry)
        end
        parsed = {raw = raw, entry = entry}
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

--Active (S6, B8): a condition or effect a row started that is still on. Several rows can
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

--- Removes entries from a map's History, for everyone (the Director's Delete entry, L41).
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
--- Reveal to players, L41). The Director still sees them.
--- @param entries HistoryEntry[]
--- @param hidden boolean
function History.SetHiddenFromPlayers(entries, hidden)
    for _, entry in ipairs(entries) do
        entry.hiddenfromplayers = hidden or nil
        History.Rewrite(entry)
    end
end

--- Empties a map's History, for everyone.
--- @param mapid string
function History.Clear(mapid)
    local doc = mod:GetDocumentSnapshot(History.DocId(mapid))
    doc:BeginChange()
    doc.data.entries = nil
    doc.data.encounters = nil
    doc.data.hovers = nil
    doc.data.hoverused = nil
    doc:CompleteChange("Clear History", {undoable = false})
end

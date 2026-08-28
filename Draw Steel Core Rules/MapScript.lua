local mod = dmhub.GetModLoading()

-- ===========================================================================
-- Map Scripts
-- ===========================================================================
-- A Map Script is Lua attached to a map that runs while the map is active.
-- The sibling of Encounter Scripts (MCDMEncounter.lua) with Zone Scripts'
-- (EnvironmentalKeyword.lua) lifecycle discipline:
--
--   * The script source RETURNS a definition table (the AbilityScript /
--     EncounterScript / ZoneScript load-with-env precedent):
--
--       return {
--           name = ..., description = ...,
--           params = { {id, name, type, default, min, max, options}, ... },
--           onActivate = function(ctx) end,    -- every client, map became active
--           onDeactivate = function(ctx) end,  -- every client, guaranteed teardown
--           think = function(ctx) end,         -- every client, every thinkInterval
--           thinkInterval = 1,
--           onBecomeHost = function(ctx) end,  -- this client became the host
--           onLoseHost = function(ctx) end,    -- this client stopped being the host
--           hostThink = function(ctx) end,     -- HOST ONLY, every hostThinkInterval
--           hostThinkInterval = 1,
--           events = { eventName = function(ctx, ...) end },  -- global events
--       }
--
--   * Every client viewing the map runs an instance of each attached script.
--     Exactly one client - the elected HOST, always a director - additionally
--     runs the host handlers, for events that must happen exactly once with
--     no conflicts. Handover on disconnect is automatic.
--
--   * HOST ELECTION: session presence has no notion of which map a user is
--     viewing, so directors running a script-bearing map publish a presence
--     heartbeat into that map's shared document ("mapscripts-<mapid>"). Every
--     client on the map computes the same election over the same shared data:
--     lowest-sorting userid among fresh entries whose session passes the
--     director-presence test (dmhub.GetSessionInfo(uid).dm - NOT
--     dmhub.IsUserDM, which reflects the stale roster). A crashed host's
--     entry goes stale after HOST_FRESH_SECONDS and the next director on the
--     map takes over; a graceful exit removes its entry immediately.
--
--   * The same per-map document carries each script's shared replicated
--     state (ctx:GetShared/ModifyShared) and run-once watermarks
--     (ctx:RunOnce), so a host handover RESUMES rather than refires.
--
-- Where things live:
--   * MapScript              - a library script in the "mapScripts" object
--                              table, authored in the Compendium under Rules.
--                              Built-ins are registered in code below.
--   * Attachment records     - plain tables (NOT game types - they ride in a
--                              map setting, which serializes raw values) in
--                              the "map:scripts" per-map setting:
--                              { guid, scriptid, code, name, params }.
--                              scriptid = library id or "builtin:" id; "" for
--                              inline custom code. Replicated + undoable via
--                              the map-settings machinery, and editable in
--                              Map Settings / the Settings screen's Map tab.
--   * Runtime                - the 0.5s driver below reconciles attachments
--                              against running instances every tick;
--                              teardown is guaranteed via the reconcile
--                              diff, the map-change check, and
--                              mod.unloadHandlers.

--- @class MapScript
--- @field name string Display name of the library script.
--- @field description string What the script does, shown in pickers and the compendium.
--- @field code string The Lua source; must return a definition table.
MapScript = RegisterGameType("MapScript")

MapScript.name = "New Map Script"
MapScript.description = ""
MapScript.code = ""
MapScript.tableName = "mapScripts"

function MapScript.OnDeserialize(self)
    if not self:has_key("guid") then
        self.guid = dmhub.GenerateGuid()
    end
end

--The per-map list of attachment records. No editor: the Map Scripts section
--in Map Settings / the Settings screen renders it with custom controls.
setting{
    id = "map:scripts",
    description = "Map Scripts",
    storage = "map",
    default = {},
}

--The seed code for a brand new custom or library script. Doubles as the
--reference documentation for the definition shape.
MapScript.starterTemplate = [==[
-- A Map Script. The code runs once to produce a definition table: declare
-- parameters the director can edit in Map Settings, and the handlers that
-- run while the map is active. The script runs on EVERY client viewing the
-- map; one client (the elected host, always a director) additionally runs
-- the host handlers, for things that must happen exactly once.
--
-- ctx fields available in handlers:
--   ctx.params    resolved parameter values
--   ctx.state     per-client scratch table (lives while the map is active here)
--   ctx.mapid     the map this script is attached to
--   ctx.isHost    true while this client is the elected host
-- ctx methods (call with ':'):
--   ctx:IsLive()          still active on this client (for coroutines)
--   ctx:IsHost()          currently the elected host
--   ctx:Announce(text)    send a chat message (host only)
--   ctx:Log(text)         print to this client's console
--   ctx:GetShared()       read a copy of the script's shared replicated state
--   ctx:ModifyShared(fn)  fn(shared) mutates the shared state; syncs to all clients
--   ctx:RunOnce(key, fn)  run fn exactly once EVER for this map (host only)

return {
    name = "My Map Script",
    description = "Describe what this script does.",

    params = {
        -- { id = "message", name = "Message", type = "string", default = "Hello!" },
        -- { id = "minutes", name = "Minutes", type = "number", default = 5, min = 1, max = 240 },
        -- { id = "enabled", name = "Enabled", type = "boolean", default = true },
    },

    -- Every client, when the map becomes active there (also after the script
    -- is attached, edited, reparameterized, or Lua reloads).
    onActivate = function(ctx)
    end,

    -- Every client, when the map stops being active there. Guaranteed to run:
    -- map change, script removal, edits, and Lua reloads all land here.
    onDeactivate = function(ctx)
    end,

    -- Every client, every thinkInterval seconds while the map is active.
    think = function(ctx)
    end,
    thinkInterval = 1,

    -- Host only: exactly one client (a director) runs these, with automatic
    -- handover if that client leaves the map or disconnects.
    onBecomeHost = function(ctx)
    end,
    onLoseHost = function(ctx)
    end,
    hostThink = function(ctx)
    end,
    hostThinkInterval = 1,

    -- Global event handlers, registered while the map is active on this
    -- client. They fire on ALL clients; gate shared side effects with
    -- ctx:IsHost(). Event names are dmhub global events (e.g. "DiceRoll"),
    -- including custom ones fired with dmhub.FireGlobalEvent.
    events = {
        -- DiceRoll = function(ctx, info) end,
    },
}
]==]

--- @return MapScript
function MapScript.CreateNew()
    return MapScript.new{
        guid = dmhub.GenerateGuid(),
        name = "New Map Script",
        description = "",
        code = MapScript.starterTemplate,
    }
end

--- Appends {id, text} entries for all library map scripts into options
--- (sorted by name).
function MapScript.FillDropdownOptions(options)
    local result = {}
    local dataTable = dmhub.GetTable(MapScript.tableName) or {}
    for k, item in unhidden_pairs(dataTable) do
        result[#result + 1] = {
            id = k,
            text = item.name,
        }
    end
    table.sort(result, function(a, b) return a.text < b.text end)
    for _, item in ipairs(result) do
        options[#options + 1] = item
    end
end

-- ---------------------------------------------------------------------------
-- Built-in scripts
-- ---------------------------------------------------------------------------
-- Starter scripts shipped in code (repo-versioned, available in every game
-- without seeding the object table). They appear in the Add Script picker;
-- the compendium library holds game-authored scripts.

MapScript.builtins = {}
local g_builtinsById = {}

--info: { id, name, description, code }. id convention: "builtin:<slug>".
function MapScript.RegisterBuiltin(info)
    for i, existing in ipairs(MapScript.builtins) do
        if existing.id == info.id then
            MapScript.builtins[i] = info
            g_builtinsById[info.id] = info
            return
        end
    end
    MapScript.builtins[#MapScript.builtins + 1] = info
    g_builtinsById[info.id] = info
end

function MapScript.GetBuiltin(id)
    return g_builtinsById[id]
end

--- Appends built-in scripts, then library scripts, as {id, text} options.
--- Used by the Map Settings Add Script picker.
function MapScript.FillPickerOptions(options)
    for _, builtin in ipairs(MapScript.builtins) do
        options[#options + 1] = { id = builtin.id, text = builtin.name .. " (built-in)" }
    end
    MapScript.FillDropdownOptions(options)
end

-- ---------------------------------------------------------------------------
-- Definition compilation + validation
-- ---------------------------------------------------------------------------

local g_paramTypes = {
    number = true,
    string = true,
    boolean = true,
    choice = true,
}

--Validate and normalize a raw definition table returned by a script chunk.
--Returns the normalized definition, or nil + an error string.
local function NormalizeDefinition(def)
    local norm = {}

    if def.name ~= nil and type(def.name) ~= "string" then
        return nil, "name must be a string"
    end
    norm.name = def.name

    if def.description ~= nil and type(def.description) ~= "string" then
        return nil, "description must be a string"
    end
    norm.description = def.description

    norm.params = {}
    local seenIds = {}
    if def.params ~= nil then
        if type(def.params) ~= "table" then
            return nil, "params must be a list of parameter tables"
        end
        for i, p in ipairs(def.params) do
            if type(p) ~= "table" then
                return nil, string.format("params[%d] must be a table", i)
            end
            if type(p.id) ~= "string" or p.id == "" then
                return nil, string.format("params[%d] needs a string id", i)
            end
            if seenIds[p.id] then
                return nil, string.format("duplicate parameter id \"%s\"", p.id)
            end
            seenIds[p.id] = true
            local ptype = p.type or "string"
            if not g_paramTypes[ptype] then
                return nil, string.format("parameter \"%s\" has unknown type \"%s\"", p.id, tostring(ptype))
            end
            local param = {
                id = p.id,
                name = p.name or p.id,
                type = ptype,
                default = p.default,
                min = p.min,
                max = p.max,
            }
            if ptype == "choice" then
                if type(p.options) ~= "table" or #p.options == 0 then
                    return nil, string.format("choice parameter \"%s\" needs an options list", p.id)
                end
                param.options = {}
                for _, opt in ipairs(p.options) do
                    if type(opt) ~= "table" or opt.id == nil then
                        return nil, string.format("choice parameter \"%s\" has a malformed option", p.id)
                    end
                    param.options[#param.options + 1] = { id = opt.id, text = opt.text or tostring(opt.id) }
                end
            end
            norm.params[#norm.params + 1] = param
        end
    end

    for _, handler in ipairs({ "onActivate", "onDeactivate", "think", "onBecomeHost", "onLoseHost", "hostThink" }) do
        local fn = def[handler]
        if fn ~= nil and type(fn) ~= "function" then
            return nil, handler .. " must be a function"
        end
        norm[handler] = fn
    end

    if def.events ~= nil then
        if type(def.events) ~= "table" then
            return nil, "events must be a table of eventName = function"
        end
        norm.events = {}
        for eventName, fn in pairs(def.events) do
            if type(eventName) ~= "string" or eventName == "" then
                return nil, "events keys must be event name strings"
            end
            if type(fn) ~= "function" then
                return nil, string.format("events.%s must be a function", eventName)
            end
            norm.events[eventName] = fn
        end
    end

    local interval = tonumber(def.thinkInterval) or 1
    if interval < 0.25 then
        interval = 0.25
    end
    norm.thinkInterval = interval

    --hostThink often writes shared state, so it gets a higher floor than think.
    local hostInterval = tonumber(def.hostThinkInterval) or 1
    if hostInterval < 0.5 then
        hostInterval = 0.5
    end
    norm.hostThinkInterval = hostInterval

    return norm
end

--Compiled-definition cache, keyed by the exact source string. Definitions are
--pure (no side effects at load), so identical source always yields the same
--definition; callers must treat the returned table as read-only.
local g_definitionCache = {}

--- Compile map-script source into a normalized definition table.
--- Follows the AbilityScript.lua precedent: load(code, name, "t", env) with an
--- environment that reads globals but keeps writes local to the chunk.
--- @param code string
--- @return table|nil, string|nil definition, error
function MapScript.CompileDefinition(code)
    if code == nil or code == "" then
        return nil, "The script is empty"
    end

    local cached = g_definitionCache[code]
    if cached ~= nil then
        return cached.def, cached.error
    end

    local result = { def = nil, error = nil }
    g_definitionCache[code] = result

    local env = setmetatable({}, { __index = _G })
    local chunk, err = load(code, "MapScript", "t", env)
    if chunk == nil then
        result.error = "Compile error: " .. tostring(err)
        return nil, result.error
    end

    local ok, def = pcall(chunk)
    if not ok then
        result.error = "Error running script: " .. tostring(def)
        return nil, result.error
    end
    if type(def) ~= "table" then
        result.error = "The script must return a definition table"
        return nil, result.error
    end

    local norm, normErr = NormalizeDefinition(def)
    if norm == nil then
        result.error = "Invalid definition: " .. tostring(normErr)
        return nil, result.error
    end

    result.def = norm
    return norm, nil
end

--- Human-readable summary of what a definition declares, for editor status rows.
function MapScript.DescribeDefinition(def)
    local parts = {}
    if #def.params == 1 then
        parts[#parts + 1] = "1 parameter"
    elseif #def.params > 1 then
        parts[#parts + 1] = string.format("%d parameters", #def.params)
    end
    local handlers = {}
    for _, handler in ipairs({ "onActivate", "onDeactivate", "think", "onBecomeHost", "onLoseHost", "hostThink" }) do
        if def[handler] ~= nil then
            handlers[#handlers + 1] = handler
        end
    end
    if #handlers > 0 then
        parts[#parts + 1] = "runs " .. table.concat(handlers, ", ")
    end
    if def.events ~= nil then
        local names = {}
        for eventName, _ in pairs(def.events) do
            names[#names + 1] = eventName
        end
        if #names > 0 then
            table.sort(names)
            parts[#parts + 1] = "listens for " .. table.concat(names, ", ")
        end
    end
    if #parts == 0 then
        return "Definition OK (declares nothing yet)"
    end
    return "Definition OK: " .. table.concat(parts, "; ")
end

-- ---------------------------------------------------------------------------
-- Attachment records
-- ---------------------------------------------------------------------------
-- Records are PLAIN tables, not game types: they live inside the
-- "map:scripts" per-map setting, which serializes raw values without game
-- type information. Shape: { guid, scriptid, code, name, params }.

--- The validated list of attachment records for the current map. pcall-guarded
--- because settings reads can land before a map exists.
function MapScript.GetAttachedRecords()
    local value = nil
    pcall(function() value = dmhub.GetSettingValue("map:scripts") end)
    if type(value) ~= "table" then
        return {}
    end
    local result = {}
    for _, rec in ipairs(value) do
        if type(rec) == "table" and type(rec.guid) == "string" and rec.guid ~= "" then
            result[#result + 1] = rec
        end
    end
    return result
end

--- Replace the current map's attachment list (director only; the map-settings
--- machinery replicates the write to every client, undoably).
function MapScript.SetAttachedRecords(records)
    pcall(function() dmhub.SetSettingValue("map:scripts", records) end)
end

--- Attach a library or built-in script by id.
function MapScript.CreateRecordFromLibrary(scriptid)
    local rec = {
        guid = dmhub.GenerateGuid(),
        scriptid = scriptid,
        code = "",
        name = "Map Script",
        params = {},
    }
    MapScript.RefreshRecordName(rec)
    return rec
end

--- Attach a new inline custom script seeded with the starter template.
function MapScript.CreateCustomRecord()
    local rec = {
        guid = dmhub.GenerateGuid(),
        scriptid = "",
        code = MapScript.starterTemplate,
        name = "Custom Script",
        params = {},
    }
    MapScript.RefreshRecordName(rec)
    return rec
end

--True when this record carries inline code rather than a library reference.
function MapScript.RecordIsCustom(rec)
    return (rec.scriptid or "") == ""
end

--- Resolve a record's source code. Returns code, or nil + error when the
--- referenced library script is missing/deleted.
function MapScript.GetRecordCode(rec)
    local sid = rec.scriptid or ""
    if sid == "" then
        return rec.code or "", nil
    end

    local builtin = MapScript.GetBuiltin(sid)
    if builtin ~= nil then
        return builtin.code, nil
    end

    local dataTable = dmhub.GetTable(MapScript.tableName) or {}
    local item = dataTable[sid]
    if item == nil or item:try_get("hidden", false) then
        return nil, "Script not found in library"
    end
    return item:try_get("code", ""), nil
end

--- Resolve + compile a record's definition.
--- @return table|nil, string|nil definition, error
function MapScript.GetRecordDefinition(rec)
    local code, err = MapScript.GetRecordCode(rec)
    if code == nil then
        return nil, err
    end
    return MapScript.CompileDefinition(code)
end

--- The director's parameter values with defaults applied and values coerced to
--- their declared types. def is optional (resolved when absent).
function MapScript.ResolveRecordParams(rec, def)
    local result = {}
    if def == nil then
        def = select(1, MapScript.GetRecordDefinition(rec))
    end
    if def == nil then
        return result
    end

    local values = rec.params or {}
    for _, param in ipairs(def.params) do
        local v = values[param.id]
        if v == nil then
            v = param.default
        end
        if param.type == "number" then
            v = tonumber(v) or 0
            if param.min ~= nil and v < param.min then v = param.min end
            if param.max ~= nil and v > param.max then v = param.max end
        elseif param.type == "boolean" then
            v = (v == true)
        elseif param.type == "string" then
            if v == nil then v = "" end
            v = tostring(v)
        elseif param.type == "choice" then
            local valid = false
            for _, opt in ipairs(param.options or {}) do
                if opt.id == v then
                    valid = true
                    break
                end
            end
            if not valid and param.options ~= nil and #param.options > 0 then
                v = param.options[1].id
            end
        end
        result[param.id] = v
    end
    return result
end

--- Refresh a record's cached display name from its definition.
function MapScript.RefreshRecordName(rec)
    local def = select(1, MapScript.GetRecordDefinition(rec))
    if def ~= nil and def.name ~= nil and def.name ~= "" then
        rec.name = def.name
    end
end

-- ---------------------------------------------------------------------------
-- Error reporting
-- ---------------------------------------------------------------------------

--Report a handler error once per handler per instance: a broken think would
--otherwise spam an error every tick. The flag doubles as the "stop calling
--this handler" gate in the driver.
local function ReportError(instance, handler, err)
    if instance.errorReported[handler] then
        return
    end
    instance.errorReported[handler] = true
    local name = "Map Script"
    if instance.rec ~= nil and instance.rec.name ~= nil then
        name = instance.rec.name
    end
    local text = string.format("Map Script '%s': error in %s: %s", tostring(name), tostring(handler), tostring(err))
    dmhub.CloudError(text)
    print("ERROR:", text)
end

-- ---------------------------------------------------------------------------
-- Shared per-map document: host presence, shared state, run-once watermarks
-- ---------------------------------------------------------------------------
-- One document per map:
--   data.hosts  = { [userid] = serverTime }   director presence heartbeats
--   data.shared = { [recordGuid] = {...} }    script shared state
--   data.once   = { [recordGuid] = { [key] = true } }  RunOnce watermarks

--A crashed host's presence entry looks fresh for this long; the next director
--on the map takes over once it lapses.
local HOST_FRESH_SECONDS = 25
--How often a director on the map rewrites its presence entry.
local HOST_RENEW_SECONDS = 8
--Entries older than this are removed whenever we write anyway, so the doc
--never accumulates departed directors.
local HOST_PRUNE_SECONDS = 90

local function MapDoc(mapid)
    return mod:GetDocumentSnapshot("mapscripts-" .. tostring(mapid))
end

--Presence per the director-election reference: dmhub.GetSessionInfo(uid).dm is
--the authoritative live director flag (dmhub.IsUserDM reflects the persisted
--roster and lies); ghost sessions report loggedOut == false with a huge
--timeSinceLastContact, so both checks are required. 140s matches Audio.lua.
local function IsDirectorPresent(userid)
    local info = nil
    pcall(function() info = dmhub.GetSessionInfo(userid) end)
    if info == nil or info.loggedOut then
        return false
    end
    local isdm = false
    pcall(function() isdm = (info.dm == true) end)
    return isdm and (info.timeSinceLastContact or 0) < 140
end

--Tracks our last presence write so renewals are throttled to HOST_RENEW_SECONDS.
local g_presence = { mapid = nil, lastWrite = 0 }

--Write/refresh our presence entry in the map's document (directors only),
--pruning long-dead entries while we are writing anyway.
local function RenewHostPresence(mapid)
    if not dmhub.isDM then
        return
    end
    local now = dmhub.serverTime
    if g_presence.mapid == mapid and math.abs(now - g_presence.lastWrite) < HOST_RENEW_SECONDS then
        return
    end
    local ok = pcall(function()
        local doc = MapDoc(mapid)
        doc:BeginChange()
        local data = doc.data
        if type(data.hosts) ~= "table" then
            data.hosts = {}
        end
        data.hosts[dmhub.userid] = now
        for uid, ts in pairs(data.hosts) do
            if type(ts) ~= "number" or math.abs(now - ts) > HOST_PRUNE_SECONDS then
                data.hosts[uid] = nil
            end
        end
        doc:CompleteChange("Map script host presence", { undoable = false })
    end)
    if ok then
        g_presence.mapid = mapid
        g_presence.lastWrite = now
    end
end

--Graceful handoff: remove our presence entry so a successor does not have to
--wait out the freshness window. Called when our last instance on a map ends.
local function ReleaseHostPresence(mapid)
    if g_presence.mapid == mapid then
        g_presence.mapid = nil
        g_presence.lastWrite = 0
    end
    if not dmhub.isDM then
        return
    end
    pcall(function()
        local doc = MapDoc(mapid)
        local hosts = doc.data.hosts
        if type(hosts) ~= "table" or hosts[dmhub.userid] == nil then
            return
        end
        doc:BeginChange()
        doc.data.hosts[dmhub.userid] = nil
        doc:CompleteChange("Map script host handoff", { undoable = false })
    end)
end

--- True when this client is the elected host for the given map's scripts:
--- the lowest-sorting userid among fresh presence entries whose session
--- passes the director-presence test. Every client on the map computes the
--- same answer from the same shared data, so they agree without negotiation.
--- Before our own presence write lands we simply are not host yet (rather
--- than failing open) - two directors arriving at once can never both act.
function MapScript.IsElectedHost(mapid)
    if not dmhub.isDM then
        return false
    end
    if mapid == nil or mapid == "" then
        return false
    end
    local hosts = nil
    pcall(function() hosts = MapDoc(mapid).data.hosts end)
    if type(hosts) ~= "table" then
        return false
    end
    local now = dmhub.serverTime
    local best = nil
    for uid, ts in pairs(hosts) do
        --math.abs guards clock rebasing: an entry stamped against a different
        --server-time base looks wildly far away in either direction and must
        --read as stale, never as forever-fresh.
        if type(ts) == "number" and math.abs(now - ts) < HOST_FRESH_SECONDS and IsDirectorPresent(uid) then
            if best == nil or uid < best then
                best = uid
            end
        end
    end
    return best == dmhub.userid
end

-- ---------------------------------------------------------------------------
-- Runtime: instances, ctx, and the reconciling driver
-- ---------------------------------------------------------------------------

local g_runtime = {
    --key "mapid|recordGuid" -> running instance { key, mapid, guid, rec, code,
    --def, paramsig, ctx, isHost, destroyed, nextThink, nextHostThink,
    --eventGuids, errorReported }
    instances = {},
}

--The handler context. One per instance per client; isHost is re-pointed by
--the driver on every election change so both roles share the same state.
local function MakeContext(instance)
    local ctx = {
        params = MapScript.ResolveRecordParams(instance.rec, instance.def),
        state = {},
        mapid = instance.mapid,
        guid = instance.guid,
        name = instance.rec.name or "Map Script",
        isHost = false,
    }

    ctx.IsLive = function()
        if mod.unloaded or instance.destroyed then
            return false
        end
        local current = nil
        pcall(function() current = game.currentMapId end)
        return current == instance.mapid
    end

    ctx.IsHost = function()
        return (not instance.destroyed) and instance.isHost
    end

    ctx.Log = function(_, text)
        print(string.format("MapScript '%s': %s", tostring(ctx.name), tostring(text)))
    end

    --Chat reaches every client, so it is host-gated: an ungated Announce in
    --think would post once per connected client.
    ctx.Announce = function(_, text)
        if not instance.isHost then
            ReportError(instance, "announce", "ctx:Announce only runs on the host; gate it with ctx:IsHost()")
            return false
        end
        pcall(function() chat.Send(tostring(text)) end)
        return true
    end

    --A copy of this script's shared state (safe to read anywhere; mutations
    --must go through ModifyShared to replicate).
    ctx.GetShared = function()
        local result = {}
        pcall(function()
            local shared = MapDoc(instance.mapid).data.shared
            if type(shared) == "table" and type(shared[instance.guid]) == "table" then
                result = DeepCopy(shared[instance.guid])
            end
        end)
        return result
    end

    --fn(shared) mutates the shared table in place; the change syncs to every
    --client. Keep it small and serializable. Any client may write (players
    --included, e.g. for interaction claims); routine writes belong on the host.
    ctx.ModifyShared = function(_, fn)
        if type(fn) ~= "function" then
            return false
        end
        local ok, err = pcall(function()
            local doc = MapDoc(instance.mapid)
            doc:BeginChange()
            local data = doc.data
            if type(data.shared) ~= "table" then
                data.shared = {}
            end
            if type(data.shared[instance.guid]) ~= "table" then
                data.shared[instance.guid] = {}
            end
            local fnOk, fnErr = pcall(fn, data.shared[instance.guid])
            doc:CompleteChange("Map script shared state", { undoable = false })
            if not fnOk then
                error(fnErr)
            end
        end)
        if not ok then
            ReportError(instance, "shared", tostring(err))
            return false
        end
        return true
    end

    --Run fn exactly once ever for this map (host only). The watermark is
    --written BEFORE fn fires - the EncounterScript policy - so a crashing fn
    --can never refire every heartbeat. Returns true when fn ran.
    ctx.RunOnce = function(_, key, fn)
        if not instance.isHost then
            return false
        end
        key = tostring(key or "")
        if key == "" then
            return false
        end
        local ran = false
        local ok, err = pcall(function()
            local doc = MapDoc(instance.mapid)
            local once = doc.data.once
            if type(once) == "table" and type(once[instance.guid]) == "table" and once[instance.guid][key] then
                return
            end
            doc:BeginChange()
            local data = doc.data
            if type(data.once) ~= "table" then
                data.once = {}
            end
            if type(data.once[instance.guid]) ~= "table" then
                data.once[instance.guid] = {}
            end
            data.once[instance.guid][key] = true
            doc:CompleteChange("Map script run-once", { undoable = false })
            ran = true
        end)
        if not ok then
            ReportError(instance, "runonce", tostring(err))
            return false
        end
        if ran and type(fn) == "function" then
            local fnOk, fnErr = pcall(fn)
            if not fnOk then
                ReportError(instance, "runonce", tostring(fnErr))
            end
        end
        return ran
    end

    return ctx
end

--Register the definition's global-event handlers for a running instance.
--Handler guids are kept for deregistration at destroy.
local function RegisterInstanceEvents(instance)
    instance.eventGuids = {}
    for eventName, fn in pairs(instance.def.events or {}) do
        local name = eventName
        local handler = fn
        local hkey = "event:" .. name
        local guid = dmhub.RegisterEventHandler(name, function(...)
            if mod.unloaded or instance.destroyed or instance.errorReported[hkey] then
                return
            end
            local ok, err = pcall(handler, instance.ctx, ...)
            if not ok then
                ReportError(instance, hkey, err)
            end
        end)
        if guid ~= nil then
            instance.eventGuids[#instance.eventGuids + 1] = guid
        end
    end
end

local function CreateInstance(key, mapid, rec, code, def, paramsig)
    local instance = {
        key = key,
        mapid = mapid,
        guid = rec.guid,
        rec = rec,
        code = code,
        def = def,
        paramsig = paramsig,
        isHost = false,
        destroyed = false,
        nextThink = dmhub.Time() + def.thinkInterval,
        nextHostThink = dmhub.Time() + def.hostThinkInterval,
        errorReported = {},
    }
    instance.ctx = MakeContext(instance)
    g_runtime.instances[key] = instance
    if def.onActivate ~= nil then
        local ok, err = pcall(def.onActivate, instance.ctx)
        if not ok then
            ReportError(instance, "onActivate", err)
        end
    end
    RegisterInstanceEvents(instance)
    return instance
end

--Runs the exit routine and unregisters the instance. Reentrant-safe: the
--destroyed flag is set BEFORE the handlers run, so a teardown that somehow
--triggers a reconcile cannot double-fire.
local function DestroyInstance(instance)
    if instance.destroyed then
        return
    end
    instance.destroyed = true
    g_runtime.instances[instance.key] = nil
    for _, guid in ipairs(instance.eventGuids or {}) do
        pcall(function() dmhub.DeregisterEventHandler(guid) end)
    end
    if instance.isHost then
        instance.isHost = false
        instance.ctx.isHost = false
        if instance.def.onLoseHost ~= nil then
            local ok, err = pcall(instance.def.onLoseHost, instance.ctx)
            if not ok then
                ReportError(instance, "onLoseHost", err)
            end
        end
    end
    if instance.def.onDeactivate ~= nil then
        local ok, err = pcall(instance.def.onDeactivate, instance.ctx)
        if not ok then
            ReportError(instance, "onDeactivate", err)
        end
    end
end

local function StopAll()
    local all = {}
    for _, instance in pairs(g_runtime.instances) do
        all[#all + 1] = instance
    end
    local maps = {}
    for _, instance in ipairs(all) do
        maps[instance.mapid] = true
    end
    for _, instance in ipairs(all) do
        DestroyInstance(instance)
    end
    for mapid, _ in pairs(maps) do
        ReleaseHostPresence(mapid)
    end
end

mod.unloadHandlers[#mod.unloadHandlers + 1] = StopAll

--One driver tick: reconcile the current map's attachments against running
--instances (create/destroy/restart), then run think/host duties.
local function DriverTick()
    local mapid = nil
    pcall(function() mapid = game.currentMapId end)
    if mapid == "" then
        mapid = nil
    end

    --the desired set: every attachment on the current map whose code resolves
    --and compiles. Code is re-resolved every tick so library edits restart
    --running instances (the record itself does not change).
    local desired = {}
    if mapid ~= nil then
        for _, rec in ipairs(MapScript.GetAttachedRecords()) do
            local code = MapScript.GetRecordCode(rec)
            if code ~= nil and code ~= "" then
                local def = MapScript.CompileDefinition(code)
                if def ~= nil then
                    local ok, paramsig = pcall(dmhub.ToJson, rec.params or {})
                    if not ok then
                        paramsig = ""
                    end
                    desired[mapid .. "|" .. rec.guid] = { rec = rec, code = code, def = def, paramsig = paramsig }
                end
            end
        end
    end

    --destroy first, in a collected list (DestroyInstance mutates instances):
    --anything not desired anymore, and anything whose code or parameter
    --values changed (the edit restarts the instance against the new
    --definition/params). Map changes land here too - the old map's records
    --are simply no longer desired.
    local stale = nil
    for key, instance in pairs(g_runtime.instances) do
        local want = desired[key]
        if want == nil or want.code ~= instance.code or want.paramsig ~= instance.paramsig then
            stale = stale or {}
            stale[#stale + 1] = instance
        end
    end
    local staleMaps = nil
    for _, instance in ipairs(stale or {}) do
        DestroyInstance(instance)
        staleMaps = staleMaps or {}
        staleMaps[instance.mapid] = true
    end

    for key, want in pairs(desired) do
        local instance = g_runtime.instances[key]
        if instance == nil then
            CreateInstance(key, mapid, want.rec, want.code, want.def, want.paramsig)
        else
            --keep the display name fresh for error messages/logs.
            instance.rec = want.rec
        end
    end

    --graceful host handoff for any map we no longer run instances on.
    if staleMaps ~= nil then
        for staleMapid, _ in pairs(staleMaps) do
            local still = false
            for _, instance in pairs(g_runtime.instances) do
                if instance.mapid == staleMapid then
                    still = true
                    break
                end
            end
            if not still then
                ReleaseHostPresence(staleMapid)
            end
        end
    end

    if next(g_runtime.instances) == nil then
        return
    end

    RenewHostPresence(mapid)

    local isHost = MapScript.IsElectedHost(mapid)
    local now = dmhub.Time()
    for _, instance in pairs(g_runtime.instances) do
        local def = instance.def

        if isHost ~= instance.isHost then
            instance.isHost = isHost
            instance.ctx.isHost = isHost
            local fn = def.onLoseHost
            local handlerName = "onLoseHost"
            if isHost then
                fn = def.onBecomeHost
                handlerName = "onBecomeHost"
            end
            if fn ~= nil then
                local ok, err = pcall(fn, instance.ctx)
                if not ok then
                    ReportError(instance, handlerName, err)
                end
            end
        end

        if def.think ~= nil and (not instance.errorReported.think) and now >= instance.nextThink then
            instance.nextThink = now + def.thinkInterval
            local ok, err = pcall(def.think, instance.ctx)
            if not ok then
                ReportError(instance, "think", err)
            end
        end

        if isHost and def.hostThink ~= nil and (not instance.errorReported.hostThink) and now >= instance.nextHostThink then
            instance.nextHostThink = now + def.hostThinkInterval
            local ok, err = pcall(def.hostThink, instance.ctx)
            if not ok then
                ReportError(instance, "hostThink", err)
            end
        end
    end
end

--The heartbeat: a permanent 0.5s Schedule chain (the encounter-driver idiom;
--non-overlapping ticks, dies cleanly on hot reload). It must always run -
--unlike Zone Scripts there is no external sync call to wake it when a script
--is first attached - but an idle tick is just a settings read of an empty
--list.
local function ScheduleDriver()
    dmhub.Schedule(0.5, function()
        if mod.unloaded then
            return
        end
        pcall(DriverTick)
        ScheduleDriver()
    end)
end

ScheduleDriver()

-- ---------------------------------------------------------------------------
-- Code editing UI
-- ---------------------------------------------------------------------------
-- Thin wrappers over the generic EncounterScript editor widgets, pointed at
-- the map-script compiler and library.

function MapScript.CreateCodePanel(options)
    options = options or {}
    options.compile = MapScript.CompileDefinition
    options.describe = MapScript.DescribeDefinition
    return EncounterScript.CreateCodePanel(options)
end

function MapScript.ShowCodeEditorDialog(options)
    options = options or {}
    options.title = options.title or "Map Script"
    options.compile = MapScript.CompileDefinition
    options.describe = MapScript.DescribeDefinition
    if options.canSaveToLibrary then
        options.saveToLibrary = function(def, code)
            local item = MapScript.new{
                guid = dmhub.GenerateGuid(),
                name = def.name or "New Map Script",
                description = def.description or "",
                code = code,
            }
            return dmhub.SetAndUploadTableItem(MapScript.tableName, item)
        end
    end
    return EncounterScript.ShowCodeEditorDialog(options)
end

-- ---------------------------------------------------------------------------
-- Map Settings section (shared by the Map Settings dockable panel and the
-- Settings screen's Map tab)
-- ---------------------------------------------------------------------------

--Read-modify-write on the current map's attachment list. Every mutation goes
--through here so the copy/replicate discipline lives in one place.
local function MutateRecords(fn)
    local records = DeepCopy(MapScript.GetAttachedRecords())
    fn(records)
    MapScript.SetAttachedRecords(records)
end

local function FindRecord(records, guid)
    for _, rec in ipairs(records) do
        if rec.guid == guid then
            return rec
        end
    end
    return nil
end

--Open the custom-code editor for the record with the given guid. Code is
--fetched fresh at save time via MutateRecords so concurrent edits to other
--records are not clobbered.
local function EditCustomRecord(guid, onChanged)
    local current = FindRecord(MapScript.GetAttachedRecords(), guid)
    if current == nil then
        return
    end
    MapScript.ShowCodeEditorDialog{
        title = current.name or "Custom Script",
        code = current.code or "",
        canSaveToLibrary = true,
        onSave = function(newCode)
            MutateRecords(function(records)
                local rec = FindRecord(records, guid)
                if rec ~= nil then
                    rec.code = newCode
                    MapScript.RefreshRecordName(rec)
                end
            end)
            if onChanged ~= nil then
                onChanged()
            end
        end,
        onSavedToLibrary = function(scriptid)
            --convert the attachment from inline code to a library reference.
            MutateRecords(function(records)
                local rec = FindRecord(records, guid)
                if rec ~= nil then
                    rec.scriptid = scriptid
                    rec.code = ""
                    MapScript.RefreshRecordName(rec)
                end
            end)
            if onChanged ~= nil then
                onChanged()
            end
        end,
    }
end

--- The Map Scripts configuration section: attached-script rows (name, source
--- badge, edit/delete, error display, parameter editors) plus the Add picker.
--- Used by both settings surfaces; sized to fit the narrow dockable panel.
function MapScript.CreateSettingsPanel()
    local resultPanel

    local function Refresh()
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel:FireEvent("rebuildScripts")
        end
    end

    local function CommitParamValue(guid, paramid, value)
        MutateRecords(function(records)
            local rec = FindRecord(records, guid)
            if rec ~= nil then
                rec.params = rec.params or {}
                rec.params[paramid] = value
                MapScript.RefreshRecordName(rec)
            end
        end)
    end

    --A stacked (caption above control) editor for one parameter of one record.
    local function BuildParamEditor(rec, param)
        local values = rec.params or {}
        local current = values[param.id]
        if current == nil then
            current = param.default
        end

        if param.type == "boolean" then
            return gui.Check{
                value = (current == true),
                text = param.name,
                fontSize = 12,
                halign = "left",
                vmargin = 2,
                change = function(element)
                    CommitParamValue(rec.guid, param.id, element.value == true)
                end,
            }
        end

        local editor

        if param.type == "number" then
            editor = gui.Input{
                classes = { "form" },
                width = 70,
                height = 24,
                fontSize = 12,
                halign = "left",
                numeric = true,
                characterLimit = 6,
                text = tostring(tonumber(current) or tonumber(param.default) or 0),
                change = function(element)
                    local n = tonumber(element.text)
                    if n == nil then
                        --restore the last committed value (re-read; the
                        --closure's copy goes stale after the first commit).
                        local prev = nil
                        local fresh = FindRecord(MapScript.GetAttachedRecords(), rec.guid)
                        if fresh ~= nil and fresh.params ~= nil then
                            prev = fresh.params[param.id]
                        end
                        element.text = tostring(tonumber(prev) or tonumber(param.default) or 0)
                        return
                    end
                    if param.min ~= nil and n < param.min then n = param.min end
                    if param.max ~= nil and n > param.max then n = param.max end
                    element.text = tostring(n)
                    CommitParamValue(rec.guid, param.id, n)
                end,
            }
        elseif param.type == "choice" then
            local options = {}
            local found = false
            for _, opt in ipairs(param.options or {}) do
                options[#options + 1] = { id = opt.id, text = opt.text }
                if opt.id == current then
                    found = true
                end
            end
            if not found and #options > 0 then
                current = options[1].id
            end
            editor = gui.Dropdown{
                classes = { "form" },
                width = "90%",
                height = 24,
                fontSize = 12,
                halign = "left",
                options = options,
                idChosen = current,
                change = function(element)
                    CommitParamValue(rec.guid, param.id, element.idChosen)
                end,
            }
        else --string
            editor = gui.Input{
                classes = { "form" },
                width = "90%",
                height = 24,
                fontSize = 12,
                halign = "left",
                characterLimit = 200,
                text = tostring(current or ""),
                change = function(element)
                    CommitParamValue(rec.guid, param.id, element.text)
                end,
            }
        end

        return gui.Panel{
            flow = "vertical",
            width = "100%",
            height = "auto",
            vmargin = 2,
            gui.Label{
                classes = { "fgMuted" },
                fontSize = 11,
                width = "100%",
                height = "auto",
                text = param.name,
            },
            editor,
        }
    end

    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        data = { sig = nil },

        --fires on our own writes, a remote director's writes, AND on map
        --switches changing the effective value (the map-settings monitor
        --contract).
        multimonitor = { "map:scripts" },
        monitor = function(element)
            element:FireEvent("rebuildScripts")
        end,

        create = function(element)
            element:FireEvent("rebuildScripts")
        end,

        rebuildScripts = function(element)
            local records = MapScript.GetAttachedRecords()

            --signature covers structure, not parameter VALUES, so committing
            --a value never rebuilds the row out from under the input's focus
            --(the encounter-builder param-row discipline).
            local sigParts = {}
            local entries = {}
            for _, rec in ipairs(records) do
                local def, defError = MapScript.GetRecordDefinition(rec)
                entries[#entries + 1] = { rec = rec, def = def, defError = defError }
                sigParts[#sigParts + 1] = rec.guid
                sigParts[#sigParts + 1] = rec.scriptid or ""
                sigParts[#sigParts + 1] = rec.name or ""
                if def ~= nil then
                    for _, param in ipairs(def.params) do
                        sigParts[#sigParts + 1] = param.id .. ":" .. param.type
                    end
                else
                    sigParts[#sigParts + 1] = "err:" .. tostring(defError)
                end
            end
            local sig = table.concat(sigParts, "|")
            if sig == element.data.sig then
                return
            end
            element.data.sig = sig

            local children = {}

            for _, entry in ipairs(entries) do
                local rec = entry.rec
                local def = entry.def

                local source = "Library"
                if MapScript.RecordIsCustom(rec) then
                    source = "Custom"
                elseif MapScript.GetBuiltin(rec.scriptid or "") ~= nil then
                    source = "Built-in"
                end

                local rowChildren = {}

                rowChildren[#rowChildren + 1] = gui.Label{
                    fontSize = 13,
                    width = "40%",
                    height = "auto",
                    valign = "center",
                    textWrap = true,
                    text = rec.name or "Map Script",
                }

                rowChildren[#rowChildren + 1] = gui.Label{
                    classes = { "fgMuted", "sizeXxs" },
                    width = 50,
                    height = "auto",
                    valign = "center",
                    text = source,
                }

                if MapScript.RecordIsCustom(rec) then
                    rowChildren[#rowChildren + 1] = gui.Label{
                        classes = { "link" },
                        fontSize = 12,
                        width = "auto",
                        height = "auto",
                        valign = "center",
                        hmargin = 4,
                        text = "Edit...",
                        press = function()
                            EditCustomRecord(rec.guid, Refresh)
                        end,
                    }
                end

                rowChildren[#rowChildren + 1] = gui.DeleteItemButton{
                    width = 16,
                    height = 16,
                    valign = "center",
                    halign = "right",
                    click = function()
                        MutateRecords(function(records2)
                            for i, r in ipairs(records2) do
                                if r.guid == rec.guid then
                                    table.remove(records2, i)
                                    break
                                end
                            end
                        end)
                        Refresh()
                    end,
                }

                children[#children + 1] = gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    vmargin = 2,
                    children = rowChildren,
                }

                if def == nil then
                    children[#children + 1] = gui.Label{
                        fontSize = 11,
                        color = "#ff9999",
                        width = "100%",
                        height = "auto",
                        textWrap = true,
                        bmargin = 4,
                        text = tostring(entry.defError),
                    }
                elseif #def.params > 0 then
                    local paramPanels = {}
                    for _, param in ipairs(def.params) do
                        paramPanels[#paramPanels + 1] = BuildParamEditor(rec, param)
                    end
                    children[#children + 1] = gui.Panel{
                        width = "94%",
                        height = "auto",
                        halign = "right",
                        flow = "vertical",
                        bmargin = 4,
                        children = paramPanels,
                    }
                end
            end

            --the add picker: built-ins + library scripts + custom.
            local addOptions = { { id = "none", text = "Add Script..." } }
            MapScript.FillPickerOptions(addOptions)
            addOptions[#addOptions + 1] = { id = "custom", text = "Custom Lua Script..." }

            children[#children + 1] = gui.Dropdown{
                classes = { "form" },
                width = "100%",
                height = 26,
                fontSize = 12,
                tmargin = 6,
                options = addOptions,
                idChosen = "none",
                change = function(element2)
                    local chosen = element2.idChosen
                    if chosen == "none" then
                        return
                    end
                    if chosen == "custom" then
                        local rec = MapScript.CreateCustomRecord()
                        MutateRecords(function(records2)
                            records2[#records2 + 1] = rec
                        end)
                        Refresh()
                        EditCustomRecord(rec.guid, Refresh)
                    else
                        MutateRecords(function(records2)
                            records2[#records2 + 1] = MapScript.CreateRecordFromLibrary(chosen)
                        end)
                        Refresh()
                    end
                end,
            }

            element.children = children
        end,
    }

    return resultPanel
end

-- ---------------------------------------------------------------------------
-- Compendium page (Rules > Map Scripts)
-- ---------------------------------------------------------------------------

local UploadScriptWithId = function(id)
    local dataTable = dmhub.GetTable(MapScript.tableName) or {}
    if dataTable[id] ~= nil then
        dmhub.SetAndUploadTableItem(MapScript.tableName, dataTable[id])
    end
end

local ScriptCompendiumSetData = function(tableName, scriptPanel, keyid)
    local dataTable = dmhub.GetTable(tableName) or {}
    local script = dataTable[keyid]
    if script == nil then
        return
    end
    local UploadScript = function()
        dmhub.SetAndUploadTableItem(tableName, script)
    end

    --if we were displaying a different script and it has unsaved changes, flush it.
    if scriptPanel.data.keyid ~= "" and scriptPanel.data.keyid ~= keyid and dmhub.ToJson(dataTable[scriptPanel.data.keyid]) ~= scriptPanel.data.scriptjson then
        UploadScriptWithId(scriptPanel.data.keyid)
    end

    scriptPanel.data.keyid = keyid
    scriptPanel.data.scriptjson = dmhub.ToJson(script)

    local children = {}

    if devmode() then
        children[#children + 1] = gui.Panel{
            classes = { "formStackedRow" },
            gui.Label{
                classes = { "formStacked" },
                text = "ID:",
            },
            gui.Input{
                classes = { "formStacked" },
                text = script.id,
                editable = false,
            },
        }
    end

    children[#children + 1] = gui.Panel{
        classes = { "formStackedRow" },
        gui.Label{
            classes = { "formStacked" },
            text = "Name:",
        },
        gui.Input{
            classes = { "formStacked" },
            text = script.name,
            change = function(element)
                script.name = element.text
                UploadScript()
            end,
        },
    }

    children[#children + 1] = gui.Panel{
        classes = { "formStackedRow" },
        gui.Label{
            classes = { "formStacked" },
            text = "Details:",
        },
        gui.Input{
            classes = { "formStacked" },
            text = script.description,
            multiline = true,
            textAlignment = "topLeft",
            height = 60,
            characterLimit = 600,
            change = function(element)
                script.description = element.text
                UploadScript()
            end,
        },
    }

    children[#children + 1] = MapScript.CreateCodePanel{
        width = 800,
        height = 420,
        getText = function()
            return script:try_get("code", "")
        end,
        setText = function(text)
            script.code = text
            UploadScript()
        end,
    }

    scriptPanel.children = children
end

function MapScript.CreateEditor()
    local scriptPanel
    scriptPanel = gui.Panel{
        data = {
            SetData = function(tableName, keyid)
                ScriptCompendiumSetData(tableName, scriptPanel, keyid)
            end,
            keyid = "",
            scriptjson = "",
        },
        destroy = function(element)
            local dataTable = dmhub.GetTable(MapScript.tableName) or {}
            if element.data.keyid ~= "" and dataTable[element.data.keyid] ~= nil and dmhub.ToJson(dataTable[element.data.keyid]) ~= element.data.scriptjson then
                UploadScriptWithId(element.data.keyid)
            end
        end,
        vscroll = true,
        width = 1200,
        height = "90%",
        halign = "left",
        flow = "vertical",
        pad = 20,
        borderBox = true,
    }

    return scriptPanel
end

local ShowMapScriptsPanel = function(contentPanel)
    local scriptPanel = MapScript.CreateEditor()
    local SetData = scriptPanel.data.SetData

    local listItems = {}

    local itemsListPanel
    itemsListPanel = gui.Panel{
        classes = { "list-panel" },
        vscroll = true,
        monitorAssets = true,
        refreshAssets = function(element)
            local children = {}
            local dataTable = dmhub.GetTable(MapScript.tableName) or {}
            local newListItems = {}

            for k, item in pairs(dataTable) do
                newListItems[k] = listItems[k] or Compendium.CreateListItem{
                    select = element.aliveTime > 0.2,
                    tableName = MapScript.tableName,
                    key = k,
                    click = function()
                        SetData(MapScript.tableName, k)
                    end,
                }

                newListItems[k].text = item.name

                children[#children + 1] = newListItems[k]
            end

            table.sort(children, function(a, b) return a.text < b.text end)

            listItems = newListItems
            itemsListPanel.children = children
        end,
    }

    itemsListPanel:FireEvent("refreshAssets")

    local leftPanel = gui.Panel{
        selfStyle = {
            flow = "vertical",
            height = "100%",
            width = "auto",
        },

        itemsListPanel,
        Compendium.AddButton{
            click = function(element)
                dmhub.SetAndUploadTableItem(MapScript.tableName, MapScript.CreateNew())
            end,
        },
    }

    contentPanel.children = { leftPanel, scriptPanel }
end

Compendium.Register{
    section = "Rules",
    text = "Map Scripts",
    contentType = MapScript.tableName,
    click = function(contentPanel)
        ShowMapScriptsPanel(contentPanel)
    end,
}

-- ---------------------------------------------------------------------------
-- Built-in starter scripts
-- ---------------------------------------------------------------------------
-- These double as the tutorial: pick one in Map Settings, or use Custom Lua
-- Script and crib from them.

MapScript.RegisterBuiltin{
    id = "builtin:timed-announcement",
    name = "Timed Announcement",
    description = "Posts a chat message at a regular interval while the map is active.",
    code = [==[
return {
    name = "Timed Announcement",
    description = "Posts a chat message at a regular interval while the map is active.",

    params = {
        { id = "message", name = "Message", type = "string", default = "The wind howls through the trees..." },
        { id = "minutes", name = "Interval (minutes)", type = "number", default = 5, min = 1, max = 240 },
    },

    hostThink = function(ctx)
        local shared = ctx:GetShared()
        local now = dmhub.serverTime
        local interval = ctx.params.minutes * 60
        local last = shared.lastAnnounce
        --last > now guards server-time rebasing across sessions.
        if last ~= nil and last <= now and now - last < interval then
            return
        end
        ctx:Announce(ctx.params.message)
        ctx:ModifyShared(function(s) s.lastAnnounce = now end)
    end,
    hostThinkInterval = 5,
}
]==],
}

MapScript.RegisterBuiltin{
    id = "builtin:first-visit",
    name = "First Visit Announcement",
    description = "Posts a chat message the first time this map is activated, once ever.",
    code = [==[
return {
    name = "First Visit Announcement",
    description = "Posts a chat message the first time this map is activated, once ever.",

    params = {
        { id = "message", name = "Message", type = "string", default = "You arrive somewhere new." },
    },

    hostThink = function(ctx)
        ctx:RunOnce("first-visit", function()
            ctx:Announce(ctx.params.message)
        end)
    end,
    hostThinkInterval = 2,
}
]==],
}

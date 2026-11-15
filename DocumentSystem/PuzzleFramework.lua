local mod = dmhub.GetModLoading()

-- Puzzle framework: a registry of puzzle types (each one Lua file calling
-- PuzzleType.Register) and the shared state of puzzle instances. Surfaces render
-- a puzzle by id; see RichPuzzle.lua.
--
-- "puzzle-<id>" holds the board and is NOT checkpointed, so Revert Turn never
-- throws away puzzle progress; "puzzlestatus" (all puzzles, keyed by id) is.
-- Types must store keyed tables or strings, never Lua arrays: an array is
-- uploaded whole, so two players' moves to it overwrite each other.

---@class PuzzleField
---@field id string config key
---@field type "text"|"multiline"|"number"|"toggle"|"choice"|"image"|"custom"
---@field label string
---@field default any
---@field options? {id: string, text: string}[] for "choice"
---@field min? number for "number"
---@field max? number for "number"
---@field Control? fun(config: table, setConfig: fun(changes: table)): Panel|nil for "custom": the type draws the control
---@field visible? fun(config: table): boolean hide the field unless this returns true

---@class PuzzleRole
---@field id string
---@field name string

---@class PuzzleAssist
---@field id string
---@field label string

---@class PuzzleTypeDef
---@field id string
---@field name string
---@field fields PuzzleField[]
---@field roles? PuzzleRole[]
---@field assists? PuzzleAssist[]
---@field NewState fun(config: table, ctx: PuzzleContext): table a fresh scrambled board
---@field IsSolved fun(state: table, config: table): boolean
---@field IsFailed? fun(state: table, config: table, now: number): boolean
---@field SolvedState? fun(config: table): table a finished board, for Director Solve
---@field Hint? fun(state: table, config: table): string|nil
---@field Status? fun(state: table, config: table): string|nil one line under the puzzle, e.g. "Moves: 4"
---@field ConfigKey? fun(config: table): string boards made for a different key are discarded
---@field Render fun(ctx: PuzzleContext): Panel built once; refreshed with the "refreshPuzzle" event
---@field CreateEditor? fun(puzzleid: string, config: table, setConfig: fun(changes: table)): Panel|nil
---@field HostTick? fun(id: string) runs about once a second on the host for every puzzle of this type
---@field HandleRequest? PuzzleRequestHandler the host applies players' requests (Puzzle.Request); types with their own HostTick call Puzzle.ProcessRequests instead
---@field noTimeLimit? boolean the framework's time limit is not offered for this type

---@class PuzzleStatus
---@field solved boolean|nil
---@field solvedBy string|nil userid, or "director"
---@field solvedAt number|nil serverTime
---@field bypassed boolean|nil solved by the Director's Bypass, not by the board
---@field failed boolean|nil
---@field deadline number|nil serverTime the timer runs out
---@field remaining number|nil seconds left while the timer is paused
---@field announced boolean|nil the solve or fail chat line has been posted
---@field hint boolean|nil the Director has revealed the type's hint
---@field applied table<string, boolean>|nil effects claimed by the host, so none runs twice
---@field effectsDone boolean|nil the outcome handlers have run for this solve or failure
---@field bypassWithFail boolean|nil bypassed at a cost: run the fail effects as well

Puzzle = {}
PuzzleType = {}

local STATUS_DOC = "puzzlestatus"
local BOARD_PREFIX = "puzzle-"
--Who has which puzzle open, and Director pushes. Not checkpointed.
local PRESENCE_DOC = "puzzlepresence"
--Every puzzle in the game and where it lives, for the Director's puzzle list
--(there is no way to list a game's documents from Lua).
local INDEX_DOC = "puzzleindex"

--A player counts as at a puzzle this long after their window's last heartbeat.
local PRESENCE_FRESH_SECONDS = 30

--A hold left by a client that vanished mid-move stops blocking others after this.
local HOLD_EXPIRY_SECONDS = 20

---@type table<string, PuzzleTypeDef>
local g_types = {}

--Per-client, never synced: which assists this player has switched on, and what
--they have picked up with the click-to-place helper. Keyed by puzzle id.
---@type table<string, table<string, boolean>>
local g_assists = {}
---@type table<string, string|nil>
local g_picked = {}
---@type table<string, string>
local g_holdNonces = {}
---@type table<string, number>
local g_holdSeen = {}

pcall(function()
    mod:RegisterDocumentForCheckpointBackups(STATUS_DOC)
end)
--Puzzle writes never change creature stats; without this every move would rebuild
--every creature's modifiers on every client.
pcall(function()
    CreatureCache.RegisterRulesNeutralDocument(BOARD_PREFIX, nil)
    CreatureCache.RegisterRulesNeutralDocument(STATUS_DOC, nil)
    CreatureCache.RegisterRulesNeutralDocument(PRESENCE_DOC, nil)
    CreatureCache.RegisterRulesNeutralDocument(INDEX_DOC, nil)
end)

--Code that reacts to a puzzle's outcome (map locks applying their effects).
--Each handler: { apply = fun(id, outcome, status), undo = fun(id, status) }.
--apply runs on the host only; undo runs on whichever client presses Reset.
---@type table<string, {apply: fun(id: string, outcome: string, status: PuzzleStatus), undo: fun(id: string, status: PuzzleStatus)}>
local g_outcomeHandlers = {}

---@param key string
---@param handler {apply: fun(id: string, outcome: string, status: PuzzleStatus), undo: fun(id: string, status: PuzzleStatus)}
function Puzzle.RegisterOutcomeHandler(key, handler)
    g_outcomeHandlers[key] = handler
end

local g_timerSetting = setting{
    id = "puzzletimers",
    description = "Puzzle timers",
    storage = "game",
    default = "normal",
    editor = "dropdown",
    section = "Game",
    enum = {
        { value = "normal", text = "Normal" },
        { value = "double", text = "Double time" },
        { value = "off", text = "Off" },
    },
}

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

--Register a puzzle type. Registering an id again replaces it (hot reload).
---@param def PuzzleTypeDef
function PuzzleType.Register(def)
    assert(type(def.id) == "string" and def.id ~= "", "PuzzleType.Register: id required")
    assert(def.NewState ~= nil and def.IsSolved ~= nil and def.Render ~= nil,
        "PuzzleType.Register: NewState, IsSolved and Render are required")
    def.fields = def.fields or {}
    g_types[def.id] = def
end

---@param typeid string|nil
---@return PuzzleTypeDef|nil
function PuzzleType.Get(typeid)
    if typeid == nil then
        return nil
    end
    return g_types[typeid]
end

--Every registered type, sorted by name.
---@return PuzzleTypeDef[]
function PuzzleType.List()
    local result = {}
    for _, def in pairs(g_types) do
        result[#result + 1] = def
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--Cloud keys may not contain . $ # [ ] / and similar; keep ids to a safe set.
---@param raw string
---@return string
function Puzzle.SafeId(raw)
    return (string.gsub(tostring(raw), "[^%w_%-]", "_"))
end

--A small seeded generator so every client computes the same board from the same
--seed. Returns random(k): an integer in 1..k.
---@param seedText string
---@return fun(k: integer): integer
function Puzzle.SeededRandom(seedText)
    local seed = 7
    for i = 1, #seedText do
        seed = (seed * 31 + string.byte(seedText, i)) % 2147483648
    end
    return function(k)
        seed = (seed * 1103515245 + 12345) % 2147483648
        return (seed // 65536) % k + 1
    end
end

---@param userid string|nil
---@return string
function Puzzle.UserName(userid)
    if userid == nil then
        return "Someone"
    end
    local info = dmhub.GetSessionInfo(userid)
    if info ~= nil and info.displayName ~= nil and info.displayName ~= "" then
        return info.displayName
    end
    return "Someone"
end

---@param t any
---@return any
local function DeepCopy(t)
    if type(t) ~= "table" then
        return t
    end
    local result = {}
    for k, v in pairs(t) do
        result[k] = DeepCopy(v)
    end
    return result
end

---@param id string
---@return string
function Puzzle.BoardDocId(id)
    return BOARD_PREFIX .. id
end

--The path a panel's monitorGame watches to refresh on any change to the puzzle.
---@param id string
---@return string[]
function Puzzle.MonitorPaths(id)
    return { mod:GetDocumentPath(Puzzle.BoardDocId(id)), mod:GetDocumentPath(STATUS_DOC) }
end

---@param id string
---@return table
local function BoardData(id)
    return mod:GetDocumentSnapshot(Puzzle.BoardDocId(id)).data
end

---@param id string
---@param fn fun(data: table)
---@param description string
local function WriteBoardDoc(id, fn, description)
    local doc = mod:GetDocumentSnapshot(Puzzle.BoardDocId(id))
    doc:BeginChange()
    fn(doc.data)
    doc:CompleteChange(description, {undoable = false})
end

---@param id string
---@return PuzzleStatus
function Puzzle.Status(id)
    local entry = mod:GetDocumentSnapshot(STATUS_DOC).data[id]
    if type(entry) ~= "table" then
        return {}
    end
    return entry
end

---@param id string
---@param fn fun(status: PuzzleStatus)
---@param description string
local function WriteStatus(id, fn, description)
    local doc = mod:GetDocumentSnapshot(STATUS_DOC)
    doc:BeginChange()
    local entry = doc.data[id]
    if type(entry) ~= "table" then
        entry = {}
        doc.data[id] = entry
    end
    fn(entry)
    doc:CompleteChange(description, {undoable = false})
end

--------------------------------------------------------------------------------
-- Instances: type, title, config
--------------------------------------------------------------------------------

---@param id string
---@return string|nil
function Puzzle.GetTypeId(id)
    local typeid = BoardData(id).type
    if type(typeid) == "string" then
        return typeid
    end
    return nil
end

---@param id string
---@return PuzzleTypeDef|nil
function Puzzle.GetType(id)
    return PuzzleType.Get(Puzzle.GetTypeId(id))
end

--True once a puzzle has a type, i.e. it has been set up.
---@param id string
---@return boolean
function Puzzle.Exists(id)
    return Puzzle.GetType(id) ~= nil
end

--One place a puzzle lives. A puzzle can live in several (a lock and a page).
--table and rail are the Director's own table item and rail button.
---@class PuzzleHome
---@field kind "lock"|"journal"|"table"|"rail"
---@field floorid string|nil a lock's floor
---@field objid string|nil a lock's object
---@field docid string|nil a journal puzzle's page
---@field tag string|nil a journal puzzle's tag key on its page ("puzzle:Vault")
---@field placed "component"|"object"|nil what placing it added; removing the home takes that away too

---@class PuzzleIndexEntry
---@field kind "lock"|"journal"|"standalone"|nil standalone: made in the Puzzles panel. lock/journal: an old entry's one home
---@field floorid string|nil an old entry's lock floor
---@field objid string|nil an old entry's lock object
---@field docid string|nil an old entry's page
---@field homes table<string, PuzzleHome>|nil home key -> home

--Every puzzle the index knows: id -> entry. Read homes with Puzzle.Homes.
---@return table<string, PuzzleIndexEntry>
function Puzzle.Index()
    local result = {}
    for id, entry in pairs(mod:GetDocumentSnapshot(INDEX_DOC).data) do
        if type(entry) == "table" then
            result[id] = entry
        end
    end
    return result
end

---@param home PuzzleHome|PuzzleIndexEntry
---@return string|nil
function Puzzle.HomeKey(home)
    if home.kind == "lock" and home.floorid ~= nil and home.objid ~= nil then
        return Puzzle.SafeId(string.format("lock_%s_%s", home.floorid, home.objid))
    elseif home.kind == "journal" and home.docid ~= nil then
        return Puzzle.SafeId(string.format("journal_%s_%s", home.docid, tostring(home.tag or "")))
    elseif home.kind == "table" or home.kind == "rail" then
        return home.kind
    end
    return nil
end

--The key of a home already listed for the same lock or page. An old entry's
--page home has no tag, so it matches any tag on that page.
---@param homes table<string, PuzzleHome>
---@param home PuzzleHome
---@return string|nil
local function SameHome(homes, home)
    for key, h in pairs(homes) do
        if h.kind == home.kind then
            if home.kind == "lock" and h.floorid == home.floorid and h.objid == home.objid then
                return key
            elseif home.kind == "journal" and h.docid == home.docid and (h.tag == nil or home.tag == nil or h.tag == home.tag) then
                return key
            elseif home.kind == "table" or home.kind == "rail" then
                return key
            end
        end
    end
    return nil
end

---@param entry PuzzleIndexEntry
---@return PuzzleHome|nil
local function LegacyHome(entry)
    if entry.kind ~= "lock" and entry.kind ~= "journal" then
        return nil
    end
    return { kind = entry.kind, floorid = entry.floorid, objid = entry.objid, docid = entry.docid }
end

--Every place a puzzle lives: home key -> home.
---@param id string
---@return table<string, PuzzleHome>
function Puzzle.Homes(id)
    local entry = mod:GetDocumentSnapshot(INDEX_DOC).data[id]
    local result = {}
    if type(entry) ~= "table" then
        return result
    end
    for key, home in pairs(entry.homes or {}) do
        if type(home) == "table" then
            result[key] = home
        end
    end
    local legacy = LegacyHome(entry)
    local key = legacy ~= nil and Puzzle.HomeKey(legacy) or nil
    if key ~= nil and SameHome(result, legacy --[[@as PuzzleHome]]) == nil then
        result[key] = legacy
    end
    return result
end

---@param id string
---@param fn fun(entry: PuzzleIndexEntry)
local function WriteIndex(id, fn)
    local doc = mod:GetDocumentSnapshot(INDEX_DOC)
    doc:BeginChange()
    local entry = doc.data[id]
    if type(entry) ~= "table" then
        entry = {}
        doc.data[id] = entry
    end
    --an old entry's one home moves into homes, so homes is the only list.
    local legacy = LegacyHome(entry)
    if legacy ~= nil then
        entry.homes = entry.homes or {}
        local key = Puzzle.HomeKey(legacy)
        if key ~= nil and SameHome(entry.homes, legacy) == nil then
            entry.homes[key] = legacy
        end
        entry.kind, entry.floorid, entry.objid, entry.docid = nil, nil, nil, nil
    end
    fn(entry)
    doc:CompleteChange("Index puzzle", {undoable = false})
end

--Record a puzzle in the index, and one more place it lives when info is a
--lock or a page. Writes only when something is new, so surfaces can call it
--every time they show a puzzle. A page home recorded without its tag gains it.
---@param id string
---@param info PuzzleHome|{kind: "standalone"}|nil
function Puzzle.IndexPuzzle(id, info)
    local current = mod:GetDocumentSnapshot(INDEX_DOC).data[id]
    local home = nil
    if info ~= nil and info.kind ~= "standalone" then
        home = info --[[@as PuzzleHome]]
    end
    local standalone = info ~= nil and info.kind == "standalone"
    if type(current) == "table" then
        if home == nil then
            if not standalone or current.kind ~= nil then
                return
            end
        else
            local homes = Puzzle.Homes(id)
            local key = SameHome(homes, home)
            if key ~= nil and (home.tag == nil or homes[key].tag == home.tag) then
                return
            end
        end
    end
    WriteIndex(id, function(entry)
        if home == nil then
            if standalone and entry.kind == nil then
                entry.kind = "standalone"
            end
            return
        end
        entry.homes = entry.homes or {}
        local old = SameHome(entry.homes, home)
        if old ~= nil then
            entry.homes[old] = nil
        end
        local copy = {}
        for k, v in pairs(home) do
            copy[k] = v
        end
        entry.homes[Puzzle.HomeKey(home) or Puzzle.SafeId(dmhub.GenerateGuid())] = copy
    end)
end

--Take one place out of a puzzle's homes. The puzzle itself stays.
---@param id string
---@param key string
function Puzzle.RemoveHome(id, key)
    if Puzzle.Homes(id)[key] == nil then
        return
    end
    WriteIndex(id, function(entry)
        if entry.homes ~= nil then
            entry.homes[key] = nil
        end
    end)
end

--Forget a puzzle whose lock or page is gone: clear its board, status, presence
--and index entry. The documents stay but are empty.
---@param id string
function Puzzle.Forget(id)
    WriteBoardDoc(id, function(data)
        for k in pairs(data) do
            data[k] = nil
        end
    end, "Remove puzzle")
    for _, docid in ipairs({ STATUS_DOC, PRESENCE_DOC, INDEX_DOC }) do
        local doc = mod:GetDocumentSnapshot(docid)
        if doc.data[id] ~= nil then
            doc:BeginChange()
            doc.data[id] = nil
            doc:CompleteChange("Remove puzzle", {undoable = false})
        end
    end
end

--Paths the puzzle list watches.
---@return string[]
function Puzzle.ListMonitorPaths()
    return { mod:GetDocumentPath(INDEX_DOC), mod:GetDocumentPath(STATUS_DOC), mod:GetDocumentPath(PRESENCE_DOC) }
end

--Create a puzzle (or change its type). Changing type discards the old board.
---@param id string
---@param typeid string
---@param config table|nil starting config; defaults fill the rest
---@param title string|nil
function Puzzle.Create(id, typeid, config, title)
    WriteBoardDoc(id, function(data)
        data.type = typeid
        data.config = DeepCopy(config or {})
        data.state = nil
        data.stateKey = nil
        data.holds = nil
        data.kept = nil
        if title ~= nil then
            data.title = title
        end
    end, "Set up puzzle")
    WriteStatus(id, function(status)
        for k in pairs(status) do
            status[k] = nil
        end
    end, "Set up puzzle")
    Puzzle.IndexPuzzle(id, nil)
end

---@param id string
---@return string
function Puzzle.Title(id)
    local title = BoardData(id).title
    if type(title) == "string" and title ~= "" then
        return title
    end
    return "the puzzle"
end

---@param id string
---@param title string
function Puzzle.SetTitle(id, title)
    if BoardData(id).title == title then
        return
    end
    WriteBoardDoc(id, function(data) data.title = title end, "Name puzzle")
end

--The puzzle's config with every field's default filled in. A copy: write
--changes back with Puzzle.SetConfig.
---@param id string
---@return table
function Puzzle.ReadConfig(id)
    local stored = BoardData(id).config
    local config = DeepCopy(type(stored) == "table" and stored or {})
    local def = Puzzle.GetType(id)
    if def ~= nil then
        for _, field in ipairs(def.fields) do
            if config[field.id] == nil then
                config[field.id] = DeepCopy(field.default)
            end
        end
    end
    if config.timeLimit == nil then
        config.timeLimit = 0
    end
    return config
end

--Director setup changes, merged into the stored config.
---@param id string
---@param changes table
function Puzzle.SetConfig(id, changes)
    WriteBoardDoc(id, function(data)
        if type(data.config) ~= "table" then
            data.config = {}
        end
        for k, v in pairs(changes) do
            data.config[k] = DeepCopy(v)
        end
    end, "Change puzzle setup")
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

---@param def PuzzleTypeDef
---@param config table
---@return string
local function StateKey(def, config)
    if def.ConfigKey ~= nil then
        return tostring(def.ConfigKey(config))
    end
    return ""
end

--The puzzle's current board. A puzzle nobody has touched yet (or whose setup
--changed shape) gets a board scrambled from a seed derived from its id, so
--every client sees the same opening without anyone writing it first.
---@param id string
---@return table|nil state, table config
function Puzzle.ReadState(id)
    local def = Puzzle.GetType(id)
    local config = Puzzle.ReadConfig(id)
    if def == nil then
        return nil, config
    end
    local data = BoardData(id)
    local key = StateKey(def, config)
    if type(data.state) == "table" and data.stateKey == key then
        return DeepCopy(data.state), config
    end
    local seed = string.format("%s:%s", id, key)
    local ctx = Puzzle.Context(id, { seed = seed, config = config })
    return def.NewState(config, ctx), config
end

--Mark the puzzle solved or failed if its board now says so.
---@param id string
---@param def PuzzleTypeDef
---@param state table
---@param config table
local function CheckOutcome(id, def, state, config)
    local status = Puzzle.Status(id)
    if status.solved or status.failed then
        return
    end
    if def.IsSolved(state, config) then
        WriteStatus(id, function(s)
            s.solved = true
            s.solvedBy = dmhub.userid
            s.solvedAt = dmhub.serverTime
        end, "Solve puzzle")
    elseif def.IsFailed ~= nil and def.IsFailed(state, config, dmhub.serverTime) then
        WriteStatus(id, function(s)
            s.failed = true
        end, "Fail puzzle")
    end
end

--Apply a move: fn edits a copy of the state, which is then saved (only the
--fields that changed go up) and checked for a solve or failure.
---@param id string
---@param fn fun(state: table, config: table): boolean|nil return false to cancel the write
---@param description string|nil
function Puzzle.Change(id, fn, description)
    local def = Puzzle.GetType(id)
    if def == nil then
        return
    end
    local state, config = Puzzle.ReadState(id)
    if state == nil then
        return
    end
    if fn(state, config) == false then
        return
    end
    local key = StateKey(def, config)
    WriteBoardDoc(id, function(data)
        data.state = state
        data.stateKey = key
    end, description or "Puzzle move")
    CheckOutcome(id, def, state, config)
end

--Write a board and status as-is, for migrating puzzles saved before the
--framework existed. Does not check for a solve or post a chat line.
---@param id string
---@param state table
---@param status PuzzleStatus|nil
function Puzzle.ImportState(id, state, status)
    local def = Puzzle.GetType(id)
    if def == nil then
        return
    end
    local key = StateKey(def, Puzzle.ReadConfig(id))
    WriteBoardDoc(id, function(data)
        data.state = DeepCopy(state)
        data.stateKey = key
    end, "Import puzzle")
    if status ~= nil then
        WriteStatus(id, function(s)
            for k, v in pairs(status) do
                s[k] = v
            end
        end, "Import puzzle")
    end
end

--Kept data: what a puzzle remembers through a Reset (who has rolled a once-only
--test, what it revealed). Cleared only when the puzzle is set up again.
---@param id string
---@return table
function Puzzle.ReadKept(id)
    local kept = BoardData(id).kept
    if type(kept) ~= "table" then
        return {}
    end
    return DeepCopy(kept)
end

--fn edits the kept table in place, so only the fields it touches go up. Keyed
--tables only, as for boards.
---@param id string
---@param fn fun(kept: table)
---@param description string|nil
function Puzzle.ChangeKept(id, fn, description)
    WriteBoardDoc(id, function(data)
        if type(data.kept) ~= "table" then
            data.kept = {}
        end
        fn(data.kept)
    end, description or "Puzzle kept data")
end

--Director: a fresh board from a new seed, and the status cleared. Kept data stays.
---@param id string
function Puzzle.Reset(id)
    local def = Puzzle.GetType(id)
    if def == nil then
        return
    end
    local config = Puzzle.ReadConfig(id)
    local ctx = Puzzle.Context(id, { seed = dmhub.GenerateGuid(), config = config })
    local state = def.NewState(config, ctx)
    local key = StateKey(def, config)
    g_picked[id] = nil
    local oldStatus = Puzzle.Status(id)
    for handlerKey, handler in pairs(g_outcomeHandlers) do
        local ok, err = pcall(handler.undo, id, oldStatus)
        if not ok then
            print("PUZZLE:: undo failed in", handlerKey, err)
        end
    end
    WriteBoardDoc(id, function(data)
        data.state = state
        data.stateKey = key
        data.holds = nil
    end, "Reset puzzle")
    WriteStatus(id, function(status)
        for k in pairs(status) do
            status[k] = nil
        end
    end, "Reset puzzle")
end

--Director: finish the board (when the type can) and mark it solved.
---@param id string
function Puzzle.Solve(id)
    local def = Puzzle.GetType(id)
    if def == nil then
        return
    end
    if def.SolvedState ~= nil then
        local config = Puzzle.ReadConfig(id)
        local state = def.SolvedState(config)
        local key = StateKey(def, config)
        WriteBoardDoc(id, function(data)
            data.state = state
            data.stateKey = key
            data.holds = nil
        end, "Solve puzzle")
        WriteStatus(id, function(status)
            status.solved = true
            status.failed = nil
            status.announced = nil
            status.effectsDone = nil
            status.solvedBy = "director"
            status.solvedAt = dmhub.serverTime
        end, "Solve puzzle")
    else
        Puzzle.Bypass(id)
    end
end

--Director (or the host of a game with no Director): get past the puzzle without
--touching the board. Works for every type.
--opts.withFail: the way through came at a cost; the lock's fail effects run too
--(a Draw Steel tier 2 bypass test).
---@param id string
---@param opts {withFail: boolean|nil}|nil
function Puzzle.Bypass(id, opts)
    local withFail = opts ~= nil and opts.withFail == true
    WriteStatus(id, function(status)
        status.solved = true
        status.bypassed = true
        status.bypassWithFail = withFail or nil
        status.failed = nil
        status.announced = nil
        status.effectsDone = nil
        status.solvedBy = "director"
        status.solvedAt = dmhub.serverTime
    end, "Bypass puzzle")
end

--Claim an effect before applying it: true at most once per key until a Reset,
--so a host handing over mid-way never applies the same effect twice.
---@param id string
---@param key string
---@return boolean
function Puzzle.ClaimEffect(id, key)
    local applied = Puzzle.Status(id).applied
    if type(applied) == "table" and applied[key] then
        return false
    end
    WriteStatus(id, function(status)
        if type(status.applied) ~= "table" then
            status.applied = {}
        end
        status.applied[key] = true
    end, "Apply puzzle effect")
    return true
end

---@param id string
function Puzzle.RevealHint(id)
    WriteStatus(id, function(status) status.hint = true end, "Reveal puzzle hint")
end

--------------------------------------------------------------------------------
-- Timers
--------------------------------------------------------------------------------

--The configured limit in seconds after the game's timer setting, or 0 for none.
---@param config table
---@return number
function Puzzle.EffectiveLimit(config)
    local minutes = tonumber(config.timeLimit) or 0
    if minutes <= 0 then
        return 0
    end
    local mode = g_timerSetting:Get()
    if mode == "off" then
        return 0
    elseif mode == "double" then
        return minutes * 120
    end
    return minutes * 60
end

--Seconds left, or nil when no timer is running or paused.
---@param id string
---@return number|nil
function Puzzle.TimeLeft(id)
    local status = Puzzle.Status(id)
    if status.remaining ~= nil then
        return status.remaining
    end
    if status.deadline ~= nil then
        return math.max(0, status.deadline - dmhub.serverTime)
    end
    return nil
end

---@param id string
---@return boolean
function Puzzle.TimerPaused(id)
    return Puzzle.Status(id).remaining ~= nil
end

---@param id string
function Puzzle.StartTimer(id)
    local limit = Puzzle.EffectiveLimit(Puzzle.ReadConfig(id))
    if limit <= 0 then
        return
    end
    WriteStatus(id, function(status)
        status.deadline = dmhub.serverTime + limit
        status.remaining = nil
    end, "Start puzzle timer")
end

---@param id string
function Puzzle.PauseTimer(id)
    local left = Puzzle.TimeLeft(id)
    if left == nil then
        return
    end
    WriteStatus(id, function(status)
        status.remaining = left
        status.deadline = nil
    end, "Pause puzzle timer")
end

---@param id string
function Puzzle.ResumeTimer(id)
    local status = Puzzle.Status(id)
    if status.remaining == nil then
        return
    end
    local left = status.remaining
    WriteStatus(id, function(s)
        s.deadline = dmhub.serverTime + left
        s.remaining = nil
    end, "Resume puzzle timer")
end

---@param id string
---@param seconds number
function Puzzle.ExtendTimer(id, seconds)
    WriteStatus(id, function(status)
        if status.remaining ~= nil then
            status.remaining = status.remaining + seconds
        elseif status.deadline ~= nil then
            status.deadline = math.max(status.deadline, dmhub.serverTime) + seconds
        end
    end, "Extend puzzle timer")
end

--------------------------------------------------------------------------------
-- Holds: one player at a time on a piece
--------------------------------------------------------------------------------

--The name of another player holding key, or nil. A hold goes stale
--HOLD_EXPIRY_SECONDS after THIS client first saw it, so no shared clock is needed.
---@param id string
---@param key string
---@return string|nil
function Puzzle.HeldBy(id, key)
    local holds = BoardData(id).holds
    local hold = type(holds) == "table" and holds[key] or nil
    if type(hold) ~= "table" or hold.user == dmhub.userid then
        return nil
    end
    local nonce = tostring(hold.nonce)
    local seen = g_holdSeen[nonce]
    if seen == nil then
        seen = dmhub.Time()
        g_holdSeen[nonce] = seen
    end
    if dmhub.Time() - seen > HOLD_EXPIRY_SECONDS then
        return nil
    end
    return Puzzle.UserName(hold.user)
end

--Claim key for this player. False when someone else already holds it.
---@param id string
---@param key string
---@return boolean
function Puzzle.Hold(id, key)
    if Puzzle.HeldBy(id, key) ~= nil then
        return false
    end
    local nonce = dmhub.GenerateGuid()
    g_holdNonces[id .. "/" .. key] = nonce
    WriteBoardDoc(id, function(data)
        if type(data.holds) ~= "table" then
            data.holds = {}
        end
        data.holds[key] = { user = dmhub.userid, nonce = nonce }
    end, "Pick up puzzle piece")
    return true
end

--Let go of key, if this player still holds it.
---@param id string
---@param key string
function Puzzle.Release(id, key)
    local localKey = id .. "/" .. key
    local nonce = g_holdNonces[localKey]
    g_holdNonces[localKey] = nil
    local holds = BoardData(id).holds
    local hold = type(holds) == "table" and holds[key] or nil
    if nonce == nil or type(hold) ~= "table" or hold.nonce ~= nonce then
        return
    end
    WriteBoardDoc(id, function(data)
        data.holds[key] = nil
    end, "Put down puzzle piece")
end

--True while any hold on the puzzle is live (so panels re-check expiry).
---@param id string
---@return boolean
function Puzzle.AnyHolds(id)
    local holds = BoardData(id).holds
    return type(holds) == "table" and next(holds) ~= nil
end

--------------------------------------------------------------------------------
-- Context: what a type's Render works with
--------------------------------------------------------------------------------

---@class PuzzleContext
---@field id string
---@field typeid string|nil
---@field config table
---@field state table|nil
---@field status PuzzleStatus
---@field now number serverTime, the same on every client to within about half a second
---@field random fun(k: integer): integer seeded: the same on every client for the same board
---@field userid string
---@field userName string
---@field isDirector boolean
---@field editing boolean the page holding the puzzle is in edit mode
---@field solved boolean
---@field failed boolean
---@field readonly boolean solved, failed, editing or away: the board takes no moves
---@field away boolean a player opened it away from its lock, and it is solved only there
---@field role string|nil the role id the Director gave this player
---@field panel Panel|nil the panel Render returned, once built
PuzzleContext = {}
PuzzleContext.__index = PuzzleContext

--True when a puzzle with a lock can only be solved at the lock (players who
--open it anywhere else see it but cannot move), unless the Director allowed
--solving from anywhere in the lock's setup.
---@param id string
---@return boolean
function Puzzle.SolveOnlyAtLock(id)
    local config = Puzzle.ReadConfig(id)
    if config.solveAnywhere == true or type(config.locks) ~= "table" then
        return false
    end
    return next(config.locks) ~= nil
end

--The name of the first of a puzzle's lock objects still on the map, or nil.
---@param id string
---@return string|nil
function Puzzle.LockObjectName(id)
    local locks = Puzzle.ReadConfig(id).locks
    for _, lock in pairs(type(locks) == "table" and locks or {}) do
        if type(lock) == "table" and lock.floorid ~= nil and lock.objid ~= nil then
            local obj = game.LookupObject(lock.floorid, lock.objid)
            if obj ~= nil and obj.valid and type(obj.description) == "string" and obj.description ~= "" then
                return obj.description
            end
        end
    end
    return nil
end

--Build a context for a puzzle. opts.seed seeds ctx.random; opts.editing marks a
--page in edit mode; opts.away marks a player who opened it away from its lock.
---@param id string
---@param opts {seed: string|nil, config: table|nil, editing: boolean|nil, away: boolean|nil}|nil
---@return PuzzleContext
function Puzzle.Context(id, opts)
    opts = opts or {}
    local config = opts.config or Puzzle.ReadConfig(id)
    local status = Puzzle.Status(id)
    local roles = type(config.roles) == "table" and config.roles or {}
    local ctx = setmetatable({
        id = id,
        typeid = Puzzle.GetTypeId(id),
        config = config,
        state = nil,
        status = status,
        now = dmhub.serverTime,
        random = Puzzle.SeededRandom(opts.seed or id),
        userid = dmhub.userid,
        userName = Puzzle.UserName(dmhub.userid),
        isDirector = dmhub.isDM == true,
        editing = opts.editing == true,
        solved = status.solved == true,
        failed = status.failed == true,
        readonly = false,
        away = opts.away == true,
        role = roles[dmhub.userid],
        panel = nil,
    }, PuzzleContext)
    ctx.readonly = ctx.solved or ctx.failed or ctx.editing or ctx.away
    return ctx
end

--Make a move. fn gets a copy of the board to edit (return false to cancel);
--the framework saves it and checks for a solve.
---@param fn fun(state: table, config: table): boolean|nil
---@param description string|nil
function PuzzleContext:Change(fn, description)
    if self.readonly then
        return
    end
    Puzzle.Change(self.id, fn, description)
end

---@param assistid string
---@return boolean
function PuzzleContext:Assist(assistid)
    local set = g_assists[self.id]
    return set ~= nil and set[assistid] == true
end

---@param key string
---@return boolean
function PuzzleContext:Hold(key)
    return Puzzle.Hold(self.id, key)
end

---@param key string
function PuzzleContext:Release(key)
    Puzzle.Release(self.id, key)
end

---@param key string
---@return string|nil
function PuzzleContext:HeldBy(key)
    return Puzzle.HeldBy(self.id, key)
end

--Click-to-place helper, the no-drag path every type should offer: Pick(key)
--picks a piece up (and holds it), Picked() is what is in hand, Unpick() puts it
--back. False from Pick when another player holds that piece.
---@param key string
---@return boolean
function PuzzleContext:Pick(key)
    if not self:Hold(key) then
        return false
    end
    g_picked[self.id] = key
    return true
end

---@return string|nil
function PuzzleContext:Picked()
    return g_picked[self.id]
end

function PuzzleContext:Unpick()
    local key = g_picked[self.id]
    g_picked[self.id] = nil
    if key ~= nil then
        self:Release(key)
    end
end

---@param id string
---@param assistid string
---@param on boolean
function Puzzle.SetAssist(id, assistid, on)
    local set = g_assists[id]
    if set == nil then
        set = {}
        g_assists[id] = set
    end
    set[assistid] = on or nil
end

--------------------------------------------------------------------------------
-- Presence and pushes
--------------------------------------------------------------------------------

---@param id string
---@return table
local function PresenceEntry(id)
    local entry = mod:GetDocumentSnapshot(PRESENCE_DOC).data[id]
    if type(entry) ~= "table" then
        return {}
    end
    return entry
end

--Record (or clear) that this player has the puzzle open, and where from ("at
--the Chest", "from chat"). Windows call this as a heartbeat; a client that drops
--simply stops renewing and goes stale.
---@param id string
---@param present boolean
---@param where string|nil
function Puzzle.MarkPresent(id, present, where)
    local doc = mod:GetDocumentSnapshot(PRESENCE_DOC)
    doc:BeginChange()
    local entry = doc.data[id]
    if type(entry) ~= "table" then
        entry = {}
        doc.data[id] = entry
    end
    if type(entry.users) ~= "table" then
        entry.users = {}
    end
    entry.users[dmhub.userid] = cond(present, dmhub.serverTime, nil)
    if type(entry.where) ~= "table" then
        entry.where = {}
    end
    entry.where[dmhub.userid] = cond(present, where, nil)
    doc:CompleteChange("Puzzle presence", {undoable = false})
end

--Where a present player has the puzzle open from ("at the Chest"), or nil.
---@param id string
---@param userid string
---@return string|nil
function Puzzle.PresentWhere(id, userid)
    local where = PresenceEntry(id).where
    if type(where) == "table" and type(where[userid]) == "string" then
        return where[userid]
    end
    return nil
end

--A player's name with where they are, for presence lines: "Ana (at the Chest)".
---@param id string
---@param userid string
---@return string
function Puzzle.UserNameWhere(id, userid)
    local where = Puzzle.PresentWhere(id, userid)
    if where ~= nil then
        return string.format("%s (%s)", Puzzle.UserName(userid), where)
    end
    return Puzzle.UserName(userid)
end

--Userids with the puzzle open right now, this player included.
---@param id string
---@return string[]
function Puzzle.PresentUsers(id)
    local result = {}
    local users = PresenceEntry(id).users
    if type(users) == "table" then
        local now = dmhub.serverTime
        for userid, t in pairs(users) do
            if type(t) == "number" and now - t < PRESENCE_FRESH_SECONDS then
                result[#result + 1] = userid
            end
        end
    end
    table.sort(result)
    return result
end

--Director: open the puzzle on every client. The nonce tells clients a push is new.
---@param id string
function Puzzle.PushToEveryone(id)
    local doc = mod:GetDocumentSnapshot(PRESENCE_DOC)
    doc:BeginChange()
    local entry = doc.data[id]
    if type(entry) ~= "table" then
        entry = {}
        doc.data[id] = entry
    end
    entry.push = dmhub.GenerateGuid()
    doc:CompleteChange("Show puzzle to everyone", {undoable = false})
end

--Every puzzle with presence or push data: id -> {users, push}.
---@return table<string, table>
function Puzzle.AllPresence()
    local result = {}
    for id, entry in pairs(mod:GetDocumentSnapshot(PRESENCE_DOC).data) do
        if type(entry) == "table" then
            result[id] = entry
        end
    end
    return result
end

--------------------------------------------------------------------------------
-- Requests: players ask, the host decides
--------------------------------------------------------------------------------

--A handler applies one request to the board copy it is given. Return false to
--wait (that player's later requests wait behind it); anything else finishes it.
--Writes to other documents (chat, kept data, status) go in `after`, which runs
--once the board is saved.
---@alias PuzzleRequestHandler fun(id: string, state: table, req: table, userid: string, after: fun()[]): boolean|nil

--Handlers for request kinds every type shares (a lock's bypass test), tried
--before the type's own.
---@type table<string, PuzzleRequestHandler>
local g_requestHandlers = {}

---@param kind string
---@param handler PuzzleRequestHandler
function Puzzle.RegisterRequestHandler(kind, handler)
    g_requestHandlers[kind] = handler
end

--File a request for the host: a small queue per player in the board, numbered
--so the host applies each once and in order. args.kind names it.
---@param id string
---@param args table
function Puzzle.Request(id, args)
    Puzzle.Change(id, function(state)
        state.req = state.req or {}
        local queue = state.req[dmhub.userid]
        if type(queue) ~= "table" or queue.seq ~= nil then
            queue = {}
            state.req[dmhub.userid] = queue
        end
        local seq = tonumber((state.done or {})[dmhub.userid]) or 0
        for _, queued in pairs(queue) do
            if type(queued) == "table" then
                seq = math.max(seq, tonumber(queued.seq) or 0)
            end
        end
        seq = seq + 1
        local req = { seq = seq }
        for k, v in pairs(args) do
            req[k] = v
        end
        --keyed, not a list, and one entry per request: a second request sent
        --before the host's next tick must not replace the first.
        queue["s" .. seq] = req
    end, "Puzzle request")
end

--Host: apply every pending request in the board copy `state`, in order per
--player. handler is the type's; shared kinds go to their registered handler.
--Returns true if the board changed.
---@param id string
---@param state table
---@param handler PuzzleRequestHandler|nil
---@param after fun()[]
---@return boolean
function Puzzle.ProcessRequests(id, state, handler, after)
    local changed = false
    state.req = state.req or {}
    state.done = state.done or {}
    for userid, queue in pairs(state.req) do
        if type(queue) == "table" and queue.seq ~= nil then
            --a request in the old one-slot form: drop it.
            state.req[userid] = {}
            changed = true
        elseif type(queue) == "table" then
            local pending = {}
            for key, queued in pairs(queue) do
                if type(queued) == "table" then
                    pending[#pending + 1] = { key = key, req = queued }
                end
            end
            table.sort(pending, function(a, b) return (tonumber(a.req.seq) or 0) < (tonumber(b.req.seq) or 0) end)
            for _, item in ipairs(pending) do
                local req = item.req
                local doneSeq = tonumber(state.done[userid]) or 0
                if (tonumber(req.seq) or 0) <= doneSeq then
                    queue[item.key] = nil
                    changed = true
                else
                    local fn = g_requestHandlers[req.kind] or handler
                    local finished = true
                    if fn ~= nil then
                        finished = fn(id, state, req, userid, after) ~= false
                    end
                    if not finished then
                        break
                    end
                    state.done[userid] = req.seq
                    queue[item.key] = nil
                    changed = true
                end
            end
        end
    end
    return changed
end

--Any request waiting in the saved board, without building a state copy.
---@param id string
---@return boolean
local function HasPendingRequests(id)
    local state = BoardData(id).state
    if type(state) ~= "table" or type(state.req) ~= "table" then
        return false
    end
    for _, queue in pairs(state.req) do
        if type(queue) == "table" and next(queue) ~= nil then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Heroes and tests
--------------------------------------------------------------------------------

--The hero a player acts as: their selected token, else their primary character.
---@return CharacterToken|nil
function Puzzle.MyHero()
    local tokens = dmhub.selectedOrPrimaryTokens or {}
    local tok = tokens[1]
    if tok ~= nil and tok.valid and tok.properties ~= nil then
        return tok
    end
    return nil
end

---@param tokenid string|nil
---@return CharacterToken|nil
function Puzzle.HeroById(tokenid)
    if tokenid == nil then
        return nil
    end
    local tok = dmhub.GetCharacterById(tokenid)
    if tok ~= nil and tok.valid then
        return tok
    end
    return nil
end

--Draw Steel's test difficulty rows: "success", "consequence" (success with a
--consequence), "failure" or "failconsequence"; reward is true for a natural
--19-20 or an easy tier 3.
---@param tier integer
---@param natural number|nil
---@param difficulty string "easy"|"medium"|"hard"
---@return string outcome, boolean reward
function Puzzle.TestOutcome(tier, natural, difficulty)
    local reward = natural ~= nil and natural >= 19
    if difficulty == "easy" then
        if tier >= 3 then
            return "success", true
        elseif tier == 2 then
            return "success", reward
        end
        return "consequence", reward
    elseif difficulty == "hard" then
        if tier >= 3 then
            return "success", reward
        elseif tier == 2 then
            return "failure", reward
        end
        return "failconsequence", reward
    end
    if tier >= 3 then
        return "success", reward
    elseif tier == 2 then
        return "consequence", reward
    end
    return "failure", reward
end

--A player's test: the montage's skill-aware roll (characteristic, the Skilled
--chip, the hero's features), private to the roller; without Encounter of the
--Week, the characteristic alone. skill may be "" for none. tiers are the three
--result lines the roll dialog shows. onDone(tier, natural); onCancel when the
--player closes the roll without rolling (montage roll only).
---@param tok CharacterToken
---@param attrid string
---@param skill string
---@param name string
---@param tiers string[]
---@param stillWanted fun(): boolean
---@param onDone fun(tier: integer, natural: number|nil)
---@param onCancel fun()|nil
---@param bane string|nil why this roll has a bane (shown on the roll), or nil for none
function Puzzle.RollTest(tok, attrid, skill, name, tiers, stillWanted, onDone, onCancel, bane)
    local info = (creature.attributesInfo or {})[attrid]
    local attrName = info ~= nil and info.description or "Intuition"
    local attr = attrName
    if skill ~= nil and skill ~= "" then
        attr = string.format("%s, %s", attrName, skill)
    end
    local montage = rawget(_G, "EncounterMontage")
    if montage ~= nil and montage.BuildTestRoll ~= nil and montage.ShowTestRoll ~= nil then
        --a bane rides in as a test rider, as the montage's own banes do.
        local verdict = nil
        if bane ~= nil then
            verdict = { applied = { { rider = { effect = "bane" }, why = bane } } }
        end
        local parts = montage.BuildTestRoll(tok, attr, name, verdict)
        montage.ShowTestRoll{
            creature = tok.properties,
            heroToken = tok,
            title = parts.title,
            rollType = parts.rollType,
            roll = parts.roll,
            modifiers = parts.modifiers,
            tiers = tiers,
            rollSeq = 1,
            share = false,
            completeKind = "rolled",
            cancelKind = "cancel",
            stillWanted = stillWanted,
            send = function(kind, req)
                if kind == "rolled" and stillWanted() then
                    onDone(math.tointeger(tonumber(req.tier)) or 1, tonumber(req.natural))
                elseif kind == "cancel" and onCancel ~= nil then
                    onCancel()
                end
                return true
            end,
        }
        return
    end
    local bonus = 0
    pcall(function() bonus = tok.properties:GetAttribute(attrid):Modifier() end)
    if bane ~= nil then
        bonus = bonus - 2
    end
    dmhub.Roll{
        roll = string.format("2d10 + %d", bonus),
        description = string.format("%s: %s", name, attr),
        complete = function(rollInfo)
            local tier = 1
            pcall(function() tier = RollUtils.DiceResultToTier(rollInfo) end)
            if stillWanted() then
                onDone(tier, rollInfo.naturalRoll)
            end
        end,
    }
end

--------------------------------------------------------------------------------
-- Host watcher
--------------------------------------------------------------------------------

--Exactly one client acts for the table: the lowest present Director, or the host
--of a game with no Director, whichever map they are on (LiveEncounter's election).
---@return boolean
function Puzzle.IsHost()
    local live = rawget(_G, "LiveEncounter")
    if live ~= nil and live.IsElectedHost ~= nil then
        return live.IsElectedHost()
    end
    return dmhub.isDM == true
end

--Chat lines are posted by the host only, once, and only after the host has
--checked for itself that the board really is solved.
local function HostTick()
    local data = mod:GetDocumentSnapshot(STATUS_DOC).data
    local now = dmhub.serverTime
    for id, status in pairs(data) do
        if type(status) == "table" then
            if not status.solved and not status.failed and status.deadline ~= nil and now > status.deadline then
                WriteStatus(id, function(s) s.failed = true end, "Puzzle timer ran out")
            elseif status.solved and not status.announced then
                local ok = true
                if not status.bypassed and status.solvedBy ~= "director" then
                    local def = Puzzle.GetType(id)
                    local state, config = Puzzle.ReadState(id)
                    ok = def ~= nil and state ~= nil and def.IsSolved(state, config)
                end
                if ok then
                    WriteStatus(id, function(s) s.announced = true end, "Announce puzzle")
                    if status.bypassed then
                        chat.Send(string.format("The party got past %s.", Puzzle.Title(id)))
                    else
                        chat.Send(string.format("The party solved %s.", Puzzle.Title(id)))
                    end
                else
                    --a client claimed a solve the board does not show: undo the claim.
                    WriteStatus(id, function(s)
                        s.solved = nil
                        s.solvedBy = nil
                        s.solvedAt = nil
                    end, "Reject puzzle solve")
                end
            elseif status.failed and not status.announced then
                WriteStatus(id, function(s) s.announced = true end, "Announce puzzle")
                chat.Send(string.format("The party failed %s.", Puzzle.Title(id)))
            elseif (status.solved or status.failed) and status.announced and not status.effectsDone then
                --effects run after the announcement, so a rejected solve never opens anything.
                local outcome = cond(status.solved, "solve", "fail")
                for handlerKey, handler in pairs(g_outcomeHandlers) do
                    local ok, err = pcall(handler.apply, id, outcome, status)
                    if not ok then
                        print("PUZZLE:: effects failed in", handlerKey, err)
                    end
                end
                WriteStatus(id, function(s) s.effectsDone = true end, "Puzzle effects applied")
            end
        end
    end
end

--Apply waiting requests for a type without its own HostTick.
---@param id string
---@param def PuzzleTypeDef
local function HostRequests(id, def)
    local status = Puzzle.Status(id)
    if status.solved or status.failed or not HasPendingRequests(id) then
        return
    end
    local after = {}
    Puzzle.Change(id, function(state)
        if not Puzzle.ProcessRequests(id, state, def.HandleRequest, after) then
            return false
        end
    end, "Puzzle requests")
    for _, fn in ipairs(after) do
        local ok, err = pcall(fn)
        if not ok then
            print("PUZZLE:: request follow-up failed for", id, err)
        end
    end
end

--Types with their own host work (games of chance resolving bets) get a tick
--for each of their puzzles; the rest have their requests applied.
local function TypeHostTicks()
    local ids = Puzzle.Index()
    for id in pairs(mod:GetDocumentSnapshot(STATUS_DOC).data) do
        ids[id] = ids[id] or {}
    end
    for id in pairs(ids) do
        local def = Puzzle.GetType(id)
        if def ~= nil then
            local ok, err = pcall(function()
                if def.HostTick ~= nil then
                    def.HostTick(id)
                else
                    HostRequests(id, def)
                end
            end)
            if not ok then
                print("PUZZLE:: host tick failed for", id, err)
            end
        end
    end
end

local function ScheduleHostTick()
    dmhub.Schedule(1, function()
        if mod.unloaded then
            return
        end
        local ok, err = pcall(function()
            if Puzzle.IsHost() then
                HostTick()
                TypeHostTicks()
            end
        end)
        if not ok then
            print("PUZZLE:: host tick failed:", err)
        end
        ScheduleHostTick()
    end)
end
ScheduleHostTick()

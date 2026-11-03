local mod = dmhub.GetModLoading()

--- Downtime activities a Respite can offer.
---
--- A feature registers itself here rather than the Respite reaching into it,
--- so the Respite never needs to know which features exist. Registration
--- happens after the game is up, since load order does not guarantee this
--- module is present when a feature's own files run.
---
--- The registry is module state, not document state: it describes what this
--- client can do, and the Respite records only which of them are on offer.
--- @class RSPActivity: GameType
--- @field new fun(o?: table): RSPActivity
--- @field key string
--- @field name string
--- @field paint fun(): Panel the Director's setup fields
--- @field paintPlayer fun(args: table): Panel what a player does with it
--- @field paintDirector fun(args: table): Panel what the Director watches
--- Both paintDirector and needsAttention receive args.since, which is a server
--- time OR a function returning one. Resolve it when you read it: a panel that
--- captures the number can be built before the Respite starts, and a zero
--- there means "report everything ever".
--- @field needsAttention fun(args: table): boolean something the Director must act on
--- @field onStart fun() the Respite has begun and this activity is on offer
--- @field onComplete fun() the Respite is over
--- @field onRested fun() every participant has been rested
--- onComplete and onRested sit either side of the rest, and the difference
--- matters: onComplete still sees the Respite as it was and runs before anybody
--- is rested, while onRested runs after and is the only place to touch what the
--- rest restores.
--- @field journalDetail fun(): string|nil one line about this activity for the write-up
--- @field journalSummary fun(args: table): string[]|nil what args.charid did;
--- receives args.since like paintDirector does
--- @field partyRecord fun(args: table): table[] what the players did, for the Watch
--- view: entries of {at = server time, text, charid = who acted, tone = nil|
--- RSPConstants.toneGood|toneAlert, icon = nil|image beside the text, iconColor = nil|
--- its tint, the theme's text colour when nil}; the Respite puts the activity's name in
--- front of the text. Receives args.since like paintDirector does
--- @field partyWatch fun(args: table): string[] document paths whose changes move
--- that record
--- @field paintIdle fun(args: table): Panel what a player sees of it between Respites
--- @field idleTitle string|nil the heading over paintIdle; the activity's name when nil
--- @field playerActions fun(args: table): Panel buttons on the player's Activity row, always
--- shown like the sheet button; args.selection() is the selected {charid, owner} entry or
--- nil, args.host() the Respite window. The Respite fires rspSelectionChanged down the
--- panel when the selection moves
--- @field paintStation fun(args: table): Panel the activity's tile on the player stage, which
--- characters are dropped onto; the Respite draws a plain one from the name when nil
--- @field busy fun(args: table): boolean, string|nil whether args.charid (args.owner for a
--- follower) is part way through this activity and may not leave it yet, and why
--- Every painter, summary and record also receives args.roster: an accessor for the
--- heroes on the Respite's Participants page, participating or not.
RSPActivity = RegisterGameType("RSPActivity")

RSPActivity.name = "Activity"

--- key -> RSPActivity
local m_activities = {}

--- What RSPActivity.Register takes; the fields mean what they do on RSPActivity.
---@class RSPActivityRegisterArgs
---@field key string
---@field name string
---@field paint? fun(): Panel
---@field paintPlayer? fun(args: table): Panel
---@field paintDirector? fun(args: table): Panel
---@field needsAttention? fun(args: table): boolean
---@field onStart? fun()
---@field onComplete? fun()
---@field onRested? fun()
---@field journalDetail? fun(): string|nil
---@field journalSummary? fun(args: table): string[]|nil
---@field partyRecord? fun(args: table): table[]
---@field partyWatch? fun(args: table): string[]
---@field paintIdle? fun(args: table): Panel
---@field idleTitle? string
---@field playerActions? fun(args: table): Panel
---@field paintStation? fun(args: table): Panel
---@field busy? fun(args: table): boolean, string|nil

--- Offer an activity to the Respite.
--- Registering a key twice replaces the earlier entry, so a code reload
--- refreshes an activity instead of doubling it.
--- @param args RSPActivityRegisterArgs
function RSPActivity.Register(args)
    if args == nil or type(args.key) ~= "string" or #args.key == 0 then
        return
    end

    m_activities[args.key] = RSPActivity.new{
        key = args.key,
        name = args.name or "Activity",
        paint = args.paint,
        paintPlayer = args.paintPlayer,
        paintDirector = args.paintDirector,
        needsAttention = args.needsAttention,
        onStart = args.onStart,
        onComplete = args.onComplete,
        onRested = args.onRested,
        journalDetail = args.journalDetail,
        journalSummary = args.journalSummary,
        partyRecord = args.partyRecord,
        partyWatch = args.partyWatch,
        paintIdle = args.paintIdle,
        idleTitle = args.idleTitle,
        playerActions = args.playerActions,
        paintStation = args.paintStation,
        busy = args.busy,
    }
end

--- Stop offering an activity.
--- @param key string
function RSPActivity.Unregister(key)
    m_activities[key] = nil
end

--- Everything registered, alphabetical by name.
--- @return table[] activities
function RSPActivity.All()
    local result = {}
    for _, activity in pairs(m_activities) do
        result[#result + 1] = activity
    end

    table.sort(result, function(a, b)
        return string.lower(a.name) < string.lower(b.name)
    end)

    return result
end

-- Announce the registry. Features listen for this and register themselves,
-- which works on a cold start and on a code reload alike: this module always
-- loads after theirs, so their handler is already waiting.
dmhub.FireGlobalEvent(RSPConstants.registryEvent)

--- Does any activity have something here the Director must act on?
--- Asked per hero, so the Respite can mark a row without knowing what any
--- activity actually does.
--- @param args table charid, and since as a server time
--- @return boolean
function RSPActivity.AnyNeedsAttention(args)
    for _, activity in pairs(m_activities) do
        local check = activity:try_get("needsAttention")
        if check ~= nil and check(args) then
            return true
        end
    end
    return false
end

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
--- @class RSPActivity
--- @field key string
--- @field name string
--- @field paint fun(): Panel the Director's setup fields
--- @field paintPlayer fun(args: table): Panel what a player does with it
RSPActivity = RegisterGameType("RSPActivity")

RSPActivity.name = "Activity"

--- key -> RSPActivity
local m_activities = {}

--- Offer an activity to the Respite.
--- Registering a key twice replaces the earlier entry, so a code reload
--- refreshes an activity instead of doubling it.
--- @param args {key: string, name: string, paint: nil|fun(): Panel, paintPlayer: nil|fun(args: table): Panel}
function RSPActivity.Register(args)
    if args == nil or type(args.key) ~= "string" or #args.key == 0 then
        return
    end

    m_activities[args.key] = RSPActivity.new{
        key = args.key,
        name = args.name or "Activity",
        paint = args.paint,
        paintPlayer = args.paintPlayer,
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

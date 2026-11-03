local mod = dmhub.GetModLoading()

--Encounter of the Week hero builder: the step engine. No UI lives here.
--
--The engine is shared with the main game's Builder, Level up and Hero
--sheet: HeroBuild.Create (Draw Steel V/HeroBuildPools.lua)
--holds every step, pick, status and Fill rule. EotW's engine differs only
--in its options: it offers only fully automated ("gold") complications and
--one at most, a treasure pick goes straight into the hero's gear, and its
--writes are not undoable. EotW's gate on Finish lives in its builder screen
--(EotwBuilder.lua).
--Design/plan doc: EncounterOfTheWeek/EncounterOfTheWeek.md,
--"The hero builder and hero sheet".

--Made the first time anything reads EotwBuild, so this file does not
--depend on the shared file loading first.
--- @type nil|HeroBuildEngine
local g_engine = nil

--Below-Gold treasure that still plays well enough to offer, by gear id
--(user direction 2026-10-21, after a review of the Silver trinkets).
local EXTRA_GRANT_TREASURE = {
    ["b2f04f55-0275-4e4e-a6b4-23dc3ffce594"] = true, --Color Cloak - Red
    ["d20ae94a-9917-43be-b69b-38113b36fc97"] = true, --Gecko Gloves
}

--Treasure never offered even at Gold, by gear id: no use to a hero.
local EXCLUDED_GRANT_TREASURE = {
    ["27bf449d-9a2c-40a3-aea4-a8ec4e19d67d"] = true, --Precious Collar (beastheart companions only)
}

--A complication's treasure choice (Secret Twin's "a 1st-echelon trinket of
--your choice") offers an EotW hero Gold-automation treasure only, the same
--test as the market. Draw Steel Modifiers loads after this file, so the
--filter is registered the first time the engine is used.
local g_goldTreasureFilter = false
local function EnsureGoldTreasureFilter()
    if g_goldTreasureFilter or rawget(_G, "CharacterTreasureGrantChoice") == nil then
        return
    end
    g_goldTreasureFilter = true
    CharacterTreasureGrantChoice.RegisterOptionFilter("eotw-gold", function(hero, item)
        local eotw = hero:try_get("eotwDraft", false) == true or hero:try_get("eotwHero", false) == true
        if not eotw or EXTRA_GRANT_TREASURE[item.id] then
            return true
        end
        if EXCLUDED_GRANT_TREASURE[item.id] then
            return false
        end
        return (tonumber(item:try_get("implementation", 1)) or 1) >= gui.ImplementationStatus.Gold
    end)
end

--- @return HeroBuildEngine
local function Engine()
    EnsureGoldTreasureFilter()
    if g_engine == nil then
        g_engine = HeroBuild.Create{
            complicationOffered = function(hero, item)
                return g_engine ~= nil and g_engine.ComplicationIsGold(item)
            end,
            maxComplications = 1,
            undoable = false,
            treasureOnPick = true,
            --as all EotW treasure is, a given treasure is worn at once while
            --there is a free slot.
            equipGiven = function(token, itemid)
                EotwHeroSheet.EquipInPlace(token, itemid)
            end,
        }
    end
    return g_engine
end

EotwBuild = setmetatable({}, {
    __index = function(_, key)
        return Engine()[key]
    end,
}) --[[@as HeroBuildEngine]]

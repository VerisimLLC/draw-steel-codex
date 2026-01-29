--- DESTRUCTIVE Clears all downtime data from the token
--- @param t table DMHub token from which to remove downtime info
local function _clearTokenData(t)
    if not dmhub.isDM then return end

    if t and t.properties then
        -- Wipe downtime data
        if t.properties:try_get(DTConstants.CHARACTER_STORAGE_KEY) then
            chat.Send(string.format("Removing Downtime data from %s.", t.name))
            t:ModifyProperties{
                description = "Clear Downtime Info",
                execute = function()
                    if t.properties:try_get(DTConstants.CHARACTER_STORAGE_KEY) then
                        t.properties[DTConstants.CHARACTER_STORAGE_KEY] = nil
                    end
                end
            }
        end
        -- Wipe shared projects
        local shares = DTShares.CreateNew()
        if shares then shares:RevokeAll(t.id) end
    end
end

--- DESTRUCTIVE Clears all downtime data from network storage
--- and characters!
local function _clearAllData()
    if not dmhub.isDM then return end

    local function tokenHasDowntime(t)
        if t.properties and t.properties:try_get(DTConstants.CHARACTER_STORAGE_KEY) then
            return true
        end
        return false
    end

    local heroes = DTBusinessRules.GetAllHeroTokens(tokenHasDowntime)
    for _, t in ipairs(heroes) do
        _clearTokenData(t)
    end

    chat.Send("Resetting Downtime settings.")
    DTShares.CreateNew():InitializeDocument()
    DTSettings.CreateNew():InitializeDocument()
end

if dmhub.isDM then
    -- Register the downtime panel
    local downtimeSettings = DTSettings.CreateNew()
    local directorPanel = DTDirectorPanel.new{ downtimeSettings = downtimeSettings }
    if directorPanel then
        directorPanel:Register()
    end

    -- Register maintenance commands
    Commands.wipealldowntimedata = function(args)
        _clearAllData()
    end
    Commands.wipetokendowntimedata = function(args)
        for _, t in ipairs(dmhub.selectedTokens) do
            _clearTokenData(t)
        end
    end

end

--- Our tab in the character sheet
CharSheet.RegisterTab {
    id = "Downtime",
    text = "Downtime",
	visible = function(c)
		return c ~= nil and c:IsHero()
	end,
    panel = DTCharSheetTab.CreateDowntimePanel
}
dmhub.RefreshCharacterSheet()

-- Migration
local function _migrateFollowerRollsToHero()
    local allTokens = table.values(game.GetGameGlobalCharacters())
    for _,token in ipairs(allTokens) do
        if token.properties and token.properties:IsHero() then
            local hero = token.properties
            local dt = hero:GetDowntimeInfo()
            if dt then
                if not dt:IsMigrated() then
                    chat.Send(string.format("Migrating downtime follower rolls for %s.", token.name or "Unnamed Token"))
                    local migratedRolls = {}
                    local followers = hero:try_get(DTConstants.FOLLOWERS_STORAGE_KEY)
                    if followers and type(followers) == "table" then
                        for id,_ in pairs(followers) do
                            local follower = dmhub.GetCharacterById(id)
                            if follower and follower.properties and follower.properties:IsFollower() then
                                local followerType = follower.try_get("followerType")
                                if followerType == "artisan" or followerType == "sage" then
                                    local legacyRolls = follower.properties:try_get(DTConstants.FOLLOWER_AVAILROLL_KEY, 0)
                                    migratedRolls[id] = legacyRolls
                                end
                            end
                        end
                    end
                    token:ModifyProperties{
                        description = "Migrate follower rolls to mentor",
                        undoable = false,
                        execute = function()
                            dt[DTConstants.FOLLOWER_ROLLS_KEY] = migratedRolls
                        end,
                    }
                end
            end
        end
    end
end

Commands.dtmigratefollowerrolls = function()
    _migrateFollowerRollsToHero()
end

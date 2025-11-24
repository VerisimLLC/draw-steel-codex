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
        local shares = DTShares:new()
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
    DTShares:new():InitializeDocument()
    DTSettings:new():InitializeDocument()
end

if dmhub.isDM then
    -- Register the downtime panel
    local downtimeSettings = DTSettings:new()
    local directorPanel = DTDirectorPanel:new(downtimeSettings)
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

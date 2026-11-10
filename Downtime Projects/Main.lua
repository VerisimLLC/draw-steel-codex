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

--- The /grantdtrolls targets that are not names, and how the chat line names them
local GRANT_TARGETS = {
    all = { heroes = true, followers = true, text = "everyone" },
    heroes = { heroes = true, followers = false, text = "heroes" },
    hero = { heroes = true, followers = false, text = "heroes" },
    followers = { heroes = false, followers = true, text = "followers" },
    fol = { heroes = false, followers = true, text = "followers" },
}

local GRANT_USAGE = "Usage: /grantdtrolls [amount] [all|heroes|followers|name1, name2...]"

--- Grants downtime rolls to heroes and to the followers that roll on projects,
--- then says so in chat. A follower's rolls are held on its hero.
--- @param args string|nil "[amount] [target]": amount defaults to 1, target to all
local function _grantRolls(args)
    if not dmhub.isDM then return end

    local text = trim(args or "")
    local amount = 1
    local first, rest = text:match("^(%S+)%s*(.*)$")
    local number = first and tonumber(first)
    if number ~= nil then
        if number == 0 or number ~= math.floor(number) then
            SendTitledChatMessage(GRANT_USAGE, "usage", "#e09c9c", dmhub.userid)
            return
        end
        amount = math.floor(number)
        text = trim(rest)
    end

    local target = GRANT_TARGETS[string.lower(text)]
    if text == "" then
        target = GRANT_TARGETS.all
    end
    local queries = target == nil and WhisperMatch.SplitNames(text) or {}

    local function matchesName(name)
        for _, query in ipairs(queries) do
            if WhisperMatch.Matches(query, name) then
                return true
            end
        end
        return false
    end

    local grantedNames = {}
    for _, hero in ipairs(DTBusinessRules.GetAllHeroTokens()) do
        local payHero
        if target ~= nil then
            payHero = target.heroes
        else
            payHero = matchesName(hero.name)
        end
        if payHero then
            grantedNames[#grantedNames + 1] = hero.name
        end

        local followerIds = {}
        local followers = hero.properties:try_get(DTConstants.FOLLOWERS_STORAGE_KEY)
        if followers and type(followers) == "table" then
            for followerId, _ in pairs(followers) do
                local follower = dmhub.GetCharacterById(followerId)
                if follower ~= nil and DTFollowers.RollsOnProjects(follower) then
                    local payFollower
                    if target ~= nil then
                        payFollower = target.followers
                    else
                        payFollower = matchesName(follower.name)
                    end
                    if payFollower then
                        followerIds[#followerIds + 1] = followerId
                        grantedNames[#grantedNames + 1] = follower.name
                    end
                end
            end
        end

        if payHero or #followerIds > 0 then
            hero:ModifyProperties{
                description = "Grant downtime rolls",
                execute = function()
                    local info = hero.properties:GetDowntimeInfo()
                    if info == nil then return end
                    if payHero then
                        info:GrantRolls(amount)
                    end
                    for _, followerId in ipairs(followerIds) do
                        info:GrantFollowerRolls(followerId, amount)
                    end
                end,
            }
        end
    end

    if #grantedNames == 0 then
        SendTitledChatMessage(string.format("No heroes or followers match \"%s\".", text ~= "" and text or "all"), "grantdtrolls", "#e09c9c", dmhub.userid)
        return
    end

    local list = target ~= nil and target.text or table.concat(grantedNames, ", ")
    chat.Send(string.format("Granted %d downtime %s to %s.", amount, amount == 1 and "roll" or "rolls", list))
end

if dmhub.isDM then
    -- Register the downtime panel
    local downtimeSettings = DTSettings.CreateNew()
    local directorPanel = DTDirectorPanel.new{ downtimeSettings = downtimeSettings }
    if directorPanel then
        directorPanel:Register()
    end

    -- Register maintenance commands
    Commands.RegisterMacro{
        name = "wipealldowntimedata",
        summary = "wipe all downtime",
        doc = "Usage: /wipealldowntimedata\nClears all downtime project data. DM only.",
        command = function(args)
            _clearAllData()
        end,
    }
    Commands.RegisterMacro{
        name = "wipetokendowntimedata",
        summary = "wipe token downtime",
        doc = "Usage: /wipetokendowntimedata\nClears downtime data for selected tokens. DM only.",
        command = function(args)
            for _, t in ipairs(dmhub.selectedTokens) do
                _clearTokenData(t)
            end
        end,
    }
    Commands.RegisterMacro{
        name = "grantdtrolls",
        summary = "grant downtime rolls",
        doc = GRANT_USAGE .. "\nGrants downtime rolls (1 by default, negative to take away) to every hero and project follower, only heroes, only followers, or the heroes and followers named, matched as /w matches names. DM only.",
        command = function(args)
            _grantRolls(args)
        end,
    }

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

--- Drops followerRolls entries whose id is not one of the hero's live followers.
--- These are left behind when a follower character is deleted rather than removed
--- from the mentor, and they cannot be spent.
local function _pruneStaleFollowerRolls(token, hero, dt)
    local liveFollowers = {}
    local followers = hero:try_get(DTConstants.FOLLOWERS_STORAGE_KEY)
    if followers and type(followers) == "table" then
        for id,_ in pairs(followers) do
            if dmhub.GetCharacterById(id) then
                liveFollowers[id] = true
            end
        end
    end

    local staleIds = {}
    for id,_ in pairs(dt:GetFollowerRollsMap()) do
        if not liveFollowers[id] then
            staleIds[#staleIds + 1] = id
        end
    end

    if #staleIds == 0 then return end

    chat.Send(string.format("Pruning %d stale follower roll entries for %s.",
        #staleIds, token.name or "Unnamed Token"))

    token:ModifyProperties{
        description = "Prune stale follower rolls",
        undoable = false,
        execute = function()
            for _,id in ipairs(staleIds) do
                dt:RemoveFollowerRolls(id)
            end
        end,
    }
end

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
                                local followerType = follower.properties:try_get("followerType")
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

                _pruneStaleFollowerRolls(token, hero, dt)
            end
        end
    end
end

if dmhub.isDM then
Commands.RegisterMacro{
    name = "dtmigratefollowerrolls",
    summary = "migrate follower rolls",
    doc = "Usage: /dtmigratefollowerrolls\nMigrates legacy follower roll data to hero tokens and prunes rolls stranded on deleted followers. DM only.",
    command = function()
        _migrateFollowerRollsToHero()
    end,
}
end

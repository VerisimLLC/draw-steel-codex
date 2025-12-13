local mod = dmhub.GetModLoading()

--Called by CharSheet.FeaturesAndNotesPanel to create the Followers tab
function CharSheet.CreateFollowersPanel()
    return gui.Panel {
        width = "100%-4",
        height = "100%",
        halign = "center",

        CharSheet.FollowersInnerPanel(),
    }
end

local Styles = {
    {
        classes = { "mainPanel"},
        pad = 5,
        bgimage = "panels/square.png",
        bgcolor = "#2a2a2a",
        border = 1,
        borderColor = "white",
    },
    {
        classes = { "avatarPanel"},
        borderColor = Styles.textColor,
        borderWidth = 2,
        hmargin = 8,
        width = 80,
        height = 120,
        halign = "center",
        valign = "center",
        bgcolor = "white",
    },
    {
        selectors = {'hover', "avatarPanel"},
        brightness = 2,
    },
    {
        classes = { "followerLabel"},
        height = 25,
        minWidth = 120,
        valign = "center",
        fontSize = 18,
        bold = true,
    },
    {
        classes = { "followersListLabel"},
        height = 20,
        width = 180,
        valign = "center",
        fontSize = 16,
    },
    {
        classes = { "followerDropdown"},
        width = 190,
        valign = "top",
    },
    {
        classes = { "followerNameLabel"},
        width = "50%",
        height = 25,
        fontSize = 20,
        bold = true,
        color = Styles.textColor,
        hmargin = 5,
    }
}

--Create Follower table if it does not exist
EnsureFollowers = function(creature)
    local followers = creature:try_get("followers")
    if not followers then
        creature.followers = {}
    end
    return creature.followers
end

CreateFollowerMonster = function(followerInfo, mentorToken, pregenRetainerId)
    local locs = mentorToken.properties:AdjacentLocations()
    local loc = #locs and locs[1] or mentorToken.properties.locsOccupying[1]
    local newCharId

    dmhub.Coroutine(function()
        if pregenRetainerId then
            newMonster = game.SpawnTokenFromBestiaryLocally(pregenRetainerId, loc, {fitLocatoin = true})
            newCharId = newMonster.charid
            newMonster.ownerId = mentorToken.ownerId
            newMonster.partyId = mentorToken.partyId

            newMonster.name = followerInfo.name
            newMonster:UploadToken()
            game.UpdateCharacterTokens()
        else
            newCharId = game.CreateCharacter("monster")
            for i = 1, 100 do
                local newMonster = dmhub.GetCharacterById(newCharId)
                if newMonster ~= nil then
                    newMonster.properties = monster.CreateNew(followerInfo.type)
                    local monster = newMonster.properties

                    newMonster.name = followerInfo.name
                    monster.role = "Follower"
                    monster.followerType = followerInfo.type
                    monster.creatureTemplates = {}
                    monster.creatureTemplates[#monster.creatureTemplates + 1] = "25263715-cef4-4e25-b4bd-ddedc3a87dea"

                    if followerInfo.type ~= "retainer" then
                        monster.attributes["rea"].baseValue = 1
                        if monster.followerType == "sage" then
                            monster.attributes["inu"].baseValue = 1
                        elseif monster.followerType == "artisan" then
                            monster.attributes[followerInfo.characteristic].baseValue = 1
                        end
                    end

                    local ancestryTable = dmhub.GetTable(Race.tableName)
                    local ancestry = ancestryTable[followerInfo.ancestry]
                    local bandTable = dmhub.GetTable(MonsterGroup.tableName)
                    for id, band in pairs(bandTable) do
                        if string.lower(band.name) == string.lower(ancestry.name) then
                            monster.groupid = id
                            monster.keywords = {}
                            monster.keywords[band.name] = true
                        end
                    end

                    newMonster.ownerId = mentorToken.ownerId
                    newMonster.partyId = mentorToken.partyId
                    newMonster:UploadToken()
                    game.UpdateCharacterTokens()
                    newMonster:ChangeLocation(core.Loc{x = loc.x, y = loc.y})
                    break
                end
                coroutine.yield(0.1)
            end
        end
        local newMonster = dmhub.GetTokenById(newCharId)
        followerInfo.followerToken = newMonster.id
        followerInfo.portrait = newMonster.offTokenPortrait

        mentorToken:ModifyProperties{
            description = "Assign Follower",
            execute = function()
                local followers = EnsureFollowers(mentorToken.properties)
                followers[#followers + 1] = followerInfo
            end,
        }
        
        newMonster:ShowSheet()
    end)

end

local retainerDropdownOptions, retainerLookup = buildRetainerList()

function CharSheet.FollowersInnerPanel()
    local FollowerSelectionDialog = function()
        local resultPanel

        local newFollowerType = "none"
        local follower = Follower.Create()

        local retainerType

        resultPanel = gui.Panel{
            styles = Styles,

            id = "followerSelectionDialog",
            classes = { "mainPanel", "collapsed"},
            halign = "left",
            valign = "top",
            flow = "vertical",
            height = 250,
            width = "60%",
            margin = 10,

            newFollower = function(element)
                follower = Follower.Create()
                follower.characteristic = "mgt"
                newFollowerType = "none"
                resultPanel:FireEventTree("refreshAll")
            end,

            gui.Label{
                text = "Create Follower",
                width = "auto",
                height = "auto",
                valign = "top",
                halign = "center",
                fontSize = 18,
                bold = true,
            },

            gui.Dropdown{
                vmargin = 8,
                valign = "top",
                options = {
                    { id = "none", text = "Select Follower Type" },
                    { id = "artisan", text = "Artisan" },
                    { id = "sage", text = "Sage" },
                    { id = "premaderetainer", text = "Premade Retainer" },

                    { id = "existing", text = "Manual" },
                },

                idChosen = newFollowerType,

                change = function(element)
                    newFollowerType = element.idChosen
                    resultPanel:FireEventTree("refreshAll")
                end,

                refreshAll = function(element)
                    element.idChosen = newFollowerType
                end,
            },

            gui.Panel{
                classes = {cond(newFollowerType == "none", "collapsed-anim")},
                flow = "horizontal",
                width = "auto",
                height = 30,
                gui.Label{
                    classes = { "followerLabel"},
                    width = "auto",
                    height = "auto",
                    text = "Name:",
                },
                gui.Input{
                    text = follower.name or "",
                    change = function(element)
                        follower.name = element.text
                        resultPanel:FireEventTree("refreshAll")
                    end,
                },

                refreshAll = function(element)
                    if newFollowerType == "none" then
                        element:SetClass("collapsed-anim", true)
                    else
                        element:SetClass("collapsed-anim", false)
                    end
                end,
            },

            gui.Panel{
                classes = {cond(newFollowerType ~= "premaderetainer", "collapsed-anim")},
                width = "auto",
                height = "auto",

                refreshAll = function(element)
                    if newFollowerType ~= "premaderetainer" then
                        element:SetClass("collapsed-anim", true)
                    else
                        element:SetClass("collapsed-anim", false)
                    end
                end,

                gui.Dropdown{
                    options = retainerDropdownOptions,

                    idChosen = "none",

                    change = function(element)
                        retainerType = element.idChosen
                    end,
                },
            },

            --Artisan or Sage characteristics
            gui.Panel{
                classes = {cond(newFollowerType ~= "artisan" and newFollowerType ~= "sage", "collapsed-anim")},
                flow = "vertical",
                height = "auto",
                width = "auto",
                refreshAll = function(element)
                    if newFollowerType ~= "artisan" and newFollowerType ~= "sage" then
                        element:SetClass("collapsed-anim", true)
                    else
                        element:SetClass("collapsed-anim", false)
                    end
                end,

                gui.Panel{
                    flow = "horizontal",
                    width = "auto",
                    height = 30,
                    gui.Label{
                        classes = { "followerLabel"},
                        width = "auto",
                        height = "auto",
                        text = "Ancestry:",
                    },
                    gui.Dropdown{
                        options = Race.GetDropdownList(),
                        idChosen = follower.ancestry,

                        change = function(element)
                            follower.ancestry = element.idChosen
                            resultPanel:FireEventTree("refreshAll")
                        end,

                        refreshAll = function(element)
                            element.idChosen = follower.ancestry
                        end,
                    }
                },

                gui.Panel{
                    classes = {cond(newFollowerType ~= "artisan", "collapsed-anim")},
                    flow = "horizontal",
                    width = "auto",
                    height = 30,

                    refreshAll = function(element)
                        if newFollowerType == "artisan" then
                            element:SetClass("collapsed-anim", false)
                        else
                            element:SetClass("collapsed-anim", true)
                        end
                    end,

                    gui.Label{
                        classes = { "followerLabel"},
                        width = "auto",
                        height = "auto",
                        text = "Characteristic:",
                    },

                    gui.Dropdown{
                        options = {
                            {
                                id = "mgt",
                                text = "Might",
                            },
                            {
                                id = "agl",
                                text = "Agility",
                            },
                        },

                        idChosen = follower.characteristic or "mgt",
                        
                        change = function(element)
                            follower.characteristic = element.idChosen
                            resultPanel:FireEventTree("refreshAll")
                        end,
                    },
                },
            },

            gui.Button{
                floating = true,
                valign = "bottom",
                halign = "center",
                interactable = newFollowerType ~= "none",
                text = "Create",

                refreshAll = function(element)
                    element.interactable = newFollowerType ~= "none"
                end,

                click = function(element)
                    local mentorToken = CharacterSheet.instance.data.info.token
                    if newFollowerType == "existing" then
                        local followers = EnsureFollowers(mentorToken.properties)
                        follower.manual = true
                        followers[#followers + 1] = follower
                        CharacterSheet.instance:FireEvent("refreshAll")
                        element.parent:SetClass("collapsed", true)
                        return
                    end
                    if newFollowerType == "artisan" or newFollowerType == "sage" then
                        follower.type = newFollowerType
                    else
                        follower.type = "retainer"
                    end
                    follower.assignedTo[mentorToken.charid] = follower.guid
                    local followerid = CreateFollowerMonster(follower, mentorToken, retainerType)

                    CharacterSheet.instance:FireEvent("refreshAll")
                    element.parent:SetClass("collapsed", true)
                end,
            },

            gui.CloseButton{
                floating = true,
                valign = "top",
                halign = "right",
                click = function(element)
                    element.parent:SetClass("collapsed", true)
                end
            },
        }        

        return resultPanel
    end

    local TokenDropdownOptions = function(partyid, followerType)
        local results = {
            {
                id = "none",
                text = "Select " .. string.upper_first(followerType) .. " Token",
            },
        }

        --Our Party
        local partyMembers = dmhub.GetCharacterIdsInParty(partyid) or {}
        for _, charid in ipairs(partyMembers) do
            local token = dmhub.GetTokenById(charid)
            if token ~= nil then
                if followerType == "retainer" then
                    if token.properties:IsRetainer() then
                        results[#results + 1] = {
                            id = charid,
                            text = token.name,
                        }
                    end
                elseif followerType == "artisan" then
                    if token.properties:IsArtisan() then
                        results[#results + 1] = {
                            id = charid,
                            text = token.name,
                        }
                    end
                elseif followerType == "sage" then
                    if token.properties:IsSage() then
                        results[#results + 1] = {
                            id = charid,
                            text = token.name,
                        }
                    end
                end
            end
        end

        --Allied Parties
        local partyInfo = GetParty(partyid)
        for id, _ in pairs(partyInfo.allyParties) do
            partyMembers = dmhub.GetCharacterIdsInParty(id) or {}
            for _, charid in ipairs(partyMembers) do
                local token = dmhub.GetTokenById(charid)
                if token ~= nil then
                    if followerType == "retainer" then
                    if token.properties:IsRetainer() then
                        results[#results + 1] = {
                            id = charid,
                            text = token.name,
                        }
                    end
                elseif followerType == "artisan" then
                    if token.properties:IsArtisan() then
                        results[#results + 1] = {
                            id = charid,
                            text = token.name,
                        }
                    end
                elseif followerType == "sage" then
                    if token.properties:IsSage() then
                        results[#results + 1] = {
                            id = charid,
                            text = token.name,
                        }
                    end
                end
                end
            end
        end

        return results
    end

    local CreateFollowersSection = function(i, params)
        local resultPanel

        local tok = CharacterSheet.instance.data.info.token
        local followers = tok.properties:GetFollowers()
        local follower = followers[i]

        local args = {
            classes = {"framedPanel"},
            width = "95%",
            height = "auto",
            flow = "vertical",
            halign = "center",
            bgimage = 'panels/square.png',
            bgcolor = Styles.backgroundColor,
            borderColor = Styles.textColor,
            borderWidth = 2,
            margin = 5,
            pad = 5,
            minHeight = 180,

            styles = Styles,

            refreshToken = function(element, info)
                followers = info.token.properties:GetFollowers()
                follower = followers[i]
            end,

            gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = "auto",
                vmargin = 4,
                gui.Label{
                    classes = { "followerNameLabel"},
                    text = follower.name or "Unnamed",

                    edit = function(element)
                        element:FireEvent("change")
                    end,

                    refreshAll = function(element, info)
                        local followerToken = dmhub.GetTokenById(follower.followerToken)
                        if followerToken then
                            element.text = creature.GetTokenDescription(followerToken)
                        end
                    end,
                },
                gui.DeleteItemButton {
                    width = 24,
                    height = 24,
                    halign = "right",
                    click = function(element)
                        resultPanel:FireEvent("delete")
                    end,
                },
            },

            gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = "auto",
                vmargin = 4,

                gui.Panel {
                    classes = { "avatarPanel"},
                    halign = "left",
                    valign = "top",
                    flow = "vertical",

                    bgimage = follower.portrait,

                    click = function(element)
                        local followerToken = dmhub.GetTokenById(follower.followerToken)
                        followerToken:ShowSheet()
                    end,

                    refreshAll = function(element)
                        local followerToken = dmhub.GetTokenById(follower.followerToken)
                        if followerToken then
                            element.bgimage = followerToken.offTokenPortrait
                        end
                    end,
                },

                gui.Panel{
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    flow = "vertical",

                    gui.Panel{
                        flow = "vertical",
                        width = "100%",
                        height = "auto",

                        gui.Panel{
                            flow = "horizontal",
                            width = "auto",
                            height = 30,
                            gui.Label{
                                classes = { "followerLabel"},
                                width = "auto",
                                height = "auto",
                                text = "Type:",
                            },
                            gui.Label{
                                classes = { "followerLabel", (cond(follower.manual, "collapsed"))},
                                width = "auto",
                                height = "auto",
                                text = string.upper_first(follower.type),
                            },
                            gui.Dropdown{
                                classes = (cond(not follower.manual, "collapsed")),
                                options = {
                                    {id = "artisan", text = "Artisan"},
                                    {id = "sage", text = "Sage"},
                                    {id = "retainer", text = "Retainer"},
                                },

                                idChosen = follower.type,

                                refreshAll = function(element)
                                    element.idChosen = follower.type
                                end,

                                change = function(element)
                                    follower.type = element.idChosen
                                    resultPanel:FireEventTree("refreshAll")
                                end,
                            },
                        },

                        gui.Panel{
                            flow = "horizontal",
                            width = "auto",
                            height = 30,

                            gui.Label{
                                classes = { "followerLabel"},
                                width = "auto",
                                height = "auto",
                                text = "Token:",
                            },

                            gui.Dropdown{
                                options = TokenDropdownOptions(tok.partyid, follower.type),

                                idChosen = follower.followerToken or "none",

                                refreshAll = function(element)
                                    element.options = TokenDropdownOptions(tok.partyid, follower.type)
                                end,
                                
                                change = function(element)
                                    follower.followerToken = element.idChosen
                                    resultPanel:FireEventTree("refreshAll")
                                end,
                            },
                        },
                    }
                }
            }
        }

        for k, p in pairs(params) do
            args[k] = p
        end

        resultPanel = gui.Panel(args)
        return resultPanel
    end

    local addFollowerButton = gui.Button{
        hmargin = 15,
        halign = "right",
        valign = "top",
        text = "Add New Follower",
        click = function(element)
            local followerDiag = element:Get("followerSelectionDialog")
            followerDiag:SetClass("collapsed", false)
            followerDiag:FireEvent("newFollower")
        end,
    }

    local topPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        FollowerSelectionDialog(),
        addFollowerButton,
    }

    local followerPanels = {}

    return gui.Panel {
        width = "100%",
        height = "100%",
        halign = "center",
        vscroll = true,

        gui.Panel{
            width = "97%",
            height = "auto",
            hmargin = 4,
            halign = "left",
            flow = "vertical",

            topPanel,
        
            refreshToken = function(element, info)
                local followers = info.token.properties:GetFollowers()
                local children = {topPanel}
                local newFollowerPanels = {}

                for i, follower in ipairs(followers) do
                    
                    local child = followerPanels[follower.guid]
                    if not child then
                        child = CreateFollowersSection(i, {
                            delete = function()
                                local followers = EnsureFollowers(info.token.properties)
                                for id, f in ipairs(followers) do
                                    if f.guid == follower.guid then
                                        table.remove(followers, id)
                                        break
                                    end
                                end
                                CharacterSheet.instance:FireEvent("refreshAll")
                            end,
                        })
                    end

                    newFollowerPanels[follower.guid] = child
                    children[#children + 1] = child
                end

                followerPanels = newFollowerPanels

                element.children = children
            end,
        }
    }
end
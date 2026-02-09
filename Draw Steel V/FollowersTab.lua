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

local retainerDropdownOptions = {}
local retainerLookup = {} 

dmhub.RegisterEventHandler("refreshTables", function(keys)
    retainerDropdownOptions, retainerLookup = buildRetainerList()
end)

FollowerTokenDropdownOptions = function(partyid, alliesOnly)
        local results = {
            {
                id = "none",
                text = "Select Follower Token",
            },
        }

        if not alliesOnly then
            local parties = GetAllParties()
            for _, id in ipairs(parties) do
                local partyMembers = dmhub.GetCharacterIdsInParty(id) or {}
                for _, charid in ipairs(partyMembers) do
                    local token = dmhub.GetCharacterById(charid)
                    if token ~= nil then
                        if token.properties:IsFollower() then
                            results[#results + 1] = {
                                id = charid,
                                text = token.name,
                            }
                        end
                    end
                end
            end
        else
            local partyid = partyid or GetDefaultPartyID()
            --Our Party
            local partyMembers = dmhub.GetCharacterIdsInParty(partyid) or {}
            for _, charid in ipairs(partyMembers) do
                local token = dmhub.GetCharacterById(charid)
                if token ~= nil then
                    if token.properties:IsFollower() then
                        results[#results + 1] = {
                            id = charid,
                            text = token.name,
                        }
                    end
                end
            end

            --Allied Parties
            local partyInfo = GetParty(partyid)
            for id, _ in pairs(partyInfo.allyParties) do
                partyMembers = dmhub.GetCharacterIdsInParty(id) or {}
                for _, charid in ipairs(partyMembers) do
                    local token = dmhub.GetCharacterById(charid)
                    if token ~= nil then
                        if token.properties:IsFollower() then
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

function CharSheet.FollowersInnerPanel()

    local FollowerTokenSelectionPanel = function(mentorToken)
        if not mentorToken then return end
        local resultsPanel
        resultsPanel = gui.Panel{
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
                options = FollowerTokenDropdownOptions(mentorToken.partyid, true),

                idChosen = follower.followerToken,

                refreshAll = function(element)
                    element.options = FollowerTokenDropdownOptions(mentorToken.partyid, true)
                end,
                
                change = function(element)
                    follower.followerToken = element.idChosen
                    resultPanel:FireEventTree("refreshAll")
                end,
            },
        }

        return resultsPanel
    end

    local FollowerSelectionDialog = function()
        local resultPanel

        local mentorToken
        local newFollowerType = "none"
        local follower = {}
        local options = {}

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
                --initialive follower information
                follower = {
                    type = "artisan",
                    name = "New Follower",
                    characteristic = "mgt",
                    ancestry = Race.DefaultRace(),
                    manual = false,
                    followerToken = "none",
                }
                newFollowerType = "none"
                options = {}
                mentorToken = CharacterSheet.instance.data.info.token
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
                    follower.manual = (element.idChosen == "existing")
                    resultPanel:FireEventTree("refreshAll")
                end,

                refreshAll = function(element)
                    element.idChosen = newFollowerType
                end,
            },

            gui.Panel{
                classes = {"collapsed-anim"},
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

                    refreshAll = function(element)
                        element.text = follower.name or ""
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

            --Retainers from Bestiary
            gui.Panel{
                classes = {"collapsed-anim"},
                width = "auto",
                height = "auto",
                vmargin = 5,

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

                    refreshAll = function(element)
                        retainerDropdownOptions, retainerLookup = buildRetainerList()
                        element.idChosen = options.pregenid or "none"
                    end,

                    change = function(element)
                        options.pregenid = element.idChosen
                    end,
                },
            },

            --Artisan or Sage characteristics
            gui.Panel{
                classes = {"collapsed"},
                flow = "vertical",
                height = "auto",
                width = "auto",
                refreshAll = function(element)
                    if newFollowerType ~= "artisan" and newFollowerType ~= "sage" then
                        element:SetClass("collapsed-anim", true)
                    else
                        element:SetClass("collapsed-anim", false)
                        element:SetClass("collapsed", false)
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
                    classes = {"collapsed-anim"},
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

                        idChosen = follower.characteristic,
                        
                        change = function(element)
                            follower.characteristic = element.idChosen
                            resultPanel:FireEventTree("refreshAll")
                        end,

                        refreshAll = function(element)
                            element.idChosen = follower.characteristic
                        end,
                    },
                },
            },

            gui.Panel{
                classes = {"collapsed-anim"},
                flow = "horizontal",
                width = "auto",
                height = 30,

                refreshAll = function(element)
                    if newFollowerType == "existing" then
                        element:SetClass("collapsed-anim", false)
                    else
                        element:SetClass("collapsed-anim", true)
                    end
                end,

                gui.Label{
                    classes = { "followerLabel"},
                    width = "auto",
                    height = "auto",
                    text = "Token:",
                },

                gui.Dropdown{
                    idChosen = options.followerToken or "none",

                    refreshAll = function(element)
                        element.options = FollowerTokenDropdownOptions(mentorToken.partyid, true)
                    end,
                    
                    change = function(element)
                        options.followerToken = element.idChosen
                        resultPanel:FireEventTree("refreshAll")
                    end,
                },
            },

            gui.Button{
                floating = true,
                valign = "bottom",
                halign = "center",
                interactable = newFollowerType ~= "none",
                text = "Create",
                fontSize = 25,

                refreshAll = function(element)
                    element.interactable = newFollowerType ~= "none"
                end,

                click = function(element)
                    local mentorToken = CharacterSheet.instance.data.info.token
                    CreateFollowerMonster(follower, newFollowerType, mentorToken, options)
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

    local CreateFollowersSection = function(id, params)
        local resultPanel

        local tok = CharacterSheet.instance.data.info.token
        local followers = tok.properties:GetFollowers()
        local follower = dmhub.GetCharacterById(id)

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
                follower = dmhub.GetCharacterById(id)
            end,

            gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = "auto",
                vmargin = 4,
                gui.Label{
                    classes = { "followerNameLabel"},
                    text = follower and creature.GetTokenDescription(follower) or "Unnamed",

                    edit = function(element)
                        element:FireEvent("change")
                    end,

                    refreshAll = function(element, info)
                        if follower then
                            element.text = creature.GetTokenDescription(follower)
                        else
                            element.text = "Unnamed"
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

                    bgimage = follower and follower.offTokenPortrait or "",

                    click = function(element)
                        if follower then
                            follower:ShowSheet()
                        end
                    end,

                    refreshAll = function(element)
                        if follower then
                            element.bgimage = follower.offTokenPortrait
                        else
                            element.bgimage = ""
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
                                classes = { "followerLabel"},
                                width = "auto",
                                height = "auto",
                                text = follower and follower.properties and follower.properties:has_key("followerType") and follower.properties.followerType and string.upper_first(follower.properties.followerType) or "Unknown",


                                refreshAll = function(element)
                                    if follower and follower.properties and follower.properties.followerType then
                                        element.text = string.upper_first(follower.properties.followerType)
                                    else
                                        element.text = "Unknown"
                                    end
                                end,
                            },
--[[                             gui.Dropdown{
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
                            }, ]]
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
                                idChosen = id,
                                options = (function()
                                    local mentorToken = CharacterSheet.instance.data.info.token
                                    return mentorToken and FollowerTokenDropdownOptions(mentorToken.partyId, true) or {}
                                end)(),

                                refreshAll = function(element)
                                    local mentorToken = CharacterSheet.instance.data.info.token
                                    if mentorToken then
                                        element.options = FollowerTokenDropdownOptions(mentorToken.partyId, true)
                                        element.idChosen = id
                                    end
                                end,
                                
                                change = function(element)
                                    local mentorToken = CharacterSheet.instance.data.info.token
                                    if mentorToken then
                                        mentorToken:ModifyProperties{
                                            description = "Reassign Follower",
                                            execute = function()
                                                local followers = mentorToken.properties:EnsureFollowers()
                                                followers[id] = nil
                                                followers[element.idChosen] = true
                                            end,
                                        }
                                        CharacterSheet.instance:FireEvent("refreshAll")
                                    end
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
            followerDiag:FireEvent("newFollower")
            followerDiag:SetClass("collapsed", false)
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
                local mentorToken = info.token
                local followers = mentorToken.properties:GetFollowers()
                local children = {topPanel}
                local newFollowerPanels = {}

                for followerId, _ in pairs(followers) do
                    
                    local child = followerPanels[followerId]
                    if not child then
                        child = CreateFollowersSection(followerId, {
                            delete = function()
                                mentorToken.properties:RemoveFollowerFromMentor(followerId)
                                CharacterSheet.instance:FireEvent("refreshAll")
                            end,
                        })
                    end

                    newFollowerPanels[followerId] = child
                    children[#children + 1] = child
                end

                followerPanels = newFollowerPanels

                element.children = children
            end,
        }
    }
end
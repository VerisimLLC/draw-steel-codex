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
        classes = { "avatarPanel"},
        borderColor = Styles.textColor,
        borderWidth = 2,
        width = 80,
        height = 120,
        halign = "center",
        valign = "center",
        bgcolor = "white",
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
    }
}

local function countSkills(skills)
    local count = 0
    if skills then
        for id, _ in pairs(skills) do
            count = count + 1
        end
    end
    return count
end

--Seperate skills into crafting and lore for Artisan and Sage followers
local function buildSkillLists()
    local skills = dmhub.GetTable(Skill.tableName) or {}
    local artisanSkills = {}
    local sageSkills = {}

    for id, skill in unhidden_pairs(skills) do
        if skill.category == "crafting" then
            artisanSkills[#artisanSkills + 1] = {
                id = id,
                text = skill.name,
            }
        elseif skill.category == "lore" then
            sageSkills[#sageSkills + 1] = {
                id = id,
                text = skill.name,
            }
        end
    end

    table.sort(artisanSkills, function(a,b)
        return string.lower(a.text) < string.lower(b.text)
    end)

    table.sort(sageSkills, function(a,b)
        return string.lower(a.text) < string.lower(b.text)
    end)

    return artisanSkills, sageSkills
end

local buildLanguageList = function()
    local list = Language.GetDropdownList()
    table.insert(list, 1, { id = "none", text = "Add Language" })
    return list
end

function CharSheet.FollowersInnerPanel()
    --Create Follower table if it does not exist
    local EnsureFollowers = function(creature)
        local followers = creature:try_get("followers")
        if not followers then
            creature.followers = {}
        end
        return creature.followers
    end

    local FollowerAvatar = function(follower)
        local resultPanel

        resultPanel = gui.Panel {
            halign = "left",
            valign = "top",
            flow = "vertical",

            gui.IconEditor {
                classes = { "avatarPanel"},
                library = "Avatar",
                restrictImageType = "Avatar",
                allowPaste = true,
                value = follower.portrait or false,

                refreshAll = function(element, info)
                    if follower and follower:try_get("followerToken") then
                        local followerToken = dmhub.GetTokenById(follower.followerToken)
                        if followerToken then
                            local portrait = followerToken.portrait
                            follower.portrait = portrait
                            element.value = portrait
                        end
                    else
                        element.value = follower.portrait or false
                    end
                end,

                change = function(element)
                    if follower then
                        follower.portrait = element.value
                    end
                end,
            },
        }

        return resultPanel
    end

    local FollowerSkillsPanel = function(follower)
        local resultsPanel
        local artisanSkills, sageSkills = buildSkillLists()

        resultsPanel = gui.Multiselect{
            classes = {cond(follower.type == "retainer", "collapsed-anim")},
            options = (follower.type == "sage") and sageSkills or artisanSkills,
            width = "auto",
            height = "auto",
            margin = 3,
            flow = "horizontal",
            sort = true,
            textDefault = "Select 4 skills...",
            dropdown = {
                width = 170,
            },
            chipPos = "right",
            chipPanel = {
               width = "100%-160",
                halign = "left",
            },
            chips = {
                halign = "left",
                valign = "center",
            },
            create = function(element)
                element:FireEvent("refreshAll")
            end,
            change = function(element)
                if element.idChosen == "none" then return end
                follower.skills = element.value
            end,
            refreshAll = function(element)
                if follower.type == "retainer" then
                    element:SetClass("collapsed-anim", true)
                    return
                else
                    element:SetClass("collapsed-anim", false)
                end

                local options = follower.type == "sage" and sageSkills or artisanSkills
                local selected = follower.skills or {}
                element:FireEvent("refreshSet", options, selected)
                element.value = selected
            end,
        }

        return resultsPanel
    end

    local FollowersLanguagesPanel = function(follower)
        local resultsPanel

        local languageList = buildLanguageList()

        resultsPanel = gui.Multiselect{
            classes = {cond(follower.type == "retainer", "collapsed-anim")},
            options = languageList,
            width = "auto",
            height = "auto",
            margin = 3,
            flow = "horizontal",
            sort = true,
            textDefault = "Select 2 languages...",
            dropdown = {
                width = 170,
            },
            chipPos = "right",
            chipPanel = {
               width = "100%-160",
                halign = "left",
            },
            chips = {
                halign = "left",
                valign = "center",
            },
            create = function(element)
                element:FireEvent("refreshAll")
            end,
            change = function(element)
                if element.idChosen == "none" then return end
                follower.languages = element.value
            end,
            refreshAll = function(element)
                if follower.type == "retainer" then
                    element:SetClass("collapsed-anim", true)
                    return
                else
                    element:SetClass("collapsed-anim", false)
                end
                local selected = follower.languages or {}
                element:FireEvent("refreshSet", languageList, selected)
                element.value = selected
            end,
        }

        return resultsPanel
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
        print("Members1::", json(partyMembers))
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

        local tokenOptions = TokenDropdownOptions(tok.partyid, "retainer")

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
                    editable = true,

                    edit = function(element)
                        element:FireEvent("change")
                    end,

                    refreshAll = function(element, info)
                        if follower and follower:try_get("followerToken") then
                            local followerToken = dmhub.GetTokenById(follower.followerToken)
                            if followerToken then
                                element.text = creature.GetTokenDescription(followerToken)
                            end
                            element.editable = false
                        else
                            element.text = follower.name or "Unnamed"
                            element.editable = true
                        end
                    end,

                    change = function(element, info)
                        if follower then
                            follower.name = element.text
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

                FollowerAvatar(follower),

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
                            gui.Dropdown{
                                options = {
                                    {
                                        id = "artisan",
                                        text = "Artisan",
                                    },
                                    {
                                        id = "retainer",
                                        text = "Retainer",
                                    },
                                    {
                                        id = "sage",
                                        text = "Sage",
                                    },
                                },
                                idChosen = follower.type,
                                
                                change = function(element)
                                    follower.type = element.idChosen
                                    resultPanel:FireEventTree("refreshAll")
                                end,
                            },
                            gui.Check{
                                classes = {cond(follower.type == "retainer", "collapsed-anim")},
                                text = "Assign Token",
                                hover = gui.Tooltip("If checked, a token must be assigned and it's properties will be used."),
                                value = follower:try_get("assignToken"),
                                refreshAll = function(element)
                                    if follower.type ~= "retainer" then
                                        element:SetClass("collapsed-anim", false)
                                    else
                                        element:SetClass("collapsed-anim", true)
                                    end
                                end, 
                                change = function(element)
                                    follower.assignToken = element.value
                                    resultPanel:FireEventTree("refreshAll")
                                end,
                            }
                        },

                        --Artisan or Sage characteristics
                        gui.Panel{
                            classes = {cond(follower.type == "retainer" or follower:try_get("assignToken"), "collapsed-anim")},
                            flow = "vertical",
                            height = "auto",
                            width = "auto",
                            refreshAll = function(element)
                                if follower.type == "retainer" or follower:try_get("assignToken") then
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
                                    end,
                                }
                            },

                            gui.Panel{
                                classes = {cond(follower.type ~= "artisan", "collapsed-anim")},
                                flow = "horizontal",
                                width = "auto",
                                height = 30,

                                refreshAll = function(element)
                                    if follower.type == "artisan" then
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

                            gui.Panel{
                                width = "100%",
                                height = "auto",
                                flow = "vertical",
                                pad = 5,
                                
                                FollowerSkillsPanel(follower),
                                FollowersLanguagesPanel(follower),
                            },
                        },

                        gui.Panel{
                            classes = {cond(not (follower.type == "retainer" or follower:try_get("assignToken")), "collapsed-anim")},
                            flow = "horizontal",
                            width = "auto",
                            height = 30,

                            refreshAll = function(element)
                                if not (follower.type == "retainer" or follower:try_get("assignToken")) then
                                    element:SetClass("collapsed-anim", true)
                                else
                                    element:SetClass("collapsed-anim", false)
                                end
                            end,

                            gui.Label{
                                classes = { "followerLabel"},
                                width = "auto",
                                height = "auto",
                                text = "Token:",
                            },

                            gui.Dropdown{
                                options = tokenOptions,

                                idChosen = follower:try_get("followerToken") or "none",

                                refreshAll = function(element)
                                    tokenOptions = TokenDropdownOptions(tok.partyid, follower.type)
                                    element.options = tokenOptions
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
        text = "Add New Follower",
        click = function(element)
            local followers = EnsureFollowers(CharacterSheet.instance.data.info.token.properties)
            local newFollower = Follower.Create()
            newFollower.ancestry = Race.DefaultRace()
            newFollower.followerToken = "none"

            followers[#followers + 1] = newFollower
            CharacterSheet.instance:FireEvent("refreshAll")
        end,
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

            addFollowerButton,

            refreshToken = function(element, info)
                local followers = info.token.properties:GetFollowers()
                local children = {}
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

                children[#children + 1] = addFollowerButton

                element.children = children
            end,
        }
    }
end
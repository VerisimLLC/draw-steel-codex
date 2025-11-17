local mod = dmhub.GetModLoading()

function character:GetFollowers()
    return self:try_get("followers") or {}
end

function monster:GetFollowers()
    return {}
end

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
    for id, _ in pairs(skills) do
        count = count + 1
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
    table.insert(artisanSkills, 1, { id = "none", text = "Add Artisan Skill" })

    table.sort(sageSkills, function(a,b)
        return string.lower(a.text) < string.lower(b.text)
    end)
    table.insert(sageSkills, 1, { id = "none", text = "Add Sage Skill" })

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

                thinkTime = 0.2,
                think = function(element)
                    element:FireEvent("imageLoaded")
                end,

                refreshToken = function(element, info)
                    if follower and follower.portrait then
                        element:SetValue(follower.portrait, false)
                        element:FireEvent("imageLoaded")
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

        resultsPanel = gui.Panel{
            classes = {cond(follower.type == "retainer", "collapsed-anim")},
            flow = "vertical",
            width = "auto",
            height = 150,
            margin = 3,

            refreshAll = function(element)
                if follower.type == "retainer" then
                    element:SetClass("collapsed-anim", true)
                else
                    element:SetClass("collapsed-anim", false)
                end
            end,

            gui.Label{
                classes = { "followerLabel"},
                text = "Skills",
            },
            
            gui.Dropdown{
                classes = {"followerDropdown" ,cond((countSkills(follower.skills)) >= 4 , "collapsed-anim")},
                width = 190,
                valign = "top",
                idChosen = "none",
                options = (follower.type == "sage") and sageSkills or artisanSkills,
                change = function(element)
                    if element.idChosen == "none" then return end
                    follower.skills[element.idChosen] = true
                    resultsPanel:FireEventTree("refreshAll")
                end,

                refreshList = function(element)
                    local currentType = follower.type or "artisan"
                    if currentType == "retainer" then return end
                    
                    local sourceSkills = (currentType == "sage") and sageSkills or artisanSkills
                    local filteredOptions = {}
                    
                    for _, skill in pairs(sourceSkills) do
                        if skill.id == "none" or not follower.skills[skill.id] then
                            table.insert(filteredOptions, skill)
                        end
                    end
                    
                    element.options = filteredOptions
                    element.idChosen = "none"
                end,
                
                refreshAll = function(element)
                    element:FireEvent("refreshList")
                    if countSkills(follower.skills) >= 4 then
                        element:SetClass("collapsed-anim", true)
                    else
                        element:SetClass("collapsed-anim", false)
                    end
                end,
            },

            -- Skill List
            gui.Panel{
                width = "auto",
                height = "auto", 
                flow = "vertical",
                create = function(element)
                    element:FireEvent("refreshAssets")
                end,

                refreshAll = function(element)
                    element:FireEvent("refreshAssets")
                end,

                refreshAssets = function(element)
                    local skillsList = follower.skills or {}
                    local children = {}

                    local skilltable = dmhub.GetTable(Skill.tableName) or {}

                    for id, _ in pairs(skillsList) do
                        local skill = skilltable[id]

                        children[#children+1] = gui.Panel{
                            height = "auto",
                            width = "auto",
                            gui.Label{
                                classes = { "followersListLabel"},
                                text = skill.name,
                            },
                            gui.CloseButton{
                                uiscale = 0.7,
                                valign = "center",
                                escapeActivates = false,
                                click = function()
                                    follower.skills[id] = nil
                                    resultsPanel:FireEventTree("refreshAll")
                                end
                            }
                        }
                    end

                    element.children = children
                end,
            }
        }

        return resultsPanel
    end

    local FollowersLanguagesPanel = function(follower)
        local resultsPanel

        local languageList = buildLanguageList()

        resultsPanel = gui.Panel{
            classes = {cond(follower.type == "retainer", "collapsed-anim")},
            flow = "vertical",
            width = "auto",
            margin = 3,
            height = 150,

            gui.Label{
                classes = { "followerLabel"},
                text = "Languages",
            },

            gui.Dropdown{
                classes = {"followerDropdown", cond((countSkills(follower.languages)) >= 2 , "collapsed-anim")},
                idChosen = "none",
                options = languageList,
                change = function(element)
                    if element.idChosen == "none" then return end
                    follower.languages[element.idChosen] = true
                    resultsPanel:FireEventTree("refreshAll")
                end,

                refreshList = function(element)
                    local currentType = follower.type or "artisan"
                    if currentType == "retainer" then return end
                    
                    local filteredOptions = {}
                    
                    for _, language in pairs(languageList) do
                        if language.id == "none" or not follower.languages[language.id] then
                            table.insert(filteredOptions, language)
                        end
                    end
                    
                    element.options = filteredOptions
                    element.idChosen = "none"
                end,

                refreshAll = function(element)
                    element:FireEvent("refreshList")
                    if countSkills(follower.languages) >= 2 then
                        element:SetClass("collapsed-anim", true)
                    else
                        element:SetClass("collapsed-anim", false)
                    end
                end,
            },

            -- Language List
            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "vertical",
                create = function(element)
                    element:FireEvent("refreshAssets")
                end,
                refreshAll = function(element)
                    element:FireEvent("refreshAssets")
                end,
                refreshAssets = function(element)
                    local languagesList = follower.languages or {}
                    local children = {}

                    local languagetable = dmhub.GetTable(Language.tableName) or {}

                    for id, _ in pairs(languagesList) do
                        local language = languagetable[id]

                        children[#children+1] = gui.Panel{
                            height = "auto",
                            width = "auto",
                            gui.Label{
                                classes = { "followersListLabel"},
                                text = language.name,
                            },
                            gui.CloseButton{
                                uiscale = 0.7,
                                valign = "center",
                                escapeActivates = false,
                                click = function()
                                    follower.languages[id] = nil
                                    resultsPanel:FireEventTree("refreshAll")
                                end
                            }
                        }
                    end

                    element.children = children
                end,
            },

            refreshAll = function(element)
                if follower.type == "retainer" then
                    element:SetClass("collapsed-anim", true)
                else
                    element:SetClass("collapsed-anim", false)
                end
            end,
        }

        return resultsPanel
    end

    local CreateFollowersSection = function(i, params)
        local resultPanel

        local followers = CharacterSheet.instance.data.info.token.properties:GetFollowers()
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
                local followers = info.token.properties:GetFollowers()
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

                    refreshToken = function(element, info)
                        if follower then
                            element.text = follower.name
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
                            }
                        },

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
                            classes = {cond(follower.type ~= "retainer", "collapsed-anim")},
                            flow = "horizontal",
                            width = "auto",
                            height = 30,

                            refreshAll = function(element)
                                if follower.type == "retainer" then
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
                                options = {},

                                idChosen = follower.retainerToken or "none",
                                
                                change = function(element)
                                    follower.retainerToken = element.idChosen
                                    resultPanel:FireEventTree("refreshAll")
                                end,
                            },
                        },

                        gui.Panel{
                            width = "100%",
                            height = "auto",
                            flow = "horizontal",
                            pad = 5,
                            
                            FollowerSkillsPanel(follower),
                            FollowersLanguagesPanel(follower),
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

    local addFollowerButton = gui.AddButton {
        hmargin = 15,
        halign = "right",
        linger = function(element)
            gui.Tooltip("Add a New Follower")(element)
        end,
        click = function(element)
            local followers = EnsureFollowers(CharacterSheet.instance.data.info.token.properties)
            followers[#followers + 1] = {
                guid = dmhub.GenerateGuid(),
                name = "New Follower",
                type = "artisan",
                description = "",
                portrait = false,
                skills = {},
                ancestry = Race.DefaultRace(),
                characteristic = "mgt",
                languages = {},
            }
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
                    local child = followerPanels[i] or CreateFollowersSection(i, {
                        delete = function()
                            local followers = EnsureFollowers(info.token.properties)
                            table.remove(followers, i)
                            CharacterSheet.instance:FireEvent("refreshAll")
                        end,
                    })

                    newFollowerPanels[i] = child
                    children[#children + 1] = child
                end

                followerPanels = newFollowerPanels

                children[#children + 1] = addFollowerButton

                element.children = children
            end,
        }
    }
end
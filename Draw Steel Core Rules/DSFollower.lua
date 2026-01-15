local mod = dmhub.GetModLoading()

--- @class follower
--- @field follower.availableRolls number
--- @field follower.followerType string artisan|sage|retainer
follower = RegisterGameType("follower", "monster")

follower.availableRolls = 0

function follower.CreateNew(followerType)
    local result = follower.new{
		cr = 1,

        role = "follower",
        followerType = followerType or "artisan",
        availableRolls = 0,

		monster_type = 'Follower', --this is the specific type of monster. e.g. Adult Black Dragon
		monster_category = 'Monster', --this is the "Type" of monster. e.g. Dragon


		damage_taken = 0,
		max_hitpoints = 10,

		attributes = creature.CreateAttributes(),

		walkingSpeed = 5,

        equipment = {
            mainhand1 = "22ab52f5-955b-40c8-80c3-826f823e0a5b",
        },

		--map of skill id -> rating for that skill. 'true' means the monster is proficient and use proficiency bonus.
		skillRatings = {
		},

		--map of saving throw -> rating for that saving throw.
		savingThrowRatings = {
		},

		--list of innate attacks (type = AttackDefinition)
		innateAttacks = {
		},
	}

	return result
end

function creature:EnsureFollowers()
    return {}
end

function creature:GetAvailableRolls()
    return self:try_get("availableRolls", 0)
end

function follower:GetAvailableRolls()
    return self:try_get("availableRolls", 0)
end

function follower:SetAvailableRolls(numRolls)
    self.availableRolls = math.max(0, numRolls)
end

--- Modifies the available rolls counter
--- @param rolls number The number of rolls to add
--- @return follower self For chaining
function follower:GrantRolls(rolls)
    self.availableRolls = math.max(0, self:GetAvailableRolls() + (rolls or 0))
    return self
end

--Create Follower table if it does not exist
---@return table[] table of followers as charid is true
function character:EnsureFollowers()
    local followers = self:try_get("followers")
    if not followers then
        self.followers = {}
    end
    return self.followers
end

---@param followerid string
function character:AddFollowerToMentor(followerid)
    local token = dmhub.LookupToken(self)
    token:ModifyProperties{
        description = "Assign Follower",
        execute = function()
            local followers = self:EnsureFollowers()
            followers[followerid] = true
        end,
    }
end

---@param mentorToken Token[]
---@param followerid string
function character:RemoveFollowerFromMentor(followerid)
    local token = dmhub.LookupToken(self)
    token:ModifyProperties{
        description = "Remove Follower",
        execute = function()
            local followers = self:EnsureFollowers()
            followers[followerid] = nil
        end,
    }
end

---@param follower Token[]
---@param followerInfo table[]
---@param mentorToken Token[]
local SetFollowerPartyInfo = function(follower, followerInfo, mentorToken)
    follower.name = followerInfo.name
    follower.ownerId = mentorToken.ownerId
    follower.partyId = mentorToken.partyId        
end

---@param followerInfo table[]
---@param followerType string artisan, sage, premaderetainer, existing
---@param mentorToken Token[]
---@param pregenid string|nil optional data for creating a pre-made retainer
---@param open boolean will charactersheet open after creation
CreateFollowerMonster = function(followerInfo, followerType, mentorToken, options)
    local pregenid = options and options.pregenid or nil
    local open = options and options.open or true

    if followerType == "existing" and options.followerToken then
        mentorToken.properties:AddFollowerToMentor(options.followerToken)
        return
    end

    local locs = mentorToken.properties:AdjacentLocations()
    local loc = #locs and locs[1] or mentorToken.properties.locsOccupying[1]
    local newCharId
    local newFollower

    dmhub.Coroutine(function()
        if followerType == "retainer" and (pregenid and pregenid ~= "none") then
            newFollower = game.SpawnTokenFromBestiaryLocally(pregenid, loc, {fitLocatoin = true})
            newCharId = newFollower.charid

            SetFollowerPartyInfo(newFollower, followerInfo, mentorToken)
            
            newFollower:UploadToken()
            game.UpdateCharacterTokens()
        else
            --Creates a new follower character
            newCharId = game.CreateCharacter("follower")
            --Wait for follower character to be created
            for i = 1, 100 do
                local newFollower = dmhub.GetCharacterById(newCharId)
                if newFollower ~= nil then
                    newFollower.properties = follower.CreateNew(followerType)

                    SetFollowerPartyInfo(newFollower, followerInfo, mentorToken)

                    local newFollowerCreature = newFollower.properties

                    --Set basic follower property
                    newFollowerCreature.role = "Follower"
                    
                    --Set Attributes based upon followerInfo
                    if followerInfo.type ~= "retainer" then
                        newFollowerCreature.attributes["rea"].baseValue = 1
                        if newFollowerCreature.followerType == "sage" then
                            newFollowerCreature.attributes["inu"].baseValue = 1
                        elseif newFollowerCreature.followerType == "artisan" then
                            newFollowerCreature.attributes[followerInfo.characteristic].baseValue = 1
                        end
                    else
                        --Creature template for retainers in compendium
                        newFollowerCreature.creatureTemplates = {}
                        newFollowerCreature.creatureTemplates[#newFollowerCreature.creatureTemplates + 1] = "25263715-cef4-4e25-b4bd-ddedc3a87dea"
                    end

                    --Search for ancestry in compendium bands
                    local ancestryTable = dmhub.GetTable(Race.tableName)
                    local ancestry = ancestryTable[followerInfo.ancestry]
                    local bandTable = dmhub.GetTable(MonsterGroup.tableName)
                    local found = false
                    for id, band in pairs(bandTable) do
                        if string.lower(band.name) == string.lower(ancestry.name) then
                            newFollowerCreature.groupid = id
                            newFollowerCreature.keywords = {}
                            newFollowerCreature.keywords[band.name] = true
                            found = true
                            break
                        end
                    end
                    --Set custom keywords for follower if not found in compendium bands
                    if not found then
                        newFollowerCreature.keywords = {}
                        newFollowerCreature.keywords[ancestry.name] = true
                    end
                    if followerInfo.portrait then
                        newFollower.portrait = followerInfo.portrait
                    end

                    --Set skills and languages for followers
                    newFollowerCreature.skillRatings = followerInfo.skills or {}
                    newFollowerCreature.innateLanguages = followerInfo.languages or {}
                    
                    newFollower:UploadToken()
                    game.UpdateCharacterTokens()
                    newFollower:ChangeLocation(core.Loc{x = loc.x, y = loc.y})
                    break
                end
                coroutine.yield(0.1)
            end
        end
        local newFollower = dmhub.GetTokenById(newCharId)
        mentorToken.properties:AddFollowerToMentor(newFollower.id)
        
        if open ~= false then
            newFollower:ShowSheet()
        end
    end)

end

function DescribeFollower(follower)
    local function numToString(v)
        local n = tonumber(v)
        if n then
            return string.format("%d", math.floor(n))
        end
        return "?"
    end

    local followerType = follower.type
    local s = string.format("<b>%s Follower</b>", string.upper_first(followerType))

    if followerType == "artisan" or followerType == "sage" then
        if follower.ancestry then
            s = s .. "\n<b>Ancestry:</b> "
            s = s .. dmhub.GetTable(Race.tableName)[follower.ancestry].name
        end

        if follower.skills and next(follower.skills) then
            s = s .. "\n<b>Skills:</b> "
            local sList = ""
            local skills = dmhub.GetTable(Skill.tableName)
            for id, _ in pairs(follower.skills) do
                if #sList > 0 then sList = sList .. ", " end
                sList = sList .. skills[id].name
            end
            s = s .. sList
        end

        if follower.languages and next(follower.languages) then
            s = s .. "\n<b>Languages:</b> "
            local sList = ""
            local langs = dmhub.GetTable(Language.tableName)
            for id, _ in pairs(follower.languages) do
                if #sList > 0 then sList = sList .. ", " end
                sList = sList .. langs[id].name
            end
            s = s .. sList
        end
    else
        local id = follower.retainerType
        if id and #id > 0 then
            local node = assets:GetMonsterNode(id)
            if node and node.monster and node.monster.info then
                local t = node.monster.info
                s = string.format("%s\n%s", s, t.description)
                if t.properties then
                    local m = t.properties

                    local keywords = m:Keywords()
                    if keywords and next(keywords) then
                        local keys = {}
                        for key, value in pairs(keywords) do
                            if value then
                                keys[#keys + 1] = key
                            end
                        end
                        s = string.format("%s\n%s", s, table.concat(keys, ", "))
                    end

                    local level = numToString(m:Level())
                    local role = m:Role() or "Retainer"
                    s = string.format("%s\nLevel %s %s", s, level, string.upper_first(role))

                    local stam = numToString(m.max_hitpoints)
                    local speed = numToString(m.walkingSpeed)
                    s = string.format("%s\n%s Stamina, %s Speed", s, stam, speed)
                end
            end
        end
    end

    local atl = ""
    if follower.assignedTo ~= "" then
        local token = dmhub.GetTokenById(follower.assignedTo)

        if token then
            local name = creature.GetTokenDescription(token)
            atl = atl .. "<b>Assigned To:</b> " .. name
        end
    end

    if #atl > 0 then
        s = string.format("%s\n\n%s", s, atl)
    end

    return s
end

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

local function buildLanguageList()
    return Language.GetDropdownList()
end

function buildRetainerList()
    local retainerTypes = { { id = "none", text = "Select retainer type...", }, }
    local retainerLookup = {}

    local function processNode(node)
        if node then
            if node.monster then
                local m = node.monster
                if m.info and m.info.properties and m.info.properties:IsRetainer() then
                    retainerTypes[#retainerTypes + 1] = {
                        id = node.id,
                        text = m.info.description
                    }
                    retainerLookup[node.id] = m.info.description
                end
            else
                for _,n in pairs(node.children) do
                    processNode(n)
                end
            end
        end
    end

    processNode(assets:GetMonsterNode(""))

    return retainerTypes, retainerLookup
end

local DialogStyles = {
    gui.Style{
        selectors = { "avatarPanel"},
        borderColor = Styles.textColor,
        borderWidth = 2,
        width = 90,
        height = 120,
        halign = "left",
        valign = "top",
        bgcolor = "white",
    },
    gui.Style{
        selectors = { "followerLabel"},
        height = 25,
        minWidth = 120,
        valign = "center",
        fontSize = 20,
        bold = true,
        fontFace = "Berling",
    },
    gui.Style{
        selectors = { "followersListLabel"},
        height = 20,
        width = 180,
        valign = "center",
        fontSize = 16,
        fontFace = "Berling",
    },
    gui.Style{
        selectors = { "followerDropdown"},
        width = 190,
        valign = "top",
        fontFace = "Berling",
    },
    gui.Style{
        selectors = { "followerMultiselect" },
        valign ="top",
        fontFace = "Berling",
    },
    gui.Style{
        selectors = { "followerNameLabel"},
        width = "50%",
        height = 25,
        fontSize = 32,
        bold = true,
        color = Styles.textColor,
        fontFace = "Berling",
    },
    gui.Style{
        selectors = {"saveButton"},
        fontSize = 22,
        textAlignment = "center",
        bold = true,
        height = 35,
    }
}

function CreateFollowerEditorDialog(follower, options)
    local types = {
        {id = "artisan", text = "Artisan"},
        {id = "retainer", text = "Retainer"},
        {id = "sage", text = "Sage"},
    }
    local chars = {
        {id = "mgt", text = "Might"},
        {id = "agl", text = "Agility"},
    }
    local artisanSkills, sageSkills = buildSkillLists()
    local languages = buildLanguageList()
    local retainerTypes, retainerLookup = buildRetainerList()

    local editorPanel

    local namePanel = gui.Label {
        classes = {"followerNameLabel"},
        halign = "left",
        text = follower.name or "Unnamed",
        editable = true,
        edit = function(element)
            element:FireEvent("change")
        end,
        change = function(element)
            follower.name = element.text
        end,
        refreshAll = function(element)
            element.text = follower.name or "Unnamed"
        end
    }

    local typePanel = gui.Panel {
        flow = "horizontal",
        width = "auto",
        height = 30,
        margin = 3,
        halign = "left",
        valign = "top",
        children = {
            gui.Label {
                classes = {"followerLabel"},
                width = 80,
                height = "auto",
                text = "Type:",
                halign = "left",
                valign = "top",
                fontSize = 20,
            },
            gui.Dropdown {
                halign = "left",
                valign = "top",
                options = types,
                idChosen = follower.type,
                change = function(element)
                    if follower.type ~= element.idChosen then
                        follower.skills = {}
                        follower.type = element.idChosen
                        editorPanel:FireEventTree("refreshAll")
                    end
                end,
            }
        }
    }

    local avatarPanel = gui.Panel {
        halign = "left",
        valign = "top",
        flow = "vertical",
        height = "auto",
        width = "auto",
        children = {
            gui.IconEditor {
                classes = { "avatarPanel" },
                library = "Avatar",
                restrictImageType = "Avatar",
                allowPaste = true,
                value = follower.portrait or false,
                refreshAll = function(element)
                    if follower.type == "retainer" and follower.retainerType then
                        local node = assets:GetMonsterNode(follower.retainerType)
                        if node and node.monster then
                            follower.portrait = node.monster.info.offTokenPortrait
                            element.value = follower.portrait
                        end
                    else
                        element.value = follower.portrait or false
                    end
                end,
                change = function(element)
                    follower.portrait = element.value
                end
            },
        },
    }

    local ancestryPanel = gui.Panel {
        classes = {cond(follower.type == "retainer", "collapsed-anim")},
        flow = "horizontal",
        width = "auto",
        height = 30,
        margin = 3,
        halign = "left",
        valign = "top",
        refreshAll = function(element)
            element:SetClass("collapsed-anim", follower.type == "retainer")
        end,
        children = {
            gui.Label {
                classes = {"followerLabel"},
                width = "auto",
                height = 30,
                text = "Ancestry:",
                halign = "left",
                valign = "top",
                fontSize = 20,
            },
            gui.Dropdown {
                options = Race.GetDropdownList(),
                idChosen = follower.ancestry,
                textDefault = "Select an ancestry...",
                change = function(element)
                    follower.ancestry = element.idChosen
                end,
            }
        }
    }

    local characteristicPanel = gui.Panel {
        classes = {cond(follower.type ~= "artisan", "collapsed-anim")},
        flow = "horizontal",
        width = "auto",
        height = 30,
        margin = 3,
        halign = "left",
        valign = "top",
        refreshAll = function(element)
            element:SetClass("collapsed-anim", follower.type ~= "artisan")
        end,
        children = {
            gui.Label {
                classes = {"followerLabel"},
                width = "auto",
                height = 30,
                text = "Characteristic:",
                halign = "left",
                valign = "top",
                fontSize = 20,
            },
            gui.Dropdown {
                options = chars,
                idChosen = follower.characteristic,
                textDefault = "Select a characteristic...",
                change = function(element)
                    follower.characteristic = element.idChosen
                end,
            }
        }
    }

     local skillsPanel = gui.Panel {
        classes = {cond(follower.type == "retainer", "collapsed-anim")},
        flow = "vertical",
        width = "100%-100",
        height = "auto",
        margin = 3,
        halign = "left",
        valign = "top",
        refreshAll = function(element)
            element:SetClass("collapsed-anim", follower.type == "retainer")
        end,
        children = {
            gui.Multiselect {
                id = "skillSelector",
                options = follower.type == "sage" and sageSkills or artisanSkills,
                width = "100%",
                valign = "top",
                halign = "left",
                vmargin = 4,
                textDefault = "Select 4 skills...",
                sort = true,
                flow = "horizontal",
                chipPos = "right",
                dropdown = {
                    classes = {"followerMultiselect"},
                    width = 160,
                },
                chipPanel = {
                    width = "100%-160",
                    halign = "left",
                },
                chips = {
                    halign = "left",
                },
                create = function(element)
                    element:FireEvent("refreshAll")
                end,
                change = function(element)
                    follower.skills = element.value
                end,
                refreshAll = function(element)
                    local opts = follower.type == "sage" and sageSkills or artisanSkills
                    local selected = follower.skills or {}
                    element:FireEvent("refreshSet", opts, selected)
                    element.value = selected
                end,
            },
        }
    }

    local languagesPanel = gui.Panel {
        classes = {cond(follower.type == "retainer", "collapsed-anim")},
        flow = "vertical",
        width = "100%-100",
        height = "auto",
        margin = 3,
        halign = "left",
        valign = "top",
        refreshAll = function(element, info)
            element:SetClass("collapsed-anim", follower.type == "retainer")
        end,
        children = {
            gui.Multiselect {
                options = languages,
                width = "100%",
                valign = "top",
                halign = "left",
                vmargin = 4,
                textDefault = "Select 2 languages...",
                sort = true,
                flow = "horizontal",
                chipPos = "right",
                dropdown = {
                    classes = {"followerMultiselect"},
                    width = 160,
                },
                chipPanel = {
                    width = "100%-160",
                    halign = "left",
                },
                chips = {
                    halign = "left",
                },
                create = function(element)
                    element.value = follower.languages or {}
                end,
                change = function(element)
                    follower.languages = element.value
                end,
                refreshAll = function(element, info)
                    element.value = follower.languages or {}
                end,
            }
        }
    }

    local retainersPanel = gui.Panel {
        classes = {cond(follower.type ~= "retainer", "collapsed-anim")},
        flow = "vertical",
        width = "auto",
        height = "auto",
        margin = 3,
        halign = "left",
        valign = "top",
        refreshAll = function(element)
            element:SetClass("collapsed-anim", follower.type ~= "retainer")
        end,
        children = {
            gui.Label {
                classes = {"followerLabel"},
                width = "auto",
                height = 30,
                text = "Retainer:",
                halign = "left",
                valign = "top",
                fontSize = 20,
            },
            gui.Dropdown {
                options = retainerTypes,
                idChosen = follower.retainerType or "none",
                change = function(element)
                    follower.retainerType = element.idChosen
                    editorPanel:FireEventTree("refreshAll")
                end,
            }
        }
    }

    local headerPanel = gui.Panel {
        halign = "left",
        valign = "top",
        width = "100%",
        height = "auto",
        children = {
            namePanel,
            gui.CloseButton {
                halign = "right",
                valign = "top",
                press = function()
                    editorPanel:DestroySelf()
                end
            },
        }
    }

    editorPanel = gui.Panel {
        styles = DialogStyles,
        classes = {"editorPanel"},

        halign = "center",
        valign = "center",
        width = 680,
        height = 320,
        hmargin = 12,
        vmargin = 12,
        flow = "vertical",

        children = {
            gui.Panel {
                classes = {"framedPanel"},
                styles = { Styles.Default, Styles.Panel },
                halign = "center",
                width = "100%",
                height = "100%",
                hpad = 20,
                flow = "vertical",

                children = {

                    headerPanel,

                    gui.Panel {
                        valign = "top",
                        halign = "left",
                        flow = "horizontal",
                        width = "100%",
                        height = "auto",
                        margin = 4,
                        children = {
                            avatarPanel,
                            gui.Panel {
                                flow = "vertical",
                                width = "auto",
                                height = "auto",
                                halign = "left",
                                valign = "top",
                                hpad = 20,
                                children = {
                                    typePanel,
                                    ancestryPanel,
                                    characteristicPanel,
                                    retainersPanel,
                                    gui.Panel {
                                        flow = "vertical",
                                        width = "auto",
                                        height = "auto",
                                        valign = "top",
                                        halign = "left",
                                        children = {
                                            skillsPanel,
                                            languagesPanel
                                        }
                                    }
                                }
                            }
                        }
                    },

                    gui.Button {
                        classes = {"saveButton"},
                        text = "Save",
                        halign = "Center",
                        valign = "Bottom",
                        press = function(element)
                            if options.save and type(options.save) == "function" then
                                options.save()
                            end
                            element:FindParentWithClass("editorPanel"):DestroySelf()
                        end,
                    }
                }
            }
        }
    }

    GameHud.instance.documentsPanel:AddChild(editorPanel)
end
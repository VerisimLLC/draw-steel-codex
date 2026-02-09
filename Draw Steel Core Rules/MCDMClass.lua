local mod = dmhub.GetModLoading()

Class.hitpointsCalculation = ""

Class.baseCharacteristics = {
    agl = 2,
    rea = 2,
    arrays = {
        {2,-1,-1},
        {1,1,-1},
        {1,0,0},
    }
}


local g_classArrays2 = {
    {2,-1,-1},
    {1,1,-1},
    {1,0,0},
}

local g_classArrays1 = {
    {2,2,-1,-1},
    {2,1,1,-1},
    {2,1,0,0},
    {1,1,1,0},
}

Class.numKits = 1

Class.heroicResourceName = "Heroic Resource"

--calculate the base attributes of the class.
function Class:CalculateBaseAttributes(targetCreature)
    local attributeBuild = targetCreature:try_get("attributeBuild")
    for _,attrid in ipairs(creature.attributeIds) do
        local baseValue = self.baseCharacteristics[attrid]
        if baseValue == nil and attributeBuild[attrid] ~= nil and attributeBuild.array ~= nil and self.baseCharacteristics.arrays[attributeBuild.array] ~= nil then
            local array = self.baseCharacteristics.arrays[attributeBuild.array]
            baseValue = array[attributeBuild[attrid]]
        end
        
        targetCreature:GetBaseAttribute(attrid).baseValue = baseValue or 0
    end
end

local g_createChecklistDefaultName = "New Event"
local g_createChecklistDefaultDetails = "Describe Heroic resource gain"

function creature:GetHeroicResourceChecklist()
    return nil
end

function character:GetHeroicResourceChecklist()
    local classes = self:GetClassesAndSubClasses()
    local result = {}
    for _,entry in ipairs(classes) do
        if entry.class:has_key("heroicResourceChecklist") then
            result[#result+1] = entry.class.heroicResourceChecklist
        end
    end

    --Get modifier Checklist items
    for i, modifier in ipairs(self:GetActiveModifiers()) do
        modifier.mod:ModifyResourceChecklist(modifier, self, result)
    end

    if #result == 1 then
        return result[1]
    end

    local items = {}
    for _,list in ipairs(result) do
        for _,element in ipairs(list) do
            items[#items+1] = element
        end
    end

    return items
end

function Class.GatherHeroicResourceCheckListItems()
    local result = {}
    local tables = {"classes", "subclasses"}
    for _,t in ipairs(tables) do
        local classTable = dmhub.GetTable(t)
        for k,class in unhidden_pairs(classTable) do
            local checklist = class:get_or_add("heroicResourceChecklist", {})
            for _,item in ipairs(checklist) do
                result[#result+1] = {
                    id = item.guid,
                    text = string.format("%s: %s", class.name, item.name)
                }
            end
        end
    end

    for _, entry in pairs(CharacterModifier.GlobalHeroicResourceChecklist) do
        if entry.checklist ~= nil then
            for _,item in ipairs(entry.checklist) do
                result[#result+1] = {
                    id = item.guid,
                    text = string.format("%s: %s", entry.modifierName, item.name)
                }
            end
        end
    end

    table.sort(result, function(a,b)
        return a.text < b.text
    end)

    return result
end

function creature:GetHeroicResourceChecklistEntry(guid)
    local items = self:GetHeroicResourceChecklist()
    for i,item in ipairs(items or {}) do
        if item.guid == guid then
            return item
        end
    end
end

function creature:GetHeroicResourceChecklistRefreshId(guid)
    local updateid = nil
    local items = self:GetHeroicResourceChecklist()
    for i,item in ipairs(items or {}) do
        if item.guid == guid then
            if item.mode == "recurring" then
                updateid = dmhub.GenerateGuid()
            else
                updateid = self:GetResourceRefreshId(item.mode or "encounter")
            end
        end
    end

    return updateid
end

function Class:HeroicResourceEditor(UploadFn)
    local contentPanel

    --- @return {guid: string, name: string, details: string, quantity: number, mode: nil|'encounter'|'recurring'|'round', count: nil|number}[]
    local GetCollection = function()
        return self:get_or_add("heroicResourceChecklist", {})
    end

    local addButton = gui.AddButton{
        click = function()
            local checklist = GetCollection()
            checklist[#checklist+1] = {
                guid = dmhub.GenerateGuid(),
                name = g_createChecklistDefaultName,
                details = g_createChecklistDefaultDetails,
                quantity = 1,
            }
            UploadFn()
            contentPanel:FireEvent("create")
        end
    }

    contentPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        create = function(element)
            local children = {}

            local checklist = GetCollection()
            for i,entry in ipairs(checklist) do
                local panel = gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "vertical",

                    gui.Panel{
                        classes = {"formPanel"},
                        gui.Label{
                            classes = {"formLabel"},
                            text = "Name:",
                            minWidth = 140,
                        },
                        gui.Input{
                            classes = {"formInput"},
                            characterLimit = 60,
                            text = entry.name,
                            change = function(e)
                                g_createChecklistDefaultName = e.text
                                entry.name = e.text
                                UploadFn()
                            end,
                        },
                        gui.DeleteItemButton{
                            halign = "right",
                            width = 12,
                            height = 12,
                            click = function()
                                local checklist = GetCollection()
                                table.remove(checklist, i)
                                UploadFn()
                                contentPanel:FireEvent("create")
                            end,

                        }
                    },

                    gui.Panel{
                        classes = {"formPanel"},
                        gui.Label{
                            classes = {"formLabel"},
                            text = "Quantity:",
                            minWidth = 140,
                        },

                        gui.GoblinScriptInput{
                            fontSize = 18,
                            width = 240,
                            value = entry.quantity,
                            placeholderText = "Quantity Calculation...",
                            change = function(element)
                                entry.quantity = element.value
                                UploadFn()
                            end,

                            documentation = {
                                help = "This GoblinScript is used to determine the quantity of the resource granted when this goal is achieved.",
                                output = "number",

                                examples = {
                                    {
                                        script = "2",
                                        text = "The character gains two heroic resources when the goal is achieved.",
                                    },
                                    {
                                        script = "Victories",
                                        text = "The character gains a number of heroic resources equal to the number of victories they have achieved.",
                                    },
                                },
                                subject = creature.helpSymbols,
                                subjectDescription = "The character whose heroic resources we are calculating.",
                            }
                        },
                    },

                    gui.Panel{
                        classes = {"formPanel"},
                        gui.Label{
                            classes = {"formLabel"},
                            text = "Mode:",
                            minWidth = 140,
                        },
                        gui.Dropdown{
                            options = {
                                {text = "Once per Combat", id = "encounter"},
                                {text = "Once per Round", id = "round"},
                                {text = "Recurring", id = "recurring"},
                            },
                            idChosen = entry.mode or "encounter",
                            change = function(e)
                                entry.mode = e.idChosen
                                UploadFn()
                            end,
                        },
                    },



                    gui.Panel{
                        classes = {"formPanel"},
                        gui.Input{
                            classes = {"formInput"},
                            characterLimit = 500,
                            text = entry.details,
                            multiline = true,
                            width = 400,
                            minHeight = 30,
                            height = "auto",
                            change = function(e)
                                g_createChecklistDefaultDetails = e.text
                                entry.details = e.text
                                UploadFn()
                            end,
                        },
                    },



                }

                children[#children+1] = panel
            end

            children[#children+1] = addButton
            element.children = children
        end,

        addButton,
    }


    return gui.TreeNode{
        text = "Heroic Resource Checklist",
        contentPanel = contentPanel,
        width = 600,
    }
end

function Class:CustomEditor(UploadFn, children)

    print("CLASS:: CUSTOM")
    if not self.isSubclass then
    print("CLASS:: CUSTOM IS SUB")
        children[#children+1] = gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            gui.Label{
                fontSize = 22,
                text = "Heroic Resource:",
                minWidth = 240,
            },

            gui.Input{
                fontSize = 18,
                width = 180,
                height = 22,
                characterLimit = 32,
                text = self.heroicResourceName,
                change = function(element)
                    self.heroicResourceName = element.text
                    UploadFn()
                end,
            },
        }
    else
        children[#children+1] = gui.Panel{
            classes = {'formPanel'},
            gui.Label{
                text = 'Prerequisite:',
                valign = 'center',
                minWidth = 240,
            },
            gui.GoblinScriptInput{
                value = self:try_get("prerequisite", ""),
                change = function(element)
                    self.prerequisite = element.value
                    UploadFn()
                end,

                documentation = {
                    help = string.format("This GoblinScript is used to determine whether a creature meets the prerequisite requirements to select this subclass."),
                    output = "boolean",
                    subject = creature.helpSymbols,
                    subjectDescription = "The creature who may select this subclass.",
                    symbols = Deity.helpSymbols,
                },
            },
        }
    end

    children[#children+1] = self:HeroicResourceEditor(UploadFn)

    if self.isSubclass then
        return nil
    end

    for _,attrid in ipairs(creature.attributeIds) do
        children[#children+1] = gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            gui.Label{
                fontSize = 22,
                text = creature.attributesInfo[attrid].description .. ":",
                minWidth = 240,
            },

            gui.Input{
                fontSize = 18,
                width = 180,
                height = 22,
                text = self.baseCharacteristics[attrid] or "",
                change = function(element)
                    self.baseCharacteristics = DeepCopy(self.baseCharacteristics)
                    self.baseCharacteristics[attrid] = tonumber(element.text)

                    local numCharacteristics = 0;

                    for _,attrid in ipairs(creature.attributeIds) do
                        if(self.baseCharacteristics[attrid]~=nil) then
                            numCharacteristics = numCharacteristics + 1;
                        end
                    end

                    if(numCharacteristics == 1) then
                        self.baseCharacteristics.arrays = g_classArrays1;
                    else
                        self.baseCharacteristics.arrays = g_classArrays2;
                    end

                    element.text = self.baseCharacteristics[attrid] or ""
                    UploadFn()
                end,
            },
        }
    end

    children[#children+1] = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        vmargin = 8,
        gui.Label{
            fontSize = 22,
            text = "Base Stamina:",
            minWidth = 240,
        },

        gui.GoblinScriptInput{
            fontSize = 18,
            width = 240,
            value = self.hitpointsCalculation,
            placeholderText = "Base Stamina Calculation...",
            change = function(element)
                self.hitpointsCalculation = element.value
                UploadFn()
            end,

            documentation = {
                help = "This GoblinScript is used to determine the base stamina for characters of this class.",
                output = "number",

                examples = {
                    {
                        script = "28",
                        text = "Characters of this class will have a stamina of 28.",
                    },
                    {
                        script = "12 + (level-1)*8",
                        text = "Characters of this class will have 12 stamina at 1st level and 8 stamina for each level beyond first.",
                    },
                },
                subject = creature.helpSymbols,
                subjectDescription = "The character whose stamina we are calculating.",
            }
        },

    }

    children[#children+1] = gui.Check{
        text = "Has Two Kits",
        value = self.numKits > 1,
        change = function(element)
            if element.value then
                self.numKits = 2
            else
                self.numKits = 1
            end
            UploadFn()
        end,
    }
end

function Class:Render(args, options)
	args = args or {}

    local panelParams = {
        styles = {
            Styles.Default,
            {
                selectors = {"label"},
                color = "white",
            },
        },
        width = 500,
        height = "auto",
        flow = "vertical",

        gui.Label{
            uppercase = true,
            bold = true,
            fontSize = 28,
            text = self.name,
            width = "auto",
            height = "auto",
        }
    }

	for k,v in pairs(args or {}) do
		panelParams[k] = v
	end

    return gui.Panel(panelParams)
end
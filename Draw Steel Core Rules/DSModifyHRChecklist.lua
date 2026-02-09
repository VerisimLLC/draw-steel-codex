local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType('modifyresourcechecklist', "Modify Resource Checklist")

CharacterModifier.GlobalHeroicResourceChecklist = {}

function CharacterModifier:ModifyResourceChecklist(modContext, creature, result)
    local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    if typeInfo.modifyResourceChecklist ~= nil then
        self:InstallSymbolsFromContext(modContext)
        typeInfo.modifyResourceChecklist(self, creature, result)
    end
end

function CharacterModifier:GatherModifyResourceChecklistItems(modContext, creature, result)
    local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    if typeInfo.gatherModifierResourceChecklistItems ~= nil then
        self:InstallSymbolsFromContext(modContext)
        typeInfo.gatherModifierResourceChecklistItems(self, creature, result)
    end
end

CharacterModifier.TypeInfo.modifyresourcechecklist = {

    init = function(modifier)
        modifier.resourceChecklist = {}
    end,

    modifyResourceChecklist = function(modifier, creature, result)
        if creature ~= nil then
            result[#result+1] = modifier.resourceChecklist
        end
    end,

    gatherModifierResourceChecklistItems = function(modifier, creature, result)
        if creature ~= nil then
            for _,entry in ipairs(modifier.resourceChecklist or {}) do
                result[#result+1] = {
                    id = entry.guid,
                    text = string.format("%s: %s", modifier.name, entry.name)
                }
            end
        end
    end,


    createEditor = function(modifier, element)
        local Refresh

        local firstRefresh = true

        local checklist = modifier:get_or_add("resourceChecklist", {})

        local addButton = gui.AddButton{
            click = function(element)
                checklist[#checklist+1] = {
                    guid = dmhub.GenerateGuid(),
                    name = "New Event",
                    details = "Describe Heroic resource gain",
                    quantity = 1,
                }
                Refresh()
            end
        }

        Refresh = function()
            CharacterModifier.GlobalHeroicResourceChecklist[modifier.guid] = {modifierName = modifier.name, checklist = modifier.resourceChecklist}
            
            if firstRefresh then
                firstRefresh = false
            else
                element:FireEvent("refreshModifier")
            end

            local children = {}

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
                                entry.name = e.text
                                Refresh()
                            end,
                        },
                        gui.DeleteItemButton{
                            halign = "right",
                            width = 12,
                            height = 12,
                            click = function()
                                table.remove(checklist, i)
                                Refresh()
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
                                Refresh()
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
                                Refresh()
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
                                entry.details = e.text
                                Refresh()
                            end,
                        },
                    },
                }

                children[#children+1] = panel
            end

            children[#children+1] = addButton
            element.children = children
        end

        Refresh()
    end,
}
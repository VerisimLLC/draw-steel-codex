local mod = dmhub.GetModLoading()

--- @class TriggeredAbilityDisplay
--- @field guid string
--- @field name string
--- @field cost string
--- @field keywords table<string,boolean>
--- @field flavor string
--- @field type string
--- @field distance string
--- @field target string
--- @field trigger string
--- @field effect string
TriggeredAbilityDisplay = RegisterGameType("TriggeredAbilityDisplay")

function TriggeredAbilityDisplay:OnDeserialize()
    if self:try_get("guid") == nil then
        self.guid = dmhub.GenerateGuid()
    end

    if self:try_get("keywords") == nil then
        self.keywords = {}
    end
end

TriggeredAbilityDisplay.name = "Triggered Ability"
TriggeredAbilityDisplay.cost = ""
TriggeredAbilityDisplay.flavor = ""
TriggeredAbilityDisplay.type = "trigger"
TriggeredAbilityDisplay.distance = "Ranged 10"
TriggeredAbilityDisplay.target = "One creature"
TriggeredAbilityDisplay.trigger = ""
TriggeredAbilityDisplay.effect = ""

local g_triggeredAbilityTypes = {
    {
        id = "trigger",
        text = "Triggered Action",
    },
    {
        id = "free",
        text = "Free Triggered Action",
    },
    {
        id = "passive",
        text = "Passive",
    },
}

local function GetTriggerInfo(id)
    for i=1,#g_triggeredAbilityTypes do
        if g_triggeredAbilityTypes[i].id == id then
            return g_triggeredAbilityTypes[i]
        end
    end

    return g_triggeredAbilityTypes[1]
end

CharacterModifier.RegisterType("triggerdisplay", "Triggered Ability Display")

CharacterModifier.TypeInfo.triggerdisplay = {
    init = function(modifier)
        modifier.ability = TriggeredAbilityDisplay.new{
            guid = dmhub.GenerateGuid(),
            keywords = {},
        }
    end,

    triggeredActionDisplay = function(modifier, casterCreature, output)
        output[#output+1] = modifier.ability
    end, 

	createEditor = function(modifier, element)
        print("EDITOR:: Create...")
        local Refresh
        Refresh = function()
            local children = {}

            children[#children+1] = modifier.ability:Render()

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Name:",
                },
                gui.Input{
                    characterLimit = 32,
                    classes = {"formInput"},
                    text = modifier.ability.name,
                    change = function(element)
                        modifier.ability.name = element.text
                        Refresh()
                    end,
                },
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Cost:",
                },
                gui.Input{
                    characterLimit = 32,
                    classes = {"formInput"},
                    text = modifier.ability.cost,
                    change = function(element)
                        modifier.ability.cost = element.text
                        Refresh()
                    end,
                },
            }

            children[#children+1] = gui.KeywordSelector{
                keywords = modifier.ability.keywords,
                change = function()
                    Refresh()
                end,
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Action:",
                },
                gui.Dropdown{
                    options = {

                        {
                            id = "trigger",
                            text = "Triggered Action",
                        },
                        {
                            id = "free",
                            text = "Free Triggered Action",
                        },
                        {
                            id = "passive",
                            text = "Passive",
                        },
                    },
                    idChosen = modifier.ability.type,
                    change = function(element)
                        modifier.ability.type = element.idChosen
                        Refresh()
                    end,
                },
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Distance:",
                },
                gui.Input{
                    characterLimit = 32,
                    classes = {"formInput"},
                    text = modifier.ability.distance,
                    change = function(element)
                        modifier.ability.distance = element.text
                        Refresh()
                    end,
                },
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Target:",
                },
                gui.Input{
                    characterLimit = 32,
                    classes = {"formInput"},
                    text = modifier.ability.target,
                    change = function(element)
                        modifier.ability.target = element.text
                        Refresh()
                    end,
                },
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Flavor:",
                },
                gui.Input{
                    width = 320,
                    characterLimit = 120,
                    classes = {"formInput"},
                    text = modifier.ability.flavor,
                    multiline = true,
                    height = "auto",
                    minHeight = 14,
                    maxHeight = 100,
                    change = function(element)
                        modifier.ability.flavor = element.text
                        Refresh()
                    end,
                },
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Trigger:",
                },
                gui.Input{
                    characterLimit = 240,
                    classes = {"formInput"},
                    text = modifier.ability.trigger,
                    multiline = true,
                    height = "auto",
                    width = 320,
                    minHeight = 14,
                    maxHeight = 100,
                    change = function(element)
                        modifier.ability.trigger = element.text
                        Refresh()
                    end,
                },
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Effect:",
                },
                gui.Input{
                    characterLimit = 640,
                    classes = {"formInput"},
                    text = modifier.ability.effect,
                    multiline = true,
                    width = 320,
                    height = "auto",
                    minHeight = 14,
                    maxHeight = 100,
                    change = function(element)
                        modifier.ability.effect = element.text
                        Refresh()
                    end,
                },
            }

            element.children = children
        print("EDITOR:: SET...", #children)
        end

        Refresh()
        print("EDITOR:: CALL...")
    end,

    createDropdownPanel = function(modifier, feature)
        return gui.Panel{
            classes = {"dropdownContainer"},
            styles = {
                {
                    selectors = {"dropdownContainer"},
                    bgcolor = "clear",
                },
                {
                    selectors = {"dropdownContainer", "highlight"},
                    bgcolor = Styles.textColor,
                }
            },
            width = "auto",
            height = "auto",
            bgimage = true,
            hover = function(element)
                element:SetClassTree("highlight", true)
            end,
            dehover = function(element)
                element:SetClassTree("highlight", false)
            end,
            modifier.ability:Render{
                halign = "center",
                width = 580,
            },
        }
    end,


}

function TriggeredAbilityDisplay:Render(args)
    args = args or {}
    local token = args.token
    args.token = nil
    local caster = token and token.properties
    local ability = args.ability
    args.ability = nil
    local symbols = args.symbols or {}
    args.symbols = nil

    args.summary = nil
    args.noninteractive = nil

    --see if there is a reason this trigger cannot be used.
    local suppressPanel = nil
    if ability ~= nil and caster ~= nil then
        local suppressMessage = ability:AbilityFilterFailureMessage(caster)
        if suppressMessage ~= nil then
            suppressPanel = gui.Label{
                bgimage = true,
                color = Styles.textColor,
                bgcolor = Styles.forbiddenColor,
                fontSize = 14,
                width = "100%",
                hpad = 4,
                vpad = 4,
                text = suppressMessage,
            }
        end
    end

    local width = args.width or 400

    local resultPanel

    local panelOpts = {
        classes = {"formPanel"},
        width = width,
        height = "auto",
        flow = "vertical",
        styles = {
            {
                classes = {"label"},
                textAlignment = "Left",
                width = "auto",
                height = "auto",
                maxWidth = width,
                hpad = 2,
                fontSize = 14,
                color = Styles.textColor,
                halign = "left",
            },
            {
                classes = {"label", "highlight"},
                color = Styles.backgroundColor,
                inversion = 1,
            },
        },
        gui.Label{
            width = "100%",
            vpad = 2,
            fontSize = 16,
            bold = true,
            text = string.format("%s%s", self.name, cond(self.cost ~= "", string.format(" (%s)", self.cost), "")),
            bgimage = true,
            bgcolor = cond(self.type == "free", Styles.Triggers.freeColorAgainstText, Styles.Triggers.triggerColorAgainstText),
        },
        gui.Label{
            width = "100%",
            italics = true,
            text = self.flavor,
        },
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "none",
            gui.Label{
                halign = "left",
                text = string.format("<b>Keywords:</b> %s", cond(#table.keys(self.keywords) == 0, "-", string.join(table.sort_and_return(table.keys(self.keywords)), ", "))),
            },
            gui.Label{
                halign = "right",
                text = string.format("<b>Type:</b> %s", GetTriggerInfo(self.type).text),
            },
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "none",
            gui.Label{
                halign = "left",
                text = string.format("<b>Distance:</b> %s", StringInterpolateGoblinScript(self.distance, caster)),
            },
            gui.Label{
                halign = "right",
                text = string.format("<b>Target:</b> %s", StringInterpolateGoblinScript(self.target, caster)),
            },
        },

        gui.Label{
            markdown = true,
            text = string.format("<b>Trigger:</b> %s", StringInterpolateGoblinScript(self.trigger, caster)),
            vmargin = 2,
        },

        gui.Label{
            markdown = true,
            text = string.format("<b>Effect:</b> %s", StringInterpolateGoblinScript(self.effect, caster)),
            vmargin = 2,
        },

        suppressPanel,
    }

    for k,o in pairs(args) do
        panelOpts[k] = o
    end

    resultPanel = gui.Panel(panelOpts)

    return resultPanel
end

function CharacterModifier:AccumulateTriggeredActionDisplay(context, casterCreature, output)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    local triggeredActionDisplay = typeInfo.triggeredActionDisplay
    if triggeredActionDisplay ~= nil then
        triggeredActionDisplay(self, casterCreature, output)
    end
end

function creature:GetTriggeredActions()
    local result = {}

    local modifiers = self:GetActiveModifiers()
    for _,mod in ipairs(modifiers) do
        mod.mod:AccumulateTriggeredActionDisplay(mod, self, result)
    end

    return result
end

--- @param name string
--- @return nil|TriggeredAbilityDisplay
function creature:GetTriggeredActionInfo(name)
    name = string.lower(name)
    local actions = self:GetTriggeredActions()
    for _,action in ipairs(actions) do
        if string.lower(action.name) == name then
            return action
        end
    end
end

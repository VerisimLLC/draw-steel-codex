local mod = dmhub.GetModLoading()

--- @class RoutineDisplay
--- @field guid string
--- @field keywords {string: boolean}
--- @field name string
--- @field flavor string
--- @field type string
--- @field distance string
--- @field target string
--- @field effect string
RoutineDisplay = RegisterGameType("RoutineDisplay")

RoutineDisplay.name = "Triggered Ability"
RoutineDisplay.flavor = ""
RoutineDisplay.type = "trigger"
RoutineDisplay.distance = "Ranged 10"
RoutineDisplay.target = "One creature"
RoutineDisplay.effect = ""

CharacterModifier.RegisterType("routine", "Routine")

CharacterModifier.TypeInfo.routine = {
    init = function(modifier)
        modifier.ability = RoutineDisplay.new{
            guid = dmhub.GenerateGuid(),
            keywords = {},
        }
    end,

    routineDisplay = function(modifier, casterCreature, output)
        output[#output+1] = modifier.ability
    end, 

	createEditor = function(modifier, element)
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
                    text = "Type:",
                },
                gui.Input{
                    characterLimit = 32,
                    classes = {"formInput"},
                    text = modifier.ability.type,
                    change = function(element)
                        modifier.ability.type = element.text
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
        end

        Refresh()
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

function RoutineDisplay:Render(args)
    args = args or {}
    local token = args.token
    local caster = token and token.properties
    local width = args.width or 400

    local resultPanel

    resultPanel = gui.Panel{
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
            text = self.name,
            bgimage = true,
            bgcolor = "#ff00ff9c",
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
                text = string.format("<b>Type:</b> %s", self.type),
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
            text = string.format("<b>Effect:</b> %s", StringInterpolateGoblinScript(self.effect, caster)),
            vmargin = 2,
        },
    }

    return resultPanel
end

function CharacterModifier:AccumulateRoutineDisplay(context, casterCreature, output)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    local routineDisplay = typeInfo.routineDisplay
    if routineDisplay ~= nil then
        routineDisplay(self, casterCreature, output)
    end
end

function creature:GetRoutines()
    local result = {}

    local modifiers = self:GetActiveModifiers()
    for _,mod in ipairs(modifiers) do
        mod.mod:AccumulateRoutineDisplay(mod, self, result)
    end

    return result
end

creature.RegisterSymbol{
    symbol = "routinedistance",
    lookup = function(c)
        local routinesSelected = c:try_get("routinesSelected", {})
        if routinesSelected == nil then
            return 0
        end

        local routines = c:GetRoutines()
        if routines == nil or #routines == 0 then
            return 0
        end

        for _,routine in ipairs(routines) do
            if routinesSelected[routine.guid] then
                local match = regex.MatchGroups(routine.distance, "^(?<distance>\\d+).*")
                if match == nil then
                    return 0
                end
                return tonumber(match.distance) or 0
            end
        end

        return 0
    end,
    help = {
        name = "RoutineDistance",
        type = "number",
        desc = "If the creature has a routine, this is the distance of the routine.",
        seealso = {},
    },
}
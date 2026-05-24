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
TriggeredAbilityDisplay.implementationNotes = ""

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
        --Stash the casting creature on the display so Render() can find live
        --trigger partners (TriggeredAbility / powertabletrigger) and surface
        --Modify Abilities range mods. _tmp_ prefix keeps it transient.
        modifier.ability._tmp_caster = casterCreature
        output[#output+1] = modifier.ability
    end,

	createEditor = function(modifier, element)
        print("EDITOR:: Create...")
        local Refresh
        Refresh = function()
            local children = {}
            local isPassive = modifier.ability.type == "passive"

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

            if not isPassive then
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
            end

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Action:",
                },
                gui.Dropdown{
                    styles = ThemeEngine.GetStyles(),
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

            if not isPassive then
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
            end

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = cond(isPassive, "Description:", "Effect:"),
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

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Implementation Notes:",
                },
                gui.Input{
                    characterLimit = 640,
                    classes = {"formInput"},
                    text = modifier.ability.implementationNotes,
                    multiline = true,
                    width = 320,
                    height = "auto",
                    minHeight = 14,
                    maxHeight = 100,
                    change = function(element)
                        modifier.ability.implementationNotes = element.text
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

--Find a live trigger on the creature whose name matches this display.
--Returns nil if no match. Otherwise returns:
--  { kind = "triggered", ability = <TriggeredAbility> }
--  { kind = "powerroll", modifier = <powertabletrigger CharacterModifier> }
function TriggeredAbilityDisplay:FindLivePartner(caster)
    if caster == nil then return nil end
    local displayName = self:try_get("name", "")
    if displayName == "" then return nil end
    local nameLower = string.lower(displayName)

    --Triggered abilities (CharacterModifier with a triggeredAbility field).
    local entries = caster:GetTriggeredAbilities()
    for _, entry in ipairs(entries) do
        if entry.ability ~= nil and string.lower(entry.ability:try_get("name", "")) == nameLower then
            return { kind = "triggered", ability = entry.ability }
        end
    end

    --Power roll triggers (powertabletrigger CharacterModifiers).
    for _, modContext in ipairs(caster:GetActiveModifiers()) do
        local m = modContext.mod
        if m.behavior == "powertabletrigger" and string.lower(m:try_get("name", "")) == nameLower then
            return { kind = "powerroll", modifier = m }
        end
    end

    return nil
end

--Collect Modify Abilities modifications that affect range and would apply to
--the given live partner. Returns a list of { name, operation, value } entries
--in modifier order. Empty list if no partner or no matches.
function TriggeredAbilityDisplay:CollectAppliedRangeModifications(caster, partner)
    local result = {}
    if caster == nil or partner == nil then return result end

    local modifyAbilityTypeInfo = CharacterModifier.TypeInfo.modifyability

    for _, modContext in ipairs(caster:GetActiveModifiers()) do
        local m = modContext.mod
        if m.behavior == "modifyability" then
            local applies = false

            if partner.kind == "triggered" then
                if m:try_get("applyToTriggeredAbilities", true)
                    and modifyAbilityTypeInfo ~= nil
                    and modifyAbilityTypeInfo.willModifyAbility ~= nil
                    and modifyAbilityTypeInfo.willModifyAbility(m, caster, partner.ability) then
                    applies = true
                end
            elseif partner.kind == "powerroll" then
                if m:try_get("applyToPowerRollTriggers", true)
                    and m:try_get("filterAbility", "") == "" then
                    local triggerKeywords = partner.modifier.powerRollModifier:try_get("keywords", {})
                    local pass = true
                    for kw, _ in pairs(m:try_get("keywords", {})) do
                        if not triggerKeywords[kw] then
                            pass = false
                            break
                        end
                    end
                    if pass then applies = true end
                end
            end

            if applies then
                for _, attr in ipairs(m:try_get("attributes", {})) do
                    if attr.id == "range" then
                        result[#result+1] = {
                            name = m:try_get("name", "Modifier"),
                            operation = attr.operation or "Add",
                            value = attr.value or "0",
                        }
                    end
                end
            end
        end
    end

    return result
end

--Apply a list of {operation, value} range mods to free-form text by
--transforming every numeric token (e.g. "Ranged 10" -> "Ranged 12").
--Decimal values are preserved as floats; whole results render without ".0".
local function ApplyRangeModificationsToText(text, modifications, caster)
    if text == nil or text == "" or modifications == nil or #modifications == 0 then
        return text
    end
    for _, m in ipairs(modifications) do
        local raw = dmhub.EvalGoblinScript(m.value or "0",
            GenerateSymbols(caster), "Calculate Trigger Display Range Modifier")
        local numValue = tonumber(raw) or 0
        text = string.gsub(text, "(%d+%.?%d*)", function(numStr)
            local n = tonumber(numStr)
            if n == nil then return numStr end
            local newN
            if m.operation == "Set" then
                newN = numValue
            elseif m.operation == "Multiply" then
                newN = n * numValue
            else
                newN = n + numValue
            end
            if newN == math.floor(newN) then
                return tostring(math.floor(newN))
            end
            return tostring(newN)
        end)
    end
    return text
end

--Format a one-line "Modified by" footnote for a list of range modifications.
local function FormatRangeModificationsFootnote(modifications)
    local parts = {}
    for _, m in ipairs(modifications) do
        local sign
        if m.operation == "Multiply" then
            sign = "x"
        elseif m.operation == "Set" then
            sign = "="
        else
            sign = "+"
        end
        parts[#parts+1] = string.format("%s (Range %s%s)", m.name, sign, tostring(m.value))
    end
    return string.format("<i>Modified by: %s</i>", string.join(parts, ", "))
end

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

    --Fall back to the creature stashed by triggeredActionDisplay so callers
    --that don't thread a token through Render still get partner detection.
    if caster == nil then
        caster = self:try_get("_tmp_caster")
    end

    --Find a live trigger we're partnered with (by name) and collect any Modify
    --Abilities range mods that would apply to it. Active for non-passive only;
    --passives don't surface a distance.
    local rangeMods = {}
    if self.type ~= "passive" then
        local partner = self:FindLivePartner(caster)
        rangeMods = self:CollectAppliedRangeModifications(caster, partner)
    end

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

    local commonStyles = {
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
    }

    if self.type == "passive" then
        local panelOpts = {
            classes = {"formPanel"},
            width = width,
            height = "auto",
            flow = "vertical",
            styles = commonStyles,
            gui.Label{
                width = "100%",
                vpad = 2,
                fontSize = 16,
                bold = true,
                text = self.name,
                bgimage = true,
                bgcolor = Styles.Triggers.passiveColorAgainstText,
            },
            gui.Label{
                width = "100%",
                italics = true,
                text = GetTriggerInfo(self.type).text,
            },
            gui.Label{
                markdown = true,
                text = StringInterpolateGoblinScript(self.effect, caster),
                vmargin = 2,
            },
            (self.implementationNotes ~= "") and gui.Label{
                markdown = true,
                text = string.format("<b>Implementation Notes:</b> %s", StringInterpolateGoblinScript(self.implementationNotes, caster)),
                vmargin = 2,
            } or nil,
            suppressPanel,
        }

        for k,o in pairs(args) do
            panelOpts[k] = o
        end

        return gui.Panel(panelOpts)
    end

    local panelOpts = {
        classes = {"formPanel"},
        width = width,
        height = "auto",
        flow = "vertical",
        styles = commonStyles,
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
                text = string.format("<b>Keywords:</b> %s", cond(#table.keys(self.keywords) == 0, "-", string.join(table.sort_and_return(table.mapped_keys(self.keywords, ActivatedAbility.CanonicalKeyword)), ", "))),
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
                text = string.format("<b>Distance:</b> %s",
                    ApplyRangeModificationsToText(
                        StringInterpolateGoblinScript(self.distance, caster),
                        rangeMods, caster)),
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

        (self.implementationNotes ~= "") and gui.Label{
            markdown = true,
            text = string.format("<b>Implementation Notes:</b> %s", StringInterpolateGoblinScript(self.implementationNotes, caster)),
            vmargin = 2,
        } or nil,

        (#rangeMods > 0) and gui.Label{
            markdown = true,
            italics = true,
            fontSize = 12,
            width = "100%",
            vmargin = 2,
            text = FormatRangeModificationsFootnote(rangeMods),
        } or nil,

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

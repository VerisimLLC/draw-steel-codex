local mod = dmhub.GetModLoading()

--effectImplemented is deprecated. Use the 'implementation' field instead.
--kept as a default so old serialized data doesn't error on access.
ActivatedAbility.effectImplemented = true

local g_settingTargetObjects = setting {
    id = "targetobjects",
    default = false,
    storage = "preference",
}

local g_hoverableGradient = gui.Gradient {
    point_a = { x = 0, y = 0 },
    point_b = { x = 1, y = 1 },
    stops = {
        {
            position = 0,
            color = Styles.backgroundColor,
        },
        {
            position = 12,
            color = Styles.textColor,
        },
    },
}

local g_highlightGradient = gui.Gradient {
    point_a = { x = 0, y = 0 },
    point_b = { x = 1, y = 1 },
    stops = {
        {
            position = 0,
            color = Styles.backgroundColor,
        },
        {
            position = 4,
            color = Styles.textColor,
        },
    },
}

SpellRenderStyles = {
    gui.Style {
        selectors = "#spellInfo",
        width = "100%",
        height = 'auto',
        flow = 'vertical',
        halign = 'left',
        valign = 'center',
    },
    gui.Style {
        selectors = { "hoverable", "#spellInfo" },
        bgcolor = "white",
        gradient = g_hoverableGradient,
    },
    gui.Style {
        selectors = { "hoverable", "hovered", "#spellInfo" },
        gradient = g_highlightGradient,
        transitionTime = 0.2,
    },

    gui.Style {
        selectors = { "heading", "hovered" },
        brightness = 3,
    },

    gui.Style {
        classes = { "label" },
        fontSize = 14,
        color = 'white',
        width = '100%',
        textAlignment = "left",
        height = 'auto',
        halign = 'left',

        textAlignment = 'left',
    },

    gui.Style {
        classes = { "label", "#spellName" },
        color = 'white',
        bgimage = "panels/square.png",
        bgcolor = "clear",
        fontSize = 14,
        fontFace = "Newzald",
        width = '100%',
        height = 'auto',
        halign = 'left',
        valign = 'top',
        wrap = true,
        fontWeight = "black",
    },

    gui.Style {
        classes = { "subheading" },
        color = '#bb6666',
        fontSize = 24,
        bold = true,
    },

    gui.Style {
        classes = { "label", "#spellSummary" },

        italics = true,
        color = 'white',
        fontSize = 12,
        width = 'auto',
        height = 'auto',
        halign = 'left',
        valign = 'top',
    },

    gui.Style {
        classes = { "divider" },

        bgimage = 'panels/square.png',
        bgcolor = '#666666',
        halign = "left",
        width = '100%',
        height = 1,
        halign = 'center',
        valign = 'top',
        vmargin = 4,
    },
    gui.Style {
        classes = { "description" },
        color = 'white',
        width = '96%',
    },
    gui.Style {
        classes = { "label", "highlight" },
        color = 'black',
    },
    gui.Style {
        classes = { "abilitySection" },
        bgimage = true,
        bgcolor = "clear",
    },
    gui.Style {
        classes = { "abilitySection", "highlight" },
        bgcolor = Styles.Gold03,
        color = "black",
    },

    -- Implementation chip styles
    gui.Style {
        classes = { "implementationChip" },
        height = "auto",
        width = "auto",
        lmargin = 3,
        fontSize = 14,
        bgimage = "panels/square.png",
        --borderColor = "blue",
        bgcolor = "clear",
        bold = false,
        --border = 1,
        --cornerRadius = 2,
        color = "black",
        valign = "top",
    },
    gui.Style {
        classes = { "implementationChip", "wontimplement" },
        --bgcolor = Styles.ImplementationStatusColors[0],
        color = Styles.ImplementationStatusColors[0],
    },
    gui.Style {
        classes = { "implementationChip", "unimplemented" },
        --bgcolor = Styles.ImplementationStatusColors[1],
        color = Styles.ImplementationStatusColors[1],
    },
    gui.Style {
        classes = { "implementationChip", "bronze" },
        --bgcolor = Styles.ImplementationStatusColors[2],
        color = Styles.ImplementationStatusColors[2],
    },
    gui.Style {
        classes = { "implementationChip", "silver" },
        --bgcolor = Styles.ImplementationStatusColors[3],
        color = Styles.ImplementationStatusColors[3],
    },
    gui.Style {
        classes = { "implementationChip", "gold" },
        --bgcolor = Styles.ImplementationStatusColors[4],
        color = Styles.ImplementationStatusColors[4],
    },
    gui.Style {
        classes = { "implementationDiamond", "wontimplemented" },
        bgcolor = Styles.ImplementationStatusColors[0],

    },
    gui.Style {
        classes = { "implementationDiamond", "unimplemented" },
        bgcolor = Styles.ImplementationStatusColors[1],

    },
    gui.Style {
        classes = { "implementationDiamond", "bronze" },
        bgcolor = Styles.ImplementationStatusColors[2],

    },
    gui.Style {
        classes = { "implementationDiamond", "silver" },
        bgcolor = Styles.ImplementationStatusColors[3],

    },
    gui.Style {
        classes = { "implementationDiamond", "gold" },
        bgcolor = Styles.ImplementationStatusColors[4],

    },

}

local g_damageTypeColors = {
    sonic = "#ff0088",
    fire = "#ff8888",
    lightning = "#ff8800",
}

ActivatedAbility.KeywordRemappings = {
    Attack = "Strike",
}

-- Returns the canonical display name for a keyword, applying any alias remapping.
-- Use this whenever showing a keyword string to the user.
function ActivatedAbility.CanonicalKeyword(keyword)
    return ActivatedAbility.KeywordRemappings[keyword] or keyword
end

function ActivatedAbility.OnDeserialize(self)
    if not self:has_key("behaviors") then
        self.behaviors = {}
    end

    for k, v in pairs(ActivatedAbility.KeywordRemappings) do
        if self.keywords[k] then
            self.keywords[v] = true
            self.keywords[k] = nil
        end
    end
end

function ActivatedAbility:AddKeyword(keyword)
    keyword = ActivatedAbility.KeywordRemappings[keyword] or keyword
    self.keywords = DeepCopy(self.keywords)
    self.keywords[keyword] = true
end

function ActivatedAbility:HasKeyword(keyword)
    keyword = ActivatedAbility.KeywordRemappings[keyword] or keyword
    return self.keywords[keyword] == true
end

function ActivatedAbility:RemoveKeyword(keyword)
    self.keywords = DeepCopy(self.keywords)
    keyword = ActivatedAbility.KeywordRemappings[keyword] or keyword
    self.keywords[keyword] = nil
end

RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "Keywords",
    type = "set",
    desc = "The keywords this ability has.",
    examples = { "Ability.Keywords has 'Ranged'", "Ability.Keywords has 'Attack'" },
    calculate = function(c)
        local strings = {}
        for k, v in pairs(c.keywords) do
            strings[#strings + 1] = string.lower(k)
        end

        return StringSet.new {
            strings = strings,
        }
    end,
})

RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "doesdamage",
    type = "boolean",
    desc = "Whether this ability does rolled damage.",
    calculate = function(c)
        for _, behavior in ipairs(c.behaviors) do
            if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
                local tiers = behavior.tiers
                for _, entry in ipairs(tiers) do
                    local damageMatch = regex.MatchGroups(entry, " damage")
                    if damageMatch ~= nil then
                        return true
                    end
                end
            end
        end
    end,
})


RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "haspotency",
    type = "boolean",
    desc = "Whether this ability has potency.",
    calculate = function(c)
        for _, behavior in ipairs(c.behaviors) do
            if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
                local tiers = behavior.tiers
                for _, entry in ipairs(tiers) do
                    if string.find(entry, "<", 1, true) then
                        return true
                    end
                end
            end
        end

        return false
    end,
})

RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "hasforcedmovement",
    type = "boolean",
    desc = "Whether this ability has forced movement.",
    calculate = function(c)
        for _, behavior in ipairs(c.behaviors) do
            if behavior.typeName == "ActivatedAbilityForcedMovementBehavior" then
                return true
            else
                local tiers = behavior:try_get("tiers", {})
                for _, entry in ipairs(tiers) do
                    if regex.MatchGroups(entry, "(push|pull|slide)") ~= nil then
                        return true
                    end
                end
            end
        end

        return false
    end,
})

RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "damagetypes",
    type = "set",
    desc = "The damage types this ability does.",
    calculate = function(c)
        local strings = {}

        for _, behavior in ipairs(c.behaviors) do
            if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
                local tiers = behavior.tiers
                for _, entry in ipairs(tiers) do
                    local damageMatch = regex.MatchGroups(entry, "(?<damage>[0-9 maripd+-]+) +(?<type>[a-z]+)? ?damage")
                    if damageMatch ~= nil then
                        local damageType = damageMatch.type or "untyped"
                        if not table.contains(strings, damageType) then
                            strings[#strings + 1] = string.lower(damageType)
                        end
                    end
                end
            end
        end

        return StringSet.new {
            strings = strings,
        }
    end,


})

RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "action",
    type = "boolean",
    desc = "Is this ability an action?",
    calculate = function(c)
        return c:ActionResource() == "d19658a2-4d7b-4504-af9e-1a5410fb17fd" --id of action
    end,

})

RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "main action",
    type = "boolean",
    desc = "Returns true if this ability is a main action.",
    seealso = { "action" },
    calculate = function(c)
        return c:ActionResource() == "d19658a2-4d7b-4504-af9e-1a5410fb17fd" --id of action
    end,

})

RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "maneuver",
    type = "boolean",
    desc = "Returns true if this ability is a maneuver.",
    seealso = { "action" },
    calculate = function(c)
        return c:ActionResource() == "a513b9a6-f311-4b0f-88b8-4e9c7bf92d0b" --id of maneuver
    end,

})

RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "Allegiance",
    type = "string",
    desc = "Alligance of Targets for Ability. Possible values are 'ally', 'enemy', 'dead', and 'all'.",
    calculate = function(c)
        if not c.targetAllegiance then
            if c:try_get("targetFilter") ~= nil then
                if string.lower(c.targetFilter) == "not enemy" then
                    return "ally"
                elseif string.lower(c.targetFilter) == "enemy" then
                    return "enemy"
                end
            end
            return "all"
        else
            return c.targetAllegiance
        end
    end,
})

RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "Strain",
    type = "boolean",
    desc = "Returns true if this ability can cause strain.",
    calculate = function(c)
        return c:try_get("strain", {}).enabled
    end,

})

RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "Strain Damage",
    type = "number",
    desc = "Returns the amount of damage this ability causes to the caster when strained.",
    calculate = function(c)
        local behaviors = c:try_get("behaviors", {})
        for _, behavior in ipairs(behaviors) do
            if behavior.typeName == "ActivatedAbilityDamageBehavior" and behavior:try_get("strainSelection", "") == "strained" then
                return behavior:try_get("roll", 0)
            end
        end
        return 0
    end,

})

RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "Strain Damage Type",
    type = "string",
    desc = "Returns the type of damage this ability causes to the caster when strained.",
    calculate = function(c)
        local behaviors = c:try_get("behaviors", {})
        for _, behavior in ipairs(behaviors) do
            if behavior.typeName == "ActivatedAbilityDamageBehavior" and behavior:try_get("strainSelection", "") == "strained" then
                return behavior:try_get("damageType", "untyped")
            end
        end
        return "untyped"
    end,

})

RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "Has Rolled Damage",
    type = "boolean",
    desc = "Returns true if this ability has rolled damage.",
    examples = { "Ability.HasRolledDamage" },
    calculate = function(c)
        for _, behavior in ipairs(c.behaviors) do
            if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
                local tiers = behavior.tiers
                for _, entry in ipairs(tiers) do
                    if regex.MatchGroups(entry, " damage") ~= nil then
                        return true
                    end
                end
            end
        end

        return false
    end,
})

RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "Characteristics",
    type = "set",
    desc = "Returns the characteristics of this ability.",
    examples = { 'Ability.Characteristics has "Might"', 'Ability.Characteristics has "Highest"' },
    calculate = function(c)
        local result = {}
        for _, behavior in ipairs(c.behaviors) do
            if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
                local roll = behavior:try_get("roll", "")
                if roll ~= "" then
                    local rollLower = string.lower(roll)
                    for desc, id in pairs(creature.descriptionToAttribute) do
                        if string.find(rollLower, string.lower(desc)) then
                            result[#result+1] = desc
                        end
                    end
                    if string.find(rollLower, "highest characteristic") then
                        result[#result+1] = "Highest"
                    end
                end
            end
        end

        return StringSet.new{
            strings = result,
        }
    end,
})

function ActivatedAbility:HasAttack()
    return self:HasKeyword("Strike")
end

function ActivatedAbility:IsAction()
    local resourceTable = dmhub.GetTable(CharacterResource.tableName)
    local resourceInfo = resourceTable[self:ActionResource()]
    return resourceInfo ~= nil and resourceInfo.name == "Action"
end

function ActivatedAbility:IsManeuver()
    local resourceTable = dmhub.GetTable(CharacterResource.tableName)
    local resourceInfo = resourceTable[self:ActionResource()]
    return resourceInfo ~= nil and resourceInfo.name == "Maneuver"
end

--- @return boolean Whether this ability's tooltip render changes depending on the mode.
function ActivatedAbility:RenderVariesWithDifferentModes()
    for _, behavior in ipairs(self.behaviors) do
        if behavior.typeName == "ActivatedAbilityPowerRollBehavior" and #behavior:try_get("modesSelected", {}) > 0 then
            return true
        elseif self.resourceCost ~= nil and self.resourceCost ~= "" and #behavior:try_get("modesSelected", {}) > 0 then
            return true
        end
    end

    return false
end

function ActivatedAbility:AbilityTypeDescription()
    if self.categorization == "Signature Ability" or self.categorization == "Heroic Ability" then
        return self.categorization
    end

    local actionResource = self:ActionResource()
    local resourceTable = dmhub.GetTable(CharacterResource.tableName)
    local resourceInfo = resourceTable[actionResource or ""]
    if resourceInfo == nil then
        return "Ability"
    end

    return resourceInfo.name
end

function ActivatedAbility.TabBGImage()
    return "drawsteel/power_roll_tab.png"
end

function ActivatedAbility:Render(options, params)
    params = params or {}
    options = options or {}

    options.noninteractive = nil

    params.symbols = params.symbols or {}
    params.symbols.mode = params.symbols.mode or 1

    local paramMaxHeight = params.maxHeight
    params.maxHeight = nil

    local summary = options.summary
    options.summary = nil

    local selectable = options.selectable
    options.selectable = nil

    local creatureProperties = nil
    local token = nil
    if params.token ~= nil then
        creatureProperties = params.token.properties
        token = params.token
    end

    local attackBehavior = nil
    for _, behavior in ipairs(self.behaviors) do
        if behavior.typeName == "ActivatedAbilityAttackBehavior" then
            attackBehavior = behavior
            break
        end
    end

    local powerTableBehavior = nil
    for _, behavior in ipairs(self.behaviors) do
        if behavior:IsFiltered(self, params.token, params) then
            --the modes didn't match, so just pass on this one.
        elseif behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
            powerTableBehavior = behavior
            break
        elseif behavior.typeName == "ActivatedAbilityInvokeAbilityBehavior" and behavior.abilityType == "custom" then
            --if we invoke a power roll ability try to pull that out.
            for _, subbehavior in ipairs(behavior.customAbility.behaviors) do
                if subbehavior.typeName == "ActivatedAbilityPowerRollBehavior" then
                    powerTableBehavior = subbehavior
                end
            end
        end
    end

    local powerRollLabel = nil
    local powerRollTable = nil

    local rulesNotes = {}

    if powerTableBehavior ~= nil then
        local c = nil
        if params.token ~= nil then
            c = params.token.properties
        end

        local roll = powerTableBehavior:DescribeRoll(c, self)

        local triangleBlack = nil
        if not string.find(roll, "2d6") then
            triangleBlack = gui.Panel {
                floating = true,
                rotate = 90,
                width = 6,
                height = 6,
                valign = "center",
                halign = "center",
                bgimage = "panels/triangle.png",
                bgcolor = "black",
            }
        end

        powerRollLabel = gui.Label {
            text = string.format("<b>Roll <u>%s</u></b>:", roll),
            create = function(element)
                if powerTableBehavior:try_get("resistanceRoll", false) then
                    element.text = string.format("<b>Target makes a %s resistance roll:</b>",
                        creature.attributesInfo[powerTableBehavior:ResistanceAttr()].description)
                else
                    element.text = string.format("<b>Roll <u>%s</u></b>:", roll)
                end
            end,
            tmargin = 16,

            gui.Panel {
                floating = true,
                rotate = 90,
                width = 8,
                height = 8,
                halign = "left",
                valign = "center",
                x = -10,
                bgimage = "panels/triangle.png",
                bgcolor = "white",
                triangleBlack,
            }
        }

        local rows = {}

        for i, entry in ipairs(powerTableBehavior.tiers) do
            rows[#rows + 1] = gui.TableRow {
                width = "100%",
                height = "auto",
                gui.Label {
                    text = powerTableBehavior.tierNames[i],
                    width = 80,
                    valign = "top",
                },

                gui.Label {
                    text = ActivatedAbilityDrawSteelCommandBehavior.DisplayRuleTextForCreature(creatureProperties, entry, rulesNotes, self:try_get("implementation", 1) >= gui.ImplementationStatus.Bronze),
                    markdown = true,
                    bold = true,
                    hpad = 4,
                    height = "auto",
                    width = (tonumber(options.width) or 600) - 100,
                    valign = "top",
                }
            }
        end

        powerRollTable = gui.Table {
            width = "100%",
            height = "auto",
            flow = "vertical",
            children = rows,
        }
    end

    local damageLabel = nil

    --TODO: Remove this?
    if attackBehavior ~= nil then
        local c = nil
        if params.token ~= nil then
            c = params.token.properties
        end
        local roll = attackBehavior:DescribeRoll(c, self)
        if attackBehavior.damageType ~= "untyped" then
            roll = string.format("%s %s", roll, attackBehavior.damageType)
        end

        local damageColor = g_damageTypeColors[attackBehavior.damageType] or "#ffffff"

        local triangleBlack = nil
        if not string.find(roll, "2d6") then
            triangleBlack = gui.Panel {
                floating = true,
                rotate = 90,
                width = 6,
                height = 6,
                valign = "center",
                halign = "center",
                bgimage = "panels/triangle.png",
                bgcolor = "black",
            }
        end

        damageLabel = gui.Label {
            text = string.format("<b>Damage:</b> <i><color=%s><u>%s</u></color></i>", damageColor, roll),

            gui.Panel {
                floating = true,
                rotate = 90,
                width = 8,
                height = 8,
                halign = "left",
                valign = "center",
                x = -10,
                bgimage = "panels/triangle.png",
                bgcolor = "white",
                triangleBlack,
            }
        }
    end

    --if we have a specific token and there is an aura associated with this ability, add some information about the aura.
    local tokenDependentInfoPanel = nil
    if params.token ~= nil and params.token.properties ~= nil then
        local tokenDependentChildren = {}

        local cost = self:GetCost(params.token)
        if cost.outOfAmmo then
            tokenDependentChildren[#tokenDependentChildren + 1] = gui.Label {
                color = "#ffaaaa",
                text = "Out of Ammo",
            }
        end

        if cost.moveCost ~= nil then
            local labelColor = cond(cost.cannotMove, "#ffaaaa", "#aaaaaa")
            local text = string.format("Consumes %s %s of movement",
                MeasurementSystem.NativeToDisplayString(cost.moveCost), MeasurementSystem.Abbrev())
            if params.token.properties:CurrentMovementSpeed() <= 0 then
                text = "Cannot Move"
            end

            tokenDependentChildren[#tokenDependentChildren + 1] = gui.Label {
                color = labelColor,
                text = text,
            }
        end

        if self:try_get("auraid") ~= nil then
            local aura = params.token.properties:GetAura(self.auraid)
            if aura ~= nil then
                tokenDependentChildren[#tokenDependentChildren + 1] = gui.Label {
                    id = "auraInfo",
                    create = function(element)
                        local concentrationText = ""
                        if params.token.properties:HasConcentration() and params.token.properties.concentration:try_get("auraid") == self.auraid then
                            concentrationText = "\nConcentrating on this spell"
                        end

                        local roundsSince = aura.time:RoundsSince()
                        local castTimeText = "this round"
                        if roundsSince == 1 then
                            castTimeText = "last round"
                        elseif roundsSince > 1 then
                            castTimeText = string.format("%d rounds ago", roundsSince)
                        end
                        if aura:try_get("duration") ~= "none" then
                            local duration = aura.duration
                            if type(duration) == "string" then
                                if duration == "eoe" then
                                    expiresText = "End of Encounter"
                                elseif duration == "eot" then
                                    expiresText = "End of Turn"
                                end
                            else
                                local remainingRounds = aura.duration - roundsSince
                                local expiresText = "this round"
                                if remainingRounds == 1 then
                                    expiresText = "next round"
                                elseif remainingRounds > 1 then
                                    expiresText = string.format("in %d rounds", remainingRounds)
                                end

                                element.text = string.format("Effect cast %s, expires %s%s", castTimeText, expiresText,
                                    concentrationText)
                            end
                        else
                            element.text = string.format("Effect cast %s, lasts indefinitely", castTimeText,
                                concentrationText)
                        end
                    end,
                }
            end
        end

        for _, entry in ipairs(self:try_get("modificationLog", {})) do
            tokenDependentChildren[#tokenDependentChildren + 1] = gui.Label {
                text = entry,
                color = "#aaaaff",
            }
        end

        local seenRules = {}
        for _, entry in ipairs(rulesNotes) do
            if seenRules[entry] == nil then
                seenRules[entry] = true
                tokenDependentChildren[#tokenDependentChildren + 1] = gui.Label {
                    text = entry,
                    color = "#aaaaff",
                }
            end
        end

        self:RenderTokenDependent(params.token, tokenDependentChildren)

        if #tokenDependentChildren > 0 then
            tokenDependentInfoPanel = gui.Panel {
                embedRollDialog = function(element, dialog)
                    element:SetClass("collapsed", true)
                end,
                width = "100%",
                height = "auto",
                flow = "vertical",
                tmargin = 6,
                hmargin = 8,
                children = tokenDependentChildren,
            }
        end
    end

    local description = self.description
    if description ~= "" and self:try_get("implementation", 3) ~= 3 and ActivatedAbilityDrawSteelCommandBehavior.ValidateRule(description) ~= true then
        description = string.format("<alpha=#55>%s<alpha=#ff>", description)
    end

    if self:try_get("modifyDescriptions") ~= nil then
        for _, desc in ipairs(self.modifyDescriptions) do
            description = string.format("%s\n<color=#aaaaff>%s</color>", description, desc)
        end
    end

    local costText = ""

    local headingColor = "#843030"



    if params.token ~= nil and params.token.properties ~= nil then
        local knownRefreshTypes = { rest = true, encounter = true, day = true }
        --look for a cost with a description, this means an ability that has a specific limit per refresh type.
        local costInfo = self:GetCost(params.token)
        for i, entry in ipairs(costInfo.details) do
            if entry.description ~= nil and knownRefreshTypes[entry.refreshType] then
                --costText is disabled for now. We show recharge instead.
                --costText = string.format(" [%s/%s]", tostring(entry.maxCharges), entry.refreshType)
                headingColor = "#5e4a43"
            end
        end
    end

    local resourceTable = dmhub.GetTable(CharacterResource.tableName)

    if self:has_key("resourceCost") then
        local resourceInfo = resourceTable[self.resourceCost]
        if resourceInfo ~= nil then
            local name = resourceInfo.name
            if self.resourceCost == CharacterResource.heroicResourceId and creatureProperties ~= nil then
                name = creatureProperties:GetHeroicResourceName()
            end

            local symbols = table.shallow_copy(params.symbols)
            local resourceNumberValue = rawget(self, "resourceNumber") or "1"
            local resourceNumber = 0
            if tonumber(resourceNumberValue) ~= nil then
                resourceNumber = tonumber(resourceNumberValue)
            elseif creatureProperties ~= nil then
                resourceNumber = ExecuteGoblinScript(resourceNumberValue, creatureProperties:LookupSymbol(symbols), 0,
                    "Determine resource number for " .. self.name)
            end
            if resourceNumber == 0 then
                costText = ""
            else
                costText = string.format(" %d %s", resourceNumber, name)
            end
        end
    end



    local actionText = ""
    local resourceInfo = resourceTable[self:ActionResource()]
    if self:has_key("villainAction") then
        actionText = self.villainAction
    elseif resourceInfo == nil then
        actionText = "Free"
    else
        actionText = resourceInfo.name
    end

    if actionText == "Maneuver" then
        headingColor = "#303084"
    end


    local keywords = {}

    for keyword, _ in pairs(self.keywords) do
        keywords[#keywords + 1] = ActivatedAbility.CanonicalKeyword(keyword)
    end

    table.sort(keywords, function(a, b) return a < b end)

    local keywordText = "-"
    if #keywords > 0 then
        keywordText = table.concat(keywords, ", ")
    end


    local descriptionLabel = nil

    if trim(description) ~= "" then
        descriptionLabel = gui.Label {
            markdown = true,
            text = string.format("<b>Effect: </b> %s", description),
        }
    end

    local labels = {
        gui.Label {
            text = string.format("<i>%s</i>", self:try_get("flavor", "")),
            width = "100%-80",
        },
        gui.Label {
            text = string.format("<b>Keywords:</b> <i>%s</i>", keywordText),
        },

        gui.Label {
            text = string.format("<b>Distance:</b> <i>%s</i>", self:DescribeRange(creatureProperties)),
        },

        gui.Label {
            text = string.format("<b>Target:</b> <i>%s</i>", self:DescribeTarget(token)),
        },

        damageLabel,

        powerRollLabel,
        powerRollTable,

        descriptionLabel,
    }

    local rechargeText = ""
    if tonumber(self.recharge) ~= nil then
        rechargeText = string.format("%d/Encounter: ", round(self.recharge))
    elseif self.recharge then
        rechargeText = "Recharge: "
    end

    local meleeOrRangedVariantText = ""
    if self:try_get("isMeleeVariation") then
        meleeOrRangedVariantText = " (Melee)"
    elseif self:try_get("isRangedVariation") then
        meleeOrRangedVariantText = " (Ranged)"
    end

    --Keywords calculation

    local keywords = {}

    for keyword, _ in pairs(self.keywords) do
        keywords[#keywords + 1] = ActivatedAbility.CanonicalKeyword(keyword)
    end

    table.sort(keywords, function(a, b) return a < b end)

    local keywordText = "-"
    if #keywords > 0 then
        keywordText = table.concat(keywords, ", ")
    end

    --Action name calculation

    local actionText = ""
    local resourceInfo = resourceTable[self:ActionResource()]
    if self:has_key("villainAction") then
        actionText = self.villainAction
    elseif resourceInfo == nil then
        actionText = "Free"
    else
        actionText = resourceInfo.name
    end

    local preDescription = self:try_get("preDescription", "")
    local description = self.description

    local powerTableBehavior = nil
    for _, behavior in ipairs(self.behaviors) do
        if behavior:IsFiltered(self, params.token, params) then
            --the modes didn't match, so just pass on this one.
        elseif behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
            powerTableBehavior = behavior
            break
        elseif behavior.typeName == "ActivatedAbilityInvokeAbilityBehavior" and behavior.abilityType == "custom" then
            --if we invoke a power roll ability try to pull that out.
            for _, subbehavior in ipairs(behavior.customAbility.behaviors) do
                if subbehavior.typeName == "ActivatedAbilityPowerRollBehavior" then
                    powerTableBehavior = subbehavior
                end
            end
        end
    end

    local powerRollQueenPanel

    if powerTableBehavior ~= nil then
        powerRollQueenPanel = gui.Panel {

            bgimage = true,
            bgcolor = "blue",
            width = "100%",
            height = "auto",
            tmargin = 5,
            flow = "vertical",
            bgcolor = "clear",

            --tier 1 roll
            gui.Panel {

                bgimage = true,
                bgcolor = "clear",
                flow = "horizontal",
                width = "100%",
                height = "auto",


                gui.Label {

                    bgimage = true,
                    bgcolor = "clear",
                    width = "auto",
                    height = "auto",
                    maxHeight = 22,
                    text = "!",
                    fontFace = "DrawSteelGlyphs",
                    fontSize = 34,
                    halign = "left",
                    valign = "center",

                },

                gui.Label {

                    width = "80%",
                    height = "auto",
                    text = ActivatedAbilityDrawSteelCommandBehavior.DisplayRuleTextForCreature(creatureProperties, powerTableBehavior.tiers[1], {}, self:try_get("implementation", 1) >= gui.ImplementationStatus.Bronze),
                    fontSize = 16,
                    halign = "left",
                    valign = "center",
                    lmargin = 6,
                    textAlignment = "left",
                    markdown = true,

                },



            },

            --tier 2 roll
            gui.Panel {

                bgimage = true,
                bgcolor = "clear",
                flow = "horizontal",
                width = "100%",
                height = "auto",


                gui.Label {

                    bgimage = true,
                    bgcolor = "clear",
                    width = "auto",
                    height = "auto",
                    maxHeight = 22,
                    text = "@",
                    fontFace = "DrawSteelGlyphs",
                    fontSize = 34,
                    halign = "left",
                    valign = "center",

                },

                gui.Label {

                    width = "80%",
                    height = "auto",
                    text = ActivatedAbilityDrawSteelCommandBehavior.DisplayRuleTextForCreature(creatureProperties, powerTableBehavior.tiers[2], {}, self:try_get("implementation", 1) >= gui.ImplementationStatus.Bronze),
                    fontSize = 16,
                    halign = "left",
                    valign = "center",
                    lmargin = 6,
                    textAlignment = "left",
                    markdown = true,

                },
            },

            --tier 3 roll
            gui.Panel {

                bgimage = true,
                bgcolor = "clear",
                flow = "horizontal",
                width = "100%",
                height = "auto",


                gui.Label {

                    bgimage = true,
                    bgcolor = "clear",
                    width = "auto",
                    height = "auto",
                    maxHeight = 22,
                    text = "#",
                    fontFace = "DrawSteelGlyphs",
                    fontSize = 34,
                    halign = "left",
                    valign = "center",

                },

                gui.Label {

                    width = "80%",
                    height = "auto",
                    text = ActivatedAbilityDrawSteelCommandBehavior.DisplayRuleTextForCreature(creatureProperties, powerTableBehavior.tiers[3], {}, self:try_get("implementation", 1) >= gui.ImplementationStatus.Bronze),
                    fontSize = 16,
                    halign = "left",
                    valign = "center",
                    lmargin = 6,
                    textAlignment = "left",
                    markdown = true,

                },



            },


        }
    end


    local costString
    if costText == "" then
        costString = ""
    else
        costString = "(" .. string.trim(costText) .. ")"
    end

    preDescription = string.trim(preDescription)
    description = string.trim(description)

    local preDescriptionString
    if preDescription == "" then
        preDescriptionString = ""
    else
        preDescriptionString = "<b>Effect: </b>" .. preDescription .. "\n"
    end

    local descriptionString
    if description == "" then
        descriptionString = ""
    else
        descriptionString = "<b>Effect: </b>" .. description
    end

    if self:has_key("modifyDescriptions") then
        for _, desc in ipairs(self.modifyDescriptions) do
            descriptionString = string.format("%s\n<color=#aaaaff>%s</color>", descriptionString, desc)
        end
    end

    local suppressMessage = self:try_get("suppressExplanation")
    if suppressMessage == nil and creatureProperties ~= nil then
        suppressMessage = self:AbilityFilterFailureMessage(creatureProperties)
    end

    local suppressPanel = nil
    if suppressMessage ~= nil then
        suppressPanel = gui.Label {
            bgimage = true,
            bgcolor = "#C73131", --forbidden color.
            width = "100%",
            height = "auto",
            color = "white",
            fontSize = 14,
            hpad = 16,
            vpad = 4,
            text = suppressMessage,
        }
    end

    --king panel
    local args = {
        id = 'spellInfo',
        styles = SpellRenderStyles,
        hpad = 0,
        vpad = 0,


        --King panel for inside info
        gui.Panel {

            id = "headerPanel",
            flow = "vertical",
            valign = "top",
            width = "90%",
            height = "auto",
            bgimage = true,
            bgcolor = "clear",
            tmargin = 15,
            lmargin = 20,

            maxHeight = paramMaxHeight,
            vscroll = cond(paramMaxHeight ~= nil, true, false),

            --titel and ability and icon type king panel
            gui.Panel {

                width = "100%",
                height = "auto",
                valign = "top",
                bgcolor = "clear",
                bgimage = true,

                flow = "vertical",


                --name and icon and type
                gui.Panel {

                    width = "100%",
                    height = "auto",
                    valign = "top",
                    bmargin = 10,
                    bgcolor = "clear",
                    bgimage = true,

                    flow = "horizontal",


                    --name and type
                    gui.Panel {

                        width = "auto",
                        height = "auto",
                        valign = "top",
                        bgcolor = "clear",
                        bgimage = true,

                        flow = "vertical",

                        --name of the ability
                        gui.Label {

                            width = "auto",
                            id = "spellName",
                            classes = {"abilityName"},
                            fontSize = 24,
                            fontFace = "Newzald",
                            fontWeight = "Light",
                            color = "white",
                            text = string.format("<b>%s</b>%s <size=18>%s</size>", self.name, meleeOrRangedVariantText, costString),
                            height = "auto",
                            markdown = true,
                        },

                        --Type of ability
                        gui.Panel {

                            flow = "horizontal",
                            width = "auto",
                            height = "auto",

                            gui.Label {

                                text = string.format("<b>%s</b>", self:AbilityTypeDescription()),
                                color = "red",
                                textAlignment = "left",
                                width = "auto",
                                height = "auto",
                                halign = "left",
                                markdown = true,

                            },

                            --Implementation chip

                            gui.Panel {

                                width = "auto",
                                height = "auto",

                                flow = "horizontal",
                                lmargin = 10,
                                bgimage = true,
                                bgcolor = "clear",

                                create = function(element)
                                    element.interactable = true
                                end,

                                hover = function(element)
                                    local text = [[<b>Gold:</b> Fully automated.

<b>Silver:</b> Automated with some table adjudication necessary.

<b>Bronze:</b> Partially automated.

<b>Unimplemented:</b> Requires manual adjudication.

<b>Narrative:</b> Role play only, no automation.
]]
                                    if self:try_get("implementationDetails") ~= nil and self:try_get("implementationDetails") ~= "" then
                                        text = text .. "\n\n" .. "<b>Notes:</b> " .. self:try_get("implementationDetails")
                                    end

                                    element.tooltip = gui.TooltipFrame(gui.Label {
                                        text = text,
                                        width = 300,
                                        height = "auto",
                                        wrap = true,
                                        fontSize = 14,
                                    }, {})
                                end,

                                gui.Panel {

                                    classes = { "implementationDiamond" },
                                    rotate = 45,

                                    width = 10,
                                    height = 10,
                                    bgimage = true,
                                    valign = "center",

                                    create = function(element)
                                        local impl = self:try_get("implementation", 1)
                                        -- Set the appropriate class based on implementation status
                                        if impl == 0 then
                                            element:SetClass("wontimplement", true)
                                        elseif impl == 1 then
                                            element:SetClass("unimplemented", true)
                                        elseif impl == 2 then
                                            element:SetClass("bronze", true)
                                        elseif impl == 3 then
                                            element:SetClass("silver", true)
                                        elseif impl == 4 then
                                            element:SetClass("gold", true)
                                        else
                                            element:SetClass("unimplemented", true)
                                        end
                                    end,

                                },

                                gui.Label {
                                    classes = { "implementationChip" },
                                    text = gui.ImplementationStatusValues[self:try_get("implementation", 1)] or "Unimplemented",
                                    create = function(element)
                                        print("venla:", mod.images.diamond)
                                        local impl = self:try_get("implementation", 1)
                                        -- Set the appropriate class based on implementation status
                                        if impl == 0 then
                                            element:SetClass("wontimplement", true)
                                        elseif impl == 1 then
                                            element:SetClass("unimplemented", true)
                                        elseif impl == 2 then
                                            element:SetClass("bronze", true)
                                        elseif impl == 3 then
                                            element:SetClass("silver", true)
                                        elseif impl == 4 then
                                            element:SetClass("gold", true)
                                        else
                                            element:SetClass("unimplemented", true)
                                        end
                                    end
                                },

                            },


                        },



                    },
                },
            },



            gui.Label {

                text = string.format("<i>%s</i>", self:try_get("flavor", "")),
                textAlignment = "left",
                color = "#CBCCCA",
                width = "100%",
                height = "auto",
                bgimage = true,
                bgcolor = "clear",
                markdown = true,

            },

            --divider line between top and bottom info
            gui.Panel {

                tmargin = 8,
                bgimage = true,
                bgcolor = "#CBCCCA",
                opacity = 1,
                width = "100%",
                height = 1.5,
                halign = "left",
            },

            --king panel for keywords and action type
            gui.Panel {

                bgimage = true,
                bgcolor = "clear",
                width = "100%",
                height = 25,
                tmargin = 6,
                flow = "horizontal",

                --keywords
                gui.Label {

                    text = string.format("%s", keywordText),
                    fontSize = 20,
                    minFontSize = 8,
                    fontFace = "Newzald",
                    fontWeight = "Light",
                    width = "auto",
                    height = "auto",
                    maxWidth = 200,
                    textWrap = false,
                    halign = "left",
                    markdown = true,


                },

                --acttion type
                gui.Label {

                    text = string.format("%s", actionText),
                    fontSize = 20,
                    fontFace = "Newzald",
                    fontWeight = "Light",
                    width = "auto",
                    halign = "right",
                    markdown = true,


                },



            },

            --king panel for ranged and target
            gui.Panel {
                classes = { "abilitySection" },

                width = "100%",
                height = "auto",
                tmargin = 2,
                flow = "vertical",

                showAbilitySection = function(element, options)
                    if options.ability.name ~= self.name then
                        element:SetClassTree("highlight", false)
                        return
                    end

                    if options.section == "target" then
                        element:SetClassTree("highlight", true)
                    else
                        element:SetClassTree("highlight", false)
                    end
                end,

                --tab panel
                gui.Panel {
                    styles = {
                        {
                            selectors = { "tab" },
                            collapsed = 1,
                        },
                        {
                            selectors = { "tab", "parent:highlight" },
                            collapsed = 0,
                        }
                    },

                    classes = { "tab" },
                    x = -46,
                    floating = true,
                    valign = "top",
                    halign = "left",
                    height = 136 * 0.8,
                    width = 33 * 0.8,
                    bgimage = ActivatedAbility.TabBGImage(),
                    bgcolor = Styles.Gold03,

                    gui.Label {
                        color = "black",
                        width = "auto",
                        height = "auto",
                        fontSize = 22,
                        bold = true,
                        text = "Target",
                        y = -18,
                        rotate = 90,
                        halign = "center",
                        valign = "center",
                    },
                },


                gui.Panel {
                    width = "auto",
                    height = "auto",
                    flow = "horizontal",
                    gui.Label {

                        create = function(element)
                            if self:has_key("villainAction") then
                                element.text = "d"
                            elseif self.targetType == "all" then
                                element.text = "b"
                            elseif self.targetType == "self" then
                                element.text = "f"
                            elseif self.targetType == "map" then
                                element.text = "c"
                            elseif self.targetType == "cube" or self.targetType == "line" or self:HasKeyword("Area") then
                                element.text = "e"
                            elseif self:HasKeyword("Melee") then
                                if self:HasKeyword("Ranged") then
                                    element.text = "l"
                                end
                                element.text = "t"
                            elseif self:HasKeyword("Ranged") then
                                element.text = "g"
                            else
                                element.text = "*"
                            end
                        end,
                        fontFace = "DrawSteelGlyphs",
                        fontSize = 20,
                        width = "auto",
                        halign = "right",
                        valign = "center",
                        lmargin = 5,
                    },


                    gui.Label {

                        text = self:DescribeRange(creatureProperties),
                        fontSize = 18,
                        fontFace = "Newzald",
                        fontWeight = "Light",
                        width = "auto",
                        halign = "left",
                        lmargin = 6,
                        valign = "center",
                        markdown = true,

                    },
                },


                gui.Panel {
                    width = "auto",
                    height = "auto",
                    flow = "horizontal",
                    halign = "left",
                    gui.Label {

                        text = "x",
                        fontFace = "DrawSteelGlyphs",
                        fontSize = 20,
                        width = "auto",
                        halign = "right",
                        valign = "center",
                        lmargin = 5,

                    },

                    gui.Label {

                        text = string.format("<b></b> <i>%s</i>", self:DescribeTarget(token)),
                        fontSize = 18,
                        fontFace = "Newzald",
                        fontWeight = "Light",
                        width = "auto",
                        halign = "right",
                        lmargin = 4,
                        valign = "center",
                        markdown = true,
                        height = "auto",
                    },

                },
            },

            --ability improvement checkboxes panel
            gui.Panel {
                width = "100%",
                height = "auto",
                flow = "vertical",
                bmargin = 6,
                showAbilitySection = function(element, options)
                    if options.ability.name ~= self.name or options.section ~= "target" then
                        element.children = {}
                        return
                    end
                    local improvements = options.improvements
                    if improvements == nil or #improvements == 0 then
                        element.children = {}
                        return
                    end
                    local children = {}
                    for _, entry in ipairs(improvements) do
                        local capturedEntry = entry
                        local m_value = capturedEntry.checked
                        local pillPanel
                        pillPanel = gui.Panel{
                            styles = {
                                gui.Style{
                                    classes = {"improvementPill"},
                                    borderColor = Styles.Gold04,
                                    borderWidth = 2,
                                    cornerRadius = 5,
                                    width = "auto",
                                    height = "auto",
                                    pad = 4,
                                    flow = "horizontal",
                                    bgimage = true,
                                    bgcolor = Styles.RichBlack03,
                                    tmargin = 4,
                                },
                                gui.Style{
                                    classes = {"improvementPill", "~selected"},
                                    borderColor = "#777777",
                                },
                                gui.Style{
                                    classes = {"improvementLabel"},
                                    opacity = 0.95,
                                    color = "white",
                                    fontSize = 16,
                                    width = "auto",
                                    height = "auto",
                                    valign = "center",
                                },
                                gui.Style{
                                    classes = {"improvementLabel", "~selected"},
                                    color = "#777777",
                                },
                                gui.Style{
                                    classes = {"improvementLabel", "unaffordable", "selected"},
                                    color = "#ff6666",
                                },
                                gui.Style{
                                    selectors = {"improvementLabel", "parent:hover"},
                                    brightness = 1.5,
                                },
                                gui.Style{
                                    classes = {"improvementPill", "hover"},
                                    brightness = 1.5,
                                },
                            },
                            classes = {"improvementPill"},
                            press = function(el)
                                m_value = not m_value
                                capturedEntry.checked = m_value
                                el:SetClassTree("selected", m_value)
                                local controller = el:Get("abilityController")
                                if controller ~= nil then
                                    controller:FireEvent("applyImprovements")
                                end
                            end,
                            linger = (function()
                                local rulesText = capturedEntry.mod:try_get("rules", "")
                                if rulesText ~= "" then
                                    return gui.Tooltip{
                                        text = rulesText,
                                        maxWidth = 600,
                                    }
                                end
                            end)(),
                            gui.Label{
                                classes = {"improvementLabel"},
                                text = capturedEntry.mod:try_get("name", "Ability Improvement"),
                            },
                            (function()
                                local costType = capturedEntry.mod:try_get("resourceCostType", "none")
                                if costType == "none" then return nil end
                                local casterProps = options.caster.properties
                                local costAmt = ExecuteGoblinScript(capturedEntry.mod:try_get("resourceCostAmount", "1"), casterProps:LookupSymbol{}, 1)
                                costAmt = math.floor(costAmt + 0.5)
                                local available, resourceName
                                if costType == "epic" then
                                    available = casterProps:GetEpicResources()
                                    resourceName = casterProps:GetEpicResourceName()
                                else
                                    available = casterProps:GetHeroicOrMaliceResources()
                                    resourceName = casterProps:GetHeroicResourceName()
                                end
                                available = math.floor(available or 0)
                                return gui.Label{
                                    classes = {"improvementLabel", cond(available < costAmt, "unaffordable", nil)},
                                    lmargin = 4,
                                    text = string.format("(%d / %d %s)", costAmt, available, resourceName),
                                }
                            end)(),
                        }
                        pillPanel:SetClassTree("selected", m_value)
                        children[#children+1] = pillPanel
                    end
                    element.children = children
                end,
            },

            --attack creatures vs objects panel
            gui.Panel {
                width = "auto",
                height = "auto",
                showAbilitySection = function(element, options)
                    if self.objectTarget and self.targetAllegiance ~= "none" and options.ability.name == self.name and options.section == "target" then
                        element.children = {
                            gui.EnumeratedSliderControl {
                                options = {
                                    { id = false, text = "Creatures" },
                                    { id = true,  text = "Objects" },
                                    { id = "all", text = "Creatures or Objects" },
                                },
                                value = g_settingTargetObjects:Get(),
                                change = function(element)
                                    g_settingTargetObjects:Set(element.value)
                                end,
                                styles = {
                                    {
                                        selectors = { "enumSlider" },
                                        height = 18,
                                    },
                                    {
                                        selectors = { "enumSliderOption" },
                                        fontSize = 10,
                                    },
                                }
                            },
                        }
                    else
                        element.children = {}
                    end
                end,

            },

            --modes panel
            gui.Panel {
                width = "auto",
                height = "auto",
                showAbilitySection = function(element, options)
                    if self.objectTarget and self.targetAllegiance ~= "none" and options.ability.name == self.name and options.section == "target" and
                       self ~= nil and self.multipleModes and self:try_get("modeList") and options.caster ~= nil then
                        local modeOptions = {}
                        for i, mode in ipairs(self.modeList) do
                            local available = true
                            if mode.condition ~= nil and mode.condition ~= "" then
                                available = ExecuteGoblinScript(mode.condition, options.caster.properties:LookupSymbol(), 1, "Mode condition")
                                available = type(available) == "number" and available > 0
                            end

                            if available then
                                modeOptions[#modeOptions + 1] = {
                                    id = i,
                                    text = mode.text,
                                }
                            end
                        end


                        element.children = {
                            gui.EnumeratedSliderControl {
                                options = modeOptions,
                                value = 1,
                                height = "auto",
                                wrap = true,
                                optionWidth = "33.3333%",
                                tmargin = 4,
                                change = function(element)
                                end,
                                styles = {
                                    {
                                        selectors = { "enumSliderOption" },
                                        fontSize = 10,
                                        height = 18,
                                    },
                                }
                            },
                        }
                    else
                        element.children = {}
                    end
                end,

            },


            gui.Label {
                classes = { cond(preDescriptionString == "", "collapsed", nil) },
                text = string.format("%s", preDescriptionString),
                fontSize = 18,
                fontFace = "Newzald",
                fontWeight = "Light",
                width = "100%",
                height = "auto",
                halign = "left",
                tmargin = 10,
                markdown = true,
            },

            gui.Panel {
                width = "100%",
                height = "auto",
                vmargin = 2,
                embedRollDialog = function(element, dialog)
                    element.children = { dialog }
                end,
            },

            --main Power Roll name + rolls king panel
            gui.Panel {
                embedRollDialog = function(element, dialog)
                    element:SetClass("collapsed", true)
                end,

                classes = { "abilitySection", cond(self:GetPowerRollDisplay() == "", "collapsed", nil) },
                width = "100%",
                height = "auto",
                tmargin = 2,
                flow = "vertical",
                bmargin = 2,

                showAbilitySection = function(element, options)
                    if options.ability.name ~= self.name then
                        element:SetClassTree("highlight", false)
                        return
                    end

                    if options.section == "main" then
                        element:SetClassTree("highlight", true)
                    else
                        element:SetClassTree("highlight", false)
                    end
                end,

                gui.Label {

                    text = self:GetPowerRollDisplay(),
                    fontSize = 18,
                    fontFace = "Newzald",
                    fontWeight = "Light",
                    width = "auto",
                    halign = "left",
                    markdown = true,

                    create = function(element)
                        --Tests shouldn't display power roll information in the tooltip?
                        for _, behavior in ipairs(self.behaviors or {}) do
                            if behavior:try_get("resistanceRoll", false) or behavior:try_get("isTest", false) then
                                element:SetClass("collapsed", true)
                            end
                        end
                    end,

                },

                powerRollQueenPanel,
            },

            gui.Panel {
                classes = { "abilitySection" },
                width = "100%",
                height = "auto",

                showAbilitySection = function(element, options)
                    if options.ability.name ~= self.name then
                        element:SetClassTree("highlight", false)
                        return
                    end

                    if options.section == "effects" then
                        element:SetClassTree("highlight", true)
                    else
                        element:SetClassTree("highlight", false)
                    end
                end,

                --tab panel
                gui.Panel {
                    styles = {
                        {
                            selectors = { "tab" },
                            collapsed = 1,
                        },
                        {
                            selectors = { "tab", "parent:highlight" },
                            collapsed = 0,
                        }
                    },

                    classes = { "tab" },
                    x = -46,
                    floating = true,
                    valign = "top",
                    halign = "left",
                    height = 136 * 0.8,
                    width = 33 * 0.8,
                    bgimage = ActivatedAbility.TabBGImage(),
                    bgcolor = Styles.Gold03,

                    gui.Label {
                        color = "black",
                        width = "auto",
                        height = "auto",
                        fontSize = 22,
                        bold = true,
                        text = "Effect",
                        y = -18,
                        rotate = 90,
                        halign = "center",
                        valign = "center",
                    },
                },

                gui.DocumentDisplay {
                    text = descriptionString,
                    noninteractive = true,
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    bmargin = 4,
                },
            },

            tokenDependentInfoPanel,


            gui.Panel {

                collapsed = 1,
                flow = "horizontal",
                valign = "top",
                width = "100%",
                height = "auto",
                bgcolor = "blue",
                bgimage = true,

                gui.Panel {
                    flow = "vertical",
                    width = "100%-16",
                    height = "auto",
                    lmargin = 16,

                    children = labels,
                },





            },
        },

        --[[gui.Label{
            smallcaps = true,
            bold = true,
            fontSize = 12,
            width = "auto",
            height = "auto",
            valign = "top",
            halign = "right",
            text = actionText,
        },]]

        --border line right panel
        gui.Panel {

            floating = true,
            valign = "top",
            halign = "left",
            height = 1.2,
            width = 500,
            bgimage = true,
            bgcolor = 'white',
            gradient = gui.Gradient {
                point_a = { x = 0, y = 0 },
                point_b = { x = 1, y = 0 },
                stops = {
                    {
                        position = 0,
                        color = "white",
                    },

                    {
                        position = 1,
                        color = "clear",
                    }
                }
            }

        },

        --border line down panel
        gui.Panel {

            floating = true,
            valign = "top",
            halign = "left",
            height = 200,
            width = 1.2,
            bgimage = true,
            bgcolor = 'white',
            gradient = gui.Gradient {
                point_a = { x = 0, y = 1 },
                point_b = { x = 0, y = 0 },
                stops = {
                    {
                        position = 0,
                        color = "white",
                    },

                    {
                        position = 1,
                        color = "clear",
                    }
                }
            }

        },

        --tab panel
        gui.Panel {

            floating = true,
            valign = "top",
            halign = "left",
            lmargin = -26,
            tmargin = -1,
            height = 106 * 0.8,
            width = 33 * 0.8,
            bgimage = mod.images.tabbg,
            bgcolor = Styles.Gold03,
            embedRollDialog = function(element)
                element:SetClass("collapsed", true)
            end,
            showAbilitySection = function(element, options)
                element:SetClass("collapsed", true)
            end,
        },

        suppressPanel,
    }




    if selectable then
        args.bgimage = "panels/square.png"
        args.hover = function(element)
            element:SetClassTree("hovered", true)
        end
        args.dehover = function(element)
            element:SetClassTree("hovered", false)
        end
    end

    for k, op in pairs(options) do
        args[k] = op
    end

    local result = gui.Panel(args)
    if selectable then
        result:SetClassTree("hoverable", true)
        for _, child in ipairs(result.children) do
            --child:MakeNonInteractiveRecursive()
        end
    else
        --result:MakeNonInteractiveRecursive()
    end
    return result
end

function ActivatedAbility:DescribeRange(castingCreature)
    if self:try_get("rangeTextOverride", "") ~= "" then
        if castingCreature == nil then
            return self.rangeTextOverride
        end
        return StringInterpolateGoblinScript(self.rangeTextOverride, castingCreature)
    end

    if self.targetType == 'self' then
        return 'Self'
    end

    local range = self:GetRange(castingCreature)
    local radius = self:GetRadius(castingCreature)

    if self.targetType == "cube" then
        return string.format("%s cube within %s", MeasurementSystem.NativeToDisplayString(radius),
            MeasurementSystem.NativeToDisplayStringWithUnits(range))
    elseif self.targetType == "line" then
        local distance = self:GetLineDistance(castingCreature)
        return string.format("%s x %s line within %d square%s", MeasurementSystem.NativeToDisplayString(range),
            MeasurementSystem.NativeToDisplayString(radius), MeasurementSystem.NativeToDisplayString(distance),
            cond(distance ~= 1, "s", ""))
    elseif self.targetType == "all" then
        return string.format("%s burst", MeasurementSystem.NativeToDisplayString(range))
    end

    local result = MeasurementSystem.NativeToDisplayString(range)

    if self:HasKeyword("Melee") and self:HasKeyword("Ranged") then
        local melee = self:try_get("meleeRange", 1)
        result = string.format("Melee %d or ranged %s", tonumber(melee) or 1, result)
    elseif self:HasKeyword("Ranged") then
        result = string.format("Ranged %s", result)
    elseif self:HasKeyword("Melee") then
        result = string.format("Melee %s", result)
    end

    return result
end

function ActivatedAbility:DescribeTarget(casterToken)
    if self:try_get("targetTextOverride", "") ~= "" then
        if casterToken == nil then
            return self.targetTextOverride
        end
        return StringInterpolateGoblinScript(self.targetTextOverride, casterToken.properties)
    end

    local result
    if self:IsTargetTypeAOE() then
        if self.targetAllegiance == "enemy" or string.lower(self:try_get("targetFilter", "")) == "enemy" then
            result = "Each enemy"
        elseif self.targetAllegiance == "ally" or string.lower(self:try_get("targetFilter", "")) == "not enemy" then
            if self:try_get("selfTarget") then
                result = "Self and each ally"
            else
                result = "Each ally"
            end
        elseif self.objectTarget then
            result = "Each creature or object"
        else
            result = "Each creature"
        end
    elseif self.targetType == "target" then
        local count = self:GetNumTargets(casterToken, {})
        if count == nil and type(self.numTargets) ~= "table" then
            local m = regex.MatchGroups(self.numTargets, "^\\s*(?<targets>[0-9]+)")
            if m ~= nil then
                count = tonumber(m.targets)
            end
        end
        count = count or 1
        if count <= 1 then
            result = "1 creature"
        else
            result = string.format("%d creatures", round(count))
        end

        if self.objectTarget then
            if self.targetAllegiance == "none" then
                result = string.format("%s", cond(count <= 1, "object", "objects"))
            else
                result = string.format("%s or %s", result, cond(count <= 1, "object", "objects"))
            end
        end
    elseif self.targetType == "self" then
        result = "None/self"
    elseif self.targetType == "emptyspace" then
        local count = tonumber(self.numTargets) or 1
        if count <= 1 then
            return "1 unoccupied space"
        else
            return string.format("%d unoccupied spaces", count)
        end
    else
        result = "1 square"
    end

    if self:has_key("targetAdditionalCriteria") then
        result = string.format("%s <color=#aaaaaa>%s</color>", result, self.targetAdditionalCriteria)
    end

    return result
end

function ActivatedAbility:IsForcedMovement()
    if self:try_get("invoker") == nil then
        --forced movement is always invoked by another creature.
        return false
    end

    if #self.behaviors == 0 or self.behaviors[1].typeName ~= "ActivatedAbilityRelocateCreatureBehavior" then
        return false
    end

    return true
end

function ActivatedAbility:CanTargetAdditionalTimes(casterToken, symbols, targets, targetToken)
    if self.repeatTargets then
        return true
    end

    if casterToken.properties.minion and self.categorization == "Signature Ability" and casterToken.properties:has_key("_tmp_minionSquad") then
        --signature abilities can 'stack' targeting up to three times.
        local currentTimes = 0
        for _, target in ipairs(targets) do
            if target == targetToken.id then
                currentTimes = currentTimes + 1
            end
        end

        return currentTimes < 3
    end

    return false
end

local function GetTargetsWithTokens(targets)
    local result = {}
    for _, target in ipairs(targets) do
        if target.token ~= nil then
            result[#result + 1] = target
        end
    end

    return result
end

-- Build a minion-to-target adjacency table. adjacency[minionIdx] is a list of
-- target indices that minion can reach (range overlap + line of effect).
local function BuildSquadAdjacency(squadTokens, squadTargetsPerToken, targets, targetLocsOccupying)
    local adjacency = {}
    for i, tok in ipairs(squadTokens) do
        adjacency[i] = {}
        for j, target in ipairs(targets) do
            local canReach = false
            for key, _ in pairs(targetLocsOccupying[j]) do
                if squadTargetsPerToken[i][key] then
                    canReach = true
                    break
                end
            end
            if canReach and RuleUtils.HasLineOfEffect(tok, target.token) then
                adjacency[i][#adjacency[i] + 1] = j
            end
        end
    end
    return adjacency
end

-- Augmenting-path bipartite matching. Finds a maximum matching of minions to
-- targets in O(n^2 * m) time, replacing the previous O(n!) permutation search.
-- Minions are processed in order so earlier indices (the caster) get priority.
-- committedTargets is an optional table of targetIdx -> minionIdx for
-- assignments that should be preserved. The algorithm seeds the matching with
-- these and only runs augmenting paths for unmatched targets, so committed
-- assignments are only displaced as a last resort.
-- Returns matchOfTarget[targetIdx] = minionIdx for each matched target.
local function BipartiteMatch(adjacency, nMinions, nTargets, committedTargets)
    local matchOfTarget = {} -- matchOfTarget[targetIdx] = minionIdx or nil
    local matchOfMinion = {} -- reverse map: minionIdx -> targetIdx or nil
    local committedMinions = {} -- set of minion indices that must not be displaced

    -- Seed with committed assignments.
    if committedTargets ~= nil then
        for targetIdx, minionIdx in pairs(committedTargets) do
            matchOfTarget[targetIdx] = minionIdx
            matchOfMinion[minionIdx] = targetIdx
            committedMinions[minionIdx] = true
        end
    end

    local function augment(minionIdx, visited)
        for _, targetIdx in ipairs(adjacency[minionIdx]) do
            if not visited[targetIdx] then
                visited[targetIdx] = true
                local holder = matchOfTarget[targetIdx]
                -- Never displace a committed minion.
                if holder == nil or (not committedMinions[holder] and augment(holder, visited)) then
                    if holder ~= nil then
                        matchOfMinion[holder] = nil
                    end
                    matchOfTarget[targetIdx] = minionIdx
                    matchOfMinion[minionIdx] = targetIdx
                    return true
                end
            end
        end
        return false
    end

    -- Only run augmenting paths for minions not already committed.
    for minionIdx = 1, nMinions do
        if matchOfMinion[minionIdx] == nil then
            augment(minionIdx, {})
        end
    end

    return matchOfTarget
end

-- Previous targeting result, used to stabilize assignments when new targets
-- are added so that existing minion-to-target pairings are preserved.
local g_prevTargetingRays = nil

---@param casterToken CharacterToken The token that is casting the ability.
---@param range number The range of the ability.
---@param symbols table<string, any> The symbols for the ability.
---@param targets table<{target: CharacterToken}>[] The targets of the ability.
---@return table<{a: CharacterToken, b: CharacterToken}>[]|nil The possible targeting combinations of minions to targets.
function ActivatedAbility:GetTargetingRays(casterToken, range, symbols, targets)
    if casterToken.properties.minion and self.categorization == "Signature Ability" and casterToken.properties:has_key("_tmp_minionSquad") then
        local locations = {}
        local squad = casterToken.properties._tmp_minionSquad
        local squadTokens = table.shallow_copy(squad.tokens)

        --put the caster token at the front so they'll get priority.
        for i, tok in ipairs(squadTokens) do
            if tok.id == casterToken.id then
                table.remove(squadTokens, i)
                table.insert(squadTokens, 1, tok)
                break
            end
        end

        targets = GetTargetsWithTokens(targets)

        local targetLocsOccupying = {}
        for _, target in ipairs(targets) do
            local locs = {}
            for _, loc in ipairs(target.token.locsOccupying) do
                locs[loc.xyfloorOnly.str] = true
            end

            targetLocsOccupying[#targetLocsOccupying + 1] = locs
        end

        local possibleTargetsForEachToken = {}
        for _, tok in ipairs(squadTokens) do
            if tok ~= nil and tok.valid then
                local shape = dmhub.CalculateShape {
                    shape = "radiusfromcreature",
                    token = tok,
                    radius = range,
                }

                local locs = {}
                for _, loc in ipairs(shape.locations) do
                    locs[loc.xyfloorOnly.str] = true
                end

                possibleTargetsForEachToken[#possibleTargetsForEachToken + 1] = locs
            else
                possibleTargetsForEachToken[#possibleTargetsForEachToken + 1] = {}
            end
        end

        local adjacency = BuildSquadAdjacency(squadTokens, possibleTargetsForEachToken, targets, targetLocsOccupying)

        -- Build committed assignments from the previous result. Map previous
        -- minion->target pairings onto the current squad/target indices so the
        -- matching preserves them and only assigns uncommitted minions to new targets.
        local committedTargets = nil
        if g_prevTargetingRays ~= nil then
            -- Build lookup: minionId -> squadIndex
            local minionIdToIdx = {}
            for i, tok in ipairs(squadTokens) do
                minionIdToIdx[tok.id] = i
            end

            -- Build lookup: targetCharid -> targetIndex
            local targetIdToIdx = {}
            for j, target in ipairs(targets) do
                -- Only record the first index for each target so we don't
                -- double-commit when multiple minions attack the same creature.
                if targetIdToIdx[target.token.charid] == nil then
                    targetIdToIdx[target.token.charid] = j
                end
            end

            committedTargets = {}
            for _, prev in ipairs(g_prevTargetingRays) do
                local mIdx = minionIdToIdx[prev.a.id]
                local tIdx = targetIdToIdx[prev.b.charid]
                if mIdx ~= nil and tIdx ~= nil then
                    -- Only commit if the minion can still reach this target.
                    local stillValid = false
                    for _, adjTarget in ipairs(adjacency[mIdx]) do
                        if adjTarget == tIdx then
                            stillValid = true
                            break
                        end
                    end

                    if stillValid then
                        committedTargets[tIdx] = mIdx
                        -- Remove from lookup so the next minion attacking the same
                        -- target gets a fresh slot rather than double-committing.
                        targetIdToIdx[prev.b.charid] = nil
                        minionIdToIdx[prev.a.id] = nil
                    end
                end
            end
        end

        -- Try with locked commitments first to keep assignments stable.
        local matchOfTarget = BipartiteMatch(adjacency, #squadTokens, #targets, committedTargets)

        -- Check that every target got a minion assigned.
        local allMatched = true
        for j = 1, #targets do
            if matchOfTarget[j] == nil then
                allMatched = false
                break
            end
        end

        -- If locked commitments prevented a full match, fall back to an
        -- unconstrained match that can reassign anyone.
        if not allMatched then
            matchOfTarget = BipartiteMatch(adjacency, #squadTokens, #targets)
            allMatched = true
            for j = 1, #targets do
                if matchOfTarget[j] == nil then
                    allMatched = false
                    break
                end
            end
        end

        if allMatched then
            local result = {}
            for j = 1, #targets do
                result[#result + 1] = { a = squadTokens[matchOfTarget[j]], b = targets[j].token }
            end
            g_prevTargetingRays = result
            return result
        end

        g_prevTargetingRays = nil
    end

    return nil
end

function ActivatedAbility:PrepareTargets(casterToken, symbols, targets)
    if casterToken.properties.minion and self.categorization == "Signature Ability" and casterToken.properties:has_key("_tmp_minionSquad") then
        --minion squad signature abilities will combine multiple instances
        --if the same target into one target with a multiple 'addedStacks' count.
        local result = {}

        for _, target in ipairs(targets) do
            local found = false
            for _, existing in ipairs(result) do
                if target.token ~= nil and existing.token ~= nil and target.token.id == existing.token.id then
                    existing.addedStacks = (existing.addedStacks or 0) + 1
                    found = true
                    break
                end
            end

            if not found then
                result[#result + 1] = target
            end
        end

        return result
    end

    return targets
end

local g_customTargetShapeFunction = ActivatedAbility.CustomTargetShape

function ActivatedAbility:CustomTargetShape(casterToken, range, symbols, targets)
    if (not mod.unloaded) and casterToken.properties.minion and self.categorization == "Signature Ability" and casterToken.properties:has_key("_tmp_minionSquad") then
        local locations = {}
        local squad = casterToken.properties._tmp_minionSquad
        local squadTokens = table.shallow_copy(squad.tokens)

        targets = GetTargetsWithTokens(targets)

        local targetLocsOccupying = {}
        for _, target in ipairs(targets) do
            local locs = {}
            for _, loc in ipairs(target.token.locsOccupying) do
                locs[loc.xyfloorOnly.str] = true
            end

            targetLocsOccupying[#targetLocsOccupying + 1] = locs
        end

        local possibleTargetsForEachToken = {}
        for _, tok in ipairs(squadTokens) do
            if tok ~= nil and tok.valid then
                local shape = dmhub.CalculateShape {
                    shape = "radiusfromcreature",
                    token = tok,
                    radius = range,
                }

                local locs = {}
                for _, loc in ipairs(shape.locations) do
                    locs[loc.xyfloorOnly.str] = true
                end

                possibleTargetsForEachToken[#possibleTargetsForEachToken + 1] = locs
            else
                possibleTargetsForEachToken[#possibleTargetsForEachToken + 1] = {}
            end
        end

        -- A squad member is "usable" if there exists SOME valid complete
        -- assignment of the current targets that leaves that member free.
        -- Equivalently: member i is usable if removing it from the squad
        -- still allows a complete matching of all targets.
        -- When no targets are selected yet, all members are usable.
        local usableSquadMembers = {}
        if #targets == 0 then
            usableSquadMembers = squadTokens
        else
            local adjacency = BuildSquadAdjacency(squadTokens, possibleTargetsForEachToken, targets, targetLocsOccupying)
            for i, tok in ipairs(squadTokens) do
                -- Build adjacency with member i removed (shift indices).
                local reducedAdj = {}
                local ri = 0
                for k = 1, #squadTokens do
                    if k ~= i then
                        ri = ri + 1
                        reducedAdj[ri] = adjacency[k]
                    end
                end

                local matchOfTarget = BipartiteMatch(reducedAdj, #squadTokens - 1, #targets)

                -- If all targets are still matched without member i, it's usable.
                local allMatched = true
                for j = 1, #targets do
                    if matchOfTarget[j] == nil then
                        allMatched = false
                        break
                    end
                end

                if allMatched then
                    usableSquadMembers[#usableSquadMembers + 1] = tok
                end
            end
        end

        for _, tok in ipairs(usableSquadMembers) do
            if tok ~= nil and tok.valid then
                local shape = dmhub.CalculateShape {
                    shape = "radiusfromcreature",
                    token = tok,
                    radius = range,
                }

                local locs = shape.locations
                for _, loc in ipairs(locs) do
                    locations[#locations + 1] = loc
                end
            end
        end

        return locations
    end

    return g_customTargetShapeFunction(self, casterToken, range, symbols)
end

local g_numTargetsFunction = ActivatedAbility.GetNumTargets

function ActivatedAbility:GetNumTargets(casterToken, symbols)
    local result = g_numTargetsFunction(self, casterToken, symbols)

    if (not mod.unloaded) and casterToken ~= nil and casterToken.properties.minion and self.categorization == "Signature Ability" and result == 1 and casterToken.properties:has_key("_tmp_minionSquad") then
        --minion signature abilities can target one target for each active (non-skipped) member.
        return casterToken.properties._tmp_minionSquad.activeMinions
            or casterToken.properties._tmp_minionSquad.liveMinions
    end

    return result
end

local g_moreTargetsFunction = ActivatedAbility.CanSelectMoreTargets

function ActivatedAbility:CanSelectMoreTargets(casterToken, targets, symbols)
    if not mod.unloaded then
        if casterToken.properties.minion and self.categorization == "Signature Ability" then

        end
    end

    return g_moreTargetsFunction(self, casterToken, targets, symbols)
end

function ActivatedAbility:PromptText(casterToken, targets, symbols, synthesizedSpells)
    if self:try_get("promptOverride") ~= nil then
        return self.promptOverride
    end

    if synthesizedSpells ~= nil then
        if #synthesizedSpells == 0 then
            return "No valid abilities"
        else
            if self.meleeAndRanged then
                return "Choose Melee or Ranged"
            end
            return "Choose an ability"
        end
    end

    if self:try_get("attackOverride") ~= nil and self.attackOverride:try_get("ammoType") ~= nil then
        return ""
    end

    if self.targetType == 'all' then
        return ""
    end

    local numTargets = self:GetNumTargets(casterToken, symbols)
    if numTargets == 0 then
        return ""
    end

    if numTargets == 1 and #targets == 0 then
        return nil
    end

    if numTargets >= 99 then
        return "Choose Targets"
    end

    if self.sequentialTargeting and symbols.targetnumber ~= nil and symbols.targetcount ~= nil then
        return string.format("Choose Target %d/%d", symbols.targetnumber, symbols.targetcount)
    end

    return string.format("Choose Target %d/%d", #targets + 1, numTargets)
end

function ActivatedAbility:AffectedByCover(caster)
    if self.keywords["Ranged"] then
        return true
    end

    local behaviors = self:try_get("behaviors", {})
    for _, behavior in ipairs(behaviors) do
        if behavior:AffectedByCover(caster, self) then
            return true
        end
    end

    return false
end

GameSystem.RegisterGoblinScriptField {
    target = ActivatedAbility,
    name = "Maneuver",
    type = "boolean",
    desc = "True if this ability is a maneuver.",
    seealso = {},
    examples = {},
    calculate = function(c)
        return c:IsManeuver()
    end,
}

GameSystem.RegisterGoblinScriptField {
    target = ActivatedAbility,
    name = "Trigger",
    type = "boolean",
    desc = "True if this ability is a trigger.",
    seealso = {},
    examples = {},
    calculate = function(c)
        return c:has_key("trigger")
    end,
}

GameSystem.RegisterGoblinScriptField {
    target = ActivatedAbility,
    name = "HeroicResourceCost",
    type = "number",
    desc = "The number of heroic resources this ability costs.",
    seealso = {},
    examples = {},
    calculate = function(c)
        if c.resourceCost ~= CharacterResource.heroicResourceId then
            return 0
        end

        return round(tonumber(c.resourceNumber) or 0)
    end,
}

GameSystem.RegisterGoblinScriptField {
    target = ActivatedAbility,
    name = "MaliceCost",
    type = "number",
    desc = "The number of malice resources this ability costs.",
    seealso = {},
    examples = {},
    calculate = function(c)
        if c.resourceCost ~= CharacterResource.maliceResourceId then
            return 0
        end

        return tonumber(c.resourceNumber) or 0
    end,
}

GameSystem.RegisterGoblinScriptField {
    target = ActivatedAbility,
    name = "Heroic",
    type = "boolean",
    desc = "Is this ability a heroic ability?",
    seealso = {},
    examples = {},
    calculate = function(c)
        return c.categorization == "Heroic Ability" and c.resourceCost == CharacterResource.heroicResourceId
    end,
}

GameSystem.RegisterGoblinScriptField {
    target = ActivatedAbility,
    name = "Categorization",
    type = "text",
    desc = "The categorization of this ability.",
    seealso = {},
    examples = {},
    calculate = function(c)
        return c.categorization
    end,
}

GameSystem.RegisterGoblinScriptField {
    target = ActivatedAbility,
    name = "Keywords",
    type = "set",
    desc = "The keywords this ability has.",
    seealso = {},
    examples = {},
    calculate = function(c)
        local strings = {}

        for keyword, _ in pairs(c.keywords) do
            strings[#strings + 1] = keyword
        end

        return StringSet.new {
            strings = strings,
        }
    end,
}

GameSystem.RegisterGoblinScriptField {
    target = ActivatedAbility,
    name = "Stolen",
    type = "boolean",
    desc = "True if this ability was stolen from another creature.",
    seealso = {},
    examples = {"Ability.Stolen"},
    calculate = function(c)
        return c:has_key("stolenFrom") and c.stolenFrom ~= nil and c.stolenFrom ~= ""
    end,
}

GameSystem.RegisterGoblinScriptField {
    target = ActivatedAbility,
    name = "Test",
    type = "boolean",
    desc = "True if this ability contains a power roll that is a test.",
    seealso = {},
    examples = {"Ability.Test"},
    calculate = function(c)
        if c:try_get("isTest", false) then
            return true
        end
        for _, behavior in ipairs(c.behaviors) do
            if behavior.typeName == "ActivatedAbilityPowerRollBehavior" and behavior:try_get("isTest", false) then
                return true
            end
        end
        return false
    end,
}

GameSystem.RegisterGoblinScriptField {
    target = ActivatedAbility,
    name = "TestSkills",
    type = "set",
    desc = "The skills applied to any test power rolls in this ability.",
    seealso = {},
    examples = {"Ability.TestSkills has 'Intimidate'"},
    calculate = function(c)
        local strings = {}
        local seen = {}
        local function addSkill(skillid)
            if skillid ~= nil and skillid ~= "none" and not seen[skillid] then
                seen[skillid] = true
                local skill = dmhub.GetTable(Skill.tableName)[skillid]
                if skill ~= nil then
                    strings[#strings + 1] = skill.name
                end
            end
        end
        if c:try_get("isTest", false) then
            addSkill(c:try_get("skillid"))
        end
        for _, behavior in ipairs(c.behaviors) do
            if behavior.typeName == "ActivatedAbilityPowerRollBehavior" and behavior:try_get("isTest", false) then
                addSkill(behavior:try_get("skillid"))
            end
        end
        return StringSet.new {
            strings = strings,
        }
    end,
}

ActivatedAbility.meleeAndRanged = false

function ActivatedAbility:GetTypeIconForActionBar()
    if self:try_get("isMeleeVariation") then
        return "ui-icons/skills/melee-attack-icon.png"
    elseif self:try_get("isRangedVariation") then
        return "ui-icons/skills/ranged-attack-icon.png"
    end
    return nil
end

ActivatedAbility.disableSplitIntoMeleeAndRanged = false

--if this ability is both melee and ranged we create a temporary clone
--which has each variation and return it.
function ActivatedAbility:BifurcateIntoMeleeAndRanged(creature)
    if (not self:HasKeyword("Melee")) or (not self:HasKeyword("Ranged")) or self.disableSplitIntoMeleeAndRanged then
        return self
    end

    if self.meleeAndRanged then
        --already done.
        return self
    end

    local result = self:MakeTemporaryClone()

    local melee = DeepCopy(result)
    local ranged = DeepCopy(result)
    melee.keywords["Ranged"] = nil
    ranged.keywords["Melee"] = nil
    ranged.keywords["Charge"] = nil
    melee.range = self:try_get("meleeRange", 1)

    melee.isMeleeVariation = true
    melee.isRangedVariation = false
    ranged.isMeleeVariation = false
    ranged.isRangedVariation = true

    result.meleeAndRanged = true

    result.meleeVariation = melee
    result.rangedVariation = ranged

    return result
end

--we synthesize melee/ranged abilities into different abilities for each.
function ActivatedAbility:SynthesizeAbilities(creature)
    if #self.behaviors > 0 then
        local result = self.behaviors[1]:SynthesizeAbilities(self, creature)
        if result ~= nil then
            return result
        end
    end

    return nil
end

creature.preferRanged = false

function ActivatedAbility:GetVariations(token)
    if self.meleeAndRanged then
        return { self.meleeVariation, self.rangedVariation }
    end

    return nil
end

function ActivatedAbility:GetActiveVariation(token)
    if self.meleeAndRanged then
        if token.properties.preferRanged then
            return self.rangedVariation
        else
            return self.meleeVariation
        end
    end

    return self
end

function ActivatedAbility:SetActiveVariation(token, variation)
    if self.meleeAndRanged then
        token:ModifyProperties {
            description = "Change stance",
            execute = function()
                if variation == self.meleeVariation then
                    token.properties.preferRanged = false
                elseif variation == self.rangedVariation then
                    token.properties.preferRanged = true
                end
            end,
        }
    end
end

function ActivatedAbility:DisplayOrder()
    return self:try_get("villainAction", "") .. self.name
end

ActivatedAbility.rangeBonusFromReach = 0

function ActivatedAbility:GetRange(casterCreature, castingSymbols, selfRange)
    if selfRange == nil or selfRange == "" then
        selfRange = self.range
    end

    local result = nil
    if type(selfRange) == "string" and string.lower(selfRange) == "touch" then
        result = dmhub.unitsPerSquare
    elseif type(selfRange) == "number" then
        result = selfRange
    elseif type(selfRange) == "string" then
        local n = tonumber(selfRange)
        if n ~= nil then
            result = n
        end
    end

    if result == nil then
        local caster = casterCreature or self:try_get("_tmp_boundCaster")
        if caster == nil then
            if type(selfRange) == "string" then
                local _, _, range = string.find(selfRange, "^(%d+)")
                if range ~= nil then
                    result = tonumber(range)
                end
            end

            --this means we really couldn't work out the range.
            if result == nil then
                result = dmhub.unitsPerSquare
            end
        else
            castingSymbols = castingSymbols or {}
            local symbols = {
                ability = self,
                mode = castingSymbols.mode or 1,
                charges = castingSymbols.charges or 0,
                upcast = castingSymbols.upcast or 0,
                invoker = castingSymbols.invoker,
            }
            result = ExecuteGoblinScript(selfRange, caster:LookupSymbol(symbols))
        end
    end

    if result == nil then
        result = dmhub.unitsPerSquare
    end

    --we get a ranged bonus, but not if we're invoking from a different ability because this
    --e.g. applies the bonus to forced movement.
    if casterCreature ~= nil and self:HasKeyword("Ranged") and self:try_get("invoker") == nil then
        local bonusRange = casterCreature:BonusRange()
        if bonusRange ~= nil then
            result = result + bonusRange
        end
    else
        result = result + self.rangeBonusFromReach
    end

    if castingSymbols ~= nil and castingSymbols.abilityRangeBonus ~= nil then
        result = result + castingSymbols.abilityRangeBonus
    end

    return result
end

function ActivatedAbility:GetLineDistance(castingCreature, castingSymbols)
    local distance = self.lineDistance
    local result
    if tonumber(distance) ~= nil then
        result = tonumber(distance)
    else
        castingSymbols = castingSymbols or {}
        local symbols = {
            ability = self,
            mode = castingSymbols.mode or 1,
            charges = castingSymbols.charges or 0,
            upcast = castingSymbols.upcast or 0,
            invoker = castingSymbols.invoker,
        }

        if castingCreature == nil then
            local _, _, range = string.find(distance, "^(%d+)")
            result = tonumber(range) or 1
        else
            result = ExecuteGoblinScript(self.lineDistance, castingCreature:LookupSymbol(symbols))
        end
    end

    return result
end

local g_baseGetRadius = ActivatedAbility.GetRadius
function ActivatedAbility:GetRadius(casterCreature, castingSymbols)
    local result = g_baseGetRadius(self, casterCreature, castingSymbols)
    if castingSymbols ~= nil and castingSymbols.abilityRadiusBonus ~= nil then
        result = result + castingSymbols.abilityRadiusBonus
    end
    return result
end

ActivatedAbility.registeredProperties = {}

local g_registeredPropertyToIndex = {}

--activated abilities can have boolean 'properties' that can be registered and
--control how they behave.
--- @param args {id: string, name: string, description: string}
function ActivatedAbility.RegisterProperty(args)
    local index = g_registeredPropertyToIndex[args.id] or #ActivatedAbility.registeredProperties + 1
    g_registeredPropertyToIndex[args.id] = index
    ActivatedAbility.registeredProperties[index] = args
    args.text = args.name

    GameSystem.RegisterGoblinScriptField {
        target = ActivatedAbility,
        name = args.name,
        type = "boolean",
        desc = args.description,
        examples = { "Ability has '" .. args.name .. "'" },
        calculate = function(c)
            local properties = c:try_get("properties")
            if properties == nil then
                return false
            end

            return properties[args.id] ~= nil
        end,
    }
end

function ActivatedAbility:HasProperty(id)
    return self:try_get("properties", {})[id] ~= nil
end

ActivatedAbility.RegisterProperty {
    id = "useasstrike",
    name = "Use as Free Strike",
    description = "If true, this ability can be used where a Free Strike can be used.",
}

ActivatedAbility.RegisterProperty {
    id = "useassignature",
    name = "Use as Signature Ability",
    description = "If true, this ability can be used where a Signature Ability can be used.",
}

ActivatedAbility.RegisterProperty {
    id = "remainhidden",
    name = "Remain Hidden",
    description = "If true, this ability will not cause hidden to be lost.",
}

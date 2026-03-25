local mod = dmhub.GetModLoading()

-- Registration tables for improvement param types.
CharacterModifier.ImprovementParams = {}
CharacterModifier.ImprovementParamsById = {}

--- @class AbilityImprovementParam
--- @field id string Unique identifier for this param type.
--- @field text string Display name shown in the "Add Param..." dropdown.
--- @field apply fun(ability: ActivatedAbility, value: number, caster: creature, symbols: table): fun() Temporarily patches ability fields and returns a restore function called after CalculateSpellTargeting.
--- @field documentation table|nil GoblinScript input documentation shown in the editor value field.

--- @param args AbilityImprovementParam
function CharacterModifier.RegisterImprovementParam(args)
    local existing = CharacterModifier.ImprovementParamsById[args.id]
    if existing == nil then
        CharacterModifier.ImprovementParams[#CharacterModifier.ImprovementParams + 1] = args
    else
        -- replace in-place so index order is preserved on re-registration
        for i, entry in ipairs(CharacterModifier.ImprovementParams) do
            if entry.id == args.id then
                CharacterModifier.ImprovementParams[i] = args
                break
            end
        end
    end
    CharacterModifier.ImprovementParamsById[args.id] = args
end

CharacterModifier.RegisterType("abilityimprovement", "Ability Improvement")

CharacterModifier.TypeInfo.abilityimprovement = {
    init = function(modifier)
        modifier.name = "Ability Improvement"
        modifier.rules = ""
        modifier.params = {}
        modifier.resourceCostType = "none"
        modifier.resourceCostAmount = "1"
    end,

    createEditor = function(modifier, element)
        local Refresh
        Refresh = function()
            local children = {}
            local hasCost = modifier.resourceCostType ~= "none"

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{ classes = {"formLabel"}, text = "Name:" },
                gui.Input{
                    characterLimit = 64,
                    classes = {"formInput"},
                    text = modifier.name,
                    change = function(element)
                        modifier.name = element.text
                        Refresh()
                    end,
                },
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{ classes = {"formLabel"}, text = "Description:" },
                gui.Input{
                    characterLimit = 320,
                    classes = {"formInput"},
                    text = modifier.rules,
                    multiline = true,
                    height = "auto",
                    width = 320,
                    minHeight = 14,
                    maxHeight = 80,
                    change = function(element)
                        modifier.rules = element.text
                        Refresh()
                    end,
                },
            }

            local keywordList = {}
            for keyword, _ in pairs(GameSystem.abilityKeywords) do
                keywordList[#keywordList+1] = { id = keyword, text = keyword }
            end
            table.sort(keywordList, function(a, b)
                return string.lower(a.text) < string.lower(b.text)
            end)

            children[#children+1] = gui.SetEditor{
                value = modifier:try_get("keywords", {}),
                addItemText = "Add Keyword...",
                options = keywordList,
                change = function(element, value)
                    modifier.keywords = value
                end,
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{ classes = {"formLabel"}, text = "Condition:" },
                gui.GoblinScriptInput{
                    value = modifier:try_get("abilityFilter", ""),
                    change = function(element)
                        modifier.abilityFilter = element.value
                    end,
                    documentation = {
                        help = "If set, this improvement only appears when the GoblinScript condition is true. Leave blank to always apply.",
                        output = "boolean",
                        subject = creature.helpSymbols,
                        subjectDescription = "The creature casting the ability.",
                        symbols = {
                            ability = {
                                name = "Ability",
                                type = "ability",
                                desc = "The ability being cast.",
                                examples = {
                                    "Ability.Name = 'Phalanx'",
                                    "Ability.Free Strike",
                                },
                            },
                        },
                    },
                },
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{ classes = {"formLabel"}, text = "Cost:" },
                gui.Dropdown{
                    options = {
                        { id = "none", text = "None" },
                        { id = "cost", text = "Heroic/Malice Resource" },
                        { id = "epic", text = "Epic Resource" },
                    },
                    idChosen = modifier.resourceCostType,
                    change = function(element)
                        modifier.resourceCostType = element.idChosen
                        Refresh()
                    end,
                },
            }

            if hasCost then
                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{ classes = {"formLabel"}, text = "Cost Amount:" },
                    gui.GoblinScriptInput{
                        value = modifier.resourceCostAmount,
                        change = function(element)
                            modifier.resourceCostAmount = element.value
                        end,
                        documentation = {
                            help = "The amount of resource required to use this improvement.",
                            output = "number",
                            examples = {{ script = "1", text = "Costs 1 resource." }},
                            subject = creature.helpSymbols,
                            subjectDescription = "The creature with this improvement.",
                        },
                    },
                }
            end

            -- List current params with delete buttons and value inputs.
            local params = modifier:try_get("params", {})
            for i, param in ipairs(params) do
                local info = CharacterModifier.ImprovementParamsById[param.id]
                if info ~= nil then
                    children[#children+1] = gui.Panel{
                        classes = {"formPanel"},
                        gui.Label{
                            classes = {"formLabel"},
                            width = 400,
                            text = info.text,
                        },
                        gui.DeleteItemButton{
                            width = 16,
                            height = 16,
                            valign = "center",
                            halign = "right",
                            click = function(element)
                                table.remove(params, i)
                                modifier.params = params
                                Refresh()
                            end,
                        },
                    }

                    if info.documentation ~= nil then
                        children[#children+1] = gui.Panel{
                            classes = {"formPanel"},
                            height = "auto",
                            gui.Label{ classes = {"formLabel"}, text = "Value:" },
                            gui.GoblinScriptInput{
                                height = "auto",
                                width = 360,
                                fontSize = 16,
                                value = param.value,
                                change = function(element)
                                    params[i].value = element.value
                                end,
                                documentation = info.documentation,
                            },
                        }
                    end
                end
            end

            -- Dropdown to add a new param.
            local addOptions = { { id = "none", text = "Add Param..." } }
            for _, info in ipairs(CharacterModifier.ImprovementParams) do
                addOptions[#addOptions+1] = info
            end

            children[#children+1] = gui.Dropdown{
                options = addOptions,
                idChosen = "none",
                height = 30,
                width = 260,
                fontSize = 16,
                change = function(element)
                    if element.idChosen == "none" then return end
                    params[#params+1] = { id = element.idChosen, value = "" }
                    modifier.params = params
                    Refresh()
                end,
            }

            element.children = children
        end

        Refresh()
    end,
}

-- Built-in improvement param registrations.

local g_improvSymbols = {
    ability = {
        name = "Ability",
        type = "ability",
        desc = "The ability being improved.",
    },
}

CharacterModifier.RegisterImprovementParam{
    id = "range",
    text = "Range Bonus",
    accumulate = function(ability, value, caster, symbols)
        symbols.abilityRangeBonus = (symbols.abilityRangeBonus or 0) + value
    end,
    documentation = {
        help = "This GoblinScript is added to the range of the ability in squares.",
        output = "number",
        examples = {
            { script = "2", text = "Adds 2 squares of range." },
            { script = "2 + 1 when level > 4", text = "Adds 2 squares, or 3 when the creature is above level 4." },
        },
        subject = creature.helpSymbols,
        subjectDescription = "The creature with this improvement.",
        symbols = g_improvSymbols,
    },
}


CharacterModifier.RegisterImprovementParam{
    id = "radius",
    text = "Radius Bonus",
    accumulate = function(ability, value, caster, symbols)
        -- Burst abilities (targetType == "all") use GetRange as the burst radius,
        -- so accumulate into abilityRangeBonus which GetRange will add.
        if ability:try_get("targetType") == "all" then
            symbols.abilityRangeBonus = (symbols.abilityRangeBonus or 0) + value
        else
            symbols.abilityRadiusBonus = (symbols.abilityRadiusBonus or 0) + value
        end
    end,
    documentation = {
        help = "This GoblinScript is added to the radius of the ability in squares.",
        output = "number",
        examples = {
            { script = "1", text = "Adds 1 square to radius." },
        },
        subject = creature.helpSymbols,
        subjectDescription = "The creature with this improvement.",
        symbols = g_improvSymbols,
    },
}

CharacterModifier.RegisterImprovementParam{
    id = "target_count",
    text = "Target Count Bonus",
    accumulate = function(ability, value, caster, symbols)
        -- Use a helper to accumulate across multiple improvements, then set override.
        local bonus = (symbols._abilityTargetCountBonus or 0) + value
        symbols._abilityTargetCountBonus = bonus
        symbols.numtargetsoverride = ability:GetNumTargets(caster, {}) + bonus
    end,
    documentation = {
        help = "This GoblinScript is added to the number of targets for the ability.",
        output = "number",
        examples = {
            { script = "1", text = "Adds 1 additional target." },
        },
        subject = creature.helpSymbols,
        subjectDescription = "The creature with this improvement.",
        symbols = g_improvSymbols,
    },
}

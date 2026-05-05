local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType("suppressabilities", "Suppress Abilities")


CharacterModifier.TypeInfo.suppressabilities = {

	init = function(modifier)
    end,

    createEditor = function(modifier, element)
        local Refresh

        Refresh = function()

            local children = {}

			children[#children+1] = modifier:FilterConditionEditor()

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Ability Filter:",
                },
                gui.GoblinScriptInput{
                    value = modifier:try_get("abilityFilter", ""),
                    change = function(element)
                        modifier.abilityFilter = element.value
                    end,

                    documentation = {
                        help = "This GoblinScript is used to determine if this modifier filters an ability. If the result is true, the ability will be available, if it is false, the ability will be suppressed.",
                        output = "boolean",
                        subject = creature.helpSymbols,
                        subjectDescription = "The creature that is affected by this modifier",
                        symbols = {
                            ability = {
                                name = "Ability",
                                type = "ability",
                                desc = "The ability that is being checked for suppression.",
                                examples = {
                                    "Ability.Name = 'Hide'",
                                    "Ability.Keywords has 'Fire'",
                                },
                            }
                        }
                    }
                },
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Explanation:",
                },
                gui.Input{
                    classes = {"formInput"},
                    text = modifier:try_get("explanation", ""),
                    characterLimit = 256,
                    change = function(element)
                        modifier.explanation = element.text
                    end,
                }
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Name:",
                },
                gui.Input{
                    classes = {"formInput"},
                    text = modifier:try_get("name", ""),
                    characterLimit = 64,
                    change = function(element)
                        modifier.name = element.text
                    end,
                }
            }

            local keywordList = {}
            for keyword,_ in pairs(GameSystem.abilityKeywords) do
                keywordList[#keywordList+1] = {id = keyword, text = keyword}
            end

            table.sort(keywordList, function(a, b)
                return string.lower(a.text) < string.lower(b.text)
            end)

            children[#children+1] = gui.Multiselect{
                value = modifier:try_get("keywords", {}),
                addItemText = "Add Keyword...",
                options = keywordList,
                change = function(element, value)
                    modifier.keywords = value
                end,
            }

            element.children = children
        end

        Refresh()
    end,

    modifyAbility = function(modifier, creature, ability)
        local abilityFilter = modifier:try_get("abilityFilter", "")
        if abilityFilter == "" and modifier:has_key("name") and string.lower(ability.name) == string.lower(modifier.name) then
            if modifier:has_key("explanation") and modifier.explanation ~= "" then
                ability = ability:MakeTemporaryClone()
                ability.suppressExplanation = modifier.explanation
                return ability
            end
            return nil
        end
        if modifier:has_key("keywords") then
            for keyword,_ in pairs(modifier.keywords) do
                if ability.keywords[keyword] then
                    if modifier:has_key("explanation") and modifier.explanation ~= "" then
                        ability = ability:MakeTemporaryClone()
                        ability.suppressExplanation = modifier.explanation
                        return ability
                    end
                    return nil
                end
            end
        end

        if abilityFilter ~= "" then
            local symbols = creature:LookupSymbol{ability = ability}
            local passFilter = GoblinScriptTrue(ExecuteGoblinScript(abilityFilter, symbols, 1, "Ability filter"))
            if not passFilter then
                if modifier:has_key("explanation") and modifier.explanation ~= "" then
                    ability = ability:MakeTemporaryClone()
                    ability.suppressExplanation = modifier.explanation
                    return ability
                end
                return nil
            end
        end

        return ability
    end,
}
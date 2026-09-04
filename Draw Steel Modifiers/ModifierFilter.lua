local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType('filter', "Filter")

CharacterModifier.TypeInfo.filter = {
    init = function(modifier)
        modifier.filterid = "none"
        modifier.filter = ""
    end,

    createEditor = function(modifier, element)
        local Refresh
        local firstRefresh = true

        Refresh = function()
            if firstRefresh then
                firstRefresh = false
            else
                element:FireEvent("refreshModifier")
            end

            local children = {}

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Filter Type:",
                },
                gui.Dropdown{
                    styles = ThemeEngine.GetStyles(),
                    options = CreatureFilter.filterOptions,
                    idChosen = modifier.filterid,
                    textDefault = "Choose...",
                    hasSearch = true,
                    sort = true,
                    change = function(element)
                        modifier.filterid = element.idChosen
                        Refresh()
                    end,
                },
            }

            local filterInfo = CreatureFilter.filters[modifier.filterid]
            if filterInfo ~= nil then
                children[#children+1] = gui.Label{
                    classes = {"formLabel"},
                    width = "80%",
                    height = "auto",
                    text = filterInfo.description or "",
                }
            end

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Filter:",
                },
                gui.GoblinScriptInput{
                    value = modifier.filter,
                    change = function(element)
                        modifier.filter = element.value
                        Refresh()
                    end,

                    documentation = {
                        help = "This GoblinScript is used to determine if a target passes the chosen filter type.",
                        output = "boolean",
                        examples = {
                            {
                                script = "target.type != 'goblin'",
                                text = "Goblins will not pass this filter.",
                            }
                        },
                        subject = creature.helpSymbols,
                        subjectDescription = "The creature that is filtering targets.",

                        symbols = {
                            target = {
                                name = "Target",
                                type = "creature",
                                desc = "The target of the filter.",
                            }
                        },
                    }
                },
            }

            element.children = children
        end

        Refresh()
    end,
}

--- @param targetCreature creature
--- @param filterid string
function creature:TargetPassesFilter(filterid, targetCreature)
    local modifiers = self:GetActiveModifiers()
    for _,mod in ipairs(modifiers) do
        if mod.mod.behavior == "filter" and mod.mod.filterid == filterid then
            local symbols = {
                target = targetCreature,
            }
            local passFilter = GoblinScriptTrue(ExecuteGoblinScript(mod.mod.filter, self:LookupSymbol(symbols), 1, "Filter targets"))
            if not passFilter then
                return false
            end
        end
    end
    return true
end
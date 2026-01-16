6 mod = dmhub.GetModLoading()

--- @class ActivatedAbilityApplyRidersBehavior
ActivatedAbilityApplyRidersBehavior = RegisterGameType("ActivatedAbilityApplyRidersBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityApplyRidersBehavior.summary = "Add Condition Riders"

ActivatedAbility.RegisterType
{
    id = "conditionriders",
    text = "Add Condition Riders",
    createBehavior = function()
        return ActivatedAbilityApplyRidersBehavior.new{
            conditionid = "none",
            riderid = "none",
        }
    end,
}

function ActivatedAbilityApplyRidersBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Add Condition Riders"
end

function ActivatedAbilityApplyRidersBehavior:Cast(ability, casterToken, targets, options)
    --intentionally blank, this is queried from other behaviors.
end

function ActivatedAbility:GetRidersForCondition(conditionid, casterToken, targetToken, options)
    local result = {}
    for _,behavior in ipairs(self.behaviors) do
        behavior:FillRidersOnCondition(conditionid, self, casterToken, targetToken, options, result)
    end

    if #result == 0 then
        return nil
    end
    return result
end

--- @param conditionid string
--- @param casterToken CharacterToken
--- @param targetToken CharacterToken
--- @param options table
--- @param result table
function ActivatedAbilityBehavior:FillRidersOnCondition(conditionid, ability, casterToken, targetToken, options, result)
end

--- @param conditionid string
--- @param casterToken CharacterToken
--- @param targetToken CharacterToken
--- @param options table
--- @param result table
function ActivatedAbilityApplyRidersBehavior:FillRidersOnCondition(conditionid, ability, casterToken, targetToken, options, result)
    print("Riders: Filling", conditionid, self.conditionid, self.riderid)
    if conditionid ~= self.conditionid then
            print("Riders: Condition wrong")
        return
    end

    local filterTarget = self:try_get("filterTarget", "")
    if filterTarget ~= "" then
        local filtered = ExecuteGoblinScript(filterTarget, targetToken.properties:LookupSymbol(options.symbols), 1, "Filter target")
        if not GoblinScriptTrue(filtered) then
            print("Riders: filtered out", filterTarget)
            return
        end
    end

    if self:IsFiltered(ability, casterToken, options) then
            print("Riders: IsFiltered")
        return
    end

            print("Riders: Adding", self.riderid)
    result[#result+1] = self.riderid
end

function ActivatedAbilityApplyRidersBehavior:EditorItems(parentPanel)
    local editor = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "vertical",
    }
    local Refresh
    Refresh = function()

        local result = {}
        self:FilterEditor(parentPanel, result)

        local conditionTable = dmhub.GetTable(CharacterCondition.tableName)
        local conditionOptions = {}
        for key,conditionInfo in unhidden_pairs(conditionTable) do
            conditionOptions[#conditionOptions+1] = {
                id = conditionInfo.id,
                text = conditionInfo.name,
            }
        end

        local riderTable = dmhub.GetTable(CharacterCondition.ridersTableName)
        local riderOptions = {}
        for key,riderInfo in unhidden_pairs(riderTable) do
            if riderInfo.condition == self.conditionid then
                riderOptions[#riderOptions+1] = {
                    id = riderInfo.id,
                    text = riderInfo.name,
                }
            end
        end

        result[#result+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Condition",
            },
            gui.Dropdown{
                idChosen = self.conditionid,
                options = conditionOptions,
                sort = true,
                hasSearch = true,
                change = function(element)
                    self.conditionid = element.idChosen
                    print("Riders: Condition changed", element.idChosen)
                    Refresh()
                end,
            }
        }

        if #riderOptions > 0 then
            result[#result+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Rider:",
                },
                gui.Dropdown{
                    idChosen = self.riderid,
                    options = riderOptions,
                    sort = true,
                    change = function(element)
                        self.riderid = element.idChosen
                        Refresh()
                    end,
                }
            }
        elseif self.conditionid ~= "none" then
            result[#result+1] = gui.Label{
                classes = {"formLabel"},
                text = "No riders available for this condition.",
            }
        end

        editor.children = result
    end

    Refresh()

    return {editor}
end
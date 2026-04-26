local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityCreateItemBehavior:ActivatedAbilityBehavior
--- @field summary string Short label shown in behavior lists.
--- @field itemid string Id of the equipment item to create ("none" if unset).
--- @field quantity string|number|table Number of items to create (can be a dice expression).
ActivatedAbilityCreateItemBehavior = RegisterGameType("ActivatedAbilityCreateItemBehavior", "ActivatedAbilityBehavior")


ActivatedAbility.RegisterType
{
	id = 'create_item',
	text = 'Create Item',
	createBehavior = function()
		return ActivatedAbilityCreateItemBehavior.new{
		}
	end
}

ActivatedAbilityCreateItemBehavior.summary = 'Create Item'
ActivatedAbilityCreateItemBehavior.itemid = 'none'
ActivatedAbilityCreateItemBehavior.quantity = '1'

function ActivatedAbilityCreateItemBehavior:Cast(ability, casterToken, targets, options)
    if #targets == 0 then
        return
    end

	local t = dmhub.GetTable(equipment.tableName)
    local itemInfo = t[self.itemid]
    if itemInfo == nil then
        return
    end

    for _,target in ipairs(targets) do
        if target.token ~= nil then
            local quantity = nil
            local rollComplete = false

            local rollid = gamehud.rollDialog.data.ShowDialog{
                title = "Create Items",
                description = string.format("Roll to create %s", itemInfo.name),
                roll = dmhub.EvalGoblinScript(self.quantity, casterToken.properties:LookupSymbol(options.symbols), string.format("Resource roll for %s", ability.name)),
                creature = casterToken.properties,
                skipDeterministic = true,
                type = "custom",

                cancelRoll = function()
                    rollComplete = true
                end,
                completeRoll = function(rollInfo)
                    rollComplete = true
                    quantity = rollInfo.total
                end,
            }

            while rollComplete == false do
                coroutine.yield(0.1)
            end

            if type(quantity) == "number" then
                ability:CommitToPaying(casterToken, options)

                target.token:ModifyProperties{
                    description = "Create Item",
                    execute = function()
                        target.token.properties:GiveItem(self.itemid, quantity)
                    end,
                }
            end
        end

    end

end

function ActivatedAbilityCreateItemBehavior:EditorItems(parentPanel)
    local result = {}

	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

	local options = {}
	local t = dmhub.GetTable(equipment.tableName)
	for k,item in pairs(t) do
        options[#options+1] = {
            id = k,
            text = item.name,
        }
    end

    table.sort(options, function(a,b) return a.text < b.text end)

    result[#result+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Item:",
        },
        gui.Dropdown{
            idChosen = self.itemid,
            hasSearch = true,
            options = options,
            change = function(element)
                self.itemid = element.idChosen
            end,
        }
    }

    result[#result+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Quantity:",
        },

        gui.GoblinScriptInput{
            value = self.quantity,
            events = {
                change = function(element)
                    self.quantity = element.value
                end,
            },

			documentation = {
				help = string.format("This GoblinScript determines the number of items to create."),
				output = "roll",
				examples = {
					{
						script = "1",
						text = "1 item is created.",
					},
					{
						script = "2d6",
						text = "2d6 items are created.",
					},
				},
				subject = creature.helpSymbols,
				subjectDescription = "The creature that is casting the spell.",
				symbols = ActivatedAbility.helpCasting,
			},
        },
    }


    return result
end
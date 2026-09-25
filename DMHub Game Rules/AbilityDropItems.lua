local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityDropItemsBehavior:ActivatedAbilityBehavior
--- @field summary string Short label shown in behavior lists.
--- @field slotTarget string Equipment slot to drop items from (e.g. "hands").
--- @field number string|number Number of items to drop, or "all".
ActivatedAbilityDropItemsBehavior = RegisterGameType("ActivatedAbilityDropItemsBehavior", "ActivatedAbilityBehavior")


ActivatedAbility.RegisterType
{
	id = 'drop_items',
	text = 'Discard Items',
	createBehavior = function()
		return ActivatedAbilityDropItemsBehavior.new{
            conditions = {},
		}
	end
}

ActivatedAbilityDropItemsBehavior.summary = 'Discard Items'
ActivatedAbilityDropItemsBehavior.slotTarget = 'hands'
ActivatedAbilityDropItemsBehavior.number = 'all'

ActivatedAbilityDropItemsBehavior.slotTargetTypes = {
    --[[ {
        id = "hands",
        text = "Items in Hand",
    }, ]]
    --[[ {
        id = "hands_or_belt",
        text = "Items in Hand or Belt",
    }, ]]
    { 
        id = "equipped",
        text = "Equipped Items",
    },
    {
        id = "all",
        text = "Entire Inventory",
    },
    {
        id = "named",
        text = "Named Items",
    },
}

ActivatedAbilityDropItemsBehavior.numberOptions = {
    {
        id = "one",
        text = "One Item",
    },
    {
        id = "multiple",
        text = "Multiple Items",
    },
    {
        id = "all",
        text = "All Items",
    },
}

ActivatedAbilityDropItemsBehavior.discardBehavior = "drop"
ActivatedAbilityDropItemsBehavior.behaviorOptions = {
    {
        id = "drop",
        text = "Drop Items",
    },
    {
        id = "destroy",
        text = "Destroy Items",
    },
}


function ActivatedAbilityDropItemsBehavior:Cast(ability, casterToken, targets, options)
    for i,target in ipairs(targets) do
        if target.token ~= nil then
            local discardable = self:GetDiscardable(target.token.properties)

            printf("ITEMDROP:: DISCARDABLE: %d", #discardable)

            if self.number ~= "all" then
                local options = {}

                for i,entry in ipairs(discardable) do
                    options[#options+1] = {
                        id = i,
                        iconid = entry.item.iconid,
                        text = entry.item.name,
                        selected = (i == 1 or self.number == "multiple"),
                    }
                end

                local result = self:ShowOptionsDialog{
                    title = "Discard Items",
                    multiselect = self.number == "multiple",
                    options = options,
                }

                if not result then
                    return
                end

                local newDiscardable = {}
                for i,option in ipairs(options) do
                    if option.selected then
                        newDiscardable[#newDiscardable+1] = discardable[i]
                    end
                end

                discardable = newDiscardable

            end

            if #discardable > 0 then
                ability:CommitToPaying(casterToken, options)
                local quantities = {}
                target.token:ModifyProperties{
                    description = "Discard items",
                    execute = function()
                        for _,entry in ipairs(discardable) do
                            self:ExecuteDiscard(target.token, entry, quantities)
                        end
                    end,
                }

                if self.discardBehavior == "drop" then
                    for k,v in pairs(quantities) do
                        printf("ITEMDROP:: SPAWN DROP: %s", k)
                        loot.SpawnDroppedItem(target.token, k, v)
                    end
                end
            end
        end
    end
end

function ActivatedAbilityDropItemsBehavior:ExecuteDiscard(targetToken, entry, dropQuantities)
    if entry.type == "slot" then
        local itemid = targetToken.properties:Unequip(entry.id)
        printf("ITEMDROP:: Unequip %s -> %s", entry.id, json(itemid))
        if itemid ~= nil then
            targetToken.properties:GiveItem(itemid, -1)
            dropQuantities[itemid] = (dropQuantities[itemid] or 0) + 1
            printf("ITEMDROP:: SET QUANTITIES: %s", json(dropQuantities))
        end

    else
        local itemid = entry.id
        targetToken.properties:GiveItem(itemid, -1)
        dropQuantities[itemid] = (dropQuantities[itemid] or 0) + 1
            printf("ITEMDROP:: SET QUANTITIES2: %s", json(dropQuantities))
    end
end

function ActivatedAbilityDropItemsBehavior:GetDiscardable(targetCreature)
    local result = {}
    local loadoutInfo = targetCreature:GetLoadoutInfo(targetCreature.selectedLoadout)
    local equipment = targetCreature:Equipment()
    print("ITEMDROP:: EQUIPMENT: ",json(equipment))

    local gearTable = dmhub.GetTable('tbl_Gear')
    --[[if loadoutInfo.mainhand ~= nil then
        result[#result+1] = {
            type = "slot",
            id = string.format("mainhand%d", targetCreature.selectedLoadout),
            item = gearTable[loadoutInfo.mainhand],
        }
    end

    if loadoutInfo.offhand ~= nil then
        result[#result+1] = {
            type = "slot",
            id = string.format("offhand%d", targetCreature.selectedLoadout),
            item = gearTable[loadoutInfo.offhand],
        }
    end ]]

    local equip = targetCreature:Equipment()
    if self.slotTarget == "equipped" then
        for slot, key in pairs(equip) do
            result[#result+1] = {
                type = "slot",
                id = key,
                item = gearTable[key],
            }
        end
    end

    if self.slotTarget == "all" then
        for key,info in pairs(targetCreature:try_get("inventory", {})) do
            result[#result+1] = {
                type = "item",
                id = key,
                item = gearTable[key],
            }
        end
        for slot, key in pairs(equip) do
            result[#result+1] = {
                type = "slot",
                id = key,
                item = gearTable[key],
            }
        end
    end

    return result
end


function ActivatedAbilityDropItemsBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Target Items:",
        },

        gui.Dropdown{
            idChosen = self.slotTarget,
            options = ActivatedAbilityDropItemsBehavior.slotTargetTypes,
            change = function(element)
                ---@cast element Dropdown
                self.slotTarget = element.idChosen
            end,

        },
    }

    result[#result+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Number of Items:",
        },

        gui.Dropdown{
            idChosen = self.number,
            options = ActivatedAbilityDropItemsBehavior.numberOptions,
            change = function(element)
                ---@cast element Dropdown
                self.number = element.idChosen
            end,

        },
    }

    result[#result+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Discard Behavior:",
        },

        gui.Dropdown{
            idChosen = self.discardBehavior,
            options = ActivatedAbilityDropItemsBehavior.behaviorOptions,
            change = function(element)
                ---@cast element Dropdown
                self.discardBehavior = element.idChosen
            end,

        },
    }


	return result
end

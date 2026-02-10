local mod = dmhub.GetModLoading()

RegisterGameType("EquipmentCategory")

local g_unarmoredCategory = nil

EquipmentCategory.tableName = "equipmentCategories"

EquipmentCategory.name = 'New Category'
EquipmentCategory.editorType = 'Gear'
EquipmentCategory.superset = nil --the parent category.

EquipmentCategory.allowProficiency = false
EquipmentCategory.allowIndividualProficiency = false

EquipmentCategory.ConsumableId = "95125d91-fe41-4310-8f7b-44386651b0a7"
EquipmentCategory.LeveledTreasureId = "e036b288-416c-4a2e-ac33-95c6a528ed87"
EquipmentCategory.LightSourceId = "4c9fc2bb-1c17-4072-babe-c2e3a55faa65"
EquipmentCategory.PacksId = "659f34f2-14d6-4e71-99c1-89d703d5ba48"
EquipmentCategory.TrinketId = "659f34f2-14d6-4e71-99c1-89d703d5ba48"
EquipmentCategory.ImbuementId = "f8795dac-fda0-48a7-ba63-c2618c812d76"

EquipmentCategory.isUnarmored = false
EquipmentCategory.isTool = false
EquipmentCategory.isMartial = false
EquipmentCategory.isMelee = false
EquipmentCategory.isRanged = false
EquipmentCategory.isAmmo = false
EquipmentCategory.isQuantity = false
EquipmentCategory.isTreasure = false
EquipmentCategory.isPacks = false
EquipmentCategory.isLightSource = false

EquipmentCategory.martialWeaponCategories = {}
EquipmentCategory.meleeWeaponCategories = {}
EquipmentCategory.rangedWeaponCategories = {}
EquipmentCategory.quantityCategories = {}
EquipmentCategory.treasureCategories = {}
EquipmentCategory.lightSourceCategories = {}
EquipmentCategory.packsCategories = {}

EquipmentCategory.ammunitionOptions = {
	{
		id = "none",
		text = "(None)",
	}
}

function EquipmentCategory.CreateNew()
	return EquipmentCategory.new{
	}
end

function EquipmentCategory.GetUnarmoredId()
	return g_unarmoredCategory
end

function EquipmentCategory.GetUnarmored()
	if g_unarmoredCategory == nil then
		return nil
	end

	local cats = dmhub.GetTable(EquipmentCategory.tableName) or {}
	return cats[g_unarmoredCategory]
end

function EquipmentCategory.GetEquipmentProficiencyDropdownOptions()
	local skillOptions = {}
	local cats = dmhub.GetTable(EquipmentCategory.tableName) or {}
	for k,cat in pairs(cats) do
		if (not cat:try_get("hidden")) and cat.allowProficiency then
			skillOptions[#skillOptions+1] = {
				id = k,
				text = cat.name,
			}
		end
	end

	local equipment = dmhub.GetTable("tbl_Gear") or {}
	for k,equip in pairs(equipment) do
		if (not equip:try_get("hidden")) and equip:try_get("equipmentCategory") and (not equip:has_key("magicalItem")) and equip:has_key("baseid") == false and cats[equip.equipmentCategory] and cats[equip.equipmentCategory].allowIndividualProficiency then
			skillOptions[#skillOptions+1] = {
				id = k,
				text = equip.name,
			}
		end
	end

	table.sort(skillOptions, function(a,b) 
		return a.text < b.text
	end)
	
	return skillOptions
end

local g_catsToItemsCache = {}

function EquipmentCategory.GetCategoriesToItems(includeMagical)
	local cacheKey = cond(includeMagical, true, false)
	if g_catsToItemsCache[cacheKey] ~= nil then
		return g_catsToItemsCache[cacheKey]
	end

	local catsToItems = {} --category key to list of item keys.
	local itemsTable = dmhub.GetTable('tbl_Gear')

	--walk over the items and assign them to the catsToItems table.
	for k,item in pairs(itemsTable) do
		if (not item:has_key("hidden")) and (not item:has_key("uniqueItem")) and item:has_key("equipmentCategory") and (includeMagical or (not item:has_key("magicalItem"))) then
			catsToItems[item.equipmentCategory] = catsToItems[item.equipmentCategory] or {}

			local list = catsToItems[item.equipmentCategory]
			list[#list+1] = k
		end
	end

	local result = {}
	local catsTable = dmhub.GetTable(EquipmentCategory.tableName) or {}

	--look at all of a category's parents and assign the items to them also.
	for k,itemsList in pairs(catsToItems) do
		local key = k
		while key ~= nil and catsTable[key] ~= nil do
			local catInfo = catsTable[key]

			result[key] = result[key] or {}
			local resultItems = result[key]
			for _,item in ipairs(itemsList) do
				resultItems[#resultItems+1] = item
			end

			key = catInfo:try_get("superset")
		end
	end

	g_catsToItemsCache[cacheKey] = result

	return result
end

--Generic interface for indexing data tables by name.
local NormalizeGoblinScriptString = function(str)
	return string.gsub(string.lower(str), "%s+", "")
end

local g_ItemNameIndexRefresh = {}
local g_ItemNameIndex = {}

function LookupObjectIdInTableByName(tableid, itemname)
	if g_ItemNameIndexRefresh[tableid] ~= dmhub.tablesUpdateId then
		g_ItemNameIndexRefresh[tableid] = dmhub.tablesUpdateId

		local dataTable = dmhub.GetTable(tableid)

		--prefer to keep the current cached lookup table.
		local index = g_ItemNameIndex[tableid]
		if index ~= nil then
			local counta = 0
			local countb = 0
			for k,v in pairs(dataTable) do
				if rawget(v, "hidden") ~= true then
					counta = counta+1
				end
			end

			for k,v in pairs(index) do
				countb = countb+1
			end

			if counta ~= countb then
				index = nil
			else
				for k,v in pairs(dataTable) do
					local name = NormalizeGoblinScriptString(v.name)
					if index[name] ~= k then
						index = nil
						break
					end
				end
			end
		end

		--build the index.
		if index == nil then
			index = {}

			local dataTable = dmhub.GetTable(tableid)
			for k,v in pairs(dataTable) do
				if rawget(v, "hidden") ~= true then
					index[NormalizeGoblinScriptString(v.name)] = k
				end
			end

			g_ItemNameIndex[tableid] = index
		end
	end

	return g_ItemNameIndex[tableid][NormalizeGoblinScriptString(itemname)]
end

local firstTime = true

dmhub.RegisterEventHandler("refreshTables", function()
	g_catsToItemsCache = {}

	if firstTime == false then
		return
	end

	firstTime = false

	local cats = dmhub.GetTable("equipmentCategories") or {}
	for k,cat in pairs(cats) do
		if cat.isUnarmored then
			g_unarmoredCategory = k
		end

		if cat.isMartial then
			EquipmentCategory.martialWeaponCategories[k] = true
		end

		if cat.isMelee then
			EquipmentCategory.meleeWeaponCategories[k] = true
		end

		if cat.isRanged then
			EquipmentCategory.rangedWeaponCategories[k] = true
		end

		if cat.isQuantity then
			EquipmentCategory.quantityCategories[k] = true
		end

		if cat.isTreasure then
			EquipmentCategory.treasureCategories[k] = true
		end

        if cat.isLightSource then
            EquipmentCategory.lightSourceCategories[k] = true
        end

		if cat.isPacks then
			EquipmentCategory.packsCategories[k] = true
		end

		if cat.isAmmo then
			EquipmentCategory.ammunitionOptions[#EquipmentCategory.ammunitionOptions+1] = {
				id = k,
				text = cat.name,
			}
		end
	end
end)

function EquipmentCategory.IsPack(item)
	return cond(EquipmentCategory.packsCategories[item:try_get("equipmentCategory", "")], true, false)
end

function EquipmentCategory.IsConsumable(item)
    return item:try_get("equipmentCategory", "") == EquipmentCategory.ConsumableId
end

function EquipmentCategory.IsEquippable(item)
    local cat = item:try_get("equipmentCategory", "")
    return cat == EquipmentCategory.LeveledTreasureId or cat == EquipmentCategory.TrinketId
end

function EquipmentCategory.IsLeveledTreasure(item)
    local cat = item:try_get("equipmentCategory", "")
    return cat == EquipmentCategory.LeveledTreasureId
end

function EquipmentCategory.IsTrinket(item)
    local cat = item:try_get("equipmentCategory", "")
    return cat == EquipmentCategory.TrinketId
end

function EquipmentCategory.IsTreasure(item)
	return cond(EquipmentCategory.treasureCategories[item:try_get("equipmentCategory", "")], true, false)
end

function EquipmentCategory.IsLightSource(item)
	return cond(EquipmentCategory.lightSourceCategories[item:try_get("equipmentCategory", "")], true, false)
end

function EquipmentCategory.IsImbuement(item)
    local cat = item:try_get("equipmentCategory", "")
    return cat == EquipmentCategory.ImbuementId
end

function EquipmentCategory.IsMagical(item)
	return item:has_key("magicalItem")
end

function EquipmentCategory:Render(options, token)

	options = options or {}
	local summary = options.summary
	options.summary = nil

	local catsToItems = EquipmentCategory.GetCategoriesToItems()

	local itemsList = catsToItems[self.id]
	if itemsList == nil or #itemsList == 0 then
		return nil
	end

    local inventoryTable = dmhub.GetTable("tbl_Gear")

	local itemPanels = {}
	for i,itemid in ipairs(itemsList) do
		local item = inventoryTable[itemid]
		if item ~= nil then
			itemPanels[#itemPanels+1] = gui.Label{
				text = string.format("%s %s", Styles.bullet, tr(item.name)),
			}
		end
	end

	table.sort(itemPanels, function(a,b) return a.text < b.text end)

	local children = {
		gui.Label{
			classes = {"title"},
			text = tr(self.name),
		},
		itemPanels,
	}


	return gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",

		styles = Styles.ItemTooltip,

		children = children,
	}
end
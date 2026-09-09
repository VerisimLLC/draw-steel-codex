local mod = dmhub.GetModLoading()

--This file implements rules for any entity that can hold collections of items.
--The code in it is reused by creatures to represent their inventories, so it
--contains foundational code for inventory management

local function CreateSheet()
	return gui.Panel{
		width = 100,
		height = 100,
		halign = "center",
		valign = "center",
		interactable = false,
	}
end

local function GetSheet(component)

	if component.sheet.sheet == nil then
		component.sheet.sheet = CreateSheet()
	end

	return component.sheet.sheet
end

--- @class loot: GameType
--- @field inventory table<string, table> Map of item id to inventory entry.
--- @field isLoot boolean Always true for loot objects; distinguishes from full creature objects.
--- @field discount number Percentage discount applied to item prices when purchasing (0-100).
--- Represents a loot container (chest, dropped items, NPC shop) attached to a map object.
loot = RegisterGameType("loot")

loot.inventory = {}
loot.isLoot = true
loot.discount = 0 --discount in percentage.
creature.isLoot = false

dmhub.CreateLootComponent = function()
	return loot.new{}
end

--quantity of this item not explicitly placed into slots.
function loot.UnslottedQuantity(self, itemid)
	local entry = self:try_get("inventory", {})[itemid]
	if entry == nil then
		return 0
	end
	local quantity = entry.quantity
	for _,info in ipairs(entry.slots or {}) do
		if info.quantity ~= nil then
			quantity = quantity - info.quantity
		end
	end

	return quantity
	
end

creature.UnslottedQuantity = loot.UnslottedQuantity

--Get the quantity of items in a slot. If there is 'excess quantity' of an item
--then it will be assumed to be in this slot.
function loot.QuantityInSlot(self, itemid, slot)
	local entry = self:try_get("inventory", {})[itemid]
	if entry == nil then
		return 0
	end
	local quantity = entry.quantity
	local haveUnassignedSlot = false
	for _,info in ipairs(entry.slots or {}) do
		if info.slot == slot and info.quantity ~= nil then
			return info.quantity
		elseif info.slot ~= slot and info.quantity == nil then
			--there is an unassigned slot and it's not the slot we're looking at.
			--it will consume any excess quantity for this item.
			haveUnassignedSlot = true
		end
	end

	if haveUnassignedSlot then
		return 0
	end

	return self:UnslottedQuantity(itemid)
end

creature.QuantityInSlot = loot.QuantityInSlot

function loot.RemoveInventorySlot(self, itemid, slot)
	local entry = self:try_get("inventory", {})[itemid]
	if entry == nil then
		return 0
	end
	for i,info in ipairs(entry.slots or {}) do
		if info.slot == slot then
			table.remove(entry.slots, i)
			return
		end
	end
end

creature.RemoveInventorySlot = loot.RemoveInventorySlot

function loot.GetDefaultInventorySlotForItem(self, itemid, defaultSlot)
	local entry = self:try_get("inventory", {})[itemid]
	if entry ~= nil then
		--search for the default slot for this item, or use a quantity-specified slot otherwise.
		for i,info in ipairs(entry.slots or {}) do
			if info.quantity == nil then
				return entry.slot
			else
				defaultSlot = entry.slot
			end
		end
	end

	if defaultSlot == nil then
		--do a full search of taken slots and find a slot to put this item into.
		local takenSlots = {}
		for _,item in pairs(self:try_get("inventory", {})) do
			for _,slot in ipairs(item.slots or {}) do
				takenSlots[slot.slot] = true
			end
		end

		for i=1,1000 do
			if not takenSlots[i] then
				return i
			end
		end
	end

	return math.max(defaultSlot or 1, 1)
end

creature.GetDefaultInventorySlotForItem = loot.GetDefaultInventorySlotForItem

--Move items from one slot to another in inventory. Note this does NOT displace items in the destination.
--you should be sure to do that also.
--@itemid: string: represents the current itemid
--@srcslot: number: the index of the slot to move from
--@dstslot: number: the index of the slot to move to
--@minQuantity: number?: the minimum amount to move. Source it from elsewhere if it's not in srcslot.
function loot.RearrangeInventory(self, itemid, srcslot, dstslot, minQuantity)
	if srcslot == dstslot then
		return
	end

	local entry = self:try_get("inventory", {})[itemid]
	if entry == nil then
		return
	end


	for _,info in ipairs(entry.slots or {}) do
		if info.slot == dstslot then
			--the source and dest slots both have the same item, so merge them.
			info.quantity = self:QuantityInSlot(itemid, dstslot) + self:QuantityInSlot(itemid, srcslot)
			self:RemoveInventorySlot(itemid, srcslot)
			return
		end
	end
	for i,info in ipairs(entry.slots or {}) do
		if info.slot == srcslot then
			info.slot = dstslot
			return
		end
	end


	--we don't have any existing inventory arrangement, so moved from unassigned allotment.
	local quantity = self:QuantityInSlot(itemid, srcslot)
	if quantity > 0 and (minQuantity == nil or quantity >= minQuantity) then
		self:SetDefaultInventorySlotForItem(itemid, dstslot)
	elseif minQuantity ~= nil then
		--we failed to find the expected quantity of items. This likely means the inventory is
		--invalid in some way, so let's just move all items to the new slot.
		entry.slots = {
			{
				--one new default slot which will contain all of this item.
				slot = dstslot,
			}
		}
	end
end
creature.RearrangeInventory = loot.RearrangeInventory

function loot.MergeInventoryStack(self, itemid, slot)
	local entry = self:try_get("inventory", {})[itemid]
	if entry == nil then
		return
	end
	
	entry.slots = {
		{
			slot = slot,
		}
	}
end
creature.MergeInventoryStack = loot.MergeInventoryStack




--splits an inventory stack into a new slot. The new slot is assumed to be empty.
function loot.SplitInventory(self, itemid, srcslot, dstslot, quantity)
	if srcslot == dstslot then
		return
	end

	local entry = self:try_get("inventory", {})[itemid]
	if entry == nil then
		return
	end

	local available = self:QuantityInSlot(itemid, srcslot)
	if quantity >= available then
		--moving the whole thing.
		self:RearrangeInventory(itemid, srcslot, dstslot)
		return
	end

	if available < quantity then
		quantity = available
	end

	if quantity <= 0 then
		return
	end

	entry.slots = entry.slots or {}

	--deduct from the existing slot
	for _,slot in ipairs(entry.slots) do
		if slot.slot == srcslot and slot.quantity ~= nil then
			slot.quantity = slot.quantity - quantity
		end
	end

	--create the new slot.
	entry.slots[#entry.slots+1] = {
		slot = dstslot,
		quantity = quantity,
	}
end

creature.SplitInventory = loot.SplitInventory

function loot.SetDefaultInventorySlotForItem(self, itemid, slot)
	local entry = self:try_get("inventory", {})[itemid]
	if entry == nil then
		return
	end
	
	for i,info in ipairs(entry.slots or {}) do
		if info.quantity == nil then
			info.slot = slot
			return
		end
	end

	entry.slots = entry.slots or {}
	entry.slots[#entry.slots+1] = {
		slot = slot
	}
end

creature.SetDefaultInventorySlotForItem = loot.SetDefaultInventorySlotForItem

function loot.EnsureInventorySlots(self, itemid)
	local entry = self:try_get("inventory", {})[itemid]
	if entry == nil then
		return
	end

	local quantity = entry.quantity
	for i,info in ipairs(entry.slots or {}) do
		if info.quantity ~= nil then
			quantity = quantity - info.quantity
		end
	end

	if quantity < 0 then
		local deletes = {}
		for i = #entry.slots, 1, -1 do
			local info = entry.slots[i]
			if quantity < 0 then
				if info.quantity ~= nil then
					local newQuantity = info.quantity
					info.quantity = info.quantity + quantity
					quantity = quantity + newQuantity
				end
			end

			if info.quantity <= 0 then
				deletes[#deletes+1] = i
			end
		end

		if quantity <= 0 then
			entry.slots = nil
		else
			for _,d in ipairs(deletes) do
				table.remove(entry.slots, d)
			end
		end

	end

	if entry.slots ~= nil then
		--get rid of any unused entries.
		local deletes = {}
		for i = #entry.slots, 1, -1 do
			local info = entry.slots[i]
			if (info.quantity ~= nil and info.quantity <= 0) or (info.quantity == nil and self:UnslottedQuantity(itemid) <= 0) then
				deletes[#deletes+1] = i
			end
		end
		for _,d in ipairs(deletes) do
			table.remove(entry.slots, d)
		end
	end
end

creature.EnsureInventorySlots = loot.EnsureInventorySlots

function loot.GetItemQuantity(self, itemid)
	local entry = self:try_get("inventory", {})[itemid]
	if entry == nil then
		return 0
	end
	
	return entry.quantity
end

creature.GetItemQuantity = loot.GetItemQuantity

function loot:Empty()
	for k,entry in pairs(self:try_get('inventory', {})) do
		if entry.quantity > 0 then
			return false
		end
	end
	
	local currencyTable = self:try_get("currency", {})
	for k,entry in pairs(currencyTable) do
		if entry.value > 0 then
			return false
		end
	end


	return true
end

function loot:GetCurrency(currencyid)
	return creature.GetCurrency(self, currencyid)
end

function loot:SetCurrency(currencyid, value, note)
	creature.SetCurrency(self, currencyid, value, note)
end

function loot.GiveItem(self, itemid, quantity, slotIndex)
	if slotIndex == nil then
		slotIndex = self:GetDefaultInventorySlotForItem(itemid)
	end
	local currentQuantity = self:GetItemQuantity(itemid)
	self:SetItemQuantity(itemid, currentQuantity + quantity, slotIndex)
end

function creature.GiveItem(self, itemid, quantity, slotIndex)
	if quantity < 0 and -quantity > creature.GetItemQuantity(self, itemid) then
		--don't have enough items so see if we can unequip.
		local diff = -quantity - creature.GetItemQuantity(self, itemid)

		--we iterate over equipment trying to search for this item equipped and unequip it.
		local slotsVisited = {}
		local found = true
		while diff > 0 and found do
			found = false

			--get equipment but order it so all main slots come before offhand slots, so we can completely discard out of
			--one before moving onto the other hand. This makes things work well if we have an item duplicated in a hand.
			local equipment = {}
			for slotid,equipid in pairs(self:Equipment()) do
				equipment[#equipment+1] = {slotid=slotid,equipid=equipid, ord = cond(creature.EquipmentSlots[slotid].main, 1, 0)}
			end

			table.sort(equipment, function(a,b) return a.ord < b.ord end)

			for i,entry in ipairs(equipment) do
				local slotid = entry.slotid
				local equipid = entry.equipid

				if slotsVisited[slotid] == nil and equipid == itemid then
					slotsVisited[slotid] = true
					self:Unequip(slotid)
					diff = -quantity - creature.GetItemQuantity(self, itemid)
					found = true
					break
				end
			end
		end

		for slotid,v in pairs(slotsVisited) do
			self:SetEquipmentShadowInSlot(slotid, itemid) --set the item as a shadow item in the slot so it will be used in future if we pick a new one up.
		end
	end

	if quantity > 0 then
		local anim = self:GetOrAddAnimation{
			animType = "giveItem",
			items = {},
		}

		anim.items[itemid] = quantity


		--if we have shadow slots in our loadouts then fill them if this equipment matches.
		local mainSlots = nil
		local offSlots = nil
		for k,metaInfo in pairs(self:EquipmentMeta()) do
			if metaInfo.shadow == itemid and self:Equipment()[k] == nil then
				if creature.EquipmentSlots[k].main then
					if mainSlots == nil then
						mainSlots = {}
					end
					mainSlots[#mainSlots+1] = k
				else
					if offSlots == nil then
						offSlots = {}
					end
					offSlots[#offSlots+1] = k
				end

			end
		end

		if quantity > 0 and mainSlots ~= nil then
			quantity = quantity-1
			local share = nil
			if #mainSlots > 1 then
				share = dmhub.GenerateGuid()
			end

			for _,key in ipairs(mainSlots) do
				self:EquipmentMetaSlot(key).share = share
			end

			for _,key in ipairs(mainSlots) do
				self:Equipment()[key] = itemid
			end
		end

		if quantity > 0 and offSlots ~= nil then
			quantity = quantity-1
			local share = nil
			if #offSlots > 1 then
				share = dmhub.GenerateGuid()
			end

			for _,key in ipairs(offSlots) do
				self:EquipmentMetaSlot(key).share = share
			end

			for _,key in ipairs(offSlots) do
				self:Equipment()[key] = itemid
			end
		end

	end

	loot.GiveItem(self, itemid, quantity, slotIndex)
end

function loot:SetItemQuantity(itemid, quantity, slotIndex)
	self.inventory = self:try_get('inventory', {})

	if quantity == nil or quantity <= 0 then
		self.inventory[itemid] = nil
	else
		if self.inventory[itemid] == nil then
			self.inventory[itemid] = { quantity = quantity }
		else
			local entry = self.inventory[itemid]
			local delta = quantity - entry.quantity
			entry.quantity = quantity

			if slotIndex ~= nil then
				for _,slot in ipairs(self.inventory[itemid].slots or {}) do
					if slot.slot == slotIndex and slot.quantity ~= nil then
						slot.quantity = slot.quantity + delta
					end
				end
			end
		end
	end
	self:EnsureInventorySlots(itemid)
end

function loot:GetItemPrice(itemid)
	local inventory = self:try_get("inventory", {})
	local entry = inventory[itemid]
	local result = nil
	if entry ~= nil and entry.price ~= nil then
		if type(entry.price) == "number" then
			result = Currency.CalculateSpend(nil, entry.price)
		else
			result = entry.price
		end
	end

	if result == nil then
		local gearTable = dmhub.GetTable('tbl_Gear')
		local item = gearTable[itemid]
		if item ~= nil then
			result = item:GetCurrencyCost()
		end
	end

	if self.isLoot and type(result) == "table" then

		local builtinDiscount = 0
		if result.discount ~= nil then
			builtinDiscount = result.discount
			result = DeepCopy(result)
			result.discount = nil
		end

		if self.discount ~= builtinDiscount then
			local price = Currency.EntryToNumber(result)

			if builtinDiscount < 100 then
				local multiplier = (1 - self.discount*0.01)/(1 - builtinDiscount*0.01)
				price = price * multiplier
				result = Currency.CalculateSpend(nil, price)
			end
		end
	end

	return result
end

creature.GetItemPrice = loot.GetItemPrice

function loot:SetItemPrice(itemid, price)
	self.inventory = self:try_get('inventory', {})
	if type(price) == "table" and self.discount ~= 0 then
		price.discount = self.discount
	end
	if self.inventory[itemid] ~= nil then
		self.inventory[itemid].price = price
	end
end

function creature:SetItemPrice(itemid, price)
end

--do a validation check on inventory. Make sure there aren't overloaded slots in the inventory.
function loot.ValidateInventory(self, makeChanges)
	local result = true
	local slotsSeen = {}
	for itemid,entry in pairs(self:try_get("inventory", {})) do
		for _,info in ipairs(entry.slots or {}) do
			if slotsSeen[info.slot] then
				result = false

				if makeChanges then
					--this is invalid as it uses a used up slot. Remove this item's slots altogether.
					entry.slots = nil
				end

				break
			end

			slotsSeen[info.slot] = true
		end
	end

	return result
end

function loot.SanitizeInventory(self)

	local inventoryValid = loot.ValidateInventory(self)
	if not inventoryValid then
		self:BeginInventorySanitize()
		loot.ValidateInventory(self, true)
		self:CompleteInventorySanitize()
	end

	local gearTable = dmhub.GetTable('tbl_Gear')
	local inventory = self:try_get("inventory", {})

	local deletes = nil
	for k,v in pairs(inventory) do
		if gearTable[k] == nil then
			deletes = deletes or {}
			deletes[#deletes+1] = k
		elseif v.slots ~= nil then
			for i,slotEntry in ipairs(v.slots) do
				if slotEntry.slot == nil then
					deletes = deletes or {}
					deletes[#deletes+1] = {key = k, slotIndex = i}
				end
			end
		end
	end
	
	if deletes == nil then
		return false
	end

	self:BeginInventorySanitize()
	for i=#deletes,1,-1 do
		local k = deletes[i]
		if type(k) == "string" then
			inventory[k] = nil
		else
			local slots = inventory[k.key].slots
			table.remove(slots, k.slotIndex)
		end
	end
	self:CompleteInventorySanitize()

	return true
end

creature.SanitizeInventory = loot.SanitizeInventory

function loot:BeginInventorySanitize()
end

function loot:CompleteInventorySanitize()
end

function creature:BeginInventorySanitize()
	local tok = dmhub.LookupToken(self)
	if tok ~= nil then
		tok:BeginChanges()
	end
end

function creature:CompleteInventorySanitize()
	local tok = dmhub.LookupToken(self)
	if tok ~= nil then
		tok:CompleteChanges("Sanitize inventory")
	end
end

function loot.Spawn(self, component)
	if self:has_key("lootTable") then
		self:RollLoot{
			clear = true,
		}

		local gearTable = dmhub.GetTable('tbl_Gear')

		local panels = {}
		for k,entry in pairs(self:try_get('inventory', {})) do
			local itemInfo = gearTable[k]
			if itemInfo ~= nil then
				local icon = itemInfo:GetIcon()
				for i=1,entry.quantity do
					local panel = gui.Panel{
						styles = {
							{
								brightness = 5,
								opacity = 0,
								scale = 1.5,
								
							},
							{
								classes = {"~fadein"},
								brightness = 1,
								opacity = 1,
								transitionTime = 0.5,
							},
							{
								classes = {"disappear"},
								opacity = 0,
								transitionTime = 0.35,
								scale = 0.1,
							},
						},
						classes = {"fadein"},
						bgimage = icon,
						bgcolor = "white",
						width = 64,
						height = 64,
						data = {
							ord = math.random(),
							createTime = dmhub.Time() + math.random()*0.2,
						},

						thinkTime = 0.01,

						xy = function(element, x, y)
							element.data.x = x
							element.data.y = y

							element:FireEvent("setpos", 80)
						end,

						setpos = function(element, pos)
							element.x = element.data.x * pos
							element.y = element.data.y * pos
						end,

						think = function(element)
							if dmhub.Time() > element.data.createTime then
								element:SetClass("fadein", false)
							end

							local disappearTime = dmhub.Time() - (element.data.createTime + 0.8)

							if disappearTime > 0 then
								element:SetClass("disappear", true)
								element:FireEvent("setpos", 80 - 80*disappearTime*3)
							end
						end,
					}

					panels[#panels+1] = panel
				end
			end
		end

		table.sort(panels, function(a,b) return a.data.ord < b.data.ord end)

		local angle = math.random(0, 360)
		for _,p in ipairs(panels) do
			local x = math.sin(math.rad(angle))
			local y = math.cos(math.rad(angle))

			p:FireEvent("xy", x, y)

			angle = angle + 360/#panels
		end

		local children = GetSheet(component).children
		for _,p in ipairs(panels) do
			children[#children+1] = p
		end

		GetSheet(component).children = children
	end

end

function loot.RollLoot(self, options)
	options = options or {}

	if options.clear ~= false then
		--clear out existing inventory
		local itemKeys = {}

		for k,item in pairs(self.inventory) do
			itemKeys[#itemKeys+1] = k
		end

		for i,k in ipairs(itemKeys) do
			self:SetItemQuantity(k, 0)
		end

		--clear out any currency.
		local currencyTable = dmhub.GetTable(Currency.tableName) or {}
		for currencyid,_ in pairs(currencyTable) do
			self:SetCurrency(currencyid, 0)
		end
	end

	local lootTable = options.lootTable or self:try_get("lootTable", nil)
	if lootTable == nil then
		return
	end

	local dataTable = dmhub.GetTableVisible("lootTables")
	local result = dataTable[lootTable.key]:Roll(lootTable.choiceIndex)

	self.lootTable = lootTable

	for _,item in ipairs(result.items) do
		if item.type == "item" then
			self:GiveItem(item.key, item:RollQuantity())
			if options.newItems ~= nil then
				options.newItems[item.key] = true
			end
		elseif item.type == "currency" then
			for currencyid,roll in pairs(item.value) do
				self:SetCurrency(currencyid, self:GetCurrency(currencyid) + dmhub.RollInstant(roll))
			end
		
		end
	end

end

creature.RollLoot = loot.RollLoot


--- @class ObjectComponentText: GameType
--- A map-object component that displays a text label rendered on the canvas via a game sheet.
ObjectComponentText = RegisterGameType("ObjectComponentText")

dmhub.CreateTextComponent = function()
	return ObjectComponentText.new{}
end

function ObjectComponentText.Update(self, component, sheet)

	if (not self:has_key("_tmp_label")) or (not self._tmp_label.valid) then
		if sheet.sheet == nil then
			sheet.sheet = CreateSheet()
		end

		sheet.sheet:FireEventTree("removeLabel")

		self._tmp_label = gui.Label{
			text = "",
			halign = "center",
			valign = "center",
			width = "auto",
			height = "auto",
			interactable = false,
			pad = 8,
			bgimage = "panels/square.png",
			removeLabel = function(element)
				element:DestroySelf()
			end,
		}


		sheet.sheet:AddChild(self._tmp_label)
	end

	local label = self._tmp_label
	label.text = component.text
	label.selfStyle.fontFace = component.font
	label.selfStyle.fontSize = component.fontSize
	label.selfStyle.color = component.color
	label.selfStyle.bold = component.bold
	label.selfStyle.italics = component.italics
	label.selfStyle.textOutlineWidth = component.outlineWidth
	label.selfStyle.textOutlineColor = component.outlineColor
	label.selfStyle.bgcolor = component.backgroundColor
	label.x = component.xoffset
	label.y = component.yoffset
end

function loot.SpawnDroppedItem(token, itemid, quantity)
	if quantity == nil then
		quantity = 1
	end
	local floor = game.GetFloor(token.floorid)
	local gearTable = dmhub.GetTable('tbl_Gear')
	local itemInfo = gearTable[itemid]
	if floor ~= nil and itemInfo ~= nil then
		--make an instance of the object which is lootable on the map.
		floor:CreateObject{
			asset = {
				description = "Item",
				imageId = dmhub.GetRawImageId(itemInfo.iconid),
				hidden = false,
			},
			components = {
				CORE = {
					["@class"] = "ObjectComponentCore",
					hasShadow = false,
					height = 1,
					pivot_x = 0.5,
					pivot_y = 0.5,
					rotation = 0,
					scale = 0.4,
					sprite_invisible_to_players = false,
				},

				LOOT = {
					["@class"] = "ObjectComponentLoot",
					destroyOnEmpty = true,
					instantLoot = true,
					locked = false,
					properties = {
						__typeName = "loot",
						inventory = {
							[itemid] = {
								quantity = quantity,
							},
						},
					},
				},

			},
			assetid = "none",
			inactive = false,
			pos = {
				x = token.loc.x + 0.5,
				y = token.loc.y - 0.5,
			},

			zorder = 1,
		}
	end
end

function loot.GetInventoryWeight(self)
	local result = 0
	local gearTable = dmhub.GetTable('tbl_Gear')
	local inventory = self:try_get("inventory", {})
	for itemid,info in pairs(inventory) do
		local itemEntry = gearTable[itemid]
		if itemEntry ~= nil then
			result = result + (tonumber(itemEntry.weight) or 0) * (tonumber(info.quantity) or 0)
		end
	end

	local currencies = dmhub.GetTable(Currency.tableName)
	local currencyTable = self:try_get("currency", {})
	for k,entry in pairs(currencyTable) do
		if type(entry.value) == "number" and entry.value > 0 then
			local currencyEntry = currencies[k]
			if currencyEntry ~= nil then
				result = result + entry.value*currencyEntry.weight
			end
		end
	end

	return result
end

function creature:GetInventoryWeight()
	local result = loot.GetInventoryWeight(self)

	local equipment = self:GetEquipmentInAllSlots()

	local gearTable = dmhub.GetTable('tbl_Gear')
	for itemid,quantity in pairs(equipment) do
		local itemEntry = gearTable[itemid]
		if itemEntry ~= nil then
			result = result + (tonumber(itemEntry.weight) or 0) * quantity
		end
	end

	return result
end

function loot:CarryingCapacity()
	return nil
end

function creature:CarryingCapacity()
	return ExecuteGoblinScript("Carrying Capacity", self:LookupSymbol(), 0, "Determine carrying capacity")
end

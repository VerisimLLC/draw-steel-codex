local mod = dmhub.GetModLoading()

--A Variant can currently be text, a currency, an item, or a roll on a table.
--In the future we can add more possibilities.

--- @class VariantValue
--- @field min number Minimum possible value.
--- @field max number Maximum possible value.
--- @field avg number Average (expected) value.
--- Represents a monetary value range (typically in gold) for a loot variant.
VariantValue = RegisterGameType("VariantValue")

VariantValue.min = 0
VariantValue.max = 0
VariantValue.avg = 0

function VariantValue:Add(other)
	if type(other) == "number" then
		self.min = self.min + other
		self.max = self.max + other
		self.avg = self.avg + other
		return
	end

	if type(other) == "string" then
		self.min = self.min + dmhub.RollMinValue(other)
		self.max = self.max + dmhub.RollMaxValue(other)
		self.avg = self.avg + dmhub.RollExpectedValue(other)
		return
	end

	self.min = self.min + other.min
	self.max = self.max + other.max
	self.avg = self.avg + other.avg
end

function VariantValue:Mult(num)
	if type(num) == "string" then
		self.min = self.min * dmhub.RollMinValue(num)
		self.max = self.max * dmhub.RollMaxValue(num)
		self.avg = self.avg * dmhub.RollExpectedValue(num)
		return
	end

	self.min = self.min * num
	self.max = self.max * num
	self.avg = self.avg * num
end


--- @class Variant
--- @field type string Variant content type: "text", "currency", "item", "tableRoll", "resource", "monster".
--- @field quantity number|string Quantity of the item/roll granted (can be a dice expression).
--- @field key nil|string Key into the relevant data table (e.g. item id, monster key).
--- A single entry in a loot table or reward list; represents one possible reward of a given type.
Variant = RegisterGameType("Variant")

Variant.quantity = 1

local quantityTypes = {tableRoll = true, item = true, resource = true, monster = true}
function Variant:HasQuantity()
	return quantityTypes[self.type]
end

function Variant:RollQuantity()
	return dmhub.RollInstant(self.quantity)
end

function Variant:Value()
	local result = VariantValue.new{}
	if self.type == "item" then
		local dataTable = dmhub.GetTable("tbl_Gear") or {}
		local item = dataTable[self.key]
		if item ~= nil then
			result:Add(item:GetCostInGold())
		end
	elseif self.type == "monster" then
		local monster = assets.monsters[self.key]
		if monster ~= nil then
			result:Add(monster.properties:try_get("cr", 0))
		end
	elseif self.type == "resource" then
		--resources don't have monetary value.
	elseif self.type == "currency" then
		local currencyTable = dmhub.GetTable(Currency.tableName)
		for k,v in pairs(self.value) do
			local currency = currencyTable[k]
			if currency ~= nil and (not currency.hidden) then
				local tmp = VariantValue.new{}
				tmp:Add(v)
				tmp:Mult(currency:UnitValue())
				result:Add(tmp)
			end
		end
	elseif self.type == "tableRoll" then
		local dataTable = dmhub.GetTable(self.dataTable) or {}
		local rollTable = dataTable[self.key]
		if rollTable ~= nil then
			result:Add(rollTable:CalculateValue())
		end
	end
	
	result:Mult(self.quantity)

	return result
end

function Variant:TableRef()
    if self.type == "tableRoll" then
        return RollTableReference.CreateRef(self.dataTable, self.key)
    else
        return nil
    end
end

function Variant:TableName()
	if self.type == "currency" then
		return Currency.tableName
	elseif self.type == "resource" then
		return CharacterResource.tableName
	elseif self.type == "item" then
		return "tbl_Gear"
	else
		return nil
	end
end

function Variant:ToString()
	if self.type == "text" then
		return self.value
	elseif self.type == "tableRoll" then
		local dataTable = dmhub.GetTable(self.dataTable) or {}
		local rollTable = dataTable[self.key]
		if rollTable == nil then
			return ""
		end

		if self:has_key("choiceIndex") then
			return string.format("%s - %s", rollTable.name, rollTable:RowName(self.choiceIndex))
		else
			return rollTable.name
		end
	elseif self.type == "item" or self.type == "resource" then
		local dataTable = dmhub.GetTable(self:TableName()) or {}
		local item = dataTable[self.key]
		if item == nil then
			return ""
		end

		return item.name
	elseif self.type == "monster" then
		local monster = assets.monsters[self.key]
		if monster == nil then
			return ""
		end

		return monster.description
	else
		return ""
	end
end

function Variant.CreateText(str)
	return Variant.new{
		type = "text",
		value = string.gsub(str, "\r", ""),
	}
end

function Variant.CreateCurrency()
	return Variant.new{
		type = "currency",
		value = {}, --map of currencyid -> quantity
	}
end

function Variant.CreateTableRoll(dataTable, key, choiceIndex)
	return Variant.new{
		type = "tableRoll",
		dataTable = dataTable,
		key = key,
		choiceIndex = choiceIndex,
	}
end

--an inventory item.
function Variant.CreateItem(key)
	return Variant.new{
		type = "item",
		key = key,
	}
end

--a character resource
function Variant.CreateResource(key)
	return Variant.new{
		type = "resource",
		key = key,
	}
end

--a monster.
function Variant.CreateMonster(key)
	return Variant.new{
		type = "monster",
		key = key,
	}
end

function Variant:CreateTextEditor(value, options)
	local label
	local change = options.change
	options.change = nil
	local args = {
		text = value.value,
		editable = true,
		change = function(element)
			value.value = element.text
			if change ~= nil then
				change(element)
			end
		end,
	}
	for k,v in pairs(options) do
		args[k] = v
	end

	label = gui.Label(args)
	return label
end

function Variant:CreateTableRollEditor(value, options)
	local dataTable = dmhub.GetTable(value.dataTable) or {}
	local rollTable = dataTable[value.key]
	if rollTable == nil then
		return nil
	end

	local text
	if rollTable:IsChoice() then
		local index = value:try_get("choiceIndex", 1)
		if rollTable.rows[index] == nil then
			index = 1
		end
		if rollTable.rows[index] == nil then
			text = string.format("Empty table %s", rollTable.name)
		else
			text = string.format("%s - %s", rollTable.name, rollTable:RowName(index))
		end
	else
		text = string.format("Roll on %s", rollTable.name)
	end

	local label
	local args = {
		text = text
	}
	for k,v in pairs(options) do
		args[k] = v
	end

	label = gui.Label(args)
	return label

end

function Variant:CreateMonsterEditor(value, options)
	local monster = assets.monsters[value.key]
	if monster == nil then
		return nil
	end

	local label
	local args = {
		text = string.format("%s", monster.description),
		color = "white",
		hover = function(element)
			local panel = monster:Render{ width = 800 }

			if panel ~= nil then
				element.tooltip = gui.TooltipFrame(
					panel,
					{
						halign = "right",
						valign = "center",
					}
				)

			end
		end,
	}
	for k,v in pairs(options) do
		args[k] = v
	end

	label = gui.Label(args)
	return label

end

function Variant:CreateResourceEditor(value, options)
	local dataTable = dmhub.GetTable(CharacterResource.tableName) or {}
	local resource = dataTable[value.key]
	if resource == nil then
		return nil
	end

	local label
	local args = {
		text = string.format("%s", resource.name),
		color = "white",
	}
	for k,v in pairs(options) do
		args[k] = v
	end

	label = gui.Label(args)
	return label

end

function Variant:CreateItemEditor(value, options)
	local dataTable = dmhub.GetTable('tbl_Gear') or {}
	local item = dataTable[value.key]
	if item == nil then
		return nil
	end

	local label
	local args = {
		text = string.format("%s", item.name),
		color = equipment.rarityColors[item:try_get("rarity", "common")] or "white",
		hover = function(element)
			element.tooltip = CreateItemTooltip(item, {halign = "right"}, nil)
		end,
	}
	for k,v in pairs(options) do
		args[k] = v
	end

	label = gui.Label(args)
	return label

end

function Variant:CreateCurrencyEditor(value, options)
	local resultPanel

	local children = {}

	local currencyTable = dmhub.GetTable(Currency.tableName) or {}

	--mapping of currency id of standard -> list of currencies using this standard.
	local currencyStandards = Currency.MonetaryStandards()

	for standardKey,currencyList in pairs(currencyStandards) do
		for i,currency in ipairs(currencyList) do
			children[#children+1] = gui.Panel{
				bgimage = currency.iconid,
				bgcolor = "white",
				valign = "center",
				width = 20,
				height = 20,
			}

			children[#children+1] = gui.Label{
				characterLimit = 12,
				width = "auto",
				height = "auto",
				valign = "center",
				editable = true,
				fontSize = 14,
				text = self.value[currency.id] or "0",
				change = function(element)
					local text = dmhub.NormalizeRoll(element.text)
					if text == "" then
						text = "0"
					end
					self.value[currency.id] = text

					element.text = self.value[currency.id] or "0"
					resultPanel:FireEvent("change")
				end,
				
			}
		end
	end

	local args = {
		width = "auto",
		height = "auto",
		flow = "horizontal",
		children = children,
	}
	for k,v in pairs(options) do
		args[k] = v
	end

	resultPanel = gui.Panel(args)
	return resultPanel
	
end


function Variant:CreateEditor(options)
	local value = options.value
	options.value = nil

	local resultPanel
	local childElement = nil

	if value.type == "text" then
		childElement = self:CreateTextEditor(value, options)
	elseif value.type == "tableRoll" then
		childElement = self:CreateTableRollEditor(value, options)
	elseif value.type == "item" then
		childElement = self:CreateItemEditor(value, options)
	elseif value.type == "resource" then
		childElement = self:CreateResourceEditor(value, options)
	elseif value.type == "monster" then
		childElement = self:CreateMonsterEditor(value, options)
	elseif value.type == "currency" then
		childElement = self:CreateCurrencyEditor(value, options)
	end

	local quantityLabel = nil
	if value:HasQuantity() then
		quantityLabel = gui.Panel{
			flow = "horizontal",
			width = "auto",
			height = "auto",
			pad = 3,

			gui.Label{
				pad = 0,
				width = "auto",
				height = "auto",
				color = "#ffffff88",
				text = "x",
			},

			gui.Label{
				pad = 0,
				bold = true,
				width = "auto",
				height = "auto",
				color = "#ffffffbb",
				editable = true,
				text = tostring(value.quantity),
				change = function(element)
					local quantity = tonumber(element.text)
					if quantity == nil then
						if dmhub.RollExpectedValue(element.text) ~= 0 then
							quantity = element.text
						else
							quantity = value.quantity
						end
					end

					if type(quantity) == "number" then
						if quantity <= 0 then
							resultPanel:FireEvent("delete")
							return
						elseif quantity > 999 then
							quantity = 999
						end
					end

					value.quantity = quantity
					resultPanel:FireEvent("rebuild")
					resultPanel:FireEvent("change")
				end,

			},

		}
	end

	local args = {
		bgimage = "panels/square.png",
		opacity = 0,
		width = "auto",
		height = "auto",
		flow = "horizontal",
		children = {
			childElement,
			quantityLabel,
			gui.DeleteItemButton{

				width = 16,
				height = 16,
				halign = "right",
				valign = "center",
				click = function(element)
					resultPanel:FireEvent("delete")
				end,
			}
		}
	}

	for k,v in pairs(options) do
		args[k] = v
	end

	resultPanel = gui.Panel(args)
	return resultPanel
end

--- @class VariantCollection
--- @field items Variant[] Ordered list of Variant entries in this collection.
--- An ordered list of Variant entries, typically representing a loot table or reward set.
VariantCollection = RegisterGameType("VariantCollection")

function VariantCollection.Create()
	return VariantCollection.new{
		items = {}
	}
end

function VariantCollection:ToString()
	return self:JoinString(",")
end

function VariantCollection:JoinString(delimiter)
	if delimiter == nil then
		delimiter = ""
	end

	local result = ""
	for i,item in ipairs(self.items) do
		if i ~= 1 then
			result = result .. delimiter
		end

		local str = item:ToString()
		result = result .. str
		if item:HasQuantity() and item.quantity > 1 then
			result = string.format("%s x %d", result, item.quantity)
		end
	end

	return result
end

function VariantCollection:Value()
	local result = VariantValue.new{}
	
	for _,item in ipairs(self.items) do
		result:Add(item:Value())
	end

	return result
end

function VariantCollection:Add(variant)
	self.items[#self.items+1] = variant
end

function VariantCollection:Empty()
	return #self.items == 0
end

local ShowChoiceDialog = function(argOptions)
	local options = argOptions
	local rootPanel = options.root

	if rootPanel.data.choiceDialog == nil then
		local blockingPanel --the actual panel returned, which blocks UI interaction
		local dialogPanel

		local items = {}

		local clickAllButton = nil
		if options.clickAll ~= nil then
			clickAllButton = gui.PrettyButton{
				width = 200,
				height = 40,
				halign = "center",
				text = "Add All",
				click = function(element)
					local optionsChosen = {}
					for _,item in ipairs(items) do
						if not item:HasClass("collapsed") then
							optionsChosen[#optionsChosen+1] = item.data.option
						end
					end

					options.clickAll(optionsChosen)
					blockingPanel:SetClass("hidden", true)
				end,
			}
		end

		local checksPanel = nil
		checksPanel = gui.Panel{
			width = "80%",
			height = "auto",
			halign = "center",
			flow = "vertical",
			setData = function(element, options)

				local checkboxes = options.checkboxes or {}
				local checks = {}
				for _,checkbox in ipairs(checkboxes) do
					checks[#checks+1] = gui.Check{
						width = 300,
						height = 20,
						fontSize = 14,
						halign = "left",
						text = checkbox.text,
						value = checkbox.value,
						change = function(element)
							checkbox.value = element.value
							if type(checkbox.change) == "function" then
								checkbox.change(element.value)
							end
						end,
					}
				end

				element.children = checks
			end,
		}


		dialogPanel = gui.Panel{
			classes = {'framedPanel'},
			styles = Styles.Panel,

			width = 700,
			height = 800,
			valign = "center",
			halign = "center",
			flow = "vertical",

			setData = function(element, newOptions)
				options = newOptions
			end,

			clickaway = function(element)
				blockingPanel:SetClass("hidden", true)
			end,
			escape = function(element)
				blockingPanel:SetClass("hidden", true)
			end,

			captureEscape = true,
			escapePriority = EscapePriority.EXIT_MODAL_DIALOG,


			gui.DialogBorder{},

			gui.Panel{
				width = "84%",
				halign = "center",
				height = 600,
				vscroll = true,
				valign = "center",
				
				gui.Table{
					styles = {
						{
							selectors = {"optionLabel"},
							fontSize = 14,
							hpad = 8,
							textAlignment = "left",
							color = "white",
						},
						{
							selectors = {"row"},
							width = "auto",
							height = "auto",
							bgimage = "panels/square.png",
						},
						{
							selectors = {"evenRow"},
							bgcolor = "#00000088",
						},
						{
							selectors = {"oddRow"},
							bgcolor = "#000000cc",
						},
						{
							selectors = {"row", "hover"},
							bgcolor = "#880000ff",
						},
						{
							selectors = {"row", "press"},
							bgcolor = "#220000ff",
						},
					},
					flow = "vertical",
					width = "80%",
					height = "auto",
					halign = "center",
					valign = "top",
					setData = function(element, options)

						for i,newOption in ipairs(options.options) do
							local option = newOption
							items[i] = items[i] or gui.TableRow{
								data = {
									option = option
								},

								gui.Label{
									classes = {"optionLabel"},
									width = "auto",
									height = "auto",
									text = option.text,
									color = option.color or "white",
								},

								bgimage = "panels/square.png",

								setData = function(element, options)
									local newOption = options.options[i]
									option = newOption
									if option == nil then
										return
									end

									local children = element.children
									local numChildren = 1

									children[1].text = option.text

									if option.data ~= nil then
										numChildren = 1 + #option.data
										for i,item in ipairs(option.data) do
											children[i+1] = children[i+1] or gui.Label{
												classes = {"optionLabel"},
												width = "auto",
												height = "auto",
											}

											children[i+1].text = item
										end
									end

									for i,child in ipairs(children) do
										child:SetClass("collapsed", i > numChildren)
									end

									element.children = children
								end,


								click = function(element)
									option.click()
									blockingPanel:SetClass("hidden", true)
								end,
								hover = option.hover,
								search = function(element, terms)
									if option == nil then return end
									if terms == nil then
										element:SetClass("collapsed", false)
										return
									end
									for _,term in ipairs(terms) do
										if not string.find(string.lower(option.text), term) then
											local matchData = false
											for _,dataItem in ipairs(option.data or {}) do
												if string.starts_with(string.gsub(string.lower(dataItem), "<.*>", ""), term) then
													matchData = true
												end
											end

											if not matchData then
												element:SetClass("collapsed", true)
												return
											end
										end
									end

									element:SetClass("collapsed", false)
								end,
							}

							local item = items[i]
							item.data.option = option
						end

						for i,item in ipairs(items) do
							item:SetClass("collapsed", i > #options.options)
						end

						element.children = items
					end,
				},
			},

			checksPanel,

			gui.Input{
				halign = "left",
				valign = "center",
				hmargin = 20,
				placeholderText = "Search...",
				width = 180,
				height = 20,
				fontSize = 16,
				editlag = 0.25,
				edit = function(element)
					dialogPanel:FireEventTree("search", string.split(string.lower(element.text)))
				end,
				setData = function(element, options)
					element.text = ""
				end,
			},

			clickAllButton,
		}

		blockingPanel = gui.Panel{
			width = "100%",
			height = "100%",
			opacity = 0,
			bgimage = "panels/square.png",
			dialogPanel,
			setData = function(element, options)
				element:SetClass("hidden", false)
			end,
			data = {
				dialogPanel = dialogPanel
			},
		}

		rootPanel.data.choiceDialog = blockingPanel
		rootPanel:AddChild(blockingPanel)
	end


	rootPanel.data.choiceDialog:FireEventTree("setData", options)

end

function ShowRollableTableSelectionDialog(args)

	local tableName = args.tableName
	local dataTable = dmhub.GetTableVisible(tableName)
	if dataTable == nil then
		return
	end


	local options = {}

	for k,v in pairs(dataTable) do
		if v:try_get("subtable", false) and (not args.showSubtables) then
			--subtables aren't shown so don't present this choice.
		elseif v:IsChoice() then
			for rowIndex,row in ipairs(v.rows) do
				local choiceText = cond(v.rollType == "namedChoice", row:try_get("choiceName", tostring(rowIndex)), tostring(rowIndex))
				local optionInfo
				optionInfo = {
					key = k,
					choiceIndex = rowIndex,
					text = string.format("%s - %s", v.name, choiceText),
					click = function(element)
						args.click(element, { optionInfo })
					end,
				}
				options[#options+1] = optionInfo
			end
		else
			options[#options+1] = {
				text = v.name,
				click = function(element)
					args.click(element, {{ key = k }} )
				end,
			}
		end
	end
	table.sort(options, function(a,b) return a.text < b.text end)
	ShowChoiceDialog{
		checkboxes = args.checkboxes,
		root = args.root,
		options = options,
		--clickAll = function(chosenOptions)
		--	args.click(element, chosenOptions)
		--end,
	}
	
end


function gui.VariantCollectionEditor(args)
	local value = args.value
	args.value = nil

	local variantType = args.variantType
	args.variantType = nil



	local resultPanel

	local panelArgs = {
		flow = "horizontal",
		wrap = true,
		width = 500,
		height = "auto",
		data = {
			GetAddItemOptions = function(element)

				local items = {}

				if variantType.items then
					--currency.
					items[#items+1] = {
						text = "Currency",
						click = function()
							value:Add(Variant.CreateCurrency())
							resultPanel:FireEvent("rebuild")
							resultPanel:FireEvent("change")
							element.popup = nil
						end,
					}

					--resources.

					local chooseResources = function()
						local options = {}
						local dataTable = dmhub.GetTable(CharacterResource.tableName)
						for k,item in pairs(dataTable) do
							options[#options+1] = {
								text = item.name,
								key = k,
								click = function(element)
									value:Add(Variant.CreateResource(k))
									resultPanel:FireEvent("rebuild")
									resultPanel:FireEvent("change")
								end,
							}

						end
						table.sort(options, function(a,b) return a.text < b.text end)

						ShowChoiceDialog{
							root = element.root,
							options = options,
							clickAll = function(chosenOptions)
								for _,option in ipairs(chosenOptions) do
									value:Add(Variant.CreateResource(option.key))
								end
								resultPanel:FireEvent("rebuild")
								resultPanel:FireEvent("change")
							end,
						}
						element.popup = nil
					end

					items[#items+1] = {
						text = "Resource",
						click = function()
							chooseResources()
						end,
					}

					--monsters.
					local chooseMonsters = function()
						local options = {}
						local dataTable = assets.monsters
						for k,item in pairs(dataTable) do
							if item.description ~= nil then
								options[#options+1] = {
									text = item.description,
									key = k,
									click = function(element)
										value:Add(Variant.CreateMonster(k))
										resultPanel:FireEvent("rebuild")
										resultPanel:FireEvent("change")
									end,
								}
							end

						end
						table.sort(options, function(a,b) return a.text < b.text end)

						ShowChoiceDialog{
							root = element.root,
							options = options,
							clickAll = function(chosenOptions)
								for _,option in ipairs(chosenOptions) do
									value:Add(Variant.CreateMonster(option.key))
								end
								resultPanel:FireEvent("rebuild")
								resultPanel:FireEvent("change")
							end,
						}
						element.popup = nil
					end

					items[#items+1] = {
						text = "Monster",
						click = function()
							chooseMonsters()
						end,
					}

					--inventory items.
					local chooseItems = function(magical)

						local options = {}
						local dataTable = dmhub.GetTable('tbl_Gear')
						for k,item in pairs(dataTable) do
							if (not item.unique) and (not item:has_key("hidden")) and item:has_key("magicalItem") == magical then
								local data = nil
								if magical then
									data = {string.format("<color=%s>%s", item:RarityColor(), item:Rarity())}
								end

								data = (data or {})
								local cost = item:GetCostInGold()
								if cost == math.floor(cost) then
									cost = string.format("%dgp", cost)
								else
									cost = string.format("%.2f", cost)
								end
									
								data[#data+1] = cost
								options[#options+1] = {
									text = item.name,
									color = item:RarityColor(),
									data = data,
									key = k,
									click = function(element)
										value:Add(Variant.CreateItem(k))
										resultPanel:FireEvent("rebuild")
										resultPanel:FireEvent("change")
									end,

									hover = function(element)
										element.tooltip = CreateItemTooltip(item, {halign = "right"}, nil)
									end,
								}
								
							end
						end
						table.sort(options, function(a,b) return a.text < b.text end)

						ShowChoiceDialog{
							root = element.root,
							options = options,
							clickAll = function(chosenOptions)
								for _,option in ipairs(chosenOptions) do
									value:Add(Variant.CreateItem(option.key))
								end
								resultPanel:FireEvent("rebuild")
								resultPanel:FireEvent("change")
							end,
						}
						element.popup = nil

					end
					items[#items+1] = {
						text = "Mundane Item",
						click = function()
							chooseItems(false)
						end,
					}
					items[#items+1] = {
						text = "Magical Item",
						click = function()
							chooseItems(true)
						end,
					}

				end

				if variantType.tables ~= nil then
					for _,tableName in ipairs(variantType.tables) do
						local dataTable = dmhub.GetTable(tableName)
						if dataTable ~= nil then

							items[#items+1] = {
								text = string.format("Roll on a %s table", tableName),
								click = function()
									ShowRollableTableSelectionDialog{
										showSubtables = true,
										root = element.root,
										tableName = tableName,
										click = function(element, items)
											for _,item in ipairs(items) do
												value:Add(Variant.CreateTableRoll(tableName, item.key, item.choiceIndex))
											end
											resultPanel:FireEvent("rebuild")
											resultPanel:FireEvent("change")
										end,
									}

									element.popup = nil
								end,
							}

						end
					end
				end

				return items
			end,
		},
		rebuild = function(element)
			local children = {}
			if value:Empty() and variantType.text then
				children[#children+1] = gui.Input{
					classes = {"variantInput"},
					placeholderText = "Enter text...",
					text = "",
					change = function(element)
						if element.text ~= "" then
							value:Add(Variant.CreateText(element.text))
							resultPanel:FireEvent("rebuild")
							resultPanel:FireEvent("change")
						end
					end,
					setinputfocus = function(element)
						element.hasInputFocus = true
					end,
				}
			elseif value:Empty() then
				local options = {
					{
						id = "none",
						text = "Add an Item...",
					}
				}

				--a mapping of equipment category id -> {list of itemids in that category}
				--this ultimately gets filled out recursively so even top-level categories have lists of all leaves.
				local itemCategories = {}

				if variantType.items then
					local dataTable = dmhub.GetTable('tbl_Gear')
					for k,item in pairs(dataTable) do
						if (not item.unique) and (not item:has_key("hidden")) then
							options[#options+1] = {
								id = k,
								text = item.name,
							}

							if (not item:has_key("magicalItem")) and item:has_key("equipmentCategory") then
								--for any non-magical items that have a category we list them in their category.
								local cat = itemCategories[item.equipmentCategory]
								if cat == nil then
									cat = {}
									itemCategories[item.equipmentCategory] = cat
								end
								
								cat[#cat+1] = k
							end
						end
					end

					local categoriesTable = dmhub.GetTable(EquipmentCategory.tableName) or {}

					--recursively add categories.
					local newCategories = {}

					for k,items in pairs(itemCategories) do
						if categoriesTable[k] then
							newCategories[#newCategories+1] = k
						end
					end

					local maxcount = 0
					while #newCategories > 0 and maxcount < 10 do
						maxcount = maxcount + 1
						local nextCategories = {}
						for _,cat in ipairs(newCategories) do
							local catInfo = categoriesTable[cat]

							--if this category has a superset, then add its items to its superset.
							if catInfo:has_key("superset") then
								local itemList = itemCategories[catInfo.superset]
								if itemList == nil then
									itemList = {}
									itemCategories[catInfo.superset] = itemList
								end

								for _,item in ipairs(itemCategories[cat]) do
									itemList[#itemList+1] = item
								end

								nextCategories[#nextCategories+1] = catInfo.superset
							end
						end

						newCategories = nextCategories
					end

					for cat,itemList in pairs(itemCategories) do
						local catInfo = categoriesTable[cat]
						options[#options+1] = {
							id = cat,
							text = string.format("All %s (%d)", catInfo.name, #itemCategories[cat]),
						}
					end
				end

				table.sort(options, function(a,b) return a.text < b.text end)

				local dropdown = gui.Dropdown{
					options = options,
					idChosen = "none",
					hasSearch = true,
					change = function(element)
						if element.idChosen ~= "none" then
							if itemCategories[element.idChosen] ~= nil then
								for _,itemid in ipairs(itemCategories[element.idChosen]) do
									value:Add(Variant.CreateItem(itemid))
								end
							else
								value:Add(Variant.CreateItem(element.idChosen))
							end
							resultPanel:FireEvent("rebuild")
							resultPanel:FireEvent("change")
						end
					end,
				}

				children[#children+1] = dropdown
			end

			for i,item in ipairs(value.items) do
				children[#children+1] = item:CreateEditor{
					value = item,
					change = function(element)
						resultPanel:FireEvent("change")
					end,
					delete = function(element)
						table.remove(value.items, i)
						resultPanel:FireEvent("rebuild")
						element:FireEvent("change")
					end,
				}
			end
			element.children = children
		end,

	}

	for k,v in pairs(args) do
		panelArgs[k] = v
	end

	resultPanel = gui.Panel(panelArgs)


	resultPanel.GetValue = function()
		return value
	end

	resultPanel.SetValue = function(element, val, fireevent)
		value = val
		element:FireEvent("rebuild")
	end

	resultPanel:FireEvent("rebuild")

	return resultPanel
	
end

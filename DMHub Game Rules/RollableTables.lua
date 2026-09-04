local mod = dmhub.GetModLoading()

--either a direct rolltable, or a reference to one.
---@class RollTableReference
---@field tableName string the name of the table this references, or "none" if it's an anonymous table.
---@field key string the key in the table this references, or "none" if it's an anonymous table.
---@field docid string
RollTableReference = RegisterGameType("RollTableReference")

RollTableReference.tableName = "none"
RollTableReference.key = "none"
RollTableReference.docid = false
RollTableReference.tableid = false

function RollTableReference:TryUpload(data)
	if self:has_key("tableName") then
		dmhub.SetAndUploadTableItem(self.tableName, data)
	end
end

function RollTableReference.CreateRef(tableName, key)
	if type(tableName) == "table" then
		return RollTableReference.new{
			table = tableName,
		}
	else
		return RollTableReference.new{
			tableName = tableName,
			key = key,
		}
	end
end

function RollTableReference.CreateDocumentReference(docid, tableid)
    return RollTableReference.new{
        docid = docid,
        tableid = tableid,
    }
end

function RollTableReference.CreateAnonymous()
	return RollTableReference.new{
		table = RollTable.CreateNew(),
	}
end

function RollTableReference:GetTable()

    --a reference to a markdown document.
    if self.docid then
        local t = dmhub.GetTable(CustomDocument.tableName)
        local doc = t[self.docid]
        if doc ~= nil then
            local result = doc:GetRollableTable(self.tableid)
            return result
        end
        return
    end

	if self:has_key("table") then
		return self.table
	end

	local dataTable = dmhub.GetTable(self.tableName) or {}
	local table = dataTable[self.key]
	if table ~= nil then
		return table
	end

	return nil
end

--- @class RollTable
--- @field name string Display name.
--- @field details string Optional rules text for this table.
--- @field rollType string How to determine the roll: "auto", "autoUnusual", or "custom".
--- @field customRoll string Dice expression used when rollType is "custom" (e.g. "1d100").
--- @field rollModifier string Optional GoblinScript (creature context) added to the roll when rolling on this table.
--- @field visibility string Visibility setting: "visible" or "hidden".
--- @field rows RollTableRow[] Ordered list of rows in this table.
RollTable = RegisterGameType("RollTable")

--- @class RollTableRow
--- @field weight number Relative weight for weighted random selection.
--- @field revealed boolean If true, this row's result has been revealed to players.
--- @field value VariantCollection The reward/outcome for this row.
--- @field rollRange string Optional author-defined value range (e.g. "1-12", "13+", "5") used instead of the auto-computed range when the table has a Modifier.
RollTableRow = RegisterGameType("RollTableRow")

RollTableRow.weight = 1
RollTableRow.revealed = false

function RollTableRow.Create()
	return RollTableRow.new{
		id = dmhub.GenerateGuid(),
		value = VariantCollection.Create(),
	}
end

RollTable.name = "New Table"
RollTable.details = "" --rule details of the table. Optional.
RollTable.rollType = "auto"
RollTable.customRoll = "1d100"
RollTable.rollModifier = ""
RollTable.visibility = "visible"

local rollTypes = {
	{
		id = "auto",
		text = "Auto (Standard Dice)",
	},
	{
		id = "autoUnusual",
		text = "Auto (Unusual Dice)",
	},
	{
		id = "namedChoice",
		text = "Named Choice",
	},
	{
		id = "numericChoice",
		text = "Numeric Choice",
	},
	{
		id = "d4",
		text = "1d4",
	},
	{
		id = "d3",
		text = "1d3",
	},
	{
		id = "d6",
		text = "1d6",
	},
	{
		id = "d8",
		text = "1d8",
	},
	{
		id = "d10",
		text = "1d10",
	},
	{
		id = "d12",
		text = "1d12",
	},
	{
		id = "d20",
		text = "1d20",
	},
	{
		id = "d100",
		text = "1d100",
	},
	{
		id = "custom",
		text = "Custom",
	},
}

RollTable.RollTypes = rollTypes

--things this rolltable accepts.
RollTable.text = true
RollTable.items = true

function RollTable:ContainsType(type)
	local result = false
    for _,row in ipairs(self.rows) do
        for _,item in ipairs(row.value.items) do
            if item.type == type then
                result = true
                break
            end
        end
    end

	return result
end

function RollTable:IsChoice()
	return self.rollType == "namedChoice" or self.rollType == "numericChoice"
end

function RollTable.CreateNew(params)

	local args = {
		rows = {} --List of RollTableRow
	}

	for k,v in pairs(params or {}) do
		args[k] = v
	end

	return RollTable.new(args)
end

function RollTable:CalculateValue()
	if self:try_get("_tmp_valcalc") == dmhub.FrameCount() then
		return self._tmp_val
	end

	local first = true
	local result = VariantValue.new{}
	local totalWeight = 0
	for _,row in ipairs(self.rows) do
		totalWeight = totalWeight + row.weight

		local val = row.value:Value()
		if val.max > result.max then
			result.max = val.max
		end

		if first or val.min < result.min then
			result.min = val.min
		end

		result.avg = result.avg + val.avg*row.weight
		first = false
	end

	if totalWeight > 0 then
		result.avg = result.avg/totalWeight
	end

	self._tmp_valcalc = dmhub.FrameCount()
	self._tmp_val = result
	return result
end

--Sentinel "max" for an open-ended ("13+") custom range. Large enough that any
--modified total lands inside it; the result clamp in RowIndexFromDiceResult also
--keeps over-max totals on the highest range.
RollTable.OpenRangeMax = 1000000

--Parse an author-typed custom range string into a {min, max[, openEnded]} table.
--Accepts "13" (single), "1-12" (inclusive range), and "13+" (13 or higher).
--Returns nil for empty/unrecognized input (meaning: fall back to the auto range).
function RollTable.ParseCustomRange(str)
	if type(str) ~= "string" then
		return nil
	end

	str = trim(str)
	if str == "" then
		return nil
	end

	--"13+" -> 13 or higher.
	local plusMin = string.match(str, "^(%-?%d+)%s*%+$")
	if plusMin ~= nil then
		return { min = tonumber(plusMin), max = RollTable.OpenRangeMax, openEnded = true }
	end

	--"13-15" -> inclusive range.
	local lo, hi = string.match(str, "^(%-?%d+)%s*%-%s*(%-?%d+)$")
	if lo ~= nil and hi ~= nil then
		lo = tonumber(lo)
		hi = tonumber(hi)
		if hi < lo then
			lo, hi = hi, lo
		end
		return { min = lo, max = hi }
	end

	--"13" -> single value.
	local single = string.match(str, "^(%-?%d+)$")
	if single ~= nil then
		local n = tonumber(single)
		return { min = n, max = n }
	end

	return nil
end

--Format a rollRanges entry for display ("-", "13", "13-15", or "13+").
function RollTable.FormatRange(range)
	if range == nil or range.invalid then
		return "-"
	end
	if range.openEnded then
		return string.format("%d+", round(range.min))
	end
	if range.min == range.max then
		return string.format("%d", round(range.min))
	end
	return string.format("%d-%d", round(range.min), round(range.max))
end

function RollTable:CalculateRollInfo()
	local weightSum = 0
	for _,row in ipairs(self.rows) do
		weightSum = weightSum + row.weight
	end

	if weightSum < 1 then
		return nil
	end

	if weightSum > 1000 then
		weightSum = 1000
	end

	local roll = "1d100"
	local rollFaces = 100

	if self.rollType == "auto" then
		local diceTypes = {3,4,6,8,10,12,20,100}
		local bestDice = nil
		for _,diceType in ipairs(diceTypes) do
			if weightSum <= diceType then
				if bestDice == nil or (diceType%weightSum) < (bestDice%weightSum) then
					bestDice = diceType
				end
			end
		end

		if bestDice ~= nil then
			roll = string.format("1d%d", round(bestDice))
			rollFaces = round(bestDice)
		end
	elseif self.rollType == "autoUnusual" then
		roll = string.format("1d%d", round(weightSum))
		rollFaces = round(weightSum)
	elseif self.rollType == "custom" then
		roll = self.customRoll
	else
		roll = string.format("1%s", self.rollType)
		rollFaces = round(tonumber(string.sub(self.rollType, 2)) or 100)
	end

	local minRoll = dmhub.RollMinValue(roll)
	local maxRoll = dmhub.RollMaxValue(roll)

	local range = (maxRoll - minRoll) + 1
	if range > 10000 then
		range = 10000
	end

	local weights = {}
	for i,row in ipairs(self.rows) do
		weights[#weights+1] = row.weight
	end

	local cannotReduce = false
	if weightSum > 0 and weightSum > range and (cannotReduce == false) then
		cannotReduce = true
		for index,weight in ipairs(weights) do
			if weightSum > range and weight > 1 then
				weights[index] = weight-1
				weightSum = weightSum-1
				cannotReduce = false
			end
		end
	end

	if weightSum > 0 and weightSum < range then
		--algorithm for rounding our weights up to be integers that
		--match their weight as closely as possible.
		--
		--we find the fractional number each weight should be. Then we
		--make the weight equal to the floor of this. Then we decide a
		--'cut off' for when fractions should round up instead of down
		--and iterate the list in order making high enough fractions round up.
		local multiplier = range/weightSum
		local weightsOrdered = {}
		for ord,weight in ipairs(weights) do
			weightsOrdered[#weightsOrdered+1] = {
				ord = ord,
				integer = math.floor(weight*multiplier),
				fract = weight*multiplier - math.floor(weight*multiplier),
			}
		end

		weightSum = 0
		for _,weightInfo in ipairs(weightsOrdered) do
			weightSum = weightSum + weightInfo.integer
		end

		table.sort(weightsOrdered, function(a,b) return a.fract > b.fract end)

		--now round any fractions up until we will in the entire range.
		for _,weightInfo in ipairs(weightsOrdered) do
			if weightSum < range then
				weightInfo.integer = weightInfo.integer + 1
				weightSum = weightSum+1
			end
		end

		--now map back to the original list.
		weights = {}
		table.sort(weightsOrdered, function(a,b) return a.ord < b.ord end)
		for _,weightInfo in ipairs(weightsOrdered) do
			weights[#weights+1] = weightInfo.integer
		end
	end

	local currentValue = minRoll
	local rollRanges = {}
	for i,row in ipairs(self.rows) do
		if currentValue > maxRoll then
			rollRanges[#rollRanges+1] = {
				invalid = true
			}
		else
			rollRanges[#rollRanges+1] = {
				min = currentValue,
				max = math.min(currentValue + (weights[i]-1), maxRoll),
			}
		end
		currentValue = currentValue + weights[i]
	end

	--When the table carries a Modifier, authors may override individual row
	--ranges with custom values (e.g. "1-12", "13+", "5"). These take precedence
	--over the auto-computed ranges; rows left blank keep their auto range.
	if trim(self:try_get("rollModifier", "")) ~= "" then
		for i,row in ipairs(self.rows) do
			local custom = RollTable.ParseCustomRange(row:try_get("rollRange"))
			if custom ~= nil then
				rollRanges[i] = custom
			end
		end
	end

	return {
		rollFaces = rollFaces,
		roll = roll,
		rollRanges = rollRanges,
	}
end

--if tableName is nil, then key can represent a full table.
local SetData = function(tableName, rolltablePanel, key, options)

	options = options or {}

	local data = nil
	if tableName ~= nil then
		local dataTable = dmhub.GetTable(tableName) or {}
		data = dataTable[key]
	else
		data = key --the key is actually the table.
	end

	print("TableRoll: set data = ", data, "from key = ", key)

	local hasChanges = false

	local UploadTable = function()
		hasChanges = true
		rolltablePanel:FireEventTree("refreshData")
		--rolltablePanel:FireEvent("change")
	end

	local Rebuild

	Rebuild = function()
		local choice = data:IsChoice()

		local children = {}

		local tablePanel

		--the name of the table.
		children[#children+1] = gui.Panel{
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "Name:",
			},
			gui.Input{
				classes = {"formStacked"},
				text = data.name,
				change = function(element)
					data.name = element.text

					--force upload on name change to update the name.
					if tableName ~= nil then
						dmhub.SetAndUploadTableItem(tableName, data)
					end
					hasChanges = false

					rolltablePanel:FireEvent("changename")
				end,
			},
		}

		if options.hasDetails then
			children[#children+1] = gui.Panel{
				classes = {"formStackedRow"},
				gui.Label{
					classes = {"formStacked"},
					text = "Details:",
				},
				gui.Input{
					classes = {"formStacked"},
					multiline = true,
					height = "auto",
					minHeight = 30,
					maxHeight = 300,
					vscroll = true,
					textAlignment = "topleft",
					text = data.details,
					change = function(element)
						data.details = element.text

						--force upload on name change to update the name.
						if tableName ~= nil then
							dmhub.SetAndUploadTableItem(tableName, data)
						end
						hasChanges = false
					end,
				}
			}
		end

		children[#children+1] = gui.Panel{
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "Roll:",
			},
			gui.Dropdown{
				classes = {"formStacked"},
				options = rollTypes,
				idChosen = data.rollType,
				change = function(element)
					data.rollType = element.idChosen
					UploadTable()
					Rebuild()
				end,
			}
		}

		children[#children+1] = gui.Panel{
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "Modifier:",
			},
			gui.GoblinScriptInput{
				classes = {"formStacked"},
				value = data:try_get("rollModifier", ""),
				placeholderText = "(none)",
				change = function(element)
					data.rollModifier = element.value
					UploadTable()
					--Refresh rows so the per-row range fields become (un)editable
					--as the Modifier is added or removed.
					tablePanel:FireEvent("refreshTable")
				end,
				documentation = {
					help = "GoblinScript added to the roll whenever this table is rolled on. Evaluated against the creature making the roll. Leave blank for no modifier.",
					output = "number",
					examples = {
						{
							script = "2",
							text = "Add 2 to the roll.",
						},
						{
							script = "level",
							text = "Add the rolling creature's level to the roll.",
						},
					},
					subject = creature.helpSymbols,
					subjectDescription = "The creature making the roll.",
				},
			}
		}

		children[#children+1] = gui.Panel{
			classes = {"formStackedRow", cond(data.rollType ~= "custom", "collapsed")},
			refreshData = function(element)
				element:SetClass("collapsed", data.rollType ~= "custom")
			end,
			gui.Label{
				classes = {"formStacked"},
				text = "Custom Roll:",
			},
			gui.Input{
				classes = {"formStacked"},
				text = data.customRoll,
				change = function(element)
					data.customRoll = element.text
					UploadTable()
					tablePanel:FireEventTree("refreshRoll")
				end,
			}
		}

		children[#children+1] = gui.Panel{
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "Player Visibility:",
			},
			gui.Dropdown{
				classes = {"formStacked"},
				idChosen = data.visibility,
				options = {
					{
						id = "visible",
						text = "All Rows Visible",
					},
					{
						id = "hidden",
						text = "No Rows Visible",
					},
					{
						id = "reveal",
						text = "Reveal Rows as Rolled",
					},
				},

				change = function(element)
					data.visibility = element.idChosen
					UploadTable()
					tablePanel:FireEvent("refreshTable")
				end,
			}
		}

		if not options.noSubtable then
			children[#children+1] = gui.Check{
				text = "Subtable",
				fontSize = 18,
				value = data:try_get("subtable", false),
				hover = gui.Tooltip("Subtables are used by other tables, but cannot be rolled on directly."),
				change = function(element)
					data.subtable = element.value
					UploadTable()
				end,
			}
		end

		local rollValue = nil
		if options.showValue then
			rollValue = gui.Label{
				markdown = true,
				width = 400,
				height = "auto",
				fontSize = 16,
				refreshTable = function(element)
					local val = data:CalculateValue()
					if val.min ~= nil and val.avg ~= nil and val.max ~= nil then
						element.text = string.format("Table Value: %d~%d~%d", math.tointeger(round(val.min)), math.tointeger(round(val.avg)), math.tointeger(round(val.max)))
					else
						element.text = ""
					end
				end,
			}
			children[#children+1] = rollValue
		end

		local rollInfo = data:CalculateRollInfo()

		local valueLabel = nil
		if options.showValue then
			valueLabel = gui.Label{
				markdown = true,
				text = "Value",
				minWidth = 80,
				height = "auto",
				textAlignment = "left",
			}
		end


		local headerRow = gui.TableRow{
				classes = {"headerRow"},
				gui.Label{
					markdown = true,
					text = "Roll",
					minWidth = 120,
					height = "auto",
					textAlignment = "center",
					refreshRoll = function(element)
						if choice then
							element.text = "Choice"
							return
						end

						if rollInfo == nil then
							element.text = "Roll"
							return
						end

						element.text = rollInfo.roll
					end,
				},
				gui.Label{
					classes = {cond(choice, "collapsed")},
					markdown = true,
					text = "Weight",
					minWidth = 80,
					height = "auto",
					textAlignment = "center",
				},
				gui.Label{
					markdown = true,
					text = "Result",
					minWidth = 400,
					height = "auto",
					textAlignment = "left",
				},
				--add heading.
				gui.Panel{
					width = 0,
					height = 0,
				},
				valueLabel,
			}

		local variantType = {
			text = data.text,
			items = data.items,
			tables = cond(tableName, { tableName }),
			multiple = true,
		}

		local newItem = RollTableRow.Create()
		local newItemRow = gui.TableRow{
			gui.Label{
				markdown = true,
				text = "",
				minWidth = 120,
				height = "auto",
				textAlignment = "center",
			},
			gui.Label{
				classes = {cond(choice, "collapsed")},
				markdown = true,
				text = "",
				minWidth = 80,
				height = "auto",
				textAlignment = "center",
			},
			gui.VariantCollectionEditor{
				variantType = variantType,
				value = newItem.value,
				change = function(element)
					local newItemsList = {newItem}
					if #newItem.value.items == 1 and newItem.value.items[1].type == "text" then
						--if this is a text type, see if they pasted multiple separate lines, in which case each line is treated as a different item
						local stringItems = string.split(newItem.value.items[1].value, "\n")
						newItemsList = {}
						for _,str in ipairs(stringItems) do
							local row = RollTableRow.Create()
							local collection = row.value
							collection:Add(Variant.CreateText(str))
							newItemsList[#newItemsList+1] = row
						end
					elseif #newItem.value.items > 1 then
						--by default adding an item with multiple items puts them all in different rows.
						newItemsList = {}
						for _,item in ipairs(newItem.value.items) do
							local row = RollTableRow.Create()
							local collection = row.value
							collection:Add(item)
							newItemsList[#newItemsList+1] = row
						end
					end
					
					for _,item in ipairs(newItemsList) do
						data.rows[#data.rows+1] = item
					end

					newItem = RollTableRow.Create()
					element.value = newItem.value
					rolltablePanel:FireEventTree("refreshData")
					tablePanel:FireEvent("refreshTable")
					
					UploadTable()

					element:FireEventTree("setinputfocus")
				end,
			},
			gui.Button{
				classes = {"addButton", "sizeS", "add-row-button"},
				valign = "center",
				halign = "right",
				click = function(element)
					local items = element.parent.children[3].data.GetAddItemOptions(element)
					element.popup = gui.ContextMenu{
						entries = items,
						width = 400,
					}
				end,
			},
			
		}

		local rowPanels = {}

		tablePanel = gui.Table{
			width = "auto",
			height = "auto",
			styles = {
                {
                    selectors = {"formPanel"},
                    flow = "horizontal",
                },

				{
					selectors = {"delete-item-button"},
					hidden = 1,
				},
				{
					selectors = {"delete-item-button", "parent:hover"},
					hidden = 0,
				},

				{
					selectors = {"plus-button"},
					hidden = 1,
				},
				{
					selectors = {"plus-button", "add-row-button"},
					hidden = 0,
				},
				{
					selectors = {"plus-button", "parent:hover"},
					hidden = 0,
				},

				{
					selectors = {"visibilityIcon"},
					halign = "left",
					valign = "center",
					hmargin = 2,
					width = 16,
					height = 16,
					bgcolor = "#aaaaaa",
 					bgimage = "ui-icons/eye-closed.png",
				},
				{
					selectors = {"visibilityIcon", "revealed"},
					bgimage = "ui-icons/eye.png",
				},
				{
					selectors = {"visibilityIcon", "hover"},
					bgcolor = "#ffffff",
				},
				{
					selectors = {"visibilityIcon", "~progressiveVisibility"},
					collapsed = 1,
				}
			},

			destroy = function(element)
				if hasChanges then
					if tableName ~= nil then
						dmhub.SetAndUploadTableItem(tableName, data)
					end
					hasChanges = false
				end
			end,

			create = function(element)
				element:FireEvent("refreshTable")
			end,

			refreshRoll = function(element)
				rollInfo = data:CalculateRollInfo()
			end,

			refreshTable = function(element)
				if rollValue ~= nil then
					rollValue:FireEvent("refreshTable")
				end

				local children = {headerRow}

				local newRowPanels = {}
				for i,rowItem in ipairs(data.rows) do
					local row = rowItem

					local valueItem = nil
					if options.showValue and rowPanels[i] == nil then
						valueItem = gui.Label{
							markdown = true,
							text = "",
							minWidth = 60,
							height = "auto",
							halign = "left",
							refreshRoll = function(element)
								local val = row.value:Value()
								element.text = string.format("%d~%d~%d", round(val.min), round(val.avg), round(val.max))
							end,
						}
					end

					local index = i
					local rowPanel = rowPanels[i] or gui.TableRow{
						rightClick = function(element)
							local items = {
								{
									text = "Duplicate Row",
									click = function()
										element.popup = nil
										data.rows[#data.rows+1] = DeepCopy(row)
										UploadTable()
										rolltablePanel:FireEventTree("refreshData")
										tablePanel:FireEvent("refreshTable")
									end,
								},
								{
									text = "Delete Row",
									click = function()
										element.popup = nil
										table.remove(data.rows, index)
										UploadTable()
										rolltablePanel:FireEventTree("refreshData")
										tablePanel:FireEvent("refreshTable")
									end,
								},
							}

							element.popup = gui.ContextMenu{
								entries = items,
							}
						end,

						update = function(element, newRow)
							row = newRow
						end,
						gui.Label{
							markdown = true,
							text = "",
							minWidth = 120,
							height = "auto",
							textAlignment = "center",
							editable = data.rollType == "namedChoice" or (not data:IsChoice() and trim(data:try_get("rollModifier", "")) ~= ""),
							change = function(element)
								if data.rollType == "namedChoice" then
									row.choiceName = element.text
									UploadTable()
									return
								end

								--Modifier tables: author a custom value range per
								--row ("1-12", "13+", "5"); blank reverts to auto.
								row.rollRange = trim(element.text or "")
								tablePanel:FireEvent("refreshTable")
								UploadTable()
							end,
							refreshRoll = function(element)

								--Range fields are editable for named choices, and
								--for dice tables that carry a Modifier.
								element.editable = data.rollType == "namedChoice" or (not data:IsChoice() and trim(data:try_get("rollModifier", "")) ~= "")

								if data.rollType == "namedChoice" then
									if row ~= nil then
										element.text = row:try_get("choiceName", tonumber(index))
									end
									return
								elseif data.rollType == "numericChoice" then
									element.text = tonumber(index)
									return
								end

								if rollInfo == nil then
									element.text = "-"
									return
								end

								element.text = RollTable.FormatRange(rollInfo.rollRanges[index])
							end,

							gui.Panel{
								classes = {"visibilityIcon"},
								update = function(element, row)
									element:SetClass("revealed", row.revealed)
									element:SetClass("progressiveVisibility", data.visibility == "reveal")
								end,
								press = function(element)
									element:SetClass("revealed", not element:HasClass("revealed"))
									row.revealed = element:HasClass("revealed")
									tablePanel:FireEvent("refreshTable")
									UploadTable()
								end,
							}
						},
						gui.Label{
							classes = {cond(choice, "collapsed")},
							markdown = true,
							text = "",
							minWidth = 80,
							height = "auto",
							textAlignment = "center",
							editable = true,
							update = function(element, row)
								element.text = tostring(row.weight)
							end,
							change = function(element)
								row.weight = tonumber(element.text)
								row.weight = math.floor(row.weight)
								if row.weight < 1 then
									row.weight = 1
								end
								tablePanel:FireEvent("refreshTable")
								UploadTable()
							end,
						},
						gui.VariantCollectionEditor{
							variantType = variantType,
							value = row.value,
							update = function(element, row)
								if row.value ~= element.value then
									element.value = row.value
								end
							end,
							change = function(element)
								if row.value:Empty() then
									table.remove(data.rows, index)
									tablePanel:FireEvent("refreshTable")
								else
									--refresh values.
									if valueItem ~= nil then
										valueItem:FireEvent("refreshRoll")
									end

									if rollValue ~= nil then
										rollValue:FireEvent("refreshTable")
									end
								end
								UploadTable()
							end,
						},

						gui.Button{
							classes = {"addButton", "sizeS"},
							valign = "center",
							halign = "right",
							click = function(element)
								local items = element.parent.children[3].data.GetAddItemOptions(element)
								element.popup = gui.ContextMenu{
									entries = items,
									width = 400,
								}
							end,
						},

						valueItem,
				
					}

					rowPanel:FireEventTree("update", row)
					
					newRowPanels[i] = rowPanel
					children[#children+1] = rowPanel
				end

				rowPanels = newRowPanels

				children[#children+1] = newItemRow
				element.children = children

				element:FireEventTree("refreshRoll")
			end,

			headerRow,
			newItemRow,
		}

		children[#children+1] = tablePanel

		rolltablePanel.children = children

		rolltablePanel:FireEventTree("refreshData")
	end --end Rebuild() function

	Rebuild()
end

function RollTable.CreateEditor(args)
	local rolltablePanel
	rolltablePanel = {
		id = "rolltablePanel",
		vscroll = true,
		flow = "vertical",
		hmargin = 8,
		width = 1000,
		height = "auto",

		data = {
			SetData = function(tableName, key, options)
				SetData(tableName, rolltablePanel, key, options)
			end,
		},

		styles = {
			{
				classes = {'class-panel'},
				width = "100%",
				height = '90%',
				halign = 'left',
				flow = 'vertical',
				pad = 20,
			},
		},
	}

	for k,v in pairs(args or {}) do
		if k == "styles" then
			for _,style in ipairs(v) do
				rolltablePanel.styles[#rolltablePanel.styles+1] = style
			end
		else
			rolltablePanel[k] = v
		end
	end

	rolltablePanel = gui.Panel(rolltablePanel)

	return rolltablePanel
end

function RollTable:RowName(rowIndex)
	if self.rollType == "namedChoice" then
		local row = self.rows[rowIndex]
		if row ~= nil and row:has_key("choiceName") then
			return row.choiceName
		end
	end

	return tostring(rowIndex)
end


--describe a roll table, based on an optional choiceIndex which drills down into the choice.
function RollTable:Describe(choiceIndex)
	if choiceIndex == nil then
		return self.name
	end

	local row = self.rows[choiceIndex]
	if row == nil then
		return self.name
	end

	local choiceText = cond(self.rollType == "namedChoice", row:try_get("choiceName", tostring(choiceIndex)), tostring(choiceIndex))
	return string.format("%s - %s", self.name, choiceText)
end

function RollTable:RowIndexFromDiceResult(rollNum)
	local rollInfo = self:CalculateRollInfo()

	--Clamp to the table's valid range so an added Modifier that pushes the total
	--past either end still maps to the nearest edge row instead of falling off
	--the table. For an unmodified roll the dice exactly span the range, so this
	--never alters the result.
	local minValid, maxValid
	for _,range in ipairs(rollInfo.rollRanges) do
		if not range.invalid then
			if minValid == nil or range.min < minValid then minValid = range.min end
			if maxValid == nil or range.max > maxValid then maxValid = range.max end
		end
	end
	if minValid ~= nil and rollNum < minValid then rollNum = minValid end
	if maxValid ~= nil and rollNum > maxValid then rollNum = maxValid end

	for i,range in ipairs(rollInfo.rollRanges) do
		if (not range.invalid) and rollNum >= range.min and rollNum <= range.max then
			if self.rows[i] == nil then
				return nil
			end
			return i
		end
	end

	return nil
end

--rolls on the table and generates a VariantCollection result.
function RollTable:Roll(choiceIndex, collection, depth)
	if depth == nil then
		depth = 1
	elseif depth > 8 then
		return
	end

	if collection == nil then
		collection = VariantCollection.Create()
	end

	if choiceIndex == nil then
		local rollInfo = self:CalculateRollInfo()
        if rollInfo ~= nil then
            local rollNum = dmhub.RollInstant(rollInfo.roll)
            for i,range in ipairs(rollInfo.rollRanges) do
                if (not range.invalid) and rollNum >= range.min and rollNum <= range.max then
                    choiceIndex = i
                end
            end
        end
	end
	
	if choiceIndex ~= nil and self.rows[choiceIndex] ~= nil then
		for itemNum,item in ipairs(self.rows[choiceIndex].value.items) do
			if item.type == "tableRoll" then
				local quantity = item:RollQuantity()
				if quantity >= 1 then
					for i=1,quantity do
						local dataTable = dmhub.GetTable(item.dataTable) or {}
						local subtable = dataTable[item.key]
						subtable:Roll(item:try_get("choiceIndex"), collection, depth+1)
					end
				end
			else
				collection:Add(item)
			end
		end
	end

	return collection
end

local mod = dmhub.GetModLoading()

--- @class Currency
--- @field name string Display name of this currency denomination.
--- @field details string Description/lore text.
--- @field tableName string Name of the data table ("currency").
--- @field money boolean If true, this denomination is a monetary currency (not a generic resource).
--- @field autoconvert boolean If true, the system can automatically make change using this denomination.
--- @field value number Exchange value relative to the monetary standard for this denomination's standard.
--- @field hidden boolean If true, this denomination is hidden from UI.
--- @field weight number Weight in lbs per unit.
--- @field standard string Id of the monetary standard this denomination belongs to (usually the gold piece id).
Currency = RegisterGameType("Currency")

Currency.name = "New Currency"
Currency.details = ""
Currency.tableName = "currency"
Currency.money = true
Currency.autoconvert = true
Currency.value = 1
Currency.hidden = false
Currency.weight = 0.02

--- Returns the exchange value of this denomination relative to the standard (1 for the standard itself).
--- @return number
function Currency:UnitValue()
	if self.standard == self.id then
		return 1
	end

	return self.value
end

--- Appends {id, text} entries for all currencies into options (sorted by name).
--- @param options DropdownOption[]
function Currency.FillDropdownOptions(options)
	local result = {}
	local dataTable = dmhub.GetTable(Currency.tableName)
	for k,currency in pairs(dataTable) do
		result[#result+1] = {
			id = k,
			text = currency.name,
		}
	end

	table.sort(result, function(a,b) return a.text < b.text end)
	for i,item in ipairs(result) do
		options[#options+1] = item
	end
end

--- @return Currency
function Currency.CreateNew()
	local id = dmhub.GenerateGuid()
	return Currency.new{
		id = id,
		standard = id,
		iconid = "ui-icons/skills/1.png",
	}
end


--- Returns a map from monetary standard id to a list of Currency objects in that standard, sorted descending by value.
--- @return table<string, Currency[]>
--returns a mapping of currency id of standard -> list of currencies using this standard, sorted by value (descending).
function Currency.MonetaryStandards()
	local currencyTable = dmhub.GetTable(Currency.tableName) or {}

	local currencyStandards = {}

	for k,currency in pairs(currencyTable) do
		if currency.money and (not currency.hidden) then
			local entry = currencyStandards[currency.standard]
			if entry == nil then
				entry = {}
				currencyStandards[currency.standard] = entry
			end

			entry[#entry+1] = currency
		end
	end

	for k,standardEntry in pairs(currencyStandards) do
		table.sort(standardEntry, function(a,b) return a:UnitValue() > b:UnitValue() end)
	end

	return currencyStandards
end

local SetData = function(tableName, currencyPanel, condid)
	local dataTable = dmhub.GetTable(tableName) or {}
	local currency = dataTable[condid]
	local UploadCurrency = function(currencyItem)
		dmhub.SetAndUploadTableItem(tableName, currencyItem or currency)
	end

	local possibleStandards = {}

	local CalculatePossibleStandards = function()
		possibleStandards = {}
		for k,item in pairs(dataTable) do
			possibleStandards[#possibleStandards+1] = {
				id = k,
				text = item.name,
			}
		end
	end

	CalculatePossibleStandards()

	local children = {}

	--the name of the currency.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Name:",
		},
		gui.Input{
			classes = {"formStacked"},
			text = currency.name,
			change = function(element)
				currency.name = element.text
				UploadCurrency()

				CalculatePossibleStandards()
				currencyPanel:FireEventTree("calculateStandards")
			end,
		},
	}

	--if the currency is money.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Check{
			text = "Money",
			value = currency.money,
			change = function(element)
				currency.money = element.value
				UploadCurrency()
			end,
		}
	}

	--if we auto-convert to this currency.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Check{
			text = "Auto-convert to this denomination",
			value = currency.autoconvert,
			change = function(element)
				currency.autoconvert = element.value
				UploadCurrency()
			end,
		}
	}



	local valuePanel = gui.Panel{
		classes = {"formStackedRow", cond(currency.standard == currency.id, "collapsed")},
		showValue = function(element)
			element:SetClass("collapsed", currency.standard == currency.id)
		end,
		gui.Label{
			classes = {"formStacked"},
			text = "Value:",
		},
		gui.Input{
			classes = {"formStacked"},
			text = tostring(currency.value),
			change = function(element)
				local val = tonumber(element.text)
				if val == nil then
					element.text = tostring(currency.value)
				else
					currency.value = val
					UploadCurrency()
				end
			end,
		},
	}

	local weightPanel = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Weight:",
		},
		gui.Input{
			classes = {"formStacked"},
			text = tostring(currency.weight),
			change = function(element)
				local val = tonumber(element.text)
				if val == nil then
					element.text = tostring(currency.weight)
				else
					currency.weight = val
					UploadCurrency()
				end
			end,
		},
	}

	--the standard for this currency.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Standard:",
		},
		gui.Dropdown{
			classes = {"formStacked"},
			options = possibleStandards,
			idChosen = currency.standard,
			calculateStandards = function(element)
				element.options = possibleStandards
			end,
			change = function(element)
				currency.standard = element.idChosen
				valuePanel:FireEvent("showValue")
				UploadCurrency()
			end,
		},
	}

	children[#children+1] = valuePanel
	children[#children+1] = weightPanel


	--the currency's icon.
	local iconEditor = gui.IconEditor{
		classes = {"image"},
		library = "currency",
		margin = 20,
		width = 64,
		height = 64,
		halign = "left",
		value = currency.iconid,
		change = function(element)
			currency.iconid = element.value
			UploadCurrency()
		end,
	}

	local iconPanel = gui.Panel{
		width = 'auto',
		height = 'auto',
		flow = 'horizontal',
		halign = 'left',
		iconEditor,
	}

	children[#children+1] = iconPanel

	--currency details.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Details:",
		},
		gui.Input{
			classes = {"formStacked"},
			text = currency.details,
			multiline = true,
			height = 60,
			textAlignment = "topLeft",
			change = function(element)
				currency.details = element.text
				UploadCurrency()
			end,
		}
	}

	currencyPanel.children = children
end

function Currency.CreateEditor()
	local currencyPanel
	currencyPanel = gui.Panel{
		data = {
			SetData = function(tableName, condid)
				SetData(tableName, currencyPanel, condid)
			end,
		},
		vscroll = true,
		width = 1200,
		height = "90%",
		halign = "left",
		flow = "vertical",
		pad = 20,
		borderBox = true,
	}

	return currencyPanel
end

--- Returns the display name of the primary monetary standard currency (e.g. "Gold").
--- @return string
function Currency.GetMainCurrencyName()
	local currencyTable = dmhub.GetTable(Currency.tableName) or {}
	return currencyTable[Currency.GetMainCurrencyStandard()].name
end

--- Returns the id of the primary monetary standard.
--- @return nil|string
function Currency.GetMainCurrencyStandard()
	local currencyStandard = nil
	local currencyTable = dmhub.GetTable(Currency.tableName) or {}
	for k,currency in pairs(currencyTable) do
		if (currency.name == "Gold" or currency.money) and (not currency.hidden) then
			currencyStandard = currency.standard
			if currency.money then
				break
			end
		end
	end
	
	return currencyStandard
end

--- Converts a currency map to a total value in the given standard (defaults to main standard).
--- @param currencymap table<string, number>
--- @param standard nil|string
--- @return number
function Currency.CalculatePriceInStandard(currencymap, standard)
	if standard == nil then
		standard = Currency.GetMainCurrencyStandard()
	end

	local result = 0

	local currencyTable = dmhub.GetTable(Currency.tableName) or {}
	for currencyid,amount in pairs(currencymap) do
		local currencyInfo = currencyTable[currencyid]
		if currencyInfo ~= nil and currencyInfo.standard == standard and (not currencyInfo.hidden) then
			result = result + amount * currencyInfo.value
		end
	end

	return result

end

--- Converts a currency entry map to a total numeric value using each denomination's exchange rate.
--- @param entry table<string, number>
--- @return number
function Currency.EntryToNumber(entry)
	local result = 0
	local currencyTable = dmhub.GetTable(Currency.tableName) or {}
	for currencyid,amount in pairs(entry) do
		if currencyTable[currencyid] then
			result = result + amount*currencyTable[currencyid].value
		end
	end

	return result
end

--- Returns a spend table {currencyid -> quantity} for the given amount in the given standard.
--- If creature is provided, prefers low-value denominations the creature has; otherwise uses high-value.
--- @param creature nil|creature
--- @param amount number
--- @param standard nil|string
--- @param noWholeUnit nil|boolean
--- @return table<string, number>
--returns a spend table in the format {currencyid -> quantity}
function Currency.CalculateSpend(creature, amount, standard, noWholeUnit)
	if standard == nil then
		standard = Currency.GetMainCurrencyStandard()
	end

	local GetCurrency = function(currencyid)
		if creature == nil then
			return 1000000000
		end

		return creature:GetCurrency(currencyid)
	end

	local currencyTable = dmhub.GetTable(Currency.tableName) or {}

	--try to pay in whole units we have.
	local preferCurrency = nil
	if creature == nil then
		--if we have a creature we prefer to use our low value currency, while no creature prefers a high value currency.
		preferCurrency = function(a,b) return a:UnitValue() > b:UnitValue() end
	else
		preferCurrency = function(a,b) return a:UnitValue() < b:UnitValue() end
	end
	local wholeUnitSolution = nil
	if not noWholeUnit then
		for k,currency in pairs(currencyTable) do
			if currency.standard == standard and (not currency.hidden) and currency.autoconvert then
				local units = amount / currency:UnitValue()
				if (wholeUnitSolution == nil or preferCurrency(currency, wholeUnitSolution.currency)) and math.floor(units) == units and GetCurrency(k) >= units then
					wholeUnitSolution = {
						currencyid = k,
						currency = currency,
						units = units,
					}
				end
			end
		end
	end

	if wholeUnitSolution ~= nil then
		return {
			[wholeUnitSolution.currencyid] = wholeUnitSolution.units,
		}
	end

	--get all the possible currencies. March up the list and try to contribute to the cost
	--with all the currency we have. Then make change at the end.
	local currencies = {}
	for k,currency in pairs(currencyTable) do
		if currency.standard == standard and (not currency.hidden) and currency.autoconvert then
			currencies[#currencies+1] = currency
		end
	end

	--with no actual creature, we want to prefer to spend the most expensive currency.
	--creatures prefer to get rid of their change so they prefer the least expensive currency.
	if creature == nil then
		table.sort(currencies, function(a,b)
			return a:UnitValue() > b:UnitValue()
		end)
	else
		table.sort(currencies, function(a,b)
			return a:UnitValue() < b:UnitValue()
		end)
	end

	local result = {}

	local remainingAmount = amount
	local smallestDenomination = nil

	for _,currency in ipairs(currencies) do
		if smallestDenomination == nil or currency.value < smallestDenomination then
			smallestDenomination = currency.value
		end

		if remainingAmount > 0 then
			local units = remainingAmount / currency:UnitValue()
			local available = GetCurrency(currency.id)
			local use = 0
			if units <= available then
				if creature == nil then
					use = math.floor(units + 0.001) --no actual creature, so can't make change and we rely on later currency items to fill in the difference.
				else
					use = math.ceil(units)
				end
			else
				use = available
			end

			if use ~= 0 then
				result[currency.id] = use
			end

			remainingAmount = remainingAmount - use * currency:UnitValue()
		end
	end

	--refund currency amounts from greatest amount to least.
	table.sort(currencies, function(a,b)
		return a:UnitValue() > b:UnitValue()
	end)
	for _,currency in ipairs(currencies) do
		if remainingAmount < 0 and currency:UnitValue() <= -remainingAmount then
			local units = math.floor(-remainingAmount / currency:UnitValue())
			result[currency.id] = (result[currency.id] or 0) - units
			remainingAmount = remainingAmount + units * currency:UnitValue()
		end
	end

	if smallestDenomination ~= nil and remainingAmount >= smallestDenomination then
		--cannot afford.
		return nil
	end

	return result
end

--parse currency in a format like "4g 8sp 5copper"
--to {gold = 4, silver = 8, copper = 5}
--
--Other examples:
-- "5" -> {gold = 5}
-- "5.4" -> {gold = 5.4}
-- "2s" -> {silver = 2}
-- "4.5c" -> {copper = 4.5}
-- "-4" -> {gold = -4}
-- "-4g 2c" -> {gold = -4, copper = -2}
function ParseCurrency(str, result, multiply)
	multiply = multiply or 1
	local result = result or {}

	str = string.lower(trim(str))

	if str == '' then
		return result
	end

	if string.find(str, "^%d+$") then
		result.gold = (result.gold or 0) + multiply*tonumber(str)
		return result
	end

	local i, j = string.find(str, "[%d%.]+ *")

	if i == nil then
		return result
	end

	--see if immediately before the match there is a - which makes us negative
	if i > 1 and string.sub(str, i-1, i-1) == '-' then
		multiply = -1
	end

	local num = trim(string.sub(str, i, j))

	local tail = string.sub(str, j+1, -1)

	local firstChar = string.sub(tail,1,1)

	local currencyType = 'gold'
	if firstChar == 's' then
		currencyType = 'silver'
	elseif firstChar == 'c' then
		currencyType = 'copper'
	end

	result[currencyType] = (result[currencyType] or 0) + multiply*tonumber(num)
	
	return ParseCurrency(tail, result, multiply)

end

function Currency:Render(options, token)

	options = options or {}

	local summary = options.summary
	options.summary = nil

	local children = {
		gui.Label{
			text = tr(self.name),
			classes = {"title"},
		},
		gui.Panel{
			classes = {"icon"},
			bgimage = self.iconid,
			floating = true,
		},
		gui.Label{
			text = self.details,
		},
	}

	return gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",

		styles = Styles.ItemTooltip,

		children = children,
	}

end
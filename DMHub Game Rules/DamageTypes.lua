local mod = dmhub.GetModLoading()

--- @class DamageType
--- @field name string Display name (lowercase, e.g. "fire", "slashing").
--- @field tableName string Data table name ("damageTypes").
--- @field category string Category id for grouping ("none" if uncategorized).
--- @field hidden boolean If true, this damage type is not shown in UI menus.
--- @field iscategory boolean If true, this entry is a category rather than a specific damage type.
DamageType = RegisterGameType("DamageType")

--- @class DamageFlag
DamageFlag = RegisterGameType("DamageFlag")

--- @return DamageType
function DamageType.CreateNew()
	return DamageType.new{
		iconid = "ui-icons/skills/1.png",
		display = {
			bgcolor = "white",
			hueshift = 0,
			saturation = 1,
			brightness = 1,
		}
	}
end


DamageType.tableName = "damageTypes"
DamageType.name = "damage"
DamageType.category = "none"
DamageType.hidden = false
DamageType.iscategory = false

function DamageType.InitStandards()
	local t = dmhub.GetTable(DamageType.tableName)
	if t == nil then
		for _,damageType in ipairs(rules.damageTypes) do
			local newType = DamageType.CreateNew()
			newType.name = damageType

			dmhub.SetAndUploadTableItem(DamageType.tableName, newType)
		end
	end
end

local initDamageTypes = false
dmhub.RegisterEventHandler("refreshTables", function()
	printf("REFRESHTABLES: Init damage types...")
	if initDamageTypes then
		return
	end

	local damageTypesTable = dmhub.GetTable(DamageType.tableName)
	if damageTypesTable == nil then
		return
	end

	initDamageTypes = true

	rules.damageTypes = {}
	rules.damageTypesAvailable = {} --non-deleted damage types.
	rules.damageTypesToInfo = {}

	for k,entry in pairs(damageTypesTable) do
		if not entry:try_get("hidden", false) then
			rules.damageTypesAvailable[#rules.damageTypesAvailable+1] = string.lower(entry.name)
		end
		rules.damageTypes[#rules.damageTypes+1] = string.lower(entry.name)
		rules.damageTypesToInfo[string.lower(entry.name)] = entry
	end


	printf("REFRESHTABLES: Init damage types: %d", #rules.damageTypes)

	table.sort(rules.damageTypes, function(a,b) return a < b end)
	table.sort(rules.damageTypesAvailable, function(a,b) return a < b end)

	rules.damageTypesAvailableWithAll = DeepCopy(rules.damageTypesAvailable)
	table.insert(rules.damageTypesAvailableWithAll, 1, "all")
	
end)

local UploadDamageTypeWithId = function(id)
	local dataTable = dmhub.GetTable(DamageType.tableName) or {}
	dmhub.SetAndUploadTableItem(DamageType.tableName, dataTable[id])
end

local SetDamageType = function(tableName, damageTypePanel, damageid)
	local dataTable = dmhub.GetTable(tableName) or {}
	local damageType = dataTable[damageid]
	local UploadDamageType = function()
		dmhub.SetAndUploadTableItem(tableName, damageType)
	end

	if damageTypePanel.data.damageid ~= "" and damageTypePanel.data.damageid ~= damageid and dmhub.ToJson(dataTable[damageTypePanel.data.damageid]) ~= damageTypePanel.data.damageTypejson then
		UploadDamageTypeWithId(damageTypePanel.data.damageid)
	end

	damageTypePanel.data.damageid = damageid
	damageTypePanel.data.damageTypejson = dmhub.ToJson(damageType)

	local children = {}

	--the name of the damageType.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Name:",
		},
		gui.Input{
			classes = {"formStacked"},
			text = damageType.name,
			change = function(element)
				damageType.name = element.text
				UploadDamageType()
			end,
		},
	}

	--the damageType's icon.
	local iconEditor = gui.IconEditor{
		library = "ongoingEffects",
		bgcolor = damageType.display['bgcolor'] or "white",
		margin = 20,
		width = 64,
		height = 64,
		halign = "left",
		value = damageType.iconid,
		change = function(element)
			damageType.iconid = element.value
			UploadDamageType()
		end,
		create = function(element)
			element.selfStyle.hueshift = damageType.display['hueshift']
			element.selfStyle.saturation = damageType.display['saturation']
			element.selfStyle.brightness = damageType.display['brightness']
		end,
	}

	local iconColorPicker = gui.ColorPicker{
		value = damageType.display['bgcolor'] or "white",
		hmargin = 8,
		width = 24,
		height = 24,
		valign = 'center',

		confirm = function(element)
			iconEditor.selfStyle.bgcolor = element.value
			damageType.display['bgcolor'] = element.value
			UploadDamageType()
		end,

		change = function(element)
			iconEditor.selfStyle.bgcolor = element.value
		end,
	}

	local iconPanel = gui.Panel{
		width = 'auto',
		height = 'auto',
		flow = 'horizontal',
		halign = 'left',
		iconEditor,
		iconColorPicker,
	}

	children[#children+1] = iconPanel

	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Check{
			text = "Is Category",
			value = damageType.iscategory,
			change = function(element)
				damageType.iscategory = element.value
				UploadDamageType()
			end,
		},
	}

	local categories = {
		{
			id = "none",
			text = "None",
		},
	}
	
	for key,damageType in pairs(dataTable) do
		if damageType.iscategory and key ~= damageid then
			categories[#categories+1] = {
				id = key,
				text = damageType.name,
			}
		end
	end

	if #categories > 1 then
		children[#children+1] = gui.Panel{
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "Category:",
			},
			gui.Dropdown{
				classes = {"formStacked"},
				idChosen = damageType.category,
				options = categories,
				change = function(element)
					damageType.category = element.idChosen
					UploadDamageType()
				end,
			},
		}
	end

	damageTypePanel.children = children
end

function DamageType.CreateEditor()
	local damageTypePanel
	damageTypePanel = gui.Panel{
		data = {
			SetData = function(tableName, damageid)
				SetDamageType(tableName, damageTypePanel, damageid)
			end,
			damageid = "",
			damageTypejson = "",
		},
		destroy = function(element)
			
			local dataTable = dmhub.GetTable(DamageType.tableName) or {}

			--if the damageType changed, then upload it.
			if element.data.damageid ~= "" and dmhub.ToJson(dataTable[element.data.damageid]) ~= element.data.damageTypejson then
				UploadDamageTypeWithId(element.data.damageid)
			end
		end,
		vscroll = true,
		width = 1200,
		height = "90%",
		halign = "left",
		flow = "vertical",
		pad = 20,
		borderBox = true,
	}

	return damageTypePanel
end

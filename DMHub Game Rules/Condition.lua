local mod = dmhub.GetModLoading()

--- @class CharacterCondition
CharacterCondition = RegisterGameType("CharacterCondition", "CharacterFeature")

CharacterCondition.name = "New Condition"
CharacterCondition.description = ""
CharacterCondition.tableName = "charConditions"
CharacterCondition.ridersTableName = "conditionRiders"
CharacterCondition.emoji = "none"
CharacterCondition.immunityPossible = false
CharacterCondition.trackCaster = false
CharacterCondition.source = "Condition"
CharacterCondition.stackable = false
CharacterCondition.powertable = false
CharacterCondition.indefiniteDuration = false
CharacterCondition.showInMenus = true
CharacterCondition.sustainFormula = ""


CharacterCondition.conditionsByName = {}

function CharacterCondition:SoundEvent()
    return "Condition." .. self.name
end

--- @param conditionid string
--- @param name string
--- @return nil|string
function CharacterCondition.GetRiderIdFromName(conditionid, name)
    local t = dmhub.GetTable(CharacterCondition.ridersTableName)
    for k,v in unhidden_pairs(t) do
        if v.condition == conditionid and string.lower(v.name) == string.lower(name) then
            return k
        end
    end

    return nil
end

function CharacterCondition.OnDeserialize(self)
	if not self:has_key("guid") then
		self.guid = dmhub.GenerateGuid()
	end
end

function CharacterCondition.FillDropdownOptions(options)
	local result = {}
	local dataTable = dmhub.GetTable(CharacterCondition.tableName)
	for k,condition in unhidden_pairs(dataTable) do
		result[#result+1] = {
			id = k,
			text = condition.name,
		}
	end

	table.sort(result, function(a,b) return a.text < b.text end)
	for i,item in ipairs(result) do
		options[#options+1] = item
	end
end

function CharacterCondition.CreateNew()
	return CharacterCondition.new{
		guid = dmhub.GenerateGuid(),
		iconid = "ui-icons/skills/1.png",
		display = {
			bgcolor = '#ffffffff',
			hueshift = 0,
			saturation = 1,
			brightness = 1,
		}
	}
end

function CharacterCondition:GetUnderlyingConditions()
	local result = self:try_get("underlying")
	if result == nil then
		result = {}
	end

	return result
end

function CharacterCondition:AddUnderlyingCondition(condid)
	local underlying = self:get_or_add("underlying", {})
	underlying[condid] = true
end

function CharacterCondition:RemoveUnderlyingCondition(condid)
	local underlying = self:get_or_add("underlying", {})
	underlying[condid] = nil
end

local UploadConditionWithId = function(id)
	local dataTable = dmhub.GetTable(CharacterCondition.tableName) or {}
	dmhub.SetAndUploadTableItem(CharacterCondition.tableName, dataTable[id])
end

local SetData = function(tableName, conditionPanel, condid)
	local dataTable = dmhub.GetTable(tableName) or {}
	local condition = dataTable[condid]
	local UploadCondition = function()
		dmhub.SetAndUploadTableItem(tableName, condition)
	end

	if conditionPanel.data.condid ~= "" and conditionPanel.data.condid ~= condid and dmhub.ToJson(dataTable[conditionPanel.data.condid]) ~= conditionPanel.data.conditionjson then
		UploadConditionWithId(conditionPanel.data.condid)
	end

	conditionPanel.data.condid = condid
	conditionPanel.data.conditionjson = dmhub.ToJson(condition)

	local children = {}

    if devmode() then
        --the id of the condition.
        children[#children+1] = gui.Panel{
            classes = {'formPanel'},
            gui.Label{
                text = 'ID:',
                valign = 'center',
                minWidth = 240,
            },
            gui.Input{
                text = condition.id,
                editable = false,
            },
        }
    end



	--the name of the condition.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		gui.Label{
			text = 'Name:',
			valign = 'center',
			minWidth = 240,
		},
		gui.Input{
			text = condition.name,
			change = function(element)
				condition.name = element.text
				UploadCondition()
			end,
		},
	}

	--the condition's icon.
	local iconEditor = gui.IconEditor{
		library = "ongoingEffects",
		bgcolor = condition.display['bgcolor'] or '#ffffffff',
		margin = 20,
		width = 64,
		height = 64,
		halign = "left",
		value = condition.iconid,
		change = function(element)
			condition.iconid = element.value
			UploadCondition()
		end,
		create = function(element)
			element.selfStyle.hueshift = condition.display['hueshift']
			element.selfStyle.saturation = condition.display['saturation']
			element.selfStyle.brightness = condition.display['brightness']
		end,
	}

	local iconColorPicker = gui.ColorPicker{
		value = condition.display['bgcolor'] or '#ffffffff',
		hmargin = 8,
		width = 24,
		height = 24,
		valign = 'center',
		borderWidth = 2,
		borderColor = '#999999ff',

		confirm = function(element)
			iconEditor.selfStyle.bgcolor = element.value
			condition.display['bgcolor'] = element.value
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

	local emojiOptions = {
		{
			id = "none",
			text = "No Emoji",
		}
	}

	for k,emoji in pairs(assets.emojiTable) do
		if (not emoji.hidden) and emoji.emojiType == 'Status' and emoji.looping then
			emojiOptions[#emojiOptions+1] = {
				id = k,
				text = emoji.description,
			}
		end
	end

	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		gui.Label{
			text = 'Emoji:',
			valign = "center",
			minWidth = 200,
			width = 'auto',
			height = 'auto',
		},
		gui.Dropdown{
			classes = "formDropdown",
			options = emojiOptions,
			idChosen = condition.emoji,
			change = function(element)
				condition.emoji = element.idChosen
				UploadCondition()
			end,
		},
	}

	--condition description.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		height = 'auto',
		gui.Label{
			text = "Details:",
			valign = "center",
			minWidth = 240,
		},
		gui.Input{
			text = condition.description,
			multiline = true,
			minHeight = 50,
			height = 'auto',
			width = 400,
			textAlignment = "topleft",
			change = function(element)
				condition.description = element.text
				UploadCondition()
			end,
		}
	}

	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		height = 'auto',
		gui.Check{
			value = condition.showInMenus,
			text = "Shown in Menus",
			change = function(element)
				condition.showInMenus = not condition.showInMenus
				UploadCondition()
			end,
		},
	}

	--this condition can be applied in a power table.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		height = 'auto',
		gui.Check{
			value = condition.powertable,
			text = "Can be applied from Power Table",
			change = function(element)
				condition.powertable = not condition.powertable
				UploadCondition()
			end,
		},
	}

	--this condition is stackable.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		height = 'auto',
		gui.Check{
			value = condition.indefiniteDuration,
			text = "Indefinite Duration",
			change = function(element)
				condition.indefiniteDuration = not condition.indefiniteDuration
				UploadCondition()
			end,
		},
	}

	--this condition is stackable.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		height = 'auto',
		gui.Check{
			value = condition.stackable,
			text = "Stackable",
			change = function(element)
				condition.stackable = not condition.stackable
				UploadCondition()
			end,
		},
	}

	--immunity to this condition is possible.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		height = 'auto',
		gui.Check{
			value = condition.immunityPossible,
			text = "Creatures can be immune",
			change = function(element)
				condition.immunityPossible = not condition.immunityPossible
				UploadCondition()
			end,
		},
	}

    local maxInstancesPanel
    local casterAbilityCheck

	--track caster who applied this condition.

	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		height = 'auto',
		gui.Check{
			value = condition.trackCaster,
			text = "Track Caster",
			change = function(element)
				condition.trackCaster = not condition.trackCaster
				UploadCondition()
                maxInstancesPanel:FireEventTree("refreshCollapsed")
                casterAbilityCheck:FireEventTree("refreshCollapsed")
			end,
		},
	}

    maxInstancesPanel = gui.Panel{
        classes = {'formPanel', cond(condition.trackCaster, nil, "collapsed")},
        refreshCollapsed = function(element)
            element:SetClass("collapsed", not condition.trackCaster)
        end,
        height = 'auto',
        gui.Label{
            classes = {"formLabel"},
            text = "Max. Instances:",
        },
        gui.GoblinScriptInput{
            value = condition:try_get("maxInstancesFormula", ""),
			change = function(element)
				condition.maxInstancesFormula = element.value
			end,
            documentation = {
                help = "This GoblinScript is used to determine the maximum number of instances of the condition that can be applied from a single caster.",
                output = "number",
                examples = {
                },
                subject = creature.helpSymbols,
                subjectDescription = "The creature that is applying the condition.",
            },
        },
    }

    children[#children+1] = maxInstancesPanel

	casterAbilityCheck = gui.Panel{
        classes = {'formPanel', cond(condition.trackCaster, nil, "collapsed")},
        refreshCollapsed = function(element)
            element:SetClass("collapsed", not condition.trackCaster)
        end,
        flow = "vertical",
		height = 'auto',
		gui.Check{
			value = condition:try_get("casterCanClick", false),
			text = "Caster Can Click",
			change = function(element)
				condition.casterCanClick = not condition:try_get("casterCanClick", false)
				UploadCondition()
                element.parent:FireEventTree("refreshCollapsed")
			end,
		},

        gui.Button{
            classes = {cond(condition:try_get("casterCanClick", false), nil, "collapsed")},
            refreshCollapsed = function(element)
                element:SetClass("collapsed", not condition:try_get("casterCanClick", false))
            end,
            text = "Edit Click Ability",
            width = 200,
            height = 50,
            click = function(element)
                if condition:try_get("casterClickAbility", nil) == nil then
                    condition.casterClickAbility = ActivatedAbility.Create{}
                    UploadCondition()
                end

                element.root:AddChild(condition.casterClickAbility:ShowEditActivatedAbilityDialog{
                    destroy = function()
                        UploadCondition()
                        element.parent:FireEventTree("refreshCollapsed")
                    end,
                })
            end,
        },

        gui.Check{
			value = condition:try_get("casterCanDrag", false),
			text = "Caster Can Drag",
			change = function(element)
				condition.casterCanDrag = not condition:try_get("casterCanDrag", false)
				UploadCondition()
                element.parent:FireEventTree("refreshCollapsed")
            end,
        },
	}

    children[#children+1] = casterAbilityCheck


    children[#children + 1] = gui.Panel {
        classes = { "formPanel" },
        gui.Label {
            text = "Sustain:",
            valign = "center",
            minWidth = 199,
            width = 'auto',
            height = 'auto',
        },
        gui.GoblinScriptInput {
            classes = { "formInput" },
            value = condition.sustainFormula,
            change = function(element)
                condition.sustainFormula = element.value
                UploadCondition()
            end,
            documentation = {
                help = string.format("This GoblinScript is used to calculate if the condition continues. If it results in a 0 or false value the ongoing effect will end."),
                output = "true or false",
                examples = {
                    {
                        script = "Hitpoints > 5",
                        text = "The condition will continue as long as the creature's hitpoints are greater than 5. It will end as soon as the creature's hitpoints drop to 5 or lower.",
                    },
                },
                subject = creature.helpSymbols,
                subjectDescription = "The creature who the condition is applied to.",
            },
        },
    }



	--underlying conditions.
	children[#children+1] = gui.Panel{
		flow = "vertical",
		width = 400,
		height = "auto",

		create = function(element)
			element:FireEvent("refreshUnderlying")
		end,

		refreshUnderlying = function(element)
			local currentChildren = element.children

			local children = {}

			if #condition:GetUnderlyingConditions() > 0 then
				children[#children+1] = gui.Label{
					width = "auto",
					height = "auto",
					fontSize = 22,
					text = "Underlying Conditions",
				}
			end

			local dataTable = dmhub.GetTable(CharacterCondition.tableName) or {}
			for id,_ in pairs(condition:GetUnderlyingConditions()) do
				local underlyingCond = dataTable[id]
				if underlyingCond ~= nil then
					children[#children+1] = gui.Label{
						bgimage = "panels/square.png",
						bgcolor = "#00000088",
						text = underlyingCond.name,
						fontSize = 18,
						cornerRadius = 4,
						width = 200,
						height = 22,

						gui.DeleteItemButton{
							halign = "right",
							width = 16,
							height = 16,
							click = function(element)
								condition:RemoveUnderlyingCondition(id)
								UploadCondition()
								element.parent:DestroySelf()
							end,
						}
					}
				end
			end

			children[#children+1] = currentChildren[#currentChildren]
			element.children = children
		end,

		gui.Dropdown{
			create = function(element)
				element:FireEvent("refreshUnderlying")
			end,

			refreshUnderlying = function(element)
				local options = {
					{
						id = "none",
						text = "Add Underlying Condition...",
					}
				}

				local dataTable = dmhub.GetTable(CharacterCondition.tableName) or {}
				for id,info in pairs(dataTable) do
					if info:try_get("hidden", false) == false and id ~= condid and (not condition:GetUnderlyingConditions()[id]) then
						options[#options+1] = {
							id = id,
							text = info.name,
						}
					end
				end

				element.options = options
				element.idChosen = "none"
			end,

			change = function(element)
				if element.idChosen == "none" then
					return
				end

				condition:AddUnderlyingCondition(element.idChosen)
				UploadCondition()
				conditionPanel:FireEventTree("refreshUnderlying")
			end,
		},
	}

	--list of modifiers that apply.
	children[#children+1] = gui.Panel{
		classes = {'modsPanel'},
		styles = {
			{
				halign = "left",
			},
			{
				classes = {'modsPanel'},
				width = 800,
                height = "auto",
				halign = 'left',
			},
			{
				classes = {'namePanel'},
				collapsed = 1,
			},
			{
				classes = {'sourcePanel'},
				collapsed = 1,
			},
			{
				classes = {'descriptionPanel'},
				collapsed = 1,
			},
		},

		condition:EditorPanel{
            noscroll = true,
			modifierRefreshed = function(element)
				dmhub.Debug("REFRESH:: MODIFIERS UPLOAD")
				UploadCondition()
			end,
		},
	}

	conditionPanel.children = children
end

function CharacterCondition.CreateEditor()
	local conditionPanel
	conditionPanel = gui.Panel{
		data = {
			SetData = function(tableName, condid)
				SetData(tableName, conditionPanel, condid)
			end,
			condid = "",
			conditionjson = "",
		},
		destroy = function(element)
			
			local dataTable = dmhub.GetTable(CharacterCondition.tableName) or {}

			--if the condition changed, then upload it.
			if element.data.condid ~= "" and dmhub.ToJson(dataTable[element.data.condid]) ~= element.data.conditionjson then
				UploadConditionWithId(element.data.condid)
			end
		end,
		vscroll = true,
		classes = 'class-panel',
		styles = {
			{
				halign = "left",
			},
			{
				classes = {'class-panel'},
				width = 1200,
				height = '90%',
				halign = 'left',
				flow = 'vertical',
				pad = 20,
			},
			{
				classes = {'label'},
				color = 'white',
				fontSize = 22,
				width = 'auto',
				height = 'auto',
			},
			{
				classes = {'input'},
				width = 200,
				height = 26,
				fontSize = 18,
				color = 'white',
			},
			{
				classes = {'formPanel'},
				flow = 'horizontal',
				width = 'auto',
				height = 'auto',
				halign = 'left',
				vmargin = 2,
			},

		},
	}

	return conditionPanel
end

dmhub.RegisterEventHandler("refreshTables", function()
	local dataTable = dmhub.GetTable(CharacterCondition.tableName)
	for k,v in unhidden_pairs(dataTable) do
		CharacterCondition.conditionsByName[string.lower(v.name)] = v
	end
end)

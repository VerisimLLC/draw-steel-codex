local mod = dmhub.GetModLoading()

RegisterGameType("GoblinScriptTable")
GoblinScriptTable.id = "level"
GoblinScriptTable.field = "Level"
GoblinScriptTable.editableField = false
GoblinScriptTable.upcastStyle = false --upcast style just has two rows, 'base' and 'higher levels'
GoblinScriptTable.baseLabel = "Base"
GoblinScriptTable.upcastLabel = "Upcast"

function GoblinScriptTable.tostring(script)
	if type(script) == "table" then
		return script:ToText()
	else
		return tostring(script)
	end
end


--entries are a list of {threshold -> number, script -> string}
GoblinScriptTable.entries = {}

function GoblinScriptTable:FromText(text)
	self.entries[1].script = text
end

function GoblinScriptTable:ToText()
	if self.upcastStyle then
		local result = self.entries[1].script
		if self.entries[2].script ~= "" then
			result = string.format("%s + (%s)*%s", result, self.entries[2].script, self.field)
		end

		return result
	end

	local result = ""
	for i=#self.entries,1,-1 do
		result = string.format("%s%s", result, self.entries[i].script)
		if i > 1 or self.entries[i].threshold > 1 then
			result = string.format("%s when %s >= %s", result, self.field, self.entries[i].threshold)

		end
		if i > 1 then
			result = string.format("%s else ", result)
		end
	end

	return result
end

function GoblinScriptTable:Normalize()
	table.sort(self.entries, function(a,b) return a.threshold < b.threshold end)
end

local g_completionMenuStyles = {
	gui.Style{
		selectors = {"menu"},
		bgcolor ="black",
		borderWidth = 2,
		borderColor = Styles.textColor,
	},
	gui.Style{
		selectors = {"option"},
		bgimage = "panels/square.png",
		width = "100%-2",
		height = "auto",
		halign = "center",
        hpad = 6,
		vpad = 4,
		fontSize = 18,
		color = Styles.textColor,
	},
	{
		selectors = {"option", "selected"},
		color = "black",
		bgcolor = Styles.textColor,
		brightness = 0.6,
	},
	{
		selectors = {"option", "hover"},
		color = "black",
		bgcolor = Styles.textColor,
		brightness = 1,
	},
}

function gui.GoblinScriptInput(options)

	local input_value = options.value
	options.value = nil

	local resultPanel
	local documentation = options.documentation
	options.documentation = nil
	local placeholderText = options.placeholderText or "Enter formula..."
	options.placeholderText = nil
	local multiline = cond(options.multiline ~= nil, options.multiline, true)
	options.multiline = nil
	local displayTypes = options.displayTypes
	options.displayTypes = nil

	local fieldName = options.fieldName or "Value"
	options.fieldName = nil

	local m_autoCompleteSymbols = {}
	if documentation ~= nil then
		for k,sym in pairs(documentation.subject or {}) do
			m_autoCompleteSymbols[k] = sym
		end

		for k,sym in pairs(documentation.symbols or {}) do
			m_autoCompleteSymbols[k] = sym
		end
	end

	local m_width = options.width or 360
	local editWidth = m_width - 40

	local m_value = nil

	local inputText = nil
	local inputTable = nil

	local newFieldInput
	local newValueInput

	local container = gui.Panel{
		width = "100%-40",
		height = "auto",
		halign = "left",
	}

	local InitText = function()
		if inputText == nil then
			inputText = gui.Input{
				id = "GoblinScriptInput",
				width = "100%",
				minHeight = 30,
				height = "auto",
				fontSize = 14,
				multiline = multiline,
				placeholderText = placeholderText,
                characterLimit = 1024,

				data = {
					changePending = false,
					focusPending = false,
				},

				tab = function(element)

					if element.popup ~= nil then
						element.popup:FireEventTree("tab")
					end
				end,

				uparrow = function(element)
					if element.popup ~= nil then
						element.popup:FireEventTree("uparrow")
					end
				end,

				downarrow = function(element)
					if element.popup ~= nil then
						element.popup:FireEventTree("downarrow")
					end
				end,

				thinkTime = 0.1,
				think = function(element)
					if element.data.focusPending then
						printf("GOBLINSCRIPT:: FOCUS PEND")
						element.hasInputFocus = true
						element.data.focusPending = false
						return
					end
					if element.data.changePending then
						element:FireEvent("change")
					end
				end,

				destroy = function(element)
					if element.data.changePending then
						element.data.destroying = true
						element:FireEvent("change", true)
					end
				end,

				change = function(element)
					if (not element.data.destroying) and (element.hasInputFocus or element.popup ~= nil) then
						element.data.changePending = true
						return
					end

					printf("GOBLINSCRIPT:: DO CHANGE: %s", element.text)

					element.data.changePending = false
					m_value = element.text
					resultPanel:FireEvent("change", element.text)
				end,

				edit = function(element)
					if dmhub.KeyPressed("tab") and element.popup ~= nil then
						return
					end

					if not element.hasInputFocus then
						printf("GOBLINSCRIPT:: NO FOCUS: %s", element.text)
						return
					end

					local parentPanel = element
					parentPanel.popupPositioning = "panel"

					local pos = element.caretPosition
					local text = string.sub(element.text, 1, pos)
					local completions = dmhub.AutoCompleteGoblinScript{
						text = text,
						symbols = m_autoCompleteSymbols,
						deterministic = (documentation or {}).output ~= "roll",
					}

					if completions == nil or #completions == 0 then
						element.popup = nil
					else
						local children = {}

						for i,completion in ipairs(completions) do
							local labelText = completion.word
							if completion.type ~= nil then
								labelText = string.format("%s\n<size=70%%><i>%s</i></size>", labelText, completion.type)
							end

							children[#children+1] = gui.Label{
								classes = {"option"},
								text = labelText,
								press = function(element)
									printf("GOBLINSCRIPT:: PRESS")
									local newText = completion.completion .. string.sub(text, pos+1, #text)
									local caretPosition = #completion.completion

									if completion.type == "function" then
										newText = newText .. "()"
										caretPosition = caretPosition+1
									end

									parentPanel.text = newText
									parentPanel.caretPosition = caretPosition

									parentPanel.popup = nil
									parentPanel.hasInputFocus = true
									parentPanel.data.changePending = true
									parentPanel.data.focusPending = true
									printf("GOBLINSCRIPT:: FINISH PRESS")
								end,

								hover = function(element)
									if completion.desc ~= nil then
										gui.Tooltip{
											text = completion.desc,
											valign = "center",
											halign = "right"
										}(element)
									end
								end,
							}
						end

						table.sort(children, function(a,b) return a.text < b.text end)

						local cursor = 1
						local refreshCompletions = function()
							for i,child in ipairs(children) do
								child:SetClass("selected", i == cursor)
							end
						end

						refreshCompletions()

						local menuHeight = 300
						local menu = gui.Panel{
							classes = {"menu"},
							bgimage = "panels/square.png",
							width = element.renderedWidth,
							height = "auto",
							maxHeight = menuHeight,
							flow = "vertical",
							vscroll = true,
							children = children,

							tab = function(element)
								printf("GOBLINSCRIPT:: TAB with index = %s", json(cursor))
								children[cursor]:FireEvent("press")
							end,

							uparrow = function(element)
								cursor = cursor-1
								if cursor < 1 then
									cursor = #children
								end
								refreshCompletions()
							end,
							downarrow = function(element)
								cursor = cursor+1
								if cursor > #children then
									cursor = 1
								end
								refreshCompletions()
							end,
						}
						element.popup = gui.Panel{
							styles = {Styles.Default, g_completionMenuStyles},
							width = "auto",
							height = menuHeight,
							scale = parentPanel.renderedScale.x,
							valign = "bottom",
							halign = "center",
							menu,
						}
						printf("GOBLINSCRIPT:: POPUP: %d", #children)
					end
					printf("GOBLINSCRIPT:: COMPLETIONS:: %s", json(completions))
				end,
			}
			inputTable = nil
			container.children = {inputText}
		end
	end

	local InitTable = function()
		if inputTable ~= nil and inputTable.data.upcastStyle ~= m_value.upcastStyle then
			inputTable:DestroySelf()
			inputTable = nil
		end

		if inputTable == nil then
			local fieldHeadingLabel
			local fieldValueLabel

			local headingRow
			local newRow

			local baseRow
			local upcastRow

			if m_value.upcastStyle then

				local baseLabel = gui.Label{
					text = m_value.baseLabel,
					width = editWidth*0.35-8,
				}

				local baseInput = gui.Input{
					width = editWidth*0.65-20,
					multiline = false,
					height = 20,
					text = m_value.entries[1].script,
					bgcolor = "clear",
					borderFade = true,
					border = 0,
					change = function(element)
						m_value.entries[1].script = element.text
						resultPanel:FireEvent("change", m_value)
					end,
				}

				baseRow = gui.TableRow{
					baseLabel,
					baseInput,
				}

				local upcastLabel = gui.Label{
					text = m_value.upcastLabel,
					width = editWidth*0.35-8,
				}

				local upcastInput = gui.Input{
					width = editWidth*0.65-20,
					multiline = false,
					height = 20,
					text = m_value.entries[2].script,
					bgcolor = "clear",
					borderFade = true,
					border = 0,
					change = function(element)
						m_value.entries[2].script = element.text
						resultPanel:FireEvent("change", m_value)
					end,
				}

				upcastRow = gui.TableRow{
					upcastLabel,
					upcastInput,
				}

			else

				fieldHeadingLabel = gui.Label{
					text = "",
					width = editWidth*0.35-8,
					change = function(element)
						if element.text == "" then
							element.text = m_value.field
							return
						end

						m_value.field = element.text
						resultPanel:FireEvent("change", m_value)
					end,
				}
				fieldValueLabel = gui.Label{
					text = "Value",
					width = editWidth*0.65-8,
				}
				headingRow = gui.TableRow{
					fieldHeadingLabel,
					fieldValueLabel,
				}


				local addNewRow = function()
					if newFieldInput.text ~= "" and newValueInput.text ~= "" then
						m_value.entries[#m_value.entries+1] = {
							threshold = tonumber(newFieldInput.text),
							script = newValueInput.text,
						}

						m_value:Normalize()

						newFieldInput.text = ""
						newValueInput.text = ""

						resultPanel.value = m_value
						resultPanel:FireEvent("change", m_value)

						gui.SetFocus(nil)
						dmhub.Schedule(0.05, function()
							if newFieldInput ~= nil and newFieldInput.valid then
								gui.SetFocus(newFieldInput)
							end
						end)
					end
				end

				newFieldInput = gui.Input{
					text = "",
					width = editWidth*0.35 - 20,
					multiline = false,
					height = 20,
					change = function(element)
						if tonumber(element.text) == nil then
							element.text = ""
						end

						addNewRow()
					end,
				}
				newValueInput = gui.Input{
					text = "",
					width = editWidth*0.65 - 20,
					multiline = false,
					height = 20,
					change = function(element)
						addNewRow()
					end,
				}
				newRow = gui.TableRow{
					newFieldInput,
					newValueInput,
				}
			end

			inputTable = gui.Table{
				data = {
					upcastStyle = m_value.upcastStyle,
				},
				width = "100%",
				height = "auto",
				minHeight = 30,
				styles = {
					{
						classes = {"label"},
						fontSize = 14,
						valign = "center",
						minHeight = 30,
						hmargin = 4,
						textAlignment = "left",
						width = "auto",
						height = "auto",
						color = "#dddddd"
					},
					{
						classes = {"input"},
						valign = "center",
						fontSize = 14,
					},
					{
						classes = {"row"},
						width = "100%",
						height = "auto",
						flow = "horizontal",
						bgimage = "panels/square.png",
					},
					{
						selectors = {"row", "evenRow"},
						bgcolor = "black",
					},
					{
						selectors = {"row", "oddRow"},
						bgcolor = "#333333ff",
					},
				},
				setValue = function(element, val)
					if val.upcastStyle then
						return
					end

					fieldHeadingLabel.editable = val.editableField
					fieldHeadingLabel.text = val.field
					fieldValueLabel.text = fieldName
					local children = {headingRow}
					for i,entry in ipairs(val.entries) do
						local fieldLabel = gui.Label{
							width = editWidth*0.35,
							height = "auto",
							text = tostring(entry.threshold),
							editable = true,
							change = function(element)
								if tonumber(element.text) == nil then
									element.text = tostring(entry.threshold)
									return
								end

								entry.threshold = tonumber(element.text)
								m_value:Normalize()
								resultPanel.value = m_value
								resultPanel:FireEvent("change", m_value)
							end,
						}
						local fieldValue = gui.Label{
							width = editWidth*0.55,
							height = "auto",
							text = tostring(entry.script),
							editable = true,
							change = function(element)
								entry.script = element.text
								resultPanel:FireEvent("change", m_value)
							end,
						}
						local deleteButton = gui.DeleteItemButton{
							halign = "right",
							valign = "center",
							width = 12,
							height = 12,
							x = -12,

							click = function(element)
								table.remove(m_value.entries, i)
								resultPanel.value = m_value
								resultPanel:FireEvent("change", m_value)
							end,
						}
						children[#children+1] = gui.TableRow{
							fieldLabel,
							fieldValue,
							deleteButton,
						}
					end

					children[#children+1] = newRow
					element.children = children
				end,

				headingRow,
				newRow,
				baseRow,
				upcastRow,
			}



			inputText = nil
			container.children = {inputTable}
		end
	end

    local changeEvent = options.change
    if changeEvent == nil and options.events then
        changeEvent = options.events.change
        options.events.change = nil
    end
    options.change = nil

	local args
	args = {
		width = 360,
		height = "auto",

		textAlignment = "topleft",

        change = function(element, value)
            if changeEvent ~= nil then
                changeEvent(element, value)
            end

            element:FireEventTree("checkerror", value)
        end,

		flow = "vertical",
		GetValue = function(element)
			return m_value
		end,
		SetValue = function(element, val)
			m_value = val
			if type(val) ~= "table" then
				InitText()
				if type(val) == "number" then
					inputText.text = numtostr(val)
				else
					inputText.text = tostring(val)
				end
			else
				InitTable()
				inputTable:FireEvent("setValue", val)
			end
		end,

		data = {
			inputText = inputText,
		},

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",

            container,

            gui.Panel{

                classes = {"goblinScriptLogo"},
                width = 24,
                height = 24,
                halign = "right",
                valign = "center",
                bgcolor = "white",
                bgimage = "ui-icons/DMHubLogo.png",
                click = function(element)

                    local menuItems = {}

                    local standardDisplayTypes = {
                        {
                            id = "text",
                            text = "Text Formula",
                            value = "",
                        },

                        {
                            id = "table",
                            text = "Custom Table",
                            value = GoblinScriptTable.new{
                                id = "table",
                                field = "Level",
                                editableField = true,
                                entries = {
                                    {
                                        threshold = 1,
                                        script = "",
                                    }
                                }
                            }
                        },
                    }

                    if displayTypes ~= nil then
                        if displayTypes == "none" then
                            standardDisplayTypes = nil
                        else
                            for i,displayType in ipairs(displayTypes) do
                                standardDisplayTypes[#standardDisplayTypes+1] = displayType
                            end
                        end
                    end

                    local displayTypes = standardDisplayTypes

                    if displayTypes ~= nil then
                        for i,displayType in ipairs(displayTypes) do
                            local check = false
                            if type(displayType.value) == "string" and type(resultPanel.value) == "string" then
                                check = true
                            end

                            if type(displayType.value) == "table" and type(resultPanel.value) == "table" and displayType.value.id == resultPanel.value.id then
                                check = true
                            end
                            menuItems[#menuItems+1] = {
                                group = "displayType",
                                text = displayType.text,
                                check = check,
                                click = function()
                                    local currentValue = resultPanel.value
                                    if type(currentValue) == "table" then
                                        currentValue = currentValue:ToText()
                                    end

                                    local val = DeepCopy(displayType.value)
                                    if type(currentValue) == "number" or type(currentValue) == "string" then
                                        if type(val) == "table" then
                                            val:FromText(currentValue)
                                        elseif val == "" then
                                            val = currentValue
                                        end
                                    end

                                    resultPanel.value = val
                                    resultPanel:FireEvent("change", resultPanel.value)
                                    element.popup = nil
                                end
                            }
                        end
                    end

                    menuItems[#menuItems+1] = {
                        text = "Copy",
                        group = "clipboard",
                        click = function()
                            element.popup = nil
                            dmhub.CopyToInternalClipboard(resultPanel.value)
                        end,
                    }

                    local clipboardItem = dmhub.GetInternalClipboard()
                    if type(clipboardItem) == "string" or (type(clipboardItem) == "table" and clipboardItem.typeName == "GoblinScriptTable") then
                        menuItems[#menuItems+1] = {
                            text = "Paste",
                            group = "clipboard",
                            click = function()
                                element.popup = nil
                                resultPanel.value = DeepCopy(clipboardItem)
                                resultPanel:FireEvent("change", resultPanel.value)
                            end,
                        }
                    end


                    menuItems[#menuItems+1] = {
                        text = "Formula Documentation",
                        group = "docs",
                        click = function()
                            element.popup = nil
                            element.root:AddChild(gui.GoblinScriptEditorDialog{
                                documentation = documentation,
                                text = m_value,
                                change = function(element, text)
                                    m_value = text
                                    resultPanel.value = m_value
                                    resultPanel:FireEvent("change", m_value)
                                end,
                            })
                        end,
                    }

                    if devmode() then
                        menuItems[#menuItems+1] = {
                            text = "Show Lua (Debug)",
                            group = "docs",
                            click = function()
                                element.popup = nil
                                element.root:AddChild(gui.GoblinScriptLuaDialog{
                                    formula = m_value,
                                })
                            end,
                        }
                    end

                    element.popupPositioning = 'mouse'
                    element.popup = gui.ContextMenu{
                        entries = menuItems,
                    }
                end,
                styles = {
                    {
                        selectors = {"hover"},
                        brightness = 1.5,
                    },
                    {
                        selectors = {"press"},
                        brightness = 0.8,
                    },
                }
            },
        },

        gui.Label{
            classes = {"collapsed"},
            bgimage = true,
            bgcolor = "red",
            width = "100%",
            height = "auto",
            text = "Error message",
            fontSize = 14,

            checkerror = function(element, value)
                if type(value) ~= "string" then
                    element:SetClass("collapsed", true)
                    return
                end

                if string.find(value, "<<") ~= nil or string.find(value, ">>") ~= nil or string.find(value, "%f[%w]d%f[%W]") ~= nil or string.find(value, "%dd%d") ~= nil or string.find(value, "%f[%w]d%d") ~= nil or string.find(value, "%dd%f[%W]") ~= nil then
                    --this is not a normal deterministic goblin script.
                    element:SetClass("collapsed", true)
                    return
                end

                local out = {}
                local fn = dmhub.CompileGoblinScriptDeterministic(value, out)
                if out.error ~= nil then
                    element.text = "Error: " .. out.error
                    element:SetClass("collapsed", false)
                else
                    element:SetClass("collapsed", true)
                end
            end,
            create = function(element)
                element:FireEvent("checkerror", input_value)
            end,
        },
	}

	for k,option in pairs(options) do
		args[k] = option
	end

	resultPanel = gui.Panel(args)

	if input_value ~= nil then
		resultPanel.value = input_value
	end

	return resultPanel
end

setting{
	id = "goblin-script-docs:collapse-examples",
	description = "Collapse examples in Goblin Script docs",
	storage = "preferences",
	default = false,
}

setting{
	id = "goblin-script-docs:collapse-subject",
	description = "Collapse subject in Goblin Script docs",
	storage = "preferences",
	default = false,
}

setting{
	id = "goblin-script-docs:collapse-additional-fields",
	description = "Collapse additional fields in Goblin Script docs",
	storage = "preferences",
	default = false,
}

local CollapsibleSectionPanel = function(options)

	options = dmhub.DeepCopy(options)

	local GetCollapsed = function()
		return dmhub.GetSettingValue(options.collapseSetting)
	end
	local SetCollapsed = function(val)
		dmhub.SetSettingValue(options.collapseSetting, val)
	end

	local contentPanel = options.content
	contentPanel.classes = contentPanel.classes or {}
	if GetCollapsed() then
		contentPanel.classes[#contentPanel.classes+1] = "collapsed-anim"
	end
	
	contentPanel = gui.Panel(contentPanel)

	local headerPanel = gui.Panel{
		bgimage = "panels/square.png",
		bgcolor = "clear",
		width = "auto",
		flow = "horizontal",
		height = 30,
		halign = "left",
		classes = cond(GetCollapsed(), nil, "expanded"),
		click = function(element)
			SetCollapsed(not GetCollapsed())
			contentPanel:SetClass("collapsed-anim", GetCollapsed())
			element:SetClass("expanded", not GetCollapsed())
		end,

		gui.Panel{
			interactable = false,
			bgimage = "panels/triangle.png",
			valign = "center",
			hmargin = 8,
			halign = "left",

			width = 20,
			height = 20,

			styles = {
				{
					bgcolor = "white",
				},
				{
					selectors = {"parent:hover"},
					bgcolor = "yellow",
				},
				{
					selectors = {"~parent:expanded"},
					rotate = 90,
				},
			}
		},

		gui.Label{
			hmargin = 16,
			fontSize = 20,
			color = "white",
			halign = "left",
			valign = "center",
			width = "auto",
			height = "auto",
			text = options.title,
			interactable = false,
		},
	}

	return gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",

		headerPanel,
		contentPanel,
	}
end

local GoblinScriptFriendlyTypeNames = {
	boolean = "true or false"
}

local GetFriendlyTypeName = function(name)
	return GoblinScriptFriendlyTypeNames[name] or name
end

local g_registeredTypeInfo = {}

local GetTypeInfoMap = function()
    local result = {
        creature = creature.helpSymbols,
        attack = Attack.helpSymbols,
        weapon = weapon.helpSymbols,
        aura = AuraInstance.helpSymbols,
        ability = ActivatedAbility.helpSymbols,
        equipment = equipment.helpSymbols,
        spellcast = ActivatedAbilityCast.helpSymbols,
		ongoingeffect = CharacterOngoingEffectInstance.helpSymbols,
		resources = CharacterResourceCollection.helpSymbols,
        path = PathMoved.helpSymbols,
    }
	
	-- Add registered types
	for typeName, helpSymbols in pairs(g_registeredTypeInfo) do
		result[typeName] = helpSymbols
	end
	
	return result
end

dmhub.GetSymbolTypesDocumentation = GetTypeInfoMap

RegisterGoblinScriptTypeInfo = function(typeName, helpSymbols)
	local normalizedTypeName = string.gsub(string.lower(typeName), " ", "")
	g_registeredTypeInfo[normalizedTypeName] = helpSymbols
end

local FieldsPanel = function(fields, options)
    local typeInfoMap = GetTypeInfoMap()

	options = options or {}
	local entries = {}

	for k,field in pairs(fields) do
		
		if not string.starts_with(k, "_") and (field.domain == nil or (options.domains ~= nil and options.domains[field.domain])) then
			entries[#entries+1] = field
		end
	end

	table.sort(entries, function(a,b) return a.name < b.name end)

	local panels = {}

	for _,entry in ipairs(entries) do
		local typeid = string.gsub(string.lower(entry.type or "(unknown)"), " ", "")
		local getTypeInfoLink = nil
		if typeInfoMap[typeid] ~= nil then
			getTypeInfoLink = gui.Label{
				text = "See all fields for " .. entry.type,
				bgimage = "panels/square.png",
				bgcolor = "clear",
				halign = "left",
				vmargin = 6,
				bold = true,
				width = "auto",
				height = "auto",
				fontSize = 14,
				styles = {
					{
						selectors = {"label"},
						color = "#bb88ff",
						border = {x1=0,x2=0,y2=0,y1=2},
						borderColor = "#bb88ff",
					},
					{
						selectors = {"label", "hover"},
						color = "#ff66ff",
						borderColor = "#ff66ff",
					},
					{
						selectors = {"label", "press"},
						color = "#ffaaff",
						borderColor = "#ffaaff",
					},
				},

				click = function(element)
					element.root:AddChild(gui.GoblinScriptTypeInfoDialog{
						typeinfo = typeInfoMap[typeid],
						type = entry.type,
						parentField = entry.name,
					})
				end,
			}
			
		end

		local examplesPanel = nil

		if entry.examples ~= nil then

			examplesPanel = gui.Panel{
				flow = "vertical",
				width = "100%",
				height = "auto",
				halign = "left",
				gui.Label{
					fontSize = 14,
					width = "auto",
					height = "auto",
					halign = "left",
					text = "Examples",
					bold = true,
				},
			}

			for _,example in ipairs(entry.examples) do
				local exampleStr = example
				if options.parentField ~= nil then
					--If there is a parent field, substitute the examples, to say e.g. Target.Hitpoints not just Hitpoints.
					exampleStr = exampleStr:gsub("OBJ.", options.parentField .. ".")
				else
					exampleStr = exampleStr:gsub("OBJ.", "")
				end

				examplesPanel:AddChild(gui.Label{
					text = exampleStr,
					color = "#ccccff",
					width = "auto",
					height = "auto",
					fontSize = 14,
					halign = "left",
				})
			end
		end

		local seeAlsoPanel = nil
		if entry.seealso ~= nil and #entry.seealso > 0 then
			local list = ""
			for i,item in ipairs(entry.seealso) do
				if i ~= 1 then
					list = list .. ", "
				end

				list = list .. item
			end
			seeAlsoPanel = gui.Label{
				width = "auto",
				height = "auto",
				halign = "left",
				color = "white",
				fontSize = 14,
				text = "<b>See also</b>: " .. list
			}
		end

		local descriptionText = entry.desc
		if entry.domain ~= nil and string.starts_with(entry.domain, "class:") then
			local classid = entry.domain:sub(7)
			local classesTable = dmhub.GetTable("classes")
			local classInfo = classesTable[classid]
			if classInfo ~= nil then
				descriptionText = string.format("<color=#aaffaa><b>%s-specific field</b></color>\n%s", classInfo.name, descriptionText)
			end
		end

		if typeInfoMap[entry.type] ~= nil then
			local typeInfo = typeInfoMap[entry.type]
			local sampleText = ""
			for i,field in ipairs(typeInfo.__sampleFields or {}) do
				if sampleText == "" then
					sampleText = "For instance, "
				end

				local fieldInfo = typeInfo[field]

				if fieldInfo == nil then
					dmhub.CloudError(string.format("Unknown GoblinScript sample field: %s", field))
				else
					if i ~= 1 then
						sampleText = sampleText .. ' or '
					end

					sampleText = string.format("%s<b>%s.%s</b>", sampleText, entry.name, fieldInfo.name)
				end
			end
			descriptionText = string.format("%s\n\nThis field is a <b>%s</b> with many sub-fields. You can access sub-fields using a <b>.</b> after the field. %s", descriptionText, entry.type, sampleText)
		end

		panels[#panels+1] = gui.Panel{
			flow = "vertical",
			vmargin = 8,
			height = "auto",
			width = "100%",
			valign = "top",

			gui.Panel{
				flow = "horizontal",
				width = "auto",
				height = "auto",
				halign = "left",
				gui.Label{
					halign = "left",
					minWidth = 180,
					width = "auto",
					height = "auto",
					fontSize = 18,
					color = "white",
					bold = true,
					text = entry.name,
				},
				gui.Label{
					halign = "left",
					width = "auto",
					height = "auto",
					hmargin = 8,
					fontSize = 16,
					color = "#ccffcc",
					text = GetFriendlyTypeName(entry.type),
				},
			},
			gui.Label{
				width = "100%",
				height = "auto",
				fontSize = 14,
				textWrap = true,
				text = descriptionText,
				color = "white",
			},
			getTypeInfoLink,
			examplesPanel,
			seeAlsoPanel,
		}
	end

	return gui.Panel{
		flow = "vertical",
		valign = "top",
		width = "100%",
		height = "auto",
		children = panels,
	}
end

local GoblinScriptObjectHelpStrings = {
	ability = "Creatures have abilities which they can expend actions and other resources to use. Spells and attacks are both types of abilities.",
	proximity = "An ability that has a proximity requires all targets beyond the first to be within this range of the first target.",
}


function gui.GoblinScriptLuaDialog(options)
    local formula = options.formula
    options.formula = nil
	local dialogWidth = 1200
	local dialogHeight = 980

    local resultPanel = nil

    local out = {}
    dmhub.CompileGoblinScriptDeterministic(formula, out)
    local lua = GoblinScriptDebug.formulaOverrides[formula] or out.lua

	local closePanel = 
		gui.Panel{
			style = {
				valign = 'bottom',
				flow = 'horizontal',
				height = 60,
				width = '100%',
				fontSize = '60%',
				vmargin = 0,
			},
		}

	closePanel:AddChild(gui.PrettyButton{
		text = 'Close',
		style = {
			height = 60,
			width = 160,
			fontSize = 44,
			bgcolor = 'white',
		},
		events = {
			click = function(element)
				resultPanel.data.close()
			end,
		},
	})


	local titleLabel = gui.Label{
		text = "GoblinScript Lua",
		valign = 'top',
		halign = 'center',
		width = 'auto',
		height = 'auto',
		color = 'white',
		fontSize = 28,
	}

    local mainFormPanel = gui.Panel{
		bgcolor = 'white',
		pad = 0,
		margin = 0,
		width = 1060,
		height = 840,
        flow = "vertical",
        gui.Label{
            valign = "top",
            fontSize = 14,
            width = "100%",
            height = "auto",
            text = string.format("This is the Lua used for the formula <b>%s</b>. Editing the Lua will replace it for this session as a debugging feature but the changes will not be saved once you exit the Codex.", formula),
        },

        gui.Input{
            fontSize = 16,
            fontFace = "courier",
            multiline = true,
            textAlignment = "topleft",
            width = 1060,
            height = 600,
            halign = "center",
            valign = "center",
            text = lua,
            editable = true,
            characterLimit = 8192,
            clear = function(element)
                element.text = lua
            end,
            editlag = 0.2,
            edit = function(element)
                if resultPanel == nil or element.text == lua then
                    return
                end
                local chunk, err = load(element.text)
                if not chunk then
                    resultPanel:FireEventTree("showmessage", "Lua Error: " .. err)
                    return
                end

                local ok, result = pcall(chunk)
                if not ok then
                    resultPanel:FireEventTree("showmessage", "Lua Runtime Error: " .. result)
                    return
                end

                if type(result) ~= "function" then
                    resultPanel:FireEventTree("showmessage", "Lua Error: Script did not return a function.")
                    return
                end

                GoblinScriptDebug.OverrideFormula(formula, result, element.text)

                resultPanel:FireEventTree("showmessage", "Custom Lua code loaded for this GoblinScript")
                lua = element.text
            end,
        },
        gui.Panel{
            flow = "horizontal",
            width = 1060,
            height = 80,
            gui.Panel{
                width = 620,
                height = 80,
                vscroll = true,
                gui.Label{
                    width = 600,
                    height = 80,
                    halign = "left",
                    fontSize = 14,
                    showmessage = function(element, message)
                        element.text = message
                    end,
                },
            },

            gui.Button{
                classes = {cond(GoblinScriptDebug.formulaOverrides[formula] ~= nil, nil, "hidden")},
                width = 180,
                height = 22,
                fontSize = 18,
                text = "Clear Debug Lua",
                showmessage = function(element, message)
                    element:SetClass("hidden", GoblinScriptDebug.formulaOverrides[formula] == nil)
                end,
                click = function(element)
                    GoblinScriptDebug.OverrideFormula(formula, nil, nil)
                    resultPanel:FireEventTree("showmessage", "")
                    lua = out.lua
                    resultPanel:FireEventTree("clear")
                end,
            }
        },
    }

	local args = {
		style = {
			bgcolor = 'white',
			width = dialogWidth,
			height = dialogHeight,
			halign = 'center',
			valign = 'center',
		},
		styles = {
			Styles.Default,
			Styles.Panel,
		},

		classes = {"framedPanel"},

		floating = true,

		captureEscape = true,
		escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
		escape = function(element)
			element.data.close()
		end,

		data = {
			close = function()
				resultPanel:FireEvent("close")
				resultPanel:DestroySelf()
			end,
		},

		children = {

			gui.Panel{
				id = 'content',
				styles = {
					{
						halign = 'center',
						valign = 'center',
						width = '94%',
						height = '94%',
						flow = 'vertical',
					},
				},
				children = {
					titleLabel,
					mainFormPanel,
					closePanel,

				},
			},
		},
	}

	for k,option in pairs(options) do
		args[k] = option
	end

	resultPanel = gui.Panel(args)

    if out.error then
        resultPanel:FireEventTree("showmessage", "Compilation Error: " .. out.error)
    end

	return resultPanel

end

function gui.GoblinScriptEditorDialog(options)
	options = dmhub.DeepCopy(options or {})

	local dialogWidth = 1200
	local dialogHeight = 980

	local resultPanel = nil

	local inputPanel = nil
	
	if type(options.text) ~= "table" then
		inputPanel = gui.Input{
			width = "90%",
			halign = "left",
			valign = "top",
			textAlignment = "topleft",
			hmargin = 8,
			vmargin = 8,
			multiline = true,
			height = "auto",
			minHeight = 80,
			fontSize = 16,
			text = options.text,
			change = function(element)
				resultPanel:FireEvent("change", element.text)
			end,
		}
	end

	local documentationPanel = nil

	if options.documentation ~= nil then
		documentationPanel = gui.Panel{
			flow = "vertical",
			valign = "top",
			width = "100%",
			height = "auto",

			gui.Label{
				halign = "left",
				valign = "top",
				vmargin = 4,
				fontSize = 14,
				text = options.documentation.help,
				links = true,
				width = "100%",
				height = "auto",
				textWrap = true,

				hoverLink = function(element, linkid)
					dmhub.Debug("LINK:: HOVER: " .. linkid .. " IN " .. dmhub.ToJson(GoblinScriptObjectHelpStrings) .. " OUTPUT TO " .. dmhub.ToJson(GoblinScriptObjectHelpStrings[linkid]))
					local help = GoblinScriptObjectHelpStrings[linkid]
					if help ~= nil then
						dmhub.Debug("LINK:: SHOW: " .. help)
						gui.Tooltip(help)(element)
					end
				end,

				dehoverLink = function(element, linkid)
					element.tooltip = nil
				end,
			},
		}

		if options.documentation.examples ~= nil then
			
			local examplePanels = {}
			for _,example in ipairs(options.documentation.examples) do
				examplePanels[#examplePanels+1] = gui.Panel{
					flow = "horizontal",
					height = "auto",
					width = "100%",
					vmargin = 16,
					gui.Label{
						minWidth = 140,
						width = "auto",
						height = "auto",
						color = "#ccccff",
						fontSize = 18,
						text = example.script,
						textAlignment = "left",
						halign = "left",
					},
					gui.Label{
						width = "50%",
						height = "auto",
						halign = "left",
						hmargin = 16,
						fontSize = 16,
						italics = true,
						color = "#ccffcc",
						text = example.text,
						textAlignment = "left",
					}
				}
			end

			local listPanel = {
				flow = "vertical",
				halign = "left",
				height = "auto",
				width = "100%",

				children = examplePanels,
			}

			documentationPanel:AddChild(
				CollapsibleSectionPanel{
					collapseSetting = "goblin-script-docs:collapse-examples",
					title = "Examples",
					content = listPanel,
				}
			)

			documentationPanel:AddChild(
				CollapsibleSectionPanel{
					collapseSetting = "goblin-script-docs:collapse-subject",
					title = "Self",
					content = {
						flow = "vertical",
						halign = "left",
						height = "auto",
						width = "100%",
						gui.Label{
							fontSize = 16,
							text = string.format("%s is self for this script. Any of its fields can be used directly as terms within the script.", options.documentation.subjectDescription),
							width = "100%",
							height = "auto",
							textWrap = true,
							halign = "left",
							textAlignment = "left",
						},
						FieldsPanel(options.documentation.subject, {domains = options.documentation.domains}),
					},
				}
			)

			if options.documentation.symbols ~= nil then
				documentationPanel:AddChild(
					CollapsibleSectionPanel{
						collapseSetting = "goblin-script-docs:collapse-additional-fields",
						title = "Additional Fields",
						content = {
							flow = "vertical",
							halign = "left",
							height = "auto",
							width = "100%",
							gui.Label{
								fontSize = 16,
								text = "In addition to the self creature, this GoblinScript can use the following situational fields as terms within the script.",
								width = "100%",
								height = "auto",
								textWrap = true,
								halign = "left",
								textAlignment = "left",
							},
							FieldsPanel(options.documentation.symbols),
						},
					}
				)
			end

		end


	end

	options.documentation = nil
	options.text = nil

	local mainFormPanel = gui.Panel{
		style = {
			bgcolor = 'white',
			pad = 0,
			margin = 0,
			width = 1060,
			height = 840,
		},
		vscroll = true,

		inputPanel,
		documentationPanel,
	}

	local newItem = nil

	local closePanel = 
		gui.Panel{
			style = {
				valign = 'bottom',
				flow = 'horizontal',
				height = 60,
				width = '100%',
				fontSize = '60%',
				vmargin = 0,
			},
		}

	closePanel:AddChild(gui.PrettyButton{
		text = 'Close',
		style = {
			height = 60,
			width = 160,
			fontSize = 44,
			bgcolor = 'white',
		},
		events = {
			click = function(element)
				resultPanel.data.close()
			end,
		},
	})


	local titleLabel = gui.Label{
		text = "GoblinScript Editor",
		valign = 'top',
		halign = 'center',
		width = 'auto',
		height = 'auto',
		color = 'white',
		fontSize = 28,
	}

	local args = {
		style = {
			bgcolor = 'white',
			width = dialogWidth,
			height = dialogHeight,
			halign = 'center',
			valign = 'center',
		},
		styles = {
			Styles.Default,
			Styles.Panel,
		},

		classes = {"framedPanel"},

		floating = true,

		captureEscape = true,
		escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
		escape = function(element)
			element.data.close()
		end,

		data = {
			close = function()
				if inputPanel ~= nil then
					resultPanel:FireEvent("change", inputPanel.text)
				end
				resultPanel:FireEvent("close")
				resultPanel:DestroySelf()
			end,
		},

		children = {

			gui.Panel{
				id = 'content',
				styles = {
					{
						halign = 'center',
						valign = 'center',
						width = '94%',
						height = '94%',
						flow = 'vertical',
					},
				},
				children = {
					titleLabel,
					mainFormPanel,
					closePanel,

				},
			},
		},
	}

	for k,option in pairs(options) do
		args[k] = option
	end

	resultPanel = gui.Panel(args)

	return resultPanel
end

function gui.GoblinScriptTypeInfoDialog(options)
	options = dmhub.DeepCopy(options or {})

	local dialogWidth = 1200
	local dialogHeight = 980

	local resultPanel = nil

	local parentField = options.parentField
	local documentationPanel = FieldsPanel(options.typeinfo, {parentField = parentField})
	local typeName = options.type
	options.typeinfo = nil
	options.parentField = nil
	options.type = nil

	local mainFormPanel = gui.Panel{
		style = {
			bgcolor = 'white',
			pad = 0,
			margin = 0,
			width = 1060,
			height = 840,
		},
		vscroll = true,

		documentationPanel,
	}

	local newItem = nil

	local closePanel = 
		gui.Panel{
			style = {
				valign = 'bottom',
				flow = 'horizontal',
				height = 60,
				width = '100%',
				fontSize = '60%',
				vmargin = 0,
			},
		}

	closePanel:AddChild(gui.PrettyButton{
		text = 'Close',
		style = {
			height = 60,
			width = 160,
			fontSize = 44,
			bgcolor = 'white',
		},
		events = {
			click = function(element)
				resultPanel.data.close()
			end,
		},
	})


	local titleLabel = gui.Label{
		text = string.format("Fields for %s which is a %s", parentField, typeName),
		valign = 'top',
		halign = 'center',
		width = 'auto',
		height = 'auto',
		color = 'white',
		fontSize = 28,
	}

	local args = {
		style = {
			bgcolor = 'white',
			width = dialogWidth,
			height = dialogHeight,
			halign = 'center',
			valign = 'center',
		},
		styles = {
			Styles.Default,
			Styles.Panel,
		},

		classes = {"framedPanel"},

		floating = true,

		captureEscape = true,
		escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
		escape = function(element)
			element.data.close()
		end,

		data = {
			close = function()
				resultPanel:FireEvent("close")
				resultPanel:DestroySelf()
			end,
		},

		children = {

			gui.Panel{
				id = 'content',
				styles = {
					{
						halign = 'center',
						valign = 'center',
						width = '94%',
						height = '94%',
						flow = 'vertical',
					},
				},
				children = {
					titleLabel,
					mainFormPanel,
					closePanel,

				},
			},
		},
	}

	for k,option in pairs(options) do
		args[k] = option
	end

	resultPanel = gui.Panel(args)

	return resultPanel
end


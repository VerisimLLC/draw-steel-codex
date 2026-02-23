local mod = dmhub.GetModLoading()

local ChangeLabelValue = function(info, label, newtext)

	if label.data.charid ~= nil and label.data.charid == info.charid and newtext ~= label.text then
		local currentnum = tonumber(label.text)
		local newnum = tonumber(newtext)
		if currentnum ~= nil and newnum ~= nil and currentnum ~= newnum then
			label:PulseClass(cond(currentnum < newnum, "increase", "decrease"))
		end
	end

	label.text = newtext
	label.data.charid = info.charid

	previousCharId = info.charid
	
end


local PopupStyles = {

	{
		valign = 'bottom',
		halign = 'center',
		width = 'auto',
		height = 'auto',
		bgcolor = 'black',
		flow = 'vertical',
		fontSize = 12,
	},
	{
		selectors = {'popupWindow'},
		valign = 'bottom',
		halign = 'center',
		width = 300,
		height = 'auto',
		bgcolor = 'black',
		flow = 'vertical',
		borderWidth = 2,
		borderColor = 'white',
		pad = 6,
	},
	{
		selectors = {'popupPanel'},
		flow = 'horizontal',
		width = 'auto',
		height = 'auto',
		vmargin = 4,
	},
	{
		selectors = {'popupLabel'},
		color = 'white',
		fontSize = 16,
		width = 'auto',
		height = 'auto',
		minWidth = 220,
		valign = "center",
	},
	{
		selectors = {'popupValue'},
		color = 'white',
		fontSize = 16,
		width = 'auto',
		height = 'auto',
		minWidth = 40,
	},

	{
		selectors = {"formPanel"},
		flow = "horizontal",
		width = '100%',
		height = 20,
	},
	{
		selectors = {'editable'},
		color = '#aaaaff',
		priority = 2,
	},
	{
		selectors = {'option'},
		bgcolor = 'black',
		width = '100%',
		height = 20,
	},
	{
		selectors = {'option','selected'},
		bgcolor = '#880000',
	},
	{
		selectors = {'option','hover'},
		bgcolor = '#880000',
	},
	{
		selectors = {'input'},
		bold = true,
		fontFace = "inter",
		fontSize = 14,
		height = 18,
		width = 180,
	},
}

local CreatePanelFooter = function(args)
	local resultPanel
	local text = args.text or ""
	args.text = nil

	--only show settings button if we have a 'settings' arg to handle it.
	local settingsButton = nil
	if args.settings ~= nil then
		settingsButton = gui.Panel{
			classes = {"panelSettingsButton"},
			click = function(element)
				resultPanel:FireEvent("settings")
			end,
		}
	end

	local params = {
		classes = {"panelFooter"},
		interactable = false,
		gui.Label{
			classes = {"panelFooterLabel"},
			text = text,
		},

		settingsButton,
	}

	for k,v in pairs(args) do
		params[k] = v
	end

	resultPanel = gui.Panel(params)
	return resultPanel
end

function CharSheet.CharacterArmorClassPanel()

	local resultPanel

	resultPanel = gui.Panel{
		classes = {"attributePanel", "armorClass"},
		gui.Panel{
			classes = {"attributeModifierPanel", "armorClass"},
			gui.Label{
				classes = {"attributeModifierLabel", "valueLabel", "armorClass"},
				characterLimit = 2,
				minWidth = 80,
				refreshToken = function(element, info)
					local creature = info.token.properties
					element.text = string.format("%d", info.token.properties:ArmorClass())
				end,
			},
			hover = function(element)
				local creature = CharacterSheet.instance.data.info.token.properties
				if element.popup == nil and creature:ArmorClassDetails() ~= nil then
					gui.Tooltip('Click for calculation details and to edit armor class')(element)
				end
			end,
			press = function(element)
				local creature = CharacterSheet.instance.data.info.token.properties
				element.tooltip = nil

				local armorClassElement = element

				if element.popup ~= nil then
					element.popup = nil
					return
				end

				local panels = {}

				local details = creature:ArmorClassDetails()
				if details == nil then
					return
				end

				local showNotes = false

				for i,entry in ipairs(details) do

					showNotes = showNotes or entry.showNotes

					local textValue = entry.value
					if entry.edit ~= nil and textValue == nil then
						textValue = '(none)'
					end

					if tonumber(textValue) ~= nil then
						textValue = string.format("%d", round(tonumber(textValue)))
					end

					panels[#panels+1] = gui.Panel({
						style = {
							width = 240,
							height = 24,
							fontSize = 20,
							halign = 'center',
							valign = 'center',
							flow = 'horizontal',
						},

						children = {
							gui.Label({
								text = entry.key,
								style = {
									width = 'auto',
									height = 'auto',
									textAlignment = 'left',
									halign = 'left',
									valign = 'center',
								},
							}),
							gui.Panel{ --padding.
								style = {
									width = 8,
									height = 1,
								},
							},
							gui.Label({
								text = textValue,
								editable = entry.edit ~= nil,
								style = {
									width = 'auto',
									height = 'auto',
									textAlignment = 'right',
									halign = 'right',
									valign = 'center',
								},
								events = {
									change = function(element)
										creature[entry.edit](creature, element.text)
										armorClassElement.popup = nil
										armorClassElement:FireEvent('press')
										CharacterSheet.instance:FireEvent('refreshAll')
									end,
								},
							})
						},
					})

				end

				if showNotes ~= nil then

					--padding
					panels[#panels+1] = gui.Panel{
						style = {
							width = 1,
							height = 8,
						},
					}

					panels[#panels+1] = gui.Label{
						text = 'Rules Notes:',
						style = {
							textAlignment = 'left',
							halign = 'left',
							fontSize = '50%',
							width = 'auto',
							height = 'auto',
						},
					}

					panels[#panels+1] = gui.Input{
						text = creature:ArmorClassNotes(),
						multiline = true,
						characterLimit = 1024,
						placeholderText = 'Notes on armor class calculation...',
						textAlignment = 'topleft',
						fontSize = 14,
						width = 300,
						height = "auto",
						maxHeight = 100,
						events = {
							change = function(element)
								creature:SetArmorClassNotes(element.text)
							end,
						},
					}
					
				end

				element.popupPositioning = 'panel'
				element.popup = gui.TooltipFrame(
				
					gui.Panel({
						selfStyle = {
							pad = 8,
						},
						styles = {
							Styles.Default,
							{
								valign = 'bottom',
								halign = 'center',
								width = 'auto',
								height = 'auto',
								bgcolor = 'black',
								flow = 'vertical',
							},
							{
								selectors = {'editable'},
								color = '#aaaaff',
							}
						},
						children = panels,
					}), {
						interactable = true,
					}
				)
				
			end,
		},
		gui.Label{
			classes = {"statsLabel","armorClass"},
			text = "AC",
		},
	}

	return resultPanel
end

function CharSheet.CharacterSpeedPanel()

	local resultPanel

	resultPanel = gui.Panel{
		classes = {"attributePanel", "movementSpeed"},
		gui.Panel{
			classes = {"attributeModifierPanel", "movementSpeed"},
			gui.Panel{
				id = "movementSpeedBackground",
				interactable = false,
			},
			gui.Panel{
				classes = {"movementSpeedIcon"},
				interactable = false,
				refreshToken = function(element, info)
					local creature = CharacterSheet.instance.data.info.token.properties

					local info = creature.movementTypeById[creature:CurrentMoveType()]
                    if info ~= nil then
					    element.bgimage = info.icon
                    end
				end,
			},
			gui.Label{
				interactable = false,
				characterLimit = 5,
				minWidth = 120,
				classes = {"attributeModifierLabel", "valueLabel", "movementSpeed"},
				refreshToken = function(element, info)
					local creature = CharacterSheet.instance.data.info.token.properties
					element.text = string.format("%s%s", MeasurementSystem.NativeToDisplayString(creature:CurrentMovementSpeed()), MeasurementSystem.Abbrev())
				end,
				change = function(element)
					local creature = CharacterSheet.instance.data.info.token.properties
					creature:SetSpeed('walk', element.text)
					CharacterSheet.instance:FireEvent('refreshAll')
				end,
			},

			press = function(element)
				if element.popup ~= nil then
					element.popup = nil
					return
				end

				local parentPanel = element

				local creature = CharacterSheet.instance.data.info.token.properties
				local currentMoveType = creature:CurrentMoveType()
				local panels = {}

				--padding.
				panels[#panels+1] = gui.Panel{
					width = 1,
					height = 30,
				}

				for _,movementEntry in ipairs(creature.movementTypeInfo) do
					local movementType = movementEntry.id
					local speed = creature:GetBaseSpeed(movementType)
					panels[#panels+1] = gui.Panel{
						classes = {cond(currentMoveType == movementType, "selected"), cond((speed or 0) <= 0, "disabled")},
						flow = "horizontal",
						width = "auto",
						height = "auto",

						press = function(element)
							--creature:SetCurrentMoveType(movementType)
							--parentPanel.popup = nil
							--CharacterSheet.instance:FireEvent('refreshAll')
						end,

						gui.Panel{
							classes = {"icon"},
							bgimage = movementEntry.icon,
							width = 32,
							height = 32,
							rmargin = 16,
						},

						gui.Label{
							text = string.format("%s speed", movementType),
							fontSize = 20,
							width = 192,
							height = 'auto',
							textAlignment = 'left',
							halign = 'left',
							valign = 'center',
						},

						gui.Panel{
							width = 8,
							height = 1,
						},

						gui.Label{
							text = string.format("%s", MeasurementSystem.NativeToDisplayString(speed or 0)),
							classes = {"editable"},
                            bgimage = true,
                            bgcolor = "clear",
							fontSize = 20,
							width = 50,
							height = 'auto',
							textAlignment = 'right',
							halign = 'right',
							valign = 'center',

							editable = true,
							change = function(element)
								local creature = CharacterSheet.instance.data.info.token.properties
								local num = tonumber(element.text)
								if num ~= nil then
									creature:SetSpeed(movementType, MeasurementSystem.DisplayToNative(num))
									creature:Invalidate()
								end
								CharacterSheet.instance:FireEvent('refreshAll')
							end,
						},

						gui.Label{
							text = string.format(" %s", MeasurementSystem.Abbrev()),
							fontSize = 16,
							width = "auto",
							height = "auto",
							halign = "right",
							valign = "center",
						},
					}

					--show modifications of this attribute.
					local modifications = creature:DescribeSpeedModifications(movementType)
					for _,mod in ipairs(modifications) do
						panels[#panels+1] = gui.Panel{
							flow = "horizontal",
							width = "auto",
							height = "auto",

							gui.Label{
								hmargin = 6,
								text = mod.key,
								fontSize = 20,
								width = 180,
								height = 'auto',
								textAlignment = 'left',
								halign = 'left',
								valign = 'center',
							},

							gui.Panel{
								width = 8,
								height = 1,
							},

							gui.Label{
								text = mod.value,
								fontSize = 20,
								width = 50,
								height = 'auto',
								textAlignment = 'right',
								halign = 'right',
								valign = 'center',
							},
						}

					end

				end


				element.popupPositioning = "panel"

				element.popup = gui.TooltipFrame(
				
					gui.Panel({
						selfStyle = {
							pad = 8,
						},
						styles = {
							Styles.Default,
							{
								valign = 'bottom',
								halign = 'center',
								width = 'auto',
								height = 'auto',
								bgcolor = 'black',
								flow = 'vertical',
							},
							{
								selectors = {'editable'},
								color = '#aaaaff',
							},

							{
								selectors = {"icon"},
								bgcolor = Styles.textColor,
							},
							{
								selectors = {"icon", "parent:selected"},
								bgcolor = "white",
							},
							{
								selectors = {"icon", "parent:hover"},
								bgcolor = "white",
							},
							{
								selectors = {"icon", "parent:disabled"},
								bgcolor = "grey",
							},

							{
								selectors = {"label", "~editable"},
								color = Styles.textColor,
							},
							{
								selectors = {"label", "~editable", "parent:selected"},
								color = "white",
							},
							{
								selectors = {"label", "~editable", "parent:hover"},
								color = "white",
							},
							{
								selectors = {"label", "~editable", "parent:disabled"},
								color = "grey",
							},

						},
						children = panels,
					}), {
						interactable = true,
					}
				)

				
			end,
		},
		gui.Label{
			classes = {"statsLabel","movementSpeed"},
			text = "SPEED",
		},
	}

	return resultPanel
end

local HitpointsStyles = {
	{
		selectors = {"#hitpointsInnerPanel"},
		flow = "horizontal",
		width = "100%",
		height = "100%",
	},
	{
		selectors = {"hitpointsReroll"},
		bgimage = "ui-icons/d10.png",
		width = 24,
		height = 24,
		bgcolor = "white",
		halign = "right",
		valign = "bottom",
	},

	{
		selectors = {"hitpointsReroll", "hover"},
		bgcolor = "#ff00ff",
	},

	{
		selectors = {"hitpointsReroll", "press"},
		bgcolor = "#aa00aa",
	},

	{
		selectors = {"healDamage", "background"},
		bgimage = "panels/character-sheet/LB_11_08.png",
		
		hmargin = 4,
		valign = "center",
		bgcolor = "white",
		width = 80,
		height = 42,
	},

	{
		selectors = {"healDamage", "background", "hover"},
		brightness = 1.2,
	},

	{
		selectors = {"healDamage", "background", "damage"},
		
		hueshift = 0.5,
	},

	{
		selectors = {"healDamage", "input"},
		priority = 100,
		borderWidth = 0,
		bgcolor = "clear",
		width = 60,
		height = 20,
		fontSize = 12,
		color = "white",
		textAlignment = "center",
		valign = "center",
		halign = "center",
	},
}
gui.RegisterTheme("charsheet", "Hitpoints", HitpointsStyles)

function CharSheet.CharacterHitpointsPanel()

	local mainHitpointsPanel =
	gui.Panel({
		style = {
			halign = 'center',
			valign = 'top',
			pad = 0,
			hmargin = 0,
			vmargin = 5,
			height = 80,
			width = 240,
			flow = 'horizontal',
		},


		styles = {
			gui.Style{
				selectors = {"hitpointsValueLabel"},
				fontSize = 32,
				valign = "bottom",
			},
			gui.Style{
				selectors = {"actualHitpoints"},
				color = "#44894f",
				minWidth = 80,
				minHeight = 80,
				textAlignment = "center",
			},
		},

		events = {
			edit = function(element, editing)
				element:SetClass('collapsed', editing)
			end,
		},

		children = {
			--current hitpoints panel.
			gui.Panel({
				id = 'CurrentHitpointsPanel',
				bgimage = 'panels/square.png',
				style = {
					width = "30%",
					height = "100%",
					flow = 'vertical',
					borderWidth = 0,
					vmargin = 0,
				},

				children = {
					gui.Label({
						text = 'CURRENT',
						classes = {"statsLabel"},
					}),
					gui.Label({
						classes = {"statsLabel", "hitpointsValueLabel", "actualHitpoints"},
						text = 'HP',
						editable = true,
						characterLimit = 3,

						events = {
							change = function(element)
								local creature = CharacterSheet.instance.data.info.token.properties
								creature:SetCurrentHitpoints(element.text)
								element.data.previous_value = nil --don't flash green/red on an edit.
								CharacterSheet.instance:FireEvent('refreshAll')
							end,

							refreshToken = function(element, info)
								local creature = info.token.properties
								local newValue = creature:CurrentHitpoints()
								ChangeLabelValue(info, element, tostring(newValue))
							end,
						},
					}),
				},
			}),

			--the slash separating current from max hitpoints
			gui.Panel({
				style = {
					width = "10%",
					height = "100%",
					flow = 'vertical',
					vmargin = 0,
				},

				children = {
					gui.Label({
						classes = {"statsLabel"},
						text = '',

					}),
					gui.Label({
						classes = {"statsLabel", "hitpointsValueLabel"},
						text = '/',

					}),

				},
			}),

			--max hitpoints.
			gui.Panel({
				id = 'MaxHitpointsPanel',
				style = {
					width = "28%",
					height = "100%",
					flow = 'vertical',
					borderWidth = 0,
					vmargin = 0,
				},

				children = {
					gui.Label({
						text = 'MAX',
						classes = {"statsLabel"},
					}),
					gui.Label({
						text = 'HP',
						characterLimit = 3,
						classes = {"statsLabel", "hitpointsValueLabel", "actualHitpoints"},
						editable = true,
						events = {
							change = function(element)
								local creature = CharacterSheet.instance.data.info.token.properties
								creature:SetMaxHitpoints(element.text)

								if creature:IsMonster() and element.text ~= "" then
									creature.max_hitpoints_roll = element.text
								end

								CharacterSheet.instance:FireEvent('refreshAll')
							end,

							refreshToken = function(element, info)
								local creature = info.token.properties
								element.editable = creature:IsMonster()
								local newValue = creature:MaxHitpoints()
								ChangeLabelValue(info, element, tostring(newValue))
							end,

						},

						gui.Panel{
							classes = {"hitpointsReroll"},

							refreshToken = function(element, info)
								element:SetClass("hidden", not info.token.properties:IsMonster())
							end,

							click = function(element)
								local creature = CharacterSheet.instance.data.info.token.properties

								creature:RerollHitpoints()
								CharacterSheet.instance:FireEvent('refreshAll')
							end,

							linger = function(element)
								local creature = CharacterSheet.instance.data.info.token.properties
								local text = creature.max_hitpoints_roll .. '\nClick to re-roll HP.'
								gui.Tooltip(text)(element)
							end,
						}
					}),

				},
			}),

			--temp. hitpoints.
			gui.Panel({
				id = 'TempHitpointsPanel',
				bgimage = 'panels/square.png',
				style = {
					width = "24%",
					height = "100%",
					flow = 'vertical',
					borderWidth = 0,
					vmargin = 0,
				},

				children = {
					gui.Label({
						text = 'TEMP',
						classes = {"statsLabel"},
					}),
					gui.Panel{
						width = 80,
						height = 80,
						interactable = false,
						gui.Label({
							text = '--',
							halign = "center",
							valign = "center",
							minWidth = 70,
							minHeight = 40,
							textAlignment = "center",
							characterLimit = 3,
							classes = {"statsLabel", "hitpointsValueLabel"},
							editable = true,
							events = {
								change = function(element)
									local creature = CharacterSheet.instance.data.info.token.properties
									creature:SetTemporaryHitpoints(element.text)
									element.data.previous_value = nil
									CharacterSheet.instance:FireEvent('refreshAll')
								end,

								refreshToken = function(element, info)
									local creature = info.token.properties
									ChangeLabelValue(info, element, creature:TemporaryHitpointsStr())
								end,
							},
						}),
					}

				},
			}),

		},
	})

	local healDamagePanel = gui.Panel{
		flow = "vertical",
		width = "auto",
		height = "100%",

		gui.Panel{
			classes = {"healDamage", "background", "heal"},
			press = function(element)
				element.children[1].hasFocus = true
			end,
			gui.Input{
				classes = {"healDamage", "heal"},
				text = '',
				characterLimit = 8,
				placeholderText = 'HEAL',
				events = {
					change = function(element)
						local creature = CharacterSheet.instance.data.info.token.properties
						creature:Heal(element.text)
						element.text = ''
						CharacterSheet.instance:FireEvent('refreshAll')
					end,

					edit = function(element, editing)
						element:SetClass('hidden', editing)
					end,
				},
			},
		},

		gui.Panel{
			classes = {"healDamage", "background", "damage"},
			press = function(element)
				element.children[1].hasFocus = true
			end,
			gui.Input{
				classes = {"healDamage", "damage"},
				text = '',
				characterLimit = 8,
				placeholderText = 'DAMAGE',
				events = {
					change = function(element)
						local creature = CharacterSheet.instance.data.info.token.properties
						creature:TakeDamage(element.text)
						element.text = ''
						CharacterSheet.instance:FireEvent('refreshAll')
					end,

					edit = function(element, editing)
						element:SetClass('hidden', editing)
					end,
				},
			},
		},

	}

	return gui.Panel({
		id = 'hitpointsInnerPanel',
		theme = "charsheet.Hitpoints",

		children = {

			healDamagePanel,
			
			mainHitpointsPanel,

			gui.Panel({
				y = 3,
				style = {
					pad = 0,
					width = '100%',
					height = 30,
					fontSize = '60%',
					halign = 'center',
					valign = 'bottom',
					textAlignment = 'center',
					flow = 'none',
				},
			})
		}
	})
	
end

function CharSheet.CharacterSheetSkillsPanel()

	local rowsCache = {}

	local resultPanel
	resultPanel = gui.Panel{
		id = "skillsInnerPanel",
		classes = {"statsPanel"},

		gui.Panel{
			id = "skillsHeadingPanel",
			classes = {"statsRow", "skills"},
			gui.Label{
				classes = {"statsLabel","skillsProfField"},
				text = "PROF",
			},
			gui.Label{
				classes = {"statsLabel","skillsModField"},
				text = "MOD",
			},
			gui.Label{
				classes = {"statsLabel","skillsSkillField"},
				text = "SKILL",
			},
			gui.Label{
				classes = {"statsLabel","skillsBonusField"},
				text = "BONUS",
			},
		},

		gui.Panel{
			id = "skillsFieldsPanel",
			vscroll = true,

			refreshToken = function(element, info)
				local children = {}
				local newRowsCache = {}
				for i,skillInfo in ipairs(Skill.SkillsInfo) do
					local row = rowsCache[skillInfo.id] or gui.Panel{
						classes = {"statsRow", "skills"},

						gui.Panel{
							classes = {"skillsProfField"},
							gui.Panel{
								classes = {"skillCheck",},
								data = {
									proficiencyid = nil,
								},

								gui.Panel{
									classes = {"skillBackground"},
									interactable = false,
								},

								gui.Panel{
									classes = {"skillFill"},
									interactable = false,
								},

								gui.Label{
									classes = {"expertiseLabel"},
									interactable = false,
									text = "",
									refreshToken = function(element, info)
										local proficiencyInfo = info.token.properties:SkillProficiencyLevel(skillInfo)
										if proficiencyInfo.characterSheetLabel == nil then
											element:SetClass("hidden", true)
										else
											element:SetClass("hidden", false)
											element.text = proficiencyInfo.characterSheetLabel
										end

									end,
								},

								refreshToken = function(element, info)

									local proficiency = info.token.properties:SkillProficiencyLevel(skillInfo)
									element:SetClass('override', info.token.properties:SkillProficiencyOverridden(skillInfo))

									if proficiency.id ~= element.data.proficiencyid then
										if element.data.proficiencyid ~= nil then
											element:SetClass(string.format("proficiency-%s", element.data.proficiencyid), false)
										end
										element.data.proficiencyid = proficiency.id
										element:SetClass(string.format("proficiency-%s", element.data.proficiencyid), true)
									end

									if proficiency.multiplier >= 1 then
										element:SetClass('proficient', true)
										element:SetClass('halfproficient', false)
									elseif proficiency.multiplier > 0 then
										element:SetClass('proficient', false)
										element:SetClass('halfproficient', true)
									else
										element:SetClass('proficient', false)
										element:SetClass('halfproficient', false)
									end

								end,

								click = function(element)

									local isMonster = info.token.properties:IsMonster()

										--monsters just toggles skills directly.
										--info.token.properties:ToggleSkillProficiency(skillInfo)

									--characters have calculation breakdowns for skills and can have them overridden.
									local popupParentElement = element

									local options = DeepCopy(creature.GetProficiencyDropdownOptions())
									table.insert(options, 1, {
										id = nil,
										text = "No Override",
									})

									if isMonster then
										options = {
											{
												id = "none",
												text = "Not Proficient",
												value = false,
											},
											{
												id = "proficient",
												text = "Proficient",
												value = true,
											},
											{
												id = "custom",
												text = "Custom Modifier",
											},
										}
									end

									local optionToDescription = {}
									for i,option in ipairs(options) do
										if option.id ~= nil then
											optionToDescription[option.id] = option.text
										end
									end

									local customInput = nil
									local proficiencyOverride
									
									if isMonster then
										proficiencyOverride = info.token.properties.skillRatings[skillInfo.id]
										customInput = gui.Input{
											placeholderText = "Enter Custom Modifier",
											text = cond(proficiencyOverride == nil or proficiencyOverride == true, "", tostring(proficiencyOverride)),
											width = 140,
											height = 18,
											fontSize = 14,
											characterLimit = 5,
											halign = "left",
											classes = {cond(proficiencyOverride == nil or proficiencyOverride == true, "collapsed")},
											change = function(element)
												info.token.properties:SetSkillRating(skillInfo, element.text)
												CharacterSheet.instance:FireEvent('refreshAll')
												popupParentElement.popup = nil
											end,
										}

										if proficiencyOverride == nil then
											proficiencyOverride = 'none'
										elseif proficiencyOverride == true then
											proficiencyOverride = 'proficient'
										else
											proficiencyOverride = 'custom'
										end


									else
										proficiencyOverride = info.token.properties.skillProficiencies[skillInfo.id]
										if proficiencyOverride == true then
											proficiencyOverride = 'proficient'
										end
									end

									local panels = {}
									panels[#panels+1] = gui.Label{
										text = string.format("%s (%s) Skill", skillInfo.name, string.upper(skillInfo.attribute)),
										bold = true,
									}

									if not isMonster then
										local log = {}
										local proficiencyLevel = info.token.properties:BaseSkillProficiencyLevel(skillInfo, log)

										for i,entry in ipairs(log) do
											panels[#panels+1] = gui.Panel{
												classes = {"formPanel"},
											
												gui.Label{
													halign = "left",
													text = entry.modifier.name,
													bold = true,
												},

												gui.Label{
													halign = "right",
													text = string.format("%s", optionToDescription[entry.proficiency]),
												},
											}
										end

										if #log == 0 then
											panels[#panels+1] = gui.Label{
												text = "No Proficiency",
												bold = true,
											}
										end
									end

									local proficiencyModifications = {}
									info.token.properties:SkillProficiencyBonus(skillInfo, proficiencyModifications)
									for _,mod in ipairs(proficiencyModifications) do
										panels[#panels+1] = gui.Label{
											text = mod,
											bold = true,
										}
									end

									--padding
									panels[#panels+1] = gui.Panel{
										bgimage = "panels/square.png",
										width = "98%",
										height = 1,
										halign = "center",
										bgcolor = "#999999",
										vmargin = 8,
									}

									panels[#panels+1] = gui.Label{
										text = "Override",
										bold = true,
									}

									for i,option in ipairs(options) do
										local selected = proficiencyOverride == option.id
										dmhub.Debug(string.format('OPTION: %s; vs %s selected: %s', tostring(option.id), tostring(proficiencyOverride), tostring(selected)))
										panels[#panels+1] = gui.Label{
											classes = {"option", cond(selected, "selected")},
											bgimage = "panels/square.png",
											text = option.text,
											press = function(element)
												if option.id == "custom" then
													customInput:SetClass("collapsed", false)
													for _,p in ipairs(panels) do
														p:SetClass("selected", p == element)
													end
													customInput.hasInputFocus = true
												else
													if isMonster then
														info.token.properties:SetSkillProficiency(skillInfo, option.value)
													else
														info.token.properties.skillProficiencies[skillInfo.id] = option.id
													end
													CharacterSheet.instance:FireEvent('refreshAll')
													popupParentElement.popup = nil
												end
											end,
										}
									end

									panels[#panels+1] = customInput

									element.popupPositioning = "panel"

									element.popup = gui.TooltipFrame(
										gui.Panel{
											width = 300,
											styles = {
												Styles.Default,
												PopupStyles,
											},
											children = panels,
										},
										{
											halign = "right",
											interactable = true,
										}
									)									
								end,
							},

						},

						gui.Label{
							classes = {"statsLabel", "attrLabel", "skillsModField"},
							text = string.upper(string.sub(creature.attributesInfo[skillInfo.attribute].description, 1, 3)),
						},

						gui.Label{
							classes = {"statsLabel", "skillsSkillField"},
							text = string.upper(skillInfo.name),
						},

						gui.Label{
							classes = {"statsLabel", "skillsBonusField", "valueLabel", "dice"},
							characterLimit = 5,
							textAlignment = "center",
							refreshToken = function(element, info)
								element.text = info.token.properties:SkillModStr(skillInfo)
								element.editableOnRightClick = (info.token.properties:IsMonster())
							end,
							press = function(element)
								CharacterSheet.instance.data.info.token.properties:RollSkillCheck(skillInfo)
							end,
							change = function(element)
								info.token.properties:SetSkillRating(skillInfo, element.text)
								CharacterSheet.instance:FireEvent('refreshAll')
							end,
						},
						
					}

					children[#children+1] = row

					newRowsCache[skillInfo.id] = row

				end

				rowsCache = newRowsCache
				element.children = children
			end,
		},
	}

	return resultPanel

end

function CharSheet.CharacterSheetSavingThrowPanel()

	local numLeftColumnElements = math.max(#creature.savingThrowIds/2, 3)
	local leftPanel = gui.Panel{
		classes = {"savingThrowColumnPanel"},
	}

	local formatDescription = function(text)
		return string.upper(string.sub(text, 1, 3))
	end

	local rightPanel = nil
	
	if numLeftColumnElements < #creature.savingThrowIds then
		rightPanel = gui.Panel{
			classes = {"savingThrowColumnPanel"},
		}
	else
		leftPanel:SetClass("full", true)
		formatDescription = function(text)
			return string.upper(text)
		end
	end


	local m_init = false


	local resultPanel
	resultPanel = gui.Panel{
		id = "savingThrowInnerPanel",
		classes = {"statsPanel"},

		leftPanel,
		rightPanel,

		refreshToken = function(element, info)
			if m_init == false then
				m_init = true

				local leftChildren = {}
				local rightChildren = {}
				for i,saveid in ipairs(creature.savingThrowIds) do
					local saveInfo = creature.savingThrowInfo[saveid]
					local attrid = saveInfo.attrid
					local children = cond(i <= numLeftColumnElements, leftChildren, rightChildren)
					local attrInfo = creature.attributesInfo[attrid]
					children[#children+1] = gui.Panel{
						classes = {"savingThrowOuterRow"},
						gui.Panel{
							classes = {"statsRow", "savingThrows"},
							width = "100%",
							gui.Panel{
								classes = {"skillCheck"},

								data = {
									proficiencyid = nil,
								},


								gui.Panel{
									classes = {"skillFill"},
									interactable = false,
								},

								gui.Label{
									classes = {"expertiseLabel"},
									interactable = false,
									text = "",
									refreshToken = function(element, info)
										local proficiencyInfo = creature.proficiencyKeyToValue[info.token.properties:SavingThrowProficiency(saveid)]
										if proficiencyInfo.characterSheetLabel == nil then
											element:SetClass("hidden", true)
										else
											element:SetClass("hidden", false)
											element.text = proficiencyInfo.characterSheetLabel
										end
									end,
								},


								refreshToken = function(element, info)
									local proficiency = info.token.properties:SavingThrowProficiencyLevel(saveid)
									element:SetClass('override', info.token.properties:try_get("savingThrowProficiencies", {})[saveid] ~= nil)

									if proficiency.id ~= element.data.proficiencyid then
										if element.data.proficiencyid ~= nil then
											element:SetClass(string.format("proficiency-%s", element.data.proficiencyid), false)
										end
										element.data.proficiencyid = proficiency.id
										element:SetClass(string.format("proficiency-%s", element.data.proficiencyid), true)
									end

									if proficiency.multiplier >= 1 then
										element:SetClass('proficient', true)
										element:SetClass('halfproficient', false)
									elseif proficiency.multiplier > 0 then
										element:SetClass('proficient', false)
										element:SetClass('halfproficient', true)
									else
										element:SetClass('proficient', false)
										element:SetClass('halfproficient', false)
									end

								end,

								click = function(element)

									local popupParentElement = element

									if not info.token.properties:SkillProficiencyHasOverrides() then
										--monsters just toggles skills directly.
										--info.token.properties:ToggleSavingThrowProficiency(saveid)
										--CharacterSheet.instance:FireEvent('refreshAll')

										printf("SAVE:: %s: %s has: %s; has default: %s", saveid, json(info.token.properties.savingThrowRatings[saveid]), json(info.token.properties:HasSavingThrowProficiency(saveid), "selected"), json(info.token.properties:HasDefaultSavingThrowProficiency(saveid)))
										local panels = {}

										panels[#panels+1] = gui.Label{
											text = "Not Proficient",
											classes = {"option", cond(not info.token.properties:HasSavingThrowProficiency(saveid), "selected")},
											bgimage = "panels/square.png",

											press = function(element)
												info.token.properties:SetSavingThrowRating(saveid, nil)
												CharacterSheet.instance:FireEvent('refreshAll')
												popupParentElement.popup = nil
											end,
										}

										panels[#panels+1] = gui.Label{
											text = "Proficient",
											classes = {"option", cond(info.token.properties:HasDefaultSavingThrowProficiency(saveid), "selected")},
											bgimage = "panels/square.png",

											press = function(element)
												info.token.properties:SetSavingThrowRating(saveid, info.token.properties:DefaultSavingThrowProficiency(saveid))
												CharacterSheet.instance:FireEvent('refreshAll')
												popupParentElement.popup = nil
											end,
										}

										panels[#panels+1] = gui.Label{
											text = "Custom",
											classes = {"option", cond(info.token.properties:HasSavingThrowProficiency(saveid) and (not info.token.properties:HasDefaultSavingThrowProficiency(saveid)), "selected")},
											bgimage = "panels/square.png",

											press = function(element)
												for _,p in ipairs(element.parent.children) do
													p:SetClass("selected", p == element)
												end
												info.token.properties:SetSavingThrowRating(saveid, info.token.properties:DefaultSavingThrowProficiency(saveid))
												panels[#panels]:SetClass("collapsed", false)
											end,
											click = function(element)
											end,
										}

										panels[#panels+1] = gui.Input{
											classes = {"input", cond((not info.token.properties:HasSavingThrowProficiency(saveid)) or info.token.properties:HasDefaultSavingThrowProficiency(saveid), "collapsed")},
											placeholderText = "Enter Modifier",
											characterLimit = 2,
											halign = "left",
											change = function(element)
												info.token.properties:SetSavingThrowRating(saveid, tostring(element.text))
												CharacterSheet.instance:FireEvent('refreshAll')
												popupParentElement.popup = nil
											end,
										}


										element.popup = gui.Panel({
											bgimage = 'panels/square.png',
											classes = {'popupWindow'},
											styles = {
												Styles.Default,
												PopupStyles,
											},
											children = panels,
										})


									else
										--characters have calculation breakdowns for saving throws and can have them overridden.

										local options = {
											{
												id = nil,
												text = "No Override",
												multiplier = -1,
											},
										}

										local keys = {}
										if GameSystem.IsProficiencyTypeLeveled("save") then
											for key,_ in pairs(creature.proficiencyMultiplierToValue) do
												keys[#keys+1] = key
											end
										else
											keys = {0,1}
										end

										for _,key in ipairs(keys) do
											local info = creature.proficiencyMultiplierToValue[key]
											options[#options+1] = info
										end

										table.sort(options, function(a,b) return a.multiplier < b.multiplier end)
										
										local optionToEntry = {}
										for i,option in ipairs(options) do
											if option.id ~= nil then
												optionToEntry[option.id] = option
											end
										end

										local proficiencyOverride = info.token.properties.savingThrowProficiencies[saveid]
										if proficiencyOverride == true then
											proficiencyOverride = creature.proficiencyMultiplierToValue[1].id
										end

										local panels = {}
										panels[#panels+1] = gui.Label{
											text = string.format("%s %s", string.upper(string.sub(saveInfo.description, 1, 3)), GameSystem.SavingThrowNamePlural),
										}

										local log = {}
										local proficiencyLevel = info.token.properties:BaseSavingThrowProficiency(saveid, log)

										for i,entry in ipairs(log) do
											panels[#panels+1] = gui.Panel{
												classes = {"formPanel"},
												
												gui.Label{
													halign = "left",
													text = entry.modifier.name,
												},

												gui.Label{
													halign = "right",
													text = string.format("%s", optionToEntry[entry.proficiency].text),
												},
											}
										end

										if #log == 0 then
											panels[#panels+1] = gui.Label{
												text = "No Proficiency",
											}
										end

										--padding
										panels[#panels+1] = gui.Panel{
											bgimage = "panels/square.png",
											width = "98%",
											height = 1,
											halign = "center",
											bgcolor = "#999999",
											vmargin = 8,
										}

										panels[#panels+1] = gui.Label{
											text = "Override",
										}

										for i,option in ipairs(options) do
											local selected = proficiencyOverride == option.id
											panels[#panels+1] = gui.Label{
												classes = {"option", cond(selected, "selected")},
												bgimage = "panels/square.png",
												text = option.text,
												press = function(element)
													info.token.properties.savingThrowProficiencies[saveid] = option.id
													CharacterSheet.instance:FireEvent('refreshAll')
													popupParentElement.popup = nil
												end,
											}
										end

										element.popup = gui.Panel({
											bgimage = 'panels/square.png',
											classes = {'popupWindow'},
											styles = {
												Styles.Default,
												PopupStyles,
											},
											children = panels,
										})

									end
							
								end,
							},

							gui.Label{
								classes = {"statsLabel", "attrLabel"},
								halign = "left",
								hmargin = 12,
								text = formatDescription(saveInfo.description)
							},

							gui.Label{
								classes = {"statsLabel", "valueLabel", "savingThrows", "dice"},
								refreshToken = function(element, info)
									element.text = info.token.properties:SavingThrowModStr(saveid)
								end,
								press = function(element)
									CharacterSheet.instance.data.info.token.properties:RollSavingThrow(saveid)
								end,
							},
						}
					}
				end

				leftPanel.children = leftChildren
				if rightPanel ~= nil then
					rightPanel.children = rightChildren
				end
			end
		end,
	}

	return resultPanel
end

function CharSheet.CharacterSheetPassiveSensesPanel()
	local rowsCache = {}

	local resultPanel
	resultPanel = gui.Panel{
		id = "passiveSensesInnerPanel",
		classes = {"statsPanel"},

		gui.Panel{
			classes = "statsInnerPanel",
			refreshToken = function(element, info)
				local newRowCache = {}
				local children = {}
				local creature = info.token.properties
				for i,skillInfo in ipairs(Skill.PassiveSkills) do

					local rowPanel = rowsCache[skillInfo.id] or gui.Panel{
						classes = {"statsRow", "passiveSenses"},

						gui.Label{
							classes = {"statsLabel", "valueLabel", "passiveSenses"},
							refreshToken = function(element, info)
								local creature = info.token.properties
								local value = creature:PassiveMod(skillInfo)
								element.text = tostring(value)
							end,
						},

						gui.Label{
							classes = {"statsLabel", "passiveSenses"},
							text = string.format("PASSIVE " .. string.upper(skillInfo.name)),
						},
					}

					newRowCache[skillInfo.id] = rowPanel
					children[#children+1] = rowPanel

				end


				local darkvisionPanel = rowsCache["darkvision"] or gui.Panel{
					classes = {"statsRow", "passiveSenses"},

					gui.Label{
						classes = {"statsLabel", "valueLabel", "passiveSenses"},
						refreshToken = function(element, info)
							local creature = info.token.properties
							local darkvision = creature:GetDarkvision()
							if darkvision == nil then
								element.text = "--"
							else
								element.text = string.format("%s%s", MeasurementSystem.NativeToDisplay(darkvision), MeasurementSystem.Abbrev())
							end
						end,
					},

					gui.Label{
						classes = {"statsLabel", "passiveSenses"},
						text = "DARKVISION",
					},
				}

				newRowCache["darkvision"] = darkvisionPanel
				children[#children+1] = darkvisionPanel
					
				local visionTable = dmhub.GetTable(VisionType.tableName) or {}

				for k,v in pairs(visionTable) do
					if not v.hidden then
						local visionPanel
						visionPanel = rowsCache[k] or gui.Panel{
							classes = {"statsRow", "passiveSenses"},

							gui.Label{
								classes = {"statsLabel", "valueLabel", "passiveSenses"},
								refreshToken = function(element, info)
									local creature = info.token.properties
									local radius = creature:CalculateCustomVision(v)
									if radius == nil or radius == 0 then
										visionPanel:SetClass("collapsed", v.alwaysShowOnCharacterSheet == false)
										element.text = "--"
									else
										visionPanel:SetClass("collapsed", false)
										element.text = string.format("%s%s", MeasurementSystem.NativeToDisplay(radius), MeasurementSystem.Abbrev())
									end
								end,
							},

							gui.Label{
								classes = {"statsLabel", "passiveSenses"},
								text = v.name,
							},
						}

						newRowCache[k] = visionPanel
						children[#children+1] = visionPanel
					end
				end

				element.children = children
				rowsCache = newRowCache
			end,

		},
	}

	return resultPanel
end

function CharSheet.CharacterSheetResourcesPanel()
	local groupPanels = {}
	local creature
	local resourceTable
	local resources
	local resultPanel
	local resourceStyles = {}
	local resourceGroupings = {}
	resultPanel = gui.Panel{
		id = "resourcesInnerPanel",
		classes = {"statsPanel"},
		vscroll = true,

		gui.Panel{
			classes = {"statsInnerPanel"},

			refreshToken = function(element, info)
				creature = info.token.properties

				resourceTable = dmhub.GetTable("characterResources") or {}
				resources = creature:GetResources()

				local children = {}

				local newGroupPanels = {}
				resourceGroupings = {}


				--collect resources into groupings.
				for resourceid,quantity in pairs(resources) do
					local resourceInfo = resourceTable[resourceid]
					if resourceInfo ~= nil then
						local grouping = resourceInfo.grouping
						if grouping == '' then
							grouping = resourceInfo.name
						end

						if CharacterResource.usageLimitMap[resourceInfo.usageLimit] == nil then
							print("Invalid usage limit for resource: " .. resourceInfo.name .. " (" .. resourceInfo.usageLimit .. ")" )
						end

						local resourceGroup = resourceGroupings[grouping] or {
							grouping = grouping,
							refresh = CharacterResource.usageLimitMap[resourceInfo.usageLimit].refreshDescription,
							items = {},
						}

						resourceGroup.items[#resourceGroup.items+1] = {
							resourceid = resourceid,
							quantity = quantity,
							ord = resourceInfo.name,
						}

						resourceGroupings[grouping] = resourceGroup
					end
				end
				
				for groupid,resourceGroup in pairs(resourceGroupings) do

					table.sort(resourceGroup.items, function(a,b) return a.ord < b.ord end)

					local resourceIcons = {}

					newGroupPanels[groupid] = groupPanels[groupid] or gui.Panel{
						classes = {'resourcesGroup'},

						children = {

							gui.Panel{
								classes = {'resourceContainer'},
							},

							gui.Panel{
								classes = {'resourcesGroupHeadLine'},
								gui.Label{
									classes = {'statsLabel', 'resourcesGroupTitle'},
									text = groupid,
								},
								gui.Panel{
									classes = {'resourcesRefreshIcon'},
									click = function(element)
										
										--refresh all resources in this group.
										for _,item in ipairs(resourceGroup.items) do
											local resourceInfo = resourceTable[item.resourceid]
											if resourceInfo ~= nil then
												creature:RefreshResource(item.resourceid, resourceInfo.usageLimit, true)
											end
										end
										CharacterSheet.instance:FireEvent('refreshAll')

									end,
								},
								gui.Label{
									classes = {'statsLabel', 'resourcesRefreshText'},
									text = resourceGroup.refresh,
								},
							},
						},

						refreshToken = function(element, info)
							local resourceContainer = element.children[1]

							local newResourceIcons = {}

							--make sure we have the up-to-date version of resourceGroup
							local resourceGroupRefresh = resourceGroupings[groupid]
							if resourceGroupRefresh == nil then
								return
							end

							local groupChildren = {}

							for i,item in ipairs(resourceGroupRefresh.items) do
								local resourceInfo = resourceTable[item.resourceid]

								local numExpended = creature:GetResourceUsage(item.resourceid, resourceInfo.usageLimit)
								local count = item.quantity
								while count > 0 do

									local styles = resourceStyles[resourceInfo.id] or resourceInfo:CreateStyles()
									resourceStyles[resourceInfo.id] = styles

									local childKey = string.format("%s-%d", resourceInfo.id, count)
									local childPanel

									local countConsumed = 1

									if resourceInfo.largeQuantity then
										--display resources as an icon with a label count.
										childPanel = resourceIcons[childKey] or gui.Panel{
											classes = {'resourceQuantityPanel'},
											gui.Panel{
												classes = {'resourceIcon', 'normal'},
												bgimage = resourceInfo:GetImage("normal"),
												styles = styles,
											},
											gui.Label{
												classes = {'resourceQuantityLabel'},
												editable = true,
												characterLimit = 3,
												data = {
													info = nil,
												},
												updateresource = function(element, info)
													element.text = tostring(math.max(info.count - info.numExpended, 0))
													element.data.info = info
												end,

												change = function(element)

													if tonumber(element.text) ~= nil then
														local n = clamp(round(tonumber(element.text)), 0, element.data.info.count)
														local current = element.data.info.count - element.data.info.numExpended
														local diff = n - current
														if diff ~= 0 then
															if diff > 0 then
																creature:RefreshResource(item.resourceid, resourceInfo.usageLimit, diff)
															else
																creature:ConsumeResource(item.resourceid, resourceInfo.usageLimit, -diff)
															end
														end
													end

													CharacterSheet.instance:FireEvent('refreshAll')
												end,
											},
											gui.Label{
												classes = {'resourceQuantityLabel'},
												updateresource = function(element, info)
													element.text = "/" .. tostring(info.count)
												end,
											},
										}

										childPanel:FireEventTree("updateresource", {
											count = count,
											numExpended = numExpended,
										})

										countConsumed = count

									else
										--display resources as a line of individual icons.
										local iconPanel = resourceIcons[childKey] or gui.Panel{
											classes = {'resourceIcon', 'interactable'},
											styles = styles,
											data = {
											},
											events = {
												click = function(element)
													if element.data.expended then
														creature:RefreshResource(item.resourceid, resourceInfo.usageLimit)
													else
														creature:ConsumeResource(item.resourceid, resourceInfo.usageLimit)
													end
													CharacterSheet.instance:FireEvent('refreshAll')
												end,
												linger = function(element)
													local numExpended = creature:GetResourceUsage(item.resourceid, resourceInfo.usageLimit)
													gui.Tooltip(resourceInfo:TooltipText(item.quantity, numExpended))(element)
												end,
											},
										}

										iconPanel.bgimage = resourceInfo:GetImage(cond(count > numExpended, 'normal', 'expended'))

										iconPanel:SetClass('normal', count > numExpended)
										iconPanel:SetClass('expended', count <= numExpended)
										iconPanel.data.expended = count <= numExpended
										childPanel = iconPanel
									end

									newResourceIcons[childKey] = childPanel
									groupChildren[#groupChildren+1] = childPanel

									count = count-countConsumed
								end
							end

							resourceContainer.children = groupChildren
							resourceIcons = newResourceIcons
						end,
					}

					children[#children+1] = newGroupPanels[groupid]
				end
				
				element.children = children
				groupPanels = newGroupPanels

			end,
		},
	}

	return resultPanel
end

function CharSheet.CharacterSheetProficiencesAndLanguagesPanel()
	local resultPanel
	local itemsCache = {}
	resultPanel = gui.Panel{
		id = "proficienciesAndLanguagesInnerPanel",
		classes = {"statsPanel"},
		vmargin = 40,
		vscroll = true,
		gui.Panel{
			classes = {"statsInnerPanel"},
			refreshToken = function(element, info)
				local newItemsCache = {}
				local children = {}

				local creature = info.token.properties
				local proficiencies = creature:EquipmentProficienciesKnown()

				local items = {}
				local dataTable = dmhub.GetTable("equipmentCategories")
				local equipmentTable = dmhub.GetTable("tbl_Gear")
				for k,prof in pairs(proficiencies) do
					local catInfo = dataTable[k]
					local itemInfo = catInfo
					
					if catInfo == nil then
						local equipment = equipmentTable[k]
						if equipment ~= nil then
							catInfo = dataTable[equipment:try_get("equipmentCategory", "")]
							itemInfo = equipment
						end
					end

					if catInfo ~= nil then
						local cat = "Other"
						if catInfo.isTool then
							cat = "Tools"
						elseif catInfo.editorType == "Shield" or catInfo.editorType == "Armor" then
							cat = "Armor"
						elseif catInfo.editorType == "Weapon" then
							cat = "Weapons"
						end

						local proficiencyText = nil
						if prof.proficiency ~= nil and creature.proficiencyKeyToValue[prof.proficiency].id ~= "none" then
							proficiencyText = creature.proficiencyKeyToValue[prof.proficiency].text
						end

						local itemsList = (items[cat] or {})
						itemsList[#itemsList+1] = {
							text = itemInfo.name,
							proficiency = prof.proficiency,
							proficiencyText = proficiencyText,
						}
						items[cat] = itemsList
					end
				end

				local languagesTable = dmhub.GetTable("languages") or {}
				for langid,b in pairs(creature:LanguagesKnown()) do
					local lang = languagesTable[langid]
					if lang ~= nil then
						local cat = "Languages"
						local itemsList = (items[cat] or {})
						itemsList[#itemsList+1] = {
							text = lang.name
						}
						items[cat] = itemsList
					end
				end

				if creature:try_get("customInnateLanguage") ~= nil then
					local cat = "Languages"
					local itemsList = (items[cat] or {})
					itemsList[#itemsList+1] = {
						text = creature.customInnateLanguage
					}
					items[cat] = itemsList
				end

				local categories = {"Weapons", "Armor", "Tools", "Other", "Languages"}

				for i,cat in ipairs(categories) do
					local itemsList = items[cat]
					if itemsList ~= nil then
						local categoryLabel = itemsCache[cat] or gui.Label{
							classes = {"statsLabel", "itemProficiencies"},
							text = string.upper(cat),
						}

						children[#children+1] = categoryLabel
						newItemsCache[cat] = categoryLabel

						local valueLabel = itemsCache[cat .. '-items'] or gui.Label{
							classes = {"statsLabel", "valueLabel", "itemProficiencies"},
						}

						local text = nil
						for i,item in ipairs(itemsList) do
							local itemText = item.text
							if item.proficiencyText ~= nil then
								if item.proficiency == "proficient" then
									itemText = itemText
								else
									itemText = string.format("%s (%s)", itemText, item.proficiencyText)
								end

								local proficiencyEntry = creature.proficiencyKeyToValue[item.proficiency]
								if proficiencyEntry ~= nil and proficiencyEntry.color ~= nil then
									itemText = string.format("<color=%s>%s</color>", proficiencyEntry.color, itemText)
								end
							end

							itemText = string.gsub(itemText, ' ', nbsp)

							if text == nil then
								text = itemText
							else
								text = text .. ", " .. itemText
							end
						end

						valueLabel.text = text

						children[#children+1] = valueLabel
						newItemsCache[cat .. '-items'] = valueLabel
					end
				end

				element.children = children
				itemsCache = newItemsCache
				
			end,
		},
	}

	return resultPanel
end

local EditResistanceEntry = function(creature, resistanceEntry, params)

    local damageTypeOptions = {}

    local damageTable = dmhub.GetTable(DamageType.tableName) or {}
    for k,v in unhidden_pairs(damageTable) do
        local name = string.lower(v.name)
        damageTypeOptions[#damageTypeOptions+1] = {
            id = name,
            text = string.format("%s damage", name),
        }
    end

	local resultPanel
	local args = {
		style = {
			flow = 'horizontal',
			width = "auto",
			height = "auto",
			hmargin = 0,
			vmargin = 2,
			valign = 'top',
		},

		data = {
			entry = resistanceEntry,
		},

		children = {
			gui.Dropdown({
				options = ResistanceEntry.types,
				optionChosen = resistanceEntry.apply,
				events = {
					change = function(element)
						resistanceEntry.apply = element.optionChosen
						resultPanel:FireEvent("change")
						element.parent:FireEventTree("refresh")
					end,

					refresh = function(element)
						element.optionChosen = resistanceEntry.apply
					end,
				},
				style = {
					halign = 'left',
					valign = 'center',
					height = 24,
					width = 100,
				},
			}),

			gui.Input{
				editable = true,
				characterLimit = 3,
				change = function(element)
					resistanceEntry.dr = tonumber(element.text)
					if resistanceEntry.apply == "Percent Reduction" then
						resistanceEntry.dr = tonumber(element.text)/100
					end
					resultPanel:FireEvent("change")
				end,
				create = function(element)
					element:FireEvent("refresh")
				end,
				refresh = function(element)
					local dr = resistanceEntry:try_get("dr", 0)
					if resistanceEntry.apply == "Percent Reduction" then
						dr = round(dr * 100)
					end
					element.text = tostring(dr)
					element:SetClass("collapsed", resistanceEntry.apply ~= "Damage Reduction" and resistanceEntry.apply ~= "Percent Reduction")
				end,
				halign = 'left',
				valign = 'center',
				fontSize = 14,
				height = 24,
				width = 20,
			},

			gui.Label({
				text = "to",
				style = {
					halign = 'left',
					valign = 'center',
					width = 'auto',
					height = 'auto',
					hmargin = 6,
				},
			}),

			gui.Dropdown({
				options = {'all', 'nonmagic'},
				optionChosen = cond(resistanceEntry:try_get("nonmagic", false), "nonmagic", "all"),
				style = {
					halign = 'left',
					valign = 'center',
					hmargin = 2,
					height = 24,
					width = 80,
				},

				events = {
					change = function(element)
						if element.optionChosen == 'all' then
							resistanceEntry.nonmagic = nil
						else
							resistanceEntry.nonmagic = true
						end

						resultPanel:FireEvent("change")
					end,

					refresh = function(element)
						if resistanceEntry:try_get('nonmagic', false) then
							element.optionChosen = 'nonmagic'
						else
							element.optionChosen = 'all'
						end
					end,
				},
			}),

			gui.Dropdown({
				options = damageTypeOptions,
				optionChosen = resistanceEntry.damageType,
				style = {
					halign = 'left',
					valign = 'center',
					height = 24,
					width = 80,
				},

				events = {
					change = function(element)
						resistanceEntry.damageType = element.optionChosen
						resultPanel:FireEvent("change")
					end,
				},
			}),

			gui.Label({
				text = " damage",
				style = {
					halign = 'left',
					valign = 'center',
					width = 'auto',
					height = 'auto',
				},
			}),

			gui.DeleteItemButton{
				width = 16,
				height = 16,

				click = function(element)
					creature:DeleteResistance(resistanceEntry)
					resultPanel:FireEvent("change")
				end,
			},
		},
	}

	for k,p in pairs(params) do
		args[k] = p
	end

	resultPanel = gui.Panel(args)
	return resultPanel
end

function CharSheet.CharacterSheetEditLanguagesPopup(element, info)
	local resultPanel

	local creature = info.token.properties
	local parentElement = element

	local languagesTable = dmhub.GetTable(Language.tableName)

	local children = {}

	children[#children+1] = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",

		create = function(element)
			element:FireEvent("refreshPanel")
		end,

		refreshPanel = function(element)
			local children = {}


			for k,v in pairs(creature:try_get("innateLanguages", {})) do
				local langid = k
				local lang = languagesTable[k]
				if lang ~= nil then

					children[#children+1] = gui.Label{
						width = "80%",
						height = 20,
						flow = "horizontal",
						text = lang.name,
						fontSize = 16,
						textAlignment = "left",
						halign = "center",

						gui.DeleteItemButton{
							width = 16,
							height = 16,
							halign = "right",
							valign = "center",
							click = function(element)
								creature.innateLanguages[langid] = nil
								resultPanel:FireEventTree("refreshPanel")
								CharacterSheet.instance:FireEvent('refreshAll')
							end,
						},
					}

				end
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			if creature:try_get("customInnateLanguage") ~= nil then
				children[#children+1] = gui.Label{
					editable = true,
					width = "80%",
					height = 20,
					flow = "horizontal",
					characterLimit = 40,
					text = cond(creature.customInnateLanguage == "", "(Enter Custom Language)", creature.customInnateLanguage),
					fontSize = 16,
					textAlignment = "left",
					halign = "center",

					change = function(element)
						creature.customInnateLanguage = element.text
						resultPanel:FireEventTree("refreshPanel")
						CharacterSheet.instance:FireEvent('refreshAll')
					end,

					gui.DeleteItemButton{
						width = 16,
						height = 16,
						halign = "right",
						valign = "center",
						click = function(element)
							creature.customInnateLanguage = nil
							resultPanel:FireEventTree("refreshPanel")
							CharacterSheet.instance:FireEvent('refreshAll')
						end,
					},
				}
			end

			element.children = children
		end,
	}

	children[#children+1] = gui.Dropdown{
		vmargin = 8,
		create = function(element)
			element:FireEvent("refreshPanel")
		end,

		refreshPanel = function(element)
			local innateLanguages = creature:try_get("innateLanguages", {})
			local options = {}
			for k,v in unhidden_pairs(languagesTable) do
				if innateLanguages[k] == nil then
					options[#options+1] = {
						id = k,
						text = string.format("%s (%s)", v.name, v.speakers),
					}
				end
			end

			table.sort(options, function(a,b) return a.text < b.text end)
			table.insert(options, 1, {
				id = "none",
				text = "Add Language...",
			})

			if creature:try_get("customInnateLanguage") == nil then
				options[#options+1] = {
					id = "custom",
					text = "Custom Language...",
				}
			end

			element.options = options

			element.idChosen = "none"
		end,

		change = function(element)
			if element.idChosen ~= "none" then
				if element.idChosen == "custom" then
					creature.customInnateLanguage = ""
				else
					creature:get_or_add("innateLanguages", {})[element.idChosen] = true
				end
				resultPanel:FireEventTree("refreshPanel")
				CharacterSheet.instance:FireEvent('refreshAll')
			end
		end,
	}

	local equipmentTable = dmhub.GetTable("tbl_Gear")
	local equipmentCatsTable = dmhub.GetTable(EquipmentCategory.tableName)

	--equipment proficiencies.
	children[#children+1] = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",

		create = function(element)
			element:FireEvent("refreshPanel")
		end,

		refreshPanel = function(element)
			local children = {}

			for k,v in pairs(creature:try_get("innateEquipmentProficiencies", {})) do
				local equipid = k
				local equip = equipmentTable[k] or equipmentCatsTable[k]
				if equip ~= nil then
					children[#children+1] = gui.Label{
						width = "80%",
						height = 20,
						flow = "horizontal",
						text = equip.name,
						fontSize = 18,
						textAlignment = "left",
						halign = "center",
						vmargin = 4,

						gui.Dropdown{
							fontSize = 14,
							height = 18,
							width = 140,
							halign = "right",
							valign = "center",
							create = function(element)
								local options = {
									{
										multiplier = -1,
										id = "_erase",
										text = "(Remove)",
									}
								}

								local keys
								if GameSystem.IsProficiencyTypeLeveled("equipment") then
									keys = {}
									for key,_ in pairs(creature.proficiencyMultiplierToValue) do
										keys[#keys+1] = key
									end
								else
									keys = {0,1}
								end

								for _,key in ipairs(keys) do
									options[#options+1] = creature.proficiencyMultiplierToValue[key]
								end

								table.sort(options, function(a,b) return a.multiplier < b.multiplier end)

								element.options = options

								element.idChosen = v.proficiency
							end,

							change = function(element)
								if element.idChosen == "_erase" then
									creature.innateEquipmentProficiencies[equipid] = nil
								else
									v.proficiency = element.idChosen
								end
								resultPanel:FireEventTree("refreshPanel")
								CharacterSheet.instance:FireEvent('refreshAll')
							end,
						}
					}
				end
			end

			table.sort(children, function(a,b) return a.text < b.text end)

			element.children = children
		end,
	}

	children[#children+1] = gui.Dropdown{
		hasSearch = true,

		create = function(element)
			element:FireEvent("refreshPanel")
		end,

		refreshPanel = function(element)
			local options = EquipmentCategory.GetEquipmentProficiencyDropdownOptions()

			table.insert(options, 1, {
				id = "none",
				text = "Add Proficiency...",
			})

			element.options = options

			element.idChosen = "none"
		end,

		change = function(element)
			if element.idChosen ~= "none" then
				creature:get_or_add("innateEquipmentProficiencies", {})[element.idChosen] = { proficiency = GameSystem.ProficientId() }
				resultPanel:FireEventTree("refreshPanel")
				CharacterSheet.instance:FireEvent('refreshAll')
			end
		end,
	}


	element.popupPositioning = "panel"

	resultPanel = gui.TooltipFrame(
		gui.Panel{
			width = 340,
			height = "auto",
			styles = {
				Styles.Default,
				PopupStyles,
				CharSheet.GetCharacterSheetStyles(),
			},

			children = children,
		},

		{
			halign = "right",
			valign = "center",
			interactable = true,
		}
	)

	element.popup = resultPanel

end

function CharSheet.CharacterSheetEditPassiveSensesPopup(element, info)
	local creature = info.token.properties
	local parentElement = element

	local children = {}

	children[#children+1] = gui.Label{
		halign = "center",
		fontSize = 24,
		text = "Passive Senses",
		width = "auto",
		height = "auto",
	}

	for i,skillInfo in ipairs(Skill.PassiveSkills) do

		children[#children+1] = gui.Panel{
			classes = {"statsRow", "passiveSenses"},

			gui.Label{
				classes = {"statsLabel", "passiveSenses"},
				text = string.format("PASSIVE " .. string.upper(skillInfo.name)),
			},
		}

		children[#children+1] = gui.Panel{
			classes = {"statsRow", "passiveSenses"},

			gui.Label{
				classes = {"statsLabel", "passiveSenses"},
				text = "   Base Value",
			},

			gui.Label{
				classes = {"statsLabel"},
				halign = "right",
				minWidth = 40,
				text = tostring(creature:BasePassiveModNoOverride(skillInfo))
			},
		}

		children[#children+1] = gui.Panel{
			classes = {"statsRow", "passiveSenses"},

			gui.Label{
				classes = {"statsLabel", "passiveSenses"},
				text = "   Manual Override",
			},

			gui.Label{
				classes = {"statsLabel", "editable"},
				halign = "right",
				minWidth = 40,
				characterLimit = 2,
				text = creature:BasePassiveModOverride(skillInfo) or "--",
				editable = true,
				change = function(element)
					local val = tonumber(element.text)
					creature:SetBasePassiveModOverride(skillInfo, val)
					element.text = val or "--"
					CharacterSheet.instance:FireEvent('refreshAll')
				end,
			},
		}


		local modifications = creature:DescribePassiveModModifications(skillInfo)
		for _,mod in ipairs(modifications) do
			children[#children+1] = gui.Panel{
				classes = {"statsRow", "passiveSenses"},

				gui.Label{
					classes = {"statsLabel", "passiveSenses"},
					text = "   " .. mod.key,
				},

				gui.Label{
					classes = {"statsLabel"},
					minWidth = 40,
					halign = "right",
					text = mod.value
				},
			}
		end
	end

	--DARKVISION
	if creature:IsMonster() then
		children[#children+1] = gui.Panel{
			classes = {"statsRow", "passiveSenses"},

			gui.Label{
				classes = {"statsLabel", "passiveSenses"},
				text = "DARKVISION",
			},

			gui.Label{
				classes = {"statsLabel"},
				halign = "right",
				minWidth = 40,
				text = tostring(creature:try_get("darkvision", "--")),
				editable = true,
				change = function(element)
					local val = tonumber(element.text)
					creature.darkvision = val
					CharacterSheet.instance:FireEvent('refreshAll')
				end,
			},
		}
	else

		children[#children+1] = gui.Panel{
			classes = {"statsRow", "passiveSenses"},

			gui.Label{
				classes = {"statsLabel", "passiveSenses"},
				text = "DARKVISION",
			},
		}

		local race = creature:Race()
		if race ~= nil then
			children[#children+1] = gui.Panel{
				classes = {"statsRow", "passiveSenses"},

				gui.Label{
					classes = {"statsLabel", "passiveSenses"},
					text = "   Race",
				},

				gui.Label{
					classes = {"statsLabel"},
					halign = "right",
					minWidth = 40,
					text = tostring(race:try_get("darkvision", {}).range or "--"),
				},
			}
		end

		children[#children+1] = gui.Panel{
			classes = {"statsRow", "passiveSenses"},

			gui.Label{
				classes = {"statsLabel", "passiveSenses"},
				text = "   Manual Override",
			},

			gui.Label{
				classes = {"statsLabel"},
				halign = "right",
				minWidth = 40,
				text = tostring(creature:try_get("darkvision", "--")),
				editable = true,
				change = function(element)
					local val = tonumber(element.text)
					creature.darkvision = val
					CharacterSheet.instance:FireEvent('refreshAll')
				end,
			},
		}
	end

	local modifications = creature:DescribeModifications("darkvision", 0)
	for _,mod in ipairs(modifications) do
		children[#children+1] = gui.Panel{
			classes = {"statsRow", "passiveSenses"},

			gui.Label{
				classes = {"statsLabel", "passiveSenses"},
				text = "   " .. mod.key,
			},

			gui.Label{
				classes = {"statsLabel"},
				minWidth = 40,
				halign = "right",
				text = mod.value
			},
		}
	end

	--custom vision.
	for k,v in pairs(dmhub.GetTable(VisionType.tableName) or {}) do
		if not v.hidden then
			children[#children+1] = gui.Panel{
				classes = {"statsRow", "passiveSenses"},

				gui.Label{
					classes = {"statsLabel", "passiveSenses"},
					text = v.name,
				},
			}

			local customVision = creature:try_get("customVision", {})

			children[#children+1] = gui.Panel{
				classes = {"statsRow", "passiveSenses"},

				gui.Label{
					classes = {"statsLabel", "passiveSenses"},
					text = "   Manual Override",
				},

				gui.Label{
					classes = {"statsLabel"},
					halign = "right",
					minWidth = 40,
					characterLimit = 4,
					text = tostring(customVision[k] or "--"),
					editable = true,
					change = function(element)
						local val = tonumber(element.text)
						customVision[k] = val
						creature.customVision = customVision
						CharacterSheet.instance:FireEvent('refreshAll')
					end,
				},
			}


			local modifications = creature:DescribeModifications(k, customVision[k] or 0)
			for _,mod in ipairs(modifications) do
				children[#children+1] = gui.Panel{
					classes = {"statsRow", "passiveSenses"},

					gui.Label{
						classes = {"statsLabel", "passiveSenses"},
						text = "   " .. mod.key,
					},

					gui.Label{
						classes = {"statsLabel"},
						minWidth = 40,
						halign = "right",
						text = mod.value
					},
				}
			end
		end
	end


	element.popupPositioning = "panel"

	element.popup = gui.TooltipFrame(
		gui.Panel{
			width = 300,
			height = "auto",
			styles = {
				Styles.Default,
				PopupStyles,
				CharSheet.GetCharacterSheetStyles(),
			},

			children = children,
		},

		{
			halign = "right",
			valign = "center",
			interactable = true,
		}
	)
end

function CharSheet.CharacterSheetEditConditions(element, info)
	local creature = info.token.properties
	local parentElement = element

	local children = {}

	local options = {}
	local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}

	for k,effect in pairs(ongoingEffectsTable) do
		--we only do effects that are the same name as their base conditions.
		if effect.statusEffect and not effect:try_get("hidden", false) then
			options[#options+1] = gui.Label{
				classes = {"conditionOption"},
				bgimage = "panels/square.png",
				text = effect.name,
				press = function(element)
					creature:ApplyOngoingEffect(k)
					parentElement.popup = nil
					CharacterSheet.instance:FireEvent('refreshAll')
				end,
			}
		end
	end

	table.sort(options, function(a,b) return a.text < b.text end)

	local optionsPanel = gui.Panel{
		width = "90%",
		height = "auto",
		flow = "vertical",
		halign = "left",
		children = options,
	}


	children[#children+1] = gui.Label{
		fontSize = 18,
		bold = true,
		width = "auto",
		height = "auto",
		halign = "center",
		text = "Add Condition",
	}

	children[#children+1] = gui.Panel{
		bgimage = "panels/square.png",
		width = "90%",
		height = 2,
		bgcolor = "#ffffffaa",
		halign = "center",
		vmargin = 8,
	}


	children[#children+1] = optionsPanel

	
	element.popupPositioning = "panel"

	element.popup = gui.TooltipFrame(
		gui.Panel{
			width = 300,
			height = "auto",
			maxHeight = 900,
			vscroll = true,

			styles = {
				Styles.Default,
				PopupStyles,

				{
					selectors = {"conditionOption"},
					width = "95%",
					height = 20,
					fontSize = 14,
					bgcolor = "clear",
					halign = "center",
				},
				{
					selectors = {"conditionOption", "hover"},
					bgcolor = "#ff444466",
				},
				{
					selectors = {"conditionOption", "press"},
					bgcolor = "#aaaaaa66",
				},
			},

			children = children,
		},

		{
			halign = "right",
			interactable = true,
		}
	)
end

function CharSheet.CharacterSheetEditResistancesPopup(element, info)
	local creature = info.token.properties
	local parentElement = element

	local children = {}

	children[#children+1] = gui.Label{
		halign = "center",
		fontSize = 24,
		text = "Innate Resistances",
		width = "auto",
		height = "auto",
	}

	for i,resistance in ipairs(creature:GetResistances()) do
		children[#children+1] = EditResistanceEntry(creature, resistance, {
			change = function(element)
				CharacterSheet.instance:FireEvent('refreshAll')
				CharSheet.CharacterSheetEditResistancesPopup(parentElement, info)
			end,
		})
	end

	children[#children+1] = 
		gui.PrettyButton{
			text = 'Add Resistance',
			width = 200,
			halign = 'center',
			valign = 'bottom',
			fontSize = 20,
			margin = 2,
			height = 50,
			pad = 4,
			hpad = 4,
			events = {
				click = function(element)
					local resistances = creature:GetResistances()

					resistances[#resistances+1] = ResistanceEntry.new{
						apply = 'Resistant',
						damageType = 'slashing',
					}

					creature:SetResistances(resistances)

					CharacterSheet.instance:FireEvent('refreshAll')
					CharSheet.CharacterSheetEditResistancesPopup(parentElement, info)
				end,
			},
		}


	children[#children+1] = gui.Panel{
		bgimage = "panels/square.png",
		bgcolor = "white",
		height = 1,
		width = 100,
		vmargin = 20,
		halign = "center",
	}

	children[#children+1] = gui.Label{
		halign = "center",
		fontSize = 24,
		text = "Innate Condition Immunities",
		width = "auto",
		height = "auto",
	}


	local immunityPanels = {}
	local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)

	for k,v in pairs(creature:try_get("innateConditionImmunities", {})) do
		local condid = k
		local cond = conditionsTable[k]
		if cond ~= nil then
			immunityPanels[#immunityPanels+1] = gui.Label{
				text = cond.name,
				fontSize = 20,
				width = 240,

				gui.DeleteItemButton{
					width = 16,
					height = 16,
					halign = "right",
					valign = "center",
					click = function(element)
						creature:try_get("innateConditionImmunities", {})[k] = nil
						CharacterSheet.instance:FireEvent('refreshAll')
						CharSheet.CharacterSheetEditResistancesPopup(parentElement, info)
					end,
				}
			}

		end
	end

	table.sort(immunityPanels, function(a,b) return a.text < b.text end)
	for _,p in ipairs(immunityPanels) do
		children[#children+1] = p
	end

	children[#children+1] = gui.Dropdown{
		create = function(element)
			local options = {}

			local immunities = creature:try_get("innateConditionImmunities", {})

			for j,cond in pairs(conditionsTable) do
				if cond:try_get("hidden", false) == false and cond.immunityPossible and (not immunities[j]) then
					options[#options+1] = {
						id = j,
						text = cond.name,
					}
				end
			end

			table.sort(options, function(a,b) return a.text < b.text end)
			table.insert(options, 1, {
				id = "none",
				text = "Add Immunity...",
			})

			element.options = options
			element.idChosen = "none"
		end,

		change = function(element)
			if element.idChosen == "none" then
				return
			end

			local immunities = creature:get_or_add("innateConditionImmunities", {})
			immunities[element.idChosen] = true
			CharacterSheet.instance:FireEvent('refreshAll')
			CharSheet.CharacterSheetEditResistancesPopup(parentElement, info)
		end,
	}

	
	element.popupPositioning = "panel"

	element.popup = gui.TooltipFrame(
		gui.Panel{
			width = "auto",
			height = "auto",
			styles = {
				Styles.Default,
				PopupStyles,
			},

			children = children,
		},

		{
			halign = "right",
			interactable = true,
		}
	)
end

function CharSheet.CharacterSheetDefensesPanel()
	local resultPanel
	resultPanel = gui.Panel{
		id = "defensesInnerPanel",
		classes = {"statsPanel"},
		vscroll = true,
		gui.Panel{
			classes = {"statsInnerPanel"},
			halign = "left",
			width = "95%",
			valign = "top",
		
			gui.Label{
				id = "defensesLabel",
				classes = {"valueLabel"},
				height = "auto",
				refreshToken = function(element, info)
					local resistanceDesc = info.token.properties:ResistanceDescription()
					local immunityDesc = info.token.properties:ConditionImmunityDescription()

					if resistanceDesc ~= "" and immunityDesc ~= "" then
						element.text = string.format("%s\n%s", resistanceDesc, immunityDesc)
					elseif resistanceDesc ~= "" then
						element.text = resistanceDesc
					else
						element.text = immunityDesc
					end
				end,
			},
		},
	}

	return resultPanel
end

function CharSheet.CharacterSheetConditions()

	local ongoingEffectPanels = {}

	local activeOngoingEffects

	local resultPanel
	resultPanel = gui.Panel{
		id = "conditionsInnerPanel",
		classes = {"statsPanel"},

		refreshToken = function(element, info)
			local creature = info.token.properties
			local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}
			activeOngoingEffects = creature:ActiveOngoingEffects()

			for i,cond in ipairs(activeOngoingEffects) do
				if i <= 6 then --don't display more than 6 conditions.
					local panel = ongoingEffectPanels[i]
		
					if panel == nil then
						local index = i
						local iconPanel = gui.Panel{
							classes = {'ongoingEffectIconPanel'},
						}
						local closeButton = gui.DeleteItemButton{
							width = 16,
							height = 16,
							halign = 'right',
							valign = 'top',
							floating = true,
							classes = {'hidden-unless-parent-hover'},
							click = function(element)
								creature:RemoveOngoingEffect(activeOngoingEffects[index].ongoingEffectid)
								CharacterSheet.instance:FireEvent('refreshAll')
							end,
						}
						local stacksLabel = gui.Label{
							width = 20,
							height = 20,
							fontSize = 16,
							bold = true,
							editable = true,
							characterLimit = 2,
							color = "white",
							floating = true,
							halign = "right",
							valign = "bottom",
							textAlignment = "right",
							change = function(element)
								local num = tonumber(element.text)
								if num ~= nil then
									if num < 1 then
										creature:RemoveOngoingEffect(activeOngoingEffects[index].ongoingEffectid)
									else
										local cond = activeOngoingEffects[index]
										cond.stacks = num
									end
								end

								CharacterSheet.instance:FireEvent('refreshAll')
							end,
						}
						panel = gui.Panel{
							classes = {'ongoingEffectStatusPanel'},
							bgimage = 'panels/square.png',
							iconPanel,
							closeButton,
							stacksLabel,
							refreshToken = function(element, info)
								local cond = activeOngoingEffects[index]
								if cond == nil then
									return
								end
								local ongoingEffectInfo = ongoingEffectsTable[cond.ongoingEffectid]
								if ongoingEffectInfo == nil then
									dmhub.CloudError("Invalid ongoingEffectid: %s", json(cond.ongoingEffectid))
									return
								end
								stacksLabel:SetClass("collapsed", not ongoingEffectInfo.stackable)
								if ongoingEffectInfo.stackable then
									stacksLabel.text = string.format("%d", cond.stacks)
								end
								iconPanel.bgimage = ongoingEffectInfo.iconid
								--textLabel.text = ongoingEffectInfo.name
								--durationLabel.text = cond:DescribeTimeRemaining()
								for k,v in pairs(ongoingEffectInfo.display) do
									iconPanel.selfStyle[k] = v
								end
							end,

							linger = function(element)
								local cond = activeOngoingEffects[index]
								local ongoingEffectInfo = ongoingEffectsTable[cond.ongoingEffectid]
								if ongoingEffectInfo == nil then
									dmhub.CloudError("Invalid ongoingEffectid: %s", json(cond.ongoingEffectid))
									return
								end

								local stacksText = ""
								if ongoingEffectInfo.stackable and cond.stacks > 1 then
									stacksText = string.format(" (%d stacks)", cond.stacks)
								end

								gui.Tooltip(string.format('%s%s: %s\n%s', ongoingEffectInfo.name, stacksText, ongoingEffectInfo.description, cond:DescribeTimeRemaining()))(element)
							end,
						}
					end

					ongoingEffectPanels[i] = panel

				end
			end

			for i,p in ipairs(ongoingEffectPanels) do
				p:SetClass("collapsed", i > #activeOngoingEffects)

			end

			
			element.children = ongoingEffectPanels
		end,
	}

	return resultPanel
end

function CharSheet.CharacterSheetAvatarPanel()
	local controllerDropdown
	if dmhub.isDM then
		controllerDropdown = gui.Dropdown{
			width = 220,
			height = 26,
			vmargin = 4,
			fontSize = 15,
			halign = "center",
			refreshToken = function(element, info)
				if info.token.charid == nil then
					element:SetClass("hidden", true)
					return
				end

				element:SetClass("hidden", false)

				local options = {}
                if info.token.hasTokenOnAnyMap then
                    options[#options+1] =
                        {
                            id = "gm",
                            text = "Director Controlled",
                        }
                end

				local partyids = GetAllParties()
				for _,partyid in ipairs(partyids) do
					local party = GetParty(partyid)
					options[#options+1] = {
						id = partyid,
						text = party.name
					}
				end

				for _,userid in ipairs(dmhub.users) do
					local sessionInfo = dmhub.GetSessionInfo(userid)
					if not sessionInfo.dm then
						options[#options+1] = {
							id = userid,
							text = sessionInfo.displayName,
						}
					end
				end

				element.options = options

				local ownerId = info.token.ownerId
				if ownerId == "PARTY" then
					element.idChosen = info.token.partyId
				elseif ownerId ~= nil and ownerId ~= "" then
					element.idChosen = ownerId
				else
					element.idChosen = "gm"
				end
			end,

			change = function(element)
				if element.idChosen == "gm" then
					CharacterSheet.instance.data.info.token.ownerId = nil
				elseif GetParty(element.idChosen) ~= nil then
					CharacterSheet.instance.data.info.token.partyId = element.idChosen
				else
					CharacterSheet.instance.data.info.token.ownerId = element.idChosen
				end
			end,
		}
	end


	local resultPanel
	resultPanel = gui.Panel{
		id = "avatarInnerPanel",
		classes = {"statsPanel"},
		vscroll = true,

		gui.Panel{
			id = "tokenImage",

			gui.CreateTokenImage(nil, {
				width = "100%",
				height = "100%",

				refreshAppearance = function(element, info)
					element:FireEventTree("token", info.token)
				end,
				
			}),

			gui.Panel{
				id = "avatarOverlay",
				width = "100%",
				height = "100%",
				bgimage = "panels/square.png",
				bgcolor = "black",

				click = function(element)
					CharacterSheet.instance:FireEvent("toggleAppearance")
				end,

				styles = {
					{
						selectors = {"#avatarOverlay"},
						opacity = 0,
					},
					{
						selectors = {"#avatarOverlay", "hover"},
						opacity = 0.8,
						transitionTime = 0.2,
					},
					{
						selectors = {"parent:press"},
						brightness = 0.7,
						transitionTime = 0.2,
					},
				},

				gui.Label{
					width = "100%",
					height = "20%",
					halign = "center",
					valign = "center",
					bgimage = "panels/square.png",
					bgcolor = "black",
					text = "Customize Appearance",
					color = "white",
					textAlignment = "center",
					fontSize = 14,
					interactable = false,

					styles = {
						{
							opacity = 0,
						},
						{
							selectors = {"parent:hover"},
							opacity = 1,
							transitionTime = 0.2,
						},
						{
							selectors = {"parent:press"},
							brightness = 0.7,
							transitionTime = 0.2,
						},
					},

				},
			},
		},

		controllerDropdown,

		CharSheet.CharacterNameLabel(),

		gui.Label{
			classes = {"statsLabel", "heading"},
			halign = "center",
			width = "100%-18",
			minFontSize = 12,
			textWrap = false,
			textAlignment = "center",
			editable = true,
			refreshAppearance = function(element, info)
				element:SetClass("collapsed", info.token.properties == nil or element.text == "")
			end,
			refreshToken = function(element, info)
				element.text = info.token.properties:try_get("monster_type", "")
				if info.token.properties:IsMonster() and element.text == "" then
					element.text = "(No monster type)"
					element:SetClass("invalid", true)
				else
					element:SetClass("invalid", false)
				end
			end,
			change = function(element)
				local info = CharacterSheet.instance.data.info
				info.token.properties.monster_type = element.text
				CharacterSheet.instance:FireEvent("refreshAll")
			end,
		},

		gui.Label{
			id = "characterRaceLabel",
			classes = {"statsLabel", "editableLabel", "heading"},
			halign = "center",
			refreshAppearance = function(element, info)
				element:SetClass("collapsed", info.token.properties == nil)
			end,
			refreshToken = function(element, info)
				if info.token.properties:IsMonster() then
					element.text = string.format("%s %s", info.token.properties:GetBaseCreatureSize() or info.token.creatureSize, info.token.properties:RaceOrMonsterType())
				else
					element.text = info.token.properties:RaceOrMonsterType()
				end

				element:SetClass("editableLabel", info.token.properties:IsMonster())
			end,

			click = function(element)
				if element.popup ~= nil then
					element.popup = nil
					return
				end
				local parentElement = element
				local info = CharacterSheet.instance.data.info

				--display a popup allowing editing of monster size and type.
				local panels = {}
	
				if info.token.properties:IsMonster() then
					panels[#panels+1] = gui.Panel{
						classes = {'popupPanel'},
						gui.Label{
							classes = {'popupLabel'},
							text = 'Creature Type:',
							minWidth = 140,
						},
						gui.Input{
							width = 220,
							text = info.token.properties:RaceOrMonsterType(),
							change = function(element)
								info.token.properties.monster_category = element.text
								CharacterSheet.instance:FireEvent("refreshAll")
							end,
						},
					}
				end

				local sizeText = "Creature Size"
				local sizeDropdown

				if not info.token.properties:IsMonster() then
					sizeText = "Size Override"
					local sizes = {}
					for _,sz in ipairs(creature.sizes) do
						sizes[#sizes+1] = {
							id = sz,
							text = sz,
						}
					end

					sizes[#sizes+1] = {
						id = "none",
						text = "(No Override)",
					}
					
					sizeDropdown = gui.Dropdown{
						fontSize = 16,
						height = 26,
						width = 220,
						options = sizes,
						idChosen = info.token.properties:try_get("creatureSizeOverride", "none"),
						change = function(element)
							if element.idChosen == "none" then
								info.token.properties.creatureSizeOverride = nil
							else
								info.token.properties.creatureSizeOverride = element.idChosen
							end
							CharacterSheet.instance:FireEvent("refreshAll")
						end,
					}
				else

					sizeDropdown = gui.Dropdown{
						fontSize = 16,
						height = 26,
						width = 220,
						options = creature.sizes,
						idChosen = info.token.properties:GetBaseCreatureSize() or info.token.creatureSize,
						change = function(element)
							info.token.properties.creatureSize = element.idChosen
							CharacterSheet.instance:FireEvent("refreshAll")
						end,
					}

				end


				panels[#panels+1] = gui.Panel{
					classes = {'popupPanel'},
					gui.Label{
						classes = {'popupLabel'},
						text = sizeText,
						minWidth = 140,
					},
					sizeDropdown,

				}
				

				parentElement.popupPositioning = 'panel'
				element.popup = gui.TooltipFrame(
				gui.Panel{
					styles = {
						Styles.Default,
						PopupStyles,
					},

					children = panels
				}, {
					halign = "right",
					valign = "center",
					interactable = true,
				})
			end,
		},

		gui.Label{
			id = "characterAlignmentLabel",
			classes = {"statsLabel", "editableLabel", "heading"},
			halign = "center",
			refreshAppearance = function(element, info)
				element:SetClass("collapsed", info.token.properties == nil)
			end,
			refreshToken = function(element, info)
				element.text = info.token.properties:DescribeAlignment()
			end,

			click = function(element)
				if element.popup ~= nil then
					element.popup = nil
					return
				end

				local parentElement = element
				local info = CharacterSheet.instance.data.info

				local popupPanel = nil

				local index = 1

				local rows = {}
				local alignmentPanels = {}

				for i=1,4 do
					local row = gui.Panel{
						flow = "horizontal",
						width = 600,
						height = 30,
						valign = "center",
						halign = "center",
					}
					local cells = {}
					for j=1,3 do
						if index <= #rules.alignmentIds then
							local alignmentId = rules.alignmentIds[index]

							local alignmentPanel = gui.Label{
								classes = {"alignmentLabel"},
								text = rules.alignments[alignmentId].name,
								click = function(element)
									info.token.properties.alignment = alignmentId
									info.token.properties.customAlignment = nil
									CharacterSheet.instance:FireEvent("refreshAll")
									popupPanel:FireEventTree("refresh")
								end,

								refresh = function(element)
									element:SetClass("selected", alignmentId == info.token.properties:try_get("alignment", info.token.properties:try_get("customAlignment", "unaligned")))
								end,
							}

							alignmentPanels[#alignmentPanels+1] = alignmentPanel

							cells[#cells+1] = alignmentPanel

							index = index+1
						end
					end

					row.children = cells
					rows[#rows+1] = row
				end

				if info.token.properties:IsMonster() then
					rows[#rows+1] = gui.Label{
						classes = {"alignmentLabel"},
						editable = true,
						halign = "center",
						text = "",
						characterLimit = 32,
						change = function(element)
							local text = trim(element.text)
							if text == "" then
								info.token.properties.customAlignment = nil
							else
								info.token.properties.customAlignment = text
								info.token.properties.alignment = nil
							end
							CharacterSheet.instance:FireEvent("refreshAll")
							popupPanel:FireEventTree("refresh")
						end,
						refresh = function(element)
							element.text = info.token.properties:try_get("customAlignment", "(Custom)")
							element:SetClass("selected", info.token.properties:has_key("customAlignment"))
						end,
					}

				end

				popupPanel = gui.Panel{
						flow = "vertical",
						width = "auto",
						height = "auto",
						children = rows,
					}
				
				popupPanel:FireEventTree("refresh")


				parentElement.popupPositioning = 'panel'
				parentElement.popup = gui.TooltipFrame(
					popupPanel,

					{
						halign = "right",
						valign = "center",
						interactable = true,
						styles = {
							{
								selectors = {"alignmentLabel"},
								bold = true,
								color = "#ffffff66",
								fontFace = "inter",
								halign = "center",
								valign = "center",
								fontSize = 16,
								width = 160,
								height = 30,
							},
							{
								selectors = {"alignmentLabel", "hover"},
								color = "#ffffaaff",
							},
							{
								selectors = {"alignmentLabel", "press"},
								color = "#ffffaaaa",
							},
							{
								selectors = {"alignmentLabel", "selected"},
								color = "#ffffffff",
							},
						},
					}
				)
			end,
		},

		gui.Label{
			classes = {"statsLabel", "heading"},
			halign = "center",
			minWidth = 260,
			textAlignment = "center",
			editable = true,
			refreshAppearance = function(element, info)
				element:SetClass("collapsed", info.token.properties == nil or not info.token.properties:IsMonster())
			end,
			refreshToken = function(element, info)
				if info.token.properties:has_key("monster_subtype") and trim(info.token.properties.monster_subtype) ~= "" then
					element.text = info.token.properties.monster_subtype
					element:SetClass("invalid", false)
				else
					element.text = "(no subtype)"
					element:SetClass("invalid", true)
				end
			end,
			change = function(element)
				local info = CharacterSheet.instance.data.info
				local i,j = string.find(element.text, "^%w+$")
				if i ~= nil then
					info.token.properties.monster_subtype = element.text
				else
					info.token.properties.monster_subtype = nil
				end
				CharacterSheet.instance:FireEvent("refreshAll")
			end,
		},

		gui.Label{
			id = "characterLevelLabel",
			classes = {"statsLabel", "heading"},
			halign = "center",
			refreshAppearance = function(element, info)
				element:SetClass("collapsed", info.token.properties == nil)
			end,
			refreshToken = function(element, info)
				if info.token.properties.typeName == "character" then
					local level = info.token.properties:CharacterLevel()
					if level == 0 then
						element.text = "No Class Chosen"
					else
						element.text = string.format("Level %d", level)
					end
				else
					element.text = ""
				end
			end,
		},

		gui.Panel{
			id = "characterLevelsPanel",
			classes = {},

			refreshAppearance = function(element, info)
				element:SetClass("collapsed", info.token.properties == nil or info.token.properties.typeName ~= "character")
			end,

			refreshCharacterInfo = function(element, character)

				local currentPanels = element.children


				local classesTable = dmhub.GetTable('classes')
				local children = {}

				local classes = character:get_or_add("classes", {})
				for i,entry in ipairs(classes) do
					local classInfo = classesTable[entry.classid]
					if classInfo ~= nil then
						local label = currentPanels[i] or gui.Label{
							classes = {"statsLabel", "classLevelLabel"},
						}

						label.text = string.format("%s %d", classInfo.name, entry.level)

						children[#children+1] = label
					end
				end

				element.children = children
			end,
		},

		gui.Label{
			classes = {"link", "statsLabel"},
			fontSize = 11,
			halign = "center",
			valign = "top",
			text = "Source",
			refreshAppearance = function(element, info)
				element:SetClass("collapsed", info.token.properties == nil or info.token.properties:try_get("source") == nil)
				if element:HasClass("collapsed") == false then
					element.text = dmhub.DescribeDocument(info.token.properties.source)
				end
			end,
			click = function(element)
				local info = CharacterSheet.instance.data.info
				dmhub.OpenDocument(info.token.properties.source)
			end,
		},

	}
	return resultPanel
end

function CharSheet.CharacterBuilderAccessPanel()
	local resultPanel

	resultPanel = gui.Panel{

		id = "characterBuilderAccessPanel",

		gui.Panel{
			height = "50%",
			width = "100%",
			flow = "horizontal",

			gui.Panel{
				classes = {"characterBuilderAccessPanelIcon"},
				bgimage = "panels/character-sheet/Badge_11.png",
				linger = gui.Tooltip("Inventory"),
				click = function(element)
					local creature = CharacterSheet.instance.data.info.token.properties
					CharacterSheet.instance:FireEvent("escape")

					creature.commands.inventory(creature)
					
				end,
			},
			gui.Panel{
				classes = {"characterBuilderAccessPanelIcon"},
				bgimage = "panels/character-sheet/Badge_23.png",
				linger = gui.Tooltip("Spells"),
				click = function(element)
					local creature = CharacterSheet.instance.data.info.token.properties
					CharacterSheet.instance:FireEvent("escape")

					Commands.spells(creature)
				end,
			},
			gui.Panel{
				classes = {"characterBuilderAccessPanelIcon"},
				bgimage = "panels/character-sheet/Badge_14.png",
			},
		},

		gui.Panel{
			id = "characterBuilderAccessButton",
			bgimage = "panels/square.png",
			refreshToken = function(element, info)
				element:SetClass("hidden", info.token.properties.typeName ~= 'character')
			end,
			click = function(element)
				CharacterSheet.instance:FireEventTree("showBuilder", true)
			end,
			gui.Label{
				text = "CHARACTER\nBUILDER",
				classes = "statsLabel",
				width = "50%",
				height = "auto",
				halign = "center",
				valign = "center",
				textAlignment = "center",
			},
			gui.Panel{
				id = "characterBuilderIcon",
				floating = true,
			},
		},

	}

	return resultPanel
end

function CharSheet.InspirationPanel()
	local resultPanel

	resultPanel = gui.Panel{
		classes = {"attributePanel", "inspiration"},
		refreshToken = function(element, info)
			element:SetClass("collapsed", info.token.properties.typeName ~= "character")
		end,

		gui.Panel{
			gui.Panel{
				floating = true,
				halign = "center",
				valign = "center",
				width = 60,
				height = 60,
				borderWidth = 2,
				borderColor = Styles.textColor,
				bgimage = "panels/square.png",
				bgcolor = "clear",
				rotate = 45,
			},

			gui.Panel{
				floating = true,
				halign = "center",
				valign = "center",
				width = 62,
				height = 62,
				cornerRadius = 31,
				borderWidth = 1.4,
				borderColor = Styles.textColor,
				bgimage = "panels/square.png",
				bgcolor = "clear",
				rotate = 45,
			},



			classes = {"attributeModifierPanel", "inspiration"},
			click = function(element)
				local creature = CharacterSheet.instance.data.info.token.properties
				creature:SetInspiration(not creature:HasInspiration())
				CharacterSheet.instance:FireEvent("refreshAll")
			end,

			gui.Panel{
				id = "inspirationIcon",
				interactable = false,

				styles = {
					{
						opacity = 0,
					},
					{
						selectors = {"parent:hover"},
						transitionTime = 0.2,
						opacity = 0.5,
						saturation = 0,
					},
					{
						selectors = {"inspired"},
						transitionTime = 0.2,
						opacity = 1,
						saturation = 1,
					},
				},

				refreshToken = function(element, info)
					element:SetClass("inspired", info.token.properties:HasInspiration())
				end,
			},
		},
		gui.Label{
			classes = {"statsLabel","inspiration"},
			text = "INSPIRATION",
		},
	}

	return resultPanel
end

function CharSheet.InitiativePanel()
	local resultPanel

	resultPanel = gui.Panel{
		classes = {"attributePanel", "initiative"},
		gui.Panel{
			classes = {"attributeModifierPanel", "initiative"},
			gui.Label{
				classes = {"attributeModifierLabel", "valueLabel", "initiative", "dice"},
				refreshToken = function(element, info)
					ChangeLabelValue(info, element, info.token.properties:InitiativeBonusStr())
				end,
				press = function(element)
					CharacterSheet.instance.data.info.token.properties:RollInitiative()
				end,
			},

			gui.Panel{
				classes = {"panelSettingsButton"},
				halign = "right",
				valign = "bottom",
				hmargin = 20,
				vmargin = 16,
				press = function(element)

					local initiativeElement = element
					
					local creature = CharacterSheet.instance.data.info.token.properties

					if element.popup ~= nil then
						element.popup = nil
						return
					end

					local panels = {}

					local details = creature:InitiativeDetails()
					if details == nil then
						return
					end

					local showNotes = false

					for i,entry in ipairs(details) do

						showNotes = showNotes or entry.showNotes

						local textValue = entry.value
						if entry.edit ~= nil and textValue == nil then
							textValue = '(none)'
						end

						panels[#panels+1] = gui.Panel({
							style = {
								width = 240,
								height = 24,
								fontSize = 20,
								halign = 'center',
								valign = 'center',
								flow = 'horizontal',
							},

							children = {
								gui.Label({
									text = entry.key,
									style = {
										width = 'auto',
										height = 'auto',
										textAlignment = 'left',
										halign = 'left',
										valign = 'center',
									},
								}),
								gui.Panel{ --padding.
									style = {
										width = 8,
										height = 1,
									},
								},
								gui.Label({
									text = textValue,
									editable = entry.edit ~= nil,
									style = {
										width = 'auto',
										height = 'auto',
										textAlignment = 'right',
										halign = 'right',
										valign = 'center',
									},
									events = {
										change = function(element)
											creature[entry.edit](creature, element.text)
											initiativeElement.popup = nil
											initiativeElement:FireEvent('press')
											CharacterSheet.instance:FireEvent('refreshAll')
										end,
									},
								})
							},
						})

					end

					if showNotes ~= nil then

						--padding
						panels[#panels+1] = gui.Panel{
							style = {
								width = 1,
								height = 8,
							},
						}

						panels[#panels+1] = gui.Label{
							text = 'Rules Notes:',
							style = {
								textAlignment = 'left',
								halign = 'left',
								fontSize = '50%',
								width = 'auto',
								height = 'auto',
							},
						}

						panels[#panels+1] = gui.Input{
							text = creature:InitiativeNotes(),
							multiline = true,
							characterLimit = 1024,
							placeholderText = 'Notes on initiative calculation...',
							textAlignment = 'topleft',
							fontSize = 14,
							width = 300,
							height = "auto",
							maxHeight = 100,
							events = {
								change = function(element)
									creature:SetInitiativeNotes(element.text)
								end,
							},
						}
					
					end

					element.popupPositioning = 'panel'
					element.popup = gui.TooltipFrame(
				
						gui.Panel({
							selfStyle = {
								pad = 8,
							},
							styles = {
								Styles.Default,
								{
									valign = 'bottom',
									halign = 'center',
									width = 'auto',
									height = 'auto',
									bgcolor = 'black',
									flow = 'vertical',
								},
								{
									selectors = {'editable'},
									color = '#aaaaff',
								}
							},
							children = panels,
						}), {
							interactable = true,
						}
					)

				end,
			},
		},
		gui.Label{
			classes = {"statsLabel","initiative"},
			text = "INITIATIVE",
		},
	}

	return resultPanel
end

local function concatdc(dc)
	if type(dc) == "table" then
		return table.concat(dc, "/")
	else
		return dc
	end
end

function CharSheet.ChallengeRatingPanel()
	local resultPanel

	resultPanel = gui.Panel{
		classes = {"attributePanel", "cr"},
		refreshToken = function(element, info)
			element:SetClass("collapsed", not info.token.properties:IsMonster())
		end,
		gui.Panel{
			classes = {"attributeModifierPanel", "cr"},
			gui.Label{
				classes = {"attributeModifierLabel", "valueLabel", "cr"},
				minWidth = 80,
				characterLimit = 4,
				refreshToken = function(element, info)
					if info.token.properties:IsMonster() then
						element.text = info.token.properties:PrettyCR()
					end
				end,
				editable = true,
				change = function(element)
					CharacterSheet.instance.data.info.token.properties:SetCR(element.text)
					CharacterSheet.instance:FireEvent('refreshAll')
				end,
			},
		},
		gui.Label{
			classes = {"statsLabel","cr"},
			text = GameSystem.CRName,
		},
	}

	return resultPanel
end

function CharSheet.ProficiencyBonusPanel()
	local resultPanel

	resultPanel = gui.Panel{
		classes = {"attributePanel", "proficiencyBonus"},
		gui.Panel{
			classes = {"attributeModifierPanel", "proficiencyBonus"},
			gui.Label{
				classes = {"attributeModifierLabel", "valueLabel", "proficiencyBonus"},
				minWidth = 80,
				characterLimit = 4,
				refreshToken = function(element, info)
					element.text = ModStr(GameSystem.CalculateProficiencyBonus(info.token.properties, GameSystem.Proficient()))
				end,
			},
		},
		gui.Label{
			classes = {"statsLabel","proficiencyBonus"},
			halign = "center",
			textAlignment = "center",
			text = "PROFICIENCY\nBONUS",
		},
	}

	return resultPanel
end

function CharSheet.AttrModificationOrbPanel(attrid)
	local modificationOrbs = {}
	local CreateModificationOrb = function()
		return gui.Panel{
			classes = {"modificationOrb"},
			data = {
				info = nil,
				c = nil,
			},
			hover = function(element)
				local additionalDescription = ""
				if element.data.info.modifier ~= nil then
					local description = CharacterFeature.FindDescriptionFromDomainMap(element.data.info.modifier:Domains())
					if description ~= nil then
						additionalDescription = string.format(" (%s)", description)
					end
				end
				gui.Tooltip(string.format("%s: %s%s", element.data.info.key, element.data.info.value, additionalDescription))(element)
			end,
			setclass = function(element, c)
				if element.data.c == c then
					return
				end

				if element.data.c ~= nil then
					element:SetClass(element.data.c, false)
				end

				if c ~= nil then
					element:SetClass(c, true)
				end

				element.data.c = c
			end,
		}
	end


	return gui.Panel{
		floating = true,

		classes = {"modificationOrbContainer"},

		refreshToken = function(element, info)
			element:FireEvent("refreshOrb", info.token.properties)
		end,

		refreshOrb = function(element, creature)
			local attr = creature:GetAttribute(attrid)
			local description = creature:DescribeModifications(attrid, attr.baseValue)
			local modified = #description ~= #modificationOrbs
			while #description > #modificationOrbs and #modificationOrbs < 5 do
				modificationOrbs[#modificationOrbs+1] = CreateModificationOrb()
			end

			while #modificationOrbs > #description do
				modificationOrbs[#modificationOrbs] = nil
			end

			for i,item in ipairs(description) do
				if i <= #modificationOrbs then
					local orb = modificationOrbs[i]
					orb.data.info = item

					local classification = nil

					local domains = nil
					if item.modifier ~= nil then
						domains = item.modifier:Domains()
						if domains ~= nil then
							for k,v in pairs(domains) do
								local colon = string.find(k, ":")
								if colon ~= nil then
									classification = string.sub(k, 1, colon-1)
									break
								end
							end
						end
					end

					orb:FireEvent("setclass", classification)
					orb:SetClass("unchanged", domains ~= nil and domains.unchanged ~= nil)
					orb:SetClass("debuff", domains ~= nil and domains.debuff ~= nil)
				end
			end

			if modified then
				element.children = modificationOrbs
			end
		end,
	}
end

function CharSheet.AttrPanel(attrid)
	local resultPanel



	resultPanel = gui.Panel{
		classes = {"attributePanel"},

		gui.Panel{
			classes = {"attributeModifierPanel"},
			gui.Label{
				classes = {"attributeModifierLabel", "valueLabel", "dice"},
				refreshToken = function(element, info)
					ChangeLabelValue(info, element, ModifierStr(info.token.properties:GetAttribute(attrid):Modifier()))
				end,
				press = function(element)
					CharacterSheet.instance.data.info.token.properties:RollAttributeCheck(attrid)
				end,

			},

			gui.Panel{
				classes = {"attributeStatPanel"},
				floating = true,
				gui.Panel{
					classes = {"attributeStatPanelBorder"},
				},
				gui.Label{
					data = {
						creature = nil,
						info = nil,
					},
					classes = {"attributeStatLabel", "editable"},

					refreshToken = function(element, info)
						local attr = info.token.properties:GetAttribute(attrid)
						element.text = tostring(attr:Value())
						element.data.creature = info.token.properties
						element.data.info = info

					end,


					click = function(element)
						if not element:HasClass('editable') then
							return
						end

						local parentElement = element

						local baseValue = element.data.creature:GetBaseAttribute(attrid).baseValue

						local panels = {}

						panels[#panels+1] = gui.Panel{
							classes = {'popupPanel'},
							gui.Label{
								classes = {'popupLabel'},
								text = 'Base Value:',
							},
							gui.Label{
								classes = {'popupValue','editable'},
								editable = true,
								text = tostring(baseValue),
								events = {
									create = function(element)
										element:BeginEditing()
									end,
									change = function(element)
										local num = tonumber(element.text)
										if num ~= nil then
											parentElement.data.creature:GetBaseAttribute(attrid).baseValue = num
										end

										element.text = tostring(parentElement.data.creature:GetBaseAttribute(attrid).baseValue)
										CharacterSheet.instance:FireEvent('refreshAll')
										parentElement.popup:FireEventTree('refreshToken', parentElement.data.info) --make sure elements within the popup itself get refreshed.
									end,
								}
							},
						}

						local modifications = parentElement.data.creature:DescribeModifications(attrid, baseValue)
						for i,mod in ipairs(modifications) do
							panels[#panels+1] = gui.Panel{
								classes = {'popupPanel'},
								gui.Label{
									classes = {'popupLabel'},
									text = string.format("%s:", mod.key),
								},
								gui.Label{
									classes = {'popupValue'},
									text = mod.value,
								},
							}
						end


						local attrAdd = parentElement.data.creature:try_get("attributesBonusAdd") or {}
						local attrOverride = parentElement.data.creature:try_get("attributesOverride") or {}

						panels[#panels+1] = gui.Panel{
							classes = {"popupPanel"},
							gui.Label{
								classes = {'popupLabel'},
								text = "Custom Bonus:",
							},
							gui.Label{
								classes = {'popupValue'},
								text = attrAdd[attrid] or "--",
								editable = true,
								characterLimit = 3,

								change = function(element)
									attrAdd = parentElement.data.creature:try_get("attributesBonusAdd") or {}
									local n = tonumber(element.text)
									if type(n) == "number" then
										n = round(n)
										element.text = string.format("%d", n)
									else
										element.text = "--"
									end

									attrAdd[attrid] = n
									parentElement.data.creature.attributesBonusAdd = attrAdd
									CharacterSheet.instance:FireEvent("refreshAll")
								end,

							},
						}

						panels[#panels+1] = gui.Panel{
							classes = {"popupPanel"},
							gui.Label{
								classes = {'popupLabel'},
								text = "Custom Override:",
							},
							gui.Label{
								classes = {'popupValue'},
								text = attrOverride[attrid] or "--",
								editable = true,
								characterLimit = 3,
								change = function(element)
									attrOverride = parentElement.data.creature:try_get("attributesOverride") or {}
									local n = tonumber(element.text)
									if type(n) == "number" then
										n = round(n)
										element.text = string.format("%d", n)
									else
										element.text = "--"
									end

									attrOverride[attrid] = n
									parentElement.data.creature.attributesOverride = attrOverride
									CharacterSheet.instance:FireEvent("refreshAll")
								end,
							},
						}

						panels[#panels+1] = gui.Panel{
							classes = {'popupPanel'},
							gui.Label{
								classes = {'popupLabel'},
								text = 'Total Value:',
							},
							gui.Label{
								classes = {'popupValue'},
								text = tostring(element.data.creature:GetAttribute(attrid):Value()),
								events = {
									refreshToken = function(element, info)
										element.text = tostring(parentElement.data.creature:GetAttribute(attrid):Value())
									end,
								},
							},
						}

						element.popup = gui.TooltipFrame(
							gui.Panel{
								styles = {
									Styles.Default,
									PopupStyles,
								},

								children = panels
							},
							{
								interactable = true,
							}
						)

					end,

				},

				CharSheet.AttrModificationOrbPanel(attrid),
			},
		},

		gui.Label{
			classes = {"attrLabel","attributeIdLabel"},
			text = string.upper(attrid),
		},
	}

	return resultPanel
end

CharSheet.TabsStyles = {
	gui.Style{
		selectors = {"tabContainer"},
		height = 40,
		width = "100%",
		flow = "horizontal",
		bgcolor = "black",
		bgimage = "panels/square.png",
		borderColor = Styles.textColor,
		border = { y1 = 2 },
		vmargin = 1,
		hmargin = 2,
		halign = "center",
		valign = "top",
	},
	gui.Style{
		selectors = {"tab"},
		fontFace = "Inter",
		fontWeight = "light",
		bold = false,
		bgcolor = "#111111ff",
		bgimage = "panels/square.png",
		brightness = 0.4,
		valign = "top",
		halign = "left",
		hpad = 20,
		width = 200,
		height = "100%",
		hmargin = 0,
		color = Styles.textColor,
		textAlignment = "center",
		fontSize = 26,
		minFontSize = 12,
	},
	gui.Style{
		selectors = {"tab", "small"},
		fontSize = 16,
		minFontSize = 8,
		width = 120,
	},
	gui.Style{
		selectors = {"tab", "hover"},
		brightness = 1.2,
		transitionTime = 0.2,
	},
	gui.Style{
		selectors = {"tab", "selected"},
		brightness = 1,
		transitionTime = 0.2,
	},
	gui.Style{
		selectors = {"tabBorder"},
		width = "100%",
		height = "100%",
		border = {x1 = 2, x2 = 2, y1 = 2},
		borderColor = Styles.textColor,
		bgimage = "panels/square.png",
		bgcolor = "clear",
	},
	gui.Style{
		selectors = {"tabBorder", "parent:selected"},
		border = {x1 = 2, x2 = 2, y1 = 0}
	},
}

local ActionsAndFeaturesStyles = {
	{
		selectors = {"statsHeader"},
		width = "90%",
		height = 40,
		flow = "horizontal",
		halign = "center",
		valign = "top",
	},
	CharSheet.TabsStyles,

	{
		selectors = {"featuresScrollPanel"},
		width = "100%",
		height = "90%",
		valign = "center",
	},
	{
		selectors = {"featuresPanel"},
		width = "97%",
		hmargin = 4,
		halign = "left",
		height = "auto",
	},
	{
		selectors = {"tableData"},
		valign = "center",
	},
	{
		selectors = {"abilityIcon"},
		width = "8%",
	},
	{
		selectors = {"abilityName"},
		width = "22%",
	},
	{
		selectors = {"abilityRange"},
		width = "17%",
	},
	{
		selectors = {"abilityHit"},
		width = "11%",
	},
	{
		selectors = {"abilityDamage"},
		width = "35%",
	},
	{
		selectors = {"abilityEdit"},
		width = "4%",
		height = "auto",
		valign = "center",
	},

	{
		selectors = {"abilitySave"},
		width = "9%",
	},
	{
		selectors = {"abilityEffect"},
		width = "28%",
	},

	{
		selectors = {"abilityUses"},
		width = "11%",
	},

	{
		selectors = {"tableData", "spellTable", "abilityRange"},
		fontSize = 14,
	},

	{
		selectors = {"tableData", "abilitySave"},
		fontSize = 14,
	},

	{
		selectors = {"tableData", "abilityUses"},
		fontSize = 14,
	},

	{
		selectors = {"abilityEditIcon"},
		bgimage = "panels/character-sheet/gear.png",
		bgcolor = "white",
		width = 16,
		height = 16,
		valign = "center",
		halign = "right",
	},
	{
		selectors = {"statsRow"},
		height = "auto",
	},
	{
		selectors = {"abilityIconBackground"},
		height = 32,
		width = 32,
		bgcolor = "white",
		bgimage = 'panels/InventorySlot_Background.png',
	},
	{
		selectors = {"abilityIconIcon"},
		width = "100%",
		height = "100%",
		bgcolor = "white",
	},
	{
		selectors = {"abilityTableTitle"},
		fontSize = "150%",
		halign = "center",
		width = "auto",
		height = "auto",
	},
}

gui.RegisterTheme("charsheet", "Features", ActionsAndFeaturesStyles)

function CharSheet.ActionsPanel()

	local attackPanels = {}
	local spellPanels = {}

	local creatureLookup = nil

	local abilities = {}
	local attacks = {}
	local attackAbilities = {}
	local spellAbilities = {}
	local standardAbilities = {}
	local legendaryAbilities = {}

	local CreateAbilitiesPanel = function(otherAbilities, options)
		local otherAbilityPanels = {}
		return gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",

			refreshToken = function(element, info)
				element:SetClass("collapsed", #otherAbilities == 0)
			end,

			gui.Label{
				classes = {"statsLabel", "abilityTableTitle"},
				text = options.title,
			},

			--heading
			gui.Panel{
				classes = {"statsRow"},
				gui.Label{
					classes = {"statsLabel", "tableHeading", "abilityIcon"},
					text = "",
				},
				gui.Label{
					classes = {"statsLabel", "tableHeading", "abilityName"},
					text = "NAME",
				},
				gui.Label{
					classes = {"statsLabel", "tableHeading", "abilityUses"},
					text = "USES",
				},
				gui.Label{
					classes = {"statsLabel", "tableHeading", "abilityRange"},
					text = "RANGE",
				},
				gui.Label{
					classes = {"statsLabel", "tableHeading", "abilitySave"},
					text = "SAVE",
				},
				gui.Label{
					classes = {"statsLabel", "tableHeading", "abilityEffect"},
					text = "EFFECT",
				},
				gui.Label{
					classes = {"statsLabel", "tableHeading", "abilityEdit"},
					text = "",
				},
			},

			gui.Panel{
				width = "100%",
				height = "auto",
				flow = "vertical",
				refreshToken = function(element, info)
					local children = {}
					local newPanels = {}

					for i,ability in ipairs(otherAbilities) do

						local panel = otherAbilityPanels[i] or gui.Panel{
							classes = {"statsRow", "otherAbilityTable"},

							linger = function(element)
								local tooltip = CreateAbilityTooltip(otherAbilities[i], {token = CharacterSheet.instance.data.info.token})
								tooltip.selfStyle.halign = "center"
								tooltip.selfStyle.valign = "top"
								element.tooltip = tooltip
							end,

							gui.Panel{
								classes = {"statsLabel", "abilityIcon", "tableData", "otherABilityTable"},
								gui.Panel{
									classes = {"abilityIconBackground"},
									gui.Panel{
										classes = {"abilityIconIcon"},
										refreshToken = function(element, info)
											element.bgimage = otherAbilities[i].iconid
										end,
									},
									gui.PrettyBorder{ width = 9 },
								},
							},
							gui.Label{
								classes = {"statsLabel", "abilityName", "tableData", "otherAbilityTable"},
							},
							gui.Label{
								classes = {"statsLabel", "valueLabel", "abilityUses", "tableData", "otherAbilityTable"},
								data = {
									resourceid = nil,
									maxCharges = nil,
									availableCharges = nil,
									refreshType = nil,
									abilityName = nil
								},
								press = function(element)
									local parentPanel = element
									if element.data.resourceid ~= nil then
										element.popupPositioning = 'panel'
										element.popup = gui.TooltipFrame(
			
											gui.Panel({
												selfStyle = {
													pad = 8,
												},
												styles = {
													Styles.Default,
													{
														valign = 'bottom',
														halign = 'center',
														width = 'auto',
														height = 'auto',
														bgcolor = 'black',
														flow = 'vertical',
														color = '#c4c1aa',
													},
													{
														selectors = {'editable'},
														color = '#d4d1ba',
													}
												},

												gui.Panel{
													flow = "vertical",
													width = "auto",
													height = "auto",
													gui.Label{
														width = "auto",
														height = "auto",
														halign = "center",
														fontSize = 16,
														color = "white",
														text = parentPanel.data.abilityName,
													},
													gui.Panel{
														flow = "horizontal",
														width = "auto",
														height = "auto",
														gui.Label{
															editable = true,
															characterLimit = 3,
															fontSize = 14,
															width = 30,
															height = "auto",
															text = string.format("%d", parentPanel.data.availableCharges),
															change = function(element)
																local number = tonumber(element.text)
																if number ~= nil and number >= 0 and number <= parentPanel.data.maxCharges then
																	local diff = number - parentPanel.data.availableCharges
																	parentPanel.popup = nil
																	CharacterSheet.instance.data.info.token.properties:ConsumeResource(parentPanel.data.resourceid, parentPanel.data.refreshType, -diff)
																	CharacterSheet.instance:FireEvent("refreshAll")
																end
															end,
														},
														gui.Label{
															fontSize = 14,
															width = 12,
															height = "auto",
															text = "/",
														},

														gui.Label{
															fontSize = 14,
															width = 30,
															height = "auto",
															text = string.format("%d", parentPanel.data.maxCharges),
														},
													},
												}
												
											}), {
												interactable = true,
											}
										)

									end
								end,
							},
							gui.Label{
								classes = {"statsLabel", "abilityRange", "tableData", "otherAbilityTable"},
							},
							gui.Label{
								classes = {"statsLabel", "abilitySave", "tableData", "otherAbilityTable"},
							},
							gui.Label{
								classes = {"statsLabel", "abilityEffect", "tableData", "otherAbilityTable"},
							},

							gui.Panel{
								classes = {"statsLabel", "abilityEdit", "tableData"},

								gui.Panel{
									classes = { "abilityEditIcon" },
									click = function(element)
										local a = otherAbilities[i]
										CharacterSheet.instance:AddChild(a:ShowEditActivatedAbilityDialog{
											close = function(element)
												CharacterSheet.instance:FireEvent("refreshAll")
											end,
											delete = function(element)
												options.delete(a)
											end,
										})
									end,
								},
							},
						}

						local dataItems = panel.children

						dataItems[3].data.resourceid = nil
						dataItems[3].data.availableCharges = nil
						dataItems[3].data.maxCharges = nil
						dataItems[3].text = "--"

						local costInfo = ability:GetCost(CharacterSheet.instance.data.info.token)
						for i,item in ipairs(costInfo.details) do
							if item.description ~= nil then
								dataItems[3].text = item.description
								dataItems[3].data.abilityName = ability.name
								dataItems[3].data.resourceid = item.cost
								dataItems[3].data.availableCharges = item.availableCharges
								dataItems[3].data.maxCharges = item.maxCharges
								dataItems[3].data.refreshType = item.refreshType
							end
						end

						dataItems[2].text = ability.name
						dataItems[4].text = ability:DescribeAOE()

						local dctext = "--"
						for _,behavior in ipairs(ability.behaviors) do
							if behavior:has_key("dc") then
								dctext = string.format("%s%d", string.upper(concatdc(behavior.dc)), ability:SaveDC(CharacterSheet.instance.data.info.token, behavior))
							end
						end

						dataItems[5].text = dctext

						dataItems[6].text = ability:SummarizeBehavior(creatureLookup)

						dataItems[7]:SetClass("hidden", (not info.token.properties:IsActivatedAbilityInnate(ability)) and (not info.token.properties:IsActivatedAbilityLegendary(ability)))

						newPanels[i] = panel
						children[#children+1] = panel
					end

					otherAbilityPanels = newPanels
					element.children = children
				end,
			},
		}
	end

	return gui.Panel{
		classes = {"featuresScrollPanel"},
		vscroll = true,
		refreshToken = function(element, info)
			creatureLookup = info.token.properties:LookupSymbol()
			abilities = info.token.properties:GetActivatedAbilities{ characterSheet = true }
			attacks = {}
			attackAbilities = {}
			spellAbilities = {}

			while #standardAbilities > 0 do
				standardAbilities[#standardAbilities] = nil
			end

			while #legendaryAbilities > 0 do
				legendaryAbilities[#legendaryAbilities] = nil
			end

			for i,ability in ipairs(abilities) do
				if ability:GetAttackBehavior() ~= nil then
					--this is an attack
					attackAbilities[#attackAbilities+1] = ability
					attacks[#attacks+1] = ability:GetAttackBehavior():GetAttack(ability, info.token.properties, {})
				elseif ability.typeName == "Spell" then
					spellAbilities[#spellAbilities+1] = ability
				elseif ability.legendary then
					legendaryAbilities[#legendaryAbilities+1] = ability
				else
					standardAbilities[#standardAbilities+1] = ability
				end
			end

			printf("REFRESH TOKEN: abilities = %d; standard = %d; legendary = %d", #abilities, #standardAbilities, #legendaryAbilities)
		end,
		gui.Panel{
			 classes = {"featuresPanel"},
			 flow = "vertical",

			 gui.Panel{
				id = "attacksTable",
				width = "100%",
				height = "auto",
				flow = "vertical",
				refreshToken = function(element, info)
					element:SetClass("collapsed", #attackAbilities == 0)
				end,

				gui.Label{
					classes = {"statsLabel", "abilityTableTitle"},
					text = "Attacks",
				},

				--heading
				gui.Panel{
					classes = {"statsRow"},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityIcon"},
						text = "",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityName"},
						text = "NAME",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityRange"},
						text = "RANGE",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityHit"},
						text = "HIT",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityDamage"},
						text = "DAMAGE",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityEdit"},
						text = "",
					},
				},

				--attack panel.
				gui.Panel{
					width = "100%",
					height = "auto",
					flow = "vertical",
					refreshToken = function(element, info)

						local children = {}
						local newAttackPanels = {}
						for i,ability in ipairs(attackAbilities) do

							local panel = attackPanels[i] or gui.Panel{
								classes = {"statsRow", "attackTable"},

								linger = function(element)
									local tooltip = CreateAbilityTooltip(attackAbilities[i], {token = CharacterSheet.instance.data.info.token})
									tooltip.selfStyle.halign = "center"
									tooltip.selfStyle.valign = "top"
									element.tooltip = tooltip
								end,

								gui.Panel{
									classes = {"statsLabel", "abilityIcon", "tableData"},
									gui.Panel{
										classes = {"abilityIconBackground"},
										gui.Panel{
											classes = {"abilityIconIcon"},
											refreshToken = function(element, info)
												element.bgimage = attackAbilities[i].iconid
												element.selfStyle = attackAbilities[i].display
											end,
										},
										gui.PrettyBorder{ width = 9 },
									},
								},
								gui.Label{
									classes = {"statsLabel", "abilityName", "tableData"},
								},
								gui.Label{
									classes = {"statsLabel", "abilityRange", "tableData"},
								},
								gui.Label{
									classes = {"statsLabel", "abilityHit", "tableData", "valueLabel", "dice"},
									press = function(element)
										CharacterSheet.instance.data.info.token.properties:RollAttackHit(element.data.attack, nil, {autoroll = true})
									end,
									data = {},
								},
								gui.Label{
									classes = {"statsLabel", "abilityDamage", "tableData", "valueLabel", "dice"},
									press = function(element)
										CharacterSheet.instance.data.info.token.properties:RollAttackDamage(element.data.attack)
									end,
									data = {},
								},
								gui.Panel{
									classes = {"statsLabel", "abilityEdit", "tableData"},

									gui.Panel{
										classes = { "abilityEditIcon" },
										click = function(element)
											local a = attackAbilities[i]
											CharacterSheet.instance:AddChild(a:ShowEditActivatedAbilityDialog{
												close = function(element)
													CharacterSheet.instance:FireEvent("refreshAll")
												end,
												delete = function(element)
													CharacterSheet.instance.data.info.token.properties:RemoveInnateActivatedAbility(a)
												end,
											})
										end,
									},

								},
							}

							local attack = attacks[i]

							local dataItems = panel.children
							dataItems[2].text = attack.name

							local range = attack.range
							if tonumber(range) ~= nil then
								range = string.format("%s%s", MeasurementSystem.NativeToDisplayString(range), MeasurementSystem.Abbrev())
							end
							dataItems[3].text = range
							dataItems[4].text = ModStr(attack.hit)

							dataItems[4].data.attack = attack
							dataItems[5].data.attack = attack

							local damageRoll = ""
							for j,damageInstance in ipairs(attack.damageInstances) do
								damageRoll = string.format("%s %s [%s%s]", damageRoll, damageInstance.damage, cond(damageInstance:try_get("magicalDamage", false), "magic ", ""), damageInstance.damageType)
							end

							damageRoll = trim(dmhub.NormalizeRoll(dmhub.EvalGoblinScript(damageRoll, creatureLookup, "Calculate attack damage on character sheet")))

							--try not to break a damage roll in inconvenient places.
							damageRoll = string.gsub(damageRoll, ' %[', nbsp .. '[')
							damageRoll = string.gsub(damageRoll, 'magic ', 'magic' .. nbsp)

							dataItems[5].text = damageRoll

							dataItems[6]:SetClass("hidden", not info.token.properties:IsActivatedAbilityInnate(ability))

							newAttackPanels[i] = panel
							children[#children+1] = panel
						end

						attackPanels = newAttackPanels
						element.children = children
					end,
				},
			 },

			 CreateAbilitiesPanel(standardAbilities, {
				title = "Abilities",
				delete = function(a)
					CharacterSheet.instance.data.info.token.properties:RemoveInnateActivatedAbility(a)
				end,
			 }),
	
			gui.Button{
				text = "Add Ability",
				halign = "right",
				fontSize = 16,
				click = function(element)
					local newAbility = ActivatedAbility.Create{
						name = "New Ability",
					}

					CharacterSheet.instance:AddChild(newAbility:ShowEditActivatedAbilityDialog{
						add = function(element)
							CharacterSheet.instance.data.info.token.properties:AddInnateActivatedAbility(newAbility)
							CharacterSheet.instance:FireEvent("refreshAll")
						end,
						cancel = function(element)
						end,
					})
				end,
			},

			CreateAbilitiesPanel(legendaryAbilities, {
				title = "Legendary Actions",
				delete = function(a)
					CharacterSheet.instance.data.info.token.properties:RemoveInnateLegendaryAction(a)
				end,
			}),
	
			gui.Button{
				text = "Add Legendary Action",
				halign = "right",
				fontSize = 16,
				refreshToken = function(element, info)
					element:SetClass("collapsed", not CharacterSheet.instance.data.info.token.properties:IsMonster())
				end,
				click = function(element)
					local newAbility = ActivatedAbility.Create{
						name = "Legendary Action",
						legendary = true,
					}

					CharacterSheet.instance:AddChild(newAbility:ShowEditActivatedAbilityDialog{
						add = function(element)
							CharacterSheet.instance.data.info.token.properties:AddInnateLegendaryAction(newAbility)
							CharacterSheet.instance:FireEvent("refreshAll")
						end,
						cancel = function(element)
						end,
					})
				end,
			},

			--spells panel.
			gui.Panel{
				id = "spellTable",
				width = "100%",
				height = "auto",
				flow = "vertical",

				refreshToken = function(element, info)
					element:SetClass("collapsed", #spellAbilities == 0)
				end,

				gui.Label{
					classes = {"statsLabel", "abilityTableTitle"},
					text = "Spells",
				},

				--heading
				gui.Panel{
					classes = {"statsRow"},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityIcon"},
						text = "",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityName"},
						text = "NAME",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityRange"},
						text = "RANGE",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilitySave"},
						text = "SAVE",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityEffect"},
						text = "EFFECT",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityEdit"},
						text = "",
					},
				},

				gui.Panel{
					width = "100%",
					height = "auto",
					flow = "vertical",
					refreshToken = function(element, info)
						local children = {}
						local newSpellPanels = {}

						for i,ability in ipairs(spellAbilities) do

							local panel = spellPanels[i] or gui.Panel{
								classes = {"statsRow", "spellTable"},

								linger = function(element)
									local tooltip = CreateAbilityTooltip(spellAbilities[i], {token = CharacterSheet.instance.data.info.token})
									tooltip.selfStyle.halign = "center"
									tooltip.selfStyle.valign = "top"
									element.tooltip = tooltip
								end,

								gui.Panel{
									classes = {"statsLabel", "abilityIcon", "tableData", "spellTable"},
									gui.Panel{
										classes = {"abilityIconBackground"},
										gui.Panel{
											classes = {"abilityIconIcon"},
											refreshToken = function(element, info)
												element.bgimage = spellAbilities[i].iconid
											end,
										},
										gui.PrettyBorder{ width = 9 },
									},
								},
								gui.Label{
									classes = {"statsLabel", "abilityName", "tableData", "spellTable"},
								},
								gui.Label{
									classes = {"statsLabel", "abilityRange", "tableData", "spellTable"},
								},
								gui.Label{
									classes = {"statsLabel", "abilitySave", "tableData", "spellTable"},
								},
								gui.Label{
									classes = {"statsLabel", "abilityEffect", "tableData", "spellTable"},
								},

								--this panel is blank for spells. Spells can be edited elsewhere.
								gui.Panel{
									classes = {"statsLabel", "abilityEdit", "tableData"},
								},
							}

							local dataItems = panel.children
							dataItems[2].text = ability.name
							dataItems[3].text = ability:DescribeAOE()

							local dctext = "--"
							for _,behavior in ipairs(ability.behaviors) do
								if behavior:has_key("dc") then
									dctext = string.format("%s%d", string.upper(concatdc(behavior.dc)), ability:SaveDC(CharacterSheet.instance.data.info.token))
								end
							end

							dataItems[4].text = dctext

							dataItems[5].text = ability:SummarizeBehavior(creatureLookup)

							newSpellPanels[i] = panel
							children[#children+1] = panel
						end

						spellPanels = newSpellPanels
						element.children = children
					end,
				},
			},
				
		}
	}
end


function CharSheet.CharacterFeaturesPanel()

	local triangleStyles = {
		gui.Style{
			classes = {'triangle'},
			rotate = 90,
			height = 12,
			width = 12,
			halign = "right",
			valign = "center",
			hmargin = 8,
			bgimage = "panels/triangle.png",
			bgcolor = "white",
		},
		gui.Style{
			classes = {'triangle', 'expanded'},
			rotate = 0,
			transitionTime = 0.2,
		},
	}

	local featurePanels = {}

	local resultPanel = gui.Panel{
		width = 520,
		height = 'auto',
		flow = 'vertical',
		halign = 'left',
		refreshToken = function(element, info)
			local creature = info.token.properties
			if creature.typeName ~= "character" then
				element.children = {}
				element:SetClass("collapsed", true)
				featurePanels = {}
				return
			end

			element:SetClass("collapsed", false)

			local children = {}

			local newFeaturePanels = {}

			local features = creature:GetClassFeaturesAndChoicesWithDetails()

			for i,featureInfo in ipairs(features) do


				local levelStr = ''
				if featureInfo.levels ~= nil then
					levelStr = string.format(", level %d", math.max(1, featureInfo.levels[1]))
				end

				if featureInfo.levels ~= nil and #featureInfo.levels > 1 then
					levelStr = string.format("%s upgraded at level%s %d", levelStr, cond(#featureInfo.levels > 2, 's', ''), featureInfo.levels[2])
					if #featureInfo.levels > 2 then
						for i=3,#featureInfo.levels do
							levelStr = string.format("%s, %d", levelStr, featureInfo.levels[i])
						end
					end
				end

				local key = string.format("%d-%s-%s", i, featureInfo.feature.guid, levelStr)

				local featurePanel = featurePanels[key]

				if featurePanel == nil then

					local tri = gui.Panel{
						classes = {"triangle"},
						styles = triangleStyles,
					}

					local bodyChildren = {}

					bodyChildren[#bodyChildren+1] = gui.Label{
						width = '100%',
						height = 'auto',
						fontSize = 12,
						textWrap = true,
						refreshToken = function(element, info)
							element.text = featurePanel.data.featureInfo.feature:GetDescription()
						end,
					}

					local numChoices = featureInfo.feature:NumChoices(creature)
					for i=1,numChoices do

						local dropdown = gui.Dropdown{
							fontSize = 18,
							height = 26,
							width = 240,
                            centerPopup = true,
                            menuWidth = 616,
                            menuHeight = 920,
							textDefault = "Choose...",
							sort = true,
							data = {
								featureInfo = featureInfo,
							},
							refreshToken = function(element, info)
								local creature = info.token.properties
								local choices = element.data.featureInfo.feature:Choices(i, creature:GetLevelChoices()[element.data.featureInfo.feature.guid] or {}, creature)
								
								if choices ~= nil and #choices > 0 then
									local idChosen = (creature:GetLevelChoices()[element.data.featureInfo.feature.guid] or {})[i] or 'none'
									element.options = choices
									element.idChosen = idChosen
									element:SetClass("hidden", false)
								else
									element:SetClass("hidden", true)
								end
							end,

							change = function(element)
								local choice = element.idChosen
								if choice == 'none' then
									choice = nil
								end

								local choices = creature:GetLevelChoices()
								if choices[element.data.featureInfo.feature.guid] == nil then
									choices[element.data.featureInfo.feature.guid] = {}
								end
								choices[element.data.featureInfo.feature.guid][i] = choice
								CharacterSheet.instance:FireEvent('refreshAll')
							end,
						}

						bodyChildren[#bodyChildren+1] = dropdown
					end

					local body = gui.Panel{
						width = '100%',
						height = 'auto',
						flow = 'vertical',
						classes = {"collapsed-anim"},

						children = bodyChildren,
					}
					
					local header = gui.Panel{
						classes = {"featureHeader"},
						halign = "left",
						width = "90%",
						height = "auto",
						flow = "horizontal",
						bgimage = "panels/square.png",
						press = function(element)
							body:SetClass('collapsed-anim', tri:HasClass('expanded'))
							tri:SetClass('expanded', not tri:HasClass('expanded'))
						end,
						styles = {
							{
								selectors = {"featureHeader"},
								bgcolor = 'black',
							},
							{
								selectors = {"featureHeader","hover"},
								bgcolor = '#770000ff',
							},
						},


						gui.Panel{
							width = "80%",
							height = "auto",
							flow = "vertical",
							halign = "left",

							gui.Label{
								width = "90%",
								height = "auto",
								fontSize = 12,
								bold = true,
								refreshToken = function(element, info)
									element.text = string.format("%s", featurePanel.data.featureInfo.feature:Describe())
								end,
							},
							gui.Label{
								width = "90%",
								height = "auto",
								fontSize = 12,
								italics = true,
								refreshToken = function(element, info)
									local featureInfo = featurePanel.data.featureInfo
									element.text = string.format("%s%s", (featureInfo.class or featureInfo.race or featureInfo.background or {name = ""}).name, levelStr)
								end,
							},
						},

						tri,
					}

					featurePanel = gui.Panel{
						styles = {
							{
								hmargin = 0,
							}
						},
						data = {
						},
						hmargin = 8,
						vmargin = 2,
						width = '100%',
						height = 'auto',
						flow = "vertical",
						header,body,
					}
				end

				featurePanel.data.featureInfo = featureInfo

				children[#children+1] = featurePanel
				newFeaturePanels[key] = featurePanel

			end

			featurePanels = newFeaturePanels

			element.children = children
		end
	}

	return resultPanel
end

function CharSheet.FeaturesPanel()
	return gui.Panel{
		classes = {"featuresScrollPanel"},
		vscroll = true,
		gui.Panel{
			 classes = {"featuresPanel"},
			 flow = "vertical",

			 CharSheet.CharacterFeaturesPanel(),

			 
			 --list of additional/custom features.
			gui.Panel{
				height = "auto",
				halign = "center",
				width = "100%-16",

				data = {
					properties = nil,
				},

				refreshToken = function(element, info)
					if info.token.properties ~= element.data.properties then
						element.children = { CharacterFeature.ListEditor(info.token.properties, 'characterFeatures', { dialog = CharacterSheet.instance, notify = CharacterSheet.instance }) }
						element.data.properties = info.token.properties
					end
				end,
			},

			--creature templates.
			gui.Panel{
				height = "auto",
				halign = "center",
				width = "100%-16",
				flow = "vertical",

				gui.Panel{
					width = "100%",
					height = "auto",
					flow = "vertical",
					data = {
						children = {},
					},
					refreshToken = function(element, info)
						local templates = info.token.properties:try_get("creatureTemplates")
						if templates == nil or #templates <= #element.data.children then
							return
						end


						while #templates > #element.data.children do
							local label = gui.Label{
								classes = {"statsLabel"},
								width = "80%",
								height = "auto",
							}
							local n = #element.data.children+1
							element.data.children[n] = gui.Panel{
								width = "100%",
								height = "auto",
								flow = "horizontal",
								refreshToken = function(element, info)
									local templates = info.token.properties:try_get("creatureTemplates")
									if templates == nil or #templates < n then
										element:SetClass("collapsed", true)
										return
									end

									local templatesTable = dmhub.GetTable("creatureTemplates")
									local templateInfo = templatesTable[templates[n]]
									if templateInfo == nil then
										element:SetClass("collapsed", true)
										return
									end

									element:SetClass("collapsed", false)
									if templateInfo.description ~= '' then
										label.text = string.format("%s--%s", templateInfo.name, templateInfo.description)
									else
										label.text = templateInfo.name
									end
								end,

								label,
								gui.DeleteItemButton{
									width = 24,
									height = 24,
									halign = "right",
									click = function(element)
										local creature = CharacterSheet.instance.data.info.token.properties
										creature:RemoveTemplate(n)
										CharacterSheet.instance:FireEvent("refreshAll")
									end,
								},
							}
						end

						element.children = element.data.children

					end,
				},

				gui.Dropdown{
					monitorAssets = true,
					width = 200,
					height = 30,
					vmargin = 4,
					idChosen = "none",

					create = function(element)
						element:FireEvent("refreshAssets")
					end,

					refreshAssets = function(element)
						local choices = {
							{
								id = "none",
								text = "Add Creature Template...",
							},
						}

						local templateTable = dmhub.GetTable("creatureTemplates") or {}
						for k,entry in pairs(templateTable) do
							if not entry:try_get("hidden", false) then
								choices[#choices+1] = {
									id = k,
									text = entry.name,
								}
							end
						end

						element.options = choices
					end,

					change = function(element)
						local creature = CharacterSheet.instance.data.info.token.properties
						if element.idChosen ~= "none" then
							creature:AddTemplate(element.idChosen)
						end
						element.idChosen = "none"
						CharacterSheet.instance:FireEvent('refreshAll')
					end,

				},
			},


			--feats.
			gui.Panel{
				height = "auto",
				halign = "center",
				width = "100%-16",
				flow = "vertical",

				refreshToken = function(element, info)
					if info.token.properties:IsMonster() then
						element:SetClass("collapsed", true)
						return
					end

					element:SetClass("collapsed", false)
				end,

				gui.Panel{
					width = "100%",
					height = "auto",
					flow = "vertical",
					data = {
						children = {},
					},
					refreshToken = function(element, info)
						local feats = info.token.properties:try_get("creatureFeats")
						if feats == nil or #feats <= #element.data.children then
							return
						end


						while #feats > #element.data.children do
							local label = gui.Label{
								classes = {"statsLabel"},
								width = "80%",
								height = "auto",
							}
							local n = #element.data.children+1
							element.data.children[n] = gui.Panel{
								width = "100%",
								height = "auto",
								flow = "horizontal",
								refreshToken = function(element, info)
									local feats = info.token.properties:try_get("creatureFeats")
									if feats == nil or #feats < n then
										element:SetClass("collapsed", true)
										return
									end

									local featsTable = dmhub.GetTable(CharacterFeat.tableName)
									local featInfo = featsTable[feats[n]]
									if featInfo == nil then
										element:SetClass("collapsed", true)
										return
									end

									element:SetClass("collapsed", false)
									if featInfo.description ~= '' then
										label.text = string.format("%s", featInfo.name)
									else
										label.text = featInfo.name
									end
								end,

								label,
								gui.DeleteItemButton{
									width = 24,
									height = 24,
									halign = "right",
									click = function(element)
										local creature = CharacterSheet.instance.data.info.token.properties
										creature:RemoveFeat(n)
										CharacterSheet.instance:FireEvent("refreshAll")
									end,
								},
							}
						end

						element.children = element.data.children

					end,
				},

				gui.Dropdown{
					monitorAssets = true,
					width = 200,
					height = 30,
					vmargin = 4,
					idChosen = "none",
					hasSearch = true,

					create = function(element)
						element:FireEvent("refreshAssets")
					end,

					refreshAssets = function(element)
						local choices = {
							{
								id = "none",
								text = "Add Feat...",
							},
						}

						local featTable = dmhub.GetTable(CharacterFeat.tableName) or {}
						for k,entry in pairs(featTable) do
							if not entry:try_get("hidden", false) then
								choices[#choices+1] = {
									id = k,
									text = entry.name,
								}
							end
						end

						table.sort(choices, function(a,b) return a.text < b.text end)

						element.options = choices
					end,

					change = function(element)
						local creature = CharacterSheet.instance.data.info.token.properties
						if element.idChosen ~= "none" then
							creature:AddFeat(element.idChosen)
						end
						element.idChosen = "none"
						CharacterSheet.instance:FireEvent('refreshAll')
					end,

				},
			},


		}
	}
end

function CharSheet.FeaturesNotesPanel()
	local GetNotes = function(creature)
		if creature:has_key("notes") then
			return creature.notes
		end

		if creature:IsMonster() then
			return {
				{
					title = "Monster Notes",
					text = "",
				}
			}
		else
			return {
				{
					title = "Backstory",
					text = "",
				}
			}
		end
	end

	local EnsureNotes = function(creature)
		if not creature:has_key("notes") then
			creature.notes = GetNotes(creature)
		end
		return creature.notes
	end

	local CreateNotesSection = function(i, params)

		local resultPanel

		local args = {
			width = "95%",
			height = "auto",
			flow = "vertical",
			halign = "center",

			gui.Panel{
				flow = "horizontal",
				width = "100%",
				height = "auto",
				vmargin = 4,
				gui.Input{
					fontSize = 14,
					multiline = false,
					width = "60%",
					height = 22,
					color = "#d4d1ba",
					blockChangesWhenEditing = true,
					placeholderText = "Enter section title...",
					refreshToken = function(element, info)
						local notes = GetNotes(info.token.properties)
						if i <= #notes then
							element.text = notes[i].title
						end
					end,

					editlag = 1,
					edit = function(element)
						element:FireEvent("change")
					end,
					change = function(element)
						local notes = EnsureNotes(CharacterSheet.instance.data.info.token.properties)
						if i <= #notes and notes[i].title ~= element.text then
							notes[i].title = element.text
							CharacterSheet.instance.data.info.token.properties.notesRevision = dmhub.GenerateGuid()
						end
					end,
				},
				gui.DeleteItemButton{
					width = 24,
					height = 24,
					halign = "right",
					click = function(element)
						resultPanel:FireEvent("delete")
					end,
				},
			},

			 gui.Input{
				width = "98%",
				valign = "top",
				vmargin = 4,
				halign = "center",
				height = "auto",
				multiline = true,
				minHeight = 100,
				textAlignment = "topleft",
				fontSize = 14,
				color = "#d4d1ba",
				blockChangesWhenEditing = true,

				placeholderText = "Enter notes...",

				refreshToken = function(element, info)
					local notes = GetNotes(info.token.properties)
					if i <= #notes then
						element.text = notes[i].text
					end
				end,

				--note when this is edited and make sure that when the sheet is closed we sync
				--any changes to the cloud.
				data = {
					edits = false
				},

				edit = function(element)
					element.data.edits = true
				end,

				restoreOriginalTextOnEscape = false,

				closeCharacterSheet = function(element)
					if element.data.edits then
						element:FireEvent("change")
					end
				end,

				change = function(element)
					element.data.edits = false
					local notes = EnsureNotes(CharacterSheet.instance.data.info.token.properties)
					if i <= #notes and notes[i].text ~= element.text then
						notes[i].text = element.text
						CharacterSheet.instance.data.info.token.properties.notesRevision = dmhub.GenerateGuid()
					end
				end,
			 },

		}

		for k,p in pairs(params) do
			args[k] = p
		end

		resultPanel = gui.Panel(args)
		return resultPanel
	end

	local addNotesButton = gui.AddButton{
		hmargin = 15,
		halign = "right",
		linger = function(element)
			gui.Tooltip("Add a new section")(element)
		end,
		click = function(element)
			local notes = EnsureNotes(CharacterSheet.instance.data.info.token.properties)
			notes[#notes+1] = {
				title = "",
				text = "",
			}
			CharacterSheet.instance:FireEvent("refreshAll")
		end,
	}

	local sectionPanels = {}

	return gui.Panel{
		classes = {"featuresScrollPanel"},
		vscroll = true,
		gui.Panel{
			 classes = {"featuresPanel"},

			 flow = "vertical",

			 addNotesButton,

			 refreshToken = function(element, info)
				local notes = GetNotes(info.token.properties)
				local children = {}
				local newSectionPanels = {}

				for i,note in ipairs(notes) do
					local child = sectionPanels[i] or CreateNotesSection(i, {
						delete = function(element)
							local notes = EnsureNotes(CharacterSheet.instance.data.info.token.properties)
							if i <= #notes then
								table.remove(notes, i)
								CharacterSheet.instance:FireEvent("refreshAll")
							end
						end,
					})

					newSectionPanels[i] = child
					children[#children+1] = child
				end

				sectionPanels = newSectionPanels

				children[#children+1] = addNotesButton

				element.children = children
			 end,
		}
	}
end

function CharSheet.ActionsAndFeaturesPanel()
	local resultPanel

	local indexSelected = 1

	local tabPanels = {
		CharSheet.ActionsPanel(),
		CharSheet.FeaturesPanel(),
		CharSheet.FeaturesNotesPanel(),
	}

	for i,tabPanel in ipairs(tabPanels) do
		tabPanel:SetClass("collapsed", i ~= 1)
	end

	local tabPress = function(element)
		if element:HasClass("selected") then
			return
		end
		for i,tab in ipairs(element.parent.children) do
			if tab:HasClass("tab") then
				tab:SetClass("selected", tab == element)
				tabPanels[i]:SetClass("collapsed", tab ~= element)
				if tab == element then
					indexSelected = i
				end
			end
		end
	end

	resultPanel = gui.Panel{
		classes = { "statsPanel" },
		styles = ActionsAndFeaturesStyles,
		gui.Panel{
			classes = { "statsInnerPanel" },
			width = "100%",
			valign = "top",

			gui.Panel{
				classes = { "statsHeader" },
				valign = "top",

				gui.Label{
					classes = {"tab", "selected"},
					text = "ACTIONS",
					press = tabPress,
					gui.Panel{classes = {"tabBorder"}},
				},
				gui.Label{
					classes = {"tab"},
					text = "FEATURES",
					press = tabPress,
					gui.Panel{classes = {"tabBorder"}},
				},
				gui.Label{
					classes = {"tab"},
					text = "NOTES",
					press = tabPress,
					gui.Panel{classes = {"tabBorder"}},
				},
			},

			tabPanels[1],
			tabPanels[2],
			tabPanels[3],

		},

	}

	return resultPanel
end

function CharSheet.MainSheet()

	local avatarPanel = gui.Panel{
		classes = {"characterSheetPanel", "leftAreaPanel"},
		id = "avatarPanel",

		CreatePanelFooter{
			text = "",
		},

		CharSheet.CharacterSheetAvatarPanel(),
	}

	local conditionsPanel = gui.Panel{
		classes = {"characterSheetPanel", "leftAreaPanel"},
		id = "conditionsPanel",
		CreatePanelFooter{
			text = "CONDITIONS",
			settings = function(element)
				CharSheet.CharacterSheetEditConditions(element, CharacterSheet.instance.data.info)
			end,
		},
		CharSheet.CharacterSheetConditions(),
	}

	local defensesPanel = gui.Panel{
		id = "defensesPanel",
		classes = {"characterSheetPanel", "leftAreaPanel"},
		CreatePanelFooter{
			text = "DEFENSES",
			settings = function(element)
				CharSheet.CharacterSheetEditResistancesPopup(element, CharacterSheet.instance.data.info)
			end,
		},
		CharSheet.CharacterSheetDefensesPanel(),
	}

	local proficienciesPanel = gui.Panel{
		id = "proficienciesPanel",
		classes = {"characterSheetPanel", "leftAreaPanel"},
		CreatePanelFooter{
			text = "PROFICIENCIES AND LANGUAGES",
			settings = function(element)
				CharSheet.CharacterSheetEditLanguagesPopup(element, CharacterSheet.instance.data.info)
			end,
		},
		CharSheet.CharacterSheetProficiencesAndLanguagesPanel(),
	}

	local leftArea = gui.Panel{
		id = "leftArea",

		avatarPanel,
		conditionsPanel,
		defensesPanel,
		proficienciesPanel,
	}




	local topPanel = gui.Panel{
		id = "topPanel",
		classes = {"characterSheetPanel", "charactersheet"},

		data = {
			attributesPanels = {},
		},

		refreshToken = function(element, info)
			if #element.data.attributesPanels == 0 then
				local children = {}

				for i,attrid in ipairs(creature.attributeIds) do
					local attrPanel = CharSheet.AttrPanel(attrid)
					children[#children+1] = attrPanel
				end

				local initiativePanel = CharSheet.InitiativePanel()
				children[#children+1] = initiativePanel

				local challengeRatingPanel = CharSheet.ChallengeRatingPanel()
				children[#children+1] = challengeRatingPanel

				children[#children+1] = CharSheet.ProficiencyBonusPanel()

				local inspirationPanel = CharSheet.InspirationPanel()
				children[#children+1] = inspirationPanel

				--local characterBuilderPanel = CharSheet.CharacterBuilderAccessPanel()
				--children[#children+1] = characterBuilderPanel

				element.data.attributesPanels = children

				element.children = children
			end

			local character = info.token.properties

		end,
	}

	local skillsPanel = gui.Panel{
		id = "skillsPanel",
		classes = {"characterSheetPanel"},
		CreatePanelFooter{
			text = "SKILLS",
		},
		CharSheet.CharacterSheetSkillsPanel(),
	}

	local acSpeedPanel = gui.Panel{
		id = "acSpeedPanel",
		CharSheet.CharacterArmorClassPanel(),
		CharSheet.CharacterSpeedPanel(),
		classes = {"characterSheetPanel"},
	}

	local hitpointsPanel
	hitpointsPanel = gui.Panel{
		id = "hitpointsPanel",
		classes = {"characterSheetPanel"},
		CreatePanelFooter{
			valign = "bottom",
			text = GameSystem.HitpointsName,
			settings = function(element)
				if hitpointsPanel.popup ~= nil then
					hitpointsPanel.popup = nil
					return
				end

				local rootPanel = CharacterSheet.instance

				local creature = CharacterSheet.instance.data.info.token.properties

				local hitpointsTotalPanel
				local modificationsPanel = nil

				if creature.typeName == "character" then
					local modificationRows = {}

					modificationRows[#modificationRows+1] = gui.Panel{
						classes = {"formPanel"},
						gui.Label{
							classes = {"popupLabel"},
							text = "Base Hitpoints:",
						},
						gui.Label{
							classes = {"popupValue"},
							text = tostring(creature:BaseHitpoints()),
						}
					}

					modificationRows[#modificationRows+1] = gui.Panel{
						classes = {"formPanel"},
						gui.Label{
							classes = {"popupLabel"},
							text = "Override:",
						},
						gui.Label{
							editable = true,
							classes = {"popupValue"},
							text = cond(creature.override_hitpoints, creature.max_hitpoints, "--"),
							change = function(element)
								local n = tonumber(element.text)
								if n == nil then
									element.text = "--"
									creature.override_hitpoints = false
								else
									creature.max_hitpoints = n
									creature.override_hitpoints = true
								end
								rootPanel:FireEvent('refreshAll')
								hitpointsTotalPanel:FireEvent("create")
							end,
						}
					}


					local modifications = creature:DescribeModifications("hitpoints", creature:BaseHitpoints())
					if modifications ~= nil and #modifications > 0 then
						for _,mod in ipairs(modifications) do
							modificationRows[#modificationRows+1] = gui.Panel{
								classes = {"formPanel"},
								gui.Label{
									classes = {"popupLabel"},
									text = mod.key,
								},
								gui.Label{
									classes = {"popupValue"},
									text = mod.value,
								},
							}
						end
					end

					modificationsPanel = gui.Panel{
						width = "auto",
						height = "auto",
						flow = "vertical",
						children = modificationRows,
					}

				end


				hitpointsTotalPanel = gui.Label{
					classes = {"popupValue", "editable"},
					fontSize = "200%",
					textAlignment = "center",
					halign = "center",
					editable = creature:IsMonster(),
					create = function(element)
						element.text = creature:try_get("max_hitpoints_roll", tostring(creature:MaxHitpoints()))
						if element.text == "" then
							element.text = "(none)"
						end
					end,
					change = function(element)
						if element.text == "" then
							element.text = creature:try_get("max_hitpoints_roll", tostring(creature:MaxHitpoints()))
							return
						end

						if creature:has_key("max_hitpoints_roll") then
							if element.text ~= creature.max_hitpoints_roll then
								creature.max_hitpoints_roll = element.text
								creature:RerollHitpoints()
							end
						else
							creature:SetMaxHitpoints(element.text)
						end
						rootPanel:FireEvent('refreshAll')
					end,
				}


				hitpointsPanel.popupPositioning = 'panel'
				hitpointsPanel.popup = gui.TooltipFrame(
					gui.Panel{
						halign = "center",
						valign = "bottom",
						width = 400,
						height = "auto",
						pad = 12,
						styles = {
							Styles.Default,
							PopupStyles,
						},

						gui.Label{
							text = "Max Hitpoints",
							classes = {"popupLabel"},
							textAlignment = "center",
							fontSize = "200%",
							halign = "center",
						},

						modificationsPanel,
						hitpointsTotalPanel,


					}, {
						interactable = true
					}
				)
				
			end,
		},
		CharSheet.CharacterHitpointsPanel(),
	}

	local savingThrowsPanel = gui.Panel{
		id = "savingThrowsPanel",
		classes = {"characterSheetPanel"},
		CreatePanelFooter{
			text = GameSystem.SavingThrowNamePlural,
		},
		CharSheet.CharacterSheetSavingThrowPanel(),
	}

	local passiveSensesPanel = gui.Panel{
		id = "passiveSensesPanel",
		classes = {"characterSheetPanel"},
		CreatePanelFooter{
			text = "PASSIVE SENSES",
			settings = function(element)
				CharSheet.CharacterSheetEditPassiveSensesPopup(element, CharacterSheet.instance.data.info)
			end,
		},
		CharSheet.CharacterSheetPassiveSensesPanel(),
	}

	local resourcesPanel = gui.Panel{
		id = "resourcesPanel",
		classes = {"characterSheetPanel"},
		CreatePanelFooter{
			text = "RESOURCES",
		},
		CharSheet.CharacterSheetResourcesPanel(),
	}

	local bottomRightArea = gui.Panel{
		id = "bottomRightArea",
		classes = {"charactersheet"},

		gui.Panel{
			id = "savingsThrowsAndResourcesArea",
			savingThrowsPanel,
			passiveSensesPanel,
			resourcesPanel,
		},
		skillsPanel,

		gui.Panel{
			id = "bottomRightStatsArea",
			gui.Panel{
				id = "acSpeedHitpointsArea",
				acSpeedPanel,
				hitpointsPanel,
			},
			gui.Panel{
				id = "featuresPanel",
				classes = {"characterSheetPanel"},
				CharSheet.ActionsAndFeaturesPanel(),
			},
		},

	}


	local rightArea = gui.Panel{
		width = "100%-300",
		height = "100%",
		flow = "vertical",
		hmargin = 0,
		vmargin = 0,
		halign = "right",
		hpad = 0,
		vpad = 0,
		topPanel,
		bottomRightArea,
	}

	return gui.Panel{
		width = "100%",
		height = "100%",
		flow = "horizontal",

		leftArea,
		rightArea,
	}
end

--[[
CharSheet.RegisterTab{
	id = "CharacterSheet",
	text = "CharacterOld",
	panel = CharSheet.MainSheet,
}
]]

CharSheet.defaultSheet = "CharacterSheet"

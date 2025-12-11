local mod = dmhub.GetModLoading()

--our master reference of characterFeatures
--a list of { class/race/background = Class/Race/Background, levels = {list of ints}, feature = CharacterFeature or CharacterChoice }
local g_characterFeatures

--a dict of choiceid -> feat this choice was made for. This is useful to block unique choices.
local g_choicesMade

local g_levelChoices

local g_creature

	
CharSheet.DiceStyles = {
				{
					selectors = {"dice"},
					width = 32,
					height = 32,
					halign = "center",
					bgimage = "ui-icons/d20.png",
					bgcolor = Styles.textColor,
					vmargin = 8,
				},
				{
					selectors = {"dice", "rolled"},
					bgimage = "ui-icons/icon-rotate.png",

				},
				{
					selectors = {"diceAttrLabel", "~used"},
					collapsed = 1,
				},
				{
					selectors = {"dice", "used"},
					collapsed = 1,
				},
				{
					selectors = {"dice", "hover"},
					transitionTime = 0.1,
					brightness = 4,
				},
				{
					selectors = {"dice", "press"},
					transitionTime = 0.1,
					inversion = 1,
				},
				{
					selectors = {"newvalue"},
					color = "white",
					scale = 2.5,
					transitionTime = 0.5,
				}
			}



local BuilderStyles = {
	{
		selectors = {"#builderPanel"},
		width = "100%",
		height = "100%",
		flow = "horizontal",
	},

	{
		selectors = {"dropdown"},
		width = 340,
		height = 30,
		fontSize = 20,
		vmargin = 4,
	},

	{
		selectors = {"label"},
		width = "auto",
		height = "auto",
	},

	{
		selectors = {"sheetLabel"},
		color = Styles.textColor,
	},

	{
		selectors = {"mainHeading"},
		fontSize = 36,
		fontFace = "crimsontext",
		bold = false,
	},

	{
		selectors = {"featureTitle"},
		fontSize = 26,
		bold = false,
		priority = 2,
	},

	{
		selectors = {"featureDescription"},
		fontSize = 16,
		bold = false,
		priority = 2,
		vmargin = 4,
	},

	{
		selectors = {"baseAttributeLabel"},
		valign = "center",
		halign = "center",
		fontSize = 38,
		bold = true,
		width = 60,
		height = 60,
		textAlignment = "center",
	},

	{
		selectors = {"baseAttributeLabel", "used"},
		opacity = 0.4,
	},

	{
		selectors = {"attributeModifierPanel"},
		bgimage = "panels/square.png",
		bgcolor = "clear",
		cornerRadius = 8,
		borderWidth = 2,
		height = 70,
	},
	{
		selectors = {"attributeModifierPanel", "used"},
		brightness = 0.4,
	},
	{
		selectors = {"attributeModifierPanel", "drag-target"},
		transitionTime = 0.2,
		brightness = 1.5,
	},
	{
		selectors = {"attributeModifierPanel", "drag-target-hover"},
		transitionTime = 0.2,
		borderColor = "white",
		brightness = 3,
	},
	{
		selectors = {"formPanel"},
		flow = "horizontal",
		height = "auto",
		vmargin = 4,
	},
	{
		selectors = {"formLabel"},
		textAlignment = "left",
		fontSize = 24,
		minWidth = 140,
		hmargin = 8,
		flow = "horizontal",
		height = "auto",
		color = Styles.textColor,
	},
	{
		selectors = {"input"},
		borderColor = "black",
	},
	{
		selectors = {"smallNumberInput"},
		priority = 100,
		width = 50,
		fontSize = 18,
		bold = false,
		bgcolor = "#00000000",
		borderColor = Styles.textColor,
		color = Styles.textColor,
		borderWidth = 2,
		borderFade = false,
		valign = "center",
	},
	{
		selectors = {"notesInput"},
		priority = 100,
		width = 400,
		minHeight = 80,
		bold = false,
		height = "auto",
		textAlignment = "topleft",
		bgcolor = "#00000000",
		borderWidth = 2,
		borderColor = Styles.textColor,
		color = Styles.textColor,
		borderFade = false,
		halign = "left",
	},
	{
		selectors = {"dieIcon"},
		width = 24,
		height = 24,
		bgcolor = "black",
	},
	{
		selectors = {"dieIcon","hover"},
		bgcolor = "#770000ff",
		scale = 1.4,
		transitionTime = 0.2,
	},
	{
		selectors = {"dieIcon","press"},
		bgcolor = "#330000ff",
	},
	{
		selectors = {"label", "invalid"},
		color = "#bb0000",
		italics = true,
		fontSize = 20,
	},
}

gui.RegisterTheme("charsheet", "Builder", BuilderStyles)

function CharSheet.BuilderBanner(options)

	local calculateText = options.calculateText
	options.calculateText = nil


	local resultPanel
	resultPanel = gui.Panel{
		width = "100%",
		height = "100%",
		flow = "none",
		data = {
			text = options.text,
			tab = nil,
		},

		refreshBuilder = function(element)
			resultPanel.data.alertIcon:SetClass("hidden", true)

			if calculateText ~= nil then
				calculateText(resultPanel.data.tab)
			else
				resultPanel.data.tab.text = element.data.text
			end

		end,

		showAlert = function(element)
			resultPanel.data.alertIcon:SetClass("hidden", false)
		end,

		options.content,
	}

	return resultPanel
end

function CharacterFeatureChoice:HasCustomDropdownPanel()
    return self.description ~= ""
end

function CharacterFeatureChoice:CreateDropdownPanel(name)
    return gui.Label{
        styles = {
            {
                color = Styles.textColor,
                bgcolor = Styles.backgroundColor,
            },
            {
                selectors = {"hover"},
                bgcolor = Styles.textColor,
                color = Styles.backgroundColor,
            },
        },
        text = string.format("<b>%s</b> -- %s", name, self.description),
        width = 540,
        halign = "center",
        height = "auto",
        fontSize = 14,
        bgimage = true,
        vpad = 4,
    }
end

function CharacterFeature:CreateDropdownPanel(name)
    for _,modifier in ipairs(self:try_get("modifiers", {})) do
        if modifier.behavior == "activated" and (modifier.activatedAbility.categorization == "Signature Ability" or modifier.activatedAbility.categorization == "Heroic Ability") then
            local ability = modifier.activatedAbility
            return ability:Render({selectable = true, hmargin = 4, vmargin = 8, width = 600}, {})
        end
    end

    return gui.Label{
        styles = {
            {
                color = Styles.textColor,
                bgcolor = Styles.backgroundColor,
            },
            {
                selectors = {"hover"},
                bgcolor = Styles.textColor,
                color = Styles.backgroundColor,
            },
        },
        text = string.format("<b>%s</b> -- %s", name, self.description),
        width = 540,
        halign = "center",
        height = "auto",
        fontSize = 14,
        bgimage = true,
        vpad = 4,
        hover = function(element)
            local tooltipPanel = nil
            for _,modifier in ipairs(self:try_get("modifiers", {})) do
                if modifier.behavior == "activated" then
                    local ability = modifier.activatedAbility
                    if ability ~= nil then
                        tooltipPanel = ability:Render({selectable = true, hmargin = 4, vmargin = 8, width = 600}, {})
                        break
                    end
                end

                tooltipPanel = modifier:CreateDropdownPanel(self)
                if tooltipPanel ~= nil then
                    break
                end
            end

            if tooltipPanel ~= nil then
                element.tooltip = gui.TooltipFrame(
                    tooltipPanel,
                    {
                        halign = "right",
                        valign = "center",
                    }
                )
            end
        end,
    }
end

function CharacterFeature:HasCustomDropdownPanel()

    for _,modifier in ipairs(self:try_get("modifiers", {})) do
        if modifier.behavior == "activated" then
            return true
		elseif modifier:HasDropdownPanel() then
			return true
        end
    end

    if self.description ~= "" then
        return true
    end

    return false
end

function CharSheet.FeaturePanel()
	local choiceDropdowns = {}
	local choiceErrors = {}
	local m_pointsLabel = nil

	local descriptionLabel = gui.Label{
		classes = {"featureDescription", "sheetLabel"},
		width = "100%",
		text = "",
		markdown = true,
	}

	local resultPanel
	resultPanel = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",

		descriptionLabel,

		data = {
			availableChoices = 0,
            abilityPanel = nil,
		},

		refreshFeature = function(element, featureInfo)
			local newChoiceDropdowns = {}
			local newChoiceErrors = {}
			local children = {descriptionLabel}

			local availableChoices = 0

            local hideDescription = false

            for _,modifier in ipairs(featureInfo.feature:try_get("modifiers", {})) do
                if modifier.behavior == "activated" or modifier.behavior == "triggerdisplay" or modifier.behavior == "routine" then
                    hideDescription = true
                    local ability = rawget(modifier, cond(modifier.behavior == "activated", "activatedAbility", "ability"))
                    if ability ~= nil then
                        if element.data.abilityPanel ~= nil and element.data.abilityPanelAbility == ability then
                            children[#children+1] = element.data.abilityPanel
                        else
                            element.data.abilityPanel = ability:Render({width = 600}, {
                            })

                            element.data.abilityPanelAbility = ability

                            children[#children+1] = element.data.abilityPanel
                        end
                        break
                    end
                end
            end

            if hideDescription then
                descriptionLabel:SetClass("collapsed", true)
            else
                element.data.abilityPanel = nil
                element.data.abilityPanelAbility = nil
                descriptionLabel:SetClass("collapsed", false)
			    descriptionLabel.text = featureInfo.feature:GetSummaryText()
            end

			local numChoices = featureInfo.feature:NumChoices(g_creature)
			local usePoints = featureInfo.feature:try_get("costsPoints", false)
			if usePoints then
				m_pointsLabel = m_pointsLabel or gui.Label{
					classes = {"featureDescription", "sheetLabel"},
				}
				m_pointsLabel.text = string.format("%d %s to spend", numChoices, featureInfo.feature:try_get("pointsName", "Points")),

				m_pointsLabel:SetClass("collapsed", false)
				children[#children+1] = m_pointsLabel
			elseif m_pointsLabel then
				m_pointsLabel:SetClass("collapsed", true)
				children[#children+1] = m_pointsLabel
			end

			for i=1,numChoices do

                local hasCustomPanels = false
				local choices = featureInfo.feature:Choices(i, g_levelChoices[featureInfo.feature.guid] or {}, g_creature)
				if choices ~= nil and #choices > 0 and choices[1].unique then
					local newChoices = {}
					for i,choice in ipairs(choices) do
						local choicesMade = g_choicesMade[choice.id]
						if choicesMade == nil or choicesMade[featureInfo.feature.guid] then
							newChoices[#newChoices+1] = choice
						end
					end

					choices = newChoices
					table.sort(choices, function(a,b) return a.text < b.text end)
				end

                if choices ~= nil then
                    for _,choice in ipairs(choices) do
                        if choice.hasCustomPanel then
                            hasCustomPanels = true
                            break
                        end
                    end
                end

                if choiceDropdowns[i] ~= nil and choiceDropdowns[i].data.hasCustomPanels ~= hasCustomPanels then
                    choiceDropdowns[i] = nil
                end

				local dropdown = choiceDropdowns[i] or gui.Dropdown{
                    data = {
                        hasCustomPanels = hasCustomPanels,
                    },
					textDefault = "Choose...",
                    centerPopup = hasCustomPanels,
                    width = 400,
                    menuWidth = cond(hasCustomPanels, 616),
                    menuHeight = cond(hasCustomPanels, 920),
					sort = true,
					change = function(element)
						local choice = element.idChosen
						if choice == 'none' then
							choice = nil
						end

						local choices = g_levelChoices
						if choices[featureInfo.feature.guid] == nil then
							choices[featureInfo.feature.guid] = {}
						end

						local choicesList = choices[featureInfo.feature.guid]
						if choice == nil and #choicesList > i then
							table.remove(choicesList, i)
						else
							choicesList[i] = choice
						end

						CharacterSheet.instance:FireEvent("refreshAll")
						CharacterSheet.instance:FireEventTree("refreshBuilder")
					end,
				}

				local failedPrerequisiteMessage = nil
								
				if choices ~= nil and #choices > 0 then
					local idChosen = (g_levelChoices[featureInfo.feature.guid] or {})[i] or 'none'
					if idChosen == 'none' then
						--now gets taken care of by textDefault
						--choices[#choices+1] = {
						--	id = 'none',
						--	text = 'Choose...',
						--}
					else
						for i,choice in ipairs(choices) do
							if choice.id == idChosen and choice.prerequisite ~= nil and (type(choice.prerequisite) ~= "string" or trim(choice.prerequisite) ~= "") then
								local pass = dmhub.EvalGoblinScriptDeterministic(choice.prerequisite, g_creature:LookupSymbol(), 0, string.format("Feat %s prerequisite", choice.text))
								if pass == 0 then
									if type(choice.prerequisite) == "string" then
										failedPrerequisiteMessage = "You do not meet the " .. choice.prerequisite .. " requirement for this feat."
									else
										--the prerequisite is given as a table or something else, so just give a generic message.
										failedPrerequisiteMessage = "You do not meet the requirement for this feat."
									end
								end
							end
						end

						choices[#choices+1] = {
							id = "none",
							text = "(Remove)",
						}
					end


					dropdown.options = choices
					dropdown.idChosen = idChosen
					dropdown:SetClass("hidden", false)

					if idChosen == "none" then
						availableChoices = availableChoices+1
					end
				else
					dropdown:SetClass("hidden", true)
				end

				newChoiceDropdowns[i] = dropdown
				children[#children+1] = dropdown

				if failedPrerequisiteMessage ~= nil then
					newChoiceErrors[i] = choiceErrors[i] or gui.Label{
						classes = {"invalid"},
					}

					newChoiceErrors[i].text = failedPrerequisiteMessage

					children[#children+1] = newChoiceErrors[i]
				else
					local feats = {}
					featureInfo.feature:FillFeats(g_levelChoices, feats)
					for _,feat in ipairs(feats) do
						if feat.description ~= "" then
							local label = gui.Label{
								classes = {"featureDescription"},
								text = feat.description,
							}

							children[#children+1] = label
						end
					end
				end
			end

			resultPanel.data.availableChoices = availableChoices

			choiceDropdowns = newChoiceDropdowns
			choiceErrors = newChoiceErrors
			element.children = children
		end,
	}

	return resultPanel
end

function CharSheet.FeatureDetailsPanel(params)

	local featurePanels = {}

	local resultPanel
	local args = {
		width = "100%",
		height = "auto",
		flow = "vertical",
		idprefix = "featureDetails",

		data = {
			hide = false,
			criteria = {},
		},

		refreshBuilder = function(element)
			if element.data.hide then
				featurePanels = {}
				element.children = {}
				return
			end

			local availableChoices = 0

			local newFeaturePanels = {}
			local children = {}
			local token = CharacterSheet.instance.data.info.token
			for i,featureInfo in ipairs(g_characterFeatures) do
				local exclude = false
                print("MATCH:: matching against criteria", element.data.criteria)
				for k,item in pairs(element.data.criteria) do
					if k == "minlevel" or k == "maxlevel" then
						local match = false
						for i,level in ipairs(featureInfo.levels or {}) do
							if (k == "minlevel" and level >= item) or (k == "maxlevel" and level <= item) then
								match = true
								break
							end 
						end

                        print("MATCH:: HAVE ", k, item, "levels =", featureInfo.levels or {}, "match =", match)

						if not match then
							exclude = "Level does not match for levels " .. json(featureInfo.levels or {})
							break
						end

					elseif type(item) == "table" and item.typeName == nil then
						local featureData = featureInfo[k]
						local found = false

						--this is e.g. a list of possible classes to include.
						for _,obj in ipairs(item) do
							if featureData ~= nil and obj ~= nil and obj.name == featureData.name then
								found = true
							end
						end

						if not found then
							exclude = "Class does not match"
							break
						end
					else
						local featureData = featureInfo[k]
						if featureData == nil or (item ~= "*" and item.name ~= featureData.name) then
							exclude = "Item name does not match"
							break
						end
					end
				end

				if not exclude then
					local key = string.format("%d-%s", i, featureInfo.feature.guid)
					local featurePanel = featurePanels[key]
					if featurePanel == nil then
						featurePanel = CharSheet.FeaturePanel()
					end

					featurePanel:FireEvent("refreshFeature", featureInfo)

					newFeaturePanels[key] = featurePanel
					children[#children+1] = featurePanel


					availableChoices = availableChoices + featurePanel.data.availableChoices
				end
			end

			featurePanels = newFeaturePanels
			element.children = children

			if availableChoices > 0 then
				element:FireEvent("alert", availableChoices)
			end
		end,
	}

	for k,p in pairs(params) do
		args[k] = p
	end

	resultPanel = gui.Panel(args)

	return resultPanel
end

function CharSheet.BuilderSettingsPanel()
	local banner

	local characteristicsPanel = CharSheet.BackgroundCharacteristicPanel{
		GetSelectedBackground = function()
			return g_creature:CharacterType()
		end,
	}

	local function GetComplicationOptions()
		local complicationOptions = {}
		local complicationsTable = dmhub.GetTable(CharacterComplication.tableName) or {}

		for k,complication in pairs(complicationsTable) do
			local passFilter = true
			if complication.prerequisite ~= nil and (trim(complication.prerequisite) ~= "") then
				passFilter = GoblinScriptTrue(dmhub.EvalGoblinScriptDeterministic(complication.prerequisite, g_creature:LookupSymbol(), 0, string.format("Complication %s prerequisite", complication.name)))
			end
			if passFilter then
				complicationOptions[#complicationOptions+1] = {
					id = k,
					text = complication.name,
					tooltip = function()
						return complication:Render{
							x = 8,
							halign = "right",
							width = 400,
							bgimage = true,
							bgcolor = Styles.backgroundColor,
							borderColor = Styles.textColor,
							borderWidth = 2,
							cornerRadius = 8,
						}

					end,
				}
			end
		end
		return complicationOptions
	end

    local complicationPanel
    complicationPanel = gui.Panel {
        vmargin = 32,
        halign = "center",
        width = "50%",
        height = "auto",
        flow = "vertical",
		pad = 5,

        gui.Panel{
            height = 40,
            classes = { "formPanel" },
            gui.Label {
                classes = { "formLabel" },
                text = "Complication:",
                valign = "center",
            },
			gui.Multiselect{
				options = GetComplicationOptions(),
				width = "auto",
				height = "auto",
				margin = 3,
				flow = "horizontal",
				sort = true,
				textDefault = "Add Complication...",

				dropdown = {
					classes = {"formDropdown"},
					width = 170,
				},

				chipPos = "right",
				chipPanel = {
					width = "100%-160",
					halign = "left",
				},
				chips = {
					halign = "left",
					valign = "center",
				},
				create = function(element)
					element:FireEvent("refreshAll")
				end,

				change = function(element)
					g_creature.complications = element.value
					CharacterSheet.instance:FireEvent("refreshAll")
					CharacterSheet.instance:FireEventTree("refreshBuilder")
				end,

				refreshAll = function(element)
					local selected = g_creature.complications or {}
					element:FireEvent("refreshSet", GetComplicationOptions(), selected)
				end,

				refreshBuilder = function(element)
					if not g_creature:IsHero() then
						complicationPanel:SetClass("collapsed", true)
						return
					end

					complicationPanel:SetClass("collapsed", false)
					local selected = g_creature.complications or {}
					element.value = selected
				end,
			},
        },

        gui.Panel{
            width = "100%",
            height = 650,
            flow = "vertical",
			vscroll = true,
            data = {
                complicationPanels = {},
            },
            refreshBuilder = function(element)
                local complications = g_creature.complications or {}

				local count = 0
				for _, _ in pairs(complications) do
					count = count + 1
				end
                if count == 0 then
                    element.children = {}
                    element.data.complicationPanels = {}
                    return
                end

                local complicationsTable = dmhub.GetTable(CharacterComplication.tableName) or {}
                local newPanels = {}
                local children = {}
                
                for complicationId, _ in pairs(complications) do
                    local panel = element.data.complicationPanels[complicationId]
                    if panel == nil then
                        local complication = complicationsTable[complicationId]
                        if complication ~= nil then
                            panel = complication:Render{}
                            newPanels[complicationId] = panel
                        end
                    else
                        newPanels[complicationId] = panel
                    end
                    
                    if panel ~= nil then
                        children[#children + 1] = panel
                    end
                end
                
                element.data.complicationPanels = newPanels
                element.children = children
            end,
        },
    }

	local content = gui.Panel{
		halign = "center",
		valign = "top",
		height = "auto",
		width = "90%",
		flow = "vertical",

		styles = {
			Styles.Form,
			{
				classes = {"label", "formLabel"},
				halign = "left",
				color = Styles.textColor,
				fontSize = 24,
			},
			{
				classes = {"input", "formInput"},
				fontSize = 24,
				textAlignment = "left",
			}
		},

		gui.Panel{
			width = 16,
			height = 16,
		},

		gui.Panel{
			flow = "vertical",
			height = "auto",
			width = "100%-100",
			halign = "center",

			gui.Label{
				classes = {"mainHeading"},
				halign = "center",
				text = "Character Settings",
			},

			gui.Panel{
				vmargin = 32,
                width = "auto",
				height = 40,
				halign = "center",
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					text = "Character Level:",
					valign = "center",
				},
				gui.Dropdown{
                    width = 180,
                    lmargin = 16,
                    options = {
                        { id = "first", text = "First Encounter",},
                        { id = "second", text = "Second Encounter",},
                        { id = "third", text = "Third Encounter",},
                        { id = "fourth", text = "Fourth Encounter",},
                        { id = 1, text = "Level 1",},
                        { id = 2, text = "Level 2",},
                        { id = 3, text = "Level 3",},
                        { id = 4, text = "Level 4",},
                        { id = 5, text = "Level 5",},
                        { id = 6, text = "Level 6",},
                        { id = 7, text = "Level 7",},
                        { id = 8, text = "Level 8",},
                        { id = 9, text = "Level 9",},
                        { id = 10, text = "Level 10",},
                    },
					refreshBuilder = function(element)
                        local level = g_creature:CharacterLevel()
                        if level == 1 then
                            local extra = g_creature:ExtraLevelInfo()
                            if type(extra.encounter) == "number" then
                                local mapping = {"first", "second", "third", "fourth"}
                                element.idChosen = mapping[extra.encounter] or 1
                            else
						        element.idChosen = 1
                            end
                        else
						    element.idChosen = g_creature:CharacterLevel()
                        end
					end,

					change = function(element)
                        local extra = g_creature:ExtraLevelInfo()
                        if type(element.idChosen) == "string" then
                            g_creature.levelOverride = 1
                            if element.idChosen == "first" then
                                extra.encounter = 1
                            elseif element.idChosen == "second" then
                                extra.encounter = 2
                            elseif element.idChosen == "third" then
                                extra.encounter = 3
                            else
                                extra.encounter = 4
                            end
                        else
                            extra.encounter = nil
                            g_creature.levelOverride = element.idChosen
                        end
                        g_creature.extraLevelInfo = extra

                        for _,classInfo in ipairs(g_creature:try_get("classes", {})) do
                            classInfo.level = g_creature.levelOverride
                        end

                        CharacterSheet.instance:FireEvent("refreshAll")
                        CharacterSheet.instance:FireEventTree("refreshBuilder")
					end,
				},
			},

			gui.Panel{
				width = "100%",
				height = "auto",
				flow = "horizontal",
				complicationPanel,
			},

			refreshBuilder = function(element)
			end,
		},

		gui.Panel{
			width = "100%",
			height = "auto",
			styles = CharSheet.carouselDescriptionStyles,
			characteristicsPanel,
		},
	}

	banner = CharSheet.BuilderBanner{
		text = "Character",
		content = content,
	}

	return banner
end

function CharSheet.BuilderAttributesPanel()

	local banner


	local m_pointsBuyInfo = nil

	local attributeGenerationTable = dmhub.GetTable(AttributeGenerator.tableName)

	local attributeGenerationOptions = {}

	for k,v in pairs(attributeGenerationTable) do
		if v.hiddenFromPlayers == false or dmhub.isDM then
			attributeGenerationOptions[#attributeGenerationOptions+1] = {
				id = k,
				text = v.name,
				ord = v.ord,
			}
		end
	end

	local GetGenerationMethodId = function()
		local gen = g_creature:try_get("attributeGeneration")
		if gen ~= nil then
			return gen.methodid
		else
			if attributeGenerationOptions == nil or #attributeGenerationOptions == 0 then
				return nil
			end
			return attributeGenerationOptions[1].id
		end
	end

	local GetGenerationMethodInfo = function()
		return attributeGenerationTable[GetGenerationMethodId()]
	end


	local m_baseAttrPanelsById = {}
	local m_attrPanelsById = {}

	local MakeBaseAttrPanel = function(attrInfo)
		local attrid = attrInfo.id
		local resultPanel

		resultPanel = gui.Panel{
			classes = {"attributePanel"},
			gui.Panel{
				classes = {"attributeModifierPanel", "baseAttributePanel"},
				dragTarget = true,
				data = {
					attrid = attrid,
				},
				gui.Label{
					classes = {"baseAttributeLabel"},
					characterLimit = 2,
					refreshBuilder = function(element)
						local methodInfo = GetGenerationMethodInfo()
						if methodInfo == nil then
							return
						end
						element.editable = methodInfo.method == "manual"
						if methodInfo.method == "roll" or methodInfo.method == "array" then
							
							local gen = g_creature:try_get("attributeGeneration")
							if gen == nil or gen.rollAssignment == nil or gen.rollAssignment[attrid] == nil then
								element.parent:SetClassTree("initialized", false)
								element.text = "--"
								m_attrPanelsById[attrid]:SetClassTree("initialized", false)
								return
							end
						end

						local attr = g_creature:GetBaseAttribute(attrInfo.id)
						element.text = tostring(attr.baseValue)

						element.parent:SetClassTree("initialized", true)
						m_attrPanelsById[attrid]:SetClassTree("initialized", true)
					end,

					editable = true,

					change = function(element)
						local num = tonumber(element.text)
						if num ~= nil then
							g_creature:GetBaseAttribute(attrInfo.id).baseValue = num
						end
						CharacterSheet.instance:FireEvent("refreshAll")
						CharacterSheet.instance:FireEventTree("refreshBuilder")
					end,
				},

				gui.Panel{
					floating = true,
					halign = "right",
					valign = "center",
					hmargin = 10,
					width = 30,
					height = 40,
					flow = "vertical",

					refreshBuilder = function(element)
						local methodInfo = GetGenerationMethodInfo()
						if methodInfo == nil or methodInfo.method ~= "points" then
							element:SetClass("hidden", true)
							return
						end

						element:SetClass("hidden", false)

						--set if the up and down arrows are shown or not.
						local children = element.children

						local val = g_creature:GetBaseAttribute(attrid).baseValue
						if m_pointsBuyInfo.tableCosts[val] == nil or m_pointsBuyInfo.tableCosts[val+1] == nil then
							children[1]:SetClass("hidden", true)
						else
							local cost = m_pointsBuyInfo.tableCosts[val+1] - m_pointsBuyInfo.tableCosts[val]
							children[1]:SetClass("hidden", cost > m_pointsBuyInfo.pointsRemaining)
						end

						children[2]:SetClass("hidden", m_pointsBuyInfo.tableCosts[val-1] == nil)
					end,

					styles = {
						{
							selectors = {"paging-arrow", "hover"},
							brightness = 2,
						}
					},

					gui.PagingArrow{
						floating = true,
						valign = "top",
						rotate = 90,
						height = 20,
						press = function(element)
							local attr = g_creature:GetBaseAttribute(attrid)
							attr.baseValue = attr.baseValue + 1
							CharacterSheet.instance:FireEvent("refreshAll")
							CharacterSheet.instance:FireEventTree("refreshBuilder")
						end,
					},

					gui.PagingArrow{
						floating = true,
						valign = "bottom",
						rotate = -90,
						height = 20,
						press = function(element)
							local attr = g_creature:GetBaseAttribute(attrid)
							attr.baseValue = attr.baseValue - 1
							CharacterSheet.instance:FireEvent("refreshAll")
							CharacterSheet.instance:FireEventTree("refreshBuilder")
						end,
					},

				}
			},

			gui.Label{
				classes = {"attrLabel","attributeIdLabel"},
				text = string.upper(string.sub(creature.attributesInfo[attrid].description, 1, 3)),
			},
		}

		return resultPanel
	end
	
	local MakeAttrPanel = function(attrInfo)

		local attrid = attrInfo.id
		local resultPanel

		local orbPanel = CharSheet.AttrModificationOrbPanel(attrid)

		resultPanel = gui.Panel{
			classes = {"attributePanel"},

			gui.Panel{
				classes = {"attributeModifierPanel"},
				refreshBuilder = function(element)
					orbPanel:FireEventTree("refreshOrb", g_creature)
				end,
				gui.Label{
					classes = {"attributeModifierLabel", "valueLabel", "dice"},

					refreshBuilder = function(element)
						if element:HasClass("initialized") then
							local attr = g_creature:GetBaseAttribute(attrInfo.id)
							element.text = ModifierStr(g_creature:GetAttribute(attrid):Modifier())
						else
							element.text = "--"
						end
					end,
				},

				gui.Panel{
					classes = {"attributeStatPanel"},
					floating = true,
					gui.Panel{
						classes = {"attributeStatPanelBorder"},
					},
					gui.Label{
						classes = {"attributeStatLabel", "editable"},
						refreshBuilder = function(element)
							if element:HasClass("initialized") then
								element.text = tostring(g_creature:GetAttribute(attrid):Value())
							else
								element.text = "--"
							end
						end,
					},
					orbPanel,
				},
			},

			gui.Label{
				classes = {"attrLabel","attributeIdLabel"},
				text = string.upper(string.sub(creature.attributesInfo[attrid].description, 1, 3)),
			},
		}

		return resultPanel


	end

	local basePanels = {}
	local panels = {}
	for i,attrid in ipairs(creature.attributeIds) do
		basePanels[#basePanels+1] = MakeBaseAttrPanel(creature.attributesInfo[attrid])
		panels[#panels+1] = MakeAttrPanel(creature.attributesInfo[attrid])

		m_baseAttrPanelsById[attrid] = basePanels[#basePanels]
		m_attrPanelsById[attrid] = panels[#panels]
	end

	local baseAttributesPanel = gui.Panel{
		width = "auto",
		height = 150,
		halign = "center",
		valign = "top",
		vpad = 20,
		flow = "horizontal",
		children = basePanels,
	}

	local attributesPanel = gui.Panel{
		width = "auto",
		height = 150,
		halign = "center",
		valign = "top",
		vpad = 20,
		flow = "horizontal",
		children = panels,
	}

	local ArePlayerRollsLocked = function()
		local gen = g_creature:try_get("attributeGeneration")
		if gen ~= nil then
			local methodInfo = attributeGenerationTable[gen.method]
			if methodInfo ~= nil and methodInfo.method == "roll" and methodInfo.lockInPlayerRolls and dmhub.isDM == false then
				return true
			end
		end

		return false
	end

	table.sort(attributeGenerationOptions, function(a,b) return a.ord < b.ord end)

	local attributesGenerationPanel

	if #attributeGenerationOptions > 0 then

		local manualEntryPanel = gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
			valign = "center",
			refreshBuilder = function(element)
				local methodInfo = GetGenerationMethodInfo()
				element:SetClass("collapsed", methodInfo == nil or methodInfo.method ~= "manual")
			end,

			gui.Label{
				classes = {"sheetLabel"},
				halign = "center",
				valign = "center",
				fontSize = 18,
				text = "Enter your base attributes above.",
			}
		}

		local rollPanels = {}
		local rollPanelsContainer = gui.Panel{
			flow = "horizontal",
			maxWidth = 800,
			width = "auto",
			height = "auto",
			wrap = true,

			styles = CharSheet.DiceStyles,
		
		}

		local pointsBuyLabel = gui.Label{
			classes = {"sheetLabel"},
			halign = "center",
			valign = "center",
		}
		local pointsBuyPanel
		pointsBuyPanel = gui.Panel{
			width = "auto",
			height = "auto",
			halign = "center",
			flow = "vertical",
			refreshGeneration = function(element)
				local info = GetGenerationMethodInfo()
				element:SetClass("collapsed", info == nil or info.method ~= "points")

				if element:HasClass("collapsed") then
					m_pointsBuyInfo = nil
					return
				end

				local gen = g_creature:try_get("attributeGeneration")
				if gen == nil then
					gen = {
						methodid = GetGenerationMethodId(),
					}

					g_creature.attributeGeneration = gen
				end

				if gen.init ~= GetGenerationMethodId() then
					gen.init = GetGenerationMethodId()

					local defaultValue = info:GetPointBuyDefaultValue()

					for i,attrid in ipairs(creature.attributeIds) do
						g_creature:GetBaseAttribute(attrid).baseValue = defaultValue
					end

					CharacterSheet.instance:FireEvent("refreshAll")
					CharacterSheet.instance:FireEventTree("refreshBuilder")
				end

				local tbl = info:GetPointBuyTable()

				local tableCosts = {}

				for _,entry in ipairs(tbl.entries) do
					local cost = tonumber(entry.script)
					tableCosts[entry.threshold] = cost
				end


				local spend = 0
				for _,attrid in ipairs(creature.attributeIds) do
					local val = g_creature:GetBaseAttribute(attrid).baseValue
					local cost = tableCosts[val] or 0

					spend = spend + cost
				end

				m_pointsBuyInfo = {
					minValue = tbl.entries[1].threshold,
					maxValue = tbl.entries[#tbl.entries].threshold,
					pointsRemaining = info.points - spend,
					tableCosts = tableCosts,
				}

				pointsBuyLabel.text = string.format("Points Remaining: %d", round(m_pointsBuyInfo.pointsRemaining))

			end,

			pointsBuyLabel,

		}


		local rollAttributesPanel
		rollAttributesPanel = gui.Panel{
			width = "auto",
			height = "auto",
			halign = "center",
			flow = "vertical",
			refreshBuilder = function(element)
				local info = GetGenerationMethodInfo()
				element:SetClass("collapsed", info == nil or info.method ~= "roll" and info.method ~= "array")

				if element:HasClass("collapsed") then
					return
				end

				local numPanels = #creature.attributeIds
				
				if info.method == "roll" then
					numPanels = numPanels + info.extraRolls
				end

				if numPanels ~= #rollPanels then

					while #rollPanels > numPanels do
						rollPanels[#rollPanels] = nil
					end

					while #rollPanels < numPanels do
						local panelNum = #rollPanels+1

						local m_rolling = false

						local rollPanel
						
						rollPanel = gui.Panel{
							classes = {"attributePanel"},
							halign = "center",
							height = 140,

							gui.Panel{

								classes = {"attributeModifierPanel"},

								data = {
									m_rollInfo = nil,
									m_diceRolling = false,
								},

								beginRoll = function(element, rollInfo)
									local rolls = rollInfo.rolls
									local diceStyle = rollInfo.diceStyle

									element.data.m_rollInfo = rollInfo
									element.thinkTime = 0.01

									for i,roll in ipairs(rolls) do
										local angle = ((i-0.5) / #rolls)*360
										local xoffset = math.sin(math.rad(angle))
										local yoffset = math.cos(math.rad(angle))
										local dicePanel = gui.Panel{
											styles = {
												{
													bgcolor = diceStyle.trimcolor,
												},
												{
													selectors = {"dicePreviewPanel", "create"},
													transitionTime = 0.2,
													x = -xoffset*30,
													y = -yoffset*30,
													scale = 0.2,
												},
												{
													selectors = {"create"},
													transitionTime = 0.2,
													opacity = 0,
												},
												{
													selectors = {"dicePreviewPanel"},
													brightness = 0.4,
													saturation = 0.7,
												},
												{
													selectors = {"dicePreviewPanel", "finishing"},
													transitionTime = 0.3,
													easing = "easeInBack",
													x = -xoffset*30,
													y = -yoffset*30,
												},
												{
													selectors = {"dicePreviewPanel", "finishing"},
													transitionTime = 0.3,
													brightness = 5,
													saturation = 1,
												},
												{
													selectors = {"finishing"},
													transitionTime = 0.3,
													easing = "easeInBack",
													bgcolor = "white",
												}
											},
											classes = {"dicePreviewPanel"},
											bgimage = string.format('ui-icons/d%d-filled.png', roll.numFaces),
											x = xoffset*30,
											y = yoffset*30,
											width = 28,
											height = 28,
											halign = "center",
											valign = "center",
											floating = true,

											diceface = function(element, diceguid, num)
												if diceguid == roll.guid then
													element.children[1].text = tostring(num)
												end
											end,
											finishRoll = function(element)
												element:SetClassTree("finishing", true)
												element:ScheduleEvent("die", 0.5)
											end,
											die = function(element)
												element:DestroySelf()
											end,
											gui.Label{
												bgimage = string.format('ui-icons/d%d.png', roll.numFaces),
												fontSize = 18,
												bold = true,
												width = 28,
												height = 28,
												color = diceStyle.color,
												halign = "center",
												valign = "center",
												textAlignment = "center",
											},
										}

										local events = chat.DiceEvents(roll.guid)
										if events ~= nil then
											events:Listen(dicePanel)
										end

										element:AddChild(dicePanel)
									end

								end,

								--used while a roll is active.
								think = function(element)
									if element.data.m_rollInfo.timeRemaining >= 0 then
										element.data.m_diceRolling = true
									end
									
									if element.data.m_diceRolling and element.data.m_rollInfo.timeRemaining <= 0.3 then
										element:FireEventTree("finishRoll")
										element.data.m_rollInfo = nil
										element.data.m_diceRolling = false
										element.thinkTime = nil
									end
								end,

								gui.Label{
									classes = {"baseAttributeLabel"},
									text = "--",
									startRoll = function(element)
										element.text = ""
									end,
									finishRoll = function(element)
										element:PulseClass("newvalue")
									end,


									canDragOnto = function(element, target)
										return target ~= nil and target:HasClass("baseAttributePanel")
									end,

									drag = function(element, target)
										if target ~= nil then
											local gen = g_creature:try_get("attributeGeneration")
											if gen ~= nil then
												local rollAssignment = gen.rollAssignment or {}
												gen.rollAssignment = rollAssignment

												for k,v in pairs(rollAssignment) do
													if v == panelNum then
														if k == target.data.attrid then
															--dragged onto existing target, do nothing.
															return
														else
															g_creature:GetBaseAttribute(k).baseValue = 0
															rollAssignment[k] = nil
															break
														end
													end
												end

												rollAssignment[target.data.attrid] = panelNum
												g_creature:GetBaseAttribute(target.data.attrid).baseValue = tonumber(element.text) or 0
												CharacterSheet.instance:FireEvent("refreshAll")
												CharacterSheet.instance:FireEventTree("refreshBuilder")
											end
										end
									end,


									refreshBuilder = function(element)
										if rollAttributesPanel:HasClass("collapsed") then
											return
										end

										if m_rolling then
											element.text = ""
											element.draggable = false
											return
										end

										local methodInfo = GetGenerationMethodInfo()

										local gen = g_creature:try_get("attributeGeneration")

										if methodInfo.method == "array" then
											element.text = tostring(methodInfo:GetStandardArray()[panelNum] or 0)
											element.draggable = true
										elseif gen ~= nil and gen.rolls ~= nil and type(gen.rolls[panelNum]) == "number" then
											element.text = tonumber(gen.rolls[panelNum])
											element.draggable = true
										else
											element.text = "--"
											element.draggable = false
										end

										local used = nil
										if gen ~= nil and gen.rollAssignment ~= nil then
											for k,v in pairs(gen.rollAssignment) do
												if v == panelNum then
													used = k
													break
												end
											end
										end

										rollPanel:SetClassTree("used", used ~= nil)
										if used ~= nil then
											rollPanel:FireEventTree("used", used)
										end
									end,
								}
							},

							gui.Label{
								classes = {"attrLabel","attributeIdLabel","diceAttrLabel"},
								y = -12,
								used = function(element, attrid)
									element.text = string.upper(string.sub(creature.attributesInfo[attrid].description, 1, 3))
								end,
							},

							gui.Panel{
								classes = {"dice"},

								refreshBuilder = function(element)
									if rollAttributesPanel:HasClass("collapsed") then
										return
									end

									if m_rolling then
										element:SetClass("hidden", true)
										return
									end

									local methodInfo = GetGenerationMethodInfo()
									if methodInfo.method == "array" then
										element:SetClass("hidden", true)
										return
									end

									local gen = g_creature:try_get("attributeGeneration")
									if gen ~= nil and gen.rolls ~= nil and type(gen.rolls[panelNum]) == "number" and dmhub.isDM == false and GetGenerationMethodInfo().lockInPlayerRolls then
										--player has already rolled this one, may not roll again
										element:SetClass("hidden", true)
										return
									end

									element:SetClass("rolled", gen ~= nil and gen.rolls ~= nil and type(gen.rolls[panelNum]) == "number")

									element:SetClass("hidden", false)
								end,



								click = function(element)
									local gen = g_creature:try_get("attributeGeneration")
									if gen ~= nil and gen.rolls ~= nil and type(gen.rolls[panelNum]) == "number" then
										--already rolled, so this resets.
										gen.rolls[panelNum] = "none"
										CharacterSheet.instance:FireEvent("refreshAll")
										CharacterSheet.instance:FireEventTree("refreshBuilder")
										return
									end

									m_rolling = true
									element:SetClass("hidden", true)

									rollPanel:FireEventTree("startRoll")

									dmhub.Roll{
										roll = GetGenerationMethodInfo().roll,
										description = "Attribute roll",
										tokenid = dmhub.LookupTokenId(g_creature),
										begin = function(rollInfo)
											--can look at rollInfo.rolls if we want to watch the dice rolls. See ChatPanel.cs ChatMessageDiceRollInfoLua
											rollPanel:FireEventTree("beginRoll", rollInfo)

										end,

										complete = function(rollInfo)
											rollPanel:FireEventTree("finishRoll")
											m_rolling = false

											local gen = g_creature:try_get("attributeGeneration")
											if gen == nil then
												gen = {
													methodid = GetGenerationMethodId()
												}
												g_creature.attributeGeneration = gen
											end

											gen.rolls = gen.rolls or {}
											while #gen.rolls < panelNum do
												gen.rolls[#gen.rolls+1] = "none"
											end

											gen.rolls[panelNum] = rollInfo.total

											CharacterSheet.instance:FireEvent("refreshAll")
											CharacterSheet.instance:FireEventTree("refreshBuilder")
										end
									}

								end,
							},
						}

						rollPanels[#rollPanels+1] = rollPanel
					end

					rollPanelsContainer.children = rollPanels
				end

			end,

			rollPanelsContainer,
		}




		attributesGenerationPanel = gui.Panel{
			width = 800,
			height = "auto",
			minHeight = 300,
			halign = "center",
			valign = "top",
			flow = "vertical",

			gui.Panel{
				refreshGeneration = function(element)
					element:SetClass("hidden", ArePlayerRollsLocked())
				end,

				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					halign = "left",
					text = "Generation Method:",
				},

				gui.Dropdown{
					classes = {"formDropdown"},
					options = attributeGenerationOptions,
					change = function(element)
						g_creature.attributeGeneration = {
							methodid = element.idChosen
						}
						CharacterSheet.instance:FireEvent("refreshAll")
						CharacterSheet.instance:FireEventTree("refreshBuilder")
					end,
					refreshGeneration = function(element)
						element.idChosen = GetGenerationMethodId()

					end,
				},
			},

			manualEntryPanel,
			rollAttributesPanel,
			pointsBuyPanel,

		}
	end

	local content = gui.Panel{
		halign = "center",
		valign = "top",
		height = "auto",
		width = "auto",
		flow = "vertical",

		gui.Panel{
			width = 16,
			height = 16,
		},

		gui.Label{
			classes = {"mainHeading"},
			halign = "center",
			text = "Base Attribute Scores",
		},

		baseAttributesPanel,

		attributesGenerationPanel,

		gui.Label{
			classes = {"mainHeading"},
			halign = "center",
			text = "Final Attribute Scores",
		},


		attributesPanel,

		refreshBuilder = function(element)

			--give the generation panel a chance to update things before anything else gets to it.
			if attributesGenerationPanel ~= nil then
				attributesGenerationPanel:FireEventTree("refreshGeneration")
			end
		end,
	}
	
	banner = CharSheet.BuilderBanner{
		text = "Attributes",
		content = content,
	}

	return banner
end


function CharSheet.BuilderBackgroundPanel()

	local banner

	local backgroundChoicePanel = CharSheet.BackgroundChoicePanel{
		alert = function(element)
			banner:FireEvent("showAlert")
		end,
	}

	local content = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		halign = "center",
		valign = "center",

		backgroundChoicePanel,
	}

	banner = CharSheet.BuilderBanner{
		text = "Career",
		content = content,
		calculateText = function(element)
			local bg = g_creature:Background()
			if bg ~= nil then
				element.text = string.format("%s", bg.name)
			else
				element.text = "Career"
			end
		end,
	}

	return banner
end

function CharSheet.BuilderRacePanel()

	local banner

	local raceChoicePanel = CharSheet.RaceChoicePanel{
		alert = function(element)
			banner:FireEvent("showAlert")
		end,
	}

	local content = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		halign = "center",
		valign = "center",

		raceChoicePanel,
	}

	banner = CharSheet.BuilderBanner{
		text = GameSystem.RaceName,
		content = content,
		calculateText = function(element)
			if g_creature:has_key("raceid") then
				element.text = string.format("%s", g_creature:Race().name)
			else
				element.text = tr(GameSystem.RaceName)
			end
		end,
	}

	return banner

end

function CharSheet.BuilderClassChoicePanel()
	local banner

	local hitpointsPanels = {}

	local classesPanels = {}

	local classChoicePanel = CharSheet.ClassChoicePanel(1)

	local content = gui.Panel{
		halign = "center",
		valign = "top",
		height = "auto",
		width = "100%",
		flow = "vertical",

		classChoicePanel,

		--removed for Draw Steel -- removed permanently?
		refreshBuilderxxx = function(element)
			local newClassesPanels = {}
			local children = {}

			local classLabel = classesPanels["classLabel"] or gui.Label{
				classes = {"mainHeading", "sheetLabel"},
				text = "Class",
			}

			newClassesPanels["classLabel"] = classLabel
			children[#children+1] = classLabel

			for i,entry in ipairs(g_creature:try_get("classes", {})) do
				local item = classesPanels[entry.classid]

				if item == nil then
					local classesTable = dmhub.GetTable('classes')
					local classid = entry.classid
					local classInfo = classesTable[classid]

					item = gui.Panel{
						classes = {'formPanel'},
						children = {
							gui.Label{
								classes = {'sheetLabel', "formLabel"},
								text = string.format("%s:", classInfo.name),
							},
							gui.Input{
								classes = {"smallNumberInput"},
								characterLimit = 2,
								events = {
									refreshBuilder = function(element)
										element.text = string.format("%d", g_creature:GetLevelInClass(classid))
									end,
									change = function(element)
										g_creature:SetClass(classid, tonumber(element.text))
										CharacterSheet.instance:FireEvent("refreshAll")
										CharacterSheet.instance:FireEventTree("refreshBuilder")
									end,
								},
							},
						},
					}

				end

				children[#children+1] = item
				newClassesPanels[entry.classid] = item
			end

			local dropdown = classesPanels["dropdown"] or gui.Dropdown{
				halign = "left",
				change = function(element)
					local classid = element.idChosen
					local classesTable = dmhub.GetTable('classes')
					if classid ~= "add" and classesTable[classid] ~= nil then
						g_creature:SetClass(classid, 1)
						CharacterSheet.instance:FireEvent("refreshAll")
						CharacterSheet.instance:FireEventTree("refreshBuilder")
					end
				end,

				refreshBuilder = function(element)
					local options = {}
					local classes = g_creature:try_get("classes", {})
					local haveClasses = {}
					for i,classInfo in ipairs(classes) do
						haveClasses[classInfo.classid] = true
					end

					local classesTable = dmhub.GetTable('classes')
					for k,classInfo in pairs(classesTable) do
						if (not haveClasses[k]) and classInfo:try_get("hidden", false) == false then
							options[#options+1] = {
								id = k,
								text = classInfo.name,
							}
						end
					end

					table.sort(options, function(a,b) return a.text < b.text end)

					if #classes == 0 then
						table.insert(options, 1, {
							id = "add",
							text = "Choose Class...",
						})

						banner:FireEvent("showAlert", 1)
					else
						table.insert(options, 1, {
							id = "add",
							text = "Add Multiclass...",
						})
					end

					element:SetClass("collapsed", #options == 1)

					element.options = options
					element.idChosen = "add"
				end,
			}

			newClassesPanels["dropdown"] = dropdown
			children[#children+1] = dropdown

			local hitpointsLabel = classesPanels["hitpointsLabel"] or gui.Label{
				classes = {"mainHeading", "sheetLabel"},
				text = "Hitpoints",
			}

			newClassesPanels["hitpointsLabel"] = hitpointsLabel
			children[#children+1] = hitpointsLabel

			dropdown = classesPanels["hitpointsDropdown"] or gui.Dropdown{
				options = {
					"Fixed Hitpoints",
					"Roll for Hitpoints",
					"Manual Hitpoints",
				},
				change = function(element)
					g_creature.roll_hitpoints = cond(element.optionChosen == "Roll for Hitpoints", true)
					g_creature.override_hitpoints = cond(element.optionChosen == "Manual Hitpoints", true)
					CharacterSheet.instance:FireEvent("refreshAll")
					CharacterSheet.instance:FireEventTree("refreshBuilder")
				end,
			}

			dropdown.optionChosen = cond(g_creature.roll_hitpoints, "Roll for Hitpoints", "Fixed Hitpoints")

			newClassesPanels["hitpointsDropdown"] = dropdown
			children[#children+1] = dropdown

			local hitpointsPanel = classesPanels["hitpointsPanel"] or gui.Panel{
				width = "100%",
				height = "auto",
				flow = "vertical",
				refreshBuilder = function(element)
					local newHitpointsPanels = {}
					local children = {}

					local classesTable = dmhub.GetTable("classes")
					local conMod = g_creature:AttributeMod("con")

					newHitpointsPanels["conMod"] = hitpointsPanels["conMod"] or gui.Panel{
						classes = {"formPanel"},
						gui.Label{
							classes = {"formLabel"},
							text = string.format("%s:", GameSystem.bonusHitpointsForLevelRulesText),
						},
						gui.Label{
							classes = {"formLabel"},
							refreshBuilder = function(element)
								element.text = ModStr(g_creature:AttributeMod("con"))
							end,
						},
					}

					children[#children+1] = newHitpointsPanels["conMod"]

					if g_creature.override_hitpoints then
						local overridePanel = hitpointsPanels["override"] or gui.Panel{
							classes = {"formPanel"},
							gui.Label{
								classes = {"formLabel"},
								text = "Hitpoints:",
							},
							gui.Input{
								classes = {"smallNumberInput"},
								characterLimit = 3,
								change = function(element)
									local num = tonumber(element.text)
									if num ~= nil then
										g_creature.max_hitpoints = math.floor(num)
									end
									CharacterSheet.instance:FireEvent("refreshAll")
									CharacterSheet.instance:FireEventTree("refreshBuilder")
								end,
							},
						}

						overridePanel.children[2].text = tostring(g_creature.max_hitpoints)

						newHitpointsPanels["override"] = overridePanel
						children[#children+1] = overridePanel

						local notesPanel = hitpointsPanels["notes"] or gui.Input{
							classes = {"notesInput"},
							placeholderText = "Enter hitpoints notes...",
							multiline = true,
							change = function(element)
								g_creature.override_hitpoints_note = element.text
								CharacterSheet.instance:FireEvent("refreshAll")
								CharacterSheet.instance:FireEventTree("refreshBuilder")
							end,
						}

						notesPanel.text = g_creature.override_hitpoints_note

						newHitpointsPanels["notes"] = notesPanel
						children[#children+1] = notesPanel
					else
						for classNum,classInfo in ipairs(g_creature:get_or_add("classes", {})) do

							local c = classesTable[classInfo.classid]
							if c ~= nil then
								newHitpointsPanels[classInfo.classid] = hitpointsPanels[classInfo.classid] or gui.Label{
									classes = {"formLabel"},
								}

								newHitpointsPanels[classInfo.classid].text = string.format("%s (d%d)\n", c.name, c.hit_die)
								children[#children+1] = newHitpointsPanels[classInfo.classid]

								for levelNum=1,classInfo.level do
									local key = string.format("%s-%d", classInfo.classid, levelNum)
									newHitpointsPanels[key] = hitpointsPanels[key] or gui.Panel{
										x = 20,
										classes = {"formPanel"},
										gui.Label{
											classes = {"formLabel"},
											text = string.format("Level %d", levelNum)
										},

										gui.Label{
											classes = {"formLabel"},
											width = 40,
											characterLimit = 2,

											change = function(element)
												local num = tostring(element.text)

												if num ~= nil then
													local key = string.format("%s-%d", classInfo.classid, levelNum)
													local hitpointRolls = g_creature:get_or_add("hitpointRolls", {})
													local rollData = hitpointRolls[key]
													if rollData == nil then
														rollData = {
															history = {}
														}
														hitpointRolls[key] = rollData
													end

													rollData.roll = num
													if #rollData.history > 8 then
														table.remove(rollData.history, 1)
													end
													rollData.history[#rollData.history+1] = {
														timestamp = ServerTimestamp(),
														roll = rollData.total,
														manual = true,
													}
												end
												
												CharacterSheet.instance:FireEvent("refreshAll")
												CharacterSheet.instance:FireEventTree("refreshBuilder")
											end,
										},

										gui.Panel{
											classes = {"dieIcon"},
											click = function(element)
												element:SetClass("hidden", true)
												dmhub.Roll{
													roll = string.format("1d%d", c.hit_die),
													description = string.format("Level Hitpoints"),
													tokenid = dmhub.LookupTokenId(g_creature),
													complete = function(rollInfo)
														local key = string.format("%s-%d", classInfo.classid, levelNum)
														local hitpointRolls = g_creature:get_or_add("hitpointRolls", {})
														local rollData = hitpointRolls[key]
														if rollData == nil then
															rollData = {
																history = {}
															}
															hitpointRolls[key] = rollData
														end

														rollData.roll = rollInfo.total
														if #rollData.history > 8 then
															table.remove(rollData.history, 1)
														end
														rollData.history[#rollData.history+1] = {
															timestamp = ServerTimestamp(),
															roll = rollData.total,
														}

														CharacterSheet.instance:FireEvent("refreshAll")
														CharacterSheet.instance:FireEventTree("refreshBuilder")
													end,
												}
											end,
										},

										gui.Label{
											classes = {"formLabel"},
											width = 40,
										},
									}

									local num = nil
									local editable = false
									
									if levelNum == 1 and classNum == 1 then
										num = c.hit_die
									elseif g_creature.roll_hitpoints then
										local hitpointRolls = g_creature:try_get("hitpointRolls", {})
										local roll = hitpointRolls[string.format("%s-%d", classInfo.classid, levelNum)]
										if roll ~= nil then
											num = roll.roll
										end

										editable = true
									else
										num = 1+c.hit_die/2
									end

									newHitpointsPanels[key].children[2].editable = editable


									if num == nil then
										newHitpointsPanels[key].children[2].text = "--"
										newHitpointsPanels[key].children[3]:SetClass("hidden", false)
										newHitpointsPanels[key].children[3].bgimage = string.format("ui-icons/d%d.png", c.hit_die)
										banner:FireEvent("showAlert", 1)
									else
										newHitpointsPanels[key].children[2].text = tostring(num)
										newHitpointsPanels[key].children[3]:SetClass("hidden", true)
									end

									newHitpointsPanels[key].children[4].text = ModStr(conMod)

									children[#children+1] = newHitpointsPanels[key]
								end
							end
						end --end for loop over levels.
					end --end if hitpoints override


					local text = ""
					local baseHitpoints = g_creature:BaseHitpoints()
					local mods = g_creature:DescribeModifications("hitpoints", baseHitpoints)
					if mods ~= nil and #mods ~= 0 then
						text = string.format("%sBase Hitpoints: %d\n", text, baseHitpoints)
						for i,mod in ipairs(mods) do
							text = string.format("%s%s: %s\n", text, mod.key, mod.value)
						end
					end
					text = string.format("%sTotal Hitpoints: %d\n", text, g_creature:MaxHitpoints())

					local descriptionLabel = hitpointsPanels["descriptionLabel"] or gui.Label{
						classes = {"sheetLabel", "featureDescription"},
						width = "100%",
					}

					descriptionLabel.text = text

					newHitpointsPanels["descriptionLabel"] = descriptionLabel
					children[#children+1] = descriptionLabel

					hitpointsPanels = newHitpointsPanels
					element.children = children
				end,
			}

			newClassesPanels["hitpointsPanel"] = hitpointsPanel
			children[#children+1] = hitpointsPanel

			element.children = children
			classesPanels = newClassesPanels
		end,
	}

	banner = CharSheet.BuilderBanner{
		text = "Class",
		content = content,
	}

	return banner

end

function CharSheet.BuilderClassPanel(classIndex)

	local banner

	local classChoicePanel = CharSheet.ClassChoicePanel({
		alert = function(element)
			if classIndex == 1 or element:HasClass("hasclass") then
				banner:FireEvent("showAlert")
			end

		end,
	}, classIndex)

	local content = gui.Panel{
		halign = "center",
		valign = "top",
		height = "auto",
		width = "100%",
		flow = "vertical",

		classChoicePanel,
	}

	banner = CharSheet.BuilderBanner{
		text = "Class",
		content = content,
		calculateText = function(element)
			local classEntry = g_creature:try_get("classes", {})[classIndex]
			if classEntry ~= nil then
				local classesTable = dmhub.GetTable("classes")
				local classInfo = classesTable[classEntry.classid]
				if classInfo ~= nil then
					element.text = string.format("%s", classInfo.name)
				end
			else
				element.text = cond(classIndex == 1, tr("Class"), tr("Add Class"))
			end

			--to add a new class, make the tab small.
			element:SetClass("small", classEntry == nil and classIndex ~= 1)
		end,
	}

	return banner
end

function CharSheet.BuilderPanel()
	local resultPanel

	local panels = {}
	local tabs = {}

	local tabsPanel = gui.Panel{
		classes = {"tabContainer"},
		styles = {
			CharSheet.TabsStyles,
		},
	}

	local CreateTab = function(tabid, panel)

		local alertIcon = gui.NewContentAlert{
			halign = "left",
			x = 8,
		}

		panel.data.alertIcon = alertIcon

		panel.data.tab = gui.Label{
			id = string.format("tab-%s", tabid),
			classes = {"tab"},
			press = function(element)
				for i,p in ipairs(panel.parent.children) do
					p:SetClass("collapsed", p ~= panel)
				end

				for i,p in ipairs(element.parent.children) do
					p:SetClass("selected", p == element)
				end
			end,
			gui.Panel{classes = {"tabBorder"}},
			alertIcon,
		}

		return panel
	end

    local m_subclassFeatureCache = {}
	
	resultPanel = gui.Panel{
		theme = "charsheet.Main",
		styles = BuilderStyles,
		id = "builderPanel",
		classes = {"characterSheetPanel", "builder", "hidden" },
		floating = true,

		charsheetActivate = function(element, val)
			if val then
				--element:FireEventTree("refreshBuilder")
                CharacterSheet.instance:FireEventTree("refreshBuilder")
			end
		end,

		refreshBuilder = function(element)
			local creature = CharacterSheet.instance.data.info.token.properties
			g_characterFeatures = creature:GetClassFeaturesAndChoicesWithDetails()
			g_levelChoices = creature:GetLevelChoices() or {}

			--arrange for subclass features on the same level as the subclass was chosen appear immediately
			--below the subclass choice.
			local subclassChoiceIndexByLevel = {}
			local i = 1
			while i <= #g_characterFeatures do
				local f = g_characterFeatures[i]

				if f.class ~= nil and f.class.isSubclass and f.levels ~= nil and #f.levels == 1 then
					local subclassChoiceIndex = subclassChoiceIndexByLevel[f.levels[1]]
					if subclassChoiceIndex ~= nil then
						table.remove(g_characterFeatures, i)
						table.insert(g_characterFeatures, subclassChoiceIndex+1, f)
						subclassChoiceIndexByLevel[f.levels[1]] = subclassChoiceIndex+1
					end
				end

				if f.feature.typeName == "CharacterSubclassChoice" and f.levels ~= nil and #f.levels == 1 then


					local choice = g_levelChoices[f.feature.guid]
					if choice ~= nil then
						--fish out any chosen subclasses
						local subclassesChosen = {}
						for _,choiceid in ipairs(choice) do
							local subclassesTable = dmhub.GetTable("subclasses") or {}
							local subclass = subclassesTable[choiceid]
							if subclass ~= nil then

								local classFeature = {
									class = f.class,
									levels = f.levels,
									feature = CharacterFeature.Create{
										name = subclass.name,
										description = subclass.details,
									}
								}

                                classFeature.feature = m_subclassFeatureCache[choiceid] or CharacterFeature.Create{
                                    name = subclass.name,
                                    description = subclass.details,
                                }

                                m_subclassFeatureCache[choiceid] = classFeature.feature

								table.insert(g_characterFeatures, i+1, classFeature)

								i = i+1

							end
						end
					end

					subclassChoiceIndexByLevel[f.levels[1]] = i
				end

				i = i+1
			end


			g_creature = creature

			g_choicesMade = {}

			for i,featureInfo in ipairs(g_characterFeatures) do
				local choiceList = g_levelChoices[featureInfo.feature.guid]
				if choiceList ~= nil then
					for _,choiceid in ipairs(choiceList) do
						local choicemap = g_choicesMade[choiceid] or {}
						choicemap[featureInfo.feature.guid] = true
						g_choicesMade[choiceid] = choicemap
					end
				end
			end
		end,

		gui.Panel{
			width = "100%",
			height = "100%",
			halign = "center",
			flow = "vertical",
			tabsPanel,

			gui.Panel{
				width = "100%",
				height = "100%-42",
				halign = "left",
				flow = "vertical",
				vscroll = true,
				data = {
					tablesUpdateId = 0,
				},
				refreshBuilder = function(element)
					if element.data.tablesUpdateId ~= dmhub.tablesUpdateId then
						--rebuild all panels if there has been a table update.
                        --don't do this at least for now as it's very disruptive.
                        --TODO: figure out a way to make this happen elegantly.
						--panels = {}
						--tabs = {}

						--print("SelectTab:: Table update")
					end

					local children = {}

					local newPanels = {}
					local newTabs = {}

					for i,tab in ipairs(CharSheet.BuilderTabs) do
						local panel = panels[tab.id] or CreateTab(tab.id, tab.create())
						children[#children+1] = panel
						newPanels[tab.id] = panel
						panel.data.ord = tab.ord

                        panel.data.tab:SetClass("collapsed", tab.visible ~= nil and not tab.visible(g_creature))
					end

					table.sort(children, function(a,b) return a.data.ord < b.data.ord end)

					--local classChoicePanel = panels["classChoice"] or CreateTab(CharSheet.BuilderClassChoicePanel())
					--children[#children+1] = classChoicePanel
					--newPanels["classChoice"] = classChoicePanel

					local classes = g_creature:try_get("classes", {})
					--local addNewClass = cond(dmhub.isDM or #classes == 0 or g_creature:CharacterLevelFromChosenClasses() < g_creature:CharacterLevel(), 1, 0)
					for i=1,1 do --DS always has just one class.
						local key = string.format("class-%d", i)
						local classPanel = panels[key] or CreateTab(key, CharSheet.BuilderClassPanel(i))
						children[#children+1] = classPanel
						newPanels[key] = classPanel
					end


					panels = newPanels
					element.children = children

					local tabs = {}
					for i,child in ipairs(children) do
						tabs[#tabs+1] = child.data.tab
					end

					tabsPanel.children = tabs

					local selectedIndex = 1
					for i,tab in ipairs(tabs) do
						if tab:HasClass("selected") then
							selectedIndex = i
						end
					end

					tabs[selectedIndex]:FireEvent("press")

					element.data.tablesUpdateId = dmhub.tablesUpdateId
				end,
			},
		}
	}

	return resultPanel
end

function CharSheet.BuilderCulturePanel()
    local banner

	local cultureChoicePanel = CharSheet.CultureChoicePanel{
		alert = function(element)
			banner:FireEvent("showAlert")
		end,
	}

	local content = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		halign = "center",
		valign = "center",

		cultureChoicePanel,
	}

	banner = CharSheet.BuilderBanner{
		text = "Culture",
		content = content,
		calculateText = function(element)
            local culture = g_creature:GetCulture()
            if culture ~= nil then
                element.text = string.format("%s", culture.name)
            else
                element.text = "Culture"
            end
		end,
	}

	return banner
end

CharSheet.BuilderTabs = {}

function CharSheet.ClearBuilderTabs()
	CharSheet.BuilderTabs = {}
end

function CharSheet.RegisterBuilderTab(args)
	CharSheet.BuilderTabs[#CharSheet.BuilderTabs+1] = args
	table.sort(CharSheet.BuilderTabs, function(a,b) return a.ord < b.ord end)
end

CharSheet.RegisterBuilderTab{
	id = "settings",
	ord = 10,
	create = CharSheet.BuilderSettingsPanel,
}

CharSheet.RegisterBuilderTab{
	id = "race",
	ord = 30,
	create = CharSheet.BuilderRacePanel,
}

CharSheet.RegisterBuilderTab{
	id = "background",
	ord = 40,
	create = CharSheet.BuilderBackgroundPanel,
}

CharSheet.RegisterBuilderTab{
	id = "kit",
	ord = 50,
	create = CharSheet.BuilderKitPanel,
    visible = function(c)
		--only visible for characters with access to a kit.
		return c ~= nil and c.typeName == "character" and c:CanHaveKits()
    end,
}

CharSheet.RegisterBuilderTab{
	id = "culture",
	ord = 35,
	create = CharSheet.BuilderCulturePanel,
}

CharSheet.RegisterTab{
	id = "Builder",
	text = "Builder",
	visible = function(c)
		--only visible for characters.
		return c ~= nil and c.typeName == "character"
	end,
	panel = CharSheet.BuilderPanel,
}
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
                    centerPopup = true,
                    width = 400,
                    menuWidth = cond(hasCustomPanels, 616, 545),
                    menuHeight = cond(hasCustomPanels, 920, 545),
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
								local pass = ExecuteGoblinScript(choice.prerequisite, g_creature:LookupSymbol(), 0, string.format("Feat %s prerequisite", choice.text))
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
                --print("MATCH:: matching", featureInfo.feature.name, "against criteria", element.data.criteria)
				for k,item in pairs(element.data.criteria) do
					if k == "minlevel" or k == "maxlevel" then
                        local minlevel = element.data.criteria.minlevel or -1
                        local maxlevel = element.data.criteria.maxlevel or 1000
						local match = false
						for i,level in ipairs(featureInfo.levels or {}) do
							if level >= minlevel and level <= maxlevel then
								match = true
								break
							end 
						end

                        --print("MATCH:: HAVE ", k, item, "levels =", featureInfo.levels or {}, "match =", match)

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


dmhub.RefreshCharacterSheet()

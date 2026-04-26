local mod = dmhub.GetModLoading()

DockablePanel.Register{
	name = "Triggers",
	icon = "icons/standard/Icon_App_Character.png",
	minHeight = 140,
	vscroll = true,
	content = function()
		return CreateTriggersPanel()
	end,
}

local TRIGGER_COLORS = {
	trigger = "#5C3A1E",
	free = "#1E3A5C",
	passive = "#1E5C3A",
}

local TRIGGER_TYPE_LABELS = {
	trigger = "Triggered Action",
	free = "Free Triggered Action",
	passive = "Passive",
}

local ALERT_COLOR = "#FF9730"
local ALERT_FREE_COLOR = "#3097FF"
local ALERT_PASSIVE_COLOR = "#00a300"
local ACTIVE_BORDER_COLOR = "#FF9730"

local PREF_KEY = "triggers_panel_collapsed"

local function GetCollapsedSet()
	local saved = dmhub.GetPref(PREF_KEY)
	local result = {}
	if saved ~= nil and type(saved) == "string" and saved ~= "" then
		for name in string.gmatch(saved, "[^|]+") do
			result[name] = true
		end
	end
	return result
end

local function SaveCollapsedSet(collapsedSet)
	local names = {}
	for name, _ in pairs(collapsedSet) do
		names[#names+1] = name
	end
	dmhub.SetPref(PREF_KEY, table.concat(names, "|"))
end

-- Find active triggers matching a display name (case-insensitive).
-- Returns a list of {key, trigger} pairs.
local function FindActiveTriggers(availableTriggers, displayName)
	if availableTriggers == nil then
		return {}
	end
	local lowerName = string.lower(displayName)
	local result = {}
	for key, trigger in pairs(availableTriggers) do
		if not trigger.dismissed and string.lower(trigger:GetText()) == lowerName then
			result[#result+1] = { key = key, trigger = trigger }
		end
	end
	return result
end

local function RenderTriggerCard(triggerDisplay, caster, collapsedSet, manualAbilityEntry, token, activeTriggerMatches)
	local triggerType = triggerDisplay.type or "trigger"
	local headerColor = TRIGGER_COLORS[triggerType] or TRIGGER_COLORS.trigger
	local typeLabel = TRIGGER_TYPE_LABELS[triggerType] or "Triggered Action"
	local triggerName = triggerDisplay.name
	local isCollapsed = collapsedSet[triggerName] == true
	local hasActiveTrigger = #activeTriggerMatches > 0

	-- Header: name + cost
	local nameText = triggerName
	if triggerDisplay.cost ~= nil and triggerDisplay.cost ~= "" then
		nameText = string.format("%s (%s)", nameText, triggerDisplay.cost)
	end

	-- Build body children
	local bodyChildren = {}

	-- Active trigger alert section
	if hasActiveTrigger then
		for _, match in ipairs(activeTriggerMatches) do
			local trigger = match.trigger
			local alertColor = ALERT_COLOR
			if trigger.free then
				alertColor = ALERT_FREE_COLOR
			end

			local targetPanels = {}
			for _, targetId in ipairs(trigger.targets or {}) do
				local targetToken = dmhub.GetTokenById(targetId)
				if targetToken ~= nil then
					targetPanels[#targetPanels+1] = gui.CreateTokenImage(targetToken, {
						width = 28,
						height = 28,
						hmargin = 2,
					})
				end
			end

			bodyChildren[#bodyChildren+1] = gui.Panel{
				width = "100%-12",
				height = "auto",
				flow = "horizontal",
				hmargin = 6,
				vpad = 4,
				bgimage = true,
				bgcolor = alertColor .. "30",
				cornerRadius = 4,
				borderWidth = 1,
				borderColor = alertColor,

				-- [!] icon
				gui.Label{
					textAlignment = "center",
					color = alertColor,
					bold = true,
					text = "!",
					fontSize = 18,
					width = 22,
					height = "100% width",
					valign = "center",
					hmargin = 4,
					bgimage = true,
					bgcolor = "#00000080",
					borderWidth = 1,
					borderColor = alertColor,
				},

				-- Trigger info and buttons
				gui.Panel{
					width = "100%-38",
					height = "auto",
					flow = "vertical",
					hmargin = 4,

					gui.Label{
						width = "100%",
						height = "auto",
						fontSize = 12,
						color = "#FFFEF8",
						markdown = true,
						text = StringInterpolateGoblinScript(trigger:GetRulesText(), caster:LookupSymbol{}),
					},

					-- Target tokens row
					(#targetPanels > 0) and gui.Panel{
						width = "100%",
						height = "auto",
						flow = "horizontal",
						vpad = 2,
						table.unpack(targetPanels),
					} or nil,

					-- Activate / Dismiss buttons
					gui.Panel{
						width = "100%",
						height = "auto",
						flow = "horizontal",
						vpad = 2,
						gui.Label{
							bgimage = true,
							bgcolor = alertColor,
							cornerRadius = 3,
							width = "auto",
							height = "auto",
							hpad = 8,
							vpad = 3,
							fontSize = 12,
							bold = true,
							color = "#000000",
							text = trigger.activateText or "Activate",
							press = function(element)
								token:ModifyProperties{
									undoable = false,
									description = "Trigger",
									execute = function()
										if trigger.triggered then
											trigger.triggered = false
											trigger.retargetid = nil
										else
											trigger.triggered = true
										end
										trigger.dismissed = trigger:DismissOnTrigger()
										token.properties:DispatchAvailableTrigger(trigger)
									end,
								}
							end,
						},
						gui.Label{
							bgimage = true,
							bgcolor = "#333330",
							cornerRadius = 3,
							width = "auto",
							height = "auto",
							hpad = 8,
							vpad = 3,
							hmargin = 4,
							fontSize = 12,
							color = "#8A8474",
							text = "Dismiss",
							press = function(element)
								token:ModifyProperties{
									undoable = false,
									description = "Trigger",
									execute = function()
										trigger.triggered = false
										trigger.dismissed = true
										token.properties:DispatchAvailableTrigger(trigger)
									end,
								}
							end,
						},
					},
				},
			}
		end
	end

	-- Flavor text
	local flavor = triggerDisplay:try_get("flavor")
	if flavor ~= nil and flavor ~= "" then
		bodyChildren[#bodyChildren+1] = gui.Label{
			width = "100%-12",
			height = "auto",
			hmargin = 6,
			vpad = 2,
			fontSize = 13,
			italics = true,
			color = "#B4D1C6",
			text = flavor,
		}
	end

	if triggerType == "passive" then
		bodyChildren[#bodyChildren+1] = gui.Label{
			width = "100%-12",
			height = "auto",
			hmargin = 6,
			vpad = 2,
			fontSize = 13,
			italics = true,
			color = "#8A8474",
			text = typeLabel,
		}

		local effect = triggerDisplay:try_get("effect")
		if effect ~= nil and effect ~= "" then
			bodyChildren[#bodyChildren+1] = gui.Label{
				width = "100%-12",
				height = "auto",
				hmargin = 6,
				vpad = 2,
				fontSize = 13,
				color = "#FFFEF8",
				markdown = true,
				text = StringInterpolateGoblinScript(effect, caster),
			}
		end

		local implNotes = triggerDisplay:try_get("implementationNotes")
		if implNotes ~= nil and implNotes ~= "" then
			bodyChildren[#bodyChildren+1] = gui.Label{
				width = "100%-12",
				height = "auto",
				hmargin = 6,
				vpad = 2,
				fontSize = 13,
				color = "#FFFEF8",
				markdown = true,
				text = string.format("<b>Implementation Notes:</b> %s", StringInterpolateGoblinScript(implNotes, caster)),
			}
		end
	else
		local keywords = triggerDisplay:try_get("keywords") or {}
		local keywordKeys = table.keys(keywords)
		local keywordStr = "-"
		if #keywordKeys > 0 then
			local sorted = {}
			for _,k in ipairs(keywordKeys) do
				sorted[#sorted+1] = ActivatedAbility.CanonicalKeyword(k)
			end
			table.sort(sorted)
			keywordStr = table.concat(sorted, ", ")
		end

		bodyChildren[#bodyChildren+1] = gui.Panel{
			width = "100%-12",
			height = "auto",
			flow = "none",
			hmargin = 6,
			vpad = 2,
			gui.Label{
				halign = "left",
				width = "auto",
				height = "auto",
				fontSize = 13,
				color = "#FFFEF8",
				text = string.format("<b>Keywords:</b> %s", keywordStr),
			},
			gui.Label{
				halign = "right",
				width = "auto",
				height = "auto",
				fontSize = 13,
				color = "#FFFEF8",
				text = string.format("<b>Type:</b> %s", typeLabel),
			},
		}

		local distance = triggerDisplay:try_get("distance") or ""
		local target = triggerDisplay:try_get("target") or ""
		if distance ~= "" or target ~= "" then
			bodyChildren[#bodyChildren+1] = gui.Panel{
				width = "100%-12",
				height = "auto",
				flow = "none",
				hmargin = 6,
				vpad = 2,
				gui.Label{
					halign = "left",
					width = "auto",
					height = "auto",
					fontSize = 13,
					color = "#FFFEF8",
					text = string.format("<b>Distance:</b> %s", StringInterpolateGoblinScript(distance, caster)),
				},
				gui.Label{
					halign = "right",
					width = "auto",
					height = "auto",
					fontSize = 13,
					color = "#FFFEF8",
					text = string.format("<b>Target:</b> %s", StringInterpolateGoblinScript(target, caster)),
				},
			}
		end

		local trigger = triggerDisplay:try_get("trigger")
		if trigger ~= nil and trigger ~= "" then
			bodyChildren[#bodyChildren+1] = gui.Label{
				width = "100%-12",
				height = "auto",
				hmargin = 6,
				vpad = 2,
				fontSize = 13,
				color = "#FFFEF8",
				markdown = true,
				text = string.format("<b>Trigger:</b> %s", StringInterpolateGoblinScript(trigger, caster)),
			}
		end

		local effect = triggerDisplay:try_get("effect")
		if effect ~= nil and effect ~= "" then
			bodyChildren[#bodyChildren+1] = gui.Label{
				width = "100%-12",
				height = "auto",
				hmargin = 6,
				vpad = 2,
				fontSize = 13,
				color = "#FFFEF8",
				markdown = true,
				text = string.format("<b>Effect:</b> %s", StringInterpolateGoblinScript(effect, caster)),
			}
		end

		local implNotesActive = triggerDisplay:try_get("implementationNotes")
		if implNotesActive ~= nil and implNotesActive ~= "" then
			bodyChildren[#bodyChildren+1] = gui.Label{
				width = "100%-12",
				height = "auto",
				hmargin = 6,
				vpad = 2,
				fontSize = 13,
				color = "#FFFEF8",
				markdown = true,
				text = string.format("<b>Implementation Notes:</b> %s", StringInterpolateGoblinScript(implNotesActive, caster)),
			}
		end
	end

	-- "Use" button for triggers with a manual version
	if manualAbilityEntry ~= nil then
		bodyChildren[#bodyChildren+1] = gui.Panel{
			width = "100%-12",
			height = "auto",
			hmargin = 6,
			vpad = 4,
			gui.Label{
				bgimage = true,
				bgcolor = "#966D4B",
				cornerRadius = 4,
				width = "auto",
				height = "auto",
				hpad = 12,
				vpad = 4,
				fontSize = 13,
				bold = true,
				color = "#FFFEF8",
				halign = "center",
				text = "Use",
				press = function(element)
					if gamehud.actionBarPanel.data.IsCastingSpell() then
						return
					end
					local ability
					if manualAbilityEntry.ability.typeName == "ActivatedAbility" then
						ability = DeepCopy(manualAbilityEntry.ability)
						ability._tmp_temporaryClone = true
					else
						ability = manualAbilityEntry.ability:GenerateManualVersion()
					end
					gamehud.actionBarPanel:FireEventTree("invokeAbility", token, ability, {})
				end,
			},
		}
	end

	-- If there's an active trigger, force expand and highlight border
	local cardBorderColor = cond(hasActiveTrigger, ACTIVE_BORDER_COLOR, "#333330")
	local cardCollapsed = cond(hasActiveTrigger, false, isCollapsed)

	return gui.Panel{
		classes = {"triggerCard"},
		width = "100%",
		height = "auto",
		flow = "vertical",
		bgimage = true,
		bgcolor = "#0b0f0d",
		borderWidth = cond(hasActiveTrigger, 2, 1),
		borderColor = cardBorderColor,
		cornerRadius = 4,
		bmargin = 6,
		data = {
			triggerName = triggerName,
			collapsed = cardCollapsed,
		},

		-- Header bar (always visible)
		gui.Panel{
			width = "100%",
			height = "auto",
			flow = "none",
			bgimage = true,
			bgcolor = headerColor,
			vpad = 4,
			press = function(element)
				local card = element.parent
				card.data.collapsed = not card.data.collapsed
				card:FireEventTree("setCollapse", card.data.collapsed)
				if card.data.collapsed then
					collapsedSet[card.data.triggerName] = true
				else
					collapsedSet[card.data.triggerName] = nil
				end
				SaveCollapsedSet(collapsedSet)
			end,

			-- [!] alert icon when active trigger is pending
			hasActiveTrigger and gui.Label{
				halign = "left",
				valign = "center",
				hmargin = 4,
				textAlignment = "center",
				color = ALERT_COLOR,
				bold = true,
				text = "!",
				fontSize = 14,
				width = 18,
				height = "100% width",
				bgimage = true,
				bgcolor = "#00000080",
				borderWidth = 1,
				borderColor = ALERT_COLOR,
			} or nil,

			gui.Label{
				halign = "left",
				width = "auto",
				height = "auto",
				hmargin = cond(hasActiveTrigger, 26, 6),
				fontSize = 15,
				bold = true,
				color = "#FFFEF8",
				text = nameText,
			},
			gui.CollapseArrow{
				halign = "right",
				hmargin = 4,
				valign = "center",
				width = 12,
				height = 8,
				classes = cond(cardCollapsed, {"collapseArrow", "collapseSet"}, nil),
				setCollapse = function(element, collapsed)
					element:SetClass("collapseSet", collapsed)
				end,
			},
		},

		-- Body (collapsible)
		gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
			collapsed = cond(cardCollapsed, 1, 0),
			setCollapse = function(element, collapsed)
				element.selfStyle.collapsed = cond(collapsed, 1, 0)
			end,
			table.unpack(bodyChildren),
		},
	}
end

function CreateTriggersPanel()
	local m_token = nil

	local emptyLabel = gui.Label{
		width = "100%",
		height = "auto",
		fontSize = 14,
		color = "#8A8474",
		textAlignment = "Center",
		vpad = 20,
		text = "No triggers available",
	}

	local contentPanel = gui.Panel{
		width = "100%-8",
		height = "auto",
		flow = "vertical",
		hmargin = 4,
		emptyLabel,
	}

	local function RefreshTriggers(element)
		if m_token == nil or not m_token.valid or m_token.properties == nil then
			contentPanel.children = {emptyLabel}
			element:FireEventOnParents("title", nil)
			return
		end

		local creature = m_token.properties
		local triggeredActions = creature:GetTriggeredActions()

		if #triggeredActions == 0 then
			contentPanel.children = {emptyLabel}
			element:FireEventOnParents("title", "Triggers")
			return
		end

		-- Build lookup of triggered abilities with manual versions
		local manualAbilities = {}
		local triggeredAbilities = creature:GetTriggeredAbilities()
		for _, entry in ipairs(triggeredAbilities) do
			if entry.ability.typeName == "ActivatedAbility" then
				manualAbilities[string.lower(entry.ability.name)] = entry
			elseif entry.ability:try_get("hasManualVersion", false) and not entry.ability:IsLocalOnly() then
				manualAbilities[string.lower(entry.ability.name)] = entry
			end
		end

		-- Get available (active/pending) triggers
		local availableTriggers = creature:GetAvailableTriggers(true)

		local collapsedSet = GetCollapsedSet()
		local cards = {}
		for _, triggerDisplay in ipairs(triggeredActions) do
			local activeTriggerMatches = FindActiveTriggers(availableTriggers, triggerDisplay.name)
			cards[#cards+1] = RenderTriggerCard(triggerDisplay, creature, collapsedSet, manualAbilities[string.lower(triggerDisplay.name)], m_token, activeTriggerMatches)
		end

		contentPanel.children = cards
		element:FireEventOnParents("title", string.format("Triggers (%d)", #triggeredActions))
	end

	local resultPanel = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",

		refresh = function(element)
			local tokens = dmhub.tokenInfo.selectedOrPrimaryTokens
			if #tokens >= 1 then
				local token = tokens[1]
				if token ~= m_token then
					m_token = token
					if m_token ~= nil and m_token.valid then
						element.monitorGame = m_token.monitorPath
					end
				end
				RefreshTriggers(element)
			else
				m_token = nil
				RefreshTriggers(element)
			end
		end,

		refreshGame = function(element)
			RefreshTriggers(element)
		end,

		contentPanel,
	}

	return resultPanel
end

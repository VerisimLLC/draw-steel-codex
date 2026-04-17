local mod = dmhub.GetModLoading()

--This file implements a CharacterFeature. Races, Classes, Feats, Backgrounds, etc are primarily collections
--of CharacterFeatures that are bestowed on Characters. A CharacterFeature is mostly made up of a list of
--modifiers that are applied to the creature that has the feature. It is most typical for a CharacterFeature
--to contain just one modifier.

--- @class CharacterFeature
--- @field guid string Unique identifier for this feature instance.
--- @field name string Display name of the feature.
--- @field source string Human-readable source description (e.g. "Fighter", "Race Trait").
--- @field description string Flavor/rules description shown to the player.
--- @field modifiers CharacterModifier[] The modifiers that this feature applies to the creature.
--- @field domains table<string, boolean> Set of domain strings this feature belongs to (e.g. "Class:Ranger").
--- @field canHavePrerequisites boolean If true, the feature UI allows adding prerequisites.
--- @field prerequisites nil|table[] Optional list of CharacterPrerequisite objects.
--- @field implementation number Choice implementation index (1-based enum).
--- @field options nil|table[] Optional list of sub-options for multi-option features.
--- @field costsPoints boolean If true, selecting this feature costs character build points.
CharacterFeature = RegisterGameType("CharacterFeature")

CharacterFeature.canHavePrerequisites = false
CharacterFeature.modifiers = {}

--- Creates a new CharacterFeature with default fields and optional overrides.
--- @param options nil|table Field overrides to apply after defaults.
--- @return CharacterFeature
function CharacterFeature.Create(options)
	local args = {
		guid = dmhub.GenerateGuid(),
		name = 'New Feature',
		source = 'Character Feature',
		description = '',
		modifiers = {},
	}

	if options ~= nil then
		for k,v in pairs(options) do
			args[k] = v
		end
	end

	return CharacterFeature.new(args)
end

function CharacterFeature.OnDeserialize(self)
	if type(self.modifiers) == "table" and self.modifiers.typeName ~= nil then
		--apparently an error can happen where modifiers refers to a single modifier. Correct this if it happens.
		self.modifiers = {self.modifiers}
	end

	--try to make sure this feature's mods are correctly attributing us as the source.
	local source = self:try_get("source")
	if source ~= nil then
		for _,mod in ipairs(self.modifiers) do
			mod.source = source
		end
	end
end

--- Appends this feature's active modifiers to the result list.
--- @param creature creature
--- @param result table[] The accumulator list to append modifier entries to.
--- @param params nil|table Extra key-value pairs to merge into each modifier entry.
function CharacterFeature:FillModifiers(creature, result, params)
    for _,mod in ipairs(self.modifiers) do
        local t = { mod = mod }
        if params ~= nil then
            for k,v in pairs(params) do
                t[k] = v
            end
        end
        result[#result+1] = t

		local routinesSelected = creature:try_get("routinesSelected", {})
        if mod.behavior == "routine" and routinesSelected[mod.ability.guid] == nil then
            --routines block other modifiers on the feature unless the routine is selected.
            break
        end
    end
end

--- Returns true if the feature and all its modifiers are valid game objects.
--- @param feature any
--- @return boolean
function CharacterFeature.IsValid(feature)
	if getmetatable(feature) == nil then
		return false
	end

	for _,mod in ipairs(feature.modifiers) do
		if getmetatable(mod) == nil then
			return false
		end
	end

	return true
end

--- Returns a short description of the feature (defaults to its name).
--- @return string
function CharacterFeature:Describe()
	return self.name
end

--- Returns the domain string for this feature (e.g. "CharacterFeature:guid").
--- @return string
function CharacterFeature:Domain()
	return string.format("%s:%s", self.typeName, self:try_get("id", self.guid))
end

CharacterFeature._tmp_ensured_domain = false

function CharacterFeature.EnsureDomains(self)
	if self._tmp_ensured_domain then
		return
	end

	self._tmp_ensured_domain = true
	self:SetDomain(self:Domain())
end

--- Adds a domain string to this feature and propagates it to all its modifiers.
--- @param domainid string
function CharacterFeature.SetDomain(self, domainid)
	local domains = self:get_or_add("domains", {})
	if not domains[domainid] then
		domains[domainid] = true

		for _,mod in ipairs(self:try_get("modifiers", {})) do
			mod:SetDomain(domainid)
		end
	end
end

--- Given a domain map, attempts to find a human-readable source description by looking up type entries.
--- @param domains nil|table<string, boolean>
--- @return nil|string
function CharacterFeature.FindDescriptionFromDomainMap(domains)
	if domains == nil then
		return nil
	end

	for k,v in pairs(domains) do
		local colon = string.find(k, ":")
		if colon ~= nil then
			local typeName = string.sub(k, 1, colon-1)
			local id = string.sub(k, colon+1)
			if typeName == "race" then
				local tbl = dmhub.GetTable('races')
				if tbl[id] ~= nil then
					return string.format("%s trait", tbl[id].name)
				end
			elseif typeName == "item" then
				local tbl = dmhub.GetTable('tbl_Gear')
				if tbl[id] ~= nil then
					return string.format("%s", tbl[id].name)
				end
			elseif typeName == "CharacterOngoingEffect" then
				local tbl = dmhub.GetTable("characterOngoingEffects")
				if tbl[id] ~= nil then
					return string.format("%s status effect", tbl[id].name)
				end
			elseif typeName == "CharacterCondition" then
				local tbl = dmhub.GetTable(CharacterCondition.tableName)
				if tbl[id] ~= nil then
					return string.format("%s status effect", tbl[id].name)
				end
			end
		end
	end

	return nil
end

--- Overwrites this feature's domains with a copy of the given domains table, propagating to modifiers.
--- @param domains table<string, boolean>
function CharacterFeature:ForceDomains(domains)
	self.domains = DeepCopy(domains)
	for _,mod in ipairs(self.modifiers) do
		mod:ForceDomains(domains)
	end
end

--- Returns the feature's description text. If empty, auto-generates from modifier descriptions.
--- @return string
function CharacterFeature:GetDescription()
	if self.description == "" then
		local result = ""
		for i,modifier in ipairs(self.modifiers) do
			local desc = modifier:AutoDescribe()
			if desc ~= nil then
				if result ~= "" then
					result = result .. " "
				end

				result = result .. desc
			end
		end

		return result
	end

	return self.description
end

--- Returns the rules text for this feature (defaults to GetDescription).
--- @return string
function CharacterFeature:GetRulesText()
	return self:GetDescription()
end

--- Returns a bold-name summary string suitable for inline display.
--- @return string
function CharacterFeature:GetSummaryText()
	return string.format("<b>%s.</b>  %s", self.name, self:GetRulesText())
end

function CharacterFeature:GetDetailedSummaryText()
	local summary = self:GetSummaryText()
	local options = self:try_get("options", {})
	local traits = {}
	for _,option in ipairs(options) do
		local description = option.description or ""
		description = description:trim()
		if description and #description > 0 then
			local pointValue = ""
			if self:try_get("costsPoints", false) then
				local pointCost = option.pointsCost or 1
				pointValue = string.format(" (%d Point%s)", pointCost, pointCost ~= 1 and "s" or "")
			end
			traits[#traits+1] = string.format("* <b>%s%s:</b> %s", option.name, pointValue, description)
		end
	end
	if #traits > 0 then
		summary = string.format("%s\n\n%s", summary, table.concat(traits, "\n"))
	end
	return summary
end

CharacterFeature.ModifierStyles = {
	gui.Style{
		selectors = {'content-panel'},
		width = "90%",
		height = "90%",
		halign = 'center',
		valign = 'center',
		flow = "vertical",
	},
	gui.Style{
		selectors = {'modifiers-panel'},
		width = "100%",
		height = "auto",
		halign = "center",
		valign = "top",
		flow = "vertical",
		vpad = 8,
	},
	gui.Style{
		selectors = {'prerequisites-panel'},
		width = "90%",
		halign = 'center',
	},
	gui.Style{
		selectors = {'modifierEditorPanel'},
		bgimage = 'panels/square.png',
		bgcolor = '#00000055',
		hmargin = 4,
		vmargin = 4,
		halign = 'left',
		pad = 8,
		borderWidth = 2,
		borderColor = '#ffffff88',

		width = "90%",
		height = "auto",
		flow = "vertical",
	},
	gui.Style{
		selectors = {'modifierHeadingLabel'},
		fontSize = 22,
		bold = true,
		halign = 'left',
		textAlignment = 'left',
		color = 'white',
		width = "80%",
		height = 26,
	},
	gui.Style{
		selectors = {'formPanel'},
		width = "auto",
		height = "auto",
		minHeight = 40,
		flow = "horizontal",
		pad = 4,
	},
	gui.Style{
		selectors = {'formLabel'},
		fontSize = 16,
		color = 'white',
		width = 120,
		height = 'auto',
		valign = 'center',
	},
	gui.Style{
		selectors = {'form-heading'},
		fontSize = 18,
		color = 'white',
		width = 'auto',
		height = 'auto',
		valign = 'center',
	},
	gui.Style{
		selectors = {'form-input'},
		bgcolor = 'black',
		priority = 10,
		fontSize = 16,
		width = 300,
		valign = 'center',
		height = 22,
	},
	gui.Style{
		selectors = {'dropdown-option'},
		fontSize = 16,
		priority = 20,
	},
	gui.Style{
		selectors = {'behavior-panel'},
		width = 'auto',
		height = 'auto',
		halign = "left",
		flow = 'vertical',
	},
	gui.Style{
		selectors = {'form-usage-level-editor'},
		width = 'auto',
		height = 'auto',
		flow = 'vertical',
	},
}

--- Creates the full editor UI panel for this feature.
--- @param editorPanelOptions nil|table Options controlling panel behaviour (e.g. noscroll).
--- @return Panel
function CharacterFeature:EditorPanel(editorPanelOptions)
	editorPanelOptions = editorPanelOptions or {}

	local noscroll = editorPanelOptions.noscroll
	editorPanelOptions.noscroll = nil

	local modifiersPanel
	local contentPanel
	local prerequisitesPanel = nil

	local optionsCollapseDescription = nil
	if editorPanelOptions.collapseDescription then
		optionsCollapseDescription = "collapsed"
	end

	editorPanelOptions.collapseDescription = nil

	-- Themed vs. classic path. Gated on the same classicAbilityEditor opt-out
	-- toggle used by the sectioned Ability Editor so both editors feel
	-- cohesive. rawget guards against load order where CharacterFeature
	-- might be touched before AbilityEditor is present.
	local abilityEditor = rawget(_G, "AbilityEditor")
	local themed = abilityEditor ~= nil
		and dmhub.GetSettingValue("classicAbilityEditor") ~= true
	local themeColors = themed and abilityEditor.COLORS or nil

	-- Stacked-label form row helper (label above, control below). In classic
	-- mode we defer to the existing formPanel/formLabel markup so unchanged
	-- styles render the same as before.
	local function makeFormRow(labelText, inputElement, extraRowClass)
		if themed then
			return gui.Panel{
				classes = {"ds-field-row", extraRowClass, optionsCollapseDescription},
				children = {
					gui.Label{
						classes = {"ds-field-label"},
						text = labelText,
					},
					inputElement,
				},
			}
		end
		return gui.Panel{
			classes = {"formPanel", extraRowClass, optionsCollapseDescription},
			gui.Label{
				text = labelText,
				classes = {"formLabel"},
			},
			inputElement,
		}
	end

	modifiersPanel = gui.Panel{
		classes = "modifiers-panel",

		create = function(element)
			element:FireEvent('refreshModifiers')
		end,

		refreshModifiers = function(element)
			local children = {}

			for j,mod in ipairs(self.modifiers) do

				local behaviorPanel = gui.Panel{
					classes = {'behavior-panel'},

					events = {
						create = function(element)
							local typeInfo = CharacterModifier.TypeInfo[mod.behavior] or {}
							local createEditor = typeInfo.createEditor
							if createEditor ~= nil then
								createEditor(mod, element)
							end
						end,

						refreshModifier = function(element)
							contentPanel:FireEventTree("modifiersChanged")
						end,
					}
				}

				local behaviorText = nil
				if CharacterModifier.TypesById[mod.behavior] ~= nil then
					behaviorText = CharacterModifier.TypesById[mod.behavior].text
				else
					behaviorText = string.format("Unknown Behavior Type: %s", mod.behavior)
				end


				children[#children+1] = gui.Panel{
					classes = {'modifierEditorPanel'},
					gui.Label{
						classes = {'modifierHeadingLabel'},
						text = behaviorText,
						rightClick = function(element)
							element.popup = gui.ContextMenu{
								entries = {
									{
										text = "Copy",
										click = function()
											dmhub.CopyToInternalClipboard(mod)
											element.popup = nil
										end,
									}
								}
							}

						end,
						gui.DeleteItemButton{
							classes = {cond(mod:try_get("deletable") == false, "hidden")},
							floating = true,
							halign = 'right',
							valign = 'center',
                            requireConfirm = true,
							click = function(element)
								table.remove(self.modifiers, j)
								modifiersPanel:FireEvent('refreshModifiers')
							end,
						}
					},

					behaviorPanel,
				}
			end

			-- Dispatcher for a chosen modifier type id. Used by both the classic
			-- dropdown (change) and the themed picker (onAdd). The special
			-- "CLIPBOARD" id pastes the internal clipboard entry.
			local function addModifierById(typeId)
				if typeId == nil or typeId == 'none' then return end

				if typeId == 'CLIPBOARD' then
					local clipboardItem = dmhub.GetInternalClipboard()
					if clipboardItem ~= nil and clipboardItem.typeName == 'CharacterModifier' then
						local modifier = DeepCopy(clipboardItem)
						DeepReplaceGuids(modifier)
						local modifiers = self:get_or_add("modifiers", {})
						modifiers[#modifiers+1] = modifier
						modifiersPanel:FireEvent('refreshModifiers')
					elseif clipboardItem ~= nil and clipboardItem.typeName == "ActivatedAbility" then
						local ability = DeepCopy(clipboardItem)
						DeepReplaceGuids(ability)
						local modifier = CharacterModifier.new{
							guid = dmhub.GenerateGuid(),
							name = ability.name,
							description = "",
							behavior = "activated",
							activatedAbility = ability,
						}
						local modifiers = self:get_or_add("modifiers", {})
						modifiers[#modifiers+1] = modifier
						modifiersPanel:FireEvent('refreshModifiers')
					end
					return
				end

				local domains = nil
				if self:has_key("domains") then
					domains = DeepCopy(self.domains)
				end
				local modifier = CharacterModifier.new{
					guid = dmhub.GenerateGuid(),
					sourceguid = self.guid,
					name = self.name,
					source = self.source,
					description = self.description,
					behavior = typeId,
					domains = domains,
				}
				local typeInfo = CharacterModifier.TypeInfo[modifier.behavior] or {}
				if typeInfo.init then
					typeInfo.init(modifier)
				end

				local modifiers = self:get_or_add("modifiers", {})
				modifiers[#modifiers+1] = modifier

				modifiersPanel:FireEvent('refreshModifiers')
			end

			if themed and type(abilityEditor.OpenModifierPicker) == "function" then
				children[#children+1] = gui.Button{
					text = "+ Add Modifier",
					fontSize = 16,
					width = 180,
					height = 34,
					halign = "left",
					vmargin = 8,
					click = function(element)
						abilityEditor.OpenModifierPicker(self, addModifierById)
					end,
				}
			else
				local options = DeepCopy(CharacterModifier.Types)
				options[1].text = 'Add Modifier...'
				table.sort(options, function(a, b)
					if a.id == "none" then
						return true
					end
					if b.id == "none" then
						return false
					end
					return a.text < b.text
				end)

				options[#options+1] = {
					hidden = function()
						local clipboardItem = dmhub.GetInternalClipboard()
						return clipboardItem == nil or (clipboardItem.typeName ~= 'CharacterModifier' and clipboardItem.typeName ~= "ActivatedAbility")
					end,
					id = 'CLIPBOARD',
					text = function()
						local clipboardItem = dmhub.GetInternalClipboard()
						if clipboardItem ~= nil and (clipboardItem.typeName == 'CharacterModifier' or clipboardItem.typeName == "ActivatedAbility") then
							return string.format("Paste %s", clipboardItem.name)
						end
						return 'PASTE'
					end,
				}

				children[#children+1] = gui.Dropdown{
					selfStyle = {
						height = 30,
						width = 260,
						fontSize = 16,
						halign = "left",
					},

					dropdownHeight = 240,

					options = options,
					idChosen = 'none',
					hasSearch = true,

					change = function(element)
						local chosen = element.idChosen
						if chosen == 'none' then return end
						addModifierById(chosen)
					end
				}
			end

			element.children = children
		end,
	}


	if self.canHavePrerequisites then
		local dropdown = gui.Dropdown{
			height = 30,
			width = 220,
			fontSize = 14,
			halign = "left",

			idChosen = "none",
			options = CharacterPrerequisite.options, 
			change = function(element)
				if element.idChosen ~= 'none' then
					self:get_or_add("prerequisites", {})
					self.prerequisites[#self.prerequisites+1] = CharacterPrerequisite.Create{
						type = element.idChosen,
					}
					contentPanel:FireEvent('modifierRefreshed')

					element.idChosen = 'none'
					prerequisitesPanel:FireEvent("create")
				end
			end,
		}

		prerequisitesPanel = gui.Panel{
			classes = "prerequisites-panel",

			height = 'auto',
			flow = "vertical",

			children = {dropdown},

			create = function(element)
				local children = {dropdown}

				for i,pre in ipairs(self:try_get("prerequisites", {})) do
					children[#children+1] = pre:Editor{
						change = function(element)
							contentPanel:FireEvent('modifierRefreshed')
						end,
						delete = function(element)
							table.remove(self.prerequisites, i)
							contentPanel:FireEvent('modifierRefreshed')
							prerequisitesPanel:FireEvent('create')
						end
					}
				end

				element.children = children
			end,
		}
	end

	local baselineValue = DeepCopy(self)

	-- Build the effective styles list: themed editors splice the shared DS
	-- widget + form-row pattern on top of the base ModifierStyles so
	-- formPanel/formLabel/formInput descendants inside per-modifier editors
	-- still render; classic editors leave ModifierStyles untouched.
	local effectiveStyles = CharacterFeature.ModifierStyles
	if themed then
		effectiveStyles = {}
		for _, rule in ipairs(CharacterFeature.ModifierStyles) do
			effectiveStyles[#effectiveStyles+1] = rule
		end
		-- Make any surviving classic formPanel rows render with the
		-- stacked pattern too (per-modifier sub-editors still emit them).
		effectiveStyles[#effectiveStyles+1] = gui.Style{
			selectors = {"formPanel"},
			priority = 6,
			width = "100%",
			halign = "left",
			flow = "vertical",
		}
		effectiveStyles[#effectiveStyles+1] = gui.Style{
			selectors = {"formLabel"},
			priority = 6,
			halign = "left",
			width = "100%",
			minWidth = 0,
			fontSize = 14,
			bold = true,
			color = themeColors.CREAM_BRIGHT,
			textAlignment = "left",
			bmargin = 4,
		}
		-- Dark themed background on the feature panel itself.
		effectiveStyles[#effectiveStyles+1] = gui.Style{
			selectors = {"content-panel"},
			priority = 6,
			bgcolor = themeColors.BG,
			bgimage = "panels/square.png",
			hpad = 16,
			vpad = 12,
			borderBox = true,
		}
		effectiveStyles[#effectiveStyles+1] = gui.Style{
			selectors = {"modifierEditorPanel"},
			priority = 6,
			bgcolor = themeColors.PANEL_BG,
			borderColor = themeColors.GOLD,
			borderWidth = 1,
		}
		effectiveStyles[#effectiveStyles+1] = gui.Style{
			selectors = {"modifierHeadingLabel"},
			priority = 6,
			color = themeColors.GOLD_BRIGHT,
		}
		-- Splice in shared widget + form-row pattern.
		for _, rule in ipairs(abilityEditor.GetSharedWidgetStyles(themeColors)) do
			effectiveStyles[#effectiveStyles+1] = rule
		end
		for _, rule in ipairs(abilityEditor.GetSharedFormStyles(themeColors)) do
			effectiveStyles[#effectiveStyles+1] = rule
		end
	end

	local nameInput = gui.Input{
		text = self.name,
		classes = {"input", "form-input"},
		events = {
			change = function(element)
				self.name = element.text
				for i,mod in ipairs(self.modifiers) do
					mod.name = self.name
				end
			end,
		},
	}

	local sourceInput = gui.Input{
		text = self.source,
		classes = {"input", "form-input"},
		events = {
			change = function(element)
				self.source = element.text
				for i,mod in ipairs(self.modifiers) do
					mod.source = self.source
				end
			end,
		},
	}

	local implementationWidget = gui.ImplementationStatusPanel{
		value = self:try_get("implementation", 1),
		change = function(element)
			self.implementation = element.value
		end,
	}

	local descriptionInput = gui.Input{
		text = self:GetDescription(),
		multiline = true,
		classes = {"input", "form-input"},
		characterLimit = 8192,
		selfStyle = {
			textAlignment = "topleft",
			height = "auto",
			minHeight = 40,
			width = themed and nil or 600,
		},
		events = {
			change = function(element)
				self.description = element.text
				for i,mod in ipairs(self.modifiers) do
					mod.description = self.description
				end
			end,
			modifiersChanged = function(element)
				element.text = self:GetDescription()
			end,
		},
	}

	local args = {
		id = "featureScroll",
		classes = 'content-panel',
		vscroll = not noscroll,

		width = "90%",
        height = cond(noscroll, "auto", "90%"),


		styles = effectiveStyles,

		thinkTime = 0.2,

		think = function(element)
			if not dmhub.DeepEqual(self, baselineValue) then
				baselineValue = DeepCopy(self)
				element:FireEvent("modifierRefreshed")
			end
		end,

		makeFormRow("Name:", nameInput, "namePanel"),
		makeFormRow("Source:", sourceInput, "sourcePanel"),
		makeFormRow("Implementation:", implementationWidget),
		makeFormRow("Description:", descriptionInput, "descriptionPanel"),

		prerequisitesPanel,
		modifiersPanel,
	}

	if noscroll then
		args.styles = DeepCopy(args.styles)
		args.styles[1].height = "auto"
	end

	for k,v in pairs(editorPanelOptions) do
		args[k] = v
	end

	contentPanel = gui.Panel(args)

	return contentPanel

end

function CharacterFeature:CharacterUniqueID()
	--a repeated feature is an upgrade.
	return self.name
end

function CharacterFeature:PopupEditor()

	local backup = DeepCopy(self)

	local resultPanel

	-- Match the feature panel's themed/classic split so the outer frame is
	-- visually cohesive with the inner editor. Gated on the same
	-- classicAbilityEditor opt-out as the sectioned Ability Editor.
	local abilityEditor = rawget(_G, "AbilityEditor")
	local themed = abilityEditor ~= nil
		and dmhub.GetSettingValue("classicAbilityEditor") ~= true
	local c = themed and abilityEditor.COLORS or nil

	local contentPanel = self:EditorPanel{
		modifierRefreshed = function(element)
			if resultPanel.data.notifyElement ~= nil then
				resultPanel.data.notifyElement:FireEvent('refreshModifier')
			end
		end
	}

	local popupStyles = {
		Styles.Panel,
		Styles.Default,
		Styles.Form,
		{
			selectors = {'popup-editor'},
			width = 1000,
			height = 800,
			bgcolor = themed and c.BG or 'white',
			halign = 'center',
			valign = 'center',
		},
	}

	if themed then
		popupStyles[#popupStyles+1] = gui.Style{
			selectors = {"framedPanel"},
			priority = 3,
			bgcolor = c.BG,
			borderColor = c.GOLD,
			gradient = nil,
		}
		popupStyles[#popupStyles+1] = gui.Style{
			selectors = {"label", "button", "prettyButton"},
			priority = 3,
			bgcolor = c.PANEL_BG,
			bgimage = "panels/square.png",
			color = c.CREAM_BRIGHT,
			borderColor = c.GOLD,
			borderWidth = 2,
			cornerRadius = 4,
			fontFace = "Berling",
			fontSize = 20,
			fontWeight = "bold",
			hmargin = 8,
			vmargin = 8,
			textAlignment = "center",
		}
		popupStyles[#popupStyles+1] = gui.Style{
			selectors = {"label", "button", "prettyButton", "hover"},
			priority = 3,
			bgcolor = c.GOLD_DIM,
			color = c.BG,
			borderColor = c.CREAM_BRIGHT,
		}
		popupStyles[#popupStyles+1] = gui.Style{
			selectors = {"label", "button", "prettyButton", "press"},
			priority = 3,
			bgcolor = c.GOLD,
			color = c.BG,
			brightness = 0.85,
		}
	end

	resultPanel = gui.Panel{
		id = "CharacterFeaturePopupEditor",
		classes = {'popup-editor', "framedPanel"},
		floating = true,
		flow = "vertical",

		contentPanel,

		gui.Panel{
			width = "90%",
			height = 56,
			flow = "horizontal",
			halign = "center",

			gui.PrettyButton{
				width = 160,
				height = 50,
				halign = "center",
				valign = "center",
				fontSize = 22,
				text = "Confirm",
				click = function(element)
					contentPanel:FireEvent('modifierRefreshed')
					resultPanel:DestroySelf()
				end,
			},

			gui.PrettyButton{
				width = 160,
				height = 50,
				halign = "center",
				valign = "center",
				fontSize = 22,
				text = "Cancel",
				escapeActivates = true,
				escapePriority = EscapePriority.EXIT_DIALOG,
				click = function(element)

					--cancel restores from backup.
					local keys = {}
					for k,v in pairs(self) do
						keys[#keys+1] = k
					end

					for i,k in ipairs(keys) do
						self[k] = nil
					end

					for k,v in pairs(backup) do
						self[k] = v
					end

					contentPanel:FireEvent('refreshModifier')

					resultPanel:DestroySelf()
				end,
			},

		},

		styles = popupStyles,
		data = {
			--notifies this element of 'refreshModifier' on change.
			notifyElement = nil,
		},

	}

	return resultPanel
end

function CharacterFeature.ListEditor(document, fieldName, options)

	local dialog = options.dialog
	local notify = options.notify

	local CalculateChildren
	local resultPanel

	local createOptions = options.createOptions or {}
	options.createOptions = {}

	local addButton = gui.Button{
		text = options.addText or 'Add Custom Feature',
		style = {
			width = 160,
			height = 30,
			bgcolor = 'white',
			fontSize = 16,
			halign = 'left',
		},
		events = {
			click = function(element)
				local items = document:try_get(fieldName, {})
				items[#items+1] = CharacterFeature.Create(createOptions)
				document[fieldName] = items
				resultPanel.children = CalculateChildren()
				resultPanel:FireEvent("refreshModifier")
			end,
		},
	}

	local pasteButton = gui.Button{
		text = "Paste Feature",
		style = {
			width = 160,
			height = 30,
			bgcolor = 'white',
			fontSize = 16,
			halign = 'left',
		},

		create = function(element)
			local clipboardItem = dmhub.GetInternalClipboard()
			element:SetClass("hidden", clipboardItem == nil or (clipboardItem.typeName ~= "CharacterFeature" and clipboardItem.typeName ~= "ActivatedAbility"))
		end,
		click = function(element)
			local clipboardItem = dmhub.GetInternalClipboard()
			if clipboardItem ~= nil and clipboardItem.typeName == "CharacterFeature" then
				clipboardItem = DeepCopy(clipboardItem)

                DeepReplaceGuids(clipboardItem)

				local items = document:try_get(fieldName, {})
				items[#items+1] = clipboardItem
				document[fieldName] = items
				resultPanel.children = CalculateChildren()
				resultPanel:FireEvent("refreshModifier")
            elseif clipboardItem ~= nil and clipboardItem.typeName == "ActivatedAbility" then

                local ability = DeepCopy(clipboardItem)
                DeepReplaceGuids(ability)
                local modifier = CharacterModifier.new{
                    guid = dmhub.GenerateGuid(),
                    name = ability.name,
                    description = "",
                    behavior = "activated",
                    activatedAbility = ability,
                }

                local feature = CharacterFeature.Create{
                    name = ability.name,
                    modifiers = { modifier },
                }

				local items = document:try_get(fieldName, {})
				items[#items+1] = feature
				document[fieldName] = items
				resultPanel.children = CalculateChildren()
				resultPanel:FireEvent("refreshModifier")
			end
		end,
	}

	CalculateChildren = function()
		local children = {}
		local items = document:try_get(fieldName, {})
		for i,item in ipairs(items) do
			local info = item
			local itemIndex = i
			children[#children+1] = gui.Panel{
				classes = {'modifier-summary-panel'},
				children = {
					gui.Label{
						classes = {'modifier-summary-label'},
						text = StringInterpolateGoblinScript(item:GetSummaryText(), document),
                        markdown = true,
					},

					gui.Button{
						text = 'Copy',
						hmargin = 6,
						style = {
							width = 60,
							height = 24,
							fontSize = 14
						},
						events = {
							click = function(element)
								dmhub.CopyToInternalClipboard(info)
                                gui.Tooltip("Copied to clipboard!")(element)

								pasteButton:FireEvent("create")
							end
						},
					},

					gui.Button{
						text = 'Edit',
						hmargin = 6,
						style = {
							width = 60,
							height = 24,
							fontSize = 14
						},
						events = {
							click = function(element)
								local editor = info:PopupEditor()
								editor.data.notifyElement = resultPanel
								dialog:AddChild(editor)
								--resultPanel.popup = info:PopupEditor()
							end
						},
					},

					gui.Button{
						text = 'Delete',
						hmargin = 4,
						style = {
							width = 60,
							height = 24,
							fontSize = 14
						},
						events = {
							click = function(element)
								local items = document:try_get(fieldName, {})
								table.remove(items, itemIndex)
								document[fieldName] = items
								resultPanel.children = CalculateChildren()
								resultPanel:FireEvent("refreshModifier")
							end,
						},
					},
				}
			}
		end

		children[#children+1] = gui.Panel{
			width = "auto",
			height = "auto",
			flow = "horizontal",
			addButton,
			pasteButton,
		}
		return children
	end

	resultPanel = gui.Panel{
		classes = {'modifier-list-editor'},
		styles = {
			{
				selectors = {'modifier-list-editor'},
				width = '100%',
				height = 'auto',
				flow = 'vertical',
			},
			{
				selectors = {'modifier-summary-panel'},
				width = '100%',
				height = 'auto',
				flow = 'horizontal',
				pad = 0,
				hmargin = 0,
				vmargin = 2,
			},
			{
				selectors = {'modifier-summary-label'},
				width = '100%-200',
				height = 'auto',
				fontSize = 14,
			},
		},

		events = {
			refreshModifier = function(element)
				--element.children = CalculateChildren()
				element.root:FireEventTree("refresh")
				if notify ~= nil then
					notify:FireEvent("refreshAll")
				else
					element.root:FireEvent("refreshAll")
				end
			end,
			refresh = function(element)
				--this is called within the character sheet etc. Try to be more efficient about this at some point?
				element.children = CalculateChildren()
			end,
		},
		children = CalculateChildren(),
	}

	return resultPanel
	
end

--- Returns available choices for the given option slot, or nil if no choice is needed.
--- @param numOption number 1-based index of the option.
--- @param existingChoices table Current choices already made.
--- @return nil|table
function CharacterFeature:Choices(numOption, existingChoices)
	return nil
end

--- Returns how many choices this feature requires from the given creature.
--- @param creature creature
--- @return number
function CharacterFeature:NumChoices(creature)
	return 0
end

--- Appends this feature to the result list of available choices.
--- @param choices table Current choices context.
--- @param result CharacterFeature[]
function CharacterFeature:FillChoice(choices, result)
	result[#result+1] = self
end

--- Recursively appends all features (including sub-features) to result.
--- @param choices table
--- @param result CharacterFeature[]
function CharacterFeature:FillFeaturesRecursive(choices, result)
	result[#result+1] = self
end

--- Calls fn on this feature and all nested features recursively.
--- @param fn fun(feature: CharacterFeature): nil
function CharacterFeature:VisitRecursive(fn)
	fn(self)
end

--- Creates a custom dropdown panel for this feature, or returns nil for the default.
--- @return nil|Panel
function CharacterFeature:CreateDropdownPanel()
    return nil
end

--- Returns true if this feature type provides a custom dropdown panel.
--- @return boolean
function CharacterFeature:HasCustomDropdownPanel()
    return false
end
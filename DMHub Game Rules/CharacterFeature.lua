local mod = dmhub.GetModLoading()

--This file implements a CharacterFeature. Races, Classes, Feats, Backgrounds, etc are primarily collections
--of CharacterFeatures that are bestowed on Characters. A CharacterFeature is mostly made up of a list of
--modifiers that are applied to the creature that has the feature. It is most typical for a CharacterFeature
--to contain just one modifier.

--CharacterFeature:
--  guid: string
--  name: string
--  source: string
--  canHavePrerequisites: bool 
--  prerequisites: {CharacterPrerequisite}|nil
--  description: string
--  modifiers: {CharacterModifier}
--  domains: {key -> true} map of domains which this feature knows about. e.g. Class:Ranger
RegisterGameType("CharacterFeature")

CharacterFeature.canHavePrerequisites = false
CharacterFeature.modifiers = {}

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

function CharacterFeature:FillModifiers(creature, result, params)
    for _,mod in ipairs(self.modifiers) do
        local t = { mod = mod }
        if params ~= nil then
            for k,v in pairs(params) do
                t[k] = v
            end
        end
        result[#result+1] = t

        if mod.behavior == "routine" and creature:try_get("routineSelected") ~= mod.ability.guid then
            --routines block other modifiers on the feature unless the routine is selected.
            break
        end
    end
end

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

function CharacterFeature:Describe()
	return self.name
end

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

function CharacterFeature.SetDomain(self, domainid)
	local domains = self:get_or_add("domains", {})
	if not domains[domainid] then
		domains[domainid] = true

		for _,mod in ipairs(self:try_get("modifiers", {})) do
			mod:SetDomain(domainid)
		end
	end
end

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

function CharacterFeature:ForceDomains(domains)
	self.domains = dmhub.DeepCopy(domains)
	for _,mod in ipairs(self.modifiers) do
		mod:ForceDomains(domains)
	end
end

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

function CharacterFeature:GetRulesText()
	return self:GetDescription()
end

function CharacterFeature:GetSummaryText()
	return string.format("<b>%s.</b>  %s", self.name, self:GetRulesText())
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

			local options = dmhub.DeepCopy(CharacterModifier.Types)
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
                    if element.idChosen == 'CLIPBOARD' then
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
					elseif element.idChosen ~= 'none' then
						local domains = nil
						if self:has_key("domains") then
							domains = dmhub.DeepCopy(self.domains)
						end
						local modifier = CharacterModifier.new{
							guid = dmhub.GenerateGuid(),
							sourceguid = self.guid,
							name = self.name,
							source = self.source,
							description = self.description,
							behavior = element.idChosen,
							domains = domains,
						}
						local typeInfo = CharacterModifier.TypeInfo[modifier.behavior] or {}
						if typeInfo.init then
							--initialize our new behavior type.
							typeInfo.init(modifier)
						end

						local modifiers = self:get_or_add("modifiers", {})
						modifiers[#modifiers+1] = modifier

						modifiersPanel:FireEvent('refreshModifiers')
					end
				end
				
			}

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

	local args = {
		id = "featureScroll",
		classes = 'content-panel',
		vscroll = not noscroll,

		width = "90%",
        height = cond(noscroll, "auto", "90%"),


		styles = CharacterFeature.ModifierStyles,

		thinkTime = 0.2,

		think = function(element)
			if not dmhub.DeepEqual(self, baselineValue) then
				baselineValue = DeepCopy(self)
				element:FireEvent("modifierRefreshed")
			end
		end,
		
		gui.Panel{
			classes = {'formPanel','namePanel', optionsCollapseDescription},
			gui.Label{
				text = 'Name:',
				classes = {'formLabel'},
			},
			gui.Input{
				text = self.name,
				classes = {'input', 'form-input'},
				events = {
					change = function(element)
						self.name = element.text
						for i,mod in ipairs(self.modifiers) do
							mod.name = self.name
						end
					end,
				},
			},
		},

		gui.Panel{
			classes = {'formPanel','sourcePanel', optionsCollapseDescription},
			children = {
				gui.Label{
					text = 'Source:',
					classes = {'formLabel'},
				},
				gui.Input{
					text = self.source,
					classes = {'input', 'form-input'},
					events = {
						change = function(element)
							self.source = element.text
							for i,mod in ipairs(self.modifiers) do
								mod.source = self.source
							end
						end,
					},
				},
			}
		},

		gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				classes = "formLabel",
				text = "Implementation:",
                width = 140,
			},
			gui.ImplementationStatusPanel{
				value = self:try_get("implementation", 1),
				change = function(element)
					self.implementation = element.value
				end,
			},
		},

		gui.Panel{
			classes = {'formPanel','descriptionPanel', optionsCollapseDescription},
			children = {
				gui.Label{
					text = 'Description:',
					classes = {'formLabel'},
				},
				gui.Input{
					text = self:GetDescription(),
					multiline = true,
					classes = {'input', 'form-input'},
					selfStyle = {
						textAlignment = "topleft",
						height = 'auto',
						minHeight = 40,
						width = 600,
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
				},
			}
		},

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

	local backup = dmhub.DeepCopy(self)

	local resultPanel

	local contentPanel = self:EditorPanel{
		modifierRefreshed = function(element)
			if resultPanel.data.notifyElement ~= nil then
				resultPanel.data.notifyElement:FireEvent('refreshModifier')
			end
		end
	}

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

		styles = {
			Styles.Panel,
			Styles.Default,
			Styles.Form,
			{
				selectors = {'popup-editor'},
				width = 1000,
				height = 800,
				bgcolor = 'white',
				halign = 'center',
				valign = 'center',
			},

		},
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
						text = item:GetSummaryText(),
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

function CharacterFeature:Choices(numOption, existingChoices)
	return nil
end

function CharacterFeature:NumChoices(creature)
	return 0
end

function CharacterFeature:FillChoice(choices, result)
	result[#result+1] = self
end

function CharacterFeature:FillFeaturesRecursive(choices, result)
	result[#result+1] = self
end

function CharacterFeature:VisitRecursive(fn)
	fn(self)
end

function CharacterFeature:CreateDropdownPanel()
    return nil
end

function CharacterFeature:HasCustomDropdownPanel()
    return false
end
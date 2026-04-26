local mod = dmhub.GetModLoading()
print("CHECKPOINT:: CREATE SPELLS")

--this file implements the character spell sheet. (obtained by pressing 'm' with a character selected)

SpellRenderStyles = {
	gui.Style{
		selectors = {"create"},
		transitionTime = 0.2,
		opacity = 0,
	},
	gui.Style{
		selectors = "#spellInfo",
		width = "100%",
		height = 'auto',
		flow = 'vertical',
		halign = 'left',
		valign = 'center',
	},

	gui.Style{
		classes = {"label"},
		fontSize = 14,
		color = 'white',
		width = '100%',
		textAlignment = "left",
		height = 'auto',
		halign = 'left',

		textAlignment = 'left',
	},

	gui.Style{
		classes = {"label","#spellName"},
		fontFace = 'sellyoursoul',
		color = '#bb6666',
		fontSize = 30,
		width = 'auto',
		maxWidth = 300,
		height = 'auto',
		halign = 'left',
		valign = 'top',
		bold = true,
		wrap = true,
	},

	gui.Style{
		classes = {"subheading"},
		fontFace = 'sellyoursoul',
		color = '#bb6666',
		fontSize = 24,
		bold = true,
	},

	gui.Style{
		classes = {"label","#spellSummary"},

		italics = true,
		color = 'white',
		fontSize = 12,
		width = 'auto',
		height = 'auto',
		halign = 'left',
		valign = 'top',
	},
	gui.Style{
		classes = {"divider"},

		bgimage = 'panels/square.png',
		bgcolor = '#666666',
		halign = "left",
		width = '100%',
		height = 1,
		halign = 'center',
		valign = 'top',
		vmargin = 4,
	},
	gui.Style{
		classes = {"icon"},
		vmargin = 8,
		width = 64,
		height = 64,
		halign = "left",
	},
	gui.Style{
		classes = {"description"},
		color = 'white',
		width = '96%',
	},
}

function Spell:Render(options)
	options = options or {}

	local summary = options.summary
	options.summary = nil

	local classLabel = nil
	if self:has_key("spellcastingFeature") then
		local hasSave = self:HasSavingThrow()
		local hasAttack = self:HasAttack()

		local modifiersLabel = ""
		if hasSave and hasAttack then
			modifiersLabel = string.format(" (Attack: %d, DC: %d)", ModStr(self.spellcastingFeature.attackBonus), self.spellcastingFeature.dc)
		elseif hasSave then
			modifiersLabel = string.format(" (DC: %d)", self.spellcastingFeature.dc)
		elseif hasAttack then
			modifiersLabel = string.format(" (Attack: %d)", ModStr(self.spellcastingFeature.attackBonus))
		end


		classLabel = gui.Label{
			text = string.format("<b>%s</b>%s", self.spellcastingFeature.name, modifiersLabel),
			width = "100%",
		}
	end

	local description = self.description
	if self:try_get("modifyDescriptions") ~= nil then
		for _,desc in ipairs(self.modifyDescriptions) do
			description = string.format("%s\n<color=#a6fffe>%s</color>", description, desc)
		end
	end
	local args = {
		id = 'spellInfo',
		classes = {"tooltip"},
		styles = SpellRenderStyles,

		gui.Panel{
			flow = "horizontal",
			width = "100%",
			height = "auto",
			gui.Panel{
				width = "80%",
				height = "auto",
				flow = "vertical",
				halign = "left",
				gui.Label{
					id = "spellName",
					text = self.name,
					width = "100%",
				},
			
				gui.Label{
					id = "spellSummary",
					text = string.format("%s %s", self:DescribeLevel(), self.school),
					width = "100%",
				},

				classLabel,

				gui.Label{
					text = string.format("<b>Casting Time:</b> %s", self:DescribeCastingTime()),
					width = "100%",
				},

				gui.Label{
					text = string.format("<b>Range:</b> %s", self:DescribeRange()),
					width = "100%",
				},

				gui.Label{
					text = string.format("<b>Components:</b> %s", self:DescribeComponents()),
					width = "100%",
				},

				gui.Label{
					text = string.format("<b>Duration:</b> %s", self:DescribeDuration()),
					width = "100%",
				},

				create = function(element)

					local table = dmhub.GetTable(CustomFieldCollection.tableName) or {}

					local customFields = table["spells"]
					if customFields ~= nil then
						for k,v in pairs(customFields.fields) do
							if v.display then
								local val = v:GetValue(self)
								if val ~= nil then
									element:AddChild(gui.Label{
										text = string.format("<b>%s:</b> %s", v.name, tostring(val)),
										width = "100%",
									})
								end
							end
						end
					end
				end,
			},

			gui.Panel{
				halign = "right",
				bgimage = self:GetIcon(),
				classes = "icon",
				selfStyle = self:GetIconDisplay(),
				loadingImage = function(element)
					element:AddChild(gui.LoadingIndicator{})
				end,
			},
		},
		
		gui.Panel{
			classes = "divider",
			vmargin = 12,
		},

		gui.Label{
			text = description,
			classes = "description",
		},
	}
	printf("JSON:: TOOLTIP FOR SPELLS: %s / %s", json(description), json(self))

	for k,op in pairs(options) do
		args[k] = op
	end

	return gui.Panel(args)
	
end


function CreateAbilityTooltip(spell, options)
	return CreateCompendiumItemTooltip(spell, options)
end

local NumRows = 6
local NumCols = 4
local SlotDim = 72

local CreateSpellPanel = function(dmhud, options)
	local dialogPanel = nil
	local spell = nil
	local resultPanel

	local canDelete = options.canDelete
	options.canDelete = nil

	local dragOnto = options.dragOnto
	options.dragOnto = nil

	local iconPanel = gui.Panel{
		classes = "spellIcon",
		draggable = options.draggable,
		canDragOnto = function(element, target)
			return target ~= element and target:HasClass(dragOnto or 'spells-drag-target') and (target.data.receiveDrags == nil or target.data.receiveDrags())
		end,
		drag = function(element, target)
			if target == nil then
				return
			end
			target:FireEvent('addSpell', spell)
		end,
	}

	options.draggable = nil

	local highlightPanel = gui.Panel{
		bgimage = 'panels/InventorySlot_Focus.png',
		interactable = false,
		classes = {'highlightPanel', 'hidden'},
	}

	local args = {
		classes = {"spellPanel", "framedPanel"},

		styles = Styles.Panel,

		data = {
			receiveDrags = function()
				return spell ~= nil
			end,
			GetSpell = function()
				return spell
			end,
		},

		iconPanel,
		highlightPanel,

		initDialog = function(element, dialog)
			dialogPanel = dialog
		end,

		refreshSpell = function(element, s)
			spell = s
			iconPanel:SetClass('hidden', false)
			iconPanel.bgimage = spell:GetIcon()
			iconPanel.selfStyle = spell:GetIconDisplay()
		end,

		clearSpell = function(element)
			spell = nil
			iconPanel:SetClass('hidden', true)
		end,

		rightClick = function(element)
			if spell == nil then
				return
			end

			local entries = {
				{
					text = "Edit Spell",
					click = function()
						element.popup = nil

						dmhud:ShowAddSpellDialog{
							spell = spell,
							changeSpell = function(element)
								dialogPanel:FireEventTree('refreshSpells')
							end,
						}
					end,
				},
			}

			if canDelete then
				entries[#entries+1] = {
					text = "Remove Spell",
					click = function()
						element.popup = nil
						resultPanel:FireEvent("deleteSpell", spell)
					end,
				}
			end

			element.popup = gui.ContextMenu{
				entries = entries,
			}
		end,

		hover = function(element)
			if spell ~= nil then
				element.tooltipParent = dialogPanel
				element.tooltip = CreateAbilityTooltip(spell, {})
				highlightPanel:SetClass('hidden', false)
			end
		end,

		dehover = function(element)
			highlightPanel:SetClass('hidden', true)
		end,

	}

	for k,option in pairs(options) do
		args[k] = option
	end

	resultPanel = gui.Panel(args)

	return resultPanel
end

local SpellsDialogStyles = {
	gui.Style{
		classes = {"spellsDialog"},
		bgimage = 'panels/InventorySlot_Background.png',
		bgcolor = 'white',
		width = 350,
		height = 680,
		halign = 'center',
		valign = 'center',
		bgcolor = 'white',
		flow = 'vertical',
	},
	gui.Style{
		classes = {"spellsTitle"},
		fontSize = 28,
		halign = 'center',
		valign = 'top',
		margin = 16,
		width = 'auto',
		height = 'auto',
		color = 'white',
	},

	gui.Style{
		selectors = {'highlightPanel'},
		bgcolor = 'white',
		width = 90,
		height = 90,
		halign = 'center',
		valign = 'center',
	},
	gui.Style{
		selectors = {'highlightPanel', 'parent:drag-target'},
		hidden = 0,
		opacity = 0.5,
	},
	gui.Style{
		selectors = {'highlightPanel', 'parent:drag-target-hover'},
		hidden = 0,
		opacity = 1,
	},



	gui.Style{
		classes = "spellsContentPanel",
		width = SlotDim*NumCols,
		height = SlotDim*NumRows,
		wrap = true,
		flow = "horizontal",
		halign = "center",
		valign = "center",
	},
	gui.Style{
		classes = {"spellPanel"},
		bgimage = 'panels/InventorySlot_Background.png',
		width = 72,
		height = 72,
		bgcolor = 'white',
	},
	gui.Style{
		classes = {"spellIcon"},
		width = 52,
		height = 52,
		halign = 'center',
		valign = 'center',
		bgcolor = 'white',
	},
}

--no longer used?
--[[
function GameHud.CreateSpellsDialog(self, options)
	local token = nil
	options = options or {}

	local resultPanel
	local contentPanel = gui.Panel{
		id = "ContentPanel",
		classes = {"spellsContentPanel"},
	}

	local dragTarget = gui.Panel{
		classes = {'spells-drag-target'},
		bgimage = 'panels/InventorySlot_Focus.png',
		dragTarget = true,
		interactable = false,
		bgcolor = 'white',
		width = "auto",
		height = "auto",
		pad = 24,
		halign = "center",
		valign = "center",
		bgslice = 32,
		floating = true,

		addSpell = function(element, spell)
			if token == nil or token.valid == false or token.properties == nil then
				return
			end

			dmhub.Debug('ADD SPELL: ' .. spell.id)

			token:BeginChanges()
			token.properties:AddPreparedSpell(spell.id)
			token:CompleteChanges("Prepared spell")
			resultPanel:FireEvent("refreshGame")
		end,

		styles = {
			{
				opacity = 0.0,
				selectors = 'spells-drag-target',
			},
			{
				opacity = 0.5,
				transitionTime = 0.2,
				selectors = 'drag-target',
			},
			{
				opacity = 1.0,
				transitionTime = 0.2,
				selectors = 'drag-target-hover',
			},
		},

		contentPanel,
	}

	local spellPanels = {}
	for i=1,NumRows*NumCols do
		spellPanels[#spellPanels+1] = CreateSpellPanel(self, {
			dragOnto = "spellPanel",
			dragTarget = true,
			canDelete = true,
			draggable = true,
			addSpell = function(element, otherspell)
				local spell = element.data.GetSpell()
				if token == nil or token.valid == false or token.properties == nil or spell == nil or otherspell == nil then
					return
				end

				token:BeginChanges()
				token.properties:SwitchPreparedSpellOrder(spell.id, otherspell.id)
				token:CompleteChanges("Reorder prepared spells")
				resultPanel:FireEvent("refreshGame")
			end,
			deleteSpell = function(element, spell)
				if token == nil or (not token.valid) or token.properties == nil then
					return
				end

				token:BeginChanges()
				token.properties:RemovePreparedSpell(spell.id)
				token:CompleteChanges("Remove prepared spell")
				resultPanel:FireEvent("refreshGame")
			end,
		})
	end
	contentPanel.children = spellPanels

	local RefreshSpells = function()
		if token == nil or (not token.valid) or token.properties == nil then
			for i,panel in ipairs(spellPanels) do
				panel:FireEvent('clearSpell')
			end
			return
		end

		local spells = token.properties:ListPreparedSpells()
		for i,panel in ipairs(spellPanels) do
			local spell = spells[i]
			if spell ~= nil then
				panel:FireEvent('refreshSpell', spell)
			else
				panel:FireEvent('clearSpell')
			end
		end
	end

	resultPanel = gui.Panel{
		id = "SpellsDialog",
		classes = {"hidden", "spellsDialog", "framedPanel"},
		styles = {
			Styles.Panel,
			SpellsDialogStyles,
		},

		captureEscape = true,
		escapePriority = EscapePriority.EXIT_INVENTORY_DIALOG,

		gui.CloseButton{
			valign = 'top',
			halign = 'right',
			floating = true,
			click = function(element)
				resultPanel:FireEvent('close')
			end,
		},

		gui.Label{
			classes = {"spellsTitle"},
			text = options.title or "Spells",
		},

		dragTarget,

		refreshGame = function(element)
			RefreshSpells()
		end,

		escape = function(element)
			element:FireEvent('close')
		end,

		open = function(element, tok, options)
			token = tok
			element.monitorGame = {"/assets/objectTables/Spells", tok.dataPath},
			element:SetClass('hidden', false)
			self.spellsLibraryDialog:FireEvent('open')
			resultPanel:FireEvent("refreshGame")
		end,

		close = function(element)
			element.monitorGame = nil
			element:SetClass('hidden', true)
			self.spellsLibraryDialog:FireEvent('close')
		end,
	}

	resultPanel:FireEventTree("initDialog", resultPanel)

	return resultPanel
end
]]

--no longer used?
--[[
function GameHud.CreateSpellsLibraryDialog(self)

	local npage = 1
	local searchString = ""

	local spellsTable = {}
	local filteredSpells = {}
	local spellPanels = {}

	local itemsPerPage = NumRows*NumCols
	local NumPages = function()
		local numItems = #filteredSpells
		if numItems == 0 then
			return 1
		end
		return math.ceil(numItems / itemsPerPage)
	end

	local contentPanel = gui.Panel{
		id = "ContentPanel",
		classes = {"spellsContentPanel"},

		refreshSpells = function(element)
			spellsTable = dmhub.SearchTable("Spells", searchString, {fields = {'name'}}) or {}
			filteredSpells = {}

			for k,s in pairs(spellsTable) do
				filteredSpells[#filteredSpells+1] = s
			end

			table.sort(filteredSpells, function(a, b)
				return a.name < b.name
			end)

			if npage < 1 then
				npage = 1
			end

			if npage > NumPages() then
				npage = NumPages()
			end

			for i,panel in ipairs(spellPanels) do
				local index = (npage-1)*itemsPerPage + i
				if index <= #filteredSpells then
					panel:FireEvent('refreshSpell', filteredSpells[index])
				else
					panel:FireEvent('clearSpell')
				end
			end
		end,
	}

	for i=1,NumRows*NumCols do
		spellPanels[#spellPanels+1] = CreateSpellPanel(self, {
			draggable = true,
		})
	end
	contentPanel.children = spellPanels

	local resultPanel

	resultPanel = gui.Panel{
		id = "SpellsLibraryDialog",
		classes = {"hidden", "spellsDialog", "framedPanel"},
		x = 500,
		styles = {
			Styles.Panel,
			SpellsDialogStyles,
		},

		captureEscape = true,
		escapePriority = EscapePriority.EXIT_INVENTORY_DIALOG,

		gui.Label{
			classes = {"spellsTitle"},
			text = "Spells Library",
		},

		gui.Input{
			id = "searchInput",
			placeholderText = 'Search...',
			halign = "center",
			fontSize = 14,
			bgimage = "panels/square.png",
			bgcolor = "black",
			borderWidth = 1,
			borderColor = "white",
			height = 18,
			width = 120,
			editlag = 0.25,
			edit = function(element)
				if element.text ~= searchString then
					searchString = element.text
					contentPanel:FireEvent("refreshSpells")
				end
			end,
			change = function(element)
				if element.text ~= searchString then
					searchString = element.text
					contentPanel:FireEvent("refreshSpells")
				end
			end,
		},

		contentPanel,

					gui.Panel{
						id = 'pagingPanel',
						styles = {
							{
								width = '100%',
								height = 32,
								flow = 'horizontal',
							},

							{
								selectors = {'pagingArrow'},
								height = '100%',
								width = '50% height',
								halign = 'left',
								hmargin = 40,
								bgcolor = 'white',
							},
							{
								selectors = {'hover', 'pagingArrow'},
								brightness = 2,
							},
							{
								selectors = {'press', 'pagingArrow'},
								brightness = 0.7,
							},
						},

						children = {
							gui.Panel{
								bgimage = 'panels/InventoryArrow.png',
								className = 'pagingArrow',

								events = {
									refreshSpells = function(element)
										element:SetClass('hidden', npage == 1)
									end,

									click = function(element)
										npage = npage - 1
										resultPanel:FireEventTree('refreshSpells')
									end,
								},

							},

							gui.Label{
								style = {
									fontSize = '35%',
									color = 'white',
									width = 'auto',
									height = 'auto',
									halign = 'center',
								},
								events = {
									refreshSpells = function(element)
										element.text = string.format('Page %d/%d', npage, NumPages())
									end,
								}
							},

							gui.Panel{
								bgimage = 'panels/InventoryArrow.png',
								className = 'pagingArrow',
								scale = {x = -1, y = 1},
								halign = 'right',
								hmargin = 40,

								events = {
									refreshSpells = function(element)
										element:SetClass('hidden', npage == NumPages())
									end,

									click = function(element)
										npage = npage + 1
										resultPanel:FireEventTree('refreshSpells')
									end,
								},
							},

						},
					},

		gui.AddButton{
			halign = 'right',
			valign = 'bottom',
			hmargin = 12,
			vmargin = 12,

			click = function(element)
				self:ShowAddSpellDialog{
					changeSpell = function(element)
						resultPanel:FireEventTree("refreshSpells")
					end,
				}
			end,
		},

		open = function(element)
			element:SetClass('hidden', false)
			element:FireEventTree("refreshSpells")
		end,

		close = function(element)
			element:SetClass('hidden', true)
		end,
	}

	resultPanel:FireEventTree("initDialog", resultPanel)
	resultPanel:FireEventTree("refreshSpells")

	return resultPanel
end
]]

function GameHud.ShowAddSpellDialog(self, options)

	local dialogWidth = 1200
	local dialogHeight = 980

	local resultPanel = nil

	local mainFormPanel = gui.Panel{
		style = {
			bgcolor = 'white',
			pad = 0,
			margin = 0,
			width = 1060,
			height = 840,
		},
		vscroll = true,
	}

	local newItem = nil

	local confirmCancelPanel = 
		gui.Panel{
			style = {
				valign = 'bottom',
				flow = 'horizontal',
				height = 60,
				width = '100%',
				fontSize = '60%',
				vmargin = 0,
			},

			children = {
				gui.PrettyButton{
					text = 'Create',
					style = {
						height = 60,
						width = 160,
						bgcolor = 'white',
						valign = 'center',
					},
					events = {
						click = function(element)
							--Add the new item and upload it to the game.
							local itemid = dmhub.SetAndUploadTableItem('Spells', newItem)
							resultPanel:FireEvent('changeSpell')
							resultPanel.data.close()
						end,
					},
				},
				gui.PrettyButton{
					text = 'Cancel',
					style = {
						height = 60,
						width = 160,
						bgcolor = 'white',
						valign = 'center',
					},
					events = {
						click = function(element)
							resultPanel.data.close()
						end,
					}
				},
			},
		}

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

			children = {
				gui.PrettyButton{
					text = 'Close',
					fontSize = 24,
					hpad = 10,
					vpad = 6,
					events = {
						click = function(element)
							--Add the new item and upload it to the game.
							local itemid = dmhub.SetAndUploadTableItem('Spells', newItem)
							resultPanel:FireEvent('changeSpell')
							resultPanel.data.close()
						end,
					},
				},
			},
		}

	local titleLabel = gui.Label{
		valign = 'top',
		halign = 'center',
		width = 'auto',
		height = 'auto',
		color = 'white',
		fontSize = 28,
	}

	resultPanel = gui.Panel{
		classes = {"framedPanel"},
		style = {
			bgcolor = 'white',
			width = dialogWidth,
			height = dialogHeight,
			halign = 'center',
			valign = 'center',
		},

		styles = Styles.Panel,

		changeSpell = options.changeSpell,

		captureEscape = true,
		escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
		escape = function(element)
			element.data.close()
		end,

		data = {
			show = function(editItem)
				newItem = nil

				if editItem then
					newItem = editItem
					confirmCancelPanel:SetClass('collapsed', true)
					closePanel:SetClass('collapsed', false)
				else
					newItem = Spell.Create {
					}
					confirmCancelPanel:SetClass('collapsed', false)
					closePanel:SetClass('collapsed', true)
				end

				local title = 'Create New Spell'
				if editItem then
					title = 'Edit Spell'
				end

				titleLabel.text = title

				mainFormPanel.children = {
					Spell.GenerateEditor(newItem, {
						description = title,
					})
				}

			end,
			close = function()
				resultPanel:DestroySelf()
			end,
		},

		children = {

			gui.Panel{
				id = 'content',
				style = {
					halign = 'center',
					valign = 'center',
					width = '94%',
					height = '94%',
					flow = 'vertical',
				},
				children = {
					titleLabel,
					mainFormPanel,
					confirmCancelPanel,
					closePanel,

				},
			},
		},
	}

	resultPanel.data.show(options.spell)

	self.mainDialogPanel:AddChild(resultPanel)

	return resultPanel

end

function Spell.CompendiumEditor()
	
	local resultPanel

	local leftPanel

	local searchTerms = nil

	local searchPanel = gui.Input{
		width = "100%",
		placeholderText = "Filter Spells...",

		editlag = 0.2,
		edit = function(element)
			if string.len(element.text) <= 0 then
				searchTerms = nil
			else
				searchTerms = string.split(string.lower(element.text))
			end

			resultPanel:FireEventTree("search")
		end,
	}

	local spellPanels = {}

	local spellScrollPanel = gui.Panel{
		width = "100%",
		height = "100%-60",
		flow = "vertical",
		vscroll = true,
		hideObjectsOutOfScroll = true,

		create = function(element)
			element:FireEventTree("refreshSpells")
		end,

		refreshSpells = function(element)
			local newSpellPanels = {}
			local children = {}
			local spellsTable = dmhub.GetTable("Spells")
			for k,spell in pairs(spellsTable) do
				local spellid = k
				if not spell:try_get("hidden", false) then
					local spellPanel = spellPanels[k] or gui.Panel{
						data = {
							spell = spell,
							init = false,
						},

						classes = {"spellItemPanel"},

						draggable = true,

						drag = function(element, target)
							if target == nil then
								return
							end

							local spellList = target.data.spellList
							if not spellList.spells[k] then
								spellList.spells[k] = true
								dmhub.SetAndUploadTableItem(SpellList.tableName, spellList)
								resultPanel:FireEventTree("refreshSpellLists")
							end
						end,


						canDragOnto = function(element, target)
							return target:HasClass("spellListPanel")
						end,

						rightClick = function(element)
						
							local entries = {}

							local listTable = dmhub.GetTable(SpellList.tableName)
							if listTable ~= nil then
								local submenu = {}
								for _,spellList in unhidden_pairs(listTable) do
									submenu[#submenu+1] = {
										text = spellList.name,
										check = spellList.spells[spellid] ~= nil,
										click = function()
											spellList.spells[spellid] = cond(spellList.spells[spellid] == nil, true, nil)
											dmhub.SetAndUploadTableItem(SpellList.tableName, spellList)
											resultPanel:FireEventTree("refreshSpellLists")
											element.popup = nil
										end,
									}
								end
								entries[#entries+1] = {
									text = "Spell Lists",
									submenu = submenu,
								}
							end

							entries[#entries+1] = {
								text = "Duplicate Spell",
								click = function()
									local newSpell = DeepCopy(spell)
									newSpell.name = string.format("%s (1)", newSpell.name)
									newSpell.id = dmhub.GenerateGuid()

									dmhub.SetAndUploadTableItem("Spells", newSpell)
									element.popup = nil

									resultPanel:FireEventTree("refreshSpells")
								end,
							}

							entries[#entries+1] = {
								text = "Delete Spell",
								click = function()
									spell.hidden = true
									dmhub.SetAndUploadTableItem("Spells", spell)
									element.popup = nil
									element:DestroySelf()
								end,
							}

							element.popup = gui.ContextMenu{
								entries = entries,
							}
						end,

						search = function(element)
							if searchTerms == nil then
								element:SetClass("collapsed", false)
								return
							end

							local match = true
							for _,term in ipairs(searchTerms) do
								if match then
									match = false
									if TextSearch(spell.name, term) or TextSearch(tostring(cond(spell.level == 0, "cantrip", spell.level)), term) or TextSearch(spell.school, term) then
										match = true
									end
								end
							end
						
							element:SetClass("collapsed", not match)
						end,

						expose = function(element)
							if element.data.init == false then

								element.data.init = true
								element.children = {
									gui.Label{
										classes = {"spellNameLabel"},
										refreshSpells = function(element)
											element.text = spell.name
										end,

										gui.NewContentAlertConditional("Spells", spell.id, {x = -2}),
									},

									gui.Label{
										classes = {"spellLevelLabel"},
										refreshSpells = function(element)
											if spell.level == 0 then
												element.text = "Cantrip"
											else
												element.text = string.format("Lv. %d", spell.level)
											end
										end,
									},

									gui.Label{
										classes = {"spellSchoolLabel"},
										refreshSpells = function(element)
											element.text = spell.school
										end,
									},

									gui.ImplementationStatusIcon{
										refreshSpells = function(element)
											element:FireEvent("implementation", spell:try_get("implementation", 1))
										end,
									},

									gui.SettingsButton{
										width = 16,
										height = 16,
										click = function(element)
											gamehud:ShowAddSpellDialog{
												spell = spell,
												changeSpell = function(element)
													resultPanel:FireEventTree("refreshSpells")
												end,
											}
										end,
									}

								}

								element:FireEventTree("refreshSpells")
							end

						end,

					}

					children[#children+1] = spellPanel
					newSpellPanels[k] = spellPanel
				end

			end

			table.sort(children, function(a,b) return a.data.spell.name < b.data.spell.name end)

			element.children = children
			spellPanels = newSpellPanels
		end,
	}

	local addSpellButton = gui.AddButton{
		width = 24,
		height = 24,
		halign = "right",
		click = function(element)
			gamehud:ShowAddSpellDialog{
				changeSpell = function(element)
					resultPanel:FireEventTree("refreshSpells")
				end,
			}

		end,
	}

	leftPanel = gui.Panel{
		height = "100%",
		width = 480,
		flow = "vertical",
		halign = "left",

		searchPanel,
		spellScrollPanel,
		addSpellButton
	}

	local addSpellListInput = gui.Input{
		width = "100%",
		height = 22,
		fontSize = 16,
		characterLimit = 22,
		placeholderText = "Add New Spell List...",
		text = "",
		change = function(element)
			local text = trim(element.text)
			element.text = ""
			if text ~= "" then
				local newList = SpellList.Create{
					name = text,
				}

				dmhub.SetAndUploadTableItem(SpellList.tableName, newList)
				resultPanel:FireEventTree("refreshSpellLists")
			end
		end,
	}

	local spellListPanels = {}

	local spellListPanel = gui.Panel{
		id = "spellListPanel",
		styles = {
			Styles.Triangle,
			{
				classes = {"triangle"},
				halign = "left",
				width = 12,
				height = 12,
				bgcolor = "#cccccc",
			},
			{
				classes = {"spellListHeader"},
				flow = "horizontal",
				height = 20,
				width = "100%",
			},
			{
				classes = {"spellListTitle"},
				hmargin = 4,
				fontSize = 16,
				bold = true,
				width = "60%",
				height = "auto",
				halign = "left",
			},
			{
				classes = {"spellListTitleCount"},
				fontSize = 14,
				width = "auto",
				height = "auto",
				halign = "left",
				color = "#aaaaaa",
			},
			{
				classes = {"spellListPanel"},
				width = "100%",
				height = "auto",
				bgimage = "panels/square.png",
				bgcolor = "clear",
				flow = "vertical",
			},
			{
				classes = {"spellListPanel", "drag-target"},
				bgcolor = "#ffffff33",
			},
			{
				classes = {"spellListPanel", "drag-target-hover"},
				bgcolor = "#ffffff88",
			},
			{
				classes = {"spellListSpellLabel"},
				height = "auto",
				width = "100%",
				textAlignment = "left",
				fontSize = 16,
			},
		},

		height = "100%",
		width = 500,
		vscroll = true,
		flow = "vertical",
		halign = "center",
		hmargin = 16,

		addSpellListInput,

		create = function(element)
			element:FireEventTree("refreshSpellLists")
		end,

		refreshSpellLists = function(element)
			local newSpellListPanels = {}
			local spellLists = dmhub.GetTable(SpellList.tableName) or {}
			local children = {}
			for k,spellList in pairs(spellLists) do
				if not spellList.hidden then
					local spellListPanel = spellListPanels[k] or gui.Panel{
						classes = {"spellListPanel"},
						dragTarget = true,
						data = {
							init = false,
							spellList = spellList,
						},

						rightClick = function(element)
							element.popup = gui.ContextMenu{
								entries = {
									{
										text = "Delete Spell List",
										click = function()
											spellList.hidden = true
											dmhub.SetAndUploadTableItem(SpellList.tableName, spellList)
											element.popup = nil
											element:DestroySelf()
										end,
									}
								},
							}
						end,

						refreshSpellLists = function(element)
							if element.data.init == false then
								local bodyPanel = nil
								element.data.init = true
								element.children = {
									gui.Panel{
										classes = {"spellListHeader"},
										gui.Panel{
											classes = {"triangle"},
											selfStyle = { rotate = 90 },
											press = function(element)
												element.selfStyle.rotate = cond(element.selfStyle.rotate == 0, 90, 0)
												if bodyPanel == nil then
													--make the body panel for the spell lists which has a list of all the spells
													--that this spell list contains.
													local spellPanels = {}
													bodyPanel = gui.Panel{
														width = "100%-60",
														height = "auto",
														hmargin = 30,
														flow = "vertical",

														create = function(element)
															element:FireEventTree("refreshSpellLists")
														end,
														refreshSpellLists = function(element)
															local spellTable = dmhub.GetTable("Spells")
															local children = {}
															local newSpellPanels = {}
															local spells = spellList.spells
															for k,_ in pairs(spells) do
																local spell = spellTable[k]
																local spellPanel = spellPanels[k] or gui.Label{
																	data = {
																		ord = spell.name
																	},
																	classes = {"spellListSpellLabel"},
																	refreshSpellLists = function(element)
																		element.text = spell.name
																		element.data.ord = spell.name
																		element:SetClass("collapsed", spell:try_get("hidden", false))
																	end,

																	rightClick = function(element)
																		local entries = {}
																		entries[#entries+1] = {
																			text = "Remove Spell",
																			click = function()
																				element.popup = nil
																				spellList.spells[k] = nil
																				dmhub.SetAndUploadTableItem(SpellList.tableName, spellList)

																				resultPanel:FireEventTree("refreshSpellLists")
																			end,
																		}

																		element.popup = gui.ContextMenu{
																			entries = entries,
																		}
																	end,
																}

																newSpellPanels[k] = spellPanel
																children[#children+1] = spellPanel
															end

															table.sort(children, function(a,b) return a.data.ord < b.data.ord end)
															element.children = children
															spellPanels = newSpellPanels
														end,
													}

													element:FindParentWithClass("spellListPanel"):AddChild(bodyPanel)
												end

												bodyPanel:SetClass("collapsed", element.selfStyle.rotate == 90)
											end,
										},
										gui.Label{
											classes = {"spellListTitle"},
											refreshSpellLists = function(element)
												element.text = spellList.name
											end,
										},

										gui.Label{
											classes = {"spellListTitleCount"},
											refreshSpellLists = function(element)
												local spellTable = dmhub.GetTable("Spells")
												local count = 0
												for k,_ in pairs(spellList.spells) do
													local spell = spellTable[k]
													if spell ~= nil and not spell:try_get("hidden", false) then
														count = count+1
													end
												end
												element.text = tostring(count)
											end,

										},
									},
								}
							end
						end,
					}

					spellListPanel.data.ord = spellList.name

					newSpellListPanels[k] = spellListPanel
					children[#children+1] = spellListPanel
				end
			end

			table.sort(children, function(a,b) return a.data.ord < b.data.ord end)
			spellListPanels = newSpellListPanels

			children[#children+1] = addSpellListInput

			element.children = children
		end,
	}

	resultPanel = gui.Panel{
		width = "100%",
		height = "100%",
		flow = "horizontal",
		leftPanel,
		spellListPanel,

		styles = {
			{
				selectors = {"spellItemPanel"},
				bgimage = "panels/square.png",
				bgcolor = "clear",
				height = 22,
				width = "100%",
				flow = "horizontal",
			},
			{
				selectors = {"spellItemPanel", "hover"},
				bgcolor = "#770000",
			},
			{
				selectors = {"spellNameLabel"},
				fontSize = 16,
				minFontSize = 10,
				textWrap = false,
				bold = true,
				hmargin = 4,
				width = 200,
				height = "auto",
				textAlignment = "left",
			},
			{
				selectors = {"spellLevelLabel"},
				fontSize = 16,
				hmargin = 4,
				width = 60,
				height = "auto",
				textAlignment = "left",
			},
			{
				selectors = {"spellSchoolLabel"},
				fontSize = 16,
				width = 120,
				height = "auto",
				textAlignment = "left",
				hmargin = 4,
			},

			Styles.ImplementationIcon,
		},
	}

	return resultPanel
end


local SpellStyles = {
	gui.Style{
		selectors = {"label"},
		width = "auto",
		height = "auto",
		fontSize = 14,
		hmargin = 4,
	},
	gui.Style{
		selectors = {"titleLabel"},
		fontSize = 22,
		vmargin = 4,
		bold = true,
	},
	gui.Style{
		selectors = {"subtitleLabel"},
		fontSize = 20,
		vmargin = 4,
		bold = true,
	},
	gui.Style{
		selectors = {"featurePanel"},
		width = "100%-20",
		height = "auto",
		hpad = 4,
		vpad = 4,
		flow = "vertical",
		halign = "left",
		collapsed = 1,
	},
	gui.Style{
		selectors = {"featurePanel", "selected"},
		collapsed = 0,
	},

	gui.Style{
		selectors = {"spellSlot"},
		width = 506,
		height = 36,
		vmargin = 4,

		bgimage = "panels/square.png",
		bgcolor = "black",

		color = "grey",
		fontSize = 14,
		textAlignment = "center",

	},

	gui.Style{
		selectors = {"spellSlot", "drag-target"},
		color = "white",
		border = 2,
		borderColor = "white",
	},

	gui.Style{
		selectors = {"spellSlot", "drag-target-hover"},
		color = "yellow",
		border = 2,
		borderColor = "yellow",
	},

	gui.Style{
		selectors = {"spellRow"},
		halign = "center",
		valign = "center",
		flow = "horizontal",
		width = 500,
		height = 30,
		bgimage = "panels/square.png",
		bgcolor = "black",
	},

	gui.Style{
		selectors = {"spellRow", "slotted"},
		bgcolor = "#222222",
	},

	gui.Style{
		selectors = {"spellRow", "oddRow"},
		opacity = 0.7,
	},

	gui.Style{
		selectors = {"spellRow", "evenRow"},
		opacity = 0.9,
	},

	gui.Style{
		selectors = {"spellIcon"},
		height = 30,
		width = 30,
	},

	gui.Style{
		selectors = {"spellNameLabel"},
		width = 210,
		bold = true,
		fontSize = 18,
	},
	gui.Style{
		selectors = {"spellLevelLabel"},
		width = 70,
		fontSize = 18,
	},
	gui.Style{
		selectors = {"spellAttributeLabel"},
		width = 70,
		fontSize = 18,
	},
	gui.Style{
		selectors = {"spellSchoolLabel"},
		width = 130,
		fontSize = 18,
	},
	gui.Style{
		selectors = {"spellRefreshTypeLabel"},
		width = 100,
		fontSize = 18,
	},
	gui.Style{
		selectors = {"spellRefreshCountLabel"},
		width = 20,
		fontSize = 18,
		textAlignment = "right",
	},
	gui.Style{
		selectors = {"label", "editable"},
		color = "#c0eddf",
	},
	gui.Style{
		selectors = {"label", "editable", "hover"},
		brightness = 1.5,
	},
	gui.Style{
		selectors = {"label", "disabled"},
		opacity = 0.3,
	},
}

local CreateSpellRow = function(options)

	local spellRow

	local index = options.index or 0
	options.index = nil
	local slotted = options.slotted
	options.slotted = nil
	local spellbook = options.spellbook
	options.spellbook = nil
	local nodrag = options.nodrag
	options.nodrag = nil
	local innate = options.innate
	options.innate = nil
	local immutable = options.immutable
	options.immutable = nil

	local m_innateInfo = nil

	local refreshUsesLabel = nil
	local refreshTypeLabel = nil
	local schoolLabel = nil
	local levelLabel = nil
	local attrLabel = nil
	if not innate then
		schoolLabel = gui.Label{
			classes = {"spellSchoolLabel"},
			refreshSpell = function(element, spell)
				element.text = spell.school
			end,
		}


		levelLabel = gui.Label{
			classes = {"spellLevelLabel"},
			refreshSpell = function(element, spell, innateInfo, upcastInfo)
				if spell.level == 0 then
					element.text = "Cantrip"
				else
					local level = spell.level
					if upcastInfo ~= nil then
						level = upcastInfo.level
						element:SetClass("editable", (not immutable))
					else
						element:SetClass("editable", false)
					end
					element.text = string.format("Lv. %d", level)
				end
			end,

			press = function(element)
				if element:HasClass("editable") then
					element:FireEventOnParents("cycleSpellLevel")
				end
			end,
		}


	else
		local m_spell = nil
		local editableClass = cond(immutable, nil, "editable")


		attrLabel = gui.Label{
			classes = {"spellAttributeLabel", editableClass},
			refreshSpell = function(element, spell, innateInfo)
				if innateInfo == nil then
					return
				end
				element.text = innateInfo.attrid
			end,
			press = function(element)
				if immutable then
					return
				end
				local index = 1
				for i,attrid in ipairs(creature.attributeIds) do
					if attrid == m_innateInfo.attrid then
						index = i
					end
				end

				index = index+1
				if index > #creature.attributeIds then
					index = 1
				end

				m_innateInfo.attrid = creature.attributeIds[index]
				CharacterSheet.instance.data.info.token.properties:Invalidate()
				spellRow:FireEventTree("refreshSpell", m_spell, m_innateInfo)
			end,
		}

		refreshTypeLabel = gui.Label{
			classes = {"spellRefreshTypeLabel", editableClass},
			refreshSpell = function(element, spell, innateInfo)
				if innateInfo == nil then
					return
				end
				m_innateInfo = innateInfo
				m_spell = spell

				if innateInfo.useResources then
					element.text = "use slots"
					return
				end

				if innateInfo.usageLimitOptions == nil or innateInfo.usageLimitOptions.resourceRefreshType == "none" then
					element.text = "at will"
					return
				end

				if innateInfo.usageLimitOptions.resourceRefreshType == "short" then
					element.text = "/short rest"
				elseif innateInfo.usageLimitOptions.resourceRefreshType == "long" then
					element.text = "/long rest"
				else
					element.text = "/day"
				end
			end,
			press = function(element)
				if immutable then
					return
				end
				local refreshType = "none"
				if m_innateInfo.usageLimitOptions ~= nil then
					refreshType = m_innateInfo.usageLimitOptions.resourceRefreshType
				end

				local refreshArray
				if CharacterSheet.instance.data.info.token.properties:IsMonster() then
					refreshArray = {"none", "day"}
				else
					refreshArray = {"none", "short", "long"}
				end

				local index = 1
				for i,a in ipairs(refreshArray) do
					if refreshType == a then
						index = i
					end
				end

				if m_innateInfo.useResources then
					m_innateInfo.useResources = false
				else
					index = index+1
					if index > #refreshArray then
						index = 1
					end

					if index == 1 and m_spell.level > 0 then
						m_innateInfo.useResources = true
					end
				end

				refreshType = refreshArray[index]

				if m_innateInfo.usageLimitOptions == nil then
					m_innateInfo.usageLimitOptions = {
						resourceRefreshType = refreshType,
						charges = 1,
						resourceid = dmhub.GenerateGuid(),
					}
				else
					m_innateInfo.usageLimitOptions.resourceRefreshType = refreshType
				end

				CharacterSheet.instance.data.info.token.properties:Invalidate()
				spellRow:FireEventTree("refreshSpell", m_spell, m_innateInfo)
			end,
		}
		refreshUsesLabel = gui.Label{
			classes = {"spellRefreshCountLabel", editableClass},
			editable = not immutable,
			characterLimit = 1,
			change = function(element)
				local num = tonumber(element.text)
				if num ~= nil then
					num = math.floor(num)
					m_innateInfo.usageLimitOptions.charges = num
				end
				element:FireEvent("refreshSpell", m_spell, m_innateInfo)
			end,
			refreshSpell = function(element, spell, innateInfo)
				if innateInfo == nil then
					return
				end
				if innateInfo.usageLimitOptions == nil or innateInfo.usageLimitOptions.resourceRefreshType == "none" then
					element:SetClass("hidden", true)
					return
				end

				element:SetClass("hidden", false)
				element.text = tostring(innateInfo.usageLimitOptions.charges)
			end,
		}
	end


	local m_spell = nil
	local args = {
		classes = {"spellRow", cond(slotted, "slotted", cond(index%2 == 1, "oddRow", "evenRow"))},

		data = {
			innate = innate,
			GetInnateInfo = function()
				return m_innateInfo
			end,
		},

		draggable = cond(nodrag, false, true),
		canDragOnto = function(element, target)
			if m_spell == nil or target:HasClass("spellSlot") == false then
				return false
			end

			if target:HasClass("innate") then
				return true
			end

			if m_spell.level == 0 and target:HasClass("cantrip") == false then
				return false
			end

			if m_spell.level >= 1 and target:HasClass("spell") == false then
				return false
			end

			--only require slotted if they require a spellbook to allow internal dragging
			--between slots.
			if target:HasClass("requireSpellbook") and (not slotted) then
				return false
			end

			if target:FindParentWithClass("selected") == nil then
				return false
			end

			return true
		end,

		drag = function(element, target)
			if target == nil then
				element:FireEventOnParents("dragSpell")
				return
			end

			target:FireEvent("dragSpell", m_spell, element)
		end,

		refreshSpell = function(element, spell)
			if spell ~= nil then
				m_spell = spell
			end
		end,

		hover = function(element)
			if m_spell ~= nil then
				element.tooltip = CreateAbilityTooltip(m_spell, {halign = cond(slotted, "right", "left")})
			end
		end,


		gui.Panel{
			classes = {"spellIcon", "icon"},
			halign = "left",
			refreshSpell = function(element)
				element.bgimage = m_spell:GetIcon()
				element.selfStyle = m_spell:GetIconDisplay()
			end,
		},


		gui.Label{
			classes = {"spellNameLabel"},
			refreshSpell = function(element)
				element.text = m_spell.name
			end,
		},

		levelLabel,
		attrLabel,


		schoolLabel,
		refreshUsesLabel,
		refreshTypeLabel,


		gui.ImplementationStatusIcon{
			refreshSpell = function(element)
				element:FireEvent("implementation", m_spell:try_get("implementation", 1))
			end,
		},

		gui.SettingsButton{
			width = 16,
			height = 16,
			click = function(element)
				gamehud:ShowAddSpellDialog{
					spell = m_spell,
					changeSpell = function(element)
						spellRow:FireEventTree("refreshSpell", m_spell)
					end,
				}
			end,
		}
	}

	for k,v in pairs(options) do
		args[k] = v
	end

	spellRow = gui.Panel(args)

	return spellRow
end

local CreateSpellSlotPanel = function(options)
	local spellType = options.spellType or "spell"
	options.spellType = nil

	local spellDisplay = cond(spellType == "innate", "spell", spellType)

	local spellbook = options.spellbook
	options.spellbook = nil

	local grant = options.grant
	options.grant = nil

	local immutable = options.immutable
	options.immutable = nil

	local m_spellid = nil

	local spellPanel = nil

	local resultPanel

	local args = {
		classes = {"spellSlot", spellType},
		dragTarget = cond(grant or immutable, false, true),
		text = string.format("Drag %s here", spellDisplay),

		requirespellbook = function(element, val)
			element:SetClass("requireSpellbook", val)
			if val then
				element.text = string.format("Drag %s here from spellbook", spellDisplay)
			else
				element.text = string.format("Drag %s here", spellDisplay)
			end
		end,

		discardspell = function(element)
			element:FireEvent("setspell", nil)
		end,

		setspell = function(element, spellid, innateOptions)
			if spellid ~= m_spellid or innateOptions ~= nil then
				local upcastOptions = nil
				local spell = nil
				if spellid then

					local id,level = SpellcastingFeature.DecodeSpellId(spellid)
					spellid = id

					if level ~= nil then
						upcastOptions = {
							level = level,
						}
					end

					local spellsTable = dmhub.GetTable("Spells")
					spell = spellsTable[spellid]
				end

				if spell == nil then
					element.children = {}
					spellPanel = nil
				else
					if spellPanel == nil then
						spellPanel = CreateSpellRow{
							slotted = true,
							spellbook = spellbook,
							immutable = immutable,
							nodrag = cond(grant or immutable, true, false),
							innate = cond(innateOptions ~= nil, true),
						}
						element.children = {spellPanel}
					end

					spellPanel:FireEventTree("refreshSpell", spell, innateOptions, upcastOptions)
				end
				m_spellid = spellid
			end

		end,
	}

	if options.classes ~= nil then
		for _,c in ipairs(options.classes) do
			args.classes[#args.classes+1] = c
		end
		options.classes = nil
	end

	for k,v in pairs(options) do
		args[k] = v
	end

	resultPanel = gui.Label(args)

	return resultPanel
end

local function RandomizeSpells(currentSpellcasting, spellcasting, spellType) --spellType is cantripsPrepared or spellsPrepared
	local spellsPrepared = DeepCopy(CharacterSheet.instance.data.info.token.properties:GetPreparedSpellcastingSpells(spellcasting, spellType))
	local numSpells = cond(spellType == "cantripsPrepared", currentSpellcasting.numKnownCantrips, currentSpellcasting.numKnownSpells)
	while #spellsPrepared < numSpells do
		spellsPrepared[#spellsPrepared+1] = false
	end
	

	--calculate out our levels for vacant spaces.
	local slotsToLevels = {}

	for i=1,currentSpellcasting.maxSpellLevel do
		slotsToLevels[#slotsToLevels+1] = 0
	end

	local nslotIndex = 1
	for i=1,currentSpellcasting.numKnownSpells do
		slotsToLevels[nslotIndex] = slotsToLevels[nslotIndex]+1
		nslotIndex = nslotIndex+1
		if nslotIndex > #slotsToLevels then
			nslotIndex = 1
		end
	end

	local levelOfSlot = {}
	for levelNum,num in ipairs(slotsToLevels) do
		for i=1,num do
			levelOfSlot[#levelOfSlot+1] = levelNum
		end
	end


	local availableSpellsByLevel = {}

	local spellLists = nil
	if currentSpellcasting ~= nil and #currentSpellcasting.spellLists >= 1 then
		spellLists = {}
		local listTable = dmhub.GetTable(SpellList.tableName)
		for _,listid in ipairs(currentSpellcasting.spellLists) do
			spellLists[#spellLists+1] = listTable[listid]
		end
	end

	local newSpells = {}
	local spellsTable = dmhub.GetTable("Spells")
	for i,spellid in ipairs(spellsPrepared) do
		newSpells[#newSpells+1] = false

		local spellLevel = 0

		if spellType ~= "cantripsPrepared" then
			spellLevel = levelOfSlot[i]
		end

		if spellid and spellsTable[spellid] then
			local spellInfo = spellsTable[spellid]
			spellLevel = spellInfo.level
		end


		if spellLevel ~= nil then

			if availableSpellsByLevel[spellLevel] == nil then
				--work out what spells are available at this level and add them to a list.
				local availableSpells = {}

				for k,v in pairs(spellsTable) do
					if v.level == spellLevel then
						local match = true
						if spellLists ~= nil then
							match = false
							for _,spellList in ipairs(spellLists) do
								if spellList.spells[k] then
									match = true
									break
								end
							end
						end

						if match then
							availableSpells[#availableSpells+1] = k
						end
					end
				end

				availableSpellsByLevel[spellLevel] = availableSpells
			end

			local availableSpells = availableSpellsByLevel[spellLevel]
			if #availableSpells > 0 then
				local index = math.random(#availableSpells)
				newSpells[#newSpells] = availableSpells[index]
				table.remove(availableSpells, index)
			end
		end
	end

	table.sort(newSpells, function(a,b)
		if b == false then
			return true
		end

		if a == false then
			return false
		end

		local spella = spellsTable[a]
		local spellb = spellsTable[b]

		return spella.level < spellb.level or (spella.level == spellb.level and spella.name < spellb.name)
	end)

	for i,newSpell in ipairs(newSpells) do
		CharacterSheet.instance.data.info.token.properties:AddPreparedSpellcastingSpell(spellcasting, newSpell, i, spellType)
	end
end

local CreateCharSheetSpells = function()

	local resultPanel


	local m_spellcastingFeaturesPanels = {}

	local m_currentSpellcasting = nil


	local CreateInnateSpellcastingPanel = function()

		local calculatedTitles = {}
		local calculatedSlots = {}

		local calculatedPanel = gui.Panel{
			flow = "vertical",
			width = "auto",
			height = "auto",
			refreshSpellcasting = function(element)
				local creature = CharacterSheet.instance.data.info.token.properties

				local modifiers = creature:GetActiveModifiers()

				local indexTitle = 1
				local indexSlot = 1

				local children = {}

				local currentName = nil
				for _,mod in ipairs(modifiers) do
					if mod.mod.behavior == "spell" then
						if mod.mod.name ~= currentName then
							local title = calculatedTitles[indexTitle] or gui.Label{
								classes = {"titleLabel"},
							}

							currentName = mod.mod.name

							title.text = mod.mod.name
							title:SetClass("collapsed", false)

							children[#children+1] = title

							calculatedTitles[indexTitle] = title
							indexTitle = indexTitle+1
						end


						local slot = calculatedSlots[indexSlot] or CreateSpellSlotPanel{
							spellType = "innate",
							immutable = true,
						}

						slot:FireEvent("setspell", mod.mod.spell, {
							spellid = mod.mod.spell,
							attrid = mod.mod.attribute,
							usageLimitOptions = mod.mod:try_get("usageLimitOptions"),
						})
						slot:SetClass("collapsed", false)
						children[#children+1] = slot

						calculatedSlots[indexSlot] = slot
						indexSlot = indexSlot+1
					end
				end

				while calculatedTitles[indexTitle] ~= nil do
					children[#children+1] = calculatedTitles[indexTitle]
					calculatedTitles[indexTitle]:SetClass("collapsed", true)
					indexTitle = indexTitle+1
				end

				while calculatedSlots[indexSlot] ~= nil do
					children[#children+1] = calculatedSlots[indexSlot]
					calculatedSlots[indexSlot]:SetClass("collapsed", true)
					indexSlot = indexSlot+1
				end

				element.children = children
			end
		}

		local innateSlots = {}
		local innateSlotsPanel = gui.Panel{
			width = "auto",
			height = "auto",
			flow = "vertical",
		}
		local titleLabel = gui.Label{
			classes = {"titleLabel"},
			text = "Custom Innate Spellcasting",
		}
		local innatePanel
		innatePanel = gui.Panel{

			classes = {"featurePanel"},

			data = {
				title = "Innate Spellcasting",
			},

			flow = "vertical",

			calculatedPanel,
			titleLabel,
			innateSlotsPanel,

			select = function(element)
				for _,child in ipairs(element.parent.children) do
					child:SetClass("selected", child == element)
				end

				m_currentSpellcasting = { maxSpellLevel = 9 }
				resultPanel:FireEvent("refreshCurrentSpellcasting")
			end,

			refreshSpellcasting = function(element)

				calculatedPanel:FireEvent("refreshSpellcasting")

				local tok = CharacterSheet.instance.data.info.token
				local innateSpells = tok.properties:GetInnateSpellcasting()

				local newInnateSlots = {}

				local hasNewSlots = false

				while #innateSlots < #innateSpells+1 do
					local nslot = #innateSlots+1
					hasNewSlots = true
					innateSlots[#innateSlots+1] = CreateSpellSlotPanel{
						spellType = "innate",
						dragSpell = function(element, spell, sourceElement)
							local tok = CharacterSheet.instance.data.info.token
							if sourceElement ~= nil and sourceElement.data.innate then
								--dragging between innate elements, so just swap them.
								local sourceInnateInfo = sourceElement.data.GetInnateInfo()
								local currentSpells = tok.properties:GetInnateSpellcasting()
								if currentSpells[nslot] == nil then
									return
								end

								local sourceIndex = nil
								for i,val in ipairs(currentSpells) do
									if sourceInnateInfo == val then
										sourceIndex = i
									end
								end

								if sourceIndex == nil then
									return
								end

								local a = currentSpells[sourceIndex]
								local b = currentSpells[nslot]

								currentSpells[nslot] = a
								currentSpells[sourceIndex] = b

								tok.properties:Invalidate()
								innatePanel:FireEvent("refreshSpellcasting")

								return
							end

							local val = nil
							if spell ~= nil then
								val = {
									spellid = spell.id,
									attrid = "wis",
								}

								--try to guess a good default attribute.
								local currentSpells = tok.properties:GetInnateSpellcasting()
								if currentSpells[nslot] ~= nil then
									val.attrid = currentSpells[nslot].attrid
								elseif currentSpells[#currentSpells] ~= nil then
									val.attrid = currentSpells[#currentSpells].attrid
								end
							end

							tok.properties:SetInnateSpellcasting(nslot, val)
							tok.properties:Invalidate()
							innatePanel:FireEvent("refreshSpellcasting")
						end,
					}
				end

				--build our n+1 interface.
				for i,slot in ipairs(innateSlots) do
					if i <= #innateSpells then
						slot:FireEvent("setspell", innateSpells[i].spellid, innateSpells[i])
					else
						slot:FireEvent("setspell", nil)
					end
					slot:SetClass("collapsed", i > #innateSpells+1)
				end

				if hasNewSlots then
					innateSlotsPanel.children = innateSlots
				end
			end,
		}

		return innatePanel
	end

	local m_innateSpellcastingPanel

	local CreateSpellcastingFeaturePanel = function()
		local m_spellcasting = nil


		local settingsButton = gui.SettingsButton{
			width = 32,
			height = 32,
			halign = "right",
			valign = "top",
			hmargin = 20,
			floating = true,
			press = function(element)
				resultPanel:FireEvent("showSettings")
			end,
		}

		local titleLabel = gui.Label{
			classes = {"titleLabel"},
		}

		local spellcastingLevelLabel = gui.Label{
			classes = {"subtitleLabel"},
			width = "auto",
			textAlignment = "left",
		}

		local dcLabel = gui.Label{
			classes = {"subtitleLabel"},
			width = "auto",
			hmargin = 20,
			textAlignment = "right",
		}

		local attackBonusLabel = gui.Label{
			classes = {"subtitleLabel"},
			width = "auto",
			hmargin = 20,
			textAlignment = "right",
		}

		local statsLine = gui.Panel{
			flow = "horizontal",
			width = "auto",
			height = "auto",

			gui.Label{
				classes = {"subtitleLabel"},
				text = "DC:",
				width = "auto",
			},

			dcLabel,

			gui.Label{
				classes = {"subtitleLabel"},
				text = "Atk Bonus:",
				width = "auto",
			},

			attackBonusLabel,
		}

		local cantripsTitle = gui.Label{
			classes = {"subtitleLabel"},
		}


		local cantripsRandomization = gui.Panel{
			bgimage = "ui-icons/d20.png",
			floating = true,
			halign = "right",
			valign = "top",
			width = 24,
			height = 24,
			hover = gui.Tooltip("Randomize spells"),
			styles = {
				{
					bgcolor = "white",
				},
				{
					selectors = {"hover"},
					bgcolor = "#ff00ff",
				},
			},
			press = function(element)
				RandomizeSpells(m_currentSpellcasting, m_spellcasting, "cantripsPrepared")
				resultPanel:FireEvent("charsheetActivate", true)
			end,
		}


		local cantripSlots = {}

		local cantripsPanel
		cantripsPanel = gui.Panel{
			flow = "vertical",
			width = "100%",
			height = "auto",

			cantripsRandomization,
			cantripsTitle,

			refreshSpellcasting = function(element)
				cantripsTitle.text = string.format("Cantrips known: %d", m_spellcasting.numKnownCantrips)
				element:SetClass("collapsed", m_spellcasting.numKnownCantrips == 0)

				if m_spellcasting.numKnownCantrips ~= #cantripSlots then
					local newCantripSlots = {}

					for i=1,m_spellcasting.numKnownCantrips do
						local nslot = i
						newCantripSlots[i] = cantripSlots[i] or CreateSpellSlotPanel{
							spellType = "cantrip",
							dragSpell = function(element, spell)
								local spellid = nil
								if spell ~= nil then
									spellid = spell.id
								end

								local tok = CharacterSheet.instance.data.info.token
								tok.properties:AddPreparedSpellcastingSpell(m_spellcasting, spellid, nslot, "cantripsPrepared")

								--is refreshing needed when setting a spell like this?
								--CharacterSheet.instance:FireEvent('refreshAll')
								cantripsPanel:FireEvent("refreshSpellcasting")
							end,
						}
					end

					cantripSlots = newCantripSlots

					local children = {cantripsRandomization, cantripsTitle}
					for _,slot in ipairs(cantripSlots) do
						children[#children+1] = slot
					end

					element.children = children
				end

				local spellList = CharacterSheet.instance.data.info.token.properties:GetPreparedSpellcastingSpells(m_spellcasting, "cantripsPrepared")
				for i=1,#cantripSlots do
					cantripSlots[i]:FireEvent("setspell", spellList[i])
				end
				
			end,
		}


		local grantsTitles = {}
		local grantsSlots = {}

		local grantsPanel

		grantsPanel = gui.Panel{
			flow = "vertical",
			width = "100%",
			height = "auto",
			refreshSpellcasting = function(element)
				local newGrantsTitles = {}
				local newGrantsSlots = {}
				local currentTitle = nil
				local children = {}
				for _,grant in ipairs(m_spellcasting.grantedSpells) do
					if grant.source ~= currentTitle then
						local title = grantsTitles[#newGrantsTitles+1] or gui.Label{
							classes = {"subtitleLabel"},
						}

						title.text = grant.source
						currentTitle = grant.source

						newGrantsTitles[#newGrantsTitles+1] = title
						children[#children+1] = title
					end

					local slot = grantsSlots[#newGrantsSlots+1] or CreateSpellSlotPanel{
						spellType = "spell",
						grant = true,
					}

					slot:FireEvent("setspell", grant.spellid)

					newGrantsSlots[#newGrantsSlots+1] = slot
					children[#children+1] = slot
				end

				grantsTitles = newGrantsTitles
				grantsSlots = newGrantsSlots
				element.children = children

			end,
		}

		local m_requireDragFromSpellbook = false
		local m_spellbookSlotsSet = nil

		local spellsTitle = gui.Label{
			classes = {"subtitleLabel"},
		}

		local spellsRandomization = gui.Panel{
			bgimage = "ui-icons/d20.png",
			floating = true,
			halign = "right",
			valign = "top",
			width = 24,
			height = 24,
			hover = gui.Tooltip("Randomize spells"),
			styles = {
				{
					bgcolor = "white",
				},
				{
					selectors = {"hover"},
					bgcolor = "#ff00ff",
				},
			},
			press = function(element)
				RandomizeSpells(m_currentSpellcasting, m_spellcasting, "spellsPrepared")
				resultPanel:FireEvent("charsheetActivate", true)
			end,
		}


		local spellSlots = {}

		local spellsPanel
		spellsPanel = gui.Panel{
			flow = "vertical",
			width = "100%",
			height = "auto",
			bgimage = "panels/square.png",

			spellsRandomization,
			spellsTitle,

			refreshSpellcasting = function(element)
				spellsTitle.text = string.format("Spells %s: %d", m_spellcasting.refreshType, m_spellcasting.numKnownSpells)

				element:SetClass("collapsed", m_spellcasting.numKnownSpells == 0)

				if m_spellcasting.numKnownSpells ~= #spellSlots then
					local newSpellSlots = {}

					for i=1,m_spellcasting.numKnownSpells do
						local nslot = i
						newSpellSlots[i] = spellSlots[i] or CreateSpellSlotPanel{
							spellType = "spell",
							dragSpell = function(element, spell)
								local spellid = nil
								if spell ~= nil then
									spellid = spell.id
								end

								if spellid ~= nil and m_spellcasting.upcastingType == "prepared" then
									spellid = SpellcastingFeature.EncodeSpellId(spellid, spell.level)
								end

								local tok = CharacterSheet.instance.data.info.token
								tok.properties:AddPreparedSpellcastingSpell(m_spellcasting, spellid, nslot, "spellsPrepared")

								--is refreshing needed when setting a spell like this?
								--CharacterSheet.instance:FireEvent('refreshAll')
								spellsPanel:FireEvent("refreshSpellcasting")
							end,

							cycleSpellLevel = function(element)
								local tok = CharacterSheet.instance.data.info.token
								local currentSpells = tok.properties:GetPreparedSpellcastingSpells(m_spellcasting, "spellsPrepared")
								local currentSpell = currentSpells[nslot]
								if currentSpell == nil then
									return
								end

								local spellid,level = SpellcastingFeature.DecodeSpellId(currentSpell)
								local spellInfo = dmhub.GetTable("Spells")[spellid]
								if spellInfo == nil then
									return
								end

								local minLevel = spellInfo.level
								local maxLevel = m_spellcasting.maxSpellLevel
								level = level + 1
								if level > maxLevel then
									level = minLevel
								end

								tok.properties:AddPreparedSpellcastingSpell(m_spellcasting, SpellcastingFeature.EncodeSpellId(spellid, level), nslot, "spellsPrepared")

								--is refreshing needed when setting a spell like this?
								--CharacterSheet.instance:FireEvent('refreshAll')
								spellsPanel:FireEvent("refreshSpellcasting")
							end,
						}
					end

					spellSlots = newSpellSlots

					local children = {spellsRandomization, spellsTitle}
					for _,slot in ipairs(spellSlots) do
						children[#children+1] = slot
					end

					element.children = children
				end

				local spellList = CharacterSheet.instance.data.info.token.properties:GetPreparedSpellcastingSpells(m_spellcasting, "spellsPrepared")
				for i=1,#spellSlots do
					spellSlots[i]:FireEvent("setspell", spellList[i])
				end

				if m_spellcasting.spellbook ~= m_requireDragFromSpellbook or m_spellbookSlotsSet ~= #spellSlots then
					m_requireDragFromSpellbook = m_spellcasting.spellbook
					m_spellbookSlotsSet = #spellSlots
					for i=1,#spellSlots do
						spellSlots[i]:FireEvent("requirespellbook", m_spellcasting.spellbook)
					end
				end
				
			end,
		}


		local spellbookTitle = gui.Label{
			classes = {"subtitleLabel"},
		}

		local m_spellbookSlots = {}

		local spellbookPanel
		spellbookPanel = gui.Panel{
			flow = "vertical",
			width = "100%",
			height = "auto",

			spellbookTitle,

			refreshSpellcasting = function(element)

				if not m_spellcasting.spellbook then
					element:SetClass("collapsed", true)
					return
				end

				element:SetClass("collapsed", false)

				spellbookTitle.text = string.format("Spellbook Entries: %d", m_spellcasting.spellbookSize)

				if m_spellcasting.spellbookSize ~= #m_spellbookSlots then
					local newSpellbookSlots = {}

					for i=1,m_spellcasting.spellbookSize do
						local nslot = i
						newSpellbookSlots[i] = m_spellbookSlots[i] or CreateSpellSlotPanel{
							spellType = "spell",
							spellbook = true,
							dragSpell = function(element, spell)
								local spellid = nil
								if spell ~= nil then
									spellid = spell.id
								end

								local tok = CharacterSheet.instance.data.info.token
								tok.properties:AddPreparedSpellcastingSpell(m_spellcasting, spellid, nslot, "spellbookPrepared")

								--is refreshing needed when setting a spell like this?
								--CharacterSheet.instance:FireEvent('refreshAll')
								spellbookPanel:FireEvent("refreshSpellcasting")
							end,
						}
					end

					m_spellbookSlots = newSpellbookSlots

					local children = {spellbookTitle}
					for _,slot in ipairs(m_spellbookSlots) do
						children[#children+1] = slot
					end

					element.children = children
				end

				local spellList = CharacterSheet.instance.data.info.token.properties:GetPreparedSpellcastingSpells(m_spellcasting, "spellbookPrepared")
				for i=1,#m_spellbookSlots do
					m_spellbookSlots[i]:FireEvent("setspell", spellList[i])
				end
				
			end,
		}

		local m_spellcopyTitle = gui.Label{
				classes = {"subtitleLabel"},
				text = "Copied Spells",
			}

		local m_spellcopySlots = {}

		local spellsCopiedPanel
		spellsCopiedPanel = gui.Panel{
			flow = "vertical",
			width = "100%",
			height = "auto",

			m_spellcopyTitle,


			refreshSpellcasting = function(element)

				if not m_spellcasting.spellbook then
					element:SetClass("collapsed", true)
					return
				end

				element:SetClass("collapsed", false)

				local tok = CharacterSheet.instance.data.info.token
				local spellList = tok.properties:GetPreparedSpellcastingSpells(m_spellcasting, "spellbookCopied")

				printf("CHILDREN:: COUNT %d vs %d", #spellList+1, #m_spellcopySlots)


				if #spellList+1 ~= #m_spellcopySlots then
					local newSpellbookSlots = {}

					for i=1,#spellList+1 do
						local nslot = i
						newSpellbookSlots[i] = m_spellcopySlots[i] or CreateSpellSlotPanel{
							spellType = "spell",
							spellbook = true,
							dragSpell = function(element, spell)
								local spellid = nil
								if spell ~= nil then
									spellid = spell.id
								end

								local tok = CharacterSheet.instance.data.info.token
								tok.properties:AddPreparedSpellcastingSpell(m_spellcasting, spellid, nslot, "spellbookCopied")

								--is refreshing needed when setting a spell like this?
								--CharacterSheet.instance:FireEvent('refreshAll')
								spellsCopiedPanel:FireEvent("refreshSpellcasting")
							end,
						}
					end

					m_spellcopySlots = newSpellbookSlots

					local children = {m_spellcopyTitle}
					for _,slot in ipairs(m_spellcopySlots) do
						children[#children+1] = slot
					end

					element.children = children
				end

				for i=1,#m_spellcopySlots do
					m_spellcopySlots[i]:FireEvent("setspell", spellList[i])
				end
				
			end,
		}

		return gui.Panel{
			classes = {"featurePanel"},

			settingsButton,

			titleLabel,
			spellcastingLevelLabel,
			statsLine,

			cantripsPanel,
			grantsPanel,
			spellsPanel,
			spellbookPanel,
			spellsCopiedPanel,

			select = function(element)
				for _,child in ipairs(element.parent.children) do
					child:SetClass("selected", child == element)
				end

				m_currentSpellcasting = m_spellcasting
				resultPanel:FireEvent("refreshCurrentSpellcasting")
			end,

			refreshSpellcasting = function(element, spellcasting)
				m_spellcasting = spellcasting
				titleLabel.text = spellcasting.name
				spellcastingLevelLabel.text = string.format("Level %d Spellcaster", spellcasting.level)
				dcLabel.text = tostring(spellcasting.dc)
				attackBonusLabel.text = ModStr(spellcasting.attackBonus)

				--if not custom spellcasting then hide the settings button.
				settingsButton:SetClass("hidden", spellcasting.id ~= "monster")

				cantripsPanel:FireEvent("refreshSpellcasting")
				grantsPanel:FireEvent("refreshSpellcasting")
				spellsPanel:FireEvent("refreshSpellcasting")
				spellbookPanel:FireEvent("refreshSpellcasting")
				spellsCopiedPanel:FireEvent("refreshSpellcasting")
			end,
		}
	end

	local spellcastingFeaturesScroll = gui.Panel{
		id = "spellcastingFeaturesScroll",
		vscroll = true,
		flow = "vertical",
		width = 550,
		height = "100%-40",
		vmargin = 20,
		halign = "center",
	}
		
	local m_visible = false
	local m_currentSpellList = {}
	local m_availableSpells = {} --spells that pass the filter condition and aren't displayed greyed out.
	local m_currentFilteredSpellList = {}

	local PageSize = 24

	local spellListEntries = {}
	for i = 1,PageSize do
		spellListEntries[#spellListEntries+1] = CreateSpellRow{
			index = i
		}
	end

	local m_page = 1
	local NumPages = function()
		return math.max(1, math.ceil(#m_currentFilteredSpellList / PageSize))
	end

	local pageLabel = gui.Label{
		text = "Page 1/1",
	}

	local RenderSpellList = function()
		pageLabel.text = string.format("Page %d/%d", m_page, NumPages())

		local nstart = (m_page-1)*PageSize
		for i=1,PageSize do
			local spellEntry = spellListEntries[i]
			local spell = m_currentFilteredSpellList[nstart+i]
			if spell ~= nil then
				spellEntry:SetClass("hidden", false)
				spellEntry:FireEventTree("refreshSpell", spell)


				local disabled = m_availableSpells ~= nil and (not m_availableSpells[spell.id])
				if disabled ~= spellEntry:HasClass("disabled") then
					spellEntry:SetClassTree("disabled", disabled)
				end
			else
				spellEntry:SetClass("hidden", true)
			end

		end
	end

	local spellListHeadingLabel = gui.Label{
		classes = {"titleLabel"},
		halign = "center",
	}

	local spellListLevelsLabel = gui.Label{
		halign = "center",
		text = "All Levels",
	}

	local showAllSpellsCheck = gui.Check{
		text = "Show All Spells",
		value = false,
		change = function(element)
			resultPanel:FireEvent("refreshCurrentSpellcasting")
		end,
	}


	local searchTerms = nil


	local searchSpellListInput = gui.Input{
		placeholderText = "Search...",
		editlag = 0.2,
		edit = function(element)

			if string.len(element.text) <= 0 then
				searchTerms = nil
			else
				searchTerms = string.split(string.lower(element.text))
			end

			m_page = 1
			resultPanel:FireEvent("refreshSpellListSearch")
		end,
	}

	local spellListPanel = gui.Panel{
		flow = "vertical",
		width = "auto",
		height = "auto",
		children = spellListEntries
	}

	local spellListPagingPanel = gui.Panel{

		id = 'spelllist-paging-panel',
		width = "auto",
		height = "32",
		halign = "center",
		flow = "horizontal",

		gui.PagingArrow{
			facing = -1,
			click = function(element)
				m_page = max(1, m_page-1)
				RenderSpellList()
			end,
		},

		pageLabel,

		gui.PagingArrow{
			facing = 1,
			click = function(element)
				m_page = min(NumPages(), m_page+1)
				RenderSpellList()
			end,
		}
	}


	local addButton = gui.AddButton{
		halign = 'right',
		valign = 'bottom',
		hmargin = 12,
		vmargin = 12,
		floating = true,

		click = function(element)
			GameHud.instance:ShowAddSpellDialog{
				changeSpell = function(element)
					resultPanel:FireEventTree("charsheetActivate", true)
				end,
			}
		end,
	}

	local spellListContainer = gui.Panel{
		id = "spellListContainer",
		flow = "vertical",
		width = "auto",
		height = "auto",
		vmargin = 20,
		hmargin = 20,
		halign = "center",

		spellListHeadingLabel,
		spellListLevelsLabel,
		showAllSpellsCheck,
		searchSpellListInput,

		spellListPanel,
		spellListPagingPanel,
		addButton,
	}

	local tabs = {}
	local tabsPanel
	tabsPanel = gui.Panel{
		styles = {
			CharSheet.TabsStyles,
			{
				selectors = {"statsLabel", "tab"},
				fontSize = 18,
			}
		},

		flow = "horizontal",
		height = 50,
		width = "auto",
		hmargin = 20,
		vmargin = 8,

		data = {
			featuresPanels = {},
		},

		refreshSpellcasting = function(element, spellcasting, spellcastingFeaturesPanels)
			element.data.featuresPanels = spellcastingFeaturesPanels

			local tok = CharacterSheet.instance.data.info.token

			local newTabs = false
			while #tabs < #spellcastingFeaturesPanels do
				local n = #tabs+1
				tabs[#tabs+1] = gui.Label{
					classes = {"statsLabel", "tab"},
					press = function(element)
						for _,child in ipairs(tabs) do
							child:SetClass("selected", child == element)
						end

						local feature = tabsPanel.data.featuresPanels[n]
						if feature ~= nil then
							feature:FireEvent("select")
						end
					end,
				}
				newTabs = true
			end

			local selectedIndex = 1
			for i,tab in ipairs(tabs) do
				local entry = spellcastingFeaturesPanels[i]
				if entry == nil then
					tab:SetClass("collapsed", true)
				else
					tab:SetClass("collapsed", false)
					tab.text = entry.data.title

					if spellcastingFeaturesPanels[i]:HasClass("selected") then
						selectedIndex = i
					end
				end
			end

			if newTabs then
				element.children = tabs
			end

			tabs[selectedIndex]:FireEvent("press")
		end,
	}

	local spellsHorizontalPanel = gui.Panel{
		width = "100%",
		height = "100%-60",
		flow = "horizontal",
		spellcastingFeaturesScroll,
		spellListContainer,
	}

	local m_monsterSpellcastingConfigPanel

	local CreateMonsterSpellcastingConfigPanel = function()


		local addMonsterSpellcastingButton = gui.PrettyButton{
			halign = "center",
			valign = "center",
			width = 240,
			height = 50,
			fontSize = 16,
			bold = true,
			text = "Add Custom Spellcasting",
			click = function(element)
				CharacterSheet.instance.data.info.token.properties.monsterSpellcasting = CharacterModifier.CreateMonsterSpellcastingModifier()
				CharacterSheet.instance.data.info.token.properties:Invalidate()
				m_monsterSpellcastingConfigPanel:FireEvent("refreshConfig")
			end,
		}

		local monsterSpellcastingConfigSheet = gui.Panel{
			id = "monsterSpellcastingConfigSheet",
			width = "100%",
			height = "auto",
			flow = "vertical",
			gui.Panel{
				width = 800,
				height = 600,
				flow = "vertical",
				vscroll = true,

				refreshConfig = function(element)
					local tok = CharacterSheet.instance.data.info.token
					local mod = tok.properties.monsterSpellcasting

					local typeInfo = CharacterModifier.TypeInfo[mod.behavior] or {}
					local createEditor = typeInfo.createEditor
					if createEditor ~= nil then
						createEditor(mod, element)
					end
				end,
			},

			gui.Panel{
				width = "100%",
				height = 80,

				gui.PrettyButton{
					halign = "left",
					valign = "center",
					width = 180,
					height = 50,
					fontSize = 16,
					text = "Confirm",
					click = function(element)
						resultPanel:FireEvent("charsheetActivate", true)
					end,
				},

				gui.PrettyButton{
					halign = "right",
					valign = "center",
					width = 180,
					height = 50,
					fontSize = 16,
					text = "Remove Spellcasting",
					click = function(element)
						CharacterSheet.instance.data.info.token.properties.monsterSpellcasting = nil
						m_monsterSpellcastingConfigPanel:FireEvent("refreshConfig")
					end,
				},

			},
		}



		return gui.Panel{

			id = "monsterSpellcastingConfigPanel",

			classes = {"featurePanel"},

			data = {
				title = "Spellcasting",
			},

			select = function(element)
				for _,child in ipairs(element.parent.children) do
					child:SetClass("selected", child == element)
				end

				m_currentSpellcasting = nil
				resultPanel:FireEvent("refreshCurrentSpellcasting")
				element:FireEvent("refreshConfig")
			end,


			styles = {
				Styles.Form,
				{
					selectors = {"label", "formLabel"},
					halign = "left",
				},
			},

			refreshConfig = function(element)
				local tok = CharacterSheet.instance.data.info.token
				element:SetClass("collapsed", false)

				addMonsterSpellcastingButton:SetClass("collapsed", tok.properties:has_key("monsterSpellcasting"))
				monsterSpellcastingConfigSheet:SetClass("collapsed", not tok.properties:has_key("monsterSpellcasting"))

				if tok.properties:has_key("monsterSpellcasting") then
					monsterSpellcastingConfigSheet:FireEventTree("refreshConfig")
				end
			end,

			addMonsterSpellcastingButton,
			monsterSpellcastingConfigSheet,
		}
	end

	resultPanel = gui.Panel{
		classes = {"characterSheetPanel", "hidden"},
		width = "100%",
		height = "100%",
		flow = "vertical",
		styles = {
			SpellStyles,
			Styles.ImplementationIcon,
		},

		tabsPanel,
		spellsHorizontalPanel,

		refreshToken = function(element, info)
			local tok = info.token

		end,

		--show the monster settings tab.
		showSettings = function(element)
			m_monsterSpellcastingConfigPanel:FireEvent("select")
		end,

		charsheetActivate = function(element, val)
			m_visible = val
			if not val then
				return
			end

			spellsHorizontalPanel:SetClass("collapsed", false)

			local tok = CharacterSheet.instance.data.info.token

			local newChildren = false
			if m_innateSpellcastingPanel == nil then
				m_innateSpellcastingPanel = CreateInnateSpellcastingPanel()
				newChildren = true
			end

			if m_monsterSpellcastingConfigPanel == nil then
				m_monsterSpellcastingConfigPanel = CreateMonsterSpellcastingConfigPanel()
				newChildren = true
			end

			local spellcasting = tok.properties:CalculateSpellcastingFeatures()
			if #m_spellcastingFeaturesPanels < #spellcasting then
				while #m_spellcastingFeaturesPanels < #spellcasting do
					m_spellcastingFeaturesPanels[#m_spellcastingFeaturesPanels+1] = CreateSpellcastingFeaturePanel()
				end
				newChildren = true
			end

			if newChildren then
				local children = {}
				for _,p in ipairs(m_spellcastingFeaturesPanels) do
					children[#children+1] = p
				end
				children[#children+1] = m_monsterSpellcastingConfigPanel
				children[#children+1] = m_innateSpellcastingPanel
				spellcastingFeaturesScroll.children = children
			end

			local activeChildren = {}

			for i=1,#m_spellcastingFeaturesPanels do
				local panel = m_spellcastingFeaturesPanels[i]
				if i <= #spellcasting then
					panel.data.title = spellcasting[i].name
					panel:SetClass("collapsed", false)
					panel:FireEvent("refreshSpellcasting", spellcasting[i])
					activeChildren[#activeChildren+1] = panel
				else
					panel:SetClass("collapsed", true)

				end
			end

			if #activeChildren == 0 then
				activeChildren[#activeChildren+1] = m_monsterSpellcastingConfigPanel
			end

			activeChildren[#activeChildren+1] = m_innateSpellcastingPanel
			m_innateSpellcastingPanel:FireEvent("refreshSpellcasting")


			m_monsterSpellcastingConfigPanel:SetClass("collapsed", true)

			tabsPanel:FireEvent("refreshSpellcasting", spellcasting, activeChildren)
		end,

		refreshCurrentSpellcasting = function(element)
			if m_currentSpellcasting == nil then
				spellListContainer:SetClass("hidden", true)
				return
			end

			spellListContainer:SetClass("hidden", false)
			
			searchSpellListInput.text = ""
			searchTerms = nil


			local maxLevel = m_currentSpellcasting.maxSpellLevel

			local spellLists = nil
			if m_currentSpellcasting.spellLists ~= nil and #m_currentSpellcasting.spellLists >= 1 then
				spellLists = {}
				local listTable = dmhub.GetTable(SpellList.tableName)

				for _,listid in ipairs(m_currentSpellcasting.spellLists) do
					
					local spellList = listTable[listid]
					spellLists[#spellLists+1] = spellList
				end
			end

			local showAll = showAllSpellsCheck.value

			m_availableSpells = nil
			if showAll then
				m_availableSpells = {}
			end

			if showAll or spellLists == nil then
				spellListHeadingLabel.text = "All Spells"
			else
				local joinedNames = ""
				for _,spellList in ipairs(spellLists) do
					if joinedNames ~= "" then
						joinedNames = joinedNames .. "/"
					end

					joinedNames = joinedNames .. spellList.name
				end

				spellListHeadingLabel.text = string.format("%s Spell List", joinedNames)
			end

			if showAll then
				spellListLevelsLabel.text = "All Levels"
			else
				spellListLevelsLabel.text = string.format("Level %d and below", maxLevel)
			end

			local spellsTable = dmhub.GetTable("Spells")
			m_currentSpellList = {}

			if showAll then
				for k,spell in pairs(spellsTable) do
					if spell:try_get("hidden", false) == false then

						local match = spell.level <= maxLevel

						if match and spellLists ~= nil then
							match = false
							for _,spellList in ipairs(spellLists) do
								if spellList.spells[k] then
									match = true
									break
								end
							end
						end

						if match then
							m_availableSpells[spell.id] = true
						end

						m_currentSpellList[#m_currentSpellList+1] = spell
					end
				end
			else
				for k,spell in pairs(spellsTable) do
					if spell:try_get("hidden", false) == false then

						local match = spell.level <= maxLevel

						if match and spellLists ~= nil then
							match = false
							for _,spellList in ipairs(spellLists) do
								if spellList.spells[k] then
									match = true
									break
								end
							end
						end

						if match then
							m_currentSpellList[#m_currentSpellList+1] = spell
						end
					end
				end
			end

			table.sort(m_currentSpellList, function(a,b) return a.level < b.level or (a.level == b.level and a.name < b.name) end)

			m_page = 1

			element:FireEvent("refreshSpellListSearch")

		end,


		refreshSpellListSearch = function(element)
			if searchTerms == nil then
				m_currentFilteredSpellList = m_currentSpellList
				RenderSpellList()
				return
			end

			m_currentFilteredSpellList = {}

			for _,spell in ipairs(m_currentSpellList) do
				local match = true
				for _,term in ipairs(searchTerms) do
					if match then
						match = false
						if TextSearch(spell.name, term) or TextSearch(tostring(cond(spell.level == 0, "cantrip", spell.level)), term) or TextSearch(spell.school, term) then
							match = true
						end
					end
				end
				if match then
					m_currentFilteredSpellList[#m_currentFilteredSpellList+1] = spell
				end
			end

			RenderSpellList()
		end,

	}

	return resultPanel
end

CharSheet.RegisterTab{
	id = "Spells",
	text = "Spells",
	panel = CreateCharSheetSpells,
}

local mod = dmhub.GetModLoading()

--This is the start of a journaling system but not much has been done on it yet.
RegisterGameType("JournalNode")

JournalNode.name = "New Document"
JournalNode.parentid = "none"
JournalNode.creatorid = "gm"

RegisterGameType("JournalFolder", "JournalNode")
RegisterGameType("JournalDocument", "JournalNode")

JournalDocument.text = ""
JournalDocument.image = ""

JournalNode.tableName = "documents"

local JournalStyles = {
	gui.Style{
		selectors = {"journalNodePanel"},
		flow = "horizontal",
		bgcolor = "clear",
		height = 18,
		width = "80%",
	},
	gui.Style{
		selectors = {"journalLabel"},
		fontSize = 14,
		color = "white",
		textWrap = false,
		width = "auto",
		height = "auto",
		valign = "center",
	},
	gui.Style{
		selectors = {"journalIcon"},
		bgcolor = "#d4d1ba",
		width = 16,
		height = 16,
		hmargin = 6,
		halign = "right",
		valign = "center",
	},
	gui.Style{
		selectors = {"journalIcon", "hover"},
		brightness = 1.5,
	},
}

function GameHud:JournalPanel()
	local result = nil
	local createItemButton = gui.AddButton{
		margin = 8,
		linger = function(element)
			gui.Tooltip("Add a new journal entry")(element)
		end,
		click = function(element)
			local id = dmhub.GenerateGuid()
			local doc = JournalDocument.new{
				id = id,
			}

			dmhub.SetAndUploadTableItem(JournalNode.tableName, doc)
			resultPanel:FireEvent("refreshAssets")

		end,
	}

	local dataTable

	local panels = {}
	resultPanel = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",
		styles = JournalStyles,
		monitorAssets = true,
		refreshAssets = function(element)
			local newPanels = {}
			local children = {}

			local childPanels = {}

			dataTable = dmhub.GetTable(JournalNode.tableName) or {}
			for k,entry in pairs(dataTable) do
				local nodePanel = panels[k] or gui.Panel{
					classes = {"journalNodePanel"},
					bgimage = "panels/square.png",
					gui.Label{
						classes = {"journalLabel"},
						refreshJournal = function(element)
							local nodeInfo = dataTable[k]
							element.text = nodeInfo.name
						end,
					},

					gui.Panel{
						classes = {"journalIcon"},
						bgimage = "panels/hud/stabbed-note.png",
						click = function(element)
							self:ViewJournalEntry(dataTable[k])
						end,
					},

					gui.Panel{
						classes = {"journalIcon"},
						bgimage = "panels/hud/gear.png",
						click = function(element)
							self:EditJournalDialog(k)
							
						end,
					},

				}

				childPanels[#childPanels+1] = {
					name = entry.name,
					panel = nodePanel,
				}

				newPanels[k] = nodePanel
			end

			table.sort(childPanels, function(a,b) return a.name < b.name end)
			for _,entry in ipairs(childPanels) do
				children[#children+1] = entry.panel
			end

			children[#children+1] = createItemButton
			element.children = children

			panels = newPanels
			element:FireEventTree("refreshJournal")
		end,
	}

	resultPanel:FireEvent("refreshAssets")

	return resultPanel
end

function GameHud:EditJournalDialog(journalid)
	local dataTable = dmhub.GetTable(JournalNode.tableName) or {}
	local doc = dataTable[journalid]

	local mainPanel

	local buttonPanel = gui.Panel{
		id = 'BottomButtons',
		style = {
			width = '90%',
			height = 100,
			margin = 8,
			bgcolor = 'white',
			valign = 'bottom',
			halign = 'center',
			flow = 'horizontal',
		},

		children = {
			gui.PrettyButton{
				text = 'Save & Close',
				width = 200,
				height = 80,

				events = {
					click = function(element)
						self:CloseModal()
						dmhub.SetAndUploadTableItem(JournalNode.tableName, doc)
					end,
				}
			},
		}
	}

	local iconEditor = gui.IconEditor{
		library = "journal",
		allowNone = true,
		maxWidth = 256,
		maxHeight = 256,
		width = "auto",
		height = "auto",
		autosizeimage = true,
		bgcolor = "white",
		value = doc.image,
		change = function(element)
			doc.image = element.value
		end,
	}

	local editPanel = gui.Panel{
		width = "50%",
		height = "100%",
		halign = "left",
		valign = "top",
		flow = "vertical",
		gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				classes = {"formLabel"},
				text = "Name:",
			},

			gui.Input{
				classes = {"formInput"},
				text = doc.name,
				change = function(element)
					doc.name = element.text
				end,
			},
			
		},
		iconEditor,
	}

	mainPanel = gui.Panel{
		id = 'MainEditPanel',
		width = "90%",
		height = "80%",
		flow = "horizontal",
		halign = "center",
		valign = "top",
		margin = 12,
		editPanel,
	}

	local dialogPanel = gui.Panel{
		id = 'EditJournalDialog',
		bgimage = 'panels/square.png',
		styles = {
			Styles.Form,
			{
				selectors = {"formPanel"},
				width = 400,
				halign = "left",
			},
		},

		width = 1200,
		height = 800,
		bgcolor = '#888888ff',
		borderWidth = 2,
		borderColor = 'black',
		cornerRadius = 8,
		flow = 'none',
		children = {
			mainPanel,
			buttonPanel,
		}
	}

	self:ShowModal(dialogPanel)
	
end

function GameHud:ViewJournalEntry(doc)

	local panel = gui.Panel{
		bgimage = doc.image,
		bgcolor = "white",
		maxWidth = 1024,
		maxHeight = 1024,
		width = rawget(doc, "width") or "auto",
		height = rawget(doc, "height") or "auto",
		autosizeimage = cond(rawget(doc, "autosizeimage") ~= nil, doc.autosizeimage, true),
		interactable = false,
	}

	local parentPanel = gui.Panel{
		width = "100%",
		height = "100%",
		bgimage = "panels/square.png",
		bgcolor = "#000000f2",
		styles = {
			{
				selectors = {"create"},
				transitionTime = 0.2,
				opacity = 0.0,
			},
		},

		press = function(element)
			self:CloseModal()
		end,
		click = function(element)
			self:CloseModal()
		end,

		escapeActivates = true,
		escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
		panel,
	}

	dmhub.Debug(string.format("VIEW JOURNAL: %s", doc.image))
	self:ShowModal(parentPanel)
end

function GameHud:ViewSign(imageid)
    if imageid == nil then
        return
    end

    local documentTable = dmhub.GetTable(MarkdownDocument.tableName or {})
    if documentTable[imageid] then
        documentTable[imageid]:ShowDocument()
        return
    end

	self:ViewJournalEntry(JournalDocument.new{
		image = imageid,
	})
end

--renders a compendium entry in modal form.
function GameHud:ViewCompendiumEntryModal(entry, token, options)
	local panel = gui.Panel{
		width = "100%",
		height = "100%",
		bgimage = "panels/square.png",
		bgcolor = "#000000f2",
		styles = {
			{
				selectors = {"create"},
				transitionTime = 0.2,
				opacity = 0.0,
			},
		},

		press = function(element)
			self:CloseModal()
		end,
		click = function(element)
			self:CloseModal()
		end,

		escapeActivates = true,
		escapePriority = EscapePriority.EXIT_MODAL_DIALOG,

		gui.Panel{
			width = 900,
			height = "90%",
			halign = "center",
			valign = "center",
			vscroll = true,
			gui.Panel{
				valign = "top",
				width = 880,
				height = "auto",
				halign = "left",
				hmargin = 4,
				entry:Render(options, token),
			},
		}
	}

	self:ShowModal(panel)
end
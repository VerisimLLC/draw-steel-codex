local mod = dmhub.GetModLoading()

-- Modifier type: Journal Explanation
-- Appends information to existing Journal Entry

CharacterModifier.RegisterType("journalexplanation", "Journal Explanation")

CharacterModifier.TypeInfo.journalexplanation = {
	init = function(modifier)
		modifier.heading = ""
		modifier.explanationText = ""
		modifier.targetDocId = false
	end,

	createEditor = function(modifier, element)
		local Refresh
		local firstRefresh = true

		Refresh = function()
			if firstRefresh then
				firstRefresh = false
			else
				element:FireEvent("refreshModifier")
			end

			local children = {}

			children[#children+1] = modifier:FilterConditionEditor()

			-- Target Document dropdown
			local docOptions = {}
			for id, doc in unhidden_pairs(dmhub.GetTable(CustomDocument.tableName) or {}) do
				docOptions[#docOptions+1] = {
					id = id,
					text = doc.description or id,
				}
			end

			children[#children+1] = gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					text = "Target Document:",
				},
				gui.Dropdown{
					classes = {"formDropdown"},
					options = docOptions,
					idChosen = modifier.targetDocId or "",
					textDefault = "Any",
					sort = true,
					hasSearch = true,
					change = function(element)
						modifier.targetDocId = element.idChosen
						Refresh()
					end,
				},
			}

			children[#children+1] = gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					text = "Heading:",
				},
				gui.Input{
					classes = {"formInput"},
					characterLimit = 128,
					text = modifier.heading,
					placeholderText = "Optional section heading",
					change = function(element)
						modifier.heading = element.text
					end,
				}
			}

			children[#children+1] = gui.Panel{
				classes = {"formPanel"},
				flow = "vertical",
				gui.Label{
					classes = {"formLabel"},
					text = "Explanation Text:",
					halign = "left",
				},
				gui.Input{
					width = "85%",
					height = 200,
					fontSize = 14,
					fontFace = "Courier",
					multiline = true,
					textAlignment = "topleft",
					verticalScrollbar = true,
					text = modifier.explanationText,
					placeholderText = "Markdown-formatted explanation text...",
					characterLimit = 10000,
					change = function(element)
						modifier.explanationText = element.text
					end,
				}
			}

			element.children = children
		end

		Refresh()
	end,
}

-- Ability Behavior: Show Journal
-- Displays a virtual (non-saved) journal entry assembled from a template document
-- plus explanation text gathered from journalexplanation modifiers on the caster.

ActivatedAbilityShowJournalBehavior = RegisterGameType("ActivatedAbilityShowJournalBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityShowJournalBehavior.summary = "Show Journal"
ActivatedAbilityShowJournalBehavior.templateDocId = false

ActivatedAbility.RegisterType{
	id = "show_journal",
	text = "Show Journal Entry",
	createBehavior = function()
		return ActivatedAbilityShowJournalBehavior.new{
			templateDocId = false,
		}
	end
}

function ActivatedAbilityShowJournalBehavior:Cast(ability, casterToken, targets, options)
	-- Load template document
	local templateDoc = false
	if self.templateDocId then
		templateDoc = (dmhub.GetTable(CustomDocument.tableName) or {})[self.templateDocId]
	end

	local content = ""
	local title = "Journal Entry"

	if templateDoc ~= nil then
		content = templateDoc:GetTextContent() or ""
		title = templateDoc.description or title
	end

	-- Gather explanation text from journalexplanation modifiers on the caster
	local mods = casterToken.properties:GetActiveModifiers()
	for _, modEntry in ipairs(mods) do
		if modEntry.mod.behavior == "journalexplanation" then
			local targetDocId = modEntry.mod:try_get("targetDocId")
			if targetDocId == false or targetDocId == self.templateDocId then
				local heading = modEntry.mod.heading or ""
				local text = modEntry.mod.explanationText or ""
				if heading ~= "" then
					content = content .. "\n\n## " .. heading
				end
				if text ~= "" then
					content = content .. "\n\n" .. text
				end
			end
		end
	end

	-- Create virtual document and display it
	if content == "" then
		return
	end

	local virtualDoc = MarkdownDocument.new{
		id = dmhub.GenerateGuid(),
		description = title,
		content = content,
		annotations = {},
	}

	virtualDoc:ShowDocument()
end

function ActivatedAbilityShowJournalBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)

	-- Document picker dropdown
	local docOptions = {}
	for id, doc in unhidden_pairs(dmhub.GetTable(CustomDocument.tableName) or {}) do
		docOptions[#docOptions+1] = {
			id = id,
			text = doc.description or id,
		}
	end

	result[#result+1] = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			classes = {"formLabel"},
			text = "Template Document:",
		},
		gui.Dropdown{
			classes = {"formDropdown"},
			options = docOptions,
			idChosen = self.templateDocId or "",
			textDefault = "None",
			sort = true,
			hasSearch = true,
			change = function(element)
				self.templateDocId = element.idChosen
			end,
		}
	}

	return result
end

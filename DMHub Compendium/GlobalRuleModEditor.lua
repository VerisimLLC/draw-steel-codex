local mod = dmhub.GetModLoading()


local SetGlobalRuleMod = function(tableName, ruleModPanel, ruleModid)
	local ruleModTable = dmhub.GetTable(tableName) or {}
	local ruleMod = ruleModTable[ruleModid]
	local UploadGlobalRuleMod = function()
		dmhub.SetAndUploadTableItem(tableName, ruleMod)
	end

	local children = {}

	--the name of the ruleMod.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Name:",
		},
		gui.Input{
			classes = {"formStacked"},
			text = ruleMod.name,
			change = function(element)
				ruleMod.name = element.text
				UploadGlobalRuleMod()
			end,
		},
	}

	--who the mod applies to.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Apply To:",
		},
		gui.Dropdown{
			classes = {"formStacked"},
			options = GlobalRuleMod.ApplyOptions,
			idChosen = ruleMod:GetApplyID(),
			change = function(element)
				ruleMod.applyRetainers = element.idChosen == "retainers" or element.idChosen == "characters_retainers" or element.idChosen == "characters_retainers_companions" or element.idChosen == "all"
				ruleMod.applyCharacters = element.idChosen == "characters" or element.idChosen == "characters_retainers" or element.idChosen == "characters_retainers_companions" or element.idChosen == "all"
				ruleMod.applyMonsters = element.idChosen == "monsters" or element.idChosen == "all"
				ruleMod.applyCompanions = element.idChosen == "companions" or element.idChosen == "characters_retainers_companions" or element.idChosen == "all"
				UploadGlobalRuleMod()
			end,
		},
	}

	children[#children+1] = ruleMod:GetClassLevel():CreateEditor(ruleMod, 0, {
		lmargin = 12,
		change = function(element)
			ruleModPanel:FireEvent("change")
			UploadGlobalRuleMod()
		end,
	})
	ruleModPanel.children = children
end

function GlobalRuleMod.CreateEditor()
	local ruleModPanel
	ruleModPanel = gui.Panel{
		data = {
			SetGlobalRuleMod = function(tableName, ruleModid)
				SetGlobalRuleMod(tableName, ruleModPanel, ruleModid)
			end,
		},
		vscroll = true,
		width = 1200,
		height = "90%",
		halign = "left",
		flow = "vertical",
		pad = 20,
		borderBox = true,
	}

	return ruleModPanel
end

local mod = dmhub.GetModLoading()

RegisterGameType("CharSheet")

setting{
	id = "sheet:windowed",
	storage = "preference",
	default = false,
}

CharSheet.defaultSheet = "Appearance"

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

CharSheet.TabOptions = {}

print("CharSheetFramework.lua loaded")
function CharSheet.RegisterTab(tab)
	local index = #CharSheet.TabOptions+1
	for i,t in ipairs(CharSheet.TabOptions) do
		if t.id == tab.id then
			index = i
		end
	end
	CharSheet.TabOptions[index] = tab
end

function CharSheet.DeregisterTab(tabid)
	local newTabs = {}

	for i,t in ipairs(CharSheet.TabOptions) do
		if t.id ~= tabid then
			newTabs[#newTabs+1] = t
		end
	end

	CharSheet.TabOptions = newTabs

end

dmhub.IsDialogOpen = function()
	if g_charSheet ~= nil and g_charSheet.valid and g_charSheet.enabled then
		return true
	end

	if gui.GetModal() ~= nil then
		return true
	end

	if gamehud ~= nil and gamehud.inventoryDialog ~= nil and gamehud.inventoryDialog.valid and gamehud.inventoryDialog.enabled then
		return true
	end

	return false
end

local CharacterSheetStyles = {

	{
		selectors = {"input"},
		bold = true,
		fontFace = "inter",
		fontSize = 18,
		height = 24,
		width = 180,
	},

	{
		selectors = {"label"},
		bold = true,
		fontFace = "inter",
		valign = "center",
	},

	{
		selectors = {"sliderLabel"},
		fontSize = 18,
		color = "#c4c1aa",
	},

	{
		selectors = {"statsLabel"},
		fontSize = 18,
		width = "auto",
		height = "auto",
		color = "#c4c1aa",
		bold = false,
	},
	{
		selectors = {"statsLabel", "invalid"},
		brightness = 0.8,
	},
	{
		selectors = {"statsLabel", "initiative"},
		halign = "center",
	},
	{
		selectors = {"statsLabel", "cr"},
		halign = "center",
	},
	{
		selectors = {"statsLabel", "inspiration"},
		halign = "center",
	},
	{
		selectors = {"statsLabel", "editableLabel", "hover"},
		color = "#d4d1ba",
	},
	{
		selectors = {"statsLabel", "proficiencyBonus"},
		fontSize = 12,
	},
	{
		selectors = {"#characterSheet"},
		halign = "center",
		valign = "bottom",
		width = "100%",
		height = "100%-42",
		vmargin = 2,
		flow = "horizontal",
		bgimage = "panels/square.png",
		bgcolor = "#111111ff",
	},
	{
		selectors = {"characterSheetPanel"},
		bgimage = "panels/character-sheet/Flag2_bar.png",
		bgcolor = "white",
		bgslice = 100,
		borderWidth = 6,
		opacity = 0.95,
	},
	{
		selectors = {"characterSheetParentPanel"},
	},

	{
		selectors = {"#leftArea"},
		vmargin = 0,
		hmargin = 0,
		width = 288,
		height = "100%",
		valign = "center",
		halign = "left",
		flow = "vertical",
	},

	{
		selectors = {"#rightArea"},
		vmargin = 0,
		hmargin = 0,
		width = 1920,
		height = "100%",
		valign = "center",
		halign = "left",
		flow = "vertical",
	},

	{
		selectors = {"#topPanel"},
		width = "100%",
		height = 146,
		flow = "horizontal",
	},
	{
		selectors = {"#bottomRightArea"},
		width = "100%",
		vmargin = 14,
		height = 878,
		flow = "horizontal",
	},

	{
		selectors = { "leftAreaPanel" },
		width = "100%",
	},

	{
		selectors = { "#avatarPanel" },
		height = "43.5%",
	},
	{
		selectors = { "#conditionsPanel" },
		height = "12%",
	},
	{
		selectors = { "#conditionsPanel" },
		height = "12%",
		vmargin = 14,
	},
	{
		selectors = { "#defensesPanel" },
		height = "12%",
	},
	{
		selectors = { "#proficienciesPanel" },
		height = "28%",
		vmargin = 14,
	},

	{
		selectors = { "#savingsThrowsAndResourcesArea" },
		width = "22%",
		height = "100%",
		flow = "vertical",
	},

	{
		selectors = { "#skillsPanel" },
		hmargin = 14,
		width = "28%",
		height = "100%",
	},

	{
		selectors = { "#bottomRightStatsArea" },
		width = "47.9%",
		height = "100%",
		flow = "vertical",
	},
	{
		selectors = { "#acSpeedHitpointsArea" },
		flow = "horizontal",
		width = "100%",
		height = "18%",
	},
	{
		selectors = { "#acSpeedPanel" },
		halign = "left",
		flow = "horizontal",
		width = "37.5%",
		height = "100%",
	},
	{
		selectors = { "#hitpointsPanel" },
		halign = "right",
		width = "60%",
		height = "100%",
	},
	{
		selectors = { "#featuresPanel" },
		vmargin = 14,
		width = "100%",
		height = "80%",
	},
	{
		selectors = { "#savingThrowsPanel" },
		width = "100%",
		height = "20%",
	},
	{
		selectors = { "#passiveSensesPanel" },
		width = "100%",
		height = "30%",
		vmargin = 14,
	},
	{
		selectors = { "#passiveSensesDisplayPanel" },
		flow = "vertical",
	},
	{
		selectors = { "#resourcesPanel" },
		width = "100%",
		height = "46.3%",
	},
	{
		selectors = { "panelFooter" },
		halign = "center",
		valign = "top",
		width = "80%",
		height = "auto",
		vmargin = 6,
		bgimage = "panels/square.png",
	},
	{
		selectors = { "panelFooterLabel" },
		width = "80%",
		height = 20,
		textAlignment = "center",
		fontSize = 16,
		textWrap = true,
		halign = "center",
		valign = "bottom",
		vmargin = 6,
		color = "#c4c1aa",
		uppercase = true,
	},
	{
		selectors = { "panelSettingsButton" },
		bgimage = "panels/character-sheet/gear.png",
		bgcolor = "white",
		width = 24,
		height = 24,
		halign = "right",
		valign = "center",
	},

	--a stats panel is a container panel for all of the actual stats within a panel.
	{
		selectors = { "statsPanel" },
		width = "100%-16",
		height = "100%-40",
		halign = "center",
		valign = "top",
		vmargin = 32,
	},

	--place this inside a stats panel to have the stats be centered within the stats panel.
	{
		selectors = { "statsInnerPanel" },
		width = "94%",
		height = "auto",
		valign = "top",
		halign = "center",
		flow = "vertical",
	},

	--regular rows of stats on the character sheet use this class.
	{
		selectors = { "statsRow" },
		height = 24,
		flow = "horizontal",
		vmargin = 4,
		halign = "center",
		width = "100%",
	},

	{
		selectors = {"#avatarInnerPanel"},
		height = "100%-16",
		flow = "vertical",
	},
	{
		selectors = {"#savingThrowInnerPanel"},
		height = "100%-30",
		valign = "top",
		flow = "horizontal",
	},
	{
		selectors = {"savingThrowColumnPanel"},
		flow = "vertical",
		width = "45%",
		height = "100%",
		halign = "center",
	},
	{
		selectors = {"savingThrowColumnPanel", "full"},
		width = "80%",

	},
	{
		selectors = {"#skillsInnerPanel"},
		flow = "vertical",
	},
	{
		selectors = {"#skillsFieldsPanel"},
		flow = "vertical",
		width = "100%",
		height = "92%",
		valign = "center",
		halign = "center",
	},
	{
		selectors = {"#skillsHeadingPanel"},
		valign = "top",
	},

	{
		selectors = {"savingThrowOuterRow"},
		height = 22,
		width = "100%",
		vmargin = 2,
		valign = "center",
	},

	{
		selectors = {"statsRow", "savingThrows"},
		height = "100%",
		width = "80%",
		valign = "center",
	},

	{
		selectors = {"statsRow", "skills"},
		width = "100%",
	},

	{
		selectors = {"statsRow", "passiveSenses"},
		width = "100%",
	},

	{
		selectors = {"label", "passiveSenses"},
		halign = "left",
		minWidth = 54,
		textAlignment = "left",
		uppercase = true,
	},

	--control of the width of the skills fields.
	{
		selectors = {"skillsProfField"},
		width = "15%",
		height = "100%",
		halign = "center",
	},
	{
		selectors = {"skillsModField"},
		width = "15%",
		halign = "center",
	},
	{
		selectors = {"skillsSkillField"},
		width = "50%",
		halign = "left",
	},
	{
		selectors = {"skillsBonusField"},
		width = "20%",
		halign = "right",
		textAlignment = "right",
	},

	{
		selectors = {"#tokenImage"},
		width = "80%",
		height = "100% width",
		bgcolor = "white",
		halign = "center",
	},
	{
		selectors = {"#tokenImageFrame"},
		width = "100%",
		height = "100%",
		bgcolor = "white",
	},
	
	{
		selectors = {"heading"},
		fontSize = "140%",
		valign = "top",
	},
	{
		selectors = {"centered"},
	},

	{
		selectors = {"#characterLevelsPanel"},
		halign = "center",
		height = "auto",
		width = "50%",
		flow = "vertical",
		minHeight = 60,
	},
	{
		selectors = {"classLevelLabel"},
		halign = "center",
		valign = "center",
	},
	{
		selectors = {"attributePanel"},
		hmargin = 6,
		valign = "center",
		flow = "vertical",
		height = "85%",
		width = 90,
	},
	{
		selectors = {"attributePanel", "initiative"},
		width = 140,
	},
	{
		selectors = {"attributePanel", "cr"},
		width = 140,
	},
	{
		selectors = {"attributePanel", "armorClass"},
		height = "80%",
		width = "90% height",
		valign = "center",
		halign = "center",
	},
	{
		selectors = {"statsLabel", "armorClass"},
		fontSize = 24,
		halign = "center",
	},
	{
		selectors = {"attributePanel", "movementSpeed"},
		height = "80%",
		width = "90% height",
		valign = "center",
		halign = "center",
	},
	{
		selectors = {"statsLabel", "movementSpeed"},
		fontSize = 24,
		halign = "center",
	},
	{
		selectors = {"statsLabel", "valueLabel", "savingThrows"},
		minWidth = 40,
		textAlignment = "right",
	},
	{
		selectors = {"#movementSpeedBackground"},
		bgimage = "panels/character-sheet/PartyFrame_Avatar_Frame.png",
		bgcolor = "white",
		halign = "center",
		valign = "center",
		width = 100,
		height = 100,
	},
	{
		selectors = {"movementSpeedIcon"},
		bgcolor = "#d4d1ba66",
		halign = "center",
		valign = "center",
		width = "65%",
		height = "65%",
	},
	{
		selectors = {"attrLabel"},
		color = "#7cceb4",
		bold = true,
	},
	{
		selectors = {"attributeIdLabel"},
		fontSize = 18,
		valign = "bottom",
		halign = "center",
		width = "auto",
		height = "auto",
		uppercase = true,
	},
	{
		selectors = {"attributeModifierPanel"},
		halign = "center",
		valign = "top",
		width = "100%",
		height = 90,
		bgimage = "panels/square.png",
		bgcolor = "clear",
		borderColor = Styles.textColor,
		borderWidth = 2,
		cornerRadius = 4,
	},

	{
		classes = {"attributeModifierPanel", "inspiration"},
		vmargin = 3,
		width = "100% height",
		bgcolor = "clear",
		borderColor = "clear",
	},

	{
		classes = {"attributeModifierPanel", "armorClass"},
		bgimage = "panels/character-sheet/bg_01.png",
		bgcolor = "white",
		borderWidth = 0,
		vmargin = 3,
		width = "90% height",
	},

	{
		classes = {"attributeModifierPanel", "movementSpeed"},
		vmargin = 3,
		width = "90% height",
		opacity = 0,
	},

	{
		selectors = {"attributeStatPanel"},
		bgimage = "panels/square.png",
		bgcolor = "#333333ff",
		x = -4,
		y = 6,
		width = 66,
		height = 36,
		halign = "left",
		valign = "bottom",
	},
	{
		selectors = {"attributeStatPanelBorder"},
		bgimage = "panels/square.png",
		bgcolor = "clear",
		borderColor = Styles.textColor,
		width = "100%",
		height = "100%",
		borderWidth = 2,
		cornerRadius = 4,
	},
	{
		selectors = {"attributeStatLabel"},
		color = "#c4c1aa",
		fontSize = 24,
		halign = "center",
		valign = "center",
		width = "auto",
		height = "auto",
		textAlignment = "center",
	},

	{
		selectors = {"valueLabel"},
		bgimage = "panels/square.png",
		bgcolor = "clear",
		color = "#c0eddf",
		halign = "right",
	},

	{
		selectors = {"valueLabel", "increase"},
		bgimage = "panels/square.png",
		bgcolor = "green",
		transitionTime = 0.5,
	},
	{
		selectors = {"valueLabel", "decrease"},
		bgimage = "panels/square.png",
		bgcolor = "red",
		transitionTime = 0.5,
	},

	{
		selectors = {"dice", "hover"},
		color = "#d0fdef",
	},

	{
		selectors = {"attributeModifierLabel"},
		vmargin = 18,
		valign = "top",
		halign = "center",
		textAlignment = "center",
		width = "auto",
		height = "auto",
		fontSize = 34,
	},

	{
		selectors = {"label", "itemProficiencies"},
		fontSize = 16,
	},

	{
		selectors = {"valueLabel", "itemProficiencies"},
		textWrap = true,
		height = "auto",
		width = "95%",
		halign = "left",
		hmargin = 4,
	},

	{
		selectors = {"skillCheck"},
		bgimage = 'game-icons/plain-circle.png',
		flow = "none",
		bgcolor = 'grey',
		halign = "left",
		valign = "center",
		width = 16,
		height = 16,
		vmargin = 0,
		hmargin = 0,
	},
	{
		selectors = {"skillCheck", "override"},
		bgcolor = "#4444bb",
	},
	{
		selectors = { "skillCheck", 'hover' },
		transitionTime = 0.1,
		bgcolor = 'white',
	},

	{
		selectors = { "skillBackground" },
		bgimage = 'game-icons/plain-circle.png',
		width = 12,
		height = 12,
		bgcolor = "black",
		halign = "center",
		valign = "center",
	},

	{
		selectors = { "skillFill" },
		bgimage = 'game-icons/plain-circle.png',
		bgcolor = "black",
		halign = "center",
		valign = "center",
		width = 12,
		height = 12,
	},
	{
		selectors = { "skillFill", 'parent:proficient' },
		bgcolor = '#8cdecf',
	},
	{
		selectors = { "skillFill", 'parent:halfproficient' },
		bgcolor = '#8cdecf',
		bgimage = 'game-icons/half-circle.png',
	},
	{
		selectors = { "expertiseLabel" },
		color = "black",
		bold = true,
		fontSize = 14,
		valign = "center",
		halign = "center",
		width = "auto",
		height = "auto",
		textAlignment = "center",
	},

	{
		selectors = {"#defensesLabel"},
		halign = "center",
		valign = "center",
		width = "95%",
		height = "95%",
		fontSize = 16,
	},

	{
		selectors = {"#conditionsInnerPanel"},
		flow = "horizontal",
	},

	{
		selectors = {'ongoingEffectStatusPanel'},
		width = 48,
		height = 48,
		valign = "center",
	},

	{
		selectors = {'ongoingEffectIconPanel'},
		width = 48,
		height = 48,
		valign = "center",
		halign = "center",
	},

	{
		selectors = {'resourcesGroup'},
		width = '100%',
		height = 'auto',
		valign = 'top',
		vmargin = 8,
		flow = 'vertical',
	},

	{
		selectors = {'resourceContainer'},
		width = "100%",
		height = 'auto',
		halign = 'center',
		flow = 'horizontal',
		wrap = true,
	},
	{
		selectors = {'resourcesGroupHeadLine'},
		width = '100%',
		height = 'auto',
		valign = 'top',
		flow = 'horizontal',
	},
	{
		selectors = {'resourcesGroupTitle'},
		textAlignment = 'top',

		halign = 'left',
		valign = 'top',
	},
	{
		selectors = {'resourcesRefreshIcon'},
		bgimage = 'game-icons/clockwise-rotation.png',
		width = 16,
		height = 16,
		hmargin = 4,
		halign = 'right',
		valign = 'top',
		bgcolor = "#d4d1ba",
	},
	{
		selectors = {'resourcesRefreshIcon', 'hover'},
		brightness = 1.5,
	},
	{
		selectors = {'resourcesRefreshIcon', 'press'},
		brightness = 0.7,
	},
	{
		selectors = {'resourcesRefreshText'},
		minWidth = 70,
		height = 'auto',
		fontSize = 14,
		halign = 'right',
		valign = 'top',
	},
	{
		selectors = {'resourceIcon'},
		width = 24,
		height = 24,
		margin = 0,
	},
	{
		selectors = {'resourceIcon', 'interactable', 'hover'},
		borderWidth = 2,
		borderColor = 'grey',
	},
	{
		selectors = {'resourceIcon', 'interactable', 'hover', 'press'},
		borderColor = 'white',
	},
	{
		selectors = {'resourceQuantityPanel'},
		width = "auto",
		height = 24,
		margin = 0,
		flow = "horizontal",
	},
	{
		selectors = {'resourceQuantityLabel'},
		fontSize = 16,
		width = "auto",
		height = "auto",
		color = Styles.textColor,
	},
	{
		classes = {"valueLabel", "movementSpeed"},
		valign = "center",
	},
	{
		classes = {"valueLabel", "armorClass"},
		valign = "center",
	},

	{
		classes = {"#inspirationIcon"},
		width = 50,
		height = 50,
		valign = "center",
		halign = "center",
		bgcolor = "white",
		bgimage = "panels/character-sheet/v_30.png",
	},

	{
		selectors = {"actionButton"},
		bgimage = "panels/square.png",
		width = "auto",
		height = "auto",
		vmargin = 2,
		halign = "right",
		textAlignment = "center",
		fontSize = 16,
		borderWidth = 1,
		borderColor = "white",
		color = "#d4d1ba",
		pad = 4,
		bgcolor = "black",
	},

	{
		selectors = {"actionButton", "hover"},
		borderColor = "yellow",
	},

	{
		selectors = {"actionButton", "press"},
		borderColor = "grey",
	},

	{
		selectors = {"#characterBuilderAccessButton"},
		bgcolor = "clear",
		height = "50%",
		width = "100%",
		flow = "horizontal",
	},
	{
		selectors = {"#characterBuilderAccessButton", "hover"},
		transitionTime = 0.1,
		uiscale = 1.1,
	},

	{
		selectors = {"#characterBuilderIcon"},
		bgimage = "panels/character-sheet/gear-hammer.png",
		bgcolor = "white",
		valign = "center",
		halign = "right",
		height = "70%",
		width = "100% height",
	},

	{
		selectors = { "#characterBuilderAccessPanel" },

		hmargin = 24,
		flow = "vertical",
		height = "95%",
		halign = "right",
		valign = "center",
		width = 230,
	},

	{
		selectors = {"characterBuilderAccessPanelIcon"},
		height = "70%",
		width = "100% height",
		valign = "center",
		halign = "right",
		bgcolor = "white",
		hmargin = 4,
	},
	{
		selectors = {"characterBuilderAccessPanelIcon", "hover"},
		transitionTime = 0.1,
		scale = 1.1,
	},


	{
		selectors = {"privacyIcon"},
		halign = "right",
		valign = "center",
		x = 16,
		width = 16,
		height = 16,
		bgimage = "ui-icons/eye-closed.png",
		bgcolor = Styles.textColor,
	},
	{
		selectors = {"privacyIcon", "hover"},
		brightness = 1.5,
	},
	{
		selectors = {"privacyIcon", "inactive"},
		bgimage = "ui-icons/eye.png",
	},

	{
		selectors = {"modificationOrbContainer"},
		wrap = true,
		halign = "right",
		valign = "center",
		width = 10,
		height = "90%",
		flow = "vertical",
	},

	{
		selectors = {"modificationOrb"},
		width = 6,
		height = 6,
		halign = "center",
		valign = "top",
		vmargin = 1,
		bgimage = "panels/square.png",
		bgcolor = Styles.textColor,
		cornerRadius = 3,
		brightness = 1.5,
	},
	{
		selectors = {"modificationOrb", "race"},
	},
	{
		selectors = {"modificationOrb", "item"},
		bgcolor = "#aaaaaa",
	},
	{
		selectors = {"modificationOrb", "CharacterOngoingEffect"},
		bgcolor = "#00ffff",
	},
	{
		selectors = {"modificationOrb", "unchanged"},
		brightness = 0.7,
	},
	{
		selectors = {"modificationOrb", "debuff"},
		bgcolor = "red",
	},
	{
		selectors = {"modificationOrb", "hover"},
		brightness = 8,
	},
}

gui.RegisterTheme("charsheet", "Main", CharacterSheetStyles)

local g_stylesCalculated = nil

function CharSheet.GetCharacterSheetStyles()
	
	if g_stylesCalculated == nil then
		g_stylesCalculated = {}
		for _,item in ipairs(CharacterSheetStyles) do
			g_stylesCalculated[#g_stylesCalculated+1] = item
		end

		for _,proficiencyLevel in pairs(creature.proficiencyKeyToValue) do
			if proficiencyLevel.color ~= nil then

				g_stylesCalculated[#g_stylesCalculated+1] = {
					selectors = { "skillFill", string.format('parent:proficiency-%s', proficiencyLevel.id) },
					bgcolor = proficiencyLevel.color,
					priority = 10,
				}

			end
		end
	end

	return g_stylesCalculated
end

local g_charSheet = nil

function CharSheet.CreateCharacterSheet(params)
	local selectedTab = CharSheet.defaultSheet

	table.sort(CharSheet.TabOptions, function(a, b) return tostring(a.order or a.text) < tostring(b.order or b.text) end)

	local tabPanels = {}
	for _,tabOption in ipairs(CharSheet.TabOptions) do
		local panel = nil
		if tabOption.panel ~= nil then
			panel = tabOption.panel()
            if panel == nil then
                dmhub.Error("CharSheet" .. tabOption.id .. "returned nil from the panel function: " .. traceback())
            end
        else
            dmhub.Error("CharSheet" .. tabOption.id .. "must define a panel function")
		end

		tabPanels[#tabPanels+1] = panel
	end

	local characterSheetHeight = 1080
	local characterSheetWidth = 1920 --round(characterSheetHeight * (1920/1080))
	local scale = 1

	local heightPercent = (dmhub.uiscale*characterSheetHeight)/dmhub.screenDimensionsBelowTitlebar.y
	local minPercent = 1080/1080
	local xdelta = 0
    print("RATIO::", characterSheetWidth/characterSheetHeight, dmhub.screenDimensionsBelowTitlebar.x/dmhub.screenDimensionsBelowTitlebar.y)
	if heightPercent < minPercent then
		scale = heightPercent/minPercent
		xdelta = -(1 - scale)*1920/2
    end


    if characterSheetWidth/characterSheetHeight > dmhub.screenDimensionsBelowTitlebar.x/dmhub.screenDimensionsBelowTitlebar.y then
        scale = min(scale, 0.98*(dmhub.screenDimensionsBelowTitlebar.x/dmhub.screenDimensionsBelowTitlebar.y) / (characterSheetWidth/characterSheetHeight))
		xdelta = 0
        print("RATIO:: SCALE =", scale)
	end

	local rightArea = gui.Panel{
		id = "rightArea",
        floating = true,
		scale = scale,
		halign = "center",
		x = xdelta,

		flow = "none",

		children = tabPanels,

		showTab = function(element, tabIndex)
			for i,p in ipairs(tabPanels) do
				if p ~= nil then
					local hidden = (tabIndex ~= i)
					p:SetClass("hidden", hidden)
					p:FireEventTree("charsheetActivate", not hidden)
				end
			end
		end,

	}


	local charSheet = gui.Panel{
		id = "characterSheet",

		rightArea,

		refreshToken = function(element, info)
			if info.token.properties.typeName == "character" then
				element:FireEventTree("refreshCharacterInfo", info.token.properties)
			else
				element:FireEventTree("refreshMonster", info.token.properties)
			end
		end,
	}

	local tabsPanel

	local SelectTab = function(id)
        print("SelectTab:: ", id, traceback())
		local index = nil
		for i,tabOption in ipairs(CharSheet.TabOptions) do
			if tabOption.id == id then
				index = i
			end
		end

		if index ~= nil then
			charSheet:FireEventTree("showTab", index, id)
		end
		selectedTab = id

		for i,tab in ipairs(tabsPanel.children) do
			if tab:HasClass("tab") then
				tab:SetClass("selected", tab.data.info.id == id)
			end
		end
	end

	tabsPanel = gui.Panel{
		id = "charsheetTabs",
		-- {tabContainer}: themed header gradient strip. Spans the full sheet
		-- width so the area beside the tabs is covered, not see-through.
		classes = {"tabContainer"},
		floating = true,
		valign = "top",
		halign = "left",
		width = "100%",
		height = 40,
		flow = "horizontal",

		-- The character-sheet harness still runs on the legacy Styles.*
		-- cascade, so the tab strip roots its own ThemeEngine cascade here
		-- (and re-resolves it when the user switches theme / color scheme).
		-- {tabContainer} styles this strip; {tab} styles each tab child.
		styles = ThemeEngine.GetStyles(),

		data = {},

		create = function(element)
			element.data.themeListener = ThemeEngine.OnThemeChanged(mod, function()
				if element.valid then
					element.styles = ThemeEngine.GetStyles()
				end
			end)
		end,

		destroy = function(element)
			if element.data.themeListener ~= nil then
				element.data.themeListener:Deregister()
				element.data.themeListener = nil
			end
		end,

		init = function(element)
			local children = {}
			for _,tabOption in ipairs(CharSheet.TabOptions) do
				children[#children+1] = gui.Label{
					classes = {"tab", cond(tabOption.id == selectedTab, "selected")},
					text = tabOption.text,
					-- Layout only: left-packed, and wider than the theme
					-- default so the strip stays proportionate to the
					-- full-width sheet.
					width = 200,
					halign = "left",
					refreshToken = function(element, info)
						element:SetClass("collapsed", tabOption.visible ~= nil and (not tabOption.visible(info.token.properties)))
					end,
					press = function(element)
						SelectTab(tabOption.id)
					end,
					data = {
						info = tabOption,
					},
				}
			end

			element.children = children
		end,
	}

	tabsPanel:FireEvent("init")

	local resultPanel

	local contextInfo = nil
	

	local args = {
		id = "characterSheetHarness",
		classes = {"characterSheetHarness", cond(dmhub.GetSettingValue("sheet:windowed"), "windowed")},

		borderWidth = 2,
		borderColor = Styles.textColor,
		bgimage = "panels/square.png",

		styles = {
			Styles.Default,
			Styles.Panel,
			{
				selectors = {"#characterSheetHarness", "windowed"},
				transitionTime = 0.2,
				scale = 0.6,
			},
			CharSheet.GetCharacterSheetStyles(),
		},
		--theme = "charsheet.Main",
		flow = "none",
		width = "100%",
		height = "100%",
		halign = "center",
		valign = "center",
		flow = "vertical",

		data = {},

        closeCharacterSheet = function(element)
            dmhub.PopUserRichStatus(element.data.richstatusid)
        end,
		
		escape = function(element)
			for _,p in ipairs(tabPanels) do
				p:FireEventTree("charsheetActivate", false)
			end
			element:FireEventTree("closeCharacterSheet")
			resultPanel:FireEvent("close")
		end,

		show = function(element, info, tabid)
            element.data.richstatusid = dmhub.PushUserRichStatus("Viewing Character Sheet", element.data.richstatusid)
			SelectTab(tabid or CharSheet.defaultSheet)
			resultPanel:PulseClassTree("fadein")
			element:SetClass("collapsed", false)
		end,

		refreshToken = function(element, info)
			contextInfo = info
			element.data.info = contextInfo
		end,

		refreshAll = function(element, info)
			if info ~= nil then
				contextInfo = info
				element.data.info = contextInfo
			end

			if contextInfo ~= nil then
				local sw = dmhub.Stopwatch()
				if contextInfo.token.properties ~= nil then
					contextInfo.token.properties:Invalidate()
					element:FireEventTree("refreshToken", contextInfo)
				end

				element:FireEventTree("refreshAppearance", contextInfo)
				sw:Report("refreshToken")
			end
		end,

		refreshAppearanceOnly = function(element)
			element:FireEventTree("refreshAppearance", element.data.info)
		end,

		toggleAppearance = function(element)
			SelectTab(cond(selectedTab == "Appearance", "CharacterSheet", "Appearance"))
		end,

		remoteUpdate = function(element)
			if element.data.updating then
				return
			end

			element.data.updating = true
			element:FireEvent("refreshAll")
			element.data.updating = false
		end,

		gui.Panel{
			width = "100%",
			height = "100%",
			halign = "center",
			valign = "center",
			flow = "none",

			charSheet,
			tabsPanel,
		},

		gui.Panel{
			flow = "horizontal",
			floating = true,
			width = "auto",
			height = 40,
			halign = "right",
			valign = "top",

			gui.Panel{
				classes = {"iconButton"},
				bgimage = "panels/square.png",
				bgcolor = "black",
				valign = "center",
				borderColor = Styles.textColor,
				borderWidth = 4,
				width = 24,
				height = 24,
				click = function(element)
					dmhub.SetSettingValue("sheet:windowed", not dmhub.GetSettingValue("sheet:windowed"))
					element:Get("characterSheetHarness"):SetClass("windowed", dmhub.GetSettingValue("sheet:windowed"))
				end,
			},

			gui.CloseButton{
				width = 32,
				height = 32,
				valign = "center",
				escapePriority = EscapePriority.EXIT_CHARACTER_SHEET,
				click = function(element)
					resultPanel:FireEvent("escape")
				end,
			},
		}
	}

	for k,param in pairs(params) do
		args[k] = param
	end

	resultPanel = gui.Panel(args)
	g_charSheet = resultPanel
	return resultPanel
end

dmhub.IsDialogOpen = function()
	if g_charSheet ~= nil and g_charSheet.valid and g_charSheet.enabled then
		return true
	end

	if gui.GetModal() ~= nil then
		return true
	end

	if gamehud ~= nil and gamehud.inventoryDialog ~= nil and gamehud.inventoryDialog.valid and gamehud.inventoryDialog.enabled then
		return true
	end

	return false
end
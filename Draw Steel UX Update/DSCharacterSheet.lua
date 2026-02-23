local mod = dmhub.GetModLoading()

-- Scale up the Fonts for the Character Sheet
local fontScaling = 3.0

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
		--color = SwatchBlack,
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
		selectors = {"#ds leftArea"},
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
		selectors = {"#DS bottomRightArea"},
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
		height = "100%",
        --height = "43.5%",
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
		selectors = { "#DS skillsPanel" },
		hmargin = 14,
		width = "40%",
		--width = "28%",
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
		selectors = { "#ds featuresPanel" },
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
		selectors = {"#ds_avatarInnerPanel"},
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
		selectors = {"#DS skillsInnerPanel"},
		flow = "vertical",
	},
	{
		selectors = {"#DS skillsFieldsPanel"},
		flow = "vertical",
		width = "100%",
		height = "92%",
		valign = "center",
		halign = "center",
	},
	{
		selectors = {"#DS skillsHeadingPanel"},
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
		selectors = {"ds skillsProfField"},
		--width = "20%",
		width = "15%",
		height = "100%",
		halign = "center",
	},
	{
		selectors = {"ds skillsModField"},
		width = "30%",
		--width = "15%",
		halign = "center",
	},
	{
		selectors = {"ds skillsSkillField"},
		width = "40%",		
		--width = "50%",
		halign = "left",
	},
	{
		selectors = {"skillsBonusField"},
		width = "20%",
		halign = "right",
		textAlignment = "right",
	},

	{
		selectors = {"#ds_tokenImage"},
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
        bgimage = mod.images.AbilityStatContainer,
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
		bgimage = mod.images.AbilityStatContainer,
		bgcolor = "white",
		borderWidth = 0,        
        --bgimage = "panels/square.png",
		--bgcolor = "clear",
		--borderColor = Styles.textColor,
		--borderWidth = 2,
		--cornerRadius = 4,
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
		bgimage = mod.images.AbilityStatContainer,
        --bgimage = "panels/square.png",
		--bgcolor = "#333333ff",
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
		color = SwatchBlack,
		fontSize = 48,
        fontFace = "Berling",
        fontWeight = "SemiBold",        
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
		--color = "#c0eddf",
		halign = "right",
	},

	{
		selectors = {"valueLabel", "increase"},
		bgimage = "panels/square.png",
		--bgcolor = "green",
		transitionTime = 0.5,
	},
	{
		selectors = {"valueLabel", "decrease"},
		bgimage = "panels/square.png",
		--bgcolor = "red",
		transitionTime = 0.5,
	},

	{
		selectors = {"dice", "hover"},
		--color = "#d0fdef",
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
		selectors = {"ds skillCheck"},
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
		selectors = {"ds skillCheck", "override"},
		bgcolor = "#4444bb",
	},
	{
		selectors = { "ds skillCheck", 'hover' },
		transitionTime = 0.1,
		bgcolor = 'white',
	},

	{
		selectors = { "ds skillBackground" },
		bgimage = 'game-icons/plain-circle.png',
		width = 12,
		height = 12,
		bgcolor = "black",
		halign = "center",
		valign = "center",
	},

	{
		selectors = { "ds skill_untrained" },
		--bgimage = 'game-icons/plain-circle.png',
        bgimage = mod.images.bullet_no,
		bgcolor = "black",
		halign = "left",
		valign = "top",
		width = 8*fontScaling,
		height = 8*fontScaling,
        y = 4,
	},
	{
		selectors = { "ds skill_trained" },
		bgcolor = '#8cdecf',
        bgimage = mod.images.bullet_yes,
        halign = "left",
		valign = "top",
		width = 8*fontScaling,
		height = 8*fontScaling,
        y = 4,
	},
	{
		selectors = { "ds skillFill" },
		bgimage = 'game-icons/plain-circle.png',
		bgcolor = "black",
		halign = "center",
		valign = "center",
		width = 12,
		height = 12,
	},
	{
		selectors = { "ds skillFill", 'parent:proficient' },
		bgcolor = '#8cdecf',
	},
	{
		selectors = { "ds skillFill", 'parent:halfproficient' },
		bgcolor = '#8cdecf',
		bgimage = 'game-icons/half-circle.png',
	},
	{
		selectors = { "ds expertiseLabel" },
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

local ActionsAndFeaturesStyles = {
	{
		selectors = {"statsHeader"},
		width = "90%",
		height = 40,
		flow = "horizontal",
		halign = "center",
		valign = "top",
	},
	CharSheet.TabsStyles,

	{
		selectors = {"ds featuresScrollPanel"},
		width = "100%",
		height = "90%",
		valign = "center",
	},
	{
		selectors = {"ds featuresPanel"},
		width = "97%",
		hmargin = 4,
		halign = "left",
		height = "auto",
	},
	{
		selectors = {"tableData"},
		valign = "center",
	},
	{
		selectors = {"abilityIcon"},
		width = "8%",
	},
	{
		selectors = {"abilityName"},
		width = "22%",
	},
	{
		selectors = {"abilityRange"},
		width = "17%",
	},
	{
		selectors = {"abilityHit"},
		width = "11%",
	},
	{
		selectors = {"abilityDamage"},
		width = "35%",
	},
	{
		selectors = {"abilityEdit"},
		width = "4%",
		height = "auto",
		valign = "center",
	},

	{
		selectors = {"abilitySave"},
		width = "9%",
	},
	{
		selectors = {"abilityEffect"},
		width = "28%",
	},

	{
		selectors = {"abilityUses"},
		width = "11%",
	},

	{
		selectors = {"tableData", "spellTable", "abilityRange"},
		fontSize = 14,
	},

	{
		selectors = {"tableData", "abilitySave"},
		fontSize = 14,
	},

	{
		selectors = {"tableData", "abilityUses"},
		fontSize = 14,
	},

	{
		selectors = {"abilityEditIcon"},
		bgimage = "panels/character-sheet/gear.png",
		bgcolor = "white",
		width = 16,
		height = 16,
		valign = "center",
		halign = "right",
	},
	{
		selectors = {"statsRow"},
		height = "auto",
	},
	{
		selectors = {"abilityIconBackground"},
		height = 32,
		width = 32,
		bgcolor = "white",
		bgimage = 'panels/InventorySlot_Background.png',
	},
	{
		selectors = {"abilityIconIcon"},
		width = "100%",
		height = "100%",
		bgcolor = "white",
	},
	{
		selectors = {"abilityTableTitle"},
		fontSize = "150%",
		halign = "center",
		width = "auto",
		height = "auto",
	},
}


gui.RegisterTheme("charsheet", "Features", ActionsAndFeaturesStyles)


local ChangeLabelValue = function(info, label, newtext)

	if label.data.charid ~= nil and label.data.charid == info.charid and newtext ~= label.text then
		local currentnum = tonumber(label.text)
		local newnum = tonumber(newtext)
		if currentnum ~= nil and newnum ~= nil and currentnum ~= newnum then
			label:PulseClass(cond(currentnum < newnum, "increase", "decrease"))
		end
	end

	label.text = newtext
	label.data.charid = info.charid

	previousCharId = info.charid
	
end

local PopupStyles = {

	{
		valign = 'bottom',
		halign = 'center',
		width = 'auto',
		height = 'auto',
		bgcolor = 'black',
		flow = 'vertical',
		fontSize = 12,
	},
	{
		selectors = {'popupWindow'},
		valign = 'bottom',
		halign = 'center',
		width = 300,
		height = 'auto',
		bgcolor = 'black',
		flow = 'vertical',
		borderWidth = 2,
		borderColor = 'white',
		pad = 6,
	},
	{
		selectors = {'popupPanel'},
		flow = 'horizontal',
		width = 'auto',
		height = 'auto',
		vmargin = 4,
	},
	{
		selectors = {'popupLabel'},
		color = 'white',
		fontSize = 16,
		width = 'auto',
		height = 'auto',
		minWidth = 220,
		valign = "center",
	},
	{
		selectors = {'popupValue'},
		color = 'white',
		fontSize = 16,
		width = 'auto',
		height = 'auto',
		minWidth = 40,
	},

	{
		selectors = {"formPanel"},
		flow = "horizontal",
		width = '100%',
		height = 20,
	},
	{
		selectors = {'editable'},
		color = '#aaaaff',
		priority = 2,
	},
	{
		selectors = {'option'},
		bgcolor = 'black',
		width = '100%',
		height = 20,
	},
	{
		selectors = {'option','selected'},
		bgcolor = '#880000',
	},
	{
		selectors = {'option','hover'},
		bgcolor = '#880000',
	},
	{
		selectors = {'input'},
		bold = true,
		fontFace = "inter",
		fontSize = 14,
		height = 18,
		width = 180,
	},
}

-- Define colors based on Kelsey's swatches in the components figma
-- https://www.figma.com/design/7w8B3fjUaz9YX6GxS00Un6/Design-System---TEMP-IMPORT?node-id=1-352&t=IL2AX1ioJlm2LJTL-1

SwatchWhite     = "#FFFFFF"
SwatchLight     = "#E8E8E8"
SwatchNeutral1  = "#ABABAB"
SwatchNeutral2  = "#6F6F6F"
SwatchBlack     = "#000000"

SwatchCnB       = "#231F20"

local DSCharacterSheet = {}

-- Define Font Styles based on the components figma
local BuilderStyles = {
    {
        selectors = {"FontNumbers"},
        fontSize = 16*fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },
    {
        selectors = {"Header1"},
        fontSize = 12*fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },
    {
        selectors = {"Header2"},
        fontSize = 8*fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        uppercase = true,
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },
    {
        selectors = {"Subheader"},
        fontSize = 6*fontScaling,
        fontFace = "Berling",
        fontWeight = "Regular",
        uppercase = true,
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },
    {
        selectors = {"SubheaderBold"},
        fontSize = 6*fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        uppercase = true,
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },    
    {
        selectors = {"Body"},
        fontSize = 8*fontScaling,
        fontFace = "Berling",
        fontWeight = "Regular",
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },     
    {
        selectors = {"BodyBold"},
        fontSize = 8*fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },    
    {
        selectors = {"Details"},
        fontSize = 7*fontScaling,
        fontFace = "Berling",
        fontWeight = "Regular",
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },
    {
        selectors = {"Details_Skill_Untrained"},
        fontSize = 7*fontScaling,
        fontFace = "Berling",
        fontWeight = "Regular",
        color = SwatchNeutral1,
        width = "auto",
        height = 10*fontScaling,
        valign = "top",
        lmargin = 8,
    }, 
    {
        selectors = {"Details_Skill_Trained"},
        fontSize = 7*fontScaling,
        fontFace = "Berling",
        fontWeight = "Regular",
        color = '#8cdecf',
        width = "auto",
        height = 10*fontScaling,
        valign = "top",
        lmargin = 8,
    },     
    {
        selectors = {"DetailsBold"},
        fontSize = 7*fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },   
    {
        selectors = {"Annotation*"},
        fontSize = 6*fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },   
    {
        selectors = {"panel_bg_hero"},
        bgcolor = SwatchNeutral1
    },
    {
        selectors = {"panel_bg_monster"},
        bgcolor = "#910d0d",
		borderColor = 'red',
    },    
    {
        selectors = {"panel_hero_filled"},
		bgimage = "panels/character-sheet/Flag2_bar.png",
		bgcolor = "white",
		halign = "center",
		valign = "top",
		width = 260,
		height = 50,
		borderWidth = 1,
		borderColor = SwatchNeutral2,
		--cornerRadius = 16, 
		--beveledcorners = true,
		--bgcolor = SwatchLight,
		--bgcolor = "red",        
		--bgimage = "panels/square.png",
		flow = "vertical",
		opacity = 0.9,
		--interactable = false,
    },	
	{
		selectors = {"panel_hero_label"},
		fontSize = 12,
		fontFace = "Berling",
		fontWeight = "Regular",
		color = "#c0eddf",
		height = "auto",            
		valign = "top",
		halign = "center",
		width = "auto",
		bmargin = 8,
				
	},
}
-- Incrementally pulling functions from the old character sheet as part of rebuilding the Draw Steel character sheet
function SkillDisplayParser(skillInput)
    local SkillColor = SwatchNeutral1
    local resultPanel
    local skillInfo = Skill.FindByName(skillInput)
    print("The skill is", skillInfo.name, "and the id is", skillInfo.id)
    
    resultPanel = gui.Panel{
        flow = "horizontal",
        valign = "top",
        height = "auto",
        gui.Panel{
            refreshToken = function (element, info)
                local proficient = info.token.properties:ProficientInSkill(skillInfo)
                if proficient == true then
                    element:SetClass("skill_trained", true)
                    print("dj Character is trained in", skillInfo.name, "and the id is", skillInfo.id)
                    print("dj the proficiency value is", proficient)
                    skillColor = '#8cdecf'
                else
                    element:SetClass("skill_untrained", true)
                    print("dj Character is untrained in", skillInfo.name, "and the id is", skillInfo.id)
                    print("dj the proficiency value is", proficient)
                end
            end
        },
        gui.Label{
            refreshToken = function (element, info)
                local proficient = info.token.properties:ProficientInSkill(skillInfo)
                if proficient == true then
                    element:SetClass("Details_Skill_Trained", true)
                else
                    element:SetClass("Details_Skill_Untrained", true)
                end
            end,
            text = skillInput,
        }
    }
    return resultPanel
end

local function concatdc(dc)
	if type(dc) == "table" then
		return table.concat(dc, "/")
	else
		return dc
	end
end

local CreatePanelFooter = function(args)
	local resultPanel
	local text = args.text or ""
	args.text = nil

	--only show settings button if we have a 'settings' arg to handle it.
	local settingsButton = nil
	if args.settings ~= nil then
		settingsButton = gui.Panel{
			classes = {"panelSettingsButton"},
			click = function(element)
				resultPanel:FireEvent("settings")
			end,
		}
	end

	local params = {
		classes = {"panelFooter"},
		interactable = false,
		gui.Label{
			classes = {"panelFooterLabel"},
			text = text,
		},

		settingsButton,
	}

	for k,v in pairs(args) do
		params[k] = v
	end

	resultPanel = gui.Panel(params)
	return resultPanel
end
----------------------------------------------------------------------------
-- The top panel area that includes the character attributes
----------------------------------------------------------------------------
function CharSheet.AttrPanel(attrid)
	local resultPanel

    
	resultPanel = gui.Panel{
		classes = {"attributePanel"},

		gui.Panel{
			classes = {"attributeModifierPanel"},
			gui.Label{
				classes = {"attributeStatLabel"},
                textWrap = false,
                --classes = {"attributeModifierLabel", "valueLabel", "dice"},
				refreshToken = function(element, info)
					ChangeLabelValue(info, element, ModifierStr(info.token.properties:GetAttribute(attrid):Modifier()))
				end,
				press = function(element)
					CharacterSheet.instance.data.info.token.properties:RollAttributeCheck(attrid)
				end,
                rightClick = function(element)
                    if CharacterSheet.instance.data.info.token.properties.typeName == "monster" then
                        element:BeginEditing()
                    end
                end,
                change = function(element)
                    CharacterSheet.instance.data.info.token.properties.attributes[attrid].baseValue = tonumber(element.text) or 0
					CharacterSheet.instance:FireEvent('refreshAll')
                end,
			},			
		},

		gui.Label{
			classes = {"attrLabel","attributeIdLabel"},
			text = string.upper(attrid),
		},
	}

	return resultPanel
end

----------------------------------------------------------------------------
-- The Avatar Panel to the Left Side of the Sheet
----------------------------------------------------------------------------
function DSCharacterSheet.CharacterSheetAvatarPanel()
	local controllerDropdown
	if dmhub.isDM then
		controllerDropdown = gui.Dropdown{
			width = 220,
			height = 26,
			vmargin = 4,
			fontSize = 15,
			halign = "center",
			refreshToken = function(element, info)
				if info.token.charid == nil then
					element:SetClass("hidden", true)
					return
				end

				element:SetClass("hidden", false)

				local options = {
					{
						id = "gm",
						text = "GM Controlled",
					},
				}

				local partyids = GetAllParties()
				for _,partyid in ipairs(partyids) do
					local party = GetParty(partyid)
					options[#options+1] = {
						id = partyid,
						text = party.name
					}
				end

				for _,userid in ipairs(dmhub.users) do
					local sessionInfo = dmhub.GetSessionInfo(userid)
					if not sessionInfo.dm then
						options[#options+1] = {
							id = userid,
							text = sessionInfo.displayName,
						}
					end
				end

				element.options = options

				local ownerId = info.token.ownerId
				if ownerId == "PARTY" then
					element.idChosen = info.token.partyId
				elseif ownerId ~= nil and ownerId ~= "" then
					element.idChosen = ownerId
				else
					element.idChosen = "gm"
				end
			end,

			change = function(element)
				if element.idChosen == "gm" then
					CharacterSheet.instance.data.info.token.ownerId = nil
				elseif GetParty(element.idChosen) ~= nil then
					CharacterSheet.instance.data.info.token.partyId = element.idChosen
				else
					CharacterSheet.instance.data.info.token.ownerId = element.idChosen
				end
			end,
		}
	end


	local resultPanel
	resultPanel = gui.Panel{
		id = "ds_avatarInnerPanel",
		classes = {"statsPanel"},
		vscroll = true,
        valign = "top",

		gui.Panel{
			id = "ds_tokenImage",

			gui.CreateTokenImage(nil, {
				width = "100%",
				height = "100%",

				refreshAppearance = function(element, info)
					element:FireEventTree("token", info.token)
				end,
				
			}),

			gui.Panel{
				id = "ds_avatarOverlay",
				width = "100%",
				height = "100%",
				bgimage = "panels/square.png",
				bgcolor = "black",

				click = function(element)
					CharacterSheet.instance:FireEvent("toggleAppearance")
				end,

				styles = {
					{
						selectors = {"#ds_avatarOverlay"},
						opacity = 0,
					},
					{
						selectors = {"#ds_avatarOverlay", "hover"},
						opacity = 0.8,
						transitionTime = 0.2,
					},
					{
						selectors = {"parent:press"},
						brightness = 0.7,
						transitionTime = 0.2,
					},
				},

				gui.Label{
					width = "100%",
					height = "20%",
					halign = "center",
					valign = "center",
					bgimage = "panels/square.png",
					bgcolor = "black",
					text = "Customize Appearance",
					color = "white",
					textAlignment = "center",
					fontSize = 14,
					interactable = false,

					styles = {
						{
							opacity = 0,
						},
						{
							selectors = {"parent:hover"},
							opacity = 1,
							transitionTime = 0.2,
						},
						{
							selectors = {"parent:press"},
							brightness = 0.7,
							transitionTime = 0.2,
						},
					},

				},
			},
		},

		controllerDropdown,



		gui.Panel{
            styles = BuilderStyles,
			classes = {"panel_hero_filled"},
            --id = "characterAncestryPanel",        
		    CharSheet.CharacterNameLabel(),
            
--[[
            gui.Label{
                classes = {"statsLabel", "heading"},
                valign = "center",
                halign = "center",
                width = "100%-18",
                minFontSize = 12,
                textWrap = false,
                textAlignment = "center",
                editable = true,
                refreshAppearance = function(element, info)
                    element:SetClass("collapsed", info.token.properties == nil or element.text == "")
                end,
                refreshToken = function(element, info)
                    element.text = info.token.properties:try_get("monster_type", "")
                    if info.token.properties:IsMonster() and element.text == "" then
                        element.text = "(No monster type)"
                        element:SetClass("invalid", true)
                    else
                        element:SetClass("invalid", false)
                    end
                end,
                change = function(element)
                    local info = CharacterSheet.instance.data.info
                    info.token.properties.monster_type = element.text
                    CharacterSheet.instance:FireEvent("refreshAll")
                end,
            },
]]            
        },
        gui.Label{
            styles = BuilderStyles,
			classes = {"panel_hero_label"},
            text = "Name",
        },
        ----------------------------------------
        -- Ancestry Box
        ----------------------------------------
        gui.Panel{
            styles = BuilderStyles,
			classes = {"panel_hero_filled"},
            beveledcorners = true,
            refreshToken = function(element, info)
                if info.token.properties:IsMonster() then
                    element:SetClass("panel_bg_hero", false)
                    element:SetClass("panel_bg_monster", true)                    
                else
                    element:SetClass("panel_bg_monster", false)   
                    element:SetClass("panel_bg_hero", true)
                end
            end,
            styles = BuilderStyles,
			classes = {"panel_hero_filled"},
            interactable = false,
    
            gui.Label{
                id = "ds_CharacterAncestryLabel",
                classes = {"statsLabel", "editableLabel", "heading"},
                halign = "center",
                valign = "center",
                refreshAppearance = function(element, info)
                    element:SetClass("collapsed", info.token.properties == nil)
                end,
                refreshToken = function(element, info)
                    if info.token.properties:IsMonster() then
                        element.text = info.token.properties:try_get("monster_type", "")
                        if info.token.properties:IsMonster() and element.text == "" then
                            element.text = "(No monster type)"
                            element:SetClass("invalid", true)
                        else
                            element:SetClass("invalid", false)
                        end
                        --element.text = info.token.properties:RaceOrMonsterType()
                        --element.text = creature.GetTokenDescription(element)
                    else
                        element.text = info.token.properties:RaceOrMonsterType()
                    end
                end    
            },
        },
        gui.Label{  
            styles = BuilderStyles,
			classes = {"panel_hero_label"},
            text = "Ancestry",
            refreshToken = function(element, info)
                if info.token.properties:IsMonster() then
                    element.text = "Monster Entry"
                else
                    element.text = "Ancestry"
                end
            end
        },		

        -- CLASS
        gui.Panel{
            styles = BuilderStyles,
			classes = {"panel_hero_filled"},       
            gui.Panel{
                id = "characterLevelsPanel",
                classes = {},

                refreshAppearance = function(element, info)
                    element:SetClass("collapsed", info.token.properties == nil or info.token.properties.typeName ~= "character")
                end,

                refreshCharacterInfo = function(element, character)

                    local currentPanels = element.children


                    local classesTable = dmhub.GetTable('classes')
                    local children = {}

                    local classes = character:get_or_add("classes", {})
                    for i,entry in ipairs(classes) do
                        local classInfo = classesTable[entry.classid]
                        if classInfo ~= nil then
                            local label = currentPanels[i] or gui.Label{
                                classes = {"statsLabel", "classLevelLabel", "heading"},
                            }

                            label.text = string.format("%s %d", classInfo.name, entry.level)

                            children[#children+1] = label
                        elseif info.token.properties:IsMonster() then
                            local label = currentPanels[i] or gui.Label{
                                classes = {"statsLabel", "classLevelLabel", "heading"},
                            }

							label.text = info.token.properties.role

                            children[#children+1] = label
						end
                    end

                    element.children = children
                end
            },
        },
        gui.Label{  
            styles = BuilderStyles,
			classes = {"panel_hero_label"},
            text = "Class",
            refreshToken = function(element, info)
                if info.token.properties:IsMonster() then
                    element.text = "Monster Role"
                else
                    element.text = "Class"
                end
            end
        },	    

        -- SUBCLASS
        gui.Panel{
            styles = BuilderStyles,
			classes = {"panel_hero_filled"},       
            gui.Panel{
                id = "characterLevelsPanel",
    
                --This function is called by the character sheet system when the displayed token is updated. Here we just hide the
                --panel if a monster is being shown. But we can probably get rid of this for the Codex?
                refreshAppearance = function(element, info)
                    element:SetClass("collapsed", info.token.properties == nil or info.token.properties.typeName ~= "character")
                end,
    
                --this function is called by the character sheet system whenever there is a CHARACTER ("hero") in the character sheet. It's not called if displaying a monster.
                --For the Codex, character sheets are probably ONLY for characters, so we don't even have to worry about monsters being shown?
                refreshCharacterInfo = function(element, character)
    
                    --this is the panels the class has with whatever it was showing previously. It's good for performance to
                    --reuse panels rather than destroy them so we are effectively building a new list of child panels here but
                    --reusing what we can.
                    local currentChildren = element.children
    
                    local children = {}
    
                    local subclasses = character:GetSubclasses()
                    for i,subclass in ipairs(subclasses) do
                        local label = currentChildren[i] or gui.Label{
                            classes = {"statsLabel", "classLevelLabel"},
                        }
                        label.text = subclass.name
                        children[#children+1] = label
                    end
    
                    --make sure any added child panels get added back in.
                    if #children ~= #currentChildren then
                        element.children = children
                    end
                end,
            },
        },
        gui.Label{
            styles = BuilderStyles,
			classes = {"panel_hero_label"},
            text = "Subclass",
        },    

		gui.Label{
			classes = {"link", "statsLabel"},
			fontSize = 11,
			halign = "center",
			valign = "top",
			text = "Source",
			refreshAppearance = function(element, info)
				element:SetClass("collapsed", info.token.properties == nil or info.token.properties:try_get("source") == nil)
				if element:HasClass("collapsed") == false then
					element.text = dmhub.DescribeDocument(info.token.properties.source)
				end
			end,
			click = function(element)
				local info = CharacterSheet.instance.data.info
				dmhub.OpenDocument(info.token.properties.source)
			end,
		},

	}
	return resultPanel
end

local CreatePanelFooter = function(args)
	local resultPanel
	local text = args.text or ""
	args.text = nil

	--only show settings button if we have a 'settings' arg to handle it.
	local settingsButton = nil
	if args.settings ~= nil then
		settingsButton = gui.Panel{
			classes = {"panelSettingsButton"},
			click = function(element)
				resultPanel:FireEvent("settings")
			end,
		}
	end

	local params = {
		classes = {"panelFooter"},
		interactable = false,
		gui.Label{
			classes = {"panelFooterLabel"},
			text = text,
		},

		settingsButton,
	}

	for k,v in pairs(args) do
		params[k] = v
	end

	resultPanel = gui.Panel(params)
	return resultPanel
end

----------------------------------------------------------------------------
-- Health and Recoveries Section
----------------------------------------------------------------------------
function CharSheet.CharacterHitpointsPanel()

	local mainHitpointsPanel =
	gui.Panel({
		style = {
			halign = 'center',
			valign = 'top',
			pad = 0,
			hmargin = 0,
			vmargin = 5,
			height = 80,
			width = 240,
			flow = 'horizontal',
		},


		styles = {
			gui.Style{
				selectors = {"hitpointsValueLabel"},
				fontSize = 32,
				valign = "bottom",
			},
			gui.Style{
				selectors = {"actualHitpoints"},
				color = "#44894f",
				minWidth = 80,
				minHeight = 80,
				textAlignment = "center",
			},
		},

		events = {
			edit = function(element, editing)
				element:SetClass('collapsed', editing)
			end,
		},

		children = {
			--current hitpoints panel.
			gui.Panel({
				id = 'CurrentHitpointsPanel',
				bgimage = 'panels/square.png',
				style = {
					width = "30%",
					height = "100%",
					flow = 'vertical',
					borderWidth = 0,
					vmargin = 0,
				},

				children = {
					gui.Label({
						text = 'CURRENT',
						classes = {"statsLabel"},
					}),
					gui.Label({
						classes = {"statsLabel", "hitpointsValueLabel", "actualHitpoints"},
						text = 'HP',
						editable = true,
						characterLimit = 3,

						events = {
							change = function(element)
								local creature = CharacterSheet.instance.data.info.token.properties
								creature:SetCurrentHitpoints(element.text)
								element.data.previous_value = nil --don't flash green/red on an edit.
								CharacterSheet.instance:FireEvent('refreshAll')
							end,

							refreshToken = function(element, info)
								local creature = info.token.properties
								local newValue = creature:CurrentHitpoints()
								ChangeLabelValue(info, element, tostring(newValue))
							end,
						},
					}),
				},
			}),

			--the slash separating current from max hitpoints
			gui.Panel({
				style = {
					width = "10%",
					height = "100%",
					flow = 'vertical',
					vmargin = 0,
				},

				children = {
					gui.Label({
						classes = {"statsLabel"},
						text = '',

					}),
					gui.Label({
						classes = {"statsLabel", "hitpointsValueLabel"},
						text = '/',

					}),

				},
			}),

			--max hitpoints.
			gui.Panel({
				id = 'MaxHitpointsPanel',
				style = {
					width = "28%",
					height = "100%",
					flow = 'vertical',
					borderWidth = 0,
					vmargin = 0,
				},

				children = {
					gui.Label({
						text = 'MAX',
						classes = {"statsLabel"},
					}),
					gui.Label({
						text = 'HP',
						characterLimit = 3,
						classes = {"statsLabel", "hitpointsValueLabel", "actualHitpoints"},
						editable = true,
						events = {
							change = function(element)
								local creature = CharacterSheet.instance.data.info.token.properties
								creature:SetMaxHitpoints(element.text)

								if creature:IsMonster() and element.text ~= "" then
									creature.max_hitpoints_roll = element.text
								end

								CharacterSheet.instance:FireEvent('refreshAll')
							end,

							refreshToken = function(element, info)
								local creature = info.token.properties
								element.editable = creature:IsMonster()
								local newValue = creature:MaxHitpoints()
								ChangeLabelValue(info, element, tostring(newValue))
							end,

						},

						gui.Panel{
							classes = {"hitpointsReroll"},

							refreshToken = function(element, info)
								element:SetClass("hidden", not info.token.properties:IsMonster())
							end,

							click = function(element)
								local creature = CharacterSheet.instance.data.info.token.properties

								creature:RerollHitpoints()
								CharacterSheet.instance:FireEvent('refreshAll')
							end,

							linger = function(element)
								local creature = CharacterSheet.instance.data.info.token.properties
								local text = creature.max_hitpoints_roll .. '\nClick to re-roll HP.'
								gui.Tooltip(text)(element)
							end,
						}
					}),

				},
			}),

			--temp. hitpoints.
			gui.Panel({
				id = 'TempHitpointsPanel',
				bgimage = 'panels/square.png',
				style = {
					width = "24%",
					height = "100%",
					flow = 'vertical',
					borderWidth = 0,
					vmargin = 0,
				},

				children = {
					gui.Label({
						text = 'TEMP',
						classes = {"statsLabel"},
					}),
					gui.Panel{
						width = 80,
						height = 80,
						interactable = false,
						gui.Label({
							text = '--',
							halign = "center",
							valign = "center",
							minWidth = 70,
							minHeight = 40,
							textAlignment = "center",
							characterLimit = 3,
							classes = {"statsLabel", "hitpointsValueLabel"},
							editable = true,
							events = {
								change = function(element)
									local creature = CharacterSheet.instance.data.info.token.properties
									creature:SetTemporaryHitpoints(element.text)
									element.data.previous_value = nil
									CharacterSheet.instance:FireEvent('refreshAll')
								end,

								refreshToken = function(element, info)
									local creature = info.token.properties
									ChangeLabelValue(info, element, creature:TemporaryHitpointsStr())
								end,
							},
						}),
					}

				},
			}),

		},
	})

	local healDamagePanel = gui.Panel{
		flow = "vertical",
		width = "auto",
		height = "100%",

		gui.Panel{
			classes = {"healDamage", "background", "heal"},
			press = function(element)
				element.children[1].hasFocus = true
			end,
			gui.Input{
				classes = {"healDamage", "heal"},
				text = '',
				characterLimit = 8,
				placeholderText = 'HEAL',
				events = {
					change = function(element)
						local creature = CharacterSheet.instance.data.info.token.properties
						creature:Heal(element.text)
						element.text = ''
						CharacterSheet.instance:FireEvent('refreshAll')
					end,

					edit = function(element, editing)
						element:SetClass('hidden', editing)
					end,
				},
			},
		},

		gui.Panel{
			classes = {"healDamage", "background", "damage"},
			press = function(element)
				element.children[1].hasFocus = true
			end,
			gui.Input{
				classes = {"healDamage", "damage"},
				text = '',
				characterLimit = 8,
				placeholderText = 'DAMAGE',
				events = {
					change = function(element)
						local creature = CharacterSheet.instance.data.info.token.properties
						creature:TakeDamage(element.text)
						element.text = ''
						CharacterSheet.instance:FireEvent('refreshAll')
					end,

					edit = function(element, editing)
						element:SetClass('hidden', editing)
					end,
				},
			},
		},

	}

	return gui.Panel({
		id = 'hitpointsInnerPanel',
		theme = "charsheet.Hitpoints",

		children = {

			healDamagePanel,
			
			mainHitpointsPanel,

			gui.Panel({
				y = 3,
				style = {
					pad = 0,
					width = '100%',
					height = 30,
					fontSize = '60%',
					halign = 'center',
					valign = 'bottom',
					textAlignment = 'center',
					flow = 'none',
				},
			})
		}
	})
	
end

----------------------------------------------------------------------------
-- The Skills Panel of Doom!
----------------------------------------------------------------------------
function DSCharacterSheet.CharacterSheetSkillsPanel()
    local SkillTextColor = SwatchNeutral2
    local resultPanel
    local columnMargin01 = 8
    local columnMargin02 = 110
    local lineHeight = 14
    resultPanel = gui.Panel{
        styles = BuilderStyles,
        classes = {"characterSheetPanel"},
        --classes = {"statsPanel"},
        flow = "vertical",
        valign = "top",
        width = 512,
        height = 800,
        bgcolor = "white",
        vscroll = true,
        
        
        -- Crafting
        gui.Label{
            classes = {"Body"},
            text = "Crafting",
            width = "auto",
            height = "auto",
            valign = "top",
            tmargin = 5*lineHeight,
            lmargin = columnMargin01,
            color = SkillTextColor
        },
        gui.Divider{
            width = 400,          
            valign = "top",
        },
        gui.Panel{
            flow = "horizontal",
            gui.Panel{
                flow = "vertical",
                lmargin = columnMargin01,
                valign = "top",
                height = "auto",                
                SkillDisplayParser("Alchemy"),
                SkillDisplayParser("Blacksmithing"),
                SkillDisplayParser("Cooking"),
                SkillDisplayParser("Forgery"),
                SkillDisplayParser("Mechanics"),
            },
            gui.Panel{
                flow = "vertical",
                lmargin = columnMargin02,
                valign = "top",
                height = "auto",                
                SkillDisplayParser("Architecture"),
                SkillDisplayParser("Carpentry"),
                SkillDisplayParser("Fletching"),
                SkillDisplayParser("Jewelry"),
                SkillDisplayParser("Tailoring"),
            }          
        },

        -- Exploration
        gui.Label{
            classes = {"Body"},
            text = "Exploration",
            width = "auto",
            height = "auto",
            valign = "top",
            lmargin = columnMargin01,
            tmargin = 5*lineHeight,
            color = SkillTextColor
        },    
        gui.Divider{
            width = 400,        
            valign = "top",
        },
        gui.Panel{
            flow = "horizontal",
            gui.Panel{
                flow = "vertical",
                lmargin = columnMargin01,
                valign = "top",
                height = "auto",                 
                SkillDisplayParser("Climb"),
                SkillDisplayParser("Endurance"),
                SkillDisplayParser("Heal"),
                SkillDisplayParser("Lift"),
                SkillDisplayParser("Ride"),
            },
            gui.Panel{
                flow = "vertical",
                lmargin = columnMargin02,
                valign = "top",
                height = "auto",                 
                SkillDisplayParser("Drive"),
                SkillDisplayParser("Gymnastics"),
                SkillDisplayParser("Jump"),
                SkillDisplayParser("Navigate"),
                SkillDisplayParser("Swim"),
            }          
        },        

        -- Interpersonal
        gui.Label{
            classes = {"Body"},
            text = "Interpersonal",
            width = "auto",
            height = "auto",
            valign = "top",
            lmargin = columnMargin01,
            tmargin = 5*lineHeight,            
            color = SkillTextColor
 
        },
        gui.Divider{
            width = 400,
            --height = "auto",            
            valign = "top",
        },
        gui.Panel{
            flow = "horizontal",
            gui.Panel{
                flow = "vertical",
                lmargin = columnMargin01,
                valign = "top",
                height = "auto",                 
                SkillDisplayParser("Brag"),
                SkillDisplayParser("Flirt"),
                SkillDisplayParser("Handle Animals"),
                SkillDisplayParser("Intimidate"),
                SkillDisplayParser("Lie"),
                SkillDisplayParser("Persuade"),
            },
            gui.Panel{
                flow = "vertical",
                lmargin = columnMargin02,
                valign = "top",
                height = "auto",                 
                SkillDisplayParser("Empathize"),
                SkillDisplayParser("Gamble"),
                SkillDisplayParser("Interrogate"),
                SkillDisplayParser("Lead"),
                SkillDisplayParser("Music"),
                SkillDisplayParser("Read Person"),
            }          
        },        

        -- Intrigue
        gui.Label{
            classes = {"Body"},
            text = "Intrigue",
            width = "auto",
            height = "auto",
            valign = "top",
            lmargin = columnMargin01,
            tmargin = 6*lineHeight,  
            color = SkillTextColor
        },
        gui.Divider{
            width = 400,
            valign = "top",
        },
        gui.Panel{
            flow = "horizontal",
            gui.Panel{
                flow = "vertical",
                lmargin = columnMargin01,
                valign = "top",
                height = "auto",                 
                SkillDisplayParser("Alertness"),
                SkillDisplayParser("Disguise"),
                SkillDisplayParser("Escape Artist"),
                SkillDisplayParser("Performance"),
                SkillDisplayParser("Pick Pocket"),
                SkillDisplayParser("Search"),
                SkillDisplayParser("Track"),
            },
            gui.Panel{
                flow = "vertical",
                lmargin = columnMargin02,
                valign = "top",
                height = "auto",                 
                SkillDisplayParser("Conceal Object"),
                SkillDisplayParser("Eavesdrop"),
                SkillDisplayParser("Hide"),
                SkillDisplayParser("Pick Lock"),
                SkillDisplayParser("Sabotage"),
                SkillDisplayParser("Sneak"),
            }          
        },        

        -- Lore
        gui.Label{
            classes = {"Body"},
            text = "Lore",
            width = "auto",
            height = "auto",
            valign = "top",
            lmargin = columnMargin01,
            tmargin = 7*lineHeight,  
            color = SkillTextColor
        },
        gui.Divider{
            width = 400,
            valign = "top",
        },
        gui.Panel{
            flow = "horizontal",
            gui.Panel{
                flow = "vertical",
                lmargin = columnMargin01,
                valign = "top",
                height = "auto",                 
                SkillDisplayParser("Culture"),
                SkillDisplayParser("History"),
                SkillDisplayParser("Monsters"),
                SkillDisplayParser("Psionics"),
                SkillDisplayParser("Rumors"),
                SkillDisplayParser("Strategy"),
            },
            gui.Panel{
                flow = "vertical",
                lmargin = columnMargin02,
                valign = "top",
                height = "auto",                 
                SkillDisplayParser("Criminal Underworld"),
                SkillDisplayParser("Magic"),
                SkillDisplayParser("Nature"),
                SkillDisplayParser("Religion"),
                SkillDisplayParser("Society"),
                SkillDisplayParser("Timescape"),
            }          
        },   
		refreshToken = function(element, info)
			element:SetClass("collapsed", false)
			if info.token.properties:IsMonster() then
				element:SetClass("collapsed", true)
			else
				--element:SetClass("collapsed", true)
			end
		end,     
    }
    return resultPanel
end

function DSCharacterSheet.MonsterPanel()
	local resultPanel
	resultPanel = gui.Panel{
		refreshToken = function(element, info)
			element:SetClass("collapsed", false)
			--local monsterEntry = assets.monsters[nodeid]
			--local monsterEntry = assets.monsters[nodeid]
			local monsterEntry = info.token.properties

			--if monsterEntry == nil then
			--	return
			--end

			element.children = {
				info.token.properties:Render({width = 400}, {token = info.token})
			 }

			--info.token.properties:Render({width = 400}, {token = info.token})

			if info.token.properties:IsMonster() then
				--element:SetClass("collapsed", true)
			else
				element:SetClass("collapsed", true)
			end
		end, 
	}
	return resultPanel
end

function DSCharacterSheet.CharacterSheetSkillsPanelLegacy()

	local rowsCache = {}

	local resultPanel
	resultPanel = gui.Panel{
		--styles = CharacterSheetStyles,
		id = "DS skillsInnerPanel",
		classes = {"statsPanel"},

		gui.Panel{
			id = "DS skillsHeadingPanel",
			classes = {"statsRow", "skills"},
			gui.Label{
				classes = {"statsLabel","ds skillsProfField"},
				text = "TRAINED",
			},
			gui.Label{
				classes = {"statsLabel","ds skillsModField"},
				text = "GROUP",
			},
			gui.Label{
				classes = {"statsLabel","ds skillsSkillField"},
				text = "SKILL",
			},
--			gui.Label{
--				classes = {"statsLabel","ds skillsBonusField"},
--				text = "BONUS",
--			},
		},

		gui.Panel{
			id = "DS skillsFieldsPanel",
			vscroll = true,

			refreshToken = function(element, info)
				local children = {}
				local newRowsCache = {}
				for i,skillInfo in ipairs(Skill.SkillsInfo) do
					local row = rowsCache[skillInfo.id] or gui.Panel{
						classes = {"statsRow", "skills"},

						gui.Panel{
							classes = {"ds skillsProfField"},
							gui.Panel{
								classes = {"ds skillCheck",},
								data = {
									proficiencyid = nil,
								},

								gui.Panel{
									classes = {"ds skillBackground"},
									interactable = false,
								},

								gui.Panel{
									classes = {"ds skillFill"},
									interactable = false,
								},

								gui.Label{
									classes = {"ds expertiseLabel"},
									interactable = false,
									text = "",
									refreshToken = function(element, info)
										local proficiencyInfo = info.token.properties:SkillProficiencyLevel(skillInfo)
										if proficiencyInfo.characterSheetLabel == nil then
											element:SetClass("hidden", true)
										else
											element:SetClass("hidden", false)
											element.text = proficiencyInfo.characterSheetLabel
										end

									end,
								},

								refreshToken = function(element, info)

									local proficiency = info.token.properties:SkillProficiencyLevel(skillInfo)
									element:SetClass('override', info.token.properties:SkillProficiencyOverridden(skillInfo))

									if proficiency.id ~= element.data.proficiencyid then
										if element.data.proficiencyid ~= nil then
											element:SetClass(string.format("proficiency-%s", element.data.proficiencyid), false)
										end
										element.data.proficiencyid = proficiency.id
										element:SetClass(string.format("proficiency-%s", element.data.proficiencyid), true)
									end

									if proficiency.multiplier >= 1 then
										element:SetClass('proficient', true)
										element:SetClass('halfproficient', false)
									elseif proficiency.multiplier > 0 then
										element:SetClass('proficient', false)
										element:SetClass('halfproficient', true)
									else
										element:SetClass('proficient', false)
										element:SetClass('halfproficient', false)
									end

								end,

								click = function(element)

									local isMonster = info.token.properties:IsMonster()

										--monsters just toggles skills directly.
										--info.token.properties:ToggleSkillProficiency(skillInfo)

									--characters have calculation breakdowns for skills and can have them overridden.
									local popupParentElement = element

									local options = DeepCopy(creature.GetProficiencyDropdownOptions())
									table.insert(options, 1, {
										id = nil,
										text = "No Override",
									})

									if isMonster then
										options = {
											{
												id = "none",
												text = "Not Proficient",
												value = false,
											},
											{
												id = "proficient",
												text = "Proficient",
												value = true,
											},
											{
												id = "custom",
												text = "Custom Modifier",
											},
										}
									end

									local optionToDescription = {}
									for i,option in ipairs(options) do
										if option.id ~= nil then
											optionToDescription[option.id] = option.text
										end
									end

									local customInput = nil
									local proficiencyOverride
									
									if isMonster then
										proficiencyOverride = info.token.properties.skillRatings[skillInfo.id]
										customInput = gui.Input{
											placeholderText = "Enter Custom Modifier",
											text = cond(proficiencyOverride == nil or proficiencyOverride == true, "", tostring(proficiencyOverride)),
											width = 140,
											height = 18,
											fontSize = 14,
											characterLimit = 5,
											halign = "left",
											classes = {cond(proficiencyOverride == nil or proficiencyOverride == true, "collapsed")},
											change = function(element)
												info.token.properties:SetSkillRating(skillInfo, element.text)
												CharacterSheet.instance:FireEvent('refreshAll')
												popupParentElement.popup = nil
											end,
										}

										if proficiencyOverride == nil then
											proficiencyOverride = 'none'
										elseif proficiencyOverride == true then
											proficiencyOverride = 'proficient'
										else
											proficiencyOverride = 'custom'
										end


									else
										proficiencyOverride = info.token.properties.skillProficiencies[skillInfo.id]
										if proficiencyOverride == true then
											proficiencyOverride = 'proficient'
										end
									end

									local panels = {}
									panels[#panels+1] = gui.Label{
										text = string.format("%s (%s) Skill", skillInfo.name, string.upper(skillInfo.attribute)),
										bold = true,
									}

									if not isMonster then
										local log = {}
										local proficiencyLevel = info.token.properties:BaseSkillProficiencyLevel(skillInfo, log)

										for i,entry in ipairs(log) do
											panels[#panels+1] = gui.Panel{
												classes = {"formPanel"},
											
												gui.Label{
													halign = "left",
													text = entry.modifier.name,
													bold = true,
												},

												gui.Label{
													halign = "right",
													text = string.format("%s", optionToDescription[entry.proficiency]),
												},
											}
										end

										if #log == 0 then
											panels[#panels+1] = gui.Label{
												text = "No Proficiency",
												bold = true,
											}
										end
									end

									local proficiencyModifications = {}
									info.token.properties:SkillProficiencyBonus(skillInfo, proficiencyModifications)
									for _,mod in ipairs(proficiencyModifications) do
										panels[#panels+1] = gui.Label{
											text = mod,
											bold = true,
										}
									end

									--padding
									panels[#panels+1] = gui.Panel{
										bgimage = "panels/square.png",
										width = "98%",
										height = 1,
										halign = "center",
										bgcolor = "#999999",
										vmargin = 8,
									}

									panels[#panels+1] = gui.Label{
										text = "Override",
										bold = true,
									}

									for i,option in ipairs(options) do
										local selected = proficiencyOverride == option.id
										dmhub.Debug(string.format('OPTION: %s; vs %s selected: %s', tostring(option.id), tostring(proficiencyOverride), tostring(selected)))
										panels[#panels+1] = gui.Label{
											classes = {"option", cond(selected, "selected")},
											bgimage = "panels/square.png",
											text = option.text,
											press = function(element)
												if option.id == "custom" then
													customInput:SetClass("collapsed", false)
													for _,p in ipairs(panels) do
														p:SetClass("selected", p == element)
													end
													customInput.hasInputFocus = true
												else
													if isMonster then
														info.token.properties:SetSkillProficiency(skillInfo, option.value)
													else
														info.token.properties.skillProficiencies[skillInfo.id] = option.id
													end
													CharacterSheet.instance:FireEvent('refreshAll')
													popupParentElement.popup = nil
												end
											end,
										}
									end

									panels[#panels+1] = customInput

									element.popupPositioning = "panel"

									element.popup = gui.TooltipFrame(
										gui.Panel{
											width = 300,
											styles = {
												Styles.Default,
												PopupStyles,
											},
											children = panels,
										},
										{
											halign = "right",
											interactable = true,
										}
									)									
								end,
							},

						},

						
						gui.Label{
							classes = {"statsLabel", "attrLabel", "ds skillsModField"},
							text = string.upper(skillInfo.category),
						},
						

						gui.Label{
							classes = {"statsLabel", "ds skillsSkillField"},
							text = string.upper(skillInfo.name),
						},

						--[[
						gui.Label{
							classes = {"statsLabel", "skillsBonusField", "valueLabel", "dice"},
							characterLimit = 5,
							textAlignment = "center",
							refreshToken = function(element, info)
								element.text = info.token.properties:SkillModStr(skillInfo)
								element.editableOnRightClick = (info.token.properties:IsMonster())
							end,
							press = function(element)
								CharacterSheet.instance.data.info.token.properties:RollSkillCheck(skillInfo)
							end,
							change = function(element)
								info.token.properties:SetSkillRating(skillInfo, element.text)
								CharacterSheet.instance:FireEvent('refreshAll')
							end,
						},
						]]
						
					}

					children[#children+1] = row

					newRowsCache[skillInfo.id] = row

				end

				rowsCache = newRowsCache
				element.children = children
			end,
		},
	}

	return resultPanel

end

function DSCharacterSheet.FeaturesPanel()
	return gui.Panel{
		classes = {"ds featuresScrollPanel"},
		vscroll = true,
		gui.Panel{
			 classes = {"featuresPanel"},
			 flow = "vertical",

			 DSCharacterSheet.CharacterFeaturesPanel(),

			 
			 --list of additional/custom features.
			gui.Panel{
				height = "auto",
				halign = "center",
				width = "100%-16",

				data = {
					properties = nil,
				},

				refreshToken = function(element, info)
					if info.token.properties ~= element.data.properties then
						element.children = { CharacterFeature.ListEditor(info.token.properties, 'characterFeatures', { dialog = CharacterSheet.instance, notify = CharacterSheet.instance }) }
						element.data.properties = info.token.properties
					end
				end,
			},

			--creature templates.
			gui.Panel{
				height = "auto",
				halign = "center",
				width = "100%-16",
				flow = "vertical",

				gui.Panel{
					width = "100%",
					height = "auto",
					flow = "vertical",
					data = {
						children = {},
					},
					refreshToken = function(element, info)
						local templates = info.token.properties:try_get("creatureTemplates")
						if templates == nil or #templates <= #element.data.children then
							return
						end


						while #templates > #element.data.children do
							local label = gui.Label{
								classes = {"statsLabel"},
								width = "80%",
								height = "auto",
							}
							local n = #element.data.children+1
							element.data.children[n] = gui.Panel{
								width = "100%",
								height = "auto",
								flow = "horizontal",
								refreshToken = function(element, info)
									local templates = info.token.properties:try_get("creatureTemplates")
									if templates == nil or #templates < n then
										element:SetClass("collapsed", true)
										return
									end

									local templatesTable = dmhub.GetTable("creatureTemplates")
									local templateInfo = templatesTable[templates[n]]
									if templateInfo == nil then
										element:SetClass("collapsed", true)
										return
									end

									element:SetClass("collapsed", false)
									if templateInfo.description ~= '' then
										label.text = string.format("%s--%s", templateInfo.name, templateInfo.description)
									else
										label.text = templateInfo.name
									end
								end,

								label,
								gui.DeleteItemButton{
									width = 24,
									height = 24,
									halign = "right",
									click = function(element)
										local creature = CharacterSheet.instance.data.info.token.properties
										creature:RemoveTemplate(n)
										CharacterSheet.instance:FireEvent("refreshAll")
									end,
								},
							}
						end

						element.children = element.data.children

					end,
				},

				gui.Dropdown{
					monitorAssets = true,
					width = 200,
					height = 30,
					vmargin = 4,
					idChosen = "none",

					create = function(element)
						element:FireEvent("refreshAssets")
					end,

					refreshAssets = function(element)
						local choices = {
							{
								id = "none",
								text = "Add Creature Template...",
							},
						}

						local templateTable = dmhub.GetTable("creatureTemplates") or {}
						for k,entry in pairs(templateTable) do
							if not entry:try_get("hidden", false) then
								choices[#choices+1] = {
									id = k,
									text = entry.name,
								}
							end
						end

						element.options = choices
					end,

					change = function(element)
						local creature = CharacterSheet.instance.data.info.token.properties
						if element.idChosen ~= "none" then
							creature:AddTemplate(element.idChosen)
						end
						element.idChosen = "none"
						CharacterSheet.instance:FireEvent('refreshAll')
					end,

				},
			},


			--feats.
			gui.Panel{
				height = "auto",
				halign = "center",
				width = "100%-16",
				flow = "vertical",

				refreshToken = function(element, info)
					if info.token.properties:IsMonster() then
						element:SetClass("collapsed", true)
						return
					end

					element:SetClass("collapsed", false)
				end,

				gui.Panel{
					width = "100%",
					height = "auto",
					flow = "vertical",
					data = {
						children = {},
					},
					refreshToken = function(element, info)
						local feats = info.token.properties:try_get("creatureFeats")
						if feats == nil or #feats <= #element.data.children then
							return
						end


						while #feats > #element.data.children do
							local label = gui.Label{
								classes = {"statsLabel"},
								width = "80%",
								height = "auto",
							}
							local n = #element.data.children+1
							element.data.children[n] = gui.Panel{
								width = "100%",
								height = "auto",
								flow = "horizontal",
								refreshToken = function(element, info)
									local feats = info.token.properties:try_get("creatureFeats")
									if feats == nil or #feats < n then
										element:SetClass("collapsed", true)
										return
									end

									local featsTable = dmhub.GetTable(CharacterFeat.tableName)
									local featInfo = featsTable[feats[n]]
									if featInfo == nil then
										element:SetClass("collapsed", true)
										return
									end

									element:SetClass("collapsed", false)
									if featInfo.description ~= '' then
										label.text = string.format("%s", featInfo.name)
									else
										label.text = featInfo.name
									end
								end,

								label,
								gui.DeleteItemButton{
									width = 24,
									height = 24,
									halign = "right",
									click = function(element)
										local creature = CharacterSheet.instance.data.info.token.properties
										creature:RemoveFeat(n)
										CharacterSheet.instance:FireEvent("refreshAll")
									end,
								},
							}
						end

						element.children = element.data.children

					end,
				},

				gui.Dropdown{
					monitorAssets = true,
					width = 200,
					height = 30,
					vmargin = 4,
					idChosen = "none",
					hasSearch = true,

					create = function(element)
						element:FireEvent("refreshAssets")
					end,

					refreshAssets = function(element)
						local choices = {
							{
								id = "none",
								text = "Add Feat...",
							},
						}

						local featTable = dmhub.GetTable(CharacterFeat.tableName) or {}
						for k,entry in pairs(featTable) do
							if not entry:try_get("hidden", false) then
								choices[#choices+1] = {
									id = k,
									text = entry.name,
								}
							end
						end

						table.sort(choices, function(a,b) return a.text < b.text end)

						element.options = choices
					end,

					change = function(element)
						local creature = CharacterSheet.instance.data.info.token.properties
						if element.idChosen ~= "none" then
							creature:AddFeat(element.idChosen)
						end
						element.idChosen = "none"
						CharacterSheet.instance:FireEvent('refreshAll')
					end,

				},
			},


		}
	}
end

function DSCharacterSheet.ActionsAndFeaturesPanel()
	local resultPanel

	local indexSelected = 1

	local tabPanels = {
		DSCharacterSheet.ActionsPanel(),
		DSCharacterSheet.FeaturesPanel(),
		DSCharacterSheet.FeaturesNotesPanel(),
	}

	for i,tabPanel in ipairs(tabPanels) do
		tabPanel:SetClass("collapsed", i ~= 1)
	end

	local tabPress = function(element)
		if element:HasClass("selected") then
			return
		end
		for i,tab in ipairs(element.parent.children) do
			if tab:HasClass("tab") then
				tab:SetClass("selected", tab == element)
				tabPanels[i]:SetClass("collapsed", tab ~= element)
				if tab == element then
					indexSelected = i
				end
			end
		end
	end

	resultPanel = gui.Panel{
		classes = { "statsPanel" },
		styles = ActionsAndFeaturesStyles,
		gui.Panel{
			classes = { "statsInnerPanel" },
			width = "100%",
			valign = "top",

			gui.Panel{
				classes = { "statsHeader" },
				valign = "top",

				gui.Label{
					classes = {"tab", "selected"},
					text = "ACTIONS",
					press = tabPress,
					gui.Panel{classes = {"tabBorder"}},
				},
				gui.Label{
					classes = {"tab"},
					text = "FEATURES",
					press = tabPress,
					gui.Panel{classes = {"tabBorder"}},
				},
				gui.Label{
					classes = {"tab"},
					text = "NOTES",
					press = tabPress,
					gui.Panel{classes = {"tabBorder"}},
				},
			},

			tabPanels[1],
			tabPanels[2],
			tabPanels[3],

		},

	}

	return resultPanel
end

--gui.RegisterTheme("charsheet", "Features", ActionsAndFeaturesStyles)

function DSCharacterSheet.ActionsPanel()

	local attackPanels = {}
	local spellPanels = {}

	local creatureLookup = nil

	local abilities = {}
	local attacks = {}
	local attackAbilities = {}
	local spellAbilities = {}
	local standardAbilities = {}
	local legendaryAbilities = {}

	local CreateAbilitiesPanel = function(otherAbilities, options)
		local otherAbilityPanels = {}
		return gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",

			refreshToken = function(element, info)
				element:SetClass("collapsed", #otherAbilities == 0)
			end,

			gui.Label{
				classes = {"statsLabel", "abilityTableTitle"},
				text = options.title,
			},

			--heading
			gui.Panel{
				classes = {"statsRow"},
				gui.Label{
					classes = {"statsLabel", "tableHeading", "abilityIcon"},
					text = "",
				},
				gui.Label{
					classes = {"statsLabel", "tableHeading", "abilityName"},
					text = "NAME",
				},
				gui.Label{
					classes = {"statsLabel", "tableHeading", "abilityUses"},
					text = "USES",
				},
				gui.Label{
					classes = {"statsLabel", "tableHeading", "abilityRange"},
					text = "RANGE",
				},
				gui.Label{
					classes = {"statsLabel", "tableHeading", "abilitySave"},
					text = "SAVE",
				},
				gui.Label{
					classes = {"statsLabel", "tableHeading", "abilityEffect"},
					text = "EFFECT",
				},
				gui.Label{
					classes = {"statsLabel", "tableHeading", "abilityEdit"},
					text = "",
				},
			},

			gui.Panel{
				width = "100%",
				height = "auto",
				flow = "vertical",
				refreshToken = function(element, info)
					local children = {}
					local newPanels = {}

					for i,ability in ipairs(otherAbilities) do

						local panel = otherAbilityPanels[i] or gui.Panel{
							classes = {"statsRow", "otherAbilityTable"},

							linger = function(element)
								local tooltip = CreateAbilityTooltip(otherAbilities[i], {token = CharacterSheet.instance.data.info.token})
								tooltip.selfStyle.halign = "center"
								tooltip.selfStyle.valign = "top"
								element.tooltip = tooltip
							end,

							gui.Panel{
								classes = {"statsLabel", "abilityIcon", "tableData", "otherABilityTable"},
								gui.Panel{
									classes = {"abilityIconBackground"},
									gui.Panel{
										classes = {"abilityIconIcon"},
										refreshToken = function(element, info)
											element.bgimage = otherAbilities[i].iconid
										end,
									},
									gui.PrettyBorder{ width = 9 },
								},
							},
							gui.Label{
								classes = {"statsLabel", "abilityName", "tableData", "otherAbilityTable"},
							},
							gui.Label{
								classes = {"statsLabel", "valueLabel", "abilityUses", "tableData", "otherAbilityTable"},
								data = {
									resourceid = nil,
									maxCharges = nil,
									availableCharges = nil,
									refreshType = nil,
									abilityName = nil
								},
								press = function(element)
									local parentPanel = element
									if element.data.resourceid ~= nil then
										element.popupPositioning = 'panel'
										element.popup = gui.TooltipFrame(
			
											gui.Panel({
												selfStyle = {
													pad = 8,
												},
												styles = {
													Styles.Default,
													{
														valign = 'bottom',
														halign = 'center',
														width = 'auto',
														height = 'auto',
														bgcolor = 'black',
														flow = 'vertical',
														color = '#c4c1aa',
													},
													{
														selectors = {'editable'},
														color = '#d4d1ba',
													}
												},

												gui.Panel{
													flow = "vertical",
													width = "auto",
													height = "auto",
													gui.Label{
														width = "auto",
														height = "auto",
														halign = "center",
														fontSize = 16,
														color = "white",
														text = parentPanel.data.abilityName,
													},
													gui.Panel{
														flow = "horizontal",
														width = "auto",
														height = "auto",
														gui.Label{
															editable = true,
															characterLimit = 3,
															fontSize = 14,
															width = 30,
															height = "auto",
															text = string.format("%d", parentPanel.data.availableCharges),
															change = function(element)
																local number = tonumber(element.text)
																if number ~= nil and number >= 0 and number <= parentPanel.data.maxCharges then
																	local diff = number - parentPanel.data.availableCharges
																	parentPanel.popup = nil
																	CharacterSheet.instance.data.info.token.properties:ConsumeResource(parentPanel.data.resourceid, parentPanel.data.refreshType, -diff)
																	CharacterSheet.instance:FireEvent("refreshAll")
																end
															end,
														},
														gui.Label{
															fontSize = 14,
															width = 12,
															height = "auto",
															text = "/",
														},

														gui.Label{
															fontSize = 14,
															width = 30,
															height = "auto",
															text = string.format("%d", parentPanel.data.maxCharges),
														},
													},
												}
												
											}), {
												interactable = true,
											}
										)

									end
								end,
							},
							gui.Label{
								classes = {"statsLabel", "abilityRange", "tableData", "otherAbilityTable"},
							},
							gui.Label{
								classes = {"statsLabel", "abilitySave", "tableData", "otherAbilityTable"},
							},
							gui.Label{
								classes = {"statsLabel", "abilityEffect", "tableData", "otherAbilityTable"},
							},

							gui.Panel{
								classes = {"statsLabel", "abilityEdit", "tableData"},

								gui.Panel{
									classes = { "abilityEditIcon" },
									click = function(element)
										local a = otherAbilities[i]
										CharacterSheet.instance:AddChild(a:ShowEditActivatedAbilityDialog{
											close = function(element)
												CharacterSheet.instance:FireEvent("refreshAll")
											end,
											delete = function(element)
												options.delete(a)
											end,
										})
									end,
                                    rightClick = function(element)
                                        element.popup = gui.ContextMenu{
                                            entries = {
                                                {
                                                    text = "Copy",
                                                    click = function()
                                                        dmhub.CopyToInternalClipboard(otherAbilities[i])
                                                        element.popup = nil
                                                    end,
                                                }
                                            }
                                        }
                                        
                                    end,
								},
							},
						}

						local dataItems = panel.children

						dataItems[3].data.resourceid = nil
						dataItems[3].data.availableCharges = nil
						dataItems[3].data.maxCharges = nil
						dataItems[3].text = "--"

						local costInfo = ability:GetCost(CharacterSheet.instance.data.info.token)
						for i,item in ipairs(costInfo.details) do
							if item.description ~= nil then
								dataItems[3].text = item.description
								dataItems[3].data.abilityName = ability.name
								dataItems[3].data.resourceid = item.cost
								dataItems[3].data.availableCharges = item.availableCharges
								dataItems[3].data.maxCharges = item.maxCharges
								dataItems[3].data.refreshType = item.refreshType
							end
						end

						dataItems[2].text = ability.name
						dataItems[4].text = ability:DescribeAOE()

						local dctext = "--"
						for _,behavior in ipairs(ability.behaviors) do
							if behavior:has_key("dc") then
								dctext = string.format("%s%d", string.upper(concatdc(behavior.dc)), ability:SaveDC(CharacterSheet.instance.data.info.token, behavior))
							end
						end

						dataItems[5].text = dctext

						dataItems[6].text = ability:SummarizeBehavior(creatureLookup)

						dataItems[7]:SetClass("hidden", (not info.token.properties:IsActivatedAbilityInnate(ability)) and (not info.token.properties:IsActivatedAbilityLegendary(ability)))

						newPanels[i] = panel
						children[#children+1] = panel
					end

					otherAbilityPanels = newPanels
					element.children = children
				end,
			},
		}
	end

	return gui.Panel{
		classes = {"ds featuresScrollPanel"},
		vscroll = true,
		refreshToken = function(element, info)
			creatureLookup = info.token.properties:LookupSymbol()
			abilities = info.token.properties:GetActivatedAbilities{ characterSheet = true }
			attacks = {}
			attackAbilities = {}
			spellAbilities = {}

			while #standardAbilities > 0 do
				standardAbilities[#standardAbilities] = nil
			end

			while #legendaryAbilities > 0 do
				legendaryAbilities[#legendaryAbilities] = nil
			end

			for i,ability in ipairs(abilities) do
				if ability:GetAttackBehavior() ~= nil then
					--this is an attack
					attackAbilities[#attackAbilities+1] = ability
					attacks[#attacks+1] = ability:GetAttackBehavior():GetAttack(ability, info.token.properties, {})
				elseif ability.typeName == "Spell" then
					spellAbilities[#spellAbilities+1] = ability
				elseif ability.legendary then
					legendaryAbilities[#legendaryAbilities+1] = ability
				else
					standardAbilities[#standardAbilities+1] = ability
				end
			end

			printf("REFRESH TOKEN: abilities = %d; standard = %d; legendary = %d", #abilities, #standardAbilities, #legendaryAbilities)
		end,
		gui.Panel{
			 classes = {"ds featuresPanel"},
			 flow = "vertical",

			 gui.Panel{
				id = "ds attacksTable",
				width = "100%",
				height = "auto",
				flow = "vertical",
				refreshToken = function(element, info)
					element:SetClass("collapsed", #attackAbilities == 0)
				end,

				gui.Label{
					classes = {"statsLabel", "abilityTableTitle"},
					text = "Attacks",
				},

				--heading
				gui.Panel{
					classes = {"statsRow"},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityIcon"},
						text = "",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityName"},
						text = "NAME",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityRange"},
						text = "RANGE",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityHit"},
						text = "HIT",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityDamage"},
						text = "DAMAGE",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityEdit"},
						text = "",
					},
				},

				--attack panel.
				gui.Panel{
					width = "100%",
					height = "auto",
					flow = "vertical",
					refreshToken = function(element, info)

						local children = {}
						local newAttackPanels = {}
						for i,ability in ipairs(attackAbilities) do

							local panel = attackPanels[i] or gui.Panel{
								classes = {"statsRow", "attackTable"},

								linger = function(element)
									local tooltip = CreateAbilityTooltip(attackAbilities[i], {token = CharacterSheet.instance.data.info.token})
									tooltip.selfStyle.halign = "center"
									tooltip.selfStyle.valign = "top"
									element.tooltip = tooltip
								end,

								gui.Panel{
									classes = {"statsLabel", "abilityIcon", "tableData"},
									gui.Panel{
										classes = {"abilityIconBackground"},
										gui.Panel{
											classes = {"abilityIconIcon"},
											refreshToken = function(element, info)
												element.bgimage = attackAbilities[i].iconid
												element.selfStyle = attackAbilities[i].display
											end,
										},
										gui.PrettyBorder{ width = 9 },
									},
								},
								gui.Label{
									classes = {"statsLabel", "abilityName", "tableData"},
								},
								gui.Label{
									classes = {"statsLabel", "abilityRange", "tableData"},
								},
								gui.Label{
									classes = {"statsLabel", "abilityHit", "tableData", "valueLabel", "dice"},
									press = function(element)
										CharacterSheet.instance.data.info.token.properties:RollAttackHit(element.data.attack, nil, {autoroll = true})
									end,
									data = {},
								},
								gui.Label{
									classes = {"statsLabel", "abilityDamage", "tableData", "valueLabel", "dice"},
									press = function(element)
										CharacterSheet.instance.data.info.token.properties:RollAttackDamage(element.data.attack)
									end,
									data = {},
								},
								gui.Panel{
									classes = {"statsLabel", "abilityEdit", "tableData"},

									gui.Panel{
										classes = { "abilityEditIcon" },
										click = function(element)
											local a = attackAbilities[i]
											CharacterSheet.instance:AddChild(a:ShowEditActivatedAbilityDialog{
												close = function(element)
													CharacterSheet.instance:FireEvent("refreshAll")
												end,
												delete = function(element)
													CharacterSheet.instance.data.info.token.properties:RemoveInnateActivatedAbility(a)
												end,
											})
										end,
									},

								},
							}

							local attack = attacks[i]

							local dataItems = panel.children
							dataItems[2].text = attack.name

							local range = attack.range
							if tonumber(range) ~= nil then
								range = string.format("%s%s", MeasurementSystem.NativeToDisplayString(range), MeasurementSystem.Abbrev())
							end
							dataItems[3].text = range
							dataItems[4].text = ModStr(attack.hit)

							dataItems[4].data.attack = attack
							dataItems[5].data.attack = attack

							local damageRoll = ""
							for j,damageInstance in ipairs(attack.damageInstances) do
								damageRoll = string.format("%s %s [%s%s]", damageRoll, damageInstance.damage, cond(damageInstance:try_get("magicalDamage", false), "magic ", ""), damageInstance.damageType)
							end

							damageRoll = trim(dmhub.NormalizeRoll(dmhub.EvalGoblinScript(damageRoll, creatureLookup, "Calculate attack damage on character sheet")))

							--try not to break a damage roll in inconvenient places.
							damageRoll = string.gsub(damageRoll, ' %[', nbsp .. '[')
							damageRoll = string.gsub(damageRoll, 'magic ', 'magic' .. nbsp)

							dataItems[5].text = damageRoll

							dataItems[6]:SetClass("hidden", not info.token.properties:IsActivatedAbilityInnate(ability))

							newAttackPanels[i] = panel
							children[#children+1] = panel
						end

						attackPanels = newAttackPanels
						element.children = children
					end,
				},
			 },

			 CreateAbilitiesPanel(standardAbilities, {
				title = "Abilities",
				delete = function(a)
					CharacterSheet.instance.data.info.token.properties:RemoveInnateActivatedAbility(a)
				end,
			 }),
	
			gui.Button{
				text = "Add Ability",
				halign = "right",
				fontSize = 16,
				click = function(element)
					local newAbility = ActivatedAbility.Create{
						name = "New Ability",
					}

					CharacterSheet.instance:AddChild(newAbility:ShowEditActivatedAbilityDialog{
						add = function(element)
							CharacterSheet.instance.data.info.token.properties:AddInnateActivatedAbility(newAbility)
							CharacterSheet.instance:FireEvent("refreshAll")
						end,
						cancel = function(element)
						end,
					})
				end,
			},

            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "right",

                data = {
                    val = nil,
                },

                thinkTime = 0.2,
                think = function(element)
                    local ability = dmhub.GetInternalClipboard()
                    local newVal
                    if ability ~= nil and ability.typeName == "ActivatedAbility" then
                        newVal = false
                    else
                        newVal = true
                    end

                    if newVal ~= element.data.val then
                        element.data.val = newVal
                        element.children[1]:SetClass("collapsed", newVal)
                    end
                end,



                gui.Button{
                    classes = {"collapsed"},
                    text = "Paste Ability",
                    halign = "right",
                    fontSize = 16,
                
                    click = function(element)
                        local ability = dmhub.GetInternalClipboard()
                        if ability ~= nil and ability.typeName == "ActivatedAbility" then
                            CharacterSheet.instance.data.info.token.properties:AddInnateActivatedAbility(ability)
                            CharacterSheet.instance:FireEvent("refreshAll")
                        end
                    end,

                },
            },

			--spells panel.
			gui.Panel{
				id = "ds spellTable",
				width = "100%",
				height = "auto",
				flow = "vertical",

				refreshToken = function(element, info)
					element:SetClass("collapsed", #spellAbilities == 0)
				end,

				gui.Label{
					classes = {"statsLabel", "abilityTableTitle"},
					text = "Spells",
				},

				--heading
				gui.Panel{
					classes = {"statsRow"},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityIcon"},
						text = "",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityName"},
						text = "NAME",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityRange"},
						text = "RANGE",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilitySave"},
						text = "SAVE",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityEffect"},
						text = "EFFECT",
					},
					gui.Label{
						classes = {"statsLabel", "tableHeading", "abilityEdit"},
						text = "",
					},
				},

				gui.Panel{
					width = "100%",
					height = "auto",
					flow = "vertical",
					refreshToken = function(element, info)
						local children = {}
						local newSpellPanels = {}

						for i,ability in ipairs(spellAbilities) do

							local panel = spellPanels[i] or gui.Panel{
								classes = {"statsRow", "spellTable"},

								linger = function(element)
									local tooltip = CreateAbilityTooltip(spellAbilities[i], {token = CharacterSheet.instance.data.info.token})
									tooltip.selfStyle.halign = "center"
									tooltip.selfStyle.valign = "top"
									element.tooltip = tooltip
								end,

								gui.Panel{
									classes = {"statsLabel", "abilityIcon", "tableData", "spellTable"},
									gui.Panel{
										classes = {"abilityIconBackground"},
										gui.Panel{
											classes = {"abilityIconIcon"},
											refreshToken = function(element, info)
												element.bgimage = spellAbilities[i].iconid
											end,
										},
										gui.PrettyBorder{ width = 9 },
									},
								},
								gui.Label{
									classes = {"statsLabel", "abilityName", "tableData", "spellTable"},
								},
								gui.Label{
									classes = {"statsLabel", "abilityRange", "tableData", "spellTable"},
								},
								gui.Label{
									classes = {"statsLabel", "abilitySave", "tableData", "spellTable"},
								},
								gui.Label{
									classes = {"statsLabel", "abilityEffect", "tableData", "spellTable"},
								},

								--this panel is blank for spells. Spells can be edited elsewhere.
								gui.Panel{
									classes = {"statsLabel", "abilityEdit", "tableData"},
								},
							}

							local dataItems = panel.children
							dataItems[2].text = ability.name
							dataItems[3].text = ability:DescribeAOE()

							local dctext = "--"
							for _,behavior in ipairs(ability.behaviors) do
								if behavior:has_key("dc") then
									dctext = string.format("%s%d", string.upper(concatdc(behavior.dc)), ability:SaveDC(CharacterSheet.instance.data.info.token))
								end
							end

							dataItems[4].text = dctext

							dataItems[5].text = ability:SummarizeBehavior(creatureLookup)

							newSpellPanels[i] = panel
							children[#children+1] = panel
						end

						spellPanels = newSpellPanels
						element.children = children
					end,
				},
			},
				
		}
	}
end

function DSCharacterSheet.CharacterFeaturesPanel()

	local triangleStyles = {
		gui.Style{
			classes = {'triangle'},
			rotate = 90,
			height = 12,
			width = 12,
			halign = "right",
			valign = "center",
			hmargin = 8,
			bgimage = "panels/triangle.png",
			bgcolor = "white",
		},
		gui.Style{
			classes = {'triangle', 'expanded'},
			rotate = 0,
			transitionTime = 0.2,
		},
	}

	local featurePanels = {}

	local resultPanel = gui.Panel{
		width = 520,
		height = 'auto',
		flow = 'vertical',
		halign = 'left',
		refreshToken = function(element, info)
			local creature = info.token.properties
			if creature.typeName ~= "character" then
				element.children = {}
				element:SetClass("collapsed", true)
				featurePanels = {}
				return
			end

			element:SetClass("collapsed", false)

			local children = {}

			local newFeaturePanels = {}

			local features = creature:GetClassFeaturesAndChoicesWithDetails()

			for i,featureInfo in ipairs(features) do


				local levelStr = ''
				if featureInfo.levels ~= nil then
					levelStr = string.format(", level %d", math.max(1, featureInfo.levels[1]))
				end

				if featureInfo.levels ~= nil and #featureInfo.levels > 1 then
					levelStr = string.format("%s upgraded at level%s %d", levelStr, cond(#featureInfo.levels > 2, 's', ''), featureInfo.levels[2])
					if #featureInfo.levels > 2 then
						for i=3,#featureInfo.levels do
							levelStr = string.format("%s, %d", levelStr, featureInfo.levels[i])
						end
					end
				end

				local key = string.format("%d-%s-%s", i, featureInfo.feature.guid, levelStr)

				local featurePanel = featurePanels[key]

				if featurePanel == nil then

					local tri = gui.Panel{
						classes = {"triangle"},
						styles = triangleStyles,
					}

					local bodyChildren = {}

					bodyChildren[#bodyChildren+1] = gui.Label{
						width = '100%',
						height = 'auto',
						fontSize = 12,
						textWrap = true,
						refreshToken = function(element, info)
							element.text = featurePanel.data.featureInfo.feature:GetDescription()
						end,
					}

					local numChoices = featureInfo.feature:NumChoices(creature)
					for i=1,numChoices do

						local dropdown = gui.Dropdown{
							fontSize = 18,
							height = 26,
							width = 240,
							textDefault = "Choose...",
							sort = true,
							data = {
								featureInfo = featureInfo,
							},
							refreshToken = function(element, info)
								local creature = info.token.properties
								local choices = element.data.featureInfo.feature:Choices(i, creature:GetLevelChoices()[element.data.featureInfo.feature.guid] or {}, creature)
								
								if choices ~= nil and #choices > 0 then
									local idChosen = (creature:GetLevelChoices()[element.data.featureInfo.feature.guid] or {})[i] or 'none'
									element.options = choices
									element.idChosen = idChosen
									element:SetClass("hidden", false)
								else
									element:SetClass("hidden", true)
								end
							end,

							change = function(element)
								local choice = element.idChosen
								if choice == 'none' then
									choice = nil
								end

								local choices = creature:GetLevelChoices()
								if choices[element.data.featureInfo.feature.guid] == nil then
									choices[element.data.featureInfo.feature.guid] = {}
								end
								choices[element.data.featureInfo.feature.guid][i] = choice
								CharacterSheet.instance:FireEvent('refreshAll')
							end,
						}

						bodyChildren[#bodyChildren+1] = dropdown
					end

					local body = gui.Panel{
						width = '100%',
						height = 'auto',
						flow = 'vertical',
						classes = {"collapsed-anim"},

						children = bodyChildren,
					}
					
					local header = gui.Panel{
						classes = {"featureHeader"},
						halign = "left",
						width = "90%",
						height = "auto",
						flow = "horizontal",
						bgimage = "panels/square.png",
						press = function(element)
							body:SetClass('collapsed-anim', tri:HasClass('expanded'))
							tri:SetClass('expanded', not tri:HasClass('expanded'))
						end,
						styles = {
							{
								selectors = {"featureHeader"},
								bgcolor = 'black',
							},
							{
								selectors = {"featureHeader","hover"},
								bgcolor = '#770000ff',
							},
						},


						gui.Panel{
							width = "80%",
							height = "auto",
							flow = "vertical",
							halign = "left",

							gui.Label{
								width = "90%",
								height = "auto",
								fontSize = 12,
								bold = true,
								refreshToken = function(element, info)
									element.text = string.format("%s", featurePanel.data.featureInfo.feature:Describe())
								end,
							},
							gui.Label{
								width = "90%",
								height = "auto",
								fontSize = 12,
								italics = true,
								refreshToken = function(element, info)
									local featureInfo = featurePanel.data.featureInfo
									element.text = string.format("%s%s", (featureInfo.class or featureInfo.race or featureInfo.background or {name = ""}).name, levelStr)
								end,
							},
						},

						tri,
					}

					featurePanel = gui.Panel{
						styles = {
							{
								hmargin = 0,
							}
						},
						data = {
						},
						hmargin = 8,
						vmargin = 2,
						width = '100%',
						height = 'auto',
						flow = "vertical",
						header,body,
					}
				end

				featurePanel.data.featureInfo = featureInfo

				children[#children+1] = featurePanel
				newFeaturePanels[key] = featurePanel

			end

			featurePanels = newFeaturePanels

			element.children = children
		end
	}

	return resultPanel
end

function DSCharacterSheet.FeaturesNotesPanel()
	local GetNotes = function(creature)
		if creature:has_key("notes") then
			return creature.notes
		end

		if creature:IsMonster() then
			return {
				{
					title = "Monster Notes",
					text = "",
				}
			}
		else
			return {
				{
					title = "Backstory",
					text = "",
				}
			}
		end
	end

	local EnsureNotes = function(creature)
		if not creature:has_key("notes") then
			creature.notes = GetNotes(creature)
		end
		return creature.notes
	end

	local CreateNotesSection = function(i, params)

		local resultPanel

		local args = {
			width = "95%",
			height = "auto",
			flow = "vertical",
			halign = "center",

			gui.Panel{
				flow = "horizontal",
				width = "100%",
				height = "auto",
				vmargin = 4,
				gui.Input{
					fontSize = 14,
					multiline = false,
					width = "60%",
					height = 22,
					color = "#d4d1ba",
					blockChangesWhenEditing = true,
					placeholderText = "Enter section title...",
					refreshToken = function(element, info)
						local notes = GetNotes(info.token.properties)
						if i <= #notes then
							element.text = notes[i].title
						end
					end,

					editlag = 1,
					edit = function(element)
						element:FireEvent("change")
					end,
					change = function(element)
						local notes = EnsureNotes(CharacterSheet.instance.data.info.token.properties)
						if i <= #notes and notes[i].title ~= element.text then
							notes[i].title = element.text
							CharacterSheet.instance.data.info.token.properties.notesRevision = dmhub.GenerateGuid()
						end
					end,
				},
				gui.DeleteItemButton{
					width = 24,
					height = 24,
					halign = "right",
					click = function(element)
						resultPanel:FireEvent("delete")
					end,
				},
			},

			 gui.Input{
				width = "98%",
				valign = "top",
				vmargin = 4,
				halign = "center",
				height = "auto",
				multiline = true,
				minHeight = 100,
				textAlignment = "topleft",
				fontSize = 14,
				color = "#d4d1ba",
				blockChangesWhenEditing = true,

				placeholderText = "Enter notes...",

				refreshToken = function(element, info)
					local notes = GetNotes(info.token.properties)
					if i <= #notes then
						element.text = notes[i].text
					end
				end,

				--note when this is edited and make sure that when the sheet is closed we sync
				--any changes to the cloud.
				data = {
					edits = false
				},

				edit = function(element)
					element.data.edits = true
				end,

				restoreOriginalTextOnEscape = false,

				closeCharacterSheet = function(element)
					if element.data.edits then
						element:FireEvent("change")
					end
				end,

				change = function(element)
					element.data.edits = false
					local notes = EnsureNotes(CharacterSheet.instance.data.info.token.properties)
					if i <= #notes and notes[i].text ~= element.text then
						notes[i].text = element.text
						CharacterSheet.instance.data.info.token.properties.notesRevision = dmhub.GenerateGuid()
					end
				end,
			 },

		}

		for k,p in pairs(params) do
			args[k] = p
		end

		resultPanel = gui.Panel(args)
		return resultPanel
	end

	local addNotesButton = gui.AddButton{
		hmargin = 15,
		halign = "right",
		linger = function(element)
			gui.Tooltip("Add a new section")(element)
		end,
		click = function(element)
			local notes = EnsureNotes(CharacterSheet.instance.data.info.token.properties)
			notes[#notes+1] = {
				title = "",
				text = "",
			}
			CharacterSheet.instance:FireEvent("refreshAll")
		end,
	}

	local sectionPanels = {}

	return gui.Panel{
		classes = {"ds featuresScrollPanel"},
		vscroll = true,
		gui.Panel{
			 classes = {"ds featuresPanel"},

			 flow = "vertical",

			 addNotesButton,

			 refreshToken = function(element, info)
				local notes = GetNotes(info.token.properties)
				local children = {}
				local newSectionPanels = {}

				for i,note in ipairs(notes) do
					local child = sectionPanels[i] or CreateNotesSection(i, {
						delete = function(element)
							local notes = EnsureNotes(CharacterSheet.instance.data.info.token.properties)
							if i <= #notes then
								table.remove(notes, i)
								CharacterSheet.instance:FireEvent("refreshAll")
							end
						end,
					})

					newSectionPanels[i] = child
					children[#children+1] = child
				end

				sectionPanels = newSectionPanels

				children[#children+1] = addNotesButton

				element.children = children
			 end,
		}
	}
end

----------------------------------------------------------------------------
-- Where the Character Sheet Panels Are Assembled
-- Panels attach in a chain from this function
----------------------------------------------------------------------------
function DSCharacterSheet.MainSheet()

    --[[
    -- Big Container Panel for the Character Sheet Tab
    local backgroundPanel = gui.Panel{
		styles = BuilderStyles,
        id = "UXTestPanel",
        halign = "left",
        valign = "top",
        width = 1024,
        height = 800,
        borderWidth = 1,
        borderColor = SwatchNeutral2,
        --cornerRadius = 16, 
        --beveledcorners = true,
        bgcolor = SwatchLight,
        --bgcolor = "red",        
        bgimage = "panels/square.png",
        flow = "vertical",
        opacity = 0.9,
        interactable = false,

        gui.Label{
            classes = {"Header1"},
            text = "Welcome to the Character Sheet Tab Contents",
            width = "auto"
        },
 
        -- First Panel
        gui.Panel{
            styles = BuilderStyles,
            id = "UXTestPanel02",
            halign = "left",
            valign = "top",
            width = 800,
            height = 400,
            cornerRadius = 16, 
            beveledcorners = true,
            borderWidth = 1,
            borderColor = SwatchNeutral2,            
            bgcolor = SwatchLight,
            --bgcolor = "red",        
            bgimage = "panels/square.png",
            flow = "vertical",
            opacity = 0.9,
            interactable = false,
    
            gui.Label{
                classes = {"Details"},
                text = "Character Name",
                width = "auto"
            },

            gui.Label{
                classes = {"Details"},
                text = "Ancestry",
                width = "auto"
            },
        },
 
        -- Second Panel
        gui.Panel{
            styles = BuilderStyles,
            id = "UXTestPanel02",
            halign = "left",
            valign = "top",
            width = 400,
            height = 400,
            cornerRadius = 16, 
            beveledcorners = true,
            borderWidth = 1,
            borderColor = SwatchNeutral2,            
            bgcolor = SwatchLight,
            --bgcolor = "red",        
            bgimage = "panels/square.png",
            flow = "vertical",
            opacity = 0.9,
            interactable = false,
    
            gui.Label{
                classes = {"Header1"},
                text = "Second Panel",
                width = "auto"
            },
        }


    }
    ]]

	--[[
	local hitpointsPanel
	hitpointsPanel = gui.Panel{
		id = "hitpointsPanel",
		classes = {"characterSheetPanel"},
		CreatePanelFooter{
			valign = "bottom",
			text = GameSystem.HitpointsName,
			settings = function(element)
				if hitpointsPanel.popup ~= nil then
					hitpointsPanel.popup = nil
					return
				end

				local rootPanel = CharacterSheet.instance

				local creature = CharacterSheet.instance.data.info.token.properties

				local hitpointsTotalPanel
				local modificationsPanel = nil

				if creature.typeName == "character" then
					local modificationRows = {}

					modificationRows[#modificationRows+1] = gui.Panel{
						classes = {"formPanel"},
						gui.Label{
							classes = {"popupLabel"},
							text = "Base Hitpoints:",
						},
						gui.Label{
							classes = {"popupValue"},
							text = tostring(creature:BaseHitpoints()),
						}
					}

					modificationRows[#modificationRows+1] = gui.Panel{
						classes = {"formPanel"},
						gui.Label{
							classes = {"popupLabel"},
							text = "Override:",
						},
						gui.Label{
							editable = true,
							classes = {"popupValue"},
							text = cond(creature.override_hitpoints, creature.max_hitpoints, "--"),
							change = function(element)
								local n = tonumber(element.text)
								if n == nil then
									element.text = "--"
									creature.override_hitpoints = false
								else
									creature.max_hitpoints = n
									creature.override_hitpoints = true
								end
								rootPanel:FireEvent('refreshAll')
								hitpointsTotalPanel:FireEvent("create")
							end,
						}
					}


					local modifications = creature:DescribeModifications("hitpoints", creature:BaseHitpoints())
					if modifications ~= nil and #modifications > 0 then
						for _,mod in ipairs(modifications) do
							modificationRows[#modificationRows+1] = gui.Panel{
								classes = {"formPanel"},
								gui.Label{
									classes = {"popupLabel"},
									text = mod.key,
								},
								gui.Label{
									classes = {"popupValue"},
									text = mod.value,
								},
							}
						end
					end

					modificationsPanel = gui.Panel{
						width = "auto",
						height = "auto",
						flow = "vertical",
						children = modificationRows,
					}

				end


				hitpointsTotalPanel = gui.Label{
					classes = {"popupValue", "editable"},
					fontSize = "200%",
					textAlignment = "center",
					halign = "center",
					editable = creature:IsMonster(),
					create = function(element)
						element.text = creature:try_get("max_hitpoints_roll", tostring(creature:MaxHitpoints()))
						if element.text == "" then
							element.text = "(none)"
						end
					end,
					change = function(element)
						if element.text == "" then
							element.text = creature:try_get("max_hitpoints_roll", tostring(creature:MaxHitpoints()))
							return
						end

						if creature:has_key("max_hitpoints_roll") then
							if element.text ~= creature.max_hitpoints_roll then
								creature.max_hitpoints_roll = element.text
								creature:RerollHitpoints()
							end
						else
							creature:SetMaxHitpoints(element.text)
						end
						rootPanel:FireEvent('refreshAll')
					end,
				}


				hitpointsPanel.popupPositioning = 'panel'
				hitpointsPanel.popup = gui.TooltipFrame(
					gui.Panel{
						halign = "center",
						valign = "bottom",
						width = 400,
						height = "auto",
						pad = 12,
						styles = {
							Styles.Default,
							PopupStyles,
						},

						gui.Label{
							text = "Max Hitpoints",
							classes = {"popupLabel"},
							textAlignment = "center",
							fontSize = "200%",
							halign = "center",
						},

						modificationsPanel,
						hitpointsTotalPanel,


					}, {
						interactable = true
					}
				)
				
			end,
		},
		--CharSheet.CharacterHitpointsPanel(),
	}
	]]

	local avatarPanel = gui.Panel{
		classes = {"characterSheetPanel", "leftAreaPanel"},
		id = "avatarPanel",

		CreatePanelFooter{
			text = "",
		},

		DSCharacterSheet.CharacterSheetAvatarPanel(),
	}

    local topPanel = gui.Panel{
        classes = {"characterSheetPanel", "charactersheet"},

		width = "100%",
		height = 146,
		flow = "horizontal",

        data = {
            attributesPanels = {},
        },

        refreshToken = function(element, info)
            if #element.data.attributesPanels == 0 then
                local children = {}

                for i,attrid in ipairs(creature.attributeIds) do
                    local attrPanel = CharSheet.AttrPanel(attrid)
                    children[#children+1] = attrPanel
                end

                --local initiativePanel = CharSheet.InitiativePanel()
                --children[#children+1] = initiativePanel

                --local challengeRatingPanel = CharSheet.ChallengeRatingPanel()
                --children[#children+1] = challengeRatingPanel

                --children[#children+1] = CharSheet.ProficiencyBonusPanel()

                --local inspirationPanel = CharSheet.InspirationPanel()
                --children[#children+1] = inspirationPanel

                --local characterBuilderPanel = CharSheet.CharacterBuilderAccessPanel()
                --children[#children+1] = characterBuilderPanel

                element.data.attributesPanels = children

                element.children = children
            end

            local character = info.token.properties

        end,
		
    }
	

    local skillsPanel = gui.Panel{
		id = "DS skillsPanel",
		classes = {"characterSheetPanel"},
        --width = 512,
        --height = 512,
		CreatePanelFooter{
			text = "SKILLS",
		},
        
		--DSCharacterSheet.CharacterSheetSkillsPanel(),
		DSCharacterSheet.CharacterSheetSkillsPanelLegacy(),
		--DSCharacterSheet.MonsterPanel(),

		--DSCharacterSheet.CharacterSheetSkillsPanel(),
	}




    local bottomRightArea = gui.Panel{
		id = "DS bottomRightArea",
		classes = {"charactersheet"},
		styles = CharacterSheetStyles,

		skillsPanel,

		gui.Panel{
			id = "DS FeaturesPanel",
			classes = {"characterSheetPanel"},
			--Putting the info directly into the panel for now
			width = "60%",
			--vmargin = 14,
			height = 878,
			flow = "horizontal",
			DSCharacterSheet.ActionsAndFeaturesPanel(),
		},
	}


    local leftArea = gui.Panel{
        id = "ds leftArea",

        avatarPanel,
    }

    local rightArea = gui.Panel{
        width = "100%-300",
        height = "100%",
        flow = "vertical",
        hmargin = 0,
        vmargin = 0,
        halign = "right",
        hpad = 0,
        vpad = 0,
        topPanel,
        bottomRightArea,
    }

	return gui.Panel{
		width = "100%",
		height = "100%",
		flow = "horizontal",

        styles = CharacterSheetStyles,

		leftArea,
		rightArea,
	}

    --return backgroundPanel

end

--[[CharSheet.RegisterTab{
    id = "DSCharacter",
    text = "DS Character",
    panel = DSCharacterSheet.MainSheet,
    --order = 'zzz'
}

dmhub.RefreshCharacterSheet()]]
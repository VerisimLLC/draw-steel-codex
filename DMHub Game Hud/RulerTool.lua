local mod = dmhub.GetModLoading()

local function CreateRulerPanel()
	local hud = gamehud
	local persistentSetting = nil
	if dmhub.isDM then
		persistentSetting = CreateSettingsEditor("measure:persistent")
	end
	-- Every form-style setting in this panel uses the stacked (label-above-
	-- control) layout. Pull the option once so each CreateSettingsEditor call
	-- stays terse.
	local stackedOpts = {stacked = true}

	local resultPanel = gui.Panel{
		styles = ThemeEngine.GetStyles(),
		classes = {"LaunchablePanel"},
		width = 320,
		height = "auto",
		halign = "right",
		valign = "top",
		flow = "vertical",
        pad = 16,

		create = function(element)
			dmhub.rulerToolActive = true
		end,

		destroy = function(element)
			dmhub.rulerToolActive = false
		end,

		gui.Label{
			text = "Measuring Tool",
			classes = {"sizeXl", "bold"},
			halign = "center",
		},
		CreateSettingsEditor("measure:shape", stackedOpts),
		CreateSettingsEditor("measure:coneangle", stackedOpts),
		CreateSettingsEditor("measure:linewidth", stackedOpts),
		CreateSettingsEditor("measure:share", stackedOpts),
		CreateSettingsEditor("measure:snap", stackedOpts),
		CreateSettingsEditor("measure:distances", stackedOpts),
		persistentSetting,

	}

	return resultPanel
end


LaunchablePanel.Register{
	name = "Measuring Tool",
    menu = "tools",
	icon = "icons/icon_tool/icon_tool_101.png",
	halign = "right",
	valign = "top",
	content = function()
		return CreateRulerPanel()
	end,
}


function GameHud:ShowTooltipNearTile(text, loc)
	self.dialog.sheet:FireEvent("tiletooltip", {
		loc = loc,
		text = text,
	})

end

--------------------------------------------------------------------------------
-- Cross Section measure diagram
--
-- The engine's MeasureTool (MeasureTool.UpdateCrossSectionDiagram) drives these
-- sheet functions while a "Cross Section" measure is live: our own while
-- drawing, or another player's measure shared to this map. The engine renders
-- the side-on terrain diagram offscreen (exposed as the "#MeasureCrossSection"
-- bgimage key) and calls ShowCrossSectionMeasure with the image's pixel size,
-- the sharer's name/color (empty strings for our own measure), and a
-- preformatted distance string. ClearCrossSectionMeasure tears the panel down
-- when the measure ends. See MOVEMENT_CROSS_SECTION_REFERENCE.md.
--------------------------------------------------------------------------------

local g_crossSectionMaxWidth = 560
local g_crossSectionMaxHeight = 320

local g_crossSectionPanel = nil

local function CreateCrossSectionPanel()
	local headerLabel = gui.Label{
		classes = {"sizeM", "bold"},
		width = "auto",
		height = "auto",
		halign = "center",
		text = "",
	}

	local imagePanel = gui.Panel{
		bgimage = "#MeasureCrossSection",
		bgcolor = "white",
		width = 100,
		height = 100,
		halign = "center",
		vmargin = 4,
	}

	local resultPanel
	resultPanel = gui.Panel{
		styles = ThemeEngine.GetStyles(),
		classes = {"LaunchablePanel"},
		width = "auto",
		height = "auto",
		halign = "center",
		valign = "bottom",
		vmargin = 180,
		flow = "vertical",
		pad = 8,
		interactable = false,
		data = {},

		destroy = function(element)
			if g_crossSectionPanel == element then
				g_crossSectionPanel = nil
			end
		end,

		headerLabel,
		imagePanel,
	}

	resultPanel.data.header = headerLabel
	resultPanel.data.image = imagePanel
	return resultPanel
end

--Called by the engine each time the cross-section diagram is (re)built.
--width/height are the offscreen image's pixel dimensions; ownerName/ownerColor
--identify the sharer of a remote projection (empty strings for our own
--measure); distanceText is preformatted by the engine.
function GameHud:ShowCrossSectionMeasure(width, height, ownerName, ownerColor, distanceText)
	if g_crossSectionPanel == nil or not g_crossSectionPanel.valid then
		g_crossSectionPanel = CreateCrossSectionPanel()
		--NOTE: MainDialogPanel() is a FACTORY (creates a fresh detached panel and
		--clobbers the field); the live attached panel is the mainDialogPanel FIELD,
		--assigned during hud construction.
		local parentPanel = self.mainDialogPanel or self.dialog.sheet
		parentPanel:AddChild(g_crossSectionPanel)
	end

	local panel = g_crossSectionPanel

	--scale down uniformly to the display caps so the diagram's tiles stay square.
	local scale = math.min(1, g_crossSectionMaxWidth / width, g_crossSectionMaxHeight / height)
	panel.data.image.selfStyle.width = math.floor(width * scale)
	panel.data.image.selfStyle.height = math.floor(height * scale)

	local header = "Cross Section"
	if distanceText ~= nil and distanceText ~= "" then
		header = string.format("Cross Section: %s", distanceText)
	end
	if ownerName ~= nil and ownerName ~= "" then
		header = string.format("%s -- shared by %s", header, ownerName)
	end
	panel.data.header.text = header
	if ownerColor ~= nil and ownerColor ~= "" then
		panel.data.header.selfStyle.color = ownerColor
	else
		panel.data.header.selfStyle.color = "white"
	end
end

function GameHud:ClearCrossSectionMeasure()
	if g_crossSectionPanel ~= nil then
		if g_crossSectionPanel.valid then
			g_crossSectionPanel:DestroySelf()
		end
		g_crossSectionPanel = nil
	end
end

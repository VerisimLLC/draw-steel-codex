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

		--Measuring mode follows FOCUS, not mere existence.
		--
		--This used to arm on create and disarm on destroy, so the app
		--stayed in measuring mode for as long as the panel was open --
		--even after you clicked the Building editor and it plainly had
		--the focus ring. With several tool panels on screen at once, the
		--one you last clicked is the one that should be driving the map,
		--so the signal has to track focus the way the other tool panels'
		--do.
		--
		--Focus is taken on create so opening the panel arms it
		--immediately, which is what it always did; the difference is that
		--another panel taking focus now stands it back down.
		create = function(element)
			dmhub.rulerToolActive = gui.ChildHasFocus(element)
			--Deferred by a beat: taking focus inside create is too early
			--to stick (the panel is still being mounted -- doing it here
			--left focus nil and the tool disarmed until you clicked it).
			element:ScheduleEvent("armOnOpen", 0.01)
		end,

		--opening the panel arms it, which is what it has always done; the
		--change is that another panel taking focus now stands it down.
		armOnOpen = function(element)
			if element.valid then
				gui.SetFocus(element)
			end
		end,

		childfocus = function(element)
			dmhub.rulerToolActive = true
		end,

		childdefocus = function(element)
			dmhub.rulerToolActive = false
		end,

		--a dock tab switch away from this panel is a defocus too.
		showpanel = function(element)
			if not gui.ChildHasFocus(element) then
				gui.SetFocus(element)
			end
		end,

		hidepanel = function(element)
			if gui.ChildHasFocus(element) then
				gui.SetFocus(nil)
			end
			dmhub.rulerToolActive = false
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


DockablePanel.Register{
	name = "Measuring Tool",
    menu = "tools",
	icon = "icons/icon_tool/icon_tool_101.png",
	--summoned from the Tools menu it opens as a floating window over the
	--map (like the launchable dialog it used to be), on the right where
	--the old dialog sat. It can still be dragged into a dock.
	preferFloating = true,
	floatingHalign = "right",
	vscroll = false,
	minHeight = 100,
	maxHeight = 400,
	--the measuring modes arm map tools, so the panel needs to survive
	--Escape and map clicks the way the other tool panels do.
	stickyFocus = true,
	--a press anywhere on the panel -- its background, its title bar --
	--claims focus, so clicking it takes focus AWAY from whichever other
	--tool panel held it (you are measuring now, not drawing walls).
	focusOnClick = true,
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
		vmargin = 70,
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

local mod = dmhub.GetModLoading()

local function CreateRulerPanel()
	local hud = gamehud
	-- Every form-style setting in this panel uses the stacked (label-above-
	-- control) layout. Pull the option once so each CreateSettingsEditor call
	-- stays terse.
	local stackedOpts = {stacked = true}
	-- The slider editor hands its control a fixed 160px box, which cannot
	-- track the panel. A relative width lets it shrink with everything else.
	local stackedSliderOpts = {stacked = true, style = {width = "100%"}}
	-- The check editor takes no stacked layout of its own, but its rows still
	-- want the vertical breathing room the stacked form rows have.
	local stackedCheckOpts = {stacked = true, vmargin = 4}

	-- CreateSettingsEditor wraps every editor in an auto-width container, so
	-- the rows would size to their content and ignore the window instead of
	-- following it. Widen each container to the panel so the "98%" row/label/
	-- dropdown widths inside it resolve against the real panel width -- that
	-- is what makes the whole panel shrink and grow with the window.
	local function Setting(id, opts)
		opts = opts or stackedOpts
		local editor = CreateSettingsEditor(id, opts)
		if editor ~= nil then
			editor.selfStyle.width = "100%"
			if opts.vmargin ~= nil then
				editor.selfStyle.vmargin = opts.vmargin
			end
		end
		return editor
	end

	local persistentSetting = nil
	if dmhub.isDM then
		persistentSetting = Setting("measure:persistent", stackedCheckOpts)
	end

	--Local overrides for the stock checkbox, which is the one control here
	--that cannot shrink: its row is width = "auto" with minWidth = 200 and a
	--flat 30px height, and its caption is width = "auto" too, so a long
	--caption ("Display to others") runs straight out of a narrow panel. Pin
	--the row to the panel width and hand the caption whatever width is left
	--after the check square, with a minFontSize floor so it shrinks to fit
	--rather than overrunning. (Wrapping instead of shrinking is not an option
	--here: an "auto" height on this row stretches to the parent extent rather
	--than to its content, which is exactly why the stock rule pins 30px.)
	--
	--DIMENSION FORMS: this engine build accepts only pixels, percentages, and
	--the "100%-<pixels>" complement. The font-relative "sp"/"em" forms the
	--Definitions stubs document are NOT implemented here -- "30sp" and "2em"
	--both raise "Unrecognized dimension string" and fall back, so the row
	--cannot be made to track the Font Size setting by that route. Worse,
	--"100%-2em" fails SILENTLY (no error, wrong result), so do not reach for
	--the em/sp family in this file without testing it in a live client first.
	local rulerStyles = {
		{
			selectors = {"checkbox"},
			width = "100%",
			minWidth = 0,
			height = 30,
			borderBox = true,
		},
		{
			selectors = {"checkboxLabel"},
			--NOT "100% available": it resolves to zero inside this row and the
			--caption renders one character per line, spilling vertically out of
			--the row (the same trap DocumentSystem's find-row label documents).
			--"auto" sizes to the text; the maxWidth complement is what bounds it
			--so minFontSize has something to shrink against. 40px covers the
			--check square (21px -- "100% height" of the 70%-tall row) plus its
			--6px rmargin and the row's 4px hpad either side, with slack.
			width = "auto",
			maxWidth = "100%-40",
			height = "100%",
			minFontSize = 10,
		},
	}

	local resultPanel = gui.Panel{
		styles = ThemeEngine.MergeStyles(rulerStyles),
		classes = {"LaunchablePanel"},
		--fills whatever the dock or the floating window gives it, and grows
		--downward with its content; the host's scroll parent takes the
		--vertical overflow (see the registration below).
		width = "100%",
		height = "auto",
		halign = "left",
		valign = "top",
		flow = "vertical",
        pad = 16,
        borderBox = true,

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

		--width/height are relative + auto so the title wraps rather than
		--overruns at a narrow width or a large Font Size setting.
		gui.Label{
			text = "Measuring Tool",
			classes = {"sizeXl", "bold"},
			width = "100%",
			height = "auto",
			textAlignment = "center",
			textWrap = true,
			vmargin = 2,
		},
		Setting("measure:shape"),
		Setting("measure:coneangle"),
		Setting("measure:linewidth", stackedSliderOpts),
		Setting("measure:share", stackedCheckOpts),
		Setting("measure:snap"),
		Setting("measure:distances"),
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
	--the content is all relative-width, so the window is freely resizable on
	--both axes; the host's scroll parent (vscroll left at its default) takes
	--the vertical overflow that a large Font Size setting or a short window
	--produces, and these bounds are the range the layout was checked at.
	minHeight = 100,
	maxHeight = 520,
	minWidth = 240,
	maxWidth = 560,
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

local mod = dmhub.GetModLoading()

--The shape picker's icon grid. Mirrors the enum on the "measure:shape"
--setting (Settings.lua) -- value and bind MUST stay in step with it; the
--bind is display-only here (the engine owns the actual keybinding), it just
--means the shortcut is discoverable without opening a dropdown.
--
--Icons are Phosphor, which the client bundles whole (verified live: any
--phosphor/<name>.png resolves, and an unknown name renders blank rather than
--erroring). "selection" -- a dashed marquee -- is deliberately NOT
--"rectangle": Phosphor's rectangle is a rounded square and is indistinguishable
--from "square" at icon size, and those are two different tools.
local g_measureShapes = {
	{value = "ruler",        text = "Ruler",         bind = "alt+r",  icon = "phosphor/ruler.png"},
	{value = "circle",       text = "Circle",        bind = "alt+c",  icon = "phosphor/circle.png"},
	{value = "square",       text = "Square",        bind = "alt+s",  icon = "phosphor/square.png"},
	{value = "cone",         text = "Cone",          bind = "alt+o",  icon = "phosphor/triangle.png"},
	{value = "line",         text = "Line",          bind = "alt+l",  icon = "phosphor/line-segment.png"},
	{value = "rectangle",    text = "Rectangle",     bind = "ctrl+r", icon = "phosphor/selection.png"},
	{value = "polygon",      text = "Custom Shape",  bind = "ctrl+p", icon = "phosphor/polygon.png"},
	{value = "crosssection", text = "Cross Section", bind = "alt+x",  icon = "phosphor/mountains.png"},
}

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

	--Shape picker: one click and all eight shapes visible, replacing a dropdown
	--that cost two clicks and showed none of them. Selection is driven off the
	--setting rather than off the click, so the alt+r / ctrl+p style keybinds
	--(which the engine applies directly to the setting) keep the grid in step.
	local function CreateShapeGrid()
		local buttons = {}
		for _, shape in ipairs(g_measureShapes) do
			buttons[#buttons + 1] = gui.Panel{
				classes = {"shapeButton"},
				data = {shapeid = shape.value},

				click = function(element)
					dmhub.SetSettingValue("measure:shape", shape.value)
				end,

				--the keybind lives in the tooltip because the grid has no room
				--for it inline; the dropdown used to spell it out in the label.
				linger = function(element)
					gui.Tooltip(string.format("%s (%s)", shape.text, shape.bind))(element)
				end,

				gui.Panel{
					classes = {"shapeIcon"},
					bgimage = shape.icon,
				},
			}
		end

		--Fixed rows of four rather than a wrapping flow. Wrapping adapts to the
		--panel width, but with eight items it orphans: at the default width it
		--fitted seven and dropped one onto a row of its own. 4+4 always reads as
		--a balanced block, and four 44px buttons still fit the 240px minimum
		--width, so it never clips either.
		local rows = {}
		local perRow = 4
		for i = 1, #buttons, perRow do
			local rowButtons = {}
			for j = i, math.min(i + perRow - 1, #buttons) do
				rowButtons[#rowButtons + 1] = buttons[j]
			end
			rows[#rows + 1] = gui.Panel{
				classes = {"shapeGridRow"},
				children = rowButtons,
			}
		end

		--Iterates the captured button list, NOT element.children -- the grid's
		--direct children are rows now, so walking children would only ever see
		--the row panels and never set the selected class.
		local function SyncSelection(element)
			local current = dmhub.GetSettingValue("measure:shape")
			for _, button in ipairs(buttons) do
				button:SetClass("selected", button.data.shapeid == current)
			end
		end

		return gui.Panel{
			classes = {"shapeGrid"},
			multimonitor = {"measure:shape"},
			create = SyncSelection,
			monitor = SyncSelection,
			children = rows,
		}
	end

	--A conditional setting row that keeps its height when hidden.
	--
	--CreateSettingsEditor collapses a row whose `visible` predicate is false
	--(SettingsGui.lua sets the "collapsed" class), which is what made the panel
	--jump: switching shape added or removed a ~64px row and shoved everything
	--below it. Reserving the slot costs some blank space on the shapes that use
	--neither modifier, which this panel has to spare.
	--
	--minHeight rather than a fixed height so the row can still grow at a large
	--Font Size setting instead of clipping -- it degrades to a shift at big
	--fonts rather than to lost content. (A font-relative "sp"/"em" height would
	--express this properly but is not implemented on this engine build -- see
	--the DIMENSION FORMS note above.)
	local function ReservedRow(...)
		return gui.Panel{
			width = "100%",
			height = "auto",
			--68 = the measured height of a stacked label+control row at the
			--default Font Size (checked against both the Cone Angle dropdown
			--and the Line Width slider). 64 left a visible 4px twitch.
			minHeight = 68,
			flow = "vertical",
			halign = "left",
			children = {...},
		}
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

		--Shape picker: a vertical stack of fixed rows (see CreateShapeGrid for
		--why fixed rather than wrapping).
		{
			selectors = {"shapeGrid"},
			width = "100%",
			height = "auto",
			flow = "vertical",
			halign = "left",
			vmargin = 2,
		},
		{
			selectors = {"shapeGridRow"},
			width = "100%",
			height = "auto",
			flow = "horizontal",
			halign = "left",
		},
		{
			selectors = {"shapeButton"},
			width = 44,
			height = 44,
			margin = 2,
			bgimage = true,
			bgcolor = "@bg",
			borderWidth = 1,
			borderColor = "@border",
			halign = "left",
			valign = "top",
		},
		{
			selectors = {"shapeButton", "hover"},
			bgcolor = "@bgAlt",
			borderColor = "@fg",
			transitionTime = 0.1,
		},
		--Selected state carries THREE signals -- fill, a doubled border, and a
		--brightened icon -- so it never depends on colour alone.
		{
			selectors = {"shapeButton", "selected"},
			bgcolor = "@bgAlt",
			borderColor = "@fg",
			borderWidth = 2,
		},
		{
			selectors = {"shapeIcon"},
			width = 24,
			height = 24,
			halign = "center",
			valign = "center",
			bgcolor = "@fgMuted",
		},
		{
			selectors = {"shapeIcon", "parent:hover"},
			bgcolor = "@fg",
		},
		{
			selectors = {"shapeIcon", "parent:selected"},
			bgcolor = "@fg",
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

		--No in-panel title: the dock tab / floating window chrome already
		--names this panel "Measuring Tool", so a heading here just repeats it.
		--
		--Three groups, in the order you actually work: pick a shape, decide how
		--it snaps, then decide who sees the result. The previous order
		--interleaved them -- "Display to others" sat directly beneath Cone
		--Angle, reading as a cone option -- and left the two checkboxes
		--stranded apart from each other at opposite ends of the panel.

		--1. Shape (+ the modifier belonging to the selected shape).
		gui.Label{
			classes = {"formStacked", "sizeXs"},
			width = "98%",
			text = "Shape:",
		},
		CreateShapeGrid(),
		--Cone Angle and Line Width are mutually exclusive, so they share one
		--reserved slot; each collapses itself when its shape is not selected.
		ReservedRow(
			Setting("measure:coneangle"),
			Setting("measure:linewidth", stackedSliderOpts)
		),

		gui.MCDMDivider{},

		--2. Snap (+ Distances, which only applies while snapping).
		Setting("measure:snap"),
		ReservedRow(Setting("measure:distances")),

		gui.MCDMDivider{},

		--3. What happens to the measurement.
		Setting("measure:share", stackedCheckOpts),
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

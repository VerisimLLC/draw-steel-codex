local mod = dmhub.GetModLoading()

RegisterGameType("Hud")

function Hud.HasFocus(self)
	return gui.HasFocus()
end

function Hud.GetFocus(self)
	local result = gui.GetFocus()
	return result
end

function Hud.StickyFocus(self)
	local focus = gui.GetFocus()
	while focus ~= nil and focus.valid do
		if focus.data.stickyFocus then
			return true
		end
		focus = focus.parent
	end

	return false
end

function Hud.SetFocus(self, newFocus)
	gui.SetFocus(newFocus)
end

function Hud.CreateShapesLayer(self)
	if dmhub.isDM then
		return gui.Panel{
			interactable = false,
			bgcolor = "white",
			bgimage = "#Shapes",
			width = "100%",
			height = "100%",
		}
	else
		return nil
	end
end

local g_screenArea = core.Vector4(0,0,0,0)

--function called by dmhub to see what area of the screen is occupied by the hud.
function Hud.GetScreenHudArea(self)
	local left = 0
	local right = 0
    
	if gamehud ~= nil and not dmhub.GetSettingValue("graphics:uiblur") then
		if rawget(gamehud, "leftDock") ~= nil and (not gamehud.leftDock:HasClass("offscreen")) and #gamehud.leftDock.data.GetChildren() > 0 then
			left = (DockablePanel.DockWidth/1920) * (1920/1080) / (self.dialog.width/self.dialog.height)
		end
		if rawget(gamehud, "rightDock") ~= nil and (not gamehud.rightDock:HasClass("offscreen")) and #gamehud.rightDock.data.GetChildren() > 0 then
			right = DockablePanel.DockWidth/1920 * (1920/1080) / (self.dialog.width/self.dialog.height)
		end
	end

    g_screenArea.x = left
    g_screenArea.y = right
    return g_screenArea
end

local g_worldPanelArea = core.Vector4(0,0,0,0)

--same as above but special version for World Panel
function Hud.GetScreenHudAreaWorldPanel(self)
	local left = 0
	local right = 0
    
	if gamehud ~= nil then
        --the GetChildren() calls are expensive. Try to work out a more efficient way to do them if we need to have them.
		if gamehud:has_key("leftDock") and (not gamehud.leftDock:HasClass("offscreen")) then --and #gamehud.leftDock.data.GetChildren() > 0 then
			left = (DockablePanel.DockWidth/1920) * (1920/1080) / (self.dialog.width/self.dialog.height)
		end
		if gamehud:has_key("rightDock") and (not gamehud.rightDock:HasClass("offscreen")) then --and #gamehud.rightDock.data.GetChildren() > 0 then
			right = DockablePanel.DockWidth/1920 * (1920/1080) / (self.dialog.width/self.dialog.height)
		end
	end

    g_worldPanelArea.x = left
    g_worldPanelArea.y = right
    return g_worldPanelArea
end

--- Owner-routed modals: a modal fired from a panel living in a native
--- popout window (see Panel:MoveToNativeWindow) must appear IN that OS
--- window, not in the main app window on another monitor. Callers opt in
--- by passing options.owner = <the element the modal concerns>; when the
--- owner's hierarchy root is a native-window root (marked with
--- data.nativeWindowRoot = true by the popout flows), the modal parents
--- into a lazily-created full-bleed modal layer INSIDE that root -- which
--- keeps the host's style cascade, since a popout root owns its whole
--- cascade. No owner (or a main-window owner) means the global modalPanel,
--- exactly as before.
---
--- The layer claims Escape at EXIT_MODAL_DIALOG, which outranks the popout
--- host's own EXIT_DIALOG escape -- so Escape closes the modal, not the
--- whole OS window (same ordering modals get in the main window).
--- @param owner nil|Panel
--- @return Panel
function Hud.ResolveModalLayer(self, owner)
	if owner == nil or (not owner.valid) then
		return self.modalPanel
	end
	local root = owner.root
	if root == nil or (not root.valid) then
		return self.modalPanel
	end
	local rootData = root.data
	if rootData == nil or rootData.nativeWindowRoot ~= true then
		return self.modalPanel
	end

	local layer = rootData.popoutModalLayer
	if layer ~= nil and layer.valid then
		return layer
	end

	local hud = self
	layer = gui.Panel{
		id = 'popout-modal-panel',
		--mirrors ModalDialogPanel: the full-bleed bgimage is what blocks
		--interaction with the window behind the modal.
		bgimage = 'panels/square.png',
		classes = {'hidden'},
		--the host lays out its children vertically; the modal layer is an
		--overlay, not a row.
		floating = true,
		width = "100%",
		height = "100%",
		styles = {
			{
				valign = 'center',
				halign = 'center',
				bgcolor = 'clear',
			},
		},

		--Escape closes the topmost modal in THIS window's layer. Dialogs
		--that register their own escape handling (EXIT_MODAL_DIALOG,
		--registered later so they sort first) still win, same as globally.
		captureEscape = true,
		escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
		escape = function(element)
			hud:CloseModalInLayer(element)
		end,
	}
	root:AddChild(layer)
	rootData.popoutModalLayer = layer
	return layer
end

--- Promoted popout dialogs (Phase 5.4 of POPOUT_PANELS_PLAN.md): a modal
--- routed into a popout window's layer that WANTS to be bigger than the OS
--- window (its design size overflows the popout) is lifted into a
--- borderless, transparent, modal-to-parent child OS window of its own,
--- sized to the dialog, centered over the popout and free to extend beyond
--- its bounds -- instead of shrink-to-fitting inside a tiny window.
---
--- The in-window layer stays up, empty of the dialog, as the parent
--- window's input blocker and its escape claimant. A 1x1 placeholder holds
--- the dialog's slot in the layer's child stack so CloseModalInLayer keeps
--- addressing modals by position; every teardown path (the close pop, the
--- popout window closing, Lua reload) destroys the placeholder, whose
--- destroy handler destroys the child-window host -- and the engine closes
--- a native window whose panel died.

--selfStyle stores dimensions PARSED, not as the strings the caller wrote:
--percentages come back as fractions ("94%" -> 0.94, "150%" -> 1.5), and
--"auto" and compound expressions ("100%-20") both come back as 1; real
--pixel values come back as themselves. A dialog's DESIGN size is only
--ever a real pixel count, and anything in the fraction range means
--"scales with the window", which can never overflow it. Threshold 4: no
--dialog has a sub-4px design dimension and no percentage exceeds 400%.
local function DesignDimension(value)
	if type(value) == "number" and value > 4 then
		return value
	end
	return nil
end

--The size a dialog WANTS, from its own style: a pixel width/height, or
--the maxWidth/maxHeight design cap behind a shrink-to-fit percentage (the
--converted-dialog pattern: width = "94%", maxWidth = <design px>). nil in
--a dimension means "scales with the window" -- it can never overflow.
local function ModalPreferredSize(modal)
	local style = modal.selfStyle
	local w = DesignDimension(style.width)
	local maxw = DesignDimension(style.maxWidth)
	if w == nil then
		w = maxw
	elseif maxw ~= nil and maxw < w then
		w = maxw
	end
	local h = DesignDimension(style.height)
	local maxh = DesignDimension(style.maxHeight)
	if h == nil then
		h = maxh
	elseif maxh ~= nil and maxh < h then
		h = maxh
	end
	return w, h
end

--The promoted dialog becomes the root of its own hierarchy in the child
--window, so nothing above it supplies Styles.Default or the theme -- the
--same style-island problem the popout host solves, restated for dialogs
--(which, unlike tooltips, are NOT self-styled; they inherit the popout
--host's cascade through the modal layer today).
local function PromotedDialogStyles()
	--COPY the theme styles before appending: GetStyles returns its shared
	--cached table (see DocumentWindowStyles in DocumentSystem.lua).
	local styles = {}
	for _, rule in ipairs(ThemeEngine.GetStyles()) do
		styles[#styles + 1] = rule
	end
	--parity with dialogs inside the popout window (DocumentWindowStyles'
	--chrome rules): borderless, and fully opaque -- the child window is
	--transparent and there is no app surface behind the dialog to blur
	--through, so translucency would bleed the desktop into the surface.
	--Rounded framedPanel corners survive: the WINDOW is transparent.
	styles[#styles + 1] = gui.Style{
		classes = {"framedPanel"},
		priority = 6,
		opacity = 1,
		borderWidth = 0,
		borderColor = "clear",
	}
	return { Styles.Default, styles }
end

--Deferred one tick from ShowModal so the dialog has laid out in the layer
--(measure-then-promote, like tooltips: the in-layer size feeds the
--decision, the style-declared design size feeds the window).
local function PromoteModalToChildWindow(hud, layer, modal)
	if (not layer.valid) or (not modal.valid) then
		return
	end
	local root = layer.root
	if root == nil or (not root.valid) then
		return
	end
	if GameHud.instance == nil or GameHud.instance.documentsPanel == nil or
		(not GameHud.instance.documentsPanel.valid) then
		return
	end

	--the layer is full-bleed inside the popout root: its rendered rect IS
	--the OS window's client size (1 unit = 1 px on popout canvases).
	local winW = layer.renderedWidth
	local winH = layer.renderedHeight
	if winW <= 0 or winH <= 0 or modal.renderedWidth <= 0 then
		return
	end

	local wantW, wantH = ModalPreferredSize(modal)
	local forceHeight = wantH ~= nil
	wantW = wantW or modal.renderedWidth
	wantH = wantH or modal.renderedHeight

	--the app screen is the proxy for the desktop's size (same proxy the
	--popout tooltip placement uses); a dialog bigger than the desktop
	--helps nobody.
	local screen = dmhub.screenDimensions
	if screen ~= nil then
		wantW = math.min(wantW, math.floor(screen.x * 0.9))
		wantH = math.min(wantH, math.floor(screen.y * 0.9))
	end

	if wantW <= winW + 2 and wantH <= winH + 2 then
		--fits the popout window; the in-window layer path is right.
		return
	end

	--find the dialog in the layer's stack (it may have been closed, or a
	--modal may have stacked above it, before this tick fired).
	local children = layer.children
	local index = nil
	for i, c in ipairs(children) do
		if c == modal then
			index = i
		end
	end
	if index == nil then
		return
	end

	local host
	local placeholder = gui.Panel{
		id = "promoted-modal-placeholder",
		width = 1,
		height = 1,
		interactable = false,
		data = {
			promotedModal = modal,
		},
		destroy = function(element)
			if host ~= nil and host.valid then
				host:DestroySelf()
			end
		end,
	}

	host = gui.Panel{
		id = "popout-modal-child",
		styles = PromotedDialogStyles(),
		width = "auto",
		height = "auto",
		flow = "vertical",
		halign = "left",
		valign = "top",
		--parked off-screen for the layout pass between AddChild and
		--MoveToNativeWindow: the move measures the host's rect to size
		--the OS window (same two-step as the popout host itself).
		x = -30000,
		y = 0,

		--Escape pressed IN the child window: the engine routes it to this
		--window's own escape chain. Close the dialog exactly like Escape
		--in the parent window (where the layer keeps its claim). Same
		--priority as the layer, so a dialog registering its own
		--EXIT_MODAL_DIALOG handling still wins, same as in-window.
		captureEscape = true,
		escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
		escape = function(element)
			hud:CloseModalInLayer(layer)
		end,
	}

	--apply the design size the window denied the dialog: in the child
	--window percentages resolve against the child canvas -- which is
	--SIZED to the dialog -- so the shrink-to-fit style would re-shrink
	--it. Height is only pinned when the dialog declared a numeric
	--height/maxHeight; "auto" stays auto and re-wraps at design width.
	modal.selfStyle.width = wantW
	if forceHeight then
		modal.selfStyle.height = wantH
	end

	modal:Unparent()
	host:AddChild(modal)
	children[index] = placeholder
	layer.children = children
	placeholder.data.promotedHost = host

	GameHud.instance.documentsPanel:AddChild(host)

	--second step: the host has laid out at the dialog's design size; lift
	--it into a modal-child window centered on the popout window. Offsets
	--are parent-relative and may be negative -- the dialog extending
	--beyond the popout's bounds is the point. If the companion died since
	--the support check, the engine demotes this to a plain toplevel
	--rather than stranding the panel.
	dmhub.Schedule(0.1, function()
		if mod.unloaded or (not host.valid) or (not modal.valid) then
			return
		end
		if (not layer.valid) or (not placeholder.valid) then
			--closed while parking; the placeholder's destroy handler has
			--already torn the host down (or is about to).
			return
		end
		local rootNow = layer.root
		if rootNow == nil or (not rootNow.valid) then
			return
		end
		host:MoveToNativeWindow{
			windowType = "modalchild",
			parentPanel = rootNow,
			x = math.floor((layer.renderedWidth - host.renderedWidth) / 2),
			y = math.floor((layer.renderedHeight - host.renderedHeight) / 2),
		}
		modal:PulseClass("fadein")
	end)
end

--- Shows a modal dialog. Returns the modal layer used, so callers that
--- close programmatically can use CloseModalInLayer -- immune to the
--- owner element being destroyed while the modal is up.
--- @param modal Panel
--- @options {nofade: nil|boolean, owner: nil|Panel}
--- @return Panel
function Hud.ShowModal(self, modal, options)
	local layer = self:ResolveModalLayer(options ~= nil and options.owner or nil)
	local children = layer.children
	children[#children+1] = modal
	layer.children = children
	layer:RemoveClass('hidden')
	layer:SetAsLastSibling()

	if options == nil or (not options.nofade) then
		modal:PulseClass("fadein")
	end

	--Phase 5.4: a modal routed into a popout window's layer may be lifted
	--into a desktop-level modal-child OS window when its design size
	--overflows the popout. Decided a tick later, once the dialog has laid
	--out. Gated on the live companion advertising child-window support
	--(dmhub.popoutChildWindowsSupported reads nil on older engines).
	if layer ~= self.modalPanel and dmhub.popoutChildWindowsSupported == true then
		local root = layer.root
		if root ~= nil and root.valid and root.data ~= nil and root.data.nativeWindowRoot == true then
			local hud = self
			dmhub.Schedule(0.05, function()
				if mod.unloaded then
					return
				end
				PromoteModalToChildWindow(hud, layer, modal)
			end)
		end
	end

	return layer
end

--- Close the topmost modal in the given layer (the global modalPanel or a
--- popout window's own layer).
--- @param layer Panel
function Hud.CloseModalInLayer(self, layer)
	if layer == nil or (not layer.valid) then
		return
	end
	local children = layer.children
	if #children > 0 then
		table.remove(children, #children)
	end
	layer.children = children

	if #children == 0 then
		layer:AddClass('hidden')
	end
end

--- Close the modal dialog that is currently displayed. owner (optional)
--- routes the close the same way ShowModal routes the open: pass the same
--- owner the modal was shown with to close a popout-window modal.
--- @param owner nil|Panel
function Hud.CloseModal(self, owner)
	self:CloseModalInLayer(self:ResolveModalLayer(owner))
end

--- Get the currently displayed modal dialog. owner (optional) asks about
--- the layer that owner's window uses; nil asks about the global layer.
--- @param owner nil|Panel
--- @return nil|Panel
function Hud.GetModal(self, owner)
	if self == nil or self.modalPanel == nil or (not self.modalPanel.valid) then
		return nil
	end

	local layer = self:ResolveModalLayer(owner)
	if layer == nil or (not layer.valid) then
		return nil
	end

    -- GetChild is 0-based: child 0 is the first modal. Passing 1 asked for a
    -- (usually non-existent) SECOND modal, so GetModal returned nil whenever a
    -- single modal was open. That made canGameInput true under the modal and
    -- routed command-context keys (e.g. the PDF viewer's left/right paging) down
    -- the ExecuteCommand path instead of delivering them as a 'command' event.
    local result = layer:GetChild(0)

    -- A modal promoted into its own child OS window leaves only a bookkeeping
    -- placeholder in the layer; report the real dialog.
    if result ~= nil and result.valid then
        local resultData = result.data
        if resultData ~= nil and resultData.promotedModal ~= nil and resultData.promotedModal.valid then
            return resultData.promotedModal
        end
    end

    return result
end

--- @class ModalMessageArgs
--- @param title nil|string @message shown at the top
--- @param message string @message taking up the bulk of the dialog.
--- @param panel nil|Panel An arbitrary panel to display in the center.
--- @param options nil|{text: string, execute: function} a list of buttons that will be displayed at the bottom.
--- @param owner nil|Panel The element this message concerns. If it lives in a native popout window, the message appears in THAT window instead of the main one.

--- Display a modal message dialog.
--- @param args ModalMessageArgs
function Hud:ModalMessage(args)
	local titleText = nil
	if args.title ~= nil then
		titleText = gui.Label({
			id = 'modal-title',
			classes = {"modalTitle"},
			text = args.title,
		})
	end

	local messageText = nil
	if args.message ~= nil then
		messageText = gui.Label({
			id = 'modal-message',
			classes = {"modalMessage"},
			text = args.message,
		})
	end

	if args.panel ~= nil then
		messageText = args.panel
	end

	local argOptions = args.options
	if argOptions == nil then
		argOptions = { { text = "Okay" } }
	end

	--captured by the button closures; assigned when ShowModal below
	--returns the layer it routed to (args.owner may live in a popout
	--window). Closing by layer stays correct even if the owner element
	--is destroyed while the message is up.
	local modalLayer = nil

	local optionsPanel = nil
	local options = {}
	for i,option in ipairs(argOptions) do
		local optionInfo = option
		options[#options+1] = gui.Button({
			id = 'modal-button-' .. optionInfo.text,
			classes = {"sizeL"},
			text = optionInfo.text,
			events = {
				click = function()
					self:CloseModalInLayer(modalLayer)
					if optionInfo.execute ~= nil then
						optionInfo.execute()
					end
				end,
			},
		})
	end

	optionsPanel = gui.Panel({
		id = 'modal-buttons-panel',
		height = 'auto',
		width = '80%',
		valign = 'bottom',
		vmargin = 20,
		flow = 'horizontal',
		children = options,
	})

	modalLayer = self:ShowModal(
		gui.Panel({
			id = 'modal-dialog',
			classes = {"framedPanel"},
			styles = ThemeEngine.GetStyles(),
			halign = 'center',
			valign = 'center',
			width = '60%',
			height = '60%',
			flow = 'vertical',
			children = {
				titleText,
				messageText,
				optionsPanel,
			},
		}),
		{ owner = args.owner }
	)
end

--args.title = string message shown at the top
--args.options = a list of { text = string, click = function() } of menu options

--- Show a simple modal choice dialog.
--- @param args {title: string, options: {text: string, click: function}[]}
function Hud:ModalChoice(args)
	local optionPanels = {}

	for i,option in ipairs(args.options) do
		optionPanels[#optionPanels+1] = gui.Label{
			classes = {"option", "row", cond(i%2 == 1, "oddRow", "evenRow")},
			text = option.text,
			click = function(element)
				self:CloseModal()

				if option.click ~= nil then
					option.click()
				end
			end,
		}
	end

	local dialog
	dialog = gui.Panel{
		classes = {"framedPanel"},
		-- Theme provides framedPanel + row/oddRow/evenRow + base label rules.
		-- Local extras: option-specific size/font and bespoke red hover/press
		-- colors. Hover/press literals stay (component-specific dark-red wash;
		-- could map to @danger family later if you want them theme-driven).
		styles = ThemeEngine.MergeStyles({
			{
				selectors = {"option"},
				height = 24,
				fontSize = 20,
				width = "100%",
				valign = "top",
			},
			{
				selectors = {"option", "hover"},
				bgcolor = "#880000ff",
			},
			{
				selectors = {"option", "press"},
				bgcolor = "#550000ff",
			},
		}),

		width = 1024,
		height = 800,

		gui.Label{
			classes = {"title"},
			valign = "top",
			fontSize = 28,
			bold = true,
			text = args.title,
		},

		gui.Panel{
			height = "90%",
			width = "70%",
			flow = "vertical",
			halign = "center",
			valign = "center",
			vscroll = true,
			children = optionPanels,
		}
	}

	self:ShowModal(dialog)
	return dialog
end

function Hud.MainDialogPanel(self)
	self.dialogWorldPanel = gui.Panel{
		thinkTime = 1,
		interactable = false,
		halign = "left",
		valign = "top",
		think = function(element)
			local area = self:GetScreenHudAreaWorldPanel()
			element.x = self.dialog.width*area.x
			element.y = self.dialog.height*area.z

			element.selfStyle.width = self.dialog.width*(1 - (area.x + area.y))
			element.selfStyle.height = self.dialog.height*(1 - (area.z + area.w))
		end,
		create = function(element)
			element:FireEvent("think")
		end,
	}

	local result = gui.Panel({
		id = 'main-dialog-panel',

		interactable = false,

		self.dialogWorldPanel,

		width = "100%",
		height = "100%",
		valign = 'bottom',
		halign = 'center',
	})

	self.mainDialogPanel = result

	return result
end

function Hud.ModalDialogPanel(self)
	local result = gui.Panel({
		id = 'modal-dialog-panel',
		bgimage = 'panels/square.png',

		classes = {'hidden'},

		width = "100%",
		height = "100%",

		styles = {
			{
				valign = 'center',
				halign = 'center',
				bgcolor = 'clear',
			},
		}
	})

	self.modalPanel = result

	return result
end

--- @class UploadDialogArgs
--- @field text string
--- @field IsConfirmed nil|(fun():boolean)

--- Show an upload dialog.
--- @param options UploadDialogArgs
function Hud:UploadDialog(options)

	local label = gui.Label{
		bgimage = 'panels/square.png',
		classes = {"uploadDialogLabel"},
		text = options.text,

		-- Color, bgcolor, borderColor come from the {label, uploadDialogLabel}
		-- theme rule on the parent dialog so this label follows scheme switches.
		-- Layout/typography stays inline. Dropped a stray duplicate `height` key
		-- (was `'center'` then `'auto'`); converted '80%' fontSize to absolute
		-- 28 since the theme's {label} rule sets a 14px cascade base.
		style = {
			valign = 'center',
			width = 'auto',
			height = 'auto',
			pad = 100,
			cornerRadius = 16,
			borderWidth = 2,
			fontSize = 28,
			textAlignment = 'center',
		},
		monitorAssets = true,
		events = {
			refreshAssets = function(element)
				if options.IsConfirmed == nil or options.IsConfirmed() then
					self:CloseModal()
				end
			end,

			progress = function(element, amount)
				element.text = string.format('%s (%.0f%%)', options.text, amount*100)
			end,
		},

		children = {

		},

	}

	local closeButton = gui.Button{
		classes = {"closeButton", "sizeL"},
		halign = 'right',
		valign = 'top',
		events = {
			click = function(element)
				self:CloseModal()
			end,
		}
	}

	local dialog = gui.Panel{
		style = {
			width = 500,
			height = 400,
			flow = 'none',
		},
		styles = ThemeEngine.MergeStyles({
			{
				selectors = {"label", "uploadDialogLabel"},
				color = "@text",
				bgcolor = "@grey02",
				borderColor = "@text",
			},
		}),
		children = {
			label,
			closeButton,
		},
	}

	self:ShowModal(dialog)
	return dialog
end

RegisterGameType("GameHud", "Hud")

-- Fullscreen host panel for the shop/inventory screen. Set by
-- dmhub.CreateGameHud for the in-game hud; stays false for the lobby hud
-- (the lobby uses the titlescreen as the shop host instead).
GameHud.shopPanel = false

-- The dialog currently being presented to players, or nil if none is. The
-- in-game hud overrides this with an instance closure over its presentation
-- state (see dmhub.CreateGameHud in GameHud.lua). The lobby hud has no
-- presentation system at all -- it never fires "presentDialog" -- so nothing
-- is ever presented there and nil is the truthful answer. This class-level
-- default is what makes the accessor total: without it, callers running under
-- the lobby hud (e.g. the Present button that CustomDocument:CreateInterface
-- puts on info-bubble documents, which the lobby does show) fall through
-- GameHud to the base Hud type and raise "Attempt to read unknown field".
GameHud.GetCurrentlyPresentedDialog = function()
	return nil
end

ActionBarElements = {}

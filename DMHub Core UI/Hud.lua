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
		if gamehud:has_key("leftDock") and (not gamehud.leftDock:HasClass("offscreen")) and #gamehud.leftDock.data.GetChildren() > 0 then
			left = (DockablePanel.DockWidth/1920) * (1920/1080) / (self.dialog.width/self.dialog.height)
		end
		if gamehud:has_key("rightDock") and (not gamehud.rightDock:HasClass("offscreen")) and #gamehud.rightDock.data.GetChildren() > 0 then
			right = DockablePanel.DockWidth/1920 * (1920/1080) / (self.dialog.width/self.dialog.height)
		end
	end

    g_worldPanelArea.x = left
    g_worldPanelArea.y = right
    return g_worldPanelArea
end

--- Shows a modal dialog.
--- @param modal Panel
--- @options {nofade: nil|boolean}
function Hud.ShowModal(self, modal, options)
	local children = self.modalPanel.children
	children[#children+1] = modal
	self.modalPanel.children = children
	self.modalPanel:RemoveClass('hidden')
	self.modalPanel:SetAsLastSibling()

	if options == nil or (not options.nofade) then
		modal:PulseClass("fadein")
	end
end

--- Close the modal dialog that is currently displayed.
function Hud.CloseModal(self)
	local children = self.modalPanel.children
	if #children > 0 then
		table.remove(children, #children)
	end
	self.modalPanel.children = children

	if #children == 0 then
		self.modalPanel:AddClass('hidden')
	end
end

--- Get the currently displayed modal dialog.
--- @return nil|Panel
function Hud.GetModal(self)
	if self == nil or self.modalPanel == nil or (not self.modalPanel.valid) then
		return nil
	end

    return self.modalPanel:GetChild(1)
end

--- @class ModalMessageArgs
--- @param title nil|string @message shown at the top
--- @param message string @message taking up the bulk of the dialog.
--- @param panel nil|Panel An arbitrary panel to display in the center.
--- @param options nil|{text: string, execute: function} a list of buttons that will be displayed at the bottom.

--- Display a modal message dialog.
--- @param args ModalMessageArgs
function Hud:ModalMessage(args)
	local titleText = nil
	if args.title ~= nil then
		titleText = gui.Label({
			id = 'modal-title',
			text = args.title,
			selfStyle = {
				margin = 16,
				fontSize = '80%',
				color = 'white',
				valign = 'top',
				halign = 'center',
				textAlignment = 'center',
				width = 'auto',
				height = 'auto',
			},
		})
	end

	local messageText = nil
	if args.message ~= nil then
		messageText = gui.Label({
			id = 'modal-message',
			text = args.message,
			selfStyle = {
				width = '80%',
				height = 'auto',
				color = 'white',
				fontSize = '60%',
				valign = 'center',
				halign = 'center',
				textAlignment = 'left',
			},
		})
	end

	if args.panel ~= nil then
		messageText = args.panel
	end

	local argOptions = args.options
	if argOptions == nil then
		argOptions = { { text = "Okay" } }
	end

	local optionsPanel = nil
	local options = {}
	for i,option in ipairs(argOptions) do
		local optionInfo = option
		options[#options+1] = gui.PrettyButton({
			id = 'modal-button-' .. optionInfo.text,
			text = optionInfo.text,
			width = 140,
			height = 60,
			events = {
				click = function()
					self:CloseModal()
					if optionInfo.execute ~= nil then
						optionInfo.execute()
					end
				end,
			},
		})
	end

	optionsPanel = gui.Panel({
		id = 'modal-buttons-panel',
		style = {
			height = 'auto',
			width = '80%',
			valign = 'bottom',
			vmargin = 20,
			flow = 'horizontal',
		},
		children = options,
	})

	self:ShowModal(
		gui.Panel({
			id = 'modal-dialog',
			classes = {"framedPanel"},

			styles = {
				Styles.Panel,
				{
					halign = 'center',
					valign = 'center',
					width = '60%',
					height = '60%',
					flow = 'vertical',
				}
			},
			children = {
				titleText,
				messageText,
				optionsPanel,
			},
		})
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
		styles = {
			Styles.Default,
			Styles.Panel,
			Styles.Table,
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
		},

		width = 1024,
		height = 800,

		gui.Label{
			classes = {"title"},
			valign = "top",
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
		text = options.text,

		style = {
			valign = 'center',
			height = 'center',
			width = 'auto',
			height = 'auto',
			pad = 100,
			cornerRadius = 16,
			borderWidth = 2,
			borderColor = 'black',
			bgcolor = '#777777ff',
			color = 'white',
			fontSize = '80%',
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

	local closeButton = gui.IconButton{
		icon = 'ui-icons/close.png',
		style = {
			halign = 'right',
			valign = 'top',
			width = 24,
			height = 24,
		},
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
		children = {
			label,
			closeButton,
		},
	}
	
	self:ShowModal(dialog)
	return dialog
end

RegisterGameType("GameHud", "Hud")

ActionBarElements = {}

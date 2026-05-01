local mod = dmhub.GetModLoading()

--- @class ModalDialogArgs:PanelArgs
--- @param title string
--- @param buttons {text: string, click: nil|function, escapeActivates: boolean}[]
--- @param classes: nil|string[]

--- Create a modal dialog
--- @param options ModalDialogArgs
function GameHud:ModalDialog(options)

	local styles = ThemeEngine.GetStyles()

	local width = options.width
	local height = options.height

	options.width = nil
	options.height = nil

	local title = gui.Label{
		classes = {"dialogTitle"},
		text = options.title,
	}

	options.title = nil


	local dialogPanel

	local buttonElements = {}

	local buttons = options.buttons or { { text = "Close" } }
	options.buttons = nil

	for _,button in ipairs(buttons) do
		buttonElements[#buttonElements+1] =
			gui.Button{
				classes = {"btnLg"},
				text = button.text,
				escapeActivates = button.escapeActivates,
				escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
				halign = "right",
				hmargin = 8,
				events = {
					click = function(element)
						if button.click then
							button.click()
						end

						dialogPanel:FireEvent("close")
					end,
				}
			}
	end

	local buttonPanel = gui.Panel{
		width = "100%",
		height = 60,
		flow = "horizontal",
		valign = "bottom",
		children = buttonElements,
	}

	local clientPanel = gui.Panel(options)

	local mainPanel = gui.Panel{
		width = "100%-32",
		height = "100%-32",
		flow = "vertical",
		halign = "center",
		valign = "center",
		children = {
			title,
			clientPanel,
			buttonPanel,
		}
	}

	dialogPanel = gui.Panel{
		classes = {'framedPanel'},

		width = width or 1024,
		height = height or 768,

		styles = styles,

		close = function(element)
			gamehud:CloseModal()
		end,

		children = {
			mainPanel,
		},
	}

	gamehud:ShowModal(dialogPanel)
	return dialogPanel

end

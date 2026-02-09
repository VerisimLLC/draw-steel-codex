local mod = dmhub.GetModLoading()

--This file controls much of the default styling that DMHub uses for panels.

local textColor = "srgb:#C09571"
local textPendingColor = "#999999"
local backgroundColor = "#161616"

textColor = "white"

local dialogGradient = gui.Gradient{
	point_a = {x = 0, y = 0},
	point_b = {x = 1, y = 1},
	stops = {
		{
			position = 0,
			color = "#000000",
		},
		{
			position = 1,
			color = "#060606",
		},
	},
}

local barGradient = gui.Gradient{
	point_a = {x = -0.02, y = 0},
	point_b = {x = 1.02, y = 0},
	stops = {
		{
			position = 0,
			color = "#060605",
		},
		{
			position = 1,
			color = "#191A18",
		},
	},
}

local implementationStatusColors = {
    [0] = "#f82fcd",  -- won't implement (pink)
    [1] = "#ff0000",  -- unimplemented (red)
    [2] = "#cd7f32",  -- bronze
    [3] = "#c0c0c0",  -- silver
    [4] = "#ffd700",  -- gold
}

Styles = {

    portraitWidthPercentOfHeight = 100*3/4,
    portraitHeightPercentOfWidth = 100*4/3,

	textColor = textColor,
	backgroundColor = backgroundColor,
    forbiddenColor = "#C73131",

    RichBlackGradient = barGradient,

    ImplementationStatusColors = implementationStatusColors,

    RichBlack02 = "#10110F",
    RichBlack03 = "#191A18",
    RichBlack04 = "#343432",
    Grey02 = "srgb:#666666",
    Grey01 = "srgb:#9F9F9B",

    Cream01 = "srgb:#F3EDE7",
    Cream02 = "srgb:#DFCFC0",
    Cream03 = "srgb:#BC9B7B",

    Gold04 = "srgb:#E9B86F",
    Gold03 = "srgb:#F1D3A5",
    Gold02 = "srgb:#49362C",

    ModifierBuffColor = "srgb:#2A4DFF",
    ModifierDebuffColor = "red",


	bullet = "\u{2022}",
	emdash = "\u{2014}",
	multiplySign = "\u{00D7}",

	dialogGradient = dialogGradient,

    icons = {
        visible = "icons/standard/Icon_App_Visible.png",
        hidden = "icons/standard/Icon_App_Hidden.png",
        locked = "icons/standard/Icon_App_Lock.png",
        unlocked = "icons/standard/Icon_App_Unlock.png",
    },

    tempGradient = gui.Gradient {
        point_a = {x = 0, y = 0},
        point_b = {x = 1, y = 0},
        stops = {
            {
                position = 0,
                color = "#6666aa",
            },
            {
                position = 1,
                color = "#6666ff",
            },
        },
    },

    grayscaleGradient = gui.Gradient{
        point_a = {x = 0, y = 0},
        point_b = {x = 1, y = 0},
        stops = {
            {
                position = 0,
                color = "#484848",
            },
            {
                position = 1,
                color = "#C1C1C1",
            },
        },
    },

    healthGradient = gui.Gradient{
        point_a = {x = 0, y = 0},
        point_b = {x = 1, y = 0},
        stops = {
            {
                position = 0,
                color = "#004d52",
            },
            {
                position = 1,
                color = "#00b8c4",
            },
        },
    },

    bloodiedGradient = gui.Gradient{
        point_a = {x = 0, y = 0},
        point_b = {x = 1, y = 0},
        stops = {
            {
                position = 0,
                color = "#a15102",
            },
            {
                position = 1,
                color = "#fa9a00",
            },
        },
    },


    damagedGradient = gui.Gradient{
        point_a = {x = 0, y = 0},
        point_b = {x = 1, y = 0},
        stops = {
            {
                position = 0,
                color = "#440000",
            },
            {
                position = 1,
                color = "#bb0000",
            },
        },
    },

	conditionGradient = gui.Gradient{
        point_a = {x = 0, y = 0},
        point_b = {x = 1, y = 0},
        stops = {
            {
                position = 0,
                color = "#000000",
            },
            {
                position = 1,
                color = textColor,
            },
        },
	},

    Triggers = {
        textColor = "white",
        triggerColor = "#cccc00",
        freeColor = "#9999ff",

        triggerColorAgainstText = "#aaaa00",
        freeColorAgainstText = "#7777ee",
    },
    TriggerStyles = {
        gui.Style{
            selectors = {"triggeredActionPanel"},
            bgcolor = "#cccc00",
            color = "white",
            bold = true,
            textAlignment = "center",
        },
        gui.Style{
            selectors = {"triggeredActionPanel", "free"},
            bgcolor = "#9999ff",
            color = "white",
        },
        gui.Style{
            selectors = {"triggeredActionPanel", "expended"},
            saturation = 0.3,
            brightness = 0.3,
            color = "black",
        },
    },

	Default = {
		gui.Style{
			scrollHandleColor = "#999999",
		},

		--make it so the hidden class hides things.
		gui.Style({
			selectors = { 'hidden' },
			hidden = 1,
		}),

		gui.Style({
			selectors = { 'collapsed' },
			collapsed = 1,
		}),

		gui.Style{
			selectors = {"hideForPlayers", "player"},
			hidden = 1,
		},

		gui.Style{
			selectors = {"collapsedForPlayers", "player"},
			collapsed = 1,
		},

		gui.Style({
			priority = 100,
			selectors = { 'collapsed-anim' },
			collapsed = 1,
			transitionTime = 0.2,
			uiscale = { x = 1, y = 0.001 },
		}),

		--make sure dockable panels are interactable.
		gui.Style{
			selectors = {"dockablePanel"},
			bgimage = "panels/square.png",
		},

		--dropdowns.

		gui.Style{
			selectors = {"dropdown"},
			width = 260,
			height = 28,
			flow = "none",
			borderColor = textColor,
			bgcolor = "black",
			border = {x1 = 2, x2 = 2, y1 = 2, y2 = 2},
		},
		gui.Style{
			selectors = {"dropdown", "expandedBottom"},
			border = {x1 = 2, x2 = 2, y1 = 0, y2 = 2},
		},
		gui.Style{
			selectors = {"dropdown", "expandedTop"},
			border = {x1 = 2, x2 = 2, y1 = 2, y2 = 0},
		},
		gui.Style{
			selectors = {"dropdown", "hover", "~search"},
			bgcolor = textColor,
		},
		gui.Style{
			selectors = {"label", "dropdownLabel"},
			fontSize = 18,
			minFontSize = 10,
			color = textColor,
			halign = "left",
			valign = "center",
			width = "100%-40",
			height = "100%",
			hmargin = 6,
		},
		gui.Style{
			selectors = {"label", "dropdownLabel", "parent:hover"},
			color = "black",
		},
		gui.Style{
			selectors = {"dropdownTriangle"},
			height = "30%",
			width = "160% height",
			bgcolor = textColor,
			halign = "right",
			valign = "center",
			hmargin = 6,
	 
		},
		gui.Style{
			selectors = {"dropdownTriangle", "parent:hover"},
			bgcolor = "black",
		},

		--sliders
		gui.Style{
			selectors = {"sliderHandleBorder"},
			borderWidth = 2,
			borderColor = Styles.textColor,
			bgcolor = "black",
			bgimage = "panels/square.png",
			width = "60%",
			height = "60%",
			halign = "center",
			valign = "center",
		},

		gui.Style{
			selectors = {"sliderHandleInner"},
			bgimage = "panels/square.png",
			bgcolor = Styles.textColor,
			width = "30%",
			height = "30%",
			halign = "center",
			valign = "center",
		},

		--input.

		gui.Style{
			id = 'input-main',
			selectors = {'input'},
			fontSize = 12,
			height = 16,
			width = 240,
			pad = 4,
			hpad = 10,
			borderColor = "#999999",
			borderWidth = 2,
			selectedColor = '#444444',
			bgcolor = 'black',
		},

        gui.Style{
            selectors = {'input', 'focus'},
			borderColor = "white",
        },

        gui.Style{
            selectors = {"inputFaded"},
			borderColor = "black",
			borderWidth = 3,
			borderFade = true,
			bgcolor = 'black',
        },

		gui.Style{
			selectors = {"searchInput"},
			hpad = 6,
			fontSize = 16,
			bold = true,
			borderFade = false,

            color = "white",
            borderWidth = 1,
            borderColor = "grey",
		},

        gui.Style{
            selectors = {"searchInput", "focus"},
            borderColor = Styles.textColor,
        },

		--labels.
		gui.Style{
			selectors = {"label"},
			selectedColor = '#999944',
			color = textColor,
			highlightedColor = '#9999ffff',
		},

        gui.Style{
            selectors = {"label", "pending"},
            color = textPendingColor,
        },

		gui.Style{
			selectors = {'label', 'dialogTitle'},
			fontSize = 24,
			halign = "center",
			width = "auto",
			height = "auto",
			valign = "top",
			tmargin = 12,
			bmargin = 0,
		},

		gui.Style({
			selectors = {'label','link'},
			priority = 5,
			color = '#c49562',
		}),

		gui.Style({
			selectors = {'label','link','hover'},
			priority = 5,
			color = '#ff99ffff',
		}),

		gui.Style({
			selectors = {'label','link','press'},
			priority = 5,
			color = '#99ffffff',
		}),

		--highlighting good/bad ongoingEffects.
		gui.Style({
			selectors = {'highlight_good'},
			priority = 5,
			transitionTime = 1,
			bgcolor = 'green',
		}),

		gui.Style({
			selectors = {'highlight_bad'},
			priority = 5,
			transitionTime = 1,
			bgcolor = 'red',
		}),

		--clickable icons.
		gui.Style{
			selectors = {"clickableIcon"},
			bgcolor = textColor,
			width = 16,
			height = 16,
		},

		gui.Style{
			selectors = {"clickableIcon", "hover"},
			brightness = 1.5,
		},

		gui.Style{
			selectors = {"dice", "parent:clickableIcon", "parent:hover"},
			brightness = 1.5,
		},

		--buttons
		gui.Style({
			selectors = {'label', 'button'},
			textAlignment = 'center',
			fontSize = 16,
			fontWeight = "bold",
			color = textColor,
			borderColor = textColor,
			borderWidth = 2,
			width = "120% auto",
			height = "120% auto",

			hmargin = 8,
			vmargin = 8,

			bgcolor = "#222222",
			bgimage = "panels/square.png",
		}),

		gui.Style{
			selectors = {'label', 'button', 'tiny'},
			fontSize = 12,
			fontWeight = "thin",
			borderWidth = 1,
			hmargin = 2,
			vmargin = 2,
		},

		gui.Style({
			selectors = {'label', 'button', 'hover'},
			transitionTime = 0.1,
			color = "#222222",
			bgcolor = textColor,
			textAlignment = "center",
			fontWeight = "bold",
            soundEvent = "Mouse.Hover",
		}),

		gui.Style({
			selectors = {'label', 'button', 'press'},
			transitionTime = 0.1,
			brightness = 0.7,
            soundEvent = "Mouse.Click",
		}),

		gui.Style({
			selectors = {'label', 'button', 'selected'},
			color = "#222222",
			bgcolor = textColor,
			textAlignment = "center",
			fontWeight = "bold",
		}),


		gui.Style{
			selectors = {'label', "button", "prettyButton"},
			fontSize = 24,
			hmargin = 16,
			vmargin = 16,
			width = "130% auto",
			height = "130% auto",
			borderWidth = 3,
		},

		gui.Style{
			selectors = {"label", "button", "focus"},
			borderColor = "white",
		},

		--rollable styles.
		gui.Style({
			selectors = {'rollable'},
			color = '#ffaaaa',
			textAlignment = 'center',

			borderWidth = 0,
			priority = 10,
		}),
		gui.Style({
			selectors = {'rollable', 'hover'},
			bgcolor = 'black',
			borderWidth = 2,
			color = '#ffcccc',
			borderColor = '#ffcccc',
			priority = 10,
		}),
		gui.Style({
			selectors = {'rollable', 'hover', 'press'},
			borderWidth = 4,
			color = '#ffdddd',
			borderColor = '#ffdddd',
			priority = 10,
		}),

		--dialog
		gui.Style{
			priority = 5,
			classes = {"dialog-panel"},
			bgimage = 'panels/hud/button_09_frame_custom.png',
			bgcolor = 'white',
			bgslice = 20,
			border = 10,
		},
		gui.Style{
			priority = 5,
			classes = {"dialog-panel", "fadein"},
			opacity = 0,
			uiscale = {x = 0.01, y = 0.01},
			transitionTime = 0.2,
		},


		gui.Style({
			priority = 5,
			selectors = {'dialog-panel'},
			bgimage = 'panels/InventorySlot_Background.png',
			bgcolor = 'white',
		}),

		--border of a dialog.
		gui.Style{
			priority = 20,
			selectors = {'dialog-border'},
			hidden = 1,
		},

		--a close button
		gui.Style{
			priority = 5,
			selectors = {'close-button'},
			width = 24,
			height = 24,
			margin = 6,
			halign = 'right',
			valign = 'top',
			bgcolor = Styles.textColor,
		},

		gui.Style{
			priority = 5,
			selectors = {'close-button', 'hover'},
			brightness = 2,
		},

		gui.Style{
			priority = 5,
			selectors = {'close-button', 'press'},
			brightness = 0.5,
		},

		--a delete item button
		gui.Style {
			priority = 5,
			selectors = {'delete-item-button'},
			width = 24,
			height = 24,
		},

		--generic icons that act as buttons.
		gui.Style {
			selectors = {'iconButton'},
			bgcolor = textColor,
			width = 24,
			height = 24,
		},

		gui.Style {
			selectors = {'iconButton', 'hover'},
			brightness = 2,
		},

		gui.Style{
			selectors = {"iconButton", "settingsButton"},
			blend = "add",
		},



		--add button
		gui.Style{
			priority = 5,
			selectors = {'plus-button'},
			width = 24,
			height = 24,
			bgcolor = "white",
		},

		gui.Style{
			priority = 5,
			selectors = {'plus-button', 'hover'},
			brightness = 1.4,
		},

		gui.Style{
			priority = 5,
			selectors = {'plus-button', 'hover'},
			brightness = 0.8,
		},

		gui.Style{
			selectors = {'modal-dialog'},
			priority = 10,
			bgimage = 'panels/square.png',
			bgcolor = '#888888ff',
			borderWidth = 2,
			borderColor = 'black',
			cornerRadius = 8,
		},

		gui.Style{
			selectors = {'modal-button-panel'},
			priority = 10,
			width = '100%-50',
			height = 100,
			valign = 'bottom',
			halign = 'center',
			flow = 'horizontal',
		},

		gui.Style{
			selectors = {'pretty-button'},
			priority = 10,
			width = 140,
			height = 60,
		},
		gui.Style{
			selectors = {'pretty-button-label'},
			priority = 2,
			fontSize = 20,
			bold = true,
			textAlignment = 'center',
			width = 'auto',
			height = 'auto',
		},

		--tokens
		gui.Style{
			classes = {'token-image'},
			halign = 'center',
			valign = 'center',
			width = 60,
			height = 60,
		},

		gui.Style{
			classes = {'token-image-portrait'},
			bgcolor = 'white',
			width = "100%",
			height = "100%",
		},
		gui.Style{
			classes = {'token-image-frame'},
			width = "100%",
			height = "100%",
		},

		--checkboxes

		gui.Style{
			classes = {'check-mark'},
			bgimage = 'panels/square.png',
			bgcolor = textColor,
			halign = 'center',
			valign = 'center',
			width = '50%',
			height = '50%',
		},

		gui.Style{
			classes = {'check-background'},
			bgimage = 'panels/square.png',
			bgcolor = backgroundColor,
			halign = 'left',
			valign = 'center',
			height = '70%',
			width = '100% height',
			rmargin = 6,
			borderColor = textColor,
			borderWidth = 2,
		},

		gui.Style{
			classes = {'checkbox-label'},
			halign = 'left',
			valign = 'center',
			textAlignment = 'left',
			borderWidth = 0,
			fontSize = 18,
			width = 'auto',
			height = 'auto',
		},
		gui.Style{
			classes = {'checkbox-label', "rightAlign"},
			rmargin = 8,
		},

		gui.Style{
			classes = {'checkbox'},
			bgimage = 'panels/square.png',
			flow = 'horizontal',
			bgcolor = 'clear',
			height = 30,
			width = 'auto',
            minWidth = 200,
			hpad = 4,
		},

		gui.Style{
			classes = {'checkbox', 'hover', '~disabled'},
			bgcolor = '#ffffff44',
			borderWidth = 1,
			borderColor = 'white',
		},

		gui.Style{
			classes = {'check-background', 'disabled'},
			saturation = 0,
		},

		gui.Style{
			classes = {'check-mark', 'disabled'},
			saturation = 0,
		},

		gui.Style{
			classes = {'checkbox-label', 'disabled'},
			color = "#777777ff",
		},

		gui.Style{
			classes = {'hidden-unless-parent-hover'},
			hidden = 1,
		},

		gui.Style{
			classes = {'hidden-unless-parent-hover', 'parent:hover'},
			hidden = 0,
		},

		gui.Style{
			classes = {"hudIconButton"},
			width = 58,
			height = 58,
			--bgimage = "panels/hud/button_09_frame_custom.png",
			bgimage = "panels/square.png",
			bgcolor = backgroundColor,
			borderColor = textColor,
			borderWidth = 1,
		},

		gui.Style{
			classes = {"hudIconButton", "hover"},
			brightness = 2.5,
			transitionTime = 0.1,
		},

		gui.Style{
			classes = {"hudIconButton", "press"},
			brightness = 0.8,
			transitionTime = 0.1,
		},

		gui.Style{
			classes = {"hudIconButton", "disabled"},
			brightness = 0.5,
			saturation = 0.2,
		},
		
		gui.Style{
			classes = {"hudIconButton", "selected"},
			brightness = 3.0,
			saturation = 1.4,
			--y = -5,
		},

		gui.Style{
			classes = {"hudIconButton", "selected", "tab"},
			brightness = 1,
			saturation = 1,
			bgcolor = "#0d0d0d",
			border = {x1 = 1, x2 = 1, y1 = 0, y2 = 1},
		},

		gui.Style{
			classes = {"hudIconButtonIcon"},
			width = "75%",
			height = "75%",
			halign = "center",
			valign = "center",
			bgcolor = textColor,
		},

		gui.Style{
			classes = {"hudIconButtonIcon", "parent:hover"},
			brightness = 1.5,
			transitionTime = 0.1,
			scale = 1.15,
		},

		gui.Style{
			classes = {"hudIconButtonIcon", "parent:press"},
			brightness = 0.8,
			transitionTime = 0.1,
		},

		gui.Style{
			classes = {"hudIconButtonIcon", "parent:deselected"},
			saturation = 0.0,
			brightness = 0.8,
		},

		gui.Style{
			classes = {"hudIconButtonIcon", "parent:disabled"},
			saturation = 0.2,
			brightness = 0.5,
			scale = 1,
		},

		gui.Style{
			classes = {"hudIconButtonIcon", "parent:selected"},
			saturation = 1.5,
			brightness = 1.5,
		},
	},

    Tabs = {
        gui.Style{
            selectors = { "tab" },

            bgimage = true,
            borderWidth = 1,
            borderColor = "#cccccc",
            width = 100,
            height = 40,
            fontSize = 18,
            bgcolor = backgroundColor,
            color = "#666666",
            hpad = 6,
        },
        gui.Style{
            selectors = { "tab", "selected" },
            bold = true,
            color = "white",
            borderColor = "white",
            borderWidth = 2,
        },
        gui.Style{
            selectors = { "tab", "hover" },
            brightness = 1.2,
        }
    },

	ItemTooltip = {
		gui.Style{
			selectors = {"label"},
			color = "white",
			fontSize = 16,
			width = "auto",
			height = "auto",
			halign = "left",
		},

		gui.Style{
			selectors = {"label", "title"},
			bold = true,
			width = "100%",
			fontSize = 24,
		},
		gui.Style{
			selectors = {"icon"},
			halign = "right",
			valign = "top",
			width = 32,
			height = 32,
			bgcolor = "white",
		},

		gui.Style{
			selectors = {"hasTooltip"},
			color = "#aaaaff",
		},
		gui.Style{
			selectors = {"hasTooltip", "hover"},
			color = "#ffaaff",
		},
	},

	Panel = {
		gui.Style{
			classes = {"framedPanel"},
			bgimage = "panels/square.png",
			bgcolor = 'white',
			cornerRadius = 4,
			gradient = dialogGradient,
			borderWidth = 2.2,
			borderColor = textColor,
		},
        --gui.Style{
        --    classes = {"framedPanel", "uiblur"},
        --    borderWidth = 0,
        --    opacity = 0.98,
        --},
        gui.Style{
            classes = {"framedPanel", "toplevel"},
            borderWidth = 0,
            opacity = 0.98,
        },
        gui.Style{
            classes = {"framedPanel", "create", "~hidden", "~collapsed"},
            soundEvent = "UI.WindowOpen",
        },
	},

	Table = {
		gui.Style{
			selectors = {"label"},
			pad = 6,
			fontSize = 16,
			width = "auto",
			height = "auto",
			color = "white",
		},
		gui.Style{
			selectors = {"row"},
			width = "auto",
			height = "auto",
			bgimage = "panels/square.png",
		},
		gui.Style{
			selectors = {"row", "oddRow"},
			bgcolor = "#222222ff",
		},
		gui.Style{
			selectors = {"row", "evenRow"},
			bgcolor = "#444444ff",
		},
		gui.Style{
			selectors = {"row", "highlight"},
			bgcolor = "#999944ff",
		},
	},

	ContextMenu = {
		gui.Style({
			selectors = {'context-menu-label'},
			fontSize = 20,
			color = '#ffffff',
		}),
		gui.Style({
			selectors = {'context-menu-label', 'disabled'},
			fontSize = 20,
			color = '#777777',
		}),
		gui.Style({
			selectors = {'context-menu-item'},
			fontSize = 20,
			color = '#ffffff',
			height = "auto",
			width = "100%",
			bgcolor = '#994444',
			color = '#ffffff',
			borderColor = '#000000',
			borderWidth = 1,
		}),
		gui.Style({
			selectors = {'context-menu-item','hover'},
			borderColor = '#ffffff',
			borderWidth = 1,
			transitionTime = 0.2,
		}),
		gui.Style({
			selectors = {'context-menu-item','press'},
			brightness = 1.2,
			transitionTime = 0.2,
		}),
	},

	InventorySlot = {
		gui.Style{
			classes = 'inventory-slot-highlight',
			bgimage = 'panels/InventorySlot_Focus.png',
			bgcolor = 'white',
			width = 90,
			height = 90,
			halign = 'center',
			valign = 'center',
			opacity = 0,
		},
		gui.Style{
			classes = {'inventory-slot-highlight', 'hover'},
			opacity = 1,
		},
		gui.Style{
			classes = {'inventory-slot-highlight', 'press'},
			bgcolor = 'red',
		},

		gui.Style{
			classes = 'inventory-slot-background',
			bgimage = 'panels/InventorySlot_Background.png',
			bgcolor = 'white',
			width = 72,
			height = 72,
			margin = 0,
			pad = 0,
		},

		gui.Style{
			classes = 'inventory-slot-icon',
			bgcolor = 'white',
			halign = 'center',
			valign = 'center',
			width = "100%",
			height = "100%",
			hmargin = 0,
		},
	},

	AdvantageBar = {

		gui.Style{
			selectors = {'advantage-bar'},
			halign = 'center',
			height = 30,
			width = 340,
			flow = 'horizontal',
		},

		gui.Style{
			selectors = {'advantage-element-lock-icon'},
			hidden = 1,
		},

		gui.Style{
			selectors = {'advantage-element-lock-icon', 'parent:locked'},
			hidden = 0,
			margin = 2,
			bgcolor = 'white',
			width = 16,
			height = 16,
			halign = 'right',
			valign = 'center',
		},

		gui.Style{
			selectors = {'advantage-element'},
			bgimage = "panels/square.png",
			bgcolor = '#ffffff00',
			color = 'white',
			width = 140,
			height = 22,
			fontSize = 14,
			textAlignment = 'center',
			halign = 'center',
		},

		gui.Style{
			selectors = {'advantage-element', 'hover', '~selected'},
			bgcolor = '#ffffff66',
		},

		gui.Style{
			selectors = {'advantage-element', 'selected', '~press'},
			borderWidth = 2,
			borderColor = "white",
			bgcolor = "white",
			gradient = gui.Gradient{
				point_a = {x = 0, y = 0},
				point_b = {x = 1, y = 1},
				stops = {
					{
						position = 0,
						color = '#111111',
					},
					{
						position = 1,
						color = '#222222',
					},
				}

			},
		},

		gui.Style{
			selectors = {'advantage-element', 'locked'},
			bgcolor = '#ff7777ff',
		},

		gui.Style{
			selectors = {'advantage-element', 'press'},
			bgcolor = "white",
			color = "black",
		},

		gui.Style{
			selectors = {'advantage-rules-panel'},
			bgcolor = '#000000aa',
			width = 'auto',
			height = 'auto',
			pad = 8,
			flow = 'vertical',
		},
		gui.Style{
			selectors = {'advantage-rules-label'},
			color = 'white',
			width = 'auto',
			height = 'auto',
			fontSize = 14,
		},
		gui.Style{
			selectors = {'advantage'},
			color = '#aaffaa',
		},
		gui.Style{
			selectors = {'disadvantage'},
			color = '#ffaaaa',
		},

	},

	Form = {
		gui.Style{
			classes = "formPanel",
			flow = "horizontal",
			width = "100%",
			height = "auto",
			valign = "top",
			vmargin = 4,
		},
		gui.Style{
			classes = "formLabel",
			fontSize = 16,
			color = "white",
			width = "auto",
			height = "auto",
			minWidth = 140,
			halign = "right",
			valign = "center",
			hmargin = 8,
		},
		gui.Style{
			classes = "formInput",
			fontSize = 16,
			width = 180,
			height = 26,
			color = "white",
			halign = "right",
			valign = "center",
			textAlignment = "left",
		},
		gui.Style{
			classes = {"formInput", "multiline"},
			textAlignment = "topleft",
		},
		gui.Style{
			classes = "formDropdown",
			halign = 'right',
			vmargin = 4,
			width = 240,
			height = 30,
		},
		gui.Style{
			classes = "formValue",
			halign = 'right',
			vmargin = 4,
			width = 180,
			height = 30,
			fontSize = 14,
		},
	},

	Triangle = {
		gui.Style{
			selectors = {"triangle"},
			bgimage = "panels/triangle.png",
			bgcolor = textColor,
			width = 12,
			height = 12,
			hmargin = 4,
			valign = "center",
			halign = "center",
		},
		gui.Style{
			selectors = {"triangle", "hover"},
			brightness = 1.5,
		},
	},

	FolderLibrary = {
		{
			width = '100%',
			height = 500,
			valign = 'center',
			halign = 'right',
			flow = 'vertical',
		},

		gui.Style{
			selectors = {"folderContainer"},
			flow = "vertical",
			width = "100%",
			height = "auto",
			valign = "top",
		},

		gui.Style{
			selectors = {"folderHeader"},
			width = "100%",
			flow = "horizontal",
			height = 24,
			bgimage = "panels/square.png",
			bgcolor = textColor,
		},

		gui.Style{
			selectors = {"folderHeader", "hover"},
			brightness = 1.5,
		},

		gui.Style{
			selectors = {"triangle"},
			bgimage = "panels/triangle.png",
			bgcolor = "black",
			width = 16,
			height = 12,
			hmargin = 4,
			valign = "center",
			halign = "left",
		},

		gui.Style{
			selectors = {"triangle", "parent:expanded"},
			scale = {x = 1, y = -1},
			transitionTime = 0.1,
		},

		gui.Style{
			selectors = {"folderLabel"},
			color = "black",
			fontSize = 18,
			width = "80%",
			height = "100%",
			halign = "left",
			textAlignment = "left",

		},

		gui.Style{
			selectors = {"folderHeader", "parent:drag-target"},
			brightness = 1.5,
		},
		gui.Style{
			selectors = {"folderHeader", "parent:drag-target-hover"},
			brightness = 3,
		},
	},

	ImplementationIcon = {
		{
			selectors = {"spellImplementationIcon"},
			width = 16,
			height = 16,
			hmargin = 4,
		},
		{
			selectors = {"spellImplementationIcon", "wontimplement"},
			bgimage = "icons/icon_common/icon_common_29.png",
			bgcolor = implementationStatusColors[0],
		},
		{
			selectors = {"spellImplementationIcon", "unimplemented"},
			bgimage = "icons/icon_common/icon_common_29.png",
			bgcolor = implementationStatusColors[1],
		},
		{
			selectors = {"spellImplementationIcon", "bronze"},
			bgimage = "icons/icon_common/icon_common_29.png",
			bgcolor = implementationStatusColors[2],
		},
		{
			selectors = {"spellImplementationIcon", "silver"},
			bgimage = "icons/icon_common/icon_common_29.png",
			bgcolor = implementationStatusColors[3],
		},
		{
			selectors = {"spellImplementationIcon", "gold"},
			bgimage = "icons/icon_common/icon_common_29.png",
			bgcolor = implementationStatusColors[4],
		},
	},

	triangleStyles = {
		gui.Style{
			classes = {'triangle'},
			rotate = 90,
			transitionTime = 0.2,
			bgimage = "panels/triangle.png",
			bgcolor = "white",
			halign = "left",
			hmargin = 4,
			width = "100% height",
			valign = "center",
		},
		gui.Style{
			classes = {'triangle', 'expanded'},
			rotate = 0,
			transitionTime = 0.2,
		},
	},

	horizontalGradient = gui.Gradient{
		point_a = {x = 0, y = 0},
		point_b = {x = 1, y = 0},
		stops = {
			{
				position = 0,
				color = "#ffffff00",
			},
			{
				position = 0.2,
				color = "#ffffffff",
			},
			{
				position = 0.8,
				color = "#ffffffff",
			},
			{
				position = 1,
				color = "#ffffff00",
			},

		},
	},

	verticalGradient = gui.Gradient{
		point_a = {x = 0, y = 0},
		point_b = {x = 0, y = 1},
		stops = {
			{
				position = 0,
				color = "#ffffff00",
			},
			{
				position = 0.2,
				color = "#ffffffff",
			},
			{
				position = 0.8,
				color = "#ffffffff",
			},
			{
				position = 1,
				color = "#ffffff00",
			},
		},
	},
}


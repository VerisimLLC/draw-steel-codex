local mod = dmhub.GetModLoading()

local function track(eventType, fields)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    fields.type = eventType
    fields.userid = dmhub.userid
    fields.gameid = dmhub.gameid
    fields.version = dmhub.version
    analytics.Event(fields)
end

local CreateWhiteboardPanel

DockablePanel.Register{
    name = "Whiteboard",
	icon = "icons/standard/Icon_App_Whiteboard.png",
    vscroll = true,
    dmonly = false,

    content = function()
        track("panel_open", {
            panel = "Whiteboard",
            dailyLimit = 30,
        })
        return CreateWhiteboardPanel()
    end,
}

setting{
	id = "whiteboardtool",
	description = "Tool",
	help = "Controls which tool to use to draw terrain",
	storage = "transient",
	editor = "iconbuttons",

	default = 'free',

	enum = {
--	{
--		value = 'rectangle',
--		icon = 'game-icons/square.png',
--		help = "Rectangle tool",
--	},
--	{
--		value = 'oval',
--		icon = 'game-icons/circle.png',
--		help = "Circle & Oval tool",
--	},
--	{
--		value = 'shape',
--		icon = 'game-icons/polygon-segments.png',
--		help = "Shape tool",
--	},
--	{
--		value = 'curve',
--		icon = 'game-icons/curve.png',
--		help = "Curves tool",
--	},
		{
			value = 'free',
			icon = 'panels/hud/icon_line_tool_82.png',
			help = "Free draw tool",
		},
	},
}

setting{
	id = "whiteboardcolor",
	description = "Draw Color",
	help = "Color you will draw on the whiteboard in",
	storage = "transient",

	editor = "color",
	default = dmhub.GetSettingValue("playercolor"),
}

setting{
    id = "whiteboardwidth",
    description = "Stroke Width",
    help = "Width of strokes of your pen",
    storage = "transient",

    editor = "slider",
    default = 10,
    min = 1,
    max = 20,
}

setting{
    id = "whiteboardplayeraccess",
    description = "Players Can Draw",
    help = "Allow players to draw on the whiteboard",
    storage = "game",

    editor = "check",
    default = true,
}



CreateWhiteboardPanel = function()

    local resultPanel

    local toolPanel = CreateSettingsEditor("whiteboardtool")
    local colorPanel = CreateSettingsEditor("whiteboardcolor")
    local widthPanel = CreateSettingsEditor("whiteboardwidth")

    local GetActiveWhiteboardTool = function()
        if dmhub.isDM == false and not dmhub.GetSettingValue("whiteboardplayeraccess") then
            return nil
        end

        if gui.ChildHasFocus(resultPanel) then
            return {
                tool = dmhub.GetSettingValue("whiteboardtool"),
                color = dmhub.GetSettingValue("whiteboardcolor"),
                width = dmhub.GetSettingValue("whiteboardwidth")*0.001,
            } 
        end

        return nil
    end

    dmhub.GetActiveWhiteboardTool = GetActiveWhiteboardTool

    resultPanel = gui.Panel{

        flow = "vertical",
        width = "auto",
        height = "auto",

        gui.Label{
            styles = {
                {
                    selectors = {"~forbidden"},
                    collapsed = 1,
                }
            },
            width = "auto",
            height = "auto",
            halign = "center",
            vmargin = 20,
            fontSize = 18,
            text = "The GM has disabled the whiteboard",
        },

        toolPanel,
        colorPanel,
        widthPanel,

        gui.Button{
            text = "Clear",
            vmargin = 8,
            minWidth = 120,
            click = function(element)
                whiteboard:ClearMine()
            end,
        },

        gui.Button{
            classes = {"hideForPlayers"},
            text = "Clear Players",
            vmargin = 8,
            minWidth = 120,
            click = function(element)
                whiteboard:ClearOthers()
            end,
        },


        gui.Panel{
            classes = {"hideForPlayers"},
            width = "auto",
            height = "auto",
            CreateSettingsEditor("whiteboardplayeraccess"),
        },

        destroy = function()
            if dmhub.GetActiveWhiteboardTool == GetActiveWhiteboardTool then
                dmhub.GetActiveWhiteboardTool = nil
            end
        end,

        multimonitor = {"whiteboardtool", "whiteboardplayeraccess"},
        monitor = function(element)
            printf("MONITOR:: PANEL %s %s", json(dmhub.isDM), json(dmhub.GetSettingValue("whiteboardplayeraccess")))
            element:FireEvent("showpanel")
        end,

        clickpanel = function(element)
            element:FireEvent("showpanel")
        end,
        showpanel = function(element)
            if dmhub.isDM == false and not dmhub.GetSettingValue("whiteboardplayeraccess") then
                if gui.ChildHasFocus(element) then
                    gui.SetFocus(nil)
                end

                element:SetClassTree("forbidden", true)
            else
                element:SetClassTree("forbidden", false)
            end

            if not gui.ChildHasFocus(element) then
                gui.SetFocus(element)
            end
        end,

        hidepanel = function(element)
            if gui.ChildHasFocus(element) then
                gui.SetFocus(nil)
            end
        end,

 
        childfocus = function(element)
            element:FindParentWithClass("dockablePanel"):SetClass("highlightPanel", true)
        end,

        childdefocus = function(element)
            element:FindParentWithClass("dockablePanel"):SetClass("highlightPanel", false)
        end,
    }

    return resultPanel

end
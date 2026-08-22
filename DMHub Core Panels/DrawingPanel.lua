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
	icon = "phosphor/note-pencil.png",
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

    --Players lose the whiteboard when the DM turns "whiteboardplayeraccess"
    --off: the panel greys out and must not keep GUI focus, or it would go on
    --swallowing map clicks. That is the ONLY thing the settings monitor needs
    --to re-evaluate, so it lives apart from showpanel's arming. Returns true
    --if the panel is forbidden to this user.
    local RefreshWhiteboardAccess = function(element)
        local forbidden = dmhub.isDM == false and not dmhub.GetSettingValue("whiteboardplayeraccess")

        if forbidden and gui.ChildHasFocus(element) then
            gui.SetFocus(nil)
        end

        element:SetClassTree("forbidden", forbidden)
        return forbidden
    end

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

        --This used to fire "showpanel", which force-GRABS GUI focus. That made
        --the whiteboard a focus thief for the whole app, and it fired far more
        --often than its own two settings changed: showpanel's `pressfirst`
        --writes whiteboardtool from INSIDE the monitor dispatch loop, and
        --SheetManager cleared `potentialMonitorUpdates` after that loop, so the
        --bump was swallowed and this panel's `_multimonitorUpdate` was left
        --permanently one behind -- meaning it re-fired on the next settings
        --write ANYWHERE in the app, forever. (The engine half of that is fixed
        --in SheetManager.cs; this half stands on its own.)
        --
        --The victim was the Elevation Editor, whose tool and topographic
        --overlay were gated purely on focus: every press on one of its controls
        --wrote a setting, which fired this monitor, which took the focus back
        --and killed the overlay a frame later. Report W9BJHDAQ -- 138 firings,
        --zero height edits, every map click falling through to marquee select.
        --
        --A settings change is not a user asking for the whiteboard, so it no
        --longer arms; it only re-checks player access. Opening the panel,
        --switching to its tab and clicking it still arm, as before.
        monitor = function(element)
            printf("MONITOR:: PANEL %s %s", json(dmhub.isDM), json(dmhub.GetSettingValue("whiteboardplayeraccess")))
            RefreshWhiteboardAccess(element)
        end,

        clickpanel = function(element)
            element:FireEvent("showpanel")
        end,

        --showpanel only fires on a dock TAB switch, so opening the whiteboard
        --fresh (or hosting it in a rail window) never ran it and the panel sat
        --there with no focus -- meaning GetActiveWhiteboardTool returned nil and
        --nothing drew until the user clicked. Arm it on create as well.
        create = function(element)
            element:FireEvent("showpanel")
        end,

        showpanel = function(element)
            if RefreshWhiteboardAccess(element) then
                return
            end

            if not gui.ChildHasFocus(element) then
                --press the first (only) tool button rather than just focusing the
                --panel: that selects the free draw tool and takes focus in one go.
                toolPanel:FireEventTree("pressfirst")
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

 
        --The dockablePanel ancestor can be nil: panel content can be hosted
        --outside the dock (the document system's PanelDocument bridge), and
        --focus events can fire while detached. Guard like Objects.lua does.
        childfocus = function(element)
            local dockPanel = element:FindParentWithClass("dockablePanel")
            if dockPanel ~= nil then
                dockPanel:SetClass("highlightPanel", true)
            end
        end,

        childdefocus = function(element)
            local dockPanel = element:FindParentWithClass("dockablePanel")
            if dockPanel ~= nil then
                dockPanel:SetClass("highlightPanel", false)
            end
        end,
    }

    return resultPanel

end
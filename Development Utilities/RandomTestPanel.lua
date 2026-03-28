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

DockablePanel.Register{
	name = "Random Test Panel",
	icon = mod.images.chatIcon,
	minHeight = 200,
	vscroll = true,
    devonly = true,
	folder = "Development Tools",
	content = function()
		track("panel_open", {
			panel = "Random Test Panel",
			dailyLimit = 30,
		})
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",

            gui.Button{
                text = "Change Elevation",
                width = 200,
                height = 50,
                halign = "center",
                valign = "center",
                click = function()
                    game.currentFloor:ChangeElevation{
                        type = "ellipse",
                        center = {x = 0, y = 0},
                        radius = 4,
                        opacity = 1,
                        height = 2,
                        add = true,
                    }

                    for _,tok in ipairs(dmhub.allTokens) do
                        tok:RecalculateElevation()
                    end
                end,
            },

            gui.Button{
                text = "Draw Terrain",
                width = 200,
                height = 50,
                halign = "center",
                valign = "center",
                click = function()
                    game.currentFloor:ExecutePolygonOperation{
                        points = {{-3,-3,3,-3,3,3,-3,3}},
                        closed = true,
                        tileid = "-MCZRJ4qqI-Rz9rKbAdr",
                        terrain = true,
                    }
                end,
            },


            gui.Button{
                text = "Recalculate",
                width = 200,
                height = 50,
                halign = "center",
                valign = "center",
                click = function()
                    for _,tok in ipairs(dmhub.allTokens) do
                        --tok:RecalculateElevation()
                        tok:TryFall()
                    end

                end,
            },

        }
	end,
}

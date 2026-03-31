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
			hpad = 4,

			gui.Label{
				text = "borderBox Tests",
				fontSize = 18,
				bold = true,
				color = "#ffcc44",
				width = "auto",
				height = "auto",
				halign = "center",
				vmargin = 8,
			},

            gui.Panel{
                halign = "center",
                height = 50,
                width = 180,
                bgimage = true,
                bgcolor = "green",

                gui.Panel{
                    height = 25,
                    width = "100%",
                    hpad = 10,
                    bgimage = true,
                    bgcolor = "red",
                    valign = "center",
                    halign = "center",
                }
            },

            gui.Panel{
                halign = "center",
                height = 50,
                width = 180,
                bgimage = true,
                bgcolor = "green",

                gui.Panel{
                    height = 25,
                    width = "100%",
                    hpad = 10,
                    bgimage = true,
                    bgcolor = "red",
                    valign = "center",
                    halign = "center",
                    borderBox = true,
                }
            },


        }
	end,
}

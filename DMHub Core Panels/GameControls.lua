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

local CreateGameControls

DockablePanel.Register{
	name = "Game Controls",

	icon = "icons/standard/Icon_App_GameControls.png",
	vscroll = false,
    dmonly = true,
	minHeight = 40,
	content = function()
		track("panel_open", {
			panel = "Game Controls",
			dailyLimit = 30,
		})
		return CreateGameControls{}
	end,
}

CreateGameControls = function()
	local doc = FullscreenDisplay.GetDocumentSnapshot()
    local m_speed = 1
    local resultPanel
    resultPanel = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",

        gui.Check{
            text = "Frozen",
            value = dmhub.frozen,
            monitorGame = "/frozen",
            refreshGame = function(element)
                element.SetValue(element, dmhub.frozen, false)
            end,

            change = function(element)
                dmhub.frozen = element.value
            end,
        },

        gui.Button{
            text = "Sync Camera",
            width = 140,
            height = 24,
            fontSize = 18,
            press = function()
                dmhub.SyncCamera{
                    speed = m_speed
                }
            end,
        },

        gui.Panel{
            flow = "horizontal",
            height = "auto",
            width = "auto",
            gui.Label{
                text = "Speed:",
                fontSize = 16,
                width = "auto",
                height = "auto",
            },
            gui.Input{
                width = 120,
                height = 20,
                fontSize = 16,
                text = tostring(m_speed),
                change = function(element)
                    local n = tonumber(element.text)
                    if n == nil or n <= 0 then
                        element.text = tostring(m_speed)
                    else
                        m_speed = n
                    end
                end,
            }
        },

		gui.IconEditor{
			library = "coverart",
			bgcolor = "white",
			width = "auto",
			height = "auto",
			hideIcon = true,
			allowNone = true,
			aspect = 1080/1920,
			noneImage = game.coverart,
			hideButton = true,
			maxWidth = 1920*0.1,
			maxHeight = 1080*0.1,
			autosizeimage = true,
			halign = "left",
			value = doc.data.coverart,
			change = function(element)
	            local doc = FullscreenDisplay.GetDocumentSnapshot()
                doc:BeginChange()
                doc.data.coverart = element.value
                doc:CompleteChange("Show Fullscreen Display")
			end,

            gui.Panel{
                classes = {"coverArtRibbon"},
                interactable = false,
                width = 128,
                height = 20,
                halign = "center",
                valign = "center",
                bgcolor = "black",
                opacity = 0.8,
                bgimage = "panels/square.png",
                styles = {
                    {
                        selectors = {"coverArtRibbon"},
                        hidden = 1,
                    },
                    {
                        selectors = {"coverArtRibbon", "parent:hover"},
                        hidden = 0,
                    }
                },

                gui.Label{
                    interactable = false,
                    fontSize = 12,
                    width = "auto",
                    height = "auto",
                    color = "white",
                    bold = true,
                    halign = "center",
                    valign = "center",
                    text = "Choose Fullscreen Art",
                }
            }
		},
        gui.EnumeratedSliderControl{
            options = {
                {id = false, text = "Hide"},
                {id = true, text = "Show to Players"},
                {id = "all", text = "Show to All"},
            },
            value = doc.data.show,
            change = function(element)
                local doc = FullscreenDisplay.GetDocumentSnapshot()
                doc:BeginChange()
                doc.data.show = element.value
                doc:CompleteChange("Show Fullscreen Display")
            end,
            monitorGame = doc.path,
            refreshGame = function(element)
                local doc = FullscreenDisplay.GetDocumentSnapshot()
                element.SetValue(element, doc.data.show, false)
            end,
        },
        gui.Check{
            text = "Show Below UI",
            value = doc.data.belowui,
            change = function(element)
                local doc = FullscreenDisplay.GetDocumentSnapshot()
                doc:BeginChange()
                doc.data.belowui = element.value
                doc:CompleteChange("Show Below UI")
            end,
            monitorGame = doc.path,
            refreshGame = function(element)
                local doc = FullscreenDisplay.GetDocumentSnapshot()
                element.value = doc.data.belowui
            end,
        },
    }

    return resultPanel
end
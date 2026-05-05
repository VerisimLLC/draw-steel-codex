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
    name = "Development Info",

    devonly = true,
	folder = "Development Tools",

	content = function()
        track("panel_open", {
            panel = "Development Info",
            dailyLimit = 30,
        })
        local m_coroutinePanels = {}
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                thinkTime = 0.1,
                think = function(element)
                    local children = {}
                    local newCoroutinePanels = {}
                    for _,entry in ipairs(builtin_coroutines) do
                        local panel = m_coroutinePanels[entry.id] or gui.Label{
                            width = "100%",
                            height = "auto",
                            halign = "left",
                            valign = "top",
                            fontSize = 12,
                            refresh = function(element)
                                element.text = string.format("coroutine %s -- %s", entry.id, coroutine.status(entry.coroutine))
                            end,
                            hover = function(element)
                                local trace = debug.traceback(entry.coroutine)
                                print("TRACEBACK", trace)
                                gui.Tooltip(trace)(element)
                            end,
                        }

                        panel:FireEvent("refresh")

                        newCoroutinePanels[entry.id] = panel
                        children[#children+1] = panel
                    end

                    m_coroutinePanels = newCoroutinePanels
                    element.children = children
                end,
            },
            gui.Label{
                fontSize = 12,
                width = "auto",
                height = "auto",
                create = function(element)
                    element:FireEvent("think")
                end,
                thinkTime = 0.01,
                think = function(element)
                    --local mem = collectgarbage("count")
                    local mem = 0
                    element.text = string.format("Time: %d\nLua Memory: %dMB\n%s", math.floor(dmhub.serverTime), math.floor(mem/1024), dmhub.debugPropertyOutput)
                end,
            },

            gui.Button{
                halign = "right",
                valign = "bottom",
                fontSize = 16,
                width = 80,
                height = 24,
                text = "Run GC",
                click = function(element)
                    collectgarbage("collect")
                    --collectgarbage("stop")
                end,
            },

            gui.Button{
                halign = "right",
                valign = "bottom",
                fontSize = 16,
                width = 80,
                height = 24,
                text = "Report",
                click = function(element)
                    dmhub:DebugUserDataReport()
                end,
            },
        }
	end,
}

DockablePanel.Register{
    name = "Brightness Test",

	icon = mod.images.effectsIcon,
    devonly = true,
	minHeight = 200,
	folder = "Development Tools",

	content = function()
        track("panel_open", {
            panel = "Brightness Test",
            dailyLimit = 30,
        })
        return gui.Panel{
            width = "100%",
            height = "auto",
            wrap = true,
            flow = "horizontal",
            create = function(element)
                local children = {}

                for i = 1,10 do
                children[#children+1] = gui.Panel{
                        width = 32,
                        height = 32,
                        hmargin = 16,
                        vmargin = 16,
                        bgimage = "panels/square.png",
                        bgcolor =  "srgb:#C09571", -- "white",
                        brightness = i,
                    }
                end


                element.children = children
            end,

        }
	end,
}

DockablePanel.Register{
    name = "Network Debugger",

	icon = mod.images.effectsIcon,
    devonly = true,
    vscroll = false,
	folder = "Development Tools",
    content = function()
        track("panel_open", {
            panel = "Network Debugger",
            dailyLimit = 30,
        })
        local filter = {}
        local resultPanel
        local scrollPanel
        local dataError = function(message)
            print("NETWORK ERROR:", message)
            scrollPanel:FireEvent("error", message)
        end
        local dataStreamed = function(method, path, data)
            scrollPanel:FireEvent("record", "stream", method, path, data)
        end
        local dataTransmitted = function(method, path, data)
            scrollPanel:FireEvent("record", "transmit", method, path, data)
        end
        scrollPanel = gui.Panel{
            width = "100%",
            height = "100%-32",
            flow = "vertical",
            vscroll = true,

            styles = {
                {
                    selectors = {"recordPanel"},
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    bgimage = "panels/square.png",
                    pad = 4,
                    bgcolor = "black",
                    borderWidth = 1,
                    cornerRadius = 6,
                },
                {
                    selectors = {"recordPanel", "hover"},
                    brightness = 1.5,
                },
                {
                    selectors = {"recordPanel", "error"},
                    bgcolor = "#ffbbbb",
                },
                {
                    selectors = {"recordPanel", "stream"},
                    bgcolor = "#bbffbb",
                },
                {
                    selectors = {"recordPanel", "transmit"},
                    bgcolor = "#bbbbff",
                },
                {
                    selectors = {"recordLabel"},
                    color = "black",
                    fontSize = 14,
                    maxWidth = 300,
                    width = "auto",
                    height = "auto",
                },

            },

            clear = function(element)
                element.children = {}
            end,

            create = function(element)
                dmhub.DataStreamed = dataStreamed
                dmhub.DataTransmitted = dataTransmitted
                dmhub.DataError = dataError
            end,

            destroy = function(element)
                if dmhub.DataStreamed == dataStreamed then
                    dmhub.DataStreamed = nil
                end
                if dmhub.DataTransmitted == dataTransmitted then
                    dmhub.DataTransmitted = nil
                end
                if dmhub.DataError == dataError then
                    dmhub.DataError = nil
                end
            end,

            error = function(element, message)
                local panel = gui.Panel{
                    classes = {"recordPanel", "error"},
                    press = function(element)
                        dmhub.CopyToClipboard(message)
                        gui.Tooltip("Error message copied to clipboard")(element)
                    end,
                    gui.Label{
                        classes = {"recordLabel"},
                        bold = true,
                        text = message,
                    },

                    filter = function(element)
                        if #filter == 0 then
                            element:SetClass("collapsed", false)
                        else
                            for _,f in ipairs(filter) do
                                local match = false
                                if string.find(message, f) then
                                    match = true
                                end

                                if match == false then
                                    element:SetClass("collapsed", true)
                                    return
                                end
                            end

                            element:SetClass("collapsed", false)
                        end
                    end,
                }

                element:AddChild(panel)
            end,

            record = function(element, recordType, method, path, data)
                local panel = gui.Panel{
                    press = function(element)
                        element:FireEventTree("expand")
                    end,

                    classes = { "recordPanel", recordType },

                    create = function(element)
                        element:FireEvent("filter")
                    end,

                    filter = function(element)
                        if #filter == 0 then
                            element:SetClass("collapsed", false)
                        else
                            for _,str in ipairs(filter) do
                                local negation = false
                                local f = str
                                if string.starts_with(f, "~") then
                                    negation = true
                                    f = string.sub(f, 2)
                                end

                                local match = false
                                if (not negation) and (string.find(recordType, f) or string.find(method, f) or string.find(path, f) or string.find(data, f)) then
                                    match = true
                                end

                                if negation and (not string.find(recordType, f)) and (not string.find(method, f)) and (not string.find(path, f)) and (not string.find(data, f)) then
                                    match = true
                                end

                                if match == false then
                                    element:SetClass("collapsed", true)
                                    return
                                end
                            end

                            element:SetClass("collapsed", false)
                        end
                    end,

                    gui.Label{
                        classes = {"recordLabel"},
                        bold = true,
                        text = path,
                    },
                    gui.Label{
                        classes = {"recordLabel"},
                        text = string.format("%s - %s - %d bytes - %.2fs", recordType, method, string.len(data), dmhub.Time()),
                    },
                    gui.Label{
                        classes = {"recordLabel", "collapsed", "uninit"},
                        width = "100%",
                        text = "",
                        expand = function(element)
                            element:SetClass("collapsed", not element:HasClass("collapsed"))
                            if element:HasClass("uninit") then
                                element:SetClass("uninit", false)
                                element.text = data
                            end
                        end,
                    }
                }

                element:AddChild(panel)

            end,

        }

        resultPanel = gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",
            gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = "auto",
                gui.Input{
                    width = "70%",
                    halign = "left",
                    height = 16,
                    fontSize = 12,
                    placeholderText = "Filter...",
                    editlag = 0.3,
                    edit = function(element)
                        filter = string.split(element.text)
                        scrollPanel:FireEventTree("filter")
                    end,
                },
                gui.Button{
                    width = "15%",
                    height = 16,
                    fontSize = 10,
                    text = "Clear",
                    click = function(element)
                        resultPanel:FireEventTree("clear")
                    end,
                }
            },
            scrollPanel,
        }

        return resultPanel
    end,

}

DockablePanel.Register{
    name = "Sheet Perf",

	icon = mod.images.effectsIcon,
    devonly = true,
	minHeight = 200,
	folder = "Development Tools",
	content = function()
        track("panel_open", {
            panel = "Sheet Perf",
            dailyLimit = 30,
        })
        local resultPanel
        resultPanel = gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",
            gui.Panel{
                width = "100%",
                height = "100%-60",
                vscroll = true,
                flow = "vertical",
                test = function(element)
                    local timer = dmhub.Stopwatch()
                    local timer2 = dmhub.Stopwatch()
                    local items = {}
                    for i = 1,1000 do
                        items[i] = gui.Panel{
                            width = 100,
                            height = 10,
                            vmargin = 4,
                            bgimage = "panels/square.png",
                            bgcolor = "red",
                        }
                    end

                    timer2:Stop()

                    element.children = items

                    timer:Stop()

                    resultPanel:FireEventTree("results", string.format("%d/%dms", timer2.milliseconds, timer.milliseconds))


                end,
            },

            gui.Button{
                width = 40,
                height = 20,
                fontSize = 14,
                text = "Click",
                click = function(element)
                    resultPanel:FireEventTree("test")
                end,
            },

            gui.Label{
                width = "100%",
                height = "auto",
                fontSize = 14,
                results = function(element, text)
                    element.text = text
                end,
            }
        }

        return resultPanel
    end,
}

DockablePanel.Register{
    name = "Texture Load",

	icon = mod.images.effectsIcon,
    devonly = true,
	minHeight = 200,
	folder = "Development Tools",
	content = function()
        track("panel_open", {
            panel = "Texture Load",
            dailyLimit = 30,
        })
        local resultPanel = gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",
            vscroll = true,

            styles = {
                {
                    classes = {"label"},
                    fontSize = 12,
                    width = "auto",
                    height = "auto",
                    maxWidth = 100,
                }

            },

            texture = function(element, info)
                dmhub.Debug(string.format("TEXTURE:: %s", json(info)))
                local panel = gui.Panel{
                    width = "95%",
                    height = "auto",
                    halign = "left",
                    flow = "horizontal",
                    vmargin = 4,

                    gui.Panel{
                        width = 196,
                        height = 196,
                        gui.Panel{
                            bgimage = info.imageid,
                            bgcolor = "white",
                            autosizeimage = true,
                            width = "auto",
                            height = "auto",
                            maxWidth = 196,
                            maxHeight = 196,
                        }
                    },

                    gui.Panel{
                        width = 128,
                        height = "auto",
                        hmargin = 4,
                        flow = "vertical",
                        gui.Label{
                            text = cond(info.desc ~= nil, info.desc, info.imageid),
                        },
                        gui.Label{
                            text = string.format("%dx%d", info.width, info.height)
                        },
                        gui.Label{
                            text = string.format("%dms", info.time)
                        },
                        gui.Label{
                            text = string.format("%s", info.format)
                        },
                    }

                }

                element:AddChild(panel)
            end,

        }

        dmhub.GetTextureLoadEvent():Listen(resultPanel)

        return resultPanel
	end,
}

-- Pool stress test: spawn N labels, time the rebuild on demand.
-- Used to measure SheetPanel pooling savings -- rebuild a fixed N labels with the
-- pool enabled vs disabled and compare ms.
DockablePanel.Register{
    name = "Pool Stress Test",
    devonly = true,
    folder = "Development Tools",
    minHeight = 320,

    content = function()
        local m_count = 100
        local m_lastDurationMs = 0
        local m_lastBuildN = 0
        local m_runs = {}  -- recent run durations for averaging

        -- Forward declarations so closures can refer to them.
        local m_labelsContainer
        local m_durationLabel

        local function rebuild()
            local sw = dmhub.Stopwatch()
            local labels = {}
            for i = 1, m_count do
                labels[#labels+1] = gui.Label{
                    text = string.format("Label %d / %d", i, m_count),
                    fontSize = 12,
                    width = "100%",
                    height = 14,
                }
            end
            m_labelsContainer.children = labels
            m_lastDurationMs = sw.milliseconds
            m_lastBuildN = m_count
            m_runs[#m_runs+1] = m_lastDurationMs
            if #m_runs > 10 then
                table.remove(m_runs, 1)
            end

            local total = 0
            for _,v in ipairs(m_runs) do total = total + v end
            local avg = total / #m_runs

            m_durationLabel.text = string.format(
                "Last: %d labels in %d ms\nAvg of last %d runs: %.1f ms\n(check console for any 'Perf: Long frame' lines)",
                m_lastBuildN, m_lastDurationMs, #m_runs, avg)
        end

        m_labelsContainer = gui.Panel{
            width = "100%",
            height = "100%-130",
            vscroll = true,
            flow = "vertical",
            bgimage = "panels/square.png",
            bgcolor = "black",
            pad = 4,
        }

        m_durationLabel = gui.Label{
            width = "100%",
            height = 60,
            fontSize = 13,
            text = "Last: -- (press Rebuild)",
        }

        return gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",

            -- Count input row
            gui.Panel{
                width = "100%",
                height = 28,
                flow = "horizontal",
                halign = "left",
                gui.Label{
                    text = "N labels:",
                    width = 70, height = 24, fontSize = 14,
                    valign = "center",
                },
                gui.Input{
                    text = tostring(m_count),
                    width = 80, height = 24, fontSize = 14,
                    change = function(element)
                        local n = tonumber(element.text)
                        if n and n >= 0 and n <= 100000 then
                            m_count = math.floor(n)
                        end
                    end,
                },
            },

            -- Buttons row
            gui.Panel{
                width = "100%",
                height = 32,
                flow = "horizontal",
                halign = "left",
                gui.Button{
                    text = "Rebuild",
                    width = 100, height = 28, fontSize = 14,
                    click = function() rebuild() end,
                },
                gui.Button{
                    text = "Clear",
                    width = 80, height = 28, fontSize = 14,
                    click = function()
                        m_labelsContainer.children = {}
                    end,
                },
                gui.Button{
                    text = "Reset Avg",
                    width = 80, height = 28, fontSize = 14,
                    click = function()
                        m_runs = {}
                        m_durationLabel.text = "Last: -- (press Rebuild)"
                    end,
                },
            },

            m_durationLabel,
            m_labelsContainer,
        }
    end,
}

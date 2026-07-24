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

local function CoroutineStackTrim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Parse a coroutine's traceback into a list of frames. Frames that correspond
--- to a source location (a "[string "Mod : File"]:line:" entry) are also collected
--- into a "locatable" list and given a 1-based .number so they can be opened by
--- pressing the matching number key -- mirroring the F7 style inspector.
--- @return table frames, table locatable
local function ParseCoroutineStack(co)
    local trace = debug.traceback(co)
    local frames = {}
    local locatable = {}
    for line in string.gmatch(trace, "[^\r\n]+") do
        local modAndFile, lineNum, rest = string.match(line, '%[string "([^"]+)"%]:(%d+):?%s*(.*)$')
        local frame = {}
        local modName, fileName
        if modAndFile ~= nil then
            modName, fileName = string.match(modAndFile, "^([^:]+):(.+)$")
        end

        if modName ~= nil and fileName ~= nil and #locatable < 9 then
            frame.modName = CoroutineStackTrim(modName)
            frame.fileName = CoroutineStackTrim(fileName)
            frame.lineNumber = tonumber(lineNum)
            locatable[#locatable+1] = frame
            frame.number = #locatable
            frame.display = string.format("%s/%s:%s  %s", frame.modName, frame.fileName, lineNum, CoroutineStackTrim(rest))
        else
            frame.display = CoroutineStackTrim(line)
        end

        frames[#frames+1] = frame
    end

    return frames, locatable
end

--- Build a tooltip panel for a coroutine stack. Each locatable frame is prefixed
--- with its number. The panel is aligned to the top so it appears ABOVE the label.
local function BuildCoroutineTooltip(frames)
    local rows = {}
    rows[#rows+1] = gui.Label{
        text = "Hover and press 1-9 to open a stack location",
        width = "auto",
        height = "auto",
        fontSize = 9,
        color = "#88bbff",
        bmargin = 4,
    }

    for _,frame in ipairs(frames) do
        local text = frame.display
        if frame.number ~= nil then
            text = string.format("<color=#ffcc66>[%d]</color> %s", frame.number, frame.display)
        end

        rows[#rows+1] = gui.Label{
            text = text,
            width = "auto",
            height = "auto",
            fontSize = 10,
            color = frame.number ~= nil and "white" or "#bbbbbb",
        }
    end

    return gui.Panel{
        classes = {"tooltipFrame"},
        bgimage = "panels/square.png",
        bgcolor = "#000000fa",
        borderColor = "#000000fa",
        borderWidth = 10,
        borderFade = true,
        cornerRadius = 10,
        hpad = 16,
        vpad = 10,
        borderBox = true,
        width = "auto",
        height = "auto",
        maxWidth = 1000,
        flow = "vertical",
        valign = "top",
        halign = "left",
        interactable = false,
        children = rows,
        styles = {
            {
                selectors = {"create"},
                transitionTime = 0.2,
                opacity = 0,
            },
        },
    }
end

DockablePanel.Register{
    name = "Development Info",
    icon = "phosphor/info.png",

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
                            data = {},
                            refresh = function(element)
                                element.text = string.format("coroutine %s -- %s", entry.id, coroutine.status(entry.coroutine))
                            end,
                            hover = function(element)
                                local frames, locatable = ParseCoroutineStack(entry.coroutine)
                                element.data.locatable = locatable

                                --seed the key state with whatever is currently held so a
                                --key already down when we begin hovering won't fire until
                                --it is released and pressed again.
                                local keyState = {}
                                for i=1,#locatable do
                                    keyState[i] = dmhub.KeyPressed("Alpha" .. i)
                                end
                                element.data.keyState = keyState

                                element.tooltip = BuildCoroutineTooltip(frames)
                            end,
                            thinkTime = 0.03,
                            think = function(element)
                                if element:HasClass("hover") == false then
                                    return
                                end

                                local locatable = element.data.locatable
                                local keyState = element.data.keyState
                                if locatable == nil or keyState == nil then
                                    return
                                end

                                for i=1,#locatable do
                                    local down = dmhub.KeyPressed("Alpha" .. i)
                                    if down and keyState[i] ~= true then
                                        local f = locatable[i]
                                        dmhub.OpenModFileAtLine(f.modName, f.fileName, f.lineNumber)
                                    end
                                    keyState[i] = down
                                end
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

	icon = "phosphor/sun.png",
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

	icon = "phosphor/network.png",
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

	icon = "phosphor/gauge.png",
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

	icon = "phosphor/blueprint.png",
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

-- Pool stress test: spawn N gui.Check widgets, time the rebuild on demand.
-- Used to investigate per-check construction cost -- the settings dialog spends
-- ~19ms per check editor and we want to know why.
DockablePanel.Register{
    name = "Pool Stress Test",
    icon = "phosphor/stack-plus.png",
    devonly = true,
    folder = "Development Tools",
    minHeight = 320,

    content = function()
        local m_count = 100
        local m_lastDurationMs = 0
        local m_lastBuildN = 0
        local m_runs = {}  -- recent run durations for averaging
        local m_mode = "check"  -- "label", "check", "checkPlain", "checkWrapped"

        -- Forward declarations so closures can refer to them.
        local m_labelsContainer
        local m_durationLabel

        local makeItem = {
            -- Plain label, the original baseline.
            label = function(i)
                return gui.Label{
                    text = string.format("Label %d / %d", i, m_count),
                    fontSize = 12,
                    width = "100%",
                    height = 14,
                }
            end,

            -- Bare gui.Check with just text + value. No monitor, no event handlers,
            -- no style table. Lower bound on per-Check cost.
            checkPlain = function(i)
                return gui.Check{
                    value = false,
                    text = string.format("Check %d / %d", i, m_count),
                    halign = "left",
                    style = {
                        width = "100%",
                        height = 40,
                        fontSize = 14,
                        hpad = 0,
                    },
                }
            end,

            -- Mirrors SettingsEditors.check (SettingsGui.lua:190): outer 90%-wide
            -- wrapper panel containing a gui.Check with monitor + change events.
            -- Uses a fake setting id so monitor wiring does real work.
            check = function(i)
                return gui.Panel{
                    width = "90%",
                    height = "auto",
                    gui.Check{
                        value = false,
                        text = string.format("Check %d / %d", i, m_count),
                        halign = "left",
                        style = {
                            width = "100%",
                            height = 40,
                            fontSize = 14,
                            hpad = 0,
                        },
                        events = {
                            monitor = function() end,
                            change = function() end,
                        },
                    }
                }
            end,

            -- Like check, but also wrapped in the outer container that
            -- CreateSettingsEditor adds (SettingsGui.lua:583). This is the most
            -- faithful repro of what the settings dialog actually builds.
            checkWrapped = function(i)
                local fakeId = string.format("dev:poolstress:%d", i)
                local panel = gui.Panel{
                    width = "90%",
                    height = "auto",
                    gui.Check{
                        value = false,
                        text = string.format("Check %d / %d", i, m_count),
                        halign = "left",
                        style = {
                            width = "100%",
                            height = 40,
                            fontSize = 14,
                            hpad = 0,
                        },
                        monitor = fakeId,
                        events = {
                            monitor = function() end,
                            change = function() end,
                        },
                    }
                }
                return gui.Panel{
                    halign = "center",
                    selfStyle = {
                        width = "auto",
                        height = "auto",
                        pad = 0,
                        margin = 0,
                    },
                    children = { panel },
                }
            end,
        }

        local function rebuild()
            local fn = makeItem[m_mode] or makeItem.check
            local sw = dmhub.Stopwatch()
            local items = {}
            for i = 1, m_count do
                items[#items+1] = fn(i)
            end
            m_labelsContainer.children = items
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
                "Mode: %s\nLast: %d items in %d ms (%.2f ms/item)\nAvg of last %d runs: %.1f ms",
                m_mode, m_lastBuildN, m_lastDurationMs,
                m_lastBuildN > 0 and (m_lastDurationMs / m_lastBuildN) or 0,
                #m_runs, avg)
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
                    text = "N items:",
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
                gui.Label{
                    text = "Mode:",
                    width = 50, height = 24, fontSize = 14,
                    valign = "center",
                    hmargin = 8,
                },
                gui.Dropdown{
                    options = {
                        { id = "label", text = "label" },
                        { id = "checkPlain", text = "checkPlain" },
                        { id = "check", text = "check (settings repro)" },
                        { id = "checkWrapped", text = "checkWrapped (full editor)" },
                    },
                    idChosen = m_mode,
                    width = 200, height = 24, fontSize = 14,
                    change = function(element)
                        m_mode = element.idChosen
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

-- ============================================================
-- Game Recorder panel (developer-only). Wraps the engine `recorder` global.
-- Reuses this file's existing `mod` and `track`.
-- ============================================================

local g_includeUISetting = setting{
    id = "recorder:includeUI",
    description = "Game Recorder: include UI in capture",
    storage = "preference",
    default = true,
}

local g_audioSetting = setting{
    id = "recorder:audio",
    description = "Game Recorder: record audio",
    storage = "preference",
    default = true,
}

local g_fpsSetting = setting{
    id = "recorder:fps",
    description = "Game Recorder: fps override (blank = default)",
    storage = "preference",
    default = "",
}

local g_widthSetting = setting{
    id = "recorder:width",
    description = "Game Recorder: width override (blank = default)",
    storage = "preference",
    default = "",
}

local g_heightSetting = setting{
    id = "recorder:height",
    description = "Game Recorder: height override (blank = default)",
    storage = "preference",
    default = "",
}

local CreateGameRecorderPanel

DockablePanel.Register{
    name = "Game Recorder",
    icon = "phosphor/video-camera.png",
    minHeight = 200,
    vscroll = true,
    devonly = true,
    folder = "Development Tools",
    content = function()
        track("panel_open", {
            panel = "Game Recorder",
            dailyLimit = 30,
        })
        return CreateGameRecorderPanel()
    end,
}

CreateGameRecorderPanel = function()
    if recorder == nil then
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            gui.Label{
                width = "auto",
                height = "auto",
                halign = "left",
                fontSize = 14,
                color = "#cccccc",
                text = "Game Recorder is unavailable in this build (developer/admin only).",
            },
        }
    end

    -- transient recording state (panel-local; never serialized)
    local m_startTime = nil        -- os.time() at recording start, or nil when idle
    local m_lastSavedPath = nil    -- path from the last successful complete(path)
    local m_lastError = nil        -- last error message, shown until next start
    local m_recordingWithUI = false -- whether the active recording includes UI
    local m_autoScope = nil        -- nil | "turn" | "round"
    local m_autoRemaining = 0      -- turn/round ENDS remaining before auto-stop
    local m_autoLastId = nil       -- last observed turn-id / round-id
    local m_autoCount = 1          -- how many turns/rounds to record (user-entered)

    -- forward declarations for panels referenced by helpers/handlers
    local resultPanel
    local m_bodyPanel
    local m_pillPanel
    local ClearAuto

    local function BuildOptions()
        local options = {}
        options.ui = g_includeUISetting:Get()
        options.audio = g_audioSetting:Get()
        options.complete = function(path)
            m_lastSavedPath = path
            m_startTime = nil
        end
        options.error = function(msg)
            m_lastError = msg
            m_startTime = nil
        end
        local fps = tonumber(g_fpsSetting:Get())
        if fps ~= nil and fps > 0 then
            options.fps = math.floor(fps)
        end
        local width = tonumber(g_widthSetting:Get())
        if width ~= nil and width > 0 then
            options.width = math.floor(width)
        end
        local height = tonumber(g_heightSetting:Get())
        if height ~= nil and height > 0 then
            options.height = math.floor(height)
        end
        return options
    end

    local function StartRecording()
        if recorder.recording then
            return
        end
        m_lastError = nil
        m_recordingWithUI = g_includeUISetting:Get()
        m_startTime = os.time()
        recorder:BeginRecording(BuildOptions())
    end

    local function StopAndSave()
        ClearAuto()
        if not recorder.recording then
            return
        end
        recorder:EndRecording{
            complete = function(path)
                m_lastSavedPath = path
                m_startTime = nil
            end,
            error = function(msg)
                m_lastError = msg
                m_startTime = nil
            end,
        }
    end

    local function DiscardRecording()
        ClearAuto()
        if not recorder.recording then
            return
        end
        recorder:CancelRecording()
        m_startTime = nil
    end

    local function FormatElapsed()
        if m_startTime == nil then
            return "00:00"
        end
        local secs = os.time() - m_startTime
        if secs < 0 then secs = 0 end
        return string.format("%02d:%02d", math.floor(secs / 60), secs % 60)
    end

    local function CombatActive()
        local q = dmhub.initiativeQueue
        return q ~= nil and (not q.hidden) and q.gameMode == "combat"
    end

    local function CurrentTurnId()
        local q = dmhub.initiativeQueue
        if q == nil then return nil end
        return q:GetTurnId()
    end

    local function CurrentRoundId()
        local q = dmhub.initiativeQueue
        if q == nil then return nil end
        return q:GetRoundId()
    end

    local function StartAuto(scope, count)
        if recorder.recording or not CombatActive() then
            return
        end
        m_autoScope = scope
        m_autoRemaining = count
        if scope == "round" then
            m_autoLastId = CurrentRoundId()
        else
            -- May be nil if no turn is active yet; we record from now and wait
            -- for one to begin (a nil->id transition is not counted as an end).
            m_autoLastId = CurrentTurnId()
        end
        StartRecording()
    end

    ClearAuto = function()
        m_autoScope = nil
        m_autoRemaining = 0
        m_autoLastId = nil
    end

    -- Stop an active auto-recording when its turn/round boundary passes, or
    -- when combat ends. Called from both refreshGame (immediate) and think
    -- (reliable 0.25s safety net, in case the monitorGame path does not fire).
    local function CheckAutoStop()
        if m_autoScope == nil or not recorder.recording then
            return
        end
        if not CombatActive() then
            -- combat ended entirely; save whatever we captured so far
            StopAndSave()
            return
        end
        local currentId
        if m_autoScope == "round" then
            currentId = CurrentRoundId()
        else
            currentId = CurrentTurnId()
        end
        if currentId ~= m_autoLastId then
            -- A transition occurred. Count it as one "end" only if a real
            -- turn/round was in progress (previous id non-nil). A nil->id
            -- transition means a turn/round just STARTED (the wait-for-turn
            -- case), which is not an end.
            if m_autoLastId ~= nil then
                m_autoRemaining = m_autoRemaining - 1
            end
            m_autoLastId = currentId
            if m_autoRemaining <= 0 then
                StopAndSave()
            end
        end
    end

    local function ToggleRow(labelText, settingObj)
        local indicator
        local row
        local function Apply()
            local on = (settingObj:Get() == true)
            indicator.text = on and "[X]" or "[  ]"
            indicator.color = on and "#66dd66" or "#888888"
        end
        indicator = gui.Label{
            width = 30,
            height = "auto",
            halign = "left",
            valign = "center",
            fontSize = 15,
            bold = true,
            text = "[  ]",
        }
        row = gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",
            vmargin = 2,
            create = function(element)
                Apply()
            end,
            click = function(element)
                settingObj:Set(not (settingObj:Get() == true))
                Apply()
            end,
            indicator,
            gui.Label{
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                fontSize = 14,
                color = "#dddddd",
                text = labelText,
            },
        }
        return row
    end

    local function OptionsZone()
        return gui.Panel{
            classes = {"recorder-zone"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            borderWidth = 1,
            borderColor = "#555555",
            cornerRadius = 6,
            pad = 8,
            borderBox = true,
            vmargin = 4,
            gui.Label{
                width = "auto",
                height = "auto",
                halign = "left",
                fontSize = 10,
                uppercase = true,
                color = "#999999",
                text = "Options",
            },
            ToggleRow("Include UI", g_includeUISetting),
            ToggleRow("Record audio", g_audioSetting),
        }
    end

    local function StatusZone()
        return gui.Panel{
            classes = {"recorder-zone"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            borderWidth = 1,
            borderColor = "#aa3333",
            cornerRadius = 6,
            pad = 8,
            borderBox = true,
            vmargin = 4,
            halign = "center",

            -- live status line: "Idle" or "REC mm:ss"
            gui.Label{
                width = "auto",
                height = "auto",
                halign = "center",
                fontSize = 15,
                bold = true,
                color = "#dddddd",
                text = "Idle",
                thinkTime = 0.25,
                think = function(element)
                    if recorder.recording then
                        element.text = "REC  " .. FormatElapsed()
                        element.color = "#ee3344"
                    elseif m_lastError ~= nil then
                        element.text = "Error: " .. m_lastError
                        element.color = "#eebb33"
                    else
                        element.text = "Idle"
                        element.color = "#dddddd"
                    end
                end,
            },

            -- button row: Start (idle) <-> Stop + Cancel (recording).
            -- Rebuild the row's children on state change. Per-button
            -- SetClass("collapsed", ...) did not reliably show/hide gui.Button,
            -- so we swap which buttons exist instead (proven children= pattern).
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                vmargin = 4,
                data = { rec = nil },
                create = function(element)
                    element:FireEvent("think")
                end,
                thinkTime = 0.25,
                think = function(element)
                    local rec = (recorder.recording == true)
                    if element.data.rec == rec then
                        return
                    end
                    element.data.rec = rec
                    if rec then
                        element.children = {
                            gui.Button{
                                text = "Stop",
                                width = 90,
                                height = 30,
                                fontSize = 14,
                                hmargin = 4,
                                click = function()
                                    StopAndSave()
                                end,
                            },
                            gui.Button{
                                text = "Cancel",
                                width = 90,
                                height = 30,
                                fontSize = 14,
                                hmargin = 4,
                                click = function()
                                    DiscardRecording()
                                end,
                            },
                        }
                    else
                        element.children = {
                            gui.Button{
                                text = "Start Recording",
                                width = 150,
                                height = 30,
                                fontSize = 14,
                                hmargin = 4,
                                click = function()
                                    StartRecording()
                                end,
                            },
                        }
                    end
                end,
            },
        }
    end

    local function FooterZone()
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "center",
            vmargin = 4,
            gui.Label{
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                fontSize = 11,
                color = "#999999",
                maxWidth = 220,
                textWrap = false,
                text = "Last saved: (none yet)",
                think = function(element)
                    if m_lastSavedPath ~= nil then
                        element.text = "Last saved: " .. m_lastSavedPath
                    else
                        element.text = "Last saved: (none yet)"
                    end
                end,
                thinkTime = 0.5,
            },
            gui.Button{
                text = "Open folder",
                width = 90,
                height = 22,
                fontSize = 11,
                hmargin = 6,
                halign = "right",
                valign = "center",
                thinkTime = 0.5,
                think = function(element)
                    element:SetClass("collapsed", m_lastSavedPath == nil)
                end,
                click = function()
                    if m_lastSavedPath == nil then return end
                    local dir = string.match(m_lastSavedPath, "^(.*)[/\\][^/\\]*$")
                    if dir ~= nil then
                        -- NOTE: dmhub.OpenURL is domain-restricted; a file:// URL may be
                        -- rejected. If this button does nothing, leave the footer purely
                        -- informational - the engine already reveals the Recordings folder
                        -- in the OS file browser when a recording is saved. See the spec's
                        -- Open Questions (section 9).
                        dmhub.OpenURL("file://" .. dir)
                    end
                end,
            },
        }
    end

    local function AdvancedZone()
        local fieldsPanel

        local function NumberInput(labelText, settingObj)
            return gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                valign = "center",
                vmargin = 2,
                gui.Label{
                    text = labelText,
                    width = 70,
                    height = "auto",
                    halign = "left",
                    fontSize = 13,
                    color = "#cccccc",
                },
                gui.Input{
                    width = 80,
                    height = 20,
                    fontSize = 13,
                    halign = "left",
                    placeholderText = "default",
                    text = settingObj:Get(),
                    characterLimit = 5,
                    editlag = 0.2,
                    edit = function(element)
                        settingObj:Set(element.text)
                    end,
                },
            }
        end

        fieldsPanel = gui.Panel{
            classes = {"collapsed"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            gui.Label{
                width = "100%",
                height = "auto",
                halign = "left",
                fontSize = 10,
                color = "#888888",
                textWrap = true,
                vmargin = 2,
                text = "Leave blank to use engine defaults: 30 FPS; size = window size when 'Include UI' is on, 1920x1080 for board-only.",
            },
            NumberInput("FPS", g_fpsSetting),
            NumberInput("Width", g_widthSetting),
            NumberInput("Height", g_heightSetting),
        }

        return gui.Panel{
            classes = {"recorder-zone"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            borderWidth = 1,
            borderColor = "#555555",
            cornerRadius = 6,
            pad = 8,
            borderBox = true,
            vmargin = 4,
            gui.Label{
                width = "auto",
                height = "auto",
                halign = "left",
                fontSize = 12,
                color = "#bbbbbb",
                text = "> Advanced",
                data = { expanded = false },
                click = function(element)
                    element.data.expanded = not element.data.expanded
                    element.text = (element.data.expanded and "v Advanced") or "> Advanced"
                    fieldsPanel:SetClass("collapsed", not element.data.expanded)
                end,
            },
            fieldsPanel,
        }
    end

    local function AutoRecordZone()
        local btnRow
        btnRow = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            halign = "left",
            vmargin = 2,
            data = { combat = nil },
            thinkTime = 0.25,
            create = function(element)
                element:FireEvent("think")
            end,
            think = function(element)
                local combat = CombatActive()
                if element.data.combat == combat then
                    return
                end
                element.data.combat = combat
                if combat then
                    element.children = {
                        gui.Panel{
                            width = "auto",
                            height = "auto",
                            flow = "horizontal",
                            valign = "center",
                            vmargin = 2,
                            gui.Label{
                                text = "Count:",
                                width = "auto",
                                height = "auto",
                                halign = "left",
                                valign = "center",
                                fontSize = 13,
                                color = "#cccccc",
                            },
                            gui.Input{
                                width = 44,
                                height = 22,
                                fontSize = 13,
                                halign = "left",
                                lmargin = 6,
                                text = tostring(m_autoCount),
                                characterLimit = 3,
                                editlag = 0.1,
                                edit = function(el)
                                    local n = tonumber(el.text)
                                    if n ~= nil and n >= 1 then
                                        m_autoCount = math.floor(n)
                                    end
                                end,
                            },
                        },
                        gui.Panel{
                            width = "auto",
                            height = "auto",
                            flow = "horizontal",
                            vmargin = 2,
                            gui.Button{
                                text = "Record turns",
                                width = 120,
                                height = 28,
                                fontSize = 13,
                                hmargin = 4,
                                click = function()
                                    StartAuto("turn", m_autoCount)
                                end,
                            },
                            gui.Button{
                                text = "Record rounds",
                                width = 130,
                                height = 28,
                                fontSize = 13,
                                hmargin = 4,
                                click = function()
                                    StartAuto("round", m_autoCount)
                                end,
                            },
                        },
                    }
                else
                    element.children = {
                        gui.Label{
                            width = "auto",
                            height = "auto",
                            halign = "left",
                            valign = "center",
                            fontSize = 12,
                            color = "#777777",
                            text = "Start combat to enable auto-record.",
                        },
                    }
                end
            end,
        }

        return gui.Panel{
            classes = {"recorder-zone"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            borderWidth = 1,
            borderColor = "#555555",
            cornerRadius = 6,
            pad = 8,
            borderBox = true,
            vmargin = 4,
            gui.Label{
                width = "auto",
                height = "auto",
                halign = "left",
                fontSize = 10,
                uppercase = true,
                color = "#999999",
                text = "Auto-record (combat)",
            },
            gui.Label{
                width = "100%",
                height = "auto",
                halign = "left",
                fontSize = 10,
                color = "#888888",
                textWrap = true,
                vmargin = 1,
                text = "Records from now until this many turn/round ends. 1 = until the current one ends.",
            },
            btnRow,
            gui.Label{
                width = "100%",
                height = "auto",
                halign = "left",
                fontSize = 10,
                color = "#66dd66",
                text = "",
                thinkTime = 0.5,
                think = function(element)
                    if m_autoScope == nil or not recorder.recording then
                        element.text = ""
                    elseif m_autoScope == "turn" and m_autoLastId == nil then
                        element.text = "Waiting for a turn to start..."
                    else
                        local unit = m_autoScope
                        if m_autoRemaining ~= 1 then
                            unit = unit .. "s"
                        end
                        element.text = string.format("Auto-recording: %d %s remaining.", m_autoRemaining, unit)
                    end
                end,
            },
        }
    end

    local function RecPill()
        m_pillPanel = gui.Panel{
            classes = {"collapsed"},
            width = "auto",
            height = "auto",
            flow = "horizontal",
            valign = "center",
            halign = "center",
            borderWidth = 1,
            borderColor = "#aa3333",
            bgcolor = "#000000aa",
            cornerRadius = 6,
            pad = 6,
            borderBox = true,
            gui.Label{
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                fontSize = 14,
                bold = true,
                color = "#ee3344",
                text = "REC  00:00",
                hmargin = 4,
                thinkTime = 0.25,
                think = function(element)
                    element.text = "REC  " .. FormatElapsed()
                end,
            },
            gui.Button{
                text = "Stop",
                width = 70,
                height = 26,
                fontSize = 13,
                hmargin = 4,
                click = function()
                    StopAndSave()
                end,
            },
        }
        return m_pillPanel
    end

    m_bodyPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Label{
            width = "auto",
            height = "auto",
            halign = "left",
            fontSize = 16,
            bold = true,
            vmargin = 2,
            text = "Game Recorder",
        },
        StatusZone(),
        OptionsZone(),
        AdvancedZone(),
        AutoRecordZone(),
        FooterZone(),
    }

    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        monitorGame = "/initiativeQueue",
        refreshGame = function(element)
            CheckAutoStop()
        end,
        thinkTime = 0.25,
        think = function(element)
            CheckAutoStop()
            local collapsedToPill = (recorder.recording == true) and m_recordingWithUI
            m_bodyPanel:SetClass("collapsed", collapsedToPill)
            m_pillPanel:SetClass("collapsed", not collapsedToPill)
        end,
        RecPill(),
        m_bodyPanel,
    }

    return resultPanel
end

--------------------------------------------------------------------------------
-- TestHarness: launch the app into an isolated, MCP-drivable UI.
-- See TEST_HARNESS_PLAN.md at the engine repo root.
--
-- Launch:  Codex.exe --harness <id> [--harness-args <string>]
--          (dev builds only; forces the MCP bridge on so Claude can drive it)
-- Manual:  TestHarness.Show("<id>") from the dev console / MCP execute_lua.
-- Probe:   TestHarness.Probe() returns machine-readable state of the active
--          harness, for MCP assertions via execute_lua + json().
--
-- The harness shell is a fullscreen panel over the titlescreen root (the same
-- parenting the ToS dialog uses), shown once the lobby game has loaded so the
-- full game context (tables, documents, settings) is available underneath.
--------------------------------------------------------------------------------

TestHarness = rawget(_G, "TestHarness") or {}

--registry is rebuilt on every reload; files re-register as they load. For now
--all registrations live in this file, below.
TestHarness.registry = {}

--transient state for the currently-shown harness. NOT preserved across
--reloads; the active (id, args) pair that IS preserved lives in the
--g_TestHarnessActive global so a reload can rebuild with fresh code.
local m_shell = nil        --the shell panel.
local m_activeId = nil
local m_activeCtx = nil    --fresh table per Show; create/probe share state here.
local m_showGeneration = 0 --invalidates queued retries when a newer Show runs.

function TestHarness.Register(info)
    TestHarness.registry[info.id] = info
    print("TestHarness:: registered", info.id)
end

--the titlescreen root + its host dialog, or nil if not available (yet).
local function GetHarnessRoot()
    local root = rawget(_G, "CodexTitlescreenRoot")
    if root ~= nil and root.valid then
        return root
    end
    return nil
end

function TestHarness.Hide()
    if m_shell ~= nil and m_shell.valid then
        m_shell:DestroySelf()
    end
    m_shell = nil
    m_activeId = nil
    m_activeCtx = nil
    g_TestHarnessActive = nil
end

local function HarnessButton(text, onclick)
    return gui.Label{
        text = text,
        fontSize = 14,
        bold = true,
        width = "auto",
        height = 26,
        minWidth = 70,
        hpad = 10,
        borderBox = true,
        textAlignment = "center",
        bgimage = "panels/square.png",
        bgcolor = "#233248ff",
        borderWidth = 1,
        borderColor = "#5f7396ff",
        cornerRadius = 6,
        hmargin = 4,
        valign = "center",
        hoverCursor = "hand",
        styles = {
            { selectors = {"hover"}, brightness = 1.4, transitionTime = 0.1 },
            { selectors = {"press"}, brightness = 0.7 },
        },
        click = function(element)
            onclick(element)
        end,
    }
end

--Builds the chrome bar + content shell and mounts the harness's create()
--result inside it. Any error inside create() is caught and shown in place so
--a broken harness never takes the shell down with it.
function TestHarness.Show(id, args)
    m_showGeneration = m_showGeneration + 1
    local generation = m_showGeneration

    local root = GetHarnessRoot()
    if root == nil then
        --titlescreen not built yet (or rebuilt during a reload); retry until
        --it exists. Bounded by generation: a newer Show abandons this one.
        print("TestHarness:: waiting for titlescreen root to show", id)
        dmhub.Schedule(0.25, function()
            if mod.unloaded or generation ~= m_showGeneration then
                return
            end
            TestHarness.Show(id, args)
        end)
        return
    end

    TestHarness.Hide()

    --a Lua reload resets m_shell to nil while the pre-reload shell panel is
    --still alive in the UI tree; Hide() above cannot see it. Destroy any
    --shell found by id so re-shows never stack.
    local stale = root:Get("testHarnessShell")
    if stale ~= nil and stale.valid then
        stale:DestroySelf()
    end

    m_showGeneration = generation --Hide cleared nothing else; keep our claim.

    local reg = TestHarness.registry[id]
    m_activeId = id
    m_activeCtx = {}
    g_TestHarnessActive = { id = id, args = args }

    local contentPanel
    if reg == nil then
        contentPanel = gui.Label{
            text = string.format("Unknown harness '%s'.\nRegistered: %s", tostring(id), table.concat(table.keys(TestHarness.registry), ", ")),
            fontSize = 20,
            color = "#ff9999ff",
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
        }
    else
        local ok, result = pcall(function()
            return reg.create(args, m_activeCtx)
        end)
        if ok and result ~= nil then
            contentPanel = result
        else
            print("TestHarness:: ERROR creating harness", id, ":", tostring(result))
            contentPanel = gui.Label{
                text = string.format("Harness '%s' failed to create:\n%s", tostring(id), tostring(result)),
                fontSize = 16,
                color = "#ff9999ff",
                width = "80%",
                height = "auto",
                textWrap = true,
                halign = "center",
                valign = "center",
            }
        end
    end

    local dropdownOptions = {}
    for _, key in ipairs(table.keys(TestHarness.registry)) do
        dropdownOptions[#dropdownOptions + 1] = { id = key, text = key }
    end
    table.sort(dropdownOptions, function(a, b) return a.id < b.id end)

    --size in titlescreen coordinate space, taken from the host dialog exactly
    --as the ToS overlay does; fall back to the 1080-height convention.
    local dialog = root.data ~= nil and root.data.dialog or nil
    local shellWidth = dialog ~= nil and dialog.width or (1080 * dmhub.screenDimensions.x / dmhub.screenDimensions.y)
    local shellHeight = dialog ~= nil and dialog.height or 1080

    m_shell = gui.Panel{
        id = "testHarnessShell",
        floating = true,
        halign = "center",
        valign = "center",
        width = shellWidth,
        height = shellHeight,
        flow = "vertical",
        bgimage = "panels/square.png",
        bgcolor = "#0b1018ff",

        styles = {
            Styles.Default,
        },

        --chrome bar.
        gui.Panel{
            width = "100%",
            height = 44,
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = "#141c2aff",
            borderWidth = 1,
            borderColor = "#31415cff",

            gui.Label{
                text = "TEST HARNESS",
                fontSize = 16,
                bold = true,
                color = "#8fe3d2ff",
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                lmargin = 14,
                rmargin = 18,
            },
            gui.Dropdown{
                width = 260,
                height = 28,
                valign = "center",
                options = dropdownOptions,
                idChosen = (reg ~= nil and id) or (dropdownOptions[1] ~= nil and dropdownOptions[1].id) or "",
                change = function(element)
                    if element.idChosen ~= m_activeId then
                        TestHarness.Show(element.idChosen, args)
                    end
                end,
            },
            HarnessButton("Reload", function()
                TestHarness.Show(m_activeId, args)
            end),
            gui.Label{
                text = args ~= nil and ("args: " .. tostring(args)) or "",
                fontSize = 12,
                color = "#8295b2ff",
                width = "auto",
                height = "auto",
                maxWidth = 500,
                halign = "left",
                valign = "center",
                lmargin = 8,
            },
            HarnessButton("Close", function()
                TestHarness.Hide()
            end),
        },

        --content area.
        gui.Panel{
            id = "testHarnessContent",
            width = "100%",
            height = "100% available",
            flow = "vertical",
            contentPanel,
        },
    }

    root:AddChild(m_shell)
    print("TestHarness:: showing", id)
end

--The active harness's shared context table (whatever create() stashed there),
--for ad-hoc debugging from the dev console / MCP execute_lua.
function TestHarness.ActiveContext()
    return m_activeCtx
end

--Machine-readable state of the active harness, for MCP assertions.
function TestHarness.Probe()
    local result = {
        active = m_activeId,
        shown = m_shell ~= nil and m_shell.valid or false,
        registered = table.keys(TestHarness.registry),
    }
    local reg = m_activeId ~= nil and TestHarness.registry[m_activeId] or nil
    if reg ~= nil and reg.probe ~= nil and m_activeCtx ~= nil then
        local ok, probeResult = pcall(function()
            return reg.probe(m_activeCtx)
        end)
        if ok then
            result.probe = probeResult
        else
            result.probeError = tostring(probeResult)
        end
    end
    return result
end

--------------------------------------------------------------------------------
-- Built-in harnesses.
--------------------------------------------------------------------------------

--hello: the smallest possible harness; proves the shell, events, and probes.
TestHarness.Register{
    id = "hello",
    create = function(args, ctx)
        ctx.clicks = 0
        local countLabel
        countLabel = gui.Label{
            text = "clicks: 0",
            fontSize = 24,
            width = "auto",
            height = "auto",
            halign = "center",
        }
        return gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",
            gui.Label{
                text = "Hello from the test harness.",
                fontSize = 32,
                width = "auto",
                height = "auto",
                halign = "center",
                vmargin = 40,
            },
            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "center",
                HarnessButton("CLICK ME", function(element)
                    ctx.clicks = ctx.clicks + 1
                    countLabel.text = "clicks: " .. ctx.clicks
                end),
            },
            countLabel,
        }
    end,
    probe = function(ctx)
        return { clicks = ctx.clicks }
    end,
}

--editor: gui.TextEditor playground; the workbench for the seamless journal
--editor project (JOURNAL_SEAMLESS_EDITOR_PLAN.md).
local g_editorFixtures = {
    {
        id = "prose",
        text = "The quick brown fox jumps over the lazy dog.\n\nA second paragraph of plain prose, long enough to wrap when the window is narrow, so caret navigation across wrapped lines can be exercised.\n\nA third paragraph.",
    },
    {
        id = "markdown",
        text = "# Heading One\n\nSome **bold text** and *italics* and a [link](Some Document).\n\n## Heading Two\n\n- bullet one\n- bullet two\n\n[[encounter]]\n\nProse after the island, long enough to verify the placeholder line reserves space and the text below sits under the widget overlay.\n\n1. ordered one\n2. ordered two\n\n| Col A | Col B |\n|-------|-------|\n| a1    | b1    |\n\n[[checkbox]] and a [x] Done item\n\n??? false\nhidden conditional region\n???",
    },
    {
        id = "unicode",
        --built from escapes so this source file stays ASCII-only.
        text = "ASCII then emoji \u{1F409}\u{1F3B2} then CJK \u{4F60}\u{597D}\u{4E16}\u{754C} then accents caf\u{E9} r\u{E9}sum\u{E9} then done.\nSecond line after multibyte content.",
    },
}

--Mini seamless-markdown decoration compiler for the editor harness. This is
--deliberately throwaway: just enough construct coverage (headings, bold,
--italic, links, bullets, [[tag]] islands) to exercise the C# display
--transform end to end. The production compiler (Phase 4 of
--JOURNAL_SEAMLESS_EDITOR_PLAN.md) lives with the journal in MarkdownDocument.lua.
--Offsets are 1-based inclusive BYTE offsets, per the SetDecorations contract.
local function HarnessComputeSeamlessDecorations(text)
    local decs = {}
    local group = 0
    local pos = 1
    local len = #text

    while pos <= len + 1 do
        local newlineAt = text:find("\n", pos, true)
        local lineStop --absolute byte index of the last content byte of the line.
        local nextPos
        if newlineAt == nil then
            if pos > len then
                break
            end
            lineStop = len
            nextPos = len + 1
        else
            lineStop = newlineAt - 1
            nextPos = newlineAt + 1
        end

        local line = text:sub(pos, lineStop)
        local function A(i) return pos + i - 1 end

        local islandTag = line:match("^%[%[(.+)%]%]$")
        if islandTag ~= nil then
            --island covers the whole line INCLUDING the trailing newline.
            group = group + 1
            local toByte = lineStop
            if newlineAt ~= nil then
                toByte = newlineAt
            end
            decs[#decs + 1] = { kind = "island", from = pos, to = toByte, id = islandTag, height = 120, group = group }
        elseif line ~= "" then
            local hashes = line:match("^(#+) ")
            if hashes ~= nil then
                group = group + 1
                local prefixLen = #hashes + 1
                decs[#decs + 1] = { kind = "hide", from = A(1), to = A(prefixLen), group = group }
                if lineStop >= pos + prefixLen then
                    local size = 34 - #hashes * 5
                    if size < 18 then size = 18 end
                    decs[#decs + 1] = {
                        kind = "style",
                        from = A(prefixLen + 1),
                        to = lineStop,
                        open = string.format("<size=%d><b>", size),
                        close = "</b></size>",
                        group = group,
                    }
                end
            end

            if line:match("^%- ") then
                group = group + 1
                decs[#decs + 1] = { kind = "replace", from = A(1), to = A(2), text = "\u{2022} ", group = group }
            end

            --bold: **...**; blank the matches in a scratch copy so the italic
            --pass below cannot see the asterisks.
            local scratch = line
            local searchFrom = 1
            while true do
                local s, e = scratch:find("%*%*..-%*%*", searchFrom)
                if s == nil then break end
                group = group + 1
                decs[#decs + 1] = { kind = "hide", from = A(s), to = A(s + 1), group = group }
                if e - 2 >= s + 2 then
                    decs[#decs + 1] = { kind = "style", from = A(s + 2), to = A(e - 2), open = "<b>", close = "</b>", group = group }
                end
                decs[#decs + 1] = { kind = "hide", from = A(e - 1), to = A(e), group = group }
                scratch = scratch:sub(1, s - 1) .. string.rep("\1", e - s + 1) .. scratch:sub(e + 1)
                searchFrom = e + 1
            end

            --italic: *...*
            searchFrom = 1
            while true do
                local s, e = scratch:find("%*[^%*\1]-%*", searchFrom)
                if s == nil or e <= s + 1 then
                    if s == nil then break end
                    searchFrom = e + 1
                else
                    group = group + 1
                    decs[#decs + 1] = { kind = "hide", from = A(s), to = A(s), group = group }
                    decs[#decs + 1] = { kind = "style", from = A(s + 1), to = A(e - 1), open = "<i>", close = "</i>", group = group }
                    decs[#decs + 1] = { kind = "hide", from = A(e), to = A(e), group = group }
                    searchFrom = e + 1
                end
            end

            --links: [label](target); hide the brackets + target, style the label.
            searchFrom = 1
            while true do
                local s, e, label = scratch:find("%[(..-)%]%(..-%)", searchFrom)
                if s == nil then break end
                group = group + 1
                decs[#decs + 1] = { kind = "hide", from = A(s), to = A(s), group = group }
                decs[#decs + 1] = { kind = "style", from = A(s + 1), to = A(s + #label), open = "<u><color=#7ab3ff>", close = "</color></u>", group = group }
                decs[#decs + 1] = { kind = "hide", from = A(s + #label + 1), to = A(e), group = group }
                searchFrom = e + 1
            end
        end

        pos = nextPos
    end

    return decs
end

TestHarness.Register{
    id = "editor",
    create = function(args, ctx)
        local fixtureId = "markdown"
        if args ~= nil and type(args) == "string" and args ~= "" then
            for _, f in ipairs(g_editorFixtures) do
                if f.id == args then
                    fixtureId = args
                end
            end
        end

        local function FixtureText(fid)
            for _, f in ipairs(g_editorFixtures) do
                if f.id == fid then
                    return f.text
                end
            end
            return ""
        end

        ctx.fixture = fixtureId
        ctx.seamless = false
        ctx.decorationCount = 0
        ctx.islands = {}

        local statusLabel = gui.Label{
            text = "status",
            fontSize = 13,
            color = "#8fe3d2ff",
            width = "100%",
            height = 20,
            halign = "left",
            textAlignment = "left",
        }

        local editor
        local editorWrap
        local m_islandPanels = {}

        local function ApplySeamlessDecorations()
            if not ctx.seamless or editor == nil or not editor.valid then
                return
            end
            local ok, err = pcall(function()
                local decs = HarnessComputeSeamlessDecorations(editor.text or "")
                ctx.decorationCount = #decs
                editor:SetDecorations(decs)
            end)
            if not ok then
                statusLabel.text = "SetDecorations error: " .. tostring(err)
            end
        end

        local function SetSeamless(on)
            local ok, err = pcall(function()
                editor.richDisplay = on
            end)
            if not ok then
                statusLabel.text = "richDisplay error (old binary?): " .. tostring(err)
                return
            end
            ctx.seamless = on
            if on then
                ApplySeamlessDecorations()
            else
                ctx.decorationCount = 0
                for _, p in pairs(m_islandPanels) do
                    if p.valid then
                        p:SetClass("hidden", true)
                    end
                end
            end
        end
        ctx.SetSeamless = SetSeamless
        ctx.ApplySeamlessDecorations = ApplySeamlessDecorations

        editor = gui.TextEditor{
            width = "100%",
            height = "100%",
            fontSize = 16,
            multiline = true,
            textAlignment = "topleft",
            verticalScrollbar = true,
            selectAllOnFocus = false,
            --the SheetTextEditor prefab inherits characterLimit=256 from the
            --SheetInput prefab it was duplicated from; a fixture longer than
            --that silently swallows every keystroke. The journal always
            --overrides this; so must we.
            characterLimit = 200000,
            text = FixtureText(fixtureId),
            editlag = 0.25,
            edit = function(element)
                ApplySeamlessDecorations()
            end,

            --debug overlay for island geometry: draw a translucent panel at each
            --reported rect so the export path is visually verifiable.
            islandLayout = function(element, islands)
                ctx.islands = islands
                if editorWrap == nil or not editorWrap.valid then
                    return
                end
                local seen = {}
                for _, island in ipairs(islands or {}) do
                    seen[island.id] = true
                    local p = m_islandPanels[island.id]
                    if p == nil or not p.valid then
                        p = gui.Panel{
                            floating = true,
                            halign = "left",
                            valign = "top",
                            bgimage = "panels/square.png",
                            bgcolor = "#2e7d3266",
                            borderWidth = 2,
                            borderColor = "#66ff88ff",
                            interactable = false,
                            gui.Label{
                                text = island.id,
                                fontSize = 14,
                                color = "#ccffccff",
                                width = "auto",
                                height = "auto",
                                halign = "center",
                                valign = "center",
                                interactable = false,
                            },
                        }
                        m_islandPanels[island.id] = p
                        editorWrap:AddChild(p)
                    end
                    p:SetClass("hidden", not island.visible)
                    p.selfStyle.width = island.width
                    p.selfStyle.height = island.height
                    p.selfStyle.x = island.x
                    p.selfStyle.y = island.y
                    local label = p.children[1]
                    if label ~= nil and label.valid then
                        label.text = string.format("%s (y=%.0f h=%.0f)", island.id, island.y, island.height)
                    end
                end
                for id, p in pairs(m_islandPanels) do
                    if not seen[id] and p.valid then
                        p:SetClass("hidden", true)
                    end
                end
            end,
        }
        ctx.editor = editor

        editorWrap = gui.Panel{
            width = "100%",
            height = "100% available",
            flow = "none",
            editor,
        }

        local fixtureOptions = {}
        for _, f in ipairs(g_editorFixtures) do
            fixtureOptions[#fixtureOptions + 1] = { id = f.id, text = "fixture: " .. f.id }
        end

        return gui.Panel{
            width = "96%",
            --the app's native version text / admin button overlay the bottom
            --~50px of the screen in their own canvas; keep clear of them so
            --the status strip stays readable.
            height = "100%-60",
            halign = "center",
            valign = "top",
            tmargin = 8,
            flow = "vertical",

            --toolbar.
            gui.Panel{
                width = "100%",
                height = 36,
                flow = "horizontal",
                gui.Dropdown{
                    width = 220,
                    height = 28,
                    valign = "center",
                    options = fixtureOptions,
                    idChosen = fixtureId,
                    change = function(element)
                        ctx.fixture = element.idChosen
                        editor.text = FixtureText(element.idChosen)
                        ApplySeamlessDecorations()
                    end,
                },
                HarnessButton("Undo", function() editor:Undo() end),
                HarnessButton("Redo", function() editor:Redo() end),
                HarnessButton("Caret Start", function()
                    editor:SetTextAndCaret(0, editor.text)
                    editor.hasInputFocus = true
                end),
                HarnessButton("Caret End", function()
                    editor:SetTextAndCaret(#editor.text, editor.text)
                    editor.hasInputFocus = true
                end),
                HarnessButton("Find 'the'", function()
                    local count = editor:Find("the", false)
                    statusLabel.text = string.format("find 'the': %d matches", count or 0)
                end),
                HarnessButton("Seamless", function()
                    SetSeamless(not ctx.seamless)
                    statusLabel.text = "seamless = " .. tostring(ctx.seamless)
                end),
                HarnessButton("Validate", function()
                    local ok, err = pcall(function()
                        local result = editor:ValidateTransform()
                        statusLabel.text = "validate: " .. tostring(result or "OK")
                    end)
                    if not ok then
                        statusLabel.text = "validate error: " .. tostring(err)
                    end
                end),
                --control comparison: gui.Input is exercised all over the
                --titlescreen; if it receives typed text while the TextEditor
                --does not, the fault is TextEditor-specific.
                gui.Input{
                    width = 180,
                    height = 26,
                    valign = "center",
                    lmargin = 8,
                    fontSize = 14,
                    placeholderText = "gui.Input probe",
                    edit = function(element)
                        ctx.inputProbeText = element.text
                    end,
                    change = function(element)
                        ctx.inputProbeText = element.text
                    end,
                },
            },

            editorWrap,

            --live status strip; also mirrored by probe() for MCP assertions.
            gui.Panel{
                width = "100%",
                height = 22,
                flow = "horizontal",
                thinkTime = 0.2,
                think = function(element)
                    if not editor.valid then
                        return
                    end
                    statusLabel.text = string.format(
                        "len=%d caret=%s anchor=%s undo=%s redo=%s fixture=%s seamless=%s decs=%d",
                        #(editor.text or ""),
                        tostring(editor.caretPosition),
                        tostring(editor.selectionAnchorPosition),
                        tostring(editor.canUndo),
                        tostring(editor.canRedo),
                        tostring(ctx.fixture),
                        tostring(ctx.seamless),
                        ctx.decorationCount or 0)
                end,
                statusLabel,
            },
        }
    end,
    probe = function(ctx)
        local editor = ctx.editor
        if editor == nil or not editor.valid then
            return { editorValid = false }
        end
        local result = {
            editorValid = true,
            fixture = ctx.fixture,
            textLength = #(editor.text or ""),
            firstLine = string.match(editor.text or "", "^[^\n]*"),
            caret = editor.caretPosition,
            anchor = editor.selectionAnchorPosition,
            canUndo = editor.canUndo,
            canRedo = editor.canRedo,
            hasInputFocus = editor.hasInputFocus,
            inputProbeText = ctx.inputProbeText,
            seamless = ctx.seamless,
            decorationCount = ctx.decorationCount,
            islands = ctx.islands,
        }
        if ctx.seamless then
            pcall(function()
                result.validate = editor:ValidateTransform() or "OK"
                result.displayTextLength = #(editor.debugDisplayText or "")
            end)
        end
        return result
    end,
}

--seamless: the REAL journal seamless editor (MarkdownDocument:SeamlessEditPanel)
--over a detached document, so the production decoration compiler, island
--widgets, toolbar, and find bar can be driven without entering a game.
TestHarness.Register{
    id = "seamless",
    create = function(args, ctx)
        local doc = MarkdownDocument.new{
            content = "# Session Notes\n\nThe party met **Lord Saxton** at *the crossroads* and agreed to a [contract](Contracts).\n\n## The Ambush\n\n- goblins in the treeline\n- a ~~concealed~~ pit trap\n\n[[encounter]]\n\n> We should have taken the river road.\n\nAfter the fight the party rested. See [Supplies] for what remains.\n\n|Item|Cost|Notes|\n|:---|:---:|---:|\n|Sword|10g|fine steel|\n|Shield|5g|oak|\n\n1. rations x4\n2. rope, 50ft\n\n[[dice:Loot]]\n\n|Loot: 2d6\n|Nothing|\n|A **sword**|\n|A gem|\n\n:<>## Dramatis Personae\n\n:<>a **centered** line of body text\n\n:>-- signed, the Steward\n\n:<>[[encounter]]\n\nThe end.",
            annotations = {},
            styleSheetId = false,
        }
        ctx.doc = doc

        local panel = doc:SeamlessEditPanel{}
        panel:SetClass("collapsed", false)
        ctx.panel = panel

        return gui.Panel{
            width = "96%",
            height = "100%-60",
            halign = "center",
            valign = "top",
            tmargin = 8,
            flow = "vertical",
            panel,
        }
    end,
    probe = function(ctx)
        local result = { docValid = ctx.doc ~= nil }
        local input = ctx.panel ~= nil and ctx.panel.valid and ctx.panel:Get("editorPanel") or nil
        if input ~= nil and input.valid then
            result.editorValid = true
            result.textLength = #(input.text or "")
            result.caret = input.caretPosition
            result.canUndo = input.canUndo
            pcall(function()
                result.validate = input:ValidateTransform() or "OK"
                result.displayTextLength = #(input.debugDisplayText or "")
            end)
            local annotations = {}
            for k, _ in pairs(ctx.doc.annotations or {}) do
                annotations[#annotations + 1] = k
            end
            result.annotations = annotations
        else
            result.editorValid = false
        end
        return result
    end,
}

--------------------------------------------------------------------------------
-- Harness-mode boot: when launched with --harness, wait for the lobby game
-- (full game context) and take over the titlescreen with the named harness.
-- The g_TestHarnessBooted global survives Lua reloads (same mechanism as the
-- titlescreen's own TitlescreenVersion guard), so a reload re-shows the active
-- harness with fresh code instead of re-running the boot.
--------------------------------------------------------------------------------

local function BootHarnessMode()
    --tolerate running on a binary that predates the dmhub.harnessMode bridge.
    local harnessMode = nil
    local harnessArgs = nil
    pcall(function()
        harnessMode = dmhub.harnessMode
        harnessArgs = dmhub.harnessArgs
    end)

    if harnessMode == nil or harnessMode == "" then
        return
    end

    if rawget(_G, "g_TestHarnessBooted") == true then
        --a Lua reload while the harness is up: rebuild it with the fresh code.
        local active = rawget(_G, "g_TestHarnessActive")
        if active ~= nil then
            dmhub.Schedule(0.5, function()
                if mod.unloaded then
                    return
                end
                TestHarness.Show(active.id, active.args)
            end)
        end
        return
    end
    g_TestHarnessBooted = true

    print("TestHarness:: boot mode, waiting for lobby game; harness =", harnessMode)
    lobby:EnterLobbyGame(function()
        if mod.unloaded then
            return
        end
        print("TestHarness:: lobby game loaded; showing", harnessMode)
        TestHarness.Show(harnessMode, harnessArgs)
    end)
end

BootHarnessMode()

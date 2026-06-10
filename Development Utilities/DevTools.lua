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

-- Pool stress test: spawn N gui.Check widgets, time the rebuild on demand.
-- Used to investigate per-check construction cost -- the settings dialog spends
-- ~19ms per check editor and we want to know why.
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
    icon = mod.images.chatIcon,
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

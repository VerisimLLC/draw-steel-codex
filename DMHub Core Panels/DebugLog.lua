local mod = dmhub.GetModLoading()

local CreateDebugLogPanel

setting{
    id = "log:filter",
    section = "dev",
    description = "Log filter",
    storage = "preference",

    default = "",
}

DockablePanel.Register{
	name = "Debug Log",
	icon = "icons/standard/Icon_App_DebugLog.png",
    folder = "Development Tools",
	vscroll = false,
    dmonly = false,
	minHeight = 140,
	content = function()
		return CreateDebugLogPanel()
	end,
}

local testData = {}

for i=1,26 do
    local letter = string.char(96+i)
    local str = ""
    for j=1,80 do
        str = str .. letter
        if j% 5 == 0 then
            str = str .. " "
        end
    end
    for j=1,3 do
        testData[#testData+1] = str

    end
end

local function GetDebugLog()
    return dmhub.debugLog
    --return testData
end

local g_lineLength = 42
local g_rowHeight = 16

CreateDebugLogPanel = function()

    local m_filterString = dmhub.GetSettingValue("log:filter")
    local m_children = {}

    local m_resultPanel
    local m_scrollableList

    local m_numItems = 0

    local searchInput = gui.Input{
        placeholderText = "Enter Filter...",
        text = m_filterString,
        valign = "center",
        selectAllOnFocus = true,
        editlag = 0.1,
        edit = function(element)
            if m_resultPanel ~= nil then
                m_filterString = element.text
                dmhub.SetSettingValue("log:filter", element.text)
                m_resultPanel:FireEventTree("filter", string.lower(element.text))
                m_scrollableList.vscrollPosition = 0;
            end
        end,
    }

    m_scrollableList = gui.Panel{
        height = "100%-70",
        width = "100%",
        flow = "vertical",
        vscroll = true,
        vscrollLockToBottom = true,
        hideObjectsOutOfScroll = true,
        filter = function(element, text)
            element:FireEvent("clear")
        end,
        clear = function(element)
            m_numItems = 0
            m_children = {}
            element.children = {}
        end,

        thinkTime = 0.01,
        think = function(element)
            local newChildren = false
            local log = GetDebugLog()
            while m_numItems < #log do
                m_numItems = m_numItems + 1
                local trace = nil
                local text = log[m_numItems]
                local color = "white"
                if type(text) ~= "string" then
                    trace = text.trace
                    if text.type == "assert" or text.type == "error" then
                        color = "#ffaaaa"
                    end
                    text = text.message
                end

                if m_filterString == nil or m_filterString == "" or regex.MatchGroups(string.lower(text), m_filterString) ~= nil then
                    local textTruncated = text
                    if #text > 240 then
                        textTruncated = string.sub(text, 1, 240) .. string.format("...truncated from %d chars...", #text)
                    end

                    local numRows = 1
                    local nchars = 0
                    for i=1,#textTruncated do
                        nchars = nchars + 1
                        if nchars == g_lineLength or string.sub(textTruncated, i, i) == "\n" then
                            numRows = numRows + 1
                            nchars = 0
                        end
                    end

                    m_children[#m_children+1] = gui.Panel{
                        data = {
                            init = false,
                        },
                        flow = "horizontal",
                        width = "100%",
                        height = numRows*14,
                        bgimage = "panels/square.png",
                        bgcolor = cond(#m_children%2 == 0, "#222222", "#333333"),
                        linger = function(element)
                            if trace ~= nil then
                                gui.Tooltip{text = trace, fontSize=12,width=800}(element)
                            end

                        end,
                        expose = function(element)
                            if element.data.init then
                                return
                            end
                            element.data.init = true

                            local copyIcon = gui.Panel{
                                width = 12,
                                height = 12,
                                valign = "center",
                                halign = "center",
                                bgcolor = Styles.textColor,
                                bgimage = "icons/icon_app/icon_app_108.png",
                                click = function(element)
                                    dmhub.CopyToClipboard(text)
                                    gui.Tooltip("Copied to clipboard!")(element)
                                end,
                            }

                            element.children = {
                                gui.Label{
                                    width = "100%-36",
                                    height = numRows*14,
                                    fontFace = "courier",
                                    editable = false,
                                    hmargin = 4,
                                    fontSize = 12,
                                    links = true,
                                    color = color,
                                    halign = "left",
                                    text = textTruncated,
                                    collectText = function(element, output)
                                        output[#output+1] = text
                                    end,
                                },

                                copyIcon,
                            }
                        end,
                    }

                    newChildren = true
                end

            end

            if newChildren then
                element.children = m_children
            end
        end,
    }

    m_resultPanel = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        gui.Panel{
            flow = "horizontal",
            height = "auto",
            width = "auto",
            searchInput,
            gui.Button{
                valign = "center",
                fontSize = 12,
                text = "Clear",
                click = function(element)
                    dmhub.debugLog = {}
                    m_scrollableList:FireEventTree("clear")
                end,
            },
            gui.Button{
                valign = "center",
                fontSize = 12,
                text = "Copy",
                click = function(element)
                    local text = {}
                    m_scrollableList:FireEventTreeVisible("collectText", text)
                    dmhub.CopyToClipboard(table.concat(text, "\n"))
                    gui.Tooltip("Copied to clipboard!")(element)
                end,
            }
        },
        m_scrollableList,
    }
    
    return m_resultPanel
end
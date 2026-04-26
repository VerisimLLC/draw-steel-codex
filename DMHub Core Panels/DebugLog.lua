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
		track("panel_open", {
			panel = "Debug Log",
			dailyLimit = 30,
		})
		return CreateDebugLogPanel()
	end,
}

local g_lineLength = 42
local g_rowHeight = 14
local g_maxEntries = 5000
local g_trimCount = 1000
local g_poolSize = 100

-- (C) Fast height calculation using string.find instead of per-character iteration
local function CalcHeight(text)
    local numRows = 0
    local pos = 1
    local len = #text
    while pos <= len do
        local nl = string.find(text, "\n", pos, true)
        local lineEnd = nl and (nl - 1) or len
        local lineLen = lineEnd - pos + 1
        numRows = numRows + math.max(1, math.ceil(lineLen / g_lineLength))
        pos = (nl or len) + 1
    end
    if numRows == 0 then numRows = 1 end
    return numRows * g_rowHeight
end

-- (B) Parse a raw debug log entry into a plain data record (no GUI objects)
local function ParseEntry(raw)
    local trace = nil
    local text = raw
    local color = "white"
    if type(raw) ~= "string" then
        trace = raw.trace
        if raw.type == "assert" or raw.type == "error" then
            color = "#ffaaaa"
        end
        text = raw.message
    end

    local displayText = text
    if #text > 240 then
        displayText = string.sub(text, 1, 240) .. string.format("...truncated from %d chars...", #text)
    end

    return {
        text = text,
        displayText = displayText,
        trace = trace,
        color = color,
        height = CalcHeight(displayText),
    }
end

-- Gate trace decoration + frame-open keybinds on devmode + the "debug" preference, so we
-- don't steal number keys for users who aren't debugging.
local function ShouldShowDebugAffordances()
    return devmode() and dmhub.GetSettingValue("debug") == true
end

CreateDebugLogPanel = function()

    local m_filterString = dmhub.GetSettingValue("log:filter")

    -- Most recently hovered row's parsed trace. The panel-level 1-9 keybinds read this so
    -- the user can hover a row and then press a number to open that frame in the editor.
    local m_hoveredParsedTrace = nil

    -- (B) All parsed entries as plain data, no GUI objects
    local m_allEntries = {}
    -- (E) Filtered subset: indices into m_allEntries, rebuilt incrementally
    local m_filteredIndices = {}
    -- (A) Prefix height sums for filtered entries: m_prefixHeights[i] = total height of entries 1..i
    local m_prefixHeights = {}
    local m_totalHeight = 0
    -- How many raw debugLog entries we have ingested
    local m_numIngested = 0

    local m_resultPanel
    local m_scrollableList
    local m_needsRefresh = true

    -- (A) Pool of reusable row panels + spacers (created as children of scroll panel)
    local m_pool = {}
    local m_poolLabels = {}
    local m_topSpacer
    local m_bottomSpacer

    -- (E) Check if an entry passes the current filter
    local function PassesFilter(entry)
        if m_filterString == nil or m_filterString == "" then
            return true
        end
        return regex.MatchGroups(string.lower(entry.text), m_filterString) ~= nil
    end

    -- (E) Rebuild filtered indices from scratch
    local function RebuildFilter()
        m_filteredIndices = {}
        m_prefixHeights = {}
        m_totalHeight = 0
        for i, entry in ipairs(m_allEntries) do
            if PassesFilter(entry) then
                m_filteredIndices[#m_filteredIndices + 1] = i
                m_totalHeight = m_totalHeight + entry.height
                m_prefixHeights[#m_filteredIndices] = m_totalHeight
            end
        end
        m_needsRefresh = true
    end

    -- (E) Add a single new entry to the filtered list incrementally
    local function AddToFilter(entryIndex)
        local entry = m_allEntries[entryIndex]
        if PassesFilter(entry) then
            m_filteredIndices[#m_filteredIndices + 1] = entryIndex
            m_totalHeight = m_totalHeight + entry.height
            m_prefixHeights[#m_filteredIndices] = m_totalHeight
        end
    end

    -- (A) Binary search: find first filtered entry whose bottom edge > scrollOffset
    local function FindFirstVisible(scrollOffset)
        local lo, hi = 1, #m_filteredIndices
        while lo < hi do
            local mid = math.floor((lo + hi) / 2)
            if m_prefixHeights[mid] <= scrollOffset then
                lo = mid + 1
            else
                hi = mid
            end
        end
        return lo
    end

    -- (A) Update pool panels in-place based on current scroll state (no panel creation)
    local function UpdateVisiblePanels()
        local nFiltered = #m_filteredIndices

        if nFiltered == 0 or m_totalHeight == 0 then
            m_topSpacer.selfStyle.height = 0
            m_bottomSpacer.selfStyle.height = 0
            for i = 1, g_poolSize do
                m_pool[i].selfStyle.height = 0
                m_poolLabels[i].text = ""
            end
            return
        end

        local viewportHeight = m_scrollableList.renderedHeight
        if viewportHeight == nil or viewportHeight <= 0 then
            viewportHeight = 600
        end

        -- vscrollPosition: 1 = top, 0 = bottom
        local scrollPos = m_scrollableList.vscrollPosition or 1
        local scrollFraction = 1 - scrollPos
        local maxScroll = math.max(0, m_totalHeight - viewportHeight)
        local scrollOffset = scrollFraction * maxScroll

        -- Find first visible entry via binary search
        local firstVisible = FindFirstVisible(scrollOffset)

        -- Add a small buffer above for smooth scrolling
        firstVisible = math.max(1, firstVisible - 3)
        local topOfFirst = firstVisible > 1 and m_prefixHeights[firstVisible - 1] or 0

        -- Collect entries that fill the viewport plus a buffer below
        local visibleCount = 0
        local lastVisible = firstVisible
        for i = firstVisible, nFiltered do
            visibleCount = visibleCount + 1
            lastVisible = i
            if visibleCount >= g_poolSize then break end
            if m_prefixHeights[i] - topOfFirst > viewportHeight + 200 then break end
        end

        -- Update spacers
        m_topSpacer.selfStyle.height = math.max(0, topOfFirst)
        local bottomStart = m_prefixHeights[lastVisible] or m_totalHeight
        m_bottomSpacer.selfStyle.height = math.max(0, m_totalHeight - bottomStart)

        -- Update pool panels in-place: assign data to visible slots, hide the rest
        for p = 1, g_poolSize do
            local fi = firstVisible + p - 1
            if p <= visibleCount then
                local entryIdx = m_filteredIndices[fi]
                local entry = m_allEntries[entryIdx]
                local panel = m_pool[p]
                local label = m_poolLabels[p]

                panel.selfStyle.height = entry.height
                panel.selfStyle.bgcolor = cond(fi % 2 == 0, "#222222", "#333333")
                panel.data.fullText = entry.text
                panel.data.trace = entry.trace

                label.text = entry.displayText
                label.selfStyle.height = entry.height
                label.selfStyle.color = entry.color
            else
                m_pool[p].selfStyle.height = 0
                m_poolLabels[p].text = ""
            end
        end

        m_needsRefresh = false
    end

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
                RebuildFilter()
                m_scrollableList.vscrollPosition = 0
            end
        end,
    }

    -- Build the scroll panel with pool panels as permanent children.
    -- Order: topSpacer, pool[1..N], bottomSpacer.
    -- Unused pool panels get height=0 so they take no space.
    m_topSpacer = gui.Panel{ width = "100%", height = 0 }
    m_bottomSpacer = gui.Panel{ width = "100%", height = 0 }

    for i = 1, g_poolSize do
        local label = gui.Label{
            width = "100%-36",
            height = 0,
            fontFace = "courier",
            editable = false,
            hmargin = 4,
            fontSize = 12,
            links = true,
            color = "white",
            halign = "left",
            text = "",
        }
        m_poolLabels[i] = label

        m_pool[i] = gui.Panel{
            data = { fullText = "", trace = nil },
            flow = "horizontal",
            width = "100%",
            height = 0,
            bgimage = "panels/square.png",
            bgcolor = "#222222",
            linger = function(element)
                local trace = element.data.trace
                if trace == nil or trace == "" then return end
                if ShouldShowDebugAffordances() then
                    -- Parse each hover so the cache always reflects the row's current
                    -- trace (pool slots rebind as the user scrolls).
                    local parsed = FormatTracebackForDebug(trace)
                    m_hoveredParsedTrace = parsed
                    local text = parsed.decorated
                    if #parsed.frames > 0 then
                        text = text .. "\n\n(Press 1-9 to open that frame in your editor.)"
                    end
                    gui.Tooltip{text = text, fontSize = 12, width = 800}(element)
                else
                    gui.Tooltip{text = trace, fontSize = 12, width = 800}(element)
                end
            end,

            label,

            gui.Panel{
                width = 12,
                height = 12,
                valign = "center",
                halign = "center",
                bgcolor = Styles.textColor,
                bgimage = "icons/icon_app/icon_app_108.png",
                click = function(element)
                    local fullText = element.parent.data.fullText
                    if fullText ~= "" then
                        dmhub.CopyToClipboard(fullText)
                        gui.Tooltip("Copied to clipboard!")(element)
                    end
                end,
            },
        }
    end

    -- Build scroll panel args with all children inline
    local scrollArgs = {
        height = "100%-70",
        width = "100%",
        flow = "vertical",
        vscroll = true,
        vscrollLockToBottom = true,

        scroll = function(element)
            UpdateVisiblePanels()
        end,

        thinkTime = 0.05,
        think = function(element)
            local log = dmhub.debugLog
            local hadNew = false

            -- Ingest new entries from the engine debug log
            while m_numIngested < #log do
                m_numIngested = m_numIngested + 1
                local entry = ParseEntry(log[m_numIngested])
                m_allEntries[#m_allEntries + 1] = entry
                AddToFilter(#m_allEntries)
                hadNew = true
            end

            -- (D) Cap the buffer to prevent unbounded growth
            if #m_allEntries > g_maxEntries then
                local newAll = {}
                for i = g_trimCount + 1, #m_allEntries do
                    newAll[#newAll + 1] = m_allEntries[i]
                end
                m_allEntries = newAll
                m_numIngested = m_numIngested - g_trimCount
                RebuildFilter()
                hadNew = false
            end

            if hadNew or m_needsRefresh then
                UpdateVisiblePanels()
            end
        end,
    }

    -- Children: topSpacer, pool[1..N], bottomSpacer
    local childIndex = 1
    scrollArgs[childIndex] = m_topSpacer
    childIndex = childIndex + 1
    for i = 1, g_poolSize do
        scrollArgs[childIndex] = m_pool[i]
        childIndex = childIndex + 1
    end
    scrollArgs[childIndex] = m_bottomSpacer

    m_scrollableList = gui.Panel(scrollArgs)

    m_resultPanel = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",

        -- When the Debug Log is visible and the user hovers a row with a trace, pressing
        -- a number opens the corresponding stack frame in the editor. Mirrors the F7
        -- style-inspector affordance (Assets/StyleDebuggerInterface.cs).
        keybinds = {
            {id = "dbglog_frame1", defaultBind = "1"},
            {id = "dbglog_frame2", defaultBind = "2"},
            {id = "dbglog_frame3", defaultBind = "3"},
            {id = "dbglog_frame4", defaultBind = "4"},
            {id = "dbglog_frame5", defaultBind = "5"},
            {id = "dbglog_frame6", defaultBind = "6"},
            {id = "dbglog_frame7", defaultBind = "7"},
            {id = "dbglog_frame8", defaultBind = "8"},
            {id = "dbglog_frame9", defaultBind = "9"},
        },
        keybind = function(element, id)
            if not ShouldShowDebugAffordances() then return end
            if m_hoveredParsedTrace == nil then return end
            local n = tonumber(string.sub(id, -1))
            if n == nil then return end
            OpenTracebackFrame(m_hoveredParsedTrace, n)
        end,

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
                    m_allEntries = {}
                    m_filteredIndices = {}
                    m_prefixHeights = {}
                    m_totalHeight = 0
                    m_numIngested = 0
                    m_needsRefresh = true
                end,
            },
            gui.Button{
                valign = "center",
                fontSize = 12,
                text = "Copy",
                click = function(element)
                    -- (E) Copy directly from data, no GUI traversal needed
                    local parts = {}
                    for _, fi in ipairs(m_filteredIndices) do
                        parts[#parts + 1] = m_allEntries[fi].text
                    end
                    dmhub.CopyToClipboard(table.concat(parts, "\n"))
                    gui.Tooltip("Copied to clipboard!")(element)
                end,
            }
        },
        m_scrollableList,
    }

    return m_resultPanel
end
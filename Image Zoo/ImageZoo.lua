local DEFAULT_COLOR = "#bb9a7a"

local dialogStyles = {
    {
        selectors = {"images-dialog"},
        fontFace = "Berling",
        flow = "vertical",
    },
    {
        selectors = {"images-dialog", "images-filter"},
        fontSize = 14,
        borderColor = DEFAULT_COLOR,
        color = DEFAULT_COLOR,
        cornerRadius = 0,
        border = {y1 = 1, y2 = 0, x1 = 1, x2 = 0},
    },
    {
        selectors = {"images-pane"},
        width = 76,
        height = 76,
        pad = 4,
        margin = 4,
        flow = "vertical",
        bgimage = true,
        borderColor = DEFAULT_COLOR,
        borderWidth = 1,
        cornerRadius = 4
    },
    {
        selectors = {"images-item"},
        halign = "center",
        valign = "center",
        bgcolor = "white",
    },
    {
        selectors = {"images-item", "hover"},
        brightness = 1.2,
    }
}

local function parsePathKeywords(imagePath)
    local flags = {}
    local parts = {}

    for part in imagePath:gmatch("[^/]+") do
        parts[#parts + 1] = part
    end

    -- Skip the last part (filename)
    for i = 1, #parts - 1 do
        flags[parts[i]:lower()] = true
    end

    return flags
end

local function buildImagePane(item, allKeywords)
    local imagePath = item and item.path or ""
    if not imagePath or type(imagePath) ~= "string" or #imagePath == 0 then return nil end

    local keywords = parsePathKeywords(imagePath)
    for k,v in pairs(keywords) do
        allKeywords[k] = v
    end

    local h = math.min(64, item.h or 64)
    local w = math.min(64, item.w or 64)

    local m_pane
    m_pane = gui.Panel{
        classes = {"images-pane"},
        data = {
            keywords = keywords,
            imagePath = imagePath:lower(),
        },
        refreshIcons = function(element, filterText)
            local filter = string.lower(filterText or "")
            --plain-text find: image names contain pattern chars like "-" ("address-book-thin").
            local visible = #filter == 0
                or element.data.imagePath:find(filter, 1, true) ~= nil
                or element.data.keywords[filterText]
            element:SetClass("collapsed", not visible)
        end,
        gui.Panel{
            classes = {"images-item"},
            bgimage = imagePath,
            width = w,
            height = h,
            linger = function(element)
                gui.Tooltip{text = imagePath}(element)
            end,
            click = function(element)
                gui.Tooltip{
                    text = "Copied",
                    borderWidth = 1,
                }(element)
                dmhub.CopyToClipboard(imagePath)
            end
        },
    }
    return m_pane
end

local function builtInImagesPanel()
    local m_dialog
    local m_allKeywords = {}

    local imageList = assets.devOnlyBuiltinImagesList
    table.sort(imageList, function(a, b) return a.path < b.path end)

    local headerText = gui.Label{
        text = "Built-In Images",
        width = "100%",
        height = "30",
        fontSize = 24,
        textAlignment = "center",
        valign = "top",
        color = DEFAULT_COLOR,
    }

    local headerPanel = gui.Panel{
        width = "80%",
        height = "40",
        flow = "vertical",
        valign = "top",
        halign = "center",
        headerText,
        gui.Divider {width = "60%", bgcolor = DEFAULT_COLOR},
    }

    --Phosphor icons: the full set (~9k) is available as bgimage = "phosphor/<name>.png", served
    --lazily by the engine from a zip archive. Far too many to instantiate panes for eagerly, so we
    --show only the first MAX_PHOSPHOR_ICONS name matches for the current filter and re-query the
    --engine's name index (assets:GetPhosphorIcons -- no textures loaded) as the filter changes.
    local MAX_PHOSPHOR_ICONS = 100

    local m_phosphorLabel
    local m_phosphorPanel

    local function rebuildPhosphorPanes(filterText)
        --pcall: engine builds that predate GetPhosphorIcons just show an empty section.
        local ids = nil
        pcall(function()
            ids = assets:GetPhosphorIcons(filterText or "", MAX_PHOSPHOR_ICONS)
        end)
        if ids == nil then
            ids = {}
        end

        local panes = {}
        for _,id in ipairs(ids) do
            local pane = buildImagePane({path = id, w = 64, h = 64}, m_allKeywords)
            if pane then
                panes[#panes + 1] = pane
            end
        end

        if #ids >= MAX_PHOSPHOR_ICONS then
            m_phosphorLabel.text = string.format("Phosphor Icons (first %d matches - filter to search all)", MAX_PHOSPHOR_ICONS)
        else
            m_phosphorLabel.text = string.format("Phosphor Icons (%d matches)", #ids)
        end
        m_phosphorLabel:SetClass("collapsed", #ids == 0)
        m_phosphorPanel.children = panes
    end

    local filter = gui.Input{
        classes = {"images-dialog", "images-filter"},
        width = "50%",
        height = 20,
        vmargin = 4,
        halign = "center",
        valign = "top",
        placeholderText = "Filter...",
        editlag = 0.5,
        edit = function(element)
            rebuildPhosphorPanes(element.text)
            m_dialog:FireEventTree("refreshIcons", element.text)
        end
    }

    local imagePanes = {}
    for _,item in ipairs(imageList) do
        local imagePane = buildImagePane(item, m_allKeywords)
        if imagePane then
            imagePanes[#imagePanes + 1] = imagePane
        end
    end

    local builtinPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        children = imagePanes,
    }

    m_phosphorLabel = gui.Label{
        text = "Phosphor Icons",
        width = "100%",
        height = "auto",
        fontSize = 18,
        textAlignment = "center",
        color = DEFAULT_COLOR,
        vmargin = 4,
    }

    m_phosphorPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
    }

    local imagesPanel = gui.Panel{
        width = "100%-8",
        height = "100%-90",
        halign = "center",
        valign = "top",
        vmargin = 4,
        flow = "vertical",
        vscroll = true,
        builtinPanel,
        m_phosphorLabel,
        m_phosphorPanel,
    }

    rebuildPhosphorPanes("")

    m_dialog = gui.Panel{
        styles = dialogStyles,
        classes = {"imagesController", "images-dialog"},
        width = 660,
        height = 660,

        headerPanel,
        filter,
        imagesPanel,
    }

    return m_dialog
end

LaunchablePanel.Register{
    name = "Built In Image Zoo",
    folder = "Development Tools",
    halign = "center",
    valign = "center",
    draggable = true,
    content = function(args)
        return builtInImagesPanel()
    end,
}

local mod = dmhub.GetModLoading()

-- [[resource:<name-or-id>]] renders an editable counter showing the value of a
-- tracked global CharacterResource (e.g. [[resource:malice]] tracks Malice). It
-- mirrors RichCounter's look, but the value lives in the shared global-resource
-- document instead of the journal text, so it stays in sync across clients and
-- with the action-bar malice editor. Hovering shows the resource's change
-- history; the DM can edit the value in place.
--
-- Specific resources can opt into a custom frame (see CustomFrameFor): malice
-- renders as the same red "cost diamond" used on the action bar.

---@class RichResource
RichResource = RegisterGameType("RichResource", "RichTag")
RichResource.tag = "resource"
-- Pattern-based (carries no stored annotation): the resource is identified by
-- the text after the colon, resolved live each render. hasEdit=false keeps it
-- out of the markdown editor's annotation panel (matches RichSetting).
RichResource.pattern = "^resource:(?<resourceid>.+)$"
RichResource.hasEdit = false

-- Resolve the "malice" in [[resource:malice]] to a resource id. Accepts either a
-- raw resource id (a guid present in the table) or a resource name, matched
-- case-insensitively, mirroring how RichSetting resolves its id.
local function ResolveResourceId(text)
    if text == nil then return nil end
    text = (text:gsub("^%s*(.-)%s*$", "%1"))
    if text == "" then return nil end

    local resourceTable = dmhub.GetTable(CharacterResource.tableName) or {}
    if resourceTable[text] ~= nil then
        return text
    end

    local id = CharacterResource.nameToId[text]
    if id ~= nil then return id end

    local lower = string.lower(text)
    for k, resourceInfo in pairs(resourceTable) do
        if resourceInfo.name ~= nil and string.lower(resourceInfo.name) == lower then
            return k
        end
    end

    return nil
end

-- Default look: a RichCounter-style framed box around the value label.
local function BuildBoxFrame(label)
    return gui.Panel{
        classes = {"richCounterFrame", "bg", "fgStrong"},
        width = 64,
        height = 30,
        halign = "left",
        label,
    }
end

-- Malice look: the Draw Steel "cost diamond" from the action bar -- a square
-- rotated 45 degrees (white base + maliceDiamondGradient shading) with a red
-- inner diamond. The value label is counter-rotated by the caller so it stays
-- upright. The outer wrapper just reserves room for the rotated bounding box.
local function BuildMaliceDiamondFrame(label)
    return gui.Panel{
        width = 44,
        height = 44,
        halign = "left",
        valign = "center",
        gui.Panel{
            width = 30,
            height = 30,
            halign = "center",
            valign = "center",
            rotate = 135,
            bgimage = true,
            bgcolor = "white",
            gradient = Styles.Ability.maliceDiamondGradient,
            border = { x1 = 0, y1 = 2, x2 = 2, y2 = 0 },
            borderColor = "grey",
            gui.Panel{
                width = "65%",
                height = "65%",
                halign = "center",
                valign = "center",
                bgimage = true,
                bgcolor = "#DE1E47",
                borderWidth = 2,
                borderColor = "#FF5076",
                label,
            },
        },
    }
end

-- Resources can opt into a custom frame. Returns a builder(label) -> panel, or
-- nil to use the default box. Malice gets the red cost diamond.
local function CustomFrameFor(resourceId)
    if resourceId ~= nil and resourceId == CharacterResource.maliceResourceId then
        return BuildMaliceDiamondFrame
    end
    return nil
end

function RichResource.CreateDisplay(self)
    local resultPanel

    local m_resourceId = nil
    local m_frameBuilder = nil

    -- forward-declared: referenced by the label's refreshTag closure below.
    local ApplyFrame

    local function ResourceInfo()
        if m_resourceId == nil then return nil end
        local resourceTable = dmhub.GetTable(CharacterResource.tableName) or {}
        return resourceTable[m_resourceId]
    end

    local function SetValueText(element)
        if m_resourceId == nil then
            element.text = "?"
        else
            element.text = string.format("%d", CharacterResource.GetGlobalResource(m_resourceId))
        end
        element:SetClass("uploading", false)
    end

    local label = gui.Label{
        styles = {
            {
                selectors = {"uploading"},
                opacity = 0.4,
            },
        },
        classes = {"sizeXl", "bold", "bordered"},
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        numeric = true,
        characterLimit = 3,

        refreshTag = function(element, tag, match)
            self = tag or self
            m_resourceId = ResolveResourceId(match ~= nil and match.resourceid or nil)
            element.editable = dmhub.isDM and m_resourceId ~= nil
            ApplyFrame()
            SetValueText(element)
        end,

        -- Track concurrent changes (abilities spending the resource, the action
        -- bar editing malice, other clients) without needing a journal re-render.
        monitorGame = CharacterResource.GlobalResourcePath(),
        refreshGame = function(element)
            SetValueText(element)
        end,

        hover = function(element)
            if m_resourceId == nil then return end
            local info = ResourceInfo()
            element.tooltip = gui.StatsHistoryTooltip{
                description = (info ~= nil and info.name) or "Resource",
                entries = CharacterResource.GetGlobalResourceHistory(m_resourceId),
            }
        end,

        change = function(element)
            if m_resourceId == nil then return end

            local n = tonumber(element.text)
            if n ~= nil then
                n = round(n)
            end
            n = n or 0

            local info = ResourceInfo()
            if (info == nil or not info.mayBeNegative) and n < 0 then
                n = 0
            end

            CharacterResource.SetGlobalResource(m_resourceId, n, "Manually set")
            element.text = string.format("%d", n)
            element:SetClass("uploading", true)
        end,
    }

    -- Swap the frame around the (persistent) value label to match the resolved
    -- resource. Only rebuilds when the chosen builder actually changes. A given
    -- tag instance only ever resolves to one resource (editing the journal text
    -- spawns a fresh panel), and the default box uses the label's construction
    -- styling, so we only need to apply the diamond's overrides on the way in.
    ApplyFrame = function()
        local builder = CustomFrameFor(m_resourceId) or BuildBoxFrame
        if builder == m_frameBuilder then return end
        m_frameBuilder = builder

        label:Unparent()

        if builder == BuildMaliceDiamondFrame then
            -- compact upright value inside the small diamond; drop the box chrome.
            label:SetClass("sizeXl", false)
            label:SetClass("bordered", false)
            label.selfStyle.width = "auto"
            label.selfStyle.height = "auto"
            label.selfStyle.minWidth = 24
            label.selfStyle.fontSize = 14
            label.selfStyle.color = "white"
            label.selfStyle.rotate = -135
        end

        resultPanel.children = { builder(label) }
    end

    resultPanel = gui.Panel{
        width = "auto",
        height = "auto",
        halign = "left",
        label,
    }

    return resultPanel
end

MarkdownDocument.RegisterRichTag(RichResource)

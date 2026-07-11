local mod = dmhub.GetModLoading()

RegisterGameType("CommandDocument", "CustomDocument")
CommandDocument.command = ""

function CommandDocument:ShowDocument()
	LaunchablePanel.GetOrLaunchPanel(self.command)
end

RegisterGameType("MonsterReferenceDocument", "CustomDocument")
MonsterReferenceDocument.monsterid = ""

function MonsterReferenceDocument:Render()
    local monster = assets.monsters[self.monsterid]

    if monster ~= nil then
        return monster:Render{width = 800}
    end
end

function MonsterReferenceDocument:ShowDocument()
end

RegisterGameType("PDFDeepLink", "CustomDocument")
PDFDeepLink.docid = ""
PDFDeepLink.page = "C"

function PDFDeepLink:ShowDocument()
    local docs = assets.pdfDocumentsTable
    local doc = docs[self.docid]
    if doc ~= nil then
        OpenPDFDocument(doc, self.page)
    end
end

function PDFDeepLink:PreviewDescription()
    local docs = assets.pdfDocumentsTable
    local doc = docs[self.docid]
    if doc ~= nil then
        return doc.description
    else
        return "Cannot get document information"
    end
end

RegisterGameType("MapDocument", "CustomDocument")
MapDocument.mapid = ""
MapDocument.nodeType = "map"

function MapDocument:ShowDocument()
    for _,map in ipairs(game.maps) do
        if map.id == self.mapid then
            map:Travel()
            return
        end
    end
end

function MapDocument:GetMap()
    for _,map in ipairs(game.maps) do
        if map.id == self.mapid then
            return map
        end
    end
    return nil
end

function MapDocument:PreviewDescription()
    local map = self:GetMap()
    if map ~= nil then
        return string.format("Click to go to %s", map.description)
    else
        return "Cannot get map information"
    end
end

--A link to an info bubble on a map ("bubble:Room 1" or
--"bubble:Map Name/Room 1"). Hovering the link previews the bubble's journal
--document; clicking travels to the bubble's map if needed, centers the
--camera on the bubble (on engine builds that support loc-based camera
--moves), and opens the bubble's info dialog - the same one clicking the
--bubble on the map shows.
RegisterGameType("BubbleDocument", "CustomDocument")
BubbleDocument.mapid = ""      --"" = the current map
BubbleDocument.bubblename = "" --matched against bubble icon and description
BubbleDocument.nodeType = "bubble"

--Find a bubble on the CURRENT map by id, icon, or description (bubbles on
--other maps are not enumerable; travel first). Exact matches win over
--substring matches so "bubble:1" picks bubble 1, not bubble 11.
function BubbleDocument.FindBubble(name)
    local lname = string.lower(tostring(name or ""))
    if lname == "" then
        return nil
    end
    local substringMatch = nil
    for id, b in pairs(dmhub.infoBubbles or {}) do
        local icon, desc = "", ""
        pcall(function() icon = string.lower(tostring(b.icon or "")) end)
        pcall(function() desc = string.lower(tostring(b.description or "")) end)
        if id == name or icon == lname or desc == lname then
            return b
        end
        if substringMatch == nil and #desc > 0 and string.find(desc, lname, 1, true) then
            substringMatch = b
        end
    end
    return substringMatch
end

function BubbleDocument:GetBubble()
    if self.mapid ~= "" and game.currentMapId ~= self.mapid then
        return nil
    end
    return BubbleDocument.FindBubble(self.bubblename)
end

--The journal document behind the bubble (InfoDocument.docid). Drives the
--hover preview; nil when the bubble is on another map or has no document.
function BubbleDocument:GetMarkdownDocument()
    local bubble = self:GetBubble()
    if bubble == nil then
        return nil
    end
    local doc = nil
    pcall(function()
        if bubble.document ~= nil and bubble.document.docid then
            doc = (dmhub.GetTable(CustomDocument.tableName) or {})[bubble.document.docid]
        end
    end)
    return doc
end

local function FocusBubble(bubble)
    if bubble == nil then
        return
    end
    --Center the camera on the bubble. CenterOnLoc does not exist on older
    --engine builds and the bubble's world position comes off its hud sheet,
    --so the whole move is best-effort; the info dialog opens regardless.
    pcall(function()
        local p = bubble.sheet.sheet.positionInWorldSpace
        dmhub.CenterOnLoc{ x = p.x, y = p.y, floorid = bubble.floorid, smooth = true }
    end)
    local hud = GameHud.instance
    if hud ~= nil then
        hud:DisplayDocument(bubble)
    end
end

function BubbleDocument:ShowDocument()
    if self.mapid ~= "" and game.currentMapId ~= self.mapid then
        for _, map in ipairs(game.maps) do
            if map.id == self.mapid then
                map:Travel()
                break
            end
        end
        --bubbles populate asynchronously after the map loads; wait for ours
        --(bounded so a renamed/deleted bubble cannot leave a pending watcher).
        local bubblename = self.bubblename
        local deadline = dmhub.Time() + 10
        dmhub.ScheduleWhen(function()
            if mod.unloaded or dmhub.Time() > deadline then
                return true
            end
            return BubbleDocument.FindBubble(bubblename) ~= nil
        end, function()
            if mod.unloaded then return end
            FocusBubble(BubbleDocument.FindBubble(bubblename))
        end)
    else
        FocusBubble(self:GetBubble())
    end
end

--Hover preview: render the bubble's journal page inline (the same panel a
--[:...] page embed shows), so mousing over the link reads the room info
--without going anywhere. Falls back to PreviewDescription when the bubble
--is on another map (not enumerable from here) or carries no document.
function BubbleDocument:Render(args)
    local doc = self:GetMarkdownDocument()
    if doc == nil then
        return nil
    end
    return CustomDocument.CreateEmbeddablePanel(doc, { embedDepth = 2 })
end

function BubbleDocument:PreviewDescription()
    if self.mapid ~= "" and game.currentMapId ~= self.mapid then
        for _, map in ipairs(game.maps) do
            if map.id == self.mapid then
                return string.format("Click to go to the '%s' bubble on %s", self.bubblename, map.description)
            end
        end
        return "Cannot find the linked map"
    end
    local bubble = self:GetBubble()
    if bubble == nil then
        return string.format("No bubble named '%s' on this map", self.bubblename)
    end
    local desc = ""
    pcall(function() desc = tostring(bubble.description or "") end)
    return string.format("Click to view %s", desc ~= "" and desc or "this bubble")
end

function CustomDocument.PreviewLink(element, link)
    if string.starts_with(link, "http://") or string.starts_with(link, "https://") then
        gui.Tooltip("Click to open this link in your web browser")(element)
        return
    end


    local content = CustomDocument.ResolveLink(link)

    if content == nil then
        gui.Tooltip(string.format("No document found. Click to create '%s' as a new Text Document in your journal", link))(element)
        return
    end

    if type(content) == "table" then
        local panel = nil
        if MarkdownRender.IsRenderable(content) then
            panel = MarkdownRender.RenderToPanel(content, {
                width = 600,
                height = "auto",
                noninteractive = true,
            })
        elseif content.typeName == "CommandDocument" then
            return
        elseif content.IsDerivedFrom("CustomDocument") then
            panel = content:Render{summary = nil}
            if panel == nil then
                gui.Tooltip(content:PreviewDescription())(element)
            end
        else
            panel = content:Render{}
        end

        if panel ~= nil then
            element.tooltip = gui.TooltipFrame(panel, {
                interactable = false,
                halign = "right",
                width = 600,
            })
        end
    end

    if element.tooltip ~= nil then
        element.tooltip:MakeNonInteractiveRecursive()
    end
end

function CustomDocument.CreateEmbeddablePanel(content, args)
    if type(content) == "table" then
        if content.typeName == "CommandDocument" then
            return
        elseif content.IsDerivedFrom("CustomDocument") then
            if (args.embedDepth or 0) >= 3 then
                return gui.Label{
                    text = "(Too Deeply Nested)",
                    fontSize = 12,
                    color = "gray",
                    halign = "left",
                    width = "auto",
                    height = "auto",
                }
            end

            return gui.Panel{
                width = "100%",
                height = "auto",
                valign = "top",
                margin = 0,
                pad = 0,
                content:DisplayPanel{
                    height = "auto",
                    vscroll = false,
                    hpad = 0,
                    hmargin = 0,
                    embedDepth = (args.embedDepth or 0) + 1,
                    hostPageColor = args.hostPageColor,
                },
                savedoc = function(element)
                    element:HaltEventPropagation()
                end,
                refreshDocument = function(element)
                    element:HaltEventPropagation()
                end,
                editDocument = function(element)
                    element:HaltEventPropagation()
                end,
                refreshTag = function(element)
                    element:HaltEventPropagation()
                end,
            }
        end
    end
end

function CustomDocument.SearchLinks(search)
    search = string.lower(search)

    local isDM = dmhub.isDM

    -- Check if search has a recognized table prefix (e.g. "item:blood" or "item:")
    local prefixStr, rest = string.match(search, "^([^:]+):(.*)$")
    if prefixStr ~= nil then
        local tableName = MarkdownRender.FindTableFromPrefix(prefixStr)
        if tableName ~= nil then
            -- Hard lock: only return results from this table
            local results = {}
            local tableData = dmhub.GetTable(tableName) or {}
            for k, v in unhidden_pairs(tableData) do
                if MarkdownRender.IsRenderable(v) then
                    local entryName = rawget(v, "name") or rawget(v, "description") or ""
                    if #rest == 0 or string.find(string.lower(entryName), rest, 1, true) then
                        results[#results+1] = {
                            link = prefixStr .. ":" .. entryName,
                            name = entryName,
                            type = prefixStr,
                        }
                    end
                end
            end
            return results
        end

        -- Hard lock for the built-in link prefixes (pdf:, document:, map:).
        -- Restrict to the named category and match on description only --
        -- otherwise body-text matches via doc:MatchesSearch leak across
        -- categories (e.g. "pdf:draw" surfacing Documents that mention "draw").
        if prefixStr == "pdf" then
            local results = {}
            local docs = assets.pdfDocumentsTable
            for k, doc in pairs(docs or {}) do
                if (not doc.hidden) and (isDM or not doc.hiddenFromPlayers) then
                    if #rest == 0 or string.find(string.lower(doc.description), rest, 1, true) then
                        results[#results+1] = {
                            link = "pdf:" .. doc.description,
                            name = doc.description,
                            type = "PDF Document",
                        }
                    end
                end
            end
            local fragments = dmhub.GetTable(PDFFragment.tableName) or {}
            for k, doc in unhidden_pairs(fragments) do
                if #rest == 0 or string.find(string.lower(doc.description), rest, 1, true) then
                    results[#results+1] = {
                        link = "pdf:" .. doc.description,
                        name = doc.description,
                        type = "PDF Fragment",
                    }
                end
            end
            return results
        end

        if prefixStr == "document" then
            local results = {}
            local customDocs = dmhub.GetTable(CustomDocument.tableName) or {}
            local accessibleRoots = CustomDocument.GetAccessibleRoots()
            for k,doc in unhidden_pairs(customDocs) do
                if (isDM or not doc.hiddenFromPlayers)
                    and CustomDocument.IsDocInAccessibleRoot(doc, accessibleRoots)
                    and (#rest == 0 or string.find(string.lower(doc.description), rest, 1, true)) then
                    results[#results+1] = {
                        link = "document:" .. doc.description,
                        name = doc.description,
                        type = "Document",
                    }
                end
            end
            return results
        end

        if prefixStr == "map" and isDM then
            local results = {}
            for _,map in ipairs(game.maps) do
                if #rest == 0 or string.find(string.lower(map.description), rest, 1, true) then
                    results[#results+1] = {
                        link = "map:" .. map.description,
                        name = map.description,
                        type = "Map",
                    }
                end
            end
            return results
        end

        if prefixStr == "bubble" and isDM then
            --info bubbles on the current map only; bubbles on other maps are
            --not enumerable (link those by hand as bubble:Map Name/Bubble).
            local results = {}
            for id, b in pairs(dmhub.infoBubbles or {}) do
                local desc, icon = "", ""
                pcall(function() desc = tostring(b.description or "") end)
                pcall(function() icon = tostring(b.icon or "") end)
                local name = desc ~= "" and desc or icon
                if name ~= "" and (#rest == 0 or string.find(string.lower(name), rest, 1, true)) then
                    results[#results+1] = {
                        link = "bubble:" .. name,
                        name = string.format("%s (bubble %s)", name, icon),
                        type = "Bubble",
                    }
                end
            end
            table.sort(results, function(a, b) return a.name < b.name end)
            return results
        end
    end

    -- Normal search (no locked prefix)
    local results = {}

    local docs = assets.pdfDocumentsTable
    for k, doc in pairs(docs or {}) do
        if (not doc.hidden) and (isDM or not doc.hiddenFromPlayers) then
            if string.find(string.lower(doc.description), search, 1, true) then
                local link = "pdf:" .. doc.description
                results[#results+1] = {
                    link = link,
                    name = doc.description,
                    type = "PDF Document",
                }
            end
        end
    end

    local fragments = dmhub.GetTable(PDFFragment.tableName) or {}
    for k, doc in unhidden_pairs(fragments) do
        if string.find(string.lower(doc.description), search, 1, true) then
            local link = "pdf:" .. doc.description
            results[#results+1] = {
                link = link,
                name = doc.description,
                type = "PDF Fragment",
            }
        end
    end

    local customDocs = dmhub.GetTable(CustomDocument.tableName) or {}
    local accessibleRoots = CustomDocument.GetAccessibleRoots()
    for k,doc in unhidden_pairs(customDocs) do
        if (isDM or not doc.hiddenFromPlayers)
            and CustomDocument.IsDocInAccessibleRoot(doc, accessibleRoots)
            and (string.find(string.lower(doc.description), search, 1, true) or doc:MatchesSearch(search)) then
            local link = "document:" .. doc.description
            results[#results+1] = {
                link = link,
                name = doc.description,
                type = "Document",
            }
        end
    end

    if isDM then
        local maps = game.maps
        for _,map in ipairs(maps) do
            if string.find(string.lower(map.description), search, 1, true) ~= nil then
                local link = "map:" .. map.description
                results[#results+1] = {
                    link = link,
                    name = map.description,
                    type = "Map",
                }
            end
        end
    end

    -- Suggest matching table prefixes (e.g. typing "it" suggests "item:")
    local registeredPrefixes = MarkdownRender.GetRegisteredPrefixes()
    for _, info in ipairs(registeredPrefixes) do
        if string.find(info.prefix, search, 1, true) == 1 and info.prefix ~= search then
            results[#results+1] = {
                link = info.prefix .. ":",
                name = info.prefix .. ":",
                type = "Search " .. info.prefix .. "s...",
                isPrefix = true,
            }
        end
    end

    -- Search registered markdown tables (items, titles, etc.) by entry name,
    -- so plain text like "healing" surfaces matching items without the user
    -- needing to type the "item:" prefix first. The link still uses the
    -- "prefix:name" form so it resolves unambiguously to that table.
    for _, info in ipairs(registeredPrefixes) do
        local tableData = dmhub.GetTable(info.tableName) or {}
        for k, v in unhidden_pairs(tableData) do
            if MarkdownRender.IsRenderable(v) then
                local entryName = rawget(v, "name") or rawget(v, "description") or ""
                if #entryName > 0 and string.find(string.lower(entryName), search, 1, true) then
                    results[#results+1] = {
                        link = info.prefix .. ":" .. entryName,
                        name = entryName,
                        type = info.prefix,
                    }
                end
            end
        end
    end

    -- Search monsters by name. Monster references resolve directly from the
    -- plain link name (see ResolveLink's monster fallback), so no prefix is
    -- used here.
    local monsters = assets.monsters
    for k, monster in pairs(monsters) do
        if (not monster.hidden) and monster.name ~= nil and string.find(string.lower(monster.name), search, 1, true) then
            results[#results+1] = {
                link = monster.name,
                name = monster.name,
                type = "monster",
            }
        end
    end

    return results
end

function CustomDocument.ResolveLink(link)
    local original_link = link
    link = string.lower(link)

    if string.starts_with(link, "http://") or string.starts_with(link, "https://") then
        return original_link
    end

    local matchPrefix = regex.MatchGroups(link, "^(?<prefix>[^:]+):(?<rest>.+)$")
    if matchPrefix ~= nil then
        --see if this is a reference to a markdownable document somewhere.
        local markdownTable = MarkdownRender.FindTableFromPrefix(matchPrefix.prefix)
        if markdownTable ~= nil then
            local tableData = dmhub.GetTable(markdownTable) or {}
            local name = string.lower(matchPrefix.rest)
            for k,v in unhidden_pairs(tableData) do
                local entryName = string.lower(rawget(v, "name") or rawget(v, "description") or "")
                if name == entryName and MarkdownRender.IsRenderable(v) then
                    return v
                end
            end
        end
    end

    if string.starts_with(link, "pdf:") then
        local docs = assets.pdfDocumentsTable
        local fragments = dmhub.GetTable(PDFFragment.tableName) or {}

        -- Match the whole remainder (no page) by guid or by description first,
        -- so a title that happens to contain a colon still resolves.
        local rest = string.sub(link, 5)
        local doc = docs[rest] or fragments[rest]
        if doc == nil then
            for k,d in pairs(docs) do
                if string.lower(d.description) == rest then
                    doc = d
                    break
                end
            end
        end
        if doc == nil then
            for k,d in unhidden_pairs(fragments) do
                if string.lower(d.description) == rest then
                    doc = d
                    break
                end
            end
        end
        if doc ~= nil then
            return doc
        end

        -- Otherwise treat a trailing ":page" as a PDF deep link.
        local match = regex.MatchGroups(link, "^pdf:(?<docid>.+):(?<page>[0-9a-zA-Z]+)$")
        if match ~= nil then
            local docid = match.docid
            if docs[docid] ~= nil then
                return PDFDeepLink.new{
                    docid = docid,
                    page = match.page,
                }
            end
            for k,d in pairs(docs) do
                if string.lower(d.description) == docid then
                    return PDFDeepLink.new{
                        docid = k,
                        page = match.page,
                    }
                end
            end
        end
        return nil
    end

    if string.starts_with(link, "document:") then
        local docid = string.sub(link, 10)
        local customDocs = dmhub.GetTable(CustomDocument.tableName) or {}
        local doc = customDocs[docid]
        if doc == nil then
            for k,d in unhidden_pairs(customDocs) do
                if string.lower(d.description) == docid then
                    doc = d
                    break
                end
            end
        end
        return doc
    end

    if string.starts_with(link, "bubble:") then
        --"bubble:Room 1" (current map) or "bubble:Map Name/Room 1".
        local rest = string.sub(link, 8)
        local mapname, bubblename = string.match(rest, "^(.-)%s*/%s*(.+)$")
        if bubblename == nil then
            mapname, bubblename = nil, rest
        end

        if mapname ~= nil and mapname ~= "" then
            for _, map in ipairs(game.maps) do
                if map.id == mapname or string.lower(map.description) == mapname then
                    --cross-map bubbles are not enumerable until the map loads,
                    --so resolve optimistically; ShowDocument travels and waits.
                    return BubbleDocument.new{
                        mapid = map.id,
                        bubblename = bubblename,
                    }
                end
            end
            return nil
        end

        if BubbleDocument.FindBubble(bubblename) == nil then
            return nil
        end
        return BubbleDocument.new{
            bubblename = bubblename,
        }
    end

    if string.starts_with(link, "map:") then
        local mapid = string.sub(link, 5)
        for _,map in ipairs(game.maps) do
            if map.id == mapid then
                return MapDocument.new{
                    mapid = mapid,
                }
            end
        end
        for _,map in ipairs(game.maps) do
            if string.lower(map.description) == mapid then
                return MapDocument.new{
                    mapid = map.id,
                }
            end
        end
        return nil
    end

    local launchableWindows = LaunchablePanel.GetMenuItems()
    for _,item in ipairs(launchableWindows) do
        if item.name ~= nil and link == string.lower(item.name) then
            return CommandDocument.new{
                command = item.name,
            }
        end
    end

    local docs = assets.pdfDocumentsTable
    for k, doc in pairs(docs or {}) do
        if string.lower(doc.description) == link then
            return doc
        end
    end

    local fragments = dmhub.GetTable(PDFFragment.tableName) or {}
    for k, doc in unhidden_pairs(fragments) do
        if string.lower(doc.description) == link then
            return doc
        end
    end

    local customDocs = dmhub.GetTable(CustomDocument.tableName) or {}
    for k,doc in unhidden_pairs(customDocs) do
        if string.lower(doc.description) == link then
            return doc
        end
    end

    local monsters = assets.monsters
    for k,monster in pairs(monsters) do
        if not monster.hidden and ((monster.name ~= nil and string.lower(monster.name) == link) or (monster.properties ~= nil and string.lower(monster.properties:try_get("monster_type", "")) == link)) then
            return MonsterReferenceDocument.new{
                monsterid = k,
            }
        end
    end

    local maps = game.maps
    for _,map in ipairs(maps) do
        if string.lower(map.description) == link then
            return MapDocument.new{
                mapid = map.id,
            }
        end
    end

end



function CustomDocument.OpenContent(node)
    if node == nil then
        return
    end

    print("OPEN::", node)
    if type(node) == "string" then
        if string.starts_with(node, "http://") or string.starts_with(node, "https://") then
            dmhub.OpenURL(node)
        end
        return
    end
    if type(node) == "userdata" then
        local nodeType = node.nodeType
        if nodeType == "pdf" then
            OpenPDFDocument(node)
        elseif nodeType == "image" then
            local imageWrapper = ImageDocument.new {
                imageid = node.id,
                width = node.width,
                height = node.height,
            }

            GameHud.instance:ViewCompendiumEntryModal(imageWrapper)
        end
    elseif node.IsDerivedFrom("CustomDocument") then
        node:ShowDocument()
    elseif MarkdownRender.IsRenderable(node) then
        local doc = MarkdownRender.RenderToMarkdown(node, {
            noninteractive = false,
        })

        doc:ShowDocument()
    else
        GameHud.instance:ViewCompendiumEntryModal(node)
    end
end

RegisterGameType("CustomDocumentRef")

CustomDocumentRef.docid = ""

function CustomDocumentRef:Render(options)
    options = options or {}
    options.summary = nil

    local doc = (dmhub.GetTable(CustomDocument.tableName) or {})[self.docid]
    local text = ""
    if doc == nil then
        text = "Invalid Document"
    else
        text = doc.description
    end

    local args = {
        classes = {"link"},
        halign = "left",
        width = "auto",
        height = "auto",
        text = text,
        fontSize = 14,
        hoverCursor = "hand",
        click = function(element)
            if doc ~= nil then
                CustomDocument.OpenContent(doc)
            end
        end,
    }

    for k, v in pairs(options) do
        args[k] = v
    end

    return gui.Label(args)
end
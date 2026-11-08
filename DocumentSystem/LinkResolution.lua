local mod = dmhub.GetModLoading()

--- @class CommandDocument: CustomDocument
--- @field new fun(o?: table): CommandDocument
CommandDocument = RegisterGameType("CommandDocument", "CustomDocument")
CommandDocument.command = ""

function CommandDocument:ShowDocument()
	--panels the journal can link to live in either registry: most are now
	--ordinary dockable panels (Maps, the Compendium, the Measuring Tool),
	--the rest are still launchable dialogs.
	if DockablePanel.ShowPanelByName(self.command) then
		return
	end
	LaunchablePanel.GetOrLaunchPanel(self.command)
end

--- @class MonsterReferenceDocument: CustomDocument
--- @field new fun(o?: table): MonsterReferenceDocument
MonsterReferenceDocument = RegisterGameType("MonsterReferenceDocument", "CustomDocument")
MonsterReferenceDocument.monsterid = ""

function MonsterReferenceDocument:Render()
    local monster = assets.monsters[self.monsterid]

    if monster ~= nil then
        return monster:Render{width = 800}
    end
end

function MonsterReferenceDocument:ShowDocument()
end

--- @class PDFDeepLink: CustomDocument
--- @field new fun(o?: table): PDFDeepLink
PDFDeepLink = RegisterGameType("PDFDeepLink", "CustomDocument")
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

--- @class MapDocument: CustomDocument
--- @field new fun(o?: table): MapDocument
MapDocument = RegisterGameType("MapDocument", "CustomDocument")
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
--- @class BubbleDocument: CustomDocument
--- @field new fun(o?: table): BubbleDocument
BubbleDocument = RegisterGameType("BubbleDocument", "CustomDocument")
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
    if hud then
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
--The starting depth deliberately bounds nesting inside a hover card more tightly
--than a full journal page, but 2 bounded it to NOTHING: CreateEmbeddablePanel
--refuses at >= 3 and adds 1 for the panel it builds, so the page rendered here
--began life at 3 and every embed on it came back "(Too Deeply Nested)" -- while
--the very same embed worked when the page was opened from the journal, which
--starts at 0. That asymmetry is what reporters hit and could not explain
--("sometimes it works"; "it was because I was in the Map Journal instead of the
--original Journal"). 1 leaves room for one embed inside the previewed page and
--still stops a hover card nesting as deeply as a journal page can.
function BubbleDocument:Render(args)
    local doc = self:GetMarkdownDocument()
    if doc == nil then
        return nil
    end
    return CustomDocument.CreateEmbeddablePanel(doc, { embedDepth = 1 })
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

--options (all optional): halign -- which side of the element the preview
--tooltip opens on ("right" default; the title-bar search passes "left"
--because its popup hugs the right screen edge).
function CustomDocument.PreviewLink(element, link, options)
    options = options or {}
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
            ---@cast content CustomDocument
            panel = content:Render{summary = nil}
            if panel == nil then
                gui.Tooltip(content:PreviewDescription())(element)
            end
        else
            --the only other table ResolveLink returns (PDF assets are userdata).
            ---@cast content PDFFragment
            panel = content:Render{}
        end

        if panel ~= nil then
            element.tooltip = gui.TooltipFrame(panel, {
                interactable = false,
                halign = options.halign or "right",
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

            local embedDoc = content
            local embedPanel = content:DisplayPanel{
                height = "auto",
                vscroll = false,
                hpad = 0,
                hmargin = 0,
                embedDepth = (args.embedDepth or 0) + 1,
                hostPageColor = args.hostPageColor,
            }

            return gui.Panel{
                width = "100%",
                height = "auto",
                valign = "top",
                margin = 0,
                pad = 0,

                --Seeded from the document as it was embedded, so the host's first
                --refreshGame does not re-render an embed that has not changed.
                data = { embedUpdateId = embedDoc.updateid },

                embedPanel,

                savedoc = function(element)
                    element:HaltEventPropagation()
                end,

                --The host's refreshDocument carries the HOST's document, and
                --MarkdownDocument.DisplayPanel's handler does `self = doc` -- letting it
                --through would render the host's text inside the embed. But halting alone
                --cut the embed off from every refresh, leaving it stale (and its rich tags
                --without a refreshTag) until the host was reopened. Halt, then re-dispatch
                --a refresh carrying the embedded document instead.
                refreshDocument = function(element)
                    element:HaltEventPropagation()

                    --Re-read by id: a cloud update replaces the table row, so the object
                    --captured when the embed was built can be stale. Falls back to it if
                    --the row is gone (document deleted while the host is open).
                    local fresh = (dmhub.GetTable(CustomDocument.tableName) or {})[embedDoc.id] or embedDoc

                    --Upload() stamps a new updateid on every save, so this re-renders
                    --only on a real change -- refreshGame fires far more often than embeds
                    --change, and a host can hold several of them.
                    if element.data.embedUpdateId == fresh.updateid then
                        return
                    end

                    element.data.embedUpdateId = fresh.updateid
                    embedPanel:FireEventTree("refreshDocument", fresh)
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

    --no indexes option, so every group is a plain string.
    local matchPrefix = regex.MatchGroups(link, "^(?<prefix>[^:]+):(?<rest>.+)$") --[[@as table<string, string>?]]
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

    --"journal:<id>": any journal entry (document, PDF, image or PDF bookmark)
    --by id, as written by dropping an entry into a document. The id is read
    --from the original text because PDF and image ids are case-sensitive.
    if string.starts_with(link, "journal:") then
        return CustomDocument.FindJournalEntry(string.sub(original_link, 9))
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

    --"windows" a link can name: dockable panels first (most of them live
    --there now), then the launchable dialogs that remain. Both include
    --filtered items: a by-name lookup must find them anyway, and running the
    --menu filters from here recursed (EotW's Test Encounter filter loads the
    --map script, whose includes resolve through this function) until it crashed.
    for _,items in ipairs({DockablePanel.GetMenuItems(true, true), LaunchablePanel.GetMenuItems(true)}) do
        for _,item in ipairs(items) do
            if item.name ~= nil and link == string.lower(item.name) then
                return CommandDocument.new{
                    command = item.name,
                }
            end
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
        --RenderToMarkdown is nil only for what IsRenderable just rejected.
        ---@cast doc -nil

        doc:ShowDocument()
    else
        GameHud.instance:ViewCompendiumEntryModal(node)
    end
end

--- Finds a journal entry by id, whatever kind it is. Documents, PDFs, images
--- and PDF bookmarks each live in their own table, but their ids are guids,
--- so one id names one entry. Pass the result to CustomDocument.OpenContent
--- to open it; its nodeType says which kind it is ("custom", "negotiation",
--- "pdf", "image" or "pdffragment").
--- @param id string
--- @return any|nil entry nil when there is no such entry, or it was deleted.
function CustomDocument.FindJournalEntry(id)
    if type(id) ~= "string" or id == "" then
        return nil
    end
    local doc = (dmhub.GetTable(CustomDocument.tableName) or {})[id]
    if doc ~= nil then
        if doc.hidden then
            return nil
        end
        return doc
    end
    local pdf = (assets.pdfDocumentsTable or {})[id]
    if pdf ~= nil then
        if pdf.hidden then
            return nil
        end
        return pdf
    end
    local image = ((assets.imagesByTypeTable or {}).Document or {})[id]
    if image ~= nil then
        if image.hidden then
            return nil
        end
        return image
    end
    local fragment = (dmhub.GetTable(PDFFragment.tableName) or {})[id]
    if fragment ~= nil and not fragment.hidden then
        return fragment
    end
    return nil
end

local g_journalKindNames = {
    custom = "Journal Document",
    negotiation = "Negotiation",
    pdf = "PDF",
    image = "Image",
    pdffragment = "PDF Bookmark",
}

--- What kind of journal entry this is, for people ("PDF", "Image", ...).
--- @param entry any a CustomDocument.FindJournalEntry result
--- @return string
function CustomDocument.JournalEntryKindName(entry)
    return g_journalKindNames[entry.nodeType] or "Journal Entry"
end

--- The glyph the journal shows beside the entry.
--- @param entry any a CustomDocument.FindJournalEntry result
--- @return string
function CustomDocument.JournalEntryIcon(entry)
    local nodeType = entry.nodeType
    if nodeType == "pdf" then
        return "phosphor/file-pdf.png"
    elseif nodeType == "image" then
        return "phosphor/image.png"
    elseif nodeType == "pdffragment" then
        return "phosphor/bookmark-simple.png"
    end
    local icon = nil
    pcall(function() icon = CustomDocument.DocTypeIcon(entry) end)
    return icon or "phosphor/file-text.png"
end

--- The picture that stands for an entry, and its height over width: a PDF's
--- cover, an image, or a bookmark's page area. nil for a document.
--- @param entry any a CustomDocument.FindJournalEntry result
--- @return string|nil image
--- @return number|nil aspect
function CustomDocument.JournalEntryPicture(entry)
    local nodeType = entry.nodeType
    if nodeType == "pdf" then
        local aspect = 11 / 8.5
        local summary = entry.doc.summary
        if summary ~= nil and tonumber(summary.pageWidth) ~= nil and tonumber(summary.pageHeight) ~= nil and summary.pageWidth > 0 then
            aspect = summary.pageHeight / summary.pageWidth
        end
        return entry.doc:GetPageThumbnailId(0), aspect
    elseif nodeType == "image" then
        local w = tonumber(entry.width) or 1
        local h = tonumber(entry.height) or 1
        return entry.id, h / math.max(1, w)
    elseif nodeType == "pdffragment" then
        local area = entry.area
        local image = string.format("#PDF-Fragment:%s|%d,%f,%f,%f,%f", entry.refid, entry.page, area[1], area[2], area[3], area[4])
        return image, entry.height / math.max(1, entry.width)
    end
    return nil, nil
end

--- The icon rail key for a shortcut to a journal entry. A document uses the
--- journal's own "doc:<id>" shortcut (the one a journal row drag makes), so
--- the two gestures never put the same document on the rail twice; PDFs,
--- images and bookmarks use the "journal:<id>" entry type registered below.
--- @param entryid string
--- @return string
function CustomDocument.JournalRailKey(entryid)
    if (dmhub.GetTable(CustomDocument.tableName) or {})[entryid] ~= nil then
        return "doc:" .. entryid
    end
    return "journal:" .. entryid
end

local PREVIEW_WIDTH = 380
local PREVIEW_MAX_HEIGHT = 320

--- Shows a hover preview of a journal entry as element's tooltip: its name
--- and kind over a glimpse of it -- the top of a document as it reads, or a
--- PDF's cover, an image, a bookmark's page area. Call from a hover handler.
--- options (all optional): halign, valign -- where the tooltip opens
--- (gui.TooltipFrame's defaults: centred, below); hint -- the footer line.
--- @param element Panel
--- @param entryid string
--- @param options nil|{halign: string?, valign: string?, hint: string?}
function CustomDocument.ShowJournalPreview(element, entryid, options)
    options = options or {}
    local entry = CustomDocument.FindJournalEntry(entryid)
    if entry == nil then
        return
    end

    local body = nil
    --a tall picture narrows the whole card, so no dead space beside it.
    local width = PREVIEW_WIDTH
    local picture, aspect = CustomDocument.JournalEntryPicture(entry)
    if picture ~= nil then
        aspect = math.max(0.3, math.min(2, aspect or 1))
        local w = PREVIEW_WIDTH
        local h = math.floor(w * aspect)
        if h > PREVIEW_MAX_HEIGHT then
            w = math.floor(PREVIEW_MAX_HEIGHT / aspect)
            h = PREVIEW_MAX_HEIGHT
        end
        width = math.max(220, w)
        body = gui.Panel{
            bgimage = picture,
            bgcolor = "white",
            width = w,
            height = h,
            halign = "left",
            cornerRadius = 4,
        }
    else
        --the document as it reads, cut off at the preview's height. pcall:
        --a document type's read panel is its own code, and a preview that
        --fails should just not show its body.
        local readPanel = nil
        pcall(function()
            readPanel = entry:DisplayPanel{
                width = "100%",
                height = "auto",
                vscroll = false,
            }
        end)
        if readPanel ~= nil then
            --clip masks with the bgimage (clipHidden: not drawn), and only
            --a fixed height clips, so the box starts at the cap and shrinks
            --to a short document once it has been laid out.
            local page = readPanel --[[@as Panel]]
            body = gui.Panel{
                width = PREVIEW_WIDTH,
                height = PREVIEW_MAX_HEIGHT,
                valign = "top",
                bgimage = "panels/square.png",
                clip = true,
                clipHidden = true,
                flow = "vertical",
                page,
                thinkTime = 0.05,
                think = function(element)
                    local h = page.renderedHeight
                    if page.valid and h ~= nil and h > 0 then
                        element.selfStyle.height = math.min(PREVIEW_MAX_HEIGHT, h)
                    end
                end,
            }
        end
    end

    --- @type Panel[]
    local children = {
        gui.Label{
            text = entry.description or "",
            bold = true,
            fontSize = 16,
            color = "#f2ede1",
            width = "100%",
            height = "auto",
            textWrap = false,
            textOverflow = "ellipsis",
        },
        gui.Label{
            text = CustomDocument.JournalEntryKindName(entry),
            fontSize = 12,
            color = "#bdb3a4",
            width = "100%",
            height = "auto",
            bmargin = 6,
        },
    }
    if body ~= nil then
        children[#children+1] = body
    end
    children[#children+1] = gui.Label{
        text = options.hint or "Click to open",
        fontSize = 12,
        color = "#bdb3a4",
        width = "100%",
        height = "auto",
        tmargin = 6,
    }
    local content = gui.Panel{
        flow = "vertical",
        width = width,
        height = "auto",
        children = children,
    }
    local tooltip = gui.TooltipFrame(content, {
        interactable = false,
        halign = options.halign,
        valign = options.valign,
    })
    element.tooltip = tooltip
    tooltip:MakeNonInteractiveRecursive()
end

--Icon rail shortcuts to journal entries the "doc:<id>" shortcut cannot
--hold: PDFs, images and PDF bookmarks, which live outside the
--CustomDocument table ("journal:<entryid>"; see RailEntryTypes in
--DocumentSystem.lua). Made by dragging a tabletop item onto a rail.
RailEntryTypes = rawget(_G, "RailEntryTypes") or {}
RailEntryTypes.journal = {
    available = function(id)
        return CustomDocument.FindJournalEntry(id) ~= nil
    end,
    name = function(id)
        local entry = CustomDocument.FindJournalEntry(id)
        return (entry ~= nil and entry.description) or "Journal Entry"
    end,
    icon = function(id)
        local entry = CustomDocument.FindJournalEntry(id)
        if entry == nil then
            return "phosphor/file-text.png"
        end
        return CustomDocument.JournalEntryIcon(entry)
    end,
    --a picture taller than it is wide (a PDF's cover) gets two slots, so
    --the button can show it at its own shape.
    span = function(id)
        local entry = CustomDocument.FindJournalEntry(id)
        if entry == nil then
            return 1
        end
        local picture, aspect = CustomDocument.JournalEntryPicture(entry)
        if picture ~= nil and (aspect or 1) > 1.1 then
            return 2
        end
        return 1
    end,
    --a cover gets a little more width than the rail, enough to fill the
    --two-slot height at its page shape (the rail caps how wide).
    width = function(id, h)
        local entry = CustomDocument.FindJournalEntry(id)
        if entry == nil then
            return nil
        end
        local picture, aspect = CustomDocument.JournalEntryPicture(entry)
        if picture == nil or (aspect or 1) <= 1.1 then
            return nil
        end
        local inset = 2
        return (h - inset * 2) / aspect + inset * 2
    end,
    --the picture itself, as large as the button allows with its shape kept.
    face = function(id, w, h)
        local entry = CustomDocument.FindJournalEntry(id)
        if entry == nil then
            return nil
        end
        local picture, aspect = CustomDocument.JournalEntryPicture(entry)
        if picture == nil then
            return nil
        end
        aspect = aspect or 1
        local inset = 2
        local pw = w - inset * 2
        local ph = pw * aspect
        if ph > h - inset * 2 then
            ph = h - inset * 2
            pw = ph / aspect
        end
        return gui.Panel{
            bgimage = picture,
            bgcolor = "white",
            width = math.floor(pw),
            height = math.floor(ph),
            halign = "center",
            valign = "center",
            cornerRadius = 3,
            interactable = false,
        }
    end,
    activate = function(id, element)
        CustomDocument.OpenContent(CustomDocument.FindJournalEntry(id))
    end,
    hover = function(id, element)
        CustomDocument.ShowJournalPreview(element, id, CustomDocument.RailPreviewPlacement(element))
    end,
    menu = function(id, element)
        local entries = {
            {
                text = "Open",
                click = function()
                    element.popup = nil
                    CustomDocument.OpenContent(CustomDocument.FindJournalEntry(id))
                end,
            },
        }
        --back off the rail, as the table item it was docked from.
        if rawget(_G, "Tabletop") ~= nil and Tabletop.CanUndockDocItem ~= nil and Tabletop.CanUndockDocItem(id) then
            entries[#entries+1] = {
                text = "Move to the table",
                click = function()
                    element.popup = nil
                    Tabletop.UndockDocItem(id, "journal:" .. id, element)
                end,
            }
        end
        return entries
    end,
    onRemove = function(id)
    end,
}

--- Where a rail button's preview opens: beside the button, on the map side
--- of whichever rail it is on.
--- @param element Panel the rail button
--- @return {halign: string?, valign: string?, hint: string?}
function CustomDocument.RailPreviewPlacement(element)
    local rail = element:FindParentWithClass("iconRail")
    local side = nil
    if rail ~= nil then
        pcall(function() side = rail.data.side end)
    end
    return {halign = cond(side == "right", "left", "right"), valign = "center"}
end

--- @class CustomDocumentRef: GameType
--- @field new fun(o?: table): CustomDocumentRef
CustomDocumentRef = RegisterGameType("CustomDocumentRef")

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
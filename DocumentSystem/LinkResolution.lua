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

    local results = {}

    local docs = assets.pdfDocumentsTable
    for k, doc in pairs(docs or {}) do
        if (not doc.hidden) and (isDM or not doc.hiddenFromPlayers) then
            if string.find(string.lower(doc.description), search, 1, true) then
                local link = "pdf:" .. k
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
            local link = "pdf:" .. k
            results[#results+1] = {
                link = link,
                name = doc.description,
                type = "PDF Fragment",
            }
        end
    end

    local customDocs = dmhub.GetTable(CustomDocument.tableName) or {}
    for k,doc in unhidden_pairs(customDocs) do
        if string.find(string.lower(doc.description), search, 1, true) or doc:MatchesSearch(search) then
            local link = "document:" .. k
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
                local link = string.format("map:%s", map.id)
                results[#results+1] = {
                    link = link,
                    name = map.description,
                    type = "Map",
                }
            end
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
        local match = regex.MatchGroups(link, "^pdf:(?<docid>[^:]+?)(?<page>:[0-9a-zA-Z]+)?$")
        if match ~= nil then
            local docid = match.docid
            local docs = assets.pdfDocumentsTable
            local fragments = dmhub.GetTable(PDFFragment.tableName) or {}
            if match.page ~= nil and docs[docid] ~= nil then
                return PDFDeepLink.new{
                    docid = docid,
                    page = string.sub(match.page, 2),
                }
            elseif match.page ~= nil then
                local docidLower = string.lower(docid)
                for k,doc in pairs(docs) do
                    if string.lower(doc.description) == docidLower then
                        local pageNum = string.sub(match.page, 2)
                        return PDFDeepLink.new{
                            docid = k,
                            page = pageNum,
                        }
                    end 
                end
            end
            local doc = docs[docid] or fragments[docid]
            return doc
        end
    end

    if string.starts_with(link, "document:") then
        local docid = string.sub(link, 10)
        local customDocs = dmhub.GetTable(CustomDocument.tableName) or {}
        local doc = customDocs[docid]
        return doc
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

    local doc = dmhub.GetTable(CustomDocument.tableName or {})[self.docid]
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
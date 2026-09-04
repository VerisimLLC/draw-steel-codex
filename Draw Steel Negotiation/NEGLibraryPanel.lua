local mod = dmhub.GetModLoading()

--- The list of prepared negotiations, down the left of the Director's window.
NEGLibraryPanel = RegisterGameType("NEGLibraryPanel")

--- Rows and headers advertise themselves with one class; the theme already
--- paints "drag-target-hover" with an accent border and fill, so a drop target
--- lights up without any styling here.
local DROP_CLASS = "negDropTarget"

--- The class the panel root wears so a row can find its controller.
local ROOT_CLASS = "negLibrary"

--- @param def NEGDefinition
--- @param index number
--- @param selectedId string|nil
--- @param onSelect fun(defid: string)
--- @param indent number
--- @return Panel
local function CreateRow(def, index, selectedId, onSelect, indent)
    local defid = def:GetID()

    --Exactly one negotiation is in play at a time, so this one is either it or
    --it waits until that one is done.
    local running = NEGRun.ActiveFor(defid)
    local otherRunning = nil
    if running == nil and NEGRun.Active() ~= nil then
        otherRunning = NEGRun.Active()
    end

    local playTooltip = "Start this negotiation"
    if otherRunning ~= nil then
        playTooltip = string.format("%s is running. Finish it first.",
            otherRunning:Name() ~= "" and otherRunning:Name() or "A negotiation")
    elseif running ~= nil then
        playTooltip = "This negotiation is running."
    end

    local configured = def:IsConfigured()

    return gui.Panel{
        classes = {
            "row",
            "hoverable",
            cond(index % 2 == 1, "oddRow", "evenRow"),
            cond(defid == selectedId, "selected"),
        },
        width = cond(indent > 0, string.format("100%%-%d", indent), "100%"),
        height = 32,
        flow = "horizontal",
        halign = "right",
        valign = "top",

        draggable = true,
        canDragOnto = function(element, target)
            return target ~= nil and target:HasClass(DROP_CLASS)
        end,

        beginDrag = function(element)
            local controller = element:FindParentWithClass(ROOT_CLASS)
            if controller ~= nil then
                controller:FireEventTree("setDragging", true)
            end
        end,

        drag = function(element, target)
            local controller = element:FindParentWithClass(ROOT_CLASS)
            if controller ~= nil then
                controller:FireEventTree("setDragging", false)
            end
            if target ~= nil then
                NEGDefinition.SetFolder(defid, target.data.folderId or "")
            end
        end,

        click = function()
            onSelect(defid)
        end,

        --Takes everything the marker and the controls leave, so a name has the
        --room and the glyphs sit over against them on the right.
        gui.Label{
            classes = { "sizeS" },
            width = "100% available",
            height = "auto",
            lmargin = 8,
            halign = "left",
            valign = "center",
            text = def.name or "",
        },

        gui.Panel{
            classes = { cond(configured, "bgSuccess", "bgFgMuted") },
            width = 16,
            height = 16,
            halign = "left",
            valign = "center",
            bgimage = NEGConstants.iconConfigured,
            hover = gui.Tooltip(cond(configured,
                "Ready to run",
                "Needs an NPC, two motivations and a pitfall")),
        },

        --Sized to the buttons rather than a share of the row, so the name gets
        --back what a fixed share was over-reserving.
        gui.Panel{
            width = "auto",
            height = "100%",
            flow = "horizontal",
            halign = "right",
            valign = "center",

            gui.Button{
                classes = { "sizeXs" },
                icon = NEGConstants.iconPlay,
                halign = "right",
                valign = "center",
                hmargin = 2,
                interactable = otherRunning == nil and running == nil,
                hover = gui.Tooltip(playTooltip),
                click = function()
                    onSelect(defid)
                    NEGRun.BeginSetup(defid)
                end,
            },

            gui.Button{
                classes = { "sizeXs" },
                icon = NEGConstants.iconGear,
                halign = "right",
                valign = "center",
                hmargin = 2,
                hover = gui.Tooltip("More"),
                click = function(element)
                    element.popup = gui.ContextMenu{
                        entries = {
                            {
                                text = "Duplicate",
                                click = function()
                                    element.popup = nil
                                    NEGDefinition.Duplicate(defid)
                                end,
                            },
                            {
                                text = "Delete",
                                click = function()
                                    element.popup = nil
                                    NEGDefinition.Delete(defid)
                                end,
                            },
                        },
                    }
                end,
            },
        },
    }
end

--- Somewhere to drop a negotiation that should leave its folder. Collapsed
--- until a drag begins, so it costs nothing and shows nothing the rest of the
--- time.
--- @return Panel
local function CreateRootDropRow()
    return gui.Panel{
        classes = { DROP_CLASS, "bordered", "collapsed" },
        width = "100%",
        height = 22,
        flow = "horizontal",
        valign = "top",
        vmargin = 3,
        dragTarget = true,

        data = { folderId = "" },

        setDragging = function(element, dragging)
            element:SetClass("collapsed", not dragging)
        end,

        gui.Label{
            classes = { "sizeXs", "noBold", "fgMuted" },
            width = "100%",
            height = "auto",
            halign = "center",
            valign = "center",
            textAlignment = "center",
            text = "(root)",
        },
    }
end

--- A folder's header: its name, how many negotiations it holds, and the drop
--- target that files them into it.
--- @param folderId string
--- @param label string
--- @param onRebuild fun()
--- @param count number
--- @return Panel
local function CreateFolderHeader(folderId, label, onRebuild, count)
    --Collapse is a view preference, so it lives per client rather than in the
    --shared document where it would follow everyone around.
    local prefKey = string.format("negfolder:%s:%s", dmhub.gameid, folderId)
    local closed = dmhub.GetPref(prefKey) == true

    --The theme's "triangle" class, which gui.ExpandoArrow carries, owns the
    --glyph, colour, size, margin and hover. Only the open state and the
    --handler belong here.
    local arrowArgs = {}
    if not closed then
        arrowArgs.classes = { "expanded" }
    end
    arrowArgs.click = function(element)
        local nowExpanded = not element:HasClass("expanded")
        element:SetClass("expanded", nowExpanded)
        dmhub.SetPref(prefKey, not nowExpanded)
        onRebuild()
    end

    return gui.Panel{
        classes = { DROP_CLASS },
        width = "100%",
        height = 26,
        flow = "horizontal",
        valign = "top",
        tmargin = 6,
        bgimage = "panels/square.png",
        dragTarget = true,

        data = { folderId = folderId },

        rightClick = function(element)
            element.popup = gui.ContextMenu{
                entries = {
                    {
                        text = "Delete Folder",
                        click = function()
                            element.popup = nil
                            NEGDefinition.DeleteFolder(folderId)
                        end,
                    },
                },
            }
        end,

        gui.ExpandoArrow(arrowArgs),

        gui.Label{
            classes = { "tableLabel", "sizeXs" },
            width = "70%",
            height = "auto",
            halign = "left",
            valign = "center",
            lmargin = 4,
            editable = true,
            characterLimit = 32,
            text = label,
            change = function(element)
                local name = trim(element.text or "")
                if name == "" then
                    element.text = label
                    return
                end
                NEGDefinition.RenameFolder(folderId, name)
            end,
        },

        gui.Label{
            classes = { "sizeXs", "noBold", "fgMuted" },
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
            rmargin = 8,
            text = tostring(count),
        },
    }
end

--- The list half of the Director's window.
--- @param onSelect fun(defid: string|nil)
--- @param onImport fun()
--- @return Panel
function NEGLibraryPanel.Create(onSelect, onImport)
    local m_selected = nil

    --The only scroller in this column, and it is the bordered box itself, so
    --the bar rides the list's own right edge. Wrapping another scroller around
    --it puts a second bar in the gutter and leaves neither on the list.
    local listPanel = gui.Panel{
        classes = { "bordered" },
        pad = 4,
        width = "100%",
        height = "100%-44",
        flow = "vertical",
        valign = "top",
        vscroll = true,
    }

    local resultPanel
    resultPanel = gui.Panel{
        classes = { ROOT_CLASS },
        width = "100%",
        height = "100%",
        flow = "vertical",
        valign = "top",

        monitorGame = NEGDefinition.DocPath(),
        refreshGame = function(element)
            element:FireEvent("rebuild")
        end,

        --- Select a negotiation and tell the editor about it.
        select = function(element, defid)
            m_selected = defid
            onSelect(defid)
            element:FireEvent("rebuild")
        end,

        rebuild = function(element)
            local defs = NEGDefinition.GetAll()

            --The selection can vanish under us when a negotiation is deleted
            --here or on another client.
            if m_selected ~= nil and NEGDefinition.GetByID(m_selected) == nil then
                m_selected = nil
                onSelect(nil)
            end

            local function Select(defid)
                element:FireEvent("select", defid)
            end
            local function Rebuild()
                element:FireEvent("rebuild")
            end

            local byFolder = {}
            for _, def in ipairs(defs) do
                local key = def:try_get("folderId", "")
                byFolder[key] = byFolder[key] or {}
                local bucket = byFolder[key]
                bucket[#bucket + 1] = def
            end

            local children = {}
            local index = 0

            local function AddRows(bucket, indent)
                for _, def in ipairs(bucket or {}) do
                    index = index + 1
                    children[#children + 1] = CreateRow(def, index, m_selected, Select, indent)
                end
            end

            children[#children + 1] = CreateRootDropRow()
            AddRows(byFolder[""], 0)

            for _, folder in ipairs(NEGDefinition.GetFolders()) do
                local bucket = byFolder[folder.id] or {}
                children[#children + 1] =
                    CreateFolderHeader(folder.id, folder.name, Rebuild, #bucket)

                local prefKey = string.format("negfolder:%s:%s", dmhub.gameid, folder.id)
                if dmhub.GetPref(prefKey) ~= true then
                    AddRows(bucket, 16)
                end
            end

            --Inside the bordered list, so "nothing here yet" sits where the
            --rows would be rather than adrift under the box.
            if #defs == 0 then
                children[#children + 1] = gui.Label{
                    classes = { "sizeS", "fgMuted" },
                    width = "100%",
                    height = "auto",
                    halign = "center",
                    valign = "top",
                    vmargin = 16,
                    textAlignment = "center",
                    text = "No negotiations yet.",
                }
            end

            listPanel.children = children
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        --Rows show run state as well as library state, and a panel can only
        --monitor one path.
        gui.Panel{
            width = 0,
            height = 0,
            monitorGame = NEGRun.DocPath(),
            refreshGame = function(element)
                local controller = element:FindParentWithClass(ROOT_CLASS)
                if controller ~= nil then
                    controller:FireEvent("rebuild")
                end
            end,
        },

        listPanel,

        gui.Panel{
            width = "100%",
            height = 40,
            flow = "horizontal",
            valign = "bottom",

            gui.Button{
                classes = { "sizeS" },
                icon = NEGConstants.iconImport,
                width = 26,
                height = 26,
                halign = "right",
                valign = "center",
                hmargin = 4,
                hover = gui.Tooltip("Import a negotiation"),
                click = function()
                    onImport()
                end,
            },

            gui.Button{
                classes = { "sizeS" },
                icon = NEGConstants.iconNewFolder,
                width = 26,
                height = 26,
                halign = "right",
                valign = "center",
                hmargin = 4,
                hover = gui.Tooltip("New folder"),
                click = function()
                    NEGDefinition.CreateFolder()
                end,
            },

            gui.Button{
                classes = { "addButton", "sizeS" },
                halign = "right",
                valign = "center",
                hover = gui.Tooltip("Prepare a new negotiation"),
                click = function(element)
                    local defid = NEGDefinition.CreateInLibrary()
                    local controller = element:FindParentWithClass(ROOT_CLASS)
                    if controller ~= nil then
                        controller:FireEvent("select", defid)
                    end
                end,
            },
        },
    }

    return resultPanel
end

local mod = dmhub.GetModLoading()

--Scenes: the Director's library of scenes, arranged in folders. A scene is an
--image or video with a name, an optional caption and subtitle drawn over it,
--an art credit and a sound cue. Scenes are dragged from the Scenes panel onto
--the tabletop, where each opens in a window that can be shared with the
--players' tables (Tabletop.lua). A maximized scene window (or a [[scene]]
--journal tag) puts the Hide / Players / All control in the title bar, which
--shows the scene full screen through the fullscreen display
--(FullscreenDisplay.lua) -- the same display Game Controls' art picker uses.
--
--The library is the "scenes" shared document:
--  data.scenes[id]   {name, image, credit, caption, subtitle, sound, folder}
--  data.folders[id]  {name, parent}
--folder and parent are a folder id, or nil for the top level. image is an
--image asset id from the "coverart" library (a still or a video), sound an
--audio asset id.

Scenes = rawget(_G, "Scenes") or {}

local DOC = "scenes"

local function Doc()
    return mod:GetDocumentSnapshot(DOC)
end

--- The path to monitor (monitorGame) for library changes.
--- @return string
function Scenes.DocPath()
    return mod:GetDocumentPath(DOC)
end

local function DocTable(key)
    local t = Doc().data[key]
    if type(t) ~= "table" then
        return {}
    end
    return t
end

--- Every scene in the library, id -> scene.
--- @return table<string, table>
function Scenes.All()
    return DocTable("scenes")
end

--- Every folder in the library, id -> folder.
--- @return table<string, table>
function Scenes.Folders()
    return DocTable("folders")
end

--- @param id any
--- @return nil|table
function Scenes.Get(id)
    if type(id) ~= "string" then
        return nil
    end
    local scene = DocTable("scenes")[id]
    if type(scene) ~= "table" then
        return nil
    end
    return scene
end

--- @param id any
--- @return nil|table
function Scenes.GetFolder(id)
    if type(id) ~= "string" then
        return nil
    end
    local folder = DocTable("folders")[id]
    if type(folder) ~= "table" then
        return nil
    end
    return folder
end

--- The scene's name for display.
--- @param id any
--- @return string
function Scenes.Name(id)
    local scene = Scenes.Get(id)
    if scene == nil then
        return "(missing scene)"
    end
    if type(scene.name) ~= "string" or scene.name == "" then
        return "Untitled Scene"
    end
    return scene.name
end

--One write to the library; fn(data) makes the change.
local function Change(description, fn)
    local doc = Doc()
    doc:BeginChange()
    if type(doc.data.scenes) ~= "table" then
        doc.data.scenes = {}
    end
    if type(doc.data.folders) ~= "table" then
        doc.data.folders = {}
    end
    fn(doc.data)
    doc:CompleteChange(description)
end

--- Adds a scene to the library and returns its id.
--- @param fields nil|table name, image, credit, caption, subtitle, sound, folder
--- @return string
function Scenes.Create(fields)
    local id = dmhub.GenerateGuid()
    Change("Create scene", function(data)
        local scene = {name = "New Scene"}
        for k, v in pairs(fields or {}) do
            scene[k] = v
        end
        data.scenes[id] = scene
    end)
    return id
end

--- Changes some of a scene's fields; false clears a field. The scene on show
--- (if it is this one) follows the edit.
--- @param id string
--- @param fields table
function Scenes.Update(id, fields)
    if Scenes.Get(id) == nil then
        return
    end
    Change("Edit scene", function(data)
        local scene = data.scenes[id]
        if type(scene) ~= "table" then
            return
        end
        for k, v in pairs(fields) do
            if v == false then
                scene[k] = nil
            else
                scene[k] = v
            end
        end
    end)
    if Scenes.PresentedId() == id then
        Scenes.RefreshPresentation()
    end
end

--- Removes a scene. If it is on show, the players stop seeing it.
--- @param id string
function Scenes.Delete(id)
    if Scenes.Get(id) == nil then
        return
    end
    if Scenes.PresentedId() == id then
        Scenes.Present(id, false)
    end
    Change("Delete scene", function(data)
        data.scenes[id] = nil
    end)
end

--- A copy of a scene, beside it in the same folder. Returns the new id.
--- @param id string
--- @return nil|string
function Scenes.Duplicate(id)
    local scene = Scenes.Get(id)
    if scene == nil then
        return nil
    end
    local fields = {}
    for k, v in pairs(scene) do
        fields[k] = v
    end
    fields.name = Scenes.Name(id) .. " (copy)"
    return Scenes.Create(fields)
end

--- @param name string
--- @param parent nil|string
--- @return string
function Scenes.CreateFolder(name, parent)
    local id = dmhub.GenerateGuid()
    Change("Create scene folder", function(data)
        data.folders[id] = {name = name, parent = parent}
    end)
    return id
end

--- @param id string
--- @param name string
function Scenes.RenameFolder(id, name)
    if Scenes.GetFolder(id) == nil then
        return
    end
    Change("Rename scene folder", function(data)
        data.folders[id].name = name
    end)
end

--- Deletes a folder; what was in it moves up into its parent.
--- @param id string
function Scenes.DeleteFolder(id)
    local folder = Scenes.GetFolder(id)
    if folder == nil then
        return
    end
    local parent = folder.parent
    Change("Delete scene folder", function(data)
        for _, scene in pairs(data.scenes) do
            if type(scene) == "table" and scene.folder == id then
                scene.folder = parent
            end
        end
        for _, other in pairs(data.folders) do
            if type(other) == "table" and other.parent == id then
                other.parent = parent
            end
        end
        data.folders[id] = nil
    end)
end

--- Whether folder id is ancestor, or inside it at any depth.
--- @param id nil|string
--- @param ancestor string
--- @return boolean
function Scenes.FolderIsInside(id, ancestor)
    local count = 0
    while id ~= nil and count < 64 do
        if id == ancestor then
            return true
        end
        local folder = Scenes.GetFolder(id)
        id = folder ~= nil and folder.parent or nil
        count = count + 1
    end
    return false
end

--- Moves a scene into a folder (nil: the top level).
--- @param id string
--- @param folder nil|string
function Scenes.MoveScene(id, folder)
    local scene = Scenes.Get(id)
    if scene == nil or scene.folder == folder then
        return
    end
    Change("Move scene", function(data)
        data.scenes[id].folder = folder
    end)
end

--- Moves a folder into another (nil: the top level). A folder cannot go
--- inside itself.
--- @param id string
--- @param parent nil|string
function Scenes.MoveFolder(id, parent)
    local folder = Scenes.GetFolder(id)
    if folder == nil or folder.parent == parent or (parent ~= nil and Scenes.FolderIsInside(parent, id)) then
        return
    end
    Change("Move scene folder", function(data)
        data.folders[id].parent = parent
    end)
end

----------------------------------------------------------------------
--Showing a scene to the players: it becomes the fullscreen display's
--picture (the "fullscreen_display" document in FullscreenDisplay.lua):
--  show       false, true (players) or "all" (the Director too)
--  belowui    under the game's UI rather than over it
--  sceneid    the library scene on show (false for a plain picture)
--  coverart, coverartCredit, caption, subtitle   copied from the scene

local function DisplayDoc()
    return FullscreenDisplay.GetDocumentSnapshot()
end

--- The library scene on show, or nil.
--- @return nil|string
function Scenes.PresentedId()
    local data = DisplayDoc().data
    if data == nil or not data.show or type(data.sceneid) ~= "string" then
        return nil
    end
    return data.sceneid
end

--- What a scene's Hide / Players / All control shows: false, true or "all".
--- @param id string
--- @return boolean|string
function Scenes.ShowState(id)
    local data = DisplayDoc().data
    if data ~= nil and data.show and data.sceneid == id then
        return data.show
    end
    return false
end

--- @return boolean
function Scenes.IsBelowUI()
    local data = DisplayDoc().data
    return data ~= nil and data.belowui == true
end

--- Whether the display draws under the game's UI or over it.
--- @param value boolean
function Scenes.SetBelowUI(value)
    local doc = DisplayDoc()
    doc:BeginChange()
    doc.data.belowui = value == true
    doc:CompleteChange("Show Below UI")
end

local function CopySceneFields(data, id, scene)
    data.sceneid = id
    data.coverart = scene.image
    data.coverartCredit = scene.credit or false
    data.caption = scene.caption or false
    data.subtitle = scene.subtitle or false
end

--A scene's sound cue starts when the scene goes on show and fades when it
--goes away. audio.PlaySoundEvent reaches every client. Music goes through
--the Audio panel's own path, which fades out whatever music was playing.
local function PlayCue(scene)
    if scene == nil or type(scene.sound) ~= "string" then
        return
    end
    local asset = assets.audioTable[scene.sound]
    if asset == nil or audio.currentlyPlaying[asset.id] ~= nil then
        return
    end
    if rawget(_G, "AudioPlayBroadcastClip") ~= nil then
        AudioPlayBroadcastClip(asset)
    else
        audio.PlaySoundEvent{asset = asset}
    end
end

local function StopCue(scene, keep)
    if scene == nil or type(scene.sound) ~= "string" or scene.sound == keep then
        return
    end
    if audio.currentlyPlaying[scene.sound] ~= nil then
        audio.CrossfadeSoundEvents(scene.sound, nil, 1.5)
    end
end

--- Shows a library scene full screen (show = true for the players, "all" for
--- everyone), or stops showing it (show = false; does nothing if another
--- scene is on show). Director only.
--- @param id string
--- @param show boolean|string
function Scenes.Present(id, show)
    if not dmhub.isDM then
        return
    end
    local scene = Scenes.Get(id)
    local wasId = Scenes.PresentedId()
    if show and scene == nil then
        return
    end
    if not show and wasId ~= id then
        return
    end

    local doc = DisplayDoc()
    doc:BeginChange()
    if show then
        CopySceneFields(doc.data, id, scene)
    end
    doc.data.show = show
    doc:CompleteChange(cond(show, "Show scene", "Hide scene"))

    local nowId = nil
    if show then
        nowId = id
    end
    if wasId ~= nowId then
        local nowSound = nil
        if scene ~= nil and nowId ~= nil then
            nowSound = scene.sound
        end
        StopCue(Scenes.Get(wasId), nowSound)
        if nowId ~= nil then
            PlayCue(scene)
        end
    end
end

--- Copies the scene on show into the display again, after an edit.
function Scenes.RefreshPresentation()
    local id = Scenes.PresentedId()
    local scene = Scenes.Get(id)
    if scene == nil or not dmhub.isDM then
        return
    end
    local doc = DisplayDoc()
    doc:BeginChange()
    CopySceneFields(doc.data, id, scene)
    doc:CompleteChange("Edit scene on show")
end

----------------------------------------------------------------------
--- The {image, caption, subtitle, credit} a scene's view shows.
--- @param id string
--- @return table
function Scenes.ViewInfo(id)
    local scene = Scenes.Get(id) or {}
    return {
        image = scene.image,
        caption = scene.caption,
        subtitle = scene.subtitle,
        credit = scene.credit,
        --its cards (SceneElements.lua) are drawn over it.
        sceneid = id,
    }
end

----------------------------------------------------------------------
--The scene editor: a settings dialog that writes each change straight to
--the library.

--- @param id string
function Scenes.ShowEditor(id)
    if Scenes.Get(id) == nil then
        return
    end

    local function Field(key)
        local scene = Scenes.Get(id)
        if scene == nil then
            return nil
        end
        return scene[key]
    end

    local function TextField(label, key, placeholder)
        return gui.Panel{
            classes = {"formStackedRow"},
            vmargin = 6,
            gui.Label{
                classes = {"formStacked"},
                text = label,
            },
            gui.Input{
                classes = {"formStacked"},
                text = Field(key) or "",
                placeholderText = placeholder,
                characterLimit = 120,
                change = function(element)
                    local text = trim(element.text)
                    if key == "name" and text == "" then
                        element.text = Scenes.Name(id)
                        return
                    end
                    Scenes.Update(id, {[key] = cond(text == "", false, text)})
                end,
            },
        }
    end

    local soundEditor = gui.AudioEditor{
        width = 54,
        height = 54,
        halign = "left",
        value = Field("sound"),
        change = function(element)
            local value = element.value
            if value == nil or value == "" then
                Scenes.Update(id, {sound = false})
            else
                Scenes.Update(id, {sound = value})
            end
        end,
    }

    local dialogPanel = gui.Panel{
        classes = {"framedPanel"},
        width = 480,
        height = "auto",
        styles = ThemeEngine.GetStyles(),

        gui.Panel{
            width = "100%-48",
            height = "auto",
            halign = "center",
            valign = "top",
            flow = "vertical",
            vmargin = 24,

            gui.Label{
                classes = {"modalTitle"},
                text = "Scene",
            },

            TextField("Name:", "name", "Scene name"),

            gui.Panel{
                classes = {"formStackedRow"},
                vmargin = 6,
                gui.Label{
                    classes = {"formStacked"},
                    text = "Image or Video:",
                    linger = gui.Tooltip("A still image, or a video (it loops, muted)."),
                },
                gui.IconEditor{
                    library = "coverart",
                    classes = {"image"},
                    width = 320,
                    height = 180,
                    halign = "left",
                    allowNone = true,
                    value = Field("image"),
                    change = function(element)
                        local value = element.value
                        if value == nil or value == "" then
                            Scenes.Update(id, {image = false})
                        else
                            Scenes.Update(id, {image = value})
                        end
                    end,
                },
            },

            TextField("Caption:", "caption", "Shown over the scene (optional)"),
            TextField("Subtitle:", "subtitle", "Shown under the caption (optional)"),

            gui.Panel{
                classes = {"formStackedRow"},
                vmargin = 6,
                gui.Label{
                    classes = {"formStacked"},
                    text = "Art by:",
                    linger = gui.Tooltip("Showing the scene puts this creator's badge on it."),
                },
                gui.Dropdown{
                    width = 240,
                    options = CreatorCredit.DropdownOptions(),
                    idChosen = Field("credit") or "none",
                    change = function(element)
                        ---@cast element Dropdown
                        local credit = element.idChosen
                        Scenes.Update(id, {credit = cond(type(credit) == "string" and credit ~= "none", credit, false)})
                    end,
                },
            },

            gui.Panel{
                classes = {"formStackedRow"},
                vmargin = 6,
                gui.Label{
                    classes = {"formStacked"},
                    text = "Sound Cue:",
                    linger = gui.Tooltip("Plays for everyone when the scene is shown to the players, and fades when it is hidden."),
                },
                gui.Panel{
                    flow = "horizontal",
                    width = "auto",
                    height = "auto",
                    soundEditor,
                    gui.Button{
                        classes = {"sizeS"},
                        width = "auto",
                        valign = "center",
                        lmargin = 12,
                        text = "No Sound",
                        click = function(element)
                            Scenes.Update(id, {sound = false})
                            soundEditor.value = nil
                        end,
                    },
                },
            },

            gui.Panel{
                width = "100%",
                height = 40,
                valign = "bottom",
                vmargin = 12,
                flow = "horizontal",

                gui.Button{
                    classes = {"sizeM", "deleteButton"},
                    halign = "left",
                    text = "Delete Scene",
                    requireConfirm = true,
                    click = function(element)
                        gui.CloseModal()
                        Scenes.Delete(id)
                    end,
                },

                gui.Button{
                    classes = {"sizeM"},
                    halign = "right",
                    text = "Close",
                    escapeActivates = true,
                    escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                    click = function(element)
                        gui.CloseModal()
                    end,
                },
            },
        },
    }

    gui.ShowModal(dialogPanel)
end

--A one-field dialog for naming a folder. done(name) gets the trimmed name.
local function ShowNameDialog(title, initial, done)
    local input
    local function Finish()
        local text = trim(input.text)
        gui.CloseModal()
        if text ~= "" then
            done(text)
        end
    end
    input = gui.Input{
        classes = {"formStacked"},
        text = initial or "",
        characterLimit = 60,
        create = function(element)
            element.hasFocus = true
        end,
    }
    gui.ShowModal(gui.Panel{
        classes = {"framedPanel"},
        width = 400,
        height = "auto",
        styles = ThemeEngine.GetStyles(),
        gui.Panel{
            width = "100%-48",
            height = "auto",
            halign = "center",
            valign = "top",
            flow = "vertical",
            vmargin = 24,
            gui.Label{
                classes = {"modalTitle"},
                text = title,
            },
            gui.Panel{
                classes = {"formStackedRow"},
                vmargin = 8,
                gui.Label{
                    classes = {"formStacked"},
                    text = "Name:",
                },
                input,
            },
            gui.Panel{
                width = "100%",
                height = 40,
                vmargin = 12,
                flow = "horizontal",
                gui.Button{
                    classes = {"sizeM"},
                    halign = "left",
                    text = "Cancel",
                    escapeActivates = true,
                    escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                    click = function(element)
                        gui.CloseModal()
                    end,
                },
                gui.Button{
                    classes = {"sizeM"},
                    halign = "right",
                    text = "OK",
                    click = function(element)
                        Finish()
                    end,
                },
            },
        },
    })
end

----------------------------------------------------------------------
--The Scenes panel: the library as a folder tree. Click a scene to open it on
--the table, drag it onto the table to open it there, drag it onto a folder
--to file it. The gear (or a right-click) edits it.

--Folders the Director has collapsed, this session.
local g_collapsedFolders = {}

local INDENT = 16

--The panel's own rules, in the Maps panel's row grammar (STYLE_GUIDE.md).
local function BuildScenesStyles()
    return {
        {
            selectors = {"sceneRow"},
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = "clear",
            width = "100%",
            height = 56,
            halign = "left",
            valign = "top",
            hpad = 12,
            borderBox = true,
        },
        {
            selectors = {"sceneRow", "hover"},
            bgcolor = "@bgAlt",
            transitionTime = 0.1,
        },
        --the scene the players are looking at.
        {
            selectors = {"sceneRow", "presenting"},
            bgcolor = "@bgAlt",
            border = {x1 = 3, x2 = 0, y1 = 0, y2 = 0},
            borderColor = "@accent",
            priority = 5,
        },
        {
            selectors = {"sceneThumb"},
            width = 80,
            height = 45,
            valign = "center",
            bgcolor = "white",
            cornerRadius = 3,
        },
        {
            selectors = {"sceneThumb", "sceneThumbEmpty"},
            bgcolor = "@bgAlt",
        },
        {
            selectors = {"sceneName"},
            fontSize = 14,
            color = "@fg",
            width = "100%",
            height = "auto",
            textWrap = false,
            textOverflow = "ellipsis",
        },
        {
            selectors = {"sceneName", "parent:presenting"},
            color = "@fgStrong",
            bold = true,
        },
        {
            selectors = {"sceneSub"},
            fontSize = 11,
            color = "@fgMuted",
            width = "100%",
            height = "auto",
            textWrap = false,
            textOverflow = "ellipsis",
        },
        {
            selectors = {"scenePresentingIcon"},
            bgcolor = "@accent",
        },
        {
            selectors = {"sceneSeamLine"},
            bgcolor = "@border",
            opacity = 0.2,
            width = "100%",
            height = 1,
        },
        {
            selectors = {"sceneFolderHeader"},
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = "clear",
            width = "100%",
            height = 30,
            tmargin = 6,
            hpad = 12,
            borderBox = true,
            halign = "left",
            valign = "top",
        },
        {
            selectors = {"sceneFolderHeader", "drag-target-hover"},
            bgcolor = "@bgAlt",
            border = {x1 = 3, x2 = 0, y1 = 0, y2 = 0},
            borderColor = "@accent",
        },
        {
            selectors = {"sceneFolderLabel"},
            fontSize = 13,
            bold = true,
            color = "@fg",
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            lmargin = 6,
        },
        {
            selectors = {"sceneFolderLabel", "parent:hover"},
            color = "@fgStrong",
            transitionTime = 0.1,
        },
        {
            selectors = {"sceneFolderCount"},
            fontSize = 11,
            color = "@fgMuted",
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
        },
        {
            selectors = {"sceneFolderRule"},
            bgcolor = "@border",
            opacity = 0.35,
            width = "100%",
            height = 1,
        },
        --the strip under the list that files a dropped scene at the top level.
        {
            selectors = {"sceneRootTarget"},
            bgimage = "panels/square.png",
            bgcolor = "clear",
            width = "100%",
            height = 24,
        },
        {
            selectors = {"sceneRootTarget", "drag-target-hover"},
            bgcolor = "@bgAlt",
            border = {x1 = 0, x2 = 0, y1 = 0, y2 = 2},
            borderColor = "@accent",
        },
        {
            selectors = {"sceneEmptyText"},
            fontSize = 13,
            color = "@fgMuted",
            width = "100%-24",
            height = "auto",
            halign = "center",
            valign = "top",
            textAlignment = "center",
            vmargin = 16,
        },
        {
            selectors = {"panel", "buttonIcon", "parent:addButton"},
            bgimage = "phosphor/plus-bold.png",
            priority = 10,
        },
        {
            selectors = {"buttonIcon", "parent:settingsButton"},
            bgcolor = "@fgMuted",
            opacity = 0.5,
            priority = 10,
        },
        {
            selectors = {"buttonIcon", "parent:settingsButton", "parent:hover"},
            bgcolor = "@fg",
            opacity = 1,
            priority = 15,
            transitionTime = 0.1,
        },
    }
end

local function SortedByName(t)
    local list = {}
    for id, entry in pairs(t) do
        if type(entry) == "table" then
            list[#list+1] = {id = id, entry = entry, name = string.lower(tostring(entry.name or ""))}
        end
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.id < b.id
    end)
    return list
end

local function SceneSubtitle(scene)
    local parts = {}
    if type(scene.caption) == "string" and scene.caption ~= "" then
        parts[#parts+1] = scene.caption
    end
    if type(scene.image) == "string" and FullscreenDisplay.IsVideo(scene.image) then
        parts[#parts+1] = "Video"
    end
    if type(scene.sound) == "string" then
        parts[#parts+1] = "Sound cue"
    end
    return table.concat(parts, "  -  ")
end

--A drop target for a dragged scene or folder: a folder header, or the
--top-level strip. Its data.folderid is the folder (false for the top level).
local function DropFolder(target)
    if target == nil or not target.valid then
        return nil, false
    end
    local folderid = nil
    local ok = pcall(function()
        folderid = target.data.folderid
    end)
    if not ok or folderid == nil then
        return nil, false
    end
    if folderid == false then
        return nil, true
    end
    return folderid, true
end

local function IsSceneDropTarget(target)
    return target:HasClass("sceneFolderHeader") or target:HasClass("sceneRootTarget")
end

local function SceneRow(id, scene, depth)
    local thumb = gui.Panel{
        classes = {"sceneThumb", cond(type(scene.image) ~= "string", "sceneThumbEmpty")},
        bgimage = cond(type(scene.image) == "string", scene.image, "panels/square.png"),
        interactable = false,
    }

    local presentingIcon = gui.Panel{
        classes = {"scenePresentingIcon", "collapsed"},
        bgimage = "phosphor/eye-fill.png",
        width = 16,
        height = 16,
        valign = "center",
        rmargin = 30,
        hover = gui.Tooltip("Showing to the players"),
    }

    local function Menu(element)
        local showing = Scenes.PresentedId() == id
        local entries = {
            {
                text = "Open on Table",
                click = function()
                    element.popup = nil
                    Tabletop.OpenScene(id)
                end,
            },
            {
                text = cond(showing, "Stop Showing to Players", "Show to Players"),
                click = function()
                    element.popup = nil
                    Scenes.Present(id, cond(showing, false, true))
                end,
            },
            {
                text = "Edit Scene...",
                click = function()
                    element.popup = nil
                    Scenes.ShowEditor(id)
                end,
            },
            {
                text = "Duplicate",
                click = function()
                    element.popup = nil
                    Scenes.Duplicate(id)
                end,
            },
        }
        if scene.folder ~= nil then
            entries[#entries+1] = {
                text = "Move to Top Level",
                click = function()
                    element.popup = nil
                    Scenes.MoveScene(id, nil)
                end,
            }
        end
        entries[#entries+1] = {
            text = "Delete Scene",
            click = function()
                element.popup = nil
                Scenes.Delete(id)
            end,
        }
        element.popup = gui.ContextMenu{entries = entries}
    end

    return gui.Panel{
        classes = {"sceneRow"},
        draggable = true,
        data = {sceneid = id},
        search = function(element, text)
            local name = string.lower(Scenes.Name(id))
            element:SetClass("collapsed", text ~= "" and string.find(name, text, 1, true) == nil)
        end,
        refreshPresenting = function(element, presentedId)
            local on = presentedId == id
            element:SetClass("presenting", on)
            presentingIcon:SetClass("collapsed", not on)
        end,
        click = function(element)
            Tabletop.OpenScene(id)
        end,
        rightClick = function(element)
            Menu(element)
        end,

        canDragOnto = function(element, target)
            return IsSceneDropTarget(target)
        end,
        --over the bare table the row steps aside and the window a drop
        --there makes follows the mouse.
        dragging = function(element, target)
            ChatItemLinks.Dragging(function() return {ChatItemLinks.SceneItem(id)} end)
            if target == nil then
                Tabletop.SceneRowDragging(element, id)
            else
                Tabletop.SceneRowDragEnded(element)
            end
        end,
        drag = function(element, target)
            Tabletop.SceneRowDragEnded(element)
            --dropped on the chat: a link to the scene.
            if ChatItemLinks.Dropped() then
                return
            end
            if target == nil then
                Tabletop.SceneRowDropped(id)
                return
            end
            local folderid, ok = DropFolder(target)
            if ok then
                Scenes.MoveScene(id, folderid)
            end
        end,

        gui.Panel{
            width = depth * INDENT,
            height = 1,
            interactable = false,
        },
        thumb,
        gui.Panel{
            flow = "vertical",
            --leaves room for the thumbnail, the eye and the gear.
            width = string.format("100%%-%d", 140 + depth * INDENT),
            height = "auto",
            valign = "center",
            lmargin = 10,
            interactable = false,
            gui.Label{
                classes = {"sceneName"},
                text = Scenes.Name(id),
            },
            gui.Label{
                classes = {"sceneSub", cond(SceneSubtitle(scene) == "", "collapsed")},
                text = SceneSubtitle(scene),
            },
        },
        presentingIcon,
        gui.Button{
            classes = {"settingsButton"},
            floating = true,
            halign = "right",
            valign = "center",
            width = 16,
            height = 16,
            hmargin = 0,
            hover = gui.Tooltip("Edit scene"),
            click = function(element)
                Scenes.ShowEditor(id)
            end,
        },
    }
end

local function SeamLine()
    return gui.Panel{
        classes = {"sceneSeamLine"},
        bgimage = "panels/square.png",
        interactable = false,
        search = function(element, text)
            element:SetClass("collapsed", text ~= "")
        end,
    }
end

local BuildLevel

--Where a scene or folder is filed: a folder that no longer exists counts
--as the top level.
local function FolderOf(id)
    if id ~= nil and Scenes.GetFolder(id) == nil then
        return nil
    end
    return id
end

local function CountChildren(folderid)
    local count = 0
    for _, scene in pairs(Scenes.All()) do
        if type(scene) == "table" and FolderOf(scene.folder) == folderid then
            count = count + 1
        end
    end
    for _, folder in pairs(Scenes.Folders()) do
        if type(folder) == "table" and FolderOf(folder.parent) == folderid then
            count = count + 1
        end
    end
    return count
end

local function FolderNode(id, folder, depth)
    local content = gui.Panel{
        classes = {cond(g_collapsedFolders[id], "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",
        children = BuildLevel(id, depth + 1),
    }

    local arrow = gui.ExpandoArrow{
        bgimage = "phosphor/caret-down-fill.png",
        width = 12,
        height = 12,
        valign = "center",
        classes = cond(g_collapsedFolders[id], nil, {"expanded"}),
        click = function(element)
            local collapsed = not g_collapsedFolders[id]
            g_collapsedFolders[id] = collapsed or nil
            content:SetClass("collapsed", collapsed)
            element:SetClass("expanded", not collapsed)
        end,
    }

    local function Menu(element)
        element.popup = gui.ContextMenu{
            entries = {
                {
                    text = "New Scene Here",
                    click = function()
                        element.popup = nil
                        local sceneid = Scenes.Create{folder = id}
                        g_collapsedFolders[id] = nil
                        Scenes.ShowEditor(sceneid)
                    end,
                },
                {
                    text = "New Subfolder",
                    click = function()
                        element.popup = nil
                        ShowNameDialog("New Folder", "New Folder", function(name)
                            g_collapsedFolders[id] = nil
                            Scenes.CreateFolder(name, id)
                        end)
                    end,
                },
                {
                    text = "Rename Folder...",
                    click = function()
                        element.popup = nil
                        ShowNameDialog("Rename Folder", folder.name, function(name)
                            Scenes.RenameFolder(id, name)
                        end)
                    end,
                },
                {
                    text = "Delete Folder",
                    click = function()
                        element.popup = nil
                        Scenes.DeleteFolder(id)
                    end,
                },
            },
        }
    end

    local header = gui.Panel{
        classes = {"sceneFolderHeader"},
        dragTarget = true,
        draggable = true,
        data = {folderid = id},
        search = function(element, text)
            element:SetClass("collapsed", text ~= "")
        end,
        click = function(element)
            arrow:FireEvent("click")
        end,
        rightClick = function(element)
            Menu(element)
        end,
        doubleclick = function(element)
            ShowNameDialog("Rename Folder", folder.name, function(name)
                Scenes.RenameFolder(id, name)
            end)
        end,
        canDragOnto = function(element, target)
            if not IsSceneDropTarget(target) then
                return false
            end
            local into = DropFolder(target)
            return into == nil or not Scenes.FolderIsInside(into, id)
        end,
        drag = function(element, target)
            local into, ok = DropFolder(target)
            if ok then
                Scenes.MoveFolder(id, into)
            end
        end,
        gui.Panel{
            width = depth * INDENT,
            height = 1,
            interactable = false,
        },
        arrow,
        gui.Label{
            classes = {"sceneFolderLabel"},
            text = tostring(folder.name or "Folder"),
            interactable = false,
        },
        gui.Label{
            classes = {"sceneFolderCount"},
            text = tostring(CountChildren(id)),
            interactable = false,
        },
    }

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        header,
        gui.Panel{
            classes = {"sceneFolderRule"},
            bgimage = "panels/square.png",
            interactable = false,
            search = function(element, text)
                element:SetClass("collapsed", text ~= "")
            end,
        },
        content,
    }
end

--The panels for one folder's contents (nil: the top level): its subfolders,
--then its scenes, each sorted by name.
BuildLevel = function(folderid, depth)
    local children = {}
    for _, f in ipairs(SortedByName(Scenes.Folders())) do
        if FolderOf(f.entry.parent) == folderid then
            children[#children+1] = FolderNode(f.id, f.entry, depth)
        end
    end
    local first = true
    for _, s in ipairs(SortedByName(Scenes.All())) do
        if FolderOf(s.entry.folder) == folderid then
            if not first then
                children[#children+1] = SeamLine()
            end
            first = false
            children[#children+1] = SceneRow(s.id, s.entry, depth)
        end
    end
    return children
end

local function CreateScenesPanel()
    local m_search = ""

    local listPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
    }

    local emptyLabel = gui.Label{
        classes = {"sceneEmptyText", "collapsed"},
        text = "No scenes yet. Press + to add one, then drag it onto the table.",
    }

    local function Rebuild()
        local children = BuildLevel(nil, 0)
        emptyLabel:SetClass("collapsed", #children > 0)
        children[#children+1] = gui.Panel{
            classes = {"sceneRootTarget"},
            dragTarget = true,
            data = {folderid = false},
        }
        listPanel.children = children
        listPanel:FireEventTree("refreshPresenting", Scenes.PresentedId())
        if m_search ~= "" then
            listPanel:FireEventTree("search", m_search)
        end
    end

    local toolbar = gui.Panel{
        flow = "horizontal",
        width = "100%",
        height = 40,
        gui.SearchInput{
            width = "100%-84",
            height = 24,
            borderBox = true,
            halign = "left",
            valign = "center",
            lmargin = 12,
            placeholderText = "Search Scenes...",
            edit = function(element)
                m_search = string.lower(trim(element.text))
                listPanel:FireEventTree("search", m_search)
            end,
        },
        gui.Button{
            icon = "phosphor/folder-plus-duotone.png",
            width = 26,
            height = 26,
            valign = "center",
            lmargin = 6,
            hover = gui.Tooltip("New folder"),
            click = function(element)
                ShowNameDialog("New Folder", "New Folder", function(name)
                    Scenes.CreateFolder(name, nil)
                end)
            end,
        },
        gui.Button{
            classes = {"addButton"},
            width = 26,
            height = 26,
            valign = "center",
            lmargin = 4,
            hover = gui.Tooltip("New scene"),
            click = function(element)
                local id = Scenes.Create{}
                Scenes.ShowEditor(id)
            end,
        },
    }

    local body = gui.Panel{
        width = "100%",
        height = "100% available",
        flow = "vertical",
        vscroll = true,
        listPanel,
        emptyLabel,
    }

    local resultPanel
    resultPanel = gui.Panel{
        styles = ThemeEngine.MergeStyles(BuildScenesStyles()),
        width = "100%",
        height = "100%",
        flow = "vertical",
        toolbar,
        body,

        create = function(element)
            Rebuild()
            element:FireEvent("think")
        end,
        monitorGame = Scenes.DocPath(),
        refreshGame = function(element)
            Rebuild()
        end,

        --what is on show changes without the library changing.
        thinkTime = 0.5,
        think = function(element)
            local presented = Scenes.PresentedId()
            if presented ~= element.data.presented then
                element.data.presented = presented
                listPanel:FireEventTree("refreshPresenting", presented)
            end
        end,
        data = {presented = nil},
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if resultPanel.valid then
            resultPanel.styles = ThemeEngine.MergeStyles(BuildScenesStyles())
        end
    end)

    return resultPanel
end

DockablePanel.Register{
    name = "Scenes",
    icon = "phosphor/image.png",
    dmonly = true,
    vscroll = false,
    minHeight = 200,
    maxHeight = 900,
    content = function()
        return CreateScenesPanel()
    end,
}

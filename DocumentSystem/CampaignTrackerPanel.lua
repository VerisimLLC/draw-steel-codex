local mod = dmhub.GetModLoading()

-- Campaign Tracker
-- ----------------
-- A dockable panel, available to players and Directors alike, that holds a list
-- of free-form "notes" about the campaign. Each note is a MarkdownDocument, so
-- it can contain rich text plus the existing interactive widgets (checkboxes,
-- counters, dice, images, progress bars) with no new widget code.
--
-- Notes live in their own data table ("campaignNotes"). Every note records its
-- creator (ownerid) and a "shared" flag:
--   - private (shared == false): visible only to its creator. Not even the
--     Director can see another user's private notes.
--   - shared  (shared == true) : visible to everyone and collaboratively
--     editable (any viewer may edit text, tick checkboxes, bump counters).
-- Only the creator may flip a note between shared and private.
--
-- Presentation is deliberately lightweight: notes render as a clean stack with
-- no chrome. Per-note actions (share/private, edit, delete) are available two
-- ways: right-clicking an entry, or toggling the pen "edit mode" button at the
-- bottom, which reveals per-entry edit/share/delete icons. A single small "+"
-- at the bottom adds a new note. Editing the text shows a plain multiline text
-- box directly below the entry, with the entry live-previewing as you type.

----------------------------------------------------------------------
-- Storage type: a MarkdownDocument subtype stored in its own table.
----------------------------------------------------------------------

CampaignNote = RegisterGameType("CampaignNote", "MarkdownDocument")

--Upload() routes to self.tableName, so rows land in our own table.
CampaignNote.tableName = "campaignNotes"

--false = private to creator, true = shared/collaborative.
CampaignNote.shared = false

--keep these out of the journal folder hierarchy.
CampaignNote.parentFolder = ""

--collaborative when shared; otherwise only the creator may edit.
function CampaignNote:HaveEditPermissions()
    return (not self.readonly) and (self.shared or self.ownerid == dmhub.loginUserid)
end

--list-visibility test: shared notes are visible to all, private notes only to
--their creator (no Director bypass).
function CampaignNote:CanView()
    return self.shared or self.ownerid == dmhub.loginUserid
end

local function GetNotesTable()
    return dmhub.GetTable(CampaignNote.tableName) or {}
end

local function GetNote(noteid)
    return GetNotesTable()[noteid]
end

function CampaignNote.CreateNew()
    local maxOrd = 0
    for _, note in unhidden_pairs(GetNotesTable()) do
        if note:try_get("ord", 0) > maxOrd then
            maxOrd = note.ord
        end
    end

    local note = CampaignNote.new {
        id = dmhub.GenerateGuid(),
        ownerid = dmhub.loginUserid,
        shared = false,
        description = "New Note",
        content = "",
        annotations = {},
        parentFolder = "",
        ord = maxOrd + 1,
    }

    --The caller uploads after wiring up edit state, so a brand-new empty draft
    --is protected from the empty-note auto-cleanup before it is persisted.
    return note
end

--whitespace-only (or blank) content counts as empty.
local function NoteIsEmpty(note)
    return note:GetTextContent():match("^%s*$") ~= nil
end

----------------------------------------------------------------------
-- Ordering. Notes carry an "ord" field and the panel sorts ascending by
-- it. These helpers reorder the visible notes and persist the result by
-- normalizing to sequential ords, uploading only the rows that changed.
----------------------------------------------------------------------

local function GetSortedVisibleNotes()
    local visible = {}
    for _, note in unhidden_pairs(GetNotesTable()) do
        if note:CanView() then
            visible[#visible + 1] = note
        end
    end
    table.sort(visible, function(a, b)
        local oa = a:try_get("ord", 0)
        local ob = b:try_get("ord", 0)
        if oa ~= ob then
            return oa < ob
        end
        return (a.description or "") < (b.description or "")
    end)
    return visible
end

local function IndexOfNote(list, noteid)
    for i, note in ipairs(list) do
        if note.id == noteid then
            return i
        end
    end
    return nil
end

--Assign 1..N ords to the given order, uploading only notes whose ord moved.
local function PersistOrder(ordered)
    for i, note in ipairs(ordered) do
        if note:try_get("ord", 0) ~= i then
            local orig = DeepCopy(note)
            note.ord = i
            note:Upload(orig)
        end
    end
end

--Move a note one slot toward the top (direction -1) or bottom (+1).
local function MoveNote(noteid, direction)
    local list = GetSortedVisibleNotes()
    local i = IndexOfNote(list, noteid)
    if i == nil then return end
    local j = i + direction
    if j < 1 or j > #list then return end
    list[i], list[j] = list[j], list[i]
    PersistOrder(list)
end

----------------------------------------------------------------------
-- Icons for the per-entry edit-mode controls.
----------------------------------------------------------------------

local SHARED_ICON = "ui-icons/eye.png"                       --open eye: shared
local PRIVATE_ICON = "ui-icons/eye-closed.png"               --closed eye: private
local EDIT_ICON = "icons/icon_tool/icon_tool_79.png"         --pen: edit

----------------------------------------------------------------------
-- A single note: rendered content + an inline plain-text editor.
-- Actions (share/private, edit, delete) live on a right-click context menu,
-- so the resting state is just the rendered note.
----------------------------------------------------------------------

local function CreateNoteRow(noteid)
    local note = GetNote(noteid)
    if note == nil then
        return gui.Panel { width = 1, height = 1 }
    end

    local readContainer
    local editInput
    local editButton, shareIcon, deleteButton
    local row

    --Reused throwaway document used to render the live preview while editing,
    --so the entry can update from the in-progress text without persisting.
    local previewDoc

    --Rebuild the rendered view from scratch. Refreshing a MarkdownDocument
    --DisplayPanel in place does not pick up content changes, so we recreate it.
    --When `liveText` is supplied (while editing) the entry renders that text via
    --the preview document instead of the stored note, so it updates as the user
    --types; nothing is committed until the editor loses focus.
    local function rebuildRead(liveText)
        local cur = GetNote(noteid)
        if cur == nil then return end

        local doc = cur
        if liveText ~= nil then
            if previewDoc == nil then
                previewDoc = MarkdownDocument.new {
                    content = "",
                    annotations = cur.annotations,
                }
            end
            previewDoc.annotations = cur.annotations
            previewDoc:SetTextContent(liveText)
            doc = previewDoc
        end

        readContainer.children = {
            doc:DisplayPanel {
                width = "100%",
                height = "auto",
                vscroll = false,
            },
        }
    end

    local function enterEdit()
        local cur = GetNote(noteid)
        if cur == nil or not cur:HaveEditPermissions() then return end
        if editInput:HasClass("collapsed") then
            --mark this note as actively edited so the empty-note cleanup leaves
            --it alone while it is being written.
            local listEl = row:FindParentWithClass("noteList")
            if listEl ~= nil then listEl.data.editingId = noteid end
            editInput.text = cur:GetTextContent()
            --keep the rendered entry visible and reveal the editor directly
            --below it; the entry now mirrors what is being typed (live preview).
            editInput:SetClass("collapsed", false)
            rebuildRead(editInput.text)
            editInput.hasFocus = true
        end
    end

    readContainer = gui.Panel {
        classes = { "noteRead" },
        flow = "vertical",
        width = "100%",
        height = "auto",
    }

    editInput = gui.Input {
        classes = { "noteEditor", "collapsed" },
        multiline = true,
        text = note:GetTextContent(),
        width = "100%",
        height = "auto",
        minHeight = 48,
        textAlignment = "topleft",
        placeholderText = "Write a note...",
        --live-preview: as the user types, re-render the entry above from the
        --in-progress text. editlag throttles the rebuild to typing pauses.
        editlag = 0.2,
        edit = function(element)
            rebuildRead(element.text)
        end,
        --commit + return to the rendered view when focus leaves the box. A note
        --left empty is removed rather than kept as a blank row.
        defocus = function(element)
            local cur = GetNote(noteid)
            local txt = element.text or ""

            local listEl = element:FindParentWithClass("noteList")
            if listEl ~= nil and listEl.data.editingId == noteid then
                listEl.data.editingId = nil
            end

            if cur ~= nil and cur:HaveEditPermissions() then
                if txt:match("^%s*$") ~= nil then
                    --empty: delete it (own notes), or persist the empty content
                    --for a collaborator (the owner's client then cleans it up).
                    local orig = DeepCopy(cur)
                    if cur.ownerid == dmhub.loginUserid then
                        cur.hidden = true
                        cur:Upload(orig)
                        return
                    elseif cur:GetTextContent() ~= "" then
                        cur:SetTextContent("")
                        cur:Upload(orig)
                    end
                elseif txt ~= cur:GetTextContent() then
                    local orig = DeepCopy(cur)
                    cur:SetTextContent(txt)
                    cur:Upload(orig)
                end
            end

            element:SetClass("collapsed", true)
            rebuildRead()
        end,
    }

    --Per-entry controls, revealed only while the panel's "edit mode" is on.
    --Each gates itself further by permission: edit/delete need edit rights,
    --share needs ownership.
    editButton = gui.Panel {
        classes = { "noteControl" },
        floating = true,
        width = 14,
        height = 14,
        halign = "right",
        valign = "top",
        x = -22,
        y = 2,
        bgcolor = "white",
        bgimage = EDIT_ICON,
        linger = gui.Tooltip("Edit note"),
        press = function(element)
            enterEdit()
        end,
    }

    shareIcon = gui.Panel {
        --"shareControl" drives the eye glyph via styles (open when shared,
        --closed when private) -- a class swap repaints reliably, an inline
        --bgimage write does not.
        classes = { "noteControl", "shareControl" },
        floating = true,
        width = 14,
        height = 14,
        halign = "right",
        valign = "top",
        x = -2,
        y = 2,
        bgcolor = "white",
        --tooltip reflects the current state and the action a click performs.
        hover = function(element)
            local cur = GetNote(noteid)
            local tip = "Private -- only you can see this (click to share)"
            if cur ~= nil and cur.shared then
                tip = "Shared -- visible to everyone (click to make private)"
            end
            gui.Tooltip(tip)(element)
        end,
        press = function(element)
            local cur = GetNote(noteid)
            if cur == nil or cur.ownerid ~= dmhub.loginUserid then return end
            local orig = DeepCopy(cur)
            cur.shared = not cur.shared
            cur:Upload(orig)
            row:FireEvent("refreshRow")
        end,
    }

    deleteButton = gui.DeleteItemButton {
        classes = { "noteControl" },
        floating = true,
        requireConfirm = true,
        width = 14,
        height = 14,
        halign = "right",
        valign = "top",
        x = -42,
        y = 2,
        linger = gui.Tooltip("Delete note"),
        click = function(element)
            local cur = GetNote(noteid)
            if cur == nil or not cur:HaveEditPermissions() then return end
            local orig = DeepCopy(cur)
            cur.hidden = true
            cur:Upload(orig)
        end,
    }

    row = gui.Panel {
        --theme surface classes drive the fill; refreshRow swaps between them so
        --shared and private notes read distinctly. Starts private ("bgDisabled").
        classes = { "noteRow", "bgDisabled" },
        flow = "vertical",
        width = "100%",
        height = "auto",
        borderWidth = 0,
        data = { noteid = noteid },

        refreshRow = function(element)
            local cur = GetNote(noteid)

            --keep the rendered view current (unless we are mid-edit).
            if editInput:HasClass("collapsed") then
                rebuildRead()
            end

            --show the per-entry controls only when edit mode is toggled on (and
            --the user actually has the relevant rights for each one).
            local listEl = element:FindParentWithClass("noteList")
            local editMode = listEl ~= nil and listEl.data.editMode == true
            local canEdit = cur ~= nil and cur:HaveEditPermissions()
            local isOwner = cur ~= nil and cur.ownerid == dmhub.loginUserid

            editButton:SetClass("editActive", editMode and canEdit)
            deleteButton:SetClass("editActive", editMode and canEdit)
            shareIcon:SetClass("editActive", editMode and isOwner)

            --reflect the current shared/private state on the share icon (open
            --eye when shared, closed eye when private) and on the row's
            --background via distinct theme surface classes (@bgAlt when shared,
            --muted @disabled card when private).
            local isShared = cur ~= nil and cur.shared == true
            shareIcon:SetClass("shared", isShared)
            element:SetClass("bgAlt", isShared)
            element:SetClass("bgDisabled", not isShared)
        end,

        --used when a freshly added note should open straight into editing.
        beginEdit = function(element)
            enterEdit()
        end,

        press = function(element)
            element.popup = nil
        end,

        --all per-note actions live here: edit the text, toggle shared/private
        --(owner only), and delete. Entries the current user has no rights to are
        --simply hidden.
        rightClick = function(element)
            local cur = GetNote(noteid)
            if cur == nil then return end

            local canEdit = cur:HaveEditPermissions()
            local isOwner = cur.ownerid == dmhub.loginUserid

            --position within the sorted list, so Move Up/Down can hide at the ends.
            local sorted = GetSortedVisibleNotes()
            local pos = IndexOfNote(sorted, noteid)

            local entries = {
                {
                    text = "Edit",
                    hidden = not canEdit,
                    click = function()
                        element.popup = nil
                        enterEdit()
                    end,
                },
                {
                    text = "Move Up",
                    hidden = not canEdit or pos == nil or pos <= 1,
                    click = function()
                        element.popup = nil
                        MoveNote(noteid, -1)
                    end,
                },
                {
                    text = "Move Down",
                    hidden = not canEdit or pos == nil or pos >= #sorted,
                    click = function()
                        element.popup = nil
                        MoveNote(noteid, 1)
                    end,
                },
                {
                    text = cond(cur.shared, "Make Private", "Share"),
                    hidden = not isOwner,
                    click = function()
                        element.popup = nil
                        local note = GetNote(noteid)
                        if note == nil or note.ownerid ~= dmhub.loginUserid then return end
                        local orig = DeepCopy(note)
                        note.shared = not note.shared
                        note:Upload(orig)
                        row:FireEvent("refreshRow")
                    end,
                },
                {
                    text = "Delete",
                    hidden = not canEdit,
                    click = function()
                        element.popup = nil
                        local note = GetNote(noteid)
                        if note == nil or not note:HaveEditPermissions() then return end
                        local orig = DeepCopy(note)
                        note.hidden = true
                        note:Upload(orig)
                    end,
                },
            }

            element.popup = gui.ContextMenu {
                entries = entries,
            }
        end,

        readContainer,
        editInput,
        editButton,
        shareIcon,
        deleteButton,
    }

    rebuildRead()
    return row
end

----------------------------------------------------------------------
-- The panel body: a stack of notes plus a single "+" at the bottom.
----------------------------------------------------------------------

local function CreateCampaignTrackerPanel()
    local listPanel

    listPanel = gui.Panel {
        classes = { "noteList" },
        flow = "vertical",
        width = "100%",
        height = "auto",
        data = {
            rows = {},
            handler = nil,
            expandId = nil,
            editingId = nil,
            editMode = false,
        },

        create = function(element)
            element.data.handler = dmhub.RegisterEventHandler("refreshTables", function(keys)
                if mod.unloaded then return end
                if element ~= nil and element.valid then
                    element:FireEvent("refreshNotes")
                end
            end)
            element:FireEvent("refreshNotes")
        end,

        destroy = function(element)
            if element.data.handler ~= nil then
                dmhub.DeregisterEventHandler(element.data.handler)
                element.data.handler = nil
            end
        end,

        refreshNotes = function(element)
            local rows = element.data.rows
            local newRows = {}
            local children = {}
            local visible = {}
            local toDelete = {}

            --notes that must not be auto-removed even if momentarily empty: the
            --one being edited, and a brand-new draft about to open for editing.
            local editingId = element.data.editingId
            local protectId = element.data.expandId

            for id, note in unhidden_pairs(GetNotesTable()) do
                if note:CanView() then
                    if NoteIsEmpty(note) and id ~= editingId and id ~= protectId
                        and note.ownerid == dmhub.loginUserid then
                        --never leave an empty note of ours lying around.
                        toDelete[#toDelete + 1] = note
                    else
                        visible[#visible + 1] = { id = id, note = note }
                    end
                end
            end

            table.sort(visible, function(a, b)
                local oa = a.note:try_get("ord", 0)
                local ob = b.note:try_get("ord", 0)
                if oa ~= ob then
                    return oa < ob
                end
                return (a.note.description or "") < (b.note.description or "")
            end)

            for _, entry in ipairs(visible) do
                local p = rows[entry.id] or CreateNoteRow(entry.id)
                newRows[entry.id] = p
                children[#children + 1] = p
            end

            element.data.rows = newRows
            element.children = children

            --refresh each row individually (FireEvent, not tree, so rebuildRead
            --does not race with a tree traversal).
            for _, p in ipairs(children) do
                p:FireEvent("refreshRow")
            end

            local expandId = element.data.expandId
            if expandId ~= nil and newRows[expandId] ~= nil then
                element.data.expandId = nil
                newRows[expandId]:FireEvent("beginEdit")
            end

            --delete empty notes after rebuilding the UI; each upload re-enters
            --refreshNotes, which then finds them hidden and skips them.
            for _, note in ipairs(toDelete) do
                local orig = DeepCopy(note)
                note.hidden = true
                note:Upload(orig)
            end
        end,
    }

    local addButton = gui.Button {
        classes = { "addButton", "sizeS" },
        valign = "center",
        hmargin = 4,
        hover = function(element)
            gui.Tooltip("Add a note")(element)
        end,
        press = function(element)
            local note = CampaignNote.CreateNew()
            --protect + open for editing before persisting, so the empty draft
            --is not swept by the auto-cleanup the moment it is uploaded.
            listPanel.data.editingId = note.id
            listPanel.data.expandId = note.id
            note:Upload()
            listPanel:FireEvent("refreshNotes")
        end,
    }

    --pen toggle: flips edit mode on/off, which reveals the per-entry
    --edit/share/delete icons. The "selected" class marks the active state.
    local editModeButton = gui.Button {
        classes = { "editModeButton", "sizeS" },
        icon = EDIT_ICON,
        valign = "center",
        hmargin = 4,
        hover = function(element)
            gui.Tooltip("Edit entries")(element)
        end,
        press = function(element)
            local editMode = not listPanel.data.editMode
            listPanel.data.editMode = editMode
            element:SetClass("selected", editMode)
            --re-apply each row's control visibility for the new mode.
            for _, p in pairs(listPanel.data.rows) do
                p:FireEvent("refreshRow")
            end
        end,
    }

    local footer = gui.Panel {
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "center",
        tmargin = 6,
        bmargin = 4,

        editModeButton,
        addButton,
    }

    return gui.Panel {
        classes = { "campaignTrackerPanel" },
        flow = "vertical",
        width = "100%",
        height = "auto",

        styles = {
            --layout only; the row's fill comes from the "bg"/"bgAlt" surface
            --classes toggled per shared state in refreshRow.
            {
                selectors = { "noteRow" },
                priority = 100,
                width = "100%",
                height = "auto",
                minHeight = 22,
                vmargin = 5,
            },
            {
                selectors = { "noteEditor" },
                fontSize = 14,
                color = "white",
                bgimage = "panels/square.png",
                bgcolor = "#00000044",
                borderWidth = 1,
                borderColor = "#ffffff33",
                cornerRadius = 4,
                pad = 6,
                borderBox = true,
                textAlignment = "topleft",
            },
            --per-entry controls are hidden unless edit mode reveals them.
            --"hidden" (not "collapsed") because the controls are floating, and
            --collapsed has no effect on floating items.
            {
                selectors = { "noteControl" },
                hidden = 1,
            },
            {
                selectors = { "noteControl", "editActive" },
                hidden = 0,
            },
            --share icon: closed eye = private (default), open eye = shared.
            {
                selectors = { "shareControl" },
                bgimage = PRIVATE_ICON,
            },
            {
                selectors = { "shareControl", "shared" },
                bgimage = SHARED_ICON,
            },
            --outline the pen button while edit mode is active.
            {
                selectors = { "editModeButton", "selected" },
                borderWidth = 1,
                borderColor = "#ffffffaa",
                cornerRadius = 4,
            },
        },

        listPanel,
        footer,
    }
end

----------------------------------------------------------------------
-- Registration.
----------------------------------------------------------------------

DockablePanel.Register {
    name = "Campaign Tracker",
    icon = "icons/standard/Icon_App_Journal.png",
    vscroll = true,
    dmonly = false,
    minHeight = 200,
    content = function()
        return CreateCampaignTrackerPanel()
    end,
}

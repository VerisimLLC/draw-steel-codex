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
--
-- Mods can add their own tracking sections to the panel via
-- CampaignTracker.RegisterSection (see the extension hook section below).

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
-- Mod extension hook: custom tracker sections.
--
-- A mod can hook its own panel into the Campaign Tracker:
--
--   CampaignTracker.RegisterSection{
--       id = "myModSection",
--       ord = 50,
--       create = function()
--           return gui.Panel{ ... }
--       end,
--   }
--
-- Sections stack vertically with the built-in notes UI, ordered by ord.
-- Registration is live: any open tracker panels rebuild immediately.
----------------------------------------------------------------------

--Global interface other mods use to extend the Campaign Tracker.
--(rawget: reading an unset global errors in this runtime, so probe safely.)
CampaignTracker = rawget(_G, "CampaignTracker") or {}

--keyed by section id; kept on the global so registrations from other mods
--survive a reload of this file.
CampaignTracker._sections = CampaignTracker._sections or {}

local SECTIONS_CHANGED_EVENT = "campaignTrackerSectionsChanged"

--- Register a custom section that renders inside the Campaign Tracker panel.
--- Call at mod load time (or any time -- open tracker panels rebuild live).
--- Registering an id that already exists replaces that section, so a mod
--- reload updates its section in place.
--- @param args {id: string, create: (fun(): Panel), ord: nil|number}
---   id:     unique key for the section.
---   create: factory called once per Campaign Tracker panel instance (and
---           again whenever the section list changes); must return a panel.
---   ord:    sort order. The built-in notes section is ord 0 and custom
---           sections default to 100, placing them below the notes; use a
---           negative ord to sort above the notes.
function CampaignTracker.RegisterSection(args)
    if type(args) ~= "table" or type(args.id) ~= "string" or type(args.create) ~= "function" then
        error("CampaignTracker.RegisterSection: requires { id = string, create = function }")
    end

    CampaignTracker._sections[args.id] = {
        id = args.id,
        ord = args.ord or 100,
        create = args.create,
    }

    dmhub.FireGlobalEvent(SECTIONS_CHANGED_EVENT)
end

--- Remove a previously registered section. Open tracker panels update live.
--- @param id string
function CampaignTracker.UnregisterSection(id)
    if CampaignTracker._sections[id] ~= nil then
        CampaignTracker._sections[id] = nil
        dmhub.FireGlobalEvent(SECTIONS_CHANGED_EVENT)
    end
end

local function GetSortedSections()
    local result = {}
    for _, section in pairs(CampaignTracker._sections) do
        result[#result + 1] = section
    end
    table.sort(result, function(a, b)
        if a.ord ~= b.ord then
            return a.ord < b.ord
        end
        return a.id < b.id
    end)
    return result
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

    --The built-in notes UI is itself a section (ord 0), so registered custom
    --sections can sort above (ord < 0) or below (ord > 0) it.
    local notesSection = gui.Panel {
        classes = { "campaignTrackerSection" },
        flow = "vertical",
        width = "100%",
        height = "auto",

        listPanel,
        footer,
    }

    local sectionsContainer

    --Rebuild the ordered stack of sections. notesSection is always included
    --in the new children list, so reassigning children only destroys the
    --previous custom section panels (each replaced by a fresh factory call).
    local function rebuildSections()
        local entries = {
            { ord = 0, id = "notes", panel = notesSection },
        }

        for _, section in ipairs(GetSortedSections()) do
            local ok, panel = pcall(section.create)
            if not ok then
                printf("CampaignTracker: error building section %s: %s", section.id, tostring(panel))
            elseif panel ~= nil then
                entries[#entries + 1] = { ord = section.ord, id = section.id, panel = panel }
            end
        end

        table.sort(entries, function(a, b)
            if a.ord ~= b.ord then
                return a.ord < b.ord
            end
            return a.id < b.id
        end)

        local children = {}
        for _, entry in ipairs(entries) do
            children[#children + 1] = entry.panel
        end
        sectionsContainer.children = children
    end

    sectionsContainer = gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",
        data = { sectionsHandler = nil },

        create = function(element)
            element.data.sectionsHandler = dmhub.RegisterEventHandler(SECTIONS_CHANGED_EVENT, function()
                if mod.unloaded then return end
                if element ~= nil and element.valid then
                    rebuildSections()
                end
            end)
            rebuildSections()
        end,

        destroy = function(element)
            if element.data.sectionsHandler ~= nil then
                dmhub.DeregisterEventHandler(element.data.sectionsHandler)
                element.data.sectionsHandler = nil
            end
        end,
    }

    return gui.Panel {
        classes = { "campaignTrackerPanel" },
        flow = "vertical",
        width = "100%",
        height = "auto",

        --The footer (edit/add buttons) sits at the bottom of the content. During
        --the dockable panel's collapse->expand on first open, the footer's button
        --children miss their initial style pass: they keep their default 100x100
        --size and the icon-only add button never resolves its style-driven "+"
        --image (the parent:addButton rule), so it stays invisible until the panel
        --is resized. Force a restyle of the footer subtree once the panel has
        --settled. Staggered to be robust to the open transition's timing.
        create = function(element)
            for _, delay in ipairs({ 0.05, 0.2, 0.5 }) do
                dmhub.Schedule(delay, function()
                    if mod.unloaded or footer == nil or not footer.valid then return end
                    footer:SetClassTree("settleLayout", true)
                    footer:SetClassTree("settleLayout", false)
                end)
            end
        end,

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

        sectionsContainer,
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

----------------------------------------------------------------------
-- The Run panel
-- -------------
-- A Director-only dockable panel holding the session agenda: an ordered
-- checklist of loadable items of mixed types. Clicking an item loads it:
--   - journal documents and prepped montage tests open in the document
--     viewer (montage tests carry their own "Begin Montage" button).
--   - negotiations launch the Negotiation panel for the referenced token.
-- The first item not yet checked off is highlighted as the current one.
--
-- The agenda lives in the "runagenda" shared document so it syncs across
-- clients and persists with the game. Items are plain tables:
--   { id, itemType ("document"|"montagetest"|"negotiation"), name,
--     tableName, docid, charid, done }
----------------------------------------------------------------------

local RUN_AGENDA_DOC = "runagenda"

mod:RegisterDocumentForCheckpointBackups(RUN_AGENDA_DOC)

local RUN_ITEM_ICONS = {
    document = "icons/standard/Icon_App_Journal.png",
    montagetest = "icons/standard/Icon_App_Respite.png",
    negotiation = "icons/standard/Icon_App_Negotiation.png",
}

local function GetRunItems()
    local doc = mod:GetDocumentSnapshot(RUN_AGENDA_DOC)
    return doc.data.items or {}
end

local function SaveRunItems(items, description)
    local doc = mod:GetDocumentSnapshot(RUN_AGENDA_DOC)
    doc:BeginChange()
    doc.data.items = items
    doc:CompleteChange(description)
end

local function AddRunItem(item)
    local items = DeepCopy(GetRunItems())
    items[#items + 1] = item
    SaveRunItems(items, "Add to the run")
end

--Public hook: other modules add to the run through this global (the
--journal tree and viewer-tab "Add to Run" context entries use it; they
--guard with rawget(_G, "RunAgenda") since this file loads late).
RunAgenda = rawget(_G, "RunAgenda") or {}

--Add a journal document (a CustomDocument-derived instance) to the run.
function RunAgenda.AddDocument(doc)
    AddRunItem {
        id = dmhub.GenerateGuid(),
        itemType = "document",
        tableName = CustomDocument.tableName,
        docid = doc.id,
        name = doc.description or "Untitled",
        done = false,
    }
end

--Find the item by id and hand (items, index) to fn to mutate, then persist.
local function MutateRunItems(itemid, description, fn)
    local items = DeepCopy(GetRunItems())
    for i, item in ipairs(items) do
        if item.id == itemid then
            fn(items, i)
            SaveRunItems(items, description)
            return
        end
    end
end

--Load dispatch: what "clicking an agenda item" does for each item type.
local function LoadRunItem(item)
    if item.itemType == "negotiation" then
        local token = dmhub.GetTokenById(item.charid)
        if token == nil then
            gui.ModalMessage {
                title = "Token not found",
                message = "The token this negotiation refers to is not available on the current map.",
            }
            return
        end
        LaunchablePanel.LaunchPanelByName("Negotiation", { charid = item.charid })
    else
        local doc = (dmhub.GetTable(item.tableName) or {})[item.docid]
        if doc == nil or doc:try_get("hidden", false) then
            gui.ModalMessage {
                title = "Not found",
                message = "This entry refers to a document that no longer exists.",
            }
            return
        end
        doc:ShowDocument()
    end
end

----------------------------------------------------------------------
-- A single agenda row: expando arrow + type icon + name (click to
-- load) + done check, with an accordion body that renders the backing
-- document inline. Rows rebuild wholesale on any agenda change, so
-- expansion state lives in g_runRowExpanded (local UI state keyed by
-- item id) rather than on the panels.
----------------------------------------------------------------------

local g_runRowExpanded = {}

local function CreateRunItemRow(item, isCurrent)
    --for document-backed items prefer the live document name over the
    --name cached at add time, so renames show through.
    local displayName = item.name or "Untitled"
    local doc = nil
    if item.itemType ~= "negotiation" and item.tableName ~= nil then
        doc = (dmhub.GetTable(item.tableName) or {})[item.docid]
        if doc ~= nil then
            displayName = doc.description or displayName
        end
    end

    --only journal documents have page content to show inline.
    local expandable = item.itemType == "document" and doc ~= nil
    local expanded = expandable and g_runRowExpanded[item.id] == true

    local rowClasses = { "bordered", "hoverable" }
    if item.done then
        rowClasses[#rowClasses + 1] = "bgDisabled"
    else
        rowClasses[#rowClasses + 1] = "bgAlt"
    end
    if isCurrent then
        rowClasses[#rowClasses + 1] = "borderAccent"
    end

    local labelClasses = {}
    if item.done then
        labelClasses[#labelClasses + 1] = "fgMuted"
    end

    --the accordion body. Content is built lazily on first expand: the
    --embedded page render is heavy, and most rows stay closed.
    local bodyPanel = nil
    local arrow = nil
    if expandable then
        local bodyClasses = {}
        if not expanded then
            bodyClasses[#bodyClasses + 1] = "collapsed"
        end
        --no inner scroll region: nesting a vscroll around a single tall
        --auto-height embed makes the engine mis-measure the scroll area
        --and cull the content to blank page background (the "can't see
        --the checkboxes" bug). The page renders full-length inline and
        --the dock panel itself provides the scrolling.
        bodyPanel = gui.Panel {
            classes = bodyClasses,
            width = "100%",
            height = "auto",
            tmargin = 4,

            create = function(element)
                if expanded then
                    element:FireEvent("buildContent")
                end
            end,

            buildContent = function(element)
                if #element.children > 0 then
                    return
                end
                local embed = CustomDocument.CreateEmbeddablePanel(doc, {})
                if embed ~= nil then
                    element.children = { embed }
                end
            end,
        }

        local function Toggle()
            local nowExpanded = not (g_runRowExpanded[item.id] == true)
            g_runRowExpanded[item.id] = nowExpanded or nil
            arrow:SetClass("expanded", nowExpanded)
            bodyPanel:SetClass("collapsed", not nowExpanded)
            if nowExpanded then
                bodyPanel:FireEvent("buildContent")
            else
                --drop the embedded page and rebuild the whole list. When the
                --row shrinks back from a page-tall embed, the engine does not
                --re-evaluate its offscreen culling for the siblings that had
                --been pushed out of view, so everything below the collapsed
                --row stays invisible (and with the content now shorter than
                --the dock there is no scroll event to trigger a re-cull).
                --A full refreshRun lays the list out fresh.
                bodyPanel.children = {}
                bodyPanel:FireEventOnParents("refreshRun")
            end
        end

        --NOTE: do not pass classes = {} here: gui.CombineFields replaces
        --(not merges) when either list is empty, which would strip the
        --"triangle" theme class and with it the arrow's 12x12 sizing.
        --click, not press: rows are draggable, and press fires when a
        --drag gesture starts on a child; click only fires on a true click.
        arrow = gui.ExpandoArrow {
            click = Toggle,
            create = function(element)
                element:SetClass("expanded", g_runRowExpanded[item.id] == true)
            end,
        }
    end

    local headerRow = gui.Panel {
        flow = "horizontal",
        width = "100%",
        height = "auto",

        rightClick = function(element)
            local items = GetRunItems()
            local pos = nil
            for i, it in ipairs(items) do
                if it.id == item.id then
                    pos = i
                end
            end

            element.popup = gui.ContextMenu {
                entries = {
                    {
                        text = "Move Up",
                        hidden = pos == nil or pos <= 1,
                        click = function()
                            element.popup = nil
                            MutateRunItems(item.id, "Reorder the run", function(list, i)
                                if i > 1 then
                                    list[i], list[i - 1] = list[i - 1], list[i]
                                end
                            end)
                        end,
                    },
                    {
                        text = "Move Down",
                        hidden = pos == nil or pos >= #items,
                        click = function()
                            element.popup = nil
                            MutateRunItems(item.id, "Reorder the run", function(list, i)
                                if i < #list then
                                    list[i], list[i + 1] = list[i + 1], list[i]
                                end
                            end)
                        end,
                    },
                    {
                        text = "Remove",
                        click = function()
                            element.popup = nil
                            MutateRunItems(item.id, "Remove from the run", function(list, i)
                                table.remove(list, i)
                            end)
                        end,
                    },
                },
            }
        end,

        --accordion arrow slot: real arrow for documents, a spacer for
        --other item types so icons line up across rows (the triangle is
        --12 wide plus 4 hmargin per side).
        arrow or gui.Panel { width = 20, height = 1 },

        --icon + name: the clickable "load" area.
        gui.Panel {
            flow = "horizontal",
            width = "100%-50",
            height = "auto",
            valign = "center",

            --click, not press: see the expando arrow note above.
            click = function(element)
                LoadRunItem(item)
            end,

            gui.Panel {
                width = 16,
                height = 16,
                valign = "center",
                bgimage = RUN_ITEM_ICONS[item.itemType] or RUN_ITEM_ICONS.document,
                bgcolor = "white", --image-tint-neutral
            },

            gui.Label {
                classes = labelClasses,
                width = "100%-32",
                height = "auto",
                hmargin = 8,
                valign = "center",
                text = displayName,
            },
        },

        --done check: ticking an item off must not also load it, so it sits
        --outside the load area.
        gui.Check {
            text = "",
            value = item.done == true,
            halign = "right",
            valign = "center",
            --bare box (empty text): hug the check mark instead of reserving
            --the default label width.
            width = "auto",
            change = function(element)
                MutateRunItems(item.id, "Mark run item", function(list, i)
                    list[i].done = element.value == true
                end)
            end,
        },
    }

    rowClasses[#rowClasses + 1] = "runRow"

    return gui.Panel {
        classes = rowClasses,
        flow = "vertical",
        width = "100%",
        height = "auto",
        pad = 6,
        borderBox = true,
        vmargin = 3,

        --drag a row onto another row to reorder: dragging down lands the
        --row after the target, dragging up lands it before. The engine
        --paints eligible targets while the drag is in flight.
        draggable = true,
        dragTarget = true,
        canDragOnto = function(element, target)
            return target:HasClass("runRow")
        end,
        drag = function(element, target)
            if target ~= nil then
                target:FireEvent("dropRunItem", item.id)
            end
        end,
        dropRunItem = function(element, draggedId)
            if draggedId == item.id then
                return
            end
            local items = DeepCopy(GetRunItems())
            local from, to = nil, nil
            for i, it in ipairs(items) do
                if it.id == draggedId then from = i end
                if it.id == item.id then to = i end
            end
            if from == nil or to == nil then
                return
            end
            local moved = table.remove(items, from)
            table.insert(items, to, moved)
            SaveRunItems(items, "Reorder the run")
        end,

        headerRow,
        bodyPanel,
    }
end

----------------------------------------------------------------------
-- The "+" picker: a popup listing documents grouped into their journal
-- folders (expandable), montage tests, and a negotiation with the
-- selected token. This replaces the old nested context submenu, which
-- opened toward the screen edge from the right-hand dock and got
-- constrained back over its own parent menu, leaving only the top
-- entry clickable.
----------------------------------------------------------------------

local function CreateAddPopup(element)
    local function Close()
        element.popup = nil
    end

    --indentation inside the picker is done with leading spaces: the engine
    --has no per-side padding (pad/hpad/vpad only), and margins on
    --width-100% rows overflow.
    local function Indent(indent)
        return string.rep("      ", indent or 0)
    end

    --a clickable row that adds one item to the run and closes the picker.
    local function PickRow(text, indent, onPick)
        return gui.Label {
            classes = { "fg", "hoverable" },
            bgimage = "panels/square.png",
            bgcolor = "#00000000",
            width = "100%",
            height = "auto",
            fontSize = 14,
            borderBox = true,
            hpad = 8,
            vpad = 4,
            text = Indent(indent) .. text,
            press = function()
                Close()
                onPick()
            end,
        }
    end

    local function SectionLabel(text)
        return gui.Label {
            classes = { "fgMuted", "bold" },
            width = "100%",
            height = "auto",
            fontSize = 11,
            borderBox = true,
            hpad = 6,
            tmargin = 8,
            bmargin = 2,
            text = text,
        }
    end

    local rows = {}

    ------------------------------------------------------------------
    -- documents, grouped into the journal folder tree.
    ------------------------------------------------------------------
    rows[#rows + 1] = SectionLabel("DOCUMENTS")

    local foldersTable = assets.documentFoldersTable or {}

    --docs bucketed by their folder ("" = journal root).
    local docsByFolder = {}
    for id, docItem in unhidden_pairs(dmhub.GetTable(CustomDocument.tableName) or {}) do
        local parent = docItem:try_get("parentFolder", "")
        if parent == nil or parent == false or foldersTable[parent] == nil then
            parent = ""
        end
        docsByFolder[parent] = docsByFolder[parent] or {}
        local list = docsByFolder[parent]
        list[#list + 1] = { id = id, name = docItem.description or "Untitled" }
    end
    for _, list in pairs(docsByFolder) do
        table.sort(list, function(a, b) return a.name < b.name end)
    end

    --folder hierarchy ("" = root level).
    local childFolders = {}
    for fid, folder in pairs(foldersTable) do
        local parent = folder.parentFolder
        if parent == nil or parent == false or foldersTable[parent] == nil then
            parent = ""
        end
        childFolders[parent] = childFolders[parent] or {}
        local list = childFolders[parent]
        list[#list + 1] = fid
    end
    for _, list in pairs(childFolders) do
        table.sort(list, function(a, b)
            return (foldersTable[a].description or "") < (foldersTable[b].description or "")
        end)
    end

    local function AddDocRows(target, folderid, indent)
        for _, doc in ipairs(docsByFolder[folderid] or {}) do
            target[#target + 1] = PickRow(doc.name, indent, function()
                AddRunItem {
                    id = dmhub.GenerateGuid(),
                    itemType = "document",
                    tableName = CustomDocument.tableName,
                    docid = doc.id,
                    name = doc.name,
                    done = false,
                }
            end)
        end
    end

    --a folder renders as a header row that expands/collapses a container
    --holding its documents and subfolders.
    local function BuildFolderPanel(folderid, indent)
        local contents = {}
        AddDocRows(contents, folderid, indent + 1)
        for _, sub in ipairs(childFolders[folderid] or {}) do
            contents[#contents + 1] = BuildFolderPanel(sub, indent + 1)
        end
        if #contents == 0 then
            contents[1] = gui.Label {
                classes = { "fgMuted" },
                width = "100%",
                height = "auto",
                fontSize = 12,
                borderBox = true,
                hpad = 8,
                text = Indent(indent + 1) .. "(empty)",
            }
        end

        local bodyPanel = gui.Panel {
            classes = { "collapsed" },
            flow = "vertical",
            width = "100%",
            height = "auto",
            children = contents,
        }

        local arrow
        local function Toggle()
            arrow:SetClass("expanded", not arrow:HasClass("expanded"))
            bodyPanel:SetClass("collapsed", not arrow:HasClass("expanded"))
        end
        arrow = gui.ExpandoArrow {
            press = Toggle,
        }

        local headerRow = gui.Panel {
            classes = { "hoverable" },
            bgimage = "panels/square.png",
            bgcolor = "#00000000",
            flow = "horizontal",
            width = "100%",
            height = "auto",
            borderBox = true,
            hpad = 4,
            vpad = 3,
            press = Toggle,
            gui.Panel { width = 4 + indent * 16, height = 1 },
            arrow,
            gui.Label {
                classes = { "fg", "bold" },
                width = "auto",
                height = "auto",
                fontSize = 14,
                lmargin = 4,
                text = foldersTable[folderid].description or "Folder",
            },
        }

        return gui.Panel {
            flow = "vertical",
            width = "100%",
            height = "auto",
            headerRow,
            bodyPanel,
        }
    end

    --folders first, then loose root documents.
    for _, fid in ipairs(childFolders[""] or {}) do
        rows[#rows + 1] = BuildFolderPanel(fid, 0)
    end
    AddDocRows(rows, "", 0)

    ------------------------------------------------------------------
    -- montage tests. (The prepped MontageTest type does not exist in
    -- every build; rawget because reading an unset global errors.)
    ------------------------------------------------------------------
    local montageTestType = rawget(_G, "MontageTest")
    if montageTestType ~= nil then
        rows[#rows + 1] = SectionLabel("MONTAGE TESTS")
        local montages = {}
        for id, test in unhidden_pairs(dmhub.GetTable(montageTestType.tableName) or {}) do
            montages[#montages + 1] = { id = id, name = test.description or "Untitled" }
        end
        table.sort(montages, function(a, b) return a.name < b.name end)
        for _, test in ipairs(montages) do
            rows[#rows + 1] = PickRow(test.name, 0, function()
                AddRunItem {
                    id = dmhub.GenerateGuid(),
                    itemType = "montagetest",
                    tableName = montageTestType.tableName,
                    docid = test.id,
                    name = test.name,
                    done = false,
                }
            end)
        end
        if #montages == 0 then
            rows[#rows + 1] = gui.Label {
                classes = { "fgMuted" },
                width = "100%", height = "auto", fontSize = 12, borderBox = true, hpad = 8,
                text = "(no montage tests)",
            }
        end
    end

    ------------------------------------------------------------------
    -- negotiation with the currently selected token.
    ------------------------------------------------------------------
    rows[#rows + 1] = SectionLabel("NEGOTIATION")
    local token = dmhub.currentToken
    local negotiationText = "Negotiation with Selected Token"
    if token ~= nil and token.name ~= nil and token.name ~= "" then
        negotiationText = "Negotiation: " .. token.name
    end
    rows[#rows + 1] = PickRow(negotiationText, 0, function()
        local tok = dmhub.currentToken
        if tok == nil then
            gui.ModalMessage {
                title = "No token selected",
                message = "Select the NPC's token on the map, then add the negotiation to the run.",
            }
            return
        end
        local name = "Negotiation"
        if tok.name ~= nil and tok.name ~= "" then
            name = "Negotiation: " .. tok.name
        end
        AddRunItem {
            id = dmhub.GenerateGuid(),
            itemType = "negotiation",
            charid = tok.charid,
            name = name,
            done = false,
        }
    end)

    --themed surface (same treatment as other picker popups); scrolls when
    --the journal outgrows the height cap.
    return gui.Panel {
        width = "auto",
        height = "auto",
        constrainToScreen = true,
        gui.Panel {
            classes = { "bordered", "bg" },
            flow = "vertical",
            width = 340,
            height = "auto",
            maxHeight = 480,
            vscroll = true,
            borderBox = true,
            pad = 6,
            children = rows,
        },
    }
end

----------------------------------------------------------------------
-- The panel body: the agenda list plus a single "+" at the bottom.
----------------------------------------------------------------------

local function CreateRunPanel()
    local listPanel

    listPanel = gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",
        monitorGame = mod:GetDocumentPath(RUN_AGENDA_DOC),

        refreshGame = function(element)
            element:FireEvent("refreshRun")
        end,

        create = function(element)
            element:FireEvent("refreshRun")
        end,

        --The Rail: the agenda zoned into NOW (the current item, plus any
        --live cue banners), NEXT (what is queued behind it), and LOG
        --(checked-off items and the campaign ledger, newest first).
        --Tracker chips from campaign state pin above NOW (Director-only;
        --the whole panel is dmonly).
        refreshRun = function(element)
            local undone, done = {}, {}
            for _, item in ipairs(GetRunItems()) do
                if item.done then
                    done[#done + 1] = item
                else
                    undone[#undone + 1] = item
                end
            end

            local function ZoneHeader(text)
                return gui.Label {
                    classes = { "fgMuted", "bold" },
                    width = "100%",
                    height = "auto",
                    fontSize = 11,
                    tmargin = 10,
                    bmargin = 2,
                    text = text,
                }
            end

            local children = {}

            --tracker chips: every counter, and every flag currently set.
            local state = rawget(_G, "CampaignState") ~= nil and CampaignState.Get() or nil
            if state ~= nil then
                local chips = {}
                for key, value in pairs(state.counters) do
                    chips[#chips + 1] = string.format("%s: %d", key, value)
                end
                for key, value in pairs(state.flags) do
                    if value == true then
                        chips[#chips + 1] = key
                    end
                end
                table.sort(chips)
                if #chips > 0 then
                    local chipPanels = {}
                    for _, text in ipairs(chips) do
                        chipPanels[#chipPanels + 1] = gui.Label {
                            classes = { "bordered", "fgMuted" },
                            width = "auto",
                            height = "auto",
                            fontSize = 12,
                            borderBox = true,
                            hpad = 6,
                            vpad = 2,
                            rmargin = 4,
                            bmargin = 4,
                            text = text,
                        }
                    end
                    children[#children + 1] = gui.Panel {
                        flow = "horizontal",
                        wrap = true,
                        width = "100%",
                        height = "auto",
                        children = chipPanels,
                    }
                end
            end

            --NOW: the current item, with live cue banners mounted below it
            --so round moments are confirmable from the Rail.
            if #undone > 0 then
                children[#children + 1] = ZoneHeader("NOW")
                children[#children + 1] = CreateRunItemRow(undone[1], true)
                if rawget(_G, "Cues") ~= nil then
                    children[#children + 1] = Cues.CreateRailStrip()
                end
            end

            --NEXT: everything queued behind the current item.
            if #undone > 1 then
                children[#children + 1] = ZoneHeader("NEXT")
                for i = 2, #undone do
                    children[#children + 1] = CreateRunItemRow(undone[i], false)
                end
            end

            --LOG: checked-off items, then the campaign ledger newest-first.
            local ledger = state ~= nil and state.ledger or {}
            if #done > 0 or #ledger > 0 then
                children[#children + 1] = ZoneHeader("LOG")
                for _, item in ipairs(done) do
                    children[#children + 1] = CreateRunItemRow(item, false)
                end
                local shown = 0
                for i = #ledger, 1, -1 do
                    shown = shown + 1
                    if shown > 20 then break end
                    children[#children + 1] = gui.Label {
                        classes = { "fgMuted" },
                        width = "100%",
                        height = "auto",
                        fontSize = 12,
                        tmargin = 4,
                        text = "- " .. (ledger[i].text or ""),
                    }
                end
            end

            if #children == 0 then
                children[1] = gui.Label {
                    classes = { "fgMuted" },
                    width = "100%",
                    height = "auto",
                    vmargin = 8,
                    text = "Nothing on the run yet. Use + to add documents, montage tests, or negotiations.",
                }
            end

            element.children = children
        end,
    }

    --campaign state lives in its own shared doc; a sibling monitor (it
    --cannot live inside listPanel, whose children are rebuilt wholesale)
    --re-zones the Rail when trackers or the ledger change.
    local stateMonitor = gui.Panel {
        width = 1,
        height = 1,
        --the campaign state doc id; must match CAMPAIGN_STATE_DOC below
        --(that local is declared later in this file, out of scope here).
        monitorGame = mod:GetDocumentPath("campaignstate"),
        refreshGame = function(element)
            if listPanel ~= nil and listPanel.valid then
                listPanel:FireEvent("refreshRun")
            end
        end,
    }

    --a full-width labeled bar rather than a bare "+" icon: always visible,
    --obvious, and immune to the style-settle quirk the icon button needed
    --the settleLayout hack for.
    local addBar = gui.Label {
        classes = { "bordered", "hoverable", "bgAlt", "fgMuted" },
        width = "100%",
        height = "auto",
        textAlignment = "center",
        text = "+  Add to the run",
        borderBox = true,
        vpad = 6,
        tmargin = 6,
        bmargin = 4,
        press = function(element)
            if element.popup ~= nil then
                element.popup = nil
                return
            end
            element.popupPositioning = "panel"
            --popups re-root the style cascade; inherit the panel's theme
            --styles so bordered/bg/fg/hoverable/collapsed resolve.
            element.popupsInheritStyles = true
            element.popup = CreateAddPopup(element)
        end,
    }

    return gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",

        listPanel,
        addBar,
        stateMonitor,
    }
end

DockablePanel.Register {
    name = "Run",
    icon = "icons/standard/Icon_App_GameControls.png",
    vscroll = true,
    dmonly = true,
    minHeight = 200,
    content = function()
        return CreateRunPanel()
    end,
}

----------------------------------------------------------------------
-- Campaign state: a shared document holding the campaign's generic
-- state kit -- flags (booleans), counters (numbers, including the
-- shared "victories" counter), taken exits, and an append-only ledger
-- of what happened. Scene exits write here; the Rail's LOG zone will
-- read the ledger.
----------------------------------------------------------------------

local CAMPAIGN_STATE_DOC = "campaignstate"

mod:RegisterDocumentForCheckpointBackups(CAMPAIGN_STATE_DOC)

CampaignState = rawget(_G, "CampaignState") or {}

--The monitorGame path for panels that react to state changes.
function CampaignState.Path()
    return mod:GetDocumentPath(CAMPAIGN_STATE_DOC)
end

--Read-only snapshot of the state tables (never mutate the result).
function CampaignState.Get()
    local doc = mod:GetDocumentSnapshot(CAMPAIGN_STATE_DOC)
    local data = doc.data
    return {
        flags = data.flags or {},
        counters = data.counters or {},
        exits = data.exits or {},
        ledger = data.ledger or {},
    }
end

function CampaignState.GetFlag(key)
    return CampaignState.Get().flags[key] == true
end

function CampaignState.GetCounter(key)
    return CampaignState.Get().counters[key] or 0
end

function CampaignState.IsExitTaken(exitid)
    return CampaignState.Get().exits[exitid] == true
end

--Dev/reset utility: wipe the campaign state back to empty. Appends
--nothing; the ledger is cleared too.
function CampaignState.Reset()
    local doc = mod:GetDocumentSnapshot(CAMPAIGN_STATE_DOC)
    doc:BeginChange()
    doc.data.flags = {}
    doc.data.counters = {}
    doc.data.exits = {}
    doc.data.ledger = {}
    doc:CompleteChange("Reset campaign state")
end

--Apply a list of writes atomically and append a ledger line describing
--them. Each write is a table:
--  { kind = "flag",    key, value }         -- set a boolean flag
--  { kind = "counter", key, delta | set }   -- adjust or set a counter
--  { kind = "exit",    key }                -- record an exit as taken
function CampaignState.Apply(writes, ledgerText)
    local doc = mod:GetDocumentSnapshot(CAMPAIGN_STATE_DOC)
    doc:BeginChange()
    local data = doc.data
    data.flags = data.flags or {}
    data.counters = data.counters or {}
    data.exits = data.exits or {}
    data.ledger = data.ledger or {}

    for _, w in ipairs(writes or {}) do
        if w.kind == "flag" then
            data.flags[w.key] = w.value
        elseif w.kind == "counter" then
            if w.set ~= nil then
                data.counters[w.key] = w.set
            else
                data.counters[w.key] = (data.counters[w.key] or 0) + (w.delta or 0)
            end
        elseif w.kind == "exit" then
            data.exits[w.key] = true
        end
    end

    data.ledger[#data.ledger + 1] = {
        t = dmhub.serverTimeMilliseconds,
        text = ledgerText or "",
    }

    doc:CompleteChange(ledgerText or "Campaign state change")
end

----------------------------------------------------------------------
-- RichExit: the [[exit]] tag -- a scene card's exit block. Renders as
-- a Director-only framed block proposing this exit's writes (each with
-- a confirm checkbox; "ask" counters get a stepper); taking the exit
-- applies the confirmed writes to campaign state, appends the ledger
-- line, records the exit as taken, and queues the next scene on the
-- Run. Players never see it: exits are run furniture.
--
-- Annotation fields (authored data):
--  id       : string   stable guid; keys the taken-state in campaign state
--  label    : string   the exit's name, e.g. "The safehouse is secured"
--  writes   : list of {kind="flag", key, value, label}
--                     | {kind="counter", key, delta|set, ask, min, max, label}
--                     | {kind="victory", count, label}   (sugar: counter "victories")
--  nextDocid: string|false   journal doc to queue on the Run when taken
--  nextLabel: string|false   display name for the next scene
----------------------------------------------------------------------

---@class RichExit
RichExit = RegisterGameType("RichExit", "RichTag")
RichExit.tag = "exit"
RichExit.hasEdit = false
RichExit.id = false
RichExit.label = "Exit"
RichExit.writes = {}
RichExit.nextDocid = false
RichExit.nextLabel = false

function RichExit.Create()
    return RichExit.new {
        id = dmhub.GenerateGuid(),
    }
end

function RichExit.CreateDisplay(self)
    local resultPanel

    --per-write confirm state and ask-counter values, local to this render.
    local m_confirm = {}
    local m_counterValues = {}
    for i, w in ipairs(self:try_get("writes", {})) do
        m_confirm[i] = true
        if w.kind == "counter" and w.ask then
            m_counterValues[i] = w.set or 0
        end
    end

    --normalize a write to (writeTable, ledgerFragment) at take time.
    local function ResolveWrite(i, w)
        if w.kind == "victory" then
            local count = w.count or 1
            return { kind = "counter", key = "victories", delta = count },
                string.format("%s (+%d Victory)", w.label or "Victory", count)
        elseif w.kind == "counter" and w.ask then
            return { kind = "counter", key = w.key, set = m_counterValues[i] },
                string.format("%s = %d", w.label or w.key, m_counterValues[i])
        elseif w.kind == "counter" then
            local frag
            if w.set ~= nil then
                frag = string.format("%s = %d", w.label or w.key, w.set)
            else
                frag = string.format("%s %+d", w.label or w.key, w.delta or 0)
            end
            return { kind = "counter", key = w.key, set = w.set, delta = w.delta }, frag
        else
            return { kind = "flag", key = w.key, value = w.value },
                string.format("%s", w.label or w.key)
        end
    end

    local function BuildWriteRows()
        local rows = {}
        for i, w in ipairs(self:try_get("writes", {})) do
            local rowChildren = {}

            --explicit sizing: inside the document render context the themed
            --check's proportional sizing blows up against auto-sized rows.
            rowChildren[#rowChildren + 1] = gui.Check {
                text = w.label or w.key or "write",
                value = m_confirm[i],
                width = 360,
                height = 22,
                fontSize = 14,
                valign = "center",
                change = function(element)
                    m_confirm[i] = element.value == true
                end,
            }

            if w.kind == "counter" and w.ask then
                local valueLabel
                local function Bump(delta)
                    local v = (m_counterValues[i] or 0) + delta
                    if w.min ~= nil then v = math.max(w.min, v) end
                    if w.max ~= nil then v = math.min(w.max, v) end
                    m_counterValues[i] = v
                    valueLabel.text = tostring(v)
                end
                rowChildren[#rowChildren + 1] = gui.Button {
                    classes = { "sizeXxs" },
                    lmargin = 8,
                    text = "-",
                    press = function() Bump(-1) end,
                }
                valueLabel = gui.Label {
                    classes = { "fgStrong", "bold" },
                    width = 26,
                    height = "auto",
                    fontSize = 15,
                    textAlignment = "center",
                    valign = "center",
                    text = tostring(m_counterValues[i] or 0),
                }
                rowChildren[#rowChildren + 1] = valueLabel
                rowChildren[#rowChildren + 1] = gui.Button {
                    classes = { "sizeXxs" },
                    text = "+",
                    press = function() Bump(1) end,
                }
            end

            rows[#rows + 1] = gui.Panel {
                flow = "horizontal",
                width = "100%",
                height = 26,
                tmargin = 4,
                children = rowChildren,
            }
        end
        return rows
    end

    local exitid = self:try_get("id") or "exit"

    local m_taken = CampaignState.IsExitTaken(exitid)

    local takeButton
    local statusLabel

    local function RefreshTakenState()
        m_taken = CampaignState.IsExitTaken(exitid)
        if takeButton ~= nil and takeButton.valid then
            takeButton:SetClass("collapsed", m_taken)
        end
        if statusLabel ~= nil and statusLabel.valid then
            statusLabel:SetClass("collapsed", not m_taken)
        end
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel:SetClassTree("exitTaken", m_taken)
        end
    end

    takeButton = gui.Button {
        classes = { "sizeM" },
        halign = "left",
        tmargin = 8,
        text = "Take this exit",
        click = function(element)
            local writes = { { kind = "exit", key = exitid } }
            local frags = {}
            for i, w in ipairs(self:try_get("writes", {})) do
                if m_confirm[i] then
                    local write, frag = ResolveWrite(i, w)
                    writes[#writes + 1] = write
                    frags[#frags + 1] = frag
                end
            end

            local ledgerText = string.format("EXIT: %s", self:try_get("label", "Exit"))
            if #frags > 0 then
                ledgerText = ledgerText .. " -- " .. table.concat(frags, "; ")
            end

            local nextDocid = self:try_get("nextDocid")
            if type(nextDocid) == "string" and rawget(_G, "RunAgenda") ~= nil then
                local nextDoc = (dmhub.GetTable(CustomDocument.tableName) or {})[nextDocid]
                if nextDoc ~= nil then
                    RunAgenda.AddDocument(nextDoc)
                    ledgerText = ledgerText .. string.format(" -> %s", nextDoc.description or "next scene")
                end
            end

            CampaignState.Apply(writes, ledgerText)
            RefreshTakenState()
        end,
    }

    statusLabel = gui.Label {
        classes = { "fgMuted", "collapsed" },
        width = "100%",
        height = "auto",
        fontSize = 13,
        tmargin = 8,
        text = "Exit taken.",
    }

    local children = {}

    children[#children + 1] = gui.Label {
        classes = { "fgStrong", "bold" },
        width = "100%",
        height = "auto",
        fontSize = 15,
        text = string.format("EXIT - %s", self:try_get("label", "Exit")),
    }

    for _, row in ipairs(BuildWriteRows()) do
        children[#children + 1] = row
    end

    local nextLabel = self:try_get("nextLabel")
    if type(nextLabel) == "string" and nextLabel ~= "" then
        children[#children + 1] = gui.Label {
            classes = { "fgMuted" },
            width = "100%",
            height = "auto",
            fontSize = 13,
            tmargin = 6,
            text = string.format("Then: %s (queued on the Run)", nextLabel),
        }
    end

    children[#children + 1] = takeButton
    children[#children + 1] = statusLabel

    resultPanel = gui.Panel {
        classes = { "bordered" },
        flow = "vertical",
        width = "100%",
        height = "auto",
        borderBox = true,
        pad = 10,
        vmargin = 6,
        children = children,

        --exits are run furniture: players never see them.
        refreshTag = function(element, tag, match, token)
            self = tag or self
            element:SetClass("collapsed", token ~= nil and token.player == true)
            RefreshTakenState()
        end,

        --track cross-client state so a co-Director taking the exit
        --updates this render too.
        monitorGame = CampaignState.Path(),
        refreshGame = function(element)
            RefreshTakenState()
        end,

        create = function(element)
            RefreshTakenState()
        end,
    }

    return resultPanel
end

MarkdownDocument.RegisterRichTag(RichExit)

----------------------------------------------------------------------
-- The Flow lens: the chapter rendered as a graph. Nodes are the pages
-- of the chapter folder (the folder of the first document on the run);
-- edges are parsed from each page's "## Exit" links plus its [[exit]]
-- annotation's nextDocid. Tense comes from live state: a page whose
-- run item is checked off (or whose exit was taken) reads as
-- "happened"; the Rail's NOW item gets the accent edge; everything
-- else is "planned". Pure read-view; clicking a node opens the page.
----------------------------------------------------------------------

local FLOW_NODE_W = 150
local FLOW_NODE_H = 38
local FLOW_LEVEL_H = 68
local FLOW_COL_W = 162
local FLOW_MARGIN = 8

--the scene type letter, parsed from the page's italic subtitle line
--("*combat - Chapter 1: ...*" and friends).
local function FlowSceneType(doc)
    local content = doc:GetTextContent()
    local italic = string.match(content, "\n%*([^%*\n]+)%*")
    if italic == nil then
        return "?", ""
    end
    local word = string.lower(string.match(italic, "^(%a+)") or "")
    local letters = {
        combat = "C", montage = "M", negotiation = "N", interlude = "I",
        choice = "?", transition = ">", skill = "S",
    }
    return letters[word] or "-", italic
end

--Collect the chapter's nodes and edges and assign each node a level
--(BFS depth from the root nodes) and a column within its level.
local function BuildFlowGraph(folderid)
    local nodes = {}
    local byId = {}
    for id, doc in unhidden_pairs(dmhub.GetTable(CustomDocument.tableName) or {}) do
        if doc:try_get("parentFolder") == folderid then
            local node = { id = id, doc = doc, name = doc.description or "Untitled", edges = {}, incoming = 0 }
            nodes[#nodes + 1] = node
            byId[id] = node
        end
    end
    table.sort(nodes, function(a, b) return a.name < b.name end)

    --map "C1-NN"-style name prefixes to nodes for exit-link resolution.
    local byPrefix = {}
    for _, node in ipairs(nodes) do
        local prefix = string.match(node.name, "^(C%d+%-%d+)")
        if prefix ~= nil then
            byPrefix[prefix] = node
        end
    end

    for _, node in ipairs(nodes) do
        local seen = {}
        local function AddEdge(targetid)
            if targetid ~= nil and targetid ~= node.id and byId[targetid] ~= nil and not seen[targetid] then
                seen[targetid] = true
                node.edges[#node.edges + 1] = targetid
                byId[targetid].incoming = byId[targetid].incoming + 1
            end
        end

        local exitSection = string.match(node.doc:GetTextContent(), "## Exit(.*)$")
        if exitSection ~= nil then
            for target in string.gmatch(exitSection, "%[(C%d+%-%d+)") do
                local t = byPrefix[target]
                AddEdge(t ~= nil and t.id or nil)
            end
        end

        local ann = node.doc:try_get("annotations")
        local exitAnn = ann ~= nil and ann.exit or nil
        if exitAnn ~= nil and type(exitAnn) == "table" and exitAnn.typeName == "RichExit" then
            local nd = exitAnn:try_get("nextDocid")
            if type(nd) == "string" then
                AddEdge(nd)
            end
            node.exitId = exitAnn:try_get("id")
        end
    end

    --BFS levels from the roots (no incoming edges; fall back to the
    --first node so a cyclic or single-page folder still renders).
    local queue = {}
    for _, node in ipairs(nodes) do
        if node.incoming == 0 then
            node.level = 0
            queue[#queue + 1] = node
        end
    end
    if #queue == 0 and #nodes > 0 then
        nodes[1].level = 0
        queue[1] = nodes[1]
    end
    local head = 1
    while head <= #queue do
        local node = queue[head]
        head = head + 1
        for _, targetid in ipairs(node.edges) do
            local target = byId[targetid]
            if target.level == nil then
                target.level = node.level + 1
                queue[#queue + 1] = target
            end
        end
    end
    for _, node in ipairs(nodes) do
        node.level = node.level or 0
    end

    --column within level, in name order.
    local levels = {}
    for _, node in ipairs(nodes) do
        levels[node.level] = levels[node.level] or {}
        local list = levels[node.level]
        list[#list + 1] = node
        node.col = #list - 1
    end

    local maxLevel = 0
    local maxCols = 1
    for level, list in pairs(levels) do
        maxLevel = math.max(maxLevel, level)
        maxCols = math.max(maxCols, #list)
    end

    return nodes, byId, maxLevel, maxCols
end

--The folder the lens renders: the first REAL journal folder (builtin
--roots like "private"/"public" do not count) holding a document on the
--run, so the lens follows whatever chapter is being played.
local function FlowFolder()
    local foldersTable = assets.documentFoldersTable or {}
    for _, item in ipairs(GetRunItems()) do
        if item.itemType == "document" and item.tableName ~= nil then
            local doc = (dmhub.GetTable(item.tableName) or {})[item.docid]
            if doc ~= nil then
                local parent = doc:try_get("parentFolder")
                if type(parent) == "string" and foldersTable[parent] ~= nil then
                    return parent
                end
            end
        end
    end
    return nil
end

local function CreateFlowPanel()
    local canvas

    local function Rebuild()
        local folderid = FlowFolder()
        if folderid == nil then
            canvas.selfStyle.height = 60
            canvas.children = {
                gui.Label {
                    classes = { "fgMuted" },
                    width = "100%",
                    height = "auto",
                    vmargin = 8,
                    text = "Add a chapter page to the Run and the flow appears here.",
                },
            }
            return
        end

        local nodes, byId, maxLevel, maxCols = BuildFlowGraph(folderid)

        --tense sources: the run agenda and the campaign state.
        local doneDocids = {}
        local nowDocid = nil
        for _, item in ipairs(GetRunItems()) do
            if item.itemType == "document" then
                if item.done then
                    doneDocids[item.docid] = true
                elseif nowDocid == nil then
                    nowDocid = item.docid
                end
            end
        end
        local exitsTaken = CampaignState.Get().exits

        local function NodePos(node)
            local x = FLOW_MARGIN + node.col * FLOW_COL_W
            local y = FLOW_MARGIN + node.level * FLOW_LEVEL_H
            return x, y
        end

        local children = {}

        --edges first so nodes draw over them. Each edge is a thin
        --rotated panel from the source's bottom-center to the target's
        --top-center.
        for _, node in ipairs(nodes) do
            local x1, y1 = NodePos(node)
            x1 = x1 + FLOW_NODE_W / 2
            y1 = y1 + FLOW_NODE_H
            for _, targetid in ipairs(node.edges) do
                local target = byId[targetid]
                local x2, y2 = NodePos(target)
                x2 = x2 + FLOW_NODE_W / 2
                local dx = x2 - x1
                local dy = y2 - y1
                local len = math.sqrt(dx * dx + dy * dy)
                if len > 1 then
                    children[#children + 1] = gui.Panel {
                        bgimage = "panels/square.png",
                        bgcolor = "#ffffff26", --hairline, per the design system
                        width = len,
                        height = 2,
                        halign = "left",
                        valign = "top",
                        x = (x1 + x2) / 2 - len / 2,
                        y = (y1 + y2) / 2 - 1,
                        rotate = -math.deg(math.atan(dy, dx)),
                    }
                end
            end
        end

        for _, node in ipairs(nodes) do
            local x, y = NodePos(node)
            local letter, sceneType = FlowSceneType(node.doc)

            local happened = doneDocids[node.id] == true
                or (node.exitId ~= nil and exitsTaken[node.exitId] == true)
            local isNow = (node.id == nowDocid)

            local nodeClasses = { "bordered", "hoverable" }
            if happened then
                nodeClasses[#nodeClasses + 1] = "bgDisabled"
            else
                nodeClasses[#nodeClasses + 1] = "bgAlt"
            end
            if isNow then
                nodeClasses[#nodeClasses + 1] = "borderAccent"
            end

            local labelClasses = {}
            if happened then
                labelClasses[#labelClasses + 1] = "fgMuted"
            end

            children[#children + 1] = gui.Panel {
                classes = nodeClasses,
                flow = "horizontal",
                width = FLOW_NODE_W,
                height = FLOW_NODE_H,
                halign = "left",
                valign = "top",
                x = x,
                y = y,
                borderBox = true,
                pad = 5,

                click = function(element)
                    node.doc:ShowDocument()
                end,
                hover = function(element)
                    gui.Tooltip(string.format("%s\n%s", node.name, sceneType))(element)
                end,

                gui.Label {
                    classes = { "fgMuted", "bold" },
                    width = 16,
                    height = "auto",
                    fontSize = 13,
                    valign = "center",
                    textAlignment = "center",
                    text = letter,
                },
                gui.Label {
                    classes = labelClasses,
                    width = FLOW_NODE_W - 34,
                    height = "auto",
                    fontSize = 11,
                    valign = "center",
                    lmargin = 4,
                    maxWidth = FLOW_NODE_W - 34,
                    text = node.name,
                },
            }
        end

        canvas.selfStyle.height = FLOW_MARGIN * 2 + (maxLevel + 1) * FLOW_LEVEL_H
        canvas.selfStyle.width = math.max(FLOW_MARGIN * 2 + maxCols * FLOW_COL_W, 330)
        canvas.children = children
    end

    canvas = gui.Panel {
        flow = "none",
        width = 330,
        height = 60,

        monitorGame = mod:GetDocumentPath(RUN_AGENDA_DOC),
        refreshGame = function(element)
            Rebuild()
        end,
        create = function(element)
            Rebuild()
        end,
    }

    --second monitor: campaign state (exits taken recolor nodes).
    return gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",

        canvas,
        gui.Panel {
            width = 1,
            height = 1,
            monitorGame = mod:GetDocumentPath("campaignstate"),
            refreshGame = function(element)
                Rebuild()
            end,
        },
    }
end

DockablePanel.Register {
    name = "Flow",
    icon = "icons/standard/Icon_App_Journal.png",
    vscroll = true,
    dmonly = true,
    minHeight = 260,
    content = function()
        return CreateFlowPanel()
    end,
}

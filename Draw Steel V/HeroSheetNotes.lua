local mod = dmhub.GetModLoading()

--The Hero sheet's Notes: the Notes tab beside Features at Wide, the Notes
--pane at Medium. Each section of the Hero's notes (creature.notes) is a card:
--its title, then its text rendered as markdown with glossary terms
--(gui.MarkdownLabel, as the journal draws them). Clicking a card opens the
--note window: the markdown beside its preview, saved as you type (after a
--pause, and at once when the window closes), with Delete (asks first).
--"Add a section" opens the window empty; the section is made with the first
--thing typed.

HeroSheetNotes = rawget(_G, "HeroSheetNotes") or {}

--The old character sheet's limit on a note section's text, kept so both
--sheets accept the same notes.
local TEXT_LIMIT = 10000

--The note window's design size: a large window, so the note and its preview
--sit side by side.
local WINDOW_WIDTH = 1320
local WINDOW_BODY = 600

--- @class HeroNoteSection
--- @field title string
--- @field text string

--- The Hero's note sections as the sheet shows them: the saved notes, or one
--- empty Backstory section for a Hero who never had any (the old character
--- sheet's rule). A Hero who deleted every section has none.
--- @param creature creature
--- @return HeroNoteSection[]
local function Sections(creature)
    local notes = creature:try_get("notes")
    if notes ~= nil then
        return notes
    end
    return {{title = "Backstory", text = ""}}
end

--- The notes on the Hero itself, made real for a write (inside a save).
--- @param hero creature
--- @return HeroNoteSection[]
local function EnsureNotes(hero)
    return hero:get_or_add("notes", Sections(hero))
end

--A note changed: the character panel's notes watch notesRevision (the old
--sheet sets it the same way), and the sheet redraws at the end of the frame.
--- @param hero creature
local function Touched(hero)
    hero:get_or_add("notesRevision", "")
    local fields = hero --[[@as table]]
    fields.notesRevision = dmhub.GenerateGuid()
    HeroSheetRefresh.Changed()
end

--A field's small caps name in the note window, with an optional hint after it.
--- @param text string
--- @param hint nil|string
--- @return Panel
local function FieldName(text, hint)
    local children = {
        gui.Label{
            classes = {"heroSheetCardLabel"},
            text = string.upper(text),
            fontSize = 11.5,
            bold = true,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            textWrap = false,
        },
    }
    if hint ~= nil then
        children[#children+1] = gui.Label{
            classes = {"heroSheetCardSub"},
            text = hint,
            fontSize = 11.5,
            width = "auto",
            height = "auto",
            lmargin = 8,
            halign = "left",
            valign = "center",
            textWrap = false,
        }
    end
    return gui.Panel{
        width = "100%",
        height = 18,
        flow = "horizontal",
        bmargin = 4,
        children = children,
    }
end

--- The note window: the title, the markdown beside its preview, Delete
--- for a section that exists, Done. Everything typed saves after a pause and
--- at once when the window closes (it is the only way out, so a Hero switch
--- or the sheet closing always comes after it).
--- @param index nil|integer the section (nil: a new one, made when something is typed)
function HeroSheetNotes.OpenEditor(index)
    local token = HeroSheet.Token()
    if token == nil or not HeroSheetWrite.CanWrite() then
        return
    end
    local sections = Sections(token.properties)
    local section = index ~= nil and sections[index] or nil
    if index ~= nil and section == nil then
        return
    end
    local state = {
        index = index,
        title = section ~= nil and (section.title or "") or "",
        text = section ~= nil and (section.text or "") or "",
        deleted = false,
    }
    --The section as last saved. Sections are a list, so another client can
    --add or delete one and move this one: it is found again by its words.
    local saved = {title = state.title, text = state.text}
    --- @param notes HeroNoteSection[]
    --- @return nil|integer
    local function Find(notes)
        local function Same(note)
            return note ~= nil and (note.title or "") == saved.title and (note.text or "") == saved.text
        end
        if state.index ~= nil and Same(notes[state.index]) then
            return state.index
        end
        for i, note in ipairs(notes) do
            if Same(note) then
                return i
            end
        end
        return nil
    end
    --one pending save per window: the title and the text save together.
    local key = "note:" .. dmhub.GenerateGuid()
    local frame

    local function SaveSoon()
        HeroSheetWrite.SaveSoon(key, {
            charid = token.charid,
            description = cond(state.index == nil, "Add note", "Edit note"),
            execute = function(hero)
                local notes = EnsureNotes(hero)
                local at = nil
                if state.index ~= nil then
                    at = Find(notes)
                end
                --a new section, or one that is gone (another client or an
                --undo removed it): add it again.
                if at == nil then
                    notes[#notes+1] = {title = state.title, text = state.text}
                    at = #notes
                else
                    notes[at].title = state.title
                    notes[at].text = state.text
                end
                state.index = at
                saved = {title = state.title, text = state.text}
                Touched(hero)
            end,
        })
    end
    local function Close()
        if not state.deleted then
            HeroSheetWrite.Flush(key)
        end
    end

    --- @type Panel
    local preview
    local titleField = gui.Input{
        classes = {"heroSheetField"},
        text = state.title,
        placeholderText = "",
        width = "100%",
        height = HeroSheetWindow.TargetSize(34),
        hpad = 10,
        borderBox = true,
        border = 1,
        cornerRadius = 6,
        fontSize = 14,
        characterLimit = 120,
        editlag = 0.1,
        --an input reports its starting text as an edit too: only a change saves.
        edit = function(element)
            local title = element.text or ""
            if title ~= state.title then
                state.title = title
                SaveSoon()
            end
        end,
    }
    local textField = gui.Input{
        classes = {"heroSheetField"},
        text = state.text,
        placeholderText = "",
        width = "100%",
        height = "100%-22",
        hpad = 10,
        vpad = 8,
        borderBox = true,
        border = 1,
        cornerRadius = 6,
        fontSize = 13.5,
        fontFace = "courier",
        multiline = true,
        lineType = "MultiLineNewLine",
        textAlignment = "topleft",
        verticalScrollbar = true,
        characterLimit = TEXT_LIMIT,
        editlag = 0.25,
        edit = function(element)
            local text = element.text or ""
            if text ~= state.text then
                state.text = text
                preview.value = text
                SaveSoon()
            end
        end,
    }
    --the preview scrolls with a long note; the markdown is drawn as the
    --sheet's cards draw it, glossary terms included.
    preview = gui.MarkdownLabel{
        text = state.text,
        width = "100%-12",
        height = "auto",
        halign = "left",
        valign = "top",
    }
    local previewFrame = gui.Panel{
        classes = {"heroSheetFeatCard"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = "100%",
        height = "100%-22",
        hpad = 12,
        vpad = 8,
        borderBox = true,
        flow = "vertical",
        vscroll = true,
        preview,
    }

    local body = gui.Panel{
        width = "100%",
        height = WINDOW_BODY,
        flow = "vertical",
        FieldName("Title"),
        titleField,
        gui.Panel{
            width = "100%",
            height = string.format("100%%-%d", 22 + HeroSheetWindow.TargetSize(34) + 12),
            flow = "horizontal",
            tmargin = 12,
            gui.Panel{
                width = "50%-7",
                height = "100%",
                flow = "vertical",
                halign = "left",
                FieldName("Note", "# heading, **bold**, *italic*, - list"),
                textField,
            },
            gui.Panel{
                width = "50%-7",
                height = "100%",
                flow = "vertical",
                halign = "right",
                FieldName("Preview"),
                previewFrame,
            },
        },
    }

    --Delete asks first; a section never saved has nothing to delete.
    local deleteButton = nil
    if index ~= nil then
        deleteButton = HeroSheetTheme.WindowButton("Delete", function()
            local name = state.title
            if trim(name) == "" then
                name = "this section"
            end
            HeroSheetWindow.ShowDialog{
                title = string.format("Delete %s?", name),
                width = 520,
                bodyHeight = 22,
                body = HeroSheetWindow.DialogText("The section and its text go."),
                saveText = "Delete",
                onSave = function()
                    HeroSheetWrite.Flush(key)
                    state.deleted = true
                    local at = state.index
                    if at ~= nil then
                        HeroSheetWrite.Save{
                            charid = token.charid,
                            description = "Delete note",
                            execute = function(hero)
                                local notes = EnsureNotes(hero)
                                local found = Find(notes)
                                if found ~= nil then
                                    table.remove(notes, found)
                                end
                                Touched(hero)
                            end,
                        }
                    end
                    HeroSheetWindow.ClosePopup(frame)
                end,
            }
        end, false)
        deleteButton.selfStyle.lmargin = 0
        deleteButton.selfStyle.halign = "left"
    end

    frame = HeroSheetWindow.ShowDialog{
        title = cond(index == nil, "New note", "Edit note"),
        subtitle = token.name,
        width = WINDOW_WIDTH,
        bodyHeight = WINDOW_BODY,
        body = body,
        note = "Saved as you type.",
        footerLeft = deleteButton,
        onDone = Close,
        onCancel = Close,
    }
    --typing starts in the note, or in the title for a new one.
    dmhub.Schedule(0.05, function()
        if mod.unloaded or not textField.valid then
            return
        end
        gui.SetFocus(cond(index == nil, titleField, textField))
    end)
end

----------------------------------------------------------------------
--The pane.

--- @class HeroNoteCard
--- @field panel Panel
--- @field paint fun(index: integer, section: HeroNoteSection)

--A section's card: its title (Untitled, muted, when it has none) and its
--text as markdown. The markdown is drawn again only when the text changed.
--- @return HeroNoteCard
local function NewCard()
    local at = 1
    local shownText = nil
    local title = gui.Label{
        classes = {"heroSheetCardStrong"},
        fontSize = 15,
        bold = true,
        width = "100%",
        height = "auto",
        textWrap = true,
        interactable = false,
    }
    local text = gui.MarkdownLabel{
        text = "",
        width = "100%",
        height = "auto",
        tmargin = 4,
    }
    local panel = gui.Panel{
        classes = {"heroSheetFeatCard", "heroSheetNoteCard", "hoverable"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 8,
        width = "100%",
        height = "auto",
        flow = "vertical",
        hpad = 14,
        vpad = 10,
        borderBox = true,
        tmargin = 8,
        click = function(element)
            --a click on a glossary term (or any link) is the term's: it pins
            --its card there, so the note does not open as well.
            local onLink = false
            pcall(function()
                for _, label in ipairs(text:GetChildrenWithClassRecursive("label")) do
                    if (label --[[@as Label]]).linkHovered ~= nil then
                        onLink = true
                    end
                end
            end)
            if not onLink then
                HeroSheetNotes.OpenEditor(at)
            end
        end,
        title,
        text,
    }
    return {
        panel = panel,
        paint = function(index, section)
            at = index
            local name = section.title or ""
            local untitled = trim(name) == ""
            title.text = cond(untitled, "Untitled", name)
            title:SetClass("heroSheetCardStrong", not untitled)
            title:SetClass("heroSheetMuted", untitled)
            local body = section.text or ""
            if body ~= shownText then
                shownText = body
                text.value = body
            end
            text:SetClass("collapsed", trim(body) == "")
            panel:SetClass("hoverable", HeroSheetWrite.CanWrite())
        end,
    }
end

--- @param token CharacterToken
--- @return string
local function Signature(token)
    local parts = {tostring(HeroSheetWrite.CanWrite()), tostring(HeroSheet.Editing())}
    for _, section in ipairs(Sections(token.properties)) do
        parts[#parts+1] = (section.title or "") .. "\1" .. (section.text or "")
    end
    return table.concat(parts, "\2")
end

--- @class HeroNotesPane
--- @field bar Panel Edit mode's Add a section
--- @field body Panel the sections, scrolling once they are taller than their room
--- @field fit fun() the room changed: scroll if the sections no longer fit
--- @field setEditing fun(editing: boolean)

--- The Notes for the lists' frame (HeroSheetLists.Create places its Edit bar
--- and body). The sections are a HeroSheetRefresh block: they paint when a
--- note changes, here or on another client.
--- @return HeroNotesPane
function HeroSheetNotes.Create()
    --- @type fun()
    local FitScroll
    --- @type HeroNoteCard[]
    local cards = {}
    local holder = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }
    --Add a section as the list's last row, a dashed row; in Edit mode the
    --bar's button takes its place.
    local addRow = gui.Panel{
        classes = {"heroSklAdd", "hoverable"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 8,
        width = "100%",
        height = HeroSheetWindow.TargetSize(34),
        hpad = 12,
        borderBox = true,
        tmargin = 8,
        flow = "horizontal",
        click = function()
            HeroSheetNotes.OpenEditor(nil)
        end,
        gui.Panel{
            classes = {"heroSklAddIcon"},
            bgimage = "phosphor/plus-bold.png",
            width = 13,
            height = 13,
            rmargin = 8,
            halign = "left",
            valign = "center",
            interactable = false,
        },
        gui.Label{
            classes = {"heroSheetCardText"},
            text = "Add a section",
            fontSize = 14,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            textWrap = false,
            interactable = false,
        },
    }
    local bar = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        tmargin = 8,
        HeroSheetFeatures.BarButton("phosphor/plus-bold.png", "Add a section", function(element)
            HeroSheetNotes.OpenEditor(nil)
        end),
    }

    local function SyncAdd()
        addRow:SetClass("collapsed", HeroSheet.Editing() or not HeroSheetWrite.CanWrite())
    end

    local list = HeroSheetRefresh.Block({
        width = "100%-10",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        bmargin = 14,
        holder,
        addRow,
    }, {
        name = "notes",
        signature = Signature,
        refresh = function(panel, token)
            local sections = Sections(token.properties)
            for i, section in ipairs(sections) do
                local card = cards[i]
                if card == nil then
                    card = NewCard()
                    cards[i] = card
                    holder:AddChild(card.panel)
                end
                card.panel:SetClass("collapsed", false)
                card.paint(i, section)
            end
            for i = #sections + 1, #cards do
                cards[i].panel:SetClass("collapsed", true)
            end
            SyncAdd()
            FitScroll()
        end,
    })

    --scrolls once its content is taller (as the Features list); its height
    --is set by the lists' frame.
    local body = gui.Panel{
        width = "100%",
        height = "100%-6",
        flow = "vertical",
        tmargin = 6,
        --another Hero's notes start at the top.
        heroSheetHero = function(element)
            if element.vscroll then
                element.vscrollPosition = 1
            end
        end,
        list,
    }
    FitScroll = function()
        HeroSheetWindow.AfterLayout(function()
            if body.valid and not body.vscroll and list.renderedHeight > body.renderedHeight + 0.5 then
                body.vscroll = true
                body.hideObjectsOutOfScroll = true
            end
        end)
    end

    return {
        bar = bar,
        body = body,
        fit = function()
            FitScroll()
        end,
        setEditing = function(editing)
            SyncAdd()
        end,
    }
end

local mod = dmhub.GetModLoading()

-- A puzzle where journal entries go: a table item, an icon rail button and a
-- chat link. Each is the journal's own machinery, fed a stand-in entry
-- ("puzzle:<id>", CustomDocument.JournalEntryProviders): the table item's tile
-- shows the puzzle's state as its icon and kind line, a click (anyone's) opens
-- the puzzle window. Also the Puzzles panel row's drag to every surface (a
-- page, chat, the rail, the table, the map) and its Place menu.

local ENTRY_PREFIX = "puzzle"

---@param id string
---@return string
function PuzzlePlace.EntryId(id)
    return ENTRY_PREFIX .. ":" .. id
end

--The rail key: the journal's "journal:<entryid>" entry type.
---@param id string
---@return string
function PuzzlePlace.RailKey(id)
    return "journal:" .. PuzzlePlace.EntryId(id)
end

--The state as a word, and the icon that goes with it.
---@param id string
---@return string word, string icon
local function StateWordIcon(id)
    local status = Puzzle.Status(id)
    if status.solved then
        return cond(status.bypassed, "Bypassed", "Solved"), "phosphor/check-circle-fill.png"
    elseif status.failed then
        return "Failed", "phosphor/x-circle-fill.png"
    end
    return "Unsolved", "phosphor/puzzle-piece.png"
end

---@param id string
---@return table|nil
local function PuzzleEntry(id)
    if not Puzzle.Exists(id) then
        return nil
    end
    local word, icon = StateWordIcon(id)
    return {
        virtual = true,
        id = PuzzlePlace.EntryId(id),
        nodeType = "puzzle",
        description = Puzzle.Title(id),
        kindName = "Puzzle: " .. word,
        icon = icon,
        open = function()
            local fromChat = rawget(ChatItemLinks, "openingFromChat") == true
            Puzzle.OpenWindow(id, { where = cond(fromChat, "from chat", nil) })
        end,
        --the hover preview's body.
        DisplayPanel = function(self, args)
            local def = Puzzle.GetType(id)
            return gui.Label{
                classes = {"sizeS"},
                width = "100%",
                height = "auto",
                text = string.format("%s. %s.", def ~= nil and def.name or "Puzzle", word),
            }
        end,
    }
end

CustomDocument.JournalEntryProviders[ENTRY_PREFIX] = PuzzleEntry

--------------------------------------------------------------------------------
-- The table, the rail, chat
--------------------------------------------------------------------------------

--Put the puzzle on the Director's table (at a screen point, or the middle).
---@param id string
---@param screen any|nil a screen point
function PuzzlePlace.PutOnTable(id, screen)
    if not Tabletop.IsActive() then
        PuzzlePlace.SetStatus("The table is not showing.", nil)
        return
    end
    Tabletop.OpenDocItem(PuzzlePlace.EntryId(id), { screen = screen, placed = screen ~= nil })
    Puzzle.IndexPuzzle(id, { kind = "table" })
    PuzzlePlace.SetStatus(string.format("Put %s on your table. Share it from its title bar.", Puzzle.Title(id)), function()
        local key = Puzzle.HomeKey({ kind = "table" })
        if key ~= nil then
            PuzzlePlace.RemoveHome(id, key)
        end
    end)
end

---@param id string
---@param side string|nil
---@param target Panel|nil a rail or rail button it was dropped on
function PuzzlePlace.AddToRail(id, side, target)
    local key = PuzzlePlace.RailKey(id)
    if target ~= nil then
        IconRailKeyDrop(key, target)
    else
        IconRailKeyAdd(key, side or "left")
    end
    Puzzle.IndexPuzzle(id, { kind = "rail" })
    PuzzlePlace.SetStatus(string.format("Added %s to your icon rail.", Puzzle.Title(id)), function()
        local homeKey = Puzzle.HomeKey({ kind = "rail" })
        if homeKey ~= nil then
            PuzzlePlace.RemoveHome(id, homeKey)
        end
    end)
end

---@param id string
---@return ChatItemLink|nil
local function ChatItem(id)
    return ChatItemLinks.DocItem(PuzzlePlace.EntryId(id))
end

--Post a link in chat: anyone can click it to open the puzzle.
---@param id string
function PuzzlePlace.PostInChat(id)
    if ChatItemLinks.Send({ ChatItem(id) }) then
        PuzzlePlace.SetStatus(string.format("Posted %s in chat. Players can open it now.", Puzzle.Title(id)), nil)
    end
end

--------------------------------------------------------------------------------
-- The row's drag and menu
--------------------------------------------------------------------------------

---@param target Panel|nil
---@return boolean
local function IsRail(target)
    return target ~= nil and target.valid and (target:HasClass("iconRail") or target:HasClass("iconRailButton"))
end

--A row may be dropped on a rail; other drop targets are found by the mouse.
---@param target Panel|nil
---@return boolean
function PuzzlePlace.RowCanDragOnto(target)
    return IsRail(target) and rawget(_G, "IconRailKeyDrop") ~= nil
end

--The row is being dragged: a page or chat under it takes it (they show their
--own hints), then a rail, the table, the map.
---@param row Panel
---@param id string
---@param target Panel|nil
function PuzzlePlace.RowDraggingAnywhere(row, id, target)
    if rawget(_G, "IconRailDocDragging") ~= nil then
        IconRailDocDragging(cond(IsRail(target), target, nil))
    end
    local overItemTarget = ChatItemLinks.Dragging(function()
        return { ChatItem(id) }
    end, {
        dropItems = function()
            ---@type ItemLinkDrop
            local item = { kind = "richtag", richTag = RichPuzzle.new{ puzzleid = id }, name = Puzzle.Title(id) }
            return { item }
        end,
    })
    if overItemTarget or IsRail(target) then
        Tabletop.JournalRowDragEnded(row)
        PuzzlePlace.RowDragEnded()
        return
    end
    if dmhub.panelDropSurface == "table" then
        PuzzlePlace.RowDragEnded()
        Tabletop.JournalRowDragging(row, PuzzlePlace.EntryId(id))
        return
    end
    Tabletop.JournalRowDragEnded(row)
    PuzzlePlace.RowDragging(id)
end

---@param row Panel
---@param id string
---@param target Panel|nil
function PuzzlePlace.RowDroppedAnywhere(row, id, target)
    Tabletop.JournalRowDragEnded(row)
    if rawget(_G, "IconRailDocDragging") ~= nil then
        IconRailDocDragging(nil)
    end
    if ChatItemLinks.Dropped() then
        PuzzlePlace.RowDragEnded()
        return
    end
    if IsRail(target) then
        PuzzlePlace.RowDragEnded()
        PuzzlePlace.AddToRail(id, nil, target)
        return
    end
    if dmhub.panelDropSurface == "table" then
        PuzzlePlace.RowDragEnded()
        PuzzlePlace.PutOnTable(id, dmhub.mouseScreenPosition)
        return
    end
    PuzzlePlace.RowDropped(id)
end

--The Place menu (the row's Place button and right-click): every destination
--without dragging.
---@param id string
---@param close fun()
---@return table[]
function PuzzlePlace.MenuEntries(id, close)
    local entries = {
        { text = "Place on map", click = function()
            close()
            PuzzlePlace.StartPlacing(id)
        end },
        { text = "Lock the selected object", click = function()
            close()
            PuzzlePlace.LockSelected(id)
        end },
    }
    if Puzzle.Exists(id) then
        if Tabletop.IsActive() then
            entries[#entries + 1] = { text = "Put on your table", click = function()
                close()
                PuzzlePlace.PutOnTable(id, nil)
            end }
        end
        if rawget(_G, "IconRailKeyAdd") ~= nil and dmhub.GetSettingValue("iconrail") == true then
            entries[#entries + 1] = { text = "Add to your rail", click = function()
                close()
                PuzzlePlace.AddToRail(id, "left", nil)
            end }
        end
        entries[#entries + 1] = { text = "Post in chat", click = function()
            close()
            PuzzlePlace.PostInChat(id)
        end }
    end
    return entries
end

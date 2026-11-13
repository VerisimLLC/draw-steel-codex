local mod = dmhub.GetModLoading()

--The Hero sheet Inventory's add pane: the compendium's items in the item
--pane's place, opened by the list's Add items. A row shows the item's hover
--card, expands in place on click, adds one or its bundle with Add and drags
--onto the list or the stash. Rows are built as the list scrolls and painted
--again on each change.
--This mod loads before Draw Steel V: the sheet's globals are only read
--inside functions.

HeroSheetInventoryAdd = rawget(_G, "HeroSheetInventoryAdd") or {}

--Sizes in sheet units, and how many rows to build at a time as the list scrolls.
local ROW_HEIGHT = 44
--a row and its gap above, and the rows painted at once (the view and some).
local ROW_PITCH = ROW_HEIGHT + 6
local POOL = 26

--- @class HeroAddEntry
--- @field key string "add|<itemid>"
--- @field itemid string
--- @field name string
--- @field kind string
--- @field item table the tbl_Gear row
--- @field quantity integer what Add gives (one, or the item's bundle)
--- @field hidden boolean hidden from players (the Director sees it marked)
--- @field equipped boolean always false
--- @field equippable boolean always false
--- @field stash boolean always true: the hover card shows no worn state

--- The items the add pane offers: the compendium less deleted and unique
--- items, and for a player less those hidden from players (as the old grid).
--- @return HeroAddEntry[]
local function Offered()
    local result = {}
    local hideByDefault = dmhub.GetSettingValue("hideitems")
    for itemid, item in unhidden_pairs(dmhub.GetTable("tbl_Gear") or {}) do
        if not item:has_key("hidden") and not item:has_key("uniqueItem") then
            local hidden = item:try_get("hiddenFromPlayers", hideByDefault) == true
            if dmhub.isDM or not hidden then
                result[#result+1] = {
                    key = "add|" .. itemid,
                    itemid = itemid,
                    name = item.name,
                    kind = HeroSheetInventoryActions.KindOf(item),
                    item = item,
                    quantity = item:TradedQuantity(),
                    hidden = hidden,
                    equipped = false,
                    equippable = false,
                    stash = true,
                }
            end
        end
    end
    table.sort(result, function(left, right)
        return left.name < right.name
    end)
    return result
end

--- An item's full text for its expanded row: a leveled treasure's three
--- Levels in the book's order, else its description.
--- @param item table
--- @return string
local function FullText(item)
    if HeroSheetInventoryActions.KindOf(item) == "leveled" then
        local parts = {}
        for _, tier in ipairs(HeroSheetInventory.TIERS) do
            local text = item:try_get(tier.field)
            if type(text) == "string" and trim(text) ~= "" then
                parts[#parts+1] = string.format("**%s:** %s", tier.name, trim(text))
            end
        end
        return table.concat(parts, "\n\n")
    end
    local text = item:try_get("description")
    return type(text) == "string" and trim(text) or ""
end

--- Delete a compendium item, after asking. It is hidden as the old grid's
--- Delete Item hides it; items already carried stay.
--- @param entry HeroAddEntry
--- @param onDeleted nil|fun() the list reads the compendium again
local function ConfirmDelete(entry, onDeleted)
    HeroSheetWindow.ShowDialog{
        title = string.format("Delete %s?", entry.name),
        width = 460,
        bodyHeight = 24,
        saveText = "Delete",
        body = HeroSheetWindow.DialogText("It leaves the compendium. Items already carried stay."),
        onSave = function()
            local item = entry.item
            item.hidden = true
            dmhub.SetAndUploadTableItem("tbl_Gear", item)
            if onDeleted ~= nil then
                onDeleted()
            end
            return true
        end,
    }
end

--- One more compendium item like this one (the old grid's Duplicate Item).
--- @param entry HeroAddEntry
local function Duplicate(entry)
    local copy = HeroSheetInventoryActions.CopyItem(entry.item)
    copy.name = string.format("%s (Dup.)", copy.name)
    dmhub.SetAndUploadTableItem("tbl_Gear", copy)
end

--- @class HeroAddPaneArgs
--- @field close fun() the x: back to the item pane

--- The add pane. Fire "heroSheetAddOpen" on it when it shows (it reads the
--- compendium again then), and "heroSheetAddWarm" when it is about to (it
--- builds its rows ahead, a frame at a time).
--- @param args HeroAddPaneArgs
--- @return Panel
function HeroSheetInventoryAdd.Create(args)
    local state = {
        filter = "all",
        query = "",
        --- @type HeroAddEntry[]
        offered = {},
        --- @type HeroAddEntry[]
        matches = {},
        --the first match the row pool shows.
        first = 1,
        --- @type nil|string the expanded row's item
        open = nil,
        --a New custom item waiting for the editor: "inventory" or "compendium".
        --- @type nil|string
        pendingNew = nil,
    }
    --- @type fun()
    local Paint
    --- @type fun(top: boolean)
    local Refilter
    --- @type Panel
    local pane

    ------------------------------------------------------------------
    --Heading, chips and search.

    local close = gui.Panel{
        classes = {"heroSheetKeb", "heroSheetKebAlways", "hoverable"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 5,
        width = HeroSheetWindow.TargetSize(28),
        height = HeroSheetWindow.TargetSize(28),
        halign = "right",
        valign = "center",
        click = function(element)
            args.close()
        end,
        gui.Panel{
            classes = {"heroSheetFg"},
            bgimage = "phosphor/x-bold.png",
            width = 12,
            height = 12,
            halign = "center",
            valign = "center",
            interactable = false,
        },
    }
    local heading = gui.Panel{
        width = "100%",
        height = 30,
        flow = "horizontal",
        gui.Label{
            classes = {"heroSheetCardStrong"},
            text = "ADD ITEMS",
            fontSize = 16,
            bold = true,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            textWrap = false,
        },
        gui.Label{
            classes = {"heroSheetCardSub"},
            text = "Compendium",
            fontSize = 13,
            width = "auto",
            height = "auto",
            lmargin = 8,
            halign = "left",
            valign = "center",
            textWrap = false,
        },
        close,
    }
    --- @type table<string, Panel>
    local chips = {}
    local chipRow = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        tmargin = 6,
    }
    --the list's own chips, so both sides filter alike.
    local chipDefs = {{id = "all", chip = "All"}}
    for _, kind in ipairs(HeroSheetInventory.KINDS) do
        chipDefs[#chipDefs+1] = kind
    end
    for _, def in ipairs(chipDefs) do
        local id = def.id
        local chip = gui.Panel{
            classes = {"heroSklChip", "hoverable", cond(id == "all", "heroSklPicked", nil)},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 14,
            width = "auto",
            height = HeroSheetWindow.TargetSize(28),
            hpad = 10,
            borderBox = true,
            rmargin = 6,
            bmargin = 6,
            --packed from the left (a full-width row spreads unaligned children).
            halign = "left",
            valign = "center",
            click = function(element)
                state.filter = id
                for chipId, chipPanel in pairs(chips) do
                    chipPanel:SetClassTree("heroSklPicked", chipId == id)
                end
                state.open = nil
                Refilter(true)
            end,
            gui.Label{
                classes = {"heroSklChipText", cond(id == "all", "heroSklPicked", nil)},
                text = def.chip,
                fontSize = 12.5,
                width = "auto",
                height = "auto",
                valign = "center",
                textWrap = false,
                interactable = false,
            },
        }
        chips[id] = chip
        chipRow:AddChild(chip)
    end
    local search = gui.SearchInput{
        placeholderText = "Search the compendium",
        text = "",
        width = "100%",
        height = HeroSheetWindow.TargetSize(28),
        borderBox = true,
        tmargin = 2,
        edit = function(element)
            state.query = string.lower(trim(element.text or ""))
            state.open = nil
            Refilter(true)
        end,
    }

    ------------------------------------------------------------------
    --The rows: a pool painted again for each change.

    --- @class HeroAddRow
    --- @field panel Panel
    --- @field text Panel the expanded text under the row
    --- @field paint fun(entry: HeroAddEntry)
    --- @field entry nil|HeroAddEntry

    --- @return HeroAddRow
    local function NewRow()
        local row = {entry = nil}
        local icon = HeroSheetInventory.Icon(30)
        local name = HeroSheetTheme.EllipsisLabel{
            classes = {"heroSheetCardStrong"},
            text = "",
            fontSize = 14,
            bold = true,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
        }
        --the Director's mark on an item hidden from players.
        local hiddenPill = gui.Label{
            classes = {"heroSheetPill", "collapsed"},
            text = "Hidden",
            bgimage = "panels/square.png",
            bgcolor = "clear",
            border = 1,
            cornerRadius = 8,
            width = "auto",
            height = 16,
            hpad = 6,
            borderBox = true,
            fontSize = 10.5,
            textWrap = false,
            lmargin = 6,
            valign = "center",
            interactable = false,
        }
        local sub = gui.Label{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 11.5,
            width = "auto",
            height = "auto",
            halign = "left",
            textWrap = false,
            interactable = false,
        }
        local words = gui.Panel{
            width = "100%-130",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "center",
            lmargin = 10,
            interactable = false,
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                interactable = false,
                name,
                hiddenPill,
            },
            sub,
        }
        --shown at all times, so the words never move.
        local menu = gui.Panel{
            classes = {"heroSheetKeb", "heroSheetKebAlways", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 5,
            width = HeroSheetWindow.TargetSize(24),
            height = HeroSheetWindow.TargetSize(24),
            halign = "right",
            valign = "center",
            rmargin = 6,
            click = function(element)
                local entry = row.entry
                if entry == nil then
                    return
                end
                HeroSheetLists.ShowMenu(element, {
                    {text = "Share to chat", click = function()
                        chat.ShareObjectInfo("tbl_Gear", entry.itemid)
                    end},
                    {text = "Edit", click = function()
                        if gamehud ~= nil and gamehud.createItemDialog ~= nil then
                            gamehud.createItemDialog.data.show(pane, entry.item)
                        end
                    end},
                    {text = "Duplicate", click = function()
                        Duplicate(entry)
                        --the compendium changed: the copy joins the list.
                        state.offered = Offered()
                        Refilter(false)
                    end},
                    "-",
                    {text = "Delete", danger = true, click = function()
                        ConfirmDelete(entry, function()
                            state.offered = Offered()
                            Refilter(false)
                        end)
                    end},
                })
            end,
            gui.Panel{
                classes = {"heroSheetFg"},
                bgimage = "phosphor/dots-three-bold.png",
                width = 14,
                height = 14,
                halign = "center",
                valign = "center",
                interactable = false,
            },
        }
        local add = gui.Label{
            classes = {"heroSheetSmallButton", "hoverable", "heroSheetOn"},
            text = "Add",
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 6,
            width = "auto",
            height = 26,
            hpad = 10,
            borderBox = true,
            fontSize = 12.5,
            textWrap = false,
            halign = "right",
            valign = "center",
            click = function(element)
                if row.entry ~= nil then
                    HeroSheetInventoryActions.AddToHero(row.entry.item)
                end
            end,
        }
        --the item's full text, shown under the row when it is clicked (a
        --sibling of the row, so the row's buttons stay its own children).
        local text = gui.Label{
            classes = {"heroSheetCardText", "collapsed"},
            text = "",
            markdown = true,
            fontSize = 13,
            width = "100%-40",
            height = "auto",
            halign = "right",
            textAlignment = "left",
            textWrap = true,
            tmargin = 4,
            bmargin = 6,
            interactable = false,
        }
        row.text = text
        local rowArgs = {
            classes = {"heroSheetListRow", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 8,
            width = "100%",
            height = ROW_HEIGHT,
            flow = "horizontal",
            hpad = 10,
            borderBox = true,
            tmargin = 6,
            --a click shows the item's full text under it; one row at a time.
            click = function(element)
                local entry = row.entry
                if entry ~= nil then
                    state.open = cond(state.open == entry.itemid, nil, entry.itemid)
                    Paint()
                end
            end,
            icon.panel,
            words,
            menu,
            add,
            gui.Panel{
                classes = {"heroSheetDragCover"},
                bgimage = "panels/square.png",
                cornerRadius = 8,
                floating = true,
                width = "100%+20",
                height = "100%",
                halign = "center",
                interactable = false,
            },
        }
        for argName, value in pairs(HeroSheetInventoryActions.DragFields("add", function()
            return row.entry --[[@as HeroInventoryEntry]]
        end)) do
            rowArgs[argName] = value
        end
        local panel = gui.Panel(HeroSheetTheme.HoverCard(rowArgs, function(pinned, close)
            local entry = row.entry
            if entry == nil then
                return gui.Panel{width = 1, height = 1}
            end
            local level = 1
            pcall(function() level = HeroSheet.Token().properties:CharacterLevel() end)
            return HeroSheetTheme.CardFrame(HeroSheetCard.ItemCard(entry, level, nil, pinned), pinned, close)
        end, false))
        row.panel = panel
        row.paint = function(entry)
            local same = row.entry ~= nil and row.entry.itemid == entry.itemid
            row.entry = entry
            icon.paint(entry --[[@as HeroInventoryEntry]])
            name.text = entry.name .. cond(entry.quantity > 1, string.format(" x%d", entry.quantity), "")
            name.selfStyle.maxWidth = cond(entry.hidden, "100%-60", "100%")
            hiddenPill:SetClass("collapsed", not entry.hidden)
            sub.text = HeroSheetInventory.KindLine(entry.item, entry.kind)
            local expanded = state.open == entry.itemid
            text:SetClass("collapsed", not expanded)
            if expanded then
                text.text = FullText(entry.item)
            end
            panel:SetClass("heroSheetRowPinned", expanded)
            if not same then
                panel.tooltip = nil
            end
        end
        return row --[[@as HeroAddRow]]
    end

    --The list shows a fixed pool of rows, repainted as it scrolls, with
    --spacers above and below that keep the scroll length right. Rows are
    --costly to build, so a paint builds only the rows it needs now and
    --"heroSheetAddWarm" builds the rest, one a frame, ahead of the first click.
    --- @type HeroAddRow[]
    local rows = {}
    local topSpacer = gui.Panel{width = "100%", height = 0, interactable = false}
    local bottomSpacer = gui.Panel{width = "100%", height = 0, interactable = false}
    --the rows in order between the spacers, however late each is built.
    local rowHolder = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }
    local holder = gui.Panel{
        width = "100%-12",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        bpad = 10,
        borderBox = true,
        topSpacer,
        rowHolder,
        bottomSpacer,
    }

    --- Builds the pool's rows up to the i-th, in order.
    --- @param i integer
    --- @return HeroAddRow
    local function BuildRows(i)
        for j = #rows + 1, i do
            local row = NewRow()
            rows[j] = row
            row.panel:SetClass("collapsed", true)
            rowHolder:AddChild(row.panel)
            rowHolder:AddChild(row.text)
        end
        return rows[i]
    end
    local warming = false
    local empty = gui.Label{
        classes = {"heroSheetCardSub", "collapsed"},
        text = "No items match.",
        fontSize = 13,
        width = "auto",
        height = "auto",
        tmargin = 10,
    }
    --- @type Panel
    local listScroll

    --- The first match the pool shows, from how far the list is scrolled
    --- (the engine's vscrollPosition runs 1 at the top to 0 at the end).
    --- @return integer
    local function FirstIndex()
        local count = #state.matches
        if count <= POOL or not listScroll.vscroll then
            return 1
        end
        local range = math.max(0, holder.renderedHeight - listScroll.renderedHeight)
        local offset = (1 - listScroll.vscrollPosition) * range
        --the pool starts a few rows above the view, so a scroll shows painted rows.
        local first = math.floor(offset / ROW_PITCH) + 1 - 6
        return math.max(1, math.min(first, count - POOL + 1))
    end

    --- Paint the pool with the matches from the first in view; only when that
    --- changes, unless forced.
    --- @param force boolean
    local function PaintWindow(force)
        local first = FirstIndex()
        if not force and first == state.first then
            return
        end
        state.first = first
        local matches = state.matches
        --an expanded row scrolled out of the pool folds, so every row outside
        --it is one pitch tall and the spacers stay exact.
        if state.open ~= nil then
            local inPool = false
            for i = first, math.min(#matches, first + POOL - 1) do
                if matches[i].itemid == state.open then
                    inPool = true
                end
            end
            if not inPool then
                state.open = nil
            end
        end
        topSpacer.selfStyle.height = (first - 1) * ROW_PITCH
        for i = 1, POOL do
            local entry = matches[first + i - 1]
            local row = rows[i]
            if row == nil and entry ~= nil then
                row = BuildRows(i)
            end
            if row ~= nil then
                row.panel:SetClass("collapsed", entry == nil)
                if entry ~= nil then
                    row.paint(entry)
                else
                    row.text:SetClass("collapsed", true)
                    row.entry = nil
                end
            end
        end
        bottomSpacer.selfStyle.height = math.max(0, #matches - (first + POOL - 1)) * ROW_PITCH
        empty:SetClass("collapsed", #matches > 0)
    end

    listScroll = gui.Panel{
        width = "100%",
        height = "100%-170",
        flow = "vertical",
        vscroll = true,
        tmargin = 6,
        --the pool follows the scroll.
        thinkTime = 0.05,
        think = function(element)
            PaintWindow(false)
        end,
        holder,
        empty,
    }

    --- The matches again (chip, search or compendium changed); top: back to
    --- the start of the list.
    --- @param top boolean
    Refilter = function(top)
        local matches = {}
        for _, entry in ipairs(state.offered) do
            if HeroSheetInventory.Matches(entry, state.filter, state.query) then
                matches[#matches+1] = entry
            end
        end
        state.matches = matches
        if top then
            listScroll.vscrollPosition = 1
            state.first = 1
        end
        PaintWindow(true)
    end

    --a row's click (expand) repaints the pool where it is.
    Paint = function()
        PaintWindow(true)
    end

    ------------------------------------------------------------------
    --The foot: New custom item, and the drag's hint.

    --- New custom item: to this Hero (a unique item, as Make unique makes) or
    --- to the compendium, through the old grid's item editor.
    --- @param anchor Panel
    local function NewItemMenu(anchor)
        HeroSheetLists.ShowMenu(anchor, {
            {text = "Add to inventory", click = function()
                state.pendingNew = "inventory"
                if gamehud ~= nil and gamehud.createItemDialog ~= nil then
                    gamehud.createItemDialog.data.show(pane)
                end
            end},
            {text = "Add to the compendium", click = function()
                state.pendingNew = "compendium"
                if gamehud ~= nil and gamehud.createItemDialog ~= nil then
                    gamehud.createItemDialog.data.show(pane)
                end
            end},
        })
    end
    local newButton
    newButton = gui.Label{
        classes = {"heroSheetButton", "hoverable"},
        text = "New custom item",
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = "auto",
        height = 32,
        hpad = 12,
        borderBox = true,
        fontSize = 13,
        textWrap = false,
        halign = "left",
        valign = "center",
        click = function(element)
            NewItemMenu(newButton)
        end,
    }
    local foot = gui.Panel{
        width = "100%",
        height = 40,
        flow = "horizontal",
        valign = "bottom",
        tmargin = 6,
        newButton,
        gui.Label{
            classes = {"heroSheetCardSub"},
            text = "Drag a row into your list, or click Add",
            fontSize = 11.5,
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
            textWrap = false,
        },
    }

    pane = gui.Panel{
        classes = {"heroSheetPlate", "heroSheetBlock", "collapsed"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = 430,
        height = "100%",
        flow = "vertical",
        tpad = 12,
        bpad = 10,
        hpad = 16,
        borderBox = true,
        --the pointer rests on Add items: build the rest of the pool, a row
        --a frame, so the click finds it built.
        heroSheetAddWarm = function(element)
            if warming or #rows >= POOL then
                return
            end
            warming = true
            dmhub.Coroutine(function()
                while #rows < POOL do
                    if mod.unloaded or not element.valid then
                        return
                    end
                    BuildRows(#rows + 1)
                    coroutine.yield()
                end
                warming = false
            end)
        end,
        heroSheetAddOpen = function(element)
            state.offered = Offered()
            state.open = nil
            newButton:SetClass("collapsed", not HeroSheetInventoryActions.CanAdd())
            Refilter(true)
        end,
        --the old grid's item editor: an edit, a duplicate or a delete changed
        --the compendium; a new item may be this Hero's.
        refreshInventory = function(element)
            state.offered = Offered()
            Refilter(false)
        end,
        newItem = function(element, itemid)
            local mode = state.pendingNew
            state.pendingNew = nil
            local item = (dmhub.GetTable("tbl_Gear") or {})[itemid]
            if item ~= nil and mode == "inventory" then
                --the Hero's own item: unique and out of the compendium, as
                --Make unique leaves one.
                if not item:IsAmmoForWeapon() then
                    item.unique = true
                end
                item.hidden = true
                dmhub.SetAndUploadTableItem("tbl_Gear", item)
                HeroSheetInventoryActions.AddToHero(item)
            end
            state.offered = Offered()
            Refilter(false)
        end,
        heading,
        chipRow,
        search,
        listScroll,
        foot,
    }
    return pane
end

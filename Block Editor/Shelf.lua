local mod = dmhub.GetModLoading()

--[[
    BEShelf: the column of blocks that can be added, beside the page.

    The host's shelfSections say what the shelf holds: each section lists the
    blocks that fit one kind of list ("Common" are steps, "Inside a power roll
    tier" fit a tier). Rows are small blocks in the colour of the block they
    add. Drag a row onto a slot, or click it to add the block at the end of
    the first list it fits. The search box filters rows by name.
]]

local T = UIText.T

--- @class BEShelf
BEShelf = {}

--- The blocks a shelf section lists: those that fit its kind of list.
--- @param fits string
--- @return BlockDecl[]
local function _blocksFor(fits)
    local result = {}
    for _, decl in ipairs(Block.All("block")) do
        --- @cast decl BlockDecl
        if decl.shelf ~= false then
            for _, kind in ipairs(decl.fits or {}) do
                if kind == fits then
                    result[#result + 1] = decl
                    break
                end
            end
        end
    end
    return result
end

--- One shelf row: grip, glyph and the block's name.
--- @param decl BlockDecl
--- @return Panel
local function _row(decl)
    local children = {
        gui.Panel{ classes = {"beGrip", "beShelfGrip"}, interactable = false },
    }
    local glyph = BEStyles.Glyph(decl.group)
    if glyph ~= nil then
        glyph:SetClass("beShelfGlyph", true)
        children[#children + 1] = glyph
    end
    children[#children + 1] = gui.Label{
        classes = {"beShelfName"},
        text = decl.label,
        interactable = false,
    }
    return gui.Panel{
        classes = {"beShelfRow", BEStyles.GroupClass(decl.group)},
        data = { block = decl.id, name = string.lower(decl.label) },
        children = children,
        draggable = true,
        --the row stays put; the ghost made in BeginDrag is what moves.
        dragMove = false,
        dragThreshold = 4,
        beginDrag = function(element)
            BEStack.BeginDrag(element, { blockId = element.data.block })
        end,
        click = function(element)
            if not BEStack.JustDragged() then
                BEStack.Append(element, element.data.block)
            end
        end,
        linger = function(element)
            if decl.desc ~= nil then
                gui.Tooltip(decl.desc)(element)
            end
        end,
        shelfSearch = function(element, text)
            element:SetClass("collapsed", text ~= "" and string.find(element.data.name, text, 1, true) == nil)
        end,
    }
end

--- Builds the shelf column for a host.
--- @param host BlockHost|nil
--- @return Panel
function BEShelf.Create(host)
    local sections = host ~= nil and host.shelfSections or nil
    if sections == nil or #sections == 0 then
        sections = { { title = "Blocks", fits = "step" } }
    end

    local children = {}
    for _, section in ipairs(sections) do
        local decls = _blocksFor(section.fits)
        local header, rule = BEStyles.SectionHeader{
            title = section.title,
            count = tostring(#decls),
            shelf = true,
        }
        children[#children + 1] = header
        children[#children + 1] = rule
        for _, decl in ipairs(decls) do
            children[#children + 1] = _row(decl)
        end
    end

    --- @type Panel
    local list
    list = gui.Panel{
        classes = {"beShelfList"},
        vscroll = true,
        children = children,
    }

    return gui.Panel{
        classes = {"beShelfColumn"},
        gui.SearchInput{
            --the options replace SearchInput's own classes, so it is named again.
            classes = {"searchInput", "beShelfSearch"},
            placeholderText = T("blockeditor.search"),
            search = function(element, text)
                list:FireEventTree("shelfSearch", text)
            end,
        },
        list,
    }
end

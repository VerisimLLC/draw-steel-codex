local mod = dmhub.GetModLoading()

--[[
    BESlots: a sentence drawn as a wrapping row of words, where every word an
    author can change is a small panel of its own (a dark inset; white with
    dark text under the pointer). Clicking one opens its picker at the pointer.

    Why not one label with <link> words: the engine shows a pointing-hand
    cursor over every label link and Lua cannot turn it off. Separate panels
    keep the normal arrow, and hover alone says a word can be clicked.

    The pickers are chosen by the slot's kind (choice, stat, test, number,
    formula, text, many). A host or block never draws its own controls: it
    declares slots, and BESlots draws them (plan section 2). An amount slot
    (BlockSlot.amount) opens the kinds of amount, and shows each number, stat
    and sign of its formula as a word of its own; a number slot opens a box.
]]

local T = UIText.T

--- @class BESlots
BESlots = {}

--- The words of a text, each with whether a space came before it.
--- @param text string
--- @return {word: string, spaced: boolean}[], boolean trailingSpace
local function _splitWords(text)
    local result = {}
    for spaces, word in string.gmatch(text, "(%s*)(%S+)") do
        result[#result + 1] = { word = word, spaced = spaces ~= "" }
    end
    return result, string.match(text, "%s$") ~= nil
end

--- Text safe to put inside a label's rich text: an author's "<" would start a tag.
--- @param text string
--- @return string
local function _escape(text)
    return (string.gsub(text, "<", "<noparse><</noparse>"))
end

--- The entries of a slot's picker: {text, value} pairs, "-" for a divider, and
--- {text, action} for an entry that opens a box to type in.
--- @param slot BlockSlot
--- @return table[]
local function _choices(slot)
    local result = {}
    if slot.kind == "choice" or slot.kind == "formula" then
        for _, option in ipairs(Block.SlotOptions(slot)) do
            result[#result + 1] = { text = option.text, value = option.id }
        end
        if slot.kind == "formula" then
            result[#result + 1] = "-"
            result[#result + 1] = { text = T("blockeditor.menu.formula"), action = "type" }
        end
    elseif slot.kind == "stat" then
        for _, stat in ipairs(Block.All("stat")) do
            --- @cast stat BlockStat
            result[#result + 1] = { text = stat.words, value = stat.id }
        end
    elseif slot.kind == "test" then
        for _, test in ipairs(Block.All("test")) do
            --- @cast test BlockTest
            result[#result + 1] = { text = test.prose, value = test.id }
        end
        result[#result + 1] = "-"
        result[#result + 1] = { text = T("blockeditor.menu.build_test"), disabled = true }
    else
        result[#result + 1] = { text = T("blockeditor.menu.edit_text"), action = "type" }
    end
    return result
end

--- The word being typed over, if any: its box and how to end or cancel it.
--- @type {input: Panel, finish: fun(), cancel: fun()}|nil
local g_activeEdit = nil

--- Cancels the word being typed over, if there is one (the editor's Escape).
--- @return boolean cancelled whether there was an edit to cancel
function BESlots.CancelEdit()
    local edit = g_activeEdit
    if edit == nil or not edit.input.valid then
        g_activeEdit = nil
        return false
    end
    edit.cancel()
    return true
end

--a value longer than this is typed in a box the width of the sentence, wrapping.
local LONG_TEXT = 40
--roughly how wide one character is, to size a box to the word it replaces.
local CHAR_WIDTH = 9

--- Turns a slot's words into a text box where they sit, to type its value
--- over (ledger 2026-11-27: no pop-up to go through). Enter or clicking away
--- keeps the text; Escape puts the words back as they were.
--- @param word Panel the clicked word, inside a sentence row
--- @param value any the current value
--- @param commit fun(value: any, source: Panel) source is the box, still inside the editor
--- @param start? string what the box starts with, when not the value itself (kept even if not retyped)
local function _editInPlace(word, value, commit, start)
    local row = word.parent
    local slotId = word.data ~= nil and word.data.slot or nil
    if row == nil or slotId == nil then
        return
    end
    local text = tostring(value or "")
    local shown = start or text
    local formula = word:HasClass("beWordFormula")
    --the slot's words (one slot can wrap across several), hidden while the box is up.
    local hidden = {}
    local first = nil
    for index, child in ipairs(row.children) do
        if child.data ~= nil and child.data.slot == slotId then
            hidden[#hidden + 1] = child
            first = first or index
        end
    end
    if first == nil then
        return
    end

    local done = false
    --- @type Input
    local input
    --- Puts the words back and takes the box away, saving nothing.
    local function Restore()
        done = true
        if g_activeEdit ~= nil and g_activeEdit.input == input then
            g_activeEdit = nil
        end
        if row.valid then
            for _, child in ipairs(hidden) do
                if child.valid then
                    child:SetClass("collapsed", false)
                end
            end
            if input.valid then
                input:DestroySelf()
            end
        end
    end
    local function Finish()
        if done then
            return
        end
        local typed = input.text
        if typed ~= text then
            done = true
            g_activeEdit = nil
            --the editor redraws the sentence after a change, which removes the box.
            commit(tonumber(typed) ~= nil and type(value) == "number" and tonumber(typed) or typed, input)
            return
        end
        Restore()
    end
    local long = #shown > LONG_TEXT
    input = gui.Input{
        classes = {"beWordInput", formula and "beWordInputFormula" or nil},
        width = long and "100%" or math.max(60, (#shown + 3) * CHAR_WIDTH),
        height = "auto",
        minHeight = 24,
        lmargin = first > 1 and BEStyles.SIZES.WORD_GAP or 0,
        text = shown,
        selectAllOnFocus = true,
        restoreOriginalTextOnEscape = true,
        lineType = long and "MultiLineSubmit" or "SingleLine",
        create = function(element)
            element.hasInputFocus = true
        end,
        submit = function()
            Finish()
        end,
        change = function()
            Finish()
        end,
        --Escape restores the text without a change event, so the edit ends on focus loss too.
        defocus = function()
            Finish()
        end,
        deselect = function()
            Finish()
        end,
        --above the editor window's own Escape (a dropdown's priority), so Escape cancels the edit only.
        captureEscape = true,
        escapePriority = EscapePriority.DMHUB_DROPDOWN,
        escape = function()
            if not done then
                Restore()
            end
        end,
    }
    --one box at a time: opening another ends this one as clicking away would.
    if g_activeEdit ~= nil and g_activeEdit.finish ~= nil and g_activeEdit.input.valid then
        g_activeEdit.finish()
    end
    g_activeEdit = { input = input, finish = Finish, cancel = function()
        if not done then
            Restore()
        end
    end }
    local children = {}
    for index, child in ipairs(row.children) do
        if index == first then
            children[#children + 1] = input
        end
        children[#children + 1] = child
    end
    row.children = children
    --hidden after the box is in place: the engine will not reorder a row while it shows or hides one of its words.
    for _, child in ipairs(hidden) do
        child:SetClass("collapsed", true)
    end
end

--- Opens a slot's picker at the pointer.
--- @param word Panel the clicked word
--- @param slot BlockSlot
--- @param value any the current value
--- @param commit fun(value: any)
local function _openPicker(word, slot, value, commit)
    local entries = {}
    local group = 1
    for _, choice in ipairs(_choices(slot)) do
        if choice == "-" then
            group = group + 1
        else
            entries[#entries + 1] = {
                text = choice.text,
                group = tostring(group),
                check = choice.value ~= nil and choice.value == value,
                disabled = choice.disabled,
                click = function()
                    word.popup = nil
                    if choice.action == "type" then
                        _editInPlace(word, value, commit)
                    elseif choice.value ~= value then
                        commit(choice.value)
                    end
                end,
            }
        end
    end
    word.popupsInheritStyles = true
    word.popupPositioning = "mouse"
    word.popup = gui.ContextMenu{
        entries = entries,
        click = function()
            word.popup = nil
        end,
    }
end

----------------------------------------------------------------------------
-- The amount picker (ledger: one entry per kind, never one per value). An
-- amount slot (BlockSlot.amount) lists the kinds of amount, each with a real
-- example; searching a stat ("agility") makes the examples use it. What the
-- example shows (the stat, the sign, the numbers) is then changed on the
-- block: each is its own word (_formulaWords below).
----------------------------------------------------------------------------

--- The names an amount can be based on, for the stat menu and the search:
--- the registered stats, Level, and the slot's own extra names.
--- @param slot BlockSlot
--- @return string[]
local function _amountNames(slot)
    local result = {}
    for _, stat in ipairs(Block.All("stat")) do
        --- @cast stat BlockStat
        result[#result + 1] = stat.words
    end
    result[#result + 1] = "Level"
    for _, name in ipairs(slot.names or {}) do
        result[#result + 1] = name
    end
    return result
end

--- The name a search is for ("agi" -> "Agility"), or nil.
--- @param slot BlockSlot
--- @param query string lower case
--- @return string|nil
local function _searchedName(slot, query)
    if query == "" then
        return nil
    end
    for _, name in ipairs(_amountNames(slot)) do
        if string.sub(string.lower(name), 1, #query) == query then
            return name
        end
    end
    return nil
end

--- The kinds an amount picker lists, for a search.
--- @param slot BlockSlot
--- @param query string lower case
--- @return {name: string, example: string, value?: string, action?: string, words: string}[]
local function _amountKinds(slot, query)
    if slot.kinds ~= nil then
        local result = {}
        for _, kind in ipairs(slot.kinds) do
            result[#result + 1] = { name = kind.name, example = kind.example, value = kind.value, words = string.lower(kind.name .. " " .. kind.example) }
        end
        return result
    end
    local named = _searchedName(slot, query)
    local stat = named or "Might"
    local result = {
        { name = T("blockeditor.amount.number"), example = T("blockeditor.amount.number_example"), action = "number", words = "number amount flat fixed" },
        {
            name = T("blockeditor.amount.stat"),
            example = named ~= nil and T("blockeditor.amount.stat_found", { stat = named }) or T("blockeditor.amount.stat_example"),
            value = stat,
            words = "stat characteristic attribute",
        },
        {
            name = T("blockeditor.amount.math"),
            example = named ~= nil and T("blockeditor.amount.math_found", { stat = named }) or T("blockeditor.amount.math_example"),
            value = (named or "Level") .. " + 1",
            words = "math plus minus times multiply add subtract divide half double",
        },
        { name = T("blockeditor.amount.level"), example = T("blockeditor.amount.level_example"), value = "1 + (1 when Level >= 5 else 0)", words = "level echelon scale grows bonus" },
        { name = T("blockeditor.amount.test"), example = T("blockeditor.amount.test_example"), value = "2 when Target.Winded else 1", words = "if when else choose test depends" },
    }
    if slot.dice then
        result[#result + 1] = { name = T("blockeditor.amount.dice"), example = T("blockeditor.amount.dice_example"), value = "1d6", words = "random dice roll d6 d10" }
    end
    return result
end

--- Opens the amount picker at the pointer.
--- @param word Panel the clicked word
--- @param slot BlockSlot
--- @param value any the current value
--- @param commit fun(value: any)
local function _openAmountPicker(word, slot, value, commit)
    local current = value ~= nil and tostring(value) or ""

    --- @type Panel
    local list
    --- @param query string
    local function Fill(query)
        local rows = {}
        local named = slot.kinds == nil and _searchedName(slot, query) ~= nil
        for _, kind in ipairs(_amountKinds(slot, query)) do
            --a search for a stat keeps the kinds that use one; any other search filters by words.
            local shown
            if query == "" then
                shown = true
            elseif named then
                shown = string.find(kind.words, "stat", 1, true) ~= nil or string.find(kind.words, "math", 1, true) ~= nil
            else
                shown = string.find(string.lower(kind.name) .. " " .. kind.words, query, 1, true) ~= nil
            end
            if shown then
                rows[#rows + 1] = gui.Panel{
                    classes = {"beAmountRow"},
                    press = function(element)
                        word.popup = nil
                        if kind.action == "number" then
                            --the box starts at 1 for an amount that is not a number yet.
                            local number = tonumber(current) ~= nil and current or "1"
                            _editInPlace(word, current, commit, number)
                        elseif kind.value ~= current then
                            commit(kind.value)
                        end
                    end,
                    gui.Label{ classes = {"beAmountName"}, text = kind.name, interactable = false },
                    gui.Label{ classes = {"beAmountExample"}, text = _escape(kind.example), interactable = false },
                }
            end
        end
        rows[#rows + 1] = gui.Panel{
            classes = {"beAmountRow"},
            press = function(element)
                word.popup = nil
                _editInPlace(word, value, commit)
            end,
            gui.Label{ classes = {"beAmountName"}, text = T("blockeditor.menu.formula"), interactable = false },
        }
        list.children = rows
    end

    list = gui.Panel{
        classes = {"beAmountList"},
    }
    local children = {
        gui.Label{ classes = {"beAmountTitle"}, text = T("blockeditor.amount.title"), interactable = false },
    }
    if current ~= "" then
        children[#children + 1] = gui.Label{
            classes = {"beAmountNow"},
            text = T("blockeditor.amount.now", { value = _escape(current) }),
            interactable = false,
        }
    end
    if slot.kinds == nil then
        children[#children + 1] = gui.SearchInput{
            classes = {"searchInput", "beAmountSearch"},
            placeholderText = T("blockeditor.amount.search"),
            search = function(element, text)
                Fill(string.lower(trim(text or "")))
            end,
        }
    end
    children[#children + 1] = list
    Fill("")

    word.popupsInheritStyles = true
    word.popupPositioning = "mouse"
    word.popup = gui.Panel{
        classes = {"framedPanel", "beAmountPicker"},
        interactable = true,
        swallowPress = true,
        children = children,
    }
end

--- A path into a formula tree: the keys from the root to a node.
--- @param ast BlockFormulaNode
--- @param path string[]
--- @return BlockFormulaNode|nil
local function _nodeAt(ast, path)
    --- @type BlockFormulaNode|nil
    local node = ast
    for _, key in ipairs(path) do
        node = node ~= nil and node[key] or nil
    end
    return node
end

--- A copy of a formula tree with the node at path replaced.
--- @param ast BlockFormulaNode
--- @param path string[]
--- @param replacement BlockFormulaNode
--- @return BlockFormulaNode
local function _replaced(ast, path, replacement)
    if #path == 0 then
        replacement.comments = ast.comments
        return replacement
    end
    local copy = DeepCopy(ast)
    local parent = copy
    for i = 1, #path - 1 do
        parent = parent[path[i]]
    end
    local old = parent[path[#path]]
    replacement.parens = replacement.parens or (old ~= nil and old.parens or nil)
    parent[path[#path]] = replacement
    return copy
end

--- The pieces an amount formula shows as on the block: each number, stat and
--- sign is its own piece with its own picker. Nil when the text is not a
--- formula; anything else shows as one piece typed as a formula.
--- @param text string
--- @return BlockFormulaNode|nil ast, {text: string, edit?: string, path?: string[]}[]|nil pieces
local function _formulaPieces(text)
    local ast = Block.ParseFormula(text)
    if ast == nil then
        return nil, nil
    end
    local pieces = {}
    local function Walk(node, path)
        for _ = 1, node.parens or 0 do
            pieces[#pieces + 1] = { text = "(" }
        end
        if node.k == "num" then
            pieces[#pieces + 1] = { text = tostring(node.v), edit = "number", path = path }
        elseif node.k == "id" and node.path ~= nil and #node.path == 1 then
            pieces[#pieces + 1] = { text = node.path[1], edit = "stat", path = path }
        elseif node.k == "bin" and not node.unary and node.l ~= nil and node.r ~= nil then
            local left, right = { table.unpack(path) }, { table.unpack(path) }
            left[#left + 1] = "l"
            right[#right + 1] = "r"
            Walk(node.l, left)
            pieces[#pieces + 1] = { text = node.opText or node.op, edit = "sign", path = path }
            Walk(node.r, right)
        elseif node.k == "when" and node.v ~= nil and node.c ~= nil then
            local value, test, otherwise = { table.unpack(path) }, { table.unpack(path) }, { table.unpack(path) }
            value[#value + 1] = "v"
            test[#test + 1] = "c"
            otherwise[#otherwise + 1] = "e"
            Walk(node.v --[[@as BlockFormulaNode]], value)
            pieces[#pieces + 1] = { text = T("blockeditor.amount.if") }
            pieces[#pieces + 1] = { text = Block.PrintFormula(node.c), edit = "formula", path = test }
            if node.e ~= nil then
                pieces[#pieces + 1] = { text = T("blockeditor.amount.otherwise") }
                Walk(node.e, otherwise)
            end
        else
            local copy = DeepCopy(node)
            copy.parens = nil
            pieces[#pieces + 1] = { text = Block.PrintFormula(copy), edit = "formula", path = path }
        end
        for _ = 1, node.parens or 0 do
            pieces[#pieces + 1] = { text = ")" }
        end
    end
    Walk(ast, {})
    return ast, pieces
end

--- The picker for one piece of an amount on the block.
--- @param word Panel the clicked word
--- @param slot BlockSlot
--- @param value any the slot's value
--- @param ast BlockFormulaNode the parsed value
--- @param piece {text: string, edit?: string, path?: string[]}
--- @param commit fun(value: any)
local function _openPiecePicker(word, slot, value, ast, piece, commit)
    local path = piece.path or {}
    --- @param replacement BlockFormulaNode
    local function Put(replacement)
        commit(Block.PrintFormula(_replaced(ast, path, replacement)))
    end
    --- @param text string typed text for the piece
    local function PutText(text)
        local parsed = Block.ParseFormula(text)
        if parsed ~= nil then
            Put(parsed)
        end
    end
    if piece.edit == "number" or piece.edit == "formula" then
        _editInPlace(word, piece.text, PutText)
        return
    end
    local entries = {}
    if piece.edit == "stat" then
        for _, name in ipairs(_amountNames(slot)) do
            entries[#entries + 1] = { text = name, group = "1", check = name == piece.text, click = function()
                word.popup = nil
                if name ~= piece.text then
                    Put({ k = "id", path = { name } })
                end
            end }
        end
    elseif piece.edit == "sign" then
        local node = _nodeAt(ast, path)
        local signs = {
            { op = "+", text = T("blockeditor.amount.sign_plus") },
            { op = "-", text = T("blockeditor.amount.sign_minus") },
            { op = "*", text = T("blockeditor.amount.sign_times") },
            { op = "/", text = T("blockeditor.amount.sign_divide") },
        }
        for _, sign in ipairs(signs) do
            local op = sign.op
            entries[#entries + 1] = { text = sign.text, group = "1", check = node ~= nil and node.op == op, click = function()
                word.popup = nil
                if node ~= nil and node.op ~= op then
                    local copy = DeepCopy(node)
                    copy.op = op
                    copy.opText = nil
                    Put(copy)
                end
            end }
        end
    end
    entries[#entries + 1] = { text = T("blockeditor.amount.change"), group = "2", click = function()
        word.popup = nil
        _openAmountPicker(word, slot, value, commit)
    end }
    word.popupsInheritStyles = true
    word.popupPositioning = "mouse"
    word.popup = gui.ContextMenu{
        entries = entries,
        click = function()
            word.popup = nil
        end,
    }
end

--For tests/block_amount_test.lua: the picker's logic without drawing it.
BESlots._amountKinds = _amountKinds
BESlots._formulaPieces = _formulaPieces
BESlots._replaced = _replaced

--- Lights every word of one slot together, so a slot that wraps across lines
--- reads as one thing under the pointer.
--- @param row Panel the sentence row
--- @param slotId string|nil nil clears
local function _lightSlot(row, slotId)
    for _, child in ipairs(row.children) do
        local data = child.data
        if data ~= nil and data.slot ~= nil then
            child:SetClass("beWordHot", slotId ~= nil and data.slot == slotId)
        end
    end
end

--- One plain word.
--- @param text string
--- @param args {gap: boolean, bold?: boolean, aside?: boolean, italic?: boolean}
--- @return Panel
local function _plainWord(text, args)
    local shown = _escape(text)
    if args.italic or args.aside then
        shown = "<i>" .. shown .. "</i>"
    end
    return gui.Label{
        classes = {"beWordText", args.aside and "beWordAside" or nil},
        text = shown,
        bold = args.bold or nil,
        lmargin = args.gap and BEStyles.SIZES.WORD_GAP or 0,
        interactable = false,
    }
end

--- The keyword chips of a "many" slot, then a word that adds one.
--- @param row table the children being built
--- @param decl BlockDecl|BlockHeaderRow
--- @param slotId string
--- @param slot BlockSlot
--- @param value any
--- @param onChange fun(slotId: string, value: any, description: string, source: Panel)
--- @param gap boolean
local function _chips(row, decl, slotId, slot, value, onChange, gap)
    local chosen = type(value) == "table" and value or {}
    for i, item in ipairs(chosen) do
        local text = Block.SlotText(decl --[[@as BlockDecl]], slotId, item)
        row[#row + 1] = gui.Panel{
            classes = {"beChip"},
            lmargin = (i == 1 and gap) and BEStyles.SIZES.WORD_GAP or 0,
            gui.Label{
                classes = {"beChipText"},
                text = _escape(text),
                interactable = false,
            },
            gui.Panel{
                classes = {"beChipX"},
                press = function(element)
                    local remaining = {}
                    for _, other in ipairs(chosen) do
                        if other ~= item then
                            remaining[#remaining + 1] = other
                        end
                    end
                    onChange(slotId, remaining, T("blockeditor.change.remove_chip", { what = text }), element)
                end,
            },
        }
    end

    --- @type Label
    local add
    add = gui.Label{
        classes = {"beWord"},
        text = "<u>" .. T("blockeditor.add_keyword") .. "</u>",
        lmargin = (#chosen > 0 or gap) and BEStyles.SIZES.WORD_GAP or 0,
        hpad = 4,
        data = { slot = slotId },
        hover = function(element)
            element:SetClass("beWordHot", true)
        end,
        dehover = function(element)
            element:SetClass("beWordHot", false)
        end,
        press = function(element)
            local entries = {}
            for _, option in ipairs(Block.SlotOptions(slot)) do
                local taken = false
                for _, item in ipairs(chosen) do
                    if item == option.id then
                        taken = true
                    end
                end
                if not taken then
                    entries[#entries + 1] = {
                        text = option.text,
                        click = function()
                            element.popup = nil
                            local list = {}
                            for i, item in ipairs(chosen) do
                                list[i] = item
                            end
                            list[#list + 1] = option.id
                            onChange(slotId, list, T("blockeditor.change.set", { what = option.text }), element)
                        end,
                    }
                end
            end
            element.popupsInheritStyles = true
            element.popupPositioning = "mouse"
            element.popup = gui.ContextMenu{
                entries = entries,
                click = function()
                    element.popup = nil
                end,
            }
        end,
    }
    row[#row + 1] = add
end

--- A sentence as a wrapping row of words.
---
--- Plain words are labels; each slot's words are clickable panels that open
--- the slot's picker. Changes go to onChange as (slotId, newValue,
--- description, source); the caller turns that into one undo step, firing it
--- from source (the clicked word, still inside the editor).
--- @param args {decl: BlockDecl|BlockHeaderRow, values: table, onChange: fun(slotId: string, value: any, description: string, source: Panel), width?: string|number, italic?: boolean}
--- @return Panel
function BESlots.SentenceRow(args)
    local decl = args.decl
    local values = args.values or {}
    local onChange = args.onChange
    local children = {}
    --whether the next word follows a space: the first word never has a gap.
    local pendingSpace = false

    for _, run in ipairs(Block.Sentence(decl --[[@as BlockDecl]], values)) do
        if run.slot == nil then
            local words, trailing = _splitWords(run.text)
            for i, entry in ipairs(words) do
                local gap = #children > 0 and (entry.spaced or (i == 1 and pendingSpace))
                children[#children + 1] = _plainWord(entry.word, {
                    gap = gap,
                    bold = run.bold,
                    aside = run.style == "aside",
                    italic = args.italic,
                })
            end
            if #words > 0 then
                pendingSpace = trailing
            elseif string.match(run.text, "%s") then
                pendingSpace = true
            end
        else
            local slotId = run.slot --[[@as string]]
            local slot = decl.slots ~= nil and decl.slots[slotId] or { kind = "text" }
            local value = values[slotId]
            if value == nil then
                value = slot.default
            end
            local gap = #children > 0 and pendingSpace
            if slot.kind == "fixed" then
                --a value shown but not edited here (an Advanced block's summary).
                for i, entry in ipairs(_splitWords(run.text)) do
                    children[#children + 1] = _plainWord(entry.word, {
                        gap = #children > 0 and (i > 1 or gap),
                        italic = args.italic,
                    })
                end
            elseif slot.kind == "many" then
                _chips(children, decl, slotId, slot, value, onChange, gap)
            else
                local words = _splitWords(run.text)
                --an optional slot that reads as nothing shows its placeholder, faint.
                local empty = #words == 0
                if empty then
                    words = { { word = slot.empty or "...", spaced = false } }
                end
                --- @param newValue any
                --- @param source Panel the clicked word, which finds the editor
                local function Commit(newValue, source)
                    --a field saved as a number stays a number when the new value is one.
                    if type(value) == "number" and tonumber(newValue) ~= nil then
                        newValue = tonumber(newValue)
                    end
                    local shown = Block.SlotText(decl --[[@as BlockDecl]], slotId, newValue)
                    onChange(slotId, newValue, T("blockeditor.change.set", { what = shown }), source)
                end
                local wordClasses = {"beWord"}
                if slot.style == "formula" then
                    wordClasses[#wordClasses + 1] = "beWordFormula"
                end
                if empty then
                    wordClasses[#wordClasses + 1] = "beWordEmpty"
                end
                --an amount shows each number, stat and sign as its own word (a lone
                --number opens the kinds of amount instead).
                local ast, pieces = nil, nil
                if slot.amount and not empty and value ~= nil then
                    ast, pieces = _formulaPieces(tostring(value))
                end
                if ast ~= nil and pieces ~= nil and not (#pieces == 1 and pieces[1].edit == "number") then
                    for i, piece in ipairs(pieces) do
                        local pieceGap = #children > 0 and (i > 1 or gap)
                        if piece.edit == nil then
                            children[#children + 1] = _plainWord(piece.text, { gap = pieceGap, italic = args.italic })
                        else
                            local pieceId = slotId .. "#" .. i
                            children[#children + 1] = gui.Label{
                                classes = wordClasses,
                                text = "<u>" .. _escape(piece.text) .. "</u>",
                                lmargin = pieceGap and BEStyles.SIZES.WORD_GAP or 0,
                                lpad = 4,
                                rpad = 4,
                                data = { slot = pieceId },
                                hover = function(element)
                                    _lightSlot(element.parent, pieceId)
                                end,
                                dehover = function(element)
                                    _lightSlot(element.parent, nil)
                                end,
                                press = function(element)
                                    _openPiecePicker(element, slot, value, ast, piece, function(newValue) Commit(newValue, element) end)
                                end,
                            }
                        end
                    end
                    words = {}
                end
                for i, entry in ipairs(words) do
                    local shown = "<u>" .. _escape(entry.word) .. "</u>"
                    if args.italic then
                        shown = "<i>" .. shown .. "</i>"
                    end
                    children[#children + 1] = gui.Label{
                        classes = wordClasses,
                        text = shown,
                        lmargin = (i == 1 and gap) and BEStyles.SIZES.WORD_GAP or 0,
                        --the space between two words of one slot is padding inside
                        --the fill (a label trims a trailing space), so the slot reads as one piece.
                        lpad = i == 1 and 4 or 0,
                        rpad = i == #words and 4 or BEStyles.SIZES.WORD_GAP,
                        data = { slot = slotId },
                        hover = function(element)
                            _lightSlot(element.parent, slotId)
                        end,
                        dehover = function(element)
                            _lightSlot(element.parent, nil)
                        end,
                        press = function(element)
                            local function Done(newValue, source) Commit(newValue, source or element) end
                            --text, numbers and formulas with no suggestions are typed over in place.
                            --an amount that is just a number is typed over too (any formula can be typed there).
                            local loneNumber = (slot.amount or slot.kinds ~= nil) and not empty and tonumber(tostring(value)) ~= nil
                            --a tier's amount (its own kinds, no pieces) is typed over whole once it has one.
                            local filledKinds = slot.kinds ~= nil and not empty
                            local typed = slot.kind == "text" or slot.kind == "number" or loneNumber or filledKinds
                                or (slot.kind == "formula" and not slot.amount and slot.kinds == nil and #Block.SlotOptions(slot) == 0)
                            if typed then
                                _editInPlace(element, empty and "" or value, Done)
                            elseif slot.amount or slot.kinds ~= nil then
                                _openAmountPicker(element, slot, value, Done)
                            else
                                _openPicker(element, slot, value, Done)
                            end
                        end,
                    }
                end
            end
            pendingSpace = false
        end
    end

    return gui.Panel{
        classes = {"beSentence"},
        width = args.width or "100%",
        children = children,
    }
end

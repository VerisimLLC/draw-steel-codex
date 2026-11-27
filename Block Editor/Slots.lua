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
    declares slots, and BESlots draws them (plan section 2).
]]

local T = UIText.T

--- @class BESlots
BESlots = {}

local NUMBER_CHOICES = { 1, 2, 3, 4, 5 }

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
    elseif slot.kind == "number" then
        for _, number in ipairs(NUMBER_CHOICES) do
            result[#result + 1] = { text = tostring(number), value = number }
        end
        result[#result + 1] = "-"
        result[#result + 1] = { text = T("blockeditor.menu.formula"), action = "type" }
    else
        result[#result + 1] = { text = T("blockeditor.menu.edit_text"), action = "type" }
    end
    return result
end

--- Opens a small box at the pointer to type a slot's value in.
--- @param word Panel the clicked word
--- @param value any the current value
--- @param commit fun(value: any)
local function _openTextBox(word, value, commit)
    local done = false
    local function Commit(input)
        if done then
            return
        end
        done = true
        local text = input.text
        word.popup = nil
        if text ~= tostring(value or "") then
            commit(tonumber(text) ~= nil and type(value) == "number" and tonumber(text) or text)
        end
    end
    word.popupPositioning = "mouse"
    word.popup = gui.Panel{
        classes = {"framedPanel"},
        styles = ThemeEngine.GetStyles(),
        interactable = true,
        swallowPress = true,
        width = 360,
        height = "auto",
        pad = 8,
        borderBox = true,
        gui.Input{
            width = "100%",
            height = "auto",
            fontSize = 14,
            text = tostring(value or ""),
            selectAllOnFocus = true,
            lineType = "MultiLineSubmit",
            create = function(element)
                element.hasInputFocus = true
            end,
            submit = function(element)
                Commit(element)
            end,
            change = function(element)
                Commit(element)
            end,
        },
    }
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
                        _openTextBox(word, value, commit)
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
            local slotId = run.slot
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
                if #words == 0 then
                    words = { { word = "...", spaced = false } }
                end
                --- @param newValue any
                --- @param source Panel the clicked word, which finds the editor
                local function Commit(newValue, source)
                    local shown = Block.SlotText(decl --[[@as BlockDecl]], slotId, newValue)
                    onChange(slotId, newValue, T("blockeditor.change.set", { what = shown }), source)
                end
                for i, entry in ipairs(words) do
                    local shown = "<u>" .. _escape(entry.word) .. "</u>"
                    if args.italic then
                        shown = "<i>" .. shown .. "</i>"
                    end
                    children[#children + 1] = gui.Label{
                        classes = {"beWord", slot.style == "formula" and "beWordFormula" or nil},
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
                            _openPicker(element, slot, value, function(newValue) Commit(newValue, element) end)
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

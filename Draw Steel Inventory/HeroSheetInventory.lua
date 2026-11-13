local mod = dmhub.GetModLoading()

--The Hero sheet's Inventory tab: the Hero's items as a list grouped by
--kind, with the picked item's pane beside it. The item menu, Give, dragging
--and the party stash are in HeroSheetInventoryActions.lua, the add pane in
--HeroSheetInventoryAdd.lua. The old inventory grid (DrawSteelInventory.lua)
--stays for other creatures, loot and shops.
--This mod loads before Draw Steel V: the sheet's globals (HeroSheet,
--HeroSheetTheme, HeroSheetCard...) are only read inside functions.

HeroSheetInventory = rawget(_G, "HeroSheetInventory") or {}

--The token radial's Inventory button opens this tab for a Hero, as the
--inventory keybind does; other tokens keep the old grid. If ShowInventory is
--still this wrapper (only this file was reloaded), wrap the stored original;
--otherwise GameHud.lua reloaded, so wrap its new function.
local g_baseShowInventory = GameHud.ShowInventory
if g_baseShowInventory == rawget(_G, "g_heroInventoryShowWrapper") then
    g_baseShowInventory = rawget(_G, "g_heroInventoryBaseShowInventory")
end
rawset(_G, "g_heroInventoryBaseShowInventory", g_baseShowInventory)
function GameHud.ShowInventory(self, token, options)
    local hero = false
    pcall(function() hero = token ~= nil and token.properties ~= nil and token.properties:IsHero() and rawget(_G, "HeroSheet") ~= nil end)
    if hero then
        token:ShowSheet("Inventory")
        return
    end
    g_baseShowInventory(self, token, options)
end
rawset(_G, "g_heroInventoryShowWrapper", GameHud.ShowInventory)

----------------------------------------------------------------------
--Using a consumable: its ability goes through the cast, so costs, the
--action economy and the turn apply as on the action bar. The sheet
--minimizes while the cast targets and comes back when it ends.

--- Use one of a consumable the open Hero carries. The Inventory tab's Use
--- and the Character tab's consumable rows both come here.
--- @param itemid string
--- @return boolean started
function HeroSheetInventory.Use(itemid)
    local token = HeroSheet.Token()
    local item = (dmhub.GetTable("tbl_Gear") or {})[itemid]
    if token == nil or item == nil or not HeroSheetWrite.CanWrite() or gamehud == nil or gamehud.actionBarPanel == nil then
        return false
    end
    if (token.properties:GetItemQuantity(itemid) or 0) < 1 then
        return false
    end
    local ability = item:try_get("consumable")
    if type(ability) ~= "table" then
        return false
    end
    local clone = ability:MakeTemporaryClone()
    clone._tmp_boundCaster = token.properties
    --- @type nil|Panel
    local window = nil
    local live = rawget(_G, "g_heroSheetLive")
    if live ~= nil and live.window ~= nil and live.window.valid then
        window = live.window
    end
    local minimized = false
    if window ~= nil and not window.data.minimized and not window.data.poppedOut then
        window.data.minimize()
        minimized = true
    end
    local function Back()
        if minimized and window ~= nil and window.valid and window.data.minimized then
            window.data.restore()
        end
        minimized = false
    end
    --The action bar calls oncancel whenever the cast ends, used or abandoned,
    --so the sheet always comes back (oncast is only its start).
    gamehud.actionBarPanel:FireEventTree("invokeAbility", token, clone, {}, {oncancel = Back})
    return true
end

----------------------------------------------------------------------
--The list and the pane.

--The kinds, in the list's order, with their chips and headings: the
--Character tab names the same groups. The add pane uses them too.
local KINDS = {
    {id = "leveled", chip = "Leveled", heading = "Leveled treasures"},
    {id = "trinket", chip = "Trinkets", heading = "Trinkets"},
    {id = "consumable", chip = "Consumables", heading = "Consumables"},
    {id = "other", chip = "Other", heading = "Other"},
}
HeroSheetInventory.KINDS = KINDS

--Each kind's name in a kind line: "Leveled treasure . Neck, Magic". The
--stash rows and the add pane read it too.
local KIND_NAMES = {leveled = "Leveled treasure", trinket = "Trinket", consumable = "Consumable", other = "Item"}
HeroSheetInventory.KIND_NAMES = KIND_NAMES

--- An item's kind line: "Leveled treasure . Neck, Magic".
--- @param item table a tbl_Gear row
--- @param kind nil|string the kind when the caller has it, else read from the item
--- @return string
function HeroSheetInventory.KindLine(item, kind)
    local keywords = {}
    pcall(function()
        keywords = table.mapped_keys(item:try_get("keywords", {}), ActivatedAbility.CanonicalKeyword)
        table.sort(keywords)
    end)
    local line = KIND_NAMES[kind or HeroSheetInventoryActions.KindOf(item)] or "Item"
    if #keywords > 0 then
        line = line .. " \u{00B7} " .. table.concat(keywords, ", ")
    end
    return line
end

--- A glow over a new row that fades in about a second and a half (the
--- Downtime tab's new project uses it too). Over the row, so it keeps its own plate.
--- @param panel Panel
function HeroSheetInventory.Glow(panel)
    local color = HeroSheetTheme.WithAlpha(HeroSheetTheme.Palette().rawInfo, 1)
    local glow = gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = HeroSheetTheme.ToHex(color, 0.3),
        cornerRadius = 8,
        floating = true,
        width = "100%",
        height = "100%",
        interactable = false,
    }
    panel:AddChild(glow)
    local steps = 14
    for i = 1, steps do
        dmhub.Schedule(i * 0.1, function()
            if mod.unloaded or not glow.valid then
                return
            end
            if i == steps then
                glow:DestroySelf()
            else
                glow.selfStyle.bgcolor = HeroSheetTheme.ToHex(color, 0.3 * (1 - i / steps))
            end
        end)
    end
end

--The kind glyph an item without an icon of its own shows.
local KIND_ICONS = {
    leveled = "phosphor/crown-simple.png",
    trinket = "phosphor/diamond.png",
    consumable = "phosphor/flask.png",
    other = "phosphor/backpack.png",
}

--A leveled treasure's Level texts, in the book's order (Equipment.lua's
--fields). The add pane's expanded rows use them too.
local TIERS = {
    {level = 1, name = "1st Level", field = "description"},
    {level = 5, name = "5th Level", field = "level5"},
    {level = 9, name = "9th Level", field = "level9"},
}
HeroSheetInventory.TIERS = TIERS

--Sizes in sheet units: the pane's widest and narrowest, rows, the gap
--between the columns, the list's header (two lines on a narrow list).
local PANE_WIDTH = 430
local PANE_MIN_WIDTH = 300
local COLUMN_GAP = 12
local ROW_HEIGHT = 44
local HEADER_HEIGHT = 40
local HEADER_TWO_LINES = 78
--a list narrower than this puts its chips and search on a second line.
local HEADER_WRAP_WIDTH = 900
--a list narrower than this wraps its chip row too: chips, then search and
--Add items under them (Narrow).
local CHIP_ROW_WIDTH = 700
local HEADER_THREE_LINES = 116
--the window's card column at each tier and the sheet's padding (HeroSheet.lua).
local CARD_COLUMN = {wide = 384, medium = 320}
local CONTENT_PAD = 12
--Narrow's tab row over the list, and the gap under it.
local TAB_ROW = 40
local TAB_ROW_GAP = 8

--- @class HeroInventoryEntry
--- @field key string one row: the item, and its slot when equipped
--- @field itemid string
--- @field name string
--- @field kind string "leveled", "trinket", "consumable" or "other"
--- @field item table the tbl_Gear row
--- @field quantity integer
--- @field equipped boolean
--- @field equippable boolean
--- @field slot nil|string
--- @field remembered nil|boolean a used-up item its slot remembers
--- @field noBenefit nil|string
--- @field source table the item as HeroSheetRefresh.Read gives it in its treasures (the hover card reads it)
--- @field stash nil|boolean a party stash item shown with the same menu and pane

--- A consumable's charges, "2/3 charges", or nil when it has none.
--- @param item table
--- @return nil|string
local function ChargesText(item)
    local total = tonumber(item:try_get("consumableCharges", 1)) or 1
    if item:try_get("consumable") == nil or total <= 1 then
        return nil
    end
    local left = math.max(0, total - (tonumber(item:try_get("consumableChargesConsumed", 0)) or 0))
    return string.format("%d/%d charges", left, total)
end

--- The crafting lines, as markdown: one bold label per line in the book's
--- words and order, a line left out when its field is empty. nil for an item
--- no project makes (the New project window's rule, DTBusinessRules.IsCraftable).
--- @param item table
--- @return nil|string
local function CraftText(item)
    if not DTBusinessRules.IsCraftable(item) then
        return nil
    end
    local goal = trim(tostring(item:try_get("projectGoal") or ""))
    --- @param label string
    --- @param value any
    --- @return nil|string
    local function Line(label, value)
        value = trim(tostring(value or ""))
        if value == "" then
            return nil
        end
        return string.format("**%s:** %s", label, value)
    end
    --the characteristics a project roll may use, in the sheet's order.
    local characteristics = {}
    local keys = table.keys(item:try_get("projectRollCharacteristic", {}))
    table.sort(keys, function(left, right)
        return (creature.attributesInfo[left] or {order = 0}).order < (creature.attributesInfo[right] or {order = 0}).order
    end)
    for _, key in ipairs(keys) do
        local info = creature.attributesInfo[key]
        if info ~= nil then
            characteristics[#characteristics+1] = info.description
        end
    end
    local roll = ""
    if #characteristics <= 2 then
        roll = table.concat(characteristics, " or ")
    else
        characteristics[#characteristics] = "or " .. characteristics[#characteristics]
        roll = table.concat(characteristics, ", ")
    end
    local lines = {}
    --Line returns nil for an empty field. Assigning nil to lines[#lines+1]
    --adds nothing, so empty fields drop out.
    lines[#lines+1] = Line("Item Prerequisite", item:try_get("itemPrerequisite"))
    lines[#lines+1] = Line("Project Source", item:try_get("projectSource"))
    lines[#lines+1] = Line("Project Roll Characteristic", roll)
    lines[#lines+1] = Line("Project Goal", goal)
    return table.concat(lines, "\n")
end

--- The Hero's items as the list shows them: the treasures the sheet's read
--- of the Hero gives, by kind, then the used-up items an equipment slot
--- remembers.
--- @param token CharacterToken
--- @return HeroInventoryEntry[]
local function Entries(token)
    local read = HeroSheetRefresh.Read(token)
    local result = {}
    if read == nil or read.treasures == nil then
        return result
    end
    local treasures = read.treasures
    local seen = {}
    for _, list in ipairs({treasures.leveled, treasures.trinkets, treasures.consumables}) do
        for _, treasure in ipairs(list) do
            local key = treasure.itemid .. "|" .. tostring(treasure.slot or "carried")
            if not seen[key] then
                seen[key] = true
                result[#result+1] = {
                    key = key,
                    itemid = treasure.itemid,
                    name = treasure.name,
                    kind = treasure.kind,
                    item = treasure.item,
                    quantity = treasure.quantity or 1,
                    equipped = treasure.equipped == true,
                    equippable = treasure.equippable == true,
                    slot = treasure.slot,
                    --the read gives the reason ("weapon"); the card shows its sentence.
                    noBenefit = treasure.noBenefit ~= nil and EotwHeroSheet.NoBenefitText(treasure.noBenefit, read.kitGear) or nil,
                    source = treasure,
                }
            end
        end
    end
    --read the remembered slots without the accessor, which adds an entry. An
    --item put in the party stash is remembered too, but the stash row says
    --so, so it is not listed here as used up.
    local props = token.properties
    local gearTable = dmhub.GetTable("tbl_Gear") or {}
    local equip = props:Equipment()
    local party = HeroSheetInventoryActions.Party(token)
    for slot, meta in pairs(props:try_get("equipmentMeta", {})) do
        local info = creature.EquipmentSlots[slot]
        local shadow = type(meta) == "table" and meta.shadow or nil
        local itemid = type(shadow) == "string" and shadow or ""
        local item = gearTable[itemid]
        local stashed = party ~= nil and (party.properties:GetItemQuantity(itemid) or 0) > 0
        if info ~= nil and (info.leveled or info.trinket) and equip[slot] == nil and item ~= nil
            and (props:GetItemQuantity(itemid) or 0) < 1 and not stashed then
            local kind = cond(info.leveled, "leveled", "trinket")
            result[#result+1] = {
                key = itemid .. "|remembered|" .. slot,
                itemid = itemid,
                name = item.name,
                kind = kind,
                item = item,
                quantity = 0,
                equipped = false,
                equippable = false,
                slot = slot,
                remembered = true,
                source = {itemid = itemid, name = item.name, kind = kind, item = item, quantity = 0, equipped = false, equippable = false},
            }
        end
    end
    return result
end

--- What a change of equipment does, as the pane's chips: equipped, what the
--- item gives now ("Stamina +12", its Unequip turned round); else what
--- equipping it would change ("Speed +2"). Each change carries a + or -,
--- and a higher number is always better. The change is tried on the Hero
--- in memory and put back in the same call.
--- @param token CharacterToken
--- @param entry HeroInventoryEntry
--- @return {label: string, change: number}[]
local function PreviewChips(token, entry)
    local chips = {}
    local changes = {}
    pcall(function()
        if entry.equipped then
            changes = EotwHeroSheet.EquipPreview(token, entry.itemid, entry.slot)
        else
            local slot = HeroSheetWrite.EquipSlot(token.properties, entry.itemid)
            if slot ~= nil then
                changes = EotwHeroSheet.EquipPreview(token, entry.itemid, nil, slot)
            end
        end
    end)
    for _, change in ipairs(changes or {}) do
        local from, to = tonumber(change.from), tonumber(change.to)
        if from ~= nil and to ~= nil and from ~= to then
            chips[#chips+1] = {label = change.label, change = cond(entry.equipped, from - to, to - from)}
        end
    end
    return chips
end

--- An item's icon panel: its own icon (with its icon effect), or the kind's
--- glyph when it has none.
--- @param size number
--- @return {panel: Panel, paint: fun(entry: HeroInventoryEntry)}
local function Icon(size)
    local effect = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "100%",
        floating = true,
        interactable = false,
    }
    local glyph = gui.Panel{
        classes = {"heroSheetMutedIcon", "collapsed"},
        bgimage = "panels/square.png",
        width = "60%",
        height = "60%",
        halign = "center",
        valign = "center",
        interactable = false,
    }
    local panel = gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = "#00000055",
        cornerRadius = 6,
        width = size,
        height = size,
        valign = "center",
        interactable = false,
        effect,
        glyph,
    }
    return {
        panel = panel,
        paint = function(entry)
            local icon = nil
            pcall(function() icon = entry.item:GetIcon() end)
            local own = type(icon) == "string" and icon ~= "" and entry.item:try_get("iconid") ~= nil
            panel.bgimage = cond(own, icon, "panels/square.png")
            panel.selfStyle.bgcolor = cond(own, "white", "#00000055")
            glyph:SetClass("collapsed", own)
            if not own then
                glyph.bgimage = KIND_ICONS[entry.kind] or KIND_ICONS.other
            end
            local fx = nil
            local fxid = entry.item:try_get("iconEffect")
            if own and fxid ~= nil and ItemEffects ~= nil then
                fx = ItemEffects[fxid]
            end
            effect:SetClass("collapsed", fx == nil)
            if fx ~= nil then
                effect.bgimage = fx.video
                effect.selfStyle.opacity = fx.opacity or 1
                effect.bgimageMask = cond(fx.mask, icon)
            end
            --a remembered, used-up item is shown dimmed.
            panel.selfStyle.opacity = cond(entry.remembered == true, 0.45, 1)
        end,
    }
end

--- The same icon on an item's hover card, the drag chip and the add pane.
--- paint takes anything with the entry's item and kind.
HeroSheetInventory.Icon = Icon

--- A small button in the sheet's style (Equip, Use).
--- @param text string
--- @param click fun()
--- @param hover nil|fun(element: Panel)
--- @param dehover nil|fun(element: Panel)
--- @return Panel
local function SmallButton(text, click, hover, dehover)
    return gui.Label{
        classes = {"heroSheetSmallButton", "hoverable", "heroSheetOn"},
        text = text,
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = "auto",
        height = 26,
        hpad = 10,
        borderBox = true,
        fontSize = 12.5,
        textWrap = false,
        valign = "center",
        textAlignment = "center",
        lmargin = 6,
        click = function(element)
            click()
        end,
        hover = hover,
        dehover = dehover,
    }
end

--- Equip or Unequip a row's item, one undo step, with the old grid's sounds.
--- @param entry HeroInventoryEntry
--- @return boolean wrote false when nothing was saved, so no repaint follows
local function ToggleEquip(entry)
    if entry.equipped and entry.slot ~= nil then
        local wrote = HeroSheetWrite.Unequip(entry.slot)
        audio.FireSoundEvent("UI.Inv_Grab")
        return wrote
    elseif HeroSheetWrite.Equip(entry.itemid) then
        audio.FireSoundEvent("UI.Inv_Place")
        return true
    end
    audio.FireSoundEvent("UI.Error_Generic")
    return false
end

--The party stash item the item pane shows, picked in the stash column; nil
--when the pane shows one of the Hero's items.
--- @type nil|string
local g_stashShown = nil
--- @type nil|fun()
local g_showStash = nil

--- The stash item the pane shows, if any.
--- @return nil|string
function HeroSheetInventory.StashShown()
    return g_stashShown
end

--- Show a party stash item in the item pane, read only, with Take.
--- @param itemid nil|string nil goes back to the Hero's items
function HeroSheetInventory.ShowStashItem(itemid)
    g_stashShown = itemid
    if g_showStash ~= nil then
        g_showStash()
    end
    local live = rawget(_G, "g_heroSheetLive")
    if live ~= nil and live.window ~= nil and live.window.valid then
        live.window:FireEventTree("heroSheetStash")
    end
end

--- The "..." button of a row or the pane. The stash rows use it too.
--- @param always boolean shown at all times, not only on hover (the pane's)
--- @param click fun(element: Panel)
--- @return Panel
local function MenuButton(always, click)
    return gui.Panel{
        classes = {"heroSheetKeb", "hoverable", cond(always, "heroSheetKebAlways", nil)},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 5,
        width = HeroSheetWindow.TargetSize(cond(always, 34, 24)),
        height = HeroSheetWindow.TargetSize(cond(always, 34, 24)),
        lmargin = 6,
        halign = cond(always, "left", "right"),
        valign = "center",
        click = function(element)
            click(element)
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
end
HeroSheetInventory.MenuButton = MenuButton

--- @class HeroCountField
--- @field panel Panel the field; add it to the row
--- @field open fun(text: string, apply: fun(count: integer)) show it holding text; apply gets the typed whole number when it saves
--- @field close fun() hide it without saving
--- @field editing fun(): boolean whether it is open

--- A count field over a row's right side, for Set quantity and Set charges
--- (on the list's rows and the stash's). Enter or a click away saves, Esc
--- cancels. It starts hidden; open shows it.
--- @return HeroCountField
function HeroSheetInventory.CountField()
    --- @type nil|fun(count: integer) what a save does; nil while the field is closed
    local apply = nil
    local field
    local function Close()
        apply = nil
        field.captureEscape = false
        field:SetClass("collapsed", true)
    end
    --- @param text string
    local function Save(text)
        local onSave = apply
        if onSave == nil then
            return
        end
        Close()
        if field.hasInputFocus or gui.GetFocus() == field then
            gui.SetFocus(nil)
        end
        local count = tonumber(text)
        if count ~= nil then
            onSave(math.floor(count))
        end
    end
    field = gui.Input{
        classes = {"heroSheetNumberInput", "collapsed"},
        floating = true,
        width = 56,
        height = 24,
        fontSize = 13,
        halign = "right",
        valign = "center",
        characterLimit = 4,
        selectAllOnFocus = true,
        placeholderText = "",
        captureEscape = false,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function(element)
            Close()
            gui.SetFocus(nil)
        end,
        submit = function(element)
            Save(element.text)
        end,
        defocus = function(element)
            Save(element.text)
        end,
    }
    return {
        panel = field,
        open = function(text, onSave)
            apply = onSave
            field.text = text
            field.captureEscape = true
            field:SetClass("collapsed", false)
            --focus a frame later: the field is still collapsed until then.
            dmhub.Schedule(0.01, function()
                if not mod.unloaded and field.valid and apply ~= nil then
                    gui.SetFocus(field)
                end
            end)
        end,
        close = Close,
        editing = function()
            return apply ~= nil
        end,
    }
end

--- Whether an item row passes a kind chip and a search. The list and the
--- add pane both filter with it, so they filter alike.
--- @param entry HeroInventoryEntry|HeroAddEntry
--- @param filter string a kind id, or "all"
--- @param query string the search in lower case, or ""
--- @return boolean
function HeroSheetInventory.Matches(entry, filter, query)
    if filter ~= "all" and entry.kind ~= filter then
        return false
    end
    if query ~= "" and string.find(string.lower(entry.name), query, 1, true) == nil then
        return false
    end
    return true
end

--- @class HeroInventoryArgs
--- @field select nil|fun(key: string) a row was clicked

--- The Inventory tab's body: the list on the left, the item pane on the
--- right. A HeroSheetRefresh block: it paints when the Hero's items change.
--- Rows are kept and painted again; the pane is built once and painted.
--- @return Panel
function HeroSheetInventory.Create()
    local state = {
        --the chip picked and the search's words.
        filter = "all",
        query = "",
        --the row picked (its entry key) and its item: equipping moves an item
        --to another row, and the pane stays on it.
        --- @type nil|string
        sel = nil,
        --- @type nil|string
        selItem = nil,
        --the row the pane shows, lit in the list.
        --- @type nil|string
        shown = nil,
        --- @type HeroInventoryEntry[]
        entries = {},
        --the items painted last time: one not there before was just added.
        --- @type nil|table<string, boolean>
        known = nil,
        --- @type nil|CharacterToken
        token = nil,
        level = 1,
        write = false,
        --the add pane shows in the item pane's place.
        adding = false,
        --at Narrow: which tab, and what shows in the list's place: "list",
        --"item" (the item pane, with All items) or "add".
        narrow = false,
        narrowTab = "items",
        narrowView = "list",
    }
    --- @type fun()
    local PaintList
    --- @type fun()
    local PaintPane
    --- @type fun()
    local Arrange
    --the tab's body: the old grid's item editor tells it when an edit closes.
    --- @type Panel
    local body
    --The pane's preview chips. While the pointer is on an Unequip button for
    --the item the pane shows (the pane's own, or its row's), they show what
    --unequipping would lose.
    --- @type {label: string, change: number}[]
    local paneChips = {}
    local paneEquipped = false
    --- @type nil|string the key of the Hero's item the pane shows
    local paneItemKey = nil
    local unequipHover = false
    --- @type fun()
    local PaintPreview

    ------------------------------------------------------------------
    --The list's header: the heading and count, the chips, the search.

    local countLabel = gui.Label{
        classes = {"heroSheetMuted"},
        text = "",
        fontSize = 14,
        width = "auto",
        height = "auto",
        lmargin = 8,
        halign = "left",
        valign = "center",
        textWrap = false,
    }
    --- @type table<string, Panel>
    local chips = {}
    --- @type Panel[]
    local headerChildren = {
        gui.Label{
            classes = {"heroSheetTitle"},
            text = "Inventory",
            fontSize = 20,
            bold = true,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            textWrap = false,
        },
        countLabel,
    }
    local chipRow = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        halign = "right",
        valign = "center",
    }
    local chipDefs = {{id = "all", chip = "All"}}
    for _, kind in ipairs(KINDS) do
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
            --packed from the left: in a full-width row, children with no
            --alignment of their own spread out across it.
            halign = "left",
            valign = "center",
            click = function(element)
                state.filter = id
                for chipId, chipPanel in pairs(chips) do
                    chipPanel:SetClassTree("heroSklPicked", chipId == id)
                end
                PaintList()
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
    chipRow:AddChild(gui.SearchInput{
        placeholderText = "Search your items",
        text = "",
        width = 150,
        height = HeroSheetWindow.TargetSize(28),
        borderBox = true,
        halign = "left",
        valign = "center",
        edit = function(element)
            state.query = string.lower(trim(element.text or ""))
            PaintList()
        end,
    })
    --Add items: the add pane takes the item pane's place.
    --- @type fun(open: boolean)
    local ShowAdd
    --builds the add pane ahead of a click on Add items.
    --- @type fun()
    local WarmAdd
    local addButton = gui.Panel{
        classes = {"heroSheetPlateButton", "hoverable"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 14,
        width = "auto",
        height = HeroSheetWindow.TargetSize(28),
        hpad = 10,
        borderBox = true,
        lmargin = 6,
        flow = "horizontal",
        --a wrapped header puts it at the start of its line.
        halign = "left",
        valign = "center",
        click = function(element)
            ShowAdd(not state.adding)
        end,
        hover = function(element)
            WarmAdd()
        end,
        --Strict Inventory switched on or off: the button follows at once.
        multimonitor = {"strict:inventory"},
        monitor = function(element)
            element:SetClass("collapsed", not HeroSheetInventoryActions.CanAdd())
            if state.adding and not HeroSheetInventoryActions.CanAdd() then
                ShowAdd(false)
            end
        end,
        gui.Panel{
            classes = {"heroSheetFg"},
            bgimage = "phosphor/plus-bold.png",
            width = 11,
            height = 11,
            valign = "center",
            rmargin = 6,
            interactable = false,
        },
        gui.Label{
            classes = {"heroSheetCardStrong"},
            text = "Add items",
            fontSize = 12.5,
            bold = true,
            width = "auto",
            height = "auto",
            valign = "center",
            textWrap = false,
            interactable = false,
        },
    }
    chipRow:AddChild(addButton)
    headerChildren[#headerChildren+1] = chipRow
    local header = gui.Panel{
        width = "100%",
        height = HEADER_HEIGHT,
        flow = "horizontal",
        wrap = true,
        children = headerChildren,
    }

    ------------------------------------------------------------------
    --The rows: kept by entry key, painted again for each change.

    --- @class HeroInventoryRow
    --- @field panel Panel
    --- @field paint fun(entry: HeroInventoryEntry)
    --- @field entry nil|HeroInventoryEntry
    --- @field editQuantity fun() the count becomes a field (the menu's Set quantity)

    --- @return HeroInventoryRow
    local function NewRow()
        --the row's handlers read the entry shown from here; panel and paint
        --are filled in below.
        local row = {entry = nil}
        --- @type fun(anchor: Panel)
        local OpenMenu
        local icon = Icon(30)
        local name = HeroSheetTheme.EllipsisLabel{
            classes = {"heroSheetCardStrong"},
            text = "",
            fontSize = 15,
            bold = true,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
        }
        local sub = HeroSheetTheme.EllipsisLabel{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 12,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            tmargin = 1,
        }
        local words = gui.Panel{
            width = "100%-200",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "center",
            lmargin = 10,
            interactable = false,
            name,
            sub,
        }
        local qty = gui.Label{
            classes = {"heroSheetCardStrong"},
            text = "",
            fontSize = 13,
            bold = true,
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 6,
            textWrap = false,
        }
        local charges = gui.Label{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 12,
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 6,
            textWrap = false,
        }
        --an equipped item says so beside its Unequip.
        local equippedLabel = gui.Label{
            classes = {"heroSheetCardSuccess", "collapsed"},
            text = "Equipped",
            fontSize = 12,
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 6,
            textWrap = false,
        }
        local busy = false
        local button = SmallButton("Equip", function()
            local entry = row.entry
            if entry == nil or busy then
                return
            end
            if entry.kind == "consumable" then
                if not HeroSheetInventory.Use(entry.itemid) then
                    audio.FireSoundEvent("UI.Error_Generic")
                end
                return
            end
            --one action per press until the Hero's change repaints the row. A
            --press that saved nothing gets no repaint, so it frees the button.
            busy = true
            if not ToggleEquip(entry) then
                busy = false
            end
        end, function(element)
            --on the button the row's item card waits (it would cover the
            --pane), and Unequip on the item the pane shows previews the loss.
            local rowPanel = row.panel
            if rowPanel ~= nil and rowPanel.valid then
                rowPanel.data.cardHover = false
                rowPanel.data.cardGen = (rowPanel.data.cardGen or 0) + 1
                rowPanel.tooltip = nil
            end
            local entry = row.entry
            if element.text == "Unequip" and entry ~= nil and entry.key == paneItemKey then
                unequipHover = true
                PaintPreview()
            end
        end, function(element)
            if unequipHover then
                unequipHover = false
                PaintPreview()
            end
            --back on the row: its card starts its wait again.
            local rowPanel = row.panel
            if rowPanel ~= nil and rowPanel.valid and rowPanel:HasClass("hover") then
                rowPanel:FireEvent("hover")
            end
        end)
        local right = gui.Panel{
            width = "auto",
            height = "100%",
            flow = "horizontal",
            halign = "right",
            valign = "center",
            interactable = false,
            charges,
            qty,
            equippedLabel,
        }
        --Set quantity / Set charges (the menu) turn the row's count into a
        --field over its right side.
        local field = HeroSheetInventory.CountField()
        --- @param what string "quantity" or "charges"
        local function EditField(what)
            local entry = row.entry
            if entry == nil then
                return
            end
            if what == "quantity" then
                field.open(tostring(entry.quantity), function(count)
                    local current = row.entry
                    if current ~= nil and count >= 1 and count ~= current.quantity then
                        HeroSheetInventoryActions.SetQuantity(current, count)
                    end
                end)
            else
                local total = tonumber(entry.item:try_get("consumableCharges", 1)) or 1
                local left = math.max(0, total - (tonumber(entry.item:try_get("consumableChargesConsumed", 0)) or 0))
                field.open(tostring(left), function(count)
                    local current = row.entry
                    if current ~= nil then
                        HeroSheetInventoryActions.SetCharges(current, count)
                    end
                end)
            end
        end
        row.editQuantity = function()
            EditField("quantity")
        end
        local keb = MenuButton(false, function(element)
            OpenMenu(element)
        end)
        --dims the row while it is dragged (opacity would not reach its words).
        local dragCover = gui.Panel{
            classes = {"heroSheetDragCover"},
            bgimage = "panels/square.png",
            cornerRadius = 8,
            floating = true,
            width = "100%+20",
            height = "100%",
            halign = "center",
            interactable = false,
        }
        local panel
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
            click = function(element)
                local entry = row.entry
                if entry ~= nil then
                    state.sel = entry.key
                    state.selItem = entry.itemid
                    state.shown = entry.key
                    if g_stashShown ~= nil then
                        HeroSheetInventory.ShowStashItem(nil)
                    end
                    PaintList()
                    PaintPane()
                    --at Narrow the item opens in place of the list.
                    if state.narrow then
                        state.narrowView = "item"
                        Arrange()
                    end
                end
            end,
            --the item menu opens on right-click too.
            rightClick = function(element)
                OpenMenu(element)
            end,
            icon.panel,
            words,
            right,
            button,
            keb,
            field.panel,
            dragCover,
        }
        --dragging one of the Hero's items: a used-up row stays put.
        for argName, value in pairs(HeroSheetInventoryActions.DragFields("inv", function()
            local entry = row.entry
            if entry == nil or entry.remembered or not state.write then
                return nil
            end
            return entry
        end)) do
            rowArgs[argName] = value
        end
        panel = gui.Panel(HeroSheetTheme.HoverCard(rowArgs, function(pinned, close)
            local entry = row.entry
            if entry == nil then
                return gui.Panel{width = 1, height = 1}
            end
            return HeroSheetTheme.CardFrame(HeroSheetCard.ItemCard(entry.source, state.level, entry.noBenefit, pinned), pinned, close)
        end, false))
        row.panel = panel
        OpenMenu = function(anchor)
            local entry = row.entry
            if entry == nil or not state.write then
                return
            end
            HeroSheetInventoryActions.ShowMenu(anchor, entry, {
                editQuantity = function()
                    EditField("quantity")
                end,
                editCharges = function()
                    EditField("charges")
                end,
                notify = body,
            })
        end
        row.paint = function(entry)
            local same = row.entry ~= nil and row.entry.key == entry.key
            row.entry = entry
            busy = false
            if field.editing() and not same then
                field.close()
            end
            keb:SetClass("heroSheetKebOff", not state.write)
            icon.paint(entry)
            name.text = entry.name
            local keywords = {}
            pcall(function()
                keywords = table.mapped_keys(entry.item:try_get("keywords", {}), ActivatedAbility.CanonicalKeyword)
                table.sort(keywords)
            end)
            local line = table.concat(keywords, ", ")
            if entry.remembered then
                line = "Used up: equips again when you have one."
            end
            sub.text = line
            sub:SetClass("collapsed", line == "")
            local chargeText = ChargesText(entry.item)
            charges.text = chargeText or ""
            charges:SetClass("collapsed", chargeText == nil)
            local many = entry.quantity > 1
            qty.text = cond(many, string.format("x%d", entry.quantity), "")
            qty:SetClass("collapsed", not many)
            equippedLabel:SetClass("collapsed", not entry.equipped)
            --Use on a consumable; Equip / Unequip on what a slot can take.
            local label = nil
            if state.write and not entry.remembered then
                if entry.kind == "consumable" then
                    if type(entry.item:try_get("consumable")) == "table" then
                        label = "Use"
                    end
                elseif entry.equipped and entry.slot ~= nil then
                    label = "Unequip"
                elseif not entry.equipped and HeroSheetWrite.EquipSlot(state.token.properties, entry.itemid) ~= nil then
                    label = "Equip"
                end
            end
            button:SetClass("collapsed", label == nil)
            button.text = label or ""
            --the words take what the right side leaves (never "100% available"):
            --the icon (30), the gap before the words (10) and the row's padding (2 x 10).
            local room = 30 + 10 + 20
            room = room + cond(chargeText ~= nil, HeroSheetTheme.TextWidth(chargeText or "", 12) + 6, 0)
            room = room + cond(many, HeroSheetTheme.TextWidth(qty.text, 13) + 6, 0)
            room = room + cond(entry.equipped, HeroSheetTheme.TextWidth("Equipped", 12) + 6, 0)
            room = room + cond(label ~= nil, HeroSheetTheme.TextWidth(label or "", 12.5) + 26, 0)
            --the "..." shows on hover: its room is kept so the words never move.
            room = room + cond(state.write, HeroSheetWindow.TargetSize(24) + 6, 0)
            words.selfStyle.width = string.format("100%%-%d", math.ceil(room))
            name.selfStyle.maxWidth = "100%"
            sub.selfStyle.maxWidth = "100%"
            panel:SetClass("heroSheetRowPinned", entry.key == state.shown)
            if not same then
                panel.tooltip = nil
            end
        end
        return row --[[@as HeroInventoryRow]]
    end

    --- @class HeroInventoryGroup
    --- @field panel Panel
    --- @field paint fun(entries: HeroInventoryEntry[], first: boolean)
    --- @field rows fun(): HeroInventoryRow[]

    --- @param kind {id: string, heading: string}
    --- @return HeroInventoryGroup
    local function NewGroup(kind)
        local title = gui.Label{
            classes = {"heroSheetCardLabel"},
            text = string.upper(kind.heading),
            fontSize = 11,
            bold = true,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            textWrap = false,
        }
        --the count, or for leveled treasures the carried count.
        local count = gui.Label{
            classes = {"heroSheetPill"},
            text = "",
            bgimage = "panels/square.png",
            bgcolor = "clear",
            border = 1,
            cornerRadius = 9,
            width = "auto",
            height = 18,
            hpad = 8,
            borderBox = true,
            fontSize = 12,
            bold = true,
            textWrap = false,
            halign = "right",
            valign = "center",
            data = {tooltip = nil},
            linger = function(element)
                if element.data.tooltip ~= nil then
                    gui.Tooltip(element.data.tooltip)(element)
                end
            end,
        }
        local holder = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
        }
        local panel = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            gui.Panel{
                width = "100%",
                height = 22,
                flow = "horizontal",
                tmargin = 14,
                title,
                count,
            },
            holder,
        }
        --- @type HeroInventoryRow[]
        local rows = {}
        return {
            panel = panel,
            paint = function(entries, first)
                panel:SetClass("collapsed", #entries == 0)
                panel.children[1].selfStyle.tmargin = cond(first, 2, 14)
                if kind.id == "leveled" then
                    --Every copy counts toward the three leveled treasures a
                    --Hero can carry: a stack of two counts as two.
                    local carried = 0
                    for _, entry in ipairs(entries) do
                        if not entry.remembered then
                            carried = carried + math.max(1, entry.quantity)
                        end
                    end
                    if carried > 3 then
                        count.text = string.format("%d carried", carried)
                        count.data.tooltip = "Carrying more than three leveled treasures means a Presence test each respite."
                    else
                        count.text = string.format("%d of 3 carried", carried)
                        count.data.tooltip = nil
                    end
                    count:SetClass("heroSheetPillWarn", carried > 3)
                else
                    count.text = tostring(#entries)
                    count.data.tooltip = nil
                end
                for i, entry in ipairs(entries) do
                    local row = rows[i]
                    if row == nil then
                        row = NewRow()
                        rows[i] = row
                        holder:AddChild(row.panel)
                    end
                    row.panel:SetClass("collapsed", false)
                    row.paint(entry)
                end
                for i = #entries + 1, #rows do
                    rows[i].panel:SetClass("collapsed", true)
                    rows[i].entry = nil
                end
            end,
            --- @return HeroInventoryRow[]
            rows = function()
                return rows
            end,
        }
    end

    --- @type table<string, HeroInventoryGroup>
    local groups = {}
    local groupPanels = {}
    for _, kind in ipairs(KINDS) do
        groups[kind.id] = NewGroup(kind)
        groupPanels[#groupPanels+1] = groups[kind.id].panel
    end
    local empty = gui.Label{
        classes = {"heroSheetMuted", "collapsed"},
        text = "Nothing carried yet.",
        fontSize = 14,
        width = "auto",
        height = "auto",
        tmargin = 18,
    }
    groupPanels[#groupPanels+1] = empty
    local listContent = gui.Panel{
        width = "100%-12",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        bpad = 12,
        borderBox = true,
        children = groupPanels,
    }
    local listScroll = gui.Panel{
        width = "100%",
        height = string.format("100%%-%d", HEADER_HEIGHT),
        flow = "vertical",
        vscroll = true,
        listContent,
    }
    --The Drop on the map and Destroy zones: at the foot of the list, over it,
    --while one of the Hero's items is dragged. Off the showing map the Drop
    --zone is dimmed and says why.
    --- @param text string
    --- @param danger boolean
    --- @return Panel zone
    --- @return Panel reason the second line (Drop only)
    local function Zone(text, danger)
        local reason = gui.Label{
            classes = {"heroSheetCardSub", "collapsed"},
            text = "",
            fontSize = 11.5,
            width = "auto",
            height = "auto",
            halign = "center",
            textWrap = false,
            interactable = false,
        }
        local zone = gui.Panel{
            classes = {"heroSheetDropZone", cond(danger, "heroSheetDropZoneDanger", nil)},
            bgimage = "panels/square.png",
            border = 2,
            borderStyle = "dashed",
            borderDash = 6,
            borderGap = 4,
            cornerRadius = 8,
            width = "50%-5",
            height = 54,
            flow = "vertical",
            halign = cond(danger, "right", "left"),
            valign = "center",
            gui.Label{
                classes = {cond(danger, "heroSheetCardDanger", "heroSheetCardStrong")},
                text = text,
                fontSize = 14,
                bold = true,
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
                textWrap = false,
                interactable = false,
            },
            reason,
        }
        return zone, reason
    end
    local dropZone, dropReason = Zone("Drop on the map", false)
    local destroyZone = Zone("Destroy", true)
    local zones = gui.Panel{
        classes = {"collapsed"},
        floating = true,
        width = "100%",
        height = 54,
        valign = "bottom",
        bmargin = 12,
        flow = "horizontal",
        dropZone,
        destroyZone,
    }
    local listPanel = gui.Panel{
        classes = {"heroSheetPlate", "heroSheetBlock", "heroSheetDropTarget"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = string.format("100%%-%d", PANE_WIDTH + COLUMN_GAP),
        height = "100%",
        flow = "vertical",
        tpad = 12,
        hpad = 16,
        borderBox = true,
        --a drag began or ended: the zones show for the Hero's own items.
        heroSheetDrag = function(element, from)
            zones:SetClass("collapsed", from ~= "inv")
            if from == "inv" then
                local token = HeroSheet.Token()
                local onMap = HeroSheetInventoryActions.OnMap(token)
                --only the words dim: a dimmed zone would let the list show
                --through it; the reason stays at full strength to be read.
                dropZone.children[1]:SetClass("heroSheetDisabled", not onMap)
                dropReason:SetClass("collapsed", onMap)
                if not onMap and token ~= nil then
                    dropReason.text = HeroSheetInventoryActions.NotOnMapText(token)
                end
            end
        end,
        header,
        listScroll,
        zones,
    }
    --Where a dragged item can land: the Drop and Destroy zones while they
    --show, and the list itself for a stash item. The Drop zone refuses when
    --the Hero is not on the map.
    local function ZonesShown()
        return not zones:HasClass("collapsed")
    end
    HeroSheetInventoryActions.RegisterTarget(dropZone, "mapdrop", 10, ZonesShown)
    HeroSheetInventoryActions.RegisterTarget(destroyZone, "destroy", 10, ZonesShown)
    HeroSheetInventoryActions.RegisterTarget(listPanel, "list", 1, function()
        return listPanel.valid
    end)

    --- The entry picked: its row, else another row of the same item (it was
    --- equipped or taken off), else the first one.
    --- @return nil|HeroInventoryEntry
    local function Picked()
        local first, same = nil, nil
        for _, entry in ipairs(state.entries) do
            if entry.key == state.sel then
                return entry
            end
            if same == nil and entry.itemid == state.selItem then
                same = entry
            end
            first = first or entry
        end
        return same or first
    end

    --- What the item pane shows: the stash item picked in the stash column
    --- (read only), else the Hero's row picked.
    --- @return nil|HeroInventoryEntry entry
    --- @return boolean fromStash
    local function PaneEntry()
        if g_stashShown ~= nil and state.token ~= nil then
            for _, entry in ipairs(HeroSheetInventoryActions.StashEntries(HeroSheetInventoryActions.Party(state.token))) do
                if entry.itemid == g_stashShown then
                    return entry --[[@as HeroInventoryEntry]], true
                end
            end
            g_stashShown = nil
        end
        return Picked(), false
    end

    --- Scroll the list so a row shows: the heights above it in the list,
    --- as drawn (the engine's scroll position runs 1 at the top to 0).
    --- @param target Panel a row
    local function ScrollTo(target)
        if listScroll.vscroll ~= true or listScroll.renderedHeight <= 0 then
            return
        end
        local range = listContent.renderedHeight - listScroll.renderedHeight
        if range <= 0 then
            return
        end
        local offset = 0
        local found = false
        for _, group in ipairs(listContent.children) do
            if not found and not group:HasClass("collapsed") then
                local holder = group.children[2]
                if holder ~= nil and target.parent == holder then
                    offset = offset + group.children[1].renderedHeight
                    for _, row in ipairs(holder.children) do
                        if row == target then
                            found = true
                            break
                        end
                        if not row:HasClass("collapsed") then
                            offset = offset + row.renderedHeight
                        end
                    end
                else
                    offset = offset + group.renderedHeight
                end
            end
        end
        if found then
            listScroll.vscrollPosition = 1 - math.max(0, math.min(range, offset - 20)) / range
        end
    end

    --A new item: its row comes into view and pulses once, after the list has
    --laid out with it.
    --- @param panel Panel
    local function Pulse(panel)
        HeroSheetInventory.Glow(panel)
        dmhub.Schedule(0.1, function()
            if not mod.unloaded and panel.valid then
                ScrollTo(panel)
            end
        end)
    end

    PaintList = function()
        local byKind = {leveled = {}, trinket = {}, consumable = {}, other = {}}
        local shown = 0
        for _, entry in ipairs(state.entries) do
            if HeroSheetInventory.Matches(entry, state.filter, state.query) and byKind[entry.kind] ~= nil then
                local list = byKind[entry.kind]
                list[#list+1] = entry
                shown = shown + 1
            end
        end
        local first = true
        for _, kind in ipairs(KINDS) do
            local list = byKind[kind.id]
            groups[kind.id].paint(list, first)
            if #list > 0 then
                first = false
            end
        end
        local carried = 0
        for _, entry in ipairs(state.entries) do
            if not entry.remembered then
                carried = carried + 1
            end
        end
        countLabel.text = tostring(carried)
        empty:SetClass("collapsed", #state.entries > 0)
    end

    ------------------------------------------------------------------
    --The item pane: built once, painted for the item picked.

    local paneIcon = Icon(48)
    local paneName = gui.Label{
        classes = {"heroSheetTitle"},
        text = "",
        fontSize = 20,
        bold = true,
        width = "100%",
        height = "auto",
        textWrap = true,
    }
    local paneKind = gui.Label{
        classes = {"heroSheetCardLabel"},
        text = "",
        fontSize = 12.5,
        width = "100%",
        height = "auto",
        textWrap = true,
        tmargin = 2,
    }
    local paneBusy = false
    local mainButton = gui.Label{
        classes = {"heroSheetButton", "hoverable"},
        text = "",
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = "auto",
        height = 34,
        hpad = 14,
        borderBox = true,
        fontSize = 14,
        textWrap = false,
        valign = "center",
        textAlignment = "center",
        rmargin = 8,
        bmargin = 6,
        halign = "left",
        --Hovering Unequip repaints the preview chips as losses; nothing is rebuilt.
        hover = function(element)
            if element.text == "Unequip" then
                unequipHover = true
                PaintPreview()
            end
        end,
        dehover = function(element)
            if unequipHover then
                unequipHover = false
                PaintPreview()
            end
        end,
        click = function(element)
            local entry, fromStash = PaneEntry()
            if entry == nil or paneBusy then
                return
            end
            --one action per press until the change repaints the pane; a press
            --that saved nothing frees the button at once.
            paneBusy = true
            if fromStash then
                --a stash item's only action is Take.
                if not HeroSheetInventoryActions.Take(entry.itemid) then
                    paneBusy = false
                end
            elseif entry.kind == "consumable" then
                paneBusy = false
                if not HeroSheetInventory.Use(entry.itemid) then
                    audio.FireSoundEvent("UI.Error_Generic")
                end
            elseif not ToggleEquip(entry) then
                paneBusy = false
            end
        end,
    }
    local viewButton = gui.Label{
        classes = {"heroSheetButton", "hoverable", "collapsed"},
        text = "View",
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = "auto",
        height = 34,
        hpad = 14,
        borderBox = true,
        fontSize = 14,
        textWrap = false,
        halign = "left",
        valign = "center",
        textAlignment = "center",
        rmargin = 8,
        bmargin = 6,
        click = function(element)
            local entry = PaneEntry()
            if entry ~= nil and entry.item:has_key("inspectionImage") then
                dmhub.ViewSign(entry.item:try_get("inspectionImage", entry.item.iconid))
            end
        end,
    }
    --- A pane button in the main button's look, sized to its words.
    --- @param text string
    --- @param click fun(element: Panel)
    --- @return Panel
    local function PaneButton(text, click)
        return gui.Label{
            classes = {"heroSheetButton", "hoverable"},
            text = text,
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 6,
            width = "auto",
            height = 34,
            hpad = 14,
            borderBox = true,
            fontSize = 14,
            textWrap = false,
            halign = "left",
            valign = "center",
            textAlignment = "center",
            rmargin = 8,
            bmargin = 6,
            click = click,
        }
    end
    --Give to... and Share to chat beside the main button, then the item menu.
    local giveButton = PaneButton("Give to...", function(element)
        local entry, fromStash = PaneEntry()
        if entry ~= nil and not fromStash then
            HeroSheetInventoryActions.ShowGive(entry)
        end
    end)
    local shareButton = PaneButton("Share to chat", function(element)
        local entry = PaneEntry()
        if entry ~= nil then
            chat.ShareObjectInfo("tbl_Gear", entry.itemid)
        end
    end)
    local paneKeb = MenuButton(true, function(element)
        local entry, fromStash = PaneEntry()
        if entry == nil then
            return
        end
        if fromStash then
            --a stash item's menu; its Set quantity edits its stash row.
            HeroSheetInventoryActions.ShowMenu(element, entry, {
                editQuantity = function()
                    local live = rawget(_G, "g_heroSheetLive")
                    if live ~= nil and live.window ~= nil and live.window.valid then
                        live.window:FireEventTree("heroSheetStashEditQuantity", entry.itemid)
                    end
                end,
                --an Edit of the item repaints the pane and the stash.
                notify = body,
            })
            return
        end
        HeroSheetInventoryActions.ShowMenu(element, entry, {
            --the pane's Set quantity edits the item's row in the list.
            editQuantity = function()
                for _, kind in ipairs(KINDS) do
                    for _, row in ipairs(groups[kind.id].rows()) do
                        if row.entry ~= nil and row.entry.key == entry.key and not row.panel:HasClass("collapsed") then
                            row.editQuantity()
                            return
                        end
                    end
                end
            end,
            notify = body,
        })
    end)
    local actions = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        tmargin = 12,
        mainButton,
        giveButton,
        shareButton,
        viewButton,
        paneKeb,
    }
    local previewHeading = gui.Label{
        classes = {"heroSheetCardLabel"},
        text = "",
        fontSize = 11,
        bold = true,
        width = "100%",
        height = "auto",
        tmargin = 14,
    }
    local previewChips = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        tmargin = 4,
    }
    --- @type {panel: Panel, text: Panel, mark: Panel}[]
    local chipLabels = {}
    local preview = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        previewHeading,
        previewChips,
    }
    --- Paint paneChips: what equipping would change, what the item gives now,
    --- or, while the pointer is on Unequip, what unequipping would change
    --- (each change turned round, so its mark says worse).
    PaintPreview = function()
        local losing = unequipHover and paneEquipped
        preview:SetClass("collapsed", #paneChips == 0)
        previewHeading.text = string.upper(cond(losing, "Unequipping it would change", cond(paneEquipped, "Giving you now", "Equipping it would change")))
        local palette = HeroSheetTheme.Palette()
        for i, chipText in ipairs(paneChips) do
            local chip = chipLabels[i]
            if chip == nil then
                chip = {
                    text = gui.Label{
                        classes = {"heroSheetCardSub"},
                        text = "",
                        width = "auto",
                        height = "auto",
                        fontSize = 12.5,
                        textWrap = false,
                        valign = "center",
                        interactable = false,
                    },
                    mark = HeroSheetCard.Mark(),
                }
                chip.panel = gui.Panel{
                    classes = {"heroSheetPill"},
                    bgimage = "panels/square.png",
                    bgcolor = "clear",
                    border = 1,
                    cornerRadius = 9,
                    width = "auto",
                    height = 22,
                    hpad = 9,
                    borderBox = true,
                    flow = "horizontal",
                    rmargin = 6,
                    bmargin = 4,
                    halign = "left",
                    valign = "center",
                    chip.text,
                    chip.mark,
                }
                chipLabels[i] = chip
                previewChips:AddChild(chip.panel)
            end
            --as the Builder's "Also changes": the muted name, the change
            --in the strong colour, its mark after.
            local change = cond(losing, -chipText.change, chipText.change)
            chip.text.text = string.format("%s <b><color=%s>%s%d</color></b>", chipText.label, palette.cardStrong, cond(change > 0, "+", "-"), math.abs(change))
            HeroSheetCard.SetMark(chip.mark, change > 0)
            chip.panel:SetClass("collapsed", false)
        end
        for i = #paneChips + 1, #chipLabels do
            chipLabels[i].panel:SetClass("collapsed", true)
        end
    end
    --the Level texts (a leveled treasure), or the item's text.
    --- @type {panel: Panel, title: Panel, body: Panel}[]
    local tierBlocks = {}
    local tierHolder = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 10,
    }
    for i = 1, #TIERS do
        local title = gui.Label{
            classes = {"heroSheetCardLabel"},
            text = string.upper(TIERS[i].name),
            fontSize = 11,
            bold = true,
            width = "100%",
            height = "auto",
        }
        local body = gui.Label{
            classes = {"heroSheetCardText"},
            text = "",
            markdown = true,
            fontSize = 13.5,
            width = "100%",
            height = "auto",
            textWrap = true,
            tmargin = 3,
        }
        local panel = gui.Panel{
            classes = {"heroSheetTier"},
            bgimage = "panels/square.png",
            cornerRadius = 8,
            width = "100%",
            height = "auto",
            flow = "vertical",
            pad = 10,
            borderBox = true,
            tmargin = 8,
            title,
            body,
        }
        tierBlocks[i] = {panel = panel, title = title, body = body}
        tierHolder:AddChild(panel)
    end
    local description = gui.Label{
        classes = {"heroSheetCardText"},
        text = "",
        markdown = true,
        fontSize = 13.5,
        width = "100%",
        height = "auto",
        textWrap = true,
        tmargin = 12,
    }
    --the crafting heading, its lines and the button in a dashed box.
    local craftHeading = gui.Label{
        classes = {"heroSheetCardLabel"},
        text = "CRAFTING",
        fontSize = 11,
        bold = true,
        width = "100%",
        height = "auto",
    }
    local craftText = gui.Label{
        classes = {"heroSheetCardText"},
        text = "",
        markdown = true,
        fontSize = 13,
        width = "100%",
        height = "auto",
        textWrap = true,
        tmargin = 4,
    }
    --the Downtime tab, with New project open on Crafting at this item.
    local craftLink = PaneButton("Start it as a project", function(element)
        local entry = PaneEntry()
        local token = state.token
        if entry ~= nil and token ~= nil and HeroSheet.Open(token, "Downtime") then
            HeroSheetDowntimeWindows.NewProject(token, {tab = "crafting", itemid = entry.itemid})
        end
    end)
    craftLink.selfStyle.tmargin = 10
    craftLink.selfStyle.bmargin = 0
    local craft = gui.Panel{
        classes = {"heroSheetDashedBox", "collapsed"},
        bgimage = "panels/square.png",
        bgcolor = "clear",
        border = 1,
        borderStyle = "dashed",
        borderDash = 4,
        borderGap = 3,
        cornerRadius = 8,
        width = "100%",
        height = "auto",
        flow = "vertical",
        vpad = 9,
        hpad = 12,
        borderBox = true,
        tmargin = 14,
        craftHeading,
        craftText,
        craftLink,
    }
    local paneEmpty = gui.Label{
        classes = {"heroSheetMuted", "collapsed"},
        text = "Nothing carried yet.",
        fontSize = 14,
        width = "100%",
        height = "auto",
        tmargin = 6,
    }
    --Back to the list at Narrow; Esc does the same.
    local backButton = gui.Panel{
        classes = {"heroSheetPlateButton", "hoverable", "collapsed"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 12,
        width = "auto",
        height = HeroSheetWindow.TargetSize(26),
        hpad = 10,
        borderBox = true,
        flow = "horizontal",
        halign = "left",
        bmargin = 10,
        click = function(element)
            state.narrowView = "list"
            Arrange()
        end,
        gui.Panel{
            classes = {"heroSheetFg"},
            bgimage = "phosphor/caret-left-bold.png",
            width = 11,
            height = 11,
            valign = "center",
            rmargin = 6,
            interactable = false,
        },
        gui.Label{
            classes = {"heroSheetCardStrong"},
            text = "All items",
            fontSize = 12.5,
            bold = true,
            width = "auto",
            height = "auto",
            valign = "center",
            textWrap = false,
            interactable = false,
        },
    }
    local paneItem = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            paneIcon.panel,
            gui.Panel{
                width = "100%-60",
                height = "auto",
                flow = "vertical",
                lmargin = 12,
                valign = "center",
                paneName,
                paneKind,
            },
        },
        actions,
        preview,
        tierHolder,
        description,
        craft,
    }
    local paneContent = gui.Panel{
        width = "100%-12",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        bpad = 12,
        borderBox = true,
        backButton,
        paneItem,
        paneEmpty,
    }
    local pane = gui.Panel{
        classes = {"heroSheetPlate", "heroSheetBlock"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = PANE_WIDTH,
        height = "100%",
        flow = "vertical",
        lmargin = COLUMN_GAP,
        tpad = 14,
        hpad = 16,
        borderBox = true,
        gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",
            vscroll = true,
            paneContent,
        },
    }

    --what the pane last painted: its preview is worked out only when the
    --item or the Hero's build changes.
    local paneKey = nil

    PaintPane = function()
        local entry, fromStash = PaneEntry()
        local token = state.token
        paneItemKey = nil
        if entry ~= nil and not fromStash then
            paneItemKey = entry.key
        end
        paneItem:SetClass("collapsed", entry == nil)
        paneEmpty:SetClass("collapsed", entry ~= nil)
        if entry == nil or token == nil then
            return
        end
        paneBusy = false
        local item = entry.item
        paneIcon.paint(entry)
        paneName.text = entry.name .. cond(entry.quantity > 1, string.format(" x%d", entry.quantity), "")
        paneKind.text = HeroSheetInventory.KindLine(item, entry.kind)

        --the main button: Equip / Unequip, or "Use one (3 left)"; a stash
        --item's is Take.
        local label = nil
        if state.write and fromStash then
            label = "Take"
        elseif state.write and not entry.remembered then
            if entry.kind == "consumable" then
                if type(item:try_get("consumable")) == "table" then
                    label = string.format("Use one (%d left)", entry.quantity)
                end
            elseif entry.equipped and entry.slot ~= nil then
                label = "Unequip"
            elseif not entry.equipped and HeroSheetWrite.EquipSlot(token.properties, entry.itemid) ~= nil then
                label = "Equip"
            end
        end
        mainButton:SetClass("collapsed", label == nil)
        mainButton.text = label or ""
        mainButton:SetClass("heroSheetSolid", label ~= nil and label ~= "Unequip")
        viewButton:SetClass("collapsed", not item:has_key("inspectionImage"))
        --a stash item has Take and its menu (Give and Share are in it).
        local own = state.write and not fromStash
        giveButton:SetClass("collapsed", not own or entry.remembered == true or #HeroSheetInventoryActions.Targets(token) == 0)
        shareButton:SetClass("collapsed", not own)
        --heroSheetKebOff, not collapsed: the pane's "..." style shows it at all times.
        paneKeb:SetClass("heroSheetKebOff", not state.write)
        actions:SetClass("collapsed", label == nil and not own and not item:has_key("inspectionImage"))

        --what equipping would change, or what it gives now.
        local key = entry.key .. "|" .. tostring(token.charid) .. "|" .. dmhub.ToJson(token.properties:Equipment()) .. "|" .. tostring(state.level)
        if key ~= paneKey then
            paneKey = key
            paneChips = {}
            if entry.kind ~= "consumable" and not entry.remembered then
                paneChips = PreviewChips(token, entry)
            end
            paneEquipped = entry.equipped == true
            PaintPreview()
        end

        --a leveled treasure's three Levels in order, each one reached lit.
        local leveled = entry.kind == "leveled"
        tierHolder:SetClass("collapsed", not leveled)
        description:SetClass("collapsed", leveled)
        if leveled then
            for i, tier in ipairs(TIERS) do
                local block = tierBlocks[i]
                local text = item:try_get(tier.field)
                local has = type(text) == "string" and text ~= ""
                block.panel:SetClass("collapsed", not has)
                block.body.text = has and text or ""
                local reached = state.level >= tier.level
                --reached: a solid fill with dark words; not reached: muted words
                --(opacity is not inherited, so the words carry it themselves).
                block.panel:SetClass("heroSheetTierReached", reached)
                block.title:SetClass("heroSheetTierDim", not reached)
                block.body:SetClass("heroSheetTierDim", not reached)
            end
        else
            local text = item:try_get("description")
            description.text = type(text) == "string" and text or ""
            description:SetClass("collapsed", type(text) ~= "string" or text == "")
        end
        local craftLine = CraftText(item)
        craftText.text = craftLine or ""
        craft:SetClass("collapsed", craftLine == nil)
    end

    ------------------------------------------------------------------

    --The add pane is built the first time it is wanted (the pointer on Add
    --items, or its click), not with the tab: most visits never open it.
    --- @type nil|Panel
    local addPane = nil
    --what Fit last gave the item pane; the add pane takes its place, so the same.
    local addFit = {width = nil, lmargin = COLUMN_GAP}
    --- @return Panel
    local function EnsureAddPane()
        if addPane ~= nil and addPane.valid then
            return addPane
        end
        local built = HeroSheetInventoryAdd.Create{
            close = function()
                ShowAdd(false)
            end,
        }
        if addFit.width ~= nil then
            built.selfStyle.width = addFit.width
        end
        built.selfStyle.lmargin = addFit.lmargin
        body:AddChild(built)
        addPane = built
        return built
    end
    WarmAdd = function()
        if HeroSheetInventoryActions.CanAdd() then
            EnsureAddPane():FireEvent("heroSheetAddWarm")
        end
    end
    ShowAdd = function(open)
        open = open and HeroSheetInventoryActions.CanAdd()
        state.adding = open
        if open then
            EnsureAddPane():FireEvent("heroSheetAddOpen")
        end
        --at Narrow it takes the list's place.
        if state.narrow then
            state.narrowView = cond(open, "add", "list")
        end
        Arrange()
    end

    --Narrow's tabs over the list, in the sheet's list-tab look.
    --- @type table<string, Panel>
    local narrowTabs = {}
    --- @param id string
    --- @param text string
    --- @return Panel
    local function NarrowTab(id, text)
        local tab = gui.Panel{
            classes = {"heroSheetListTabFrame", "hoverable", cond(id == "items", "selected", nil)},
            bgimage = "panels/square.png",
            border = {x1 = 0, y1 = 2, x2 = 0, y2 = 0},
            width = "auto",
            height = 26,
            rmargin = 16,
            flow = "horizontal",
            halign = "left",
            valign = "bottom",
            click = function(element)
                state.narrowTab = id
                state.narrowView = "list"
                Arrange()
            end,
            gui.Label{
                classes = {"heroSheetListTab", cond(id == "items", "selected", nil)},
                text = string.upper(text),
                fontSize = 16,
                bold = true,
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                textWrap = false,
                interactable = false,
            },
        }
        narrowTabs[id] = tab
        return tab
    end
    local stashTab = NarrowTab("stash", "Party stash")
    --on a plate of its own: the frosted window would show through the tabs.
    local tabRow = gui.Panel{
        classes = {"heroSheetPlate", "heroSheetBlock", "collapsed"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = TAB_ROW,
        flow = "horizontal",
        hpad = 16,
        borderBox = true,
        bmargin = TAB_ROW_GAP,
        NarrowTab("items", "Items"),
        stashTab,
    }
    --the Party stash tab takes a dragged item at Narrow.
    stashTab:SetClass("heroSheetDropTarget", true)
    HeroSheetInventoryActions.RegisterTarget(stashTab, "stash", 2, function()
        return state.narrow and not tabRow:HasClass("collapsed")
    end)
    --the stash on its own tab at Narrow: a second stash block, shown by Arrange.
    local narrowStash = HeroSheetInventoryActions.StashPanel{embedded = true}

    --- Show what the tier, the Narrow tab and view call for: at Wide and Medium
    --- the list beside the item (or add) pane; at Narrow one of them at a time.
    Arrange = function()
        local narrow = state.narrow
        tabRow:SetClass("collapsed", not narrow)
        for id, tab in pairs(narrowTabs) do
            tab:SetClassTree("selected", id == state.narrowTab)
        end
        local view = state.narrowView
        local hasParty = HeroSheetInventoryActions.Party(state.token) ~= nil
        stashTab:SetClass("collapsed", not hasParty)
        if narrow and state.narrowTab == "stash" and not hasParty then
            state.narrowTab = "items"
        end
        if not narrow then
            listPanel:SetClass("collapsed", false)
            narrowStash:SetClass("collapsed", true)
            pane:SetClass("collapsed", state.adding)
            if addPane ~= nil then
                addPane:SetClass("collapsed", not state.adding)
            end
            backButton:SetClass("collapsed", true)
            body.captureEscape = false
            return
        end
        if view == "add" and not state.adding then
            view = "list"
            state.narrowView = view
        end
        listPanel:SetClass("collapsed", not (view == "list" and state.narrowTab == "items"))
        narrowStash:SetClass("collapsed", not (view == "list" and state.narrowTab == "stash"))
        if view == "list" and state.narrowTab == "stash" then
            narrowStash:FireEvent("heroSheetStash")
        end
        pane:SetClass("collapsed", view ~= "item")
        if addPane ~= nil then
            addPane:SetClass("collapsed", view ~= "add")
        end
        backButton:SetClass("collapsed", view ~= "item")
        --Esc goes back to the list first.
        body.captureEscape = view ~= "list"
    end

    body = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "horizontal",
        --the old grid's item editor closed (Edit in the menu): it changed the
        --item's record, which the Hero's signature does not see.
        refreshInventory = function(element)
            if state.token == nil then
                return
            end
            HeroSheetRefresh.Stale()
            state.entries = Entries(state.token)
            paneKey = nil
            PaintList()
            PaintPane()
        end,
        captureEscape = false,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function(element)
            if state.adding and state.narrowView == "add" then
                ShowAdd(false)
            else
                state.narrowView = "list"
                Arrange()
            end
        end,
        listPanel,
        narrowStash,
        pane,
    }

    --a stash row was clicked, or the pane goes back to the Hero's items.
    g_showStash = function()
        if g_stashShown ~= nil then
            state.shown = nil
            --at Narrow the stash item opens in place of the stash.
            if state.narrow then
                state.narrowView = "item"
                Arrange()
            end
        else
            local picked = Picked()
            state.shown = picked ~= nil and picked.key or nil
        end
        PaintList()
        PaintPane()
    end

    --- The two columns for the window's width: the pane takes about two
    --- fifths, within its bounds, and the list the rest; a narrow list's
    --- header takes two lines.
    --- @param width number the window's width in sheet units
    local function Fit(width)
        local tier = HeroSheet.Tier()
        local narrow = tier == "narrow"
        local card = CARD_COLUMN[tier]
        local room = width - 2 * CONTENT_PAD - cond(card ~= nil, (card or 0) + COLUMN_GAP, 0)
        local listWidth = room
        if narrow then
            --one thing at a time, the whole width, under the tabs.
            for _, panel in ipairs({listPanel, pane, narrowStash}) do
                panel.selfStyle.width = "100%"
                panel.selfStyle.lmargin = 0
            end
            addFit.width = "100%"
            addFit.lmargin = 0
            body.selfStyle.height = string.format("100%%-%d", TAB_ROW + TAB_ROW_GAP)
        else
            local paneWidth = math.floor(math.max(PANE_MIN_WIDTH, math.min(PANE_WIDTH, room * 0.42)))
            pane.selfStyle.width = paneWidth
            pane.selfStyle.lmargin = COLUMN_GAP
            addFit.width = paneWidth
            addFit.lmargin = COLUMN_GAP
            listPanel.selfStyle.width = string.format("100%%-%d", paneWidth + COLUMN_GAP)
            body.selfStyle.height = "100%"
            listWidth = room - paneWidth - COLUMN_GAP
        end
        if addPane ~= nil then
            addPane.selfStyle.width = addFit.width
            addPane.selfStyle.lmargin = addFit.lmargin
        end
        --the header: one line, the chips under the heading, or (too narrow
        --for the chips and the search side by side) a third line.
        --Beside the heading the chip row sits at the right; on its own line
        --it starts at the left. It wraps only when it needs a third line: a
        --row that wraps with room to spare spreads its chips apart.
        local headerHeight = HEADER_HEIGHT
        local ownLine = listWidth < HEADER_WRAP_WIDTH
        local threeLines = listWidth < CHIP_ROW_WIDTH
        chipRow.wrap = threeLines
        --the full width keeps it off the heading's line.
        chipRow.selfStyle.width = cond(ownLine, "100%", "auto")
        chipRow.selfStyle.halign = cond(ownLine, "left", "right")
        if threeLines then
            headerHeight = HEADER_THREE_LINES
        elseif ownLine then
            headerHeight = HEADER_TWO_LINES
        end
        header.selfStyle.height = headerHeight
        listScroll.selfStyle.height = string.format("100%%-%d", headerHeight)
        if narrow ~= state.narrow then
            state.narrow = narrow
            state.narrowView = "list"
        end
        Arrange()
    end

    return HeroSheetRefresh.Block({
        width = "100%",
        height = "100%",
        flow = "vertical",
        heroSheetLayout = function(element, width, height)
            Fit(width)
        end,
        --switching tab returns Narrow's view to the list.
        heroSheetTab = function(element, tabid)
            if state.narrowView ~= "list" then
                if state.adding then
                    ShowAdd(false)
                end
                state.narrowView = "list"
                Arrange()
            end
        end,
        tabRow,
        body,
    }, {
        name = "inventory",
        signature = function(token)
            local props = token.properties
            --charges live on each item's record, not the Hero (Set charges
            --uploads the record), so the items' charges count here too.
            local gearTable = dmhub.GetTable("tbl_Gear") or {}
            local charges = {}
            local function Charges(itemid)
                local item = gearTable[itemid]
                if item ~= nil then
                    charges[#charges+1] = string.format("%s:%s/%s", itemid, tostring(item:try_get("consumableChargesConsumed")), tostring(item:try_get("consumableCharges")))
                end
            end
            for _, itemid in pairs(props:Equipment()) do
                if type(itemid) == "string" then
                    Charges(itemid)
                end
            end
            for itemid, _ in pairs(props:try_get("inventory", {})) do
                Charges(itemid)
            end
            table.sort(charges)
            --an item put in the party stash is not listed as used up (Entries).
            local party = HeroSheetInventoryActions.Party(token)
            return table.concat({
                tostring(token.charid),
                dmhub.ToJson(props:Equipment()),
                dmhub.ToJson(props:try_get("inventory", {})),
                dmhub.ToJson(props:try_get("equipmentMeta", {})),
                tostring(props:CharacterLevel()),
                tostring(props:try_get("kitid")), tostring(props:try_get("kitid2")),
                tostring(HeroSheetWrite.CanWrite()),
                table.concat(charges, ","),
                party ~= nil and dmhub.ToJson(party.properties.inventory or {}) or "",
            }, "|")
        end,
        refresh = function(panel, token)
            local previous = state.token
            local otherHero = previous == nil or previous.charid ~= token.charid
            state.token = token
            state.write = HeroSheetWrite.CanWrite()
            addButton:SetClass("collapsed", not HeroSheetInventoryActions.CanAdd())
            if state.adding and not HeroSheetInventoryActions.CanAdd() then
                ShowAdd(false)
            end
            state.level = 1
            pcall(function() state.level = token.properties:CharacterLevel() end)
            state.entries = Entries(token)
            --another Hero starts on the list's first item, with nothing new.
            if otherHero then
                state.sel = nil
                state.selItem = nil
                state.known = nil
                paneKey = nil
                g_stashShown = nil
                --another Hero at Narrow starts on the list.
                state.narrowView = "list"
            end
            local items = {}
            --- @type nil|string
            local added = nil
            for _, entry in ipairs(state.entries) do
                if not entry.remembered then
                    items[entry.itemid] = true
                    if state.known ~= nil and not state.known[entry.itemid] then
                        added = added or entry.key
                    end
                end
            end
            state.known = items
            if added ~= nil then
                state.sel = added
            end
            local picked = Picked()
            state.shown = picked ~= nil and picked.key or nil
            if picked ~= nil then
                state.sel, state.selItem = picked.key, picked.itemid
            end
            --a stash item just taken shows as the Hero's new row instead.
            if added ~= nil then
                g_stashShown = nil
            end
            if g_stashShown ~= nil then
                state.shown = nil
            end
            PaintList()
            PaintPane()
            Arrange()
            if added ~= nil then
                for _, kind in ipairs(KINDS) do
                    for _, row in ipairs(groups[kind.id].rows()) do
                        if row.entry ~= nil and row.entry.key == added and not row.panel:HasClass("collapsed") then
                            Pulse(row.panel)
                        end
                    end
                end
            end
        end,
    })
end

--- Clean the open Hero's inventory as the old grid does when it opens: items
--- gone from the compendium, and clashing grid slots.
--- @param token nil|CharacterToken
function HeroSheetInventory.Sanitize(token)
    if token == nil or token.properties == nil or not HeroSheetWrite.CanWrite() then
        return
    end
    --SanitizeInventory is shared with loot objects and typed for them, so
    --the Hero's properties are cast to call it.
    local props = token.properties --[[@as any]]
    pcall(function() props:SanitizeInventory() end)
end

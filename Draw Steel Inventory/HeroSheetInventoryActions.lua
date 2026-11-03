local mod = dmhub.GetModLoading()

--The Hero sheet Inventory's moving parts: the item menu, Give, dragging,
--the party stash column and the Drop / Destroy confirms. Writes to the open
--Hero go through HeroSheetWrite.Save; the stash (the party's loot record)
--and other tokens are written the way the old inventory grid writes them.
--This mod loads before Draw Steel V: the sheet's globals are only read
--inside functions.

HeroSheetInventoryActions = rawget(_G, "HeroSheetInventoryActions") or {}
local Actions = HeroSheetInventoryActions

--- The party stash of a Hero's party, or nil for a Hero with no party.
--- @param token nil|CharacterToken
--- @return nil|LuaPartyInfo
function Actions.Party(token)
    if token == nil or token.partyid == nil or token.partyid == "" then
        return nil
    end
    local party = dmhub.GetPartyInfo(token.partyid)
    if party == nil or not party.valid then
        return nil
    end
    return party
end

--- An item's kind as the Inventory groups it: the same rule the sheet uses
--- when it reads the Hero's treasures.
--- @param item table a tbl_Gear row
--- @return string
local function KindOf(item)
    if EquipmentCategory.IsLeveledTreasure(item) then
        return "leveled"
    elseif EquipmentCategory.IsTrinket(item) or EquipmentCategory.IsArtifact(item) then
        return "trinket"
    elseif EquipmentCategory.IsConsumable(item) then
        return "consumable"
    end
    return "other"
end

--- An item's kind as the Inventory groups it: the same rule the sheet uses
--- when it reads the Hero's treasures.
Actions.KindOf = KindOf

--- Whether the viewer may add items from the compendium: anyone who can edit
--- the Hero, except a player under Strict Inventory (as in the old grid).
--- @return boolean
function Actions.CanAdd()
    if not HeroSheetWrite.CanWrite() then
        return false
    end
    return dmhub.isDM or not dmhub.GetSettingValue("strict:inventory")
end

--- Add a compendium item to the Hero: one, or its bundle (TradedQuantity,
--- as the old grid adds). The new row is selected and pulses.
--- @param item table a tbl_Gear row
--- @return boolean
function Actions.AddToHero(item)
    if not Actions.CanAdd() then
        return false
    end
    local quantity = item:TradedQuantity()
    local ok = HeroSheetWrite.Save{
        description = string.format("Add %s", item.name),
        execute = function(hero)
            hero:GiveItem(item.id, quantity)
        end,
    }
    if ok then
        audio.FireSoundEvent("UI.Inv_Place")
    end
    return ok
end

--- Add a compendium item to the party stash (dragged onto it).
--- @param item table a tbl_Gear row
--- @return boolean
function Actions.AddToStash(item)
    local party = Actions.Party(HeroSheet.Token())
    if party == nil or not Actions.CanAdd() then
        return false
    end
    party:BeginChanges()
    party.properties:GiveItem(item.id, item:TradedQuantity())
    party:CompleteChanges(string.format("Add %s", item.name))
    audio.FireSoundEvent("UI.Inv_Place")
    return true
end

--- @class HeroStashEntry
--- @field key string "stash|<itemid>", apart from the Hero's own rows
--- @field itemid string
--- @field name string
--- @field kind string
--- @field item table the tbl_Gear row
--- @field quantity integer
--- @field equipped boolean always false
--- @field equippable boolean always false
--- @field stash boolean always true: the hover card shows no worn state

--- What the stash holds, by name.
--- @param party nil|LuaPartyInfo
--- @return HeroStashEntry[]
function Actions.StashEntries(party)
    local result = {}
    if party == nil then
        return result
    end
    local gearTable = dmhub.GetTable("tbl_Gear") or {}
    local inventory = party.properties.inventory or {}
    for itemid, entry in pairs(inventory) do
        local item = gearTable[itemid]
        local quantity = type(entry) == "table" and tonumber(entry.quantity) or 0
        if item ~= nil and quantity ~= nil and quantity > 0 then
            result[#result+1] = {
                key = "stash|" .. itemid,
                itemid = itemid,
                name = item.name,
                kind = KindOf(item),
                item = item,
                quantity = math.floor(quantity),
                equipped = false,
                equippable = false,
                stash = true,
            }
        end
    end
    table.sort(result, function(left, right)
        return left.name < right.name
    end)
    return result
end

--- Whether the Hero's token is on the map that is showing, so a dropped item
--- has somewhere to lie (otherwise Drop is dimmed).
--- @param token nil|CharacterToken
--- @return boolean
function Actions.OnMap(token)
    if token == nil or token.floorid == nil or token.floorid == "" then
        return false
    end
    return game.GetFloor(token.floorid) ~= nil
end

--- The hover reason a dimmed Drop gives.
--- @param token CharacterToken
--- @return string
function Actions.NotOnMapText(token)
    return string.format("%s isn't on this map.", token.name or "This Hero")
end

----------------------------------------------------------------------
--Writes. Each returns true when it wrote.

--- Change whoever holds a row's item, as one undo step: the open Hero
--- (through HeroSheetWrite.Save) or, for a party stash row, the party's
--- stash record (as the old trade window writes it). fn gets its properties.
--- @param entry HeroInventoryEntry|HeroStashEntry
--- @param description string
--- @param fn fun(props: any)
--- @return boolean wrote
local function SaveHolder(entry, description, fn)
    if entry.stash then
        local party = Actions.Party(HeroSheet.Token())
        if party == nil or not HeroSheetWrite.CanWrite() then
            return false
        end
        party:BeginChanges()
        fn(party.properties)
        party:CompleteChanges(description)
        return true
    end
    return HeroSheetWrite.Save{
        description = description,
        execute = function(hero)
            fn(hero)
        end,
    }
end

--- Take some of a row's item off the Hero, inside a save. An equipped row
--- comes out of its own slot; a carried row from the carried stack. remember
--- keeps the slot waiting for the item, so it is worn again when it comes
--- back (it went to the party stash).
--- @param hero creature the live Hero
--- @param entry HeroInventoryEntry
--- @param count integer
--- @param remember boolean
--- @return integer taken
local function TakeOff(hero, entry, count, remember)
    if entry.equipped and entry.slot ~= nil then
        if hero:Equipment()[entry.slot] ~= entry.itemid then
            return 0
        end
        --emptied directly, not with Unequip: Unequip hands the item back
        --through GiveItem, which refills any other empty slot waiting for the
        --same item, so the Hero would keep a copy that also left.
        hero:SetEquipmentInSlot(entry.slot, nil)
        hero:ClearEquipmentMetaSlot(entry.slot)
        --only one slot waits for an item: GiveItem fills every waiting slot
        --from a single copy, so two would turn one copy back into two.
        if remember and not Actions.SlotWaitsFor(hero, entry.itemid) then
            hero:SetEquipmentShadowInSlot(entry.slot, entry.itemid)
        end
        return 1
    end
    local have = hero:GetItemQuantity(entry.itemid) or 0
    local taken = math.min(count, have)
    if taken > 0 then
        hero:SetItemQuantity(entry.itemid, have - taken)
    end
    return taken
end

--- How many of a row can be moved: an equipped row is one item.
--- @param entry HeroInventoryEntry
--- @return integer
function Actions.Count(entry)
    if entry.equipped then
        return 1
    end
    return math.max(1, entry.quantity or 1)
end

--- Run a move's two writes (the Hero and the stash, a floor or another
--- token) as one undo step. Undo used to put the item back on only one side,
--- so it ended up in both places.
--- @param fn fun(): boolean
--- @return boolean
local function AsOneUndo(fn)
    dmhub.BeginTransaction()
    local ok, result = pcall(fn)
    dmhub.EndTransaction()
    if not ok then
        error(result, 0)
    end
    return result
end

--- Put a row in the party stash.
--- @param entry HeroInventoryEntry
--- @param count nil|integer how many; the whole row when nil
--- @return boolean
function Actions.PutInStash(entry, count)
    local party = Actions.Party(HeroSheet.Token())
    if party == nil then
        return false
    end
    --one write to both sides, refused if another player changed either first.
    local ok = HeroSheetWrite.SaveAtomic{
        description = string.format("Put %s in the party stash", entry.name),
        others = {party},
        execute = function(hero)
            local taken = TakeOff(hero, entry, count or Actions.Count(entry), true)
            if taken > 0 then
                party.properties:GiveItem(entry.itemid, taken)
            end
        end,
    }
    if ok then
        audio.FireSoundEvent("UI.Inv_Place")
    end
    return ok
end

--- Give some of a row to another token (a Hero, retainer or follower).
--- @param entry HeroInventoryEntry
--- @param target CharacterToken
--- @param count integer
--- @return boolean
function Actions.GiveTo(entry, target, count)
    if target == nil or not target.valid then
        return false
    end
    --one write to both sides, refused if another player changed either first.
    --A stash row gives from the party's stash; the Hero is a holder anyway.
    local party = nil
    if entry.stash then
        party = Actions.Party(HeroSheet.Token())
        if party == nil then
            return false
        end
    end
    ---@type (CharacterToken|LuaPartyInfo)[]
    local others = {target}
    if party ~= nil then
        others[#others+1] = party
    end
    local ok = HeroSheetWrite.SaveAtomic{
        description = string.format("Give %s", entry.name),
        others = others,
        execute = function(hero)
            local holder = party ~= nil and party.properties or hero
            local taken = TakeOff(holder, entry, count, false)
            if taken > 0 then
                target.properties:GiveItem(entry.itemid, taken)
            end
        end,
    }
    if ok then
        audio.FireSoundEvent("UI.Inv_Place")
    end
    return ok
end

--- Take a stash item into the Hero's inventory, all of it. If another player
--- takes it first (here, or in the same moment elsewhere), nothing moves and a
--- toast says so. A slot that remembers the item equips it again.
--- @param itemid string
--- @return boolean
function Actions.Take(itemid)
    local party = Actions.Party(HeroSheet.Token())
    local item = (dmhub.GetTable("tbl_Gear") or {})[itemid]
    if party == nil or item == nil or not HeroSheetWrite.CanWrite() then
        return false
    end
    local have = party.properties:GetItemQuantity(itemid) or 0
    if have <= 0 then
        HeroSheetWindow.Toast(string.format("%s was already taken.", item.name))
        audio.FireSoundEvent("UI.Error_Generic")
        return false
    end
    local ok = HeroSheetWrite.SaveAtomic{
        description = string.format("Take %s from the party stash", item.name),
        others = {party},
        refusedText = string.format("%s was already taken.", item.name),
        execute = function(hero)
            local count = party.properties:GetItemQuantity(itemid) or 0
            if count > 0 then
                party.properties:SetItemQuantity(itemid, 0)
                hero:GiveItem(itemid, count)
            end
        end,
    }
    if not ok then
        return false
    end
    audio.FireSoundEvent("UI.Inv_Grab")
    --at Narrow the inventory is on the other tab: say where it went.
    if HeroSheet.Tier() == "narrow" then
        HeroSheetWindow.Toast(string.format("%s moved to your inventory.", item.name))
    end
    return true
end

--- Take everything in the stash, as one change on each side.
--- @return boolean
function Actions.TakeAll()
    local party = Actions.Party(HeroSheet.Token())
    if party == nil or not HeroSheetWrite.CanWrite() then
        return false
    end
    local moving = {}
    for _, entry in ipairs(Actions.StashEntries(party)) do
        moving[#moving+1] = entry.itemid
    end
    if #moving == 0 then
        return false
    end
    local ok = HeroSheetWrite.SaveAtomic{
        description = "Take all from the party stash",
        others = {party},
        refusedText = "Someone else took from the stash first. Nothing moved.",
        execute = function(hero)
            for _, itemid in ipairs(moving) do
                local count = party.properties:GetItemQuantity(itemid) or 0
                if count > 0 then
                    party.properties:SetItemQuantity(itemid, 0)
                    hero:GiveItem(itemid, count)
                end
            end
        end,
    }
    if not ok then
        return false
    end
    audio.FireSoundEvent("UI.Inv_Grab")
    return true
end

--- Drop some of a row on the map beside the Hero, as a lootable object. The
--- Hero must be on the showing map: the item leaves only once it has a floor.
--- @param entry HeroInventoryEntry
--- @param count integer
--- @return boolean
function Actions.Drop(entry, count)
    local token = HeroSheet.Token()
    if token == nil or not Actions.OnMap(token) then
        return false
    end
    return AsOneUndo(function()
        local taken = 0
        local ok = HeroSheetWrite.Save{
            description = string.format("Drop %s", entry.name),
            execute = function(hero)
                taken = TakeOff(hero, entry, count, false)
            end,
        }
        if not ok or taken <= 0 then
            return false
        end
        loot.SpawnDroppedItem(token, entry.itemid, taken)
        audio.FireSoundEvent("UI.Inv_Place")
        return true
    end)
end

--- Destroy some of a row.
--- @param entry HeroInventoryEntry
--- @param count integer
--- @return boolean
function Actions.Destroy(entry, count)
    return SaveHolder(entry, string.format("Destroy %s", entry.name), function(holder)
        TakeOff(holder, entry, count, false)
    end)
end

--- Set how many of a carried item the Hero has (at least one: Destroy, which
--- asks first, is the way to none).
--- @param entry HeroInventoryEntry
--- @param count integer
--- @return boolean
function Actions.SetQuantity(entry, count)
    if count < 1 then
        return false
    end
    return SaveHolder(entry, string.format("Set quantity of %s", entry.name), function(holder)
        holder:SetItemQuantity(entry.itemid, count)
    end)
end

--- Set a consumable's charges left. Charges live on the item's record, so
--- every Hero carrying the same item shares them.
--- @param entry HeroInventoryEntry
--- @param left integer
function Actions.SetCharges(entry, left)
    local item = entry.item
    local total = tonumber(item:try_get("consumableCharges", 1)) or 1
    if left < 0 then
        return
    end
    if left > total then
        item.consumableCharges = left
        total = left
    end
    item.consumableChargesConsumed = total - left
    dmhub.SetAndUploadTableItem("tbl_Gear", item)
    HeroSheetRefresh.Changed()
end

--- A copy of an item record under a new id; its map object and the consumable
--- it uses up follow the copy. The caller uploads it. The old inventory grid
--- and the Add pane's Duplicate use it too.
--- @param item table a tbl_Gear row
--- @return table
local function CopyItem(item)
    local copy = DeepCopy(item)
    copy.id = dmhub.GenerateGuid()
    if copy:has_key("itemObjectId") then
        local asset = assets:GetObjectNode(copy.itemObjectId)
        if asset ~= nil then
            copy.itemObjectId = asset:Duplicate()
        end
    end
    if copy:has_key("consumable") and copy.consumable:has_key("consumables") then
        copy.consumable.consumables[item.id] = nil
        copy.consumable.consumables[copy.id] = 1
    end
    return copy
end
Actions.CopyItem = CopyItem

--- Swap one of a carried item for a copy only this Hero has, which can be
--- edited (the old grid's Make Unique).
--- @param entry HeroInventoryEntry
function Actions.MakeUnique(entry)
    local item = entry.item
    local copy = CopyItem(item)
    if not string.starts_with(item.name, "Unique") then
        copy.name = string.format("Unique %s", item.name)
    end
    copy.baseid = item.id
    if not copy:IsAmmoForWeapon() then
        copy.unique = true
    end
    copy.hidden = true
    dmhub.SetAndUploadTableItem("tbl_Gear", copy)
    SaveHolder(entry, string.format("Make %s unique", entry.name), function(holder)
        local have = holder:GetItemQuantity(entry.itemid) or 0
        if have >= 1 then
            holder:SetItemQuantity(entry.itemid, have - 1)
            holder:SetItemQuantity(copy.id, 1)
        end
    end)
end

--- One more of a unique item, as its own copy (the old grid's Duplicate Item).
--- @param entry HeroInventoryEntry
function Actions.Duplicate(entry)
    local copy = CopyItem(entry.item)
    dmhub.SetAndUploadTableItem("tbl_Gear", copy)
    SaveHolder(entry, string.format("Duplicate %s", entry.name), function(holder)
        holder:GiveItem(copy.id, 1)
    end)
end

--- A unique item becomes a compendium item anyone can add.
--- @param entry HeroInventoryEntry
function Actions.AddToCompendium(entry)
    local item = entry.item
    item.unique = nil
    item.hidden = nil
    dmhub.SetAndUploadTableItem("tbl_Gear", item)
    HeroSheetRefresh.Changed()
end

--- Open a pack: one fewer pack, its contents added.
--- @param entry HeroInventoryEntry
function Actions.Unpack(entry)
    local item = entry.item
    SaveHolder(entry, string.format("Unpack %s", entry.name), function(holder)
        local have = holder:GetItemQuantity(entry.itemid) or 0
        if have < 1 then
            return
        end
        holder:SetItemQuantity(entry.itemid, have - 1)
        for _, content in ipairs(item:try_get("packItems", {})) do
            holder:GiveItem(content.itemid, content.quantity)
        end
    end)
end

--- Edit an item in the old grid's item editor. It writes the item's record,
--- so the sheet is told to look again when it closes.
--- @param entry HeroInventoryEntry
--- @param notify nil|Panel gets "refreshInventory" when the editor closes
function Actions.Edit(entry, notify)
    if gamehud == nil or gamehud.createItemDialog == nil then
        return
    end
    gamehud.createItemDialog.data.show(notify, entry.item)
end

--- A small modal with one centred message, in the old inventory grid's look.
--- The grid's Destroy confirm and the imbue failure below both use it.
--- @param title string
--- @param message string
--- @param buttons table[] the buttons, as gamehud:ModalDialog takes them
function Actions.MessageModal(title, message, buttons)
    if gamehud == nil then
        return
    end
    gamehud:ModalDialog{
        title = title,
        width = 560,
        height = 240,
        flow = "vertical",
        buttonsHalign = "center",
        buttons = buttons,
        children = {
            --fixed width: the body panel sizes to its content, so "100%" would wrap every word.
            gui.Label{
                width = 500,
                height = "auto",
                halign = "center",
                valign = "center",
                textAlignment = "center",
                text = message,
            },
        },
    }
end

--- Show why an imbue failed ("Imbuement Failed"); nil (success) shows
--- nothing. The old grid's imbue menu uses it too.
--- @param message nil|string the reason DSImbuement gave
function Actions.ShowImbueFailure(message)
    if message == nil then
        return
    end
    Actions.MessageModal("Imbuement Failed", message, {
        {text = "Close", escapeActivates = true},
    })
end

--- The Apply imbuement targets for an imbuement row, as the old grid offers
--- them: a new mundane item of its type, then the Hero's unique items it can
--- go on (only unique items, so a failed imbue never leaves a free copy).
--- @param entry HeroInventoryEntry
--- @return HeroListMenuEntry[]
local function ImbueTargets(entry)
    local item = entry.item
    local targets = {}
    local targetType = item:try_get("imbueTargetType")
    if not EquipmentCategory.IsImbuement(item) or not targetType then
        return targets
    end
    local token = HeroSheet.Token()
    if token == nil then
        return targets
    end
    --one imbuement used up, with the item it made or changed, in one save.
    --- @param description string
    --- @param imbued table
    --- @param gives boolean the Hero gets the imbued item (a new mundane one)
    local function Spend(description, imbued, gives)
        dmhub.SetAndUploadTableItem(equipment.tableName, imbued)
        HeroSheetWrite.Save{
            description = description,
            execute = function(hero)
                if gives then
                    hero:GiveItem(imbued.id, 1)
                end
                hero:SetItemQuantity(entry.itemid, (hero:GetItemQuantity(entry.itemid) or 0) - 1)
            end,
        }
    end
    local prereq = item:try_get("imbuePrereq")
    if prereq == nil or prereq == "none" then
        targets[#targets+1] = {
            text = "Mundane " .. targetType,
            click = function()
                local mundane = DSImbuement.CreateMundaneItem(targetType)
                if mundane == nil then
                    return
                end
                local imbued, message = DSImbuement.ImbueItem(item, mundane)
                if imbued then
                    Spend("Imbue mundane item", imbued, true)
                else
                    Actions.ShowImbueFailure(message)
                end
            end,
        }
    end
    local itemTable = dmhub.GetTable(equipment.tableName) or {}
    local props = token.properties
    local seen = {}
    --- @param id string
    local function Offer(id)
        local target = itemTable[id]
        if seen[id] or target == nil or target:try_get("unique", false) ~= true or not DSImbuement.CanImbue(item, target) then
            return
        end
        seen[id] = true
        targets[#targets+1] = {
            text = target.name,
            click = function()
                --run on a copy, so a failure changes nothing.
                local imbued, message = DSImbuement.ImbueItem(item, DeepCopy(target))
                if imbued then
                    Spend("Imbue Item", imbued, false)
                else
                    Actions.ShowImbueFailure(message)
                end
            end,
        }
    end
    for id, _ in pairs(props:try_get("inventory", {})) do
        Offer(id)
    end
    for _, id in pairs(props:try_get("equipment", {})) do
        if type(id) == "string" then
            Offer(id)
        end
    end
    return targets
end

----------------------------------------------------------------------
--Windows.

--- A count with - and + either side; the number itself is click-to-type
--- like every number on the sheet.
--- @param get fun(): integer
--- @param set fun(count: integer)
--- @param max integer
--- @return Panel
local function Stepper(get, set, max)
    local number
    --- @param delta integer
    local function Step(delta)
        set(math.max(1, math.min(max, get() + delta)))
        number:FireEventTree("refreshNumber")
    end
    --- @param icon string
    --- @param delta integer
    --- @param label string
    local function Button(icon, delta, label)
        return gui.Panel{
            classes = {"heroSheetButton", "heroSheetSolid", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 6,
            width = HeroSheetWindow.TargetSize(28),
            height = HeroSheetWindow.TargetSize(28),
            valign = "center",
            click = function()
                Step(delta)
            end,
            linger = function(element)
                gui.Tooltip(label)(element)
            end,
            gui.Panel{
                classes = {"heroSheetFg"},
                bgimage = icon,
                width = 12,
                height = 12,
                halign = "center",
                valign = "center",
                interactable = false,
            },
        }
    end
    number = HeroSheetTheme.ClickNumber{
        get = get,
        set = function(count)
            set(math.max(1, math.min(max, count)))
        end,
        min = 1,
        fontSize = 16,
        classes = {"heroSheetCardStrong"},
    }
    return gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "center",
        Button("phosphor/minus-bold.png", -1, "Fewer"),
        gui.Panel{
            width = 44,
            height = "auto",
            valign = "center",
            number,
        },
        Button("phosphor/plus-bold.png", 1, "More"),
    }
end

--The "How many" line's height and the gap above it; a window with one is
--this much taller.
local HOW_MANY_LINE = 34
local HOW_MANY_GAP = 14
local HOW_MANY_HEIGHT = HOW_MANY_LINE + HOW_MANY_GAP

--- The "How many" line of a window, for a stack.
--- @param get fun(): integer
--- @param set fun(count: integer)
--- @param max integer
--- @return Panel
local function HowMany(get, set, max)
    return gui.Panel{
        width = "100%",
        height = HOW_MANY_LINE,
        flow = "horizontal",
        tmargin = HOW_MANY_GAP,
        gui.Label{
            classes = {"heroSheetCardLabel"},
            text = "How many",
            fontSize = 13,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            rmargin = 12,
            textWrap = false,
        },
        Stepper(get, set, max),
    }
end

--Size of a Give target: a portrait card, its name under it.
local TARGET_W = 64
local TARGET_PICTURE_H = 76
local TARGET_H = TARGET_PICTURE_H + 34

--- @class HeroGiveTarget
--- @field stash boolean the party stash
--- @field token nil|CharacterToken
--- @field name string

--- Who a Hero can give to, as in the old grid: the party stash first, then
--- every player-controlled token but the Hero, retainers and followers included.
--- @param token CharacterToken
--- @return HeroGiveTarget[]
function Actions.Targets(token)
    local result = {}
    if Actions.Party(token) ~= nil then
        result[#result+1] = {stash = true, name = "Party stash"}
    end
    local others = {}
    if gamehud ~= nil and gamehud.tokenInfo ~= nil then
        for _, other in pairs(gamehud.tokenInfo.tokens) do
            if other.playerControlled and other.charid ~= token.charid and other.properties ~= nil
                and type(other.name) == "string" and other.name ~= "" then
                others[#others+1] = {stash = false, token = other, name = other.name}
            end
        end
    end
    table.sort(others, function(left, right)
        return left.name < right.name
    end)
    for _, other in ipairs(others) do
        result[#result+1] = other
    end
    return result
end

--- The Give window: who to, and how many for a stack.
--- @param entry HeroInventoryEntry
function Actions.ShowGive(entry)
    local token = HeroSheet.Token()
    if token == nil then
        return
    end
    local targets = Actions.Targets(token)
    --a stash item goes to someone, never back to the stash.
    if entry.stash then
        local others = {}
        for _, target in ipairs(targets) do
            if not target.stash then
                others[#others+1] = target
            end
        end
        targets = others
    end
    local count = Actions.Count(entry)
    local quantity = 1
    --- @type nil|HeroGiveTarget
    local picked = nil
    --- @type nil|Panel
    local saveButton = nil
    --- @type Panel[]
    local pictures = {}

    --Save reads "Give" until someone is picked, then "Give to <name>".
    local function PaintSave()
        if saveButton == nil or not saveButton.valid then
            return
        end
        saveButton:SetClass("heroSheetDisabled", picked == nil)
        local label = saveButton.children[1]
        if label ~= nil then
            --opacity is not inherited: the words dim with the frame.
            label:SetClass("heroSheetDisabled", picked == nil)
            label.text = cond(picked ~= nil, string.format("Give to %s", picked ~= nil and picked.name or ""), "Give")
        end
    end

    local width = HeroSheetWindow.DialogWidth(520)
    local perRow = math.max(1, math.floor((width - 40) / (TARGET_W + 10)))
    local rows = math.ceil(#targets / perRow)
    local children = {}
    for i, target in ipairs(targets) do
        local picture = gui.Panel{
            classes = {"heroSheetGiveTarget"},
            bgimage = "panels/square.png",
            border = 2,
            cornerRadius = 6,
            width = TARGET_W,
            height = TARGET_PICTURE_H,
            halign = "center",
            interactable = false,
        }
        if target.stash then
            picture:AddChild(gui.Panel{
                classes = {"heroSheetFg"},
                bgimage = "phosphor/treasure-chest.png",
                width = 32,
                height = 32,
                halign = "center",
                valign = "center",
                interactable = false,
            })
        elseif target.token ~= nil then
            local tok = target.token --[[@as CharacterToken]]
            local applied = false
            pcall(function() applied = EotwHeroCard.ApplyPortrait(picture, tok, TARGET_W / TARGET_PICTURE_H) end)
            if not applied and type(tok.portrait) == "string" and tok.portrait ~= "" then
                picture.bgimage = tok.portrait
                picture.selfStyle.bgcolor = "white"
            end
        end
        pictures[i] = picture
        children[#children+1] = gui.Panel{
            classes = {"hoverable"},
            bgimage = "panels/square.png",
            bgcolor = "clear",
            width = TARGET_W,
            height = TARGET_H,
            flow = "vertical",
            rmargin = 10,
            bmargin = 8,
            click = function(element)
                picked = target
                for j, picturePanel in ipairs(pictures) do
                    picturePanel:SetClass("heroSheetGivePicked", j == i)
                end
                PaintSave()
            end,
            picture,
            gui.Label{
                classes = {"heroSheetCardSub"},
                text = target.name,
                fontSize = 12,
                width = TARGET_W + 8,
                height = 30,
                halign = "center",
                textAlignment = "top",
                textWrap = true,
                tmargin = 3,
                interactable = false,
            },
        }
    end
    local body = {
        gui.Panel{
            width = "100%",
            height = rows * (TARGET_H + 8),
            flow = "horizontal",
            wrap = true,
            children = children,
        },
    }
    if count > 1 then
        body[#body+1] = HowMany(function() return quantity end, function(chosen) quantity = chosen end, count)
    end
    local frame = HeroSheetWindow.ShowDialog{
        title = string.format("Give %s", entry.name),
        width = 520,
        bodyHeight = rows * (TARGET_H + 8) + cond(count > 1, HOW_MANY_HEIGHT, 0),
        saveText = "Give",
        body = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            children = body,
        },
        onSave = function()
            if picked == nil then
                return false
            end
            if picked.stash then
                Actions.PutInStash(entry, quantity)
            else
                Actions.GiveTo(entry, picked.token --[[@as CharacterToken]], quantity)
            end
            return true
        end,
    }
    --Save is the footer's primary button (its frame holds the label).
    if frame ~= nil then
        for _, panel in ipairs(frame:GetChildrenWithClassRecursive("heroSheetPrimary") or {}) do
            if #panel.children > 0 then
                saveButton = panel
            end
        end
        PaintSave()
    end
end

--- Drop or Destroy asks first, and for a stack how many.
--- @param entry HeroInventoryEntry
--- @param kind string "drop" or "destroy"
function Actions.ShowRemove(entry, kind)
    local count = Actions.Count(entry)
    local quantity = 1
    local drop = kind == "drop"
    --- @type Panel[]
    local children = {
        HeroSheetWindow.DialogText(cond(drop, "It leaves your inventory and lies on the map beside you.", "This removes it for good.")),
    }
    if count > 1 then
        children[#children+1] = HowMany(function() return quantity end, function(chosen) quantity = chosen end, count)
    end
    HeroSheetWindow.ShowDialog{
        title = cond(drop, string.format("Drop %s on the map?", entry.name), string.format("Destroy %s?", entry.name)),
        width = 460,
        --one line of text, plus the How many line for a stack.
        bodyHeight = 24 + cond(count > 1, HOW_MANY_HEIGHT, 0),
        saveText = cond(drop, "Drop", "Destroy"),
        body = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            children = children,
        },
        onSave = function()
            local removing = cond(count > 1, quantity, count)
            if drop then
                Actions.Drop(entry, removing)
            else
                Actions.Destroy(entry, removing)
            end
            return true
        end,
    }
end

----------------------------------------------------------------------
--The item menu: only what applies to the item, as in the old grid. Split
--and Merge are not on it: the list shows one row per item.

--- @class HeroInventoryMenuArgs
--- @field editQuantity nil|fun() turns the row's count into its field
--- @field editCharges nil|fun() turns the row's charges into their field
--- @field notify nil|Panel gets "refreshInventory" when the item editor closes

--- Open a row's or the pane's "..." menu for an item the Hero has, or one in
--- the party stash.
--- @param anchor Panel
--- @param entry HeroInventoryEntry
--- @param args HeroInventoryMenuArgs
function Actions.ShowMenu(anchor, entry, args)
    local token = HeroSheet.Token()
    if token == nil or not HeroSheetWrite.CanWrite() then
        return
    end
    local item = entry.item
    local unique = item:try_get("unique", false) == true
    local hidden = item:try_get("hidden", false) == true
    local carried = not entry.equipped and not entry.remembered
    --A party stash row offers neither Put in party stash nor Drop, and no
    --imbuing, which only works on the Hero's own items.
    local stash = entry.stash == true
    --- @type (HeroListMenuEntry|string)[]
    local entries = {}
    --- @param menuEntry HeroListMenuEntry
    local function Add(menuEntry)
        entries[#entries+1] = menuEntry
    end
    local function Separator()
        if #entries > 0 and entries[#entries] ~= "-" then
            entries[#entries+1] = "-"
        end
    end

    Add{text = "Share to chat", click = function()
        chat.ShareObjectInfo("tbl_Gear", entry.itemid)
    end}
    if not entry.remembered then
        local targets = 0
        for _, target in ipairs(Actions.Targets(token)) do
            if not (stash and target.stash) then
                targets = targets + 1
            end
        end
        if targets > 0 then
            Add{text = "Give to...", click = function()
                Actions.ShowGive(entry)
            end}
        end
        if not stash and Actions.Party(token) ~= nil then
            Add{text = "Put in party stash", click = function()
                Actions.PutInStash(entry)
            end}
        end
    end

    Separator()
    if carried and not unique and args.editQuantity ~= nil then
        Add{text = "Set quantity", click = args.editQuantity}
    end
    if carried and args.editCharges ~= nil and item:try_get("consumable") ~= nil and (tonumber(item:try_get("consumableCharges", 1)) or 1) > 1 then
        Add{text = "Set charges", click = args.editCharges}
    end
    if carried and EquipmentCategory.IsPack(item) then
        Add{text = "Unpack", click = function()
            Actions.Unpack(entry)
        end}
    end

    Separator()
    if carried and not unique and not hidden then
        Add{text = "Make unique", click = function()
            Actions.MakeUnique(entry)
        end}
    end
    if unique or hidden then
        Add{text = "Edit", click = function()
            Actions.Edit(entry, args.notify)
        end}
        if carried then
            Add{text = "Duplicate", click = function()
                Actions.Duplicate(entry)
            end}
        end
    end
    if unique then
        Add{text = "Add to compendium", click = function()
            Actions.AddToCompendium(entry)
        end}
    end
    local imbue = {}
    if carried and not stash then
        imbue = ImbueTargets(entry)
    end
    if #imbue > 0 then
        --what to imbue opens beside the entry on hover.
        Add{text = "Apply imbuement", submenu = imbue}
    end

    if stash then
        Separator()
        Add{text = "Destroy", danger = true, click = function()
            Actions.ShowRemove(entry, "destroy")
        end}
    elseif not entry.remembered then
        Separator()
        if Actions.OnMap(token) then
            Add{text = "Drop on the map", click = function()
                Actions.ShowRemove(entry, "drop")
            end}
        else
            Add{text = "Drop on the map", reason = Actions.NotOnMapText(token)}
        end
        Add{text = "Destroy", danger = true, click = function()
            Actions.ShowRemove(entry, "destroy")
        end}
    end
    if entries[#entries] == "-" then
        entries[#entries] = nil
    end
    HeroSheetLists.ShowMenu(anchor, entries)
end

----------------------------------------------------------------------
--Dragging: a row stays where it is, dimmed, and a chip with the item's icon
--and name follows the pointer. The Hero's items drop on the stash or on the
--Drop / Destroy zones at the foot of the list; a stash item drops on the
--list (Take). The buttons and the menu do each without dragging.

--- @class HeroInventoryDrag
--- @field from string "inv" (one of the Hero's rows), "stash" or "add" (a compendium row)
--- @field entry HeroInventoryEntry|HeroStashEntry
--- @field row Panel the row being dragged
--- @field chip Panel
--- @field start {x: number, y: number} the pointer at the start, in the pop-up layer's units

--- The drag under way, if any.
--- @type nil|HeroInventoryDrag
local g_drag = nil

--The chip's size, in screen units.
local CHIP_HEIGHT = 34

--- Where the pointer is over a panel, in the pop-up layer's units (the
--- engine's mousePoint runs 0-1 from the panel's bottom-left corner).
--- @param panel Panel
--- @return nil|{x: number, y: number}
local function PointerOver(panel)
    local rect = Tabletop.PanelRect(panel)
    if rect == nil then
        return nil
    end
    local mouse = panel.mousePoint
    return {x = rect.x + mouse.x * rect.w, y = rect.y + (1 - mouse.y) * rect.h}
end


--- Whether a drag from `from` may end on a target of `kind`.
--- @param from string
--- @param kind nil|string
--- @return boolean
function Actions.CanDrop(from, kind)
    if from == "inv" then
        if kind == "stash" then
            return Actions.Party(HeroSheet.Token()) ~= nil
        elseif kind == "mapdrop" then
            return Actions.OnMap(HeroSheet.Token())
        end
        return kind == "destroy"
    end
    if from == "add" then
        --a compendium row goes into the list or the stash.
        return kind == "list" or (kind == "stash" and Actions.Party(HeroSheet.Token()) ~= nil)
    end
    return from == "stash" and kind == "list"
end

--The drop targets: the engine finds targets under the dragged panel itself,
--which stays put here (only the chip moves), so the sheet tests the pointer
--against these instead.
--- @class HeroInventoryDropTarget
--- @field panel Panel
--- @field kind string what it takes: "stash", "list", "mapdrop" or "destroy"
--- @field priority number the higher wins where targets overlap (a zone over the list)
--- @field shown fun(): boolean whether it is showing (and taking drops) now

--- @type HeroInventoryDropTarget[]
local g_targets = {}
--- @type nil|Panel the target under the pointer, edged while the chip is over it
local g_over = nil

--- Make a panel a drop target for dragged items.
--- @param panel Panel
--- @param kind string
--- @param priority number
--- @param shown fun(): boolean
function Actions.RegisterTarget(panel, kind, priority, shown)
    local kept = {}
    for _, target in ipairs(g_targets) do
        if target.panel.valid and target.panel ~= panel then
            kept[#kept+1] = target
        end
    end
    kept[#kept+1] = {panel = panel, kind = kind, priority = priority, shown = shown}
    g_targets = kept
end

--- Where the pointer is during a drag: where it started plus how far it has
--- moved (dragDelta runs right and down, in screen pixels).
--- @param row Panel
--- @return {x: number, y: number}
local function Pointer(row)
    local delta = row.dragDelta
    local start = g_drag ~= nil and g_drag.start or {x = 0, y = 0}
    return {x = start.x + delta.x, y = start.y + delta.y}
end

--- The showing target under a point that takes a drag from `from`.
--- @param point {x: number, y: number}
--- @param from string
--- @return nil|HeroInventoryDropTarget
local function TargetAt(point, from)
    local best = nil
    for _, target in ipairs(g_targets) do
        if target.panel.valid and target.shown() then
            local rect = Tabletop.PanelRect(target.panel)
            if rect ~= nil and rect.w > 0 and point.x >= rect.x and point.x <= rect.x + rect.w and point.y >= rect.y and point.y <= rect.y + rect.h
                and Actions.CanDrop(from, target.kind) and (best == nil or target.priority > best.priority) then
                best = target
            end
        end
    end
    return best
end

--- Edge the target under the chip (and only it).
--- @param target nil|HeroInventoryDropTarget
local function Highlight(target)
    local panel = target ~= nil and target.panel or nil
    if panel == g_over then
        return
    end
    if g_over ~= nil and g_over.valid then
        g_over:SetClass("heroSheetDropOver", false)
    end
    g_over = panel
    if panel ~= nil then
        panel:SetClass("heroSheetDropOver", true)
    end
end

--- Tell the sheet a drag began or ended, so the zones and the targets show.
--- @param from nil|string nil when it ended
local function Announce(from)
    local live = rawget(_G, "g_heroSheetLive")
    if live ~= nil and live.window ~= nil and live.window.valid then
        live.window:FireEventTree("heroSheetDrag", from)
    end
end

--- The chip that follows the pointer: the item's icon and name.
--- @param entry HeroInventoryEntry|HeroStashEntry
--- @return Panel
local function Chip(entry)
    local icon = HeroSheetInventory.Icon(24)
    --paint reads only the item and its kind, which a stash entry has too.
    icon.paint(entry --[[@as HeroInventoryEntry]])
    local name = entry.name .. cond((entry.quantity or 1) > 1, string.format(" x%d", entry.quantity or 1), "")
    return gui.Panel{
        classes = {"heroSheetDragChip"},
        styles = HeroSheetTheme.RootStyles(),
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 8,
        width = "auto",
        height = CHIP_HEIGHT,
        hpad = 8,
        borderBox = true,
        flow = "horizontal",
        halign = "left",
        valign = "top",
        --never in the way of the targets under the pointer.
        interactable = false,
        icon.panel,
        gui.Label{
            classes = {"heroSheetCardStrong"},
            text = name,
            fontSize = 13,
            bold = true,
            width = "auto",
            height = "auto",
            lmargin = 8,
            valign = "center",
            textWrap = false,
        },
    }
end

--- A row's drag began: the chip appears at the pointer and the zones show.
--- @param row Panel
--- @param from string "inv" or "stash"
--- @param entry HeroInventoryEntry|HeroStashEntry
function Actions.BeginDrag(row, from, entry)
    Actions.CancelDrag()
    local layer = HeroSheetWindow.PopupLayer()
    local start = PointerOver(row)
    if layer == nil or start == nil then
        return
    end
    --dragDelta counts from the press, but a drag begins only once the pointer
    --has moved past the threshold: take that first move off the start.
    local moved = row.dragDelta
    start = {x = start.x - moved.x, y = start.y - moved.y}
    local chip = Chip(entry)
    layer:AddChild(chip)
    chip.x = math.floor(start.x + moved.x + 12)
    chip.y = math.floor(start.y + moved.y - CHIP_HEIGHT / 2)
    chip:SetAsLastSibling()
    g_drag = {from = from, entry = entry, row = row, chip = chip, start = start}
    row:SetClass("heroSheetDragSource", true)
    audio.FireSoundEvent("UI.Inv_Grab")
    Announce(from)
end

--- The pointer moved during a drag: the chip follows it.
--- @param row Panel
function Actions.DragMove(row)
    if g_drag == nil or g_drag.row ~= row or not g_drag.chip.valid then
        return
    end
    local pointer = Pointer(row)
    g_drag.chip.x = math.floor(pointer.x + 12)
    g_drag.chip.y = math.floor(pointer.y - CHIP_HEIGHT / 2)
    Highlight(TargetAt(pointer, g_drag.from))
end

--- The drag is over without a drop (or a drop was handled): the chip goes,
--- the row and the zones go back.
function Actions.CancelDrag()
    local drag = g_drag
    g_drag = nil
    if drag == nil then
        return
    end
    if drag.chip.valid then
        drag.chip:DestroySelf()
    end
    if drag.row.valid then
        drag.row:SetClass("heroSheetDragSource", false)
    end
    Highlight(nil)
    Announce(nil)
end

--- The row was let go: the drop goes to the target under the pointer, if any.
--- @param row Panel
function Actions.EndDrag(row)
    local drag = g_drag
    if drag == nil or drag.row ~= row then
        Actions.CancelDrag()
        return
    end
    local target = TargetAt(Pointer(row), drag.from)
    Actions.CancelDrag()
    if target == nil then
        return
    end
    local kind = target.kind
    if drag.from == "stash" then
        Actions.Take(drag.entry.itemid)
        return
    end
    if drag.from == "add" then
        if kind == "stash" then
            Actions.AddToStash(drag.entry.item)
        else
            Actions.AddToHero(drag.entry.item)
        end
        return
    end
    local entry = drag.entry --[[@as HeroInventoryEntry]]
    if kind == "stash" then
        Actions.PutInStash(entry)
    elseif kind == "mapdrop" then
        Actions.ShowRemove(entry, "drop")
    elseif kind == "destroy" then
        Actions.ShowRemove(entry, "destroy")
    end
end

--- The drag fields a row takes: draggable without moving, the chip in its
--- place. entry() gives the row's entry now (nil: not draggable).
--- @param from string "inv", "stash" or "add"
--- @param entry fun(): nil|HeroInventoryEntry|HeroStashEntry
--- @return table fields to merge into the row's gui args
function Actions.DragFields(from, entry)
    return {
        draggable = true,
        dragMove = false,
        dragThreshold = 6,
        beginDrag = function(element)
            local current = entry()
            if current ~= nil and HeroSheetWrite.CanWrite() and (from ~= "add" or Actions.CanAdd()) then
                Actions.BeginDrag(element, from, current)
            end
        end,
        dragging = function(element)
            Actions.DragMove(element)
        end,
        drag = function(element)
            Actions.EndDrag(element)
        end,
    }
end

----------------------------------------------------------------------
--The party stash column: under the kit card on the Inventory tab. Rows show
--the item's hover card; a click opens it in the item pane, read only, with
--Take. The stash is another record (the party's), so the block looks for
--changes itself, twice a second while it shows.

--Its heading, footer and row sizes, in sheet units.
local STASH_HEADER = 26
local STASH_FOOTER = 30
local STASH_ROW = 44

--- Whether one of a Hero's empty slots waits for an item (it was equipped
--- when it went in the stash).
--- @param props creature
--- @param itemid string
--- @return boolean
function Actions.SlotWaitsFor(props, itemid)
    for slot, meta in pairs(props:try_get("equipmentMeta", {})) do
        if type(meta) == "table" and meta.shadow == itemid and props:Equipment()[slot] == nil then
            return true
        end
    end
    return false
end

--- @class HeroStashPanelArgs
--- @field embedded nil|boolean Narrow's copy on the Inventory's Party stash tab: the Inventory shows it, and it fills its place

--- The stash block. Its height is set by the sheet's column fit (the card
--- column's copy) or fills its place (the embedded copy).
--- @param args nil|HeroStashPanelArgs
--- @return Panel
function Actions.StashPanel(args)
    local embedded = args ~= nil and args.embedded == true
    --- @type HeroStashEntry[]
    local entries = {}
    local signature = nil
    --- @type nil|Panel
    local block = nil

    local takeAll = gui.Label{
        classes = {"heroSheetPlateButton", "hoverable"},
        text = "Take all",
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 12,
        width = "auto",
        height = 24,
        hpad = 10,
        borderBox = true,
        fontSize = 12,
        bold = true,
        textWrap = false,
        halign = "right",
        valign = "center",
        click = function(element)
            Actions.TakeAll()
        end,
    }
    local header = gui.Panel{
        width = "100%",
        height = STASH_HEADER,
        flow = "horizontal",
        gui.Label{
            classes = {"heroSheetCardStrong"},
            text = "PARTY STASH",
            fontSize = 16,
            bold = true,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            textWrap = false,
        },
        takeAll,
    }
    local empty = gui.Label{
        classes = {"heroSheetCardSub", "collapsed"},
        text = "The stash is empty.",
        fontSize = 13,
        width = "auto",
        height = "auto",
        halign = "left",
        tmargin = 6,
    }
    local holder = gui.Panel{
        width = "100%-10",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
    }
    local list = gui.Panel{
        width = "100%",
        height = string.format("100%%-%d", STASH_HEADER + STASH_FOOTER + 4),
        flow = "vertical",
        vscroll = true,
        tmargin = 2,
        holder,
        empty,
    }
    --the drag's hint, shown only to someone who can move items (Paint).
    local hint = gui.Label{
        classes = {"heroSheetCardSub"},
        text = "Drag an item here to stash it",
        fontSize = 11.5,
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "bottom",
        textWrap = false,
    }
    local footer = gui.Panel{
        width = "100%",
        height = STASH_FOOTER,
        flow = "horizontal",
        gui.Label{
            classes = {"heroSheetPill"},
            text = "Shared by the party",
            bgimage = "panels/square.png",
            bgcolor = "clear",
            border = 1,
            cornerRadius = 9,
            width = "auto",
            height = 20,
            hpad = 8,
            borderBox = true,
            fontSize = 11.5,
            textWrap = false,
            halign = "left",
            valign = "bottom",
        },
        hint,
    }

    --- @class HeroStashRow
    --- @field panel Panel
    --- @field paint fun(entry: HeroStashEntry, waits: boolean, write: boolean)
    --- @field entry nil|HeroStashEntry

    --- @type HeroStashRow[]
    local rows = {}

    --- @return HeroStashRow
    local function NewRow()
        local row = {entry = nil}
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
        local sub = HeroSheetTheme.EllipsisLabel{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 11.5,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
        }
        local words = gui.Panel{
            width = "100%-60",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "center",
            interactable = false,
            name,
            sub,
        }
        local take = gui.Label{
            classes = {"heroSheetSmallButton", "hoverable", "heroSheetOn"},
            text = "Take",
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
                    Actions.Take(row.entry.itemid)
                end
            end,
        }
        --Set quantity (the menu) turns the row's right side into a count
        --field, as on the list's rows.
        local field = HeroSheetInventory.CountField()
        local function EditQuantity()
            local entry = row.entry
            if entry == nil then
                return
            end
            field.open(tostring(entry.quantity), function(count)
                local current = row.entry
                if current ~= nil and count >= 1 and count ~= current.quantity then
                    Actions.SetQuantity(current --[[@as HeroInventoryEntry]], count)
                end
            end)
        end
        --- @param anchor Panel
        local function OpenMenu(anchor)
            local entry = row.entry
            if entry ~= nil and HeroSheetWrite.CanWrite() then
                Actions.ShowMenu(anchor, entry --[[@as HeroInventoryEntry]], {
                    editQuantity = EditQuantity,
                    --an Edit of the item repaints the stash (the block's refreshInventory).
                    notify = block,
                })
            end
        end
        local keb = HeroSheetInventory.MenuButton(false, function(element)
            OpenMenu(element)
        end)
        local rowArgs = {
            classes = {"heroSheetListRow", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 8,
            width = "100%",
            height = STASH_ROW,
            flow = "horizontal",
            hpad = 10,
            borderBox = true,
            tmargin = 6,
            click = function(element)
                if row.entry ~= nil then
                    HeroSheetInventory.ShowStashItem(row.entry.itemid)
                end
            end,
            --the item menu opens on right-click too, as the list's rows.
            rightClick = function(element)
                OpenMenu(element)
            end,
            --the item pane's Set quantity for this stash item edits this row.
            heroSheetStashEditQuantity = function(element, itemid)
                if row.entry ~= nil and row.entry.itemid == itemid then
                    EditQuantity()
                end
            end,
            words,
            take,
            keb,
            field.panel,
            --dims the row while it is dragged (opacity would not reach its words).
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
        --a stash item dragged onto the list is taken.
        for argName, value in pairs(Actions.DragFields("stash", function()
            return row.entry
        end)) do
            rowArgs[argName] = value
        end
        local panel = gui.Panel(HeroSheetTheme.HoverCard(rowArgs, function(pinned, close)
            local entry = row.entry
            local token = HeroSheet.Token()
            if entry == nil or token == nil then
                return gui.Panel{width = 1, height = 1}
            end
            local level = 1
            pcall(function() level = token.properties:CharacterLevel() end)
            return HeroSheetTheme.CardFrame(HeroSheetCard.ItemCard(entry, level, nil, pinned), pinned, close)
        end, false))
        row.panel = panel
        row.paint = function(entry, waits, write)
            local same = row.entry ~= nil and row.entry.itemid == entry.itemid
            row.entry = entry
            name.text = entry.name .. cond(entry.quantity > 1, string.format(" x%d", entry.quantity), "")
            --a slot that remembers the item says it will be worn again.
            sub.text = cond(waits, "Equips again when you take it", HeroSheetInventory.KIND_NAMES[entry.kind] or "Item")
            take:SetClass("collapsed", not write)
            keb:SetClass("heroSheetKebOff", not write)
            if field.editing() and not same then
                field.close()
            end
            --the words leave room for Take and the "..." (shown on hover).
            words.selfStyle.width = cond(write, "100%-90", "100%")
            name.selfStyle.maxWidth = "100%"
            sub.selfStyle.maxWidth = "100%"
            panel:SetClass("heroSheetRowPinned", HeroSheetInventory.StashShown() == entry.itemid)
            if not same then
                panel.tooltip = nil
            end
        end
        return row --[[@as HeroStashRow]]
    end

    --- Paint the stash as it is now; only when what it shows changed.
    --- @param force boolean
    local function Paint(force)
        local token = HeroSheet.Token()
        local party = Actions.Party(token)
        if token == nil or party == nil then
            return
        end
        local write = HeroSheetWrite.CanWrite()
        local props = token.properties
        local key = table.concat({
            token.charid,
            dmhub.ToJson(party.properties.inventory or {}),
            dmhub.ToJson(props:try_get("equipmentMeta", {})),
            tostring(write),
            tostring(HeroSheetInventory.StashShown()),
        }, "|")
        if not force and key == signature then
            return
        end
        --the party's stash changed (another Hero, another client): the list
        --checks again, as it hides used-up items that sit in the stash.
        if signature ~= nil and key ~= signature then
            HeroSheetRefresh.Recheck()
        end
        signature = key
        entries = Actions.StashEntries(party)
        for i, entry in ipairs(entries) do
            local row = rows[i]
            if row == nil then
                row = NewRow()
                rows[i] = row
                holder:AddChild(row.panel)
            end
            row.panel:SetClass("collapsed", false)
            row.paint(entry, Actions.SlotWaitsFor(props, entry.itemid), write)
        end
        for i = #entries + 1, #rows do
            rows[i].panel:SetClass("collapsed", true)
            rows[i].entry = nil
        end
        empty:SetClass("collapsed", #entries > 0)
        takeAll:SetClass("collapsed", not write or #entries == 0)
        hint:SetClass("collapsed", not write)
    end

    block = gui.Panel{
        classes = {"heroSheetPlate", "heroSheetBlock", "heroSheetDropTarget", "collapsed"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = HeroSheetCard.TREASURES_MIN_HEIGHT,
        flow = "vertical",
        vpad = 12,
        hpad = 16,
        borderBox = true,
        tmargin = 12,
        valign = "top",
        data = {tier = ""},
        thinkTime = 0.5,
        think = function(element)
            Paint(false)
        end,
        --shown on the Inventory tab for a Hero in a party (at Narrow the
        --Inventory shows its own copy on the Party stash tab).
        heroSheetTab = function(element, tabid)
            element:FireEvent("heroSheetStashShow", tabid)
        end,
        heroSheetHero = function(element)
            local state = HeroSheet.State()
            element:FireEvent("heroSheetStashShow", state ~= nil and state.tab or "")
        end,
        --Narrow has no stash column: look again when the tier changes.
        heroSheetLayout = function(element)
            local tier = HeroSheet.Tier()
            if tier ~= element.data.tier then
                element.data.tier = tier
                local state = HeroSheet.State()
                element:FireEvent("heroSheetStashShow", state ~= nil and state.tab or "")
            end
        end,
        heroSheetStashShow = function(element, tabid)
            if embedded then
                return
            end
            local show = tabid == "Inventory" and HeroSheet.Tier() ~= "narrow" and Actions.Party(HeroSheet.Token()) ~= nil
            element:SetClass("collapsed", not show)
            if show then
                Paint(true)
            end
        end,
        heroSheetStash = function(element)
            Paint(true)
        end,
        --the item editor closed after an Edit: the item's record changed, which
        --the stash's signature does not read. This repaints every stash block
        --and the item pane, which may show the same stash item.
        refreshInventory = function(element)
            HeroSheetInventory.ShowStashItem(HeroSheetInventory.StashShown())
        end,
        header,
        list,
        footer,
    }
    if embedded then
        block.selfStyle.height = "100%"
        block.selfStyle.tmargin = 0
    end
    --one of the Hero's items dropped here goes in the stash.
    Actions.RegisterTarget(block, "stash", 1, function()
        return not block:HasClass("collapsed")
    end)
    return block
end

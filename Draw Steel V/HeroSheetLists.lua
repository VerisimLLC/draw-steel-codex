local mod = dmhub.GetModLoading()

--The Hero sheet's lists: Abilities beside Features and Notes, under the
--stats band on the Character tab. Wide shows the two columns side by side,
--each scrolling on its own; Medium shows one pane with Abilities / Features /
--Notes tabs. This file is the frame and Abilities; HeroSheetFeatures and
--HeroSheetNotes fill the other column. The abilities come from the shared
--read of the Hero (HeroSheetRefresh.Read, which the EotW sheet uses too), so
--both sheets list the same abilities in the same groups.

HeroSheetLists = rawget(_G, "HeroSheetLists") or {}

--- The lists' floor in sheet units: a window too short for the band and
--- this much list scrolls the whole tab instead.
HeroSheetLists.MIN_HEIGHT = 300

--- The gap between the band and the lists, as between the sheet's other blocks.
HeroSheetLists.TOP_MARGIN = 16

--The hover cards' content width (the stat and item cards' too).
local CARD_WIDTH = HeroSheetTheme.CARD_WIDTH

--Rows, in sheet units: 8-unit padding round a 16-unit name, 6 apart; free
--strikes and standard actions are smaller, two to a line.
local ROW_HEIGHT = 38
local COMPACT_ROW_HEIGHT = 32
local ROW_GAP = 6

--Widths a row sets aside when it sizes its name and keywords, in sheet
--units: the Custom pill with its margins, and the "..." button with the
--row's padding and the gaps between its parts.
local CUSTOM_PILL_ROOM = 76
local ROW_FIXED_ROOM = 70

--- @class HeroListItem
--- @field name string
--- @field keywords string the ability's keywords, sorted ("Kit, Melee, Strike")
--- @field actionTag string "Main action", "Maneuver", "Triggered action"...
--- @field costTag nil|string "Signature", "3 Focus"
--- @field colorKey string the action colour key's class (ActivatedAbility.actionColorKey)
--- @field custom boolean saved on this Hero by hand (innateActivatedAbilities): Edit and Delete apply
--- @field ability nil|ActivatedAbility
--- @field trigger nil|TriggeredAbilityDisplay a triggered action shown from a feature's trigger

--- @class HeroListGroup
--- @field id string
--- @field items HeroListItem[]

--The ability groups in order: the groups the EotW sheet lists, with the
--Beastheart's companion abilities after Other abilities; free strikes and
--standard actions are every Hero's and show smaller.
local GROUPS = {
    {id = "main", name = "Main actions"},
    {id = "maneuver", name = "Maneuvers"},
    {id = "triggered", name = "Triggered actions"},
    {id = "other", name = "Other abilities"},
    {id = "companion", name = "Companion abilities"},
    {id = "freestrike", name = "Free strikes", compact = true},
    {id = "standard", name = "Standard actions", compact = true, note = "Every Hero can do these"},
}

--Which groups the player has folded, remembered on this machine for every
--Hero ("ab:standard": Standard actions starts folded, as on the EotW sheet).
local g_foldedSetting = setting{
    id = "herosheet:foldedgroups",
    description = "Hero sheet folded list groups",
    storage = "preference",
    default = "ab:standard",
}

--- @param key string
--- @return boolean
local function IsFolded(key)
    for part in string.gmatch(g_foldedSetting:Get() or "", "[^,]+") do
        if part == key then
            return true
        end
    end
    return false
end

--- @param key string
--- @param folded boolean
local function SetFolded(key, folded)
    local parts = {}
    for part in string.gmatch(g_foldedSetting:Get() or "", "[^,]+") do
        if part ~= key then
            parts[#parts+1] = part
        end
    end
    if folded then
        parts[#parts+1] = key
    end
    g_foldedSetting:Set(table.concat(parts, ","))
end

--- Whether a list group is folded (keys: "ab:<group>", "f:<section>"); the
--- Features list keeps its groups' folds in the same memory.
HeroSheetLists.IsFolded = IsFolded
--- @type fun(key: string, folded: boolean)
HeroSheetLists.SetFolded = SetFolded

----------------------------------------------------------------------
--Reading the Hero.

--- @param ability ActivatedAbility
--- @return string
local function KeywordText(ability)
    local list = {}
    pcall(function()
        for kw, on in pairs(ability:try_get("keywords", {})) do
            if on then
                list[#list+1] = ActivatedAbility.CanonicalKeyword(kw)
            end
        end
    end)
    table.sort(list)
    return table.concat(list, ", ")
end

--The row tags for an ability the shared read did not list (a companion's, or
--a custom one sharing a name), worded as that read words the Hero's own: the
--action, then Signature or the cost.
--- @param ability ActivatedAbility
--- @param resourceName string
--- @return string actionTag
--- @return nil|string costTag
local function ActionTags(ability, resourceName)
    local resources = dmhub.GetTable(CharacterResource.tableName) or {}
    local actionName = nil
    pcall(function()
        local rid = ability:ActionResource()
        if rid ~= nil and resources[rid] ~= nil then
            actionName = resources[rid].name
        end
    end)
    local category = ability:try_get("categorization")
    local actionTag
    if category == "Trigger" then
        actionTag = "Triggered action"
    elseif actionName == nil or actionName == "" or actionName == "Free" then
        actionTag = "No action"
    else
        actionTag = string.upper(string.sub(actionName, 1, 1)) .. string.lower(string.sub(actionName, 2))
    end
    local costTag = nil
    pcall(function()
        if ability:has_key("resourceCost") and resources[ability.resourceCost] ~= nil then
            local cost = tonumber(ability:try_get("resourceNumber", 1)) or 1
            if cost > 0 then
                costTag = string.format("%d %s", cost, resourceName)
            end
        end
    end)
    if costTag == nil and category == "Signature Ability" then
        costTag = "Signature"
    end
    return actionTag, costTag
end

--- An ability's tags as the Abilities list words them; the Builder's (i)
--- cards head an ability with its action tag.
HeroSheetLists.ActionTags = ActionTags

--Which group an ability the shared read did not list goes in, grouped as
--that read groups: by the action, basic attacks as free strikes.
--- @param actionTag string
--- @param ability ActivatedAbility
--- @return string
local function GroupFor(actionTag, ability)
    if ability:try_get("categorization") == "Basic Attack" then
        return "freestrike"
    end
    local tag = string.lower(actionTag)
    if string.find(tag, "trigger", 1, true) then
        return "triggered"
    end
    if string.find(tag, "main action", 1, true) then
        return "main"
    end
    if string.find(tag, "maneuver", 1, true) then
        return "maneuver"
    end
    return "other"
end

--The groups made from the sheet's shared read (HeroSheetRefresh.Read), kept
--while that read is the same, so the block's signature and redraw share them.
--- @type {read: nil|table, groups: HeroListGroup[]}
local g_read = {read = nil, groups = {}}

--- The Hero's ability groups, in GROUPS order, empty ones included.
--- @param token CharacterToken
--- @return HeroListGroup[]
local function Read(token)
    local read = HeroSheetRefresh.Read(token)
    if read ~= nil and g_read.read == read then
        return g_read.groups
    end
    local hero = token.properties
    --- @type table<string, HeroListItem[]>
    local byId = {}
    local ownGuids = {}
    for _, group in ipairs((read ~= nil and read.abilities) or {}) do
        local items = {}
        for _, listed in ipairs(group.items) do
            local item = {
                name = listed.name,
                keywords = "",
                actionTag = listed.actionTag or "",
                --a free strike's row names the action only.
                costTag = cond(group.id == "freestrike", nil, listed.costTag),
                colorKey = "ms-action-triggered",
                custom = false,
                ability = listed.ability,
                trigger = listed.trigger,
            }
            if listed.ability ~= nil then
                local ability = listed.ability --[[@as ActivatedAbility]]
                item.keywords = KeywordText(ability)
                pcall(function() item.colorKey = ability:ActionColorKeyClass() end)
                pcall(function() item.custom = hero:IsActivatedAbilityInnate(ability) ~= false end)
                ownGuids[ability:try_get("guid", "")] = true
            end
            items[#items+1] = item
        end
        byId[group.id] = items
    end

    --Abilities the shared read leaves out that the sheet still lists:
    --Companion-keyword ones saved on the Hero (listed apart, to edit or delete),
    --and a custom ability sharing a name with another (the read keeps one per name).
    local companion = {}
    pcall(function()
        local resourceName = (read ~= nil and read.resource ~= nil and read.resource.name) or hero:GetHeroicResourceName()
        local all = hero:GetActivatedAbilities{bindCaster = true, characterSheet = true, excludeKeywords = {}}
        local customNames = {}
        for _, ability in ipairs(all) do
            if hero:IsActivatedAbilityInnate(ability) ~= false then
                customNames[ability.name] = true
            end
        end
        for _, ability in ipairs(all) do
            local guid = ability:try_get("guid", "")
            local isCompanion = ability:has_key("keywords") and ability:HasKeyword("Companion")
            local custom = hero:IsActivatedAbilityInnate(ability) ~= false
            local hidden = ability:try_get("hidden") == true or ability:try_get("categorization") == "Hidden"
            local sharesCustomName = customNames[ability.name] == true and not hidden
            if not ownGuids[guid] and (isCompanion or sharesCustomName) then
                ownGuids[guid] = true
                local actionTag, costTag = ActionTags(ability, resourceName)
                local item = {
                    name = ability.name,
                    keywords = KeywordText(ability),
                    actionTag = actionTag,
                    costTag = costTag,
                    colorKey = "ms-action-other",
                    custom = custom,
                    ability = ability,
                }
                pcall(function() item.colorKey = ability:ActionColorKeyClass() end)
                if isCompanion then
                    companion[#companion+1] = item
                else
                    local groupId = GroupFor(actionTag, ability)
                    local list = byId[groupId] or {}
                    byId[groupId] = list
                    list[#list+1] = item
                end
            end
        end
    end)
    table.sort(companion, function(left, right) return left.name < right.name end)
    byId.companion = companion

    local groups = {}
    for _, def in ipairs(GROUPS) do
        groups[#groups+1] = {id = def.id, items = byId[def.id] or {}}
    end
    g_read = {read = read, groups = groups}
    return groups
end

--What the abilities show, as a string: equal strings mean nothing to redraw.
--The action colours are written into the rows, so a colour scheme with a
--new background redraws them too.
--- @param token CharacterToken
--- @return string
local function Signature(token)
    local parts = {HeroSheetTheme.Palette().bg}
    for _, group in ipairs(Read(token)) do
        parts[#parts+1] = group.id
        for _, item in ipairs(group.items) do
            parts[#parts+1] = string.format("%s|%s|%s|%s|%s|%s", item.name, item.keywords, item.actionTag,
                tostring(item.costTag), item.colorKey, tostring(item.custom))
        end
    end
    return table.concat(parts, "\n")
end

----------------------------------------------------------------------
--The shared ability editors and the row menu's actions.

--Where the shared editors and dialogs open: the main dialog layer, above a
--sheet in either place (a maximized sheet sits at the bottom of that layer).
--- @param fallback Panel
--- @return Panel
local function DialogLayer(fallback)
    local hud = GameHud.instance
    if hud then
        local layer = hud:try_get("mainDialogPanel")
        if layer ~= nil and layer.valid then
            return layer
        end
    end
    return fallback.root
end

--A Companion-keyword ability added to a Hero is the companion's, so it is
--listed under Companion abilities, not with the Hero's own: say where.
--- @param ability ActivatedAbility
local function WarnIfCompanion(ability)
    if not ability:has_key("keywords") or not ability:HasKeyword("Companion") then
        return
    end
    local token = HeroSheet.Token()
    if token == nil or token.properties == nil then
        return
    end
    --some Heroes list companion abilities with their own (usecompanionabilities).
    local guid = ability:try_get("guid")
    for _, heroAbility in ipairs(token.properties:GetActivatedAbilities{}) do
        if heroAbility:try_get("guid") == guid then
            return
        end
    end
    HeroSheetWindow.ShowDialog{
        title = "Companion ability",
        width = 520,
        bodyHeight = 44,
        body = HeroSheetWindow.DialogText(string.format("%s has the Companion keyword, so it is listed under Companion abilities, where you can edit or delete it.", ability.name)),
        onDone = function() end,
    }
end

--The shared ability editor on a new ability: Create adds it to the Hero.
--- @param from Panel
local function NewAbility(from)
    if not HeroSheetWrite.CanWrite() then
        return
    end
    local ability = ActivatedAbility.Create{name = "New Ability"}
    local editor = ability:ShowEditActivatedAbilityDialog{
        add = function(element)
            HeroSheetWrite.Save{
                description = "New ability",
                execute = function(props)
                    props:AddInnateActivatedAbility(ability)
                end,
            }
            HeroSheet.Saved()
            WarnIfCompanion(ability)
        end,
    }
    DialogLayer(from):AddChild(editor)
end

--- The copied ability, if the clipboard holds one.
--- @return nil|ActivatedAbility
local function ClipboardAbility()
    local item = dmhub.GetInternalClipboard()
    if item ~= nil and item.typeName == "ActivatedAbility" then
        return item --[[@as ActivatedAbility]]
    end
    return nil
end

--Adds a copy of the copied ability. A pasted ability is a new one, so
--it and its behaviours get fresh guids: two abilities sharing a guid would
--edit and delete as one.
local function PasteAbility()
    local copied = ClipboardAbility()
    if copied == nil or not HeroSheetWrite.CanWrite() then
        return
    end
    local ability = DeepCopy(copied) --[[@as ActivatedAbility]]
    DeepReplaceGuids(ability)
    HeroSheetWrite.Save{
        description = "Paste ability",
        execute = function(props)
            props:AddInnateActivatedAbility(ability)
        end,
    }
    HeroSheet.Saved()
    WarnIfCompanion(ability)
end

--The shared ability editor on an ability saved on the Hero, through the editor
--bridge: the editor changes the Hero in place, and closing it saves that as
--one undo step. Its Delete asks first, with the row menu's words.
--- @param item HeroListItem
--- @param from Panel
local function EditAbility(item, from)
    local token = HeroSheet.Token()
    if token == nil or item.ability == nil then
        return
    end
    local stored = token.properties:IsActivatedAbilityInnate(item.ability)
    if not stored then
        return
    end
    --- @type HeroSheetBridgeArgs
    local args
    args = {
        description = "Edit ability",
        fields = {"innateActivatedAbilities"},
        open = function(props, done)
            local ability = props:IsActivatedAbilityInnate(item.ability)
            if not ability then
                done()
                return
            end
            local editor = ability:ShowEditActivatedAbilityDialog{
                close = function(element)
                    done()
                    HeroSheet.Saved()
                end,
                delete = function(element)
                    args.description = "Delete ability"
                    props:RemoveInnateActivatedAbility(ability)
                end,
                deleteConfirm = {
                    title = string.format("Delete %s?", ability.name),
                    message = "Removes the custom ability.",
                },
            }
            DialogLayer(from):AddChild(editor)
        end,
    }
    HeroSheetWrite.Bridge(args)
end

--Delete asks first; undo puts the ability back.
--- @param item HeroListItem
local function DeleteAbility(item)
    if item.ability == nil or not HeroSheetWrite.CanWrite() then
        return
    end
    local ability = item.ability --[[@as ActivatedAbility]]
    HeroSheetWindow.ShowDialog{
        title = string.format("Delete %s?", item.name),
        width = 520,
        bodyHeight = 22,
        body = HeroSheetWindow.DialogText("Removes the custom ability."),
        saveText = "Delete",
        onSave = function()
            HeroSheetWrite.Save{
                description = "Delete ability",
                execute = function(props)
                    props:RemoveInnateActivatedAbility(ability)
                end,
            }
            HeroSheet.Saved()
        end,
    }
end

--The ability's Customize dialog (a display overlay for this Hero; it saves
--itself).
--- @param item HeroListItem
--- @param from Panel
local function Customize(item, from)
    local token = HeroSheet.Token()
    if token == nil or item.ability == nil or not HeroSheetWrite.CanWrite() then
        return
    end
    local dialog = item.ability:ShowCustomisationDialog(token, from)
    if dialog ~= nil then
        DialogLayer(from):AddChild(dialog)
    end
end

--- @class HeroListMenuEntry
--- @field text string
--- @field hint nil|string muted at the right ("Display only")
--- @field danger nil|boolean a removal, in the danger colour
--- @field reason nil|string the entry is dimmed and says this on hover
--- @field click nil|fun()
--- @field submenu nil|(HeroListMenuEntry|string)[] entries shown beside this one on hover or click (a caret marks it)

--The row menu: a popover beside the row's "..." button. An entry with a
--submenu (such as Apply imbuement's item types) opens a second menu beside
--it while it is hovered.
--- @param anchor Panel
--- @param entries (HeroListMenuEntry|string)[] "-" is a separator
--- @param parent nil|{close: fun()} set for a submenu: picking in it closes its parent too
--- @param placement nil|{below: nil|boolean, alignRight: nil|boolean} where it opens (ShowPopup's below / alignRight); beside the anchor by default
--- @return nil|Panel frame
local function ShowMenu(anchor, entries, parent, placement)
    local frame
    local rows = {}
    local height = 12
    --the submenu open beside this menu, if any.
    --- @type nil|Panel
    local child = nil
    local function CloseChild()
        if child ~= nil then
            HeroSheetWindow.ClosePopup(child)
            child = nil
        end
    end
    local this = {close = function()
        HeroSheetWindow.ClosePopup(frame)
        if parent ~= nil then
            parent.close()
        end
    end}
    for _, entry in ipairs(entries) do
        if entry == "-" then
            rows[#rows+1] = gui.Panel{
                classes = {"heroSheetCardRule"},
                bgimage = "panels/square.png",
                width = "100%-8",
                height = 1,
                halign = "center",
                vmargin = 4,
            }
            height = height + 9
        else
            local menuEntry = entry --[[@as HeroListMenuEntry]]
            local enabled = menuEntry.reason == nil
            --opacity is not inherited: a dimmed entry dims its words too.
            local textClasses = {"heroSheetPopRowText", cond(enabled, nil, "heroSheetDisabled")}
            if menuEntry.danger then
                textClasses[#textClasses+1] = "heroSheetMenuDanger"
            end
            --- @type Panel[]
            local children = {
                gui.Label{
                    classes = textClasses,
                    text = menuEntry.text,
                    fontSize = 14,
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    valign = "center",
                    textWrap = false,
                    interactable = false,
                },
            }
            if menuEntry.hint ~= nil then
                children[#children+1] = gui.Label{
                    classes = {"heroSheetCardSub", cond(enabled, nil, "heroSheetDisabled")},
                    text = menuEntry.hint,
                    fontSize = 12,
                    width = "auto",
                    height = "auto",
                    halign = "right",
                    valign = "center",
                    textWrap = false,
                    interactable = false,
                }
            end
            if menuEntry.submenu ~= nil then
                children[#children+1] = gui.Panel{
                    classes = {"heroSheetFg"},
                    bgimage = "phosphor/caret-right-fill.png",
                    width = 12,
                    height = 12,
                    halign = "right",
                    valign = "center",
                    interactable = false,
                }
            end
            --- @param element Panel
            local function OpenChild(element)
                CloseChild()
                child = ShowMenu(element, menuEntry.submenu --[[@as (HeroListMenuEntry|string)[] ]], this)
            end
            rows[#rows+1] = gui.Panel{
                classes = {"heroSheetPopRow", cond(enabled, "hoverable", "heroSheetDisabled")},
                bgimage = "panels/square.png",
                cornerRadius = 6,
                width = "100%",
                height = 32,
                hpad = 10,
                borderBox = true,
                flow = "none",
                --hovering an entry opens its submenu, and closes another's.
                hover = function(element)
                    if not enabled then
                        return
                    end
                    if menuEntry.submenu ~= nil then
                        OpenChild(element)
                    else
                        CloseChild()
                    end
                end,
                linger = function(element)
                    if menuEntry.reason ~= nil then
                        gui.Tooltip(menuEntry.reason)(element)
                    end
                end,
                click = function(element)
                    if not enabled then
                        return
                    end
                    if menuEntry.submenu ~= nil then
                        OpenChild(element)
                        return
                    end
                    this.close()
                    if menuEntry.click ~= nil then
                        menuEntry.click()
                    end
                end,
                children = children,
            }
            height = height + 32
        end
    end
    frame = HeroSheetWindow.ShowPopup{
        width = 230,
        height = height,
        anchor = anchor,
        below = placement ~= nil and placement.below == true,
        alignRight = placement ~= nil and placement.alignRight == true,
        --a submenu takes no click-away layer of its own: that would cover its
        --parent, whose other entries must still take the hover.
        dismissOutside = parent == nil,
        onClose = CloseChild,
        content = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            vpad = 6,
            hpad = 6,
            borderBox = true,
            children = rows,
        },
    }
    return frame
end

--the sheet's other row menus (a follower's) are the same popover.
HeroSheetLists.ShowMenu = ShowMenu

--The menu for one ability: Copy and Share to chat; Edit mode adds
--Customize, then Edit and Delete for abilities saved on this Hero.
--- @param anchor Panel
--- @param item HeroListItem
local function AbilityMenu(anchor, item)
    local ability = item.ability
    if ability == nil then
        return
    end
    --- @type (HeroListMenuEntry|string)[]
    local entries = {}
    local function Copy()
        dmhub.CopyToInternalClipboard(ability)
        HeroSheetWindow.Toast(string.format("Copied %s.", item.name))
    end
    local function Share()
        local token = HeroSheet.Token()
        if token ~= nil then
            chat.ShareObjectInfo(nil, nil, {charid = token.charid, ability = ability})
        end
    end
    if HeroSheet.Editing() then
        entries[#entries+1] = {text = "Customize", hint = "Display only", click = function() Customize(item, anchor) end}
    end
    entries[#entries+1] = {text = "Copy", click = Copy}
    entries[#entries+1] = {text = "Share to chat", click = Share}
    if HeroSheet.Editing() then
        entries[#entries+1] = "-"
        if item.custom then
            entries[#entries+1] = {text = "Edit", click = function() EditAbility(item, anchor) end}
            entries[#entries+1] = {text = "Delete", danger = true, click = function() DeleteAbility(item) end}
        else
            entries[#entries+1] = {text = "Edit", hint = "Custom only", reason = "Only custom abilities can be edited. Customize changes how this one shows."}
            entries[#entries+1] = {text = "Delete", hint = "Custom only", danger = true, reason = "Only custom abilities can be deleted."}
        end
    end
    ShowMenu(anchor, entries)
end

----------------------------------------------------------------------
--The rows.

--The codex's own card for a row: the ability card, or a triggered action's
--card, on the sheet's card surface.
--- @param item {name: string, ability: nil|ActivatedAbility, trigger: nil|any}
--- @return Panel
local function AbilityCard(item)
    local token = HeroSheet.Token()
    local card = nil
    if item.ability ~= nil then
        pcall(function() card = CreateAbilityTooltip(item.ability, {token = token, width = CARD_WIDTH, bgcolor = "#00000000"}) end)
    elseif item.trigger ~= nil then
        pcall(function() card = item.trigger:Render{token = token, width = CARD_WIDTH} end)
    end
    if card == nil then
        card = gui.Label{
            classes = {"heroSheetCardStrong"},
            text = item.name,
            fontSize = 16,
            bold = true,
            width = "auto",
            height = "auto",
        }
    end
    return card
end

--- The codex's own card for an ability or a triggered action, as the
--- Abilities list shows it (the Features list's View ability uses it too).
HeroSheetLists.AbilityCard = AbilityCard

--- @class HeroListRow
--- @field panel Panel
--- @field fill fun(item: HeroListItem)
--- @field setEditing fun(editing: boolean)

--One ability row: name, keywords, the action in its Codex colour, then
--Signature or the cost, a Custom pill on abilities saved on this Hero, and
--the "..." menu, shown on hover and always in Edit mode. Hover shows the
--card after the wait; a click pins it. A row is made once and filled again
--when its ability changes; the pill and the "..." are made only when first
--needed, as most rows never show them.
--- @param compact boolean free strikes and standard actions: smaller, no keywords, no menu
--- @return HeroListRow
local function NewRow(compact)
    --a name too long for its row (a compact row two to a line) is cut with
    --an ellipsis and shows in full on a tooltip.
    local name = HeroSheetTheme.EllipsisLabel{
        classes = {"heroSheetCardStrong"},
        fontSize = cond(compact, 14.5, 16),
        bold = true,
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
    }
    --The keywords take the room the name and tags leave, worked out from the
    --texts when the row is filled. A width of "100% available" beside text
    --makes the engine lay the row out again every frame.
    local keywords = nil
    if not compact then
        keywords = HeroSheetTheme.EllipsisLabel{
            classes = {"heroSheetCardSub"},
            fontSize = 12,
            width = "auto",
            height = "auto",
            lmargin = 10,
            halign = "left",
            valign = "center",
        }
    end
    --the tags are one label (markup colours the action), so a row stays cheap.
    local tags = gui.Label{
        classes = {"heroSheetCardLab"},
        fontSize = 12.5,
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "center",
        textWrap = false,
        interactable = false,
    }
    --- @type nil|Panel
    local pill = nil
    --- @type nil|Panel
    local keb = nil
    local editing = false
    local row

    --- @return boolean
    local function HasMenu()
        local item = row.data.item
        return not compact and item ~= nil and item.ability ~= nil and HeroSheetWrite.CanWrite()
    end

    --the "..." stays the row's last child, so a pill made later goes before it.
    local function EnsureKeb()
        if keb ~= nil or not HasMenu() then
            return
        end
        keb = gui.Panel{
            classes = {"heroSheetKeb", "hoverable", cond(editing, "heroSheetEditOn", nil)},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 5,
            width = HeroSheetWindow.TargetSize(24),
            height = HeroSheetWindow.TargetSize(24),
            lmargin = 6,
            rmargin = -6,
            halign = "right",
            valign = "center",
            click = function(element)
                local item = row.data.item
                if item ~= nil then
                    AbilityMenu(element, item)
                end
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
        row:AddChild(keb)
    end

    local function EnsurePill()
        if pill ~= nil then
            return
        end
        pill = gui.Panel{
            classes = {"heroSheetCustomPill"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 9,
            width = "auto",
            height = 18,
            hpad = 7,
            borderBox = true,
            lmargin = 6,
            rmargin = 8,
            halign = "right",
            valign = "center",
            interactable = false,
            gui.Label{
                classes = {"heroSheetCardStrong"},
                text = "CUSTOM",
                fontSize = 11,
                bold = true,
                width = "auto",
                height = "auto",
                valign = "center",
                textWrap = false,
            },
        }
        --before the tags, so a custom row's action lines up with the others.
        row:AddChild(pill)
        tags:SetAsLastSibling()
        if keb ~= nil then
            keb:SetAsLastSibling()
        end
    end

    --- @type Panel[]
    local children = {name}
    if keywords ~= nil then
        children[#children+1] = keywords
    end
    children[#children+1] = tags

    local args = {
        classes = {"heroSheetListRow", "hoverable"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = cond(compact, 7, 8),
        width = "100%",
        height = cond(compact, COMPACT_ROW_HEIGHT, ROW_HEIGHT),
        hpad = cond(compact, 10, 12),
        borderBox = true,
        flow = "horizontal",
        data = {item = nil},
        hover = function(element)
            EnsureKeb()
        end,
        children = children,
    }
    --a pinned card lights its row's edge until it closes.
    row = gui.Panel(HeroSheetTheme.HoverCard(args, function(pinned, close, element)
        local item = element.data.item
        local frame = HeroSheetTheme.CardFrame(AbilityCard(item), pinned, close, item ~= nil and item.ability ~= nil)
        if not pinned then
            --beside the row, not over the card column.
            frame.selfStyle.halign = "right"
            frame.selfStyle.valign = "center"
            return frame
        end
        element:SetClass("heroSheetRowPinned", true)
        return gui.Panel{
            width = "auto",
            height = "auto",
            destroy = function()
                if element.valid then
                    element:SetClass("heroSheetRowPinned", false)
                end
            end,
            frame,
        }
    end, nil, {halign = "right", valign = "center"}))

    --- @param item HeroListItem
    local function Fill(item)
        row.data.item = item
        name.text = item.name
        local plain = item.actionTag .. cond(item.costTag ~= nil, "  .  " .. tostring(item.costTag), "")
        local tagRoom = HeroSheetTheme.TextWidth(plain, 12.5) + cond(item.custom, CUSTOM_PILL_ROOM, 0)
        --the name takes what the tags and the "..." leave (a percent here is
        --of the row inside its padding), with a gap before the tags.
        name.selfStyle.maxWidth = string.format("100%%-%d", math.floor(tagRoom + cond(compact, 12, 38)))
        if keywords ~= nil then
            keywords.text = item.keywords
            --the room the name, the tags, the pill and the "..." can take,
            --estimated from their texts (the row's padding included).
            local used = HeroSheetTheme.TextWidth(item.name, 16) + tagRoom + ROW_FIXED_ROOM
            keywords.selfStyle.maxWidth = string.format("100%%-%d", math.floor(used))
        end
        --the Hero's own actions in their Codex colour (lifted to read as
        --text); free strikes and standard actions stay quiet.
        local action = item.actionTag
        if not compact then
            local key = ActivatedAbility.actionColorKey[item.colorKey] or ActivatedAbility.actionColorKey["ms-action-none"]
            action = string.format("<color=%s>%s</color>", HeroSheetTheme.ActionTextColor(key), item.actionTag)
        end
        if item.costTag ~= nil then
            local palette = HeroSheetTheme.Palette()
            --two spaces each side give about a 6-unit gap round the dot.
            tags.text = string.format("%s  <color=%s>\u{00B7}</color>  <color=%s><b>%s</b></color>", action, palette.cardSub, palette.cardLabel, item.costTag)
        else
            tags.text = action
        end
        if item.custom then
            EnsurePill()
        end
        if pill ~= nil then
            pill:SetClass("collapsed", not item.custom)
        end
        if editing then
            EnsureKeb()
        end
        --a triggered action's card has no menu: nothing to copy or customize.
        if keb ~= nil then
            keb:SetClass("heroSheetKebOff", not HasMenu())
        end
    end

    --- @param on boolean
    local function SetEditing(on)
        editing = on
        if on then
            EnsureKeb()
        end
        if keb ~= nil then
            keb:SetClass("heroSheetEditOn", on)
        end
    end

    return {panel = row, fill = Fill, setEditing = SetEditing}
end

----------------------------------------------------------------------
--The groups.

--- @class HeroListGroupPanel
--- @field panel Panel
--- @field refresh fun(items: HeroListItem[])
--- @field setEditing fun(editing: boolean)

--A foldable group: a header with its name and count (and a note for
--Standard actions) over its rows. Rows are made as needed and kept, and a
--folded group makes none until it is first opened; a group with nothing to
--show is hidden.
--- @param def table a GROUPS entry
--- @param first boolean the list's first group sits closer to the header
--- @param grew fun() the list got taller (an opened group): it may need to scroll
--- @return HeroListGroupPanel
local function NewGroup(def, first, grew)
    local key = "ab:" .. def.id
    local folded = IsFolded(key)
    local compact = def.compact == true

    --- @type HeroListRow[]
    local rows = {}
    --compact rows go two to a line; each line holds two row slots.
    --- @type Panel[]
    local lines = {}
    --- @type HeroListItem[]
    local shown = {}
    local editing = false

    local body = gui.Panel{
        classes = {cond(folded, "collapsed", nil)},
        width = "100%",
        height = "auto",
        flow = "vertical",
    }
    local caret = gui.Panel{
        classes = {"heroSheetMutedIcon"},
        bgimage = "phosphor/caret-down-fill.png",
        width = 10,
        height = 10,
        rmargin = 8,
        halign = "left",
        valign = "center",
        rotate = cond(folded, 90, 0),
        interactable = false,
    }
    local count = gui.Label{
        classes = {"heroSheetCardSub"},
        fontSize = 13,
        width = "auto",
        height = "auto",
        lmargin = 8,
        halign = "left",
        valign = "center",
        textWrap = false,
        interactable = false,
    }

    --The row for the i-th item, made the first time it is needed.
    --- @param i integer
    --- @return HeroListRow
    local function RowAt(i)
        local row = rows[i]
        if row ~= nil then
            return row
        end
        row = NewRow(compact)
        rows[i] = row
        if compact then
            local lineIndex = math.floor((i - 1) / 2) + 1
            local line = lines[lineIndex]
            if line == nil then
                line = gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    tmargin = ROW_GAP,
                }
                lines[lineIndex] = line
                body:AddChild(line)
            end
            row.panel.selfStyle.width = "50%-3"
            if i % 2 == 0 then
                row.panel.selfStyle.lmargin = 6
            end
            row.panel.selfStyle.halign = "left"
            line:AddChild(row.panel)
        else
            row.panel.selfStyle.tmargin = ROW_GAP
            body:AddChild(row.panel)
        end
        row.setEditing(editing)
        return row
    end

    --Fills the rows from the items shown; a folded group waits until opened.
    local function Fill()
        if folded then
            return
        end
        for i, item in ipairs(shown) do
            local row = RowAt(i)
            row.panel:SetClass("collapsed", false)
            row.fill(item)
        end
        --rows past the end are hidden, kept for a later longer list.
        for i = #shown + 1, #rows do
            rows[i].panel:SetClass("collapsed", true)
            rows[i].panel.data.item = nil
        end
        for i, line in ipairs(lines) do
            line:SetClass("collapsed", (i - 1) * 2 >= #shown)
        end
    end

    local headerChildren = {
        caret,
        gui.Label{
            classes = {"heroSheetCardLabel"},
            text = string.upper(def.name),
            fontSize = 12,
            bold = true,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            textWrap = false,
            interactable = false,
        },
        count,
    }
    if def.note ~= nil then
        headerChildren[#headerChildren+1] = gui.Label{
            classes = {"heroSheetCardSub"},
            text = def.note,
            fontSize = 12,
            italics = true,
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
            textWrap = false,
            interactable = false,
        }
    end
    local header = gui.Panel{
        classes = {"hoverable"},
        bgimage = "panels/square.png",
        bgcolor = "clear",
        width = "100%",
        height = HeroSheetWindow.TargetSize(24),
        flow = "horizontal",
        click = function(element)
            folded = not folded
            SetFolded(key, folded)
            body:SetClass("collapsed", folded)
            caret.selfStyle.rotate = cond(folded, 90, 0)
            if not folded then
                Fill()
                grew()
            end
        end,
        children = headerChildren,
    }
    local panel = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = cond(first, 4, 14),
        header,
        body,
    }

    --- @param items HeroListItem[]
    local function Refresh(items)
        shown = items
        panel:SetClass("collapsed", #items == 0)
        count.text = tostring(#items)
        Fill()
    end

    --- @param on boolean
    local function SetEditing(on)
        editing = on
        for _, row in ipairs(rows) do
            row.setEditing(on)
        end
    end

    return {panel = panel, refresh = Refresh, setEditing = SetEditing}
end

----------------------------------------------------------------------
--The frame.

--A heading tab: its name in capitals; the open one is in the strong colour
--over a warm underline. Also returns a muted count label, hidden until used.
--- @param text string
--- @param click fun()
--- @return Panel tab
--- @return Panel countLabel
local function HeadTab(text, click)
    local countLabel = gui.Label{
        classes = {"heroSheetCardSub", "collapsed"},
        fontSize = 13,
        width = "auto",
        height = "auto",
        lmargin = 6,
        halign = "left",
        valign = "center",
        textWrap = false,
        interactable = false,
    }
    local tab = gui.Panel{
        classes = {"heroSheetListTabFrame", "hoverable"},
        bgimage = "panels/square.png",
        border = {x1 = 0, y1 = 2, x2 = 0, y2 = 0},
        width = "auto",
        height = 26,
        rmargin = 16,
        flow = "horizontal",
        halign = "left",
        valign = "bottom",
        click = function(element)
            click()
        end,
        gui.Label{
            classes = {"heroSheetListTab"},
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
        countLabel,
    }
    return tab, countLabel
end

--- @param tab Panel
--- @param on boolean
local function SetTabOn(tab, on)
    tab:SetClassTree("selected", on)
end

--The warm rule under a list's heading.
--- @return Panel
local function HeadRule()
    return gui.Panel{
        classes = {"heroSheetDialogRule"},
        bgimage = "panels/square.png",
        width = "100%",
        height = 1,
        tmargin = 9,
    }
end

--- @class HeroSheetListsArgs
--- @field statsPane nil|Panel Narrow's Stats pane (the sheet moves the band into it)
--- @field gearPane nil|Panel Narrow's Gear pane (the kit card and Treasures)

--- The lists under the stats band on the Character tab. A HeroSheetRefresh
--- block: the abilities redraw when what they show changes. The tier and
--- Edit mode restyle the frame (classes), never rebuild it. At Narrow
--- its tab row also offers the sheet's Stats and Gear panes, which it shows
--- in its own plate.
--- @param args nil|HeroSheetListsArgs
--- @return Panel
function HeroSheetLists.Create(args)
    local statsPane = args ~= nil and args.statsPane or nil
    local gearPane = args ~= nil and args.gearPane or nil
    --Narrow's Stats and Gear tabs need both panes from the sheet; without
    --them the lists stay on their own panes.
    local hasPanes = statsPane ~= nil
    --Medium's open pane: "abilities", "features" or "notes" (and Narrow's
    --"stats" and "gear"); Wide's Features column shows "features" or "notes"
    --(the same choice carries across tiers).
    local state = HeroSheet.State()
    local pane = "abilities"
    local featuresTab = "features"
    --a pane picked by hand (or by the search's way in) is kept when the
    --sheet narrows; otherwise Narrow opens on Stats, its first tab.
    local paneChosen = false
    if state ~= nil and state.pane == "Features" then
        pane = "features"
        paneChosen = true
    end
    local tier = HeroSheet.Tier()
    if tier == "narrow" and not paneChosen and hasPanes then
        pane = "stats"
    end
    --the headings' line: tall enough for the features' chips beside their tabs,
    --so both columns' rules line up.
    local headH = math.max(26, HeroSheetWindow.TargetSize(28))

    --- @type fun()
    local FitScroll

    --- @type HeroListGroupPanel[]
    local groups = {}
    local groupPanels = {}
    for i, def in ipairs(GROUPS) do
        local group = NewGroup(def, i == 1, function() FitScroll() end)
        groups[i] = group
        groupPanels[i] = group.panel
    end

    local abilityList = gui.Panel{
        width = "100%-10",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        bmargin = 14,
        children = groupPanels,
    }
    --scrolls once its content is taller: panels made inside a scrolling
    --panel lay out far more slowly, so the rows are made first.
    --its height is what the heading, the Edit bar and the rule leave (Arrange):
    --never "100% available", which the engine restyles every frame.
    local abilityBody = gui.Panel{
        width = "100%",
        height = "100%-42",
        flow = "vertical",
        tmargin = 6,
        abilityList,
    }
    FitScroll = function()
        HeroSheetWindow.AfterLayout(function()
            if abilityBody.valid and not abilityBody.vscroll and abilityList.renderedHeight > abilityBody.renderedHeight + 0.5 then
                abilityBody.vscroll = true
                --the engine then skips cards well outside the view, so the tab shows and
                --scrolls faster. Set only once the scroll view exists: before that the engine errors.
                abilityBody.hideObjectsOutOfScroll = true
            end
        end)
    end

    local abilityCount = gui.Label{
        classes = {"heroSheetCardSub"},
        fontSize = 13,
        width = "auto",
        height = "auto",
        lmargin = 10,
        halign = "left",
        valign = "center",
        textWrap = false,
    }

    local pasteButton = HeroSheetFeatures.BarButton("phosphor/copy.png", "Paste ability", function(element)
        PasteAbility()
    end, function()
        local copied = ClipboardAbility()
        if copied == nil then
            return "Nothing to paste. Copy an ability from its menu first."
        end
        local token = HeroSheet.Token()
        return string.format("Adds a copy of %s to %s.", copied.name, token ~= nil and token.name or "this Hero")
    end)
    --Paste is dimmed while nothing it can paste is copied.
    local function SyncPaste()
        --opacity is not inherited: the icon and words dim with the frame.
        pasteButton:SetClassTree("heroSheetDisabled", ClipboardAbility() == nil)
    end
    --Edit mode's row of add buttons under the heading. The clipboard
    --can change anywhere in the app, so it is checked while the bar shows (a
    --collapsed panel does not think).
    local abilityBar = gui.Panel{
        classes = {cond(HeroSheet.Editing(), nil, "collapsed")},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        tmargin = 8,
        thinkTime = 0.5,
        think = function(element)
            SyncPaste()
        end,
        HeroSheetFeatures.BarButton("phosphor/plus-bold.png", "New ability", function(element)
            NewAbility(element)
        end),
        pasteButton,
    }

    local abilityTitleRow = gui.Panel{
        width = "100%",
        height = headH,
        flow = "horizontal",
        gui.Label{
            classes = {"heroSheetCardStrong"},
            text = "ABILITIES",
            fontSize = 16,
            bold = true,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            textWrap = false,
        },
        abilityCount,
    }
    local abilityRule = HeadRule()
    local abilityColumn = gui.Panel{
        width = "48%-10",
        height = "100%",
        flow = "vertical",
        halign = "left",
        abilityTitleRow,
        abilityBar,
        abilityRule,
        abilityBody,
    }

    --The Features column: its own Features / Notes tabs at Wide.
    local features = HeroSheetFeatures.Create()
    local notes = HeroSheetNotes.Create()
    --the features' chips and search on their own line, when they do not
    --fit beside the tabs (always at Medium).
    local filterRow = gui.Panel{
        width = "100%",
        height = HeroSheetWindow.TargetSize(28),
        flow = "horizontal",
        tmargin = 8,
    }
    --whether the filters fit beside the Features / Notes tabs at Wide, and
    --where they are now ("inline" or "row").
    local filtersFit = true
    local filtersAt = "none"
    local featureTabs = {}
    local mediumTabs = {}
    local mediumCount
    local featureColumn
    --- @type Panel
    local featureRule
    --- @type Panel
    local featureBody
    --- @type Panel
    local columnsRow

    --The heights above the ability list: the heading and its rule at Wide,
    --the Edit bar while editing, the list's own gap.
    local function SizeAbilityBody()
        local medium = tier ~= "wide"
        local used = 6
        if not medium then
            used = used + headH + 10
        end
        if not abilityBar:HasClass("collapsed") then
            used = used + HeroSheetWindow.TargetSize(26) + 8
        end
        abilityBody.selfStyle.height = string.format("100%%-%d", used)
    end

    --Shows the panes for the tier and the open pane: restyles, never rebuilds.
    local function Arrange()
        local medium = tier ~= "wide"
        --A view-only Hero's notes are private to its owner, so the Notes tab is hidden.
        local notesShown = HeroSheetWrite.CanWrite()
        featureTabs.notes:SetClass("collapsed", not notesShown)
        mediumTabs.notes:SetClass("collapsed", not notesShown)
        if not notesShown then
            if featuresTab == "notes" then
                featuresTab = "features"
            end
            if pane == "notes" then
                pane = "features"
            end
        end
        local narrow = tier == "narrow" and hasPanes
        --Stats and Gear are Narrow's: a wider sheet has them elsewhere.
        if not narrow and (pane == "stats" or pane == "gear") then
            pane = "abilities"
        end
        local listPane = pane == "abilities" or pane == "features" or pane == "notes"
        columnsRow:SetClass("collapsed", not listPane)
        for id, holder in pairs({stats = statsPane, gear = gearPane}) do
            holder:SetClass("collapsed", not (narrow and pane == id))
            holder.selfStyle.height = "100%-36"
            mediumTabs[id]:SetClass("collapsed", not narrow)
            SetTabOn(mediumTabs[id], pane == id)
        end
        abilityTitleRow:SetClass("collapsed", medium)
        abilityRule:SetClass("collapsed", medium)
        featureRule:SetClass("collapsed", medium)
        --the columns take what Medium's tab row leaves (its tabs and rule).
        columnsRow.selfStyle.height = cond(medium, "100%-36", "100%")
        --the open tab's Edit bar shows in Edit mode (Features or Notes).
        local shownTab = featuresTab
        if medium and (pane == "features" or pane == "notes") then
            shownTab = pane
        end
        local barShown = HeroSheet.Editing() and (shownTab == "features" or shownTab == "notes")
        features.bar:SetClass("collapsed", not (barShown and shownTab == "features"))
        notes.bar:SetClass("collapsed", not (barShown and shownTab == "notes"))
        local above = cond(medium, 0, headH + 10) + cond(barShown, HeroSheetWindow.TargetSize(26) + 8, 0)
        featureBody.selfStyle.height = cond(above > 0, string.format("100%%-%d", above), "100%")
        SizeAbilityBody()
        abilityColumn.selfStyle.width = cond(medium, "100%", "48%-10")
        featureColumn.selfStyle.width = cond(medium, "100%", "52%-10")
        featureColumn.selfStyle.lmargin = cond(medium, 0, 20)
        abilityColumn:SetClass("collapsed", medium and pane ~= "abilities")
        featureColumn:SetClass("collapsed", medium and pane ~= "features" and pane ~= "notes")
        mediumTabs.row:SetClass("collapsed", not medium)
        featureTabs.row:SetClass("collapsed", medium)
        local shown = featuresTab
        if medium and (pane == "features" or pane == "notes") then
            shown = pane
        end
        local onFeatures = shown == "features"
        features.body:SetClass("collapsed", not onFeatures)
        notes.body:SetClass("collapsed", onFeatures)
        --the filters beside the tabs when they fit there (Wide), else on
        --their own line over the list; only the Features tab has them.
        local inline = not medium and filtersFit
        local at = cond(inline, "inline", "row")
        if at ~= filtersAt then
            filtersAt = at
            --a panel added elsewhere without leaving first stays listed in both.
            if features.filters.parent ~= nil then
                features.filters:Unparent()
            end
            if inline then
                featureTabs.row:AddChild(features.filters)
            else
                filterRow:AddChild(features.filters)
            end
        end
        features.filters:SetClass("collapsed", not onFeatures)
        filterRow:SetClass("collapsed", inline or not onFeatures)
        --the list's own 6-unit gap, and the filters' line when it shows.
        features.body.selfStyle.height = cond(inline or not onFeatures, "100%-6", string.format("100%%-%d", HeroSheetWindow.TargetSize(28) + 8 + 6))
        SetTabOn(featureTabs.features, shown == "features")
        SetTabOn(featureTabs.notes, shown == "notes")
        SetTabOn(mediumTabs.abilities, pane == "abilities")
        SetTabOn(mediumTabs.features, pane == "features")
        SetTabOn(mediumTabs.notes, pane == "notes")
        --a pane hidden while the Hero changed is drawn before the frame shows it.
        HeroSheetRefresh.CatchUpShown()
        FitScroll()
        features.fit()
        notes.fit()
    end

    --Measures whether the filters fit beside the tabs at Wide (after layout:
    --they are as wide as their chips and field), and places them again when
    --that changed.
    local function MeasureFilters()
        HeroSheetWindow.AfterLayout(function()
            if mod.unloaded or not featureColumn.valid or tier ~= "wide" then
                return
            end
            local perUnit = featureTabs.row.renderedHeight / headH
            local width = features.filters.renderedWidth
            if perUnit <= 0 or width <= 0 then
                return
            end
            --each tab keeps 16 units to its right; 12 more keep the chips off the tabs.
            local need = featureTabs.features.renderedWidth + featureTabs.notes.renderedWidth + 44 * perUnit + width
            local fits = need <= featureColumn.renderedWidth
            if fits ~= filtersFit then
                filtersFit = fits
                Arrange()
            end
        end)
    end

    local function ShowFeaturesTab(id)
        featuresTab = id
        if pane ~= "abilities" then
            pane = id
        end
        Arrange()
    end
    local function ShowPane(id)
        pane = id
        paneChosen = true
        if id == "features" or id == "notes" then
            featuresTab = id
        end
        Arrange()
        --the sheet fits its parts again (a Narrow pane scrolls once it overflows).
        local fit = HeroSheetRefresh.afterRedraw
        if fit ~= nil then
            fit()
        end
    end

    featureTabs.features = HeadTab("Features", function() ShowFeaturesTab("features") end)
    featureTabs.notes = HeadTab("Notes", function() ShowFeaturesTab("notes") end)
    featureTabs.row = gui.Panel{
        width = "100%",
        height = headH,
        flow = "horizontal",
        featureTabs.features,
        featureTabs.notes,
    }
    featureRule = HeadRule()
    --what the tabs and the rule leave (Arrange).
    featureBody = gui.Panel{
        width = "100%",
        height = string.format("100%%-%d", headH + 10),
        flow = "vertical",
        filterRow,
        features.body,
        notes.body,
    }
    featureColumn = gui.Panel{
        width = "52%-10",
        height = "100%",
        flow = "vertical",
        lmargin = 20,
        featureTabs.row,
        features.bar,
        notes.bar,
        featureRule,
        featureBody,
    }

    mediumTabs.stats = HeadTab("Stats", function() ShowPane("stats") end)
    mediumTabs.abilities, mediumCount = HeadTab("Abilities", function() ShowPane("abilities") end)
    mediumCount:SetClass("collapsed", false)
    mediumTabs.features = HeadTab("Features", function() ShowPane("features") end)
    mediumTabs.gear = HeadTab("Gear", function() ShowPane("gear") end)
    mediumTabs.notes = HeadTab("Notes", function() ShowPane("notes") end)
    --Narrow's own tabs (Stats first) show only when the sheet gave its panes.
    if not hasPanes then
        statsPane = gui.Panel{classes = {"collapsed"}, width = 1, height = 1}
        gearPane = gui.Panel{classes = {"collapsed"}, width = 1, height = 1}
    end
    mediumTabs.row = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Panel{
            width = "100%",
            height = 26,
            flow = "horizontal",
            mediumTabs.stats,
            mediumTabs.abilities,
            mediumTabs.features,
            mediumTabs.gear,
            mediumTabs.notes,
        },
        HeadRule(),
    }

    --the two columns, under Medium's tab row (its height set in Arrange).
    columnsRow = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "horizontal",
        abilityColumn,
        featureColumn,
    }

    --Edit mode as the features were last painted for: every abilities
    --refresh sets it again, and the features repaint only when it changes.
    --- @type nil|boolean
    local featuresEditing = nil
    --whether the Hero could be written when last arranged: another Hero
    --can be view only, which hides Notes.
    local arrangedWrite = HeroSheetWrite.CanWrite()
    --- @param editing boolean
    local function SetEditing(editing)
        if HeroSheetWrite.CanWrite() ~= arrangedWrite then
            arrangedWrite = HeroSheetWrite.CanWrite()
            Arrange()
        end
        editing = editing and HeroSheetWrite.CanWrite()
        abilityBar:SetClass("collapsed", not editing)
        if editing ~= featuresEditing then
            featuresEditing = editing
            features.setEditing(editing)
            notes.setEditing(editing)
            Arrange()
        end
        SizeAbilityBody()
        if editing then
            SyncPaste()
        end
        for _, group in ipairs(groups) do
            group.setEditing(editing)
        end
    end

    local spec = {
        name = "abilities",
        signature = Signature,
        refresh = function(panel, token)
            local total = 0
            for i, group in ipairs(Read(token)) do
                groups[i].refresh(group.items)
                if group.id ~= "standard" then
                    total = total + #group.items
                end
            end
            abilityCount.text = tostring(total)
            mediumCount.text = tostring(total)
            SetEditing(HeroSheet.Editing())
            FitScroll()
        end,
    }

    local root = HeroSheetRefresh.Block({
        classes = {"heroSheetPlate", "heroSheetBlock"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 12,
        width = "100%",
        --the sheet sets the height to fit its window.
        height = HeroSheetLists.MIN_HEIGHT,
        tmargin = HeroSheetLists.TOP_MARGIN,
        tpad = 12,
        hpad = 14,
        borderBox = true,
        flow = "vertical",
        heroSheetTier = function(element, newTier)
            --a sheet narrowing opens on Stats unless a pane was picked.
            if newTier == "narrow" and tier ~= "narrow" and not paneChosen and hasPanes then
                pane = "stats"
            end
            tier = newTier
            Arrange()
            MeasureFilters()
        end,
        heroSheetLayout = function(element)
            MeasureFilters()
            features.fit()
            notes.fit()
        end,
        heroSheetEdit = function(element, editing)
            SetEditing(editing)
        end,
        --the sheet opened on Features (the search's way in, "Features" as the
        --tab): show that pane, filtered by what was searched, once.
        heroSheetTab = function(element, tabid)
            local sheetState = HeroSheet.State()
            if tabid == "CharacterSheet" and sheetState ~= nil and sheetState.pane == "Features" then
                sheetState.pane = nil
                ShowPane("features")
                features.route(sheetState.featuresFilter)
                sheetState.featuresFilter = nil
            end
        end,
        --another Hero starts at the top of their list.
        heroSheetHero = function(element)
            if abilityBody.vscroll then
                abilityBody.vscrollPosition = 1
            end
        end,
        mediumTabs.row,
        columnsRow,
        statsPane,
        gearPane,
    }, spec)
    Arrange()
    MeasureFilters()
    return root
end

local mod = dmhub.GetModLoading()

--The Hero sheet's write layer. The sheet lives outside the engine's sheet
--harness, which diffs the Hero every frame and uploads whatever changed. Out
--here nothing uploads by itself, so every change the sheet makes goes
--through this file, under these rules:
--  * No direct writes: change a Hero only inside HeroSheetWrite.Save (one
--    token:ModifyProperties call: one undo step, diffs only).
--  * Previews and unsaved text stay in the UI, not in token.properties:
--    ModifyProperties uploads the difference from the Hero as it was when the
--    save began, so a value already written in place uploads nothing.
--  * Typing saves after a pause (SaveSoon); drags and sliders preview locally
--    and Save on release; everything pending is saved at once on close, on
--    switching Hero and when an input loses focus (Flush).
--  * Read the live Hero inside the save: a reconnect can hand the token a new
--    properties object, so execute gets token.properties looked up then.
--  * View only never writes.
--  * On close, a development check compares the Hero against its state after
--    the last save or remote update and logs anything never sent.
--The classic sheet's editors that edit in place (ability editor,
--Customize, feature editor, stat popup, immunities) open through Bridge.

HeroSheetWrite = rawget(_G, "HeroSheetWrite") or {}

--How long typing waits for a pause before it saves.
HeroSheetWrite.TYPING_PAUSE = 0.6

--- @class HeroSheetSaveArgs
--- @field description string what the undo list shows, e.g. "Set Victories"
--- @field execute fun(props: creature, token: CharacterToken) changes the live Hero
--- @field undoable nil|boolean default true
--- @field combine nil|boolean upload with this frame's other changes as one transaction
--- @field charid nil|string the Hero the change was made for: refused if the sheet has switched to another

--pending typed saves by key: {args, due}
--- @type table<string, {args: HeroSheetSaveArgs, due: number}>
local g_pending = {}

--the Hero's JSON after the last save or remote update, for the close check.
--- @type nil|string
local g_baseline = nil
--- @type nil|string
local g_baselineFor = nil

--The open Hero's token, looked up now (never kept between calls).
--- @return nil|CharacterToken
local function LiveToken()
    local state = HeroSheet.State()
    if state == nil then
        return nil
    end
    return dmhub.GetCharacterById(state.tokenid) or dmhub.GetTokenById(state.tokenid)
end

--- True when the open Hero may be written: open, and not view only.
--- @return boolean
function HeroSheetWrite.CanWrite()
    local state = HeroSheet.State()
    return state ~= nil and not state.viewOnly and LiveToken() ~= nil
end

--- Remember the Hero as it is now as "everything sent": after a save, a
--- remote update, or opening the sheet.
function HeroSheetWrite.Rebaseline()
    local token = LiveToken()
    if token == nil or token.properties == nil then
        g_baseline = nil
        g_baselineFor = nil
        return
    end
    g_baseline = dmhub.ToJson(token.properties)
    g_baselineFor = token.charid
end

--- Save a change to the open Hero now, as one undo step. Returns false when
--- nothing was written (no Hero, or view only).
--- @param args HeroSheetSaveArgs
--- @return boolean
function HeroSheetWrite.Save(args)
    if not HeroSheetWrite.CanWrite() then
        --a view-only Hero refuses the change: the error sound says so.
        audio.FireSoundEvent("UI.Error_Generic")
        return false
    end
    local token = LiveToken() --[[@as CharacterToken]]
    local charid = token.charid
    if args.charid ~= nil and args.charid ~= charid then
        --an editor or a delayed save from before a Hero switch: never write
        --one Hero's change onto another.
        print(string.format("HEROSHEET:: refused \"%s\": made for %s, the sheet now shows %s", args.description, args.charid, charid))
        audio.FireSoundEvent("UI.Error_Generic")
        return false
    end
    token:ModifyProperties{
        description = args.description,
        undoable = args.undoable ~= false,
        combine = args.combine == true,
        execute = function()
            --the token looked up again: execute runs on the live Hero.
            local live = dmhub.GetCharacterById(charid) or token
            args.execute(live.properties, live)
        end,
    }
    --the sheet's shared read is from before this save; the cloud's copy of
    --the save, when it comes back, needs no second read.
    HeroSheetRefresh.Stale()
    HeroSheetRefresh.ExpectEcho()
    HeroSheetWrite.Rebaseline()
    return true
end

--- @class HeroSheetAtomicArgs
--- @field description string
--- @field others (CharacterToken|LuaPartyInfo)[] the other holders the change edits, such as the party stash
--- @field execute fun(hero: creature, token: CharacterToken) edits the Hero and the others' properties in place
--- @field refusedText nil|string the toast when another player changed the same items first

--- Save a change that moves things between the open Hero and other holders
--- (the party stash, another token) as one write that can't race another
--- player's: if someone changed the same items first, the server refuses it,
--- nothing moves, the sheet shows the server's values again and a toast says
--- so. Undo is refused the same way once the items have moved since.
--- Returns false when nothing was sent (no Hero, or view only).
--- @param args HeroSheetAtomicArgs
--- @return boolean
function HeroSheetWrite.SaveAtomic(args)
    if not HeroSheetWrite.CanWrite() then
        audio.FireSoundEvent("UI.Error_Generic")
        return false
    end
    local token = LiveToken() --[[@as CharacterToken]]
    ---@type (CharacterToken|LuaPartyInfo)[]
    local holders = {token}
    for _, other in ipairs(args.others) do
        holders[#holders+1] = other
    end
    dmhub.AtomicChange{
        holders = holders,
        description = args.description,
        execute = function()
            args.execute(token.properties, token)
        end,
        onFail = function(error, step)
            if mod.unloaded then
                return
            end
            print(string.format("HEROSHEET:: \"%s\" %s refused: %s", args.description, step, error))
            local text = args.refusedText or "Someone else changed those items first. Nothing moved."
            if step == "undo" then
                text = "Can't undo: those items have changed since."
            elseif step == "redo" then
                text = "Can't redo: those items have changed since."
            end
            HeroSheetWindow.Toast(text)
            audio.FireSoundEvent("UI.Error_Generic")
            HeroSheetRefresh.Stale()
        end,
    }
    HeroSheetRefresh.Stale()
    HeroSheetRefresh.ExpectEcho()
    HeroSheetWrite.Rebaseline()
    return true
end

--- Save after a pause in typing. A newer call with the same key replaces the
--- older one, so only the last value saves. Flush saves it at once.
--- @param key string one per field, e.g. "notes:<section id>"
--- @param args HeroSheetSaveArgs
function HeroSheetWrite.SaveSoon(key, args)
    if not HeroSheetWrite.CanWrite() then
        return
    end
    local due = dmhub.Time() + HeroSheetWrite.TYPING_PAUSE
    g_pending[key] = {args = args, due = due}
    dmhub.Schedule(HeroSheetWrite.TYPING_PAUSE, function()
        if mod.unloaded then
            return
        end
        local entry = g_pending[key]
        if entry ~= nil and entry.due <= dmhub.Time() + 0.001 then
            g_pending[key] = nil
            HeroSheetWrite.Save(entry.args)
        end
    end)
end

--- Save pending typed changes now: every one, or only the one for key (an
--- input losing focus). Called on close, on switching Hero and on focus loss.
--- @param key nil|string
function HeroSheetWrite.Flush(key)
    if key ~= nil then
        local entry = g_pending[key]
        g_pending[key] = nil
        if entry ~= nil then
            HeroSheetWrite.Save(entry.args)
        end
        return
    end
    local entries = g_pending
    g_pending = {}
    for _, entry in pairs(entries) do
        HeroSheetWrite.Save(entry.args)
    end
end

--- True while a typed change waits to save.
--- @return boolean
function HeroSheetWrite.HasPending()
    return next(g_pending) ~= nil
end

--The top-level fields where two JSON snapshots of a Hero differ, or nil when
--either snapshot cannot be decoded.
--- @param before string
--- @param after string
--- @return nil|string[]
local function ChangedFields(before, after)
    --FromJson answers {success = ..., result = <the value>}.
    local beforeHero = dmhub.FromJson(before)
    local afterHero = dmhub.FromJson(after)
    beforeHero = type(beforeHero) == "table" and beforeHero.result or nil
    afterHero = type(afterHero) == "table" and afterHero.result or nil
    if type(beforeHero) ~= "table" or type(afterHero) ~= "table" then
        return nil
    end
    local changed = {}
    --the decoded Hero is a typed object, which errors on reading a field it
    --does not have, so fields of one side are read from the other with pcall.
    local function Field(tbl, key)
        local value = nil
        pcall(function() value = tbl[key] end)
        return value
    end
    local seen = {}
    for key, value in pairs(afterHero) do
        seen[key] = true
        if dmhub.ToJson(value) ~= dmhub.ToJson(Field(beforeHero, key)) then
            changed[#changed+1] = tostring(key)
        end
    end
    for key, _ in pairs(beforeHero) do
        if not seen[key] then
            changed[#changed+1] = tostring(key)
        end
    end
    table.sort(changed)
    return changed
end

--- The development check, run when the sheet closes or switches Hero: logs
--- any change to the Hero that was never sent (a write made outside Save,
--- which the classic sheet's harness would catch and upload). Logging
--- only; one compare.
function HeroSheetWrite.CheckUnsent()
    local token = LiveToken()
    if token == nil or token.properties == nil or g_baseline == nil or g_baselineFor ~= token.charid then
        return
    end
    local now = dmhub.ToJson(token.properties)
    if now ~= g_baseline then
        local fields = ChangedFields(g_baseline, now)
        --The first open of a Hero in a session rebuilds its properties, which
        --writes the same fields in another order: no field differs, so no log.
        if fields ~= nil and #fields == 0 then
            return
        end
        local named = fields ~= nil and table.concat(fields, ", ") or "(fields unknown)"
        print(string.format("HEROSHEET:: UNSENT CHANGES on %s (%s): %s -- a write outside HeroSheetWrite.Save; it is lost on reload.",
            tostring(token.name), token.charid, named))
    end
end

--- Run before the sheet closes or leaves a Hero: save what is pending, then
--- check for changes never sent.
function HeroSheetWrite.OnLeave()
    HeroSheetWrite.Flush()
    --a development aid: it must never stop the sheet closing.
    local ok, err = pcall(HeroSheetWrite.CheckUnsent)
    if not ok then
        print("HEROSHEET:: close check failed: " .. tostring(err))
    end
    g_baseline = nil
    g_baselineFor = nil
end

--- @class HeroSheetBridgeArgs
--- @field description string the undo step's text, e.g. "Edit ability"
--- @field fields string[] the Hero's top-level fields the editor may change
--- @field open fun(props: creature, done: fun()) opens the classic sheet's editor on the Hero; it calls done() when the editor closes

--- The editor bridge for the classic sheet's editors, which edit the Hero in
--- place and rely on the harness to upload: the named fields are copied on
--- open; on close the copies go back and the edited values are re-applied
--- inside one Save, on the live Hero. One upload, one undo step.
--- @param args HeroSheetBridgeArgs
--- @return boolean false when the Hero cannot be edited (view only)
function HeroSheetWrite.Bridge(args)
    if not HeroSheetWrite.CanWrite() then
        return false
    end
    local token = LiveToken() --[[@as CharacterToken]]
    local props = token.properties
    local snapshot = {}
    for _, field in ipairs(args.fields) do
        snapshot[field] = dmhub.DeepCopy(props:try_get(field))
    end
    local finished = false
    args.open(props, function()
        if finished then
            return
        end
        finished = true
        local edited = {}
        for _, field in ipairs(args.fields) do
            edited[field] = dmhub.DeepCopy(props:try_get(field))
            props[field] = snapshot[field]
        end
        HeroSheetWrite.Save{
            description = args.description,
            charid = token.charid,
            execute = function(live)
                for _, field in ipairs(args.fields) do
                    live[field] = edited[field]
                end
            end,
        }
    end)
    return true
end

----------------------------------------------------------------------
--Equipping treasure. No cap of three: carrying more than three leveled
--treasures is a rule the sheet informs about, not one it enforces. Leveled
--treasures and artifacts go in the leveled slots, trinkets in the trinket
--slots (creature.EquipmentSlots); a full set of slots stops an equip.

--- The free equipment slot one of an item would go in, or nil and why.
--- @param hero creature
--- @param itemid string
--- @return nil|string slot
--- @return nil|string reason "none" (none left to equip), "noslot" (not equippable here) or "full"
function HeroSheetWrite.EquipSlot(hero, itemid)
    local item = (dmhub.GetTable("tbl_Gear") or {})[itemid]
    if item == nil then
        return nil, "noslot"
    end
    --a second click before the sheet redraws would otherwise equip a copy
    --the Hero does not have.
    if (hero:GetItemQuantity(itemid) or 0) < 1 then
        return nil, "none"
    end
    local slotType = nil
    if EquipmentCategory.IsLeveledTreasure(item) or EquipmentCategory.IsArtifact(item) then
        slotType = "leveled"
    elseif EquipmentCategory.IsTrinket(item) then
        slotType = "trinket"
    end
    if slotType == nil then
        return nil, "noslot"
    end
    local equip = hero:Equipment()
    local i = 1
    while creature.EquipmentSlots[slotType .. i] ~= nil do
        if equip[slotType .. i] == nil then
            return slotType .. i, nil
        end
        i = i + 1
    end
    return nil, "full"
end

--- Equip one of an item from the open Hero's inventory (one undo step).
--- @param itemid string
--- @return boolean ok
--- @return nil|string reason see EquipSlot
function HeroSheetWrite.Equip(itemid)
    local token = LiveToken()
    if token == nil or not HeroSheetWrite.CanWrite() then
        return false, "none"
    end
    local slot, reason = HeroSheetWrite.EquipSlot(token.properties, itemid)
    if slot == nil then
        --every slot of its kind is taken: say so, as the error sound alone
        --does not tell the player why.
        if reason == "full" then
            local item = (dmhub.GetTable("tbl_Gear") or {})[itemid]
            HeroSheetWindow.Toast(item ~= nil and EquipmentCategory.IsTrinket(item)
                and "All 10 trinket slots are full." or "All 5 leveled treasure slots are full.")
        end
        return false, reason
    end
    HeroSheetWrite.Save{
        description = "Equip treasure",
        execute = function(hero)
            --the slot found again on the live Hero.
            local at = HeroSheetWrite.EquipSlot(hero, itemid)
            if at ~= nil then
                hero:SetItemQuantity(itemid, hero:GetItemQuantity(itemid) - 1)
                hero:Equipment()[at] = itemid
            end
        end,
    }
    return true, nil
end

--- Unequip the item in an equipment slot back into the open Hero's
--- inventory (one undo step).
--- @param slot string
--- @return boolean
function HeroSheetWrite.Unequip(slot)
    return HeroSheetWrite.Save{
        description = "Unequip treasure",
        execute = function(hero)
            if hero:Equipment()[slot] ~= nil then
                hero:Unequip(slot)
            end
        end,
    }
end

--- An appearance change: token fields outside properties (portrait,
--- frame, size...) upload through UploadAppearance with a snapshot, so they
--- undo too. mutate changes the live token.
--- @param mutate fun(token: CharacterToken)
--- @return boolean
function HeroSheetWrite.SaveAppearance(mutate)
    if not HeroSheetWrite.CanWrite() then
        return false
    end
    local token = LiveToken() --[[@as CharacterToken]]
    local snapshot = token:PrepareUploadAppearance()
    mutate(token)
    token:UploadAppearance(snapshot)
    --the map's token redraws only when marked: our own upload does not mark it.
    token:RefreshAppearanceLocally()
    return true
end

--- Start a previewed change to the open Hero's look (a drag, a slider): the
--- caller sets token fields locally while it previews, then passes the
--- snapshot to CommitAppearance once, on release. Nil when view only.
--- @return nil|CharacterToken token
--- @return nil|string snapshot
function HeroSheetWrite.PreviewAppearance()
    if not HeroSheetWrite.CanWrite() then
        return nil, nil
    end
    local token = LiveToken() --[[@as CharacterToken]]
    return token, token:PrepareUploadAppearance()
end

--- Upload a previewed look change as one undo step (see PreviewAppearance).
--- @param snapshot string
function HeroSheetWrite.CommitAppearance(snapshot)
    local token = LiveToken()
    if token ~= nil then
        token:UploadAppearance(snapshot)
        token:RefreshAppearanceLocally()
    end
end

--- Who controls the open Hero (the Director's choice): a player ("player",
--- their userid), a party ("party", its id) or the Director ("director").
--- As with the classic sheet's controller dropdown, the token fields are set
--- and the engine sends them; there is no undo step.
--- @param kind "player"|"party"|"director"
--- @param id nil|string
--- @return boolean
function HeroSheetWrite.SetController(kind, id)
    if not HeroSheetWrite.CanWrite() or not dmhub.isDM then
        return false
    end
    local token = LiveToken() --[[@as CharacterToken]]
    if kind == "director" then
        token.ownerId = nil
    elseif kind == "party" then
        --partyId makes the token party-owned (ownerId becomes "PARTY").
        token.partyId = id
    else
        token.ownerId = id
    end
    return true
end

----------------------------------------------------------------------
--Edit mode's stat editors, on the model of the classic sheet's
--modification popup (Draw Steel UI/PopupOverrideAttribute.lua): a custom change to a
--stat is a feature on the Hero (source "Custom") whose one modifier carries
--the value and points back at the feature through its sourceguid.

--- A custom change's number: resource modifiers keep it in num, the rest in value.
--- @param modifier CharacterModifier
--- @return number
function HeroSheetWrite.CustomChangeValue(modifier)
    if modifier.behavior == "resource" then
        return tonumber(modifier:try_get("num")) or 0
    end
    return tonumber(modifier:try_get("value")) or 0
end

--- @param modifier CharacterModifier
--- @param value number
local function SetChangeValue(modifier, value)
    --the number's fields are not declared on the type.
    local fields = modifier --[[@as table]]
    if modifier.behavior == "resource" then
        fields.num = value
    else
        fields.value = value
    end
end

--The feature with this guid on a Hero, and its place in the feature list.
--- @param props creature
--- @param guid string
--- @return nil|CharacterFeature feature
--- @return nil|number index
local function FindFeature(props, guid)
    for i, feature in ipairs(props:try_get("characterFeatures", {})) do
        if feature.guid == guid then
            return feature, i
        end
    end
    return nil, nil
end

--- Add a custom change to a stat, made from the stat's standard
--- "<stat> Modification" feature as the classic sheet's popup makes it.
--- @param featureName string the standard feature, e.g. "Might Modification"
--- @param name string the source the change shows, e.g. "Homebrew ring"
--- @param value number
--- @param description string the undo step
--- @return boolean false when nothing was written (no such feature, view only)
function HeroSheetWrite.AddCustomChange(featureName, name, value, description)
    local template = MCDMImporter.GetStandardFeature(featureName)
    if template == nil then
        return false
    end
    local feature = DeepCopy(template)
    feature.guid = dmhub.GenerateGuid()
    feature.name = name
    feature.source = "Custom"
    local modifier = feature.modifiers[1]
    modifier.sourceguid = feature.guid
    modifier.name = name
    modifier.source = "Custom"
    SetChangeValue(modifier, value)
    return HeroSheetWrite.Save{
        description = description,
        execute = function(props)
            local features = props:get_or_add("characterFeatures", {})
            features[#features+1] = feature
        end,
    }
end

--- Rename a custom change (fields.name) or change its number (fields.value).
--- @param guid string the custom change's feature guid
--- @param fields {name: nil|string, value: nil|number}
--- @param description string the undo step
--- @return boolean
function HeroSheetWrite.EditCustomChange(guid, fields, description)
    return HeroSheetWrite.Save{
        description = description,
        execute = function(props)
            local feature = FindFeature(props, guid)
            if feature == nil then
                return
            end
            if fields.name ~= nil then
                feature.name = fields.name
                feature.modifiers[1].name = fields.name
            end
            if fields.value ~= nil then
                SetChangeValue(feature.modifiers[1], fields.value)
            end
        end,
    }
end

--- Remove a custom change (or a movement type given by hand).
--- @param guid string the feature's guid
--- @param description string the undo step
--- @return boolean
function HeroSheetWrite.RemoveCustomChange(guid, description)
    return HeroSheetWrite.Save{
        description = description,
        execute = function(props)
            local _, index = FindFeature(props, guid)
            if index ~= nil then
                table.remove(props:get_or_add("characterFeatures", {}), index)
            end
        end,
    }
end

--- Give the Hero a movement type by hand, as the classic Speed popup does: a
--- custom feature whose modifier sets the type. RemoveCustomChange takes it away.
--- @param movementType string "fly", "climb"...
--- @param name string the type's name, "Fly"
--- @return boolean
function HeroSheetWrite.AddCustomMovement(movementType, name)
    local modifier = CharacterModifier.new{
        behavior = "attribute",
        attribute = movementType,
        operation = "set",
        value = "1",
        name = string.format("Custom %s", name),
        source = "Custom",
    }
    local feature = CharacterFeature.Create{
        name = string.format("Custom %s", name),
        source = "Custom",
        modifiers = {modifier},
    }
    modifier.sourceguid = feature.guid
    return HeroSheetWrite.Save{
        description = string.format("Add custom %s movement", name),
        execute = function(props)
            local features = props:get_or_add("characterFeatures", {})
            features[#features+1] = feature
        end,
    }
end

--- Set the Hero's size by hand (the classic sheet's size override), or "none" to follow
--- the ancestry again.
--- @param sizeid string one of creature.sizes, or "none"
--- @return boolean
function HeroSheetWrite.SetSizeOverride(sizeid)
    local token = LiveToken()
    local ok = HeroSheetWrite.Save{
        description = "Change creature size",
        execute = function(props)
            if sizeid == "none" then
                --no override: the field goes, as on a Hero that never had one.
                local fields = props --[[@as table]]
                fields.creatureSizeOverride = nil
            else
                props:SetSizeOverride(sizeid)
            end
        end,
    }
    --the token on the map takes its new footprint, as the classic popup does.
    if ok and token ~= nil then
        game.Refresh{tokens = {token.charid}}
    end
    return ok
end

--- Which hand-added immunity or weakness an editor row shows: its place in
--- the Hero's resistance list, and its damage type and dr when it was read.
--- @class HeroSheetResistanceRef
--- @field index number
--- @field damageType string
--- @field dr number

--The hand-added entry a row showed, found on the live Hero: at its place if
--it is unchanged there, else the first entry that matches it.
--- @param props creature
--- @param ref HeroSheetResistanceRef
--- @return nil|ResistanceEntry
local function FindResistance(props, ref)
    local list = props:GetResistances()
    local function Same(candidate)
        return candidate:try_get("damageType") == ref.damageType and candidate:try_get("dr", 0) == ref.dr
    end
    local entry = list[ref.index]
    if entry ~= nil and Same(entry) then
        return entry
    end
    for _, candidate in ipairs(list) do
        if Same(candidate) then
            return candidate
        end
    end
    return nil
end

--- Add an immunity (dr above 0) or a weakness (dr below 0) by hand, as
--- the classic sheet's immunities editor does.
--- @param damageType string a damage type's name in lower case, or "all"
--- @param dr number
--- @return boolean
function HeroSheetWrite.AddResistance(damageType, dr)
    return HeroSheetWrite.Save{
        description = cond(dr < 0, "Add weakness", "Add immunity"),
        execute = function(props)
            local list = props:GetResistances()
            list[#list+1] = ResistanceEntry.new{
                apply = "Damage Reduction",
                damageType = damageType,
                dr = dr,
            }
            props:SetResistances(list)
        end,
    }
end

--- Change a hand-added immunity or weakness: its damage type, or its dr
--- (the sign says which it is).
--- @param ref HeroSheetResistanceRef
--- @param fields {damageType: nil|string, dr: nil|number}
--- @return boolean
function HeroSheetWrite.EditResistance(ref, fields)
    local dr = fields.dr or ref.dr
    return HeroSheetWrite.Save{
        description = cond(dr < 0, "Change weakness", "Change immunity"),
        execute = function(props)
            local entry = FindResistance(props, ref)
            if entry == nil then
                return
            end
            if fields.damageType ~= nil then
                entry.damageType = fields.damageType
            end
            if fields.dr ~= nil then
                entry.dr = fields.dr
            end
        end,
    }
end

--- Remove a hand-added immunity or weakness.
--- @param ref HeroSheetResistanceRef
--- @return boolean
function HeroSheetWrite.RemoveResistance(ref)
    return HeroSheetWrite.Save{
        description = cond(ref.dr < 0, "Remove weakness", "Remove immunity"),
        execute = function(props)
            local entry = FindResistance(props, ref)
            if entry ~= nil then
                props:DeleteResistance(entry)
            end
        end,
    }
end

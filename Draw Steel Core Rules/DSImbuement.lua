--[[
    Imbuement management
]]

--- @class DSImbuement
--- @field imbueTargetType string The equipment type this imbuement applies to: "armor", "implement", or "weapon".
--- @field imbueLevel number Imbuement tier level (1, 5, or 9 correspond to kit tiers).
--- @field imbuePrereq nil|string Id of a prerequisite imbuement that must already be applied.
--- @field imbueReplacesPrereq boolean If true, applying this imbuement removes the prerequisite's features from the target item.
--- @field features table[] Features/modifiers applied to the target item when imbued.
--- Represents an imbuement: a magical enhancement that can be applied to a mundane item.
DSImbuement = RegisterGameType("DSImbuement")

DSImbuement.ArmorGuids = {
    [1] = "8670dc44-3c60-4c40-9e23-ebbbe378fea2",
    [5] = "5e404a72-9492-4d84-b5d0-bf4e4653e94c",
    [9] = "f27d7287-7ce2-49e8-a5f4-0c35c8899199",
}
DSImbuement.ImplementGuids = {
    [1] = "d05c3df7-756e-40af-bd63-d69b4bfac4b8",
    [5] = "c070e277-c31b-45b1-8c8c-d2338a953195",
    [9] = "0937e1d1-094e-4576-95d7-d987f16b6943",
}
DSImbuement.WeaponGuids = {
    [1] = "ceb20ee5-1a3f-4c9f-8f17-648554caceeb",
    [5] = "afed5ebd-ac56-47fe-9707-3628d4cfa442",
    [9] = "60cdc48d-3ffc-4922-b3f9-a9afbbc2d1db",
}

DSImbuement.imbueReplacesPrereq = false

--- Create a unique mundane item to be imbued
--- @param itemType "armor"|"implement"|"weapon"
--- @return equipment|nil
function DSImbuement.CreateMundaneItem(itemType)

    local iconIds = {
        armor = "02302b4b-d942-41b8-a4d5-8a39b6426824",
        implement = "cc913329-17fb-46c0-9a66-25e9bafbd445",
        weapon = "925b4c62-0173-4853-af63-d5936c04985b"
    }
    if iconIds[itemType] == nil then return nil end

    local item = equipment.new{
        id = dmhub.GenerateGuid(),
        unique = true,
        imbueTarget = itemType,
        name = "Mundane " .. itemType,
        type = "Gear",
        category = "Gear",
        equipmentCategory = EquipmentCategory.LeveledTreasureId,
        description = "A mundane " .. itemType .. " suitable for imbuing.",
        weight = 1,
        iconid = iconIds[itemType],
        implementation = 0,
        hidden = true,
    }

    dmhub.SetAndUploadTableItem(equipment.tableName, item)

    return item
end

--- Remove features contributed by a specific imbuement from targetItem,
--- and clean up the imbuements tracking table entry.
--- @param targetItem equipment
--- @param imbueId string
--- @param imbuements table
local function _removeImbuementFromItem(targetItem, imbueId, imbuements)
    local imbueObj = dmhub.GetTable(equipment.tableName)[imbueId]
    if imbueObj then
        for _,oldFeature in ipairs(imbueObj:try_get("features", {})) do
            for i,itemFeature in ipairs(targetItem:try_get("features", {})) do
                if itemFeature.guid == oldFeature.guid then
                    table.remove(targetItem.features, i)
                    break
                end
            end
        end
    end
    imbuements[imbueId] = nil
    local byLevel = imbuements.byLevel or {}
    for level, id in pairs(byLevel) do
        if id == imbueId then
            byLevel[level] = nil
            break
        end
    end
end

--- Determine whether the imbuement can be applied to the target
--- @param imbueItem equipment
--- @param targetItem equipment
--- @return boolean
function DSImbuement.CanImbue(imbueItem, targetItem)
    if imbueItem == nil or targetItem == nil then
        return false
    end
    if targetItem:try_get("imbueTarget", "absent-target") ~= imbueItem:try_get("imbueTargetType", "absent-imbue") then
        return false
    end
    local prereq = imbueItem:try_get("imbuePrereq")
    if prereq == nil then return true end
    local imbuements = targetItem:get_or_add("imbuements", {})
    return imbuements[prereq] == true
end

--- Add the core damage bonus by level to a weapon imbuement
--- @param imbueItem equipment
--- @return nil
function DSImbuement.AddDamageToWeapon(imbueItem)
    local itemLevel = imbueItem:try_get("imbueLevel", 1)
    local damageByLevel = { [1] = 1, [5] = 2, [9] = 3 }
    local damage = damageByLevel[itemLevel] or damageByLevel[1]
    local sourceGuid = DSImbuement.WeaponGuids[itemLevel]
    if sourceGuid == nil then return end
    for _,existing in ipairs(imbueItem:try_get("features", {})) do
        if existing.guid == sourceGuid then
            return
        end
    end
    local f = CharacterFeature.new{
        addText = "Add Magical Property",
        description = "",
        guid = sourceGuid,
        source = "Item",
        itemAttached = true,
        modifiers = {},
        name = "Imbued Weapon",
    }
    f.modifiers[#f.modifiers+1] = CharacterModifier.new{
        activationAfterRoll = false,
        activationCondition = "1",
        displayCondition = "Ability.Has Rolled Damage",
        behavior = "power",
        damageModifier = damage,
        description = "A weapon imbued with an enhancement grants you special benefits while it is wielded. Additionally, when a weapon receives its 1st-level enhancement, it grants your weapon abilities that deal rolled damage a +1 damage bonus. A 5th-level enhancement increases the damage bonus to +2, and a 9th-level enhancement increases it to +3.",
        guid = dmhub.GenerateGuid(),
        keywords = {
            Weapon = true,
        },
        modtype = "none",
        name = "Imbued Weapon",
        rollType = "ability_power_roll",
        source = "Item",
        sourceguid = sourceGuid,
    }
    imbueItem.features[#imbueItem.features+1] = f
end

--- Add the core damage bonus by level to an implement imbuement
--- @param imbueItem equipment
--- @return nil
function DSImbuement.AddDamageToImplement(imbueItem)
    local itemLevel = imbueItem:try_get("imbueLevel", 1)
    local damageByLevel = { [1] = 1, [5] = 2, [9] = 3 }
    local damage = damageByLevel[itemLevel] or damageByLevel[1]
    local sourceGuid = DSImbuement.ImplementGuids[itemLevel]
    if sourceGuid == nil then return end
    for _,existing in ipairs(imbueItem:try_get("features", {})) do
        if existing.guid == sourceGuid then
            return
        end
    end
    local f = CharacterFeature.new{
        addText = "Add Magical Property",
        description = "",
        guid = sourceGuid,
        source = "Item",
        itemAttached = true,
        modifiers = {},
        name = "Imbued Implement",
    }
    f.modifiers[#f.modifiers+1] = CharacterModifier.new{
        activationAfterRoll = false,
        activationCondition = "1",
        displayCondition = "Ability.Has Rolled Damage",
        behavior = "power",
        damageModifier = damage,
        description = "An implement imbued with an enhancement grants you special benefits while it is wielded. Additionally, when an implement receives its 1st-level enhancement, it grants your magic or psionic abilities that deal rolled damage a +1 damage bonus. A 5th-level enhancement increases the bonus to +2, and a 9th-level enhancement increases it to +3. Censors, conduits, elementalists, nulls, talents, and troubadours benefit from using implements more than the other classes in this book.",
        filterCondition = '',
        guid = dmhub.GenerateGuid(),
        keywords = {Magic = true, Psionic = true},
        matchAnyKeywords = true,
        modtype = "none",
        name = "Imbued Implement",
        rollType = "ability_power_roll",
        source = "Item",
        sourceguid = sourceGuid,
    }
    imbueItem.features[#imbueItem.features+1] = f
end

--- Add the core stamina bonus by level to an armor imbuement
--- @param imbueItem equipment
--- @return nil
function DSImbuement.AddStaminaToArmor(imbueItem)
    local itemLevel = imbueItem:try_get("imbueLevel", 1)
    local staminaByLevel = { [1] = 6, [5] = 12, [9] = 21 }
    local stamina = staminaByLevel[itemLevel] or staminaByLevel[1]
    local sourceGuid = DSImbuement.ArmorGuids[itemLevel]
    if sourceGuid == nil then return end
    for _,existing in ipairs(imbueItem:try_get("features", {})) do
        if existing.guid == sourceGuid then
            return
        end
    end
    local f = CharacterFeature.new{
        addText = "Add Magical Property",
        itemAttached = true,
        description = "",
        name = "Imbued Armor",
        guid = sourceGuid,
        source = "Item",
        modifiers = {},
    }
    f.modifiers[#f.modifiers+1] = CharacterModifier.new{
        value = stamina,
        sourceguid = sourceGuid,
        source = "Item",
        name = "Imbued Armor",
        description = "",
        behavior = "attribute",
        guid = dmhub.GenerateGuid(),
        attribute = "hitpoints"
    }
    imbueItem.features[#imbueItem.features+1] = f
end

--- Imbue an item
--- @param imbueItem equipment
--- @param targetItem equipment
--- @return equipment|nil
--- @return string message
function DSImbuement.ImbueItem(imbueItem, targetItem)
    if imbueItem == nil or targetItem == nil then
        return nil, "Imbuement and item are required."
    end
    if targetItem:try_get("unique", false) ~= true then
        return nil, "Target item for imbuement must be a unique item."
    end
    if targetItem:try_get("imbueTarget", "absent-target") ~= imbueItem:try_get("imbueTargetType", "absent-imbue") then
        return nil, "Imbuement type does not match item type."
    end

    local imbuements = targetItem:get_or_add("imbuements", {})
    imbuements.byLevel = imbuements.byLevel or {}

    -- If the imbuement has a prereq, validate its presence
    local prereq = imbueItem:try_get("imbuePrereq")
    if prereq and prereq ~= "none" then
        if imbuements[prereq] == nil then
            return nil, "Target item does not meet imbuement's prerequisites."
        end
    end

    -- Determine if we're overwriting an imbuement (one per level 1, 5, 9)
    -- and remove its features if we are
    local imbueLevel = imbueItem:try_get("imbueLevel", 1)
    local imbuedAtLevel = imbuements.byLevel[imbueLevel]
    if imbuedAtLevel ~= nil then
        imbuements[imbuedAtLevel] = nil
        -- TODO: Remove if we decide we're not merging features
        local oldImbue = dmhub.GetTable(equipment.tableName)[imbuedAtLevel]
        if oldImbue then
            for _,oldFeature in ipairs(oldImbue.features) do
                for i,itemFeature in ipairs(targetItem.features) do
                    if itemFeature.guid == oldFeature.guid then
                        table.remove(targetItem.features, i)
                        break
                    end
                end
            end
        end
    end

    -- If this imbuement replaces its prereq, recursively remove
    -- the prereq and any imbuements it also replaced.
    if imbueItem:try_get("imbueReplacesPrereq", false) and prereq and prereq ~= "none" then
        local function removeChain(chainId)
            if chainId == nil or chainId == "none" then return end
            if imbuements[chainId] ~= true then return end
            local chainObj = dmhub.GetTable(equipment.tableName)[chainId]
            if chainObj and chainObj:try_get("imbueReplacesPrereq", false) then
                removeChain(chainObj:try_get("imbuePrereq"))
            end
            _removeImbuementFromItem(targetItem, chainId, imbuements)
        end
        removeChain(prereq)
    end

    -- Strip any lower-tier core feature (identified by the target-type guid
    -- table) from the target, then add the tier-appropriate core feature to
    -- the imbueItem so it gets copied over in the features loop below.
    local targetType = imbueItem:try_get("imbueTargetType")
    local coreGuidTable = ({
        armor = DSImbuement.ArmorGuids,
        implement = DSImbuement.ImplementGuids,
        weapon = DSImbuement.WeaponGuids,
    })[targetType]
    if coreGuidTable then
        local targetFeatures = targetItem:try_get("features", {})
        for lowerLevel, lowerGuid in pairs(coreGuidTable) do
            if lowerLevel < imbueLevel then
                for i = #targetFeatures, 1, -1 do
                    if targetFeatures[i].guid == lowerGuid then
                        table.remove(targetFeatures, i)
                    end
                end
            end
        end
    end

    if targetType == "armor" then
        DSImbuement.AddStaminaToArmor(imbueItem)
    elseif targetType == "implement" then
        DSImbuement.AddDamageToImplement(imbueItem)
    elseif targetType == "weapon" then
        DSImbuement.AddDamageToWeapon(imbueItem)
    end

    -- Apply the imbuement's features
    -- TODO: Remove if we decide we're not merging features
    local targetFeatures = targetItem:try_get("features", {})
    for _,feature in ipairs(imbueItem:try_get("features", {})) do
        targetFeatures[#targetFeatures+1] = feature
    end
    targetItem.features = targetFeatures

    if targetItem.name:sub(1, 6) ~= "Imbued" then
        targetItem.name = "Imbued " .. targetItem.name
    end

    imbuements.byLevel[imbueLevel] = imbueItem.id
    imbuements[imbueItem.id] = true
    targetItem.imbuements = imbuements

    return targetItem, "Success"
end
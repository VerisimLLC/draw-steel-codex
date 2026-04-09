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

function DSImbuement.AddStaminaToArmor(imbueItem)
    local itemLevel = imbueItem:try_get("imbueLevel", 1)
    local staminaByLevel = { [1] = 6, [5] = 12, [9] = 21 }
    local stamina = staminaByLevel[itemLevel] or staminaByLevel[1]
    local sourceGuid = dmhub.GenerateGuid()
    local f = CharacterFeature.new{
        addText = "Add Magical Property",
        itemAttached = true,
        description = "",
        name = "Item Feature",
        guid = sourceGuid,
        source = "Item",
        modifiers = {},
    }
    f.modifiers[#f.modifiers+1] = CharacterModifier.new{
        value = stamina,
        sourceguid = sourceGuid,
        source = "Item",
        name = "itemFeature",
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

    -- Add stamina bonus when imbuing armor
    if imbueItem:try_get("imbueTargetType") == "armor" then
        DSImbuement.AddStaminaToArmor(imbueItem)
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
local mod = dmhub.GetModLoading()

--Grant Treasure: lets a hero pick one treasure from the gear table that matches
--a category / echelon / keyword filter, then claim it into their inventory.
--Used by complication benefits like "a 1st-echelon trinket of your choice".
--
--The pick and the claim live on the creature under treasureGrants, keyed by
--this modifier's guid, so both the character builder and the character sheet
--can report "Claimed" afterwards and never hand the treasure out twice.
--
--Delivery modes: "claim" shows a Claim button that adds the item for good;
--"manifest" only records the pick, and a Manifest Treasure ability behavior
--(defined at the bottom of this file) equips and removes the item when its
--trigger fires. The modifier's treasureId pairs it with those behaviors.

CharacterModifier.RegisterType("granttreasure", "Grant Treasure")

local CATEGORY_OPTIONS = {
    { id = "trinket", text = "Trinket" },
    { id = "leveled", text = "Leveled Treasure" },
    { id = "consumable", text = "Consumable" },
    { id = "artifact", text = "Artifact" },
    { id = "any", text = "Any Treasure" },
}

local ECHELON_OPTIONS = {
    { id = "0", text = "Any Echelon" },
    { id = "1", text = "1st Echelon" },
    { id = "2", text = "2nd Echelon" },
    { id = "3", text = "3rd Echelon" },
    { id = "4", text = "4th Echelon" },
}

local DELIVERY_OPTIONS = {
    { id = "claim", text = "Claim button adds it to the inventory" },
    { id = "manifest", text = "Manifest Treasure behaviors equip and remove it" },
}

local ECHELON_NAMES = { [1] = "1st-echelon", [2] = "2nd-echelon", [3] = "3rd-echelon", [4] = "4th-echelon" }
local CATEGORY_NAMES = { trinket = "trinket", leveled = "leveled treasure", consumable = "consumable", artifact = "artifact", any = "treasure" }

--Split the comma-separated keyword filter into lowercase search terms.
local function ParseKeywordTerms(text)
    local terms = {}
    for term in string.gmatch(text or "", "[^,]+") do
        term = string.trim(term):lower()
        if term ~= "" then
            terms[#terms+1] = term
        end
    end
    return terms
end

local function ItemMatchesCategory(item, category)
    if category == "trinket" then
        return EquipmentCategory.IsTrinket(item)
    elseif category == "leveled" then
        return EquipmentCategory.IsLeveledTreasure(item)
    elseif category == "consumable" then
        return EquipmentCategory.IsConsumable(item)
    elseif category == "artifact" then
        return EquipmentCategory.IsArtifact(item)
    end
    return EquipmentCategory.IsTreasure(item) or EquipmentCategory.IsArtifact(item)
end

--Keyword terms are OR'd: the item needs one keyword containing any term, so
--"Weapon, Bow" matches both "Medium Weapon" and "Bow".
local function ItemMatchesKeywords(item, terms)
    if #terms == 0 then
        return true
    end
    local keywords = item:try_get("keywords", {})
    for keyword,_ in pairs(keywords) do
        local lower = tostring(keyword):lower()
        for _,term in ipairs(terms) do
            if string.find(lower, term, 1, true) ~= nil then
                return true
            end
        end
    end
    return false
end

local function ItemMatches(modifier, item)
    if not ItemMatchesCategory(item, modifier:try_get("treasureCategory", "trinket")) then
        return false
    end
    --Items without an echelon field are 1st echelon.
    local echelon = tonumber(modifier:try_get("treasureEchelon", 1)) or 1
    if echelon > 0 and (tonumber(item:try_get("echelon", 1)) or 1) ~= echelon then
        return false
    end
    return ItemMatchesKeywords(item, ParseKeywordTerms(modifier:try_get("treasureKeywords", "")))
end

--All gear entries this modifier lets the player choose from, sorted by name,
--as { id = itemid, item = equipment } pairs.
local function MatchingItems(modifier)
    local result = {}
    local gearTable = dmhub.GetTable(equipment.tableName) or {}
    for itemid,item in unhidden_pairs(gearTable) do
        if ItemMatches(modifier, item) then
            result[#result+1] = { id = itemid, item = item }
        end
    end
    table.sort(result, function(a, b) return a.item.name < b.item.name end)
    return result
end

--Human-readable version of the filter, e.g. "a 1st-echelon trinket".
local function FilterDescription(modifier)
    local echelon = tonumber(modifier:try_get("treasureEchelon", 1)) or 1
    local parts = {}
    if ECHELON_NAMES[echelon] ~= nil then
        parts[#parts+1] = ECHELON_NAMES[echelon]
    end
    local terms = ParseKeywordTerms(modifier:try_get("treasureKeywords", ""))
    if #terms > 0 then
        parts[#parts+1] = terms[1]
    end
    parts[#parts+1] = CATEGORY_NAMES[modifier:try_get("treasureCategory", "trinket")] or "treasure"
    local text = table.concat(parts, " ")
    local article = cond(string.find(text, "^[aeiou]") ~= nil, "an ", "a ")
    return article .. text
end

--The player-facing instruction, led by the author's note when there is one,
--e.g. "The Director chooses this trinket. Choose a 2nd-echelon trinket".
local function ChoicePrompt(modifier)
    local prompt = "Choose " .. FilterDescription(modifier)
    local note = string.trim(modifier:try_get("treasureNote", ""))
    if note ~= "" then
        return note .. " " .. prompt
    end
    return prompt
end

local function IsManifestMode(modifier)
    return modifier:try_get("treasureDelivery", "claim") == "manifest"
end

--Per-creature record of the pick: { itemid = string|nil, claimed = boolean,
--manifested = { itemid, slot }|nil }. manifested is set while a Manifest
--Treasure behavior has the item equipped.
local function GetGrantState(creature, modifier, create)
    local grants = creature:try_get("treasureGrants")
    if grants == nil then
        if not create then
            return nil
        end
        grants = creature:get_or_add("treasureGrants", {})
    end
    local state = grants[modifier.guid]
    if state == nil and create then
        state = { claimed = false }
        grants[modifier.guid] = state
    end
    return state
end

local function IsClaimed(creature, modifier)
    local state = GetGrantState(creature, modifier, false)
    return state ~= nil and state.claimed == true
end

--Hands the picked treasure to the creature and locks the grant. Callers own
--the upload: the sheet and builder both write creature fields directly.
local function ClaimTreasure(creature, modifier)
    local state = GetGrantState(creature, modifier, false)
    if state == nil or state.itemid == nil or state.claimed then
        return false
    end
    creature:GiveItem(state.itemid, 1)
    state.claimed = true
    return true
end

local function ClaimedItemName(creature, modifier)
    local state = GetGrantState(creature, modifier, false)
    local gearTable = dmhub.GetTable(equipment.tableName) or {}
    local item = state ~= nil and state.itemid ~= nil and gearTable[state.itemid] or nil
    if item ~= nil then
        return item.name
    end
    return "treasure"
end

CharacterModifier.TypeInfo.granttreasure = {
    init = function(modifier)
        modifier.treasureCategory = "trinket"
        modifier.treasureEchelon = 1
        modifier.treasureKeywords = ""
        modifier.treasureNote = ""
        modifier.treasureDelivery = "claim"
        modifier.treasureId = ""
    end,

    autoDescribe = function(modifier)
        return "Grants " .. FilterDescription(modifier) .. " of your choice"
    end,

    createEditor = function(modifier, element)
        local children = {}
        local matchCountLabel

        local function RefreshMatchCount()
            if matchCountLabel == nil or not matchCountLabel.valid then
                return
            end
            matchCountLabel.text = string.format("%d matching treasures", #MatchingItems(modifier))
        end

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Category:",
            },
            gui.Dropdown{
                classes = {"formDropdown"},
                options = CATEGORY_OPTIONS,
                idChosen = modifier:try_get("treasureCategory", "trinket"),
                change = function(element)
                    ---@cast element Dropdown
                    modifier.treasureCategory = element.idChosen
                    RefreshMatchCount()
                end,
            },
        }

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Echelon:",
            },
            gui.Dropdown{
                classes = {"formDropdown"},
                options = ECHELON_OPTIONS,
                idChosen = tostring(tonumber(modifier:try_get("treasureEchelon", 1)) or 1),
                change = function(element)
                    ---@cast element Dropdown
                    modifier.treasureEchelon = tonumber(element.idChosen) or 0
                    RefreshMatchCount()
                end,
            },
        }

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Keywords (any of):",
            },
            gui.Input{
                classes = {"formInput"},
                characterLimit = 128,
                placeholderText = "e.g. Weapon, Bow",
                text = modifier:try_get("treasureKeywords", ""),
                change = function(element)
                    modifier.treasureKeywords = element.text
                    RefreshMatchCount()
                end,
            },
        }

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Delivery:",
            },
            gui.Dropdown{
                classes = {"formDropdown"},
                options = DELIVERY_OPTIONS,
                idChosen = modifier:try_get("treasureDelivery", "claim"),
                change = function(element)
                    ---@cast element Dropdown
                    modifier.treasureDelivery = element.idChosen
                end,
            },
        }

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Treasure Id:",
            },
            gui.Input{
                classes = {"formInput"},
                characterLimit = 64,
                placeholderText = "Matches Manifest Treasure behaviors, e.g. artifact-bonded",
                text = modifier:try_get("treasureId", ""),
                change = function(element)
                    modifier.treasureId = string.trim(element.text)
                end,
            },
        }

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Note to player:",
            },
            gui.Input{
                classes = {"formInput"},
                characterLimit = 256,
                placeholderText = "e.g. The Director chooses this trinket.",
                text = modifier:try_get("treasureNote", ""),
                change = function(element)
                    modifier.treasureNote = element.text
                end,
            },
        }

        matchCountLabel = gui.Label{
            classes = {"formLabel"},
            width = "auto",
            height = "auto",
            fontSize = 12,
            italics = true,
        }
        children[#children+1] = matchCountLabel
        RefreshMatchCount()

        element.children = children
    end,

    --The character builder shows this grant as a regular feature choice
    --(nav button, target slot, options list) with a Claim button under the slot.
    builderChoices = function(modifier, hero, feature)
        return { CharacterTreasureGrantChoice.CreateNew(hero, feature, modifier) }
    end,

    --Row controls on the character sheet: pick a matching treasure, then
    --"Claim Treasure" adds it to the inventory and locks the choice in.
    --The sheet owns the upload lifecycle, so creature fields are written directly.
    createSheetPanel = function(modifier, creature, options)
        if IsClaimed(creature, modifier) then
            return gui.Label{
                width = "100%",
                height = "auto",
                fontSize = 12,
                italics = true,
                textWrap = true,
                text = string.format("Claimed: %s", ClaimedItemName(creature, modifier)),
            }
        end

        local itemOptions = {}
        for _,entry in ipairs(MatchingItems(modifier)) do
            itemOptions[#itemOptions+1] = { id = entry.id, text = entry.item.name }
        end
        if #itemOptions == 0 then
            return gui.Label{
                width = "100%",
                height = "auto",
                fontSize = 12,
                italics = true,
                textWrap = true,
                text = string.format("No treasures in the compendium match %s.", FilterDescription(modifier)),
            }
        end

        local state = GetGrantState(creature, modifier, false)
        local chosenItemid = state ~= nil and state.itemid or nil
        local gearTable = dmhub.GetTable(equipment.tableName) or {}
        if chosenItemid ~= nil and gearTable[chosenItemid] == nil then
            chosenItemid = nil
        end

        local claimButton
        claimButton = gui.Button{
            classes = {"sizeS"},
            text = "Claim Treasure",
            halign = "left",
            vmargin = 2,
            click = function(element)
                if ClaimTreasure(creature, modifier) and options.refresh ~= nil then
                    options.refresh()
                end
            end,
        }
        claimButton:SetClass("collapsed", chosenItemid == nil or IsManifestMode(modifier))

        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            halign = "left",

            gui.Label{
                width = "100%",
                height = "auto",
                fontSize = 12,
                textWrap = true,
                text = ChoicePrompt(modifier) .. ":",
            },

            gui.Dropdown{
                height = 26,
                width = 240,
                halign = "left",
                vmargin = 2,
                textDefault = "Choose treasure...",
                hasSearch = true,
                options = itemOptions,
                idChosen = chosenItemid or "none",
                change = function(element)
                    ---@cast element Dropdown
                    local current = GetGrantState(creature, modifier, true)
                    if current.claimed then
                        return
                    end
                    if element.idChosen == "none" then
                        current.itemid = nil
                    else
                        current.itemid = element.idChosen
                    end
                    claimButton:SetClass("collapsed", current.itemid == nil or IsManifestMode(modifier))
                end,
            },

            claimButton,
        }
    end,
}

--[[
    Character Treasure Grant Choice

    Makes a Grant Treasure modifier behave like a feature choice in the
    character builder, the same way titles and kits do: the feature cache
    wraps it, so it gets a nav button, header, target slot and a filterable
    options list for free. Selecting an option records the pick; the Claim
    button injected under the target slot hands the item over and locks it.
]]
--- @class CharacterTreasureGrantChoice: CharacterChoice
CharacterTreasureGrantChoice = RegisterGameType("CharacterTreasureGrantChoice", "CharacterChoice")

CharacterTreasureGrantChoice.description = "Treasure Choice"
CharacterTreasureGrantChoice.numChoices = 1
CharacterTreasureGrantChoice.costsPoints = false
CharacterTreasureGrantChoice.hasRoll = false

--- @param hero character
--- @param feature CharacterFeature the feature carrying the modifier; names the choice
--- @param modifier CharacterModifier the granttreasure modifier
--- @return CharacterTreasureGrantChoice
function CharacterTreasureGrantChoice.CreateNew(hero, feature, modifier)
    local options = {}
    local choices = {}

    for _,entry in ipairs(MatchingItems(modifier)) do
        local item = entry.item
        local renderFn = function()
            local content = item.description
            pcall(function()
                content = item:RenderToMarkdown{ noninteractive = true }.content
            end)
            return gui.Label{
                classes = {"builder-base", "label", "info"},
                width = "98%",
                height = "auto",
                halign = "left",
                vmargin = 12,
                textAlignment = "topleft",
                markdown = true,
                text = content,
            }
        end
        options[#options+1] = {
            guid = entry.id,
            name = item.name,
            description = nil,
            unique = true,
            render = renderFn,
        }
        choices[#choices+1] = {
            id = entry.id,
            text = item.name,
            description = nil,
            unique = true,
            render = renderFn,
        }
    end

    local name = "Treasure"
    pcall(function() name = feature.name or name end)

    return CharacterTreasureGrantChoice.new{
        guid = modifier.guid,
        name = name,
        description = cond(IsManifestMode(modifier),
            ChoicePrompt(modifier) .. ".",
            ChoicePrompt(modifier) .. ", then claim it to add it to your inventory."),
        modifier = modifier,
        options = options,
        choices = choices,
    }
end

function CharacterTreasureGrantChoice:CanRepeat()
    return false
end

function CharacterTreasureGrantChoice:Choices()
    return self.choices or {}
end

function CharacterTreasureGrantChoice:GetDescription()
    return self.description
end

function CharacterTreasureGrantChoice:GetOptions()
    return self.options or {}
end

function CharacterTreasureGrantChoice:GetSelected(hero)
    local state = GetGrantState(hero, self.modifier, false)
    if state ~= nil and state.itemid ~= nil then
        return { state.itemid }
    end
    return {}
end

--The step badge only counts the treasure once it is claimed, so a picked but
--unclaimed treasure keeps the step incomplete. Manifest-mode grants have no
--claim step, so the pick itself completes them.
function CharacterTreasureGrantChoice:GetStatus()
    local hero = CharacterBuilder._getHero()
    local done = false
    if hero ~= nil then
        if IsManifestMode(self.modifier) then
            done = #self:GetSelected(hero) > 0
        else
            done = IsClaimed(hero, self.modifier)
        end
    end
    return {
        numChoices = 1,
        selected = cond(done, 1, 0),
    }
end

function CharacterTreasureGrantChoice:NumChoices()
    return 1
end

function CharacterTreasureGrantChoice:OfferFilter()
    return true
end

--A claimed treasure is already in the inventory, so the pick is locked.
--Returning true tells the builder the removal was handled (as a no-op).
function CharacterTreasureGrantChoice:RemoveSelection(hero, option)
    local state = GetGrantState(hero, self.modifier, false)
    if state ~= nil and not state.claimed then
        state.itemid = nil
    end
    return true
end

function CharacterTreasureGrantChoice:SaveSelection(hero, option)
    local state = GetGrantState(hero, self.modifier, true)
    if not state.claimed then
        state.itemid = option.guid or option.id
    end
    return true
end

--Claim button under the target slot. Rebuilds from hero state on every
--builder refresh: hidden until a treasure is picked, replaced by a
--"Claimed" note once the item is in the inventory.
function CharacterTreasureGrantChoice:UIInjections()
    local modifier = self.modifier
    if IsManifestMode(modifier) then
        return {}
    end
    return {
        afterTargets = function()
            return gui.Panel{
                classes = {"builder-base", "panel-base"},
                width = "100%",
                height = "auto",
                flow = "vertical",
                --The injection mounts after the step's initial refresh, so pull state once.
                create = function(element)
                    element:FireEvent("refreshBuilderState", CharacterBuilder._getState())
                end,
                refreshBuilderState = function(element, state)
                    local hero = CharacterBuilder._getHero()
                    local grant = hero ~= nil and GetGrantState(hero, modifier, false) or nil
                    if hero == nil or grant == nil or grant.itemid == nil then
                        element.children = {}
                        return
                    end

                    if grant.claimed then
                        element.children = {
                            gui.Label{
                                classes = {"builder-base", "label", "feature-header", "desc"},
                                text = string.format("%s has been added to your inventory.", ClaimedItemName(hero, modifier)),
                            },
                        }
                        return
                    end

                    element.children = {
                        gui.Button{
                            classes = {"builder-base", "button", "selector"},
                            text = "Claim Treasure",
                            click = function(element)
                                local current = CharacterBuilder._getHero()
                                if current ~= nil and ClaimTreasure(current, modifier) then
                                    CharacterBuilder._fireControllerEvent("tokenDataChanged")
                                end
                            end,
                        },
                    }
                end,
            }
        end,
    }
end

--[[
    Manifest Treasure ability behavior

    Pairs with a manifest-mode Grant Treasure modifier through a shared
    treasureId. "manifest" equips the recorded item in a free trinket or
    leveled slot (item properties are only live while equipped); "vanish"
    unequips and removes it again. Both are no-ops when there is nothing
    to do, so triggers can fire them freely.
]]
--- @class ActivatedAbilityManifestTreasureBehavior:ActivatedAbilityBehavior
--- @field treasureId string Matches the Grant Treasure modifier's treasureId.
--- @field mode string "manifest" or "vanish".
ActivatedAbilityManifestTreasureBehavior = RegisterGameType("ActivatedAbilityManifestTreasureBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
    id = "manifest_treasure",
    text = "Manifest Treasure",
    createBehavior = function()
        return ActivatedAbilityManifestTreasureBehavior.new{
        }
    end
}

ActivatedAbilityManifestTreasureBehavior.summary = "Manifest Treasure"
ActivatedAbilityManifestTreasureBehavior.treasureId = ""
ActivatedAbilityManifestTreasureBehavior.mode = "manifest"

local MANIFEST_MODE_OPTIONS = {
    { id = "manifest", text = "Manifest (equip the treasure)" },
    { id = "vanish", text = "Vanish (remove the treasure)" },
}

--The creature's active Grant Treasure modifier carrying this treasureId, or nil.
local function FindGrantById(creature, treasureId)
    if treasureId == nil or treasureId == "" then
        return nil
    end
    for _,entry in ipairs(creature:GetActiveModifiers()) do
        local candidate = entry.mod
        if candidate.behavior == "granttreasure" and candidate:try_get("treasureId", "") == treasureId then
            return candidate
        end
    end
    return nil
end

--First empty slot of the kind this item equips into: trinkets use the trinket
--slots, everything else (leveled treasures, artifacts) the leveled slots.
local function FreeSlotForItem(creature, item)
    local slotType = cond(EquipmentCategory.IsTrinket(item), "trinket", "leveled")
    local slotids = {}
    for slotid,slot in pairs(creature.EquipmentSlots) do
        if slot.type == slotType then
            slotids[#slotids+1] = slotid
        end
    end
    table.sort(slotids)
    local equip = creature:Equipment()
    for _,slotid in ipairs(slotids) do
        if equip[slotid] == nil then
            return slotid
        end
    end
    return nil
end

--Queues the token's item pickup / loss float. GiveItem only queues the pickup
--one for positive quantities, and manifest bypasses GiveItem entirely.
local function QueueItemAnimation(creature, animType, itemid)
    local anim = creature:GetOrAddAnimation{
        animType = animType,
        items = {},
    }
    anim.items[itemid] = 1
end

--Where the creature currently holds an item: an equipment slot id,
--"inventory", or nil when they no longer have it at all.
local function LocateItem(creature, itemid)
    for slotid,equipped in pairs(creature:Equipment()) do
        if equipped == itemid then
            return slotid
        end
    end
    if creature:GetItemQuantity(itemid) > 0 then
        return "inventory"
    end
    return nil
end

--The manifested flag is only trusted while the item is actually still on the
--creature. If the player dropped or destroyed it by hand, the record is
--stale: clear it so the artifact can appear again next encounter.
local function IsManifested(creature, state)
    if state == nil or state.manifested == nil then
        return false
    end
    if LocateItem(creature, state.manifested.itemid) == nil then
        state.manifested = nil
        return false
    end
    return true
end

--Equips the recorded item straight into a slot (equipped items live in the
--slot, not the inventory) and remembers where so vanish can find it.
local function ManifestTreasure(creature, modifier)
    local state = GetGrantState(creature, modifier, false)
    if state == nil or state.itemid == nil or IsManifested(creature, state) then
        return false
    end
    local item = (dmhub.GetTable(equipment.tableName) or {})[state.itemid]
    if item == nil then
        return false
    end
    local slot = FreeSlotForItem(creature, item)
    if slot == nil then
        printf("ManifestTreasure: no free slot for %s", item.name)
        return false
    end
    creature:Equipment()[slot] = state.itemid
    state.manifested = { itemid = state.itemid, slot = slot }
    QueueItemAnimation(creature, "giveItem", state.itemid)
    return true
end

--Removes the item from wherever it is now (the player may have moved it to
--another slot or the inventory). Slots are cleared directly rather than via
--Unequip, which would hand the item to the inventory and queue a pickup float.
local function VanishTreasure(creature, modifier)
    local state = GetGrantState(creature, modifier, false)
    if not IsManifested(creature, state) then
        return false
    end
    local itemid = state.manifested.itemid
    local location = LocateItem(creature, itemid)
    if location == "inventory" then
        creature:GiveItem(itemid, -1)
    else
        creature:SetEquipmentInSlot(location, nil)
        creature:ClearEquipmentMetaSlot(location)
    end
    state.manifested = nil
    QueueItemAnimation(creature, "loseItem", itemid)
    return true
end

function ActivatedAbilityManifestTreasureBehavior:Cast(ability, casterToken, targets, options)
    local tokens = {}
    for _,target in ipairs(targets) do
        if target.token ~= nil then
            tokens[#tokens+1] = target.token
        end
    end
    if #tokens == 0 then
        tokens[1] = casterToken
    end

    for _,token in ipairs(tokens) do
        local modifier = FindGrantById(token.properties, self.treasureId)
        if modifier == nil then
            printf("ManifestTreasure: %s has no Grant Treasure modifier with id '%s'", token.name or "creature", self.treasureId)
        else
            token:ModifyProperties{
                description = cond(self.mode == "vanish", "Treasure vanishes", "Treasure manifests"),
                execute = function()
                    if self.mode == "vanish" then
                        VanishTreasure(token.properties, modifier)
                    else
                        ManifestTreasure(token.properties, modifier)
                    end
                end,
            }
        end
    end
end

function ActivatedAbilityManifestTreasureBehavior:EditorItems(parentPanel)
    local result = {}

    self:ApplyToEditor(parentPanel, result)
    self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Treasure Id:",
        },
        gui.Input{
            classes = {"formInput"},
            characterLimit = 64,
            placeholderText = "Matches a Grant Treasure modifier's id",
            text = self.treasureId,
            change = function(element)
                self.treasureId = string.trim(element.text)
            end,
        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Mode:",
        },
        gui.Dropdown{
            classes = {"formDropdown"},
            options = MANIFEST_MODE_OPTIONS,
            idChosen = self.mode,
            change = function(element)
                ---@cast element Dropdown
                self.mode = element.idChosen
            end,
        },
    }

    return result
end

--Lets vanish triggers (end of turn, regaining Stamina) fire only while
--something is actually manifested.
GameSystem.RegisterGoblinScriptField{
    target = creature,
    name = "HasManifestedTreasure",
    type = "boolean",
    desc = "True while a treasure from a manifest-mode Grant Treasure is currently equipped by a Manifest Treasure behavior.",
    examples = {"HasManifestedTreasure", "Target.HasManifestedTreasure"},
    calculate = function(c)
        local grants = c:try_get("treasureGrants")
        if grants == nil then
            return false
        end
        for _,state in pairs(grants) do
            if type(state) == "table" and state.manifested ~= nil
                    and LocateItem(c, state.manifested.itemid) ~= nil then
                return true
            end
        end
        return false
    end,
}

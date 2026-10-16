local mod = dmhub.GetModLoading()

local Importers
local MatchSignature

import.Register{
    id = "generic_json",
    description = "Generic JSON",
    input = "text",
    priority = 0,
    json = function(importer, doc)
        if importer.init == false then
            importer.init = true
            importer.initImporter(importer)
        end

        local found = false
        for k,items in pairs(doc) do
            if Importers[k] ~= nil and type(items) == "table" then
                local importer = Importers[k]
                for _,item in ipairs(items) do
                    if type(item) == "table" then
                        importer(item)
                        found = true
                    end
                end
            end
        end

        if not found then
            for _,item in ipairs(doc) do
                if importer.json(importer, item) then
                    found = true
                end
            end
        end

        if not found then
            local sig = MatchSignature(doc)
            if sig ~= nil then
                local importer = Importers[sig]
                found = importer(doc)
            end
        end

        return found
    end,

    init = false,

    initImporter = function(importer)
    end,
}

local function AppendDescription(description, entry)
    if type(entry) == "string" then
        if description == "" then
            description = entry
        else
            description = string.format("%s\n%s", description, entry)
        end

    elseif type(entry) == "table" then
        if entry.type == "list" and type(entry.items) == "table" then
            if entry.style == "list-hang-notitle" then
                for _,item in ipairs(entry.items) do
                    local itemDesc = ""
                    for _,subentry in ipairs(item.entries or {}) do
                        itemDesc = AppendDescription(itemDesc, subentry)
                    end
                    description = AppendDescription(description, string.format(" %s <b>%s.</b> %s", Styles.bullet, item.name, itemDesc))
                end

            end
        end
    end

    return description
end

local function ParseResistanceTable(c, t, resistType)
    if type(t) ~= "table" then
        return
    end

    if #t == 0 then
        for k,v in pairs(t) do
            if type(v) == "string" then
                c.resistances[#c.resistances+1] = ResistanceEntry.new{
                    apply = resistType,
                    damageType = k,
                    nonmagic = (string.find(v, "non.*magic") ~= nil),
                }
            end
        end
    else

        for _,v in ipairs(t) do
            if type(v) == "string" then
                c.resistances[#c.resistances+1] = ResistanceEntry.new{
                    apply = resistType,
                    damageType = string.lower(v),
                }
            end
        end
    end
end

local function ParseResistanceString(c, str, resistType)
    if type(str) == "table" then
        ParseResistanceTable(c, str, resistType)
        return
    end

    if type(str) ~= "string" then
        return
    end
    for _,item in ipairs(string.split(string.lower(str), ",")) do
        local resistanceid = trim(item)
        c.resistances[#c.resistances+1] = ResistanceEntry.new{
            apply = resistType,
            damageType = resistanceid,
        }
    end
end



local function ParseResistanceType(c, doc, srcType, dstType)
    for _,entry in ipairs(doc[srcType] or {}) do
        if type(entry) == "table" then
            local note = entry.note or ""
            local nonmagic = nil
            if string.find(note, "nonmagic") then
                nonmagic = true
            end
            for _,damageType in ipairs(entry[srcType] or {}) do
                c.resistances[#c.resistances+1] = {
                    apply = dstType,
                    damageType = damageType,
                    nonmagic = nonmagic,
                }
            end
        else
            local damageType = entry
            c.resistances[#c.resistances+1] = {
                apply = dstType,
                damageType = damageType,
            }
        end
    end
end

local g_Signatures = {
    character = {
        keys = {"race", "class", "level", "alignment", "equipment"},
        requirement = 3,
    },
    monster = {
        keys = {"size", "type", "alignment", "ac", "hp", "armor_class", "hitpoints", "challenge_rating", "str", "cr"},
        requirement = 4,
    },
    spell = {
        keys = {"school", "components", "entriesHigherLevel"},
        requirement = 2,
    },
    item = {
        keys = { "rarity", "attunement" },
        requirement = 2,
    }
}


MatchSignature = function(doc)
    if doc.name == nil then
        printf("JSON:: SIG NO NAME")
        return nil
    end

    if doc.type ~= nil and g_Signatures[string.lower(doc.type)] then
        --the type is explicitly specified
        return doc.type
    end

    for sigkey,entry in pairs(g_Signatures) do
        printf("JSON:: SIG CONSIDER %s FOR %s", sigkey, json(doc))
        local score = 0
        for _,key in ipairs(entry.keys) do
            printf("JSON:: KEY %s -> %s", key, json(doc[key] ~= nil))
            if doc[key] ~= nil then
                score = score+1
            end
        end

        printf("JSON:: SIG CONSIDER %s GOT SCORE %s / %s", sigkey, json(score), json(entry.requirement))
        if score >= entry.requirement then
            return sigkey
        end
    end

    return nil
end

local function ParseCharacterClass(c, doc)
    local className = doc.class
    local level = tonumber(doc.level)
    if type(className) ~= "string" or type(level) ~= "number" then
        printf("CLASS:: INVALID %s / %s", json(className), json(level))
        return
    end

    local classid = nil
    local stripstr = function(s) return string.lower(string.gsub(s, "%W", "")) end
    local classTable = dmhub.GetTable(Class.tableName)

    printf("CLASS:: SEARCH FOR %s", className)

    for k,v in pairs(classTable) do
        if stripstr(className) == stripstr(v.name) then
            classid = k
        end
    end

    printf("CLASS:: FOUND CLASS = %s", json(classid))

    if classid ~= nil then
        printf("CLASS:: SET CLASS!")
        c.classes = {
            {
                classid = classid,
                level = level,
            }
        }
    end

end

local function ParseCharacterRace(c, doc)
    local raceName = doc.race or doc.Race
    if type(raceName) ~= "string" then
        return
    end

    local stripstr = function(s) return string.lower(string.gsub(s, "%W", "")) end

    local racesTable = dmhub.GetTable("races") or {}
    local subracesTable = dmhub.GetTable("subraces") or {}

    local race = nil
    local subrace = nil

    for k,v in pairs(racesTable) do
        if stripstr(raceName) == stripstr(v.name) then
            race = v
        end
    end

    for k,v in pairs(subracesTable) do
        if stripstr(raceName) == stripstr(v.name) then
            subrace = v
        end
    end

    if subrace ~= nil then
        race = racesTable[subrace:try_get("parentRace")]
    elseif race ~= nil and subrace == nil then
        for k,v in pairs(subracesTable) do
            if v:try_get("parentRace") == race.id then
                subrace = v
            end
        end
    end

    if race ~= nil then
        c.raceid = race.id
    end

    if subrace ~= nil then
        c.subraceid = subrace.id
    end
end

local function ParseMonsterAttributes(c, doc)

    for _,attrid in ipairs(creature.attributeIds) do
        local attrName = creature.attributesInfo[attrid].description
        if tonumber(doc[attrid]) ~= nil then
            c.attributes[attrid] = { baseValue = tonumber(doc[attrid]) }
        elseif tonumber(doc[string.lower(attrName)]) ~= nil then
            c.attributes[attrid] = { baseValue = tonumber(doc[string.lower(attrName)]) }
        elseif tonumber(doc[attrName]) ~= nil then
            c.attributes[attrid] = { baseValue = tonumber(doc[attrName]) }
        else
            c.attributes[attrid] = { baseValue = 10 }

            if type(doc.abilities) ~= "table" then
                import:Log(string.format("Could not find attribute %s", attrid))
            end
        end
    end

    local abilities = doc.abilities or doc.ability_scores or doc.stats
    if type(abilities) == "table" then
        for k,v in pairs(abilities) do
            if type(k) == "string" and (type(v) == "string" or type(v) == "number") then
                for attrid,attrInfo in pairs(creature.attributesInfo) do
                    if string.lower(k) == string.lower(attrInfo.id) or string.lower(k) == string.lower(attrInfo.description) then
                        c.attributes[attrid] = { baseValue = tonumber(v) }
                    end
                end
            end
        end
    end

    local allLowValues = true
    local hasModifiers = false
    for k,v in pairs(c.attributes) do
        if v.baseValue ~= nil and v.baseValue < 1 then
            hasModifiers = true
        elseif v.baseValue ~= nil and v.baseValue > 4 then
            allLowValues = false
        end
    end

    if allLowValues or hasModifiers then
        for k,v in pairs(c.attributes) do
            if v.baseValue ~= nil then
                v.baseValue = v.baseValue*2 + 10
            end
        end
    end
end

local function ParseCharacterNotes(c, doc)

    local keys = {"notes", "traits", "ideals", "bonds", "flaws"}

    for _,key in ipairs(keys) do
        local note = nil
        if type(doc[key]) == "string" then
            note = doc[key]
        elseif type(doc[key]) == "table" then
            for _,n in ipairs(doc[key]) do
                if type(n) == "string" then
                    if note == nil then
                        note = n
                    else
                        note = note .. "\n\n" .. n
                    end
                end
            end
        end

        if note ~= nil then
            c.notes[#c.notes+1] = {
                title = key,
                text = note,
            }
        end
    end
end

local function ParseCharacterEquipment(c, doc)
    local equipmentTable = doc.equipment or doc.inventory
    if type(equipmentTable) ~= "table" then
        return
    end


    --The slot the first armor found is equipped into; nil once it is filled.
    ---@type string|nil
    local armorSlot = "armor"

    local stripstr = function(s) return string.lower(string.gsub(s, "%W", "")) end

    local itemsTable = dmhub.GetTable(equipment.tableName) --equipment.GetMundaneItems()
    for _,itemName in ipairs(equipmentTable) do
        if type(itemName) == "string" then
            local name = itemName
            ---@type number
            local quantity = 1
            local i,j,nameParsed,quantityParsed = string.find(itemName, "^(.+) %((%d+)%)$")

            if nameParsed ~= nil then
                name = nameParsed
                --quantityParsed is a %d+ capture, so tonumber cannot fail.
                quantity = tonumber(quantityParsed) --[[@as number]]
            end

            name = stripstr(name)

            local itemidFound = nil
            local itemInfoFound = nil
            for itemid,itemInfo in pairs(itemsTable) do
                if stripstr(itemInfo.name) == name and (not itemInfo:try_get("unique")) then
                    itemidFound = itemid
                    itemInfoFound = itemInfo

                end
            end

            if itemidFound ~= nil then
                --assigned together with itemidFound above.
                ---@cast itemInfoFound -nil
                if EquipmentCategory.IsPack(itemInfoFound) and itemInfoFound:has_key("packItems") then
                    --unpack packs immediately.
					for i,entry in ipairs(itemInfoFound.packItems) do
						c:GiveItem(entry.itemid, entry.quantity)
					end

                else
                    c:GiveItem(itemidFound, quantity)
                    if itemInfoFound.isArmor and armorSlot ~= nil then
                        c:Equipment()[armorSlot] = itemidFound
                        armorSlot = nil

                        c:GiveItem(itemidFound, -1)
                    end
                end
            end
        end
    end

    local primaryHandItems = {}
    local secondaryHandItems = {}

    local inventoryEntries = c:try_get("inventory", {})
    for k,entry in pairs(inventoryEntries) do
        if type(entry.quantity) == "number" and entry.quantity > 0 then
            local itemInfo = itemsTable[k]
            if itemInfo.isWeapon then
                --isWeapon is true only on the weapon type.
                ---@cast itemInfo weapon
                primaryHandItems[#primaryHandItems+1] = {
                    itemid = k,
                    twohanded = itemInfo:TwoHanded(),
                    ord = cond(itemInfo:IsRanged(), 1, 0),
                }
            elseif itemInfo.isShield or itemInfo:has_key("emitLight") then
                secondaryHandItems[#secondaryHandItems+1] = {
                    itemid = k,
                    ord = cond(itemInfo.isShield, 0, 1),
                }
            end
        end
    end

    --try to assign items to sensible loadout slots.
    local loadouts = creature.GetMainHandLoadoutSlots()

    table.sort(primaryHandItems, function(a,b) return a.ord < b.ord end)
    table.sort(secondaryHandItems, function(a,b) return a.ord < b.ord end)

    local usedItems = {}

    while #secondaryHandItems > 0 and #primaryHandItems > 0 and #loadouts > 0 do
        for _,entry in ipairs(primaryHandItems) do
            c:Equipment()[loadouts[1].slotid] = entry.itemid
            if entry.twohanded or #secondaryHandItems == 0 then

                if entry.twohanded then
                    c:EquipmentMetaSlot(loadouts[1].slotid).twohanded = true
                    c:EquipmentMetaSlot(loadouts[1].otherhand).twohanded = true
                end

            else
                usedItems[entry.itemid] = secondaryHandItems[1].itemid

                c:Equipment()[loadouts[1].otherhand] = secondaryHandItems[1].itemid

                table.remove(secondaryHandItems, 1)
            end

            usedItems[entry.itemid] = true

            table.remove(loadouts, 1)
            if #loadouts == 0 then
                break
            end
        end
    end

    for itemid,_ in pairs(usedItems) do
        c:GiveItem(itemid, -1)
    end
end

local function ParseAlignment(c, doc)
    local knownAlignments = {
        "lawful good",
        "neutral good",
        "chaotic good",
        "lawful neutral",
        "true neutral",
        "neutral neutral",
        "chaotic neutral",
        "lawful evil",
        "neutral evil",
        "chaotic evil",
        "unaligned",
    }

    --alignment
    if doc.alignment ~= nil and doc.alignment:find("any") then
        c.alignment = nil
        c.customAlignment = doc.alignment 
    elseif doc.alignment == nil or (type(doc.alignment) == "string" and #doc.alignment ~= 2) then
        c.alignment = "unknown"

        if type(doc.alignment) == "string" then
            for _,align in ipairs(knownAlignments) do
                if string.lower(align) == string.lower(doc.alignment) then
                    c.alignment = align
                end
            end
        end
    else
        local alignmentTables = {
            C = "chaotic",
            L = "lawful",
            N = "neutral",
            G = "good",
            E = "evil",
        }

        c.alignment = ""
        for _,align in ipairs(doc.alignment) do
            if alignmentTables[align] == nil then
                import:Log("Unrecognized alignment")
                c.alignment = "unknown"
                break
            else
                if c.alignment ~= "" then
                    c.alignment = c.alignment .. " "
                end

                c.alignment = c.alignment .. alignmentTables[align]
            end
        end
    end

    if c:try_get("alignment") == "neutral neutral" then
        c.alignment = "true neutral"
    end
end

Importers = {
    item = function(doc)
        local itemsTable = dmhub.GetTable("tbl_Gear")

        local baseItem = nil
        if type(doc.baseItem) == "string" then
            for _,item in pairs(equipment.GetMundaneItems()) do
                if string.lower(item.name) == string.lower(doc.baseItem) then
                    baseItem = DeepCopy(item)
                    baseItem.id = nil
                end
            end
        end

        local bookmark = import:BookmarkLog()

        local category = string.lower(doc.category or "item")

        local newItem

        if baseItem == nil then
            baseItem = {}
        end

        if string.find(category, "weapon") ~= nil then
            newItem = weapon.new(baseItem)
            newItem.type = "Weapon"
        elseif string.find(category, "armor") ~= nil then
            newItem = armor.new(baseItem)
            newItem.type = "Armor"
        elseif string.find(category, "shield") ~= nil then
            newItem = shield.new(baseItem)
            newItem.type = "Shield"
        else
            newItem = equipment.new(baseItem)
            newItem.type = "Item"
        end

        newItem.name = doc.name
        newItem.description = doc.description or ""
        newItem.iconid = ""

        for _,p in ipairs(doc.properties or {}) do
            if type(p) == "string" then
                newItem.description = string.format("%s\n\n%s", doc.description, p)
            end
        end

        if type(doc.cost) == "number" then
            newItem.costInCurrency = nil
            newItem.costInGold = doc.cost
        end

        if type(doc.weight) == "number" then
            newItem.weight = doc.weight
        end



        import:StoreLogFromBookmark(bookmark, newItem)

        printf("JSON:: IMPORT: %s", json(newItem))
        import:ImportAsset("tbl_Gear", newItem)

    end,

    spell = function(spell)

        local bookmark = import:BookmarkLog()

        local school
        if Spell.schoolsByChar[spell.school] ~= nil then
            school = Spell.schoolsByChar[spell.school].id
        else
            for _,schoolEntry in ipairs(Spell.schools) do
                if string.lower(schoolEntry.text) == string.lower(spell.school) or string.lower(schoolEntry.id) == string.lower(spell.school) then
                    school = schoolEntry.id
                    break
                end
            end
        end

        local description = spell.description or ""

        if type(spell.entriesHigherLevel) == "table" then
            for i,higherLevelEntry in ipairs(spell.entriesHigherLevel) do
                if higherLevelEntry.type == "entries" and type(higherLevelEntry.entries) == "table" then
                    for n,entry in ipairs(higherLevelEntry.entries) do
                        description = AppendDescription(description, entry)
                    end
                end
            end
        end

        local range
        local radius
        local targetType

        if type(spell.range) == "string" then
            if string.lower(spell.range) == "touch" then
                range = 5
            else
                local i,j = string.find(spell.range, "^%d+")
                if i ~= nil then
                    range = tonumber(string.sub(spell.range, i, j))
                end
            end
        end

        local shapeInfo = ImportUtils.ParseTargetShape(description)
        if shapeInfo ~= nil then
            if range == nil then
                range = shapeInfo.range
            end

            targetType = shapeInfo.targetType
            radius = shapeInfo.radius
        end

        local componentCost = nil
        local components = {}
        if type(spell.components) == "table" then
            for i,id in ipairs(spell.components) do
                components[string.lower(id)] = true
            end
        elseif type(spell.components) == "string" then
            local c = string.lower(spell.components)
            for i=1,3 do
                while string.find(c, "^ ") ~= nil do
                    c = string.sub(c, 2, #c)
                end
                if string.find(c, "^v,") ~= nil then
                    components["v"] = true
                    c = string.sub(c, 3, #c)
                elseif string.find(c, "^s,") ~= nil then
                    components["s"] = true
                    c = string.sub(c, 3, #c)
                else
                    local i,j,m = string.find(c, "^m %((.+)%)")
                    if i ~= nil then
                        components["m"] = m
                    end
                end
            end
        end

        if type(spell.material) == "string" then
            components["m"] = spell.material
            local i,j,cost = string.find(string.lower(spell.material), " (%d+) g")
            if cost ~= nil then
                componentCost = tonumber(cost)
            end
        end

        local newSpell = Spell.Create{
            name = spell.name,
            level = tonumber(spell.level),
            iconid = "",
            school = school,
            description = description,
            components = components,
            componentCost = componentCost,
            range = range,
            radius = radius,
            targetType = targetType,
        }
        printf("JSON:: READ DESCRIPTION: %s", newSpell.description)

        local ParseDurationType = function(durationType)

            durationType = string.lower(durationType)

            if durationType == "round" then
                newSpell.durationType = "rounds"
            elseif durationType == "minute" then
                newSpell.durationType = "minutes"
            elseif durationType == "hour" then
                newSpell.durationType = "hours"
            elseif durationType == "day" then
                newSpell.durationType = "days"
            else
                import:Log(string.format("Unimplemented duration type: %s", durationType))
            end
        end

        local spellDuration = spell.duration
        if type(spellDuration) == "table" and type(spellDuration.type) == "string" and string.lower(spellDuration.type) == "time" then
            spellDuration = spellDuration.duration
        end

        if type(spellDuration) == "string" then
            if string.find(string.lower(spellDuration), "^instant") ~= nil then
                newSpell.durationType = "instant"
            else
                --quantity is a %d+ capture, so tonumber cannot fail.
                local i,j,quantity,durationType = string.find(spellDuration, "^(%d+) (%a+)")
                if i ~= nil then
                    newSpell.durationLength = tonumber(quantity) --[[@as number]]
                    ParseDurationType(durationType)
                else
                    local i,j,quantity,durationType = string.find(spellDuration, "^concentration.+to (%d+) (%a+)")
                    if i ~= nil then
                        newSpell.concentration = true
                        newSpell.durationLength = tonumber(quantity) --[[@as number]]
                        ParseDurationType(durationType)
                    else
                        newSpell.durationType = "indefinite"
                    end
                end
            end
        elseif type(spellDuration) == "table" then
            for _,entry in ipairs(spellDuration) do
                if entry.type == "instant" then
                    newSpell.durationType = "instant"
                    
                elseif entry.type == "timed" then
                    local duration = entry.duration
                    if type(duration) == "table" then
                        ParseDurationType(duration.type)
                        newSpell.durationLength = duration.amount
                    else
                        import:Log(string.format("Could not find duration on timed spell"))
                    end

                elseif entry.type == "permanent" or entry.type == "special" then
                    newSpell.durationType = "indefinite"
                else
                    import:Log(string.format("Unimplemented duration entry type: %s", entry.type))
                end
            end
        end

        if type(spell.casting_time) == "string" then
            local castingTime = string.lower(spell.casting_time)
            if castingTime == "1 action" then
                newSpell.actionResourceId = "standardAction"
            elseif string.find(castingTime, "bonus") ~= nil then
                newSpell.actionResourceId = "bonusAction"
            elseif string.find(castingTime, "reaction") ~= nil then
                newSpell.actionResourceId = "reaction"
            end
        end


        import:StoreLogFromBookmark(bookmark, newSpell)

        printf("JSON:: IMPORT: %s", json(newSpell))
        import:ImportAsset("Spells", newSpell)
    end,

    character = function(doc)
        local bookmark = import:BookmarkLog()

        local token = import:CreateCharacter()
        token.properties = character.CreateNew()

        token.partyId = GetDefaultPartyID()
        token.name = tostring(doc.name) or ""
        
        local c = token.properties

        c.notes = {}

        ParseCharacterRace(c, doc)
        ParseCharacterClass(c, doc)

        ParseMonsterAttributes(c, doc)

        ParseAlignment(c, doc)

        ParseCharacterEquipment(c, doc)

        ParseCharacterNotes(c, doc)

        import:StoreLogFromBookmark(bookmark, token)

        import:ImportCharacter(token)
    end,

    monster = function(doc)
        local bookmark = import:BookmarkLog()

        local is_character = doc.isNamedCreature

        --A CharacterToken when is_character, otherwise a MonsterAssetLua.
        ---@type CharacterToken|MonsterAssetLua
        local m

        local notes = {}

        if is_character then
            local token = import:CreateCharacter()
            token.properties = monster.CreateNew()

            local partiesTable = dmhub.GetTable(Party.tableName)
            local targetParty = nil
            for partyid,partyInfo in pairs(partiesTable) do
                if partyInfo:try_get("hidden", false) == false and partyid ~= GetDefaultPartyID() and (targetParty == nil or string.find(partyInfo.name, "NPC")) then
                    targetParty = partyid

                end
            end

            if targetParty ~= nil then
                token.partyId = targetParty
            else
                token.partyId = GetDefaultPartyID()
            end

            m = token
        else
            --the "monster" table only ever yields a MonsterAssetLua (or nil).
            local existing = import:GetExistingItem("monster", doc.name) --[[@as MonsterAssetLua|nil]]
            if existing == nil then
                existing = import:CreateMonster()
                existing.properties = monster.CreateNew()
            end
            m = existing
        end


        local c = m.properties

        m.name = doc.name
        c.monster_type = doc.name
        c.monster_category = doc.type
        if doc.race ~= nil and (doc.type == nil or doc.type == "monster") then
            c.monster_category = doc.race
        end

        if type(doc.description) == "string" then
            notes[#notes+1] = {
                title = "Description",
                text = doc.description,
            }
        end

        local splitOnColonOrPeriod = function(s)
            -- Find the position of the first colon or period
            local position = s:find("[:.]")
        
            -- If no colon or period was found, return nil
            if not position then
                return nil
            end
        
            -- Return the substrings before and after the position
            return s:sub(1, position - 1), s:sub(position + 1)
        end
        

        local abilitiesKeys = {"special_abilities", "special_traits"}

        for _,keyName in ipairs(abilitiesKeys) do

            for _,ability in ipairs(doc[keyName] or {}) do
                if type(ability) == "table" then
                    notes[#notes+1] = {
                        title = ability.name,
                        text = ability.description
                    }
                elseif type(ability) == "string" then
                    local title, text = splitOnColonOrPeriod(ability)
                    if title == nil or #title > 24 then
                        notes[#notes+1] = {
                            title = "Special Trait",
                            text = ability,
                        }
                    else
                        notes[#notes+1] = {
                            title = title,
                            text = text,
                        }
                    end
                end
            end
        end

        local cr = doc.cr or doc.challenge_rating
        if type(cr) == "string" or type(cr) == "number" then
            c.cr = ImportUtils.ParseCR(cr)
        end


        ParseMonsterAttributes(c, doc)

        if type(doc.innate_spellcasting) == "table" then
            local info = doc.innate_spellcasting
            local ability = info.ability or info.attr or info.attribute

            local attr = nil
            if ability ~= nil then
             for attrKey,attrInfo in pairs(creature.attributesInfo) do
                 if string.lower(attrKey) == string.lower(ability) or (attrInfo.description ~= nil and string.lower(attrInfo.description) == string.lower(ability)) then
                     attr = attrKey
                 end
             end
            end

             if attr ~= nil then
                local innateSpellcasting = {}

                --example:
                --"spells": {
                --    "at_will": ["feather fall (self only)"],
                --    "1/day": ["blink", "blur"]
                --}
                for k,entry in pairs(info.spells or {}) do
                    if type(entry) == "table" then
                        for _,spellnameStr in ipairs(entry) do
                            if type(spellnameStr) == "string" then
                                local spellname = spellnameStr

                                local beginParens = string.find(spellname, " %(")
                                if beginParens ~= nil then
                                    spellname = string.sub(spellname, 1, beginParens-1)
                                end

                                local spellidMatch = nil
                                local spellnameLower = string.lower(string.gsub(spellname, "%W", ""))
                                local spellsTable = dmhub.GetTable(Spell.tableName)
                                for spellid,spellInfo in pairs(spellsTable) do
                                    if string.lower(string.gsub(spellInfo.name, "%W", "")) == spellnameLower then
                                        spellidMatch = spellid
                                        break
                                    end
                                end

                                if spellidMatch ~= nil then

                                    local usageLimitOptions = nil
                                    local i1,i2,charges,freq = string.find(k, "(%d+)/(%a+)")
                                    if i1 ~= nil and freq == "day" then
                                        usageLimitOptions = {
                                            charges = tonumber(charges),
                                            resourceRefreshType = freq,
                                            resourceid = dmhub.GenerateGuid(),
                                        }
                                    end

                                    innateSpellcasting[#innateSpellcasting+1] = {
                                        spellid = spellidMatch,
                                        attrid = attr,
                                        usageLimitOptions = usageLimitOptions,
                                    }
                                end

                            end
                        end
                    end
                end

                m.properties.innateSpellcasting = innateSpellcasting
             end
        end

        if type(doc.spellcasting) == "table" then
            m.properties.monsterSpellcasting = CharacterModifier.CreateMonsterSpellcastingModifier()
            m.properties.monsterSpellcasting.spellcasting.name = "Spellcasting"

            local attr = nil
            local spellcastingLevel = nil
            local preparedSpells = nil
            ---@type table<number, string[]>
            local preparedSpellsByLevel = nil

            for k,v in pairs(doc.spellcasting) do
                if string.find(string.lower(k), "level") ~= nil and tonumber(v) ~= nil then
                    spellcastingLevel = tonumber(v)
                    m.properties.monsterSpellcasting.spellcastingLevel = tonumber(v)
                end

                if string.find(string.lower(k), "ability") ~= nil or string.find(string.lower(k), "attr") ~= nil then
                    for attrKey,attrInfo in pairs(creature.attributesInfo) do
                        if string.lower(attrKey) == string.lower(v) or string.lower(attrInfo.description) == string.lower(v) then
                            attr = attrKey
                        end
                    end

                    if attr ~= nil then
                        m.properties.spellcastingAttr = attr
                        m.properties.monsterSpellcasting.spellcasting.attr = attr
                    end
                end

                local numSpells = 0
                local numCantrips = 0

                --"spells_prepared": {
                --    "cantrips": ["light", "sacred flame", "spare the dying", "thaumaturgy"],
                --    "1st_level": ["cure wounds", "detect magic", "guiding bolt", "healing word", "protection from evil and good"],
                --    "2nd_level": ["lesser restoration", "see invisibility", "silence", "spiritual weapon"],
                --    "3rd_level": ["dispel magic", "remove curse"]
                --  }
                if k == "spells_prepared" and type(v) == "table" then

                    local cantripsPrepared = {}
                    local spellsPrepared = {}


                    for spellsKey,spellsValue in pairs(v) do
                        if type(spellsValue) == "table" then
                            for _,spellname in ipairs(spellsValue) do
                                if type(spellname) == "string" then
                                    local spellidMatch = nil
                                    local spellnameLower = string.lower(string.gsub(spellname, "%W", ""))
                                    local spellsTable = dmhub.GetTable(Spell.tableName)
                                    for spellid,spellInfo in pairs(spellsTable) do
                                        if string.lower(string.gsub(spellInfo.name, "%W", "")) == spellnameLower then
                                            spellidMatch = spellid
                                            break
                                        end
                                    end

                                    if spellidMatch ~= nil then
                                        if preparedSpells == nil then
                                            preparedSpells = {}
                                            preparedSpellsByLevel = {}
                                        end

                                        --do we think this spell was a level or a cantrip?
                                        local num = tonumber(string.match(spellsKey, "(%d+)") or 0)
                                        --tonumber of a run of digits, or of 0, always succeeds.
                                        ---@cast num -nil
                                        if num > 0 then
                                            numSpells = numSpells+1
                                            spellsPrepared[#spellsPrepared+1] = spellidMatch
                                        else
                                            numCantrips = numCantrips+1
                                            cantripsPrepared[#cantripsPrepared+1] = spellidMatch
                                        end

                                        if preparedSpellsByLevel[num] == nil then
                                            preparedSpellsByLevel[num] = {}
                                        end

                                        local lvl = preparedSpellsByLevel[num]
                                        lvl[#lvl+1] = spellidMatch

                                        preparedSpells[spellidMatch] = { timestamp = 1 }
                                    end

                                end
                            end

                        end
                    end

                    if preparedSpells ~= nil then
                        m.properties.preparedSpells = preparedSpells

                        m.properties.spellcasting = {
                            monster = {
                                cantripsPrepared = cantripsPrepared,
                                spellsPrepared = spellsPrepared,
                            }
                        }
                    end
                end
            end

            local spellcastingNote = ""

            if spellcastingLevel == nil then
                spellcastingLevel = c.cr
            end
            
            if spellcastingLevel ~= nil then
                spellcastingNote = string.format("The %s is a level %d spellcaster. ", doc.name, tonumber(spellcastingLevel))
            end

            if attr ~= nil then
                spellcastingNote = string.format("%sIts spellcasting ability is %s. ", spellcastingNote, creature.attributesInfo[attr].description)
            end

            if preparedSpellsByLevel ~= nil then
                spellcastingNote = string.format("%sThe %s has the following spells prepared:\n", spellcastingNote, doc.name)
                for i=0,GameSystem.maxSpellLevel do
                    local lvl = preparedSpellsByLevel[i]
                    if lvl ~= nil then
                        local levelName = "Cantrips"
                        if i > 0 then
                            levelName = string.format("Level %d", i)
                        end

                        local spellObjects = {}
                        local spellTable = dmhub.GetTable(Spell.tableName)
                        for _,spellid in ipairs(lvl) do
                            spellObjects[#spellObjects+1] = spellTable[spellid]
                        end

                        table.sort(spellObjects, function(a,b) return a.name < b.name end)

                        local spellNames = {}
                        for _,spellInfo in ipairs(spellObjects) do
                            spellNames[#spellNames+1] = spellInfo.name
                        end

                        spellcastingNote = string.format("%s\n%s: %s", spellcastingNote, levelName, string.join(spellNames, ", "))
                    end
                end
            end

            notes[#notes+1] = {
                title = "Spellcasting",
                text = spellcastingNote,
            }
        end

        if type(doc.skills) == "table" then
            for k,v in pairs(doc.skills) do
                if type(k) == "string" then
                    for _,skillInfo in ipairs(Skill.SkillsInfo) do
                        if string.lower(k) == string.lower(skillInfo.id) or string.lower(k) == string.lower(skillInfo.name) then
                            if tonumber(v) ~= nil then
                                local ratings = c:get_or_add("skillRatings", {})
                                ratings[skillInfo.id] = round(tonumber(v))
                            else
                                c:SetSkillProficiency(skillInfo, true)
                            end
                        end
                    end
                end
            end
        end

        if type(doc.saving_throws) == "table" then
            c.savingThrowRatings = {}
            for k,v in pairs(doc.saving_throws) do
                if type(k) == "string" and tonumber(v) ~= nil then
                    c.savingThrowRatings[k] = tonumber(v)
                end
            end
        end

        local languages = doc.languages

        if type(doc.languages) == "string" then
            languages = string.split(languages, ",")
        end


        if type(languages) == "table" then
            local customLanguages = {}
            local creatureLanguages = {}
            local langTable = dmhub.GetTable(Language.tableName) or {}

            for _,item in ipairs(languages) do
                local lang = trim(item)
                local found = false

                for langid,langInfo in pairs(langTable) do
                    if string.lower(langInfo.name) == string.lower(lang) then
                        creatureLanguages[langid] = true
                        found = true
                    end
                end

                if found == false then
                    customLanguages[#customLanguages+1] = item
                end
            end

            c.innateLanguages = creatureLanguages

            if #customLanguages > 0 then
                c.customInnateLanguage = string.join(customLanguages, ",")
            end
        end

        local hp = doc.hp or doc.hitpoints or doc.hit_points

        if type(hp) == "string" or type(hp) == "number" then
            if type(hp) == "string" and string.find(hp, "^%d+ %(.+%)") then
                local i,j,hp_base,hp_roll = string.find(hp, "^(%d+) %((.+)%)")
                --the guard above matched, so hp_base is a %d+ capture and tonumber cannot fail.
                c.max_hitpoints = tonumber(hp_base) --[[@as number]]
                c.max_hitpoints_roll = hp_roll
            else
                c.max_hitpoints = tonumber(hp)
                c.max_hitpoints_roll = tostring(doc.hit_dice)
            end
        else
            import:Log("Could not find hitpoints")
        end

        local ac = doc.ac or doc.armor_class
        if type(ac) == "string" or type(ac) == "number" then
            c.armorClassOverride = tonumber(ac)
        end

        if type(doc.size) == "string" then
            for _,size in ipairs(creature.sizes) do
                if string.starts_with(string.lower(size), string.lower(doc.size)) then
                    c.creatureSize = size
                end
            end
        end

        if doc.subtype ~= nil then
            c.monster_subtype = doc.subtype
        end

        if type(doc.speed) == "string" then
            local attr = ImportUtils.ParseAttributeToNumberString(doc.speed)

            for k,v in pairs(attr) do
                if k == "" then
                    c:SetSpeed("walk", v)
                else
                    for _,entry in ipairs(creature.movementTypeInfo) do
                        if k == entry.id or k == string.lower(entry.tense) then
                            c:SetSpeed(entry.id, v)
                        end
                    end
                end
            end
        elseif type(doc.speed) == "table" then
            for k, v in pairs(doc.speed) do
                if type(v) == "number" then
                    c:SetSpeed(k, v)
                end 
            end
        end

        if type(doc.senses) == "string" then
            local passives = {}
            local attr = ImportUtils.ParseAttributeToNumberString(doc.senses)
            for key,value in pairs(attr) do
                if key == "darkvision" then
                    c.darkvision = value
                end

                --load the vision table and see if this matches any named type of vision (e.g. blindsight).
                local visionTable = dmhub.GetTable(VisionType.tableName) or {}
                for visionid,visionEntry in pairs(visionTable) do
                    if string.lower(visionEntry.name) == string.lower(key) then
                        local creatureVision = c:get_or_add("customVision", {})
                        creatureVision[visionid] = tonumber(value)
                    end
                end

                for _,skillInfo in ipairs(Skill.PassiveSkills) do
                    if string.lower(skillInfo.name) == key then
                        passives[skillInfo.id] = value
                    end
                end
            end

            c.passives = passives
        elseif type(doc.senses) == "table" then
            local passives = {}

            for key, value in pairs(doc.senses) do
                if key == "darkvision" then
                    if type(value) == "string" then
                        value = tonumber(value:match("(%d+) ft"))
                    end
                    c.darkvision = value
                end

                --load the vision table and see if this matches any named type of vision (e.g. blindsight).
                local visionTable = dmhub.GetTable(VisionType.tableName) or {}
                for visionid,visionEntry in pairs(visionTable) do
                    if string.lower(visionEntry.name) == string.lower(key) then
                        if type(value) == "string" then
                            value = tonumber(value:match("(%d+) ft"))
                        end

                        local creatureVision = c:get_or_add("customVision", {})
                        creatureVision[visionid] = tonumber(value)
                    end
                end

                for _, skillInfo in ipairs(Skill.PassiveSkills) do
                    if string.find(key, string.lower(skillInfo.name)) ~= nil then
                        passives[skillInfo.id] = value
                    end
                end
            end
            c.passives = passives
        end

        ParseAlignment(c, doc)

        c.resistances = {}

        ParseResistanceString(c, doc.damage_immunities, "Immune")
        ParseResistanceString(c, doc.damage_resistances, "Resistant")
        ParseResistanceString(c, doc.damage_resistance, "Resistant")
        ParseResistanceString(c, doc.damage_vuln, "Vulnerable")
        ParseResistanceString(c, doc.damage_vulnerable, "Vulnerable")
        ParseResistanceString(c, doc.damage_vulnerabilities, "Vulnerable")

        ParseResistanceString(c, doc.resistances, "Resistant")
        ParseResistanceString(c, doc.immunities, "Immune")


        local conditionTable = dmhub.GetTable(CharacterCondition.tableName)

        local condition_immunities = doc.condition_immunities
        if type(condition_immunities) == "string" then
            condition_immunities = string.split(string.lower(condition_immunities), ",")
        end

        if type(condition_immunities) == "table" then
            c.innateConditionImmunities = {}
            for _,condid in ipairs(condition_immunities) do
                local condidtrimmed = trim(string.lower(condid))
                for k,v in pairs(conditionTable) do
                    local name = string.lower(v.name)
                    if condidtrimmed == name or string.starts_with(condidtrimmed, name) or string.starts_with(name, condidtrimmed) then
                        c.innateConditionImmunities[k] = true
                    end
                end
            end
        end
       
        local innateActivatedAbilities = {}
        local innateLegendaryActions = {}

        --a list of abilities to process. Each item in the list is a {name: string, text: string, recharge: number?}
        local rawAbilities = {}

        for _,action in ipairs(doc.actions or {}) do
            local name = action.name
            local description = action.description or action.desc

            if type(action) == "string" then
                name, description = splitOnColonOrPeriod(action)
            end

            if type(name) == "string" then
                local recharge = nil
                local i,j,rechargeStr = string.find(name, " %(Recharge (%d+)")
                if rechargeStr ~= nil then
                    recharge = tonumber(rechargeStr)
                    name = string.sub(name, 1, i-1)
                end

                if type(description) == "string" then
                    rawAbilities[#rawAbilities+1] = {
                        name = name,
                        recharge = recharge,
                        text = description,
                        resource = "standardAction",
                    }
                elseif type(name) == "string" and (type(action.damage) == "string" or type(action.damage_dice) == "string") and (type(action.attack_bonus) == "string" or type(action.attack_bonus) == "number") then
                    --this isn't so well put together, but try to make it work.
                    local damage_type = action.damage_type or action.type or "slashing"
                    rawAbilities[#rawAbilities+1] = {
                        name = name,
                        recharge = recharge,
                        text = string.format("Melee Weapon Attack. +%d to hit. %s %s damage", round(tonumber(action.attack_bonus) or 0), action.damage or action.damage_dice, damage_type),
                        resource = "standardAction",
                        additional_damage = action.additional_damage, --in case there is some kind of additional damage field we'll try to read it.
                    }
                end
            end

        end

        for _,action in ipairs(doc.reactions or {}) do
            local name = action.name
            local description = action.description or action.desc

            if type(action) == "string" then
                name, description = splitOnColonOrPeriod(action)
            end

            if type(name) == "string" then
                local recharge = nil
                local i,j,rechargeStr = string.find(name, " %(Recharge (%d+)")
                if rechargeStr ~= nil then
                    recharge = tonumber(rechargeStr)
                    name = string.sub(name, 1, i-1)
                end

                if type(description) == "string" then
                    rawAbilities[#rawAbilities+1] = {
                        name = name,
                        recharge = recharge,
                        text = description,
                        resource = "reaction"
                    }
                elseif type(name) == "string" and type(action.damage) == "string" and (type(action.attack_bonus) == "string" or type(action.attack_bonus) == "number") then
                    --this isn't so well put together, but try to make it work.
                    rawAbilities[#rawAbilities+1] = {
                        name = name,
                        recharge = recharge,
                        text = string.format("Melee Weapon Attack. +%s to hit. %s", action.attack_bonus, action.damage),
                        resource = "reaction",
                    }
                end
            end
        end

        for _,action in ipairs(doc.legendary_actions or {}) do
            local name = action.name
            local description = action.description or action.desc

            if type(action) == "string" then
                name, description = splitOnColonOrPeriod(action)
            end

            ---@type number
            local numActions = 1
            --name is nil for a string with no ":" or "." and for a table with no name;
            --the check below skips those, so do not crash on them here.
            if type(name) == "string" then
                local i,j,numActionsStr = string.find(name, " %((%d+) actions")
                if numActionsStr ~= nil then
                    --a %d+ capture, so tonumber cannot fail.
                    numActions = tonumber(numActionsStr) --[[@as number]]
                    name = string.sub(name, 1, i-1)
                end
            end

            if type(name) == "string" then
                if type(description) == "string" then
                    rawAbilities[#rawAbilities+1] = {
                        name = name,
                        text = description,
                        resource = CharacterResource.legendaryAction,
                        actionNumber = numActions,
                        legendary = true,
                    }
                elseif type(name) == "string" and type(action.damage) == "string" and (type(action.attack_bonus) == "string" or type(action.attack_bonus) == "number") then
                    local damage_type = action.damage_type or action.type or "slashing"
                    --this isn't so well put together, but try to make it work.
                    rawAbilities[#rawAbilities+1] = {
                        name = name,
                        text = string.format("Melee Weapon Attack. +%d to hit. %s %s damage", round(tonumber(action.attack_bonus) or 0), action.damage, damage_type),
                        resource = CharacterResource.legendaryAction,
                        actionNumber = numActions,
                        legendary = true,
                    }
                end
            end
        end

        
        for _,action in ipairs(rawAbilities) do
            local name = action.name

            local entry = action.text

            if string.starts_with(entry, "{@atk") then
                local i,j = string.find(entry, "{@atk [,a-z ]+}")

                if i == nil then
                    import:Log("Could not recognize attack: " .. entry)
                else
                    local attackTypes = {"rw", "mw", "rs", "ms"}
                    local foundAttackType = nil
                    local atk = string.sub(entry, i,j)
                    for _,attackType in ipairs(attackTypes) do
                        if string.find(atk, attackType) then
                            foundAttackType = attackType
                            break
                        end
                    end

                    if foundAttackType == nil then
                        import:Log("Could not find attack type: " .. entry)
                        foundAttackType = "mw"
                    end

                    local _,_,hit_bonus = string.find(entry, "{@hit (%d+)}")
                    if hit_bonus == nil then
                        import:Log("Could not find hit bonus in attack: " .. entry)
                        hit_bonus = 0
                    end

                    local range
                    local rangeDisadvantage

                    if foundAttackType == "rs" then
                        _,_,range = string.find(entry, "range (%d+) ft")
                        if range == nil then
                            import:Log("Could not find range in attack: " .. entry)
                            range = 30
                        end
                        range = tonumber(range)
                    elseif foundAttackType == "rw" then
                        _,_,range,rangeDisadvantage = string.find(entry, "range (%d+)/(%d+) ft")
                        if range == nil then
                            import:Log("Could not find range in attack: " .. entry)
                            range = 30
                            rangeDisadvantage = 120
                        end
                        range = tonumber(range)
                        rangeDisadvantage = tonumber(rangeDisadvantage)
                    else
                        _,_,range = string.find(entry, "reach (%d+) ft")
                        if range == nil then
                            import:Log("Could not find reach in attack: " .. entry)
                            range = 5
                        end
                        range = tonumber(range)
                    end

                    local _,_,damageRoll,damageType = string.find(entry, ".{@damage (.+)}. (%a+) damage")
                    if damageRoll == nil then
                        --backup for damage, just literally one damage specified bare.
                        _,_,damageRoll,damageType = string.find(entry, "{@h}(1) (%a+) damage")
                    end

                    if damageRoll == nil then
                        import:Log("Could not find damage roll in attack2: " .. entry)
                        damageRoll = "1"
                        damageType = "piercing"
                    end

                    local attackBehavior = ActivatedAbilityAttackBehavior.new{
                        attackType = cond(foundAttackType == "mw" or foundAttackType == "ms", "Melee", "Ranged"),
                        hit = hit_bonus,
                        roll = damageRoll,
                        damageType = damageType,
                        magicalDamage = (foundAttackType == "ms" or foundAttackType == "rs"),
                    }

                    --a damage behavior may be appended below.
                    ---@type ActivatedAbilityBehavior[]
                    local behaviors = {attackBehavior}

                    local abilityArgs = {
                        name = name,
                        iconid = ImportUtils.GetExistingIconForAttackName(name),
                        recharge = action.recharge,
                        description = entry,
                        targetType = "target",
                        range = range,
                        rangeDisadvantage = rangeDisadvantage,
                        actionResourceId = "standardAction",
                        behaviors = behaviors,
                    }

                    if action.additional_damage ~= nil and type(action.additional_damage) == "table" then
                        abilityArgs.behaviors[#abilityArgs.behaviors+1] = ActivatedAbilityDamageBehavior.new{
                            applyto = "hit_targets",
                            damageType = action.additional_damage.damage_type or "slashing",
                            roll = action.damage_dice or action.damage or "1d6",
                        }
                    end

                    local ability
                    if foundAttackType == "ms" or foundAttackType == "rs" then
                        ability = Spell.Create(abilityArgs)
                    else
                        ability = ActivatedAbility.Create(abilityArgs)
                    end

                    innateActivatedAbilities[#innateActivatedAbilities+1] = ability
                end
            else
                --not an attack action.
                local abilityArgs = {
                    name = name,
                    recharge = action.recharge,
                    iconid = ImportUtils.GetExistingIconForAttackName(name),
                    description = entry,
                    actionResourceId = action.resource,
                    actionNumber = action.actionNumber,
                    legendary = action.legendary,
                }

                local ability = ActivatedAbility.Create(abilityArgs)

                if abilityArgs.legendary then
                    innateLegendaryActions[#innateLegendaryActions+1] = ability
                else
                    innateActivatedAbilities[#innateActivatedAbilities+1] = ability
                end
            end
        end
        
        c.innateActivatedAbilities = innateActivatedAbilities

        printf("Legendary:: %s", json(innateLegendaryActions))
        if #innateLegendaryActions > 0 then
            c.innateLegendaryActions = innateLegendaryActions
        end

        c.notes = notes
        c.notesRevision = dmhub.GenerateGuid()

        import:StoreLogFromBookmark(bookmark, m)

        if is_character then
            --is_character built m with CreateCharacter.
            ---@cast m CharacterToken
            import:ImportCharacter(m)
        else
            --otherwise m came from GetExistingItem("monster") or CreateMonster.
            ---@cast m MonsterAssetLua
            import:ImportMonster(m)
        end
    end,
}
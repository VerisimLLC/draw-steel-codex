local mod = dmhub.GetModLoading()

local m_attackIcons = nil

ImportUtils = {

    GetExistingIconForAttackName = function(name)
        local iconsTable = ImportUtils.GetAttackIconsByName()
        return iconsTable[string.lower(name)] or ""
    end,

    GetAttackIconsByName = function()
        if m_attackIcons == nil then
            m_attackIcons = {}

            for k,entry in pairs(assets.monsters) do
                for j,attack in ipairs(entry.properties:try_get('innateAttacks', {})) do
                    if attack.iconid ~= '' then
                        m_attackIcons[string.lower(attack.name)] = attack.iconid
                    end
                end

                for j,attack in ipairs(entry.properties:try_get('innateActivatedAbilities', {})) do
                    if attack.iconid ~= '' then
                        m_attackIcons[string.lower(attack.name)] = attack.iconid
                    end
                end
            end
        end

        return m_attackIcons
    end,

    ParseCR = function(str)
        local i,j,num,denom = string.find(str, "(%d+)/(%d+)")
        if i ~= nil then
            return tonumber(num)/tonumber(denom)
        end

        i,j,num = string.find(str, "(%d+)")
        if i ~= nil then
            return tonumber(num)
        end

        return tonumber(str)
    end,

    --given a string like "120 fly 30 feet swim 40 feet" will return {"" = 120, fly = 30, swim = 40}
    ParseAttributeToNumberString = function(str)
        str = string.lower(str)

        local result = {}

        local i,j,startStr = string.find(str, "^(%d+) ")
        if startStr ~= nil then
            result[""] = tonumber(startStr)
        end


        local i,j,attrid,val = string.find(str, "(%a+) (%d+)")
        while attrid ~= nil do

            result[attrid] = tonumber(val)

            --a match (attrid ~= nil) always sets j.
            ---@cast j -nil
            str = string.sub(str, j, #str)
            i,j,attrid,val = string.find(str, "(%a+) (%d+)")
        end

        return result
    end,

    ParseRanges = function(desc)
        local result = {}
        local i1,i2,short,long = string.find(desc, 'range (%d+)/(%d+) ?ft')
        if i1 ~= nil then
            result[#result+1] = {
                type = "range",
                range = short,
                rangeDisadvantage = long,
            }
            dmhub.Debug(string.format("PARSE RANGE: %d, %d, %d, %d from %s TO RESULT %s", i1,i2,short,long, desc, dmhub.ToJson(result)))
        else

            i1,i2,short = string.find(desc, 'range (%d+) ?ft')
            if i1 ~= nil then
                result[#result+1] = {
                    type = "range",
                    range = short,
                }
            end
        end
        
        
        local i3,i4,reach = string.find(desc, 'reach (%d+) ?ft')
        if i3 ~= nil then
            dmhub.Debug(string.format("PARSE MELEE: %d,%d from %s", i3, reach, desc))
            result[#result+1] = {
                type = "melee",
                range = reach,
            }
        end

        if #result == 0 then
            dmhub.Debug("Could not parse range: " .. desc)
            result[#result+1] = {
                type = "melee",
                range = 5,
            }
        end

        return result
    end,


    ParseCSVDamage = function(action)

        local csvDamage = {}
        if action.damage == nil then
            return csvDamage
        end

        for i,damageInstance in ipairs(action.damage) do
            if damageInstance.damage_type then
                csvDamage[#csvDamage+1] = damageInstance.damage_dice
                csvDamage[#csvDamage+1] = damageInstance.damage_type.index
            end
        end

        return csvDamage
    end,

    ParseTargetShape = function(desc)
        desc = string.lower(desc)
        if string.find(desc, "melee weapon attack") ~= nil or string.find(desc, "melee spell attack") ~= nil or string.find(desc, "ranged weapon attack") ~= nil or string.find(desc, "ranged spell attack") ~= nil or string.find(desc, "weapon attack") ~= nil then
            return nil
        end
        if string.find(desc,"cone") then
            local i1,i2,range = string.find(desc, "(%d+)-foot cone")
            if i1 ~= nil then
                return {
                    targetType = "cone",
                    range = range,
                }
            else
                dmhub.Debug("Could not parse target shape (cone): " .. desc)
                return nil
            end
        elseif string.find(desc, " line") then
            local i1,i2,range,radius = string.find(desc, "(%d+)-foot line that is (%d+) f")
            if i1 == nil then
                i1,i2,range,radius = string.find(desc, "that is (%d+) ft. long and (%d+) ft. wide")
            end
            if i1 ~= nil then
                return {
                    targetType = "line",
                    range = range,
                    radius = radius,
                }
            end
        end
        
        if string.find(desc,"one target") or string.find(desc,"one creature") then
            local i1,i2,range = string.find(desc, "within (%d+) f")
            if i1 ~= nil then
                return {
                    targetType = "target",
                    range = range,
                }
            else
                dmhub.Debug("Could not parse target shape (target): " .. desc)
                return nil
            end
        elseif string.find(desc,"each creature") and string.find(desc, "choice") then
            local i1,i2,range = string.find(desc, "within (%d+) f")
            if i1 ~= nil then
                return {
                    targetType = "target",
                    range = range,
                    numTargets = 99,
                }
            else
                dmhub.Debug("Could not parse target shape (multi targets): " .. desc)
                return nil
            end
        elseif string.find(desc,"each creature") then
            local i1,i2,range = string.find(desc, "within (%d+) f")
            if i1 == nil then
                i1,i2,range = string.find(desc, "in a (%d+)-foot")
            end

            if i1 ~= nil then
                return {
                    targetType = "all",
                    range = range,
                }
            else
                dmhub.Debug("Could not parse target shape (all): " .. desc)
                return nil
            end
        end

        --dmhub.Debug("Could not parse target shape: recognize target type: " .. desc)
        return nil

    end,

    --ability that adds extra dice to melee attacks.
    CreateBruteAbility = function(ability)

        local featureGuid = dmhub.GenerateGuid()
        local feature = CharacterFeature.Create{
            guid = featureGuid,
            name = ability.name,
            description = ability.desc,
            modifiers = {
                CharacterModifier.new{
                    guid = dmhub.GenerateGuid(),
                    sourceguid = featureGuid,
                    name = ability.name,
                    source = ability.name,
                    description = ability.desc,

                    behavior = "damage",

                    damageFilterCondition = "Attack.Melee and self.Distance(Target) <= Attack.Melee Range",
                    modifyRoll = "extradie",
                }
            }
        }

        return feature
    end,


    --ability contains 'name' and 'desc' fields, both strings.
    CreateParryAbility = function(ability)
        local i1,i2,number = string.find(ability.desc, "(%d+)")
        number = tostring(number) or 2

        local behaviorGuid = dmhub.GenerateGuid()

        local triggeredAbility = TriggeredAbility.Create{
            name = "Parry",
            abilityType = "none",
            actionResourceId = "reaction",
            conditionFormula = string.format('outcome = "hit" and (Armor Class+%d) > Roll and Attack.Melee', number),
            description = ability.desc,
            trigger = "attacked",

            iconid = "4ea2f7d6-a30f-47f1-aa36-ca319b5c90f9",
            display = {
                bgcolor = "#ffffffff",
                brightness = 1,
                hueshift = 0,
                saturation = 1,
            },

            numTargets = "1",
            targetType = "self",
            range = 5,

            behaviors = {
                ActivatedAbilityApplyMomentaryEffectBehavior.new{
                    applyto = "caster",
                    name = "Parry",
                    momentaryEffect = CharacterOngoingEffect.Create{
                        guid = behaviorGuid,
                        id = behaviorGuid,
                        description = "",

                        iconid = "4ea2f7d6-a30f-47f1-aa36-ca319b5c90f9",
                        display = {
                            bgcolor = "#ffffffff",
                            brightness = 1,
                            hueshift = 0,
                            saturation = 1,
                        },

                        name = "Parry",
                        source = "Parry",

                        modifiers = {
                            CharacterModifier.new{
                                behavior = "attribute",
                                attribute = "armorClass",
                                guid = dmhub.GenerateGuid(),
                                name = "Parry",
                                source = "Parry",
                                sourceguid = behaviorGuid,
                                value = number,
                            }
                        }
                    }
                }
            }
        }

        local featureGuid = dmhub.GenerateGuid()
        local feature = CharacterFeature.Create{
            guid = featureGuid,
            name = ability.name,
            description = ability.desc,
            behavior = "trigger",
            modifiers = {
                CharacterModifier.new{
                    guid = dmhub.GenerateGuid(),
                    sourceguid = featureGuid,
                    name = ability.name,
                    source = ability.name,
                    description = ability.desc,

                    behavior = "trigger",

                    triggeredAbility = triggeredAbility,
                }
            }
        }

        return feature

    end,


}
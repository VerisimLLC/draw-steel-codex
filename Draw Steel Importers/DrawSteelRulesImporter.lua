local mod = dmhub.GetModLoading()

local function track(eventType, fields)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    fields.type = eventType
    fields.userid = dmhub.userid
    fields.gameid = dmhub.gameid
    fields.version = dmhub.version
    analytics.Event(fields)
end

local g_nameToExistingKitId = {}
local g_nameToExistingAbility = {}
local g_nameToExistingManeuver = {}

local g_nameToExistingClassId = {}

local function InitParser()
    local t = dmhub.GetTable(Kit.tableName)
    for k, v in pairs(t) do
        g_nameToExistingKitId[string.lower(v.name)] = k
        if v.signatureAbility ~= false then
            g_nameToExistingAbility[string.lower(v.signatureAbility.name)] = v.signatureAbility
        end

        if v:has_key("kitManeuverAbility") then
            g_nameToExistingManeuver[string.lower(v.kitManeuverAbility.name)] = v.kitManeuverAbility
        end
    end

    local t = dmhub.GetTable(Class.tableName)
    for k, v in pairs(t) do
        g_nameToExistingClassId[string.lower(v.name)] = k
    end
end

local ImportClass

import.Register{
    id = "mcdmkits",
    description = "MCDM Rules",
    --input = "docx",
    input = "plaintext",
    priority = 200,

    renderLog = MCDMImporter.renderLog,

    text = function(importer, text)
        InitParser()

        text = MCDMImporter.ReplaceSpecialCharactersWithASCII(text)

        local sections = {}
        local currentSection = nil

        for sline in string.gmatch(text, "([^\r\n]*)\r?\n") do
            if regex.MatchGroups(sline, "^Kits$") ~= nil then
                currentSection = "kits"
                print("KITS:: FOUND")
            elseif regex.MatchGroups(sline, "^Classes$") ~= nil then
                currentSection = "classes"
                print("CLASSES:: FOUND")
            elseif currentSection ~= nil then
                sections[currentSection] = sections[currentSection] or {}
                local lines = sections[currentSection]
                lines[#lines+1] = sline
            end
        end

        for sectionid,lines in pairs(sections) do
            print("SECTION::", sectionid, #lines)
        end

        local mode = "classes"
        local newParagraph = false

        local subclassName = nil
        local classes = {}
        local currentClass = nil
        local currentClassMode = nil
        local currentLevel = nil

        print("CLASSES:: COUNT", #sections.classes or 0)
        for lineNum,sline in ipairs(sections.classes or {}) do

            sline = trim(sline)

            local skipping = false
            local className = regex.MatchGroups(sline, "^(?<className>[A-Za-z]+)$")
            if className ~= nil and #className.className > 3 and #className.className < 16 then
                --search ahead 5 lines to find the 'Basics' section.
                local foundBasics = false
                for j=1,5 do
                    local nextLine = sections.classes[lineNum+j]

                    if nextLine ~= nil and regex.MatchGroups(trim(nextLine), "^Basics$") ~= nil then
                        foundBasics = true
                        break
                    end
                end

                if not foundBasics then
                    className = nil
                end
            end

            if className ~= nil and #className.className > 3 and #className.className < 16 then
                print("CLASSES:: PARSE", className.className)
                currentClass = {name = className.className, existingid = g_nameToExistingClassId[string.lower(className.className)], flavor = {}, basics = {}, features = {}, abilities = {}}
                classes[className.className] = currentClass
                currentClassMode = "flavor"
                skipping = true
            end

            if regex.MatchGroups(sline, "^Basics$") ~= nil then
                currentClassMode = "basics"
                skipping = true
            elseif currentClass ~= nil and regex.MatchGroups(sline, "^.*Level Features.*$") ~= nil then
                currentClassMode = "features"

                local levelMatch = regex.MatchGroups(sline, "^(?<level>[0-9]+)[a-z][a-z]-Level Features$")
                if levelMatch ~= nil then
                    currentLevel = tonumber(levelMatch.level)
                    currentClassMode = "features"
                end


            elseif currentClass ~= nil and regex.MatchGroups(sline, "^" .. currentClass.name .. " Abilities$") ~= nil then
                currentClassMode = "abilities"
                skipping = true
                if currentClass ~= nil then
                    print("CLASSES:: found abilities for", currentClass.name)
                end
            elseif currentLevel ~= nil and currentLevel > 1 and currentClass ~= nil and regex.MatchGroups(sline, "^[0-9]+-[A-Za-z]+ Abilit(y|ies)$") ~= nil then
                currentClassMode = "abilities"
                skipping = false

                local lines = currentClass[currentClassMode] or {}
                currentClass[currentClassMode] = lines
                lines[#lines+1] = string.format("__Level %d", currentLevel)
                print("CLASS:: Abilities for level", currentLevel, "for", currentClass.name)

            elseif currentLevel ~= nil and currentLevel > 1 and currentClass ~= nil and regex.MatchGroups(sline, "^[0-9]+[a-z][a-z]-Level [A-Za-z ]+ Abilit(ies|y)$") then
                local subclassNameMatch = regex.MatchGroups(sline, "^(?<level>[0-9]+[a-z][a-z])-Level (?<subclass>[A-Za-z ]+) Abilit(ies|y)$")
                currentClassMode = "abilities"
                skipping = true

                local subclassid = nil

                local t = dmhub.GetTable("subclasses")
                for key,v in unhidden_pairs(t) do
                    if string.find(string.lower(v.name), string.lower(subclassNameMatch.subclass)) ~= nil then
                        subclassid = key
                        print("CLASS:: Match subclass for heroic abilities", v.name, subclassNameMatch.subclass)
                        found = true
                        break
                    end
                end


                if subclassid ~= nil then
                    local lines = currentClass[currentClassMode] or {}
                    currentClass[currentClassMode] = lines
                    lines[#lines+1] = string.format("__Level %d", currentLevel)
                    lines[#lines+1] = string.format("__Subclass %s", subclassid)
                end

            elseif currentClass ~= nil and regex.MatchGroups(sline, "^" .. currentClass.name .. " Advancement") ~= nil then
                currentClassMode = "advancement"
                skipping = true

                local subclassNameMatch = regex.MatchGroups(sections.classes[lineNum+1], "^\\|Level\\|Features\\|Abilities\\|(?<subclass>.*) Abilities$")
                if subclassNameMatch ~= nil then
                    subclassName = subclassNameMatch.subclass
                else
                    subclassName = "Specialization"
                end

                print("CLASSES:: Subclass for", currentClass.name, "is", subclassName)
            end

            if (not skipping) and currentClass ~= nil then
                local lines = currentClass[currentClassMode] or {}
                currentClass[currentClassMode] = lines
                lines[#lines+1] = sline
            end

            if regex.MatchGroups(sline, "^$") ~= nil then
                newParagraph = true
            else
                newParagraph = false
            end
        end

        local classCount = 0
        for classid,classInfo in pairs(classes) do
            print("CLASSES:: IMPORT:", classInfo.name, "flavor=", #classInfo.flavor, "basics=", #classInfo.basics, "features=", #classInfo.features, "abilities=", #classInfo.abilities)
            ImportClass(import, classInfo)
            classCount = classCount + 1
        end

        mode = "kits"

        local kitType = nil
        local kitInfo = {}
        local currentKit = nil
        local kitCount = 0

        for _,sline in ipairs(sections.kits or {}) do
            if mode == "kitStats" then
                if regex.MatchGroups(sline, "^Signature Ability$") ~= nil then
                    mode = "kitAbility"
                else
                    currentKit.statsLines[#currentKit.statsLines+1] = sline
                end

            elseif mode == "kitAbility" then
                if regex.MatchGroups(sline, "^You gain the following signature ability") ~= nil then
                    --pass. This line shouldn't be present?
                elseif regex.MatchGroups(sline, "^[^<]") ~= nil and #currentKit.abilityLines > 3 then
                    mode = "kits"
                    print(string.format("Parsed kit: %s (%s): %d / %d / %s", currentKit.name, currentKit.type, #currentKit.statsLines, #currentKit.abilityLines, json(currentKit.abilityLines)))
                    import:Log(string.format("Parsed kit: %s (%s): %d / %d", currentKit.name, currentKit.type, #currentKit.statsLines, #currentKit.abilityLines))
                    currentKit = nil
                else
                    currentKit.abilityLines[#currentKit.abilityLines+1] = sline
                end
            end
            
            if mode == "kits" then
                --local t = regex.MatchGroups(sline, "^(?<kitType>Martial|Caster) Kits$")
                local t = regex.MatchGroups(sline, "^Kits A to Z$")
                if t ~= nil then
                    kitType = "martial" --string.lower(t.kitType)
                    print("KITS:: FOUND KIT TYPE", kitType)
                elseif kitType ~= nil then
                    t = regex.MatchGroups(sline, "^(?<kitName>[A-Za-z -]{3,24})$")
                    if t ~= nil then
                        kitInfo[#kitInfo+1] = {
                            name = t.kitName,
                            type = kitType,
                            statsLines = {},
                            abilityLines = {},
                        }

                        print("KITS:: FOUND KIT", t.kitName)

                        currentKit = kitInfo[#kitInfo]
                        mode = "kitStats"
                    end
                end

            elseif mode == "finished" then
            end
        end

        --the last kit didn't complete so it's not a valid kit. Remove it.
        kitInfo[#kitInfo] = nil

        for i,kit in ipairs(kitInfo) do
            local bookmark = import:BookmarkLog()

            local newKit = Kit.CreateNew()

            print("KITS:: IMPORT", kit.name, kit.type, #kit.statsLines, #kit.abilityLines)

            newKit.name = kit.name
            newKit.type = kit.type

            local importGuid

            local existingKitId = g_nameToExistingKitId[string.lower(kit.name)]
            if existingKitId ~= nil then
                local existingKit = dmhub.GetTable(Kit.tableName)[existingKitId]
                importGuid = existingKit:try_get("imported")
                newKit.portraitid = existingKit.portraitid
            end

            if importGuid == nil then
                importGuid = dmhub.GenerateGuid()
            end

            newKit.imported = importGuid

            local description = {}
            local equipment = {}
            local bonuses = {}

            local categories = {Equipment = equipment, ["Kit Bonuses"] = bonuses}
            local curEntry = description

            for _,line in ipairs(kit.statsLines) do
                local modeMatch = regex.MatchGroups(line, "^(?<mode>Equipment|Kit Bonuses)$")
                if modeMatch ~= nil then
                    curEntry = categories[modeMatch.mode]
                else
                    curEntry[#curEntry+1] = line
                end
            end

            newKit.description = table.concat(description, "\n")
            newKit.equipmentDescription = table.concat(equipment, "\n")

            local function ParseNumericBonus(match, attrid)
                local numMatch = regex.MatchGroups(match.value, "^\\+?(?<num>[0-9]+)( *per echelon)?$")
                if numMatch == nil then
                    import:Log(string.format("Unrecognized %s: %s", match.attr, match.value))
                else
                    rawset(newKit, attrid, tonumber(numMatch.num))
                end
            end

            for _,line in ipairs(bonuses) do
                line = regex.ReplaceAll(line, "</b>\\s*<b>", "")
                local bonusMatch = regex.MatchGroups(line, "^<b>\\s*(?<attr>[a-zA-Z ]+)\\s*:\\s*</b>\\s*(?<value>.*?)\\s*$")
                if bonusMatch ~= nil then
                    local attr = string.lower(bonusMatch.attr)
                    local damageTypeMatch = regex.MatchGroups(attr, "^(?<attr>supernatural|melee|ranged) (weapon )?(damage|attack) bonus$")


                    if damageTypeMatch ~= nil then
                        local damageMatch = regex.MatchGroups(bonusMatch.value, Kit.damageBonusMatchPattern)
                        if damageMatch == nil then
                            import:Log(string.format("Unrecognized %s: %s", bonusMatch.attr, line))
                        else
                            newKit:DamageBonuses()[string.lower(damageTypeMatch.attr)] = {tonumber(damageMatch.tier1), tonumber(damageMatch.tier2), tonumber(damageMatch.tier3)}
                        end
                    elseif attr == "stamina bonus" then
                        ParseNumericBonus(bonusMatch, "health")
                    elseif attr == "speed bonus" then
                        ParseNumericBonus(bonusMatch, "speed")
                    elseif attr == "reach bonus" or attr == "melee distance bonus" then
                        ParseNumericBonus(bonusMatch, "reach")
                    elseif attr == "ranged distance bonus" then
                        ParseNumericBonus(bonusMatch, "range")
                    elseif attr == "area bonus" then
                        ParseNumericBonus(bonusMatch, "area")
                    elseif attr == "stability bonus" then
                        ParseNumericBonus(bonusMatch, "stability")
                    elseif attr == "disengage bonus" then
                        ParseNumericBonus(bonusMatch, "disengage")
                    else
                        import:Log(string.format("Unknown kit bonus: %s", line))
                    end

                end
            end

            local abilities = {}
            MCDMImporter.ParseCreatureAbilities(nil, kit.abilityLines, g_nameToExistingAbility, abilities)

            if #abilities == 0 then
                import:Log(string.format("In kit %s an ability could not be recognized.", kit.name))
                print("In kit " .. kit.name .. " an ability could not be recognized: ", kit.abilityLines)
            elseif #abilities > 1 then
                import:Log(string.format("In kit %s, multiple abilities were detected.", kit.name))
                print("In kit " .. kit.name .. " have " .. #abilities .. " ability")
                newKit.signatureAbility = abilities[1]
                newKit.signatureAbility:AddKeyword("Kit")
            else
                newKit.signatureAbility = abilities[1]
                newKit.signatureAbility:AddKeyword("Kit")
                print("In kit " .. kit.name .. " have an ability")
            end

            newKit.kitManeuver = false


            import:StoreLogFromBookmark(bookmark, newKit)
            import:ImportAsset(Kit.tableName, newKit)
            kitCount = kitCount + 1
        end

        if classCount > 0 then
            track("rules_import", {
                contentType = "classes",
                count = classCount,
                dailyLimit = 3,
            })
        end
        if kitCount > 0 then
            track("rules_import", {
                contentType = "kits",
                count = kitCount,
                dailyLimit = 3,
            })
        end
    end,
}

--@param level integer
--@param featureName string|string[]
--@return integer
local function GetImportedFeatureIndex(level, featureName)
    local featureNames = {}
    if type(featureName) == "table" then
        featureNames = featureName
    else
        featureNames[1] = featureName
    end
    for i,feature in ipairs(level.features) do
        local match = false
        for _,name in ipairs(featureNames) do
            if string.lower(feature.name) == string.lower(name) then
                match = true
                break
            end
        end
        if match and feature:try_get("imported", false) then
            if feature:try_get("importOverride", false) then
                return nil
            end
            return i
        end
    end

    return #level.features+1
end

local ExtractAbilities
ExtractAbilities = function(t, result)
    if type(t) ~= "table" then
        return
    end
    if t.typeName == "ActivatedAbility" and rawget(t, "name") ~= nil then
        result[string.lower(rawget(t, "name"))] = t
        return
    end

    for k,v in pairs(t) do
        ExtractAbilities(v, result)
    end
end

ImportClass = function(import, classInfo)
    local importGuid = dmhub.GenerateGuid()

    local bookmark = import:BookmarkLog()

    local classTable = dmhub.GetTable(Class.tableName)
    local existingClass = nil

    local existingClassAbilities = {}

    if classInfo.existingid ~= nil then
        existingClass = classTable[classInfo.existingid]
        ExtractAbilities(existingClass, existingClassAbilities)
    end

    local newClass
    if existingClass ~= nil then
        newClass = DeepCopy(existingClass)
    else
        newClass = Class.CreateNew{
            id = dmhub.GenerateGuid(),
        }
    end

    newClass.name = classInfo.name

    local level = newClass:GetLevel(1)

    local basicsMap = {}

    for _,line in ipairs(classInfo.basics) do
        print("CLASS:: BASICS", newClass.name, " :: ", line)

        local match = regex.MatchGroups(line, "^<b>\\s*(?<attr>[a-zA-Z0-9 ]+)\\s*:\\s*</b>\\s*(?<value>.*?)\\s*$")
        if match ~= nil then
            basicsMap[string.lower(match.attr)] = match.value
        end
    end

    local staminaAttr = "starting stamina at 1st level"
    local characteristicsAttr = "starting characteristics"
    local recoversAttr = "recoveries"
    local skillsAttr = "skills"

    local staminaValue = basicsMap[staminaAttr]
    local characteristicsValue = basicsMap[characteristicsAttr]
    local recoversValue = basicsMap[recoversAttr]
    local skillsValue = basicsMap[skillsAttr]

    if staminaValue == nil then
        import:Log("No stamina value found for class " .. newClass.name)
    else
        newClass.hitpointsCalculation = staminaValue
    end

    if characteristicsValue == nil then
        import:Log("No characteristics value found for class " .. newClass.name)
    else
    end

    if recoversValue == nil then
        import:Log("No recovers value found for class " .. newClass.name)
        print("CLASS:: Recoveries not found")
    else
        local recoveriesTemplate = MCDMImporter.GetStandardFeature("Recoveries")
        if recoveriesTemplate ~= nil and getmetatable(recoveriesTemplate) == nil then
            print("ERROR:: NO META on recoveriesTemplate from GetStandardFeature('Recoveries'):", json(recoveriesTemplate))
        end
        local newFeature = DeepCopy(recoveriesTemplate)
        if getmetatable(newFeature) == nil then
            print("ERROR:: NO META on DeepCopy of recoveriesTemplate:", json(newFeature))
        end
        newFeature.imported = importGuid
        MCDMUtils.DeepReplace(newFeature, "<<quantity>>", recoversValue)

        local index = GetImportedFeatureIndex(level, "Recoveries")
        if index ~= nil then
            --an index of nil means that this feature is protected from import so we'll just drop it.
            level.features[index] = newFeature
            print("CLASS:: Recoveries: Set to ", recoversValue, "//", newFeature ~= nil, "at index", index, "for class", newClass.name)
        else
            print("CLASS:: Recoveries: overridden so not importing.")
        end

    end

    if skillsValue == nil then
        import:Log("No skills value found for class " .. newClass.name)
    else
    end

    local abilityTarget = nil
    local signatureAbilityLines = {}
    local heroicAbilityByCostInfo = {}
    local heroicAbilityMode = false

    local signatureAbilityFeatureName = "Signature Ability"
    local signatureAbilityDescription = ""

    local currentLevel = nil

    for i,line in ipairs(classInfo.abilities) do
        local levelMatch = regex.MatchGroups(line, "^__Level (?<level>[0-9]+)$")
        local subclassMatch = regex.MatchGroups(line, "^__Subclass (?<subclass>.+)$")
        if levelMatch ~= nil then
            currentLevel = tonumber(levelMatch.level)
        elseif regex.MatchGroups(line, "^Signature Ability$") ~= nil or regex.MatchGroups(line, "^Signature Abilities$") ~= nil then
            abilityTarget = signatureAbilityLines 
            signatureAbilityDescription = classInfo.abilities[i+1]

            if regex.MatchGroups(line, "^Signature Abilities$") ~= nil then
                signatureAbilityFeatureName = "Signature Abilities"
            end
        elseif regex.MatchGroups(line, "^Heroic Abilities$") ~= nil then
            abilityTarget = nil
            heroicAbilityMode = true
        elseif heroicAbilityMode and regex.MatchGroups(line, "^(?<cost>\\d+-.*) Abilit(y|ies)$") ~= nil then
            abilityTarget = {}
            local info = {cost = regex.MatchGroups(line, "^(?<cost>\\d+-.*) Abilit(y|ies)$").cost, level = currentLevel, lines = abilityTarget}
            heroicAbilityByCostInfo[#heroicAbilityByCostInfo+1] = info
        elseif heroicAbilityMode and subclassMatch ~= nil then
            local t = dmhub.GetTable("subclasses")
            local subclass = t[subclassMatch.subclass]
            abilityTarget = {}
            local info = {cost = subclass.name, level = currentLevel, subclass = subclass, lines = abilityTarget}
            heroicAbilityByCostInfo[#heroicAbilityByCostInfo+1] = info
            print("CLASS:: parse abilities info =", info)

        elseif abilityTarget ~= nil then
            --local heroicNameMatch = regex.MatchGroups(line, "^(?<name>.+) \\(\\d+ [a-zA-Z]+\\)$")
            abilityTarget[#abilityTarget+1] = line
        end
    end

    print("CLASS:: parse abilities", classInfo.name, "parse abilities", #signatureAbilityLines, #heroicAbilityByCostInfo)

    local abilityTemplate = MCDMImporter.GetStandardFeature("Ability")
    if abilityTemplate ~= nil and getmetatable(abilityTemplate) == nil then
        print("ERROR:: NO META on abilityTemplate from GetStandardFeature('Ability'):", json(abilityTemplate))
    end

    local signatureAbilities = {}
    local heroicAbilities = {}

    MCDMImporter.ParseCreatureAbilities(nil, signatureAbilityLines, existingClassAbilities, signatureAbilities)

    local count = 0
    for _,heroicAbilityEntry in ipairs(heroicAbilityByCostInfo) do
        local choicePrompt = heroicAbilityEntry.lines[1]
        table.remove(heroicAbilityEntry.lines, 1)

        local newAbilities = {}
        MCDMImporter.ParseCreatureAbilities(nil, heroicAbilityEntry.lines, existingClassAbilities, newAbilities)
        heroicAbilities[#heroicAbilities+1] = newAbilities
        count = count + #newAbilities

        local level = newClass:GetLevel(heroicAbilityEntry.level or 1)

        if heroicAbilityEntry.subclass ~= nil then
            level = heroicAbilityEntry.subclass:GetLevel(heroicAbilityEntry.level or 1)
        end

        local choiceName = string.format("%s Heroic Abilities", heroicAbilityEntry.cost)
        local heroicAbilityIndex = GetImportedFeatureIndex(level, choiceName)
        if heroicAbilityIndex ~= nil then
            local existingChoice = level.features[heroicAbilityIndex]

            local heroicAbilityOptions = {}

            for _,ability in ipairs(newAbilities) do
                local feature = DeepCopy(abilityTemplate)
                if getmetatable(feature) == nil then
                    print("ERROR:: NO META on DeepCopy of abilityTemplate (heroic):", ability.name, json(feature))
                end

                ability.categorization = "Heroic Ability"

                feature.id = dmhub.GenerateGuid()
                feature.guid = feature.id

                if existingChoice ~= nil then
                    for _,existingOption in ipairs(existingChoice.options) do
                        if string.lower(existingOption.name) == string.lower(ability.name) then
                            feature.id = existingOption.id
                            feature.guid = existingOption.guid
                            break
                        end
                    end
                end

                feature.imported = importGuid
                feature.name = ability.name
                feature.modifiers[1].activatedAbility = DeepCopy(ability)

                heroicAbilityOptions[#heroicAbilityOptions+1] = feature
            end

            if existingChoice ~= nil and existingChoice:has_key("options") then
                for i,option in ipairs(existingChoice.options) do
                    if option:try_get("importOverride", false) then
                        --set to override imports so keep this alive.
                        local insertIndex = #heroicAbilityOptions+1
                        for j,newOption in ipairs(heroicAbilityOptions) do
                            if newOption.name == option.name then
                                insertIndex = j
                                break
                            end
                        end

                        heroicAbilityOptions[insertIndex] = option
                    end
                end
            end
            
            local newHeroicAbilityChoice = CharacterFeatureChoice.CreateNew{
                name = choiceName,
                description = choicePrompt,
                imported = importGuid,
                options = heroicAbilityOptions,
            }

            print("CLASS:: Match ability =", choiceName)

            if existingChoice ~= nil then
                newHeroicAbilityChoice.guid = existingChoice.guid
            end

            level.features[heroicAbilityIndex] = newHeroicAbilityChoice
        end

    end

    local signatureAbilityIndex = GetImportedFeatureIndex(level, {"Signature Ability", "Signature Abilities"})
    if signatureAbilityIndex ~= nil then
        local existingSignature = level.features[signatureAbilityIndex]

        local signatureAbilityOptions = {}

        for _,ability in ipairs(signatureAbilities) do
            local feature = DeepCopy(abilityTemplate)
            if getmetatable(feature) == nil then
                print("ERROR:: NO META on DeepCopy of abilityTemplate (signature):", ability.name, json(feature))
            end

            feature.id = dmhub.GenerateGuid()
            feature.guid = feature.id

            if existingSignature ~= nil then
                for _,existingOption in ipairs(existingSignature.options) do
                    if string.lower(existingOption.name) == string.lower(ability.name) then
                        feature.id = existingOption.id
                        feature.guid = existingOption.guid
                        break
                    end
                end
            end


            feature.imported = importGuid
            feature.name = ability.name
            feature.modifiers[1].activatedAbility = DeepCopy(ability)


            if existingSignature ~= nil then
                --if we have an existing signature abilities feature and it has
                --an ability of the same name that has an import override, then use that instead.
                local existingOptions = existingSignature:try_get("options")
                if existingOptions ~= nil then
                    for i,option in ipairs(existingOptions) do
                        if option.name == feature.name and option:try_get("importOverride", false) then
                            print("Signature ability", option.name, "has an override so ignoring import.")
                            feature = DeepCopy(option)
                            break
                        end
                    end
                end
            end


            signatureAbilityOptions[#signatureAbilityOptions+1] = feature
        end

        if existingSignature ~= nil and existingSignature:has_key("options") then
            for i,option in ipairs(existingSignature.options) do
                if option:try_get("importOverride", false) then
                    --set to override imports so keep this alive.
                    local insertIndex = #signatureAbilityOptions+1
                    for j,newOption in ipairs(signatureAbilityOptions) do
                        if newOption.name == option.name then
                            insertIndex = j
                            break
                        end
                    end

                    signatureAbilityOptions[insertIndex] = option
                end
            end
        end


        local numChoices = 1
        if regex.MatchGroups(signatureAbilityDescription, "select two") ~= nil then
            numChoices = 2
        end

        local newSignatureAbilityChoice = CharacterFeatureChoice.CreateNew{
            name = signatureAbilityFeatureName,
            description = signatureAbilityDescription,
            numChoices = numChoices,
            imported = importGuid,
            options = signatureAbilityOptions,
        }

        if existingSignature ~= nil then
            newSignatureAbilityChoice.guid = existingSignature.guid
        end

        level.features[signatureAbilityIndex] = newSignatureAbilityChoice
    end




    print("CLASS:: ABILITIES", newClass.name, #signatureAbilities, #heroicAbilities, count)


    --purge any old imported features
    local newFeatures = {}
    for _,feature in ipairs(level.features) do
        if feature:try_get("imported") == nil or feature.imported == importGuid then
            newFeatures[#newFeatures+1] = feature
        end
    end

    level.features = newFeatures

    import:StoreLogFromBookmark(bookmark, newClass)
    import:ImportAsset(Class.tableName, newClass)
end

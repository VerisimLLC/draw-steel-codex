print("Draw Steel Monster Importer Script Loading...")
local mod = dmhub.GetModLoading()

local function escapeNonAsciiChars(inputString)
    return (inputString:gsub("([\128-\255])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

MCDMImporter = {
    ReplaceSpecialCharactersWithASCII = function(text)
        -- Replace curly apostrophes (U+2018) and (U+2019) with ASCII apostrophe (')
        text = text:gsub("\xE2\x80\x98", "'") -- Replace left curly apostrophe
        text = text:gsub("\xE2\x80\x99", "'") -- Replace right curly apostrophe
        text = text:gsub("\xE2\x80\x9C", '"') -- Replace double quotes
        text = text:gsub("\xE2\x80\x9D", '"') -- Replace double quotes
        text = text:gsub("\xEF\xBF\xBD", "'") -- The replacement character
        text = text:gsub("\xCA\xBC", "'") -- Replace U+02BC MODIFIER LETTER APOSTROPHE with regular apostrophe
        text = text:gsub("\r", "") --get rid of evil \r
        text = escapeNonAsciiChars(text)

        text = text:gsub("%%F0%%9F%%9B%%A1%%EF%%B8%%8F", ":shield:")
        text = text:gsub("%%EF%%B8%%8F", ":shield:")
        text = text:gsub("%%E2%%9A%%A1", ":surge:")
        text = text:gsub("%%E2%%80%%A6", "...")
        text = text:gsub("%%CA%%BC", "'") -- Replace encoded U+02BC MODIFIER LETTER APOSTROPHE

        -- Replace encoded modifier apostrophe using regex
        text = regex.ReplaceAll(text, "%CA%BC", "'")

        --replace non-breaking spaces.
        text = regex.ReplaceAll(text, "(%C2%A0)+$", "")
        text = regex.ReplaceAll(text, "%C2%A0", " ")

        return text
    end,

    renderLog = function(log)
        log = log or {}
        return gui.TooltipFrame(
            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "vertical",
                styles = {
                    Styles.Default,
                    {
                        selectors = {"label"},
                        fontSize = 14,
                        width = "100%",
                        height = "auto",
                    },
                    {
                        selectors = {"error"},
                        color = "red",
                    },
                    {
                        selectors = {"note"},
                        color = "#aaaaaa",
                    },
                    {
                        selectors = {"impl"},
                        color = "yellow",
                    },
                    {
                        selectors = {"override"},
                        color = "#ff8800",
                    },
                    {
                        selectors = {"good"},
                        color = "#00ff00",
                    },
                },

                create = function(element)
                    local inputPanel = nil
                    local diagnosticPanel = nil
                    local currentPanel = nil
                    local children = {}
                    if #log > 0 and log[1] ~= "-" then
                        table.insert(log, 1, "-")
                    end

                    for _,entry in ipairs(log) do
                        if entry == "-" or entry == "--" then
                            inputPanel = gui.Panel{
                                width = 590,
                                height = "auto",
                                flow = "vertical",
                                halign = "left",
                                vmargin = cond(entry == "-", 2, 6),
                            }
                            diagnosticPanel = gui.Panel{
                                width = 290,
                                height = "auto",
                                flow = "vertical",
                                halign = "right",
                            }
                            currentPanel = gui.Panel{
                                width = 900,
                                height = "auto",
                                flow = "horizontal",
                                inputPanel,
                                diagnosticPanel,
                            }
                            children[#children+1] = currentPanel
                        elseif type(entry) == "string" then
                            inputPanel:AddChild(gui.Label{
                                text = entry,
                                gui.Button{
                                    classes = {"copyButton", "sizeXxs"},
                                    halign = "right",
                                    valign = "center",
                                    click = function(element)
                                        gui.Tooltip{text = "Copied to Clipboard", valign = "top", borderWidth = 0}(element)
                                        dmhub.CopyToClipboard(entry)
                                    end,
                                }
                            })
                        else
                            diagnosticPanel:AddChild(gui.Label{
                                classes = {entry.status},
                                text = "<i>" .. entry.message .. "</i>",
                            })
                        end
                    end

                    element.children = children
                end,
            },
            {
                halign = "right",
                valign = "center",
            }
        )
    end,

    GetStandardAbility = function(name)
        name = string.lower(name)
        local abilityTable = dmhub.GetTable("standardAbilities")
        for key,ability in pairs(abilityTable) do
            if string.lower(ability.name) == name then
                return ability
            end
        end

        return nil
    end,

    GetStandardFeature = function(name)
        name = string.lower(name)
        local featuresTable = dmhub.GetTable("importerStandardFeatures")
        for key,feature in pairs(featuresTable) do
            if string.lower(feature.name) == name then
                if getmetatable(feature) == nil then
                    print("ERROR:: NO META on standard feature from table:", feature.name, "key:", key)
                end
                return feature
            end
        end

        print("Failed to find standard feature:", name)

        return nil
    end,
}

local function ParseMonsterHeader(str)
    local match = regex.MatchGroups(str, "^(?<name>.+?)\\s+(Level|Lvl) (?<level>\\d+(/\\d+)?)\\s+(?<role>.*)")
    if match ~= nil then
        printf("Importing monster: Parse header: (%s)", json(match.name))
    end
    return match
end

local descriptionsToIds = {}

local function InitParser()
    for k,m in pairs(assets.monsters) do
        if (not m.hidden) and m.properties:try_get("monster_type") ~= nil then
            descriptionsToIds[trim(m.properties.monster_type)] = k
            printf("Importing monster: existing: %s -> (%s) trimmed to (%s) / %s", k, json(m.properties.monster_type), trim(m.properties.monster_type), json(k))
        elseif m.hidden and m.properties:try_get("monster_type") ~= nil then
            print("Importing monster: hidden", k, json(m.properties.monster_type))
        else
            print("Importing monster: no monster_type", k)
        end
    end
end

function trimTrailingWhitespace(str)
    return (string.gsub(str, "%s*$", ""))
end

local function startsWith(str, substring)
    return string.sub(str, 1, string.len(substring)) == substring
end

local function StatusToColor(status)
    local color = "#00ff00"
    if status == "ignore" then
        color = "#aaaaaa"
    elseif status == "error" then
        color = "#ff0000"
    elseif status == "impl" then
        color = "#ffff00"
    elseif status == "good" then
        color = "#00ff00"
    elseif status == "override" then
        color = "#ff8800"
    end
    return color
end

local function FormatStatus(msg, status)
    return string.format("<color=%s>%s</color>", StatusToColor(status), msg)
end

local function FormatError(msg)
    return { status = "error", message = msg }
end

local function FormatNote(msg)
    return { status = "note", message = msg }
end

local function FormatSuccess(msg)
    return { status = "good", message = msg }
end

local function FormatImpl(msg)
    return { status = "impl", message = msg }
end

local function FormatOverride(msg)
    return { status = "override", message = msg }
end



local function ParseHeaderAttributesLine(bestiaryEntry, m, text)
    text = text:gsub("<[^>]+>", "")

    local logOutput = {}
    local errors = {}
    local notes = {}
    local items = string.split(text, "|")

    for i=1,#items,2 do
        local status = "success"
        local key = trim(items[i])
        local value = items[i+1]

        if key == "Health" or key == "Stamina" then
            if tonumber(value) == nil then
                errors[#errors+1] = "Stamina: Expected a number"
                status = "error"
            else
                m.max_hitpoints_roll = value
                m.max_hitpoints = tonumber(value)
            end
            
        elseif key == "Stability" then
            m.stability = tonumber(value) or 0
        elseif key == "Size" then
            if string.starts_with(value, "2") then
                m.creatureSize = "Large"
            elseif string.starts_with(value, "3") then
                m.creatureSize = "Huge"
            elseif string.starts_with(value, "4") then
                m.creatureSize = "Gargantuan"
            else
                m.creatureSize = "Medium"
            end
        elseif key == "Winded" then
            status = "ignore"
            notes[#notes+1] = "Winded is redundant; calculated from health"
        elseif key == "Damage Threshold" then
            m.damageThreshold = tonumber(value)
        elseif key == "Weight" then
            m.weight = tonumber(value)
        elseif key == "Reach" then
            m.reach = tonumber(value)
        elseif key == "Speed" then
            if not regex.Match(value, "^ *[0-9]+ *$") then
                local match, speed, moveType = regex.Match(value, "^ *([0-9]+) \\(([a-zA-Z]+)\\) *$")
                if match == nil then
                    status = "error"
                    errors[#errors+1] = "Speed: unrecognized format."
                elseif moveType ~= "fly" and moveType ~= "climb" and moveType ~= "swim" then
                    status = "error"
                    errors[#errors+1] = "Unrecognized movement type: " .. moveType
                end
            end

            m.movementSpeeds = {}
            local num = string.match(value, "%d+")
            if num ~= nil then
                m.walkingSpeed = tonumber(num)

                if string.find(value, "fly") ~= nil then
                    m.movementSpeeds.fly = m.walkingSpeed
                end

                if string.find(value, "climb") ~= nil then
                    m.movementSpeeds.climb = m.walkingSpeed
                end

                if string.find(value, "swim") ~= nil then
                    m.movementSpeeds.swim = m.walkingSpeed
                end

            else
                status = "error"
                errors[#errors+1] = "Speed: Expected a number"
            end

        elseif key == "Opportunity Attack" then
            m.opportunityAttack = value
        elseif key == "Grapple/Knockback TN" then
            status = "ignore"
            notes[#notes+1] = "Grapple/Knockback TN is redundant; calculated from might"
        elseif key == "Characteristics" then
        elseif key == "Might" then
            m.attributes["mgt"] = { baseValue = tonumber(value) }
        elseif key == "Agility" then
            m.attributes["agl"] = { baseValue = tonumber(value) }
        elseif key == "Endurance" then
            m.attributes["end"] = { baseValue = tonumber(value) }
        elseif key == "Reason" then
            m.attributes["rea"] = { baseValue = tonumber(value) }
        elseif key == "Intuition" then
            m.attributes["inu"] = { baseValue = tonumber(value) }
        elseif key == "Presence" then
            m.attributes["prs"] = { baseValue = tonumber(value) }
        else
            status = "error"
            errors[#errors+1] = "Unknown characteristic: " .. json(key)
        end

        logOutput[#logOutput+1] = FormatStatus(items[i], status)
        logOutput[#logOutput+1] = FormatStatus(items[i+1], status)
    end

    import:Log("--")
    import:Log(table.concat(logOutput, "|"))
    for _,error in ipairs(errors) do
        import:Log(FormatError(error))
    end
    for _,note in ipairs(notes) do
        import:Log(FormatNote(note))
    end
end

local function ParseSkillsLine(bestiaryEntry, m, text)
    text = text:gsub("<[^>]+>", "")

    local skills_str = text:match("Skills %(%+1 Boon to Tests%):(.*)")

    if not skills_str then
        import:Log("-")
        import:Log(FormatStatus(text, "error"))
        import:Log(FormatError("Unrecognized skills"))
        return nil
    end

    local skills = {}
    -- Split the string by commas
    for skill in skills_str:gmatch("[^,]+") do
        -- Trim whitespace
        skill = skill:match("^%s*(.-)%s*$")
        
        -- Check for specialty
        local skill_name, specialty = skill:match("^(.-)%s*%((.-)%)$")
        
        if skill_name then
            -- Skill with specialty
            table.insert(skills, {skill = skill_name, specialty = specialty})
        else
            -- Simple skill
            table.insert(skills, {skill = skill})
        end
    end

    import:Log("-")
    import:Log(FormatStatus(text, "impl"))
    import:Log(FormatImpl("Monster skills not yet implemented"))

    print("Importing monster:", m.monster_type, "Parsed skills:", skills)
end

local function ParseHeaderLine(bestiaryEntry, m, input)

    if trim(input) == "" then
        return
    end

    -- Capture the text between <b> and </b>
    local name = input:match("<b>(.-)</b>")

    if name == nil then
        import:Log("-")
        import:Log(FormatStatus(input, "error"))
        import:Log(FormatError("Unrecognized input"))
        return
    end

    -- Remove any trailing colon from the name
    name = trim(name:gsub(":%s*$", ""))

    -- Extract the description part
    local description = input:match("</b>%s*(.*)")
    
    -- Trim any leading colon from the description
    description = trim(description:gsub("^:%s*", ""))

    if description == nil then
        return
    end


    local guid = dmhub.GenerateGuid()
    local feature = CharacterFeature.new{
        guid = guid,
        name = name,
        description = description,
        domains = {
            [string.format("CharacterFeature:%s", guid)] = true,
        },

        source = "Trait",

        modifiers = {},
    }

    local matched = false
    local traitsTemplates = dmhub.GetTable("importerMonsterTraits") or {}
    for k,v in pairs(traitsTemplates) do
        local trait = v:MatchMCDMMonsterTrait(bestiaryEntry, name, description)
        if trait ~= nil then
            import:Log("-")
            import:Log(FormatStatus(input, "success"))
            import:Log(FormatSuccess("Matched known trait: " .. v.name))
            matched = true
            feature.modifiers = DeepCopy(trait.modifiers)
            for _,mod in ipairs(feature.modifiers) do
                mod.description = description
            end
            break
        end
    end

    if not matched then
        import:Log("-")
        import:Log(FormatStatus(input, "impl"))
        import:Log(FormatImpl("Unrecognized trait"))
    end

    m.characterFeatures[#m.characterFeatures+1] = feature
end

local function splitByTabsIntoAttributes(str)
    --tab followed by bold should be treated like a new line.
    return regex.Split(str, "\\s*\\t\\s*<b>")
end

local function FixRoll(roll)
    --parse lists like "Reason, Presence, or Intuition" into "Reason or Presence or Intuition"
    roll = regex.ReplaceAll(roll, ",\\s+or ", " or ")
    roll = regex.ReplaceAll(roll, "\\s*,\\s*", " or ")
    return roll
end


MCDMImporter.ParseMonsterAbility = function(bestiaryEntry, lines, knownAbilities, report)

    report = report or {}

    import:Log("--")

    local headerLine = lines[1]

    local abilityHeaderMatch = regex.MatchGroups(headerLine, "^<b>(?<name>[^<]+)</b>\\s*\\((?<action>Action|Main Action|Triggered Action|Maneuver|Free Action|Free Triggered Action|Villain Action 1|Villain Action 2|Villain Action 3)\\).*?(?<signature>Signature)?((?<vp>[0-9]+) (VP|Malice))?$")

    if abilityHeaderMatch == nil then
        import:Log(FormatError("Could not recognize ability header."))
        report[#report+1] = "Unknown"
        report[#report+1] = "Unrecognized"
        for i=1,#lines do
            import:Log(FormatStatus(lines[i], "error"))
        end
        return
    end

    report[#report+1] = abilityHeaderMatch.name

    local hasErrors = false

    local rrMatch = regex.MatchGroups(headerLine, "^.*(?<rr>[A-Z][A-Z][A-Z]) RR.*$")
    local powerRollMatch = regex.MatchGroups(headerLine, "^.*(?<roll>2d10\\s*[+-]\\s*[0-9]+).*$")

    local powerRollEffects = {}
    local hasPowerRoll = false

    local attributes = {}
    local maliceEntries = {}

    for i=2,#lines do

        --print("TRYMATCH:: ", lines[i])

        local lineStatus = "good"
        local powerRollLine1 = regex.MatchGroups(lines[i], "^(%E2%9C...)?\\s*(<b>)?%E2%89%A411(</b>)?\\s+(?<effect>.*)$")
        local powerRollLine2 = regex.MatchGroups(lines[i], "^(%E2%98%85)?\\s*(<b>)?12(-|%E2%80%93)16(</b>)?\\s+(?<effect>.*)$")
        local powerRollLine3 = regex.MatchGroups(lines[i], "^(%E2%9C...)?\\s*(<b>)?17\\+?(</b>)?\\s+(?<effect>.*)$")
        if powerRollLine1 ~= nil then
            import:Log()
            powerRollEffects[1] = powerRollLine1.effect
            hasPowerRoll = true
        elseif powerRollLine2 ~= nil then
            powerRollEffects[2] = powerRollLine2.effect
            hasPowerRoll = true
        elseif powerRollLine3 ~= nil then
            powerRollEffects[3] = powerRollLine3.effect
            hasPowerRoll = true
        else
            local line = lines[i]

            line = regex.ReplaceAll(line, "<b>\\s+</b>", "  ")
            line = regex.ReplaceAll(line, "</b><b>", "")
            line = regex.ReplaceAll(line, "\\t", "")

            --replace text line <b>M<3</b> with M<3
            local maliceWithGatePattern = "^(?<head>.*)<b>(?<malice>[0-9]+ Malice)(?<gate>[MARIP]<[0-9])</b>(?<tail>.*)$"
            local matchBoldGate = regex.MatchGroups(line, maliceWithGatePattern)
            if matchBoldGate ~= nil then
                line = string.format("%s<b>%s</b> %s %s", matchBoldGate.head, matchBoldGate.malice, matchBoldGate.gate, matchBoldGate.tail)
            end

            local count = 0
            local remaining = line
            while trim(remaining) ~= "" and count < 5 do
                count = count + 1

                --first try to match effect or malice which would take the entire line.
                local effectMatch = regex.MatchGroups(remaining, "^\\s*<b>\\s*Effect\\s*</b>\\s*(?<value>.*)$")
                local maliceMatch = regex.MatchGroups(remaining, "^\\s*<b>(?<malice>[0-9]+\\+? Malice)\\s*</b>\\s*(?<value>.*)$")
                if effectMatch ~= nil then
                    attributes["effect"] = trim(regex.ReplaceAll(effectMatch.value, "</?b>", ""))
                    remaining = ""
                elseif maliceMatch ~= nil then
                    maliceEntries[#maliceEntries+1] = {
                        malice = maliceMatch.malice,
                        effect = trim(regex.ReplaceAll(maliceMatch.value, "</?b>", ""))
                    }
                    remaining = ""
                else

                    local match = regex.MatchGroups(remaining, "^\\s*<b>(?<name>[^<]+)</b>\\s*(?<value>[^<]+)(?<rest>.*)$")
                    if match == nil then
                        import:Log(FormatError("Could not parse attribute: (" .. remaining .. ")"))
                        hasErrors = true
                        lineStatus = "error"
                        break
                    end

                    --import:Log(FormatSuccess("Parsed attribute: " .. match.name .. " = " .. match.value))
                    attributes[string.lower(trim(match.name))] = trim(match.value)
                    remaining = match.rest
                end
            end
        end

        local loggableLine = regex.ReplaceAll(lines[i], "\\t", "  ")
        import:Log(FormatStatus(loggableLine, lineStatus))
    end


    if rrMatch ~= nil and creature.attributesInfo[string.lower(rrMatch.rr)] == nil then
        import:Log(FormatError("Unknown resistance attribute: " .. rrMatch.rr))
        hasErrors = true
        rrMatch = nil
    end

    if hasPowerRoll then
        for i = 1, #powerRollEffects do
            powerRollEffects[i] = regex.ReplaceAll(powerRollEffects[i], "</?b>", "")
        end

        -- Capitalize attribute abbreviations in potency patterns (e.g., "i<2" -> "I<2")
        for i = 1, #powerRollEffects do
            powerRollEffects[i] = string.gsub(powerRollEffects[i], "([marip])(<)", function(attr, lt)
                return string.upper(attr) .. lt
            end)
        end

        if #powerRollEffects ~= 3 then
            import:Log(FormatError("Could not find all three power roll effects."))
            hasErrors = true
            hasPowerRoll = false
        end

        if rrMatch == nil and powerRollMatch == nil then
            import:Log(FormatError("Could not find power roll or resistance roll in (" .. headerLine .. ")"))
            hasErrors = true
            hasPowerRoll = false
        end
    end




    local keywordsTable = {}

    if attributes["keywords"] ~= nil and attributes["keywords"] ~= "-" then
        for _,kw in ipairs(regex.Split(attributes["keywords"], "[,\\. \\t]+")) do
            local keyword = trim(kw)

            if keyword ~= "" then
                keywordsTable[keyword] = true
            end
        end
    end

    local existingAbility = knownAbilities[string.lower(trim(abilityHeaderMatch.name))]

    local categorization = "Signature Ability"
    if abilityHeaderMatch.vp ~= nil or string.starts_with(abilityHeaderMatch.action, "Villain Action") then
        categorization = "Heroic Ability"
    end

    local newAbility = ActivatedAbility.Create{
        name = abilityHeaderMatch.name,
        keywords = keywordsTable,
        flavor = "",
        behaviors = {},
        categorization = categorization,
    }

    print("TARGET:: PARSING ABILITY", newAbility.name, lines)

    for i,entry in ipairs(maliceEntries) do
        print("MALICE:: When parsing", newAbility.name, i, #maliceEntries, "found malice entry", entry.malice, "::", entry.effect)
    end

    if abilityHeaderMatch.vp ~= nil then
        local resourcesTable = dmhub.GetTable(CharacterResource.tableName)
        local resourceKey = nil
        for k,v in pairs(resourcesTable) do
            if (not v:try_get("hidden", false)) and v.name == "Malice" then
                resourceKey = k
                break
            end
        end

        if resourceKey == nil then
            import:Log(FormatError("Could not find malice resource."))
            hasErrors = true
        else
            newAbility.resourceCost = resourceKey
            newAbility.resourceNumber = tonumber(abilityHeaderMatch.vp)
            import:Log(FormatNote("Set Malice cost to " .. abilityHeaderMatch.vp))
        end
    end

    if abilityHeaderMatch.action ~= nil then
        local actionName = string.lower(abilityHeaderMatch.action)
        if string.starts_with(abilityHeaderMatch.action, "Villain Action") then
            newAbility.villainAction = abilityHeaderMatch.action
            actionName = "action"

            newAbility.usageLimitOptions = {
                charges = "1",
                multicharge = false,
                resourceRefreshType = "encounter",
                resourceid = dmhub.GenerateGuid(),
            }
        end
        local resourceName = string.lower(abilityHeaderMatch.action)
        local resourcesTable = dmhub.GetTable(CharacterResource.tableName)
        for k,resourceInfo in pairs(resourcesTable) do
            if string.starts_with(actionName, string.lower(resourceInfo.name)) then
                newAbility.actionResourceId = k
            end
        end

        print("Importing monster: ability resource", resourceName, json(newAbility:try_get("actionResourceId")))
    end



    if hasPowerRoll then
        local abilityPowerRoll = MCDMImporter.GetStandardAbility("Ability Power Roll")

        if abilityPowerRoll == nil then
            import:Log(FormatError("Could not find standard 'Ability Power Roll' ability to apply."))
        else
            for _,behavior in ipairs(abilityPowerRoll.behaviors) do
                local b = DeepCopy(behavior)
                b.tiers = powerRollEffects
                if powerRollMatch ~= nil then
                    b.roll = powerRollMatch.roll
                end

                if rrMatch ~= nil then
                    b.resistanceRoll = true
                    b.resistanceAttr = string.lower(rrMatch.rr)
                end

                newAbility.behaviors[#newAbility.behaviors+1] = b
            end

            local rulesValid = true
        end
    end


    local target = "1 creature or object"
    if attributes["target"] == nil then
        import:Log(FormatError("Required attribute 'Target' missing"))
        hasErrors = true
    else
        target = attributes["target"]
    end

    print("TARGET:: PARSING ABILITY", newAbility.name, "FOR DISTANCE", attributes["distance"])
    local distance = "1"
    if attributes["distance"] == nil then
        import:Log(FormatError("Required attribute 'Distance' missing"))
        hasErrors = true
    print("TARGET:: PARSING ABILITY", newAbility.name, "DISTANCE MISSING")
    else
        distance = attributes["distance"]

        local distanceMatch = regex.MatchGroups(distance, "^(Range|Reach|Melee) (?<range>[0-9]+)$")
        if distanceMatch ~= nil then
            distance = distanceMatch.range
        end

    print("TARGET:: PARSING ABILITY", newAbility.name, "DISTANCE PARSED TO", distance)
        import:Log(FormatNote("Distance: parsed from (" .. attributes["distance"] .. ") to (" .. distance .. ")"))
    end


    local numberedTargetsMatch = regex.MatchGroups(target, "(?<number>[0-9]+|One|Two|Three|Four|Five|Six|Seven|Eight|Nine|Ten|A|An) (?<type>creature|creatures|ally|allies|enemy|enemies)( or objects?)?(of weight (?<weightRequirement>[0-9]+) or lower)?( per minion)?")

    local numbersTable = {
        ["a"] = 1,
        ["an"] = 1,
        ["one"] = 1,
        ["two"] = 2,
        ["three"] = 3,
        ["four"] = 4,
        ["five"] = 5,
        ["six"] = 6,
        ["seven"] = 7,
        ["eight"] = 8,
        ["nine"] = 9,
        ["ten"] = 10,
    }


    if numberedTargetsMatch ~= nil then
        local range = string.match(distance, "%d+")
        if range == nil then
            import:Log(FormatError("Could not recognize target distance"))
            hasErrors = true
            range = "1"
        end

        range = tonumber(range)

        local meleeOrRangedMatch = regex.MatchGroups(distance, "^Melee (?<melee>[0-9]+) or Ranged? (?<ranged>[0-9]+)")
        if meleeOrRangedMatch ~= nil then
            --melee should be calculated fine by the creature's reach?
            range = tonumber(meleeOrRangedMatch.ranged)

            newAbility.meleeRange = tonumber(meleeOrRangedMatch.melee)
        end

        newAbility.targetType = "target"
        newAbility.numTargets = numbersTable[string.lower(numberedTargetsMatch.number)] or tonumber(numberedTargetsMatch.number)
        newAbility.range = range

        if numberedTargetsMatch.type == "enemy" or numberedTargetsMatch.type == "enemies" then
            newAbility.targetFilter = "Enemy"
        elseif numberedTargetsMatch.type == "ally" or numberedTargetsMatch.type == "allies" then
            newAbility.targetFilter = "not Enemy"
        end

    elseif target == "All creatures and objects" or target == "All creatures" or target == "All enemies in the burst" or target == "All enemies" or target == "All allies" or target == "All allies in the burst" or target == "Each creature" or target == "Each enemy" or target == "Each enemy in the cube" or target == "Each ally" or target == "Self and each ally" then
        local _, flat_range = regex.Match(distance, "^\\s*(\\d+)\\s*$")

        if flat_range ~= nil then
            newAbility.targetType = "all"
            newAbility.range = tonumber(flat_range)
            newAbility.numTargets = 1
        else
            local cubeMatch = regex.MatchGroups(distance, "(?<radius>\\d+)\\s+cube within (?<range>\\d+)( squares?)?")
            if cubeMatch ~= nil then
                newAbility.targetType = "cube"
                newAbility.numTargets = "1"
                newAbility.radius = tonumber(cubeMatch.radius)
                newAbility.range = tonumber(cubeMatch.range)
            else
                local lineMatch = regex.MatchGroups(distance, "(?<length>\\d+)\\s*x\\s*(?<width>\\d+)\\s*line within (?<range>\\d+)( squares?)?")
                if lineMatch ~= nil then
                    if tonumber(lineMatch.range) ~= 1 then
                        import:Log(FormatError("Do not currently support line abilities with range other than 1."))
                    end
                    newAbility.targetType = "line"
                    newAbility.numTargets = 1
                    newAbility.radius = tonumber(lineMatch.width)
                    newAbility.range = tonumber(lineMatch.length)
                else
                    local burstMatch = regex.MatchGroups(distance, "(?<radius>\\d+)\\s*burst")
                    if burstMatch ~= nil then
                        newAbility.targetType = "all"
                        newAbility.range = tonumber(burstMatch.radius)
                        newAbility.numTargets = 1
                    else
                        import:Log(FormatError("Could not recognize target distance: (" .. distance .. ") with target (" .. target .. ")"))
                        hasErrors = true
                    end
                end

            end
        end

        if string.find(target, "allies") ~= nil then
            newAbility.targetFilter = "not Enemy"
        end
        
        if string.find(target, "enem") ~= nil then
            newAbility.targetFilter = "Enemy"
        elseif target == "Each ally" or target == "All allies" then
            newAbility.targetFilter = "not Enemy"
        elseif target == "Self and each ally" then
            newAbility.targetFilter = "not Enemy"
            newAbility.selfTarget = true
        end
    else
        import:Log(FormatError("Could not recognize target '" .. target .. "'"))
        hasErrors = true
    end

    if attributes["effect"] ~= nil then
        newAbility.description = attributes["effect"]

        local abilityTemplate = nil
        local effectsTemplates = dmhub.GetTable("importerAbilityEffects") or {}
        for k,v in pairs(effectsTemplates) do
            abilityTemplate = v:MatchMCDMEffect(bestiaryEntry, newAbility.name, newAbility.description)
            if abilityTemplate ~= nil then
                import:Log(FormatSuccess("Matched known effect: " .. v.name))
                break
            end
        end

        if abilityTemplate == nil then
            import:Log(FormatImpl("Effect: Could not find implementation.", "impl"))
            hasErrors = true

            newAbility.implementation = 0
        else
            --any keys we copy from the effect if they differ from the default values.
            local substituteKeys = {"targetType", "range", "numTargets"}
            for _,key in ipairs(substituteKeys) do
                if abilityTemplate[key] ~= ActivatedAbility[key] then
                    newAbility[key] = abilityTemplate[key]
                end
            end

            if abilityTemplate:try_get("invokeSurroundingAbility") then
                --we embed the newAbility within the template behavior.
                local invokeCustom = MCDMImporter.GetStandardAbility("InvokeCustom")
                local invokeBehavior = invokeCustom.behaviors[1]
                invokeBehavior.customAbility = DeepCopy(newAbility)
                invokeBehavior.customAbility.guid = dmhub.GenerateGuid()

                local a = DeepCopy(abilityTemplate)
                a.name = newAbility.name
                a.iconid = newAbility.iconid
                a.flavor = newAbility:try_get("flavor")
                a.description = newAbility.description
                a.categorization = newAbility.categorization
                a.keywords = DeepCopy(newAbility.keywords)
                a.display = DeepCopy(newAbility.display)

                if abilityTemplate:try_get("insertAtStart") then
                    --note this is inverted to what we expect since insert at start mean *our* new behaviors go before the invoked ability.
                    a.behaviors[#a.behaviors+1] = invokeBehavior
                else
                    table.insert(a.behaviors, 1, invokeBehavior)
                end

                newAbility = a
            else
                --import:Log(FormatNote("Effect matched known effect: " .. v.name))
                if abilityTemplate:try_get("insertAtStart") then
                    local behaviors = {}
                    for i,behavior in ipairs(abilityTemplate.behaviors) do
                        behaviors[#behaviors+1] = behavior
                    end

                    for i,behavior in ipairs(newAbility.behaviors) do
                        behaviors[#behaviors+1] = behavior
                    end

                    newAbility.behaviors = behaviors
                else
                    for i,behavior in ipairs(abilityTemplate.behaviors) do
                        newAbility.behaviors[#newAbility.behaviors+1] = behavior
                    end
                end
            end
        end
    end

    for i,entry in ipairs(maliceEntries) do
        newAbility.description = string.format("%s\n**%s**: %s", newAbility.description, entry.malice, entry.effect)
        print("ABILITY::", newAbility.name, "MALICE", i, newAbility.description)
    end

    if hasErrors then
        report[#report+1] = "Unrecognized"
    else
        report[#report+1] = "Recognized"
    end
    
    return newAbility

end


MCDMImporter.ParseCreatureAbilities = function(bestiaryEntry, inputLines, knownAbilities, abilitiesOutput)
    local lines = {}
    for _,line in ipairs(inputLines) do
        local splitLines = splitByTabsIntoAttributes(line)
        for _,splitLine in ipairs(splitLines) do
            lines[#lines+1] = splitLine
        end
    end

    --occasionally there is an attribute that wraps to the next line. This includes a space at the end of the line. Try to detect that.

    local joinedLines = {}

    local oncolon = false
    local trailingspace = false
    for _,line in ipairs(lines) do
        local colonMatch = regex.MatchGroups(line, "^.*:.*$")

        local possibleWrapMatch = regex.MatchGroups(line, "^(?<match>[a-z0-9])")
        if trailingspace and oncolon and colonMatch == nil and possibleWrapMatch ~= nil and string.lower(possibleWrapMatch.match) == possibleWrapMatch.match then
            --this looks like it appends to the previous line.
            joinedLines[#joinedLines] = joinedLines[#joinedLines] .. " " .. trimTrailingWhitespace(line)
            oncolon = false
            trailingspace = false
        else
            oncolon = colonMatch ~= nil

            trailingspace = string.ends_with(line, " ")

            joinedLines[#joinedLines+1] = line
        end
    end

    lines = joinedLines


    local abilities = {}
    local currentAbility = nil
    for _,line in ipairs(lines) do
        local originalLine = line

        --multiple spaces just get replaced by a single space.
        line = regex.ReplaceAll(line, "\\s+", " ")

        local allItalics = regex.MatchGroups(line, "^\\s*<i>([^<]+)</i>\\s*$") ~= nil

        local status = "success"
        local diagnostic = nil
        local logAttribute = nil

        local hasTags = regex.MatchGroups(line, "^.*[<>].*$") ~= nil

        --remove all tags.
        local linePrev = line
        line = regex.ReplaceAll(line, "<[/a-zA-Z][^>]*>", "")

        local rollMatch = regex.MatchGroups(line, "^\\s*Power Roll *(?<roll>.*):\\s*$")

        local resistanceRollMatch = regex.MatchGroups(line, "^.*Target makes an? (?<attribute>[a-zA-Z]+) resistance roll:.*$")

        local rechargeMatch = regex.MatchGroups(line, "^\\s*(Recharge|(?<recharge>\\d+)/Encounter):\\s*(?<ability>.*?)\\s*$")

        local colon = string.find(line, ":")
        if allItalics then
            if currentAbility == nil then
                status = "error"
                diagnostic = "Unrecognized input"
            else
                currentAbility.flavor = line
            end
        elseif rollMatch ~= nil then
            if currentAbility == nil then
                status = "error"
                diagnostic = "Roll found when not in ability section."
            else
                currentAbility.roll = FixRoll(GameSystem.BaseAttackRoll .. " " .. rollMatch.roll)
                currentAbility.tiers = {}
            end
        elseif resistanceRollMatch ~= nil then
            if currentAbility == nil then
                status = "error"
                diagnostic = "Roll found when not in ability section."
            else

                local attrid = nil
                for key,info in pairs(creature.attributesInfo) do
                    if string.lower(info.description) == string.lower(resistanceRollMatch.attribute) then
                        attrid = key
                        break
                    end
                end

                if attrid == nil then
                    status = "error"
                    diagnostic = "Attribute " .. resistanceRollMatch.attribute .. " not recognized for resistance roll."
                else
                    currentAbility.resistanceAttr = attrid
                    currentAbility.resistanceRoll = true
                    currentAbility.tiers = {}
                end
            end
        elseif colon ~= nil and rechargeMatch == nil then

            local rollTierMatch = regex.MatchGroups(line, "^\\s*(?<tier>11 or lower|12(-|%..%..%..)16|17\\+):\\s*(?<rule>.*?)\\s*$")
            
            if currentAbility == nil then
                status = "error"
                diagnostic = "Unrecognized attribute input: " .. line
            elseif rollTierMatch ~= nil then
                if currentAbility.tiers == nil then
                    currentAbility.tiers = {}
                end

                if currentAbility.roll == nil then
                    currentAbility.roll = GameSystem.BaseAttackRoll .. " + Power Roll Bonus"

                end
                currentAbility.tiers[#currentAbility.tiers+1] = rollTierMatch.rule
            else

                local knownAttributes = {
                    ["Type"] = true,
                    ["Damage"] = true,
                    ["Target"] = true,
                    ["Distance"] = true,
                    ["Keywords"] = true,
                    ["Effect"] = true,
                    ["Trigger"] = true,
                    ["Extra"] = true,
                }


                --see if we match something like Effect (TN 10 MGT Resists): The target is knocked prone.
                local pattern = "(%w+) %((.-)%): (.+)"

                -- Extracting the name, arg, and description
                local name, arg, description = line:match(pattern)

                if name ~= nil then
                    currentAbility.attributes[name] = {value = trim(description), arg = arg}
                    logAttribute = name

                    if knownAttributes[name] == nil then
                        status = "error"
                        diagnostic = "Unknown attribute: " .. name
                    end
                else
                    local s = line
                    local foundKnown = false

                    for knownAttribute,_ in pairs(knownAttributes) do
                        local pattern = "^(?<head>.*) " .. knownAttribute .. ": (?<tail>.*)$"
                        local match = regex.MatchGroups(s, pattern)
                        while match ~= nil do
                            foundKnown = true
                            logAttribute = knownAttribute
                            currentAbility.attributes[knownAttribute] = {value = trim(match.tail)}

                            s = match.head
                            match = regex.MatchGroups(s, pattern)
                        end
                    end

                    --fallback way of matching.
                    local pattern = "(%w+): (.+)"
                    local name, value = s:match(pattern)
                    if name == nil then
                        if foundKnown == false then
                            status = "error"
                            diagnostic = "Unrecognized attribute format: " .. s
                        end
                    else
                        logAttribute = name
                        currentAbility.attributes[name] = {value = trim(value)}
                        if knownAttributes[name] == nil then
                            status = "error"
                            diagnostic = "Unknown attribute: " .. name
                        end
                    end
                end
            end
        else

            local name = nil

            if rechargeMatch ~= nil then
                name = rechargeMatch.ability
                print("ABILITY:: PARSING", name, "FROM LINE", line, "//", originalLine)
            else
                local nameMatch = regex.MatchGroups(line, "^\\s*(?<ability>.*[A-Za-z]+.*)\\s*$")
                if nameMatch ~= nil then
                    name = nameMatch.ability
                    print("ABILITY:: PARSING2", name, "FROM LINE", line, " // ", originalLine)
                end
            end

            local stillParsingAbility = false
            if currentAbility ~= nil then
                stillParsingAbility = true
                for _,_ in pairs(currentAbility.attributes) do
                    stillParsingAbility = false
                    break
                end
            end

            if name ~= nil and name ~= "" and #name < 60 and (not stillParsingAbility) then

                local rechargeValue = nil
                if rechargeMatch ~= nil then
                    rechargeValue = tonumber(rechargeMatch.recharge) or true
                end

                currentAbility = {
                    name = name,
                    recharge = rechargeValue,
                    attributes = {},
                    logLines = {},
                }

                abilities[#abilities+1] = currentAbility
            elseif (not hasTags) and currentAbility ~= nil and next(currentAbility.attributes) == nil then
                currentAbility.flavor = line
            elseif regex.MatchGroups(line, "^\\s*$") == nil then
                status = "error"
                diagnostic = "Unrecognized input: (" .. line .. ")"
            end
        end

        if currentAbility == nil then
            import:Log("-")
            import:Log(FormatStatus(line, status))
            if diagnostic ~= nil then
                import:Log(FormatError(diagnostic))
            end
        else
            currentAbility.logLines[#currentAbility.logLines+1] = {
                line = line,
                status = status,
                diagnostic = diagnostic,
                attribute = logAttribute,
            }
        end
    end

    for _,ability in ipairs(abilities) do

        local MarkAttributeError = function(attr, status)
            for _,lineEntry in ipairs(ability.logLines) do
                if lineEntry.attribute == attr then
                    lineEntry.status = status or "error"
                end
            end
        end

        local abilityNotes = {}
        local abilityErrors = {}

        local keywordsTable = {}
        
        if ability.attributes["Keywords"] then
            local keywords = trim(ability.attributes["Keywords"].value)
            if keywords ~= "-" then
                keywords = string.split(keywords, ",")
                for _,keyword in ipairs(keywords) do
                    keyword = trim(keyword)

                    --handle [Psionic/Magic] as just Magic
                    if string.lower(keyword) == "[psionic/magic]" then
                        keyword = "Magic"
                    elseif keyword ~= "" then
                        -- Capitalize first letter
                        keyword = keyword:sub(1, 1):upper() .. keyword:sub(2)
                    end

                    if keyword ~= "" then
                        keywordsTable[keyword] = true
                    end
                end

            end
        end

        local existingAbility = knownAbilities[string.lower(trim(ability.name))]

        local newAbility = ActivatedAbility.Create{
            name = ability.name,
            keywords = keywordsTable,
            flavor = ability.flavor,
            behaviors = {},
            categorization = "Signature Ability",
        }

        --see if the ability includes the resource cost.
        local nameResourceMatch = regex.MatchGroups(ability.name, "^(?<name>[a-z][a-z!, -]+) +\\((?<resourceCost>[0-9]+) (?<resourceName>[a-z]+)\\)$")
    print("ABILITY:: PARSING", newAbility.name, "resource match", nameResourceMatch ~= nil, "WITH TIERS", json(ability.tiers))
        if nameResourceMatch ~= nil then
            name = nameResourceMatch.name
            newAbility.name = name
            local resourceName = nameResourceMatch.resourceName
            local resourcesTable = dmhub.GetTable(CharacterResource.tableName)
            local found = false
            print("ABILITY:: RESOURCE: ", newAbility.name, "has resource", resourceName)
            for k,resourceInfo in pairs(resourcesTable) do
                if string.starts_with(string.lower(resourceName), string.lower(resourceInfo.name)) then
                    --newAbility.resourceCost = k --now give all heroes the heroic resource.
                    newAbility.resourceCost = CharacterResource.heroicResourceId
                    newAbility.resourceNumber = tonumber(nameResourceMatch.resourceCost)
                    found = true
                end
            end

            print("ABILITY:: RESOURCE: ", newAbility.name, "found resource", found)
            if not found then
                abilityErrors[#abilityErrors+1] = FormatStatus("Could not recognize ability resource cost " .. resourceName .. " for " .. name, "error")
            end
        end


        if ability.roll ~= nil or ability.tiers ~= nil then
            if ability.roll == nil or ability.tiers == nil or #ability.tiers ~= 3 then
                abilityErrors[#abilityErrors+1] = FormatStatus("Could not recognize power roll format.", "error")
            else
                local abilityPowerRoll = MCDMImporter.GetStandardAbility("Ability Power Roll")

                if abilityPowerRoll == nil then
                    abilityErrors[#abilityErrors+1] = FormatStatus("Could not find standard 'Ability Power Roll' ability to apply.", "error")
                else
                    for _,behavior in ipairs(abilityPowerRoll.behaviors) do
                        local b = DeepCopy(behavior)
                        b.tiers = ability.tiers
                        b.roll = ability.roll
                        b.resistanceAttr = ability.resistanceAttr
                        b.resistanceRoll = ability.resistanceRoll
                        newAbility.behaviors[#newAbility.behaviors+1] = b
                    end

                    local rulesValid = true
                    --see if the rules are valid/make sense.
                    for i,tier in ipairs(ability.tiers) do
                        local result = ActivatedAbilityDrawSteelCommandBehavior.ValidateRule(tier)
                        if type(result) == "string" then
                            abilityErrors[#abilityErrors+1] = FormatStatus(string.format("Tier %d rule invalid: %s", i, result), "error")

                            --make it so the portion of the line that we couldn't recognize is in red in the log.
                            for _,lineEntry in ipairs(ability.logLines) do
                                if string.ends_with(string.lower(lineEntry.line), string.lower(result)) then
                                    local line = lineEntry.line
                                    local n = #result
                                    local head = string.sub(line, 1, -n-1)
                                    local tail = string.sub(line, -n)

                                    lineEntry.line = string.format("%s<color=#ff0000>%s</color>", head, tail)
                                end
                            end

                            rulesValid = false
                        end
                    end

                    if rulesValid then
                        abilityErrors[#abilityErrors+1] = FormatStatus("Power table rules all recognized.", "good")
                    end
                end

            end
        end

        if ability.attributes["Type"] ~= nil then
            local resourceName = string.lower(ability.attributes["Type"].value)
            local resourcesTable = dmhub.GetTable(CharacterResource.tableName)
            for k,resourceInfo in pairs(resourcesTable) do
                if string.starts_with(string.lower(resourceName), string.lower(resourceInfo.name)) then
                    newAbility.actionResourceId = k
                end
            end

            print("Importing monster: ability resource", newAbility.name, resourceName, json(newAbility:try_get("actionResourceId")))
        end

        if ability.attributes["Damage"] ~= nil then
            local damage = ability.attributes["Damage"].value
            local damageTypeKey = "normal"
            local damageTypesTable = dmhub.GetTable(DamageType.tableName) or {}
            for k,v in pairs(damageTypesTable) do
                if (not v:try_get("hidden")) and string.ends_with(string.lower(damage), string.lower(v.name)) then
                    damage = string.sub(damage, 1, string.len(damage) - string.len(v.name))
                    damage = trim(damage)
                    damageTypeKey = string.lower(v.name)
                    break
                end
            end

            newAbility.behaviors[#newAbility.behaviors+1] = ActivatedAbilityAttackBehavior.new{
                roll = damage,
                damageType = damageTypeKey,
            }

        end


        if existingAbility ~= nil then
            newAbility.display = existingAbility.display
            newAbility.iconid = existingAbility.iconid
        end

        if ability.recharge then
            newAbility.usageLimitOptions = {
                charges = "1",
                multicharge = false,
                resourceRefreshType = "encounter",
                resourceid = dmhub.GenerateGuid(),
            }

            --preserve the id of the resource if possible.
            if existingAbility ~= nil and existingAbility:try_get("usageLimitOptions") ~= nil and existingAbility.usageLimitOptions.resourceid ~= nil then
                newAbility.usageLimitOptions.resourceid = existingAbility.usageLimitOptions.resourceid
            end
        end

        local target = "1 creature or object"
        if ability.attributes["Target"] == nil then
            abilityErrors[#abilityErrors+1] = "Required attribute 'Target' missing"
        else
            target = ability.attributes["Target"].value
        end

        local distance = "1"
        if ability.attributes["Distance"] == nil then
            abilityErrors[#abilityErrors+1] = "Required attribute 'Distance' missing"
        else
            distance = ability.attributes["Distance"].value
        end


        local numberedTargetsMatch = regex.MatchGroups(target, "(?<number>[0-9]+|One|Two|Three|Four|Five|Six|Seven|Eight|Nine|Ten|A|An) (?<type>creature|creatures|ally|allies|enemy|enemies)( or objects?)?(of weight (?<weightRequirement>[0-9]+) or lower)?( per minion)?")

        local numbersTable = {
            ["a"] = 1,
            ["an"] = 1,
            ["one"] = 1,
            ["two"] = 2,
            ["three"] = 3,
            ["four"] = 4,
            ["five"] = 5,
            ["six"] = 6,
            ["seven"] = 7,
            ["eight"] = 8,
            ["nine"] = 9,
            ["ten"] = 10,
        }

        if numberedTargetsMatch ~= nil then
            local rangeMatch = regex.MatchGroups(distance, "^Melee (?<melee>[0-9]+) or Ranged? (?<range>[0-9]+)")
            if rangeMatch == nil then
                rangeMatch = regex.MatchGroups(distance, "Range (?<range>[0-9]+)")
                if rangeMatch == nil then
                    rangeMatch = regex.MatchGroups(distance, "(?<range>[0-9]+)")
                end
            end

            local range = "1"
            if rangeMatch == nil then
                abilityErrors[#abilityErrors+1] = "Could not recognize target distance"
                MarkAttributeError("Distance")
            else
                range = rangeMatch.range
                if rangeMatch.melee ~= nil then
                    newAbility.meleeRange = tonumber(rangeMatch.melee)
                end
            end

            range = tonumber(range)

            newAbility.targetType = "target"
            newAbility.numTargets = numbersTable[string.lower(numberedTargetsMatch.number)] or tonumber(numberedTargetsMatch.number)
            newAbility.range = range

            if numberedTargetsMatch.type == "enemy" or numberedTargetsMatch.type == "enemies" then
                newAbility.targetFilter = "Enemy"
            elseif numberedTargetsMatch.type == "ally" or numberedTargetsMatch.type == "allies" then
                newAbility.targetFilter = "not Enemy"
            end

        elseif target == "All creatures" or target == "ally or enemy" or target == "allies or enemies" or target == "All enemies" or target == "All allies" or target == "Each creature" or target == "Each enemy" or target == "Each ally" or target == "Self and each ally" or target == "Each enemy in the area" or target == "Each ally in the area" or target == "Each enemy in the cube" or target == "Each ally in the cube" or target == "Self and each ally in the area" then
            local _, flat_range = regex.Match(distance, "^\\s*(\\d+)\\s*$")
                        print("TARGET:: match for burst", newAbility.name, "have match", target, "flat_range =", flat_range)

            if flat_range ~= nil then
                newAbility.targetType = "all"
                newAbility.range = tonumber(flat_range)
                newAbility.numTargets = 1
            else
                local cubeMatch = regex.MatchGroups(distance, "(?<radius>\\d+)\\s+cube within (?<range>\\d+)( squares?)?")
                if cubeMatch == nil then
                    --alternative format for cubes can sometimes show it after instead of before the 'cube'.
                    cubeMatch = regex.MatchGroups(distance, "cube (?<radius>\\d+)\\s+within (?<range>\\d+)( squares?)?")
                end
                if cubeMatch ~= nil then
                    newAbility.targetType = "cube"
                    newAbility.numTargets = "1"
                    newAbility.radius = tonumber(cubeMatch.radius)
                    newAbility.range = tonumber(cubeMatch.range)
                else
                    local lineMatch = regex.MatchGroups(distance, "(?<length>\\d+)\\s*x\\s*(?<width>\\d+)\\s*line within (?<range>\\d+)( squares?)?")
                    if lineMatch ~= nil then
                        if tonumber(lineMatch.range) ~= 1 then
                            abilityErrors[#abilityErrors+1] = "Do not currently support line abilities with range other than 1."
                        end
                        newAbility.targetType = "line"
                        newAbility.numTargets = 1
                        newAbility.radius = tonumber(lineMatch.width)
                        newAbility.range = tonumber(lineMatch.length)
                    else
                        local burstMatch = regex.MatchGroups(distance, "(?<radius>\\d+)\\s*burst")
                        print("TARGET:: burst match", newAbility.name, burstMatch ~= nil)
                        if burstMatch ~= nil then
                            newAbility.targetType = "all"
                            newAbility.range = tonumber(burstMatch.radius)
                            newAbility.numTargets = 1
                        else
                            abilityErrors[#abilityErrors+1] = "Could not recognize target distance: (" .. distance .. ") with target (" .. target .. ")"
                            MarkAttributeError("Distance")
                        end
                    end

                end
            end

            if target == "Each enemy" or target == "All enemies" then
                newAbility.targetFilter = "Enemy"
            elseif target == "Each ally" or target == "All allies" then
                newAbility.targetFilter = "not Enemy"
            elseif target == "Self and each ally" then
                newAbility.targetFilter = "not Enemy"
                newAbility.selfTarget = true
            else
                local hasEnemy = string.find(string.lower(target), "enem")
                local hasAlly = string.find(string.lower(target), "ally")
                local hasSelf = string.find(string.lower(target), "self")

                if hasEnemy then
                    newAbility.targetFilter = "Enemy"
                elseif hasAlly then
                    newAbility.targetFilter = "not Enemy"
                    newAbility.selfTarget = cond(hasSelf, true, false)
                end

            end
        else
            abilityErrors[#abilityErrors+1] = "Could not recognize target '" .. target .. "'"
            MarkAttributeError("Target")
        end

        local effectAttr = "Effect"
        if ability.attributes["Effect"] == nil then
            effectAttr = "Extra"
        end

        if ability.attributes[effectAttr] ~= nil then
            newAbility.description = ability.attributes[effectAttr].value

            local abilityTemplate = nil
            local effectsTemplates = dmhub.GetTable("importerAbilityEffects") or {}
            for k,v in pairs(effectsTemplates) do
                abilityTemplate = v:MatchMCDMEffect(bestiaryEntry, newAbility.name, newAbility.description)
                if abilityTemplate ~= nil then
                    abilityNotes[#abilityNotes+1] = "<color=#00ff00>Matched known effect: " .. v.name .. "</color>"
                    break
                end
            end

            if abilityTemplate == nil then
                abilityErrors[#abilityErrors+1] = FormatStatus(effectAttr .. ": Could not find implementation for " .. effectAttr .. ".", "impl")
                MarkAttributeError(effectAttr, "impl")

                newAbility.implementation = 0
            else
                if abilityTemplate:try_get("invokeSurroundingAbility") then
                    --we embed the newAbility within the template behavior.
                    local invokeCustom = MCDMImporter.GetStandardAbility("InvokeCustom")
                    local invokeBehavior = invokeCustom.behaviors[1]
                    invokeBehavior.customAbility = DeepCopy(newAbility)
                    invokeBehavior.customAbility.guid = dmhub.GenerateGuid()

                    local a = DeepCopy(abilityTemplate)
                    a.name = newAbility.name
                    a.iconid = newAbility.iconid
                    a.flavor = newAbility:try_get("flavor")
                    a.description = newAbility.description
                    a.categorization = newAbility.categorization
                    a.keywords = DeepCopy(newAbility.keywords)
                    a.display = DeepCopy(newAbility.display)

                    if abilityTemplate:try_get("insertAtStart") then
                        --note this is inverted to what we expect since insert at start mean *our* new behaviors go before the invoked ability.
                        a.behaviors[#a.behaviors+1] = invokeBehavior
                    else
                        table.insert(a.behaviors, 1, invokeBehavior)
                    end

                    newAbility = a
                else
                    --import:Log(FormatNote("Effect matched known effect: " .. v.name))
                    if abilityTemplate:try_get("insertAtStart") then
                        local behaviors = {}
                        for i,behavior in ipairs(abilityTemplate.behaviors) do
                            behaviors[#behaviors+1] = behavior
                        end

                        for i,behavior in ipairs(newAbility.behaviors) do
                            behaviors[#behaviors+1] = behavior
                        end

                        newAbility.behaviors = behaviors
                    else
                        for i,behavior in ipairs(abilityTemplate.behaviors) do
                            newAbility.behaviors[#newAbility.behaviors+1] = behavior
                        end
                    end
                end
            end

        end

        abilitiesOutput[#abilitiesOutput+1] = newAbility

        import:Log("--")
        for _,logLine in ipairs(ability.logLines) do
            import:Log(FormatStatus(logLine.line, logLine.status))
            if logLine.diagnostic ~= nil then
                import:Log(FormatError(logLine.diagnostic))
            end
        end

        for _,note in ipairs(abilityNotes) do
            import:Log(FormatNote(note))
        end

        for _,error in ipairs(abilityErrors) do
            import:Log(FormatError(error))
        end
    end
end

local g_monsterModes = {
    ["Maneuver"] = "Maneuvers",
    ["Maneuvers"] = "Maneuvers",
    ["Actions"] = "Actions",
    ["Triggered Actions"] = "Triggered Actions",
    ["Triggered Action"] = "Triggered Actions",
    ["Villain Abilities"] = "Villain Abilities",
}

--if we have lines of text, this gets one "paragraph" (ending with an empty line) and returns it in a list.
--the input list will have those lines removed.
local function GetNextParagraph(lines)
    local result = {}

    local foundNonEmpty = false

    while #lines > 0 do
        local empty = regex.MatchGroups(lines[1], "^\\s*$") ~= nil
        if not empty then
            foundNonEmpty = true
            result[#result+1] = lines[1]
        end

        table.remove(lines, 1)

        if foundNonEmpty and empty then
            return result
        end
    end

    return result
end

--parses "<b>Size:</b> 1   <b>Weight: </b>3   <b>Languages:</b> Caelian, Szetch" -> {Size = "1", Weight = "3", Languages = "Caelian, Szetch"}
local function ParseLineAttributes(line, result)
    local pattern = "<b>(?<name>[^:]+):\\s*</b>\\s*(?<value>[^<]+)(?<tail>.*)"
    local match = regex.MatchGroups(line, pattern)
    while match ~= nil do
        result[match.name] = trim(match.value)
        line = match.tail
        match = regex.MatchGroups(line, pattern)
    end
end

local function ParseParagraphAttributes(lines)
    local result = {}

    for _,line in ipairs(lines) do
        ParseLineAttributes(line, result)
    end

    return result
end

local function PeekNextNonEmptyLine(lines)
    for _,line in ipairs(lines) do
        if regex.MatchGroups(line, "^\\s*$") == nil then
            return line
        end
    end

    return nil
end

local function ParseMonsterTrait(name, text)
    print("MONSTER:: TRAIT PARSING TRAIT", name, "TEXT", text)

    local guid = dmhub.GenerateGuid()
    local feature = CharacterFeature.new{
        guid = guid,
        name = name,
        description = text,
        domains = {
            [string.format("CharacterFeature:%s", guid)] = true,
        },

        source = "Trait",

        modifiers = {},
    }

    local matchedTrait = false

    local traitsTemplates = dmhub.GetTable("importerMonsterTraits") or {}
    for k,v in unhidden_pairs(traitsTemplates) do
        local trait = v:MatchMCDMMonsterTrait(nil, name, text)
        if trait ~= nil then
            feature.implementation = trait:try_get("implementation")
            feature.modifiers = DeepCopy(trait.modifiers)
            for _,mod in ipairs(feature.modifiers) do
                mod.description = text
            end
            matchedTrait = true
            import:Log("--")
            import:Log(FormatStatus(name .. ": " .. text, "success"))
            import:Log(FormatSuccess("Matched known trait: " .. v.name))
            print("MONSTER:: TRAIT IMPORT TEXT", text)
            break
        end
    end

    if not matchedTrait then
        print("MONSTER:: TRAIT UNRECGOZNIED", name, text)
        import:Log("--")
        import:Log(FormatStatus(name .. ": " .. text, "impl"))
        import:Log(FormatImpl("Unrecognized trait"))
    end

    return feature

end

MCDMImporter.ImportText = function(importer, text)
    import:Log("[DS-JSON] Starting ImportText...")
    local options = import.options or {}

    -- Fail safe: Check if this is JSON content and redirect
    local firstChar = string.sub(text, 1, 1)
    import:Log("[DS-JSON] First character: " .. tostring(firstChar))
    if text:match("^%s*{") then
        import:Log("[DS-JSON] Detected JSON, redirecting to JSON Importer...")
        MCDMImporter.ImportJSON(importer, text)
        import:Log("[DS-JSON] Returned from JSON Importer")
        return
    end
    import:Log("[DS-JSON] Not JSON, processing as text...")

    --makes it easier to parse if we have a newline at the end.
    if not string.ends_with(text, "\n") then
        text = text .. "\n"
    end

    if options.replaceExisting ~= false then
        InitParser()
    end

    local importReport = {}

    text = MCDMImporter.ReplaceSpecialCharactersWithASCII(text)

    local monsterEntries = {}

    local currentMonster = nil
    local cursor = nil

    local prevLine = nil
    local monsterSections = {}
    local currentSection = nil



    local currentVillainPower = nil
    local currentMonsterGroup = nil
    local currentMonsterGroupImported = false
    local createdMonsterGroups = {}
    local currentMaliceAbility = nil


    local lines = {}
    for sline in string.gmatch(text, "([^\r\n]*)\r?\n") do
        lines[#lines+1] = regex.ReplaceAll(trim(sline), "</?b>\\s*</?b>", "")
    end

    --blank line at the end helps single-monster imports.
    lines[#lines+1] = ""

    local monsterHeaderPattern = "^(?<name>.*)\tLevel (?<level>[0-9]+) (?<role>.*)(?<minion> (Captain|Minion))?$"

    local i = 1
    while i <= #lines do
        local nlineStart = i

        local sline = lines[i]
        i = i+1

        local villainPowerMatch = regex.MatchGroups(sline, "^(?<keyword>[A-Za-z ]+) Malice.+Malice Features$")
        if villainPowerMatch ~= nil then
            currentVillainPower = villainPowerMatch.keyword
            currentMaliceAbility = nil

            currentMonsterGroup = import:GetExistingItem(MonsterGroup.tableName, villainPowerMatch.keyword) or createdMonsterGroups[villainPowerMatch.keyword]
            if currentMonsterGroup == nil then
                currentMonsterGroup = MonsterGroup.CreateNew{
                    name = villainPowerMatch.keyword,
                }
                currentMonsterGroupImported = false
                createdMonsterGroups[villainPowerMatch.keyword] = currentMonsterGroup
            end
        end


        local monsterHeadingMatch = regex.MatchGroups(sline, monsterHeaderPattern)

        local maliceAbilityMatch = regex.MatchGroups(sline, "^\\s*<b>(?<abilityName>.+?)</b>.* (?<malice>[0-9]+)\\+? Malice")
        if maliceAbilityMatch ~= nil and currentMonsterGroup ~= nil then
            print("MonsterGroup:: match", maliceAbilityMatch.abilityName, "malice =", maliceAbilityMatch.malice, "for group =", currentMonsterGroup.name)

            local a = nil
            for _,ability in ipairs(currentMonsterGroup.maliceAbilities) do
                if ability.name == maliceAbilityMatch.abilityName then
                    a = ability
                    break
                end
            end

            if a == nil then
                a = MaliceAbility.Create{
                    name = maliceAbilityMatch.abilityName,
                }

                currentMonsterGroup.maliceAbilities[#currentMonsterGroup.maliceAbilities+1] = a
            end

            a.description = ""
            a.resourceCost = CharacterResource.maliceResourceId
            a.resourceNumber = tonumber(maliceAbilityMatch.malice)
            currentMaliceAbility = a

            print("MonsterGroup:: import ability", a.name)

        elseif monsterHeadingMatch == nil then
            if currentMaliceAbility ~= nil then
                if currentMaliceAbility.description ~= "" then
                    currentMaliceAbility.description = currentMaliceAbility.description .. "\n"
                end
                currentMaliceAbility.description = currentMaliceAbility.description .. sline
            end
        else
            if currentMaliceAbility ~= nil then
                currentMaliceAbility.description = trim(currentMaliceAbility.description)
            end

            currentMaliceAbility = nil

            sline = lines[i] or ""
            i = i+1

            local error = nil

            local evMatch = regex.MatchGroups(sline, "^(?<keywords>.*)\\s+EV (?<ev>[0-9]+)( for four minions)?$")
            local staminaMatch
            local immunityMatch = nil
            local weaknessMatch = nil
            local creatureTraits = {}
            if evMatch == nil then
                error = "Could not find EV " .. monsterHeadingMatch.name

            else
                sline = lines[i] or ""
                i = i+1

                sline = trim(regex.ReplaceAll(sline, "</?b>", ""))



                staminaMatch = regex.MatchGroups(sline, "Stamina\\s+(?<stamina>[0-9]+)")
                if staminaMatch == nil then
                    error = "Could not find Stamina in " .. sline
                end

                immunityMatch = regex.MatchGroups(sline, "Immunity (?<immunity>.*)$")
                weaknessMatch = regex.MatchGroups(sline, "Weakness (?<immunity>.*)$")
            end

            local speedSizeMatch
            if staminaMatch ~= nil then
                sline = lines[i] or ""
                i = i+1

                sline = trim(regex.ReplaceAll(sline, "</?b>", ""))

                speedSizeMatch = regex.MatchGroups(sline, "Speed\\s+(?<speed>[0-9]+)\\s+\\(?(?<moveType>[A-Za-z, ]+)?\\)?.*Size.*(?<size>[0-9]+[LMST]?).*Stability.*(?<stability>([0-9]+|all))$")
                if speedSizeMatch == nil then
                    error = "Could not find Speed/Size/Stability in " .. sline
                end
            end

            local traitsFreeStrikeMatch
            if speedSizeMatch ~= nil then
                sline = lines[i] or ""
                i = i+1

                sline = trim(regex.ReplaceAll(sline, "</?b>", ""))

                traitsFreeStrikeMatch = regex.MatchGroups(sline, "^(\\s*(Traits)?\\s*)?\\s*(?<traits>.*?)?\\s*(With Captain\\s*(?<withcaptain>.*))?\\s*Free Strike\\s*(?<freeStrike>[0-9]+)$")
                if traitsFreeStrikeMatch == nil then
                    error = "Could not find Traits/Free Strikes in " .. sline
                end
            end

            local attrMatch
            if traitsFreeStrikeMatch ~= nil then
                sline = lines[i] or ""
                i = i+1

                attrMatch = regex.MatchGroups(sline, "^Might \\+?(?<might>[0-9-]+)\\s*Agility \\+?(?<agility>[0-9+-]+)\\s*Reason \\+?(?<reason>[0-9+-]+)\\s*Intuition \\+?(?<intuition>[0-9+-]+)\\s*Presence \\+?(?<presence>[0-9+-]+)$")
                if attrMatch == nil then
                    error = "Could not find attributes in " .. sline
                end
            end

            local abilitiesEntries = {}
            local traitsEntries = {}


            local endLine = i


            --search for a new monster section which we would end on.
            for j=i,#lines do
                if regex.MatchGroups(lines[j] or "", "^(?<keyword>[A-Za-z ]+) (Languages|Malice.+Malice Features)$") ~= nil then
                    --new monster section so our ending is the last whitespace.
                    break
                elseif trim(lines[j] or "") == "" then
                    endLine = j
                end
            end

            print("MONSTER:: MONSTER", monsterHeadingMatch.name, "ENDLINE", endLine)

            local whitespaceLinesRun = 0

            while attrMatch ~= nil and i < endLine do
                sline = lines[i] or ""
                i = i+1

                local lastWhitespace = whitespaceLinesRun

                if trim(sline) == "" then
                    whitespaceLinesRun = whitespaceLinesRun + 1
                    if whitespaceLinesRun >= 3 then
                        break
                    end
                else
                    whitespaceLinesRun = 0
                end

                local abilityHeaderMatch = regex.MatchGroups(sline, "^<b>(?<name>[^<]+)</b>\\s*\\((?<type>Action|Main Action|Triggered Action|Maneuver|Free Action|Free Triggered Action|Villain Action 1|Villain Action 2|Villain Action 3)\\).*(?<signature>Signature)?((?<vp>[0-9]+) (VP|Malice))?$")
                if abilityHeaderMatch ~= nil then
                    local entries = {}
                    abilitiesEntries[#abilitiesEntries+1] = entries

                    entries[#entries+1] = sline

                    --ability goes until next whitespace, or the next 'heading line' which has bolded text without any non-bolded text..
                    while i <= #lines do
                        sline = lines[i] or ""
                        local matchNewHeading = regex.MatchGroups(sline, "^\\s*<b>[^<]+</b>\\s*$")
                        if matchNewHeading ~= nil then
                            break
                        end

                        i = i+1

                        if trim(sline) == "" then
                            whitespaceLinesRun = 1
                            break
                        end

                        entries[#entries+1] = sline
                    end

                    print("MONSTER:: monster", monsterHeadingMatch.name, "has ability", abilityHeaderMatch.name, #entries, "MATCH::", abilityHeaderMatch)
                elseif regex.MatchGroups(sline, monsterHeaderPattern) ~= nil then
                    print("MONSTER:: monster", monsterHeadingMatch.name, "NEXT MONSTER", sline)
                    --we've hit the next monster.
                    i = i-1
                    break
                elseif lastWhitespace <= 1 and regex.MatchGroups(sline, "^\\s*<b>[^<]+</b>\\s*$") ~= nil then
                    print("MONSTER:: monster", monsterHeadingMatch.name, "TRAIT", sline)
                    --trait.
                    local traitLines = {}

                    traitsEntries[#traitsEntries+1] = traitLines

                    traitLines[#traitLines+1] = sline

                    print("MONSTER:: PARSE TRAIT:", lines[i-1], "xx", lines[i])
                    while lines[i] ~= nil and trim(lines[i]) ~= "" and regex.MatchGroups(lines[i], "[<>]") == nil do
                        sline = lines[i]
                        i = i+1
                        traitLines[#traitLines+1] = sline
                    end

                elseif whitespaceLinesRun == 0 then
                    print("MONSTER:: monster", monsterHeadingMatch.name, "UNRECOGNIZED WITH WHITESPACE", lastWhitespace, sline)
                    import:Log(FormatError("MONSTER:: UNRECOGNIZED LINE: " .. sline))
                else
                    print("MONSTER:: monster", monsterHeadingMatch.name, "WHITESPACE")
                end
            end


            if error ~= nil then
                import:Log(FormatError("In monster " .. monsterHeadingMatch.name .. ": " .. error))
                print("MONSTER:: ERROR", monsterHeadingMatch.name, error)
            else

                --work out the monster group, 'goblin', 'kobold', etc.
                local folder = nil
                if currentVillainPower ~= nil then
                    folder = import:GetExistingItem("monsterFolder", currentVillainPower)
                    print("MonsterFolder:: monster", monsterHeadingMatch.name, "is in", currentVillainPower)
                    if folder == nil then
                        folder = import:CreateMonsterFolder(currentVillainPower)
                        import:ImportMonsterFolder(folder)
                    end

                    if currentMonsterGroupImported == false then
                        import:ImportAsset(MonsterGroup.tableName, currentMonsterGroup)
                print("MonsterGroup:: Import", currentMonsterGroup.name)
                        
                        currentMonsterGroupImported = true
                    end
                else
                    print("MonsterFolder:: monster", monsterHeadingMatch.name, "no folder")
                end

                local bookmark = import:BookmarkLog()

                local bestiaryEntry
                
                if options.replaceExisting ~= false then
                    bestiaryEntry = import:GetExistingItem("monster", monsterHeadingMatch.name)
                end

                print("MONSTER:: PARSED AND ADDING", monsterHeadingMatch.name, "bestiaryEntry:", bestiaryEntry ~= nil, "replaceExisting=", options.replaceExisting)

                if bestiaryEntry ~= nil and bestiaryEntry.properties:try_get("import", {}).override then
                    local report = {}
                    report[#report+1] = bestiaryEntry.name
                    report[#report+1] = "Monster"
                    report[#report+1] = "OVERRIDE"

                    local cr = bestiaryEntry.properties:try_get("cr", 1)
                    if cr <= 3 then
                        report[#report+1] = "1"
                    elseif cr <= 6 then
                        report[#report+1] = "2"
                    elseif cr <= 9 then
                        report[#report+1] = "3"
                    else
                        report[#report+1] = "4"
                    end


                    importReport[#importReport+1] = report

                    for _,a in ipairs(bestiaryEntry.properties:try_get("innateActivatedAbilities", {})) do
                        local report = {}
                        report[#report+1] = bestiaryEntry.name
                        report[#report+1] = a.name

                        local statusOptions = {"Unimplemented", "Partial", "Implemented", "Won't Implement"}
                        local implementation = a:try_get("implementation", 1)
                        implementation = statusOptions[implementation] or "Unknown"
                        report[#report+1] = implementation
                        
                        importReport[#importReport+1] = report
                    end

                end

                if bestiaryEntry == nil or ((not bestiaryEntry.properties:has_key("import")) or (not bestiaryEntry.properties.import.override)) then

                    if bestiaryEntry == nil then
                        bestiaryEntry = import:CreateMonster()
                        bestiaryEntry.properties = monster.CreateNew()
                    end

                    bestiaryEntry.name = monsterHeadingMatch.name

                    if folder ~= nil then
                        bestiaryEntry.parentFolder = folder.id
                    end

                    --bestiaryEntry.properties.import = {
                    --    type = "mcdm",
                    --    data = monsterInfo.rawdata,
                    --}

                    bestiaryEntry.properties.reach = nil
                    bestiaryEntry.properties.monster_type = monsterHeadingMatch.name
                    if currentMonsterGroup ~= nil then
                        bestiaryEntry.properties.groupid = currentMonsterGroup.id
                    end
                    bestiaryEntry.properties.role = monsterHeadingMatch.role
                    bestiaryEntry.properties.minion = regex.MatchGroups(monsterHeadingMatch.role, "Minion") ~= nil

                    local m = bestiaryEntry.properties

                    m.cr = round(tonumber(monsterHeadingMatch.level) or 0)

                    local report = {}
                    report[#report+1] = bestiaryEntry.name
                    report[#report+1] = "Monster"
                    report[#report+1] = "IMPORT"
                    if m.cr <= 3 then
                        report[#report+1] = "1"
                    elseif m.cr <= 6 then
                        report[#report+1] = "2"
                    elseif m.cr <= 9 then
                        report[#report+1] = "3"
                    else
                        report[#report+1] = "4"
                    end
                    importReport[#importReport+1] = report




                    m.keywords = {}
                    m.ev = tonumber(evMatch.ev)

                    local keywords = regex.Split(evMatch.keywords or "", "[,\\. \\t]+")
                    print("KEYWORDS:: MONSTER HAS", keywords)
                    for _,keyword in ipairs(keywords) do
                        keyword = trim(keyword)
                        if keyword ~= "" and keyword ~= "-" then
                            print("KEYWORDS:: MONSTER KEYWORD =", keyword)
                            m.keywords[keyword] = true
                        end
                    end

                    if speedSizeMatch.stability == "all" then
                        m.stability = 99
                    else
                        m.stability = tonumber(speedSizeMatch.stability)
                    end

                    local foundSize = false
                    for _,entry in ipairs(dmhub.rules.CreatureSizes) do
                        if string.lower(entry.name) == string.lower(speedSizeMatch.size) then
                            m.creatureSize = entry.name
                            foundSize = true
                            break
                        end
                    end

                    if foundSize == false then
                        import:Log(FormatError("Could not find size " .. speedSizeMatch.size))
                    end

                    import:Log(FormatSuccess("Creature size is " .. m.creatureSize .. " from " .. speedSizeMatch.size))

                    m.max_hitpoints = tonumber(staminaMatch.stamina)
                    m.max_hitpoints_roll = staminaMatch.stamina

                    m.resistances = {}

                    import:Log(FormatSuccess("Stamina is " .. m.max_hitpoints))

                    local ParseImmunity = function(immunityMatch, multiplier)
                        if immunityMatch == nil then
                            return
                        end

                        local immunity = trim(immunityMatch.immunity)

                        local tries = 0
                        while tries < 12 and trim(immunity) ~= "" do
                            tries = tries+1

                            local immunityMatch = regex.MatchGroups(immunity, "^\\s*,?\\s*(?<keyword>[A-Za-z]+)\\s+(?<value>[0-9]+)(?<tail>.*)$")

                            if immunityMatch == nil then
                                import:Log(FormatError("Could not parse immunity: " .. immunity))
                                break
                            end

                            immunity = immunityMatch.tail

                            local damageType = "all"
                            local matchDamage = false

                            local damageTypesTable = dmhub.GetTable(DamageType.tableName) or {}
                            for k,v in pairs(damageTypesTable) do
                                if (not v:try_get("hidden")) and string.lower(v.name) == string.lower(immunityMatch.keyword) then
                                    matchDamage = true
                                    damageType = string.lower(v.name)
                                end
                            end

                            local keywords = nil

                            if matchDamage == false then
                                if string.lower(immunityMatch.keyword) ~= "damage" then
                                    keywords = {}
                                    keywords[string.lower(immunityMatch.keyword)] = true
                                end
                            end

                            local resistances = m:try_get("resistances", {})

                            resistances[#resistances+1] = ResistanceEntry.new{
                                keywords = keywords,
                                damageType = damageType,
                                apply = "Damage Reduction",
                                dr = tonumber(immunityMatch.value)*multiplier,
                            }

                            m.resistances = resistances


                        end

                    end

                    ParseImmunity(immunityMatch, 1)
                    ParseImmunity(weaknessMatch, -1)

                    print("RESISTANCE::", m:try_get("resistances"))

                    m.walkingSpeed = tonumber(speedSizeMatch.speed)
                    m.movementSpeeds = {}
                    if speedSizeMatch.moveType ~= nil then
                        local moveTypes = string.split(speedSizeMatch.moveType, ",")
                        for _,s in ipairs(moveTypes) do
                            local moveType = trim(s)
                            if string.find(moveType, "fly") ~= nil then
                                m.movementSpeeds.fly = m.walkingSpeed
                            end
                            if string.find(moveType, "climb") ~= nil then
                                m.movementSpeeds.climb = m.walkingSpeed
                            end
                            if string.find(moveType, "swim") ~= nil then
                                m.movementSpeeds.swim = m.walkingSpeed
                            end
                            if string.find(moveType, "teleport") ~= nil then
                                m.movementSpeeds.teleport = m.walkingSpeed
                            end
                            if string.find(moveType, "burrow") ~= nil then
                                m.movementSpeeds.burrow = m.walkingSpeed
                            end
                        end
                    end


                    m.attributes["mgt"] = { baseValue = tonumber(attrMatch.might) }
                    m.attributes["agl"] = { baseValue = tonumber(attrMatch.agility) }
                    m.attributes["rea"] = { baseValue = tonumber(attrMatch.reason) }
                    m.attributes["inu"] = { baseValue = tonumber(attrMatch.intuition) }
                    m.attributes["prs"] = { baseValue = tonumber(attrMatch.presence) }

                    m.opportunityAttack = tonumber(traitsFreeStrikeMatch.freeStrike)

                    m.traitNames = {}

                    if traitsFreeStrikeMatch.traits ~= nil then
                        local traitNames = string.split(traitsFreeStrikeMatch.traits or "", ",")

                        for _,traitName in ipairs(traitNames) do
                            if trim(traitName) ~= "" then
                                m.traitNames[#m.traitNames+1] = trim(traitName)
                            end
                        end
                    end

                    if traitsFreeStrikeMatch.withcaptain ~= nil then
                        m.withCaptain = trim(traitsFreeStrikeMatch.withcaptain)
                    else
                        m.withCaptain = nil
                    end

                    local existingAbilities = m:GetActivatedAbilities()

                    local knownAbilities = {}
                    for _,ability in ipairs(existingAbilities) do
                        knownAbilities[string.lower(trim(ability.name))] = ability
                    end

                    m.characterFeatures = creatureTraits
                    m.innateActivatedAbilities = {}


                    for _,abilityLines in ipairs(abilitiesEntries) do

                        local report = {}
                        report[#report+1] = bestiaryEntry.name
                        importReport[#importReport+1] = report

                        local ability = MCDMImporter.ParseMonsterAbility(bestiaryEntry, abilityLines, knownAbilities, report)
                        if ability ~= nil then
                            m.innateActivatedAbilities[#m.innateActivatedAbilities+1] = ability
                        end
                    end

                    for _,traitEntry in ipairs(traitsEntries) do
                        local traitMatch = regex.MatchGroups(traitEntry[1], "^\\s*<b>(?<name>[^<]+)</b>\\s*$")

                        local traitText = ""
                        for j=2,#traitEntry do
                            traitText = traitText .. traitEntry[j]
                        end

                        if traitText == "" then
                            error = "Could not find text for trait " .. traitMatch.name
                            print("MONSTER:: COULD NOT PARSE MONSTER TRAIT", traitMatch.name)
                        else
                            local feature = ParseMonsterTrait(traitMatch.name, traitText)
                            print("MONSTER:: PARSE MONSTER TRAIT", traitMatch.name, feature, json(feature))
                            if feature ~= nil then
                                import:Log(FormatSuccess("Matched trait: " .. traitMatch.name))
                                creatureTraits[#creatureTraits+1] = feature
                            else
                                import:Log(FormatError("Unrecognized trait: " .. traitMatch.name))
                            end
                        end
                    end

                    print("MONSTER:: traits for ", monsterHeadingMatch.name, json(m.traitNames))

                    local rawText = ""
                    for j=nlineStart,i-1 do
                        rawText = rawText .. lines[j] .. "\n"
                    end

                    print("MONSTER:: import with rawtext", #rawText)

                    bestiaryEntry.properties.import = {
                        type = "mcdm",
                        data = rawText,
                    }

                    print("MONSTER:: IMPORTED MONSTER:", bestiaryEntry.name)

                    import:StoreLogFromBookmark(bookmark, bestiaryEntry)
                    import:Log("-")
                    import:Log(bestiaryEntry.name .. " (Level " .. tostring(m.cr) .. ")")
                    local success = import:ImportMonster(bestiaryEntry)
                    if success == false then
                        import:Log(FormatError("FAILED to import: Item may be locked/overridden. Check if '" .. bestiaryEntry.name .. "' is marked as 'overridden' in the compendium."))
                    else
                        import:Log(FormatSuccess("Imported"))
                    end
                end
            end
        end
    end

    local importReportStr = ""
    for _,report in ipairs(importReport) do
        importReportStr = importReportStr .. string.join(report, "\t") .. "\n"
    end
    print("Import Report:\n", importReportStr)
end

import.Register{
    id = "mcdm",
    description = "MCDM Monsters",
    input = "docx",
    priority = 200,

    renderLog = MCDMImporter.renderLog,

    text = function(importer, text)
        MCDMImporter.ImportText(importer, text)
    end,
}

import.Register{
    id = "mcdmtext",
    description = "MCDM Monsters (text)",
    input = "plaintext",
    priority = 200,

    renderLog = MCDMImporter.renderLog,


    text = function(importer, text)
        MCDMImporter.ImportText(importer, text)
    end,
}

-- Simple JSON parser for basic structures
local function parseJSON(jsonStr)
    local pos = 1

    local function skipWhitespace()
        while pos <= #jsonStr and jsonStr:match("^%s", pos) do
            pos = pos + 1
        end
    end

    local function parseValue()
        skipWhitespace()

        local char = jsonStr:sub(pos, pos)

        -- Parse null
        if jsonStr:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        end

        -- Parse boolean
        if jsonStr:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        end
        if jsonStr:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        end

        -- Parse number
        if char == "-" or char:match("%d") then
            local numStr = ""
            if char == "-" then
                numStr = numStr .. char
                pos = pos + 1
            end
            while pos <= #jsonStr and jsonStr:sub(pos, pos):match("[%d.]") do
                numStr = numStr .. jsonStr:sub(pos, pos)
                pos = pos + 1
            end
            return tonumber(numStr)
        end

        -- Parse string
        if char == '"' then
            pos = pos + 1
            local str = ""
            while pos <= #jsonStr and jsonStr:sub(pos, pos) ~= '"' do
                if jsonStr:sub(pos, pos) == "\\" then
                    pos = pos + 1
                    local escapeChar = jsonStr:sub(pos, pos)
                    if escapeChar == "n" then str = str .. "\n"
                    elseif escapeChar == "t" then str = str .. "\t"
                    elseif escapeChar == "r" then str = str .. "\r"
                    elseif escapeChar == '"' then str = str .. '"'
                    elseif escapeChar == "\\" then str = str .. "\\"
                    elseif escapeChar == "/" then str = str .. "/"
                    elseif escapeChar == "b" then str = str .. "\b"
                    elseif escapeChar == "f" then str = str .. "\f"
                    else str = str .. escapeChar end
                    pos = pos + 1
                else
                    str = str .. jsonStr:sub(pos, pos)
                    pos = pos + 1
                end
            end
            pos = pos + 1 -- Skip closing quote
            return str
        end

        -- Parse array
        if char == "[" then
            pos = pos + 1
            local arr = {}
            skipWhitespace()
            if jsonStr:sub(pos, pos) ~= "]" then
                while pos <= #jsonStr do
                    table.insert(arr, parseValue())
                    skipWhitespace()
                    if jsonStr:sub(pos, pos) == "," then
                        pos = pos + 1
                        skipWhitespace()
                    else
                        break
                    end
                end
            end
            skipWhitespace()
            pos = pos + 1 -- Skip closing bracket
            return arr
        end

        -- Parse object
        if char == "{" then
            pos = pos + 1
            local obj = {}
            skipWhitespace()
            if jsonStr:sub(pos, pos) ~= "}" then
                while pos <= #jsonStr do
                    skipWhitespace()
                    -- Parse key
                    if jsonStr:sub(pos, pos) ~= '"' then
                        break
                    end
                    local key = parseValue()
                    skipWhitespace()
                    -- Expect colon
                    if jsonStr:sub(pos, pos) ~= ":" then
                        break
                    end
                    pos = pos + 1
                    skipWhitespace()
                    -- Parse value
                    obj[key] = parseValue()
                    skipWhitespace()
                    if jsonStr:sub(pos, pos) == "," then
                        pos = pos + 1
                        skipWhitespace()
                    else
                        break
                    end
                end
            end
            skipWhitespace()
            pos = pos + 1 -- Skip closing brace
            return obj
        end

        return nil
    end

    return parseValue()
end

MCDMImporter.ImportJSON = function(importer, jsonContent)
    import:Log("[DS-JSON] Starting JSON Import...")
    import:Log("[DS-JSON] Content type: " .. type(jsonContent))
    import:Log("[DS-JSON] Content length: " .. tostring(#jsonContent))
    local options = import.options or {}

    local data = nil
    
    -- Check if content is already a table (parsed by system) or string
    if type(jsonContent) == "table" then
        import:Log("[DS-JSON] Received table data, using directly.")
        data = jsonContent
    else
        import:Log("[DS-JSON] Received string data, attempting parse. Length: " .. tostring(#jsonContent))

        -- Try various JSON parsers using pcall to avoid uninitialized variable errors
        local parsed = false

        -- Try cjson
        if not parsed then
            import:Log("[DS-JSON] Trying cjson...")
            local status, res = pcall(function()
                -- Use _G to safely check global variables
                return (_G.cjson and _G.cjson.decode and _G.cjson.decode(jsonContent)) or nil
            end)
            if status and res and type(res) == "table" then
                data = res
                parsed = true
                import:Log(FormatStatus("[DS-JSON] cjson.decode succeeded!", "success"))
            end
        end

        -- Try json.decode
        if not parsed then
            import:Log("[DS-JSON] Trying json.decode...")
            local status, res = pcall(function()
                return (type(_G.json) == "table" and _G.json.decode and _G.json.decode(jsonContent)) or nil
            end)
            if status and res and type(res) == "table" then
                data = res
                parsed = true
                import:Log(FormatStatus("[DS-JSON] json.decode succeeded!", "success"))
            end
        end

        -- Try dkjson
        if not parsed then
            import:Log("[DS-JSON] Trying dkjson...")
            local status, res = pcall(function()
                return (_G.dkjson and _G.dkjson.decode and _G.dkjson.decode(jsonContent)) or nil
            end)
            if status and res and type(res) == "table" then
                data = res
                parsed = true
                import:Log(FormatStatus("[DS-JSON] dkjson.decode succeeded!", "success"))
            end
        end

        -- Try custom JSON parser as fallback
        if not parsed then
            import:Log("[DS-JSON] Trying custom parseJSON...")
            local status, res = pcall(function()
                return parseJSON(jsonContent)
            end)
            if status and res and type(res) == "table" then
                data = res
                parsed = true
                import:Log(FormatStatus("[DS-JSON] Custom parseJSON succeeded!", "success"))
            else
                import:Log(FormatStatus("[DS-JSON] Custom parseJSON failed: " .. tostring(res), "error"))
            end
        end

        if not parsed then
            import:Log(FormatStatus("[DS-JSON] ERROR: No JSON parser could parse the content", "error"))
            -- Log first 500 chars of content for debugging
            local contentPreview = string.sub(jsonContent, 1, 500)
            import:Log(FormatError("[DS-JSON] Content preview: " .. contentPreview))
            return
        end
    end


    if data == nil then
        import:Log(FormatStatus("[DS-JSON] Data is nil after parse.", "error"))
        return
    end

    import:Log("[DS-JSON] Data type: " .. type(data))
    import:Log("[DS-JSON] Data.type value: " .. tostring(data.type))
    import:Log("[DS-JSON] Data.items exists: " .. tostring(data.items ~= nil))

    if data.type ~= "npc" then
        import:Log("-")
        import:Log(tostring(data.name or "Unknown"))
        import:Log(FormatError("Not an NPC (type: " .. tostring(data.type) .. ")"))
        return
    end

    local bookmark = import:BookmarkLog()

    local monsterEntries = {}
    local importReport = {}

    local bestiaryEntry
    local isExisting = false
    if options.replaceExisting ~= false then
        bestiaryEntry = import:GetExistingItem("monster", data.name)
        if bestiaryEntry ~= nil then
            isExisting = true
            import:Log("[DS-JSON] Found existing monster, will update it")
        end
    end

    if bestiaryEntry ~= nil and bestiaryEntry.properties:try_get("import", {}).override then
        local report = {}
        report[#report+1] = bestiaryEntry.name
        report[#report+1] = "Monster"
        report[#report+1] = "OVERRIDE"

        local cr = bestiaryEntry.properties:try_get("cr", 1)
        if cr <= 3 then
            report[#report+1] = "1"
        elseif cr <= 6 then
            report[#report+1] = "2"
        elseif cr <= 9 then
            report[#report+1] = "3"
        else
            report[#report+1] = "4"
        end

        importReport[#importReport+1] = report

        for _,a in ipairs(bestiaryEntry.properties:try_get("innateActivatedAbilities", {})) do
            local report = {}
            report[#report+1] = bestiaryEntry.name
            report[#report+1] = a.name

            local statusOptions = {"Unimplemented", "Partial", "Implemented", "Won't Implement"}
            local implementation = a:try_get("implementation", 1)
            implementation = statusOptions[implementation] or "Unknown"
            report[#report+1] = implementation

            importReport[#importReport+1] = report
        end

        import:Log("-")
        import:Log(FormatStatus(bestiaryEntry.name, "override"))
        local overrideMsg = FormatOverride("Override - will not be imported")
        import:Log(overrideMsg)
        return importReport
    end

    if bestiaryEntry == nil then
        bestiaryEntry = import:CreateMonster()
        bestiaryEntry.properties = monster.CreateNew()
    else
        -- Reset properties for existing monster to clear old data
        bestiaryEntry.properties = monster.CreateNew()
    end

    bestiaryEntry.name = MCDMImporter.ReplaceSpecialCharactersWithASCII(data.name)
    import:Log("[DS-JSON] Importing Monster: " .. bestiaryEntry.name)

    local m = bestiaryEntry.properties
    m.name = bestiaryEntry.name  -- Also set the name on the properties object
    m.monster_type = bestiaryEntry.name  -- Set monster_type for proper identification

    -- Core Stats
    if data.system and data.system.stamina then
        m.max_hitpoints = data.system.stamina.max
        m.max_hitpoints_roll = tostring(data.system.stamina.max)
    end
    
    if data.system and data.system.combat then
        m.stability = data.system.combat.stability
        m.cr = data.system.monster and data.system.monster.level or 1
        
        -- Size
        if data.system.combat.size then
            local sizeValue = data.system.combat.size.value or ""
            local sizeLetter = data.system.combat.size.letter or ""
            if tonumber(sizeValue) and tonumber(sizeValue) > 1 then
                m.creatureSize = tostring(sizeValue)
            else
                m.creatureSize = tostring(sizeValue) .. sizeLetter
            end
        end
    end


    -- Attributes (Characteristics)
    if data.system and data.system.characteristics then
        m.attributes["mgt"] = { baseValue = data.system.characteristics.might and data.system.characteristics.might.value or 0 }
        m.attributes["agl"] = { baseValue = data.system.characteristics.agility and data.system.characteristics.agility.value or 0 }
        m.attributes["rea"] = { baseValue = data.system.characteristics.reason and data.system.characteristics.reason.value or 0 }
        m.attributes["inu"] = { baseValue = data.system.characteristics.intuition and data.system.characteristics.intuition.value or 0 }
        m.attributes["prs"] = { baseValue = data.system.characteristics.presence and data.system.characteristics.presence.value or 0 }
    end

    -- Movement
    if data.system and data.system.movement then
        m.walkingSpeed = data.system.movement.value or 6
        m.movementSpeeds = {}
        if data.system.movement.types then
            for _, moveType in ipairs(data.system.movement.types) do
                if moveType ~= "walk" then
                    if moveType == "fly" then m.movementSpeeds.fly = m.walkingSpeed
                    elseif moveType == "climb" then m.movementSpeeds.climb = m.walkingSpeed
                    elseif moveType == "swim" then m.movementSpeeds.swim = m.walkingSpeed
                    elseif moveType == "burrow" then m.movementSpeeds.burrow = m.walkingSpeed
                    elseif moveType == "teleport" then m.movementSpeeds.teleport = m.walkingSpeed
                    end
                end
            end
        end
    end

    -- EV & Role
    if data.system and data.system.monster then
        m.ev = data.system.monster.ev

        -- Role: Combine organization + role with title case
        -- Skip role if it duplicates organization (e.g., both "solo" → "Solo" not "Solo Solo")
        local org = data.system.monster.organization or ""
        local role = data.system.monster.role or ""
        local roleStr = ""
        if org ~= "" then
            roleStr = org:sub(1, 1):upper() .. org:sub(2)
        end
        if role ~= "" and role:lower() ~= org:lower() then
            if roleStr ~= "" then
                roleStr = roleStr .. " " .. role:sub(1, 1):upper() .. role:sub(2)
            else
                roleStr = role:sub(1, 1):upper() .. role:sub(2)
            end
        end
        m.role = roleStr

        -- Keywords
        m.keywords = {}
        local firstKeyword = nil
        if data.system.monster.keywords then
            for _, kw in ipairs(data.system.monster.keywords) do
                if kw and kw ~= "" then
                    -- Capitalize first letter
                    local capitalizedKw = kw:sub(1, 1):upper() .. kw:sub(2)
                    m.keywords[capitalizedKw] = true
                    if firstKeyword == nil then
                        firstKeyword = capitalizedKw
                    end
                end
            end
        end

        m.opportunityAttack = data.system.monster.freeStrike

        -- Monster category (folder name from Foundry data, e.g. "Angulotls", "Demons")
        -- This drives MonsterGroup lookup for malice abilities
        if data.system.monster.folder and data.system.monster.folder ~= "" then
            m.monster_category = data.system.monster.folder
            import:Log("[DS-JSON] Monster Category: " .. m.monster_category)
        else
            m.monster_category = firstKeyword or "Monster"
            import:Log("[DS-JSON] Monster Category (fallback): " .. m.monster_category)
        end

        -- Minion flag
        if data.system.monster.organization and regex.MatchGroups(data.system.monster.organization, "[Mm]inion") ~= nil then
            m.minion = true
        end
    end

    -- Immunities & Weaknesses
    m.resistances = {}
    local damageData = data.system and data.system.damage
    if damageData then
        local damageTypesTable = dmhub.GetTable(DamageType.tableName) or {}

        local ParseDamageEntries = function(entries, multiplier)
            if entries == nil then
                return
            end

            for key, value in pairs(entries) do
                if type(value) == "number" and value > 0 then
                    local damageType = "all"
                    local matchDamage = false
                    local keywords = nil

                    for k, v in pairs(damageTypesTable) do
                        if (not v:try_get("hidden")) and string.lower(v.name) == string.lower(key) then
                            matchDamage = true
                            damageType = string.lower(v.name)
                        end
                    end

                    if not matchDamage then
                        if string.lower(key) ~= "damage" and string.lower(key) ~= "all" then
                            keywords = {}
                            keywords[string.lower(key)] = true
                        end
                    end

                    m.resistances[#m.resistances + 1] = ResistanceEntry.new{
                        keywords = keywords,
                        damageType = damageType,
                        apply = "Damage Reduction",
                        dr = value * multiplier,
                    }

                    import:Log(FormatSuccess("[DS-JSON] Resistance: " .. key .. " = " .. tostring(value * multiplier)))
                end
            end
        end

        ParseDamageEntries(damageData.immunities, 1)
        ParseDamageEntries(damageData.weaknesses, -1)
    end

    -- Items (Features and Abilities)
    local creatureTraits = {}
    m.innateActivatedAbilities = {}
    local villainActionCount = 0

    local pendingBandAbilities = {}

    import:Log("[DS-JSON] Checking items... data.items exists: " .. tostring(data.items ~= nil))
    if data.items then
        import:Log("[DS-JSON] Found " .. tostring(#data.items) .. " items to process")
        for idx, item in ipairs(data.items) do
            import:Log("[DS-JSON] Item " .. idx .. ": type=" .. tostring(item.type) .. ", name=" .. tostring(item.name))
            if item.type == "feature" then
                -- Parse Trait
                local traitName = MCDMImporter.ReplaceSpecialCharactersWithASCII(item.name or "Unknown Trait")
                local traitDesc = (item.system and item.system.description and item.system.description.value) or ""
                -- Replace special characters and apostrophes FIRST
                traitDesc = MCDMImporter.ReplaceSpecialCharactersWithASCII(traitDesc)
                -- Then clean html and damage tags from desc
                traitDesc = regex.ReplaceAll(traitDesc, "<[^>]+>", "")
                traitDesc = regex.ReplaceAll(traitDesc, "\\[\\[/damage ([^\\]]+)\\]\\]\\{([^}]+)\\}", "$2")
                traitDesc = regex.ReplaceAll(traitDesc, "\\[\\[/damage ([\\dd+\\-\\s]+?)\\s+([^\\]]+)\\]\\]", "$1 $2")
                traitDesc = regex.ReplaceAll(traitDesc, "\\[\\[/damage ([^\\]]+)\\]\\]", "$1")
                traitDesc = regex.ReplaceAll(traitDesc, "\\[\\[/heal ([^\\]]+?) temporary\\]\\]", "$1 temporary Stamina")
                traitDesc = regex.ReplaceAll(traitDesc, "\\[\\[/heal ([^\\]]+)\\]\\]", "$1 Stamina")
                traitDesc = regex.ReplaceAll(traitDesc, "@UUID\\[[^\\]]*\\]\\{([^}]+)\\}", "$1")
                -- Clean [[/apply ...]] and [[/Apply ...]] enricher tags
                traitDesc = regex.ReplaceAll(traitDesc, "\\[\\[/[Aa]pply [^\\]]+\\]\\]\\{([^}]+)\\}", "$1") -- With display text: use it
                traitDesc = regex.ReplaceAll(traitDesc, "\\[\\[/[Aa]pply ([a-z]+) save\\]\\]", "$1 (save ends)") -- Named condition + save
                traitDesc = regex.ReplaceAll(traitDesc, "\\[\\[/[Aa]pply ([a-z]+) turn\\]\\]", "$1 (EoT)") -- Named condition + turn
                traitDesc = regex.ReplaceAll(traitDesc, "\\[\\[/[Aa]pply ([a-z]+) encounter\\]\\]", "$1 (encounter)") -- Named condition + encounter
                traitDesc = regex.ReplaceAll(traitDesc, "\\[\\[/[Aa]pply ([a-z]+) respite\\]\\]", "$1 (respite)") -- Named condition + respite
                traitDesc = regex.ReplaceAll(traitDesc, "\\[\\[/[Aa]pply ([a-z]+)\\]\\]", "$1") -- Named condition, no duration
                traitDesc = regex.ReplaceAll(traitDesc, "\\[\\[/[Aa]pply [^\\]]+\\]\\]", "") -- Raw IDs without display text: strip

                -- Handle "With Captain" feature separately - set m.withCaptain instead of adding as trait
                local dsid = item.system and item.system._dsid
                if dsid == "with-captain" then
                    -- Extract the With Captain text, stripping the "With Captain:" prefix if present
                    local withCaptainText = regex.ReplaceAll(traitDesc, "^\\s*With Captain:\\s*", "")
                    withCaptainText = trim(withCaptainText)
                    if withCaptainText ~= "" then
                        m.withCaptain = withCaptainText
                        import:Log(FormatSuccess("[DS-JSON] With Captain: " .. withCaptainText))
                    end
                    goto continue_feature
                end

                -- Check for known trait match similar to text importer
                local featureGuid = dmhub.GenerateGuid()
                local feature = CharacterFeature.new{
                    guid = featureGuid,
                    name = traitName,
                    description = traitDesc,
                    domains = {
                        [string.format("CharacterFeature:%s", featureGuid)] = true,
                    },
                    source = "Trait",
                    modifiers = {},
                }

                -- Attempt to match standard traits
                local matchedTrait = false
                local traitsTemplates = dmhub.GetTable("importerMonsterTraits") or {}
                for k,v in unhidden_pairs(traitsTemplates) do
                    local trait = v:MatchMCDMMonsterTrait(nil, traitName, traitDesc)
                    if trait ~= nil then
                        feature.implementation = trait:try_get("implementation")
                        feature.modifiers = DeepCopy(trait.modifiers)
                        matchedTrait = true
                        import:Log(FormatSuccess("Matched known trait: " .. v.name))
                        break
                    end
                end

                creatureTraits[#creatureTraits+1] = feature

                ::continue_feature::

            elseif item.type == "ability" then
                -- Parse Ability
                local abSystem = item.system
                if abSystem == nil then
                    import:Log(FormatError("[DS-JSON] Ability '" .. tostring(item.name) .. "' has no system data, skipping"))
                    goto continue_ability
                end
                local abilityName = MCDMImporter.ReplaceSpecialCharactersWithASCII(item.name or "Unknown Ability")
                abilityName = string.gsub(abilityName, " and ", " & ")
                local newAbility = ActivatedAbility.Create{
                    name = abilityName,
                    keywords = {},
                    flavor = (abSystem.story and abSystem.story ~= "") and abSystem.story or "",
                    behaviors = {},
                    categorization = "Action", -- Default
                }
                newAbility.targetType = "target"

                -- Action resource IDs
                local actionId = "d19658a2-4d7b-4504-af9e-1a5410fb17fd"
                local maneuverId = "a513b9a6-f311-4b0f-88b8-4e9c7bf92d0b"
                local triggeredId = "b9bc06dd-80f1-4f33-bc55-25c114e3300c"

                -- Categorization
                if abSystem.type == "maneuver" then
                    newAbility.categorization = "Maneuver"
                    newAbility.actionResourceId = maneuverId
                elseif abSystem.type == "triggered" then
                    newAbility.categorization = "Triggered Action"
                    newAbility.actionResourceId = triggeredId
                elseif abSystem.type == "villain" then
                    newAbility.categorization = "Villain Action"
                    villainActionCount = villainActionCount + 1
                    newAbility.villainAction = "Villain Action " .. villainActionCount
                    newAbility.usageLimitOptions = {
                        charges = "1",
                        multicharge = false,
                        resourceRefreshType = "encounter",
                        resourceid = dmhub.GenerateGuid(),
                    }
                elseif abSystem.category == "heroic" then newAbility.categorization = "Heroic Ability"
                elseif abSystem.type == "main" then
                    newAbility.categorization = "Action"
                    newAbility.actionResourceId = actionId
                end

                -- Check for signature category explicitly
                if abSystem.category == "signature" then
                    newAbility.categorization = "Signature Ability"
                    newAbility.actionResourceId = newAbility.actionResourceId or actionId
                end

                -- Skip abilities from class abilities (Actor) compendium - imported separately
                local compendiumSource = item._stats and item._stats.compendiumSource or ""
                if string.match(compendiumSource, "^Actor%.") then
                    import:Log("[DS-JSON] Skipping compendium ability: " .. abilityName .. " (source: " .. compendiumSource .. ")")
                    goto continue_ability
                end

                -- Detect band abilities (heroic category from monster-features) - collect for MonsterGroup
                if string.find(compendiumSource, "monster-features") then
                    if abSystem.category == "heroic" then
                        -- Build description with same cleanup as other abilities
                        local desc = ""
                        if abSystem.effect then
                            if abSystem.effect.before and abSystem.effect.before ~= "" then
                                desc = desc .. abSystem.effect.before .. "\n"
                            end
                            if abSystem.effect.after and abSystem.effect.after ~= "" then
                                desc = desc .. abSystem.effect.after
                            end
                        end
                        desc = MCDMImporter.ReplaceSpecialCharactersWithASCII(desc)
                        desc = regex.ReplaceAll(desc, "<[^>]+>", "")
                        desc = regex.ReplaceAll(desc, "\\[\\[/damage (.-)\\]\\]\\{(.-)\\}", "$2")
                        desc = regex.ReplaceAll(desc, "\\[\\[/damage ([\\dd+\\-\\s]+?)\\s+([^\\]]+)\\]\\]", "$1 $2 damage")
                        desc = regex.ReplaceAll(desc, "\\[\\[/heal ([^\\]]+?) temporary\\]\\]", "$1 temporary Stamina")
                        desc = regex.ReplaceAll(desc, "\\[\\[/heal ([^\\]]+)\\]\\]", "$1 Stamina")
                        desc = regex.ReplaceAll(desc, "@UUID\\[[^\\]]*\\]\\{([^}]+)\\}", "$1")
                        desc = regex.ReplaceAll(desc, "\\[\\[/[Aa]pply [^\\]]+\\]\\]\\{([^}]+)\\}", "$1")
                        desc = regex.ReplaceAll(desc, "\\[\\[/[Aa]pply ([a-z]+) save\\]\\]", "$1 (save ends)")
                        desc = regex.ReplaceAll(desc, "\\[\\[/[Aa]pply ([a-z]+) turn\\]\\]", "$1 (EoT)")
                        desc = regex.ReplaceAll(desc, "\\[\\[/[Aa]pply ([a-z]+) encounter\\]\\]", "$1 (encounter)")
                        desc = regex.ReplaceAll(desc, "\\[\\[/[Aa]pply ([a-z]+) respite\\]\\]", "$1 (respite)")
                        desc = regex.ReplaceAll(desc, "\\[\\[/[Aa]pply ([a-z]+)\\]\\]", "$1")
                        desc = regex.ReplaceAll(desc, "\\[\\[/[Aa]pply [^\\]]+\\]\\]", "")

                        pendingBandAbilities[#pendingBandAbilities+1] = {
                            name = abilityName,
                            description = desc,
                            resource = tonumber(abSystem.resource),
                        }
                        import:Log("[DS-JSON] Collected band ability for MonsterGroup: " .. abilityName .. " (malice: " .. tostring(abSystem.resource) .. ")")
                    else
                        import:Log("[DS-JSON] Skipping non-band monster-features ability: " .. abilityName .. " (source: " .. compendiumSource .. ")")
                    end
                    goto continue_ability
                end

                -- Action Resource ID
                local actionNameMap = {
                    ["villain"] = "action",
                    ["main"] = "action",
                    ["maneuver"] = "maneuver",
                    ["triggered"] = "triggered action",
                    ["free"] = "free action",
                    ["freeTriggered"] = "free triggered action",
                }
                local actionName = actionNameMap[abSystem.type] or "action"
                local resourcesTable = dmhub.GetTable(CharacterResource.tableName)
                for k, resourceInfo in pairs(resourcesTable) do
                    if string.starts_with(actionName, string.lower(resourceInfo.name)) then
                        newAbility.actionResourceId = k
                    end
                end

                -- Keywords
                if abSystem.keywords and #abSystem.keywords > 0 then
                    for _, k in ipairs(abSystem.keywords) do
                        -- Capitalize first letter
                        local capitalizedK = k:sub(1, 1):upper() .. k:sub(2)
                        newAbility.keywords[capitalizedK] = true
                    end
                end

                -- Distance / Range
                local dist = abSystem.distance
                if dist then
                    newAbility.range = dist.primary or 1
                    if dist.type == "melee" then
                        -- Default is melee range 1 usually
                    elseif dist.type == "ranged" then
                        -- Range is the primary value
                    elseif dist.type == "burst" then
                        newAbility.targetType = "all"
                        newAbility.range = dist.primary
                        newAbility.numTargets = 1
                    elseif dist.type == "meleeRanged" then
                         newAbility.meleeRange = dist.primary
                         newAbility.range = dist.secondary
                    end
                end

                -- Target
                local targetObj = abSystem.target
                if targetObj then
                    newAbility.numTargets = targetObj.value or 1
                    -- target.type mapping: 'creatureObject', 'ally', 'special', 'enemyObject'
                    if string.find(targetObj.type or "", "ally") then
                        newAbility.targetFilter = "not Enemy"
                    elseif string.find(targetObj.type or "", "enemy") then
                         newAbility.targetFilter = "Enemy"
                    end
                end
                
                -- Power Rolls
                if abSystem.power and abSystem.power.roll then
                    -- Characteristics
                     local rollFormula = abSystem.power.roll.formula or ""

                    local hasPowerRoll = false
                    local powerRollEffects = {}
                    
                    if abSystem.power.effects then
                        -- The effects object keys are random IDs, we need to sort or find them.
                        -- Usually tier1, tier2, tier3.
                        local characteristicToAttributeMap = {
                            ["might"] = "mgt",
                            ["agility"] = "agl",
                            ["reason"] = "rea",
                            ["intuition"] = "inu",
                            ["presence"] = "prs"
                        }

                        local characteristicNameMap = {
                            ["might"] = "Might",
                            ["agility"] = "Agility",
                            ["reason"] = "Reason",
                            ["intuition"] = "Intuition",
                            ["presence"] = "Presence"
                        }

                        -- Find the highest attribute score across all characteristics
                        local highestAttributeScore = 0
                        for _, attrKey in pairs(characteristicToAttributeMap) do
                            if m.attributes[attrKey] then
                                local attrValue = m.attributes[attrKey].baseValue or 0
                                if attrValue > highestAttributeScore then
                                    highestAttributeScore = attrValue
                                end
                            end
                        end

                        for _, eff in pairs(abSystem.power.effects) do
                            if eff.type == "damage" and eff.damage then
                                hasPowerRoll = true
                                for tierNum = 1, 3 do
                                    local tierKey = "tier" .. tierNum
                                    local tierData = eff.damage[tierKey]
                                    local damageText = ""
                                    if tierData and tierData.value then
                                        local dmgTypes = ""
                                        if tierData.types and #tierData.types > 0 then
                                            dmgTypes = table.concat(tierData.types, "/") .. " "
                                        end
                                        damageText = tierData.value .. " " .. dmgTypes .. "damage"
                                    end
                                    if damageText ~= "" then
                                        if powerRollEffects[tierNum] and powerRollEffects[tierNum] ~= "" then
                                            powerRollEffects[tierNum] = damageText .. "; " .. powerRollEffects[tierNum]
                                        else
                                            powerRollEffects[tierNum] = damageText
                                        end
                                    end
                                end
                            elseif eff.type == "applied" and eff.applied then
                                hasPowerRoll = true
                                -- Handle applied effects (conditions, etc.)
                                -- Find the first non-empty display text to use as a template
                                local baseDisplay = ""
                                for tierNum = 1, 3 do
                                    local tierKey = "tier" .. tierNum
                                    if eff.applied[tierKey] and eff.applied[tierKey].display and eff.applied[tierKey].display ~= "" then
                                        baseDisplay = eff.applied[tierKey].display
                                        break
                                    end
                                end

                                -- Find first valid characteristic to use as fallback for tiers with empty characteristic
                                local inheritedCharacteristic = ""
                                for tierNum = 1, 3 do
                                    local tierKey = "tier" .. tierNum
                                    if eff.applied[tierKey] and eff.applied[tierKey].potency and eff.applied[tierKey].potency.characteristic and eff.applied[tierKey].potency.characteristic ~= "" and eff.applied[tierKey].potency.characteristic ~= "none" then
                                        inheritedCharacteristic = eff.applied[tierKey].potency.characteristic
                                        break
                                    end
                                end

                                -- Process each tier
                                for tierNum = 1, 3 do
                                    local tierKey = "tier" .. tierNum
                                    if eff.applied[tierKey] then
                                        local tierData = eff.applied[tierKey]

                                        -- Skip this tier if it has no display text AND no effects defined
                                        -- (empty display + empty effects = no condition on this tier)
                                        local hasEffects = tierData.effects and type(tierData.effects) == "table" and next(tierData.effects) ~= nil
                                        local hasDisplay = tierData.display and tierData.display ~= ""
                                        if not hasDisplay and not hasEffects then
                                            goto continue_applied_tier
                                        end

                                        local display = hasDisplay and tierData.display or baseDisplay

                                        -- Always strip {{potency}} template from display text
                                        display = display:gsub("{{potency}}%s*", "")

                                        -- Calculate and prepend characteristic with potency value
                                        local charName = (tierData.potency and tierData.potency.characteristic and tierData.potency.characteristic ~= "none" and tierData.potency.characteristic ~= "") and tierData.potency.characteristic or inheritedCharacteristic
                                        if tierData.potency and tierData.potency.value and charName ~= "" then
                                            local charFullName = characteristicNameMap[charName] or "?"

                                            -- Calculate potency value based on highest attribute score
                                            local potencyValue = highestAttributeScore
                                            if tierData.potency.value == "@potency.average" then
                                                potencyValue = highestAttributeScore - 1
                                            elseif tierData.potency.value == "@potency.weak" then
                                                potencyValue = highestAttributeScore - 2
                                            end

                                            -- Prepend characteristic and value to display (e.g., "M<0")
                                            display = charFullName:sub(1, 1) .. "<" .. potencyValue .. " " .. display
                                        end

                                        -- If display is still empty, build from effect name and end condition
                                        if display == "" and eff.name and eff.name ~= "" then
                                            local endType = ""
                                            if tierData.effects then
                                                for _, ce in pairs(tierData.effects) do
                                                    if ce["end"] and ce["end"] ~= "" then
                                                        local endLabels = {save = "save ends", turn = "EoT", encounter = "EoE"}
                                                        endType = endLabels[ce["end"]] or ce["end"]
                                                        break
                                                    end
                                                end
                                            end
                                            if endType ~= "" then
                                                display = string.lower(eff.name) .. " (" .. endType .. ")"
                                            else
                                                display = string.lower(eff.name)
                                            end
                                        end

                                        -- Append to powerRollEffects
                                        if display ~= "" then
                                            if powerRollEffects[tierNum] and powerRollEffects[tierNum] ~= "" then
                                                powerRollEffects[tierNum] = powerRollEffects[tierNum] .. "; " .. display
                                            else
                                                powerRollEffects[tierNum] = display
                                            end
                                        end
                                        ::continue_applied_tier::
                                    end
                                end
                            elseif eff.type == "forced" and eff.forced then
                                hasPowerRoll = true
                                local forceName = (eff.name and eff.name ~= "") and string.lower(eff.name) or "push"
                                for tierNum = 1, 3 do
                                    local tierKey = "tier" .. tierNum
                                    local tierData = eff.forced[tierKey]
                                    if tierData and tierData.distance and tierData.distance ~= "" then
                                        local forcedText = tierData.distance .. " " .. forceName
                                        if powerRollEffects[tierNum] and powerRollEffects[tierNum] ~= "" then
                                            powerRollEffects[tierNum] = powerRollEffects[tierNum] .. "; " .. forcedText
                                        else
                                            powerRollEffects[tierNum] = forcedText
                                        end
                                    end
                                end
                            elseif eff.type == "other" and eff.other then
                                hasPowerRoll = true
                                for tierNum = 1, 3 do
                                    local tierKey = "tier" .. tierNum
                                    if eff.other[tierKey] and eff.other[tierKey].display and eff.other[tierKey].display ~= "" then
                                        local display = eff.other[tierKey].display
                                        if powerRollEffects[tierNum] and powerRollEffects[tierNum] ~= "" then
                                            powerRollEffects[tierNum] = powerRollEffects[tierNum] .. "; " .. display
                                        else
                                            powerRollEffects[tierNum] = display
                                        end
                                    end
                                end
                            end
                        end
                    end

                    if hasPowerRoll then
                        import:Log("[DS-JSON] Getting standard ability for power roll...")
                        local abilityPowerRoll = MCDMImporter.GetStandardAbility("Ability Power Roll")
                        import:Log("[DS-JSON] Got standard ability: " .. tostring(abilityPowerRoll ~= nil))
                        if abilityPowerRoll then
                             for _,behavior in ipairs(abilityPowerRoll.behaviors) do
                                local b = DeepCopy(behavior)
                                b.tiers = powerRollEffects
                                if abSystem.power.roll and abSystem.power.roll.characteristics and #abSystem.power.roll.characteristics > 0 then
                                    local nameMap = {might = "Might", agility = "Agility", reason = "Reason", intuition = "Intuition", presence = "Presence"}
                                    local charNames = {}
                                    for _, charKey in ipairs(abSystem.power.roll.characteristics) do
                                        charNames[#charNames+1] = nameMap[charKey] or charKey
                                    end
                                    b.roll = GameSystem.BaseAttackRoll .. " + " .. table.concat(charNames, " or ")
                                else
                                    b.roll = GameSystem.BaseAttackRoll .. " + Power Roll Bonus"
                                end
                                newAbility.behaviors[#newAbility.behaviors+1] = b
                            end
                        end
                    end
                end
                
                -- Effects / Description
                local desc = ""
                if abSystem.effect then
                    if abSystem.effect.before and abSystem.effect.before ~= "" then
                        desc = desc .. abSystem.effect.before .. "\n"
                    end
                    if abSystem.effect.after and abSystem.effect.after ~= "" then
                        desc = desc .. abSystem.effect.after
                    end
                end

                -- Replace special characters and apostrophes FIRST
                desc = MCDMImporter.ReplaceSpecialCharactersWithASCII(desc)
                -- Then clean HTML
                newAbility.description = regex.ReplaceAll(desc, "<[^>]+>", "")
                newAbility.description = regex.ReplaceAll(newAbility.description, "\\[\\[/damage (.-)\\]\\]\\{(.-)\\}", "$2") -- Simplify damage tags [[/damage 2]]{2 damage} -> 2 damage
                newAbility.description = regex.ReplaceAll(newAbility.description, "\\[\\[/damage ([\\dd+\\-\\s]+?)\\s+([^\\]]+)\\]\\]", "$1 $2 damage") -- Simplify [[/damage 2d6 lightning]] -> 2d6 lightning damage
                newAbility.description = regex.ReplaceAll(newAbility.description, "\\[\\[/heal ([^\\]]+?) temporary\\]\\]", "$1 temporary Stamina") -- Simplify [[/heal 10 temporary]] -> 10 temporary Stamina
                newAbility.description = regex.ReplaceAll(newAbility.description, "\\[\\[/heal ([^\\]]+)\\]\\]", "$1 Stamina") -- Simplify [[/heal 4]] -> 4 Stamina
                newAbility.description = regex.ReplaceAll(newAbility.description, "@UUID\\[[^\\]]*\\]\\{([^}]+)\\}", "$1") -- Replace @UUID[...]{Display Name} -> Display Name
                -- Clean [[/apply ...]] and [[/Apply ...]] enricher tags
                newAbility.description = regex.ReplaceAll(newAbility.description, "\\[\\[/[Aa]pply [^\\]]+\\]\\]\\{([^}]+)\\}", "$1") -- With display text: use it
                newAbility.description = regex.ReplaceAll(newAbility.description, "\\[\\[/[Aa]pply ([a-z]+) save\\]\\]", "$1 (save ends)") -- Named condition + save
                newAbility.description = regex.ReplaceAll(newAbility.description, "\\[\\[/[Aa]pply ([a-z]+) turn\\]\\]", "$1 (EoT)") -- Named condition + turn
                newAbility.description = regex.ReplaceAll(newAbility.description, "\\[\\[/[Aa]pply ([a-z]+) encounter\\]\\]", "$1 (encounter)") -- Named condition + encounter
                newAbility.description = regex.ReplaceAll(newAbility.description, "\\[\\[/[Aa]pply ([a-z]+) respite\\]\\]", "$1 (respite)") -- Named condition + respite
                newAbility.description = regex.ReplaceAll(newAbility.description, "\\[\\[/[Aa]pply ([a-z]+)\\]\\]", "$1") -- Named condition, no duration
                newAbility.description = regex.ReplaceAll(newAbility.description, "\\[\\[/[Aa]pply [^\\]]+\\]\\]", "") -- Raw IDs without display text: strip


                -- Resource Cost (Malice/Heroic)
                if abSystem.resource then
                    if newAbility.categorization == "Heroic Ability" then
                        newAbility.resourceCost = CharacterResource.heroicResourceId
                        newAbility.resourceNumber = tonumber(abSystem.resource)
                    else
                        newAbility.resourceCost = CharacterResource.maliceResourceId
                        newAbility.resourceNumber = tonumber(abSystem.resource)
                    end
                end
                
                if abSystem.source and abSystem.source.page then
                    newAbility.sourceReference = SourceReference.new{
                        page = tonumber(abSystem.source.page) or 1,
                        docid = abSystem.source.book == "Monsters" and "cc66844a-04d0-49a0-8687-65ef83b15363" or "none",
                    }
                end

                if newAbility:try_get("implementation") == nil then
                    newAbility.implementation = 2
                end

                m.innateActivatedAbilities[#m.innateActivatedAbilities+1] = newAbility

                -- Add per-ability report entry
                local abilityReport = {}
                abilityReport[#abilityReport+1] = bestiaryEntry.name
                abilityReport[#abilityReport+1] = newAbility.name

                local statusOptions = {"Unimplemented", "Partial", "Implemented", "Won't Implement"}
                local implementation = newAbility:try_get("implementation", 1)
                implementation = statusOptions[implementation] or "Unknown"
                abilityReport[#abilityReport+1] = implementation

                importReport[#importReport+1] = abilityReport

                ::continue_ability::
            end
        end
    end

    m.characterFeatures = creatureTraits

    -- Trait names (from feature items)
    m.traitNames = {}
    for _, feature in ipairs(creatureTraits) do
        m.traitNames[#m.traitNames+1] = feature.name
    end

    -- With Captain effect (from actor-level effects array, fallback only)
    -- Items with _dsid="with-captain" are the canonical source (set above).
    -- Only use actor-level effects if we didn't already get a value from items.
    if m.withCaptain == nil and data.effects then
        for _, effect in ipairs(data.effects) do
            if effect.name and string.lower(effect.name):find("with.*captain") then
                local desc = effect.description or ""
                -- Strip HTML tags
                desc = regex.ReplaceAll(desc, "<[^>]+>", "")
                desc = trim(desc)
                if desc ~= "" then
                    m.withCaptain = desc
                    import:Log("[DS-JSON] With Captain (from actor effect): " .. desc)
                else
                    import:Log("[DS-JSON] With Captain: (empty actor effect description, skipping)")
                end
                break
            end
        end
    end

    -- Languages (from system.biography.languages)
    if data.system and data.system.biography and data.system.biography.languages then
        local langTable = dmhub.GetTable(Language.tableName) or {}
        local creatureLanguages = {}
        local customLanguages = {}
        for _, langName in ipairs(data.system.biography.languages) do
            local found = false
            for langid, langInfo in pairs(langTable) do
                if string.lower(langInfo.name) == string.lower(langName) then
                    creatureLanguages[langid] = true
                    found = true
                    break
                end
            end
            if not found then
                customLanguages[#customLanguages+1] = langName
            end
        end
        m.innateLanguages = creatureLanguages
        if #customLanguages > 0 then
            m.customInnateLanguage = string.join(customLanguages, ",")
        end
        import:Log("[DS-JSON] Languages: " .. tostring(#data.system.biography.languages) .. " entries")
    end

    -- Comprehensive import log
    import:Log("=== [DS-JSON] IMPORT SUMMARY ===")
    import:Log("[DS-JSON] Monster Name: " .. tostring(bestiaryEntry.name))
    import:Log("[DS-JSON] HP: " .. tostring(m.max_hitpoints))
    import:Log("[DS-JSON] Size: " .. tostring(m.creatureSize))
    import:Log("[DS-JSON] Speed: " .. tostring(m.walkingSpeed))
    import:Log("[DS-JSON] Stability: " .. tostring(m.stability))
    import:Log("[DS-JSON] EV: " .. tostring(m.ev))
    import:Log("[DS-JSON] Role: " .. tostring(m.role))
    import:Log("[DS-JSON] Keywords count: " .. (m.keywords and #m.keywords or "nil"))

    import:Log("[DS-JSON] Attributes:")
    import:Log("[DS-JSON]   Might: " .. tostring(m.attributes["mgt"] and m.attributes["mgt"].baseValue or "nil"))
    import:Log("[DS-JSON]   Agility: " .. tostring(m.attributes["agl"] and m.attributes["agl"].baseValue or "nil"))
    import:Log("[DS-JSON]   Reason: " .. tostring(m.attributes["rea"] and m.attributes["rea"].baseValue or "nil"))
    import:Log("[DS-JSON]   Intuition: " .. tostring(m.attributes["inu"] and m.attributes["inu"].baseValue or "nil"))
    import:Log("[DS-JSON]   Presence: " .. tostring(m.attributes["prs"] and m.attributes["prs"].baseValue or "nil"))

    import:Log("[DS-JSON] Abilities imported: " .. tostring(#m.innateActivatedAbilities))
    for i, ability in ipairs(m.innateActivatedAbilities) do
        import:Log("[DS-JSON]   " .. i .. ". " .. ability.name .. " (cat: " .. ability.categorization .. ")")
    end

    import:Log("[DS-JSON] Features imported: " .. tostring(#creatureTraits))
    for i, feature in ipairs(creatureTraits) do
        import:Log("[DS-JSON]   " .. i .. ". " .. feature.name)
    end
    import:Log("=== [DS-JSON] END SUMMARY ===")

    -- Import Log / Storing
    local report = {}
    report[#report+1] = bestiaryEntry.name
    report[#report+1] = "Monster"
    report[#report+1] = "JSON IMPORT"
    local cr = m.cr or 1
    if cr <= 3 then
        report[#report+1] = "1"
    elseif cr <= 6 then
        report[#report+1] = "2"
    elseif cr <= 9 then
        report[#report+1] = "3"
    else
        report[#report+1] = "4"
    end
    importReport[#importReport+1] = report

    bestiaryEntry.properties.import = {
        type = "draw-steel-json",
        data = jsonContent,
    }

    -- Monster folder and group setup (for malice ability lookup)
    local folderName = m:try_get("monster_category")
    if folderName ~= nil and folderName ~= "" and folderName ~= "Monster" then
        local folder = import:GetExistingItem("monsterFolder", folderName)
        if folder == nil then
            folder = import:CreateMonsterFolder(folderName)
            import:ImportMonsterFolder(folder)
            import:Log("[DS-JSON] Created monster folder: " .. folderName)
        end
        bestiaryEntry.parentFolder = folder.id

        -- Find or create MonsterGroup for malice ability association
        local monsterGroup = import:GetExistingItem(MonsterGroup.tableName, folderName)
        if monsterGroup == nil then
            monsterGroup = MonsterGroup.CreateNew{
                name = folderName,
            }
            import:ImportAsset(MonsterGroup.tableName, monsterGroup)
            import:Log("[DS-JSON] Created monster group: " .. folderName)
        end
        m.groupid = monsterGroup.id

        -- Add pending band abilities to the MonsterGroup
        if #pendingBandAbilities > 0 then
            local addedCount = 0
            for _, bandAb in ipairs(pendingBandAbilities) do
                -- Deduplicate by name
                local exists = false
                for _, existing in ipairs(monsterGroup.maliceAbilities) do
                    if existing.name == bandAb.name then
                        exists = true
                        break
                    end
                end
                if not exists then
                    local a = MaliceAbility.Create{
                        name = bandAb.name,
                    }
                    a.description = bandAb.description
                    a.resourceCost = CharacterResource.maliceResourceId
                    a.resourceNumber = bandAb.resource
                    monsterGroup.maliceAbilities[#monsterGroup.maliceAbilities+1] = a
                    addedCount = addedCount + 1
                    import:Log(FormatSuccess("[DS-JSON] Added band malice ability to " .. folderName .. ": " .. bandAb.name .. " (malice: " .. tostring(bandAb.resource) .. ")"))
                end
            end
            if addedCount > 0 then
                import:ImportAsset(MonsterGroup.tableName, monsterGroup)
                import:Log("[DS-JSON] Re-uploaded monster group with " .. addedCount .. " new malice abilities")
            end
        end
    end

    import:StoreLogFromBookmark(bookmark, bestiaryEntry)
    import:Log("-")
    import:Log(bestiaryEntry.name .. " (Level " .. tostring(m.cr) .. ")")
    local success = import:ImportMonster(bestiaryEntry)
    if success == false then
        import:Log(FormatError("FAILED to import: Item may be locked/overridden. Check if '" .. bestiaryEntry.name .. "' is marked as 'overridden' in the compendium."))
    else
        import:Log(FormatSuccess("Imported"))
    end

end

MCDMImporter.ImportFolder = function(importer, folderPath)
    import:Log("[DS-JSON] Starting folder import from: " .. tostring(folderPath))

    local jsonFiles = {}
    local fileSystem = dmhub.GetFileSystem()
    if not fileSystem then
        import:Log(FormatError("[DS-JSON] File system not available"))
        return
    end

    -- List all files in the folder
    local files = fileSystem:ListFiles(folderPath)
    if not files then
        import:Log(FormatError("[DS-JSON] Could not read folder: " .. folderPath))
        return
    end

    -- Filter for JSON files
    for _, fileName in ipairs(files) do
        if string.match(fileName, "%.json$") then
            table.insert(jsonFiles, fileName)
        end
    end

    import:Log("[DS-JSON] Found " .. tostring(#jsonFiles) .. " JSON files")

    -- Import each file
    for _, fileName in ipairs(jsonFiles) do
        local filePath = folderPath .. "/" .. fileName
        import:Log("[DS-JSON] Importing: " .. fileName)

        local content = fileSystem:ReadFile(filePath)
        if content then
            MCDMImporter.ImportJSON(importer, content)
        else
            import:Log(FormatError("[DS-JSON] Failed to read file: " .. fileName))
        end
    end

    import:Log("[DS-JSON] Folder import completed")
end

import.Register{
    id = "draw-steel-json",
    description = "Draw Steel JSON (Foundry)",
    input = "files",
    extensions = {"json"},
    priority = 300,

    renderLog = MCDMImporter.renderLog,

    json = function(importer, content, filename)
        import:Log("[DS-JSON] Direct handler called!")
        MCDMImporter.ImportJSON(importer, content)
    end,

    text = function(importer, content)
        import:Log("[DS-JSON] Text handler called, redirecting to JSON parser...")
        MCDMImporter.ImportJSON(importer, content)
    end,
}

import.Register{
    id = "draw-steel-json-folder",
    description = "Draw Steel JSON Folder (Foundry)",
    input = "folder",
    priority = 300,

    renderLog = MCDMImporter.renderLog,

    folder = function(importer, folderPath)
        import:Log("[DS-JSON] Folder handler called!")
        MCDMImporter.ImportFolder(importer, folderPath)
    end
}


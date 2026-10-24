local mod = dmhub.GetModLoading()

--PROTOTYPE: the back of the hero card (EotwHeroCard.lua), for heroes and
--monsters alike: the tac panel's information (MCDMCharacterPanel.lua) laid
--out on the card's own face, turned over by a hover button. What the front
--already shows (stamina, recoveries, resource) is kept to one slim strip.
--Every read is pcall-guarded: one missing rule must not blank the back.

--the design width the back is laid out at before it is scaled onto the card;
--narrower makes the text larger on the card.
local BACK_WIDTH = 350
local PAD = 18
local INNER_WIDTH = BACK_WIDTH - PAD * 2

local COLOR_TEXT = "#eef1f4"
local COLOR_SOFT = "#c6d0da"
local COLOR_MUTED = "#9aa6b2"
local COLOR_PLATE = "#1e2228"
local COLOR_GOLD = "#ffd66b"
local COLOR_BLUE = "#6fa8ff"
local COLOR_TEMP = "#9cc4ff"
local COLOR_STAMINA = "#4caf6a"
local COLOR_RESOURCE = "#ffc98f"

local function Try(fn, default)
    local ok, result = pcall(fn)
    if ok and result ~= nil then
        return result
    end
    return default
end

local function Signed(n)
    n = tonumber(n) or 0
    if n == 0 then
        return "0"
    end
    return string.format("%+d", n)
end

local function Text(args)
    args.width = args.width or "100%"
    args.height = args.height or "auto"
    args.fontSize = args.fontSize or 12
    args.color = args.color or COLOR_SOFT
    args.textAlignment = args.textAlignment or "left"
    args.textWrap = args.textWrap ~= false
    args.interactable = false
    return gui.Label(args)
end

local function SectionLabel(text, color)
    return Text{
        text = string.upper(text),
        fontSize = 11,
        bold = true,
        color = color or COLOR_MUTED,
        bmargin = 2,
    }
end

local function Divider()
    return gui.Panel{
        width = "100%",
        height = 1,
        bgimage = "panels/square.png",
        bgcolor = "#ffffff1c",
        interactable = false,
    }
end

--- Header --------------------------------------------------------------------

local function Header(tok, c)
    local portrait = gui.Panel{
        width = 50,
        height = 50,
        valign = "center",
        --a circle is the shape itself, not a theme corner.
        cornerRadius = 25,
        border = 2,
        borderColor = COLOR_BLUE,
        bgimage = "panels/square.png",
        bgcolor = "#2b3440",
        interactable = false,
    }
    pcall(function() EotwHeroCard.ApplyPortrait(portrait, tok, 1) end)

    local classItem = Try(function() return c:GetClass() end)
    local className = classItem and classItem.name or nil
    local subclass = classItem and Try(function() return c:GetSubClass(classItem) end) or nil
    local level = Try(function() return c:CharacterLevel() end, 1)

    local line2 = string.format("Level %d", level)
    if className ~= nil then
        line2 = line2 .. " " .. className
    end
    if subclass ~= nil and subclass.name ~= nil then
        line2 = line2 .. " - " .. subclass.name
    end

    local parts = {}
    local ancestry = Try(function() return c:RaceOrMonsterType() end)
    if ancestry ~= nil and ancestry ~= "" then
        parts[#parts+1] = ancestry
    end
    local kit = Try(function() return c:Kit() end)
    if kit ~= nil and kit.name ~= nil then
        parts[#parts+1] = kit.name .. " kit"
    end
    local owner = Try(function() return tok.ownerId end)
    if owner ~= nil and owner ~= "" and owner ~= "PARTY" then
        parts[#parts+1] = Try(function() return dmhub.GetDisplayName(owner) end, owner)
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        interactable = false,
        portrait,
        gui.Panel{
            width = INNER_WIDTH - 50 - 11 - 44,
            height = "auto",
            lmargin = 11,
            valign = "center",
            flow = "vertical",
            interactable = false,
            Text{
                text = EotwHeroCard.HeroDisplayName(tok),
                fontSize = 24,
                bold = true,
                color = COLOR_TEXT,
                textWrap = false,
            },
            Text{ text = line2, fontSize = 13 },
            Text{ text = table.concat(parts, " - "), fontSize = 12, color = COLOR_MUTED },
        },
        gui.Panel{
            width = 44,
            height = "auto",
            valign = "center",
            flow = "vertical",
            interactable = false,
            Text{ text = tostring(level), fontSize = 24, bold = true, color = COLOR_GOLD, textAlignment = "center" },
            Text{ text = "LEVEL", fontSize = 10, bold = true, color = COLOR_MUTED, textAlignment = "center" },
        },
    }
end

--- Stamina strip -------------------------------------------------------------

local function IsHeroProps(c)
    return Try(function() return c:IsHero() end, false) == true
end

local function StaminaStrip(c)
    local isHero = IsHeroProps(c)
    local cur = Try(function() return c:CurrentHitpoints() end, 0)
    local max = Try(function() return c:MaxHitpoints() end, 0)
    local temp = Try(function() return c:TemporaryHitpoints() end, 0)
    local winded = Try(function() return c:BloodiedThreshold() end, math.floor(max / 2))

    local recCurrent, recMax, recValue = 0, 0, nil
    pcall(function()
        local id = CharacterResource.recoveryResourceId
        recMax = c:GetResources()[id] or 0
        local used = c:GetResourceUsage(id, "long") or 0
        recCurrent = math.max(0, recMax - used)
        recValue = c:RecoveryAmount()
    end)
    local victories = Try(function() return c:GetVictories() end, 0)
    local heroTokens = Try(function() return c:GetHeroTokens() end, 0)

    local barWidth = INNER_WIDTH - 20
    local function Px(value)
        if max <= 0 then
            return 0
        end
        return math.floor(barWidth * math.max(0, math.min(1, value / max)))
    end
    local fillWidth = Px(cur)
    local tempWidth = math.min(barWidth - fillWidth, Px(temp))

    local numbers = string.format("<b><color=%s>%d</color></b> / %d", COLOR_TEXT, cur, max)
    if temp > 0 then
        numbers = numbers .. string.format("   <color=%s>+%d temp</color>", COLOR_TEMP, temp)
    end

    local recText = string.format("Recoveries <b><color=%s>%d/%d</color></b>", COLOR_TEXT, recCurrent, recMax)
    if recValue ~= nil then
        recText = recText .. string.format(" (%d each)", recValue)
    end

    --heroes only: monsters have no recoveries, victories or hero tokens.
    local bottomRow
    if isHero then
        bottomRow = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            interactable = false,
            Text{ text = recText, fontSize = 11.5, color = COLOR_MUTED, width = "46%", textWrap = false },
            Text{ text = string.format("Victories <b><color=%s>%d</color></b>", COLOR_TEXT, victories), fontSize = 11.5, color = COLOR_MUTED, width = "24%", textAlignment = "center", textWrap = false },
            Text{ text = string.format("Hero Tokens <b><color=%s>%d</color></b>", COLOR_TEXT, heroTokens), fontSize = 11.5, color = COLOR_MUTED, width = "30%", textAlignment = "right", textWrap = false },
        }
    else
        bottomRow = gui.Panel{ width = 1, height = 1, interactable = false }
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        hpad = 10,
        vpad = 6,
        borderBox = true,
        bgimage = "panels/square.png",
        bgcolor = COLOR_PLATE,
        interactable = false,
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            interactable = false,
            Text{ text = numbers, fontSize = 13, color = COLOR_MUTED, width = "60%" },
            Text{ text = string.format("Winded at %d", winded), fontSize = 11, color = COLOR_MUTED, width = "40%", textAlignment = "right" },
        },
        gui.Panel{
            width = barWidth,
            height = 6,
            vmargin = 4,
            bgimage = "panels/square.png",
            bgcolor = "#00000080",
            interactable = false,
            gui.Panel{
                floating = true,
                halign = "left",
                width = fillWidth,
                height = "100%",
                bgimage = "panels/square.png",
                bgcolor = COLOR_STAMINA,
                interactable = false,
            },
            gui.Panel{
                floating = true,
                halign = "left",
                x = fillWidth,
                width = tempWidth,
                height = "100%",
                bgimage = "panels/square.png",
                bgcolor = COLOR_TEMP,
                interactable = false,
            },
            gui.Panel{
                floating = true,
                halign = "left",
                x = Px(winded),
                width = 2,
                height = "100%",
                bgimage = "panels/square.png",
                bgcolor = "#151515",
                interactable = false,
            },
        },
        bottomRow,
    }
end

--- Characteristics -----------------------------------------------------------

local function Characteristics(c)
    local attrs = {}
    pcall(function()
        attrs = table.values(creature.attributesInfo)
        table.sort(attrs, function(a, b) return a.order < b.order end)
    end)

    local values = {}
    local best = nil
    for i, attr in ipairs(attrs) do
        local v = Try(function() return c:GetAttribute(attr.id):Modifier() end, 0)
        values[i] = v
        if best == nil or v > best then
            best = v
        end
    end

    local cells = {}
    local cellWidth = math.floor(INNER_WIDTH / math.max(1, #attrs))
    for i, attr in ipairs(attrs) do
        local top = values[i] == best and best > 0
        cells[#cells+1] = gui.Panel{
            width = cellWidth,
            height = "auto",
            flow = "vertical",
            interactable = false,
            gui.Panel{
                width = 38,
                height = 34,
                halign = "center",
                bgimage = "panels/square.png",
                bgcolor = cond(top, COLOR_GOLD, COLOR_PLATE),
                border = cond(top, 0, 1),
                borderColor = "#5a6672",
                interactable = false,
                Text{
                    text = Signed(values[i]),
                    fontSize = 18,
                    bold = true,
                    color = cond(top, "#1a1200", COLOR_TEXT),
                    textAlignment = "center",
                    height = "100%",
                    valign = "center",
                },
            },
            Text{
                text = attr.description,
                fontSize = 11,
                bold = top,
                color = cond(top, COLOR_GOLD, COLOR_SOFT),
                textAlignment = "center",
                tmargin = 3,
            },
        }
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        interactable = false,
        children = cells,
    }
end

--- Movement line -------------------------------------------------------------

local function MovementLine(c)
    local function Stat(name, value)
        return string.format("%s <b><color=%s>%s</color></b>", name, COLOR_TEXT, tostring(value))
    end

    local parts = {}
    local speed = Try(function() return c:CurrentMovementSpeed() end)
    if speed ~= nil then
        parts[#parts+1] = Stat("Speed", speed)
    end
    local disengage = Try(function()
        return c:GetCustomAttribute(CustomAttribute.attributeInfoByLookupSymbol["disengagespeed"])
    end)
    if disengage ~= nil then
        parts[#parts+1] = Stat("Disengage", disengage)
    end
    local stability = Try(function() return c:Stability() end)
    if stability ~= nil then
        parts[#parts+1] = Stat("Stability", stability)
    end
    local size = Try(function() return c:SizeDescription() end)
    if size ~= nil and size ~= "" then
        parts[#parts+1] = Stat("Size", size)
    end
    if not IsHeroProps(c) then
        local freeStrike = Try(function() return c:OpportunityAttack() end)
        if freeStrike ~= nil then
            parts[#parts+1] = Stat("Free strike", freeStrike)
        end
    end

    local moveType = Try(function() return c:CurrentMoveType() end)
    if moveType == "fly" then
        parts[#parts+1] = "Flying"
    elseif moveType == "burrow" then
        parts[#parts+1] = "Burrowing"
    elseif Try(function() return c:IsClingingToCeiling() end, false) then
        parts[#parts+1] = "Clinging"
    elseif moveType == "climb" then
        parts[#parts+1] = "Climbing"
    end
    --"On ground" is the usual state and is left unsaid.

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        interactable = false,
        Divider(),
        Text{
            text = table.concat(parts, "     "),
            fontSize = 12,
            color = COLOR_MUTED,
            textAlignment = "center",
            vmargin = 4,
        },
        Divider(),
    }
end

--- Conditions, effects, immunities -------------------------------------------

local function DurationText(duration)
    if duration == "eot" then
        return "EoT"
    elseif duration == "eoe" then
        return "EoE"
    elseif duration == "save" then
        return "save ends"
    elseif type(duration) == "string" and duration ~= "" then
        return string.upper(duration) .. " ends"
    end
    return "EoT"
end

local function Chip(text, fill, border, color)
    return gui.Panel{
        width = "auto",
        height = "auto",
        hpad = 7,
        vpad = 2,
        rmargin = 5,
        bmargin = 5,
        bgimage = "panels/square.png",
        bgcolor = fill,
        border = 1,
        borderColor = border,
        interactable = false,
        gui.Label{
            text = text,
            width = "auto",
            height = "auto",
            fontSize = 11.5,
            bold = true,
            color = color,
            textWrap = false,
            interactable = false,
        },
    }
end

--TacPanel lives in a game-side mod; the titlescreen never loads it.
local function CleanResistanceText(text)
    local tacPanel = rawget(_G, "TacPanel")
    if tacPanel ~= nil and tacPanel.CleanResistanceText ~= nil then
        return tacPanel.CleanResistanceText(text)
    end
    return text
end

local function Effects(c)
    local chips = {}

    local conditionsTable = Try(function() return dmhub.GetTable(CharacterCondition.tableName) end, {})
    local inflicted = Try(function() return c:try_get("inflictedConditions", {}) end, {})
    for condid, condEntry in pairs(inflicted) do
        local info = conditionsTable[condid]
        if info ~= nil then
            local text = info.name
            if not info.indefiniteDuration then
                text = text .. " - " .. DurationText(condEntry.duration)
            end
            chips[#chips+1] = Chip(text, "#4a1716", "#cc2222", "#ffd9d6")
        end
    end

    local effectsTable = Try(function() return dmhub.GetTable("characterOngoingEffects") end, {})
    local effects = Try(function() return c:ActiveOngoingEffects() end, {})
    for _, entry in ipairs(effects) do
        local info = effectsTable[entry.ongoingEffectid]
        if info ~= nil and info.statusEffect then
            local text = info.name
            local stacks = Try(function() return entry.stacks end, 1)
            if stacks > 1 then
                text = text .. " x" .. stacks
            end
            local remaining = Try(function() return entry:DescribeTimeRemaining() end)
            if remaining ~= nil and remaining ~= "" then
                text = text .. " - " .. remaining
            end
            chips[#chips+1] = Chip(text, "#3d2512", "#c46a1c", "#ffe2c2")
        end
    end

    local immunities, weaknesses = {}, {}
    pcall(function()
        for _, e in ipairs(c:ResistanceEntries()) do
            local dr = e.entry:try_get("dr", 0)
            local label = CleanResistanceText(e.text) .. " " .. math.abs(dr)
            if dr < 0 then
                weaknesses[#weaknesses+1] = label
            else
                immunities[#immunities+1] = label
            end
        end
    end)
    local conditionImmunity = Try(function() return c:ConditionImmunityDescription() end)
    if conditionImmunity ~= nil and conditionImmunity ~= "" then
        immunities[#immunities+1] = conditionImmunity
    end

    local defenseParts = {}
    if #immunities > 0 then
        defenseParts[#defenseParts+1] = string.format("<color=%s>Immunity</color> %s", COLOR_MUTED, table.concat(immunities, ", "))
    end
    if #weaknesses > 0 then
        defenseParts[#defenseParts+1] = string.format("<color=%s>Weakness</color> %s", COLOR_MUTED, table.concat(weaknesses, ", "))
    end
    local defenseText = table.concat(defenseParts, "   ")
    if defenseText == "" then
        defenseText = string.format("<color=%s>No immunities or weaknesses</color>", COLOR_MUTED)
    end

    local children = {}
    if #chips > 0 then
        children[#children+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            interactable = false,
            children = chips,
        }
    end
    children[#children+1] = Text{ text = defenseText, fontSize = 11.5 }

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        interactable = false,
        children = children,
    }
end

--- Heroic resource gains -----------------------------------------------------

local function TwoColumnRow(left, right, rightColor, dim)
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        opacity = cond(dim, 0.45, 1),
        interactable = false,
        Text{ text = left, fontSize = 12, width = INNER_WIDTH - 90 },
        Text{ text = right, fontSize = 12, bold = true, color = rightColor or COLOR_TEXT, width = 90, textAlignment = "right" },
    }
end

local function ResourceGains(c)
    local checklist = Try(function() return c:GetHeroicResourceChecklist() end, {})
    if #checklist == 0 then
        return nil
    end
    local resourceName = Try(function() return c:GetHeroicResourceName() end, "Heroic Resource")
    local record = Try(function() return c:try_get("heroicResourceRecord") end)
    local q = dmhub.initiativeQueue
    local inCombat = q ~= nil and not q.hidden

    ---@type Panel[]
    local rows = { SectionLabel("Gain " .. resourceName, COLOR_RESOURCE) }
    for _, entry in ipairs(checklist) do
        --quantities are GoblinScript ("Victories", "1 + 1 when level >= 4"):
        --evaluate them as the tac panel does. A dice expression stays as
        --written, so the card reads "+1d3" rather than one random roll.
        local quantity = tostring(entry.quantity or 1)
        local amount = tonumber(quantity)
        if amount == nil and not string.find(quantity, "%d+d%d+") then
            amount = Try(function() return dmhub.EvalGoblinScript(quantity, c:LookupSymbol()) end)
        end
        local amountText = "+" .. quantity
        if tonumber(amount) ~= nil then
            amountText = string.format("+%d", tonumber(amount))
        end
        --spent this turn/encounter: dimmed, as the tac panel checks it off.
        local consumed = false
        if inCombat and record ~= nil and entry.mode ~= "recurring" then
            consumed = Try(function()
                return record[entry.guid] == c:GetResourceRefreshId(entry.mode or "encounter")
            end, false)
        end
        rows[#rows+1] = TwoColumnRow(entry.name or "", amountText, nil, consumed)
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        interactable = false,
        children = rows,
    }
end

--- Persistent abilities (combat only) ----------------------------------------

local function PersistentAbilities(c)
    local q = dmhub.initiativeQueue
    if q == nil or q.hidden then
        return nil
    end
    local resourceName = Try(function() return c:GetHeroicResourceName() end, "")
    local rows = {}
    for _, entry in ipairs(Try(function() return c:try_get("persistentAbilities") end, {})) do
        if entry.combatid == q.guid then
            rows[#rows+1] = TwoColumnRow(entry.abilityName or "", string.format("%d %s / turn", entry.cost or 0, resourceName), COLOR_RESOURCE)
        end
    end
    if #rows == 0 then
        return nil
    end
    table.insert(rows, 1, SectionLabel("Persistent"))
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        interactable = false,
        children = rows,
    }
end

--- Skills, languages, perks, notes -------------------------------------------

local function LabelledLine(label, text)
    return Text{
        text = string.format("<b><color=%s>%s</color></b>  %s", COLOR_MUTED, string.upper(label), text),
        fontSize = 12,
        bmargin = 3,
    }
end

local function SkillsText(c)
    local names = {}
    pcall(function()
        for _, cat in ipairs(Skill.categories) do
            local group = {}
            for _, skill in ipairs(Skill.SkillsInfo) do
                if skill.category == cat.id and c:ProficientInSkill(skill) then
                    group[#group+1] = skill.name
                end
            end
            table.sort(group)
            for _, name in ipairs(group) do
                names[#names+1] = name
            end
        end
    end)
    return table.concat(names, ", ")
end

local function LanguagesText(c)
    local names = {}
    pcall(function()
        local languages = dmhub.GetTableVisible(Language.tableName)
        for langid, _ in pairs(c:LanguagesKnown()) do
            local lang = languages[langid]
            if lang ~= nil then
                names[#names+1] = lang.name
            end
        end
    end)
    table.sort(names)
    return table.concat(names, ", ")
end

local function PerksText(c)
    local names = {}
    pcall(function()
        local levelChoices = c:GetLevelChoices()
        local feats = dmhub.GetTableVisible(CharacterFeat.tableName)
        for _, entry in ipairs(FeatureCategoriser.BuildIndexCached(c).features) do
            local feature = entry.feature
            if feature ~= nil and feature.typeName == "CharacterFeatChoice" then
                for _, guid in ipairs(levelChoices[feature.guid] or {}) do
                    local feat = feats[guid]
                    if feat ~= nil then
                        names[#names+1] = feat.name
                    end
                end
            end
        end
    end)
    return table.concat(names, ", ")
end

local function NotesText(c)
    for _, note in ipairs(Try(function() return c:try_get("notes") end, {})) do
        if note.text ~= nil and note.text ~= "" then
            local text = note.text
            if #text > 140 then
                text = string.sub(text, 1, 137) .. "..."
            end
            return text
        end
    end
    return nil
end

local function Details(c)
    local lines = {}
    local skills = SkillsText(c)
    if skills ~= "" then
        lines[#lines+1] = LabelledLine("Skills", skills)
    end
    local languages = LanguagesText(c)
    if languages ~= "" then
        lines[#lines+1] = LabelledLine("Languages", languages)
    end
    local perks = PerksText(c)
    if perks ~= "" then
        lines[#lines+1] = LabelledLine("Perks", perks)
    end
    local notes = NotesText(c)
    if notes ~= nil then
        lines[#lines+1] = Divider()
        lines[#lines+1] = LabelledLine("Notes", string.format("<i>%s</i>", notes))
    end
    if #lines == 0 then
        return nil
    end
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        interactable = false,
        children = lines,
    }
end

--- Monster identity --------------------------------------------------------

local COLOR_MONSTER = "#e0868c"

local function MonsterHeader(tok, c)
    local portrait = gui.Panel{
        width = 50,
        height = 50,
        valign = "center",
        --a circle is the shape itself, not a theme corner.
        cornerRadius = 25,
        border = 2,
        borderColor = "#b0444a",
        bgimage = "panels/square.png",
        bgcolor = "#3a2e2f",
        interactable = false,
    }
    pcall(function() EotwHeroCard.ApplyPortrait(portrait, tok, 1) end)

    local name = Try(function() return creature.GetTokenDescription(tok) end)
    if name == nil or name == "" then
        name = Try(function() return tok.name end, "Monster")
    end
    local monsterType = Try(function() return c:try_get("monster_type", "") end, "")
    --"Arixx / ARIXX": the type only says something when it is not the name.
    if string.lower(monsterType) == string.lower(name) then
        monsterType = ""
    end

    local parts = {}
    local level = Try(function() return c:CharacterLevel() end)
    local role = Try(function() return c:try_get("role", "") end, "")
    if level ~= nil then
        parts[#parts+1] = string.format("Level %d %s", level, role)
    elseif role ~= "" then
        parts[#parts+1] = role
    end
    local keywords = {}
    pcall(function()
        for keyword, _ in pairs(c:try_get("keywords", {})) do
            keywords[#keywords+1] = keyword
        end
    end)
    table.sort(keywords)
    if #keywords > 0 then
        parts[#parts+1] = table.concat(keywords, ", ")
    end

    local ev = Try(function() return c:EV() end)

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        interactable = false,
        portrait,
        gui.Panel{
            width = INNER_WIDTH - 50 - 11 - 44,
            height = "auto",
            lmargin = 11,
            valign = "center",
            flow = "vertical",
            interactable = false,
            Text{ text = name, fontSize = 24, bold = true, color = COLOR_TEXT, textWrap = false },
            Text{ text = string.upper(monsterType), fontSize = 12, bold = true, color = COLOR_MONSTER, collapsed = monsterType == "" },
            Text{ text = table.concat(parts, " - "), fontSize = 12, color = COLOR_MUTED },
        },
        gui.Panel{
            width = 44,
            height = "auto",
            valign = "center",
            flow = "vertical",
            interactable = false,
            Text{ text = tostring(ev or "-"), fontSize = 24, bold = true, color = COLOR_MONSTER, textAlignment = "center" },
            Text{ text = "EV", fontSize = 10, bold = true, color = COLOR_MUTED, textAlignment = "center" },
        },
    }
end

--- Monster abilities, triggers, villain actions, traits ----------------------

--the tac panel's buckets (MonsterSheetAbilities in MCDMCharacterPanel.lua).
local TRIGGER_CATEGORIES = { ["Trigger"] = true, ["Triggered Ability"] = true }
local VILLAIN_CATEGORIES = { ["Villain Action"] = true }

local function AbilityBuckets(c)
    local abilities, triggers, villainActions = {}, {}, {}
    local list = Try(function()
        return c:GetActivatedAbilities{ excludeGlobal = true, allLoadouts = true, bindCaster = true }
    end, {})
    for _, ability in ipairs(list) do
        local category = Try(function() return ability:try_get("categorization", "") end, "")
        if TRIGGER_CATEGORIES[category] then
            triggers[#triggers+1] = ability
        elseif VILLAIN_CATEGORIES[category] or Try(function() return ability:has_key("villainAction") end, false) then
            villainActions[#villainActions+1] = ability
        else
            abilities[#abilities+1] = ability
        end
    end
    return abilities, triggers, villainActions
end

--Abilities and traits are one row each; hovering shows the full card (for
--abilities, the action bar's own ability:Render), so a solo fits.

local ROW_STYLES = {
    {
        selectors = {"heroCardRow"},
        bgcolor = "#00000000",
    },
    {
        selectors = {"heroCardRow", "hover"},
        bgcolor = COLOR_PLATE,
    },
}

--- One row: name on the left, meta on the right, a card on hover.
--- @param name string
--- @param meta string rich text for the right-hand side
--- @param tooltip fun(): Panel builds the hover card
local function Row(name, meta, tooltip)
    return gui.Panel{
        classes = {"heroCardRow"},
        styles = ROW_STYLES,
        width = "100%",
        height = "auto",
        flow = "horizontal",
        hpad = 8,
        vpad = 3,
        borderBox = true,
        bgimage = "panels/square.png",
        popupPositioning = "panel",
        hover = function(element)
            local ok, card = pcall(tooltip)
            if ok and card ~= nil then
                element.tooltip = gui.TooltipFrame(card, { halign = "right", valign = "center" })
            end
        end,
        --a click on a row is for reading it, not for turning the card.
        click = function(element) end,
        Text{ text = name, fontSize = 13, bold = true, color = COLOR_TEXT, width = "58%", textWrap = false },
        Text{ text = meta, fontSize = 11.5, color = COLOR_MUTED, width = "42%", textAlignment = "right", textWrap = false },
    }
end

--- What an ability costs and what kind of action it is, for the right-hand
--- side of its row: "3 Malice - Main Action", "Signature - Maneuver".
local function AbilityMeta(ability, kind)
    local resources = Try(function() return dmhub.GetTable(CharacterResource.tableName) end, {})
    local parts = {}
    local costNumber = Try(function() return ability:try_get("resourceNumber") end)
    local costName = Try(function() return resources[ability.resourceCost].name end)
    if costNumber ~= nil and costName ~= nil then
        parts[#parts+1] = string.format("<b><color=%s>%s %s</color></b>", COLOR_MONSTER, tostring(costNumber), costName)
    end
    local category = Try(function() return ability:try_get("categorization", "") end, "")
    if string.find(category, "Signature") then
        parts[#parts+1] = string.format("<color=%s>Signature</color>", COLOR_GOLD)
    end
    if kind ~= nil then
        parts[#parts+1] = kind
    else
        local action = Try(function() return resources[ability.actionResourceId].name end)
        if action ~= nil then
            parts[#parts+1] = action
        end
    end
    return table.concat(parts, " - ")
end

local function AbilityRow(ability, tok, kind)
    return Row(ability.name or "", AbilityMeta(ability, kind), function()
        return ability:Render({ width = 420 }, { token = tok })
    end)
end

--- A trait's hover card: its name over its rules text.
local function TraitCard(name, text)
    return gui.Panel{
        width = 380,
        height = "auto",
        flow = "vertical",
        hpad = 12,
        vpad = 10,
        borderBox = true,
        bgimage = "panels/square.png",
        bgcolor = "#151515f8",
        border = 1,
        borderColor = "#b0444acc",
        gui.Label{ text = name, width = "100%", height = "auto", fontSize = 16, bold = true, color = COLOR_TEXT, bmargin = 4 },
        gui.Label{ text = text, width = "100%", height = "auto", fontSize = 13, color = COLOR_SOFT, textWrap = true },
    }
end

local function TraitRow(feature)
    return Row(feature.name, "", function()
        return TraitCard(feature.name, feature.description)
    end)
end

--- Every monster ability, trigger, villain action and trait, each its own
--- row so a page can break between any two of them. Each bucket's heading
--- travels with its first entry (see Paginate).
local function MonsterEntries(tok, c)
    local entries = {}
    local abilities, triggers, villainActions = AbilityBuckets(c)
    local function AddBucket(title, list, build)
        local heading = title
        for _, item in ipairs(list) do
            local ok, row = pcall(build, item)
            if ok and row ~= nil then
                entries[#entries+1] = { heading = heading, bucket = title, panel = row, name = item.name }
                heading = nil
            end
        end
    end
    AddBucket("Abilities", abilities, function(ability) return AbilityRow(ability, tok) end)
    AddBucket("Triggers", triggers, function(ability) return AbilityRow(ability, tok, "Triggered") end)
    AddBucket("Villain Actions", villainActions, function(ability) return AbilityRow(ability, tok, "Villain Action") end)

    local traits = {}
    pcall(function()
        for _, feature in ipairs(c:GetTraitsFromGroup() or {}) do
            traits[#traits+1] = feature
        end
    end)
    for _, feature in ipairs(Try(function() return c:try_get("characterFeatures", {}) end, {})) do
        traits[#traits+1] = feature
    end
    AddBucket("Traits", traits, function(feature)
        if feature.name == nil or feature.description == nil or feature.description == "" then
            return nil
        end
        return TraitRow(feature)
    end)
    return entries
end

--- A bucket heading (ABILITIES, TRAITS, ...) that folds its rows away. A
--- click tells the back's content, its parent, to fold or unfold the bucket
--- (toggleBucket); the content answers with setFolded, which turns the caret
--- and shows how many rows the fold is hiding.
--- @param title string
--- @param count number rows in the bucket
--- @return Panel
local function BucketHeading(title, count)
    local caret = gui.Panel{
        width = 12,
        height = 12,
        valign = "center",
        bgimage = "phosphor/caret-down-fill.png",
        bgcolor = COLOR_MONSTER,
        interactable = false,
    }
    local countLabel = Text{
        text = string.format("(%d)", count or 0),
        width = "auto",
        valign = "center",
        lmargin = 6,
        fontSize = 11,
        color = COLOR_MUTED,
        textWrap = false,
    }
    countLabel:SetClass("collapsed", true)

    return gui.Panel{
        classes = {"heroCardHeading"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        vpad = 2,
        bmargin = 2,
        bgimage = "panels/square.png",
        styles = {
            { selectors = {"heroCardHeading"}, bgcolor = "#00000000" },
            { selectors = {"heroCardHeading", "hover"}, bgcolor = COLOR_PLATE },
        },
        setFolded = function(element, folded)
            caret.bgimage = cond(folded, "phosphor/caret-right-fill.png", "phosphor/caret-down-fill.png")
            countLabel:SetClass("collapsed", not folded)
        end,
        --on click: a handled click folds the bucket instead of turning the card.
        click = function(element)
            audio.FireSoundEvent("Mouse.Click")
            element.parent:FireEvent("toggleBucket", title)
        end,
        caret,
        Text{
            text = string.upper(title),
            width = "auto",
            valign = "center",
            lmargin = 4,
            fontSize = 11,
            bold = true,
            color = COLOR_MONSTER,
            textWrap = false,
        },
        countLabel,
    }
end

--- The back ------------------------------------------------------------------

--- The back's sections in order, and beside each what paging and folding
--- need: is it a bucket heading, which bucket, its name for the "Next:" line.
--- @return Panel[] sections
--- @return {heading: boolean, bucket: string|nil, name: string|nil}[] info
local function BuildSections(tok)
    local c = tok.properties
    local isHero = IsHeroProps(c)
    local builders
    if isHero then
        builders = {
            function() return Header(tok, c) end,
            function() return StaminaStrip(c) end,
            function() return Characteristics(c) end,
            function() return MovementLine(c) end,
            function() return Effects(c) end,
            function() return ResourceGains(c) end,
            function() return PersistentAbilities(c) end,
            function() return Details(c) end,
        }
    else
        builders = {
            function() return MonsterHeader(tok, c) end,
            function() return StaminaStrip(c) end,
            function() return Characteristics(c) end,
            function() return MovementLine(c) end,
            function() return Effects(c) end,
        }
    end
    --a section with nothing to show returns nil and is left out; one that
    --errors is logged and left out rather than blanking the whole back.
    local result, info = {}, {}
    for _, build in ipairs(builders) do
        local ok, section = pcall(build)
        if not ok then
            print("HeroCardBack: section failed:", section)
        elseif section ~= nil then
            section.selfStyle.bmargin = 9
            result[#result+1] = section
            info[#info+1] = { heading = false }
        end
    end
    if not isHero then
        local entries = MonsterEntries(tok, c)
        local counts = {}
        for _, entry in ipairs(entries) do
            counts[entry.bucket] = (counts[entry.bucket] or 0) + 1
        end
        for _, entry in ipairs(entries) do
            if entry.heading ~= nil then
                result[#result+1] = BucketHeading(entry.heading, counts[entry.bucket])
                info[#info+1] = { heading = true, bucket = entry.bucket }
            end
            entry.panel.selfStyle.bmargin = 6
            result[#result+1] = entry.panel
            info[#info+1] = { heading = false, bucket = entry.bucket, name = entry.name }
        end
    end
    return result, info
end

--- Pages -----------------------------------------------------------------------

--A big monster (a solo has a dozen abilities, villain actions and traits)
--does not fit on one card face, so the back is a stack of pages. The footer
--turns them and names what the next page holds.

--room the page title (pages after the first) and the footer take up.
local PAGE_TITLE_HEIGHT = 26
local FOOTER_HEIGHT = 46

--- Splits the sections into pages that fit. heights[i] is section i's
--- laid-out height with its margin. A page never ends on a bucket heading:
--- the heading moves over with its first entry. A section taller than a
--- whole page gets a page to itself.
--- @return {first: number, last: number}[]
local function Paginate(heights, info, available)
    local pages = {}
    local first = 1
    local used = 0
    local limit = available - FOOTER_HEIGHT
    local i = 1
    while i <= #heights do
        if used > 0 and used + heights[i] > limit then
            local last = i - 1
            if info[last].heading and last > first then
                last = last - 1
            end
            pages[#pages+1] = { first = first, last = last }
            first = last + 1
            used = 0
            limit = available - FOOTER_HEIGHT - PAGE_TITLE_HEIGHT
            i = first
        else
            used = used + heights[i]
            i = i + 1
        end
    end
    pages[#pages+1] = { first = first, last = #heights }
    return pages
end

--- The names of the entries on a page, for the "Next:" line. Rows in a
--- folded bucket are not on the page in any way a reader would see.
local function PageNames(page, info, folded)
    local names = {}
    for i = page.first, page.last do
        local hiddenByFold = info[i].bucket ~= nil and folded[info[i].bucket] == true
        if info[i].name ~= nil and info[i].name ~= "" and not hiddenByFold then
            names[#names+1] = info[i].name
        end
    end
    return table.concat(names, ", ")
end

local function OpenSheet(charid, element)
    local toggle = rawget(_G, "ToggleCharacterPanelDocument")
    if toggle ~= nil then
        toggle(charid, nil, element)
    end
end

--- The footer: on a single page, how to turn the card back; on a stack, the
--- page arrows, the page number, what the next page holds and a link to the
--- full sheet (the tac panel).
--- @param content Panel the back's content, which handles "turnPage"
--- @param charid string
--- @return Panel
local function CreateFooter(content, charid)
    local function Arrow(icon, delta)
        return gui.Panel{
            classes = {"heroCardPageArrow"},
            width = 22,
            height = 22,
            valign = "center",
            bgimage = icon,
            bgcolor = COLOR_SOFT,
            swallowPress = true,
            styles = {
                { selectors = {"heroCardPageArrow", "hover"}, bgcolor = COLOR_GOLD },
                { selectors = {"heroCardPageArrow", "disabled"}, opacity = 0.2 },
            },
            --on click: a handled click stops here instead of turning the card.
            click = function(element)
                if element:HasClass("disabled") then
                    return
                end
                audio.FireSoundEvent("Mouse.Click")
                content:FireEvent("turnPage", delta)
            end,
        }
    end

    local prev = Arrow("phosphor/caret-left-bold.png", -1)
    local nextArrow = Arrow("phosphor/caret-right-bold.png", 1)
    local pageLabel = Text{
        text = "",
        width = 60,
        height = "auto",
        valign = "center",
        fontSize = 12,
        bold = true,
        color = COLOR_TEXT,
        textAlignment = "center",
    }
    local nextLabel = Text{ text = "", fontSize = 11, color = COLOR_MUTED, textWrap = false, bmargin = 3 }
    local hint = Text{
        text = "Click to turn the card back over",
        fontSize = 11,
        color = "#6c7782",
        textAlignment = "center",
    }
    local pager = gui.Panel{
        width = "100%",
        height = 24,
        flow = "horizontal",
        interactable = false,
        prev,
        pageLabel,
        nextArrow,
        gui.Label{
            text = "Full sheet",
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
            fontSize = 12,
            bold = true,
            color = COLOR_GOLD,
            swallowPress = true,
            styles = {
                { selectors = {"label", "hover"}, color = "#ffffff" },
            },
            click = function(element)
                audio.FireSoundEvent("Mouse.Click")
                OpenSheet(charid, element)
            end,
        },
    }

    --floating at the card's foot, in the room Paginate keeps free for it.
    return gui.Panel{
        floating = true,
        width = "100%",
        height = "auto",
        valign = "bottom",
        flow = "vertical",
        interactable = false,
        showPage = function(element, page, count, nextNames)
            local single = count <= 1
            pager:SetClass("collapsed", single)
            hint:SetClass("collapsed", not single)
            nextLabel:SetClass("collapsed", single or nextNames == "")
            if not single then
                pageLabel.text = string.format("%d / %d", page, count)
                prev:SetClass("disabled", page <= 1)
                nextArrow:SetClass("disabled", page >= count)
                nextLabel.text = string.format("<b>Next:</b> %s", nextNames)
            end
        end,
        nextLabel,
        pager,
        hint,
    }
end

--- The flip ------------------------------------------------------------------

--The back is laid out at the mockup's size and scaled down onto the card, so
--it keeps the card's exact size and shape at any card size.
local DESIGN_WIDTH = BACK_WIDTH

local FLIP_SECONDS = 0.42

--Turns the card over: squeezes it edge-on, swaps the faces at the midpoint
--and opens it out again, lifting slightly as it turns. Driven by hand rather
--than by a style transition so it runs on the card itself, whose styles
--belong to the host.
local function AnimateFlip(card, onMidpoint)
    if card.data.heroCardFlipping then
        return
    end
    card.data.heroCardFlipping = true
    local start = dmhub.Time()
    local swapped = false
    local function Step()
        if not card.valid then
            return
        end
        local p = math.min(1, (dmhub.Time() - start) / FLIP_SECONDS)
        if p >= 0.5 and not swapped then
            swapped = true
            onMidpoint()
        end
        if p >= 1 then
            --1, not nil: clearing selfStyle.scale leaves the card at scale 0.
            card.selfStyle.scale = 1
            card.data.heroCardFlipping = false
            return
        end
        local eased = 0.5 - 0.5 * math.cos(p * math.pi)
        local sx = math.max(0.02, math.abs(math.cos(eased * math.pi)))
        local lift = 1 + 0.06 * math.sin(p * math.pi)
        card.selfStyle.scale = {x = sx * lift, y = lift}
        dmhub.Schedule(0.01, Step)
    end
    Step()
end

local function CreatureName(tok)
    local name = nil
    if IsHeroProps(tok.properties) then
        name = EotwHeroCard.HeroDisplayName(tok)
    else
        name = Try(function() return creature.GetTokenDescription(tok) end)
    end
    if name == nil or name == "" then
        name = Try(function() return tok.name end, "")
    end
    return name
end

--- The back face: a layer over the whole card, hidden until it is turned.
--- @param charid string
--- @param cardWidth number
--- @param cardHeight number
--- @return Panel
local function CreateBackFace(charid, cardWidth, cardHeight)
    local scale = cardWidth / DESIGN_WIDTH
    local designHeight = math.floor(cardHeight / scale)
    local VPAD = 14

    --what the current build put on the back, and which page is showing. The
    --page survives a rebuild (stamina changing under an open card).
    local state = {
        sections = {},
        info = {},
        pages = {},
        page = 1,
        title = nil,
        footer = nil,
        name = "",
        generation = 0,
        --measured section heights, unfolded.
        heights = {},
        --bucket title -> true while folded. Kept across rebuilds.
        folded = {},
    }

    local function IsFoldedRow(i)
        local info = state.info[i]
        return not info.heading and info.bucket ~= nil and state.folded[info.bucket] == true
    end

    local function ShowPage()
        local count = #state.pages
        if count == 0 then
            return
        end
        state.page = math.max(1, math.min(count, state.page))
        local current = state.pages[state.page]
        for i, section in ipairs(state.sections) do
            section:SetClass("collapsed", i < current.first or i > current.last or IsFoldedRow(i))
            if state.info[i].heading then
                section:FireEvent("setFolded", state.folded[state.info[i].bucket] == true)
            end
        end
        state.title:SetClass("collapsed", state.page == 1)
        state.title.text = string.format("<b>%s</b>   <color=%s>page %d of %d</color>", state.name, COLOR_MUTED, state.page, count)
        local nextNames = ""
        if state.page < count then
            nextNames = PageNames(state.pages[state.page + 1], state.info, state.folded)
        end
        state.footer:FireEvent("showPage", state.page, count, nextNames)
    end

    --pages from the measured heights, with folded rows taking no room.
    local function Repaginate(available)
        local heights = {}
        for i, h in ipairs(state.heights) do
            heights[i] = cond(IsFoldedRow(i), 0, h)
        end
        state.pages = Paginate(heights, state.info, available)
    end

    --laid out at design size and shrunk around its centre (scale, not
    --uiscale: purely visual, so it lands exactly on the card's face).
    local content = gui.Panel{
        floating = true,
        width = DESIGN_WIDTH,
        height = designHeight,
        scale = scale,
        halign = "center",
        valign = "center",
        flow = "vertical",
        hpad = PAD,
        vpad = VPAD,
        borderBox = true,
        interactable = false,
        refreshBack = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid or tok.properties == nil then
                return
            end
            --monsters wear the enemy red the mockup gave them.
            element.parent.selfStyle.borderColor = cond(IsHeroProps(tok.properties), "#6fa8ffcc", "#b0444acc")

            state.sections, state.info = BuildSections(tok)
            state.name = CreatureName(tok)
            state.title = Text{ text = "", fontSize = 13, color = COLOR_TEXT, bmargin = 8 }
            state.title:SetClass("collapsed", true)
            state.footer = CreateFooter(element, charid)

            ---@type Panel[]
            local children = { state.title }
            for _, section in ipairs(state.sections) do
                children[#children+1] = section
            end
            children[#children+1] = state.footer
            --hidden until it is paged: the first layout pass shows every
            --section at once, running off the bottom of the card.
            element.selfStyle.opacity = 0
            element.children = children

            --measure once the new sections have been laid out; a newer
            --rebuild supersedes this one.
            state.generation = state.generation + 1
            local generation = state.generation
            dmhub.Schedule(0.05, function()
                if not element.valid or state.generation ~= generation then
                    return
                end
                state.heights = {}
                for i, section in ipairs(state.sections) do
                    state.heights[i] = section.renderedHeight + (section.selfStyle.bmargin or 0)
                end
                Repaginate(designHeight - VPAD * 2)
                ShowPage()
                element.selfStyle.opacity = 1
            end)
        end,
        turnPage = function(element, delta)
            state.page = state.page + delta
            ShowPage()
        end,
        toggleBucket = function(element, bucket)
            state.folded[bucket] = not state.folded[bucket]
            --stay with the heading that was clicked: find its page afresh.
            Repaginate(designHeight - VPAD * 2)
            for p, page in ipairs(state.pages) do
                for i = page.first, page.last do
                    if state.info[i].heading and state.info[i].bucket == bucket then
                        state.page = p
                    end
                end
            end
            ShowPage()
        end,
    }

    return gui.Panel{
        classes = {"heroCardBackFace"},
        floating = true,
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#151515",
        border = 2,
        borderColor = "#6fa8ffcc",
        --the back is the same card as the front, so it takes the front's
        --corners: EotwHeroCard draws the card with cornerRadius 8.
        cornerRadius = 8,
        swallowPress = true,
        styles = {
            {
                selectors = {"heroCardBackFace"},
                hidden = 1,
            },
            {
                selectors = {"heroCardBackFace", "turned"},
                hidden = 0,
            },
        },
        --stamina, conditions and the like change under the card: rebuild
        --the back while it is showing.
        monitorGame = "/characters",
        refreshGame = function(element)
            if element:HasClass("turned") then
                content:FireEvent("refreshBack")
            end
        end,
        showBack = function(element, show)
            element:SetClass("turned", show)
            if show then
                state.page = 1
                content:FireEvent("refreshBack")
            end
        end,
        click = function(element)
            audio.FireSoundEvent("Mouse.Click")
            element.parent:FireEvent("turnCard")
        end,
        content,
    }
end

--- The flip button: top centre, shown only while the card is hovered.
--- @param charid string
--- @return Panel
local function CreateFlipButton(charid)
    return gui.Panel{
        classes = {"heroCardFlip"},
        floating = true,
        halign = "center",
        valign = "top",
        y = 4,
        width = 26,
        height = 26,
        --a dark round chip so the icon reads against any portrait.
        cornerRadius = 13,
        border = 1,
        borderColor = "#ffffff66",
        bgimage = "panels/square.png",
        bgcolor = "#000000c0",
        swallowPress = true,
        styles = {
            {
                selectors = {"heroCardFlip"},
                hidden = 1,
            },
            {
                selectors = {"heroCardFlip", "parent:hover"},
                hidden = 0,
            },
            {
                selectors = {"heroCardFlip", "hover"},
                hidden = 0,
                borderColor = COLOR_GOLD,
                scale = 1.15,
            },
            {
                selectors = {"heroCardFlipIcon", "parent:hover"},
                bgcolor = COLOR_GOLD,
            },
        },
        gui.Panel{
            classes = {"heroCardFlipIcon"},
            width = 16,
            height = 16,
            halign = "center",
            valign = "center",
            bgimage = "phosphor/arrow-clockwise.png",
            bgcolor = "#ffffffee",
            interactable = false,
        },
        hover = gui.Tooltip("Turn the card over"),
        --on click, as the card's dismiss X does: a handled click stops
        --here instead of bubbling up to open the hero's sheet.
        click = function(element)
            audio.FireSoundEvent("Mouse.Click")
            element.parent:FireEvent("turnCard")
        end,
    }
end

--every decorated card while it lives, weakly held: lets a dev session turn a
--card over from Lua (HeroCardBack.TurnAll()).
local g_cards = setmetatable({}, {__mode = "k"})

--- Gives a hero card (EotwHeroCard.CreateHeroCard) its back: the back face
--- and the flip button go on as the card's top layers, and the card learns
--- the "turnCard" event they both fire.
--- @param cardArgs table the card's gui.Panel args, before it is built
--- @param charid string
--- @param cardWidth number
--- @param cardHeight number
local function Decorate(cardArgs, charid, cardWidth, cardHeight)
    local backFace = CreateBackFace(charid, cardWidth, cardHeight)
    local create = cardArgs.create
    cardArgs.create = function(element)
        g_cards[element] = true
        if create ~= nil then
            create(element)
        end
    end
    cardArgs[#cardArgs+1] = backFace
    cardArgs[#cardArgs+1] = CreateFlipButton(charid)
    cardArgs.turnCard = function(element)
        local turned = not backFace:HasClass("turned")
        AnimateFlip(element, function()
            backFace:FireEvent("showBack", turned)
        end)
    end
end

--- Turn every live hero card over (dev aid).
local function TurnAll()
    for card, _ in pairs(g_cards) do
        if card.valid then
            card:FireEvent("turnCard")
        end
    end
end

HeroCardBack = {
    Decorate = Decorate,
    TurnAll = TurnAll,
}

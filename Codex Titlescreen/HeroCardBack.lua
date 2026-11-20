local mod = dmhub.GetModLoading()

local T = UIText.T

--PROTOTYPE: the back of the hero card (EotwHeroCard.lua), for heroes and
--monsters alike: the tac panel's information (MCDMCharacterPanel.lua) laid
--out on the card's own face, turned over by a hover button. A hero's back is
--split into tabs by what the hero is doing (Combat, Montage, Negotiation,
--Downtime); a monster's is one scrolling list.
--Every read is pcall-guarded: one missing rule must not blank the back.

--the design width the back is laid out at before it is scaled onto the card;
--narrower makes the text larger on the card.
local BACK_WIDTH = 350
local PAD = 18
local INNER_WIDTH = BACK_WIDTH - PAD * 2
--the back's rows scroll: they are laid out this much clear of the scrollbar.
local SCROLLBAR_ROOM = 14
local CONTENT_WIDTH = INNER_WIDTH - SCROLLBAR_ROOM

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

--- Fades a panel and everything in it: a panel's opacity doesn't reach its
--- children, and a row's words are children.
--- @param panel Panel
--- @param alpha number
--- @return Panel panel
local function Fade(panel, alpha)
    panel.selfStyle.opacity = alpha
    for _, child in ipairs(panel.children or {}) do
        Fade(child, alpha)
    end
    return panel
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
            width = CONTENT_WIDTH - 50 - 11 - 44,
            height = "auto",
            lmargin = 11,
            valign = "center",
            flow = "vertical",
            interactable = false,
            Text{
                text = EotwHeroCard.HeroDisplayName(tok),
                --a fixed height so a long name shrinks to fit (minFontSize).
                height = 30,
                fontSize = 24,
                minFontSize = 12,
                bold = true,
                color = COLOR_TEXT,
                textWrap = false,
            },
            --one line each, shrunk to fit: a long subclass or kit name must
            --not push the header down into the tab rows under it.
            Text{ text = line2, height = 17, fontSize = 13, minFontSize = 8, textWrap = false },
            Text{ text = table.concat(parts, " - "), height = 16, fontSize = 12, minFontSize = 8, textWrap = false, color = COLOR_MUTED },
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

    local barWidth = CONTENT_WIDTH - 20
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
    local cellWidth = math.floor(CONTENT_WIDTH / math.max(1, #attrs))
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
    else
        local surges = Try(function() return c:GetAvailableSurges() end)
        if surges ~= nil then
            parts[#parts+1] = Stat("Surges", surges)
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

    --the authored movement modes beyond walking, as the tac panel lists them.
    local modes = {}
    for mode, modeSpeed in pairs(Try(function() return c:try_get("movementSpeeds", {}) end, {})) do
        if (tonumber(modeSpeed) or 0) > 0 then
            modes[#modes+1] = Stat(string.upper(string.sub(mode, 1, 1)) .. string.sub(mode, 2), modeSpeed)
        end
    end
    table.sort(modes)

    local movementLine
    if #modes > 0 then
        movementLine = Text{
            text = "Movement  " .. table.concat(modes, "   "),
            fontSize = 12,
            color = COLOR_MUTED,
            textAlignment = "center",
            bmargin = 4,
        }
    else
        movementLine = gui.Panel{ width = 1, height = 1, interactable = false }
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        interactable = false,
        Divider(),
        Text{
            text = table.concat(parts, "   "),
            fontSize = 12,
            color = COLOR_MUTED,
            textAlignment = "center",
            vmargin = 4,
        },
        movementLine,
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
    local row = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        interactable = false,
        Text{ text = left, fontSize = 12, width = CONTENT_WIDTH - 90 },
        Text{ text = right, fontSize = 12, bold = true, color = rightColor or COLOR_TEXT, width = 90, textAlignment = "right" },
    }
    if dim then
        Fade(row, 0.45)
    end
    return row
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
        --a number, a GoblinScript string or a level table (turned into a string just below).
        ---@type number|string|table
        local quantity = entry.quantity or 1
        --a level table (the Beastheart's "1d3, +1 from level 7"): the row for
        --the hero's level, its symbols resolved ("1d Heroic Resource Gain at
        --Start" reads 1d3).
        if type(quantity) == "table" then
            local level = Try(function() return c:CharacterLevel() end, 1)
            local row = nil
            for _, candidate in ipairs(quantity.entries or {}) do
                if (candidate.threshold or 1) <= level and (row == nil or (candidate.threshold or 1) > (row.threshold or 1)) then
                    row = candidate
                end
            end
            local script = row and row.script or ""
            quantity = Try(function() return dmhub.NormalizeRoll(script, c:LookupSymbol()) end, script)
        end
        local quantityText = tostring(quantity)
        local amount = tonumber(quantityText)
        if amount == nil and not string.find(quantityText, "%d+d%d+") then
            amount = Try(function() return dmhub.EvalGoblinScript(quantityText, c:LookupSymbol()) end)
        end
        local amountText = "+" .. quantityText
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

local function LanguagesText(c)
    local names = {}
    pcall(function()
        local languages = dmhub.GetTableVisible(Language.tableName)
        for langid, _ in pairs(c:LanguagesKnown()) do
            local lang = languages[langid]
            if lang ~= nil then
                names[#names+1] = lang:DisplayName()
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
            width = CONTENT_WIDTH - 50 - 11 - 44,
            height = "auto",
            lmargin = 11,
            valign = "center",
            flow = "vertical",
            interactable = false,
            Text{ text = name, height = 30, fontSize = 24, minFontSize = 12, bold = true, color = COLOR_TEXT, textWrap = false },
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
--- @param tooltip fun(): Panel|nil builds the hover card; nil shows none
local function Row(name, meta, tooltip)
    return gui.Panel{
        classes = {"heroCardRow"},
        styles = ROW_STYLES,
        width = "100%",
        height = "auto",
        flow = "horizontal",
        hpad = 8,
        vpad = 1,
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
    --kind "" says the cost is the whole story (malice).
    if kind ~= nil then
        if kind ~= "" then
            parts[#parts+1] = kind
        end
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

--- Every monster ability, trigger, villain action, malice ability and trait,
--- one row each, grouped into buckets that fold under their headings.
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

    --malice abilities belong to the monster group, not the creature.
    local malice = {}
    pcall(function()
        for _, ability in ipairs(c:MonsterGroup().maliceAbilities or {}) do
            malice[#malice+1] = ability
        end
    end)
    table.sort(malice, function(a, b)
        return (tonumber(a:try_get("resourceNumber")) or 0) < (tonumber(b:try_get("resourceNumber")) or 0)
    end)
    AddBucket("Malice", malice, function(ability) return AbilityRow(ability, tok, "") end)

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
--- click tells its parent, the back's scroll list, to fold or unfold the
--- bucket (toggleBucket); the list answers with setFolded, which turns the caret
--- and shows how many rows the fold is hiding.
--- @param title string
--- @param count number rows in the bucket
--- @param color? string the heading's colour; monster red by default
--- @return Panel
local function BucketHeading(title, count, color)
    color = color or COLOR_MONSTER
    local caret = gui.Panel{
        width = 12,
        height = 12,
        valign = "center",
        bgimage = "phosphor/caret-down-fill.png",
        bgcolor = color,
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
            color = color,
            textWrap = false,
        },
        countLabel,
    }
end

--- The back ------------------------------------------------------------------

--- @alias HeroCardSectionInfo {heading: boolean, bucket: string|nil, name: string|nil, foldedByDefault: boolean|nil}

--- Runs each builder into a section. A section with nothing to show returns
--- nil and is left out; one that errors is logged and left out rather than
--- blanking the whole back.
--- @param builders (fun(): Panel|nil)[]
--- @return Panel[] sections
--- @return HeroCardSectionInfo[] info
local function Collect(builders)
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
    return result, info
end

--- A monster's back: its sections in order, then its folding buckets.
--- @return Panel[] sections
--- @return HeroCardSectionInfo[] info
local function BuildSections(tok)
    local c = tok.properties
    local result, info = Collect{
        function() return MonsterHeader(tok, c) end,
        function() return StaminaStrip(c) end,
        function() return Characteristics(c) end,
        function() return MovementLine(c) end,
        function() return Effects(c) end,
    }
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
        entry.panel.selfStyle.bmargin = 1
        result[#result+1] = entry.panel
        info[#info+1] = { heading = false, bucket = entry.bucket, name = entry.name }
    end
    return result, info
end

--- Hero tabs -------------------------------------------------------------------

--A hero's back keeps its header and tab rows in place and scrolls the tab's
--content under them. Combat opens a second row: Basics, Abilities, Triggers
--and the class's heroic resource. The card turns over onto the tab for the
--current scene.

local HERO_HEADER_HEIGHT = 66
local TAB_ROW_HEIGHT = 38
local SUB_ROW_HEIGHT = 26
local TOP_GAP = 6

local HERO_TABS = {
    { id = "combat", icon = "phosphor/sword-fill.png" },
    { id = "montage", icon = "phosphor/mountains.png" },
    { id = "negotiation", icon = "phosphor/handshake.png" },
    { id = "downtime", icon = "phosphor/campfire-bold.png" },
}
local COMBAT_SUBS = { "basics", "abilities", "triggers", "resource" }

--ability buckets on the Abilities tab, in order; only Signature starts open.
local HERO_BUCKETS = { "signature", "heroic", "main", "maneuver", "other", "freestrike", "standard" }

--reading a hero's abilities builds the feature index, so a card reuses the
--list this long while game updates rebuild its back.
local ABILITY_CACHE_SECONDS = 5

--charid -> the Combat sub-tab last picked on that hero's card. Cards are
--rebuilt as screens change, so the choice lives here for the session.
local g_lastSubTab = {}

--- @param id string
--- @return string
local function TabLabel(id)
    if id == "combat" then
        return T("herocard.back.tab.combat")
    elseif id == "montage" then
        return T("herocard.back.tab.montage")
    elseif id == "negotiation" then
        return T("herocard.back.tab.negotiation")
    end
    return T("herocard.back.tab.downtime")
end

--- @param id string
--- @return string
local function BucketLabel(id)
    if id == "signature" then
        return T("herocard.back.bucket.signature")
    elseif id == "heroic" then
        return T("herocard.back.bucket.heroic")
    elseif id == "main" then
        return T("herocard.back.bucket.main")
    elseif id == "maneuver" then
        return T("herocard.back.bucket.maneuver")
    elseif id == "freestrike" then
        return T("herocard.back.bucket.freestrike")
    elseif id == "standard" then
        return T("herocard.back.bucket.standard")
    end
    return T("herocard.back.bucket.other")
end

--- A running scene's state from its module, or nil when none is running.
--- @param moduleName string
--- @return table|nil
local function SceneState(moduleName)
    local m = rawget(_G, moduleName)
    if m == nil or m.GetState == nil then
        return nil
    end
    local state = Try(function() return m.GetState() end)
    if type(state) ~= "table" or state.phase == "done" then
        return nil
    end
    return state
end

--- The tab that fits what the party is doing now, or nil when nothing is
--- running: the card then opens on Combat with no current-scene dot.
--- @return string|nil
local function CurrentMode()
    local q = dmhub.initiativeQueue
    if q ~= nil and not q.hidden then
        return "combat"
    end
    if SceneState("EncounterNegotiation") ~= nil then
        return "negotiation"
    end
    if SceneState("EncounterMontage") ~= nil or SceneState("EncounterGauntlet") ~= nil then
        return "montage"
    end
    local respite = rawget(_G, "RSPShell")
    if respite ~= nil and Try(function() return respite.IsOpen() end, false) then
        return "downtime"
    end
    if q ~= nil and Try(function() return q.gameMode end) == "respite" then
        return "downtime"
    end
    local analytics = rawget(_G, "EotwAnalytics")
    if analytics ~= nil then
        if Try(function() return analytics.IsTownOpen() end, false) then
            return "downtime"
        end
        local phase = Try(function() return analytics.CurrentPhase() end)
        if phase == "negotiation" then
            return "negotiation"
        elseif phase == "montage" or phase == "narrative" then
            return "montage"
        elseif phase == "gathering" then
            return "downtime"
        end
    end
    return nil
end

local function InCombat()
    local q = dmhub.initiativeQueue
    return q ~= nil and not q.hidden
end

--- One tab: a word with an optional icon above it, a bar under it while
--- selected, and a green dot while it is the current scene's tab. A click
--- picks the tab instead of turning the card.
--- @param args {text: string, icon: string|nil, fontSize: number, width: number, height: number, selected: boolean, live: boolean|nil, barColor: string, selectedFill: string, click: fun()}
--- @return Panel
local function TabButton(args)
    local color = cond(args.selected, COLOR_TEXT, COLOR_MUTED)
    local inner = {}
    if args.icon ~= nil then
        inner[#inner+1] = gui.Panel{
            width = 13,
            height = 13,
            halign = "center",
            bmargin = 2,
            bgimage = args.icon,
            bgcolor = color,
            interactable = false,
        }
    end
    inner[#inner+1] = gui.Label{
        text = args.text,
        width = "auto",
        height = "auto",
        halign = "center",
        fontSize = args.fontSize,
        bold = true,
        color = color,
        textWrap = false,
        interactable = false,
    }
    local children = {
        gui.Panel{
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
            flow = "vertical",
            interactable = false,
            children = inner,
        },
        gui.Panel{
            floating = true,
            width = "100%",
            height = 2,
            valign = "bottom",
            bgimage = "panels/square.png",
            bgcolor = cond(args.selected, args.barColor, "#00000000"),
            interactable = false,
        },
    }
    if args.live then
        children[#children+1] = gui.Panel{
            floating = true,
            width = 6,
            height = 6,
            halign = "right",
            valign = "top",
            x = -6,
            y = 5,
            --a dot is the shape itself, not a theme corner.
            cornerRadius = 3,
            bgimage = "panels/square.png",
            bgcolor = COLOR_STAMINA,
            interactable = false,
        }
    end
    return gui.Panel{
        classes = {"heroCardTab"},
        styles = {
            { selectors = {"heroCardTab"}, bgcolor = cond(args.selected, args.selectedFill, "#00000000") },
            { selectors = {"heroCardTab", "hover"}, bgcolor = COLOR_PLATE },
        },
        width = args.width,
        height = args.height,
        bgimage = "panels/square.png",
        hover = function(element)
            if args.live then
                element.tooltip = T("herocard.back.tab.current")
            end
        end,
        click = function(element)
            audio.FireSoundEvent("Mouse.Click")
            args.click()
        end,
        children = children,
    }
end

--- The heroic resource's name and the hero's current amount.
--- @return string name
--- @return number value
local function HeroResource(c)
    local name = Try(function() return c:GetHeroicResourceName() end, "Heroic Resource")
    local value = Try(function() return c:GetHeroicOrMaliceResources() end, 0)
    return name, tonumber(value) or 0
end

--- The main tab row, and under Combat the second row.
--- @param state {tab: string, sub: string}
--- @param pick fun(tab: string, sub: string|nil)
--- @return Panel
local function HeroTabs(state, c, pick)
    local live = CurrentMode()
    local tabWidth = math.floor(INNER_WIDTH / #HERO_TABS)
    local mainTabs = {}
    for _, tab in ipairs(HERO_TABS) do
        mainTabs[#mainTabs+1] = TabButton{
            text = TabLabel(tab.id),
            icon = tab.icon,
            fontSize = 11,
            width = tabWidth,
            height = TAB_ROW_HEIGHT,
            selected = state.tab == tab.id,
            live = live == tab.id,
            barColor = COLOR_GOLD,
            selectedFill = "#00000000",
            click = function() pick(tab.id, nil) end,
        }
    end
    local rows = {
        gui.Panel{
            width = INNER_WIDTH,
            height = TAB_ROW_HEIGHT,
            flow = "horizontal",
            interactable = false,
            children = mainTabs,
        },
        Divider(),
    }
    if state.tab == "combat" then
        local resourceName, resourceValue = HeroResource(c)
        local subWidth = math.floor(INNER_WIDTH / #COMBAT_SUBS)
        local subTabs = {}
        for _, sub in ipairs(COMBAT_SUBS) do
            local text
            if sub == "basics" then
                text = T("herocard.back.sub.basics")
            elseif sub == "abilities" then
                text = T("herocard.back.sub.abilities")
            elseif sub == "triggers" then
                text = T("herocard.back.sub.triggers")
            else
                text = T("herocard.back.sub.resource", {
                    resource = resourceName,
                    value = string.format("<color=%s>%d</color>", COLOR_RESOURCE, resourceValue),
                })
            end
            subTabs[#subTabs+1] = TabButton{
                text = text,
                fontSize = 11.5,
                width = subWidth,
                height = SUB_ROW_HEIGHT,
                selected = state.sub == sub,
                barColor = COLOR_BLUE,
                selectedFill = COLOR_PLATE,
                click = function() pick("combat", sub) end,
            }
        end
        rows[#rows+1] = gui.Panel{
            width = INNER_WIDTH,
            height = SUB_ROW_HEIGHT,
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = "#0b0d10",
            interactable = false,
            children = subTabs,
        }
    end
    return gui.Panel{
        width = INNER_WIDTH,
        height = "auto",
        flow = "vertical",
        interactable = false,
        children = rows,
    }
end

--- What a heroic ability costs, or nil for one that costs no heroic resource.
--- @return number|nil
local function HeroicCost(ability)
    return Try(function()
        if ability.resourceCost == CharacterResource.heroicResourceId then
            return tonumber(ability:try_get("resourceNumber", 1))
        end
        return nil
    end)
end

--- The hero sheet's ability groups (EotwHeroSheet.Data), reused for a few
--- seconds per card.
--- @param state table the back's state; holds the cache
--- @return table[] groups
local function HeroAbilityGroups(tok, state)
    local now = dmhub.Time()
    local cache = state.abilities
    if cache ~= nil and now - cache.at < ABILITY_CACHE_SECONDS then
        return cache.groups
    end
    local groups = {}
    local sheet = rawget(_G, "EotwHeroSheet")
    if sheet ~= nil then
        local d = Try(function() return sheet.Data(tok, {"resource", "abilities"}) end)
        if d ~= nil and d.abilities ~= nil then
            groups = d.abilities
        end
    end
    state.abilities = { at = now, groups = groups }
    return groups
end

--- Sorts the sheet's ability items into the Abilities tab's buckets, and pulls
--- out the triggered actions for the Triggers tab.
--- @return table<string, table[]> buckets
--- @return table[] triggers
local function SortAbilities(groups)
    local buckets, triggers = {}, {}
    for _, id in ipairs(HERO_BUCKETS) do
        buckets[id] = {}
    end
    for _, group in ipairs(groups) do
        for _, item in ipairs(group.items or {}) do
            if group.id == "triggered" then
                triggers[#triggers+1] = item
            else
                local id = group.id
                if item.category == "Signature Ability" then
                    id = "signature"
                elseif item.ability ~= nil and HeroicCost(item.ability) ~= nil then
                    id = "heroic"
                end
                if buckets[id] == nil then
                    id = "other"
                end
                local list = buckets[id]
                list[#list+1] = item
            end
        end
    end
    table.sort(buckets.heroic, function(a, b)
        local ca, cb = HeroicCost(a.ability) or 0, HeroicCost(b.ability) or 0
        if ca ~= cb then
            return ca < cb
        end
        return (a.name or "") < (b.name or "")
    end)
    return buckets, triggers
end

--- How much heroic resource the hero can spend now: nil outside combat,
--- where nothing is greyed out for cost.
--- @return number|nil
local function SpendableResource(c)
    if not InCombat() then
        return nil
    end
    local value = Try(function() return c:GetHeroicOrMaliceResourcesAvailableToSpend() end)
    if value == nil then
        local _, current = HeroResource(c)
        value = current
    end
    return tonumber(value) or 0
end

--- One ability as a row: its cost and action on the right, its card on hover.
--- Greyed out when the hero can't pay for it now.
--- @return Panel
local function AbilityItemRow(item, tok, spendable)
    local parts = {}
    if item.costTag ~= nil then
        parts[#parts+1] = string.format("<b><color=%s>%s</color></b>", COLOR_RESOURCE, item.costTag)
    end
    if item.actionTag ~= nil and item.actionTag ~= "" then
        parts[#parts+1] = item.actionTag
    end
    local row = Row(item.name or "", table.concat(parts, " - "), function()
        if item.ability ~= nil then
            return item.ability:Render({ width = 420 }, { token = tok })
        end
        if item.trigger ~= nil then
            return item.trigger:Render{ token = tok }
        end
        return nil
    end)
    local cost = item.ability ~= nil and HeroicCost(item.ability) or nil
    if spendable ~= nil and cost ~= nil and cost > spendable then
        Fade(row, 0.45)
    end
    return row
end

--- Adds a folding bucket of rows: its heading, then the rows.
local function AppendBucket(result, info, title, rows, foldedByDefault)
    if #rows == 0 then
        return
    end
    result[#result+1] = BucketHeading(title, #rows, COLOR_GOLD)
    info[#info+1] = { heading = true, bucket = title, foldedByDefault = foldedByDefault }
    for _, row in ipairs(rows) do
        row.selfStyle.bmargin = 1
        result[#result+1] = row
        info[#info+1] = { heading = false, bucket = title }
    end
end

--- A muted line for a tab or section with nothing in it.
local function EmptyLine(text)
    return Text{ text = "<i>" .. text .. "</i>", fontSize = 12, color = COLOR_MUTED }
end

local function Lines(lines)
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

--- Combat > Abilities: every ability in folding buckets.
local function AbilitiesTab(tok, c, state)
    local buckets = SortAbilities(HeroAbilityGroups(tok, state))
    local spendable = SpendableResource(c)
    local result, info = {}, {}
    for _, id in ipairs(HERO_BUCKETS) do
        local rows = {}
        for _, item in ipairs(buckets[id]) do
            local ok, row = pcall(AbilityItemRow, item, tok, spendable)
            if ok and row ~= nil then
                rows[#rows+1] = row
            end
        end
        AppendBucket(result, info, BucketLabel(id), rows, id ~= "signature")
    end
    if #result == 0 then
        return { EmptyLine(T("herocard.back.abilities.none")) }, { { heading = false } }
    end
    return result, info
end

--- One triggered action: its row, then what sets it off.
local function TriggerEntry(item, tok, c)
    local children = { AbilityItemRow(item, tok, SpendableResource(c)) }
    local when = nil
    if item.trigger ~= nil then
        when = Try(function() return StringInterpolateGoblinScript(item.trigger.trigger, c) end)
    end
    if when ~= nil and when ~= "" then
        children[#children+1] = Text{
            text = T("herocard.back.trigger.when", { trigger = when }),
            width = CONTENT_WIDTH - 16,
            lmargin = 8,
            fontSize = 11.5,
        }
    end
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        interactable = false,
        children = children,
    }
end

--- Combat > Triggers: whether the triggered action is spent this round, then
--- every triggered action.
local function TriggersTab(tok, c, state)
    local _, triggers = SortAbilities(HeroAbilityGroups(tok, state))
    local builders = {}
    if InCombat() then
        builders[#builders+1] = function()
            local id = CharacterResource.triggerResourceId
            local max = tonumber(Try(function() return c:GetResources()[id] end, 0)) or 0
            local used = tonumber(Try(function() return c:GetResourceUsage(id, "round") end, 0)) or 0
            if max <= 0 then
                return nil
            end
            if used < max then
                return Text{ text = T("herocard.back.triggers.ready"), fontSize = 12, bold = true, color = COLOR_STAMINA }
            end
            return Text{ text = T("herocard.back.triggers.used"), fontSize = 12, color = COLOR_MUTED }
        end
    end
    if #triggers == 0 then
        builders[#builders+1] = function() return EmptyLine(T("herocard.back.triggers.none")) end
    end
    for _, item in ipairs(triggers) do
        builders[#builders+1] = function() return TriggerEntry(item, tok, c) end
    end
    return Collect(builders)
end

--- The resource's name beside the hero's amount, large.
local function ResourceHeadline(c)
    local name, value = HeroResource(c)
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        interactable = false,
        Text{ text = tostring(value), width = "auto", fontSize = 40, bold = true, color = COLOR_RESOURCE, textWrap = false, valign = "center", rmargin = 12 },
        Text{ text = name, width = "auto", fontSize = 20, bold = true, color = COLOR_TEXT, textWrap = false, valign = "center" },
    }
end

--- Level 10: the class's epic resource and how much the hero has.
local function EpicResource(tok)
    local sheet = rawget(_G, "EotwHeroSheet")
    if sheet == nil then
        return nil
    end
    local d = Try(function() return sheet.Data(tok, {"progress"}) end)
    local epic = d ~= nil and d.progress ~= nil and d.progress.epic or nil
    if epic == nil or epic.name == nil or epic.name == "" then
        return nil
    end
    return TwoColumnRow(T("herocard.back.resource.epic", { resource = epic.name }), tostring(epic.value or 0), COLOR_RESOURCE)
end

--- The heroic abilities the resource pays for, cheapest first.
local function SpendList(tok, c, state)
    local buckets = SortAbilities(HeroAbilityGroups(tok, state))
    if #buckets.heroic == 0 then
        return nil
    end
    local name = HeroResource(c)
    local spendable = SpendableResource(c)
    local rows = { SectionLabel(T("herocard.back.resource.spend", { resource = name }), COLOR_RESOURCE) }
    for _, item in ipairs(buckets.heroic) do
        local ok, row = pcall(AbilityItemRow, item, tok, spendable)
        if ok and row ~= nil then
            row.selfStyle.bmargin = 1
            rows[#rows+1] = row
        end
    end
    return Lines(rows)
end

--- One threshold of a growing resources table: the amount it needs, then
--- what it gives. Full while reached, muted while only reached earlier this
--- turn (it lasts to the end of the turn), faint while not reached.
local function GrowthRow(need, text, active, expiring)
    return Fade(gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        bmargin = 4,
        interactable = false,
        gui.Panel{
            width = 22,
            height = 22,
            valign = "top",
            --a circle is the shape itself, not a theme corner.
            cornerRadius = 11,
            border = 1,
            borderColor = COLOR_RESOURCE,
            bgimage = "panels/square.png",
            bgcolor = cond(active, COLOR_RESOURCE, "#00000000"),
            interactable = false,
            Text{
                text = tostring(need),
                height = "100%",
                valign = "center",
                fontSize = 12,
                bold = true,
                textAlignment = "center",
                color = cond(active, "#1a1200", COLOR_RESOURCE),
            },
        },
        Text{ text = text, width = CONTENT_WIDTH - 32, lmargin = 10, fontSize = 12, valign = "center" },
    }, cond(active, 1, cond(expiring, 0.75, 0.45)))
end

--- The class's growing resources tables (Growing Ferocity and the like), at
--- the hero's level, each threshold lit once the hero has enough.
local function GrowthTables(c)
    local tables = Try(function() return c:GetGrowingResourcesTables() end, {})
    if #tables == 0 then
        return nil
    end
    local level = Try(function() return c:CharacterLevel() end, 1)
    local have = tonumber(Try(function() return c:GetProgressionResource() end, 0)) or 0
    local high = tonumber(Try(function() return c:GetProgressionResourceHighWaterMark() end, have)) or have
    local children = {}
    for _, growth in ipairs(tables) do
        local name = Try(function() return growth:try_get("name") end, "")
        if name ~= "" then
            children[#children+1] = SectionLabel(name, COLOR_RESOURCE)
        end
        local shownNeed = false
        for _, entry in ipairs(Try(function() return growth.progression end, {})) do
            if (tonumber(entry.level) or 0) <= level then
                local need = tonumber(entry.resources) or 0
                local active = need <= have
                local expiring = (not active) and need <= high
                local text = Try(function() return StringInterpolateGoblinScript(entry.description, c) end, entry.description or "")
                if not active and not expiring and not shownNeed then
                    text = text .. string.format("  <color=%s>%s</color>", COLOR_MUTED, T("herocard.back.growth.needs", { count = need - have }))
                    shownNeed = true
                end
                children[#children+1] = GrowthRow(need, text, active, expiring)
            end
        end
    end
    return Lines(children)
end

--the tac panel's own resource boxes; the card shows these itself.
local CORE_RESOURCE_DISPLAYS = { victories = true, heroic = true, recoveries = true, herotokens = true, surges = true }

--- The class's own pieces of the tac panel, in its styles: the boxes classes
--- register (the Beastheart's Rampage, the Acolyte's Patron's Gaze) and the
--- Summoner's minion squads. Each hides itself on a hero it doesn't fit.
--- TacPanel is game-side: in town there is none. Kept on the card's state and
--- refreshed, so the boxes keep their state.
local function ClassPanel(tok, c, state)
    local tac = rawget(_G, "TacPanel")
    if tac == nil or tac.AllStyles == nil then
        return nil
    end
    if state.classPanel == nil or not state.classPanel.valid then
        local children = {}
        if tac.GetHeroicResourceDisplays ~= nil then
            local boxes = {}
            for _, entry in ipairs(tac.GetHeroicResourceDisplays()) do
                if not CORE_RESOURCE_DISPLAYS[entry.id] then
                    local ok, box = pcall(entry.create)
                    if ok and box ~= nil then
                        boxes[#boxes+1] = box
                    end
                end
            end
            if #boxes > 0 then
                children[#children+1] = gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    wrap = true,
                    children = boxes,
                }
            end
        end
        if tac.Summoner ~= nil then
            children[#children+1] = tac.Summoner()
        end
        if #children == 0 then
            return nil
        end
        state.classPanel = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            styles = tac.AllStyles(),
            children = children,
        }
    end
    state.classPanel:FireEventTree("refreshToken", tok)
    return state.classPanel
end

--- Combat > the heroic resource: how much, how to gain it, what to spend it
--- on, what having it unlocks, and the class's own panel.
local function ResourceTab(tok, c, state)
    return Collect{
        function() return ResourceHeadline(c) end,
        function() return EpicResource(tok) end,
        function() return ResourceGains(c) end,
        function() return SpendList(tok, c, state) end,
        function() return GrowthTables(c) end,
        function() return ClassPanel(tok, c, state) end,
    }
end

--- Trained skills by group, one line per group.
local function SkillsByGroup(c)
    local lines = {}
    for _, cat in ipairs(Try(function() return Skill.categories end, {})) do
        local names = {}
        pcall(function()
            for _, skill in ipairs(Skill.SkillsInfo) do
                if skill.category == cat.id and c:ProficientInSkill(skill) then
                    names[#names+1] = skill.name
                end
            end
        end)
        if #names > 0 then
            table.sort(names)
            lines[#lines+1] = LabelledLine(cat.text, table.concat(names, ", "))
        end
    end
    if #lines == 0 then
        return EmptyLine(T("herocard.back.skills.none"))
    end
    return Lines(lines)
end

local function HeroTokensLine(c)
    local tokens = Try(function() return c:GetHeroTokens() end, 0)
    return LabelledLine(T("herocard.back.label.hero_tokens"), string.format("<b><color=%s>%d</color></b>", COLOR_TEXT, tonumber(tokens) or 0))
end

local function PerksLine(c)
    local perks = PerksText(c)
    if perks == "" then
        return nil
    end
    return LabelledLine(T("herocard.back.label.perks"), perks)
end

local function NotesLine(c)
    local notes = NotesText(c)
    if notes == nil then
        return nil
    end
    return LabelledLine(T("herocard.back.label.notes"), string.format("<i>%s</i>", notes))
end

--- Montage: what a test leans on.
local function MontageTab(tok, c)
    return Collect{
        function() return Characteristics(c) end,
        function() return HeroTokensLine(c) end,
        function() return SkillsByGroup(c) end,
        function() return MovementLine(c) end,
        function() return PerksLine(c) end,
    }
end

--- The interpersonal skills, trained ones first, the rest muted.
local function InterpersonalSkills(c)
    local trained, untrained = {}, {}
    pcall(function()
        for _, skill in ipairs(Skill.SkillsInfo) do
            if skill.category == "interpersonal" then
                if c:ProficientInSkill(skill) then
                    trained[#trained+1] = skill.name
                else
                    untrained[#untrained+1] = skill.name
                end
            end
        end
    end)
    table.sort(trained)
    table.sort(untrained)
    local lines = {}
    if #trained > 0 then
        lines[#lines+1] = LabelledLine(T("herocard.back.negotiation.trained"), string.format("<b><color=%s>%s</color></b>", COLOR_TEXT, table.concat(trained, ", ")))
    end
    if #untrained > 0 then
        lines[#lines+1] = LabelledLine(T("herocard.back.negotiation.untrained"), string.format("<color=%s>%s</color>", COLOR_MUTED, table.concat(untrained, ", ")))
    end
    return Lines(lines)
end

--- Negotiation: what talking leans on.
local function NegotiationTab(tok, c)
    return Collect{
        function() return Characteristics(c) end,
        function()
            local renown = Try(function() return c:CalculateNamedCustomAttribute("Renown") end, 0)
            return Lines{
                LabelledLine(T("herocard.back.label.renown"), string.format("<b><color=%s>%s</color></b>", COLOR_TEXT, tostring(renown))),
                HeroTokensLine(c),
            }
        end,
        function() return InterpersonalSkills(c) end,
        function()
            local languages = LanguagesText(c)
            if languages == "" then
                return nil
            end
            return LabelledLine(T("herocard.back.label.languages"), languages)
        end,
        function() return PerksLine(c) end,
        function() return NotesLine(c) end,
    }
end

--- The hero's own downtime projects with their progress.
local function ProjectsList(c)
    local projects = Try(function() return c:GetDowntimeInfo():GetSortedProjects() end, {})
    if #projects == 0 then
        return nil
    end
    local rows = { SectionLabel(T("herocard.back.label.projects")) }
    for _, project in ipairs(projects) do
        local title = Try(function() return project:GetTitle() end, "")
        local progress = Try(function() return project:GetProgress() end, 0)
        local goal = Try(function() return project:GetProjectGoal() end, 0)
        rows[#rows+1] = TwoColumnRow(title, string.format("%s / %s", tostring(progress), tostring(goal)))
    end
    return Lines(rows)
end

--- Downtime: progress, what there is to spend, and projects.
local function DowntimeTab(tok, charid, c)
    return Collect{
        function()
            local lines = {}
            local victories = Try(function() return c:GetVictories() end, 0)
            lines[#lines+1] = LabelledLine(T("herocard.back.label.victories"), tostring(victories))
            local sheet = rawget(_G, "EotwHeroSheet")
            local xp = sheet ~= nil and Try(function() return sheet.XpProgress(c) end) or nil
            if xp ~= nil then
                local xpText = tostring(xp.xp)
                if not xp.maxLevel then
                    xpText = string.format("%d / %d", xp.xpIntoLevel, xp.xpPerLevel)
                end
                lines[#lines+1] = LabelledLine(T("herocard.back.label.xp"), xpText)
            end
            local wealth = Try(function() return c:CalculateNamedCustomAttribute("Wealth") end)
            if wealth ~= nil then
                lines[#lines+1] = LabelledLine(T("herocard.back.label.wealth"), tostring(wealth))
            end
            local renown = Try(function() return c:CalculateNamedCustomAttribute("Renown") end)
            if renown ~= nil then
                lines[#lines+1] = LabelledLine(T("herocard.back.label.renown"), tostring(renown))
            end
            local roster = rawget(_G, "EotwRoster")
            if roster ~= nil then
                local downtime = Try(function() return roster.GetDowntime(charid) end, 0)
                if (tonumber(downtime) or 0) > 0 then
                    lines[#lines+1] = LabelledLine(T("herocard.back.label.downtime"), tostring(downtime))
                end
            end
            return Lines(lines)
        end,
        function() return ProjectsList(c) end,
        function()
            local id = CharacterResource.recoveryResourceId
            local max = tonumber(Try(function() return c:GetResources()[id] end, 0)) or 0
            local used = tonumber(Try(function() return c:GetResourceUsage(id, "long") end, 0)) or 0
            return LabelledLine(T("herocard.back.label.recoveries"), string.format("%d / %d", math.max(0, max - used), max))
        end,
        function() return NotesLine(c) end,
    }
end

--- A hero's back for the chosen tab (and, under Combat, the chosen sub-tab).
--- @param state {tab: string, sub: string}
--- @return Panel[] sections
--- @return HeroCardSectionInfo[] info
local function BuildHeroTab(tok, charid, state)
    local c = tok.properties
    local result, info
    if state.tab == "montage" then
        result, info = MontageTab(tok, c)
    elseif state.tab == "negotiation" then
        result, info = NegotiationTab(tok, c)
    elseif state.tab == "downtime" then
        result, info = DowntimeTab(tok, charid, c)
    elseif state.sub == "abilities" then
        result, info = AbilitiesTab(tok, c, state)
    elseif state.sub == "triggers" then
        result, info = TriggersTab(tok, c, state)
    elseif state.sub == "resource" then
        result, info = ResourceTab(tok, c, state)
    else
        result, info = Collect{
            function() return StaminaStrip(c) end,
            function() return Characteristics(c) end,
            function() return MovementLine(c) end,
            function() return Effects(c) end,
            function() return PersistentAbilities(c) end,
        }
    end
    if #result == 0 then
        return { EmptyLine(T("herocard.back.empty")) }, { { heading = false } }
    end
    return result, info
end

--- Footer ----------------------------------------------------------------------

local FOOTER_HEIGHT = 26

local function OpenSheet(charid, element)
    local toggle = rawget(_G, "ToggleCharacterPanelDocument")
    if toggle ~= nil then
        toggle(charid, nil, element)
    end
end

--- The footer: how to turn the card back, and a link to the full sheet.
--- @param charid string
--- @return Panel
local function CreateFooter(charid)
    return gui.Panel{
        floating = true,
        width = "100%",
        height = FOOTER_HEIGHT,
        valign = "bottom",
        flow = "horizontal",
        interactable = false,
        Text{
            text = "Click to turn the card back over",
            width = "auto",
            valign = "center",
            fontSize = 11,
            color = "#6c7782",
            textWrap = false,
        },
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
end

--- The flip ------------------------------------------------------------------

--The back is laid out at the mockup's size and scaled down onto the card, so
--it keeps the card's exact size and shape at any card size.
local DESIGN_WIDTH = BACK_WIDTH

local FLIP_SECONDS = 0.42
--how much bigger the card is while its back is showing. It grows upward and
--then rises a further TURNED_RISE of its own height, clear of the screen's foot.
local TURNED_SCALE = 3
local TURNED_RISE = 0.25

--Turns the card over: squeezes it edge-on, swaps the faces at the midpoint
--and opens it out again, lifting slightly as it turns. Driven by hand rather
--than by a style transition so it runs on the card itself, whose styles
--belong to the host. The card grows from fromScale to toScale as it turns,
--rising so the growth goes upward (scale is around the card's centre).
local function AnimateFlip(card, cardHeight, fromScale, toScale, onMidpoint, onDone)
    if card.data.heroCardFlipping then
        return
    end
    card.data.heroCardFlipping = true
    if card.data.heroCardBaseY == nil then
        card.data.heroCardBaseY = card.selfStyle.y or 0
    end
    local baseY = card.data.heroCardBaseY
    --the engine pulls an enlarged card back inside the screen.
    card.constrainToScreen = true
    local function Lift(size)
        local grown = (size - 1) / (TURNED_SCALE - 1)
        return baseY - (size - 1) * cardHeight / 2 - grown * TURNED_RISE * cardHeight
    end
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
            --never nil: clearing selfStyle.scale leaves the card at scale 0.
            card.selfStyle.scale = toScale
            card.selfStyle.y = Lift(toScale)
            card.constrainToScreen = toScale ~= 1
            card.data.heroCardFlipping = false
            onDone()
            return
        end
        local eased = 0.5 - 0.5 * math.cos(p * math.pi)
        local sx = math.max(0.02, math.abs(math.cos(eased * math.pi)))
        local grown = fromScale + (toScale - fromScale) * eased
        local size = grown * (1 + 0.06 * math.sin(p * math.pi))
        card.selfStyle.scale = {x = sx * size, y = size}
        card.selfStyle.y = Lift(grown)
        dmhub.Schedule(0.01, Step)
    end
    Step()
end

--- The back face: a layer over the whole card, hidden until it is turned.
--- What does not fit scrolls; bucket headings fold their rows away.
--- @param charid string
--- @param cardWidth number
--- @param cardHeight number
--- @return Panel
local function CreateBackFace(charid, cardWidth, cardHeight)
    local scale = cardWidth / DESIGN_WIDTH
    local designHeight = math.floor(cardHeight / scale)
    local VPAD = 14

    --bucket title -> true while folded, false while opened. Kept across
    --rebuilds (stamina changing under an open card); a bucket nobody has
    --touched takes its default (hero ability buckets but Signature start folded).
    local folded = {}
    local foldDefaults = {}
    local sections, info = {}, {}

    --a hero's tab and Combat sub-tab, the cached ability list and class panel.
    local state = { tab = "combat", sub = "basics", abilities = nil, classPanel = nil }

    local function IsFolded(bucket)
        local f = folded[bucket]
        if f == nil then
            f = foldDefaults[bucket] == true
        end
        return f
    end

    local function ApplyFolds()
        for i, section in ipairs(sections) do
            local entry = info[i]
            if entry.heading then
                section:FireEvent("setFolded", IsFolded(entry.bucket))
            elseif entry.bucket ~= nil then
                section:SetClass("collapsed", IsFolded(entry.bucket))
            end
        end
    end

    --the bucket headings are its children, so their clicks land here.
    local scroller = gui.Panel{
        width = "100%",
        height = designHeight - VPAD * 2 - FOOTER_HEIGHT,
        flow = "vertical",
        vscroll = true,
        interactable = false,
        toggleBucket = function(element, bucket)
            folded[bucket] = not IsFolded(bucket)
            ApplyFolds()
        end,
    }

    --a hero's header and tab rows: they stay put while the tab scrolls.
    local heroTop = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        bmargin = TOP_GAP,
        interactable = false,
    }

    local content
    local function Pick(tab, sub)
        state.tab = tab
        if sub ~= nil then
            state.sub = sub
            g_lastSubTab[charid] = sub
        end
        scroller.vscrollPosition = 1
        content:FireEvent("refreshBack")
    end

    --laid out at design size and shrunk around its centre (scale, not
    --uiscale: purely visual, so it lands exactly on the card's face).
    content = gui.Panel{
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
            local c = tok.properties
            local isHero = IsHeroProps(c)
            --monsters wear the enemy red the mockup gave them.
            element.parent.selfStyle.borderColor = cond(isHero, "#6fa8ffcc", "#b0444acc")
            local scrollHeight = designHeight - VPAD * 2 - FOOTER_HEIGHT
            if isHero then
                local top = {}
                local ok, header = pcall(Header, tok, c)
                if ok and header ~= nil then
                    top[#top+1] = gui.Panel{
                        width = "100%",
                        height = HERO_HEADER_HEIGHT,
                        bmargin = TOP_GAP,
                        interactable = false,
                        header,
                    }
                end
                local okTabs, tabs = pcall(HeroTabs, state, c, Pick)
                if okTabs then
                    top[#top+1] = tabs
                else
                    print("HeroCardBack: tabs failed:", tabs)
                end
                heroTop.children = top
                heroTop:SetClass("collapsed", false)
                scrollHeight = scrollHeight - HERO_HEADER_HEIGHT - TOP_GAP * 2 - TAB_ROW_HEIGHT - 1
                if state.tab == "combat" then
                    scrollHeight = scrollHeight - SUB_ROW_HEIGHT
                end
                sections, info = BuildHeroTab(tok, charid, state)
            else
                heroTop.children = {}
                heroTop:SetClass("collapsed", true)
                sections, info = BuildSections(tok)
            end
            scroller.selfStyle.height = scrollHeight
            for _, entry in ipairs(info) do
                if entry.heading and entry.foldedByDefault ~= nil then
                    foldDefaults[entry.bucket] = entry.foldedByDefault
                end
            end
            for _, section in ipairs(sections) do
                section.selfStyle.width = CONTENT_WIDTH
            end
            scroller.children = sections
            ApplyFolds()
        end,
        heroTop,
        scroller,
        CreateFooter(charid),
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
                state.tab = CurrentMode() or "combat"
                state.sub = g_lastSubTab[charid] or "basics"
                state.abilities = nil
                scroller.vscrollPosition = 1
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
            --"hover" sits only on the panel under the pointer, so on the
            --button the card loses it: without hidden = 0 here the button
            --hides, the card is hovered again, and it flickers.
            {
                --hidden = 0 too: while the button itself is hovered the card
                --may not be, and without this it would hide and flicker.
                selectors = {"heroCardFlip", "hover"},
                hidden = 0,
                borderColor = COLOR_GOLD,
                scale = 1.15,
            },
            {
                selectors = {"heroCardFlipIcon", "parent:hover"},
                bgcolor = COLOR_GOLD,
            },
            --edge-on, the card slips out from under the mouse: while it
            --turns the button holds its hovered look instead of blinking.
            {
                selectors = {"heroCardFlip", "turning"},
                hidden = 0,
                borderColor = COLOR_GOLD,
                scale = 1.15,
            },
            {
                selectors = {"heroCardFlipIcon", "parent:turning"},
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
        --no tooltip mid-turn: the mouse leaving and re-entering the edge-on
        --card would pop it away and back.
        hover = function(element)
            if element:HasClass("turning") then
                return
            end
            element.tooltip = "Turn the card over"
        end,
        --on click, as the card's dismiss X does: a handled click stops
        --here instead of bubbling up to open the hero's sheet.
        click = function(element)
            element.tooltip = nil
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
--- the "turnCard" event they both fire. Mid-turn the card tells its hosts
--- with "heroCardTurned" (turned) on its parents: the table hides the card's
--- titlebar, which the grown back would otherwise sit under.
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
    local flipButton = CreateFlipButton(charid)
    cardArgs[#cardArgs+1] = flipButton
    cardArgs.turnCard = function(element)
        local turned = not backFace:HasClass("turned")
        flipButton:SetClass("turning", true)
        AnimateFlip(element, cardHeight, cond(turned, 1, TURNED_SCALE), cond(turned, TURNED_SCALE, 1), function()
            backFace:FireEvent("showBack", turned)
            element:FireEventOnParents("heroCardTurned", turned)
        end, function()
            flipButton:SetClass("turning", false)
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

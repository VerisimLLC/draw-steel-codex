local mod = dmhub.GetModLoading()

local T = UIText.T
local TP = UIText.Plural

--PROTOTYPE: the back of the hero card (EotwHeroCard.lua), for heroes and
--monsters alike: the tac panel's information (MCDMCharacterPanel.lua) laid
--out on the card's own face, turned over by a hover button. A hero's back is
--one scroll in the hero sheet's order (Stats, Abilities, Features, Gear) under
--a jump row; a monster's is one scrolling list.
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
--the separator in "Winded 22 · dies at -22", as the hero sheet's {dot}: a
--hyphen there reads as a minus sign.
local MIDDOT = "\u{00B7}"

--dying: a lighter red than the condition chips' #cc2222 border, so it reads
--as text on the dark plate.
local COLOR_DYING = "#ff6b61"

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

--- Hovers --------------------------------------------------------------------

--- Text in a plain dark hover box: a bare gui.Tooltip draws no background
--- over the card's face, and gui.TooltipFrame's faded edge reads as a blur.
--- Long text wraps.
--- @param text string
--- @param markdown? boolean the text is markdown (the tac panel's tooltip text)
--- @return Panel
local function TipFrame(text, markdown)
    local long = #text > 70
    return gui.Panel{
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "center",
        hpad = 12,
        vpad = 8,
        borderBox = true,
        bgimage = "panels/square.png",
        bgcolor = COLOR_PLATE,
        interactable = false,
        gui.Label{ text = text, width = cond(long, 340, "auto"), height = "auto", fontSize = 13, color = COLOR_SOFT, textWrap = long, markdown = markdown == true, interactable = false },
    }
end

--- A built card (an ability's, a trait's) in the same plain box as the text
--- hovers, beside its row.
--- @param card Panel
--- @return Panel
local function CardTip(card)
    return gui.Panel{
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "center",
        pad = 8,
        borderBox = true,
        bgimage = "panels/square.png",
        bgcolor = COLOR_PLATE,
        interactable = false,
        card,
    }
end

--- Shows a hover built when hovered, so a rebuild of the back costs nothing:
--- build returns text (shown framed), a ready tooltip panel, or nil for none.
--- @param element Panel
--- @param build fun(): string|Panel|nil
local function ShowHover(element, build)
    local ok, tip = pcall(build)
    if not ok or tip == nil or tip == "" then
        return
    end
    if type(tip) == "string" then
        element.tooltip = TipFrame(tip)
    else
        element.tooltip = tip
    end
end

--- Gives an already-built panel a hover (see ShowHover). A click on it is for
--- reading it, not for turning the card.
--- @param panel Panel|nil
--- @param build fun(): string|Panel|nil
--- @return Panel|nil
local function WithHover(panel, build)
    if panel == nil then
        return nil
    end
    panel.interactable = true
    if panel.bgimage == nil or panel.bgimage == "" then
        panel.bgimage = "panels/square.png"
        panel.selfStyle.bgcolor = "#00000000"
    end
    if panel.events == nil then
        panel.events = {}
    end
    panel.events.hover = function(element)
        ShowHover(element, build)
    end
    panel.events.click = function(element) end
    return panel
end

--- The tac panel's tooltip text (markdown) in the card's own hover box.
--- @param text string|nil
--- @return Panel|nil
local function TacTip(text)
    if text == nil or text == "" then
        return nil
    end
    return TipFrame(text, true)
end

--- A stat's history (who changed it, when), as the tac panel's boxes show it.
--- @param tok CharacterToken
--- @param resourceid string
--- @param description string
--- @return Panel|nil
local function HistoryTip(tok, resourceid, description)
    local entries = tok.properties:GetStatHistory(resourceid):GetHistory()
    if entries == nil or #entries == 0 then
        return nil
    end
    --as gui.StatsHistoryTooltip reads it: only the latest refresh's changes,
    --in its words, but in the card's own hover box.
    local latest, refreshid = {}, nil
    for _, entry in ipairs(entries) do
        if entry.refreshid ~= refreshid then
            latest = {}
        end
        latest[#latest+1] = entry
        refreshid = entry.refreshid
    end
    local lines = { "Recent changes to " .. description }
    for _, entry in ipairs(latest) do
        local value = entry.value
        if tonumber(value) ~= nil then
            value = round(tonumber(value))
        end
        lines[#lines+1] = string.format("Set to <b>%s</b> by <b>%s</b> %s (%s)", tostring(value), tostring(entry.who), tostring(entry.when), entry.note or "")
    end
    return TipFrame(table.concat(lines, "\n"))
end

--- Where a hero's stat comes from: its base, then one line per source, as the
--- hero sheets show it (EotwHeroSheet.Data).
--- @param tok CharacterToken
--- @param key string a characteristic's attribute id, or a stats key ("speed", "maxStamina", "recoveryValue", ...)
--- @return string|nil
local function SourcesText(tok, key)
    local d = EotwHeroSheet.Data(tok, {"characteristics", "stats"})
    if d == nil then
        return nil
    end
    local s = nil
    for _, entry in ipairs(d.characteristics or {}) do
        if entry.id == key then
            s = entry
        end
    end
    if s == nil and d.stats ~= nil then
        s = d.stats[key]
    end
    if s == nil then
        return nil
    end
    local lines = {}
    if s.base ~= nil then
        lines[#lines+1] = T("herosheet.stats.source_base", { base = tostring(s.base) })
    end
    for _, src in ipairs(s.sources or {}) do
        lines[#lines+1] = string.format("%s %s", src.name or "", src.value or "")
    end
    return table.concat(lines, "\n")
end

--- @param tok CharacterToken
--- @param key string
--- @return fun(element: Panel)
local function StatHover(tok, key)
    return function(element)
        ShowHover(element, function() return SourcesText(tok, key) end)
    end
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
            --hover: the kit's stat bonuses, as the tac panel's kit name shows them.
            WithHover(Text{ text = table.concat(parts, " - "), height = 16, fontSize = 12, minFontSize = 8, textWrap = false, color = COLOR_MUTED }, function()
                local tac = rawget(_G, "TacPanel")
                local kit = Try(function() return c:Kit() end)
                if tac == nil or tac.KitStatsTooltip == nil or kit == nil then
                    return nil
                end
                return TacTip(tac.KitStatsTooltip(kit))
            end),
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

--- @param tok? CharacterToken a hero's token: stamina, recoveries, victories and hero tokens get hovers
local function StaminaStrip(c, tok)
    local isHero = IsHeroProps(c)
    --only built when tok is set (Hover), so the closures can rely on it.
    local heroTok = tok --[[@as CharacterToken]]
    local function Hover(panel, build)
        if tok == nil then
            return panel
        end
        return WithHover(panel, build) or panel
    end
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

    --heroes and retainers die below 0 (at -winded); for them the label gives
    --the range, and while dying the bar fills red with how far in they are.
    local death = tonumber(Try(function() return c:KillThresholdStamina() end, 0)) or 0
    local dying = death < 0 and Try(function() return c:IsDying() end, cur <= 0) == true
    local dyingWidth = 0
    if dying then
        dyingWidth = math.floor(barWidth * math.max(0, math.min(1, cur / death)))
    end

    local numbers
    if dying then
        numbers = string.format("<b><color=%s>%d</color></b> / %d  <b><color=%s>%s</color></b>", COLOR_DYING, cur, max, COLOR_DYING, T("herocard.back.stamina.dying"))
    else
        numbers = string.format("<b><color=%s>%d</color></b> / %d", COLOR_TEXT, cur, max)
    end
    if temp > 0 then
        numbers = numbers .. string.format("   <color=%s>+%d temp</color>", COLOR_TEMP, temp)
    end
    local thresholds
    if death < 0 then
        thresholds = T("herocard.back.stamina.range", { winded = string.format("%d", winded), dot = MIDDOT, death = string.format("%d", death) })
    else
        thresholds = T("herocard.back.stamina.winded", { winded = string.format("%d", winded) })
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
            --hovers: the hero sheet's own words for recoveries and victories,
            --and the tac panel's rules and history for hero tokens.
            Hover(Text{ text = recText, fontSize = 11.5, color = COLOR_MUTED, width = "46%", textWrap = false }, function()
                local tip = T("herosheet.card.recovery_tip", { value = string.format("%d", recValue or 0) })
                local sources = SourcesText(heroTok, "recoveryValue")
                if sources ~= nil and sources ~= "" then
                    tip = tip .. "\n\n" .. sources
                end
                return tip
            end),
            Hover(Text{ text = string.format("Victories <b><color=%s>%d</color></b>", COLOR_TEXT, victories), fontSize = 11.5, color = COLOR_MUTED, width = "24%", textAlignment = "center", textWrap = false }, function()
                local resource = Try(function() return c:GetHeroicResourceName() end) or T("herosheet.card.resource_fallback")
                return T("herosheet.card.victories_tip", { victories = string.format("%d", victories), resource = resource })
            end),
            Hover(Text{ text = string.format("Hero Tokens <b><color=%s>%d</color></b>", COLOR_TEXT, heroTokens), fontSize = 11.5, color = COLOR_MUTED, width = "30%", textAlignment = "right", textWrap = false }, function()
                local tac = rawget(_G, "TacPanel")
                if tac == nil or tac.HeroTokenTooltipText == nil then
                    return nil
                end
                return TacTip(tac.HeroTokenTooltipText(c))
            end),
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
        --hover: where the hero's maximum Stamina comes from.
        Hover(gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            interactable = false,
            Text{ text = numbers, fontSize = 13, color = COLOR_MUTED, width = "52%" },
            Text{ text = thresholds, fontSize = 11, color = COLOR_MUTED, width = "48%", textAlignment = "right", valign = "center" },
        }, function() return SourcesText(heroTok, "maxStamina") end),
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
            --while dying: how far toward death.
            gui.Panel{
                floating = true,
                halign = "left",
                width = dyingWidth,
                height = "100%",
                bgimage = "panels/square.png",
                bgcolor = COLOR_DYING,
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

--- @param tok? CharacterToken a hero's token: each characteristic gets a hover with its sources
local function Characteristics(c, tok)
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
            bgimage = "panels/square.png",
            bgcolor = "#00000000",
            interactable = tok ~= nil,
            hover = tok ~= nil and StatHover(tok, attr.id) or nil,
            --a click rolls a test with the characteristic, as the tac panel's
            --box does, for whoever controls the hero; for anyone else it only
            --stops the card turning.
            click = tok ~= nil and function(element)
                if not (dmhub.isDM or Try(function() return tok.canControl end, false)) then
                    return
                end
                audio.FireSoundEvent("Mouse.Click")
                pcall(function() tok.properties:ShowCharacteristicRollDialog(attr.id) end)
            end or nil,
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

--- @param tok? CharacterToken a hero's token: speed, disengage, stability and size get hovers with their sources
local function MovementLine(c, tok)
    local function Stat(name, value)
        return string.format("%s <b><color=%s>%s</color></b>", name, COLOR_TEXT, tostring(value))
    end

    --each part: its text and, for a stat with sources, the key StatHover reads.
    local parts = {}
    local speed = Try(function() return c:CurrentMovementSpeed() end)
    if speed ~= nil then
        parts[#parts+1] = { Stat("Speed", speed), "speed" }
    end
    local disengage = Try(function()
        return c:GetCustomAttribute(CustomAttribute.attributeInfoByLookupSymbol["disengagespeed"])
    end)
    if disengage ~= nil then
        parts[#parts+1] = { Stat("Disengage", disengage), "disengage" }
    end
    local stability = Try(function() return c:Stability() end)
    if stability ~= nil then
        parts[#parts+1] = { Stat("Stability", stability), "stability" }
    end
    local size = Try(function() return c:SizeDescription() end)
    if size ~= nil and size ~= "" then
        parts[#parts+1] = { Stat("Size", size), "size" }
    end
    if not IsHeroProps(c) then
        local freeStrike = Try(function() return c:OpportunityAttack() end)
        if freeStrike ~= nil then
            parts[#parts+1] = { Stat("Free strike", freeStrike) }
        end
    else
        local surges = Try(function() return c:GetAvailableSurges() end)
        if surges ~= nil then
            --what each surge adds to damage, as the hero sheet works it out.
            local damage = 0
            local sheet = rawget(_G, "EotwHeroSheet")
            if sheet ~= nil and tok ~= nil then
                damage = tonumber(Try(function() return sheet.Data(tok, {"resource"}).surgeDamage end, 0)) or 0
            end
            local text = Stat("Surges", surges)
            if damage > 0 then
                text = text .. string.format(" <color=%s>%s</color>", COLOR_MUTED, T("herocard.back.surges.damage", { damage = string.format("%d", damage) }))
            end
            --hover: the hero sheet's words for surges and their damage.
            parts[#parts+1] = { text, nil, function()
                return TP("herosheet.card.surges_tip", tonumber(surges) or 0, { damage = string.format("%d", damage) })
            end }
        end
    end

    local moveType = Try(function() return c:CurrentMoveType() end)
    if moveType == "fly" then
        parts[#parts+1] = { "Flying" }
    elseif moveType == "burrow" then
        parts[#parts+1] = { "Burrowing" }
    elseif Try(function() return c:IsClingingToCeiling() end, false) then
        parts[#parts+1] = { "Clinging" }
    elseif moveType == "climb" then
        parts[#parts+1] = { "Climbing" }
    end

    --a monster's line is one label; a hero's is one piece per stat, so each
    --can carry its own hover.
    local statsRow
    if tok == nil then
        local texts = {}
        for _, part in ipairs(parts) do
            texts[#texts+1] = part[1]
        end
        statsRow = Text{
            text = table.concat(texts, "   "),
            fontSize = 12,
            color = COLOR_MUTED,
            textAlignment = "center",
            vmargin = 4,
        }
    else
        local pieces = {}
        for i, part in ipairs(parts) do
            --a stats key reads the stat's sources; a function builds its own hover.
            local key, build = part[2], part[3]
            local hover = nil
            if key ~= nil then
                hover = StatHover(tok, key)
            elseif build ~= nil then
                hover = function(element) ShowHover(element, build) end
            end
            pieces[#pieces+1] = gui.Panel{
                width = "auto",
                height = "auto",
                lmargin = cond(i == 1, 0, 9),
                bgimage = "panels/square.png",
                bgcolor = "#00000000",
                interactable = hover ~= nil,
                hover = hover,
                click = hover ~= nil and function(element) end or nil,
                Text{ text = part[1], width = "auto", fontSize = 12, color = COLOR_MUTED, textWrap = false },
            }
        end
        statsRow = gui.Panel{
            width = "auto",
            height = "auto",
            halign = "center",
            vmargin = 4,
            flow = "horizontal",
            interactable = false,
            children = pieces,
        }
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
        statsRow,
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

--Whether this user may change a creature's conditions, effects and auras
--from its card: the Director, or whoever controls it outside Encounter of the
--Week (where the character panels are read-only too).
local function CanEditEffects(tok)
    if dmhub.isDM then
        return true
    end
    local control = false
    pcall(function() control = tok.canControl == true end)
    if not control then
        return false
    end
    local eotw = false
    local eotwGame = rawget(_G, "EncounterOfTheWeekGame")
    if eotwGame ~= nil then
        pcall(function() eotw = eotwGame.IsEotwGame() == true end)
    end
    return not eotw
end

--the add button whose menu is open, if any: the back is not rebuilt under an
--open menu (see the back face's refreshGame), which would close it.
---@type Panel|nil
local g_effectsMenuButton = nil
--when that menu last closed: the press that closes it by clicking the card
--must not also turn the card (see the back face's click).
---@type number|nil
local g_effectsMenuClosedAt = nil

--- Whether a card's add-a-condition menu is open.
--- @return boolean
local function EffectsMenuOpen()
    local button = g_effectsMenuButton
    return button ~= nil and button.valid and button.popup ~= nil
end

--each card back's heroic resource entry box: like the menu, a back is not
--rebuilt while one is open, which would throw away the typing.
---@type Input[]
local g_resourceEntries = {}

--- Whether something on a card back is mid-edit (the add-a-condition menu,
--- the heroic resource box), so a rebuild must wait.
--- @return boolean
local function BackEditOpen()
    if EffectsMenuOpen() then
        return true
    end
    for i = #g_resourceEntries, 1, -1 do
        local entry = g_resourceEntries[i]
        if not entry.valid then
            table.remove(g_resourceEntries, i)
        elseif not entry:HasClass("collapsed") then
            return true
        end
    end
    return false
end

--- For a click on the card: true when it closed the add-a-condition menu
--- (the menu closes on the press), so the card must not turn this time.
--- @return boolean
local function ConsumeMenuClick()
    local button = g_effectsMenuButton
    if button ~= nil and button.valid and button.popup ~= nil then
        button.popup = nil
        g_effectsMenuClosedAt = nil
        return true
    end
    if g_effectsMenuClosedAt ~= nil and dmhub.Time() - g_effectsMenuClosedAt < 1 then
        g_effectsMenuClosedAt = nil
        return true
    end
    return false
end

--- The "+" that opens the character panel's add-a-condition menu
--- (TacPanel.AddConditionMenu) for this creature.
local function AddEffectButton(tok, tac)
    return gui.Panel{
        classes = {"heroCardAddEffect", "editOnly"},
        width = "auto",
        height = "auto",
        hpad = 8,
        vpad = 1,
        margin = 2,
        valign = "top",
        bgimage = "panels/square.png",
        bgcolor = "#00000000",
        border = 1,
        borderColor = COLOR_GOLD,
        cornerRadius = 4,
        styles = {
            { selectors = {"heroCardAddEffect", "hover"}, bgcolor = "#ffffff22" },
        },
        hover = function(element)
            gui.Tooltip("Add a condition or effect")(element)
        end,
        click = function(element)
            if not CanEditEffects(tok) then
                return
            end
            element.tooltip = nil
            g_effectsMenuButton = element
            tac.AddConditionMenu{ tokens = {tok}, button = element }
            --the menu's dialog look comes from the theme, which the card's
            --style cascade does not carry: give the menu the theme itself.
            local theme = rawget(_G, "ThemeEngine")
            local tacStyles = rawget(_G, "TacPanelStyles")
            if element.popup ~= nil and theme ~= nil and tacStyles ~= nil then
                element.popup.styles = theme.MergeStyles(tacStyles.AddConditionMenu)
            end
        end,
        closePopup = function(element)
            g_effectsMenuClosedAt = dmhub.Time()
            --picking from the menu closes it on the press, so the release
            --lands on whatever was under the menu. Over a map window, that
            --release would bring the map up over the card. Raising the card
            --here counts as a window activation, so the map stays put
            --(MapViewport.RaiseOnMapPress).
            local frame = element:FindParentWithClass("tabletopCard")
            if frame ~= nil and frame.valid then
                frame:SetAsLastSibling()
            end
        end,
        gui.Label{
            text = "+",
            width = "auto",
            height = "auto",
            fontSize = 15,
            bold = true,
            color = COLOR_GOLD,
            interactable = false,
        },
    }
end

--- The character panel's condition, effect and aura chips, with their
--- controls (TacPanel.ConditionChipList), and a "+" to add one. nil where
--- that panel isn't loaded (the title screen).
--- @return Panel|nil
local function ManagedEffects(tok)
    local tac = rawget(_G, "TacPanel")
    local tacStyles = rawget(_G, "TacPanelStyles")
    if tok == nil or tac == nil or tac.ConditionChipList == nil or tacStyles == nil then
        return nil
    end
    local chips = tac.ConditionChipList(tok, AddEffectButton(tok, tac))
    --the chips' looks, and "readonly" hiding their controls from a user
    --who may not change them (TacPanel.IsReadOnly).
    local styles = {}
    for _, list in ipairs({tacStyles.Conditions or {}, tacStyles.ReadOnly or {}}) do
        for _, rule in ipairs(list) do
            styles[#styles+1] = rule
        end
    end
    --the chips' buttons (Set Caster, remove) take their look from the
    --theme, which the card's cascade lacks: without it they are invisible
    --but still pressable. The tactical panel gets the theme from its dock.
    local theme = rawget(_G, "ThemeEngine")
    if theme ~= nil then
        styles = theme.MergeStyles(styles)
    end
    return gui.Panel{
        classes = {"panel", "cond-chips", cond(CanEditEffects(tok), nil, "readonly")},
        styles = styles,
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        tmargin = 0,
        bmargin = 4,
        --a click among the chips (a remove X acts on press) is not for
        --turning the card.
        click = function(element) end,
        children = chips,
    }
end

--- Under the chips while a condition or effect on the creature ends on a
--- save: what the save needs, worked out as the save itself does it
--- (MCDMAbilitySaveBehavior: 1d10 + Save Bonus against the Save Ends
--- threshold, 6 unless something changes it). nil when nothing saves.
local function SaveLine(c)
    local saving = false
    for _, entry in pairs(Try(function() return c:try_get("inflictedConditions", {}) end, {})) do
        if entry.duration == "save" then
            saving = true
        end
    end
    for _, entry in ipairs(Try(function() return c:ActiveOngoingEffects() end, {})) do
        if Try(function() return entry.removeOnSave end, false) == true then
            saving = true
        end
    end
    if not saving then
        return nil
    end
    local threshold = tonumber(Try(function()
        return ExecuteGoblinScript("Save Ends", c:LookupSymbol({}), 6, "Save Ends threshold")
    end, 6)) or 6
    local bonus = tonumber(Try(function() return c:CalculateNamedCustomAttribute("Save Bonus") end, 0)) or 0
    local roll = "1d10"
    if bonus ~= 0 then
        roll = string.format("1d10 %s %d", cond(bonus > 0, "+", "-"), math.abs(bonus))
    end
    return Text{
        text = T("herocard.back.save.line", {
            threshold = string.format("<b><color=%s>%d+</color></b>", COLOR_TEXT, threshold),
            roll = roll,
        }),
        fontSize = 11.5,
        color = COLOR_MUTED,
        bmargin = 3,
    }
end

local function Effects(c, tok)
    local chips = {}
    ---@type Panel|nil
    local managed = nil
    local ok, err = pcall(function() managed = ManagedEffects(tok) end)
    if not ok then
        print("HeroCardBack: effects failed:", err)
    end

    --without the character panel (the title screen): plain chips, with
    --their rules on hover.
    local conditionsTable = Try(function() return dmhub.GetTable(CharacterCondition.tableName) end, {})
    local inflicted = Try(function() return c:try_get("inflictedConditions", {}) end, {})
    if managed ~= nil then
        inflicted = {}
    end
    for condid, condEntry in pairs(inflicted) do
        local info = conditionsTable[condid]
        if info ~= nil then
            local text = info.name
            if not info.indefiniteDuration then
                text = text .. " - " .. DurationText(condEntry.duration)
            end
            --hover: the condition's rules, as the tac panel's chip shows them.
            chips[#chips+1] = WithHover(Chip(text, "#4a1716", "#cc2222", "#ffd9d6"), function()
                local tac = rawget(_G, "TacPanel")
                if tac == nil or tac.ConditionTooltipText == nil then
                    return nil
                end
                return TacTip(tac.ConditionTooltipText(condid, condEntry, c))
            end)
        end
    end

    local effectsTable = Try(function() return dmhub.GetTable("characterOngoingEffects") end, {})
    local effects = Try(function() return c:ActiveOngoingEffects() end, {})
    if managed ~= nil then
        effects = {}
    end
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
            chips[#chips+1] = WithHover(Chip(text, "#3d2512", "#c46a1c", "#ffe2c2"), function()
                local tac = rawget(_G, "TacPanel")
                if tac == nil or tac.StatusEffectTooltipText == nil then
                    return nil
                end
                return TacTip(tac.StatusEffectTooltipText(entry, info, c))
            end)
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
    if managed ~= nil then
        children[#children+1] = managed
    elseif #chips > 0 then
        children[#children+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            interactable = false,
            children = chips,
        }
    end
    local okSave, saveLine = pcall(SaveLine, c)
    if okSave and saveLine ~= nil then
        children[#children+1] = saveLine
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
        --hover: the gain's own details, as the tac panel's gain row shows them.
        local details = entry.details
        rows[#rows+1] = WithHover(TwoColumnRow(entry.name or "", amountText, nil, consumed), function()
            if type(details) ~= "string" then
                return nil
            end
            return details
        end)
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

--- @param tok? CharacterToken a hero's token: each row's hover shows the ability's card
local function PersistentAbilities(c, tok)
    local q = dmhub.initiativeQueue
    if q == nil or q.hidden then
        return nil
    end
    local resourceName = Try(function() return c:GetHeroicResourceName() end, "")
    local rows = {}
    for _, entry in ipairs(Try(function() return c:try_get("persistentAbilities") end, {})) do
        if entry.combatid == q.guid then
            local row = TwoColumnRow(entry.abilityName or "", string.format("%d %s / turn", entry.cost or 0, resourceName), COLOR_RESOURCE)
            if tok ~= nil then
                local name = entry.abilityName
                row = WithHover(row, function()
                    for _, ability in ipairs(c:GetActivatedAbilities{ bindCaster = true }) do
                        if ability.name == name then
                            return CardTip(ability:Render({ width = 420 }, { token = tok }))
                        end
                    end
                    return nil
                end) or row
            end
            rows[#rows+1] = row
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
--- @param onClick nil|fun() what a click does; without it a click does nothing
local function Row(name, meta, tooltip, onClick)
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
                element.tooltip = CardTip(card)
            end
        end,
        --a click on a row is never for turning the card.
        click = function(element)
            if onClick ~= nil then
                element.tooltip = nil
                onClick()
            end
        end,
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
        function() return Effects(c, tok) end,
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

--- Hero scroll -----------------------------------------------------------------

--A hero's back is one scroll in the hero sheet's order: Stats, Abilities,
--Features, Gear. The header and a jump row stay in place above it; the jump
--row only scrolls to a section's heading.

local HERO_HEADER_HEIGHT = 66
local JUMP_ROW_HEIGHT = 28
local TOP_GAP = 6

local HERO_SECTIONS = { "stats", "abilities", "features", "gear" }

--ability buckets, in the sheet's order. These start open; the rest folded.
local HERO_BUCKETS = { "freestrike", "signature", "heroic", "triggered", "main", "maneuver", "other", "standard" }
local OPEN_BUCKETS = { freestrike = true, signature = true, heroic = true, triggered = true }

--reading a hero's abilities builds the feature index, so a card reuses the
--list this long while game updates rebuild its back.
local ABILITY_CACHE_SECONDS = 5

--- @param id string
--- @return string
local function SectionTitle(id)
    if id == "stats" then
        return T("herocard.back.section.stats")
    elseif id == "abilities" then
        return T("herocard.back.section.abilities")
    elseif id == "features" then
        return T("herocard.back.section.features")
    end
    return T("herocard.back.section.gear")
end

--- A section's big heading in the scroll: the place the jump row scrolls to.
--- @param id string
--- @return Panel
local function SectionHeading(id)
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 4,
        interactable = false,
        Text{
            text = string.upper(SectionTitle(id)),
            fontSize = 17,
            bold = true,
            color = COLOR_GOLD,
            bmargin = 2,
        },
        Divider(),
    }
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
    elseif id == "triggered" then
        return T("herocard.back.bucket.triggered")
    end
    return T("herocard.back.bucket.other")
end

local function InCombat()
    local q = dmhub.initiativeQueue
    return q ~= nil and not q.hidden
end

--- One button in the jump row: a word that lights on hover. A click scrolls
--- to its section instead of turning the card.
--- @param args {text: string, width: number, height: number, click: fun()}
--- @return Panel
local function JumpButton(args)
    return gui.Panel{
        classes = {"heroCardJump"},
        styles = {
            { selectors = {"heroCardJump"}, bgcolor = "#00000000" },
            { selectors = {"heroCardJump", "hover"}, bgcolor = COLOR_PLATE },
            { selectors = {"heroCardJumpLabel"}, color = COLOR_MUTED },
            { selectors = {"heroCardJumpLabel", "parent:hover"}, color = COLOR_TEXT },
        },
        width = args.width,
        height = args.height,
        bgimage = "panels/square.png",
        click = function(element)
            audio.FireSoundEvent("Mouse.Click")
            args.click()
        end,
        gui.Label{
            classes = {"heroCardJumpLabel"},
            text = args.text,
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
            fontSize = 12,
            bold = true,
            textWrap = false,
            interactable = false,
        },
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

--- The jump row: one button per section, each scrolling to its heading.
--- @param jump fun(section: string)
--- @return Panel
local function JumpRow(jump)
    local width = math.floor(INNER_WIDTH / #HERO_SECTIONS)
    local buttons = {}
    for _, id in ipairs(HERO_SECTIONS) do
        buttons[#buttons+1] = JumpButton{
            text = SectionTitle(id),
            width = width,
            height = JUMP_ROW_HEIGHT,
            click = function() jump(id) end,
        }
    end
    return gui.Panel{
        width = INNER_WIDTH,
        height = "auto",
        flow = "vertical",
        interactable = false,
        gui.Panel{
            width = INNER_WIDTH,
            height = JUMP_ROW_HEIGHT,
            flow = "horizontal",
            interactable = false,
            children = buttons,
        },
        Divider(),
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

--- Starts using an ability from the card, as the action bar does when one of
--- its abilities is clicked: targeting on the map, then the cast. Only for
--- whoever controls the hero, and only while the hero is on the map being
--- shown (the bar targets there).
--- @param charid string
--- @param ability ActivatedAbility
local function UseAbility(charid, ability)
    local tok = dmhub.GetTokenById(charid)
    if tok == nil or not tok.valid then
        return
    end
    local control = false
    pcall(function() control = tok.canControl == true end)
    if not (dmhub.isDM or control) then
        return
    end
    local hud = rawget(_G, "gamehud")
    if hud == nil or hud.actionBarPanel == nil then
        return
    end
    audio.FireSoundEvent("Mouse.Click")
    hud.actionBarPanel:FireEventTree("invokeAbility", tok, ability, {})
end

--- One ability as a row: its cost and action on the right, its card on hover.
--- Greyed out when the hero can't pay for it now. usable: a click uses it
--- (UseAbility).
--- @param usable nil|boolean
--- @return Panel
local function AbilityItemRow(item, tok, spendable, usable)
    local onClick = nil
    if usable and item.ability ~= nil then
        local charid = tok.charid
        onClick = function()
            UseAbility(charid, item.ability)
        end
    end
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
    end, onClick)
    local cost = item.ability ~= nil and HeroicCost(item.ability) or nil
    if spendable ~= nil and cost ~= nil and cost > spendable then
        Fade(row, 0.45)
    end
    return row
end

--- Adds a folding bucket of rows: its heading, then the rows.
--- @param count? number what the folded heading counts, when not every row
local function AppendBucket(result, info, title, rows, foldedByDefault, count)
    if #rows == 0 then
        return
    end
    result[#result+1] = BucketHeading(title, count or #rows, COLOR_GOLD)
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

--- In combat: whether the triggered action is spent this round. Nil outside
--- combat, or for a hero with no triggered action to spend.
local function TriggerReadyLine(c)
    if not InCombat() then
        return nil
    end
    local id = CharacterResource.triggerResourceId
    local max = tonumber(Try(function() return c:GetResources()[id] end, 0)) or 0
    local used = tonumber(Try(function() return c:GetResourceUsage(id, "round") end, 0)) or 0
    if max <= 0 then
        return nil
    end
    if used < max then
        return Text{ text = T("herocard.back.triggers.ready"), fontSize = 12, bold = true, color = COLOR_STAMINA, bmargin = 2 }
    end
    return Text{ text = T("herocard.back.triggers.used"), fontSize = 12, color = COLOR_MUTED, bmargin = 2 }
end

--- The hero's potencies, Weak, Average and Strong, with their bonuses: the top
--- of Abilities, since every potency effect in them is checked against these.
--- Hover: what potency does.
local function PotencyRow(c)
    --the rules' potency names, with the card's words for them.
    local tiers = {
        { id = "weak", text = T("herocard.back.potency.weak") },
        { id = "average", text = T("herocard.back.potency.average") },
        { id = "strong", text = T("herocard.back.potency.strong") },
    }
    local labelWidth = 66
    local cellWidth = math.floor((CONTENT_WIDTH - labelWidth) / #tiers)
    local cells = {
        Text{ text = string.upper(T("herocard.back.potency.title")), width = labelWidth, fontSize = 11, bold = true, color = COLOR_MUTED, valign = "center", textWrap = false },
    }
    for _, tier in ipairs(tiers) do
        local value = tonumber(Try(function() return c:CalculatePotencyValue(tier.id) end))
        if value == nil then
            return nil
        end
        cells[#cells+1] = gui.Panel{
            width = cellWidth - 6,
            height = 24,
            rmargin = 6,
            bgimage = "panels/square.png",
            bgcolor = COLOR_PLATE,
            border = 1,
            borderColor = "#3a4654",
            interactable = false,
            Text{
                text = string.format("<b><size=15><color=%s>%d</color></size></b>  %s", COLOR_TEXT, value, tier.text),
                height = "100%",
                valign = "center",
                fontSize = 11,
                color = COLOR_MUTED,
                textAlignment = "center",
                textWrap = false,
            },
        }
    end
    return WithHover(gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        --clear of the Abilities heading's rule above it.
        tmargin = 8,
        interactable = false,
        children = cells,
    }, function() return T("herocard.back.potency.tip") end)
end

--- Abilities: every ability in folding buckets in the sheet's order, the
--- triggered actions in their own bucket with what sets each off.
--- Appended to result/info.
local function AppendAbilities(result, info, tok, c, state)
    local buckets, triggers = SortAbilities(HeroAbilityGroups(tok, state))
    buckets.triggered = triggers
    local spendable = SpendableResource(c)
    local before = #result
    for _, id in ipairs(HERO_BUCKETS) do
        local rows = {}
        if id == "triggered" and #triggers > 0 then
            local ok, ready = pcall(TriggerReadyLine, c)
            if ok and ready ~= nil then
                rows[#rows+1] = ready
            end
        end
        for _, item in ipairs(buckets[id] or {}) do
            local ok, row
            if id == "triggered" then
                ok, row = pcall(TriggerEntry, item, tok, c)
            else
                ok, row = pcall(AbilityItemRow, item, tok, spendable, true)
            end
            if ok and row ~= nil then
                rows[#rows+1] = row
            end
        end
        AppendBucket(result, info, BucketLabel(id), rows, not OPEN_BUCKETS[id], #(buckets[id] or {}))
    end
    if #result == before then
        result[#result+1] = EmptyLine(T("herocard.back.abilities.none"))
        info[#info+1] = { heading = false }
    end
end

--the heroic resource's amount: a little larger than the stamina numbers.
local RESOURCE_FONT_SIZE = 18

--- A resource on one line in Stats: the amount, then its name. Edited where it
--- stands while current() gives a number; hover shows its history.
--- @param args {name: string, value: number, holder: CharacterToken, resourceid: string, current: (fun(): number|nil)|nil, apply: fun(amount: integer)|nil}
--- @return Panel
local function ResourceLine(args)
    local valueLabel = Text{ text = tostring(args.value), width = "auto", fontSize = RESOURCE_FONT_SIZE, bold = true, color = COLOR_RESOURCE, textWrap = false, valign = "center", rmargin = 6 }
    local card = rawget(_G, "EotwHeroCard")
    if card ~= nil and args.current ~= nil and args.current() ~= nil then
        --room for the highlight's left edge inside the scroll's clip.
        valueLabel.selfStyle.lmargin = 4
        g_resourceEntries[#g_resourceEntries+1] = card.CreateNumberEntry{
            label = valueLabel,
            fontSize = RESOURCE_FONT_SIZE,
            color = COLOR_RESOURCE,
            current = args.current,
            apply = args.apply,
        }
    end
    local holder, resourceid, name = args.holder, args.resourceid, args.name
    return WithHover(gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        bmargin = 2,
        interactable = false,
        valueLabel,
        Text{ text = name, width = "auto", fontSize = 13, bold = true, color = COLOR_SOFT, textWrap = false, valign = "center" },
    }, function() return HistoryTip(holder, resourceid, name) end)
end

--- The hero's heroic resource (who may edit it is decided on the card's front).
local function ResourceHeadline(c, tok)
    local name, value = HeroResource(c)
    local charid = tok.charid
    local card = rawget(_G, "EotwHeroCard")
    return ResourceLine{
        name = name,
        value = value,
        holder = tok,
        resourceid = CharacterResource.heroicResourceId,
        current = card ~= nil and function() return card.HeroResourceCurrent(charid) end or nil,
        apply = card ~= nil and function(amount) card.SetHeroResource(charid, amount) end or nil,
    }
end

--- A class's own resource (Rampage, Patron's Gaze), from its tac panel
--- display's card entry, as a line like the heroic resource's. Editable by
--- whoever may edit the heroic resource.
--- @param info {name: string, resourceid: string, holder: CharacterToken}
local function ClassResourceLine(tok, info)
    local holder, resourceid = info.holder, info.resourceid
    local value = Try(function() return holder.properties:GetUnboundedResourceQuantity(resourceid) end, 0)
    local charid = tok.charid
    local card = rawget(_G, "EotwHeroCard")
    local current = nil
    if card ~= nil then
        current = function()
            if card.HeroResourceCurrent(charid) == nil or not holder.valid then
                return nil
            end
            return Try(function() return holder.properties:GetUnboundedResourceQuantity(resourceid) end, 0)
        end
    end
    return ResourceLine{
        name = info.name,
        value = tonumber(value) or 0,
        holder = holder,
        resourceid = resourceid,
        current = current,
        apply = function(amount)
            if not holder.valid then
                return
            end
            local n = math.max(0, amount)
            local have = tonumber(Try(function() return holder.properties:GetUnboundedResourceQuantity(resourceid) end, 0)) or 0
            if n == have then
                return
            end
            holder:ModifyProperties{
                description = "Set " .. info.name,
                execute = function()
                    holder.properties:AddUnboundedResource(resourceid, n - have, info.name)
                end,
            }
        end,
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
    --hover: its history, as the tac panel's Other Resources row keeps it.
    local name = epic.name
    return WithHover(TwoColumnRow(T("herocard.back.resource.epic", { resource = name }), tostring(epic.value or 0), COLOR_RESOURCE), function()
        return HistoryTip(tok, CharacterResource.epicResourceId, name)
    end)
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
                --hover: the threshold's own tooltip, as the tac panel's row shows it.
                local tip = entry.tooltip
                children[#children+1] = WithHover(GrowthRow(need, text, active, expiring), function()
                    if type(tip) ~= "string" then
                        return nil
                    end
                    return tip
                end)
            end
        end
    end
    return Lines(children)
end

--the tac panel's own resource boxes; the card shows these itself.
local CORE_RESOURCE_DISPLAYS = { victories = true, heroic = true, recoveries = true, herotokens = true, surges = true }

--- The class resources registered with the tac panel that say how the card
--- shows them (entry.card): one line each, like the heroic resource's.
local function ClassResourceLines(tok)
    local tac = rawget(_G, "TacPanel")
    if tac == nil or tac.GetHeroicResourceDisplays == nil then
        return nil
    end
    local lines = {}
    for _, entry in ipairs(tac.GetHeroicResourceDisplays()) do
        if not CORE_RESOURCE_DISPLAYS[entry.id] and entry.card ~= nil then
            local ok, info = pcall(entry.card, tok)
            if ok and info ~= nil and info.holder ~= nil and info.holder.valid then
                local okLine, line = pcall(ClassResourceLine, tok, info)
                if okLine and line ~= nil then
                    lines[#lines+1] = line
                end
            end
        end
    end
    return Lines(lines)
end

--- A small word that lights on hover and does something on click, instead of
--- turning the card.
--- @param args {text: string, tip: string|nil, click: fun()}
--- @return Panel
local function LinkButton(args)
    return gui.Panel{
        classes = {"heroCardLink"},
        styles = {
            { selectors = {"heroCardLink"}, bgcolor = "#00000000" },
            { selectors = {"heroCardLink", "hover"}, bgcolor = "#ffffff14" },
            { selectors = {"heroCardLinkLabel"}, color = COLOR_BLUE },
            { selectors = {"heroCardLinkLabel", "parent:hover"}, color = COLOR_TEXT },
        },
        width = "auto",
        height = "auto",
        hpad = 4,
        vpad = 1,
        lmargin = 4,
        valign = "center",
        bgimage = "panels/square.png",
        hover = function(element)
            if args.tip ~= nil then
                element.tooltip = TipFrame(args.tip)
            end
        end,
        click = function(element)
            audio.FireSoundEvent("Mouse.Click")
            args.click()
        end,
        gui.Label{
            classes = {"heroCardLinkLabel"},
            text = args.text,
            width = "auto",
            height = "auto",
            fontSize = 11,
            bold = true,
            textWrap = false,
            interactable = false,
        },
    }
end

--- One squad: its name, how many minions are up and its Stamina, their
--- portraits, and a thin bar in the squad's colour.
local function SquadRow(name, total, liveTokens, sq)
    local maxhp = tonumber(sq.maximum_health) or 0
    local hp = math.max(0, maxhp - (tonumber(sq.damage_taken) or 0))
    local pct = 0
    if maxhp > 0 then
        pct = math.max(0, math.min(1, hp / maxhp))
    end
    local portraits = {}
    for _, minion in ipairs(liveTokens) do
        local ok, image = pcall(gui.CreateTokenImage, minion, { width = 22, height = 22, rmargin = 3, bmargin = 2, interactable = false })
        if ok and image ~= nil then
            portraits[#portraits+1] = image
        end
    end
    local barWidth = CONTENT_WIDTH - 20
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 4,
        interactable = false,
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            interactable = false,
            Text{ text = name, width = "55%", fontSize = 12, bold = true, color = COLOR_TEXT, textWrap = false },
            Text{
                text = T("herocard.back.summoner.count", {
                    dot = MIDDOT,
                    live = string.format("%d", tonumber(sq.liveMinions) or #liveTokens),
                    total = string.format("%d", total),
                    stamina = string.format("<b><color=%s>%d</color></b>/%d", COLOR_TEXT, hp, maxhp),
                }),
                width = "45%",
                fontSize = 11,
                color = COLOR_MUTED,
                textAlignment = "right",
                textWrap = false,
            },
        },
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            tmargin = 3,
            interactable = false,
            children = portraits,
        },
        gui.Panel{
            width = barWidth,
            height = 6,
            tmargin = 2,
            bgimage = "panels/square.png",
            bgcolor = "#00000080",
            interactable = false,
            gui.Panel{
                floating = true,
                halign = "left",
                width = math.floor(barWidth * pct),
                height = "100%",
                bgimage = "panels/square.png",
                bgcolor = sq.color or COLOR_STAMINA,
                interactable = false,
            },
        },
    }
end

--- A Summoner's minion squads in the card's style, on a plate like the
--- stamina strip. Sacrifice and Edit for whoever controls the hero; the
--- squads' rules on the label's hover. Nil for a hero who isn't a summoner.
local function MinionSquads(tok, c)
    local range = tonumber(Try(function() return c:CalculateNamedCustomAttribute("SummonerRange") end, 0)) or 0
    if range <= 0 then
        return nil
    end
    local control = Try(function() return tok.canControlAsUser end, false) == true

    local title = SectionLabel(T("herocard.back.summoner.title"))
    title.selfStyle.width = "auto"
    title.selfStyle.valign = "center"
    local header = {
        --hover: what a squad does on its turn.
        WithHover(title, function()
            return TipFrame(T("herocard.back.summoner.rules"), true)
        end),
    }
    if control then
        local buttons = {}
        buttons[#buttons+1] = LinkButton{
            text = T("herocard.back.summoner.sacrifice"),
            tip = T("herocard.back.summoner.sacrifice_tip"),
            click = function()
                if not tok.valid or not tok.canControlAsUser then
                    return
                end
                local utils = rawget(_G, "MCDMUtils")
                local ability = utils ~= nil and utils.GetStandardAbility("Summoner Sacrifice Minions") or nil
                local hud = rawget(_G, "gamehud")
                if ability == nil or hud == nil or hud.actionBarPanel == nil then
                    return
                end
                hud.actionBarPanel:FireEventTree("invokeAbility", tok, ability:MakeTemporaryClone(), {})
            end,
        }
        buttons[#buttons+1] = LinkButton{
            text = T("herocard.back.summoner.edit"),
            tip = T("herocard.back.summoner.edit_tip"),
            click = function()
                if not tok.valid or not tok.canControlAsUser then
                    return
                end
                local minion = rawget(_G, "DrawSteelMinion")
                if minion ~= nil then
                    minion.ShowSquadManager(tok)
                end
            end,
        }
        header[#header+1] = gui.Panel{
            width = "auto",
            height = "auto",
            halign = "right",
            flow = "horizontal",
            interactable = false,
            children = buttons,
        }
    end

    local children = {
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            interactable = false,
            children = header,
        },
    }

    local squads = Try(function() return c:GetSummonedSquadsByType(nil) end, {})
    local list = {}
    for squadName, info in pairs(squads) do
        local live = {}
        for _, charid in ipairs(info.charids or {}) do
            local minion = dmhub.GetTokenById(charid)
            if minion ~= nil and minion.valid and minion.properties ~= nil and not Try(function() return minion.properties:IsDeadOrDying() end, false) then
                live[#live+1] = minion
            end
        end
        if #live > 0 then
            table.sort(live, function(a, b) return a.charid < b.charid end)
            list[#list+1] = { name = squadName, total = #(info.charids or {}), live = live }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    for _, entry in ipairs(list) do
        local leader = entry.live[1]
        pcall(function() leader.properties:RefreshSquadInfo(leader) end)
        local sq = Try(function() return leader.properties:try_get("_tmp_minionSquad") end)
        if sq ~= nil then
            local ok, row = pcall(SquadRow, entry.name, entry.total, entry.live, sq)
            if ok and row ~= nil then
                children[#children+1] = row
            end
        end
    end
    if #list == 0 then
        children[#children+1] = Text{ text = "<i>" .. T("herocard.back.summoner.none") .. "</i>", fontSize = 12, color = COLOR_MUTED }
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
        children = children,
    }
end

--- The class's own pieces of the tac panel that have no card form yet, in the
--- tac panel's styles: boxes a class registers without entry.card. Each hides
--- itself on a hero it doesn't fit.
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
                if not CORE_RESOURCE_DISPLAYS[entry.id] and entry.card == nil then
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

--- Rolls a test with a skill: the skill's own characteristic (or the hero's
--- best when it has none), with the skill applied, in the roll sidebar.
local function RollSkillTest(tok, skill)
    local characteristics = {}
    if skill.attribute ~= nil and creature.attributesInfo[skill.attribute] ~= nil then
        characteristics[skill.attribute] = true
    else
        for id, _ in pairs(creature.attributesInfo) do
            characteristics[id] = true
        end
    end
    tok.properties:RollCustomPowerTableTest(T("herocard.back.skill_test", { skill = skill.name }), characteristics, { skill.id },
        { "Tier 1 Result", "Tier 2 Result", "Tier 3 Result" })
end

--- One skill in a group's line: hover shows what it covers; a click rolls a
--- test with it for whoever controls the hero.
--- @param style? {color: string|nil, bold: boolean|nil} how the name reads (Negotiation's trained skills are bold, the rest muted)
local function SkillPiece(tok, skill, last, style)
    local canRoll = dmhub.isDM or Try(function() return tok.canControl end, false)
    return gui.Panel{
        width = "auto",
        height = "auto",
        rmargin = 4,
        bgimage = "panels/square.png",
        bgcolor = "#00000000",
        styles = {
            { selectors = {"heroCardSkill", "hover"}, bgcolor = COLOR_PLATE },
        },
        classes = {"heroCardSkill"},
        hover = function(element)
            ShowHover(element, function()
                if type(skill.description) ~= "string" or skill.description == "" then
                    return nil
                end
                return skill.description
            end)
        end,
        click = function(element)
            if not canRoll then
                return
            end
            audio.FireSoundEvent("Mouse.Click")
            pcall(RollSkillTest, tok, skill)
        end,
        Text{ text = skill.name .. cond(last, "", ","), width = "auto", fontSize = 12, bold = style ~= nil and style.bold == true, color = style ~= nil and style.color or COLOR_SOFT, textWrap = false },
    }
end

--- Trained skills by group, one line per group; each skill hovers and rolls.
local function SkillsByGroup(c, tok)
    local lines = {}
    for _, cat in ipairs(Try(function() return Skill.categories end, {})) do
        local skills = {}
        pcall(function()
            for _, skill in ipairs(Skill.SkillsInfo) do
                if skill.category == cat.id and c:ProficientInSkill(skill) then
                    skills[#skills+1] = skill
                end
            end
        end)
        if #skills > 0 then
            table.sort(skills, function(a, b) return a.name < b.name end)
            local pieces = {
                Text{ text = string.format("<b><color=%s>%s</color></b>", COLOR_MUTED, string.upper(cat.text)), width = "auto", fontSize = 12, rmargin = 8, textWrap = false },
            }
            for i, skill in ipairs(skills) do
                pieces[#pieces+1] = SkillPiece(tok, skill, i == #skills)
            end
            lines[#lines+1] = gui.Panel{
                width = CONTENT_WIDTH,
                height = "auto",
                flow = "horizontal",
                wrap = true,
                bmargin = 3,
                interactable = false,
                children = pieces,
            }
        end
    end
    if #lines == 0 then
        return EmptyLine(T("herocard.back.skills.none"))
    end
    return Lines(lines)
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

local function LanguagesLine(c)
    local languages = LanguagesText(c)
    if languages == "" then
        return nil
    end
    return LabelledLine(T("herocard.back.label.languages"), languages)
end

--- XP, Wealth, Renown and banked downtime. Victories and hero tokens are on
--- the stamina strip.
local function ProgressLines(c, charid)
    local lines = {}
    local sheet = rawget(_G, "EotwHeroSheet")
    local xp = sheet ~= nil and Try(function() return sheet.XpProgress(c) end) or nil
    if xp ~= nil then
        local xpText = tostring(xp.xp)
        if not xp.maxLevel then
            xpText = string.format("%d / %d", xp.xpIntoLevel, xp.xpPerLevel)
        end
        --hover: the hero sheet's own words for XP.
        lines[#lines+1] = WithHover(LabelledLine(T("herocard.back.label.xp"), xpText), function()
            if xp.maxLevel then
                return nil
            end
            local args = { xp = string.format("%d", xp.xpIntoLevel), per = string.format("%d", xp.xpPerLevel), level = string.format("%d", xp.level + 1) }
            if xp.readyToLevel then
                return T("herosheet.card.xp_ready_tip", args)
            end
            return T("herosheet.card.xp_tip", args)
        end)
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

--- Appends one section of the scroll: its big heading, then what its builders
--- make. The heading is marked so the jump row can find it.
local function AppendSection(result, info, id, builders)
    result[#result+1] = SectionHeading(id)
    info[#info+1] = { heading = false, section = id }
    local sections, sectionInfo = Collect(builders)
    for i, section in ipairs(sections) do
        result[#result+1] = section
        info[#info+1] = sectionInfo[i]
    end
end

--- A hero's back: one scroll in the hero sheet's order.
--- @return Panel[] sections
--- @return HeroCardSectionInfo[] info
local function BuildHeroScroll(tok, charid, state)
    local c = tok.properties
    local result, info = {}, {}
    AppendSection(result, info, "stats", {
        function() return StaminaStrip(c, tok) end,
        function() return ResourceHeadline(c, tok) end,
        function() return EpicResource(tok) end,
        function() return ClassResourceLines(tok) end,
        function() return ClassPanel(tok, c, state) end,
        function() return MinionSquads(tok, c) end,
        function() return Characteristics(c, tok) end,
        function() return MovementLine(c, tok) end,
        function() return Effects(c, tok) end,
        function() return PersistentAbilities(c, tok) end,
    })

    result[#result+1] = SectionHeading("abilities")
    info[#info+1] = { heading = false, section = "abilities" }
    local potency, potencyInfo = Collect{ function() return PotencyRow(c) end }
    for i, row in ipairs(potency) do
        result[#result+1] = row
        info[#info+1] = potencyInfo[i]
    end
    AppendAbilities(result, info, tok, c, state)

    AppendSection(result, info, "features", {
        function() return ResourceGains(c) end,
        function() return GrowthTables(c) end,
        function()
            return Lines{ SectionLabel(T("herocard.back.label.skills")), SkillsByGroup(c, tok) }
        end,
        function() return LanguagesLine(c) end,
        function() return PerksLine(c) end,
        function() return ProgressLines(c, charid) end,
        function() return NotesLine(c) end,
    })

    AppendSection(result, info, "gear", {
        function() return ProjectsList(c) or EmptyLine(T("herocard.back.gear.none")) end,
    })
    return result, info
end

--- Footer ----------------------------------------------------------------------

local FOOTER_HEIGHT = 26

--The Hero sheet where it opens for this hero, as the table card's Character
--Sheet icon does (HeroSheet.CardButton); the character panel otherwise.
local function OpenSheet(charid, element)
    local heroSheet = rawget(_G, "HeroSheet")
    local tok = dmhub.GetCharacterById(charid)
    if heroSheet ~= nil and tok ~= nil and heroSheet.Routes(tok) then
        heroSheet.CardButton(charid)
        return
    end
    local toggle = rawget(_G, "ToggleCharacterPanelDocument")
    if toggle ~= nil then
        toggle(charid, nil, element)
    end
end

--- The footer's button that turns the card back over: always there while the
--- back is up, whatever the mouse is on.
--- @return Panel
local function CreateTurnBackButton()
    return gui.Panel{
        classes = {"heroCardTurnBack"},
        width = "auto",
        height = 22,
        halign = "left",
        valign = "center",
        flow = "horizontal",
        hpad = 8,
        borderBox = true,
        cornerRadius = 6,
        border = 1,
        bgimage = "panels/square.png",
        swallowPress = true,
        styles = {
            {
                selectors = {"heroCardTurnBack"},
                bgcolor = "#ffffff14",
                borderColor = "#ffd66baa",
            },
            {
                selectors = {"heroCardTurnBack", "hover"},
                bgcolor = "#ffffff30",
                borderColor = "#ffffff",
            },
            {
                selectors = {"heroCardTurnBackIcon"},
                bgcolor = COLOR_GOLD,
            },
            {
                selectors = {"heroCardTurnBackIcon", "parent:hover"},
                bgcolor = "#ffffff",
            },
        },
        gui.Panel{
            classes = {"heroCardTurnBackIcon"},
            width = 13,
            height = 13,
            valign = "center",
            rmargin = 6,
            bgimage = "phosphor/arrow-clockwise.png",
            interactable = false,
        },
        Text{
            text = "Turn the card over",
            width = "auto",
            valign = "center",
            fontSize = 12,
            bold = true,
            color = COLOR_TEXT,
            textWrap = false,
        },
        click = function(element)
            --turns the card even when the click closed the add-a-condition
            --menu; that close must not swallow the next click.
            ConsumeMenuClick()
            audio.FireSoundEvent("Mouse.Click")
            element:FireEventOnParents("turnCard")
        end,
    }
end

--- The footer: the button that turns the card back, and a link to the full sheet.
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
        CreateTurnBackButton(),
        gui.Label{
            text = "Full Character Sheet",
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
            fontSize = 12,
            bold = true,
            swallowPress = true,
            --the colour lives in the styles: one set on the label itself
            --would beat the hover rule.
            styles = {
                { selectors = {"label"}, color = COLOR_GOLD },
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

local FLIP_SECONDS = 0.21
--how much bigger the card is while its back is showing. It grows upward and
--then rises a further TURNED_RISE of its own height, clear of the screen's foot.
local TURNED_SCALE = 3
local TURNED_RISE = 0.25

--cards showing their back, oldest first. Only the last one opened draws on
--top of everything, so a newer card is never hidden under an older one, and
--only it takes Escape, which turns it back.
--- @type Panel[]
local g_turnedOrder = {}

--- Lets only the newest card in the turned list draw above the screen's
--- other panels and take Escape, dropping any card that no longer exists.
local function RaiseNewestTurned()
    for i = #g_turnedOrder, 1, -1 do
        if not g_turnedOrder[i].valid then
            table.remove(g_turnedOrder, i)
        end
    end
    local top = g_turnedOrder[#g_turnedOrder]
    for _, other in ipairs(g_turnedOrder) do
        other.renderOnTop = other == top
        other.captureEscape = other == top
    end
end

--- Records that a card was turned to its back (turned = true) or back to
--- its face (false), then lets only the newest turned card draw on top.
--- @param card Panel
--- @param turned boolean
local function SetTurnedOrder(card, turned)
    table.remove_value(g_turnedOrder, card)
    if turned then
        g_turnedOrder[#g_turnedOrder+1] = card
    else
        card.renderOnTop = false
        card.captureEscape = false
    end
    RaiseNewestTurned()
end

--Where a turning card goes, in the card's own units: its scale and its x/y
--offset at the start of the turn and at the end. Scale is around the card's
--centre. A host that places the card itself (the table) gives one from
--Decorate's options.onTurn; without one the card grows TURNED_SCALE times
--where it lies, upward.
--- @class HeroCardFlipMotion
--- @field fromScale number
--- @field toScale number
--- @field fromX nil|number
--- @field fromY nil|number
--- @field toX nil|number
--- @field toY nil|number
--- @field turned nil|boolean true when the card is turning to its back

--Turns the card over: squeezes it edge-on, swaps the faces at the midpoint
--and opens it out again, lifting slightly as it turns. Driven by hand rather
--than by a style transition so it runs on the card itself, whose styles
--belong to the host. The card grows from motion.fromScale to motion.toScale
--as it turns, rising so the growth goes upward, unless the motion gives
--offsets, which it then moves between instead.
--- @param motion HeroCardFlipMotion
local function AnimateFlip(card, cardHeight, motion, onMidpoint, onDone)
    if card.data.heroCardFlipping then
        return
    end
    card.data.heroCardFlipping = true
    local fromScale, toScale = motion.fromScale, motion.toScale
    local hosted = motion.fromY ~= nil
    --a card grows while it shows its back, so any scale but 1 means opening.
    --A hosted card's scales are relative to the host, so it says which way it turns.
    local opening = motion.turned
    if opening == nil then
        opening = toScale ~= 1
    end
    --only cards on the screen itself take turns drawing on top; the table
    --orders its own cards.
    if opening and not hosted then
        SetTurnedOrder(card, true)
    end
    --puts the card t of the way through the turn, at size grown.
    local Place
    if hosted then
        Place = function(t, grown)
            card.selfStyle.x = motion.fromX + (motion.toX - motion.fromX) * t
            card.selfStyle.y = motion.fromY + (motion.toY - motion.fromY) * t
        end
    else
        if card.data.heroCardBaseY == nil then
            card.data.heroCardBaseY = card.selfStyle.y or 0
        end
        local baseY = card.data.heroCardBaseY
        --the engine pulls an enlarged card back inside the screen.
        card.constrainToScreen = true
        Place = function(t, grown)
            local risen = (grown - 1) / (TURNED_SCALE - 1)
            card.selfStyle.y = baseY - (grown - 1) * cardHeight / 2 - risen * TURNED_RISE * cardHeight
        end
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
            Place(1, toScale)
            if not hosted then
                card.constrainToScreen = opening
                --stays on top while it shrinks, then hands the top to the card
                --opened before it.
                if not opening then
                    SetTurnedOrder(card, false)
                end
            end
            card.data.heroCardFlipping = false
            onDone()
            return
        end
        local eased = 0.5 - 0.5 * math.cos(p * math.pi)
        local sx = math.max(0.02, math.abs(math.cos(eased * math.pi)))
        local grown = fromScale + (toScale - fromScale) * eased
        local size = grown * (1 + 0.06 * math.sin(p * math.pi))
        card.selfStyle.scale = {x = sx * size, y = size}
        Place(eased, grown)
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
--- @param draggable nil|boolean the host drags the card by its back: a press
--- on the back passes through to it
local function CreateBackFace(charid, cardWidth, cardHeight, draggable)
    local scale = cardWidth / DESIGN_WIDTH
    local designHeight = math.floor(cardHeight / scale)
    local VPAD = 14

    --bucket title -> true while folded, false while opened. Kept across
    --rebuilds (stamina changing under an open card); a bucket nobody has
    --touched takes its default (hero ability buckets but Signature start folded).
    local folded = {}
    local foldDefaults = {}
    local sections, info = {}, {}

    --a hero's cached ability list and class panel.
    local state = { abilities = nil, classPanel = nil }

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

    --a hero's header and jump row: they stay put while the back scrolls.
    local heroTop = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        bmargin = TOP_GAP,
        interactable = false,
    }

    --Scrolls so a section's heading sits at the top. There is no engine
    --scroll-into-view: the offset is summed from the rendered heights (and
    --bottom margins) of the shown rows above it, as ActionLogPanel does.
    local function JumpTo(id)
        local target = nil
        for i, entry in ipairs(info) do
            if entry.section == id then
                target = i
                break
            end
        end
        if target == nil then
            return
        end
        --panel reads raise rather than return nil, so each is guarded.
        local offset, total = 0, 0
        for i, section in ipairs(sections) do
            local shown = Try(function() return section.valid and not section:HasClass("collapsed") end, false)
            local h = 0
            if shown then
                h = (tonumber(Try(function() return section.renderedHeight end, 0)) or 0)
                    + (tonumber(Try(function() return section.selfStyle.bmargin end, 0)) or 0)
            end
            if i < target then
                offset = offset + h
            end
            total = total + h
        end
        local range = total - Try(function() return scroller.renderedHeight end, 0)
        if range <= 0 then
            return
        end
        scroller.vscrollPosition = 1 - math.max(0, math.min(range, offset)) / range
    end

    local content

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
                local okJump, jumpRow = pcall(JumpRow, JumpTo)
                if okJump then
                    top[#top+1] = jumpRow
                else
                    print("HeroCardBack: jump row failed:", jumpRow)
                end
                heroTop.children = top
                heroTop:SetClass("collapsed", false)
                scrollHeight = scrollHeight - HERO_HEADER_HEIGHT - TOP_GAP * 2 - JUMP_ROW_HEIGHT - 1
                sections, info = BuildHeroScroll(tok, charid, state)
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
        --not swallowed when the host drags the card: the press goes on to it.
        swallowPress = draggable ~= true,
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
        --Not under an open add-a-condition menu or heroic resource box,
        --which the rebuild would close: it waits until they are gone.
        monitorGame = "/characters",
        refreshGame = function(element)
            if not element:HasClass("turned") then
                return
            end
            if BackEditOpen() then
                if not element.data.refreshWaiting then
                    element.data.refreshWaiting = true
                    dmhub.ScheduleWhen(function()
                        return mod.unloaded or not BackEditOpen()
                    end, function()
                        if mod.unloaded or not element.valid then
                            return
                        end
                        element.data.refreshWaiting = false
                        if element:HasClass("turned") then
                            content:FireEvent("refreshBack")
                        end
                    end)
                end
                return
            end
            content:FireEvent("refreshBack")
        end,
        showBack = function(element, show)
            element:SetClass("turned", show)
            if show then
                state.abilities = nil
                scroller.vscrollPosition = 1
                content:FireEvent("refreshBack")
            end
        end,
        click = function(element)
            --a click that closed the add-a-condition menu only closes it;
            --the next click turns the card.
            if ConsumeMenuClick() then
                return
            end
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

--- The History chip: just left of the flip button, in its look, shown only while the card
--- is hovered. Opens History showing only this hero.
--- @param charid string
--- @param offsetX number Its x offset from the card's centre.
--- @return Panel
local function CreateHistoryButton(charid, offsetX)
    return gui.Panel{
        classes = {"heroCardHistory"},
        floating = true,
        halign = "center",
        valign = "top",
        x = offsetX,
        y = 4,
        width = 26,
        height = 26,
        cornerRadius = 13,
        border = 1,
        borderColor = "#ffffff66",
        bgimage = "panels/square.png",
        bgcolor = "#000000c0",
        swallowPress = true,
        styles = {
            {
                selectors = {"heroCardHistory"},
                hidden = 1,
            },
            {
                selectors = {"heroCardHistory", "parent:hover"},
                hidden = 0,
            },
            --as on the flip button: with the pointer on the chip the card is no longer
            --hovered, so the chip's own hover keeps it shown.
            {
                selectors = {"heroCardHistory", "hover"},
                hidden = 0,
                borderColor = COLOR_GOLD,
                scale = 1.15,
            },
            {
                selectors = {"heroCardHistoryIcon", "parent:hover"},
                bgcolor = COLOR_GOLD,
            },
        },
        gui.Panel{
            classes = {"heroCardHistoryIcon"},
            width = 16,
            height = 16,
            halign = "center",
            valign = "center",
            bgimage = "phosphor/clock-counter-clockwise-bold.png",
            bgcolor = "#ffffffee",
            interactable = false,
        },
        hover = gui.Tooltip("History"),
        --a handled click stops here instead of opening the hero's sheet.
        click = function(element)
            local history = rawget(_G, "History")
            local token = dmhub.GetTokenById(charid)
            if history == nil or token == nil then
                return
            end
            audio.FireSoundEvent("Mouse.Click")
            history.OpenFor(token)
        end,
    }
end

--every decorated card while it lives, weakly held: lets a dev session turn a
--card over from Lua (HeroCardBack.TurnAll()).
local g_cards = setmetatable({}, {__mode = "k"})

--Decorate's options.
--  noButton   leave off the flip button, for a host that turns the card on a
--             click (the table's cards)
--  dragBack   the host drags the turned card: a press on the back reaches it
--  onTurn     onTurn(turned), called as a turn starts: the host may move the
--             card's frame and return where the card goes (HeroCardFlipMotion),
--             or nil for the usual growth in place
--- @class HeroCardBackOptions
--- @field noButton nil|boolean
--- @field dragBack nil|boolean
--- @field onTurn nil|fun(turned: boolean): HeroCardFlipMotion|nil

--- Gives a hero card (EotwHeroCard.CreateHeroCard) its back: the back face
--- and (unless options.noButton) the flip button go on as the card's top layers, and the card learns
--- the "turnCard" event they both fire. Mid-turn the card tells its hosts
--- with "heroCardTurned" (turned) on its parents: the table hides the card's
--- titlebar, which the grown back would otherwise sit under.
--- @param cardArgs table the card's gui.Panel args, before it is built
--- @param charid string
--- @param cardWidth number
--- @param cardHeight number
--- @param options nil|HeroCardBackOptions
local function Decorate(cardArgs, charid, cardWidth, cardHeight, options)
    options = options or {}
    local backFace = CreateBackFace(charid, cardWidth, cardHeight, options.dragBack)
    local create = cardArgs.create
    cardArgs.create = function(element)
        g_cards[element] = true
        if create ~= nil then
            create(element)
        end
    end
    --a turned card can be destroyed (its row rebuilt, the card removed);
    --the card turned before it then takes the top.
    local destroy = cardArgs.destroy
    cardArgs.destroy = function(element)
        table.remove_value(g_turnedOrder, element)
        RaiseNewestTurned()
        if destroy ~= nil then
            destroy(element)
        end
    end
    cardArgs[#cardArgs+1] = backFace
    --Escape turns the card back (captureEscape is RaiseNewestTurned's). An
    --ability being aimed takes the key first, as do menus and dialogs.
    cardArgs.escapePriority = EscapePriority.CANCEL_TOKEN_MENU
    cardArgs.escape = function(element)
        if backFace:HasClass("turned") then
            element:FireEvent("turnCard")
        end
    end
    --the front's hover buttons: off the card while its back, which has its
    --own turn button, is up.
    ---@type Panel[]
    local frontButtons = {}
    ---@type Panel|nil
    local flipButton = nil
    if not options.noButton then
        flipButton = CreateFlipButton(charid)
        cardArgs[#cardArgs+1] = flipButton
        frontButtons[#frontButtons+1] = flipButton
        --History sits just left of the centred flip button, unless this user is on the old Action
        --Log. The top-left corner is the trigger and downtime badges', so it stays out of there.
        local history = rawget(_G, "History")
        if history ~= nil and not history.UsingOldLog() then
            local historyButton = CreateHistoryButton(charid, -32)
            cardArgs[#cardArgs+1] = historyButton
            frontButtons[#frontButtons+1] = historyButton
        end
    end
    cardArgs.turnCard = function(element)
        --one turn at a time (the host moves the card as a turn starts).
        if element.data.heroCardFlipping then
            return
        end
        local turned = not backFace:HasClass("turned")
        if flipButton ~= nil then
            flipButton:SetClass("turning", true)
        end
        ---@type HeroCardFlipMotion|nil
        local motion = nil
        if options.onTurn ~= nil then
            motion = options.onTurn(turned)
        end
        if motion == nil then
            motion = {fromScale = cond(turned, 1, TURNED_SCALE), toScale = cond(turned, TURNED_SCALE, 1)}
        end
        motion.turned = turned
        AnimateFlip(element, cardHeight, motion, function()
            backFace:FireEvent("showBack", turned)
            for _, button in ipairs(frontButtons) do
                button:SetClass("collapsed", turned)
            end
            element:FireEventOnParents("heroCardTurned", turned)
        end, function()
            if flipButton ~= nil and flipButton.valid then
                flipButton:SetClass("turning", false)
            end
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
    ConsumeMenuClick = ConsumeMenuClick,
}

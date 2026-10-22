local mod = dmhub.GetModLoading()

--The hero card: full-bleed portrait with the name, stamina bar, heroic
--resource, surges, conditions and (opts.showStats) characteristics and
--skills. Shared by the Encounter of the Week montage stage and in-game
--roster (EncounterOfTheWeek/EncounterOfTheWeekHud.lua) and the Blackbottom
--town's active-hero strip on the titlescreen -- which is why it lives in
--this core mod: the game-side EotW mod never loads at the titlescreen.
--Everything reads the character through dmhub.GetCharacterById, which
--resolves lobby-game characters as well as map tokens.
--Design/plan doc: EncounterOfTheWeek/EncounterOfTheWeek.md.
--- Hero collection ----------------------------------------------------------

--A hero whose player never typed a name still has to label its card with
--something. (EncounterMontage.HeroDisplayName says the same thing; kept
--local here because this file only reaches that module defensively.)
local function HeroDisplayName(tok)
    local name = nil
    pcall(function() name = tok.name end)
    if name == nil or name == "" then
        return "Unnamed Hero"
    end
    return name
end

--Every hero on the map, the local player's own first. "Own" is strict
--ownership (ownerId == loginUserid), not canControl: the EotW host can
--control everything but only their claimed heroes are theirs.
--
--Enumerated exactly the way combat entry does it (GatherCombatSides in
--EncounterOfTheWeek.lua): every token on the map whose properties IsHero.
--NOT Party.GetPlayerCharacters, which silently drops any token with a blank
--name -- an unnamed hero fought in the encounter but was missing from this
--strip and from the montage (report QKG5YTWG).
--The player who controls a hero, for the line under its name on the card.
local function HeroPlayerName(tok)
    local owner = nil
    pcall(function() owner = tok.ownerId end)
    if owner == nil or owner == "" then
        return "Unclaimed"
    end
    if owner == "PARTY" then
        return "The party"
    end
    local name = owner
    pcall(function() name = dmhub.GetDisplayName(owner) or owner end)
    return name
end

--
--opts.includeDead also lists the heroes who died on this map. Hero Death
--despawns a dead hero into a corpse object, which drops its token out of
--dmhub.allTokens; dmhub.despawnedTokens still has it. The card itself
--shows the skull (IsCardHeroDead), so this only decides who is listed.
local function CollectHeroes(opts)
    opts = opts or {}
    local result = {}
    local seen = {}
    local function Add(tok)
        if tok == nil or not tok.valid or seen[tok.charid] then
            return
        end
        local isHero = false
        pcall(function() isHero = tok.properties ~= nil and tok.properties:IsHero() end)
        if isHero then
            seen[tok.charid] = true
            local mine = false
            pcall(function() mine = tok.ownerId ~= nil and tok.ownerId == dmhub.loginUserid end)
            result[#result+1] = {
                charid = tok.charid,
                mine = mine,
                name = HeroDisplayName(tok),
            }
        end
    end
    for _, tok in ipairs(dmhub.allTokens) do
        Add(tok)
    end
    if opts.includeDead then
        for _, tok in ipairs(dmhub.despawnedTokens or {}) do
            Add(tok)
        end
    end
    table.sort(result, function(a, b)
        if a.mine ~= b.mine then
            return a.mine
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.charid < b.charid
    end)
    return result
end

--A hero is dead once Hero Death has despawned it into a corpse, or (for
--the second before that rule runs) once its stamina is past the kill
--threshold.
local function IsCardHeroDead(tok)
    if tok == nil or not tok.valid then
        return false
    end
    local dead = false
    pcall(function() dead = tok.despawned or (tok.properties ~= nil and tok.properties:IsDead()) end)
    return dead == true
end

--the montage allies ride in the signature too, so a monster joining a
--hero rebuilds the column with its card.
local function RosterSignature(heroes)
    local parts = {}
    for _, entry in ipairs(heroes) do
        local allies = {}
        local montage = rawget(_G, "EncounterMontage")
        if montage ~= nil and montage.GetAllies ~= nil then
            pcall(function() allies = montage.GetAllies(entry.charid) or {} end)
        end
        parts[#parts+1] = string.format("%s:%s:%s", entry.charid, tostring(entry.mine), table.concat(allies, ","))
    end
    return table.concat(parts, "|")
end

--The condition + status-effect entries shown as icons on a card: the same
--table lookups the character panel's condition chips use.
local function CollectConditions(c)
    local entries = {}
    local conditionsTable = dmhub.GetTable("charConditions") or {}
    local inflicted = nil
    pcall(function() inflicted = c:try_get("inflictedConditions") end)
    for condid, _ in pairs(inflicted or {}) do
        local info = conditionsTable[condid]
        if info ~= nil then
            entries[#entries+1] = {
                icon = info.iconid,
                display = info.display or {},
                name = info.name or "Condition",
                condid = condid,
            }
        end
    end

    local ongoingTable = dmhub.GetTable("characterOngoingEffects") or {}
    local effects = nil
    pcall(function() effects = c:ActiveOngoingEffects() end)
    for _, entry in ipairs(effects or {}) do
        local info = ongoingTable[entry.ongoingEffectid]
        if info ~= nil and info.statusEffect then
            local icon = nil
            local display = nil
            pcall(function()
                icon = info:GetDisplayIcon()
                display = info:GetDisplayDisplay()
            end)
            if icon ~= nil then
                entries[#entries+1] = {
                    icon = icon,
                    display = display or {},
                    name = info.name or "Effect",
                    effectid = entry.ongoingEffectid,
                }
            end
        end
    end
    return entries
end

--- Hero cards ---------------------------------------------------------------

--The hero-card style rules, shared by the right-rail roster and the montage
--stage (EncounterMontageStage.lua): both wrap them in their own MergeTokens /
--MergeStyles call so the theme tokens resolve for that cascade root.
--the montage card's extras (opts.showStats): the characteristics strip down
--the right edge and the skills line under the name. Declared up here rather
--than beside the other card constants because the style rules need them.
local SKILLS_HEIGHT = 46
--the small "played by" line under every card's hero name.
local PLAYER_HEIGHT = 12
local STAT_ROW_HEIGHT = 15
local STAT_CHIP_WIDTH = 36
--the stats card (opts.showStats) is drawn a fifth larger than the roster's
--(user direction 2026-09-21); uiscale scales its layout size too, so the
--stage rows budget for the scaled card (EncounterMontageStage's
--HERO_ROW_HEIGHT).
local STATS_CARD_UISCALE = 1.2

local g_heroCardRules = {
    {
        selectors = {"eotwHeroCard"},
        bgcolor = "#151515",
        border = 1,
        borderColor = "#000000cc",
        transitionTime = 0.15,
    },
    {
        selectors = {"eotwHeroCard", "hover"},
        brightness = 1.15,
        borderColor = "#ffffff88",
    },
    {
        selectors = {"eotwHeroCard", "mine"},
        border = 2,
        borderColor = "#6fa8ffcc",
    },
    {
        selectors = {"eotwHeroCard", "mine", "hover"},
        borderColor = "#9cc4ffff",
    },
    {
        selectors = {"eotwHeroCard", "stats"},
        uiscale = STATS_CARD_UISCALE,
    },
    --the hero whose test is in flight (the stage sets "active"): a gold
    --border and a small transform scale -- scale rather than uiscale so the
    --neighbours do not shuffle when the turn passes.
    {
        selectors = {"eotwHeroCard", "active"},
        border = 3,
        borderColor = "#ffd66bff",
        scale = 1.06,
    },
    --a dead hero: the portrait drains to grey and a dark wash with a skull
    --(eotwDeadMark) covers the card.
    {
        selectors = {"eotwHeroCard", "dead"},
        saturation = 0,
        brightness = 0.7,
        borderColor = "#000000ff",
    },
    {
        selectors = {"eotwDeadMark"},
        hidden = 1,
    },
    {
        selectors = {"eotwDeadMark", "parent:dead"},
        hidden = 0,
        bgimage = "panels/square.png",
        bgcolor = "#000000a0",
    },
    {
        selectors = {"eotwDeadSkull"},
        bgimage = "phosphor/skull-fill.png",
        bgcolor = "#e6e6e6ee",
    },
    {
        selectors = {"eotwCardOverlay"},
        bgcolor = "#000000c0",
    },
    {
        selectors = {"eotwCardOverlay", "mine"},
        bgcolor = "#0d1e31d0",
    },
    {
        selectors = {"eotwHeroName"},
        fontSize = 12,
        bold = true,
        color = "#ffffff",
        width = "100%",
        height = 15,
        textAlignment = "left",
        textWrap = false,
        --a long name shrinks to fit the card rather than running off its
        --edge; past the floor it ends in an ellipsis.
        minFontSize = 8,
        textOverflow = "ellipsis",
        bmargin = 3,
    },
    --montage only (opts.showStats): one chip per characteristic ("M +2")
    --stacked down the card's right edge, and the comma-separated skills
    --line under the name. Both read over artwork, hence the dark chip and
    --the light-but-not-white skills text.
    --one fixed chip width for all five rows (auto width let "M +2" and
    --"I +1" size differently, which left the column ragged), with the
    --letter in a left column and the score in a right one so both line up
    --down the strip.
    {
        selectors = {"eotwStatChip"},
        width = STAT_CHIP_WIDTH,
        height = STAT_ROW_HEIGHT,
        halign = "right",
        flow = "horizontal",
        bgimage = "panels/square.png",
        bgcolor = "#000000b0",
        cornerRadius = 3,
        hpad = 3,
        borderBox = true,
        tmargin = 1,
    },
    --the characteristic the test in flight is rolled with (the stage's
    --highlightCharacteristic event): gold chip, dark text.
    {
        selectors = {"eotwStatChip", "active"},
        bgcolor = "#ffd66bf0",
        border = 1,
        borderColor = "#fff2c0ff",
    },
    {
        selectors = {"eotwStatKey", "parent:active"},
        color = "#1a1200",
    },
    {
        selectors = {"eotwStatValue", "parent:active"},
        color = "#1a1200",
    },
    {
        selectors = {"eotwStatKey"},
        fontSize = 11,
        bold = true,
        color = "#ffffff",
        width = 12,
        height = "100%",
        halign = "left",
        valign = "center",
        textAlignment = "left",
        textWrap = false,
    },
    {
        selectors = {"eotwStatValue"},
        fontSize = 11,
        bold = true,
        color = "#ffffff",
        width = 18,
        height = "100%",
        halign = "right",
        valign = "center",
        textAlignment = "right",
        textWrap = false,
    },
    --who controls the hero, in small text hugging the name above it.
    {
        selectors = {"eotwHeroPlayer"},
        fontSize = 9,
        color = "#c6d0da",
        width = "100%",
        height = PLAYER_HEIGHT,
        textAlignment = "left",
        textWrap = false,
        tmargin = -3,
        bmargin = 3,
    },
    {
        selectors = {"eotwSkillsLine"},
        fontSize = 9,
        color = "#c6d0da",
        width = "100%",
        height = SKILLS_HEIGHT,
        textAlignment = "topleft",
        textWrap = true,
        --a hero with many skills shrinks the text to stay inside the fixed
        --height rather than spilling over the stamina bar; past the floor
        --it ends in an ellipsis.
        minFontSize = 6,
        textOverflow = "ellipsis",
        bmargin = 2,
    },
    {
        selectors = {"eotwResIcon"},
        width = 17,
        height = 17,
        halign = "left",
        valign = "center",
        bgcolor = "white",
    },
    {
        selectors = {"eotwResValue"},
        fontSize = 14,
        bold = true,
        color = "#ffffff",
        width = "auto",
        height = "auto",
        --both the icon and the value align left so the flow packs
        --them together instead of spreading them across the row.
        halign = "left",
        valign = "center",
        lmargin = 3,
    },
    --the health bar's state tints, copied from the character
    --panel's HealthFill styles: success/warning/danger are the
    --documented theme tiers for stamina. The gradient overrides
    --the global fillBarFill's flat horizontal shade with a glossy
    --vertical one; grayscale stops so the bgcolor tint carries
    --the state color.
    {
        selectors = {"fillBarFill", "healthFill"},
        bgcolor = "@success",
        gradient = gui.Gradient{
            point_a = {x = 0, y = 0},
            point_b = {x = 0, y = 1},
            stops = {
                { position = 0, color = "#5A5A5A" },
                { position = 0.45, color = "#8E8E8E" },
                { position = 0.55, color = "#B4B4B4" },
                { position = 1, color = "#E4E4E4" },
            },
        },
    },
    {
        selectors = {"healthFill", "winded"},
        transitionTime = 0.4,
        bgcolor = "@warning",
    },
    {
        selectors = {"healthFill", "dying"},
        transitionTime = 0.4,
        bgcolor = "@danger",
    },
    {
        selectors = {"fillBarFill", "eotwTempFill"},
        bgcolor = "@accent",
        gradient = gui.Gradient{
            point_a = {x = 0, y = 0},
            point_b = {x = 0, y = 1},
            stops = {
                { position = 0, color = "#6A6A6A" },
                { position = 1, color = "#E4E4E4" },
            },
        },
    },
    {
        selectors = {"eotwBarLabel"},
        fontSize = 10,
        bold = true,
        color = "#ffffff",
        width = "100%",
        height = "100%",
        textAlignment = "center",
        textWrap = false,
    },
    --the recoveries circle to the left of the stamina bar: a dark disc
    --with a light ring and the count in white.
    {
        selectors = {"eotwRecoveriesCircle"},
        width = 16,
        height = 16,
        valign = "center",
        halign = "left",
        rmargin = 3,
        cornerRadius = 8,
        bgimage = "panels/square.png",
        bgcolor = "#000000aa",
        border = 1,
        borderColor = "#ffffffaa",
    },
    {
        selectors = {"eotwRecoveriesCircle", "empty"},
        borderColor = "#ff5555aa",
    },
    {
        selectors = {"eotwRecoveriesLabel"},
        fontSize = 10,
        bold = true,
        color = "#ffffff",
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        textWrap = false,
    },
    {
        selectors = {"eotwSurgeIcon"},
        width = 12,
        height = 12,
        valign = "center",
        lmargin = 1,
        bgimage = "game-icons/surge.png",
        bgcolor = "white",
    },
    --the hurt flash: a red wash over the whole card for a moment when the
    --creature loses stamina. It has to be its own floating overlay rather
    --than a tint on the card, because refreshCard writes
    --selfStyle.bgcolor = "white" to keep the portrait untinted and
    --selfStyle beats every class rule. Its own class also keeps it out of
    --the fight over {eotwHeroCard} borderColor that the stage's
    --selected/flashing rules would win.
    --
    --PulseClass applies the {hurt} rule instantly and then ramps it back
    --out over THAT rule's transitionTime, so the fade timing lives there,
    --not on the resting rule. The resting rule keeps the border WIDTH so
    --only the color animates -- a border whose width changed would shift
    --the panel's content box mid-flash.
    {
        selectors = {"eotwHurtFlash"},
        bgimage = "panels/square.png",
        bgcolor = "#ff3b3b00",
        border = 3,
        borderColor = "#ff808000",
    },
    {
        selectors = {"eotwHurtFlash", "hurt"},
        bgcolor = "#ff3b3baa",
        borderColor = "#ff8080ff",
        transitionTime = 0.45,
        easing = "easeOutCubic",
    },
    --the heal flash: the same overlay in green, for the other direction.
    --Everything the hurt flash's note above says applies here too -- it is
    --a second floating wash for the same reasons, and the fade lives on
    --the {healed} rule's transitionTime.
    --
    --A hero can be healed and hurt in the same instant (a montage clause
    --that costs Stamina and a heal landing together), so these are two
    --overlays rather than one with two colors: each pulses on its own and
    --the later one simply sits on top.
    {
        selectors = {"eotwHealFlash"},
        bgimage = "panels/square.png",
        bgcolor = "#3bff7b00",
        border = 3,
        borderColor = "#80ffa000",
    },
    {
        selectors = {"eotwHealFlash", "healed"},
        bgcolor = "#3bff7b99",
        borderColor = "#80ffa0ff",
        transitionTime = 0.45,
        easing = "easeOutCubic",
    },
}


local CARD_WIDTH = 132
--the player line grows the card and its overlay alike, so the artwork
--above the overlay keeps its size.
local CARD_HEIGHT = 176 + PLAYER_HEIGHT
local OVERLAY_HEIGHT = 60 + PLAYER_HEIGHT
--the heroic resource row's share of the overlay (CreateResourceRow).
local RESOURCE_ROW_HEIGHT = 19
--condition chips in the card's top-right corner: the outer dark/red-bordered
--chip and the condition icon inside it.
local CONDITION_CHIP_SIZE = 26
local CONDITION_ICON_SIZE = 18

--The wash a card wears for a moment when its creature's stamina moves: red
--({eotwHurtFlash}, pulsed "hurt") for a loss, green ({eotwHealFlash},
--pulsed "healed") for a heal. The card pulses them from its own
--staminaLost / staminaGained handlers, which the card's stamina bar fires
--up the hierarchy.
local function CreateCardFlash(class, cornerRadius)
    return gui.Panel{
        classes = {class},
        floating = true,
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        cornerRadius = cornerRadius,
        interactable = false,
    }
end

--The roster and the montage stage each build their own card for the same
--hero, so one point of damage (or one heal) gets noticed twice. Keyed by
--charid, these remember the stamina total the sound last fired for and
--when: whichever card sees the change first plays it and the other stays
--silent. (Attack.Hit already de-duplicates itself over 0.2s, but the two
--surfaces refresh on different cadences -- 0.5s on the stage, 1s on the
--roster -- so they can easily notice the same hit further apart than that.)
--
--The window is what makes it a de-duplicator rather than a mute: landing
--on the same total again later -- healed back up and hit for the same
--amount -- is a new hit and must sound like one.
local CARD_SOUND_DEDUP = 2
local g_hurtSound = {}
local g_healSound = {}

--2D, with no tokenid: the card is what the player is looking at, and
--during a montage the map is not even on screen to position it in.
local function FireCardSound(seen, charid, total, eventName)
    local now = dmhub.Time()
    local last = seen[charid]
    if last ~= nil and last.total == total and now - last.t < CARD_SOUND_DEDUP then
        return
    end
    seen[charid] = { total = total, t = now }
    audio.FireSoundEvent(eventName)
end

--How the bar slides to a new stamina value instead of snapping to it, so
--damage reads as a drain. The ease is exponential (tau), with a floor on
--the speed -- a full bar in MAX_TIME seconds -- so the exponential tail
--still lands promptly instead of creeping.
local STAMINA_SLIDE_TAU = 0.14
local STAMINA_SLIDE_MAX_TIME = 0.7
local STAMINA_SLIDE_THINK = 0.02

--The stamina bar: the character panel's health bar in miniature -- a
--theme-bordered track whose border and fill both track the
--healthy/winded/dying state (success/warning/danger, the documented
--stamina tiers), with a glossy vertical gradient on the fill, the
--cur/max numbers centered in white, and a temp-stamina segment in the
--accent color riding the end of the fill when the hero has any.
--
--A drop in stamina drains the fill down over ~0.3-0.7s (the numbers count
--with it), fires the generic hit sound, and fires "staminaLost" up the
--hierarchy so the card it sits on can flash red. A rise in stamina does
--the mirror image: the generic heal sound and "staminaGained", so the
--card flashes green.
--
--opts (optional): height (default 14) and fontSize for the numbers, for a
--bar drawn larger than the card's (the hero sheet's).
local function CreateStaminaBar(charid, opts)
    opts = opts or {}
    local fill = gui.Panel{
        classes = {"fillBarFill", "healthFill"},
        width = "0%",
        height = "100%-2",
        valign = "center",
        halign = "left",
        lmargin = 1,
        bgimage = true,
        interactable = false,
    }
    local tempFill = gui.Panel{
        classes = {"fillBarFill", "eotwTempFill"},
        width = "0%",
        height = "100%-2",
        valign = "center",
        halign = "left",
        bgimage = true,
        interactable = false,
    }
    local numbers = gui.Label{
        classes = {"eotwBarLabel"},
        floating = true,
        halign = "center",
        valign = "center",
        fontSize = opts.fontSize,
        text = "",
        interactable = false,
    }

    --what the fill is drawn at right now, easing toward the true fraction
    --(m_targetPct). nil until the first refresh, which snaps: a card built
    --mid-encounter must not animate up from empty.
    local m_shownPct = nil
    local m_targetPct = 0
    --the clock for the slide, and the marker that one is running.
    local m_slideTime = nil
    --the values the numbers read.
    local m_cur, m_max, m_temp = 0, 0, 0
    --stamina + temp stamina as of the last refresh, so a drop can be
    --spotted. nil until the first refresh, so a card built on an already
    --hurt hero does not flash on arrival.
    local m_seenTotal = nil
    --stamina ALONE as of the last refresh, for spotting a heal. Temp
    --stamina is deliberately left out of this one: a grant of temp is not
    --healing (it has its own Notify.TempStamina_Gain elsewhere), and
    --counting it would flash the card green for it. nil on the same terms
    --as m_seenTotal.
    local m_seenCur = nil

    --paint the two fills and the numbers from m_shownPct.
    local function Paint()
        local pct = m_shownPct or 0
        fill.selfStyle.width = string.format("%f%%", pct * 98)
        local tempPct = 0
        if m_max > 0 and m_temp > 0 then
            tempPct = math.min(1 - pct, m_temp / m_max)
        end
        tempFill.selfStyle.width = string.format("%f%%", tempPct * 98)
        --mid-slide the number counts with the bar; once it lands the true
        --value shows. Only while stamina is positive: a dying hero's is
        --negative while the bar is pinned empty, and counting down to that
        --through the fraction would not reach it.
        local shown = m_cur
        if m_shownPct ~= m_targetPct and m_cur > 0 then
            shown = math.ceil(pct * m_max)
        end
        local text = string.format("%d/%d", shown, m_max)
        if m_temp > 0 then
            text = string.format("%s +%d", text, m_temp)
        end
        numbers.text = text
    end

    return gui.Panel{
        classes = {"bordered"},
        width = "100%",
        height = opts.height or 14,
        flow = "horizontal",
        halign = "center",
        cornerRadius = 2,
        bgimage = true,
        bgcolor = "#00000066",
        interactable = false,
        fill,
        tempFill,
        numbers,

        --any character change (damage, healing, temp stamina) lands here
        --straight away, so the flash and the hit sound follow the hit
        --rather than the card's own refresh cadence (0.5s on the montage
        --stage, 1s on the roster), which stays as the fallback.
        monitorGame = "/characters",
        refreshGame = function(element)
            element:FireEvent("refreshCard")
        end,

        --point the bar at another character (the hero sheet's switcher). The
        --next refresh snaps to them, with no hurt or heal flash.
        setCharid = function(element, newCharid)
            charid = newCharid
            m_shownPct, m_seenTotal, m_seenCur, m_slideTime = nil, nil, nil, nil
            element.thinkTime = nil
        end,

        refreshCard = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid or tok.properties == nil then
                return
            end
            local c = tok.properties
            local cur, max, temp = 0, 0, 0
            local winded, dying = false, false
            local ok = pcall(function()
                cur = c:CurrentHitpoints()
                max = c:MaxHitpoints()
                temp = c:TemporaryHitpoints() or 0
                winded = cur <= c:BloodiedThreshold()
                dying = c:IsDying()
            end)
            --a failed read leaves cur at 0, which would read as a wipeout
            --and drain the bar for no reason: leave it where it is.
            if not ok or max <= 0 then
                return
            end
            m_cur, m_max, m_temp = cur, max, temp
            m_targetPct = math.max(0, math.min(1, cur / max))

            --stamina lost: flash the card and play the hit. Temp stamina
            --is counted in, so a hit fully soaked by temp still reads as
            --one -- it is still damage taken.
            local total = cur + temp
            if m_seenTotal ~= nil and total < m_seenTotal then
                element:FireEventOnParents("staminaLost", m_seenTotal - total)
                FireCardSound(g_hurtSound, charid, total, "Attack.Hit")
            end
            m_seenTotal = total

            --stamina gained: flash the card green and play the heal. Off
            --`cur` rather than the total, so temp stamina landing does not
            --read as a heal, and a hero healed out of dying (cur going
            --from negative to positive) still does.
            if m_seenCur ~= nil and cur > m_seenCur then
                element:FireEventOnParents("staminaGained", cur - m_seenCur)
                FireCardSound(g_healSound, charid, cur, "Ability.Heal_Generic")
            end
            m_seenCur = cur

            if m_shownPct == nil then
                m_shownPct = m_targetPct
            elseif m_shownPct ~= m_targetPct then
                if m_slideTime == nil then
                    m_slideTime = dmhub.Time()
                end
                element.thinkTime = STAMINA_SLIDE_THINK
            end

            fill:SetClass("winded", winded)
            fill:SetClass("dying", dying)
            element:SetClass("borderSuccess", not winded and not dying)
            element:SetClass("borderWarning", winded and not dying)
            element:SetClass("borderDanger", dying)
            Paint()
        end,

        --only runs while the bar is catching up to a new value; the last
        --step takes thinkTime back off.
        think = function(element)
            local now = dmhub.Time()
            local dt = math.max(0, math.min(0.25, now - (m_slideTime or now)))
            m_slideTime = now
            local diff = m_targetPct - (m_shownPct or 0)
            local step = diff * (1 - math.exp(-dt / STAMINA_SLIDE_TAU))
            local floorStep = dt / STAMINA_SLIDE_MAX_TIME
            if math.abs(step) < floorStep then
                step = floorStep * cond(diff < 0, -1, 1)
            end
            if math.abs(step) >= math.abs(diff) then
                m_shownPct = m_targetPct
                m_slideTime = nil
                element.thinkTime = nil
            else
                m_shownPct = (m_shownPct or 0) + step
            end
            Paint()
        end,
    }
end

--Heroic resource, icon only: the class's heroic resource icon (the
--character panel's own source) with the current value beside it. Surges
--are NOT here -- they render as per-surge icons in the card's bottom-right
--corner (CreateSurgeCorner).
local function CreateResourceRow(charid)
    local hrIcon = gui.Panel{
        classes = {"eotwResIcon"},
        interactable = false,
        refreshCard = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid or tok.properties == nil then
                return
            end
            local icon = nil
            pcall(function()
                --a hero's properties are a character; anything else raises into the pcall.
                local props = tok.properties --[[@as character]]
                local classInfo = props:GetClass()
                if classInfo ~= nil then
                    icon = classInfo:try_get("heroicResourceIcon")
                end
            end)
            element:SetClass("hidden", icon == nil)
            if icon ~= nil then
                element.selfStyle.bgimage = icon
            end
        end,
        linger = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok ~= nil and tok.valid and tok.properties ~= nil then
                local name = nil
                pcall(function() name = tok.properties:GetHeroicResourceName() end)
                gui.Tooltip(name or "Heroic Resource")(element)
            end
        end,
    }
    local hrValue = gui.Label{
        classes = {"eotwResValue"},
        text = "0",
        interactable = false,
        refreshCard = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid or tok.properties == nil then
                return
            end
            local value = 0
            pcall(function() value = tok.properties:GetHeroicOrMaliceResources() or 0 end)
            element.text = tostring(value)
        end,
    }
    return gui.Panel{
        width = "100%",
        height = RESOURCE_ROW_HEIGHT,
        flow = "horizontal",
        halign = "left",
        valign = "center",
        hrIcon,
        hrValue,
    }
end

--The recoveries circle: the hero's remaining recoveries (max minus the
--ones spent this long rest), in a small ringed disc. The ring turns red
--when none are left.
local function CreateRecoveriesCircle(charid)
    local label = gui.Label{
        classes = {"eotwRecoveriesLabel"},
        text = "0",
        interactable = false,
    }
    return gui.Panel{
        classes = {"eotwRecoveriesCircle"},
        label,
        refreshCard = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid or tok.properties == nil then
                return
            end
            local current = 0
            pcall(function()
                local c = tok.properties
                local id = CharacterResource.recoveryResourceId
                local max = c:GetResources()[id] or 0
                local used = c:GetResourceUsage(id, "long") or 0
                current = math.max(0, max - used)
            end)
            label.text = tostring(current)
            element:SetClass("empty", current <= 0)
        end,
        linger = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid or tok.properties == nil then
                return
            end
            local current, max, recoveryValue = 0, 0, nil
            pcall(function()
                local c = tok.properties
                local id = CharacterResource.recoveryResourceId
                max = c:GetResources()[id] or 0
                local used = c:GetResourceUsage(id, "long") or 0
                current = math.max(0, max - used)
                recoveryValue = c:RecoveryAmount()
            end)
            local lines = {
                string.format("<b>Recoveries: %d / %d</b>", current, max),
            }
            if recoveryValue ~= nil then
                lines[#lines+1] = string.format("Recovery Value: %d Stamina", recoveryValue)
            end
            gui.Tooltip(table.concat(lines, "\n"))(element)
        end,
    }
end

--The hero card's stamina row: the recoveries circle on the left, the
--stamina bar filling the rest. The bar keeps firing staminaLost /
--staminaGained up through this row to the card. noRecoveries drops the
--circle (a monster or NPC card: they have no recoveries).
local function CreateStaminaRow(charid, noRecoveries)
    if noRecoveries then
        return gui.Panel{
            width = "100%",
            height = 16,
            halign = "center",
            valign = "center",
            interactable = false,
            CreateStaminaBar(charid),
        }
    end
    return gui.Panel{
        width = "100%",
        height = 16,
        flow = "horizontal",
        halign = "center",
        valign = "center",
        interactable = false,
        CreateRecoveriesCircle(charid),
        gui.Panel{
            width = "100%-19",
            height = "auto",
            valign = "center",
            interactable = false,
            CreateStaminaBar(charid),
        },
    }
end

--One surge icon PER available surge, in the card's bottom-right corner --
--and nothing at all when the hero has none. Rebuilt only when the count
--changes; display capped at 9 icons (they would outgrow the card).
local function CreateSurgeCorner(charid)
    return gui.Panel{
        floating = true,
        halign = "right",
        valign = "bottom",
        x = -4,
        y = -3,
        width = "auto",
        height = 13,
        flow = "horizontal",
        interactable = false,
        data = { count = nil },
        refreshCard = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid or tok.properties == nil then
                return
            end
            local surges = 0
            pcall(function() surges = tok.properties:GetAvailableSurges() or 0 end)
            if surges == element.data.count then
                return
            end
            element.data.count = surges
            local icons = {}
            for i = 1, math.min(surges, 9) do
                icons[#icons+1] = gui.Panel{
                    classes = {"eotwSurgeIcon"},
                    interactable = false,
                }
            end
            element.children = icons
        end,
    }
end

--Encounter of the Week Intelligence the hero has earned and not yet spent:
--a brain chip with the count, at the left edge just above the overlay
--plate. Hidden at 0, and always outside an EotW game (the EncounterMontage
--codemod is not loaded on the titlescreen, where the town shows this card).
local function CreateIntelligenceBadge(charid, overlayHeight)
    local countLabel = gui.Label{
        text = "",
        fontSize = 12,
        bold = true,
        color = "#ffffff",
        width = "auto",
        height = "auto",
        valign = "center",
        lmargin = 3,
        textWrap = false,
        interactable = false,
    }
    return gui.Panel{
        classes = {"collapsed"},
        floating = true,
        halign = "left",
        valign = "bottom",
        x = 4,
        y = -(overlayHeight + 3),
        width = "auto",
        height = 20,
        flow = "horizontal",
        hpad = 5,
        borderBox = true,
        bgimage = "panels/square.png",
        bgcolor = "#000000cc",
        cornerRadius = 6,
        border = 1,
        borderColor = "#9cc4ffff",
        data = { count = 0 },
        linger = function(element)
            gui.Tooltip(string.format("%d Intelligence earned, to spend before the fight", element.data.count))(element)
        end,
        refreshCard = function(element)
            local count = 0
            local montage = rawget(_G, "EncounterMontage")
            if montage ~= nil and montage.GetHeroIntelligence ~= nil then
                pcall(function() count = montage.GetHeroIntelligence(charid) or 0 end)
            end
            if count == element.data.count then
                return
            end
            element.data.count = count
            countLabel.text = string.format("%d", count)
            element:SetClass("collapsed", count <= 0)
        end,
        gui.Panel{
            width = 13,
            height = 13,
            valign = "center",
            bgimage = "phosphor/brain.png",
            bgcolor = "#9cc4ff",
            interactable = false,
        },
        countLabel,
    }
end

--Downtime Activities the hero has to spend on projects (town only, opts.
--showDowntime): an amber hammer chip with the count in the card's top-left
--corner, hidden at 0. The count lives in the City and reaches us with the
--roster list (EotwRoster.GetDowntime).
local function CreateDowntimeBadge(charid)
    local countLabel = gui.Label{
        text = "",
        fontSize = 14,
        bold = true,
        color = "#ffd38a",
        width = "auto",
        height = "auto",
        valign = "center",
        lmargin = 3,
        textWrap = false,
        interactable = false,
    }
    return gui.Panel{
        classes = {"collapsed"},
        floating = true,
        halign = "left",
        valign = "top",
        x = 4,
        y = 4,
        width = "auto",
        height = 22,
        flow = "horizontal",
        hpad = 5,
        borderBox = true,
        bgimage = "panels/square.png",
        bgcolor = "#3a2a10f0",
        cornerRadius = 6,
        border = 1,
        borderColor = "#e0a43aff",
        data = { count = 0 },
        linger = function(element)
            gui.Tooltip(string.format("%d Downtime %s to spend on projects", element.data.count, cond(element.data.count == 1, "Activity", "Activities")))(element)
        end,
        refreshCard = function(element)
            local count = 0
            local roster = rawget(_G, "EotwRoster")
            if roster ~= nil and roster.GetDowntime ~= nil then
                pcall(function() count = roster.GetDowntime(charid) or 0 end)
            end
            if count == element.data.count then
                return
            end
            element.data.count = count
            countLabel.text = string.format("%d", count)
            element:SetClass("collapsed", count <= 0)
        end,
        gui.Panel{
            width = 14,
            height = 14,
            valign = "center",
            bgimage = "phosphor/hammer-fill.png",
            bgcolor = "#ffd38a",
            interactable = false,
        },
        countLabel,
    }
end

--A gently pulsing "!" trigger badge in the card's top-left corner while
--the hero has an available (non-hostile, undismissed) trigger -- the same
--test the Monster AI's trigger-reaction dice uses. Hostile prompts are
--skipped because they never expire and would pulse forever. Hover lists
--the pending triggers; clicking centers the map on the hero and selects
--them (selection only takes for a hero the user controls). Rebuilt only
--when the set of trigger ids changes.
local function CreateTriggerCorner(charid)
    local badge = gui.TriggerPanel{
        width = 22,
        height = 22,
        halign = "left",
        valign = "top",
        swallowPress = true,
        data = { tooltipText = "" },
        hover = function(element)
            element.tooltip = element.data.tooltipText
        end,
        press = function(element)
            audio.FireSoundEvent("Mouse.Click")
            dmhub.CenterOnToken(charid, function()
                dmhub.SelectToken(charid)
            end)
        end,
        thinkTime = 0.03,
        think = function(element)
            local r = (math.sin(dmhub.Time() * 2 * math.pi / 1.4) + 1) / 2
            element.selfStyle.opacity = 0.6 + 0.4 * r
            element.selfStyle.scale = 0.92 + 0.16 * r
        end,
    }

    return gui.Panel{
        classes = {"collapsed"},
        floating = true,
        halign = "left",
        valign = "top",
        x = 4,
        y = 4,
        width = 22,
        height = 22,
        styles = Styles.TriggerStyles,
        data = { sig = nil },
        refreshCard = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid or tok.properties == nil then
                return
            end
            local triggers = nil
            pcall(function() triggers = tok.properties:GetAvailableTriggers(true) end)
            local ids = {}
            local lines = {}
            if triggers ~= nil then
                for id, t in pairs(triggers) do
                    if not t.hostile then
                        ids[#ids+1] = id
                        local text = t.text
                        if t.powerRollModifier then
                            text = t.powerRollModifier:try_get("name") or text
                        end
                        if text ~= nil and text ~= "" then
                            lines[#lines+1] = text
                        end
                    end
                end
            end
            table.sort(ids)
            local sig = table.concat(ids, ",")
            if sig == element.data.sig then
                return
            end
            element.data.sig = sig
            if #ids == 0 then
                element:SetClass("collapsed", true)
                return
            end
            table.sort(lines)
            local name = HeroDisplayName(tok)
            local tip = string.format("%s has a trigger available.", name)
            if #lines > 0 then
                tip = tip .. "\n\n" .. table.concat(lines, "\n")
            end
            tip = tip .. "\n\nClick to jump to " .. name .. "."
            badge.data.tooltipText = tip
            element:SetClass("collapsed", false)
        end,
        badge,
    }
end

--MONTAGE ONLY (opts.showStats). The five characteristics down the card's
--right edge, one chip each, initial + score ("M +2") so the whole set fits
--in the artwork's margin. Ordered by the attribute's own `order` (Might,
--Agility, Reason, Intuition, Presence -- MARIP), read from the game system
--rather than hardcoded so a system with other characteristics still works.
local function CreateStatStrip(charid)
    local attrList = {}
    for _, info in pairs(creature.attributesInfo) do
        attrList[#attrList+1] = info
    end
    table.sort(attrList, function(a, b) return a.order < b.order end)

    local rows = {}
    for _, info in ipairs(attrList) do
        local attrid = info.id
        local initial = string.sub(info.description, 1, 1)
        rows[#rows+1] = gui.Panel{
            classes = {"eotwStatChip"},
            interactable = false,
            --the stage fires this down the card with the attrid the test in
            --flight is rolled with (nil = none): that chip turns gold.
            highlightCharacteristic = function(element, activeAttrid)
                element:SetClass("active", activeAttrid == attrid)
            end,
            gui.Label{
                classes = {"eotwStatKey"},
                text = initial,
                interactable = false,
            },
            gui.Label{
                classes = {"eotwStatValue"},
                text = "",
                interactable = false,
                refreshCard = function(element)
                    local tok = dmhub.GetCharacterById(charid)
                    if tok == nil or not tok.valid or tok.properties == nil then
                        return
                    end
                    local value = nil
                    pcall(function() value = tok.properties:GetAttribute(attrid):Modifier() end)
                    if value == nil then
                        return
                    end
                    element.text = string.format("%+d", value)
                end,
            },
        }
    end

    --below the condition chips (top-right) and above the overlay, so the
    --strip never collides with either.
    return gui.Panel{
        floating = true,
        halign = "right",
        valign = "top",
        x = -3,
        y = 34,
        width = "auto",
        height = "auto",
        flow = "vertical",
        interactable = false,
        children = rows,
    }
end

--MONTAGE ONLY (opts.showStats). The hero's trained skills, comma separated,
--on the line under their name. Skills do not change during an encounter, so
--the (30-odd skill) proficiency sweep runs at most every few seconds rather
--than on every refreshCard tick.
local SKILLS_RECHECK_SECONDS = 5

--The skill the test in flight is using (the stage's highlightSkill event)
--is set in gold within the line.
local SKILL_HIGHLIGHT_COLOR = "#ffd66b"

local function CreateSkillsLine(charid)
    --skills = the proficient {id, name} pairs in display order; skillid =
    --the one to highlight, nil for none. Rendered again whenever either
    --changes.
    local function Render(element)
        local parts = {}
        for _, skill in ipairs(element.data.skills) do
            if skill.id == element.data.skillid then
                parts[#parts+1] = string.format("<color=%s><b>%s</b></color>", SKILL_HIGHLIGHT_COLOR, skill.name)
            else
                parts[#parts+1] = skill.name
            end
        end
        element.text = table.concat(parts, ", ")
    end

    return gui.Label{
        classes = {"eotwSkillsLine"},
        text = "",
        interactable = false,
        data = { nextCheck = 0, signature = nil, skills = {}, skillid = nil },
        refreshCard = function(element)
            local now = dmhub.Time()
            if now < element.data.nextCheck then
                return
            end
            element.data.nextCheck = now + SKILLS_RECHECK_SECONDS
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid or tok.properties == nil then
                return
            end
            local skills = {}
            local ids = {}
            pcall(function()
                --Skill.SkillsInfo is already sorted by name.
                for _, skill in ipairs(Skill.SkillsInfo) do
                    if tok.properties:ProficientInSkill(skill) then
                        skills[#skills+1] = { id = skill.id, name = skill.name }
                        ids[#ids+1] = skill.id
                    end
                end
            end)
            local signature = table.concat(ids, ",")
            if signature == element.data.signature then
                return
            end
            element.data.signature = signature
            element.data.skills = skills
            Render(element)
        end,
        highlightSkill = function(element, skillid)
            if skillid == element.data.skillid then
                return
            end
            element.data.skillid = skillid
            Render(element)
        end,
    }
end

--True when an image id is a cloud-asset GUID whose asset record has not
--loaded. The engine draws such an id as a plain white square until the
--record arrives -- e.g. for a few seconds after re-entering the lobby, whose
--asset records load after its characters. Other id kinds never count.
---@param id any
---@return boolean
local function IsUnregisteredAssetId(id)
    if type(id) ~= "string" then
        return false
    end
    if string.match(id, "^%x+%-%x+%-%x+%-%x+%-%x+$") == nil then
        return false
    end
    local known = false
    pcall(function() known = assets.allAssets[id] ~= nil end)
    return not known
end

local PORTRAIT_RECORD_POLL_SECONDS = 0.25

local ApplyPortrait

--Re-applies a portrait that was waiting on its asset record, once the record
--has loaded. One chain per panel: element.data.eotwPortraitWait holds the
--latest request and is cleared by whichever ApplyPortrait call settles it.
---@param element Panel
local function SchedulePortraitRetry(element)
    dmhub.Schedule(PORTRAIT_RECORD_POLL_SECONDS, function()
        if mod.unloaded or not element.valid then
            return
        end
        local wait = element.data.eotwPortraitWait
        if wait == nil then
            return
        end
        if IsUnregisteredAssetId(wait.portrait) then
            SchedulePortraitRetry(element)
            return
        end
        element.data.eotwPortraitWait = nil
        --pcall: the token may be a detached snapshot copy, or gone by now.
        pcall(ApplyPortrait, element, wait.tok, wait.aspect)
    end)
end

--Paints a hero's portrait as a panel's full-bleed background, cropped to the
--panel's shape the way the hero card crops it. `aspect` is the panel's
--width / height. Leaves the panel alone when the hero has no art, so its own
--dark ground shows. Returns true when art was applied. Art whose asset
--record has not loaded yet is treated as no art for now, and applied by
--itself once the record arrives (rather than showing white meanwhile).
---@param element Panel
---@param tok CharacterToken
---@param aspect number
---@return boolean
ApplyPortrait = function(element, tok, aspect)
    local portrait = nil
    pcall(function() portrait = tok.offTokenPortrait end)
    local waiting = element.data.eotwPortraitWait
    if IsUnregisteredAssetId(portrait) then
        element.data.eotwPortraitWait = { tok = tok, aspect = aspect, portrait = portrait }
        if waiting == nil then
            SchedulePortraitRetry(element)
        end
        return false
    end
    element.data.eotwPortraitWait = nil
    if portrait == nil or portrait == "" then
        return false
    end
    --bgcolor white keeps the artwork untinted; the card's border and the
    --overlay carry the mine/others styling.
    element.bgimage = portrait
    element.selfStyle.bgcolor = "white"
    local rect = nil
    pcall(function() rect = tok:GetPortraitRectForAspect(aspect, portrait) end)
    element.selfStyle.imageRect = rect
    return true
end

--opts (all optional):
--  halign      the card's halign (default "right", the roster's edge)
--  draggable   non-nil = the drag callbacks below are passed through to
--              the panel (the montage stage); the value itself is the
--              card's starting draggable state, which the caller may flip
--              later (the stage makes only the local user's own heroes
--              draggable, and only while they can act)
--  canDragOnto, drag, beginDrag, dragging   drag callbacks (see Definitions/Panel.lua);
--              dragging fires every frame of a drag with the drop target hovered
--  useClick    use the click event for the character-panel popout instead
--              of press (press also fires when a drag gesture ends)
--  click       replaces the character-panel popout with this handler
--              (element, OpenCharacterPanel) -- the second argument is the
--              default behavior, for handlers that fall back to it
--  subtitle    function(tok) -> the line under the name (default: who
--              controls the hero; the town shows class and level instead)
--  showStats   the montage stage's fuller card: the characteristics strip
--              down the right edge and the skills line under the name (the
--              roster's cards are too crowded for either)
--  showSkills  the skills line on its own (default: showStats). The town's
--              cards show the characteristics but not the skills.
--  showResources  the heroic resource row under the stamina bar (default
--              true). The town has no use for it outside an encounter.
--  showDowntime   the hammer chip with the hero's unspent Downtime
--              Activities (the town's cards; see CreateDowntimeBadge)
--  noRecoveries   no recoveries circle beside the stamina bar (a monster or
--              NPC card on the tabletop view's table, Tabletop.lua)
--  displayName    function(tok) -> the name on the card (default: the
--              hero's name, "Unnamed Hero" when it has none)
--  passPress   the card does not swallow presses, so a draggable panel
--              around it can be dragged by the card (the tabletop view's
--              NPC cards); the host must swallow them instead
local function CreateHeroCard(entry, opts)
    opts = opts or {}
    local showSkills = opts.showSkills
    if showSkills == nil then
        showSkills = opts.showStats == true
    end
    local showResources = opts.showResources ~= false
    local charid = entry.charid
    local mineClass = nil
    if entry.mine then
        mineClass = "mine"
    end

    local nameLabel = gui.Label{
        classes = {"eotwHeroName"},
        text = entry.name,
        interactable = false,
    }

    local playerLabel = gui.Label{
        classes = {"eotwHeroPlayer"},
        text = "",
        interactable = false,
    }

    --condition icons over the artwork, packed into the TOP-RIGHT corner
    --(user direction 2026-08-29 -- they used to center across the top);
    --rebuilt only when the set actually changes. Each icon sits on a dark
    --red-bordered chip so it reads against any portrait.
    local conditionsRow = gui.Panel{
        floating = true,
        halign = "right",
        valign = "top",
        x = -4,
        y = 4,
        width = CARD_WIDTH - 8,
        height = "auto",
        flow = "horizontal",
        wrap = true,
        interactable = false,
        data = { signature = nil },
        refreshCard = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid or tok.properties == nil then
                return
            end
            local entries = CollectConditions(tok.properties)
            local parts = {}
            for _, cond in ipairs(entries) do
                parts[#parts+1] = tostring(cond.icon)
            end
            local sig = table.concat(parts, "|")
            if sig == element.data.signature then
                return
            end
            element.data.signature = sig
            local icons = {}
            for _, cond in ipairs(entries) do
                local condName = cond.name
                local condid = cond.condid
                local effectid = cond.effectid
                local menuText = string.format("End '%s' %s", condName, cond.condid ~= nil and "Condition" or "Ongoing Effect")
                --halign right on every chip is what right-packs the row:
                --the flow layout places the trailing run of halign="right"
                --children against the right edge, in order.
                icons[#icons+1] = gui.Panel{
                    halign = "right",
                    width = CONDITION_CHIP_SIZE,
                    height = CONDITION_CHIP_SIZE,
                    lmargin = 3,
                    bmargin = 3,
                    bgimage = "panels/square.png",
                    bgcolor = "#000000cc",
                    cornerRadius = 6,
                    border = 2,
                    borderColor = "#cc2222ff",
                    linger = function(iconElement)
                        gui.Tooltip(condName)(iconElement)
                    end,
                    --Right-click ends the condition/effect (director or the token's controller only).
                    rightClick = function(iconElement)
                        local tok = dmhub.GetCharacterById(charid)
                        if tok == nil or not tok.valid or tok.properties == nil then
                            return
                        end
                        if not (dmhub.isDM or tok.canControl) then
                            return
                        end
                        iconElement.popup = gui.ContextMenu{
                            entries = {
                                {
                                    text = menuText,
                                    click = function()
                                        iconElement.popup = nil
                                        tok:ModifyProperties{
                                            description = "Remove Condition",
                                            execute = function()
                                                if condid ~= nil then
                                                    tok.properties:InflictCondition(condid, {purge = true})
                                                else
                                                    tok.properties:RemoveOngoingEffect(effectid)
                                                end
                                            end,
                                        }
                                    end,
                                },
                            },
                        }
                    end,
                    gui.Panel{
                        width = CONDITION_ICON_SIZE,
                        height = CONDITION_ICON_SIZE,
                        halign = "center",
                        valign = "center",
                        bgimage = cond.icon,
                        bgcolor = cond.display.bgcolor or "white",
                        hueshift = cond.display.hueshift or 0,
                        saturation = cond.display.saturation or 1,
                        brightness = cond.display.brightness or 1,
                        interactable = false,
                    },
                }
            end
            element.children = icons
        end,
    }

    --the bottom-third overlay: name, stamina bar, resource icons on a
    --semi-opaque plate over the artwork. On the montage card the skills
    --line sits under the name, and the plate grows to make room for it.
    ---@type Panel[]
    local overlayChildren = { nameLabel, playerLabel }
    if showSkills then
        overlayChildren[#overlayChildren+1] = CreateSkillsLine(charid)
    end
    overlayChildren[#overlayChildren+1] = CreateStaminaRow(charid, opts.noRecoveries)
    if showResources then
        overlayChildren[#overlayChildren+1] = CreateResourceRow(charid)
    end

    local overlayHeight = OVERLAY_HEIGHT
    local cardHeight = CARD_HEIGHT
    if not showResources then
        --the plate shrinks; the card keeps its size and shows more artwork.
        overlayHeight = overlayHeight - RESOURCE_ROW_HEIGHT
    end
    if showSkills then
        overlayHeight = overlayHeight + SKILLS_HEIGHT
        --the plate grows downward out of the artwork rather than eating into
        --it: the card itself gets the extra height (EncounterMontageStage's
        --HERO_ROW_HEIGHT budgets for it).
        cardHeight = CARD_HEIGHT + SKILLS_HEIGHT
    end

    local overlay = gui.Panel{
        classes = {"eotwCardOverlay", mineClass},
        floating = true,
        halign = "center",
        valign = "bottom",
        width = "100%",
        height = overlayHeight,
        flow = "vertical",
        bgimage = "panels/square.png",
        cornerRadius = 8,
        hpad = 6,
        vpad = 4,
        borderBox = true,
        interactable = false,

        children = overlayChildren,
    }

    --the red wash for a hit and the green one for a heal, over the artwork
    --and the overlay alike.
    local hurtFlash = CreateCardFlash("eotwHurtFlash", 8)
    local healFlash = CreateCardFlash("eotwHealFlash", 8)

    --the dead hero's wash and skull, hidden until the card gets the "dead"
    --class. The skull is centered on the artwork above the overlay plate,
    --so the name and player line stay readable under the wash.
    local artworkHeight = cardHeight - overlayHeight
    local skullSize = math.min(64, artworkHeight - 16)
    local deadMark = gui.Panel{
        classes = {"eotwDeadMark"},
        floating = true,
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        cornerRadius = 8,
        interactable = false,
        gui.Panel{
            classes = {"eotwDeadSkull"},
            width = skullSize,
            height = skullSize,
            halign = "center",
            valign = "top",
            y = math.floor((artworkHeight - skullSize) / 2),
            interactable = false,
        },
    }

    --the card IS the portrait: full-bleed artwork with the overlay and
    --condition chips floating on top.
    local function OpenCharacterPanel(element)
        audio.FireSoundEvent("Mouse.Click")
        local toggle = rawget(_G, "ToggleCharacterPanelDocument")
        if toggle ~= nil then
            --anchored to this card: the window opens right beside it
            --instead of at the remembered/center position.
            toggle(charid, nil, element)
        end
    end

    --no holes in the class list: the engine stops at the first nil.
    local cardClasses = {"eotwHeroCard"}
    if mineClass ~= nil then
        cardClasses[#cardClasses+1] = mineClass
    end
    if opts.showStats then
        cardClasses[#cardClasses+1] = "stats"
    end

    local cardArgs = {
        classes = cardClasses,
        width = CARD_WIDTH,
        height = cardHeight,
        halign = opts.halign or "right",
        cornerRadius = 8,
        bgimage = "panels/square.png",
        --passPress lets the press through to a draggable host around the card.
        swallowPress = opts.passPress ~= true,

        data = { charid = charid, mine = entry.mine },

        refreshCard = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid then
                return
            end
            element:SetClass("dead", IsCardHeroDead(tok))
            if opts.displayName ~= nil then
                nameLabel.text = opts.displayName(tok) or ""
            else
                nameLabel.text = HeroDisplayName(tok)
            end
            if opts.subtitle ~= nil then
                playerLabel.text = opts.subtitle(tok) or ""
            else
                playerLabel.text = HeroPlayerName(tok)
            end
            ApplyPortrait(element, tok, CARD_WIDTH / cardHeight)
        end,

        --fired up from the stamina bar in the overlay when this hero loses
        --or regains stamina.
        staminaLost = function(element)
            hurtFlash:PulseClass("hurt")
        end,

        staminaGained = function(element)
            healFlash:PulseClass("healed")
        end,

        conditionsRow,
        overlay,
        CreateSurgeCorner(charid),
        CreateTriggerCorner(charid),
        CreateIntelligenceBadge(charid, overlayHeight),
    }
    if opts.showStats then
        cardArgs[#cardArgs+1] = CreateStatStrip(charid)
    end
    if opts.showDowntime then
        cardArgs[#cardArgs+1] = CreateDowntimeBadge(charid)
    end
    --last, so the washes sit over every other layer of the card.
    cardArgs[#cardArgs+1] = deadMark
    cardArgs[#cardArgs+1] = hurtFlash
    cardArgs[#cardArgs+1] = healFlash
    --opts.dismiss = {tooltip=, click=}: an X in the top-right corner that
    --shows only while the card is hovered. A direct child of the card so
    --"parent:hover" reaches it; after the washes so it sits on top.
    if opts.dismiss ~= nil then
        cardArgs[#cardArgs+1] = gui.Panel{
            classes = {"eotwCardDismiss"},
            floating = true,
            halign = "right",
            valign = "top",
            x = -4,
            y = 4,
            width = 18,
            height = 18,
            bgimage = "phosphor/x-bold.png",
            bgcolor = "#ffffffcc",
            swallowPress = true,
            styles = {
                {
                    selectors = {"eotwCardDismiss"},
                    hidden = 1,
                },
                {
                    selectors = {"eotwCardDismiss", "parent:hover"},
                    hidden = 0,
                },
                {
                    selectors = {"eotwCardDismiss", "hover"},
                    hidden = 0,
                    bgcolor = "#ff7a6aff",
                    scale = 1.15,
                },
            },
            hover = gui.Tooltip(opts.dismiss.tooltip or "Dismiss"),
            --on click, not press: a handled click stops here, but an
            --unhandled one bubbles up to the card, whose click opens the
            --hero's sheet. swallowPress covers cards that open on press.
            click = function(element)
                audio.FireSoundEvent("Mouse.Click")
                opts.dismiss.click(element)
            end,
        }
    end
    --PROTOTYPE: the card's back and the hover button that turns the card
    --over to it (HeroCardBack.lua).
    local cardBack = rawget(_G, "HeroCardBack")
    if cardBack ~= nil then
        cardBack.Decorate(cardArgs, charid, CARD_WIDTH, cardHeight)
    end
    if opts.click ~= nil then
        cardArgs.click = function(element)
            opts.click(element, OpenCharacterPanel)
        end
    elseif opts.useClick then
        cardArgs.click = OpenCharacterPanel
    else
        cardArgs.press = OpenCharacterPanel
    end
    if opts.draggable ~= nil then
        cardArgs.draggable = opts.draggable == true
        cardArgs.canDragOnto = opts.canDragOnto
        cardArgs.drag = opts.drag
        cardArgs.beginDrag = opts.beginDrag
        cardArgs.dragging = opts.dragging
    end
    --the card as a drop target (the montage drops item icons on it).
    if opts.dragTarget then
        cardArgs.dragTarget = true
        cardArgs.dragTargetPriority = opts.dragTargetPriority
        cardArgs.dragTargets = opts.dragTargets
    end
    return gui.Panel(cardArgs)
end

EotwHeroCard = {
    CreateHeroCard = CreateHeroCard,
    CreateStaminaBar = CreateStaminaBar,
    CreateCardFlash = CreateCardFlash,
    ApplyPortrait = ApplyPortrait,
    CollectHeroes = CollectHeroes,
    IsCardHeroDead = IsCardHeroDead,
    RosterSignature = RosterSignature,
    HeroDisplayName = HeroDisplayName,
    --the card's style rules; callers wrap them in their own MergeTokens /
    --MergeStyles so the theme tokens resolve for their cascade root.
    rules = g_heroCardRules,
    CARD_WIDTH = CARD_WIDTH,
    CARD_HEIGHT = CARD_HEIGHT,
}

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

local T = UIText.T
local TP = UIText.Plural

--- Hero collection ----------------------------------------------------------

--A hero whose player never typed a name still has to label its card with
--something. (EncounterMontage.HeroDisplayName says the same thing; kept
--local here because this file only reaches that module defensively.)
local function HeroDisplayName(tok)
    local name = nil
    pcall(function() name = tok.name end)
    if name == nil or name == "" then
        return T("herocard.name.unnamed")
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
        return T("herocard.player.unclaimed")
    end
    if owner == "PARTY" then
        return T("herocard.player.party")
    end
    local name = owner
    pcall(function() name = dmhub.GetDisplayName(owner) or owner end)
    --their Player Tag, known while the town is connected (not inside a game yet).
    return name .. EotwPlayerTags.Inline(EotwPlayerTags.TagOf(owner), 90)
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
                condid = condid,
                name = info.name or T("herocard.condition.fallback"),
            }
        end
    end

    local ongoingTable = dmhub.GetTable("characterOngoingEffects") or {}
    local effects = nil
    pcall(function() effects = c:ActiveOngoingEffects() end)
    --built-in effects (Squeezed, ...) are rebuilt from token state on every
    --refresh, so RemoveOngoingEffect cannot end them: they get no effectid,
    --which keeps the card from offering to end them.
    local builtin = {}
    for _, entry in ipairs(rawget(c, "_tmp_builtinOngoingEffects") or {}) do
        builtin[entry] = true
    end
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
                    effectid = (not builtin[entry]) and entry.ongoingEffectid or nil,
                    name = info.name or T("herocard.effect.fallback"),
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
--a characteristic chip at its full height, and the gap above each chip
--(CreateStatStrip shrinks the chip where the artwork is too short for five).
local STAT_ROW_HEIGHT = 15
local STAT_ROW_GAP = 1
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
        tmargin = STAT_ROW_GAP,
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
        width = 25,
        height = 25,
        halign = "left",
        valign = "center",
        bgcolor = "white",
    },
    {
        selectors = {"eotwResValue"},
        fontSize = 21,
        bold = true,
        color = "#ffffff",
        width = "auto",
        height = "auto",
        --both the icon and the value align left so the flow packs
        --them together instead of spreading them across the row.
        halign = "left",
        valign = "center",
        --room for the edit frame between the number and its icon.
        lmargin = 6,
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
        width = 22,
        height = 22,
        valign = "center",
        halign = "left",
        rmargin = 3,
        cornerRadius = 11,
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
        fontSize = 15,
        bold = true,
        color = "#ffffff",
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        textWrap = false,
    },
    --the "+" that spends a Recovery (CreateSpendRecoveryButton): a green
    --disc the size of the recoveries circle, brighter on hover.
    {
        selectors = {"eotwSpendRecovery"},
        width = 20,
        height = 20,
        valign = "center",
        halign = "left",
        rmargin = 3,
        cornerRadius = 10,
        bgimage = "panels/square.png",
        bgcolor = "#2f7d3acc",
        border = 1,
        borderColor = "#9fe3a8cc",
    },
    {
        selectors = {"eotwSpendRecovery", "hover"},
        bgcolor = "#3fa64dff",
        borderColor = "#ffffffff",
    },
    {
        selectors = {"eotwSpendRecoveryLabel"},
        fontSize = 19,
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
    --the speech balloon hanging off the card's left edge while the hero's
    --player talks on Discord voice (CreateVoiceBalloon).
    {
        selectors = {"eotwVoiceBalloon"},
        bgcolor = "@bg",
        border = 1,
        borderColor = "@accent",
    },
    {
        selectors = {"eotwVoiceBalloonIcon"},
        bgcolor = "@fgStrong",
    },
}


local CARD_WIDTH = 132
--the player line grows the card and its overlay alike, so the artwork
--above the overlay keeps its size.
local CARD_HEIGHT = 176 + PLAYER_HEIGHT
--the stamina row and the resource row are drawn half again as large as
--they were (user direction 2026-11-19); the plate grows up over the
--artwork for them and the card keeps its size.
local OVERLAY_HEIGHT = 76 + PLAYER_HEIGHT
--the heroic resource row's share of the overlay (CreateResourceRow).
local RESOURCE_ROW_HEIGHT = 28
--the card's stamina row and the bar inside it, and the bar's numbers.
local STAMINA_ROW_HEIGHT = 23
local CARD_STAMINA_BAR = { height = 21, fontSize = 15 }
--the stamina bar's recovery preview (CreateStaminaBar), as on the card's back
--(HeroCardBack.lua): pale green when a Recovery all lands, amber when some of
--it would be wasted past max.
local RECOVERY_PREVIEW_FITS = "#4caf6a66"
local RECOVERY_PREVIEW_OVER = "#e8a33dbb"
--condition chips in the card's top-right corner: the outer dark/red-bordered
--chip and the condition icon inside it.
local CONDITION_CHIP_SIZE = 26
local CONDITION_ICON_SIZE = 18
local CONDITION_ROW_Y = 4
--the top of the characteristics strip: clear of one row of condition chips.
local STAT_STRIP_Y = CONDITION_ROW_Y + CONDITION_CHIP_SIZE + 4

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
--charid, these remember the damage entry the sound last fired for and
--when: whichever card sees the entry first plays it and the other stays
--silent. (Attack.Hit already de-duplicates itself over 0.2s, but the two
--surfaces refresh on different cadences -- 0.5s on the stage, 1s on the
--roster -- so they can easily notice the same hit further apart than that.)
local CARD_SOUND_DEDUP = 2
--how old (seconds) a damage entry may be and still sound on a card. Undo
--and Revert Turn can bring back entries from minutes ago, which must not.
local CARD_ENTRY_FRESH = 10
local g_hurtSound = {}
local g_healSound = {}

--2D, with no tokenid: the card is what the player is looking at, and
--during a montage the map is not even on screen to position it in.
--- @param seen table g_hurtSound or g_healSound
--- @param charid string
--- @param key string the damage entry's id and amounts
--- @param eventName string
local function FireCardSound(seen, charid, key, eventName)
    local now = dmhub.Time()
    local last = seen[charid]
    if last ~= nil and last.key == key and now - last.t < CARD_SOUND_DEDUP then
        return
    end
    seen[charid] = { key = key, t = now }
    audio.FireSoundEvent(eventName)
end

--How the bar slides to a new stamina value instead of snapping to it, so
--damage reads as a drain. The ease is exponential (tau), with a floor on
--the speed -- a full bar in MAX_TIME seconds -- so the exponential tail
--still lands promptly instead of creeping.
local STAMINA_SLIDE_TAU = 0.14
local STAMINA_SLIDE_MAX_TIME = 0.7
local STAMINA_SLIDE_THINK = 0.02

--How much of a creature's Stamina the local user may see on a card, by the
--same rules as its token's stamina bar (the "lifebar" in DrawSteelTokenHud):
--"val" (the numbers), "pct" (a percentage), "bar" (the fill alone) or "none".
--The Director and the creature's controller always see it all: the token's
--"shown to Director / controlling player" settings are display preferences,
--and both can open the sheet anyway. The lobby (the town) is not gated.
local function StaminaDisplayFor(tok)
    if dmhub.isDM or dmhub.isLobbyGame then
        return "val"
    end
    local controlled, friend = false, false
    pcall(function() controlled = tok.canControl == true end)
    pcall(function() friend = tok.isFriendOfPlayer == true end)
    if controlled then
        return "val"
    end
    if friend then
        local party = true
        pcall(function() party = dmhub.GetSettingValue("hpbarforparty") ~= false end)
        return cond(party, "val", "none")
    end
    local mode = "none"
    pcall(function() mode = dmhub.GetSettingValue("enemystambardisplay") or "none" end)
    if mode == "none" or mode == "val" then
        return mode
    end
    --a monster whose Stamina the players have learned (Monster Info) shows
    --its numbers, as on the token. rawget: Draw Steel Core Rules may not be loaded.
    local knowledge = rawget(_G, "MonsterKnowledge")
    if knowledge ~= nil and knowledge.PlayersKnowStaminaExactly ~= nil then
        local knows = false
        pcall(function() knows = knowledge.PlayersKnowStaminaExactly(tok.properties, tok) == true end)
        if knows then
            return "val"
        end
    end
    return mode
end

--Whether the local user may make a card's click edits at all (typing a
--Stamina or heroic resource, spending a Recovery from the circle). The
--Director always may; players may not in an Encounter of the Week game or
--under strict resource rules (StrictActionEconomyEnforced).
--- @return boolean
local function CardEditsAllowed()
    if dmhub.isDM then
        return true
    end
    if StrictActionEconomyEnforced() then
        return false
    end
    local eotw = false
    local eotwGame = rawget(_G, "EncounterOfTheWeekGame")
    if eotwGame ~= nil then
        pcall(function() eotw = eotwGame.IsEotwGame() == true end)
    end
    return not eotw
end

--Makes a number on the card editable where it stands (the Stamina, the
--heroic resource): under the mouse it lights up, a click edits it, and
--ctrl+scroll steps it by one. args.current() is the number, or nil while it
--may not be edited; args.apply(value) sets it. Enter or clicking away sets
--the typed whole number; Escape does not.
--
--The box is a floating child of the label, drawn exactly over its text, which
--is made transparent: the label keeps its place in the layout, so nothing
--moves. The label follows the typing, as it will read once it is set.
--
--The label's own refresh must leave it alone while the box is up (the box
--is not "collapsed").
--args: label, current, apply; fontSize (the label's); color (the label's,
--default white); target (default the label): the panel that takes the mouse;
--refreshText: paints the label again, when its text is not just current().
--- @class CardNumberEntryArgs
--- @field label Label
--- @field current fun(): number|nil
--- @field apply fun(value: integer)
--- @field fontSize number
--- @field color string|nil
--- @field target Panel|nil
--- @field refreshText fun()|nil

--how far the engine insets an input's text from its top and bottom. With
--hpad = 0 there is no side inset: the box's left edge is the text's.
local INPUT_INSET_Y = 6.5

--- @param args CardNumberEntryArgs
--- @return Input entry
local function CreateNumberEntry(args)
    local label = args.label
    local target = args.target or label
    ---@type Input
    local entry
    --true while the box is up; a change that arrives after it closed (an
    --escape's focus loss) is not applied.
    local m_open = false
    --true once the box really has focus, so the defocus fired while it is
    --still opening does not shut it again.
    local m_focused = false
    local m_hover = false

    --the light under the mouse, and the box's backing while it is up.
    local frame = gui.Panel{
        classes = {"hidden"},
        floating = true,
        interactable = false,
        width = 1,
        height = 1,
        x = -3,
        halign = "left",
        valign = "center",
        bgimage = "panels/square.png",
        border = 1,
        borderColor = "#ffffffcc",
        cornerRadius = 4,
    }

    --sized by hand: a percentage of an auto-sized label is not its own size.
    local function FitFrame()
        if frame.valid and label.valid then
            frame.selfStyle.width = label.renderedWidth + 6
            --taller than the text, so the selection does not run into the border.
            frame.selfStyle.height = label.renderedHeight + 4
        end
    end

    local function UpdateFrame()
        if not frame.valid then
            return
        end
        local show = m_open or (m_hover and args.current() ~= nil)
        frame:SetClass("hidden", not show)
        if show then
            frame.selfStyle.bgcolor = cond(m_open, "#000000e0", "#ffffff18")
            FitFrame()
        end
    end

    --the label reads what is set.
    local function ShowValue()
        if not label.valid then
            return
        end
        if args.refreshText ~= nil then
            args.refreshText()
            return
        end
        local current = args.current()
        if current ~= nil then
            label.text = tostring(current)
        end
    end

    --the label reads what is typed.
    local function Mirror()
        label.text = cond(entry.text == "", "0", entry.text)
        gui.AfterLayout(FitFrame)
    end

    local function Close()
        m_open = false
        m_focused = false
        if entry.valid then
            entry:SetClass("collapsed", true)
            entry.captureEscape = false
        end
        if label.valid then
            label.selfStyle.opacity = 1
        end
        ShowValue()
        UpdateFrame()
        --the label may have just changed width.
        gui.AfterLayout(FitFrame)
    end

    entry = gui.Input{
        classes = {"collapsed"},
        floating = true,
        width = 1,
        height = 1,
        x = 0,
        halign = "left",
        valign = "center",
        hpad = 0,
        vpad = 0,
        border = 0,
        borderWidth = 0,
        bgimage = "panels/square.png",
        bgcolor = "#00000000",
        color = args.color or "#ffffff",
        bold = true,
        fontSize = args.fontSize,
        --the theme's selection grey is lost on the backing's black.
        selectedColor = "#3a78d8",
        textAlignment = "left",
        --blank rather than the default "Enter text...", which is wider
        --than the box.
        placeholderText = "",
        characterLimit = 5,
        numeric = true,
        selectAllOnFocus = true,
        hoverCursor = "text",
        captureEscape = false,
        escapePriority = EscapePriority.EXIT_DIALOG,
        --a click inside the box is for the box, not for turning the card.
        click = function(element) end,
        escape = function(element)
            Close()
            gui.SetFocus(nil)
        end,
        focus = function(element)
            m_focused = true
        end,
        defocus = function(element)
            if not m_focused then
                return
            end
            m_focused = false
            --a frame later: change also fires on focus loss and must run
            --first, and a click inside the box defocuses and refocuses it.
            dmhub.Schedule(0.01, function()
                if mod.unloaded or not element.valid then
                    return
                end
                if m_focused or not m_open then
                    return
                end
                Close()
            end)
        end,
        edit = function(element)
            if m_open then
                Mirror()
            end
        end,
        change = function(element)
            if not m_open then
                return
            end
            local value = tonumber(element.text)
            --still focused: ctrl+scroll stepped it (numeric), and the edit goes on.
            if element.hasInputFocus then
                if value ~= nil then
                    args.apply(math.floor(value))
                end
                element.textNoNotify = tostring(args.current() or "")
                Mirror()
                return
            end
            if value ~= nil then
                args.apply(math.floor(value))
            end
            Close()
        end,
    }

    label:AddChild(frame)
    label:AddChild(entry)

    target.interactable = true
    if target.events == nil then
        target.events = {}
    end
    target.events.hover = function(element)
        m_hover = true
        UpdateFrame()
    end
    target.events.dehover = function(element)
        m_hover = false
        UpdateFrame()
    end
    target.events.click = function(element)
        local current = args.current()
        if m_open or current == nil then
            return
        end
        audio.FireSoundEvent("Mouse.Click")
        entry.textNoNotify = tostring(current)
        label.text = tostring(current)
        --room to type a few more digits without the text scrolling in the box,
        --and for the engine's inset around an input's text.
        entry.selfStyle.width = label.renderedWidth + args.fontSize * 3
        entry.selfStyle.height = label.renderedHeight + INPUT_INSET_Y * 2
        label.selfStyle.opacity = 0
        entry:SetClass("collapsed", false)
        entry.captureEscape = true
        m_open = true
        m_focused = false
        UpdateFrame()
        --a frame later: the box is still collapsed as far as the engine
        --knows, so focusing it now does not stick.
        dmhub.Schedule(0.01, function()
            if mod.unloaded then
                return
            end
            if m_open and entry.valid then
                gui.SetFocus(entry)
            end
        end)
    end
    --a wheel handler takes every notch over the number, ctrl or not.
    target.events.wheel = function(element, delta)
        if not dmhub.modKeys["ctrl"] then
            return
        end
        local current = args.current()
        if current == nil then
            return
        end
        args.apply(math.floor(current) + cond(delta > 0, 1, -1))
        if m_open then
            entry.textNoNotify = tostring(args.current() or "")
            Mirror()
        else
            ShowValue()
            UpdateFrame()
            gui.AfterLayout(FitFrame)
        end
    end

    return entry
end

--The stamina bar: the character panel's health bar in miniature -- a
--theme-bordered track whose border and fill both track the
--healthy/winded/dying state (success/warning/danger, the documented
--stamina tiers), with a glossy vertical gradient on the fill, the
--cur/max numbers centered in white, and a temp-stamina segment in the
--accent color riding the end of the fill when the hero has any.
--
--A change in stamina slides the fill over ~0.3-0.7s (the numbers count
--with it). Real damage (a new damage entry) also fires the generic hit
--sound and "staminaLost" up the hierarchy so the card it sits on can flash
--red; real healing that raises Stamina fires the heal sound and
--"staminaGained" (green). A Stamina set by hand or a new maximum only slides.
--
--opts (optional): height (default 14) and fontSize for the numbers, for a
--bar drawn larger than the card's (the hero sheet's). editable: a click on
--the numbers swaps them for an entry box holding the current Stamina, and
--enter sets it (the Director or the creature's controller only).
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
    --the recovery preview (a hero with a Recovery to spend, below max): one
    --Recovery's worth from current Stamina (from 0 while dying), amber when
    --some would be wasted past max. A floating layer of its own, under temp
    --Stamina, so temp keeps riding the end of the fill. recLead is the
    --clear gap up to where the preview starts. Colours set directly (not by
    --class) so the bar reads the same on the hero sheet, outside the card.
    local recLead = gui.Panel{
        width = "0%",
        height = "100%-2",
        valign = "center",
        halign = "left",
        lmargin = 1,
        interactable = false,
    }
    local recFill = gui.Panel{
        width = "0%",
        height = "100%-2",
        valign = "center",
        halign = "left",
        bgimage = "panels/square.png",
        bgcolor = RECOVERY_PREVIEW_FITS,
        interactable = false,
    }
    local recLayer = gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        flow = "horizontal",
        interactable = false,
        recLead,
        recFill,
    }
    --the numbers. An editable bar splits off the current Stamina
    --(currentLabel), which is edited where it stands; numbers then takes the
    --mouse for the whole bar.
    ---@type Label|nil
    local currentLabel = nil
    ---@type Label
    local restLabel
    ---@type Panel
    local numbers
    if opts.editable then
        local function Part()
            return gui.Label{
                classes = {"eotwBarLabel"},
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                textAlignment = "left",
                fontSize = opts.fontSize,
                text = "",
                interactable = false,
            }
        end
        currentLabel = Part()
        restLabel = Part()
        numbers = gui.Panel{
            floating = true,
            width = "100%",
            height = "100%",
            bgimage = "panels/square.png",
            bgcolor = "#00000000",
            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
                flow = "horizontal",
                interactable = false,
                currentLabel,
                restLabel,
            },
        }
    else
        restLabel = gui.Label{
            classes = {"eotwBarLabel"},
            floating = true,
            halign = "center",
            valign = "center",
            fontSize = opts.fontSize,
            text = "",
            interactable = false,
        }
        numbers = restLabel
    end

    --what the fill is drawn at right now, easing toward the true fraction
    --(m_targetPct). nil until the first refresh, which snaps: a card built
    --mid-encounter must not animate up from empty.
    local m_shownPct = nil
    local m_targetPct = 0
    --the clock for the slide, and the marker that one is running.
    local m_slideTime = nil
    --the values the numbers read.
    local m_cur, m_max, m_temp = 0, 0, 0
    --what one Recovery would heal now, or nil when there's no preview (not a
    --hero, no Recovery left, at max, or dead).
    ---@type number|nil
    local m_heal = nil
    --the creature's damage and heal entries at the last refresh, with the
    --largest amounts seen. Only a new or bigger one plays a sound.
    --- @type nil|table<string, {damage: number, heal: number}>
    local m_seenEntries = nil
    --Stamina at the last refresh, so a heal sounds only when it went up.
    --- @type nil|number
    local m_seenCur = nil
    --how much of the stamina the local user may see (StaminaDisplayFor).
    local m_display = "val"

    --who may type a new Stamina: whoever can see the exact numbers and also
    --controls the creature (or the Director), where card edits are allowed.
    local function CanEdit(tok)
        if tok == nil or not tok.valid or tok.properties == nil then
            return false
        end
        if not CardEditsAllowed() or StaminaDisplayFor(tok) ~= "val" then
            return false
        end
        local control = false
        pcall(function() control = tok.canControl == true end)
        return dmhub.isDM or control
    end

    --the entry box for opts.editable; nil when not editable.
    ---@type Input|nil
    local entry = nil
    --paints the bar from m_shownPct; set further down.
    ---@type fun()
    local Paint
    if currentLabel ~= nil then
        entry = CreateNumberEntry{
            label = currentLabel,
            target = numbers,
            fontSize = opts.fontSize or 10,
            refreshText = function() Paint() end,
            current = function()
                local tok = dmhub.GetCharacterById(charid)
                if not CanEdit(tok) then
                    return nil
                end
                ---@cast tok -nil
                return tok.properties:CurrentHitpoints()
            end,
            apply = function(value)
                local tok = dmhub.GetCharacterById(charid)
                if not CanEdit(tok) then
                    return
                end
                ---@cast tok -nil
                --only heroes go below zero; they keep counting down while dying.
                local hero = false
                pcall(function() hero = tok.properties:IsHero() == true end)
                if value < 0 and not hero then
                    return
                end
                if value == tok.properties:CurrentHitpoints() then
                    return
                end
                tok:ModifyProperties{
                    description = "Set Stamina",
                    execute = function()
                        tok.properties:SetStaminaDirect(value)
                    end,
                }
            end,
        }
    end

    --paint the two fills and the numbers from m_shownPct.
    Paint = function()
        local pct = m_shownPct or 0
        fill.selfStyle.width = string.format("%f%%", pct * 98)
        local tempPct = 0
        if m_max > 0 and m_temp > 0 then
            tempPct = math.min(1 - pct, m_temp / m_max)
        end
        tempFill.selfStyle.width = string.format("%f%%", tempPct * 98)
        --the recovery preview: from the fill's end (it slides with the
        --fill), or from 0 while dying, to where one Recovery would land.
        local recStart, recWidth, recOver = 0, 0, false
        if m_heal ~= nil and m_heal > 0 and m_display == "val" and m_max > 0 and m_cur + m_heal > 0 then
            local finish
            if m_cur > 0 then
                recStart = pct
                finish = pct + m_heal / m_max
            else
                finish = (m_cur + m_heal) / m_max
            end
            recWidth = math.max(0, math.min(1, finish) - recStart)
            recOver = m_cur + m_heal > m_max
        end
        recLead.selfStyle.width = string.format("%f%%", recStart * 98)
        recFill.selfStyle.width = string.format("%f%%", recWidth * 98)
        recFill.selfStyle.bgcolor = cond(recOver, RECOVERY_PREVIEW_OVER, RECOVERY_PREVIEW_FITS)
        --mid-slide the number counts with the bar; once it lands the true
        --value shows. Only while stamina is positive: a dying hero's is
        --negative while the bar is pinned empty, and counting down to that
        --through the fraction would not reach it.
        local shown = m_cur
        if m_shownPct ~= m_targetPct and m_cur > 0 then
            shown = math.ceil(pct * m_max)
        end
        local current, rest = "", ""
        if m_display == "val" then
            current = string.format("%d", shown)
            rest = string.format("/%d", m_max)
            if m_temp > 0 then
                rest = string.format("%s +%d", rest, m_temp)
            end
        elseif m_display == "pct" then
            rest = string.format("%d%%", round(100 * pct + 100 * m_temp / m_max))
        end
        if currentLabel == nil then
            restLabel.text = current .. rest
            return
        end
        restLabel.text = rest
        --while it is edited it reads what is typed.
        if entry == nil or entry:HasClass("collapsed") then
            currentLabel.text = current
        end
    end

    --the visible bar. It sits in a plain holder that keeps the logic, so
    --hiding it ("none", StaminaDisplayFor) never stops the refresh or the
    --slide's think, which would leave it hidden for good.
    local track = gui.Panel{
        classes = {"bordered"},
        width = "100%",
        height = "100%",
        flow = "horizontal",
        halign = "center",
        cornerRadius = 2,
        bgimage = true,
        bgcolor = "#00000066",
        interactable = false,
        fill,
        recLayer,
        tempFill,
        numbers,
    }

    return gui.Panel{
        width = "100%",
        height = opts.height or 14,
        halign = "center",
        interactable = false,
        track,

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
            m_shownPct, m_seenEntries, m_seenCur, m_slideTime = nil, nil, nil, nil
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
            m_heal = nil
            if cur < max and not IsCardHeroDead(tok) then
                pcall(function()
                    if c:IsHero() then
                        local id = CharacterResource.recoveryResourceId
                        local left = (c:GetResources()[id] or 0) - (c:GetResourceUsage(id, "long") or 0)
                        if left > 0 then
                            m_heal = tonumber(c:RecoveryAmount())
                        end
                    end
                end)
            end
            m_targetPct = math.max(0, math.min(1, cur / max))
            m_display = StaminaDisplayFor(tok)
            track:SetClass("collapsed", m_display == "none")

            --damage or healing that just happened (an entry new to this bar or
            --grown, and fresh): one hit and one heal sound however many landed.
            --A hit soaked by Temp Stamina still records an entry.
            local entries = {}
            pcall(function() entries = c:try_get("damageEntries", {}) end)
            local firstRefresh = m_seenEntries == nil
            local seen = {}
            local hurt, healed = 0, 0
            --the newest entry of each kind names the sound for FireCardSound,
            --so two cards on the same Hero pick the same one.
            local hurtPick, healPick = nil, nil
            local function Newer(pick, id, age)
                return pick == nil or age < pick.age or (age == pick.age and tostring(id) < pick.id)
            end
            for id, entry in pairs(entries) do
                local damage = tonumber(entry.damage) or 0
                local heal = tonumber(entry.heal) or 0
                local before = (m_seenEntries or {})[id] or {damage = 0, heal = 0}
                seen[id] = {damage = math.max(damage, before.damage), heal = math.max(heal, before.heal)}
                local age = TimestampAgeInSeconds(entry.timestamp)
                if not firstRefresh and age < CARD_ENTRY_FRESH then
                    local pick = {id = tostring(id), age = age, key = string.format("%s|%s|%s", tostring(id), tostring(damage), tostring(heal))}
                    if damage > before.damage then
                        hurt = hurt + damage - before.damage
                        if Newer(hurtPick, id, age) then
                            hurtPick = pick
                        end
                    end
                    if heal > before.heal then
                        healed = healed + heal - before.heal
                        if Newer(healPick, id, age) then
                            healPick = pick
                        end
                    end
                end
            end
            m_seenEntries = seen
            if hurtPick ~= nil then
                element:FireEventOnParents("staminaLost", hurt)
                FireCardSound(g_hurtSound, charid, hurtPick.key, "Attack.Hit")
            end
            --a heal at full Stamina records an entry but changes nothing: no
            --sound or flash unless the Hero's Stamina went up.
            if healPick ~= nil and m_seenCur ~= nil and cur > m_seenCur then
                element:FireEventOnParents("staminaGained", healed)
                FireCardSound(g_healSound, charid, healPick.key, "Ability.Heal_Generic")
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
            track:SetClass("borderSuccess", not winded and not dying)
            track:SetClass("borderWarning", winded and not dying)
            track:SetClass("borderDanger", dying)
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

--The hero whose heroic resource this user may change from a card: a hero or
--companion's controller (or the Director), where card edits are allowed.
--nil when they may not.
--- @param charid string
--- @return CharacterToken|nil
local function HeroResourceEditableToken(charid)
    local tok = dmhub.GetCharacterById(charid)
    if tok == nil or not tok.valid or tok.properties == nil or not CardEditsAllowed() then
        return nil
    end
    local ok = false
    pcall(function()
        ok = (dmhub.isDM or tok.canControl == true)
            and (tok.properties:IsHero() or tok.properties:IsCompanion())
    end)
    if not ok then
        return nil
    end
    return tok
end

--The heroic resource to start an edit from; nil when it may not be edited
--(a CreateNumberEntry's current).
--- @param charid string
--- @return number|nil
local function HeroResourceCurrent(charid)
    local tok = HeroResourceEditableToken(charid)
    if tok == nil then
        return nil
    end
    return tok.properties:GetHeroicOrMaliceResources()
end

--Sets a hero's heroic resource as the character panel does: clamped to what
--the resource allows, then refreshed or consumed by the difference.
--- @param charid string
--- @param value integer
local function SetHeroResource(charid, value)
    local tok = HeroResourceEditableToken(charid)
    if tok == nil then
        return
    end
    local resource = dmhub.GetTable(CharacterResource.tableName)[CharacterResource.heroicResourceId]
    local amount = value
    if resource ~= nil then
        amount = resource:ClampQuantity(tok.properties, value)
    end
    local diff = amount - tok.properties:GetHeroicOrMaliceResources()
    if diff == 0 then
        return
    end
    tok:ModifyProperties{
        description = "Change Heroic Resource",
        execute = function()
            if diff > 0 then
                tok.properties:RefreshResource(CharacterResource.heroicResourceId, "unbounded", diff)
            else
                tok.properties:ConsumeResource(CharacterResource.heroicResourceId, "unbounded", -diff)
            end
        end,
    }
end

--Sets a hero's surges as the character panel does; ConsumeSurges routes a
--shared pool (a summoner's, a mentor's) to its owner.
--- @param charid string
--- @param value integer
local function SetHeroSurges(charid, value)
    local tok = HeroResourceEditableToken(charid)
    if tok == nil then
        return
    end
    local diff = math.max(0, value) - tok.properties:GetAvailableSurges()
    if diff == 0 then
        return
    end
    tok:ModifyProperties{
        description = "Change Surges",
        execute = function()
            tok.properties:ConsumeSurges(-diff, creature.manualSurgeNote)
        end,
    }
end

--The hero whose Victories this user may change from a card: as
--HeroResourceEditableToken, but heroes only (companions have none).
--- @param charid string
--- @return CharacterToken|nil
local function HeroVictoriesEditableToken(charid)
    local tok = HeroResourceEditableToken(charid)
    if tok == nil or not tok.properties:IsHero() then
        return nil
    end
    return tok
end

--- @param charid string
--- @param value integer
local function SetHeroVictories(charid, value)
    local tok = HeroVictoriesEditableToken(charid)
    if tok == nil then
        return
    end
    local n = math.max(0, value)
    if n == tok.properties:GetVictories() then
        return
    end
    tok:ModifyProperties{
        description = "Set Victories",
        execute = function()
            tok.properties:SetVictories(n)
        end,
    }
end

--One count on the resource row: an icon and the number beside it.
--args: icon (fun(props) -> image or nil, which hides the icon); value
--(fun(props) -> number or text, or nil to hide the count); tooltip
--(fun(props) -> string); current, apply (CreateNumberEntry's, only when
--editable); lmargin, halign.
--- @param charid string
--- @param editable boolean
--- @param args table
local function CreateResourceCount(charid, editable, args)
    --one size for every count, small enough that three fit across the card.
    --With a fourth showing, the row makes them all compact (setCompact).
    local iconSize, compactIconSize = 18, 13
    local fontSize, compactFontSize = 17, 13
    local m_compact = false
    --the space before this count; compact counts sit closer together.
    local function Gap()
        local gap = args.lmargin or 0
        return cond(m_compact, gap / 2, gap)
    end
    local icon = gui.Panel{
        classes = {"eotwResIcon"},
        width = iconSize,
        height = iconSize,
        --takes the mouse so this tooltip can show; with no click handler,
        --clicks still reach the card.
        linger = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok ~= nil and tok.valid and tok.properties ~= nil then
                local text = nil
                pcall(function() text = args.tooltip(tok.properties) end)
                if text ~= nil then
                    gui.Tooltip(text)(element)
                end
            end
        end,
    }
    ---@type Input|nil
    local entry = nil
    local valueLabel = gui.Label{
        classes = {"eotwResValue"},
        fontSize = fontSize,
        lmargin = 4,
        text = "0",
        interactable = false,
    }
    ---@type CardNumberEntryArgs
    local entryArgs = {
        label = valueLabel,
        fontSize = fontSize,
        current = args.current,
        apply = args.apply,
    }
    if editable then
        entry = CreateNumberEntry(entryArgs)
    end
    return gui.Panel{
        width = "auto",
        height = "100%",
        flow = "horizontal",
        halign = args.halign or "left",
        valign = "center",
        lmargin = args.lmargin or 0,
        data = { shown = false },
        setCompact = function(element, compact)
            m_compact = compact
            local size = cond(compact, compactIconSize, iconSize)
            local textSize = cond(compact, compactFontSize, fontSize)
            icon.selfStyle.width = size
            icon.selfStyle.height = size
            valueLabel.selfStyle.fontSize = textSize
            valueLabel.selfStyle.lmargin = cond(compact, 2, 4)
            if entry ~= nil then
                entryArgs.fontSize = textSize
                entry.selfStyle.fontSize = textSize
            end
            if element.data.shown then
                element.selfStyle.lmargin = Gap()
            end
        end,
        refreshCard = function(element)
            local tok = dmhub.GetCharacterById(charid)
            if tok == nil or not tok.valid or tok.properties == nil then
                return
            end
            local props = tok.properties
            local value = nil
            pcall(function() value = args.value(props) end)
            --the count itself stays visible: a collapsed panel gets no
            --refreshCard, so it could never come back.
            valueLabel:SetClass("collapsed", value == nil)
            element.selfStyle.lmargin = cond(value == nil, 0, Gap())
            local shown = value ~= nil
            if shown ~= element.data.shown then
                element.data.shown = shown
                --the row counts what shows, to decide whether all must shrink.
                element:FireEventOnParents("resourceCountsChanged")
            end
            if value == nil then
                icon:SetClass("collapsed", true)
                return
            end
            icon:SetClass("collapsed", false)
            local image = nil
            pcall(function() image = args.icon(props) end)
            icon:SetClass("hidden", image == nil)
            if image ~= nil then
                icon.selfStyle.bgimage = image
            end
            --while it is edited it reads what is typed.
            if entry == nil or entry:HasClass("collapsed") then
                valueLabel.text = tostring(value)
            end
        end,
        icon,
        valueLabel,
    }
end

--true for a hero or a companion: the creatures the row's surges are for.
local function IsHeroOrCompanion(props)
    return props:IsHero() or props:IsCompanion()
end

--the card shows surges only in combat (the test HeroCardBack's CurrentMode uses).
local function InCombat()
    local q = dmhub.initiativeQueue
    return q ~= nil and not q.hidden
end

--- Resource readouts --------------------------------------------------------

--Extra counts on the resource row, for classes with more than one heroic
--resource. Kept across reloads of this file, because mods register once when
--they load and their readouts would otherwise vanish.
local g_resourceReadouts = {}
do
    local previous = rawget(_G, "EotwHeroCard")
    if type(previous) == "table" and type(previous.resourceReadouts) == "table" then
        g_resourceReadouts = previous.resourceReadouts
    end
end

--- Add a readout to the resource row on every hero card, after the heroic
--- resource and surges, for a class with a second heroic resource.
--- Registering an id again replaces it. Register when your mod loads: a card
--- already on screen shows a new readout only once it is rebuilt.
---   id    unique key
---   ord   sort order among readouts (default 0, lower is further left)
---   read  function(tok) -> nil to show nothing for this hero, or
---         { icon = image id, text = "4/6", tooltip = optional hover text }
---         It runs on every card refresh, so keep it cheap; if it errors,
---         the readout is hidden.
--- @param entry {id: string, ord: nil|number, read: fun(tok: CharacterToken): nil|{icon: string, text: string, tooltip: nil|string}}
local function RegisterResourceReadout(entry)
    g_resourceReadouts[entry.id] = entry
end

--The registered readouts in ord order, then by id so the order is stable.
local function SortedResourceReadouts()
    local result = {}
    for _, entry in pairs(g_resourceReadouts) do
        result[#result+1] = entry
    end
    table.sort(result, function(left, right)
        local leftOrd, rightOrd = left.ord or 0, right.ord or 0
        if leftOrd ~= rightOrd then
            return leftOrd < rightOrd
        end
        return left.id < right.id
    end)
    return result
end

--One registered readout, drawn as a count on the resource row. Its icon,
--value and tooltip each call read again, finding the readout by id so a
--re-registration takes over; an error or nil hides the count.
--- @param charid string
--- @param id string
local function CreateResourceReadout(charid, id)
    local function Read()
        local entry = g_resourceReadouts[id]
        local tok = dmhub.GetCharacterById(charid)
        if entry == nil or tok == nil or not tok.valid then
            return nil
        end
        local ok, shown = pcall(entry.read, tok)
        if ok and type(shown) == "table" then
            return shown
        end
        return nil
    end
    return CreateResourceCount(charid, false, {
        lmargin = 8,
        value = function()
            local shown = Read()
            return shown ~= nil and shown.text or nil
        end,
        icon = function()
            local shown = Read()
            return shown ~= nil and shown.icon or nil
        end,
        tooltip = function()
            local shown = Read()
            return shown ~= nil and shown.tooltip or nil
        end,
    })
end

--The resource row under the stamina bar: the heroic resource (the class's
--own icon, from the character panel's source), surges (in combat only) and
--any registered readouts at the left; the hero's Victories at the right.
--editable: a click on a number opens a box to type a new one (the Director
--or the hero's controller, where CardEditsAllowed).
local function CreateResourceRow(charid, editable)
    local heroic = CreateResourceCount(charid, editable, {
        icon = function(props)
            local classInfo = props:GetClass()
            return classInfo ~= nil and classInfo:try_get("heroicResourceIcon") or nil
        end,
        value = function(props)
            return props:GetHeroicOrMaliceResources() or 0
        end,
        tooltip = function(props)
            return props:GetHeroicResourceName() or T("herocard.heroic_resource.fallback")
        end,
        current = function() return HeroResourceCurrent(charid) end,
        apply = function(value) SetHeroResource(charid, value) end,
    })
    local surges = CreateResourceCount(charid, editable, {
        lmargin = 8,
        icon = function(props) return "game-icons/surge.png" end,
        value = function(props)
            if not InCombat() then
                return nil
            end
            local n = props:GetAvailableSurges() or 0
            --a monster shows its surges only when it has some.
            if n == 0 and not IsHeroOrCompanion(props) then
                return nil
            end
            return n
        end,
        tooltip = function(props)
            local n = props:GetAvailableSurges() or 0
            local damage = 0
            local sheet = rawget(_G, "EotwHeroSheet")
            local tok = dmhub.GetCharacterById(charid)
            if sheet ~= nil and tok ~= nil then
                local d = sheet.Data(tok, {"resource"})
                damage = d ~= nil and d.surgeDamage or 0
            end
            return TP("herosheet.card.surges_tip", n, { damage = string.format("%d", damage) })
        end,
        current = function()
            local tok = HeroResourceEditableToken(charid)
            return tok ~= nil and tok.properties:GetAvailableSurges() or nil
        end,
        apply = function(value) SetHeroSurges(charid, value) end,
    })
    local victories = CreateResourceCount(charid, editable, {
        halign = "right",
        icon = function(props) return "drawsteel/HeroicResources/T_UI_ICON_FLAT_HR_VICTORY.png" end,
        value = function(props)
            if not props:IsHero() then
                return nil
            end
            return props:GetVictories() or 0
        end,
        tooltip = function(props)
            return T("herosheet.card.victories_tip", {
                victories = string.format("%d", props:GetVictories() or 0),
                resource = props:GetHeroicResourceName() or T("herosheet.card.resource_fallback"),
            })
        end,
        current = function()
            local tok = HeroVictoriesEditableToken(charid)
            return tok ~= nil and tok.properties:GetVictories() or nil
        end,
        apply = function(value) SetHeroVictories(charid, value) end,
    })
    local children = { heroic, surges }
    for _, entry in ipairs(SortedResourceReadouts()) do
        children[#children+1] = CreateResourceReadout(charid, entry.id)
    end
    children[#children+1] = victories
    return gui.Panel{
        width = "100%",
        height = RESOURCE_ROW_HEIGHT,
        flow = "horizontal",
        halign = "left",
        valign = "center",
        data = { compact = false },
        --more than three counts showing do not fit at full size: shrink them
        --all, and grow them back once one hides again.
        resourceCountsChanged = function(element)
            local shown = 0
            for _, count in ipairs(element.children) do
                if count.data.shown then
                    shown = shown + 1
                end
            end
            local compact = shown > 3
            if compact ~= element.data.compact then
                element.data.compact = compact
                for _, count in ipairs(element.children) do
                    count:FireEvent("setCompact", compact)
                end
            end
        end,
        children = children,
    }
end

--forward-declared: the circle's click and the "+" button both spend one.
local SpendableRecovery
local SpendRecovery

--The recoveries circle: the hero's remaining recoveries (max minus the
--ones spent this long rest), in a small ringed disc. The ring turns red
--when none are left. Hidden from anyone who may not see the hero's exact
--Stamina (StaminaDisplayFor); barHolder then takes the circle's room.
--spendOnClick: a click on the circle spends one (SpendRecovery).
local function CreateRecoveriesCircle(charid, barHolder, spendOnClick)
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
            local hide = StaminaDisplayFor(tok) ~= "val"
            if hide ~= element:HasClass("collapsed") then
                element:SetClass("collapsed", hide)
                barHolder.selfStyle.width = cond(hide, "100%", "100%-25")
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
            local stamina, maxStamina = 0, 0
            pcall(function()
                local c = tok.properties
                local id = CharacterResource.recoveryResourceId
                max = c:GetResources()[id] or 0
                local used = c:GetResourceUsage(id, "long") or 0
                current = math.max(0, max - used)
                recoveryValue = c:RecoveryAmount()
                stamina, maxStamina = c:CurrentHitpoints(), c:MaxHitpoints()
            end)
            local lines = {
                T("herocard.recoveries.tooltip_count", { current = string.format("%d", current), max = string.format("%d", max) }),
            }
            if recoveryValue ~= nil then
                lines[#lines+1] = T("herocard.recoveries.tooltip_value", { value = string.format("%d", recoveryValue) })
            end
            --what spending one now would do, as the bar's preview shows it.
            local heal = tonumber(recoveryValue) or 0
            if current > 0 and heal > 0 and stamina < maxStamina then
                local from, to = string.format("%d", stamina), string.format("%d", math.min(maxStamina, stamina + heal))
                local wasted = stamina + heal - maxStamina
                if wasted > 0 then
                    lines[#lines+1] = T("herocard.recovery.preview_over", { from = from, to = to, wasted = string.format("%d", wasted) })
                else
                    lines[#lines+1] = T("herocard.recovery.preview", { from = from, to = to })
                end
            end
            gui.Tooltip(table.concat(lines, "\n"))(element)
        end,
        click = spendOnClick and function(element)
            if not CardEditsAllowed() then
                return
            end
            SpendRecovery(charid)
            element:FireEvent("refreshCard")
        end or nil,
    }
end

--Can the local user spend one of this hero's Recoveries right now? They
--must control the hero, be below max Stamina and have a Recovery left.
--Returns the Stamina it would give, or nil.
SpendableRecovery = function(tok)
    if tok == nil or not tok.valid or tok.properties == nil or IsCardHeroDead(tok) then
        return nil
    end
    local mine = nil
    pcall(function() mine = tok.canControlAsUser end)
    if mine == nil then
        pcall(function() mine = tok.canControl end)
    end
    if mine ~= true then
        return nil
    end
    local amount = nil
    pcall(function()
        local c = tok.properties
        local id = CharacterResource.recoveryResourceId
        local left = (c:GetResources()[id] or 0) - (c:GetResourceUsage(id, "long") or 0)
        if left > 0 and c:CurrentHitpoints() < c:MaxHitpoints() then
            amount = c:RecoveryAmount()
        end
    end)
    return amount
end

--Spends one of the hero's Recoveries for Recovery-value Stamina, if
--SpendableRecovery allows it; otherwise does nothing.
--- @param charid string
SpendRecovery = function(charid)
    local tok = dmhub.GetCharacterById(charid)
    if SpendableRecovery(tok) == nil then
        return
    end
    ---@cast tok -nil
    audio.FireSoundEvent("Mouse.Click")
    tok:ModifyProperties{
        description = "Use Recovery",
        execute = function()
            local props = tok.properties
            props:Heal(props:RecoveryAmount(), "Use Recovery")
            props:ConsumeResource(CharacterResource.recoveryResourceId, "long", 1, "Used Recovery")
        end,
    }
end

--The small "+" beside the recoveries circle: spends one Recovery to regain
--Recovery-value Stamina, no action needed (EotW montages and the screens
--before a fight). Collapsed whenever SpendableRecovery says no; barHolder
--gives up the button's room while it shows.
local function CreateSpendRecoveryButton(charid, barHolder)
    return gui.Panel{
        classes = {"eotwSpendRecovery", "collapsed"},
        --Keep the press from reaching the card, which opens the character panel.
        swallowPress = true,
        refreshCard = function(element)
            local show = SpendableRecovery(dmhub.GetCharacterById(charid)) ~= nil
            if show ~= not element:HasClass("collapsed") then
                element:SetClass("collapsed", not show)
                barHolder.selfStyle.width = cond(show, "100%-48", "100%-25")
            end
        end,
        linger = function(element)
            local amount = SpendableRecovery(dmhub.GetCharacterById(charid))
            if amount ~= nil then
                gui.Tooltip(T("herocard.recoveries.spend_tooltip", { amount = string.format("%d", amount) }))(element)
            end
        end,
        press = function(element)
            SpendRecovery(charid)
            element:FireEvent("refreshCard")
        end,
        gui.Label{ classes = {"eotwSpendRecoveryLabel"}, text = "+", interactable = false },
    }
end

--The hero card's stamina row: the recoveries circle on the left, the
--stamina bar filling the rest. The bar keeps firing staminaLost /
--staminaGained up through this row to the card. noRecoveries drops the
--circle (a monster or NPC card: they have no recoveries). spendRecovery
--adds the "+" that spends one (CreateSpendRecoveryButton). clickToEdit: a
--click on the Stamina numbers edits them, and one on the circle spends a
--Recovery.
local function CreateStaminaRow(charid, noRecoveries, spendRecovery, clickToEdit)
    local barOpts = CARD_STAMINA_BAR
    if clickToEdit then
        barOpts = { height = CARD_STAMINA_BAR.height, fontSize = CARD_STAMINA_BAR.fontSize, editable = true }
    end
    if noRecoveries then
        return gui.Panel{
            width = "100%",
            height = STAMINA_ROW_HEIGHT,
            halign = "center",
            valign = "center",
            interactable = false,
            CreateStaminaBar(charid, barOpts),
        }
    end
    local barHolder = gui.Panel{
        width = "100%-25",
        height = "auto",
        valign = "center",
        interactable = false,
        CreateStaminaBar(charid, barOpts),
    }
    ---@type Panel[]
    local children = { CreateRecoveriesCircle(charid, barHolder, clickToEdit == true) }
    if spendRecovery then
        children[#children+1] = CreateSpendRecoveryButton(charid, barHolder)
    end
    children[#children+1] = barHolder
    return gui.Panel{
        width = "100%",
        height = STAMINA_ROW_HEIGHT,
        flow = "horizontal",
        halign = "center",
        valign = "center",
        interactable = false,
        children = children,
    }
end

--One surge icon PER available surge, in the card's bottom-right corner --
--and nothing at all when the hero has none or combat is not running. Only on
--cards with no resource row. Rebuilt only when the count changes; display
--capped at 9 icons (they would outgrow the card).
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
            if InCombat() then
                pcall(function() surges = tok.properties:GetAvailableSurges() or 0 end)
            end
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
            gui.Tooltip(T("herocard.intelligence.tooltip", { count = string.format("%d", element.data.count) }))(element)
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
            gui.Tooltip(TP("herocard.downtime.tooltip", element.data.count))(element)
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
            local tip = T("herocard.trigger.tooltip", { hero = name })
            if #lines > 0 then
                tip = T("herocard.trigger.tooltip_list", { hero = name, triggers = table.concat(lines, "\n") })
            end
            badge.data.tooltipText = tip
            element:SetClass("collapsed", false)
        end,
        badge,
    }
end

--A speech balloon on the card's left edge, half outside it, while this
--hero's player is talking on Discord voice, and for the same short linger
--after as the token's Talk emote (DiscordVoice.IsTokenSpeaking). It polls
--on its own think because the card's refreshCard comes only about once a
--second, far too slow to follow speech. The think sits on an invisible
--holder because a collapsed or hidden panel does not think.
local function CreateVoiceBalloon(charid)
    local balloon = gui.Panel{
        classes = {"eotwVoiceBalloon", "collapsed"},
        width = 26,
        height = 26,
        cornerRadius = 13,
        bgimage = "panels/square.png",
        interactable = false,
        gui.Panel{
            classes = {"eotwVoiceBalloonIcon"},
            width = 16,
            height = 16,
            halign = "center",
            valign = "center",
            bgimage = "phosphor/chat-circle-dots-fill.png",
            interactable = false,
        },
    }
    return gui.Panel{
        floating = true,
        halign = "left",
        valign = "top",
        x = -12,
        y = 30,
        width = 26,
        height = 26,
        interactable = false,
        thinkTime = 0.1,
        think = function(element)
            local voice = rawget(_G, "DiscordVoice")
            local speaking = voice ~= nil and voice.IsTokenSpeaking(charid)
            balloon:SetClass("collapsed", not speaking)
        end,
        balloon,
    }
end

--MONTAGE ONLY (opts.showStats). The five characteristics down the card's
--right edge, one chip each, initial + score ("M +2") so the whole set fits
--in the artwork's margin. Ordered by the attribute's own `order` (Might,
--Agility, Reason, Intuition, Presence -- MARIP), read from the game system
--rather than hardcoded so a system with other characteristics still works.
--artworkHeight: the card's height above its overlay plate. The chips shrink
--to fit in it under the condition chips, so a taller plate never puts the
--last one over the name.
--- @param charid string
--- @param artworkHeight number
--- @return Panel
local function CreateStatStrip(charid, artworkHeight)
    local attrList = {}
    for _, info in pairs(creature.attributesInfo) do
        attrList[#attrList+1] = info
    end
    table.sort(attrList, function(a, b) return a.order < b.order end)

    local rowSpace = math.floor((artworkHeight - STAT_STRIP_Y) / math.max(1, #attrList))
    local chipHeight = math.min(STAT_ROW_HEIGHT, rowSpace - STAT_ROW_GAP)

    local rows = {}
    for _, info in ipairs(attrList) do
        local attrid = info.id
        local initial = string.sub(info.description, 1, 1)
        rows[#rows+1] = gui.Panel{
            classes = {"eotwStatChip"},
            height = chipHeight,
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

    --below the first row of condition chips (top-right); chipHeight ends it
    --above the overlay.
    return gui.Panel{
        floating = true,
        halign = "right",
        valign = "top",
        x = -3,
        y = STAT_STRIP_Y,
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
    pcall(function() rect = CardPortraitRect(tok, aspect, portrait) end)
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
--  spendRecovery  a small "+" beside the recoveries circle that spends one
--              Recovery for Stamina, shown only while the local user controls
--              a hurt hero with a Recovery left (the EotW montage, narrative
--              and prep stages: out of combat, so it costs no action)
--  showDowntime   the hammer chip with the hero's unspent Downtime
--              Activities (the town's cards; see CreateDowntimeBadge)
--  noRecoveries   no recoveries circle beside the stamina bar (a monster or
--              NPC card on the tabletop view's table, Tabletop.lua)
--  clickToEdit    a click on the Stamina numbers, the heroic resource,
--              surges or Victories opens a box to type a new value, and a
--              click on the recoveries circle spends one (the tabletop view's cards;
--              see CardEditsAllowed)
--  noTurnButton   no hover button to turn the card over: the host turns it
--              on a click instead (the tabletop view's cards)
--  dragBack, onTurn   passed to HeroCardBack.Decorate: the host drags the
--              turned card by its back, and places the card as it turns
--  displayName    function(tok) -> the name on the card (default: the
--              hero's name, "Unnamed Hero" when it has none)
--  extraChips  function(charid) -> a list of extra status chips to show
--              beside the condition icons, for states that are not real
--              conditions on the creature (the EotW narrative's Weary).
--              Each: { key, icon, tooltip, count (a corner badge when >= 2),
--              tint (icon colour), borderColor }. key must change whenever
--              the chip's look does; it is what rebuilds the row.
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
        y = CONDITION_ROW_Y,
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
            local extras = {}
            if opts.extraChips ~= nil then
                extras = opts.extraChips(charid) or {}
            end
            local parts = {}
            for _, cond in ipairs(entries) do
                --the ids ride in the signature because each chip's right-click
                --menu captures them: two effects can share an icon.
                parts[#parts+1] = string.format("%s:%s:%s", tostring(cond.icon), tostring(cond.condid), tostring(cond.effectid))
            end
            for _, chip in ipairs(extras) do
                parts[#parts+1] = tostring(chip.key or chip.icon)
            end
            local sig = table.concat(parts, "|")
            if sig == element.data.signature then
                return
            end
            element.data.signature = sig
            local icons = {}
            for _, chip in ipairs(extras) do
                local tooltip = chip.tooltip
                local count = tonumber(chip.count) or 0
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
                    borderColor = chip.borderColor or "#cc2222ff",
                    linger = function(iconElement)
                        if tooltip ~= nil then
                            gui.Tooltip(tooltip)(iconElement)
                        end
                    end,
                    gui.Panel{
                        width = CONDITION_ICON_SIZE,
                        height = CONDITION_ICON_SIZE,
                        halign = "center",
                        valign = "center",
                        bgimage = chip.icon,
                        bgcolor = chip.tint or "white",
                        interactable = false,
                    },
                    --how many (a double bane is "2"), in the chip's corner.
                    gui.Label{
                        classes = {cond(count >= 2, nil, "collapsed")},
                        floating = true,
                        halign = "right",
                        valign = "bottom",
                        x = 4,
                        y = 4,
                        width = 13,
                        height = 13,
                        fontSize = 10,
                        bold = true,
                        color = "#ffffff",
                        textAlignment = "center",
                        bgimage = "panels/square.png",
                        bgcolor = chip.borderColor or "#cc2222ff",
                        cornerRadius = 6,
                        text = tostring(count),
                        interactable = false,
                    },
                }
            end
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
                        if condid == nil and effectid == nil then
                            return
                        end
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
    overlayChildren[#overlayChildren+1] = CreateStaminaRow(charid, opts.noRecoveries, opts.spendRecovery == true, opts.clickToEdit == true)
    if showResources then
        overlayChildren[#overlayChildren+1] = CreateResourceRow(charid, opts.clickToEdit == true)
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
        valign = opts.valign,
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
        CreateTriggerCorner(charid),
        CreateIntelligenceBadge(charid, overlayHeight),
    }
    --without the resource row, the surges show in the corner instead.
    if not showResources then
        cardArgs[#cardArgs+1] = CreateSurgeCorner(charid)
    end
    if opts.showStats then
        cardArgs[#cardArgs+1] = CreateStatStrip(charid, artworkHeight)
    end
    if opts.showDowntime then
        cardArgs[#cardArgs+1] = CreateDowntimeBadge(charid)
    end
    --last, so the washes sit over every other layer of the card.
    cardArgs[#cardArgs+1] = deadMark
    cardArgs[#cardArgs+1] = hurtFlash
    cardArgs[#cardArgs+1] = healFlash
    --after the washes too, so a hurt flash does not tint the balloon.
    cardArgs[#cardArgs+1] = CreateVoiceBalloon(charid)
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
            hover = gui.Tooltip(opts.dismiss.tooltip or T("herocard.dismiss.tooltip")),
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
        cardBack.Decorate(cardArgs, charid, CARD_WIDTH, cardHeight, {
            noButton = opts.noTurnButton == true,
            dragBack = opts.dragBack == true,
            onTurn = opts.onTurn,
        })
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
    --for the card back's own click-to-edit heroic resource.
    CreateNumberEntry = CreateNumberEntry,
    HeroResourceCurrent = HeroResourceCurrent,
    SetHeroResource = SetHeroResource,
    RegisterResourceReadout = RegisterResourceReadout,
    --the registry itself, read back by the next load of this file.
    resourceReadouts = g_resourceReadouts,
    --the card's style rules; callers wrap them in their own MergeTokens /
    --MergeStyles so the theme tokens resolve for their cascade root.
    rules = g_heroCardRules,
    CARD_WIDTH = CARD_WIDTH,
    CARD_HEIGHT = CARD_HEIGHT,
}

--Encounter of the Week: the montage stage.
--
--The full-screen presentation every client sees while a montage beat plays:
--the scene as a backdrop, the round's Opportunities down the left and
--Threats down the right, the party's hero cards along the bottom (drag one
--onto an entry to approach it), and the current turn in the middle -- the
--approach text, the options with their power rolls, then the landed tier
--and what it did. After the last round the middle shows each unresolved
--threat in turn with the malice diamond and its consequence.
--
--Shown through GameHud's presented-dialog mechanism (the host presents it;
--every client, late joiners included, instantiates it from the shared
--presentdialog document). All state comes from EncounterMontage's document;
--this file never writes montage state, only requests.
--Design: EncounterOfTheWeek.md, "Encounter scripts: montage beats before combat".

local mod = dmhub.GetModLoading()

local T = UIText.T
local TP = UIText.Plural

--Launch-timing marker (see EncounterOfTheWeek.lua): grep Player.log for "[EOTWPROF]".
local function EotwProf(fmt, ...)
    local args = table.pack(...)
    pcall(function()
        printf("[EOTWPROF] server=%.3f app=%.3f " .. fmt, dmhub.serverTimeMilliseconds * 0.001, dmhub.Time(), table.unpack(args, 1, args.n))
    end)
end

--While the game's loading screen is held for this launch, the stage keeps it
--up until the whole party is in and the opening beat has opened
--(EncounterOfTheWeekGame.RevealReady), so it reveals every hero and the
--beat's unlocks at once. Renews the engine's hold while waiting; gives up
--after REVEAL_WAIT_MAX_SECONDS so a player who never arrives cannot trap the
--rest. True = keep waiting.
local REVEAL_WAIT_MAX_SECONDS = 45
local m_revealWaitStart = nil
local m_revealRenewAt = 0
local function HoldForParty()
    local held = false
    pcall(function() held = dmhub.loadingScreenHeld end)
    local eotw = rawget(_G, "EncounterOfTheWeekGame")
    if not held or eotw == nil or eotw.RevealReady() then
        m_revealWaitStart = nil
        return false
    end
    local now = dmhub.Time()
    if m_revealWaitStart == nil then
        m_revealWaitStart = now
        EotwProf("stage up; holding the loading screen for the party")
    end
    if now - m_revealWaitStart > REVEAL_WAIT_MAX_SECONDS then
        printf("EotW: the party was not all in after %d seconds; revealing the stage anyway", REVEAL_WAIT_MAX_SECONDS)
        m_revealWaitStart = nil
        return false
    end
    if now >= m_revealRenewAt then
        m_revealRenewAt = now + 5
        pcall(function() dmhub.HoldLoadingScreen() end)
    end
    return true
end

EncounterMontageStage = rawget(_G, "EncounterMontageStage") or {}

local DIALOG_ID = "eotwmontage"

local HEADER_HEIGHT = 76
--The montage header is auto-height so the intro prose can wrap; this is as
--far as it is allowed to push the body down (title + the intro's own
--maxHeight + the round line).
local HEADER_HEIGHT_MAX = 260
--where the right rail parks the malice / hero-token strip: the rail's top
--inset (IconRailTop, 64 at the default zoom) and its 12-unit edge margin.
--The stage covers the rail, so it shows the same strip in the same spot.
local POOLS_TOP = 64
local POOLS_RIGHT = 12
--The Tactical Preparation header carries the pool the party is about to
--spend under the title and instructions, so it is taller than the narrative's
--and the body below has to start further down -- at HEADER_HEIGHT the pool
--sat behind the top edge of the panel (reported 2026-09-20).
local PREP_HEADER_HEIGHT = 128
--a montage hero card (188 incl. its player line + its 46-tall skills block)
--plus one row of ally cards (80) and their gaps.
--budgets for the stats card at its 1.2 uiscale (EncounterOfTheWeekHud's
--STATS_CARD_UISCALE: 234 * 1.2 = 281) plus the ally row under it.
local HERO_ROW_HEIGHT = 374
--The montage stage packs allies beside the hero card instead of under it
--(user direction 2026-09-23), so its row is just the stats card (281) plus
--a small gap to the bottom of the screen; the turn panel gets the rest.
local MONTAGE_HERO_ROW_HEIGHT = 293
--the row's tmargin, which the body's height arithmetic has to leave room for.
local MONTAGE_HERO_ROW_TMARGIN = 10
--space left under the side columns when they run down past the hero row.
local MONTAGE_COLUMN_BOTTOM_GAP = 12
--allies drawn smaller than the roster's, stacked up the hero card's right side.
local MONTAGE_ALLY_UISCALE = 0.75
local COLUMN_WIDTH = "25%"
local CENTER_WIDTH = "46%"

--The scene stage a hero's approach plays on (CreateSceneStage).
local SCENE_TITLE_HEIGHT = 34
--a figure on the stage: the part of the portrait that shows, standing on
--the dialog box.
local SCENE_PORTRAIT_WIDTH = 230
local SCENE_PORTRAIT_HEIGHT = 300
--how much the figure who is speaking grows.
local SCENE_SPEAKING_SCALE = 1.06
--the portrait fades out at its top and sides (style edgeFade). edgeFade
--measures from the edges of the whole IMAGE, not the panel, so the bottom
--is kept crisp by cropping the image's bottom band away: the crop's bottom
--edge then sits beyond the fade (SetPortraitFrom's keepBottom).
local SCENE_PORTRAIT_FADE = 0.15
--the dialog box: tall enough for the prompt and four options stacked
--(three tests and Leave) without scrolling; longer lists scroll.
local SCENE_BOX_HEIGHT = 196
--typing speed of a line, in characters per second.
local SCENE_TYPE_CPS = 45
--A chest row found for the first time holds "???" this long after the roll
--lands, then types in; a client that sees the landing later than the
--window shows it settled.
local CHEST_REVEAL_DELAY = 0.6
local CHEST_REVEAL_WINDOW = 4
local SCENE_ACTOR_FADE = 0.35
--seconds per half-cycle of the page prompt's blink.
local SCENE_PROMPT_BLINK = 0.6
--Emotes: how long an "alert" / "alarmed" mark stays up before it fades, how
--long a "scared" figure trembles, and how far (in pixels) it jerks about.
local SCENE_EMOTE_HOLD = 1.6
local SCENE_EMOTE_FADE = 0.3
local SCENE_SHAKE_TIME = 1.4
local SCENE_SHAKE_PX = 7
--a figure's laid-out width: the portrait plus the actor's margins.
local SCENE_FIGURE_WIDTH = SCENE_PORTRAIT_WIDTH + 8

--tier 4 is the critical: a natural 19-20, not a total.
local TIER_RANGES = { T("stage.tier.range_low"), "12-16", "17+", T("stage.tier.range_critical") }

--"tier 2", or "critical" for tier 4 (capitalized = true for "Tier 2").
local function TierName(tier, capitalized)
    if tier == 4 then
        return capitalized and T("stage.tier.critical_cap") or T("stage.tier.critical")
    end
    return capitalized and T("stage.tier.name_cap", { tier = tier or 0 }) or T("stage.tier.name", { tier = tier or 0 })
end

--the montage haul: one icon per distinct item a hero has been granted,
--stacked down a reserved gutter to the LEFT of their card. The gutter is
--always reserved (even empty) so the row of cards doesn't shuffle
--sideways the moment the first item lands.
local ITEM_ICON_SIZE = 30
local ITEM_STRIP_WIDTH = ITEM_ICON_SIZE + 4
--how far above its slot a newly granted item starts, how long it takes to
--fall into place, and how far apart two items landing in the same refresh
--are staggered (so a pair of grants reads as two pickups, not one thud).
local ITEM_DROP_HEIGHT = ITEM_ICON_SIZE + 14
local ITEM_DROP_TIME = 0.4
local ITEM_DROP_STAGGER = 0.18

--A threat's consequence lands as a malice moment (MaliceMoment): the malice
--diamond slams home, the block flashes malice red with the malice sound, and
--the consequence types on. Several landing together are staggered.
local MALICE_RED = "#DE1E47" --DramaticBanner.maliceAccent
local CONSEQUENCE_SLAM_TIME = 0.28
local CONSEQUENCE_FLASH_TIME = 0.9
local CONSEQUENCE_TYPE_DELAY = 0.3
local CONSEQUENCE_STAGGER = 0.7

--entry cards come and go with the rounds rather than sitting on the stage
--greyed out ahead of time: an entry materializes on the round it enters,
--and one that has been dealt with fades away when that round ends. How
--long each takes, how far apart two cards materializing together are
--staggered, and how far a card is offset while it is ramping in or out.
local ENTRY_APPEAR_TIME = 0.5
local ENTRY_APPEAR_STAGGER = 0.15
local ENTRY_FADE_TIME = 0.5
local ENTRY_APPEAR_OFFSET = 30

--The hero who took the entry on, as a small portrait slot down the card's
--right edge under its outcome icons. It keeps the proportions of the
--montage's hero cards (EotwHeroCard at 132 wide by 176 + 12 + 46 tall, the
--stats-bearing card) so the same crop of the artwork shows, at a
--thumbnail's size. The text column gives up the slot's width plus a gap.
local ENTRY_HERO_SLOT_WIDTH = 56
local ENTRY_HERO_SLOT_HEIGHT = math.floor(ENTRY_HERO_SLOT_WIDTH * 234 / 132 + 0.5)
local ENTRY_HERO_SLOT_GAP = 10
--how far down the slot sits when the outcome icons are above it.
local ENTRY_HERO_SLOT_ICON_CLEARANCE = 26
--the bar drawn through the title of an entry that is out of contention:
--how long it takes to sweep across, and how thick it is.
local ENTRY_STRIKE_TIME = 0.45
local ENTRY_STRIKE_THICKNESS = 2
--the entry card's padding; the hero slot's minimum card height counts it.
local ENTRY_CARD_PAD = 10

--the mounted stage (one per client) and the hero picked by a click, for
--the click-a-hero-then-click-an-entry alternative to dragging.
local m_root = nil
local m_selectedHero = nil

--The action bar renders above windows (renderOnTop), so it paints straight
--through a full-screen stage; the stage hides it through the transient
--"hideactionbar" setting the bar already monitors. It is REF COUNTED because
--one stage beat hands over to the next by creating the new stage before the
--old one is destroyed: the first stage up captures the value to put back and
--the last one down restores it, so the bar neither blinks through a cut nor
--stays hidden after the last stage goes.
local m_actionBarHiders = 0
local m_actionBarRestore = false

local function AcquireActionBarHide()
    if m_actionBarHiders == 0 then
        m_actionBarRestore = dmhub.GetSettingValue("hideactionbar")
        dmhub.SetSettingValue("hideactionbar", true)
    end
    m_actionBarHiders = m_actionBarHiders + 1
end

local function ReleaseActionBarHide()
    m_actionBarHiders = math.max(0, m_actionBarHiders - 1)
    if m_actionBarHiders > 0 then
        return
    end
    --A stage handing over to the next may be destroyed either side of the new
    --one's create, so do not put the bar back until we know nothing has taken
    --it straight back; otherwise the bar blinks through the cut.
    dmhub.Schedule(0.15, function()
        if mod.unloaded or m_actionBarHiders > 0 then
            return
        end
        dmhub.SetSettingValue("hideactionbar", m_actionBarRestore or false)
    end)
end

local function Broadcast(eventName, ...)
    if m_root ~= nil and m_root.valid then
        m_root:FireEventTree(eventName, ...)
    end
end

--what a pick-up or a click is offering to do with the selected hero:
--"approach" (take a beat) or "narrative" (choose in a narrative section).
local m_selectMode = "approach"

--the entry whose hero slot is previewing the hero being dragged (the one
--under the cursor), so the drag only broadcasts when that changes.
local m_previewEntry = nil

local function PreviewHero(charid, entryId)
    if entryId == m_previewEntry then
        return
    end
    m_previewEntry = entryId
    Broadcast("previewHero", charid, entryId)
end

local function SelectHero(charid, mode)
    m_selectedHero = charid
    m_selectMode = mode or "approach"
    Broadcast("selectHero", charid, m_selectMode)
end

local function Hud()
    return rawget(_G, "EncounterOfTheWeekHud")
end

--A class list from optional entries: false/nil entries are dropped, so the
--list never has holes (the engine stops at the first nil).
--defined with the perk buttons, below; the scene stage calls them.
local PerkActionChildren, PerkOfferChildren

local function Classes(...)
    local result = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v then
            result[#result + 1] = v
        end
    end
    return result
end

local function StageRules()
    local rules = {}
    local hud = Hud()
    if hud ~= nil and hud.HeroCardRules ~= nil then
        for _, rule in ipairs(hud.HeroCardRules()) do
            rules[#rules + 1] = rule
        end
    end
    local own = {
        {
            selectors = {"eotwStageTitle"},
            fontSize = 34,
            bold = true,
            color = "#ffffff",
            width = "auto",
            height = "auto",
            textAlignment = "center",
        },
        {
            selectors = {"eotwStageSubtitle"},
            fontSize = 16,
            color = "#d0d0d0",
            width = "auto",
            height = "auto",
            textAlignment = "center",
            maxWidth = 1100,
        },
        {
            --The montage's context prose (the paragraph under "# Montage").
            --It stands in for the Director's read-aloud, so it is sized to
            --be read at a glance from across the table and wraps to as many
            --lines as the writing needs; the header grows to fit it.
            selectors = {"eotwMontageIntro"},
            fontSize = 19,
            italics = true,
            color = "#efe4cc",
            width = "auto",
            height = "auto",
            maxWidth = 1000,
            --about seven wrapped lines: a generous read-aloud paragraph.
            --Past that the header would start eating the entry columns, so
            --the prose is clipped instead (HEADER_HEIGHT_MAX matches).
            maxHeight = 186,
            textAlignment = "center",
            tmargin = 2,
            bmargin = 4,
        },
        {
            selectors = {"eotwStageRound"},
            fontSize = 18,
            bold = true,
            color = "#ffd66b",
            width = "auto",
            height = "auto",
            textAlignment = "center",
        },
        {
            selectors = {"eotwColumnTitle"},
            fontSize = 22,
            bold = true,
            color = "#ffffff",
            width = "100%",
            height = 30,
            textAlignment = "center",
            bmargin = 6,
        },
        {
            selectors = {"eotwEntryCard"},
            bgcolor = "#0f1318e6",
            border = 2,
            borderColor = "#ffffff40",
            cornerRadius = 8,
            transitionTime = 0.15,
        },
        {
            selectors = {"eotwEntryCard", "opportunity"},
            borderColor = "#d4a83ab0",
        },
        {
            selectors = {"eotwEntryCard", "threat"},
            borderColor = "#c0392bb0",
        },
        --highlight states tint the card's background toward its accent colour rather than
        --raising brightness: brightness washes out the child labels and made them unreadable.
        {
            selectors = {"eotwEntryCard", "hover"},
            bgcolor = "#1d2430f2",
            borderColor = "#ffffffc0",
        },
        {
            selectors = {"eotwEntryCard", "opportunity", "hover"},
            bgcolor = "#2a2313f2",
            borderColor = "#d4a83aff",
        },
        {
            selectors = {"eotwEntryCard", "threat", "hover"},
            bgcolor = "#2a1613f2",
            borderColor = "#c0392bff",
        },
        {
            selectors = {"eotwEntryCard", "done"},
            brightness = 0.55,
            saturation = 0.3,
        },
        {
            selectors = {"eotwEntryCard", "active"},
            bgcolor = "#1d2430f2",
            borderColor = "#ffffffff",
        },
        {
            selectors = {"eotwEntryCard", "opportunity", "active"},
            bgcolor = "#2a2313f2",
            borderColor = "#f0c75cff",
        },
        {
            selectors = {"eotwEntryCard", "threat", "active"},
            bgcolor = "#2a1613f2",
            borderColor = "#e05a4aff",
        },
        --an entry the dragged / selected hero may be dropped on.
        {
            selectors = {"eotwEntryCard", "droppable"},
            bgcolor = "#243044f2",
            borderColor = "#ffffffff",
            border = 3,
        },
        {
            selectors = {"eotwEntryCard", "opportunity", "droppable"},
            bgcolor = "#372d15f2",
            borderColor = "#f0c75cff",
            border = 3,
        },
        {
            selectors = {"eotwEntryCard", "threat", "droppable"},
            bgcolor = "#371a15f2",
            borderColor = "#e05a4aff",
            border = 3,
        },
        --while a hero is dragged the engine adds "drag-target" to every
        --valid drop (and "drag-target-hover" to the one under the cursor),
        --which the theme fills with the accent colour and inverts the text
        --of. Keep the cards dark instead (priority beats the theme's 5) and
        --single out the hovered one: brighter, thicker border, a touch larger.
        {
            selectors = {"eotwEntryCard", "drag-target"},
            bgcolor = "#243044f2",
            borderColor = "#ffffffff",
            border = 3,
            priority = 6,
        },
        {
            selectors = {"eotwEntryCard", "opportunity", "drag-target"},
            bgcolor = "#372d15f2",
            borderColor = "#f0c75cff",
            border = 3,
            priority = 6,
        },
        {
            selectors = {"eotwEntryCard", "threat", "drag-target"},
            bgcolor = "#371a15f2",
            borderColor = "#e05a4aff",
            border = 3,
            priority = 6,
        },
        {
            selectors = {"eotwEntryCard", "drag-target-hover"},
            bgcolor = "#34466af8",
            borderColor = "#ffffffff",
            border = 5,
            scale = 1.03,
            priority = 7,
        },
        {
            selectors = {"eotwEntryCard", "opportunity", "drag-target-hover"},
            bgcolor = "#56461cf8",
            borderColor = "#ffe9a3ff",
            border = 5,
            scale = 1.03,
            priority = 7,
        },
        {
            selectors = {"eotwEntryCard", "threat", "drag-target-hover"},
            bgcolor = "#56251cf8",
            borderColor = "#ffa597ff",
            border = 5,
            scale = 1.03,
            priority = 7,
        },
        --materializing in, and fading out again. Same shape as the item
        --drop-in above: the card is put into the start state IMMEDIATELY
        --(SetClassTreeImmediate ignores transitionTime), so it simply
        --starts small, transparent and pushed down; taking the class off
        --ramps THIS rule back out over its own transitionTime, which is
        --the animation. The timing therefore has to live on the rule
        --whose match changes, not on a resting-state rule.
        --
        --Style opacity is NOT inherited by children (SheetPanel applies it
        --to its own background, SheetLabel to its own text), so the class
        --goes on the whole card subtree and the opacity rule is written
        --without "eotwEntryCard" so it matches the labels inside too. The
        --transform bits (scale, y) move children with the card, so they
        --stay on the card alone.
        {
            selectors = {"eotwEntryAppear"},
            opacity = 0,
            transitionTime = ENTRY_APPEAR_TIME,
            easing = "easeOutCubic",
        },
        {
            selectors = {"eotwEntryCard", "eotwEntryAppear"},
            scale = 0.85,
            y = ENTRY_APPEAR_OFFSET,
            transitionTime = ENTRY_APPEAR_TIME,
            easing = "easeOutCubic",
        },
        --an entry dealt with this round fades away once the round ends,
        --and is destroyed when the fade has run.
        {
            selectors = {"eotwEntryLeave"},
            opacity = 0,
            transitionTime = ENTRY_FADE_TIME,
            easing = "easeInCubic",
        },
        {
            selectors = {"eotwEntryCard", "eotwEntryLeave"},
            scale = 0.9,
            transitionTime = ENTRY_FADE_TIME,
            easing = "easeInCubic",
        },
        {
            selectors = {"eotwEntryName"},
            fontSize = 19,
            bold = true,
            color = "#ffffff",
            width = "100%",
            height = "auto",
            textAlignment = "left",
        },
        --the bar through the title of an entry out of contention, in the
        --title's own white. Its width is driven from the card (it sweeps
        --left to right), so the rule only carries its look.
        {
            selectors = {"eotwEntryStrike"},
            bgcolor = "#ffffff",
            cornerRadius = 1,
        },
        --the slot for the hero who took the entry on: an empty frame until
        --someone does, then their portrait with their name along the
        --bottom and the tier they rolled across the top.
        {
            selectors = {"eotwEntryHeroSlot"},
            bgcolor = "#ffffff0a",
            border = 1,
            borderColor = "#ffffff30",
            cornerRadius = 5,
        },
        {
            selectors = {"eotwEntryHeroSlot", "filled"},
            borderColor = "#ffffff90",
        },
        {
            selectors = {"eotwEntryHeroSlot", "filled", "hover"},
            borderColor = "#ffd66bff",
        },
        --the hero being dragged over the entry, shown ahead of the drop.
        {
            selectors = {"eotwEntryHeroSlot", "preview"},
            border = 2,
            borderColor = "#ffffffff",
        },
        {
            selectors = {"eotwEntryHeroArt"},
            bgcolor = "white",
            cornerRadius = 5,
            transitionTime = 0.6,
        },
        --done with the entry: the portrait stays, drained of colour.
        {
            selectors = {"eotwEntryHeroArt", "finished"},
            saturation = 0,
            brightness = 0.75,
            transitionTime = 0.6,
        },
        --the slot is narrow, so a long name shrinks to keep each word on
        --one line instead of breaking mid-word ("Bottlebrus / h").
        {
            selectors = {"eotwEntryHeroName"},
            fontSize = 10,
            minFontSize = 6,
            bold = true,
            color = "#ffffff",
            bgcolor = "#000000c0",
            width = "100%",
            height = "auto",
            textAlignment = "center",
            hpad = 2,
            vpad = 1,
        },
        {
            selectors = {"eotwEntryHeroTier"},
            fontSize = 10,
            bold = true,
            color = "#ffffff",
            bgcolor = "#000000c0",
            width = "100%",
            height = "auto",
            textAlignment = "center",
            vpad = 1,
        },
        {
            selectors = {"eotwEntryHeroTier", "tier1"},
            bgcolor = "#8f2a22e6",
        },
        {
            selectors = {"eotwEntryHeroTier", "tier2"},
            bgcolor = "#8a6d14e6",
        },
        {
            selectors = {"eotwEntryHeroTier", "tier3"},
            bgcolor = "#2c7a3ae6",
        },
        {
            selectors = {"eotwEntryDesc"},
            fontSize = 14,
            color = "#dcdcdc",
            width = "100%",
            height = "auto",
            textAlignment = "left",
            tmargin = 4,
        },
        {
            selectors = {"eotwEntryStatus"},
            fontSize = 13,
            italics = true,
            color = "#b0b0b0",
            width = "100%",
            height = "auto",
            textAlignment = "left",
            tmargin = 6,
        },
        --a "(Temporary)" entry's deadline: the same line, warmer, so it
        --reads as a clock rather than as the card's state.
        {
            selectors = {"eotwEntryStatus", "deadline"},
            color = "#d8a25a",
        },
        --the theme's "parent:drag-target" rule inverts the text of a drop
        --target's direct children; these cards stay dark, so keep it light.
        {
            selectors = {"eotwEntryName", "parent:drag-target"},
            color = "#ffffff",
            priority = 6,
        },
        {
            selectors = {"eotwEntryDesc", "parent:drag-target"},
            color = "#dcdcdc",
            priority = 6,
        },
        {
            selectors = {"eotwEntryStatus", "parent:drag-target"},
            color = "#b0b0b0",
            priority = 6,
        },
        {
            selectors = {"eotwEntryStatus", "deadline", "parent:drag-target"},
            color = "#d8a25a",
            priority = 6,
        },
        --the strip of items a hero has picked up this montage, down the
        --left edge of their card.
        {
            selectors = {"eotwItemIcon"},
            width = ITEM_ICON_SIZE,
            height = ITEM_ICON_SIZE,
            halign = "center",
            valign = "top",
            bmargin = 4,
            cornerRadius = 5,
            border = 1,
            borderColor = "#ffffff50",
            bgcolor = "white",
        },
        {
            selectors = {"eotwItemIcon", "hover"},
            borderColor = "#ffd66bff",
            brightness = 1.25,
        },
        --an item being carried to another hero.
        {
            selectors = {"eotwItemIcon", "dragging"},
            opacity = 0.4,
        },
        --a hero card that can take the item being dragged.
        {
            selectors = {"eotwHeroCard", "droppable"},
            borderColor = "#ffd66bff",
            border = 3,
            brightness = 1.15,
        },
        --the drop-in. An icon is BORN with "dropIn", and a rule that is
        --present at construction applies at full strength immediately, so
        --the icon simply starts raised and transparent; taking the class
        --off ramps that rule back OUT over its own transitionTime, which
        --is the fall. The timing therefore has to live on THIS rule -- the
        --one whose match changes -- not on a rule for the resting state
        --(verified live: a resting-state rule's y never arrives at all,
        --because style y accumulates over every matching rule rather than
        --being overridden by the last one). (Style y is a post-layout
        --render offset and NEGATIVE y is up.)
        {
            selectors = {"eotwItemIcon", "dropIn"},
            y = -ITEM_DROP_HEIGHT,
            opacity = 0,
            transitionTime = ITEM_DROP_TIME,
            easing = "easeOutCubic",
        },
        --a second copy of an item the hero already has bumps the icon it
        --already owns instead of adding a new one, so that gain gets a
        --pulse (PulseClass applies this instantly and fades it back out
        --over the rule's transitionTime).
        {
            selectors = {"eotwItemIcon", "bump"},
            scale = 1.3,
            brightness = 1.5,
            transitionTime = 0.3,
            easing = "easeOutCubic",
        },
        --a consequence landing (MaliceMoment). The diamond is BORN with
        --"slamIn" (huge and clear) and drops it to slam home, the same
        --born-with-a-class trick as the drop-in above.
        {
            selectors = {"eotwMaliceSlam", "slamIn"},
            scale = 3.2,
            opacity = 0,
            transitionTime = CONSEQUENCE_SLAM_TIME,
            easing = "easeInCubic",
        },
        --at impact the diamond flares and the block flashes red (PulseClass).
        {
            selectors = {"eotwMaliceSlam", "impact"},
            scale = 1.25,
            brightness = 2.2,
            transitionTime = 0.35,
            easing = "easeOutCubic",
        },
        {
            selectors = {"eotwMaliceFlash"},
            bgcolor = MALICE_RED .. "00",
            cornerRadius = 8,
        },
        {
            selectors = {"eotwMaliceFlash", "lit"},
            bgcolor = MALICE_RED .. "8c",
            transitionTime = CONSEQUENCE_FLASH_TIME,
            easing = "easeOutCubic",
        },
        {
            selectors = {"eotwItemQty"},
            fontSize = 10,
            bold = true,
            color = "#ffffff",
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "bottom",
            textAlignment = "right",
            bgimage = "panels/square.png",
            bgcolor = "#000000c0",
            cornerRadius = 3,
            hpad = 2,
        },
        {
            selectors = {"eotwTurnPanel"},
            bgcolor = "#0b0e12e0",
            border = 2,
            borderColor = "#ffffff30",
            cornerRadius = 10,
        },
        {
            selectors = {"eotwTurnTitle"},
            fontSize = 26,
            bold = true,
            color = "#ffffff",
            width = "100%",
            height = "auto",
            textAlignment = "center",
        },
        {
            selectors = {"eotwTurnText"},
            fontSize = 16,
            color = "#e6e6e6",
            width = "100%",
            height = "auto",
            textAlignment = "center",
            vmargin = 6,
        },
        {
            selectors = {"eotwTurnHint"},
            fontSize = 15,
            italics = true,
            color = "#b8b8b8",
            width = "100%",
            height = "auto",
            textAlignment = "center",
            vmargin = 6,
        },
        {
            selectors = {"eotwOptionCard"},
            bgcolor = "#161b22f0",
            border = 1,
            borderColor = "#ffffff30",
            cornerRadius = 6,
            transitionTime = 0.12,
        },
        {
            selectors = {"eotwOptionCard", "actionable", "hover"},
            borderColor = "#ffffffc0",
            brightness = 1.2,
        },
        {
            selectors = {"eotwOptionCard", "chosen"},
            borderColor = "#ffd66bff",
        },
        --a test only some heroes may take: violet when this hero unlocked
        --it, dimmed and inert when they did not
        {
            selectors = {"eotwOptionCard", "unlocked"},
            borderColor = "#c58cffc0",
            bgcolor = "#1d1626f0",
        },
        {
            selectors = {"eotwOptionCard", "unlocked", "actionable", "hover"},
            borderColor = "#e2c6ffff",
        },
        {
            selectors = {"eotwOptionCard", "locked"},
            borderColor = "#ffffff18",
            brightness = 0.55,
        },
        {
            selectors = {"eotwRider"},
            fontSize = 13,
            color = "#a8a8a8",
            width = "100%",
            height = "auto",
            textAlignment = "left",
            bmargin = 3,
        },
        {
            selectors = {"eotwRider", "unlocked"},
            color = "#d9b3ff",
            bold = true,
        },
        {
            selectors = {"eotwRider", "locked"},
            color = "#e08c8c",
        },
        {
            selectors = {"eotwRider", "met"},
            color = "#9be29b",
            bold = true,
        },
        {
            selectors = {"eotwRider", "hurt"},
            color = "#e08c8c",
            bold = true,
        },
        {
            selectors = {"eotwRider", "unmet"},
            color = "#6a6a6a",
        },
        {
            selectors = {"eotwOptionName"},
            fontSize = 18,
            bold = true,
            color = "#ffffff",
            width = "100%",
            height = "auto",
            textAlignment = "left",
        },
        {
            selectors = {"eotwOptionRoll"},
            fontSize = 15,
            bold = true,
            color = "#9cc4ff",
            width = "100%",
            height = "auto",
            textAlignment = "left",
            bmargin = 4,
        },
        {
            selectors = {"eotwTierRange"},
            fontSize = 13,
            bold = true,
            color = "#a0a0a0",
            width = 80,
            height = "auto",
            textAlignment = "left",
            valign = "top",
        },
        {
            selectors = {"eotwTierText"},
            fontSize = 14,
            color = "#d8d8d8",
            width = "100%-84",
            height = "auto",
            textAlignment = "left",
            valign = "top",
        },
        {
            selectors = {"eotwTierRange", "landed"},
            color = "#ffd66b",
        },
        {
            selectors = {"eotwTierText", "landed"},
            color = "#ffd66b",
            bold = true,
        },
        {
            selectors = {"eotwTierText", "dim"},
            color = "#707070",
        },
        {
            selectors = {"eotwTierRange", "dim"},
            color = "#606060",
        },
        {
            selectors = {"eotwAppliedLine"},
            fontSize = 16,
            bold = true,
            color = "#8ee08e",
            width = "100%",
            height = "auto",
            textAlignment = "center",
            vmargin = 2,
        },
        --the scene stage (CreateSceneStage): portraits, the dialog box along
        --the bottom (narration and speech) and its blinking page prompt.
        {
            selectors = {"eotwSceneTitle"},
            fontSize = 20,
            bold = true,
            color = "#ffd66b",
            width = "100%",
            height = SCENE_TITLE_HEIGHT,
            textAlignment = "center",
        },
        {
            selectors = {"eotwSceneActor"},
            transitionTime = 0.25,
        },
        {
            selectors = {"eotwSceneActor", "speaking"},
            scale = SCENE_SPEAKING_SCALE,
            transitionTime = 0.25,
        },
        --who has the floor: at rest (the narrator talking) the figures are
        --a touch dim; the speaker lights up; anyone else on stage while
        --somebody speaks sinks back, desaturated.
        {
            selectors = {"eotwScenePortrait"},
            brightness = 0.8,
            transitionTime = 0.25,
        },
        {
            selectors = {"eotwScenePortrait", "speaking"},
            brightness = 1.1,
        },
        {
            selectors = {"eotwScenePortrait", "quiet"},
            brightness = 0.45,
            saturation = 0.35,
        },
        --the name, laid over the foot of the portrait, with a dark copy
        --offset behind it so it reads over any art.
        {
            selectors = {"eotwSceneActorName"},
            fontSize = 21,
            bold = true,
            color = "#ffffff",
            width = "100%",
            height = "auto",
            textAlignment = "center",
            transitionTime = 0.25,
        },
        {
            selectors = {"eotwSceneActorName", "shadow"},
            color = "#000000e0",
        },
        {
            selectors = {"eotwSceneActorName", "speaking"},
            color = "#ffd66b",
        },
        {
            selectors = {"eotwSceneActorName", "shadow", "speaking"},
            color = "#000000e0",
        },
        {
            selectors = {"eotwSceneActorName", "quiet"},
            color = "#9a9a9a",
        },
        {
            selectors = {"eotwSceneActorName", "shadow", "quiet"},
            color = "#000000a0",
        },
        --entering and leaving: the same shape as the entry cards' appear
        --and leave (opacity is not inherited, so the class goes on the whole
        --actor subtree and this rule matches every piece of it).
        {
            selectors = {"eotwSceneOffstage"},
            opacity = 0,
            transitionTime = SCENE_ACTOR_FADE,
            easing = "easeOutCubic",
        },
        {
            selectors = {"eotwSceneActor", "eotwSceneOffstage"},
            y = 24,
            transitionTime = SCENE_ACTOR_FADE,
            easing = "easeOutCubic",
        },
        {
            selectors = {"eotwSceneBox"},
            bgcolor = "#06080cf2",
            border = 2,
            borderColor = "#ffffff60",
            cornerRadius = 8,
        },
        --narration is italic, so it never reads as somebody speaking.
        {
            selectors = {"eotwSceneNarration"},
            fontSize = 19,
            italics = true,
            color = "#f1ead8",
            width = "100%",
            height = "auto",
            textAlignment = "left",
        },
        --a line of speech: upright, with the speaker's name above it.
        {
            selectors = {"eotwSceneNarration", "speech"},
            italics = false,
            color = "#ffffff",
        },
        --words in a language the hero does not know.
        {
            selectors = {"eotwSceneNarration", "speech", "garbled"},
            italics = true,
            color = "#b9ab94",
        },
        --a garbled line being translated in place: it fades out, its words
        --are swapped for the real ones, and it fades back in with a brief
        --green glow (born-with/pulse pattern: the timing is on these rules).
        {
            selectors = {"eotwSceneNarration", "transposing"},
            opacity = 0,
            transitionTime = 0.45,
        },
        {
            selectors = {"eotwSceneNarration", "translated"},
            color = "#9fffc4",
            transitionTime = 1.5,
        },
        {
            selectors = {"eotwSceneSpeaker"},
            fontSize = 16,
            bold = true,
            color = "#ffd66b",
            width = "100%",
            height = "auto",
            textAlignment = "left",
            bmargin = 4,
        },
        --emotes over a figure's head: they pop in from small, hold, and
        --fade (the same born-with-a-class pattern as the actors' entrance).
        {
            selectors = {"eotwEmotePop"},
            opacity = 0,
            transitionTime = 0.15,
        },
        {
            selectors = {"eotwEmote", "eotwEmotePop"},
            scale = 0.2,
            transitionTime = 0.18,
            easing = "easeOutCubic",
        },
        {
            selectors = {"eotwEmoteGone"},
            opacity = 0,
            transitionTime = SCENE_EMOTE_FADE,
        },
        --"alert": a red "!" in a cream balloon.
        {
            selectors = {"eotwEmoteBalloon"},
            bgcolor = "#fff6dcff",
            border = 3,
            borderColor = "#1c1712ff",
            cornerRadius = 19,
        },
        {
            selectors = {"eotwEmoteBang"},
            fontSize = 30,
            bold = true,
            color = "#d8342a",
            width = "100%",
            height = "100%",
            textAlignment = "center",
        },
        --"alarmed": three yellow dashes fanned out over the head.
        {
            selectors = {"eotwEmoteDash"},
            bgcolor = "#ffd23aff",
            cornerRadius = 2,
        },
        {
            selectors = {"eotwScenePrompt"},
            bgcolor = "#ffd66b",
            transitionTime = SCENE_PROMPT_BLINK * 0.8,
        },
        {
            selectors = {"eotwScenePrompt", "dimmed"},
            opacity = 0.2,
        },
        {
            selectors = {"eotwSceneHint"},
            fontSize = 15,
            italics = true,
            color = "#b8b8b8",
            width = "100%",
            height = "auto",
            textAlignment = "left",
            bmargin = 6,
        },
        {
            selectors = {"eotwSceneOption"},
            bgcolor = "#161b22f0",
            border = 1,
            borderColor = "#ffffff50",
            cornerRadius = 6,
            transitionTime = 0.12,
        },
        {
            selectors = {"eotwSceneOption", "actionable", "hover"},
            bgcolor = "#2a2313f2",
            borderColor = "#ffd66bff",
        },
        {
            selectors = {"eotwSceneOption", "hover"},
            borderColor = "#ffffffc0",
        },
        {
            selectors = {"eotwSceneOption", "unlocked"},
            bgcolor = "#1d1626f0",
            borderColor = "#c58cffc0",
        },
        {
            selectors = {"eotwSceneOption", "locked"},
            borderColor = "#ffffff20",
            bgcolor = "#0e1116e0",
        },
        --an option on someone else's turn: a dotted outline, like the ghost
        --Accept / Re-roll buttons, since clicking it only pings it.
        {
            selectors = {"eotwSceneOption", "pingGhost"},
            border = 2,
            borderStyle = "dotted",
        },
        --brightness on the button does not reach its label, so the name
        --dims itself.
        {
            selectors = {"eotwSceneOptionName", "locked"},
            color = "#6f6f6f",
        },
        {
            selectors = {"eotwSceneOptionName"},
            fontSize = 17,
            bold = true,
            color = "#ffffff",
            width = "auto",
            height = "auto",
        },
        {
            selectors = {"eotwSceneOptionName", "pass"},
            bold = false,
            italics = true,
            color = "#c8c8c8",
        },
        --"no roll" after the name of an option a hero's knack (or the
        --option itself) settles without dice.
        {
            selectors = {"eotwSceneOptionTag"},
            fontSize = 13,
            italics = true,
            color = "#d9b3ff",
            width = "auto",
            height = "auto",
            lmargin = 8,
        },
        --an item that would help at the entry (EncounterMontage.ItemBenefits),
        --its "!" and the options it would help while it is hovered.
        {
            selectors = {"eotwItemIcon", "benefit"},
            borderColor = "#7dffb0ff",
            border = 2,
        },
        {
            selectors = {"eotwItemAlert"},
            width = 16,
            height = 16,
            fontSize = 12,
            bold = true,
            color = "#0c1a12",
            textAlignment = "center",
            bgimage = "panels/square.png",
            bgcolor = "#7dffb0ff",
            cornerRadius = 8,
        },
        {
            selectors = {"eotwSceneOption", "itemBenefit"},
            borderColor = "#7dffb0ff",
            border = 2,
            brightness = 1.2,
        },
        {
            selectors = {"eotwOptionCard", "itemBenefit"},
            borderColor = "#7dffb0ff",
            border = 2,
        },
        --the pulsing "?" over a hero card in a narrative section who has
        --still to choose.
        {
            selectors = {"eotwHeroBadge"},
            bgcolor = "#1b2740ff",
            borderColor = "#9cc4ffff",
            border = 2,
            cornerRadius = 11,
        },
        {
            selectors = {"eotwHeroBadgeText"},
            fontSize = 16,
            bold = true,
            color = "#9cc4ff",
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
            textAlignment = "center",
        },
        {
            selectors = {"eotwHeroCard", "acted"},
            saturation = 0.15,
            brightness = 0.45,
        },
        {
            selectors = {"eotwHeroCard", "dragging"},
            brightness = 1.2,
        },
        {
            selectors = {"eotwHeroCard", "selected"},
            borderColor = "#ffd66bff",
            border = 3,
            brightness = 1.15,
        },
        --a hero the local user can act with right now (take a beat): a green
        --ring just outside the card that pulses (CreateHeroColumn drives the opacity), so a
        --player can see at a glance who is waiting on them.
        {
            selectors = {"eotwCanActRing"},
            bgcolor = "clear",
            border = 3,
            borderColor = "#7cf29aff",
            cornerRadius = 11,
        },
        --the narrative stage: the section's prose, the option cards as drop
        --targets, the chips saying who chose what, and the flash that
        --settles a split decision.
        {
            selectors = {"eotwNarrativeText"},
            fontSize = 20,
            color = "#e8e4dc",
            width = "100%",
            height = "auto",
            textAlignment = "center",
            bmargin = 12,
        },
        {
            selectors = {"eotwNarrativePrompt"},
            fontSize = 17,
            italics = true,
            color = "#ffd66b",
            width = "100%",
            height = "auto",
            textAlignment = "center",
            bmargin = 10,
        },
        {
            selectors = {"eotwOptionCard", "droppable"},
            bgcolor = "#243018f2",
            borderColor = "#b8e04aff",
        },
        {
            selectors = {"eotwOptionCard", "flashing"},
            bgcolor = "#2a2313f2",
            borderColor = "#ffd66bff",
            brightness = 1.2,
        },
        {
            selectors = {"eotwChoiceChip"},
            fontSize = 13,
            color = "#9cc4ff",
            width = "100%",
            height = "auto",
            textAlignment = "center",
            tmargin = 6,
        },
        {
            selectors = {"eotwHeroChoice"},
            fontSize = 12,
            bold = true,
            color = "#b8e04a",
            width = 132,
            height = "auto",
            textAlignment = "center",
            tmargin = 2,
        },
        {
            selectors = {"eotwHeroChoice", "waiting"},
            color = "#d0d0d0",
            bold = false,
            italics = true,
        },
        {
            selectors = {"eotwDecideBanner"},
            fontSize = 26,
            bold = true,
            color = "#ffd66b",
            width = "100%",
            height = "auto",
            textAlignment = "center",
            vmargin = 6,
        },
        {
            selectors = {"eotwDecideName"},
            fontSize = 34,
            bold = true,
            color = "#ffffff",
            width = "100%",
            height = "auto",
            textAlignment = "center",
        },
        {
            selectors = {"eotwHeroCard", "flashing"},
            borderColor = "#ffd66bff",
            border = 4,
            brightness = 1.35,
        },

        --the feature-unlock callout: what a currency the party has never seen
        --before is FOR, said once, where they are already reading.
        {
            --borderless: it is a note, not a card the party can take.
            selectors = {"eotwCallout"},
            bgcolor = "#121a26f0",
            border = 0,
            cornerRadius = 8,
        },
        {
            selectors = {"eotwCalloutIcon"},
            width = 40,
            height = 40,
            halign = "center",
            valign = "top",
            bgcolor = "#9cc4ff",
            bmargin = 4,
        },
        {
            selectors = {"eotwCalloutTitle"},
            fontSize = 20,
            bold = true,
            color = "#9cc4ff",
            width = "100%",
            height = "auto",
            textAlignment = "center",
            bmargin = 4,
        },
        {
            selectors = {"eotwCalloutText"},
            fontSize = 17,
            color = "#e8e4dc",
            width = "100%",
            height = "auto",
            textAlignment = "center",
        },

        --the Tactical Preparation screen: one card per bar, a notched track
        --across it, and the level the party is on written underneath. The
        --cards are option cards (the same frame every choice on this stage
        --wears); only the track is new.
        {
            selectors = {"eotwPrepPool"},
            fontSize = 30,
            bold = true,
            color = "#9cc4ff",
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 8,
        },
        {
            selectors = {"eotwPrepPoolIcon"},
            width = 34,
            height = 34,
            valign = "center",
            bgcolor = "#9cc4ff",
        },
        --"your Intelligence" after the big number, and the party total
        --beside it, quieter: what you can spend is the number that matters.
        {
            selectors = {"eotwPrepPoolCaption"},
            fontSize = 16,
            color = "#9cc4ff",
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 6,
            textWrap = false,
        },
        {
            selectors = {"eotwPrepPoolCaption", "party"},
            color = "#aab4c0",
            lmargin = 18,
        },
        {
            selectors = {"eotwPrepTrack"},
            width = "100%",
            height = 14,
            flow = "horizontal",
            halign = "center",
            vmargin = 8,
        },
        {
            selectors = {"eotwPrepPip"},
            height = "100%",
            bgimage = "panels/square.png",
            bgcolor = "#ffffff18",
            border = 1,
            borderColor = "#ffffff30",
            cornerRadius = 3,
            hmargin = 3,
            transitionTime = 0.2,
        },
        {
            selectors = {"eotwPrepPip", "filled"},
            bgcolor = "#9cc4ffff",
            borderColor = "#dce9ffff",
        },
        {
            selectors = {"eotwPrepLevel"},
            fontSize = 18,
            color = "#e8e4dc",
            width = "100%",
            height = "auto",
            textAlignment = "center",
            vmargin = 4,
        },
        {
            selectors = {"eotwPrepLevel", "bought"},
            color = "#b8e04a",
            bold = true,
        },
    }
    for _, rule in ipairs(own) do
        rules[#rules + 1] = rule
    end
    return rules
end

--- small builders ----------------------------------------------------------------

local function MaliceIcon(size, classes)
    local hud = Hud()
    local diamond = nil
    if hud ~= nil and hud.CreateMaliceDiamond ~= nil then
        diamond = hud.CreateMaliceDiamond()
    end
    return gui.Panel{
        classes = classes,
        width = size,
        height = size,
        halign = "center",
        valign = "center",
        interactable = false,
        uiscale = size / 26,
        diamond,
    }
end

--- outcome icons -------------------------------------------------------------------
--
--A row of small icons on each entry card and each option button saying what
--it MAY lead to. Worked out from the parsed effects
--(EncounterScript.EntryOutcomes / OptionOutcomes), never authored. Each icon
--explains itself on hover.

local OUTCOME_INFO = {
    intelligence = {
        bgimage = "phosphor/brain.png",
        color = "#ffffff",
        text = T("stage.outcome.intelligence"),
    },
    herotoken = {
        bgimage = "drawsteel/hero-token.png",
        color = "#ffffff",
        text = T("stage.outcome.herotoken"),
    },
    treasure = {
        bgimage = "phosphor/treasure-chest.png",
        color = "#ffd66b",
        text = T("stage.outcome.treasure"),
    },
    temphp = {
        bgimage = "phosphor/shield.png",
        color = "#9fd3ff",
        text = T("stage.outcome.temphp"),
    },
    malice = {
        text = T("stage.outcome.malice"),
    },
    harm = {
        bgimage = "phosphor/sword.png",
        color = "#ff8a7a",
        text = T("stage.outcome.harm"),
    },
    --white on an opportunity, red on a threat (where only the consequence
    --counts -- EncounterScript.EntryOutcomes).
    other = {
        bgimage = "phosphor/question.png",
        color = "#ffffff",
        consequenceColor = "#ff6b5e",
        text = T("stage.outcome.other"),
        consequenceText = T("stage.outcome.other_consequence"),
    },
}

--The parse the stage's script came from (resolves "Delve:" options).
local function CurrentParse()
    local script = EncounterMontage.FindMapScript()
    return script ~= nil and script.parse or nil
end

local function OutcomeTooltip(outcome)
    local info = OUTCOME_INFO[outcome.kind]
    if outcome.fromConsequence and info.consequenceText ~= nil then
        return info.consequenceText
    end
    local text = info.text
    if outcome.fromConsequence and not outcome.fromOptions then
        text = T("stage.outcome.only_if_unresolved", { outcome = text })
    elseif outcome.fromConsequence then
        text = T("stage.outcome.also_if_unresolved", { outcome = text })
    end
    return text
end

--One icon in a square slot. The slot is the hover target (a transparent
--bgimage so it is hit-tested); a press on it still reaches the card or
--button underneath, since presses pass up to the parent.
local function OutcomeIcon(outcome, size)
    local info = OUTCOME_INFO[outcome.kind]
    local icon
    if outcome.kind == "malice" then
        --the diamond fills less of its box than the line icons do.
        icon = MaliceIcon(size * 1.3)
    else
        icon = gui.Panel{
            width = size,
            height = size,
            halign = "center",
            valign = "center",
            interactable = false,
            bgimage = info.bgimage,
            bgcolor = cond(outcome.fromConsequence and info.consequenceColor ~= nil, info.consequenceColor, info.color),
        }
    end
    return gui.Panel{
        width = size + 4,
        height = size + 4,
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#00000000",
        icon,
        linger = function(element)
            gui.Tooltip(OutcomeTooltip(outcome))(element)
        end,
    }
end

--The row for a list of outcomes, or nil when there are none.
local function OutcomeIconRow(outcomes, size, args)
    if outcomes == nil or #outcomes == 0 then
        return nil
    end
    local children = {}
    for _, outcome in ipairs(outcomes) do
        children[#children + 1] = OutcomeIcon(outcome, size)
    end
    local row = {
        width = "auto",
        height = "auto",
        flow = "horizontal",
        valign = "center",
        children = children,
    }
    for k, v in pairs(args or {}) do
        row[k] = v
    end
    return gui.Panel(row)
end

--- typewriter --------------------------------------------------------------------
--
--Text types out a character at a time, but it is laid out in full from the
--first frame: the part not yet typed is drawn in a clear colour. So every
--word sits where it will end up -- nothing starts at the end of a line and
--jumps down when it turns out not to fit, and the label is its final size
--from the start. Rich-text tags (the green rules markup) are kept in the
--typed part and dropped from the hidden part, where only layout matters.

--The byte length of the UTF-8 character starting at byte i.
local function CharLength(text, i)
    local b = string.byte(text, i) or 0
    if b >= 0xF0 then
        return 4
    elseif b >= 0xE0 then
        return 3
    elseif b >= 0xC0 then
        return 2
    end
    return 1
end

--How many characters a line shows, tags not counted.
local function VisibleLength(markup)
    local plain = string.gsub(markup or "", "<[^>]*>", "")
    if utf8 ~= nil and utf8.len ~= nil then
        local n = utf8.len(plain)
        if n ~= nil then
            return n
        end
    end
    return #plain
end

--`markup` with only its first `count` characters visible.
local function RevealText(markup, count)
    markup = markup or ""
    if count >= VisibleLength(markup) then
        return markup
    end
    local out = {}
    local shown = 0
    local openColors = 0
    local i, len = 1, #markup
    while i <= len and shown < count do
        local close = nil
        if string.sub(markup, i, i) == "<" then
            close = string.find(markup, ">", i, true)
        end
        if close ~= nil then
            local tag = string.sub(markup, i, close)
            if string.find(tag, "^<color") ~= nil then
                openColors = openColors + 1
            elseif string.find(tag, "^</color") ~= nil and openColors > 0 then
                openColors = openColors - 1
            end
            out[#out + 1] = tag
            i = close + 1
        else
            local n = CharLength(markup, i)
            out[#out + 1] = string.sub(markup, i, i + n - 1)
            shown = shown + 1
            i = i + n
        end
    end
    if i <= len then
        for _ = 1, openColors do
            out[#out + 1] = "</color>"
        end
        local rest = string.gsub(string.sub(markup, i), "<[^>]*>", "")
        out[#out + 1] = "<color=#00000000>" .. rest .. "</color>"
    end
    return table.concat(out)
end

--The recognized-rules colours: the green the applied-effect lines already
--use, and a muted version of it for a dimmed row.
local RULES_COLOR = "#8ee08e"
local RULES_COLOR_DIM = "#5d7a5d"

--What one tier row reads. A tier with a "teaser => full text" line shows
--only its teaser until it is the landed tier
--(EncounterScript.TierDisplayText); tiers not achieved keep their teaser.
--
--Wherever the FULL text is on show -- the landed tier, and any tier
--written without a teaser -- every clause the effect grammar recognizes is
--coloured the applied-effect green, so a player can see at a glance which
--words the montage will actually act on and which are flavour. A teaser is
--never marked: the grammar only ever parses the full text.
local function TierText(roll, t, landed, dim)
    local text = EncounterScript.TierDisplayText(roll, t, landed)
    local teaser = roll.teasers ~= nil and roll.teasers[t] or nil
    if (not landed) and teaser ~= nil then
        return text
    end
    local color = dim and RULES_COLOR_DIM or RULES_COLOR
    return EncounterScript.MarkupRules(text, string.format("<color=%s>", color), "</color>")
end

--The critical tier (4) gets no row until a critical has landed: every test
--has one, and what it gives is a surprise until it is rolled.
local function TierRows(roll, landedTier, dimOthers)
    local rows = {}
    for t in ipairs(roll.tiers) do
        if t > 3 and landedTier ~= t then
            break
        end
        local range = TIER_RANGES[t] or ""
        local landed = landedTier == t
        local dim = dimOthers and landedTier ~= nil and not landed
        local tierText = TierText(roll, t, landed, dim)
        rows[#rows + 1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            vmargin = 1,
            interactable = false,
            gui.Label{ classes = Classes("eotwTierRange", landed and "landed", dim and "dim"), text = range, interactable = false },
            gui.Label{ classes = Classes("eotwTierText", landed and "landed", dim and "dim"), text = tierText, interactable = false },
            --types a revealed outcome in (SetLandedTier).
            think = function(element)
                local d = element.data
                local typing = d ~= nil and d.typing or nil
                if typing == nil then
                    element.thinkTime = nil
                    return
                end
                local n = math.floor((dmhub.Time() - typing.start) * SCENE_TYPE_CPS)
                if n >= typing.total then
                    element.children[2].text = typing.markup
                    d.typing = nil
                    element.thinkTime = nil
                else
                    element.children[2].text = RevealText(typing.markup, n)
                end
            end,
        }
        rows[#rows].data = { roll = roll, tier = t, shown = tierText }
    end
    return rows
end

--Re-mark a set of tier rows with the landed tier (nil = none landed yet).
--While the dice tumble (`reveal` false) the running tier is only
--highlighted: a hidden outcome keeps its teaser, so the roll is never
--previewed. Once the roll has settled (`reveal` true) the landed tier's
--outcome types in over its teaser, laid out at full size from the start.
local function SetLandedTier(rows, landedTier, reveal)
    for t, row in ipairs(rows) do
        local landed = landedTier == t
        local dim = landedTier ~= nil and not landed
        for _, label in ipairs(row.children) do
            label:SetClass("landed", landed)
            label:SetClass("dim", dim)
        end
        local d = row.data
        if d ~= nil and d.roll ~= nil then
            local showFull = landed and reveal == true
            local text = TierText(d.roll, t, showFull, dim)
            if text ~= d.shown then
                local teaser = d.roll.teasers ~= nil and d.roll.teasers[t] or nil
                d.shown = text
                if showFull and teaser ~= nil then
                    d.typing = { markup = text, total = VisibleLength(text), start = dmhub.Time() }
                    row.children[2].text = RevealText(text, 0)
                    row.thinkTime = 0.03
                else
                    d.typing = nil
                    row.children[2].text = text
                end
            end
        end
    end
end

--The tier rows of the option being rolled, highlighting the tier the dice
--are landing on WHILE they tumble, the way the remote ability card's tier
--table does (Timeline/AbilitySidebar.lua). The roll dialog broadcasts its
--state to the shared ability document (BroadcastDialogState ->
--CharacterPanel.UpdateAbilitySharing): while rollState is "rolling" we
--look up the chat message by dialogState.rollId, subscribe to each die's
--DiceEvents and recompute the running tier on every 'diceface'; when the
--dice settle, or once rollState is "finished", the broadcast
--highlightedTier (which already includes post-roll edges/banes) wins.
--The roller's own client reads the same document it writes, so every
--client runs the one code path. Falls back to plain rows on a core
--without the share exports.
local function LiveTierRows(roll)
    local rows = TierRows(roll, nil, true)
    if CharacterPanel.AbilityShareDocPath == nil or CharacterPanel.GetAbilityShareData == nil then
        return rows
    end

    local function ShareState()
        local share = nil
        pcall(function() share = CharacterPanel.GetAbilityShareData() end)
        if share == nil then
            return nil
        end
        return share.dialogState
    end

    --the tier a running total of the dice would land on, using the roll
    --message's own edges/banes/tier shifts.
    local function RunningTier(d, total)
        local rm = d.rollMsg
        local tier = 1
        pcall(function()
            tier = RollUtils.DiceResultToTier{
                total = total,
                naturalRoll = total - d.mod,
                boons = rm.boons,
                banes = rm.banes,
                tiers = rm.tiers,
                autosuccess = rm.autosuccess,
                autofailure = rm.autofailure,
                nottierthree = rm.nottierthree,
                nottierone = rm.nottierone,
            }
        end)
        return tier
    end

    return {
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            interactable = false,
            children = rows,
            data = { rollId = nil, finished = false },

            monitorGame = CharacterPanel.AbilityShareDocPath(),
            refreshGame = function(element)
                element:FireEvent("syncRoll")
            end,
            create = function(element)
                element:FireEvent("syncRoll")
            end,

            syncRoll = function(element)
                local ds = ShareState()
                if ds == nil then
                    return
                end
                local d = element.data
                local lastState = d.lastState
                d.lastState = ds.rollState

                --a Re-roll keeps the dialog's rollId and only flips rollState
                --back to "rolling", so going back into "rolling" is a new
                --throw too. Without this the broadcast tier, already worked
                --out from the re-roll's result, showed before the dice landed.
                local reroll = ds.rollState == "rolling" and ds.rollId ~= nil and ds.rollId == d.rollId
                    and lastState ~= nil and lastState ~= "rolling"
                if ds.rollState == "rolling" and ds.rollId ~= nil and (ds.rollId ~= d.rollId or reroll) then
                    local rollMsg = nil
                    for _, msg in ipairs(chat.messages) do
                        if msg.key == ds.rollId then
                            rollMsg = msg
                            break
                        end
                    end
                    if rollMsg == nil then
                        --the chat message lands a beat after the broadcast.
                        --Keep the old state so the retry still sees the change.
                        d.lastState = lastState
                        element:ScheduleEvent("syncRoll", 0.1)
                        return
                    end
                    local flat = rollMsg.total or 0
                    local numDice = 0
                    for _, r in ipairs(rollMsg.rolls or {}) do
                        flat = flat - r.result
                        local events = chat.DiceEvents(r.guid)
                        if events ~= nil then
                            events:Listen(element)
                            numDice = numDice + 1
                        end
                    end
                    --a re-roll changes only the dice, and the message's total
                    --can still be the old roll's, so keep the first throw's
                    --flat modifier.
                    if reroll and d.mod ~= nil then
                        flat = d.mod
                    end
                    element.data = {
                        rollId = ds.rollId,
                        rollMsg = rollMsg,
                        mod = flat,
                        reroll = reroll,
                        numDice = numDice,
                        faces = {},
                        endTime = nil,
                        finished = false,
                        lastState = ds.rollState,
                    }
                    element.thinkTime = 0.1
                    if numDice == 0 and rollMsg.total ~= nil then
                        element.data.finished = true
                        SetLandedTier(rows, RunningTier(element.data, rollMsg.total), true)
                    else
                        SetLandedTier(rows, nil, false)
                    end
                    return
                end

                --the roll finished with no die ever reporting a face here
                --(e.g. a re-roll whose dice this client never saw): stop
                --waiting and take the broadcast tier.
                if d.rollId ~= nil and not d.finished and d.endTime == nil and ds.rollState == "finished" then
                    d.finished = true
                    element.thinkTime = nil
                end

                --not animating (or already settled): the broadcast tier is
                --authoritative, and it moves with post-roll edges/banes.
                if d.rollId == nil or d.finished then
                    if ds.rollState == "finished" or ds.rollState == "rolling" then
                        SetLandedTier(rows, ds.highlightedTier, d.finished or ds.rollState == "finished")
                    elseif d.rollId == nil then
                        SetLandedTier(rows, nil, false)
                    end
                end
            end,

            diceface = function(element, diceguid, num, timeRemaining)
                local d = element.data
                if d == nil or d.rollId == nil or d.finished then
                    return
                end
                local endTime = dmhub.Time() + (timeRemaining or 0)
                d.faces[diceguid] = num
                if d.endTime == nil or endTime > d.endTime then
                    d.endTime = endTime
                end
                local total = d.mod
                local count = 0
                for _, value in pairs(d.faces) do
                    count = count + 1
                    total = total + value
                end
                if count == d.numDice then
                    SetLandedTier(rows, RunningTier(d, total), false)
                end
            end,

            think = function(element)
                local d = element.data
                if d == nil or d.rollId == nil or d.finished then
                    element.thinkTime = nil
                    return
                end
                if d.endTime ~= nil and dmhub.Time() > d.endTime and d.rollMsg.total ~= nil then
                    d.finished = true
                    element.thinkTime = nil
                    --a re-roll's message total may be the old roll's; the
                    --landed faces are the re-roll's.
                    local total = d.rollMsg.total
                    if d.reroll then
                        total = d.mod
                        for _, value in pairs(d.faces) do
                            total = total + value
                        end
                    end
                    SetLandedTier(rows, RunningTier(d, total), true)
                    --pick up the broadcast tier if it has already moved on.
                    element:FireEvent("syncRoll")
                end
            end,
        },
    }
end

--- entry cards ---------------------------------------------------------------------

--Who the entry's hero slot shows: the hero at it right now, or else the
--last hero whose turn there has finished (from the montage log, so a failed
--threat shows the latest hero to try it). Returns the turn or log record
--and whether that hero is finished with it; nil when nobody has been.
local function EntryHeroRecord(m, entry)
    local t = m.turn
    if t ~= nil and t.entryId == entry.id and t.status ~= "resolved" then
        return t, false
    end
    local logs = m.log or {}
    for i = #logs, 1, -1 do
        local rec = logs[i]
        if rec.entryId == entry.id and rec.heroid ~= nil and not rec.consequence then
            return rec, true
        end
    end
    return nil, false
end

--What the slot says across the top of a finished hero's portrait.
local function EntryHeroResultText(rec)
    if rec.passed then
        return T("stage.entry.slot.passed")
    elseif rec.delve then
        return T("stage.entry.slot.delved")
    elseif (rec.tier or 0) > 0 then
        return TierName(rec.tier, true)
    end
    return T("stage.entry.slot.done")
end

--The hover text for the slot: who it was and everything their turn there
--came to, the same facts the round summary reads out.
local function EntryHeroTooltip(rec, finished)
    local name = rec.heroName or T("stage.fallback.a_hero")
    if not finished then
        return T("stage.entry.slot.tooltip_now", { hero = name })
    end
    local lines = {}
    if rec.passed then
        lines[#lines + 1] = T("stage.entry.slot.tooltip_passed", { hero = name })
    elseif rec.delve and rec.ordered then
        lines[#lines + 1] = T("stage.entry.slot.tooltip_ordered_delve", { hero = name, depth = rec.depth or 0,
            steps = TP("stage.count.steps", rec.steps or 0) })
    elseif rec.delve then
        lines[#lines + 1] = T("stage.entry.slot.tooltip_delve", { hero = name,
            obstacles = TP("stage.count.obstacles", rec.depth or 0), chests = TP("stage.count.chests", rec.chests or 0) })
    else
        lines[#lines + 1] = string.format("<b>%s</b>: %s", name, rec.optionName or "")
        if (rec.tier or 0) > 0 then
            if rec.total ~= nil then
                lines[#lines + 1] = T("stage.entry.slot.tooltip_rolled", { tier = TierName(rec.tier, true), total = tostring(rec.total) })
            else
                lines[#lines + 1] = string.format("<b>%s</b>", TierName(rec.tier, true))
            end
        else
            lines[#lines + 1] = T("stage.entry.slot.tooltip_no_roll")
        end
        if (rec.tierText or "") ~= "" then
            lines[#lines + 1] = string.format("<i>%s</i>", rec.tierText)
        end
    end
    if rec.knack ~= nil then
        lines[#lines + 1] = T("stage.entry.slot.tooltip_knack", { knack = rec.knack })
    end
    for _, line in ipairs(rec.applied or {}) do
        lines[#lines + 1] = string.format("- %s", line)
    end
    return table.concat(lines, "\n")
end

--The slot itself: an empty frame until a hero approaches the entry, then
--their portrait (in colour while they are there, desaturated once they are
--done), their name along the bottom and, after the roll, the tier across
--the top. `top` clears the outcome icons when the card has any.
local function CreateEntryHeroSlot(entry, top)
    local art = gui.Panel{
        classes = {"eotwEntryHeroArt", "hidden"},
        width = "100%",
        height = "100%",
        bgimage = "panels/square.png",
        interactable = false,
    }
    local tierLabel = gui.Label{
        classes = {"eotwEntryHeroTier", "hidden"},
        floating = true,
        valign = "top",
        text = "",
        interactable = false,
    }
    local nameLabel = gui.Label{
        classes = {"eotwEntryHeroName", "hidden"},
        floating = true,
        valign = "bottom",
        text = "",
        interactable = false,
    }
    --puts `heroid`'s portrait in the art panel; the same hero keeps what
    --is already there.
    local shownHero = nil
    local function ShowPortrait(heroid)
        if shownHero == heroid then
            return
        end
        shownHero = heroid
        local tok = dmhub.GetCharacterById(heroid)
        local portrait = nil
        local rect = nil
        if tok ~= nil and tok.valid then
            --a narrowed local: the nil check does not reach into the closure.
            local heroTok = tok
            pcall(function()
                portrait = heroTok.offTokenPortrait
                rect = heroTok:GetPortraitRectForAspect(ENTRY_HERO_SLOT_WIDTH / ENTRY_HERO_SLOT_HEIGHT, portrait)
            end)
        end
        if portrait ~= nil and portrait ~= "" then
            art.bgimage = portrait
            art.selfStyle.imageRect = rect
        else
            art.bgimage = "panels/square.png"
            art.selfStyle.imageRect = nil
        end
    end

    return gui.Panel{
        classes = {"eotwEntryHeroSlot"},
        floating = true,
        halign = "right",
        valign = "top",
        y = top,
        width = ENTRY_HERO_SLOT_WIDTH,
        height = ENTRY_HERO_SLOT_HEIGHT,
        bgimage = "panels/square.png",
        flow = "none",
        data = { tooltip = nil, preview = nil, held = false, m = nil },
        children = { art, tierLabel, nameLabel },

        linger = function(element)
            if element.data.tooltip ~= nil and element.data.preview == nil then
                gui.Tooltip(element.data.tooltip)(element)
            end
        end,

        --a hero is being dragged over this entry (charid) or off it: stand
        --them in the slot ahead of the drop, over whoever is there.
        --`hold`: the hero was dropped here, so keep them until the montage
        --state shows them arriving (or a few seconds pass, if it never does).
        previewHero = function(element, charid, entryId, hold)
            local preview = nil
            if charid ~= nil and entryId == entry.id then
                preview = charid
            end
            element.data.held = hold == true and preview ~= nil
            if element.data.held then
                element:ScheduleEvent("previewExpire", 3)
            end
            if preview == element.data.preview then
                return
            end
            element.data.preview = preview
            if element.data.m ~= nil then
                element:FireEvent("refreshMontage", element.data.m)
            end
        end,
        previewExpire = function(element)
            if element.data.held then
                element:FireEvent("previewHero", nil, nil)
            end
        end,

        refreshMontage = function(element, m)
            element.data.m = m
            local rec, finished = EntryHeroRecord(m, entry)
            --the dropped hero has arrived: the real record takes over.
            if element.data.held and rec ~= nil and rec.heroid == element.data.preview then
                element.data.held = false
                element.data.preview = nil
            end
            local preview = element.data.preview
            element:SetClass("preview", preview ~= nil)
            if preview ~= nil then
                local tok = dmhub.GetCharacterById(preview)
                local name = ""
                if tok ~= nil and tok.valid then
                    name = tok.name or ""
                end
                element:SetClass("filled", true)
                art:SetClass("hidden", false)
                art:SetClass("finished", false)
                nameLabel:SetClass("hidden", false)
                nameLabel.text = name
                tierLabel:SetClass("hidden", true)
                ShowPortrait(preview)
                return
            end
            local filled = rec ~= nil
            element:SetClass("filled", filled)
            art:SetClass("hidden", not filled)
            nameLabel:SetClass("hidden", not filled)
            if rec == nil then
                tierLabel:SetClass("hidden", true)
                element.data.tooltip = nil
                return
            end
            --a new hero (a failed threat taken up by someone else) brings
            --their own artwork.
            ShowPortrait(rec.heroid)
            art:SetClass("finished", finished)
            nameLabel.text = rec.heroName or ""
            tierLabel:SetClass("hidden", not finished)
            if finished then
                tierLabel.text = EntryHeroResultText(rec)
                --a critical wears tier 3's colour.
                local shownTier = math.min(rec.tier or 0, 3)
                for tier = 1, 3 do
                    tierLabel:SetClass("tier" .. tier, shownTier == tier and not rec.passed and not rec.delve)
                end
            end
            element.data.tooltip = EntryHeroTooltip(rec, finished)
        end,
    }
end

--One entry's card. An entry is only ever carded from the round it enters
--onwards (the columns used to carry every entry of the beat, greyed out
--with an "Appears in round N" line; user direction 2026-09-19: an entry
--the party cannot reach yet should not be on the stage at all). `appearIn`
--is the delay after which it materializes -- nil for the cards that come
--up with the stage itself, a stagger offset for the ones a new round
--introduces.
local function CreateEntryCard(entry, appearIn)
    --The name is a DIRECT child of the card: while a hero is dragged the
    --engine marks valid drops "drag-target", the theme turns them light,
    --and its "parent:drag-target" rule darkens only the card's direct
    --children's text. The outcome icons float in the corner so they do not
    --need a row around the name.
    local outcomes = EncounterScript.EntryOutcomes(entry, CurrentParse())
    local outcomeRow = OutcomeIconRow(outcomes, 18, {
        floating = true,
        halign = "right",
        valign = "top",
    })
    --the text column leaves the hero slot's width free down the right; the
    --title, beside the icons rather than the slot when there are any, gives
    --up whichever is wider.
    local slotTop = cond(#outcomes > 0, ENTRY_HERO_SLOT_ICON_CLEARANCE, 0)
    local textWidth = string.format("100%%-%d", ENTRY_HERO_SLOT_WIDTH + ENTRY_HERO_SLOT_GAP)
    local nameReserve = math.max(ENTRY_HERO_SLOT_WIDTH + ENTRY_HERO_SLOT_GAP, cond(#outcomes > 0, #outcomes * 22 + 8, 0))
    --the title is only as wide as its text (up to the column), so the bar
    --that crosses it out can be sized to the words rather than the column.
    --the bar through the title once the entry is out of contention (taken,
    --vanquished, or carried off by the round). It sweeps left to right over
    --ENTRY_STRIKE_TIME from `start`; a card built already struck draws it
    --whole. It is a floating CHILD of the title, so its y is measured from
    --the title's own top. (It used to be a sibling on the card, measured from
    --the card's padded top -- but the card's vertical flow spreads its rows
    --over the card's height, so the title sits a varying distance below that
    --and no constant offset could find its letters.)
    local nameLabel
    local strike = gui.Panel{
        classes = {"eotwEntryStrike", "hidden"},
        floating = true,
        halign = "left",
        valign = "top",
        width = 0,
        height = ENTRY_STRIKE_THICKNESS,
        bgimage = "panels/square.png",
        interactable = false,
        data = { start = nil },
        think = function(element)
            local w = nameLabel.renderedWidth
            local h = nameLabel.renderedHeight
            if w == nil or w <= 0 then
                return
            end
            local p = 1
            if element.data.start ~= nil then
                p = math.min(1, (dmhub.Time() - element.data.start) / ENTRY_STRIKE_TIME)
            end
            --ease in and out, so the stroke reads as drawn by hand.
            local eased = p * p * (3 - 2 * p)
            element.selfStyle.width = w * eased
            --the font draws the letters low in the label's line box: at 19pt
            --the box is 22.8 tall and the lowercase body runs from 9 to 18
            --down (measured on screen), so the bar centres at 0.55 of the box.
            element.selfStyle.y = math.floor(h * 0.55 - ENTRY_STRIKE_THICKNESS / 2 + 0.5)
            --once drawn, keep following the title at a slow tick rather than
            --stopping: a card built already struck draws whole on its first
            --frame, when the title's box may not have its final height yet,
            --and freezing that reading left the bar over the letters' tops.
            --(Struck cards leave at the round's end, so this does not run long.)
            if p >= 1 then
                element.thinkTime = 0.2
            end
        end,
    }
    --the title is only as wide as its text (up to the column), so the bar
    --that crosses it out can be sized to the words rather than the column.
    nameLabel = gui.Label{ classes = {"eotwEntryName"}, text = entry.name, interactable = false, halign = "left",
        width = "auto", maxWidth = string.format("100%%-%d", nameReserve), children = {strike} }
    local function StrikeTitle(animate)
        if strike.data.struck then
            return
        end
        strike.data.struck = true
        strike.data.start = cond(animate, dmhub.Time(), nil)
        strike:SetClass("hidden", false)
        strike.thinkTime = 0.01
    end
    local heroSlot = CreateEntryHeroSlot(entry, slotTop)
    local statusLabel = gui.Label{
        classes = {"eotwEntryStatus"},
        text = "",
        interactable = false,
        width = textWidth,
        halign = "left",
    }
    ---@type Panel[]
    local cardChildren = {
        nameLabel,
        gui.Label{ classes = {"eotwEntryDesc"}, text = entry.description, interactable = false, width = textWidth, halign = "left" },
    }
    if outcomeRow ~= nil then
        cardChildren[#cardChildren + 1] = outcomeRow
    end
    --a deadline the party cannot see is not a deadline, so a "(Temporary)"
    --entry wears its own line. (The other two heading tags are bookkeeping
    --and are never shown anywhere.)
    if entry.temporary then
        local deadline = T("stage.entry.deadline")
        if entry.kind == "threat" and entry.consequence ~= nil then
            deadline = T("stage.entry.deadline_threat")
        end
        cardChildren[#cardChildren + 1] = gui.Label{
            classes = {"eotwEntryStatus", "deadline"},
            text = deadline,
            interactable = false,
            width = textWidth,
            halign = "left",
        }
    end
    cardChildren[#cardChildren + 1] = statusLabel
    --the slot floats, so it goes last: later siblings draw on top.
    cardChildren[#cardChildren + 1] = heroSlot

    local card = gui.Panel{
        classes = {"eotwEntryCard", entry.kind},
        width = "100%",
        height = "auto",
        flow = "vertical",
        pad = ENTRY_CARD_PAD,
        borderBox = true,
        --the hero slot floats, so it does not grow the card by itself: a
        --card with little text is still tall enough to hold it.
        minHeight = ENTRY_CARD_PAD * 2 + slotTop + ENTRY_HERO_SLOT_HEIGHT,
        vmargin = 5,
        bgimage = "panels/square.png",
        dragTarget = true,
        dragTargetPriority = 10,
        data = { entryId = entry.id, kind = entry.kind, available = false, refreshed = false },
        children = cardChildren,

        --the click alternative to dragging: a hero picked by a click on
        --its card, then a click here, approaches.
        press = function(element)
            local heroid = m_selectedHero
            if heroid == nil or m_selectMode ~= "approach" or not element.data.available or not EncounterMontage.LocalUserCanAct(heroid) then
                return
            end
            audio.FireSoundEvent("Mouse.Click")
            SelectHero(nil)
            EncounterMontage.SendRequest("approach", { heroid = heroid, entryId = entry.id })
        end,

        --highlight while a hero is being dragged or has been clicked to
        --approach (an item or a narrative pick leaves the columns alone).
        dragTargets = function(element, on, mode)
            element:SetClass("droppable", on == true and (mode or "approach") == "approach" and element.data.available)
        end,
        selectHero = function(element, heroid, mode)
            element:SetClass("droppable", heroid ~= nil and (mode or "approach") == "approach" and element.data.available)
        end,

        refreshMontage = function(element, m)
            --a card on its way out keeps the face it had when the round
            --ended; it is only fading.
            if element.data.leaving then
                return
            end
            local available = EncounterMontage.EntryAvailable(m, entry)
            local done = false
            local status = ""
            if entry.kind == "opportunity" then
                if (m.taken or {})[entry.id] then
                    done = true
                    status = T("stage.entry.status_taken")
                end
            else
                if (m.vanquished or {})[entry.id] then
                    done = true
                    status = T("stage.entry.status_vanquished")
                end
                --Challenge Mode: a threat to vanquish twice wears "x2" until
                --the first vanquish, then says how many times are left.
                local remaining = EncounterMontage.ThreatRemaining(m, entry)
                if remaining >= 2 then
                    nameLabel.text = T("stage.entry.name_times", { name = entry.name, count = remaining })
                else
                    nameLabel.text = entry.name
                end
                if not done and remaining < EncounterMontage.ThreatTimes(m, entry) then
                    status = TP("stage.entry.status_vanquished_partly", remaining, { count = remaining })
                end
            end
            --a resolved turn is over: its entry is open again at once (an
            --unvanquished threat may be tried by the next hero).
            local active = m.turn ~= nil and m.turn.entryId == entry.id and m.turn.status ~= "resolved"
            if active then
                status = T("stage.entry.status_hero_here", { hero = m.turn.heroName or T("stage.fallback.a_hero") })
            elseif status == "" and available then
                status = T("stage.entry.status_drag_here")
            end
            element.data.available = available and not active
            --dealt with: cross the title out. It sweeps across when it
            --happens in front of the party; a card that comes up already
            --done (a rebuild, a late joiner) is simply drawn struck.
            if done then
                StrikeTitle(element.data.refreshed)
            end
            element.data.refreshed = true
            element:SetClass("done", done)
            element:SetClass("active", active)
            element:SetClass("droppable", m_selectedHero ~= nil and m_selectMode == "approach" and element.data.available)
            statusLabel.text = status
        end,

        --the round ended and this entry was dealt with (or, a "(Temporary)"
        --one, carried off): fade the card away and drop it, so the columns
        --carry only what is still in play. A title not yet crossed out is
        --struck first and the fade waits for the stroke; returns that wait
        --through element.data.leaveDelay for the caller to stagger after.
        leave = function(element)
            if element.data.leaving then
                return
            end
            element.data.leaving = true
            element.data.available = false
            local delay = 0
            if not strike.data.struck then
                StrikeTitle(true)
                delay = ENTRY_STRIKE_TIME + 0.15
            end
            element.data.leaveDelay = delay
            element:ScheduleEvent("fadeOut", delay)
        end,
        fadeOut = function(element)
            element:SetClassTree("eotwEntryLeave", true)
            element:ScheduleEvent("gone", ENTRY_FADE_TIME + 0.05)
        end,
        gone = function(element)
            element:DestroySelf()
        end,
    }

    if appearIn ~= nil then
        --into the start state with no ramp, then a frame (plus this card's
        --stagger) later the class comes off and the transition runs.
        card:SetClassTreeImmediate("eotwEntryAppear", true)
        dmhub.Schedule(0.05 + appearIn, function()
            if mod.unloaded or card == nil or not card.valid then
                return
            end
            card:SetClassTree("eotwEntryAppear", false)
        end)
    end

    return card
end

--- the turn panel -----------------------------------------------------------------

local function IsMyTurn(m)
    return m.turn ~= nil and m.turn.userid == dmhub.loginUserid
end

--One line per rider on a test ("Edge: You speak Caelian"), coloured by how
--it fell for the hero at the entry when a verdict is known: an Allow rider
--reads "Unlocked" (violet) once met; an edge/bane rider lights green/red
--when it applies and dims when it does not. With no verdict (nobody at the
--entry) the lines are plain.
--A hero who does not meet an Allow requirement is not read the requirement
--back at them: every unmet Allow on the card collapses into one plain line
--(user direction 2026-09-19).
local function RiderRows(riders, verdict)
    local rows = {}
    local saidLocked = false
    for _, row in ipairs(TestRiders.DescribeRows(riders, verdict)) do
        local text = string.format("%s: %s", row.label, row.text)
        if row.state == "locked" then
            if saidLocked then
                goto continue
            end
            saidLocked = true
            text = T("stage.option.rider_locked")
        end
        rows[#rows + 1] = gui.Label{
            classes = Classes("eotwRider", row.state),
            text = text,
            interactable = false,
        }
        ::continue::
    end
    return rows
end

--Standing edges and banes an earlier outcome put on this test ("Edge on
--Capture Them"). They are not riders -- nobody has to meet anything, they
--apply to whoever takes the test -- so they get their own always-lit rows
--under the option's own rider lines.
local function GrantedRows(option)
    local rows = {}
    for _, g in ipairs(EncounterMontage.OptionTestMods(nil, option)) do
        local label = EncounterScript.RiderLabel(g.effect)
        local text = label
        if g.entryName ~= nil and g.entryName ~= "" then
            text = T("stage.option.granted_at", { label = label, entry = g.entryName })
        end
        rows[#rows + 1] = gui.Label{
            classes = Classes("eotwRider", cond(EncounterScript.RiderBoons(g.effect) > 0, "met", "hurt")),
            text = text,
            interactable = false,
        }
    end
    return rows
end

--The rules of a free version (no roll), marked up like a landed tier once
--they have been applied.
local function FreeRulesRow(free, applied)
    local text = EncounterScript.VisibleText(free.text or "")
    local markup = EncounterScript.MarkupRules(text, string.format("<color=%s>", RULES_COLOR), "</color>")
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        vmargin = 1,
        interactable = false,
        gui.Label{ classes = Classes("eotwTierText", applied and "landed"), width = "100%", text = markup, interactable = false },
    }
end

local function OptionCard(entry, option, index, m)
    local mine = IsMyTurn(m) and m.turn.status == "choosing"
    local chosen = m.turn ~= nil and m.turn.optionIndex == index
    local landed = nil
    if chosen and m.turn.status == "resolved" then
        landed = m.turn.tier
    elseif chosen and m.turn.status == "perk" then
        --a perk may still move the tier before anything is applied.
        landed = m.turn.baseTier
    end
    --the version of the option the hero at the entry takes: once chosen,
    --the one the host fixed; before that, the first knack they meet.
    local heroid = m.turn ~= nil and m.turn.heroid or nil
    local version = option
    local knackReason = nil
    if chosen then
        version = EncounterScript.OptionVersion(option, m.turn.knackIndex)
        knackReason = m.turn.knackReason
    elseif heroid ~= nil then
        version = EncounterMontage.OptionForHero(heroid, option)
        if version.knack ~= nil then
            knackReason = EncounterMontage.KnackReason(heroid, option, version.knackIndex)
        end
    end
    ---@type Panel[]
    local children = {
        gui.Label{ classes = {"eotwOptionName"}, text = option.name, interactable = false },
    }
    if (version.text or "") ~= "" then
        children[#children + 1] = gui.Label{ classes = {"eotwEntryDesc"}, text = version.text, interactable = false }
    end
    --the option's riders, weighed against the hero standing at the entry: a
    --secret option is never drawn for a hero who does not meet it, so here
    --a met Allow marks it special and says why.
    local verdict = nil
    if heroid ~= nil then
        verdict = EncounterMontage.RiderVerdict(heroid, option, version)
    end
    local locked = verdict ~= nil and not verdict.allowed
    local unlocked = (verdict ~= nil and verdict.gated and verdict.allowed) or version.knack ~= nil
    if version.knack ~= nil then
        children[#children + 1] = gui.Label{
            classes = {"eotwRider", "unlocked"},
            text = T("stage.option.knack", { knack = knackReason or version.knack.requirementText }),
            interactable = false,
        }
    end
    if version.roll ~= nil then
        children[#children + 1] = gui.Label{ classes = {"eotwOptionRoll"}, text = string.format("%s: %s", version.roll.name, EncounterScript.AttrWithoutSkills(version.roll.attr)), interactable = false }
        for _, row in ipairs(RiderRows(EncounterScript.VersionRiders(option, version), verdict)) do
            children[#children + 1] = row
        end
        for _, row in ipairs(GrantedRows(option)) do
            children[#children + 1] = row
        end
        if chosen and m.turn.blessing ~= nil then
            children[#children + 1] = gui.Label{
                classes = {"eotwRider", "met"},
                text = T("stage.option.blessed", { hero = m.turn.blessing.heroName or T("stage.option.blessed_fallback") }),
                interactable = false,
            }
        end
        local rows
        if chosen and (m.turn.status == "rolling" or m.turn.status == "pardon") then
            rows = LiveTierRows(version.roll)
        else
            rows = TierRows(version.roll, landed, true)
        end
        for _, row in ipairs(rows) do
            children[#children + 1] = row
        end
    elseif version.free ~= nil then
        children[#children + 1] = gui.Label{ classes = {"eotwOptionRoll"}, text = T("stage.option.no_roll_needed"), interactable = false }
        for _, row in ipairs(RiderRows(EncounterScript.VersionRiders(option, version), verdict)) do
            children[#children + 1] = row
        end
        children[#children + 1] = FreeRulesRow(version.free, chosen and m.turn.status == "resolved")
    end
    local takeable = version.roll ~= nil or version.free ~= nil or (option.delve ~= nil and (m.turn == nil or m.turn.delve == nil))
    return gui.Panel{
        classes = Classes("eotwOptionCard", mine and not locked and "actionable", chosen and "chosen", locked and "locked", unlocked and "unlocked"),
        width = "100%",
        height = "auto",
        flow = "vertical",
        pad = 10,
        borderBox = true,
        vmargin = 5,
        bgimage = "panels/square.png",
        children = children,
        --lit while the player hovers an item that would help this test.
        itemBenefitHighlight = function(element, set)
            element:SetClass("itemBenefit", set ~= nil and set[index] == true)
        end,
        press = function(element)
            --a "Delve:" option has no roll; it enters its delve instead.
            if not mine or locked or not takeable then
                return
            end
            audio.FireSoundEvent("Mouse.Click")
            EncounterMontage.SendRequest("choose", { optionIndex = index })
        end,
    }
end

--whose move it is now: shown whenever the floor is free, which includes
--over a resolved turn -- its result never holds the next hero up.
local function YourMoveLabel(classes)
    local mine = {}
    for _, hero in ipairs(EncounterMontage.Heroes()) do
        if EncounterMontage.LocalUserCanAct(hero.charid) then
            mine[#mine + 1] = hero.name
        end
    end
    local text = T("stage.montage.waiting_for_others")
    if #mine > 0 then
        text = T("stage.montage.your_move", { heroes = table.concat(mine, T("stage.montage.your_move_or")) })
    end
    return gui.Label{ classes = classes or {"eotwTurnHint"}, text = text }
end

--- perks on the stage ----------------------------------------------------------
--The montage plays a few perks by their real rules (EncounterMontage,
--"perks"). Their buttons go to whoever controls the hero with the perk.

--Does the local user control this hero?
local function LocalControls(charid)
    local tok = dmhub.GetCharacterById(charid)
    if tok == nil or not tok.valid then
        return false
    end
    local mine = nil
    pcall(function() mine = tok.canControlAsUser end)
    if mine == nil then
        pcall(function() mine = tok.canControl end)
    end
    return mine == true
end

local function PerkButton(label, tooltip, onPress)
    return gui.Panel{
        classes = {"eotwSceneOption", "actionable", "unlocked"},
        width = "auto",
        height = "auto",
        halign = "left",
        hpad = 14,
        vpad = 5,
        borderBox = true,
        vmargin = 2,
        bgimage = "panels/square.png",
        gui.Label{ classes = {"eotwSceneOptionName"}, text = label, interactable = false },
        linger = function(element)
            if tooltip ~= nil then
                gui.Tooltip(tooltip)(element)
            end
        end,
        press = function(element)
            audio.FireSoundEvent("Mouse.Click")
            onPress(element)
        end,
    }
end

--While a hero chooses: a Ritualist at the entry may bless the test they
--are about to take, once a round (the ritual needs a touch).
PerkActionChildren = function(m, t)
    local children = {}
    if t == nil or t.delve ~= nil then
        return children
    end
    if t.blessing ~= nil then
        children[#children + 1] = gui.Label{
            classes = {"eotwSceneHint"},
            text = T("stage.perk.blessed", { hero = t.blessing.heroName or T("stage.perk.blessed_fallback") }),
        }
        return children
    end
    local key = string.format("ritual:%d:%s", m.round or 1, t.heroid)
    if LocalControls(t.heroid) and not (m.perkUsed or {})[key] and EncounterMontage.HeroHasPerk(t.heroid, "Ritualist") then
        children[#children + 1] = PerkButton(T("stage.perk.bless_button"),
            T("stage.perk.bless_tooltip"),
            function(element)
                EncounterMontage.SendRequest("bless", { heroid = t.heroid })
                element:SetClass("hidden", true)
            end)
    end
    return children
end

--After a failed test: the perks that could rescue it, each to its owner.
PerkOfferChildren = function(m, t)
    local children = {}
    local rolled = T("stage.perk.rolled_tier", { hero = t.heroName or T("stage.fallback.the_hero"), tier = t.baseTier or t.tier or 1 })
    if t.baseTotal ~= nil then
        rolled = T("stage.perk.rolled_tier_total", { hero = t.heroName or T("stage.fallback.the_hero"), tier = t.baseTier or t.tier or 1, total = tostring(t.baseTotal) })
    end
    children[#children + 1] = gui.Label{ classes = {"eotwSceneHint"}, text = rolled }
    for i, offer in ipairs(t.offers or {}) do
        if LocalControls(offer.heroid) then
            children[#children + 1] = PerkButton(T("stage.perk.use_button", { hero = offer.heroName or T("stage.fallback.your_hero"), perk = offer.perk }), offer.text,
                function(element)
                    EncounterMontage.SendRequest("perkUse", { offerIndex = i })
                    element:SetClass("hidden", true)
                end)
            children[#children + 1] = gui.Panel{
                classes = {"eotwSceneOption", "actionable"},
                width = "auto",
                height = "auto",
                halign = "left",
                hpad = 14,
                vpad = 5,
                borderBox = true,
                vmargin = 2,
                bgimage = "panels/square.png",
                gui.Label{ classes = {"eotwSceneOptionName", "pass"}, text = T("stage.perk.dont_use_button", { perk = offer.perk }), interactable = false },
                press = function(element)
                    audio.FireSoundEvent("Mouse.Click")
                    EncounterMontage.SendRequest("perkPass", { offerIndex = i })
                    element:SetClass("hidden", true)
                end,
            }
        else
            children[#children + 1] = gui.Label{
                classes = {"eotwSceneHint"},
                text = T("stage.perk.may_use", { hero = offer.heroName or T("stage.fallback.a_hero"), perk = offer.perk }),
            }
        end
    end
    return children
end

--Pardon My Friend: another hero is making the failed test in the hero's place.
local function PardonChildren(m, t)
    local p = t.pardon or {}
    return {
        gui.Label{
            classes = {"eotwSceneHint"},
            text = T("stage.perk.pardon", { hero = t.heroName or T("stage.fallback.the_hero"), tier = t.baseTier or t.tier or 1,
                helper = p.heroName or T("stage.perk.pardon_helper_fallback") }),
        },
    }
end

--Round 1, before anyone acts: a Team Leader may spend a hero token so the
--whole party tests with their exploration skills. Afterwards, a reminder.
local function TeamLeaderChildren(m)
    local children = {}
    if m.teamLeader ~= nil then
        children[#children + 1] = gui.Label{
            classes = {"eotwTurnHint"},
            text = T("stage.perk.team_leader_active", { hero = m.teamLeader.heroName or T("stage.fallback.a_hero"),
                owner = m.teamLeader.heroName or T("stage.perk.team_leader_owner_fallback") }),
        }
        return children
    end
    if (m.round or 1) ~= 1 or next(m.acted or {}) ~= nil or m.turn ~= nil then
        return children
    end
    for _, hero in ipairs(EncounterMontage.Heroes()) do
        if LocalControls(hero.charid) and EncounterMontage.HeroHasPerk(hero.charid, "Team Leader") then
            children[#children + 1] = gui.Button{
                text = T("stage.perk.team_leader_button", { hero = hero.name or T("stage.fallback.your_hero") }),
                halign = "center",
                tmargin = 8,
                width = 380,
                height = 40,
                linger = function(element)
                    gui.Tooltip(T("stage.perk.team_leader_tooltip"))(element)
                end,
                click = function(element)
                    EncounterMontage.SendRequest("teamLeader", { heroid = hero.charid })
                    element:SetClass("hidden", true)
                end,
            }
        end
    end
    return children
end

local function DiceLanded(d)
    local n = 0
    for _, r in ipairs((d or {}).rolls or {}) do
        if r.total ~= nil then
            n = n + 1
        end
    end
    return n
end

local function TurnSignature(m)
    local t = m.turn or {}
    local d = t.delve or {}
    return table.concat({
        tostring(d.obstacleId), tostring(d.depth), tostring(d.chests),
        tostring(m.phase), tostring(m.round), tostring(t.seq), tostring(t.status), tostring(t.optionIndex),
        tostring(t.rollSeq), tostring(t.tier), tostring(m.consequenceIndex), tostring(#(m.log or {})),
        tostring(dmhub.loginUserid == t.userid),
        tostring((t.pardon or {}).rollSeq),
        tostring(t.knackIndex), tostring(#(t.offers or {})), tostring(t.blessing ~= nil and t.blessing.heroid or nil),
        tostring(m.teamLeader ~= nil), tostring(m.perkSeq),
        --an item used here can reveal an option or open a knack.
        tostring(m.consumeSeq),
        tostring((m.dice or {}).seq), tostring(DiceLanded(m.dice)),
    }, "|")
end

--The montage dice that are out (m.dice: a table roll, a recovery loss),
--one line per roll with its result once it lands, and for a table roll the
--table itself with the rows the dice landed on lit.
local function DiceCard(m, beat)
    local d = m.dice or {}
    ---@type Panel[]
    local children = {
        gui.Label{ classes = {"eotwOptionName"}, text = d.entryName or T("stage.dice.title_fallback"), interactable = false },
    }
    local tableKey = nil
    for _, r in ipairs(d.rolls or {}) do
        local result = T("stage.dice.result_rolling")
        if r.total ~= nil then
            result = tostring(r.total)
        elseif r.userid == dmhub.loginUserid then
            result = T("stage.dice.result_yours")
        end
        children[#children + 1] = gui.Label{
            classes = {"eotwOptionRoll"},
            text = T("stage.dice.roll_line", { hero = r.heroName or T("stage.fallback.a_hero"), label = r.label or T("stage.dice.label_fallback"), dice = r.dice or "?", result = result }),
            interactable = false,
        }
        if r.kind == "table" then
            tableKey = r.tableKey
        end
    end
    local entry = tableKey ~= nil and EncounterScript.FindEntry(beat, d.entryId) or nil
    local tableRoll = entry ~= nil and (entry.tables or {})[tableKey] or nil
    if tableRoll ~= nil then
        local lit = {}
        local any = false
        for _, r in ipairs(d.rolls or {}) do
            if r.kind == "table" and r.total ~= nil then
                local row = EncounterScript.ChestRow(tableRoll, r.total)
                if row ~= nil then
                    lit[row] = true
                    any = true
                end
            end
        end
        for _, row in ipairs(tableRoll.rows or {}) do
            local range = cond(row.lo == row.hi, tostring(row.lo), string.format("%d-%d", row.lo, row.hi))
            local landed = lit[row] == true
            local dim = any and not landed
            children[#children + 1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                vmargin = 1,
                interactable = false,
                gui.Label{ classes = Classes("eotwTierRange", landed and "landed", dim and "dim"), text = range, interactable = false },
                gui.Label{ classes = Classes("eotwTierText", landed and "landed", dim and "dim"), text = EncounterScript.VisibleText(row.text), interactable = false },
            }
        end
    end
    return gui.Panel{
        classes = {"eotwOptionCard"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        pad = 10,
        borderBox = true,
        vmargin = 5,
        bgimage = "panels/square.png",
        children = children,
    }
end

--"Roll your dice." or who the table is waiting on.
local function DiceHint(m)
    local waiting = {}
    for _, r in ipairs((m.dice or {}).rolls or {}) do
        if r.total == nil then
            if r.userid == dmhub.loginUserid then
                return T("stage.dice.hint_yours")
            end
            waiting[#waiting + 1] = r.heroName or T("stage.fallback.a_hero_lower")
        end
    end
    if #waiting == 0 then
        return T("stage.dice.hint_all_in")
    end
    return T("stage.dice.hint_waiting", { heroes = table.concat(waiting, ", ") })
end

--The Roll button for this user's montage dice, or nil when they have none
--waiting (or have already clicked it).
local function DiceRollButton(halign)
    if not EncounterMontage.MyDiceWaiting() then
        return nil
    end
    return gui.Panel{
        classes = {"eotwSceneOption", "actionable"},
        width = "auto",
        height = "auto",
        halign = halign or "left",
        hpad = 14,
        vpad = 5,
        borderBox = true,
        vmargin = 2,
        bgimage = "panels/square.png",
        gui.Label{ classes = {"eotwSceneOptionName"}, text = T("stage.dice.roll_button"), interactable = false },
        press = function(element)
            audio.FireSoundEvent("Mouse.Click")
            element:SetClass("hidden", true)
            EncounterMontage.RollMyDice()
        end,
    }
end

--- the scene stage -------------------------------------------------------------------
--
--While a hero is at an entry the centre panel is a small stage (user
--direction 2026-09-23): the hero's portrait on the left, whoever the scene
--brings on at the right, both standing on a dialog box along the bottom
--where narration (italic) and speech (under the speaker's name, with the
--speaker lit up on stage) type out. While the hero chooses,
--the box carries the bare option names, and hovering one lays its test out
--in the middle of the stage. What plays was worked out by the host
--(EncounterMontage's BuildScenePart); this only shows it.

--Point a portrait panel at a token's off-token portrait, cropped to fit.
--`keepBottom` (a fade fraction) crops the image so its bottom edge lies
--outside an edgeFade of that size: the portrait fades everywhere else but
--stands on a crisp foot.
local function SetPortraitFrom(element, tok, aspect, keepBottom)
    if tok == nil then
        return
    end
    local portrait = nil
    pcall(function() portrait = tok.offTokenPortrait end)
    if portrait == nil or portrait == "" then
        return
    end
    element.bgimage = portrait
    element.selfStyle.bgcolor = "white"
    local rect = nil
    if keepBottom ~= nil then
        --frame a taller crop, then trim its bottom band so the shown part
        --keeps the panel's aspect.
        pcall(function() rect = tok:GetPortraitRectForAspect(aspect * (1 - keepBottom), portrait) end)
        if rect ~= nil then
            local y1 = rect.y1 + (rect.y2 - rect.y1) * keepBottom
            if y1 < keepBottom then
                y1 = keepBottom
            end
            rect = { x1 = rect.x1, y1 = y1, x2 = rect.x2, y2 = rect.y2 }
        end
    else
        pcall(function() rect = tok:GetPortraitRectForAspect(aspect, portrait) end)
    end
    element.selfStyle.imageRect = rect
end

--One figure on the stage: the hero (args.charid) or a scene character,
--pictured by the bestiary monster that plays them (args.monster).
--The mark an emote puts over a figure's head ("alert" or "alarmed").
local function EmoteMarker(emote)
    if emote == "alert" then
        return gui.Panel{
            classes = {"eotwEmote", "eotwEmoteBalloon"},
            floating = true,
            width = 38,
            height = 38,
            halign = "right",
            valign = "top",
            bgimage = "panels/square.png",
            interactable = false,
            gui.Label{ classes = {"eotwEmoteBang"}, text = "!", interactable = false },
        }
    end
    local function Dash(angle, length)
        return gui.Panel{
            classes = {"eotwEmoteDash"},
            width = 5,
            height = length,
            valign = "bottom",
            hmargin = 3,
            rotate = angle,
            bgimage = "panels/square.png",
            interactable = false,
        }
    end
    return gui.Panel{
        classes = {"eotwEmote"},
        floating = true,
        width = "auto",
        height = 26,
        halign = "right",
        valign = "top",
        flow = "horizontal",
        interactable = false,
        Dash(30, 16),
        Dash(0, 22),
        Dash(-30, 16),
    }
end

local function SceneActor(args)
    local aspect = SCENE_PORTRAIT_WIDTH / SCENE_PORTRAIT_HEIGHT
    --"scared" jerks this wrapper about. It carries no style rules, so no
    --transitionTime smooths the jerks into a drift.
    local shakeUntil = 0
    local shaker = gui.Panel{
        width = "100%",
        height = SCENE_PORTRAIT_HEIGHT,
        interactable = false,
        think = function(element)
            if dmhub.Time() >= shakeUntil then
                element.selfStyle.x = 0
                element.selfStyle.y = 0
                element.thinkTime = nil
                return
            end
            element.selfStyle.x = math.random(-SCENE_SHAKE_PX, SCENE_SHAKE_PX)
            element.selfStyle.y = math.random(-2, 2)
        end,
    }
    local actor = gui.Panel{
        classes = {"eotwSceneActor"},
        width = SCENE_PORTRAIT_WIDTH,
        height = SCENE_PORTRAIT_HEIGHT,
        hmargin = 4,
        --the speaker grows from their feet, never down into the dialog box.
        pivot = { x = 0.5, y = 0 },
        interactable = false,
        gone = function(element)
            element:DestroySelf()
        end,
        --play an emote: "scared" trembles, the others put a mark over the
        --head that pops in, holds and fades.
        emote = function(element, emote)
            if emote == "scared" then
                shakeUntil = dmhub.Time() + SCENE_SHAKE_TIME
                shaker.thinkTime = 0.03
                return
            end
            local marker = EmoteMarker(emote)
            element:AddChild(marker)
            marker.selfStyle.x = 12
            marker.selfStyle.y = -24
            marker:SetClassTreeImmediate("eotwEmotePop", true)
            dmhub.Schedule(0.03, function()
                if mod.unloaded or not marker.valid then
                    return
                end
                marker:SetClassTree("eotwEmotePop", false)
            end)
            dmhub.Schedule(SCENE_EMOTE_HOLD, function()
                if mod.unloaded or not marker.valid then
                    return
                end
                marker:SetClassTree("eotwEmoteGone", true)
            end)
            dmhub.Schedule(SCENE_EMOTE_HOLD + SCENE_EMOTE_FADE + 0.05, function()
                if mod.unloaded or not marker.valid then
                    return
                end
                marker:DestroySelf()
            end)
        end,
        shaker,
    }
    shaker:AddChild(gui.Panel{
            classes = {"eotwScenePortrait"},
            floating = true,
            width = SCENE_PORTRAIT_WIDTH,
            height = SCENE_PORTRAIT_HEIGHT,
            valign = "bottom",
            bgimage = "panels/square.png",
            bgcolor = "#00000000",
            --no card: the portrait fades into the scene at its top and sides.
            --Set on the panel itself -- edgeFade from a class rule is not
            --applied (verified live 2026-09-23).
            edgeFade = SCENE_PORTRAIT_FADE,
            interactable = false,
            create = function(element)
                if args.charid ~= nil then
                    local tok = dmhub.GetCharacterById(args.charid)
                    if tok ~= nil and tok.valid then
                        SetPortraitFrom(element, tok, aspect, SCENE_PORTRAIT_FADE)
                    end
                    return
                end
                local _, asset = EncounterMontage.FindMonster(args.monster)
                if asset == nil then
                    _, asset = EncounterMontage.FindMonster(args.name)
                end
                if asset ~= nil then
                    local info = nil
                    pcall(function() info = asset.info end)
                    SetPortraitFrom(element, info, aspect, SCENE_PORTRAIT_FADE)
                end
            end,
        })
    local nameShadow = gui.Label{ classes = {"eotwSceneActorName", "shadow"}, floating = true, valign = "bottom", bmargin = 6, text = args.name or "", interactable = false }
    nameShadow.selfStyle.x = 2
    nameShadow.selfStyle.y = 2
    shaker:AddChild(nameShadow)
    shaker:AddChild(gui.Label{ classes = {"eotwSceneActorName"}, floating = true, valign = "bottom", bmargin = 6, text = args.name or "", interactable = false })
    return actor
end

--The page prompt: a small caret that blinks at the end of the line once it
--has finished typing, for the player who turns the page.
local function ScenePrompt(floating)
    return gui.Panel{
        classes = {"eotwScenePrompt", "collapsed"},
        floating = floating,
        width = 18,
        height = 18,
        halign = "right",
        valign = "bottom",
        bgimage = "phosphor/caret-down-fill.png",
        interactable = false,
        thinkTime = SCENE_PROMPT_BLINK,
        think = function(element)
            element:SetClass("dimmed", not element:HasClass("dimmed"))
        end,
    }
end

local function CreateSceneStage()
    local m_heroid = nil
    --the characters on the right, by lowered name.
    local m_actors = {}
    --the line on screen ("sceneId:index"), so a refresh that changes
    --nothing about it does not restart its typing.
    local m_textKey = nil
    --the line being typed: { label, full, total, start }.
    local m_typing = nil
    --the garbled line on screen, while it is still garbled: { key, plain,
    --speaker, lang, t }. Watched so it can be translated in place.
    local m_garbledShown = nil
    --the prompt belonging to the text on screen.
    local m_prompt = nil
    local m_boxKey = nil
    --false until the stage has shown something. A stage that comes up with
    --a turn already in progress (a join, a reload) shows it settled, with
    --no typing and no entrances.
    local m_settled = false

    local root

    local titleLabel = gui.Label{ classes = {"eotwSceneTitle"}, text = "" }
    --the figures stand on the dialog box: hero at the left, cast at the right.
    local castRow = gui.Panel{ floating = true, width = "auto", height = "auto", halign = "right", valign = "bottom", flow = "horizontal" }
    --the cast's own size (smaller when two or more share the stage), and how
    --much every figure shrinks so it fits under the title on a short stage
    --(stageArea's think). The cast's uiscale is the product of the two.
    local m_castScale = 1
    local m_fit = 1

    --The hero at the entry, at the left. stageArea's fit shrinks it with a
    --transform scale from its feet, so its layout stays in unscaled units.
    local heroSlot = gui.Panel{
        floating = true,
        width = "100%",
        height = SCENE_PORTRAIT_HEIGHT,
        halign = "left",
        valign = "bottom",
        flow = "none",
        pivot = { x = 0, y = 0 },
    }
    local m_mainFigure = nil

    --One hero on the stage.
    local function CreateFigure(charid, name)
        local actor = SceneActor{ name = name, charid = charid }
        return gui.Panel{
            width = SCENE_FIGURE_WIDTH,
            height = SCENE_PORTRAIT_HEIGHT,
            halign = "left",
            valign = "bottom",
            flow = "none",
            data = { charid = charid, actor = actor },
            actor,
        }
    end

    --Put the turn's hero on the stage (a new hero replaces the last).
    local function SyncHero(t)
        if m_mainFigure == nil or not m_mainFigure.valid or m_mainFigure.data.charid ~= t.heroid then
            m_mainFigure = CreateFigure(t.heroid, t.heroName)
            heroSlot.children = { m_mainFigure }
        end
    end

    --the middle of the stage: the test of the option under the mouse, or of
    --the one being rolled / already rolled.
    local detail = gui.Panel{
        classes = {"collapsed"},
        floating = true,
        width = "46%",
        height = "100%",
        halign = "center",
        valign = "top",
        flow = "vertical",
        vscroll = true,
    }
    local m_detailDefault = {}
    local function ShowDetail(children)
        detail.children = children or {}
        detail:SetClass("collapsed", #(children or {}) == 0)
    end

    --top-aligned: a short line reads from the top of the box, not its middle.
    --the dialog box: who is speaking (collapsed for narration), then the line.
    local speakerLabel = gui.Label{ classes = {"eotwSceneSpeaker", "collapsed"}, valign = "top", text = "", interactable = false }
    local narration
    local boxExtra = gui.Panel{ width = "100%", height = "auto", valign = "top", flow = "vertical" }
    local boxPrompt = ScenePrompt(true)
    local StartTyping

    --The group has just come to speak the language of the garbled line on
    --screen (an item such as Imp's Tongue): the garbled words fade out and the
    --line fades back in as written, in an ordinary font.
    local function TransposeLine()
        local shown = m_garbledShown
        m_garbledShown = nil
        if shown == nil then
            return
        end
        narration:SetClass("transposing", true)
        dmhub.Schedule(0.5, function()
            if mod.unloaded or narration == nil or not narration.valid then
                return
            end
            if m_textKey ~= shown.key then
                --the page turned while it faded.
                narration:SetClass("transposing", false)
                return
            end
            narration:SetClass("garbled", false)
            narration.selfStyle.fontFace = nil
            speakerLabel.text = T("stage.scene.speaker_in_language", { speaker = shown.speaker, language = shown.lang })
            StartTyping(narration, shown.plain, true)
            narration:SetClass("transposing", false)
            narration:PulseClass("translated")
        end)
    end

    narration = gui.Label{
        classes = {"eotwSceneNarration"},
        valign = "top",
        text = "",
        interactable = false,
        thinkTime = 0.5,
        think = function(element)
            local shown = m_garbledShown
            if shown ~= nil and shown.key == m_textKey and EncounterMontage.HeroSpeaks(shown.t, shown.lang) then
                TransposeLine()
            end
        end,
    }

    local function ShowPrompt()
        boxPrompt:SetClass("collapsed", true)
        if m_typing ~= nil or m_prompt == nil then
            return
        end
        local m = EncounterMontage.GetState()
        if not EncounterMontage.LocalUserPacesScene(m) then
            return
        end
        --LocalUserPacesScene is false when m is nil.
        ---@cast m -nil
        local index = EncounterMontage.SceneCursor(m)
        if index ~= nil and index <= #((m.turn.scene or {}).steps or {}) then
            m_prompt:SetClass("collapsed", false)
        end
    end

    local function FinishTyping()
        if m_typing == nil then
            return
        end
        m_typing.label.text = m_typing.full
        m_typing = nil
        root.thinkTime = nil
        ShowPrompt()
    end

    StartTyping = function(label, text, instant)
        m_typing = nil
        if instant or text == "" then
            label.text = text
            ShowPrompt()
            return
        end
        label.text = RevealText(text, 0)
        m_typing = { label = label, full = text, total = VisibleLength(text), start = dmhub.Time() }
        root.thinkTime = 0.03
        ShowPrompt()
    end

    --a click on the line: the first finishes the typing, the next (from the
    --player pacing the scene) turns the page.
    local function PagePressed()
        if m_typing ~= nil then
            FinishTyping()
            return
        end
        if EncounterMontage.AdvanceScene() then
            audio.FireSoundEvent("Mouse.Click")
        end
    end

    local box = gui.Panel{
        classes = {"eotwSceneBox"},
        width = "100%",
        height = SCENE_BOX_HEIGHT,
        valign = "bottom",
        bgimage = "panels/square.png",
        pad = 14,
        borderBox = true,
        press = PagePressed,
        gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",
            vscroll = true,
            speakerLabel,
            narration,
            boxExtra,
        },
        boxPrompt,
    }

    --flush against the box, so the figures stand right on it.
    local stageArea = gui.Panel{
        width = "100%",
        height = string.format("100%%-%d", SCENE_BOX_HEIGHT + SCENE_TITLE_HEIGHT),
        --A figure is a fixed SCENE_PORTRAIT_HEIGHT tall, so on a short stage
        --(the montage's turn panel on a small screen) it would reach up over
        --the title. Shrink the hero and the cast to the room there is. The
        --hero uses a transform scale from its bottom-left corner, so its
        --layout stays in unscaled units.
        thinkTime = 0.25,
        think = function(element)
            local h = element.renderedHeight
            if h == nil or h <= 0 then
                return
            end
            local fit = math.min(1, h / (SCENE_PORTRAIT_HEIGHT * SCENE_SPEAKING_SCALE))
            if math.abs(fit - m_fit) < 0.01 then
                return
            end
            m_fit = fit
            heroSlot.selfStyle.scale = fit
            castRow.selfStyle.uiscale = m_castScale * fit
        end,
        heroSlot,
        castRow,
        detail,
    }

    --who is lit: the speaker; everyone else is dimmed while someone speaks,
    --and nobody is while the narrator has the floor.
    local function SetSpeaking(side, speaker)
        if m_mainFigure ~= nil and m_mainFigure.valid then
            m_mainFigure.data.actor:SetClassTree("speaking", side == "left")
            m_mainFigure.data.actor:SetClassTree("quiet", side == "right")
        end
        for key, panel in pairs(m_actors) do
            local speaking = side == "right" and key == string.lower(speaker or "")
            panel:SetClassTree("speaking", speaking)
            panel:SetClassTree("quiet", side ~= nil and not speaking)
        end
    end

    --the emotes that come with a line, on the figures they belong to.
    local function PlayEmotes(emotes)
        for _, e in ipairs(emotes or {}) do
            local panel = nil
            if e.side == "left" then
                panel = m_mainFigure ~= nil and m_mainFigure.data.actor or nil
            else
                panel = m_actors[string.lower(e.name or "")]
            end
            if panel ~= nil and panel.valid then
                panel:FireEvent("emote", e.emote)
            end
        end
    end

    --bring the right-hand side in line with `cast`: newcomers fade in,
    --leavers fade out.
    local function SyncCast(cast, instant)
        local want = {}
        for _, c in ipairs(cast or {}) do
            want[string.lower(c.name)] = true
        end
        for key, panel in pairs(m_actors) do
            if not want[key] then
                m_actors[key] = nil
                if panel.valid then
                    if instant then
                        panel:DestroySelf()
                    else
                        panel:SetClassTree("eotwSceneOffstage", true)
                        panel:ScheduleEvent("gone", SCENE_ACTOR_FADE + 0.05)
                    end
                end
            end
        end
        for _, c in ipairs(cast or {}) do
            local key = string.lower(c.name)
            if m_actors[key] == nil then
                local panel = SceneActor{ name = c.name, monster = c.monster }
                m_actors[key] = panel
                castRow:AddChild(panel)
                if not instant then
                    panel:SetClassTreeImmediate("eotwSceneOffstage", true)
                    dmhub.Schedule(0.05, function()
                        if mod.unloaded or not panel.valid then
                            return
                        end
                        panel:SetClassTree("eotwSceneOffstage", false)
                    end)
                end
            end
        end
        --two or more characters share the right-hand side at a smaller size.
        m_castScale = cond(#(cast or {}) > 1, 0.8, 1)
        castRow.selfStyle.uiscale = m_castScale * m_fit
    end

    --The option names along the bottom while the hero chooses. Hovering one
    --puts its full test (roll, riders, tiers) in the middle of the stage.
    local function OptionButtons(m, entry)
        local t = m.turn
        local mine = IsMyTurn(m)
        local parse = CurrentParse()
        local buttons = {}
        --everyone but the chooser gets the options as dotted ghosts: a click
        --pings that option for the whole table, and every copy -- the
        --chooser's real one included -- pulses in the pinger's colour. Rides
        --the roll button pings (Timeline's EmbeddedRollDialog.lua), keyed to
        --this turn; only pings made after these buttons were built pulse.
        local canPing = CharacterPanel ~= nil and CharacterPanel.SendRollButtonPing ~= nil
        local pingKey = string.format("montage:%s:%s", tostring(t.entryId), tostring(t.seq))
        local pingSince = dmhub.serverTime
        local pingSeen = {}
        local optionPanels = {}
        local pingDocPath = nil
        if canPing then
            pingDocPath = CharacterPanel.RollButtonPingDocPath()
        end
        for i, option in ipairs(entry.options) do
            --a secret option the hero at the entry does not qualify for is
            --not drawn at all -- for them, or for anyone watching them.
            if not EncounterMontage.OptionVisible(t.heroid, option) then
                goto nextOption
            end
            local version = EncounterMontage.OptionForHero(t.heroid, option)
            local verdict = EncounterMontage.RiderVerdict(t.heroid, option, version)
            local locked = verdict ~= nil and not verdict.allowed
            local unlocked = (verdict ~= nil and verdict.gated and verdict.allowed) or version.knack ~= nil
            local takeable = version.roll ~= nil or version.free ~= nil or (option.delve ~= nil and t.delve == nil)
            local optionPanel = gui.Panel{
                classes = Classes("eotwSceneOption", mine and not locked and "actionable", locked and "locked", unlocked and "unlocked", canPing and not mine and "pingGhost"),
                width = "auto",
                height = "auto",
                halign = "left",
                flow = "horizontal",
                hpad = 14,
                vpad = 5,
                borderBox = true,
                vmargin = 2,
                bgimage = "panels/square.png",
                children = Classes(
                    gui.Label{ classes = Classes("eotwSceneOptionName", locked and "locked"), text = option.name, interactable = false, valign = "center" },
                    (version.roll == nil and version.free ~= nil) and gui.Label{ classes = {"eotwSceneOptionTag"}, text = T("stage.scene.option_no_roll_tag"), interactable = false, valign = "center" } or nil,
                    OutcomeIconRow(EncounterScript.OptionOutcomes(version, parse, entry), 16, { lmargin = 10 })
                ),
                hover = function(element)
                    ShowDetail({ OptionCard(entry, option, i, m) })
                end,
                --lit while the player hovers an item that would help here.
                itemBenefitHighlight = function(element, set)
                    element:SetClass("itemBenefit", set ~= nil and set[i] == true)
                end,
                dehover = function(element)
                    ShowDetail(m_detailDefault)
                end,
                linger = function(element)
                    if canPing and not mine and not locked and takeable then
                        gui.Tooltip(T("stage.scene.option_ping_tooltip", { hero = t.heroName or T("stage.fallback.the_hero_lower") }))(element)
                    end
                end,
                press = function(element)
                    if locked or not takeable then
                        return
                    end
                    if not mine then
                        if canPing then
                            audio.FireSoundEvent("Mouse.Click")
                            CharacterPanel.SendRollButtonPing(pingKey, tostring(i))
                        end
                        return
                    end
                    --a "Delve:" option has no roll; it enters its delve instead.
                    audio.FireSoundEvent("Mouse.Click")
                    EncounterMontage.SendRequest("choose", { optionIndex = i })
                end,
            }
            optionPanels[tostring(i)] = optionPanel
            buttons[#buttons + 1] = optionPanel
            ::nextOption::
        end
        --inside a delve the way out is turning back at a chest, not leaving
        --an obstacle half met.
        if mine and t.delve == nil then
            --no free withdrawal: having approached, the only way out is to
            --do nothing, which costs the hero their turn (user direction
            --2026-09-19).
            buttons[#buttons + 1] = gui.Panel{
                classes = {"eotwSceneOption", "actionable"},
                width = "auto",
                height = "auto",
                halign = "left",
                hpad = 14,
                vpad = 5,
                borderBox = true,
                vmargin = 2,
                bgimage = "panels/square.png",
                gui.Label{ classes = {"eotwSceneOptionName", "pass"}, text = T("stage.scene.leave_button"), interactable = false },
                linger = function(element)
                    gui.Tooltip(T("stage.scene.leave_tooltip"))(element)
                end,
                press = function(element)
                    audio.FireSoundEvent("Mouse.Click")
                    EncounterMontage.SendRequest("pass", {})
                end,
            }
        end
        return {
            gui.Label{
                classes = {"eotwSceneHint"},
                text = cond(mine, T("stage.scene.choose_prompt"), T("stage.scene.hero_choosing", { hero = t.heroName or T("stage.fallback.the_hero") })),
            },
            --one option per row, like an RPG choice menu.
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                children = buttons,
                monitorGame = pingDocPath,
                refreshGame = function(element)
                    if not canPing then
                        return
                    end
                    for _, ping in ipairs(CharacterPanel.TakeRollButtonPings(pingKey, pingSince, pingSeen)) do
                        CharacterPanel.PulseRollButton(optionPanels[ping.button], ping.userid)
                    end
                end,
            },
        }
    end

    --A delve's chest table, in the middle of the stage from the moment its
    --dice are out until the hero takes the find: one row per range, the
    --same look as a test's tier rows. A row the party has never landed on
    --reads "???" (EncounterMontage.ChestRowSeen). While the dice tumble, the
    --row their running total would land on is highlighted; once landed
    --(t.chest.rowIndex) the card rests on that row, and a row nobody had
    --seen shows "???" a moment longer, then types its treasure in.
    local function ChestCard(chestTable, t)
        local c = t.chest or {}
        local delveName = t.delve ~= nil and t.delve.name or nil
        local landedIndex = cond(t.status == "chestlanded", c.rowIndex, nil)
        ---@type Panel[]
        local children = {
            gui.Label{ classes = {"eotwOptionName"}, text = T("stage.chest.title"), interactable = false },
            gui.Label{ classes = {"eotwOptionRoll"}, text = string.format("%s: %s", chestTable.name or T("stage.chest.table_fallback"), chestTable.dice or "1d6"), interactable = false },
        }
        local rowPanels = {}
        for i, row in ipairs(chestTable.rows or {}) do
            local range = cond(row.lo == row.hi, tostring(row.lo), string.format("%d-%d", row.lo, row.hi))
            local full = EncounterScript.VisibleText(row.text)
            --only a client that watched the landing plays the reveal; a
            --late joiner sees it settled.
            local reveal = landedIndex == i and c.newReveal == true
                and dmhub.serverTime - (tonumber(c.landedAt) or 0) < CHEST_REVEAL_WINDOW
            local text = full
            if reveal or not EncounterMontage.ChestRowSeen(delveName, row) then
                text = "???"
            end
            local textLabel = gui.Label{ classes = {"eotwTierText"}, text = text, interactable = false }
            local panel = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                vmargin = 1,
                interactable = false,
                gui.Label{ classes = {"eotwTierRange"}, text = range, interactable = false },
                textLabel,
                think = function(element)
                    local r = element.data.reveal
                    if r == nil then
                        element.thinkTime = nil
                        return
                    end
                    local now = dmhub.Time()
                    if now < r.start then
                        return
                    end
                    local n = math.floor((now - r.start) * SCENE_TYPE_CPS)
                    if n >= r.total then
                        textLabel.text = r.full
                        element.data.reveal = nil
                        element.thinkTime = nil
                    else
                        textLabel.text = RevealText(r.full, n)
                    end
                end,
            }
            panel.data = {}
            if reveal then
                panel.data.reveal = { full = full, total = VisibleLength(full), start = dmhub.Time() + CHEST_REVEAL_DELAY }
                panel.thinkTime = 0.03
            end
            rowPanels[i] = panel
        end

        --light one row (nil = none) and dim the rest.
        local function MarkRow(index)
            for i, panel in ipairs(rowPanels) do
                for _, label in ipairs(panel.children) do
                    label:SetClass("landed", index == i)
                    label:SetClass("dim", index ~= nil and index ~= i)
                end
            end
        end

        local function RowFor(total)
            for i, row in ipairs(chestTable.rows or {}) do
                if total >= row.lo and total <= row.hi then
                    return i
                end
            end
            return nil
        end

        children[#children + 1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            interactable = false,
            children = rowPanels,
            data = { dice = nil, faces = {} },
            create = function(element)
                if landedIndex ~= nil then
                    MarkRow(landedIndex)
                elseif t.status == "chest" then
                    element.thinkTime = 0.1
                end
            end,
            --wait for the chest's dice: the roller's own client knows them
            --the moment they are thrown, everyone else once the host has them.
            think = function(element)
                local m = EncounterMontage.GetState()
                local turn = m ~= nil and m.turn or nil
                if turn == nil or turn.status ~= "chest" then
                    element.thinkTime = nil
                    return
                end
                local dice = turn.chest
                local localDice = EncounterMontage.localChestDice
                if localDice ~= nil and localDice.rollSeq == turn.rollSeq then
                    dice = localDice
                end
                if dice == nil or dice.guids == nil or #dice.guids == 0 then
                    return
                end
                element.thinkTime = nil
                element.data.dice = dice
                for _, guid in ipairs(dice.guids) do
                    local events = chat.DiceEvents(guid)
                    if events ~= nil then
                        events:Listen(element)
                    end
                end
            end,
            diceface = function(element, diceguid, num)
                local dice = element.data.dice
                if dice == nil then
                    return
                end
                element.data.faces[diceguid] = num
                local total = tonumber(dice.mod) or 0
                local count = 0
                for _, value in pairs(element.data.faces) do
                    count = count + 1
                    total = total + value
                end
                if count >= #dice.guids then
                    MarkRow(RowFor(total))
                end
            end,
        }
        return gui.Panel{
            classes = {"eotwOptionCard"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            pad = 10,
            borderBox = true,
            vmargin = 5,
            bgimage = "panels/square.png",
            children = children,
        }
    end

    --What a delve has granted so far, in the middle of the stage while the
    --hero decides whether to press on.
    local function HaulCard(t)
        local rows = {
            gui.Label{ classes = {"eotwOptionName"}, text = T("stage.delve.haul_title", { delve = t.delve.entryName or T("stage.delve.haul_title_fallback") }), interactable = false },
            gui.Label{
                classes = {"eotwOptionRoll"},
                text = T("stage.delve.haul_summary", {
                    obstacles = TP("stage.count.obstacles", t.delve.depth or 0),
                    chests = TP("stage.count.chests", t.delve.chests or 0),
                    recoveries = TP("stage.count.recoveries", EncounterMontage.HeroRecoveries(t.heroid)) }),
                interactable = false,
            },
        }
        for _, line in ipairs(t.delve.applied or {}) do
            rows[#rows + 1] = gui.Label{ classes = {"eotwAppliedLine"}, textAlignment = "left", text = line, interactable = false }
        end
        return gui.Panel{
            classes = {"eotwOptionCard"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            pad = 10,
            borderBox = true,
            vmargin = 5,
            bgimage = "panels/square.png",
            children = rows,
        }
    end

    local function DelveChoiceButtons(m, t)
        local mine = IsMyTurn(m)
        local delve = EncounterMontage.TurnDelve(t)
        --an in-order delve (a story chain) presses on for free.
        local ordered = delve ~= nil and delve.ordered == true
        ---@type Panel[]
        local children = {
            gui.Label{
                classes = {"eotwSceneHint"},
                text = cond(mine, cond(ordered, T("stage.delve.prompt_ordered"), T("stage.delve.prompt")), T("stage.delve.hero_deciding", { hero = t.heroName or T("stage.fallback.the_hero") })),
            },
        }
        if mine then
            local function Button(label, kind, tooltip, locked)
                return gui.Panel{
                    classes = Classes("eotwSceneOption", not locked and "actionable", locked and "locked"),
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    hpad = 14,
                    vpad = 5,
                    borderBox = true,
                    vmargin = 2,
                    bgimage = "panels/square.png",
                    gui.Label{ classes = Classes("eotwSceneOptionName", locked and "locked"), text = label, interactable = false },
                    linger = function(element)
                        gui.Tooltip(tooltip)(element)
                    end,
                    press = function(element)
                        if locked then
                            return
                        end
                        audio.FireSoundEvent("Mouse.Click")
                        EncounterMontage.SendRequest(kind, {})
                    end,
                }
            end
            --pressing on costs a Recovery up front (EncounterMontage.CanPressDeeper).
            local cost = EncounterMontage.DelvePressOnCost(delve)
            local costText = TP("stage.count.recoveries", cost)
            if ordered then
                children[#children + 1] = Button(T("stage.delve.press_on_button"), "delveOn", T("stage.delve.press_on_tooltip"))
            elseif EncounterMontage.CanPressDeeper(t.heroid, delve) then
                children[#children + 1] = Button(T("stage.delve.press_deeper_button", { cost = costText }), "delveOn",
                    T("stage.delve.press_deeper_tooltip", { cost = costText }))
            else
                children[#children + 1] = Button(T("stage.delve.press_deeper_button", { cost = costText }), "delveOn",
                    T("stage.delve.press_deeper_locked_tooltip", { cost = costText }), true)
            end
            children[#children + 1] = Button(T("stage.delve.turn_back_button"), "delveOut", T("stage.delve.turn_back_tooltip"))
        end
        return children
    end

    local function Render(m, beat)
        local t = m.turn
        local entry = EncounterScript.FindEntry(beat, t.entryId)
        if entry == nil then
            return
        end
        local instant = not m_settled
        m_settled = true

        --inside a delve, the obstacle the hero faces is what is on offer.
        local here = EncounterMontage.TurnEntry(beat, t) or entry
        if t.delve ~= nil and here ~= entry then
            titleLabel.text = T("stage.scene.title_delve_place", { hero = t.heroName or T("stage.fallback.a_hero"), entry = entry.name, place = here.name })
        elseif t.delve ~= nil then
            titleLabel.text = T("stage.scene.title_delve", { hero = t.heroName or T("stage.fallback.a_hero"), entry = entry.name })
        else
            titleLabel.text = T("stage.scene.title_approach", { hero = t.heroName or T("stage.fallback.a_hero"), entry = entry.name })
        end
        m_heroid = t.heroid
        SyncHero(t)

        local scene = t.scene or {}
        local steps = scene.steps or {}
        local index = EncounterMontage.SceneCursor(m)
        local step = nil
        if index ~= nil and #steps > 0 then
            index = math.min(index, #steps)
            step = steps[index]
        end
        SyncCast(step ~= nil and step.cast or scene.cast, instant)

        if step ~= nil then
            m_boxKey = nil
            ShowDetail({})
            boxExtra.children = {}
            --the first line of an approach shows nothing about the entry yet,
            --so a mis-clicked hero may still walk away for free.
            if IsMyTurn(m) and EncounterMontage.CanBackOut(m) then
                boxExtra.children = {
                    gui.Panel{
                        classes = {"eotwSceneOption", "actionable"},
                        width = "auto",
                        height = "auto",
                        halign = "left",
                        hpad = 14,
                        vpad = 5,
                        borderBox = true,
                        tmargin = 8,
                        bgimage = "panels/square.png",
                        --the box's own press turns the page, which would
                        --move past the first line and void the back-out.
                        swallowPress = true,
                        gui.Label{ classes = {"eotwSceneOptionName", "pass"}, text = T("stage.scene.back_out_button"), interactable = false },
                        linger = function(element)
                            gui.Tooltip(T("stage.scene.back_out_tooltip"))(element)
                        end,
                        press = function(element)
                            audio.FireSoundEvent("Mouse.Click")
                            EncounterMontage.SendRequest("backout", {})
                        end,
                    },
                }
            end
            narration:SetClass("collapsed", false)
            local key = string.format("%s:%d", tostring(scene.id), index)
            if key == m_textKey then
                --the last line has been read and the host is moving on.
                ShowPrompt()
                return
            end
            m_textKey = key
            if not instant then
                PlayEmotes(step.emotes)
            end
            m_prompt = boxPrompt
            m_garbledShown = nil
            narration:SetClass("transposing", false)
            local text = step.text or ""
            if step.kind == "say" then
                --speech takes the narrator's place in the box, under the
                --speaker's name, and the speaker lights up on stage.
                local side = cond(step.side == "left", "left", "right")
                --a line garbled when the scene was built reads as written
                --once the hero speaks its language (an item used since).
                local garbled = step.garbled == true
                if garbled and step.plain ~= nil and EncounterMontage.HeroSpeaks(t, step.lang) then
                    garbled = false
                    text = step.plain
                end
                local name = step.speaker or ""
                if step.lang ~= nil then
                    name = cond(garbled, T("stage.scene.speaker_speaking_language", { speaker = name, language = step.lang }), T("stage.scene.speaker_in_language", { speaker = name, language = step.lang }))
                end
                speakerLabel.text = name
                speakerLabel:SetClass("collapsed", false)
                narration:SetClass("speech", true)
                narration:SetClass("garbled", garbled)
                --words the hero can't understand appear in the language's
                --own script (Dwarvish runes, Tengwar, ...).
                narration.selfStyle.fontFace = cond(garbled, Language.UnreadableFontForName(step.lang), nil)
                if garbled and step.plain ~= nil then
                    m_garbledShown = { key = key, plain = step.plain, speaker = step.speaker or "", lang = step.lang, t = t }
                end
                SetSpeaking(side, step.speaker)
            else
                speakerLabel:SetClass("collapsed", true)
                narration:SetClass("speech", false)
                narration:SetClass("garbled", false)
                narration.selfStyle.fontFace = nil
                SetSpeaking(nil)
            end
            StartTyping(narration, text, instant)
            return
        end

        --between lines: the choice, the roll, the result.
        m_textKey = nil
        m_typing = nil
        m_prompt = nil
        root.thinkTime = nil
        ShowPrompt()
        SetSpeaking(nil)
        speakerLabel:SetClass("collapsed", true)
        narration:SetClass("collapsed", true)

        local boxKey = TurnSignature(m)
        if boxKey == m_boxKey then
            return
        end
        m_boxKey = boxKey
        local option = here.options[t.optionIndex or 0]
        m_detailDefault = {}
        if t.status == "choosing" then
            local buttons = OptionButtons(m, here)
            for _, child in ipairs(PerkActionChildren(m, t)) do
                buttons[#buttons + 1] = child
            end
            boxExtra.children = buttons
        elseif t.status == "chest" or t.status == "chestlanded" then
            local delve = EncounterMontage.TurnDelve(t)
            local chest = delve ~= nil and delve.sections.chest or nil
            if chest ~= nil and chest.table ~= nil then
                m_detailDefault = { ChestCard(chest.table, t) }
            end
            if t.status == "chest" then
                boxExtra.children = {
                    gui.Label{
                        classes = {"eotwSceneHint"},
                        text = cond(IsMyTurn(m), T("stage.chest.prompt_roll"), T("stage.chest.hero_opening", { hero = t.heroName or T("stage.fallback.the_hero") })),
                    },
                }
            else
                --the roll rests on its row until the hero takes the find.
                ---@type Panel[]
                local landed = {
                    gui.Label{
                        classes = {"eotwSceneHint"},
                        text = T("stage.chest.hero_rolls", { hero = t.heroName or T("stage.fallback.the_hero"), total = tostring((t.chest or {}).total or "?") }),
                    },
                }
                if IsMyTurn(m) then
                    landed[#landed + 1] = gui.Panel{
                        classes = {"eotwSceneOption", "actionable"},
                        width = "auto",
                        height = "auto",
                        halign = "left",
                        hpad = 14,
                        vpad = 5,
                        borderBox = true,
                        vmargin = 2,
                        bgimage = "panels/square.png",
                        gui.Label{ classes = {"eotwSceneOptionName"}, text = T("stage.chest.continue_button"), interactable = false },
                        press = function(element)
                            audio.FireSoundEvent("Mouse.Click")
                            EncounterMontage.SendRequest("chestTake", {})
                        end,
                    }
                end
                boxExtra.children = landed
            end
        elseif t.status == "delvechoice" then
            m_detailDefault = { HaulCard(t) }
            boxExtra.children = DelveChoiceButtons(m, t)
        elseif t.status == "dice" then
            m_detailDefault = { DiceCard(m, beat) }
            boxExtra.children = {
                gui.Label{ classes = {"eotwSceneHint"}, text = DiceHint(m) },
                DiceRollButton(),
            }
        else
            if option ~= nil then
                m_detailDefault = { OptionCard(here, option, t.optionIndex, m) }
            end
            if t.status == "rolling" then
                boxExtra.children = {
                    gui.Label{
                        classes = {"eotwSceneHint"},
                        text = cond(IsMyTurn(m), T("stage.scene.prompt_roll"), T("stage.scene.hero_rolling", { hero = t.heroName or T("stage.fallback.the_hero") })),
                    },
                }
            elseif t.status == "perk" then
                boxExtra.children = PerkOfferChildren(m, t)
            elseif t.status == "pardon" then
                boxExtra.children = PardonChildren(m, t)
            else
                boxExtra.children = {}
            end
        end
        ShowDetail(m_detailDefault)
    end

    root = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "100%",
        flow = "vertical",
        titleLabel,
        stageArea,
        box,

        think = function(element)
            local d = m_typing
            if d == nil then
                element.thinkTime = nil
                return
            end
            local n = math.floor((dmhub.Time() - d.start) * SCENE_TYPE_CPS)
            if n >= d.total then
                FinishTyping()
            else
                d.label.text = RevealText(d.full, n)
            end
        end,

        --m.turn is set: show it.
        showTurn = function(element, m, beat)
            Render(m, beat)
        end,
        --no hero at an entry. Remembered so the next approach animates
        --rather than coming up settled.
        showIdle = function(element)
            m_settled = true
            if m_heroid == nil then
                return
            end
            m_heroid = nil
            m_textKey = nil
            m_boxKey = nil
            m_typing = nil
            m_garbledShown = nil
            element.thinkTime = nil
            SyncCast({}, true)
            heroSlot.children = {}
            m_mainFigure = nil
        end,
    }
    return root
end

--A threat's consequence: the malice icon beside `title`, then the `body`
--panels. `startAt` (a dmhub.Time()) plays it as a malice moment -- slam,
--flash, sound, then the `typed` labels type on in turn -- timed from then,
--so a rebuild mid-moment picks up where it was and fires nothing twice.
--nil shows it settled. `delay` staggers several; `sound` = false is quiet.
local function MaliceMoment(args)
    local now = dmhub.Time()
    local startAt = args.startAt
    local slamAt = (startAt or now) + (args.delay or 0) + 0.05
    local impactAt = slamAt + CONSEQUENCE_SLAM_TIME
    local typeAt = impactAt + CONSEQUENCE_TYPE_DELAY
    local typed = args.typed or {}
    local fulls = {}
    local total = 0
    for i, label in ipairs(typed) do
        fulls[i] = label.text
        total = total + VisibleLength(fulls[i])
    end
    local doneAt = typeAt + total / SCENE_TYPE_CPS
    local animate = startAt ~= nil and now < doneAt

    local iconClasses = {"eotwMaliceSlam"}
    if animate and now < slamAt then
        iconClasses[#iconClasses + 1] = "slamIn"
    end
    local icon = MaliceIcon(args.iconSize, iconClasses)
    ---@type Panel[]
    local children = {
        gui.Panel{ width = "auto", height = "auto", flow = "horizontal", halign = "center", interactable = false, icon, args.title },
    }
    for _, child in ipairs(args.body or {}) do
        children[#children + 1] = child
    end

    --the typed labels as of time `t`: each starts once the one before is done.
    local function ShowTyping(t)
        local n = math.max(0, math.floor((t - typeAt) * SCENE_TYPE_CPS))
        for i, label in ipairs(typed) do
            label.text = RevealText(fulls[i], n)
            n = math.max(0, n - VisibleLength(fulls[i]))
        end
    end

    --a moment rebuilt after its slam or impact must not do either again.
    local slammed = now >= slamAt
    local impacted = now >= impactAt
    if animate then
        ShowTyping(now)
    end

    --the block's own background is the flash: a floating overlay at 100%
    --height of an auto-height panel sizes to far more than the block.
    return gui.Panel{
        classes = {"eotwMaliceFlash"},
        bgimage = "panels/square.png",
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "center",
        vpad = 6,
        borderBox = true,
        interactable = false,
        children = children,
        thinkTime = cond(animate, 0.03, nil),
        think = function(element)
            local t = dmhub.Time()
            if not slammed and t >= slamAt then
                slammed = true
                icon:SetClass("slamIn", false)
            end
            if not impacted and t >= impactAt then
                impacted = true
                icon:PulseClass("impact")
                element:PulseClass("lit")
                if args.sound ~= false then
                    audio.FireSoundEvent("Notify.Malice_Use")
                end
            end
            ShowTyping(t)
            if t >= doneAt then
                element.thinkTime = nil
            end
        end,
    }
end

--What identifies a consequence landing, for the stage's played set: the
--consequences phase's one at `idx`, or a "(Temporary)" one at log index `i`.
local function ConsequenceKey(m, idx)
    return string.format("%s:c%s", tostring(m.beatIndex), tostring(idx))
end
local function ExpiredKey(m, i)
    return string.format("%s:e%d", tostring(m.beatIndex), i)
end

--Every consequence landing on the board right now.
local function CurrentConsequenceKeys(m)
    local keys = {}
    if m.phase == "consequences" then
        keys[#keys + 1] = ConsequenceKey(m, m.consequenceIndex or 1)
    end
    for i, entryLog in ipairs(m.log or {}) do
        if entryLog.consequence and entryLog.expired then
            keys[#keys + 1] = ExpiredKey(m, i)
        end
    end
    return keys
end

--`consequenceStart(key)` gives when that consequence started playing on this
--stage, or nil to show it settled (CreateStage's m_consequencesPlayed).
--- @param consequenceStart nil|fun(key: string): number|nil
local function BuildTurnChildren(m, beat, consequenceStart)
    consequenceStart = consequenceStart or function(key) return nil end
    local children = {}
    local function Add(child)
        children[#children + 1] = child
    end

    if m.phase == "arriving" then
        Add(gui.Label{ classes = {"eotwTurnTitle"}, text = T("stage.montage.arriving_title") })
        Add(gui.Label{ classes = {"eotwTurnHint"}, text = T("stage.montage.arriving_hint") })
        return children
    end

    if m.phase == "done" then
        if m.lastApplied ~= nil and #(m.lastApplied.applied or {}) > 0 then
            Add(gui.Label{ classes = {"eotwTurnHint"}, text = string.format("%s:", m.lastApplied.entryName or "") })
            for _, line in ipairs(m.lastApplied.applied) do
                Add(gui.Label{ classes = {"eotwAppliedLine"}, text = line })
            end
            Add(gui.Panel{ width = "60%", height = 1, bgimage = "panels/square.png", bgcolor = "#ffffff30", halign = "center", vmargin = 10 })
        end
        Add(gui.Label{ classes = {"eotwTurnTitle"}, text = T("stage.montage.over_title") })
        Add(gui.Label{ classes = {"eotwTurnHint"}, text = T("stage.montage.over_hint") })
        return children
    end

    if m.phase == "consequences" then
        local idx = m.consequenceIndex or 1
        local entryId = (m.consequences or {})[idx]
        local entry = entryId ~= nil and EncounterScript.FindEntry(beat, entryId) or nil
        if m.lastApplied ~= nil and #(m.lastApplied.applied or {}) > 0 then
            Add(gui.Label{ classes = {"eotwTurnHint"}, text = string.format("%s:", m.lastApplied.entryName or "") })
            for _, line in ipairs(m.lastApplied.applied) do
                Add(gui.Label{ classes = {"eotwAppliedLine"}, text = line })
            end
            Add(gui.Panel{ width = "60%", height = 1, bgimage = "panels/square.png", bgcolor = "#ffffff30", halign = "center", vmargin = 10 })
        end
        if entry == nil then
            Add(gui.Label{ classes = {"eotwTurnTitle"}, text = T("stage.montage.over_title") })
            return children
        end
        Add(gui.Label{ classes = {"eotwTurnHint"}, text = T("stage.consequence.heading") })
        ---@type Panel[]
        local body = {}
        local typed = {}
        if entry.description ~= "" then
            body[#body + 1] = gui.Label{ classes = {"eotwTurnText"}, text = entry.description }
        end
        if entry.consequence ~= nil then
            local label = gui.Label{ classes = {"eotwTurnText"}, text = T("stage.consequence.text", { consequence = EncounterScript.VisibleText(entry.consequence.text) }), bold = true }
            body[#body + 1] = label
            typed[1] = label
        else
            body[#body + 1] = gui.Label{ classes = {"eotwTurnHint"}, text = T("stage.consequence.none_written") }
        end
        Add(MaliceMoment{
            iconSize = 44,
            title = gui.Label{ classes = {"eotwTurnTitle"}, width = "auto", text = entry.name, lmargin = 12, valign = "center" },
            body = body,
            typed = typed,
            startAt = consequenceStart(ConsequenceKey(m, idx)),
        })
        if m.dice ~= nil then
            Add(DiceCard(m, beat))
            Add(gui.Label{ classes = {"eotwTurnHint"}, text = DiceHint(m) })
            local rollButton = DiceRollButton("center")
            if rollButton ~= nil then
                Add(rollButton)
            end
            return children
        end
        Add(gui.Button{
            text = T("stage.consequence.continue_button"),
            halign = "center",
            tmargin = 14,
            width = 180,
            height = 44,
            fontSize = 20,
            click = function(element)
                EncounterMontage.SendRequest("continue", {})
                element:SetClass("hidden", true)
            end,
        })
        return children
    end

    --a resolved turn is over: the centre is back to the round, with a
    --one-line summary of what just happened (the last log entry).
    local t = m.turn
    if t == nil or t.status == "resolved" then
        Add(gui.Label{ classes = {"eotwTurnTitle"}, text = T("stage.round.title", { round = m.round or 1 }) })
        Add(YourMoveLabel())
        for _, child in ipairs(TeamLeaderChildren(m)) do
            Add(child)
        end
        --a "(Temporary)" threat that ran out pays its consequence at the
        --round boundary, and the consequences phase -- the only other
        --place one is ever read out -- does not run mid-montage. So the
        --run of them that just landed is what the new round opens with,
        --in place of the last hero's result.
        local logs = m.log or {}
        local expiredFrom = #logs + 1
        while expiredFrom > 1 and logs[expiredFrom - 1].consequence and logs[expiredFrom - 1].expired do
            expiredFrom = expiredFrom - 1
        end
        if expiredFrom <= #logs then
            Add(gui.Panel{ width = "60%", height = 1, bgimage = "panels/square.png", bgcolor = "#ffffff30", halign = "center", vmargin = 10 })
            --they land together: staggered, and only the first one sounds.
            local playing = 0
            for i = expiredFrom, #logs do
                local entryLog = logs[i]
                ---@type Panel[]
                local lines = {}
                for _, line in ipairs(entryLog.applied or {}) do
                    lines[#lines + 1] = gui.Label{ classes = {"eotwAppliedLine"}, text = line }
                end
                local startAt = consequenceStart(ExpiredKey(m, i))
                Add(MaliceMoment{
                    iconSize = 30,
                    title = gui.Label{ classes = {"eotwTurnText"}, width = "auto", text = T("stage.round.threat_expired", { threat = entryLog.entryName or T("stage.round.threat_expired_fallback") }), lmargin = 10, valign = "center" },
                    body = lines,
                    typed = lines,
                    startAt = startAt,
                    delay = playing * CONSEQUENCE_STAGGER,
                    sound = playing == 0,
                })
                if startAt ~= nil then
                    playing = playing + 1
                end
            end
            return children
        end
        local last = logs[#logs]
        if last ~= nil and not last.consequence then
            Add(gui.Panel{ width = "60%", height = 1, bgimage = "panels/square.png", bgcolor = "#ffffff30", halign = "center", vmargin = 10 })
            if last.delve and last.ordered then
                Add(gui.Label{ classes = {"eotwTurnText"}, text = T("stage.round.summary_ordered_delve", { hero = last.heroName or T("stage.fallback.a_hero"), entry = last.entryName or "",
                    depth = last.depth or 0, steps = TP("stage.count.steps", last.steps or 0) }) })
            elseif last.delve then
                Add(gui.Label{ classes = {"eotwTurnText"}, text = T("stage.round.summary_delve", { hero = last.heroName or T("stage.fallback.a_hero"), entry = last.entryName or "",
                    obstacles = TP("stage.count.obstacles", last.depth or 0), chests = TP("stage.count.chests", last.chests or 0) }) })
            elseif last.passed then
                Add(gui.Label{ classes = {"eotwTurnText"}, text = T("stage.round.summary_passed", { hero = last.heroName or T("stage.fallback.a_hero"), entry = last.entryName or "" }) })
            elseif (last.tier or 0) == 0 then
                Add(gui.Label{ classes = {"eotwTurnText"}, text = T("stage.round.summary_no_roll", { hero = last.heroName or "", entry = last.entryName or "", option = last.optionName or "" }) })
            else
                Add(gui.Label{ classes = {"eotwTurnText"}, text = T("stage.round.summary_tier", { hero = last.heroName or "", entry = last.entryName or "", option = last.optionName or "", tier = TierName(last.tier or 0) }) })
            end
            if last.knack ~= nil then
                Add(gui.Label{ classes = {"eotwAppliedLine"}, text = T("stage.round.summary_knack", { knack = last.knack }) })
            end
            for _, line in ipairs(last.applied or {}) do
                Add(gui.Label{ classes = {"eotwAppliedLine"}, text = line })
            end
        end
        return children
    end

    --a hero at an entry is shown on the scene stage (CreateSceneStage),
    --which takes this panel's place for the length of the turn.
    return children
end

--- the hero row ---------------------------------------------------------------------

local function HeroSignature(heroes)
    local parts = {}
    for _, hero in ipairs(heroes) do
        local allies = EncounterMontage.GetAllies(hero.charid)
        parts[#parts + 1] = hero.charid .. ":" .. table.concat(allies, ",")
    end
    return table.concat(parts, "|")
end

--- the montage haul ------------------------------------------------------------------

local function ItemGear(itemid)
    local gearTable = dmhub.GetTable("tbl_Gear") or {}
    return gearTable[itemid]
end

--The sound a landing item makes: the same pair the in-combat giveItem float
--plays over the token (TokenUI's "giveItem" animation), so picking something
--up in a montage sounds like picking something up in a fight.
--
--"Each party member gains X" lands the same item in four strips at the same
--instant, and four copies of one sample is a mush rather than four pickups,
--so an identical event inside SOUND_COALESCE seconds is dropped. Landings
--that are genuinely apart (the per-strip stagger, or a later beat) are
--further apart than that and all still play.
local SOUND_COALESCE = 0.1
local g_lastPickupSound = {}

local function PlayItemPickupSound(itemid)
    local item = ItemGear(itemid)
    local special = false
    if item ~= nil then
        pcall(function() special = EquipmentCategory.IsTreasure(item) end)
    end
    local eventName = cond(special, "UI.Inv_Item_Pickup_Special", "UI.Inv_Item_Pickup_Gnrc")
    local now = dmhub.Time()
    if g_lastPickupSound[eventName] ~= nil and now - g_lastPickupSound[eventName] < SOUND_COALESCE then
        return
    end
    g_lastPickupSound[eventName] = now
    audio.FireSoundEvent(eventName)
end

--Does the local user drive this hero in their own right? (The Director
--counts.) Gates the item drag: only the hero's own player may hand their
--haul to someone else.
local function LocalUserControlsHero(charid)
    local tok = dmhub.GetCharacterById(charid)
    if tok == nil or not tok.valid then
        return false
    end
    local mine = false
    pcall(function() mine = tok.canControlAsUser end)
    if mine == nil then
        pcall(function() mine = tok.canControl end)
    end
    return mine == true
end

--One item icon in `charid`'s haul. `animate` plays the drop-in: the icon
--starts a slot-height above where it belongs, transparent, and falls into
--place while the pickup sound plays. `delay` staggers it behind other items
--landing in the same refresh. Returns { panel, Update(entry) }.
--
--Hovering shows the item's full tooltip. The hero's own player may drag the
--icon onto another hero's card to hand over ONE of the item (a stack takes
--one drag per unit); the host moves it between inventories ("giveItem").
local function CreateItemIcon(entry, animate, delay, charid)
    local qtyLabel = gui.Label{
        classes = {"eotwItemQty"},
        text = "",
        interactable = false,
    }

    local classes = {"eotwItemIcon"}
    if animate then
        classes[#classes + 1] = "dropIn"
    end

    local m_qty = nil
    --Set while a giveItem is in flight and this icon is showing the handed-
    --off outcome ahead of the host's reply. Cleared by the Update the
    --resulting refresh brings, or by the safety restore below.
    local m_handoff = false
    local HandOff

    --The "!" an item wears while using it now would help at the entry its
    --hero stands at (EncounterMontage.ItemBenefits): a secret option, a
    --knack, an edge on the roll. Everyone sees it; the party decides together.
    local alertBadge = gui.Label{
        classes = {"eotwItemAlert", "collapsed"},
        text = "!",
        floating = true,
        halign = "left",
        valign = "top",
        x = -6,
        y = -6,
        interactable = false,
    }

    --What using it now would do, as tooltip lines over the item's own card.
    local function BenefitTooltip(benefits)
        local item = ItemGear(entry.itemid)
        ---@type Panel[]
        local lines = {
            gui.Label{
                text = T("stage.item.use_now_heading"),
                fontSize = 15,
                bold = true,
                color = "#8fffb8",
                width = "100%",
                height = "auto",
            },
        }
        for _, b in ipairs(benefits) do
            lines[#lines + 1] = gui.Label{
                text = "- " .. b.text,
                fontSize = 14,
                color = "#d8ffe6",
                width = "100%",
                height = "auto",
                textWrap = true,
            }
        end
        lines[#lines + 1] = gui.Panel{ width = "100%", height = 1, bgimage = "panels/square.png", bgcolor = "#ffffff30", vmargin = 6 }
        if item ~= nil then
            pcall(function()
                lines[#lines + 1] = item:Render({ noninteractive = true, width = 360 }, nil)
            end)
        end
        local frame = gui.TooltipFrame(gui.Panel{
            width = 360,
            height = "auto",
            flow = "vertical",
            children = lines,
        }, { halign = "left", valign = "center" })
        frame:MakeNonInteractiveRecursive()
        return frame
    end

    local icon = gui.Panel{
        classes = classes,
        bgimage = "panels/square.png",
        data = { itemid = entry.itemid, charid = charid },
        --only a montage find can be handed to another hero; anything the
        --hero carried in stays with them.
        draggable = charid ~= nil and entry.haul ~= false and LocalUserControlsHero(charid),
        thinkTime = 0.5,
        think = function(element)
            local benefits = nil
            if charid ~= nil then
                benefits = EncounterMontage.ItemBenefits(charid, entry.itemid)
            end
            element:SetClass("benefit", benefits ~= nil)
            alertBadge:SetClass("collapsed", benefits == nil)
        end,
        --the hero's own player clicks an item to use it: one menu entry per
        --use (each mode of a multi-mode item), greyed with the reason when it
        --needs the battle map or the moment is wrong. (click, not press: a
        --find can also be dragged to another hero, and a drag is no click.)
        click = function(element)
            if charid == nil or not LocalUserControlsHero(charid) then
                return
            end
            local item = ItemGear(entry.itemid)
            local uses = EncounterMontage.ConsumableUses(charid, entry.itemid)
            if item == nil or #uses == 0 then
                return
            end
            local blocked = EncounterMontage.ConsumeBlockedReason(charid)
            local entries = {}
            for _, use in ipairs(uses) do
                local text = T("stage.item.use", { item = item.name })
                if use.mode ~= nil then
                    text = T("stage.item.use_mode", { mode = use.label })
                end
                --a greyed entry shows no tooltip, so why it is greyed goes in
                --its text.
                if not use.usable then
                    text = string.format("%s (%s)", text, use.shortReason or T("stage.item.reason_combat_only"))
                elseif blocked ~= nil then
                    text = string.format("%s (%s)", text, blocked)
                elseif use.lasts == "location" then
                    text = T("stage.item.use_lasts_location", { use = text })
                elseif use.lasts == "encounter" then
                    text = T("stage.item.use_lasts_encounter", { use = text })
                end
                local tooltip = use.rules
                entries[#entries + 1] = {
                    text = text,
                    disabled = (not use.usable) or blocked ~= nil,
                    tooltip = tooltip,
                    click = function()
                        element.popup = nil
                        if (not use.usable) or EncounterMontage.ConsumeBlockedReason(charid) ~= nil then
                            return
                        end
                        audio.FireSoundEvent("Mouse.Click")
                        local ok, why = EncounterMontage.ConsumeItem(charid, entry.itemid, use.mode)
                        if not ok then
                            printf("EotW montage: could not use %s: %s", tostring(item.name), tostring(why))
                        end
                    end,
                }
            end
            element.popup = gui.ContextMenu{
                width = 280,
                entries = entries,
                click = function() element.popup = nil end,
            }
        end,
        beginDrag = function(element)
            element:SetClass("dragging", true)
            element.tooltip = nil
            SelectHero(nil)
            Broadcast("dragTargets", true, "item", charid)
        end,
        canDragOnto = function(element, target)
            if not target:HasClass("eotwHeroCard") or target:HasClass("eotwAllyCard") then
                return false
            end
            local targetId = target.data ~= nil and target.data.charid or nil
            return targetId ~= nil and targetId ~= charid and LocalUserControlsHero(charid)
        end,
        drag = function(element, target)
            element:SetClass("dragging", false)
            Broadcast("dragTargets", false)
            if target == nil or target.data == nil or target.data.charid == nil or not LocalUserControlsHero(charid) then
                return
            end
            audio.FireSoundEvent("Mouse.Click")
            --The item is gone from this hero the moment it is dropped, as
            --far as this strip is concerned. Without that, clearing
            --"dragging" snaps the icon back into its old slot at full
            --opacity and it sits there until the host's giveItem reply
            --comes back -- the flash. Show the outcome now and let the
            --refresh reconcile it.
            HandOff()
            EncounterMontage.SendRequest("giveItem", { heroid = charid, targetId = target.data.charid, itemid = entry.itemid })
        end,
        hover = function(element)
            local item = ItemGear(entry.itemid)
            --an item that would help at the entry says how, and lights up
            --the options it helps.
            local benefits = charid ~= nil and EncounterMontage.ItemBenefits(charid, entry.itemid) or nil
            if benefits ~= nil then
                local set = {}
                for _, b in ipairs(benefits) do
                    if b.optionIndex ~= nil then
                        set[b.optionIndex] = true
                    end
                end
                Broadcast("itemBenefitHighlight", set)
                local ok = pcall(function()
                    element.tooltip = BenefitTooltip(benefits)
                end)
                if ok then
                    return
                end
            end
            local tooltipFn = rawget(_G, "CreateItemTooltip")
            if item ~= nil and tooltipFn ~= nil then
                local ok = pcall(function()
                    element.tooltip = tooltipFn(item, { valign = "center", width = 360 }, nil)
                end)
                if ok then
                    return
                end
            end
            gui.Tooltip(entry.name or T("stage.item.name_fallback"))(element)
        end,
        dehover = function(element)
            Broadcast("itemBenefitHighlight", nil)
        end,
        qtyLabel,
        alertBadge,
    }

    --`animateChange` is for a refresh that lands while the stage is up: a
    --repeat grant bumps this icon's quantity rather than adding an icon, so
    --that gain announces itself with the same sound and a pulse.
    local function Update(newEntry, animateChange)
        local item = ItemGear(newEntry.itemid)
        local iconid = nil
        if item ~= nil then
            pcall(function() iconid = item:GetIcon() end)
        end
        if iconid ~= nil and iconid ~= "" then
            icon.bgimage = iconid
            icon.selfStyle.bgcolor = "white"
        else
            icon.bgimage = "panels/square.png"
            icon.selfStyle.bgcolor = "#232a33"
        end
        --a carried item becomes a find (handable) once the montage grants one.
        local canDrag = charid ~= nil and newEntry.haul ~= false and LocalUserControlsHero(charid)
        if icon.draggable ~= canDrag then
            icon.draggable = canDrag
        end
        local qty = newEntry.qty or 1
        if m_handoff then
            if qty > (m_qty or 0) then
                --a refresh driven by something else, carrying a document
                --that predates our giveItem: keep showing the handoff
                --rather than snapping the item back for an instant.
                return
            end
            --the document has caught up with the handoff.
            m_handoff = false
            icon:SetClass("collapsed", false)
        end
        qtyLabel.text = cond(qty > 1, string.format("x%d", qty), "")
        qtyLabel:SetClass("collapsed", qty <= 1)
        if animateChange and m_qty ~= nil and qty > m_qty then
            icon:PulseClass("bump")
            PlayItemPickupSound(newEntry.itemid)
        end
        m_qty = qty
    end

    --One of this item has just been handed to another hero. A stack simply
    --loses one from its count; the last one leaves the strip, which is what
    --the refresh will do to it anyway, so collapsing it now means the
    --strip reflows once rather than snapping back and then reflowing.
    HandOff = function()
        local prevQty = m_qty or 1
        local qty = prevQty - 1
        m_handoff = true
        m_qty = qty
        if qty <= 0 then
            icon:SetClass("collapsed", true)
        else
            qtyLabel.text = cond(qty > 1, string.format("x%d", qty), "")
            qtyLabel:SetClass("collapsed", qty <= 1)
        end
        --if the reply never lands (rejected, or the host went away) put the
        --icon back rather than leaving the haul short an item forever.
        dmhub.Schedule(2, function()
            if mod.unloaded or icon == nil or not icon.valid or not m_handoff then
                return
            end
            m_handoff = false
            m_qty = prevQty
            icon:SetClass("collapsed", false)
            qtyLabel.text = cond(prevQty > 1, string.format("x%d", prevQty), "")
            qtyLabel:SetClass("collapsed", prevQty <= 1)
        end)
    end

    Update(entry)

    if animate then
        --a frame for the strip to lay the icon out in its raised start
        --state before the class comes off and the transition runs.
        dmhub.Schedule(0.05 + (delay or 0), function()
            if mod.unloaded or icon == nil or not icon.valid then
                return
            end
            icon:SetClass("dropIn", false)
            PlayItemPickupSound(entry.itemid)
        end)
    end

    return { panel = icon, Update = Update }
end

--The gutter of item icons beside one hero's card. Items already in the
--document when the strip is built appear instantly (a rebuilt hero row must
--not replay the whole montage); anything that lands afterwards drops in.
local function CreateItemStrip(charid)
    local m_icons = {}
    local m_count = 0
    --the first refreshMontage is the one that comes straight after this
    --strip is created, so it populates silently.
    local m_primed = false

    return gui.Panel{
        width = ITEM_STRIP_WIDTH,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        --a used consumable reaches this client as a token change, which does
        --not refresh the montage; look again now and then.
        thinkTime = 1,
        think = function(element)
            if m_primed then
                element:FireEvent("refreshMontage")
            end
        end,
        refreshMontage = function(element)
            --the haul and every consumable the hero carries.
            local entries = EncounterMontage.GetStripItems(charid)
            local children = {}
            local added = false
            --items landing together drop one after another, not all at once.
            local newCount = 0
            --an item that left this haul (given to another hero) had its
            --icon destroyed when it dropped out of `children`; forget it so
            --the item coming back gets a fresh icon rather than an Update
            --on a dead panel.
            local present = {}
            for _, entry in ipairs(entries) do
                present[entry.itemid] = true
            end
            for itemid, icon in pairs(m_icons) do
                if not present[itemid] or not icon.panel.valid then
                    m_icons[itemid] = nil
                end
            end
            for _, entry in ipairs(entries) do
                local icon = m_icons[entry.itemid]
                if icon == nil then
                    icon = CreateItemIcon(entry, m_primed, newCount * ITEM_DROP_STAGGER, charid)
                    m_icons[entry.itemid] = icon
                    newCount = newCount + 1
                    added = true
                else
                    icon.Update(entry, m_primed)
                end
                children[#children + 1] = icon.panel
            end
            if added or #children ~= m_count then
                m_count = #children
                element.children = children
            end
            m_primed = true
        end,
    }
end

--- the hero column -------------------------------------------------------------------

--A hero may be picked up to take a beat. Returns the mode, or nil when this
--card must not move at all.
local function DragMode(charid)
    if EncounterMontage.LocalUserCanAct(charid) then
        return "approach"
    end
    return nil
end

--The characteristic and skill this hero is rolling the test in flight
--with (attrid, skillid; either nil), or nothing when they are not rolling:
--after the roll it is what the acting hero reported (turn.attrid,
--turn.skillid); while the roll dialog is still up it is the best of the
--option's listed characteristics for this hero and the first listed skill
--they are trained in, the same picks LaunchRoll and ApplySkilledModifier
--make.
local function ActiveCharacteristic(m, charid)
    local t = m.turn
    if t == nil or t.status == "resolved" or t.heroid ~= charid then
        return nil, nil
    end
    if t.attrid ~= nil then
        return t.attrid, t.skillid
    end
    if t.optionIndex == nil then
        return nil, nil
    end
    local beat = EncounterMontage.CurrentBeat()
    local entry = beat ~= nil and EncounterMontage.TurnEntry(beat, t) or nil
    local option = EncounterMontage.TurnOption(entry, t)
    if option == nil or option.roll == nil then
        return nil, nil
    end
    local tok = dmhub.GetCharacterById(charid)
    if tok == nil or not tok.valid or tok.properties == nil then
        return nil, nil
    end
    local characteristics, skills = EncounterScript.ParseAttr(option.roll.attr, creature.attributesInfo, Skill.skillsDropdownOptions)
    local best, bestModifier = nil, nil
    for attrid, _ in pairs(characteristics) do
        local modifier = nil
        pcall(function() modifier = tok.properties:GetAttribute(attrid):Modifier() end)
        if modifier ~= nil and (bestModifier == nil or modifier > bestModifier) then
            best, bestModifier = attrid, modifier
        end
    end
    local skillid = nil
    pcall(function() skillid = EncounterMontage.MainTestSkill(t, option) end)
    return best, skillid
end

local function CreateHeroColumn(hero)
    local hud = Hud()
    local charid = hero.charid
    local card = nil
    --the "you can act" ring: shown while DragMode says the local user can
    --take a beat with this hero; 5px outside the card on each
    --side so it frames the card's own border instead of covering it.
    local canActRing = gui.Panel{
        classes = {"eotwCanActRing", "collapsed"},
        floating = true,
        halign = "center",
        valign = "center",
        width = "100%+10",
        height = "100%+10",
        bgimage = "panels/square.png",
        interactable = false,
        thinkTime = 0.05,
        think = function(element)
            if element:HasClass("collapsed") then
                return
            end
            local r = (math.sin(dmhub.Time() * 2 * math.pi / 1.4) + 1) / 2
            element.selfStyle.opacity = 0.4 + 0.6 * r
        end,
    }
    if hud ~= nil and hud.CreateHeroCard ~= nil then
        card = hud.CreateHeroCard({ charid = charid, mine = false, name = hero.name }, {
            halign = "center",
            --only a hero the local user controls, and only while that hero
            --can still take a beat: a card
            --nobody here can act with must not even pick up (the drop gates
            --below reject it anyway, but a player dragging someone else's
            --hero around reads as allowed).
            draggable = DragMode(charid) ~= nil,
            --another hero's item icon may be dropped here to hand it over
            --(CreateItemIcon). Only an "item" drag lights the card up, and
            --never the card of the hero the item is coming from.
            dragTarget = true,
            dragTargetPriority = 10,
            dragTargets = function(element, on, mode, sourceCharid)
                element:SetClass("droppable", on == true and mode == "item" and sourceCharid ~= charid)
            end,
            --the montage is where the party weighs who should take a beat,
            --so these cards carry the characteristics and skills the roster's
            --do not.
            showStats = true,
            --out of combat a hero may spend a Recovery whenever they like.
            spendRecovery = true,
            click = function(element, openCharacterPanel)
                local mode = DragMode(charid)
                if mode ~= nil then
                    audio.FireSoundEvent("Mouse.Click")
                    if m_selectedHero == charid then
                        SelectHero(nil)
                    else
                        SelectHero(charid, mode)
                    end
                    return
                end
                openCharacterPanel(element)
            end,
            beginDrag = function(element)
                element:SetClass("dragging", true)
                local mode = DragMode(charid) or "approach"
                SelectHero(nil)
                PreviewHero(nil, nil)
                Broadcast("dragTargets", true, mode)
            end,
            --every frame of the drag, with the drop target under the
            --cursor: the entry hovered previews this hero in its slot.
            dragging = function(element, target)
                local entryId = nil
                if target ~= nil and target:HasClass("eotwEntryCard") then
                    entryId = target.data.entryId
                end
                PreviewHero(charid, entryId)
            end,
            canDragOnto = function(element, target)
                if not target:HasClass("eotwEntryCard") then
                    return false
                end
                if not target.data.available then
                    return false
                end
                return EncounterMontage.LocalUserCanAct(charid)
            end,
            drag = function(element, target)
                element:SetClass("dragging", false)
                Broadcast("dragTargets", false)
                --dropped on an entry: the preview holds until the approach
                --lands, so the slot does not blink empty in between.
                if target ~= nil and target:HasClass("eotwEntryCard") and EncounterMontage.LocalUserCanAct(charid) then
                    m_previewEntry = nil
                    Broadcast("previewHero", charid, target.data.entryId, true)
                else
                    PreviewHero(nil, nil)
                end
                if target == nil then
                    return
                end
                if target:HasClass("eotwEntryCard") and EncounterMontage.LocalUserCanAct(charid) then
                    audio.FireSoundEvent("Mouse.Click")
                    EncounterMontage.SendRequest("approach", { heroid = charid, entryId = target.data.entryId })
                end
            end,
        })
        card:AddChild(canActRing)
    else
        card = gui.Label{ width = 132, height = 176, text = hero.name, bgimage = "panels/square.png", bgcolor = "#333333" }
    end

    --allies stack bottom-up against the card's right edge; the column widens
    --by the stack, which is what spaces this hero from the next one. The
    --stage rebuilds the columns when an ally joins (HeroSignature), so this
    --is only filled once.
    local allyStack = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "bottom",
        lmargin = 3,
        rmargin = 6,
        uiscale = MONTAGE_ALLY_UISCALE,
        create = function(element)
            local minis = {}
            for _, allyId in ipairs(EncounterMontage.GetAllies(charid)) do
                if hud ~= nil and hud.CreateAllyCard ~= nil then
                    minis[#minis + 1] = hud.CreateAllyCard(allyId)
                end
            end
            element.children = minis
            element:SetClass("collapsed", #minis == 0)
        end,
    }

    --the haul gutter, the card and its allies, side by side.
    local cardRow = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "center",
        valign = "top",
        CreateItemStrip(charid),
        card,
        allyStack,
    }

    return gui.Panel{
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "center",
        valign = "top",
        hmargin = 6,
        data = { charid = charid },
        cardRow,
        refreshMontage = function(element, m)
            --dimmed once they have taken their beat this round.
            local done = m.phase ~= "rounds" or (m.acted or {})[charid] == true
            card:SetClass("acted", done)
            local mode = DragMode(charid)
            card.draggable = mode ~= nil
            canActRing:SetClass("collapsed", mode == nil)
            if m_selectedHero == charid and mode == nil then
                SelectHero(nil)
            end
            card:SetClass("selected", m_selectedHero == charid)
            --the hero taking (or stepping in on) the test in flight, and the
            --characteristic they are rolling it with.
            local activeAttr, activeSkill = ActiveCharacteristic(m, charid)
            local active = m.turn ~= nil and m.turn.status ~= "resolved"
                and (m.turn.heroid == charid or (m.turn.pardon ~= nil and m.turn.pardon.heroid == charid))
            card:SetClass("active", active)
            card:FireEventTree("highlightCharacteristic", activeAttr)
            card:FireEventTree("highlightSkill", activeSkill)
        end,
        selectHero = function(element, heroid)
            card:SetClass("selected", heroid == charid)
        end,
    }
end

--- the stage ---------------------------------------------------------------------------

--Is this image asset a video (a .webm/.mp4 scene)? Videos have to be
--streamed with an engine loop flag, or the clip plays once and goes blank.
local function IsVideoAsset(imageid)
    local video = false
    pcall(function()
        local asset = assets.imagesTable[imageid]
        video = asset ~= nil and asset.isVideo == true
    end)
    return video
end

--Fill the stage with art of the given aspect (height / width), cropping
--the overflow, exactly like FullscreenDisplay does it.
local function FitBackdrop(element, imageAspect)
    if element.parent == nil or imageAspect == nil or imageAspect <= 0 then
        return
    end
    local w = element.parent.renderedWidth
    local h = element.parent.renderedHeight
    if w == 0 or h == 0 then
        return
    end
    local aspect = h / w
    if aspect > imageAspect then
        element.selfStyle.height = "100%"
        element.selfStyle.width = string.format("%f%% height", 100 / imageAspect)
    else
        element.selfStyle.width = "100%"
        element.selfStyle.height = string.format("%f%% width", 100 * imageAspect)
    end
end

--The art credit for the scene on a backdrop: the creator's logo badge in
--the stage's bottom-right corner (CreatorCredit), shown while the scene is
--credited art (a [[scene]] with "Art by" set). A sibling of the backdrop,
--not a child, because the backdrop overflows the stage when it crops.
--Has no bgimage, so it only takes clicks on the badge itself.
local function CreateCreditHolder()
    return gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        flow = "none",
        data = { creator = nil },
        setSceneCredit = function(element, scene)
            local info = nil
            if scene ~= nil then
                info = CreatorCredit.ForArt(scene)
            end
            local creator = info ~= nil and info.id or nil
            if creator == element.data.creator then
                return
            end
            element.data.creator = creator
            local badge = nil
            if creator ~= nil then
                badge = CreatorCredit.Badge{ creator = creator, light = true }
            end
            element.children = { badge }
        end,
    }
end

--The credit badge holder belonging to a backdrop (nil for no backdrop), for
--the stage's children list.
local function CreditOf(backdrop)
    if backdrop == nil then
        return nil
    end
    return backdrop.data.credit
end

--The scene art behind a stage, aspect-fit exactly like FullscreenDisplay
--does it. Shared by the montage and the narrative stage. Set its art with
--SetBackdropScene, which knows how to play a video scene. Its credit badge
--(CreditOf) must be added to the stage after the dim.
local function CreateBackdrop()
    return gui.Panel{
        floating = true,
        classes = {"hidden"},
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "white",
        interactable = false,
        data = { sceneId = nil, credit = CreateCreditHolder() },
        --aspect-fit the scene art exactly like FullscreenDisplay does.
        imageLoaded = function(element)
            if element.bgsprite ~= nil then
                FitBackdrop(element, element.bgsprite.dimensions.y / element.bgsprite.dimensions.x)
                return
            end
            --a streamed video has no sprite to measure; ask for its size.
            local sceneId = element.data.sceneId
            if sceneId == nil then
                return
            end
            pcall(function()
                gui.GetImageDimensionsCallback(sceneId, function(dims)
                    if mod.unloaded or not element.valid or element.data.sceneId ~= sceneId then
                        return
                    end
                    if dims ~= nil and (dims.width or 0) > 0 and (dims.height or 0) > 0 then
                        FitBackdrop(element, dims.height / dims.width)
                    end
                end)
            end)
        end,
        screenResized = function(element)
            element:ScheduleEvent("imageLoaded", 0.5)
        end,
    }
end

--Show a scene (an image or video asset id) on a backdrop, or hide it (nil).
local function SetBackdropScene(backdrop, scene)
    local credit = backdrop.data.credit
    if credit ~= nil and credit.valid then
        credit:FireEvent("setSceneCredit", scene)
    end
    if scene == nil then
        backdrop.data.sceneId = nil
        backdrop:SetClass("hidden", true)
        return
    end
    backdrop.data.sceneId = scene
    if IsVideoAsset(scene) then
        --a private looping player (the "###" suffix), muted: the stage's
        --own music and sound play over it.
        backdrop.bgimageStreamed = scene .. "###LOOP" .. dmhub.GenerateGuid()
    else
        backdrop.bgimage = scene
    end
    backdrop:SetClass("hidden", false)
    backdrop:ScheduleEvent("imageLoaded", 0.2)
end

local function CreateDim()
    return gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        bgimage = "panels/square.png",
        bgcolor = "#000000a8",
        interactable = false,
    }
end

--The encounter pools (malice + hero tokens): exactly the right rail's strip,
--floated where the rail keeps it, because the stage covers the rail.
local function CreatePoolsPanel()
    local hud = Hud()
    if hud == nil or hud.CreateEncounterPoolsPanel == nil then
        return nil
    end
    return gui.Panel{
        floating = true,
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "top",
        tmargin = POOLS_TOP,
        rmargin = POOLS_RIGHT,
        hud.CreateEncounterPoolsPanel(),
    }
end

--`args.embedded` means this stage is a BODY inside the mounted script stage
--(CreateScriptStage below), which owns the chrome both beat kinds share --
--the opaque background, the scene art, the dim, the pools strip, the hidden
--action bar, the held loading screen -- so that none of it blinks when the
--script moves from one beat to the next.
local function CreateStage(args)
    local embedded = args ~= nil and args.embedded == true
    local m_builtBeat = nil
    --the header height the body is currently sized against (SyncHeaderHeight).
    local m_headerHeight = nil
    local m_turnSignature = nil
    local m_heroSignature = nil
    local m_scene = nil
    --when each consequence (ConsequenceKey/ExpiredKey) started playing here,
    --so a rebuild never replays one. false = it was already on the board at
    --this stage's first refresh (a join, a reload) and shows settled.
    ---@type nil|table<string, number|false>
    local m_consequencesPlayed = nil
    local function ConsequenceStart(key)
        m_consequencesPlayed = m_consequencesPlayed or {}
        local t = m_consequencesPlayed[key]
        if t == nil then
            t = dmhub.Time()
            m_consequencesPlayed[key] = t
        end
        return t or nil
    end

    --cond() evaluates both branches, so build these only when we own them.
    local backdrop, dim = nil, nil
    if not embedded then
        backdrop = CreateBackdrop()
        dim = CreateDim()
    end

    local titleLabel = gui.Label{ classes = {"eotwStageTitle"}, text = T("stage.montage.title"), halign = "center" }
    local introLabel = gui.Label{ classes = {"eotwStageSubtitle", "eotwMontageIntro"}, text = "", halign = "center" }
    local roundLabel = gui.Label{ classes = {"eotwStageRound"}, text = "", halign = "center" }
    --Auto height, not the fixed HEADER_HEIGHT: the intro prose wraps to as
    --many lines as it needs, and the body below is re-sized from what the
    --header actually rendered (SyncHeaderHeight).
    local header = gui.Panel{
        width = "100%",
        height = "auto",
        minHeight = HEADER_HEIGHT,
        flow = "vertical",
        halign = "center",
        valign = "top",
        titleLabel,
        introLabel,
        roundLabel,
    }

    --inset from the scroll area, which clips: a card under a dragged hero
    --scales up 3% (drag-target-hover) and would lose its side borders.
    local opportunities = gui.Panel{ width = "100%-24", height = "auto", flow = "vertical", halign = "center", valign = "top" }
    local threats = gui.Panel{ width = "100%-24", height = "auto", flow = "vertical", halign = "center", valign = "top" }

    local function Column(title, list)
        return gui.Panel{
            width = COLUMN_WIDTH,
            height = "100%",
            flow = "vertical",
            halign = "center",
            valign = "top",
            hmargin = 10,
            gui.Label{ classes = {"eotwColumnTitle"}, text = title },
            gui.Panel{
                width = "100%",
                height = "100%-36",
                vscroll = true,
                halign = "center",
                valign = "top",
                list,
            },
        }
    end

    local turnBody = gui.Panel{
        width = "100%-40",
        height = "auto",
        flow = "vertical",
        halign = "center",
        valign = "top",
    }
    --the round's text, and the scene stage that takes its place while a
    --hero is at an entry.
    local turnScroll = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        vscroll = true,
        turnBody,
    }
    local sceneStage = CreateSceneStage()
    local turnPanel = gui.Panel{
        classes = {"eotwTurnPanel"},
        width = CENTER_WIDTH,
        height = string.format("100%%-%d", MONTAGE_HERO_ROW_TMARGIN + MONTAGE_HERO_ROW_HEIGHT),
        flow = "vertical",
        halign = "center",
        valign = "top",
        bgimage = "panels/square.png",
        pad = 20,
        borderBox = true,
        turnScroll,
        sceneStage,
    }

    --The body runs to the bottom of the screen. Only the turn panel stops
    --short to make room for the hero row; the side columns carry on down
    --past it while the row fits between them (SyncHeaderHeight).
    local opportunitiesColumn = Column(T("stage.montage.column_opportunities"), opportunities)
    local threatsColumn = Column(T("stage.montage.column_threats"), threats)
    local body = gui.Panel{
        width = "100%-40",
        height = string.format("100%%-%d", HEADER_HEIGHT),
        flow = "horizontal",
        halign = "center",
        valign = "top",
        opportunitiesColumn,
        turnPanel,
        threatsColumn,
    }

    --auto width + left-aligned columns: the cards pack together and the
    --row as a whole sits centered (center-aligned children of a horizontal
    --flow would be spread across the full width instead).
    --floating: the body already spans down to the bottom of the screen, so
    --the row sits over the gap the turn panel leaves for it.
    local heroRow = gui.Panel{
        floating = true,
        width = "auto",
        height = MONTAGE_HERO_ROW_HEIGHT,
        flow = "horizontal",
        halign = "center",
        valign = "bottom",
    }

    local pools = nil
    if not embedded then
        pools = CreatePoolsPanel()
    end

    --The columns only ever hold what is in play: an entry gets a card the
    --round it enters (materializing as it arrives) and loses it at the end
    --of the round it was dealt with in (fading out first). m_cards holds
    --the live cards by entry id -- a card that has begun to leave is taken
    --out of here immediately, so nothing tries to bring it back.
    local m_cards = {}
    local m_entryRound = nil
    local m_entryPhase = nil
    --true while a round's party-size draw has not been made yet: its entries
    --are withheld entirely rather than shown and then taken away.
    local m_entryDrawPending = false
    --how many "(Locked)" entries have been unlocked; a change brings the
    --newly available cards in without waiting for the round to turn over.
    local m_unlockCount = nil

    local function EntryDone(m, entry)
        if entry.kind == "opportunity" then
            return (m.taken or {})[entry.id] == true
        end
        return (m.vanquished or {})[entry.id] == true
    end

    --Cards for the entries this round introduces. `animate` gives each one
    --the materialize ramp, staggered so a round that opens with three
    --entries reads as three arrivals rather than one pop; the beat's first
    --round comes up with the stage itself and so is built settled.
    --`keepDone` is for a build from cold (a join or a resume mid-montage):
    --an entry dealt with in an earlier round has already faded away on
    --everyone else's stage, so it is not put back here either.
    local function AddEntriesForRound(beat, round, animate, m, keepDone, startDelay)
        local delay = startDelay or 0
        for _, entry in ipairs(EncounterScript.MontageEntries(beat)) do
            if entry.round == round and m_cards[entry.id] == nil
                and not EncounterMontage.EntryHidden(m, beat, entry)
                and (keepDone or not EntryDone(m, entry)) then
                local card = CreateEntryCard(entry, cond(animate, delay, nil))
                m_cards[entry.id] = card
                if entry.kind == "opportunity" then
                    opportunities:AddChild(card)
                else
                    threats:AddChild(card)
                end
                if animate then
                    delay = delay + ENTRY_APPEAR_STAGGER
                end
            end
        end
    end

    local function ClearEntries()
        for _, card in pairs(m_cards) do
            if card.valid then
                card:DestroySelf()
            end
        end
        m_cards = {}
        opportunities.children = {}
        threats.children = {}
    end

    --Everything the party dealt with, now that the round it happened in is
    --over, leaves the columns -- and so does every "(Temporary)" entry the
    --round carried off, dealt with or not.
    local function RetireDoneEntries(m)
        local taken = m.taken or {}
        local vanquished = m.vanquished or {}
        local expired = m.expired or {}
        local n = 0
        --the longest any leaving card waits on its title strike before fading.
        local maxDelay = 0
        for id, card in pairs(m_cards) do
            if not card.valid then
                m_cards[id] = nil
            elseif expired[id] == true
                or cond(card.data.kind == "opportunity", taken[id], vanquished[id]) == true then
                m_cards[id] = nil
                card:FireEvent("leave")
                n = n + 1
                maxDelay = math.max(maxDelay, card.data.leaveDelay or 0)
            end
        end
        return n, maxDelay
    end

    --Bring the columns into line with the round (and the phase: the last
    --round ending into the consequences retires that round's kills too).
    local function SyncEntries(m, beat, rebuilt)
        local round = m.round or 1
        local phase = m.phase
        --the draw landing is a rebuild: the entries it let through have to
        --arrive, and the round number has not changed to bring them in.
        local drawPending = m.removed == nil and EncounterScript.HasScaling(beat)
        local drawLanded = m_entryDrawPending and not drawPending
        m_entryDrawPending = drawPending
        --an "Unlock <name>" outcome can land at any moment; the count only
        --ever rises, so a change means at least one more entry is now
        --allowed on the board.
        local unlockCount = 0
        for _ in pairs(m.unlocked or {}) do
            unlockCount = unlockCount + 1
        end
        local unlocksLanded = m_unlockCount ~= nil and unlockCount ~= m_unlockCount
        m_unlockCount = unlockCount
        local fullRebuild = rebuilt or m_entryRound == nil or round < m_entryRound or drawLanded
        if fullRebuild then
            ClearEntries()
            for r = 1, round do
                --what was dealt with in the round still running stays on
                --the board with its "Taken" / "Vanquished" line; anything
                --older, or anything at all once the rounds are over, has
                --already gone.
                AddEntriesForRound(beat, r, false, m, r == round and phase == "rounds")
            end
        elseif round > m_entryRound then
            --what is leaving goes first: the new round's entries wait for
            --the old cards to finish fading and the columns to close up,
            --so the two animations read as one hand-over rather than a
            --scramble.
            local leaving, strikeDelay = RetireDoneEntries(m)
            local startDelay = cond(leaving > 0, strikeDelay + ENTRY_FADE_TIME + 0.1, 0)
            for r = m_entryRound + 1, round do
                AddEntriesForRound(beat, r, true, m, true, startDelay)
            end
        elseif phase ~= m_entryPhase and m_entryPhase == "rounds" then
            --the final round has ended; there is no round after it to
            --clear the board, so the phase change does it.
            RetireDoneEntries(m)
        end
        --an entry unlocked this tick joins the board straight away if its
        --round has already come; one declared in a later round waits for
        --it, because only rounds up to the current one are swept. The
        --sweep is over every round, not just the new ones, since the
        --unlock may free a card the party walked past two rounds ago; the
        --m_cards check makes it a no-op for everything already up.
        if unlocksLanded and not fullRebuild then
            for r = 1, round do
                AddEntriesForRound(beat, r, true, m, r == round and phase == "rounds")
            end
        end
        m_entryRound = round
        m_entryPhase = phase
    end

    local function RefreshHeroes(m)
        local heroes = EncounterMontage.Heroes()
        local sig = HeroSignature(heroes)
        if sig ~= m_heroSignature then
            m_heroSignature = sig
            local columns = {}
            for _, hero in ipairs(heroes) do
                columns[#columns + 1] = CreateHeroColumn(hero)
            end
            heroRow.children = columns
        end
    end

    --The header is auto-height so the intro prose can wrap; the body's
    --height is arithmetic off it, so follow what the header actually
    --rendered rather than the HEADER_HEIGHT floor.
    --Also decides whether the side columns may run down past the hero row:
    --only while the row fits between them (five heroes with allies can be
    --wider than the turn panel, and would then cover the columns' cards).
    local m_columnsFull = nil
    local function SyncHeaderHeight()
        if not header.valid then
            return
        end
        local h = math.max(HEADER_HEIGHT, math.min(HEADER_HEIGHT_MAX, math.ceil(header.renderedHeight or 0)))
        if h ~= m_headerHeight then
            m_headerHeight = h
            body.selfStyle.height = string.format("100%%-%d", h)
        end
        local full = (heroRow.renderedWidth or 0) <= (turnPanel.renderedWidth or 0)
        if full ~= m_columnsFull then
            m_columnsFull = full
            local columnHeight = string.format("100%%-%d", cond(full, MONTAGE_COLUMN_BOTTOM_GAP, MONTAGE_HERO_ROW_TMARGIN + MONTAGE_HERO_ROW_HEIGHT))
            opportunitiesColumn.selfStyle.height = columnHeight
            threatsColumn.selfStyle.height = columnHeight
        end
    end

    local resultPanel
    local function Refresh(element)
        SyncHeaderHeight()
        local m = EncounterMontage.GetState()
        local beat, script = EncounterMontage.CurrentBeat()
        if m == nil or beat == nil then
            return
        end
        if m_consequencesPlayed == nil then
            m_consequencesPlayed = {}
            for _, key in ipairs(CurrentConsequenceKeys(m)) do
                m_consequencesPlayed[key] = false
            end
        end
        local rebuilt = m_builtBeat ~= m.beatIndex
        if rebuilt then
            m_builtBeat = m.beatIndex
            m_entryRound = nil
            m_entryPhase = nil
            introLabel.text = beat.intro or ""
            introLabel:SetClass("collapsed", (beat.intro or "") == "")
            m_turnSignature = nil
        end
        if not embedded then
            --backdrop is built whenever the stage is not embedded. A round
            --may hang its own scene, so this is checked every refresh.
            ---@cast backdrop -nil
            local scene = EncounterMontage.MontageSceneImage(script, beat, m.round)
            if scene ~= m_scene then
                m_scene = scene
                SetBackdropScene(backdrop, scene)
            end
        end

        SyncEntries(m, beat, rebuilt)

        local rounds = EncounterScript.RoundCount(beat)
        if m.phase == "arriving" then
            roundLabel.text = T("stage.montage.status_arriving")
        elseif m.phase == "consequences" then
            roundLabel.text = T("stage.montage.status_consequences")
        elseif m.phase == "done" then
            roundLabel.text = T("stage.montage.status_complete")
        else
            local text = T("stage.montage.status_round", { round = m.round or 1, rounds = rounds })
            roundLabel.text = text
        end

        RefreshHeroes(m)

        --the stage is up while a hero is at a location; once their turn has
        --resolved, the centre goes back to the neutral round view.
        local staged = m.turn ~= nil and m.phase == "rounds" and m.turn.status ~= "resolved"
        turnScroll:SetClass("collapsed", staged)
        sceneStage:SetClass("collapsed", not staged)
        if staged then
            m_turnSignature = nil
            sceneStage:FireEvent("showTurn", m, beat)
        else
            sceneStage:FireEvent("showIdle")
            local sig = TurnSignature(m)
            if sig ~= m_turnSignature then
                m_turnSignature = sig
                turnBody.children = BuildTurnChildren(m, beat, ConsequenceStart)
            end
        end

        element:FireEventTree("refreshMontage", m)
    end

    resultPanel = gui.Panel{
        styles = ThemeEngine.MergeStyles(StageRules()),
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        flow = "vertical",
        bgimage = cond(embedded, nil, "panels/square.png"),
        bgcolor = cond(embedded, "#00000000", "#05070a"),
        swallowPress = true,

        children = Classes(backdrop, dim, header, body, heroRow, pools, CreditOf(backdrop)),

        monitorGame = EncounterMontage.DocPath(),
        refreshGame = function(element)
            Refresh(element)
        end,

        create = function(element)
            Refresh(element)
            if not embedded then
                AcquireActionBarHide()
                EotwProf("stage created")
                element:ScheduleEvent("releaseLoadingScreen", 0.1)
            end
        end,

        destroy = function(element)
            if not embedded then
                ReleaseActionBarHide()
            end
        end,

        releaseLoadingScreen = function(element)
            if HoldForParty() then
                element:ScheduleEvent("releaseLoadingScreen", 0.1)
                return
            end
            EotwProf("stage up; releasing the loading screen")
            pcall(function() dmhub.ReleaseLoadingScreen() end)
        end,

        thinkTime = 0.5,
        think = function(element)
            if mod.unloaded then
                element:DestroySelf()
                return
            end
            pcall(EncounterMontage.ClientTick)
            SyncHeaderHeight()
            element:FireEventTree("refreshCard")
        end,
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel.styles = ThemeEngine.MergeStyles(StageRules())
        end
    end)

    m_root = resultPanel
    m_selectedHero = nil

    return resultPanel
end

EncounterMontageStage.Create = CreateStage

--- the narrative stage -------------------------------------------------------
--
--The same frame (scene backdrop, header, hero row, pools) around a different
--middle: the section's text, its options as cards, and what the party's
--choices did. A section is either AGREED UPON -- one vote per player, a split
--settled by a random pick the stage flashes through first -- or taken by EACH
--HERO ON THEIR OWN, in which case a hero is dragged (or clicked) onto the
--option they take, exactly like approaching a montage entry.

--how many times the flash steps through the players before it lands.
local DECIDE_FLASH_STEPS = 21

--The candidate a split decision is flashing on right now, given the time
--since it started. Deterministic (it is a function of decision.startedAt and
--the server clock, both shared), decelerating, and lands on the winner.
local function FlashCandidateIndex(decision, now)
    local candidates = decision.candidates or {}
    local n = #candidates
    if n == 0 then
        return 1
    end
    local winner = 1
    for i, candidate in ipairs(candidates) do
        if candidate.key == decision.winner then
            winner = i
        end
    end
    local total = EncounterNarrative.DECIDE_FLASH_SECONDS or 3.2
    local elapsed = now - (tonumber(decision.startedAt) or now)
    if elapsed >= total then
        return winner, true
    end
    --a step count that is a multiple of the candidate count would start the
    --flash ON the winner, which gives the answer away; shift it by one.
    local steps_total = DECIDE_FLASH_STEPS
    if n > 1 and steps_total % n == 0 then
        steps_total = steps_total + 1
    end
    local p = math.max(0, elapsed / total)
    --ease out: the steps come fast and slow to a stop.
    local steps = math.floor(steps_total * (1 - (1 - p) * (1 - p)))
    --start so that the last step lands exactly on the winner.
    local start = ((winner - 1) - steps_total) % n
    return ((start + steps) % n) + 1, false
end

local function NarrativeChoiceFor(m, section, heroEntry)
    return EncounterNarrative.ChoiceForHero(m, section, heroEntry)
end

--Who chose this option, as a display line ("Kira, Brann").
local function ChoosersOfOption(m, section, index)
    local names = {}
    local heroes = EncounterMontage.Heroes()
    for _, voter in ipairs(EncounterNarrative.Voters(section, heroes)) do
        local choice = (m.choices or {})[voter.key]
        if choice ~= nil and tonumber(choice.optionIndex) == index then
            names[#names + 1] = voter.name
        end
    end
    return names
end

local function NarrativeOptionCard(section, option, index)
    local children = {
        gui.Label{ classes = {"eotwOptionName"}, text = option.name, interactable = false },
    }
    if option.text ~= "" then
        children[#children + 1] = gui.Label{ classes = {"eotwEntryDesc"}, text = option.text, interactable = false }
    end
    for _, effect in ipairs(option.effects or {}) do
        children[#children + 1] = gui.Label{
            classes = {"eotwAppliedLine"},
            text = EncounterScript.DescribeEffect(effect),
            interactable = false,
        }
    end
    local chooserLabel = gui.Label{ classes = {"eotwChoiceChip"}, text = "", interactable = false }
    children[#children + 1] = chooserLabel

    --individual sections take a hero (dragged or clicked); agreed ones take
    --the local player's vote straight off the card.
    local function CanTakeHero(heroid)
        return section.mode == "individual" and heroid ~= nil
            and EncounterNarrative.LocalUserCanChooseFor(heroid)
    end

    return gui.Panel{
        classes = {"eotwOptionCard"},
        width = 300,
        height = "auto",
        flow = "vertical",
        pad = 10,
        borderBox = true,
        margin = 6,
        valign = "top",
        bgimage = "panels/square.png",
        dragTarget = true,
        dragTargetPriority = 10,
        data = { optionIndex = index },
        children = children,

        press = function(element)
            local m = EncounterNarrative.GetState()
            if m == nil or m.phase ~= "choosing" then
                return
            end
            if section.mode == "individual" then
                local heroid = m_selectedHero
                if not CanTakeHero(heroid) or m_selectMode ~= "narrative" then
                    return
                end
                audio.FireSoundEvent("Mouse.Click")
                SelectHero(nil)
                EncounterNarrative.Choose(index, heroid)
                return
            end
            if EncounterNarrative.LocalUserPendingChoice() then
                audio.FireSoundEvent("Mouse.Click")
                EncounterNarrative.Choose(index)
            end
        end,

        dragTargets = function(element, on, mode)
            element:SetClass("droppable", on == true and (mode or "") == "narrative")
        end,
        selectHero = function(element, heroid, mode)
            element:SetClass("droppable", heroid ~= nil and (mode or "") == "narrative" and CanTakeHero(heroid))
        end,

        refreshNarrative = function(element, m)
            local chosen = false
            if m.phase == "resolved" and m.result ~= nil then
                if m.result.mode == "individual" then
                    for _, group in ipairs(m.result.groups or {}) do
                        if group.optionIndex == index then
                            chosen = true
                        end
                    end
                else
                    chosen = m.result.optionIndex == index
                end
            end
            element:SetClass("chosen", chosen)

            local actionable = false
            if m.phase == "choosing" then
                if section.mode == "individual" then
                    actionable = CanTakeHero(m_selectedHero)
                else
                    actionable = EncounterNarrative.LocalUserPendingChoice()
                end
            end
            element:SetClass("actionable", actionable)
            element:SetClass("droppable", section.mode == "individual" and CanTakeHero(m_selectedHero))

            --while the choices are still coming in, the names are hidden in
            --an agreed-upon section: a vote nobody can see is an honest one.
            local names = {}
            if m.phase ~= "choosing" or section.mode == "individual" then
                names = ChoosersOfOption(m, section, index)
            end
            chooserLabel.text = cond(#names > 0, table.concat(names, ", "), "")
            chooserLabel:SetClass("collapsed", #names == 0)
        end,

        narrativeFlash = function(element, optionIndex)
            element:SetClass("flashing", optionIndex == index)
        end,
    }
end

--One hero's card on the narrative stage: draggable onto an option while its
--owner still owes this section a choice, with the choice they made (or their
--player's, in an agreed-upon section) written under it.
local function CreateNarrativeHeroColumn(hero, section)
    local hud = Hud()
    local charid = hero.charid
    local card = nil
    local individual = section ~= nil and section.mode == "individual"

    local waitingBadge = gui.Panel{
        classes = {"eotwHeroBadge", "collapsed"},
        floating = true,
        halign = "center",
        valign = "top",
        y = 3,
        width = 22,
        height = 22,
        bgimage = "panels/square.png",
        interactable = false,
        thinkTime = 0.05,
        think = function(element)
            local r = (math.sin(dmhub.Time() * 2 * math.pi / 1.2) + 1) / 2
            element.selfStyle.scale = 0.9 + 0.2 * r
        end,
        gui.Label{ classes = {"eotwHeroBadgeText"}, text = "?", interactable = false },
    }

    if hud ~= nil and hud.CreateHeroCard ~= nil then
        card = hud.CreateHeroCard({ charid = charid, mine = false, name = hero.name }, {
            halign = "center",
            draggable = individual and EncounterNarrative.LocalUserCanChooseFor(charid),
            showStats = true,
            spendRecovery = true,
            click = function(element, openCharacterPanel)
                if individual and EncounterNarrative.LocalUserCanChooseFor(charid) then
                    audio.FireSoundEvent("Mouse.Click")
                    if m_selectedHero == charid then
                        SelectHero(nil)
                    else
                        SelectHero(charid, "narrative")
                    end
                    return
                end
                openCharacterPanel(element)
            end,
            beginDrag = function(element)
                element:SetClass("dragging", true)
                SelectHero(nil)
                Broadcast("dragTargets", true, "narrative")
            end,
            canDragOnto = function(element, target)
                if not target:HasClass("eotwOptionCard") then
                    return false
                end
                return individual and EncounterNarrative.LocalUserCanChooseFor(charid)
            end,
            drag = function(element, target)
                element:SetClass("dragging", false)
                Broadcast("dragTargets", false)
                if target == nil or not target:HasClass("eotwOptionCard") then
                    return
                end
                if individual and EncounterNarrative.LocalUserCanChooseFor(charid) then
                    audio.FireSoundEvent("Mouse.Click")
                    EncounterNarrative.Choose(target.data.optionIndex, charid)
                end
            end,
        })
        card:AddChild(waitingBadge)
    else
        card = gui.Label{ width = 132, height = 176, text = hero.name, bgimage = "panels/square.png", bgcolor = "#333333" }
    end

    local choiceLabel = gui.Label{ classes = {"eotwHeroChoice", "waiting"}, text = "", halign = "center" }

    local cardRow = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "center",
        valign = "top",
        CreateItemStrip(charid),
        card,
    }

    local allyRow = gui.Panel{
        width = 132,
        height = "auto",
        flow = "horizontal",
        halign = "center",
        wrap = true,
        tmargin = 4,
        create = function(element)
            local minis = {}
            for _, allyId in ipairs(EncounterMontage.GetAllies(charid)) do
                if hud ~= nil and hud.CreateAllyCard ~= nil then
                    minis[#minis + 1] = hud.CreateAllyCard(allyId)
                end
            end
            element.children = minis
        end,
    }

    return gui.Panel{
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "center",
        valign = "top",
        hmargin = 6,
        data = { charid = charid },
        cardRow,
        choiceLabel,
        allyRow,

        refreshNarrative = function(element, m)
            local choice = NarrativeChoiceFor(m, section, hero)
            local chosen = choice ~= nil
            card:SetClass("acted", chosen or m.phase ~= "choosing")
            local canChoose = individual and EncounterNarrative.LocalUserCanChooseFor(charid)
            card.draggable = canChoose
            --a "?" over every hero still owed a choice (their own in an
            --individual section, their player's in an agreed one), so the
            --party can see who they are waiting on.
            waitingBadge:SetClass("collapsed", chosen or m.phase ~= "choosing")
            if m_selectedHero == charid and not canChoose then
                SelectHero(nil)
            end
            card:SetClass("selected", m_selectedHero == charid)

            local text = ""
            local waiting = true
            if m.phase == "choosing" then
                if chosen then
                    --chosen is choice ~= nil.
                    ---@cast choice -nil
                    waiting = false
                    if individual then
                        text = (section.options[tonumber(choice.optionIndex) or 0] or {}).name or T("stage.narrative.hero_chosen")
                    else
                        --an agreed-upon vote stays secret until they are all in.
                        text = T("stage.narrative.hero_ready")
                    end
                else
                    text = T("stage.narrative.hero_choosing")
                end
            elseif chosen then
                ---@cast choice -nil
                waiting = false
                local index = tonumber(choice.optionIndex) or 0
                text = (section.options[index] or {}).name or ""
            end
            choiceLabel.text = text
            choiceLabel:SetClass("collapsed", text == "")
            choiceLabel:SetClass("waiting", waiting)
        end,

        selectHero = function(element, heroid)
            card:SetClass("selected", heroid == charid)
        end,

        narrativeFlashHeroes = function(element, heroids)
            local on = false
            for _, id in ipairs(heroids or {}) do
                if id == charid then
                    on = true
                end
            end
            card:SetClass("flashing", on)
        end,
    }
end

--The lines the stage shows once a section has resolved.
local function NarrativeResultChildren(m, section)
    local children = {}
    local result = m.result or {}
    if result.mode == "individual" then
        for _, group in ipairs(result.groups or {}) do
            children[#children + 1] = gui.Label{
                classes = {"eotwTurnTitle"},
                text = string.format("%s -- %s", group.optionName or "", table.concat(group.heroNames or {}, ", ")),
                interactable = false,
            }
            for _, line in ipairs(group.applied or {}) do
                children[#children + 1] = gui.Label{ classes = {"eotwAppliedLine"}, text = line, interactable = false }
            end
        end
        if #children == 0 then
            children[#children + 1] = gui.Label{ classes = {"eotwTurnText"}, text = T("stage.narrative.result_moves_on"), interactable = false }
        end
        return children
    end

    children[#children + 1] = gui.Label{
        classes = {"eotwTurnTitle"},
        text = result.optionName or "",
        interactable = false,
    }
    if result.decidedBy ~= nil and m.decision ~= nil then
        children[#children + 1] = gui.Label{
            classes = {"eotwTurnHint"},
            text = T("stage.narrative.result_decided_by", { hero = tostring(m.decision.winnerName or T("stage.narrative.result_decided_by_fallback")) }),
            interactable = false,
        }
    end
    for _, line in ipairs(result.applied or {}) do
        children[#children + 1] = gui.Label{ classes = {"eotwAppliedLine"}, text = line, interactable = false }
    end
    if #(result.applied or {}) == 0 then
        children[#children + 1] = gui.Label{ classes = {"eotwTurnText"}, text = T("stage.narrative.result_moves_on"), interactable = false }
    end
    return children
end

local function CreateNarrativeStage(args)
    local embedded = args ~= nil and args.embedded == true
    local m_sectionKey = nil
    local m_heroSignature = nil
    local m_scene = nil
    local m_flashIndex = nil

    --cond() evaluates both branches, so build these only when we own them.
    local backdrop, dim = nil, nil
    if not embedded then
        backdrop = CreateBackdrop()
        dim = CreateDim()
    end

    local titleLabel = gui.Label{ classes = {"eotwStageTitle"}, text = "", halign = "center" }
    local introLabel = gui.Label{ classes = {"eotwStageSubtitle"}, text = "", halign = "center" }
    local statusLabel = gui.Label{ classes = {"eotwStageRound"}, text = "", halign = "center" }
    local header = gui.Panel{
        width = "100%",
        height = HEADER_HEIGHT,
        flow = "vertical",
        halign = "center",
        valign = "top",
        titleLabel,
        introLabel,
        statusLabel,
    }

    local textLabel = gui.Label{ classes = {"eotwNarrativeText"}, text = "", halign = "center" }

    --A feature this section just unlocked, explained where the party is
    --already reading. It sits still: the blinking is on the POOL the words
    --point at, and a panel that blinks by itself just looks like a button
    --nobody can press. It stands until the party presses on.
    local calloutTitle = gui.Label{ classes = {"eotwCalloutTitle"}, text = "", interactable = false }
    local calloutText = gui.Label{ classes = {"eotwCalloutText"}, text = "", interactable = false }
    local calloutPanel = gui.Panel{
        classes = {"eotwCallout", "collapsed"},
        width = "92%",
        height = "auto",
        flow = "vertical",
        halign = "center",
        valign = "top",
        pad = 12,
        borderBox = true,
        bmargin = 12,
        bgimage = "panels/square.png",
        interactable = false,
        gui.Panel{
            classes = {"eotwCalloutIcon"},
            bgimage = "phosphor/brain.png",
            interactable = false,
        },
        calloutTitle,
        calloutText,
    }

    local promptLabel = gui.Label{ classes = {"eotwNarrativePrompt"}, text = "", halign = "center" }
    local optionsRow = gui.Panel{
        width = "auto",
        maxWidth = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        halign = "center",
        valign = "top",
    }
    local resultPanel = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "center",
        valign = "top",
        tmargin = 10,
    }

    --the split-decision flash: the banner names whoever it is on right now
    --and the hero cards of that player light up with it.
    local decideName = gui.Label{ classes = {"eotwDecideName"}, text = "", halign = "center" }
    local decideOption = gui.Label{ classes = {"eotwTurnText"}, text = "", halign = "center" }
    local decidePanel = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "center",
        valign = "top",
        vmargin = 8,
        gui.Label{ classes = {"eotwDecideBanner"}, text = T("stage.narrative.split_banner"), halign = "center" },
        decideName,
        decideOption,
    }

    local centerBody = gui.Panel{
        width = "100%-40",
        height = "auto",
        flow = "vertical",
        halign = "center",
        valign = "top",
        textLabel,
        calloutPanel,
        promptLabel,
        decidePanel,
        optionsRow,
        resultPanel,
    }
    local center = gui.Panel{
        classes = {"eotwTurnPanel"},
        width = "68%",
        height = "auto",
        maxHeight = "100%",
        flow = "vertical",
        halign = "center",
        valign = "top",
        bgimage = "panels/square.png",
        pad = 20,
        borderBox = true,
        vscroll = true,
        centerBody,
    }
    local body = gui.Panel{
        width = "100%-40",
        height = string.format("100%%-%d", HEADER_HEIGHT + HERO_ROW_HEIGHT),
        flow = "horizontal",
        halign = "center",
        valign = "top",
        center,
    }

    local heroRow = gui.Panel{
        width = "auto",
        height = HERO_ROW_HEIGHT,
        flow = "horizontal",
        halign = "center",
        valign = "bottom",
        tmargin = 10,
    }

    local pools = nil
    if not embedded then
        pools = CreatePoolsPanel()
    end

    local function RefreshHeroes(section)
        local heroes = EncounterMontage.Heroes()
        local sig = string.format("%s|%s", HeroSignature(heroes), tostring(section ~= nil and section.mode or ""))
        if sig ~= m_heroSignature then
            m_heroSignature = sig
            local columns = {}
            for _, hero in ipairs(heroes) do
                columns[#columns + 1] = CreateNarrativeHeroColumn(hero, section)
            end
            heroRow.children = columns
        end
    end

    local stage
    local function Refresh(element)
        local m = EncounterNarrative.GetState()
        local beat, script = EncounterNarrative.CurrentBeat()
        if m == nil or beat == nil then
            return
        end
        local sections = EncounterScript.NarrativeSections(beat)
        local index = math.max(1, math.min(#sections, tonumber(m.sectionIndex) or 1))
        local section = sections[index]
        if section == nil then
            return
        end

        --a new section rebuilds the middle (and re-hangs the scene art).
        local key = string.format("%s|%s", tostring(m.beatIndex), section.id)
        if key ~= m_sectionKey then
            m_sectionKey = key
            m_flashIndex = nil
            titleLabel.text = section.name
            --a series part's "If ...:" blocks read for the story so far.
            local sectionText = section.text
            if section.storyBlocks ~= nil then
                sectionText = EncounterScript.ResolveStoryText(section, EncounterMontage.Story())
            end
            textLabel.text = sectionText
            textLabel:SetClass("collapsed", sectionText == "")
            local intro = cond(index == 1, beat.intro or "", "")
            introLabel.text = intro
            introLabel:SetClass("collapsed", intro == "")
            local cards = {}
            for i, option in ipairs(section.options) do
                cards[#cards + 1] = NarrativeOptionCard(section, option, i)
            end
            optionsRow.children = cards
            if not embedded then
                --backdrop is built whenever the stage is not embedded.
                ---@cast backdrop -nil
                local scene = EncounterNarrative.SceneImage(script, beat, section)
                if scene ~= m_scene then
                    m_scene = scene
                    SetBackdropScene(backdrop, scene)
                end
            end
        end

        --the prompt line: the author's, plus how this section is decided.
        local how = cond(section.mode == "individual",
            T("stage.narrative.how_individual"),
            T("stage.narrative.how_party"))
        if section.implicitOption then
            how = T("stage.narrative.how_implicit")
        end
        promptLabel.text = trim(string.format("%s %s", section.prompt or "", how))

        if m.phase == "arriving" then
            statusLabel.text = T("stage.narrative.status_arriving")
        elseif m.phase == "done" then
            statusLabel.text = T("stage.narrative.status_complete")
        else
            local pending = EncounterNarrative.PendingVoters(m, section, nil)
            local text = T("stage.narrative.status_section", { index = index, count = #sections })
            if m.phase == "choosing" and #pending > 0 then
                text = T("stage.narrative.status_section_pending", { index = index, count = #sections, heroes = table.concat(pending, ", ") })
            elseif m.phase == "deciding" then
                text = T("stage.narrative.status_section_deciding", { index = index, count = #sections })
            end
            statusLabel.text = text
        end

        --a feature this section unlocked, explained for as long as
        --EncounterNarrative says the callout stands.
        local announce = EncounterNarrative.ActiveAnnounce()
        calloutPanel:SetClass("collapsed", announce == nil)
        if announce ~= nil then
            calloutTitle.text = T("stage.narrative.callout_unlocked", { feature = tostring(announce.name or "") })
            calloutText.text = tostring(announce.text or "")
        end

        decidePanel:SetClass("collapsed", m.phase ~= "deciding")
        resultPanel:SetClass("collapsed", m.phase ~= "resolved" and m.phase ~= "done")
        if m.phase == "resolved" then
            resultPanel.children = NarrativeResultChildren(m, section)
        end

        RefreshHeroes(section)
        element:FireEventTree("refreshNarrative", m)
    end

    stage = gui.Panel{
        styles = ThemeEngine.MergeStyles(StageRules()),
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        flow = "vertical",
        bgimage = cond(embedded, nil, "panels/square.png"),
        bgcolor = cond(embedded, "#00000000", "#05070a"),
        swallowPress = true,

        children = Classes(backdrop, dim, header, body, heroRow, pools, CreditOf(backdrop)),

        monitorGame = EncounterMontage.DocPath(),
        refreshGame = function(element)
            Refresh(element)
        end,

        create = function(element)
            Refresh(element)
            if not embedded then
                AcquireActionBarHide()
                EotwProf("stage created")
                element:ScheduleEvent("releaseLoadingScreen", 0.1)
            end
        end,

        destroy = function(element)
            if not embedded then
                ReleaseActionBarHide()
            end
        end,

        releaseLoadingScreen = function(element)
            if HoldForParty() then
                element:ScheduleEvent("releaseLoadingScreen", 0.1)
                return
            end
            EotwProf("stage up; releasing the loading screen")
            pcall(function() dmhub.ReleaseLoadingScreen() end)
        end,

        thinkTime = 0.05,
        think = function(element)
            if mod.unloaded then
                element:DestroySelf()
                return
            end
            local m = EncounterNarrative.GetState()
            if m ~= nil and m.phase == "deciding" and m.decision ~= nil then
                local index, landed = FlashCandidateIndex(m.decision, dmhub.serverTime)
                if index ~= m_flashIndex then
                    m_flashIndex = index
                    local candidate = (m.decision.candidates or {})[index]
                    if candidate ~= nil then
                        decideName.text = tostring(candidate.name or "")
                        decideOption.text = tostring(candidate.optionName or "")
                        element:FireEventTree("narrativeFlash", candidate.optionIndex)
                        element:FireEventTree("narrativeFlashHeroes", candidate.heroids)
                        if not landed then
                            audio.FireSoundEvent("Mouse.Click")
                        end
                    end
                end
            elseif m_flashIndex ~= nil then
                m_flashIndex = nil
                element:FireEventTree("narrativeFlash", nil)
                element:FireEventTree("narrativeFlashHeroes", {})
            end
            element:FireEventTree("refreshCard")
        end,
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if stage ~= nil and stage.valid then
            stage.styles = ThemeEngine.MergeStyles(StageRules())
        end
    end)

    m_root = stage
    m_selectedHero = nil

    return stage
end

EncounterMontageStage.CreateNarrative = CreateNarrativeStage

--- the Tactical Preparation stage ---------------------------------------------
--
--The last thing the party sees before the fight, when the week unlocked
--Intelligence: one card per bar, and a point of Intelligence buys a notch.
--Only the level they are ON is ever written down -- the rungs above it are
--blank pips, because what you have not worked out yet is exactly the thing
--the screen is selling.

local function PrepBrainIcon(classes)
    return gui.Panel{
        classes = classes,
        bgimage = "phosphor/brain.png",
        interactable = false,
    }
end

--One bar: its title, the notched track, the level the party is on, and
--(while there is anything to spend) the button that buys the next notch.
local function CreatePrepBar(beat, barId)
    local info = EncounterPrep.BarInfo(beat, barId)
    local max = #info.levels - 1

    --One segment per notch the party can BUY, not one per level: knowing
    --nothing is an empty track, so level 0 fills none of it.
    local pips = {}
    local fills = {}
    for i = 1, max do
        --the "if you spend" preview, pulsed over the empty segment while the
        --button is hovered. It is a floating child rather than a colour
        --written onto the segment, so nothing has to put the segment's own
        --colour back afterwards.
        local fill = gui.Panel{
            floating = true,
            interactable = false,
            width = "100%",
            height = "100%",
            bgimage = "panels/square.png",
            bgcolor = "#9cc4ff",
            cornerRadius = 3,
            opacity = 0,
            data = { previewing = false, opacity = 0 },
            thinkTime = 0.05,
            think = function(element)
                local opacity = 0
                if element.data.previewing then
                    local alpha = 0
                    pcall(function() alpha = EncounterMontage.FeatureBlinkAlpha() end)
                    --never all the way to solid: this is what the segment
                    --WOULD look like, not what it looks like.
                    opacity = 0.12 + 0.55 * alpha
                end
                if opacity ~= element.data.opacity then
                    element.data.opacity = opacity
                    element.selfStyle.opacity = opacity
                end
            end,
        }
        fills[i] = fill
        pips[i] = gui.Panel{
            classes = {"eotwPrepPip"},
            width = string.format("%.4f%%-6", 100 / max),
            interactable = false,
            data = { level = i },
            fill,
        }
    end
    local track = gui.Panel{ classes = {"eotwPrepTrack"}, children = pips }
    local levelLabel = gui.Label{ classes = {"eotwPrepLevel"}, text = info.levels[1], interactable = false }

    --the level the bar is on, kept here so the hover preview knows which
    --segment the next point would fill without re-reading the document.
    local m_level = 0
    local m_previewing = false

    local function ShowPreview(on)
        m_previewing = on
        for i, fill in ipairs(fills) do
            fill.data.previewing = on and (i == m_level + 1)
        end
    end

    local button = gui.Button{
        text = T("stage.prep.spend_button"),
        halign = "center",
        tmargin = 6,
        width = 220,
        height = 38,
        fontSize = 16,
        click = function(element)
            audio.FireSoundEvent("Mouse.Click")
            EncounterPrep.Spend(barId)
        end,
        hover = function(element)
            ShowPreview(true)
        end,
        dehover = function(element)
            ShowPreview(false)
        end,
    }

    return gui.Panel{
        classes = {"eotwOptionCard"},
        width = 520,
        height = "auto",
        flow = "vertical",
        pad = 12,
        borderBox = true,
        margin = 6,
        halign = "center",
        valign = "top",
        bgimage = "panels/square.png",
        data = { barId = barId },

        gui.Label{ classes = {"eotwOptionName"}, text = info.title, interactable = false },
        track,
        levelLabel,
        button,

        refreshPrep = function(element, m)
            local level = EncounterPrep.Level(m, barId) or 0
            local start = tonumber((m.start or {})[barId]) or level
            m_level = level
            for _, pip in ipairs(pips) do
                pip:SetClass("filled", pip.data.level <= level)
            end
            --a spend that landed while the pointer is still on the button
            --moves the preview along to the next segment.
            if m_previewing then
                ShowPreview(m.phase == "spending")
            end
            levelLabel.text = info.levels[level + 1] or ""
            --what their Intelligence bought reads differently from what they
            --already had.
            levelLabel:SetClass("bought", level > start)

            local canBuy = level < max and EncounterPrep.CanSpend(m, beat) and EncounterPrep.LocalUserIsVoter()
            button:SetClass("collapsed", not canBuy)
            element:SetClass("actionable", canBuy)
        end,
    }
end

local function CreatePrepHeroColumn(hero)
    local hud = Hud()
    local card = nil
    if hud ~= nil and hud.CreateHeroCard ~= nil then
        card = hud.CreateHeroCard({ charid = hero.charid, mine = false, name = hero.name }, {
            halign = "center",
            showStats = true,
            spendRecovery = true,
        })
    else
        card = gui.Label{ width = 132, height = 176, text = hero.name, bgimage = "panels/square.png", bgcolor = "#333333" }
    end

    local stateLabel = gui.Label{ classes = {"eotwHeroChoice", "waiting"}, text = "", halign = "center" }

    return gui.Panel{
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "center",
        valign = "top",
        hmargin = 6,
        data = { charid = hero.charid },
        card,
        stateLabel,

        refreshPrep = function(element, m)
            --one voice per player, so a hero's card shows their PLAYER's
            --state (all of one player's heroes say the same thing).
            local key = hero.ownerId or "PARTY"
            local ready = ((m or {}).ready or {})[key] ~= nil
            stateLabel.text = cond(ready, T("stage.prep.hero_ready"), T("stage.prep.hero_preparing"))
            stateLabel:SetClass("waiting", not ready)
            card:SetClass("acted", ready)
        end,
    }
end

local function CreatePrepStage(args)
    local embedded = args ~= nil and args.embedded == true
    local m_barSignature = nil
    local m_heroSignature = nil

    local backdrop, dim = nil, nil
    if not embedded then
        backdrop = CreateBackdrop()
        dim = CreateDim()
    end

    local titleLabel = gui.Label{ classes = {"eotwStageTitle"}, text = EncounterPrep.TITLE, halign = "center" }
    local introLabel = gui.Label{ classes = {"eotwStageSubtitle"}, text = EncounterPrep.INSTRUCTIONS, halign = "center" }
    --each player spends what their own heroes earned, so the big number is
    --THEIR Intelligence; the party's total sits beside it (an onlooker, who
    --has nothing to spend, sees only the total).
    local poolValue = gui.Label{ classes = {"eotwPrepPool"}, text = "0", interactable = false }
    local poolCaption = gui.Label{ classes = {"eotwPrepPoolCaption"}, text = T("stage.prep.pool_yours"), interactable = false }
    local partyCaption = gui.Label{ classes = {"eotwPrepPoolCaption", "party"}, text = "", interactable = false }
    local poolRow = gui.Panel{
        width = "auto",
        height = 38,
        flow = "horizontal",
        halign = "center",
        valign = "top",
        tmargin = 4,
        PrepBrainIcon({"eotwPrepPoolIcon"}),
        poolValue,
        poolCaption,
        partyCaption,
    }
    local header = gui.Panel{
        width = "100%",
        height = PREP_HEADER_HEIGHT,
        flow = "vertical",
        halign = "center",
        valign = "top",
        titleLabel,
        introLabel,
        poolRow,
    }

    local barsPanel = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "center",
        valign = "top",
    }
    local hintLabel = gui.Label{ classes = {"eotwTurnHint"}, text = "", halign = "center" }
    local proceedButton = gui.Button{
        classes = {"collapsed"},
        text = T("stage.prep.proceed_button"),
        halign = "center",
        tmargin = 10,
        width = 200,
        height = 44,
        fontSize = 20,
        click = function(element)
            audio.FireSoundEvent("Mouse.Click")
            EncounterPrep.Ready()
        end,
    }
    local waitButton = gui.Button{
        classes = {"collapsed"},
        text = T("stage.prep.wait_button"),
        halign = "center",
        tmargin = 10,
        width = 140,
        height = 34,
        fontSize = 16,
        click = function(element)
            audio.FireSoundEvent("Mouse.Click")
            EncounterPrep.Unready()
        end,
    }
    local resultPanel = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "center",
        valign = "top",
        tmargin = 10,
    }

    local centerBody = gui.Panel{
        width = "100%-40",
        height = "auto",
        flow = "vertical",
        halign = "center",
        valign = "top",
        barsPanel,
        resultPanel,
        hintLabel,
        proceedButton,
        waitButton,
    }
    local center = gui.Panel{
        classes = {"eotwTurnPanel"},
        width = 600,
        height = "auto",
        maxHeight = "100%",
        flow = "vertical",
        halign = "center",
        valign = "top",
        bgimage = "panels/square.png",
        pad = 20,
        borderBox = true,
        vscroll = true,
        centerBody,
    }
    local body = gui.Panel{
        width = "100%-40",
        height = string.format("100%%-%d", PREP_HEADER_HEIGHT + HERO_ROW_HEIGHT),
        flow = "horizontal",
        halign = "center",
        valign = "top",
        center,
    }

    local heroRow = gui.Panel{
        width = "auto",
        height = HERO_ROW_HEIGHT,
        flow = "horizontal",
        halign = "center",
        valign = "bottom",
        tmargin = 10,
    }

    local pools = nil
    if not embedded then
        pools = CreatePoolsPanel()
    end

    local function RefreshHeroes()
        local heroes = EncounterMontage.Heroes()
        local sig = HeroSignature(heroes)
        if sig ~= m_heroSignature then
            m_heroSignature = sig
            local columns = {}
            for _, hero in ipairs(heroes) do
                columns[#columns + 1] = CreatePrepHeroColumn(hero)
            end
            heroRow.children = columns
        end
    end

    local function Refresh(element)
        local m = EncounterPrep.GetState()
        if m == nil then
            return
        end
        local script = EncounterMontage.FindMapScript()
        local beat = script.parse.beats[m.beatIndex or 0]

        local ids = {}
        for _, bar in ipairs(m.bars or {}) do
            ids[#ids + 1] = bar.id
        end
        local sig = table.concat(ids, "|")
        if sig ~= m_barSignature then
            m_barSignature = sig
            local cards = {}
            for _, bar in ipairs(m.bars or {}) do
                cards[#cards + 1] = CreatePrepBar(beat, bar.id)
            end
            barsPanel.children = cards
        end

        local total = EncounterMontage.GetIntelligence()
        if EncounterPrep.LocalUserIsVoter() then
            poolValue.text = string.format("%d", EncounterPrep.LocalSpendable())
            poolCaption.text = T("stage.prep.pool_yours_to_spend")
            partyCaption.text = T("stage.prep.pool_party_total", { total = total })
            poolCaption:SetClass("collapsed", false)
            partyCaption:SetClass("collapsed", false)
        else
            poolValue.text = string.format("%d", total)
            poolCaption.text = T("stage.prep.pool_in_party")
            poolCaption:SetClass("collapsed", false)
            partyCaption:SetClass("collapsed", true)
        end

        local spending = m.phase == "spending"
        local ready = EncounterPrep.LocalUserReady(m)
        local canProceed = EncounterPrep.CanProceed(m, beat)
        proceedButton:SetClass("collapsed", not (spending and canProceed and not ready and EncounterPrep.LocalUserIsVoter()))
        waitButton:SetClass("collapsed", not (spending and ready))

        local hint = ""
        if spending then
            --everyone BUT this client: their own Proceed button is the
            --prompt, so naming them here would read as a fault.
            local others = EncounterPrep.PendingVoters(m, nil, EncounterPrep.VoterKeyForUser(dmhub.loginUserid, nil))
            if not canProceed then
                hint = T("stage.prep.hint_must_spend")
            elseif #others > 0 then
                hint = T("stage.prep.hint_waiting", { heroes = table.concat(others, ", ") })
            elseif ready then
                hint = T("stage.prep.hint_all_ready")
            end
        else
            hint = T("stage.prep.hint_done")
        end
        hintLabel.text = hint
        hintLabel:SetClass("collapsed", hint == "")

        resultPanel:SetClass("collapsed", spending or #(m.applied or {}) == 0)
        if not spending then
            local children = { gui.Label{ classes = {"eotwTurnTitle"}, text = T("stage.prep.result_title"), interactable = false } }
            for _, line in ipairs(m.applied or {}) do
                children[#children + 1] = gui.Label{ classes = {"eotwAppliedLine"}, text = line, interactable = false }
            end
            resultPanel.children = children
        end

        RefreshHeroes()
        element:FireEventTree("refreshPrep", m)
    end

    local stage
    stage = gui.Panel{
        styles = ThemeEngine.MergeStyles(StageRules()),
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        flow = "vertical",
        bgimage = cond(embedded, nil, "panels/square.png"),
        bgcolor = cond(embedded, "#00000000", "#05070a"),
        swallowPress = true,

        children = Classes(backdrop, dim, header, body, heroRow, pools, CreditOf(backdrop)),

        monitorGame = EncounterMontage.DocPath(),
        refreshGame = function(element)
            Refresh(element)
        end,

        create = function(element)
            Refresh(element)
            if not embedded then
                AcquireActionBarHide()
                EotwProf("stage created")
                element:ScheduleEvent("releaseLoadingScreen", 0.1)
            end
        end,

        destroy = function(element)
            if not embedded then
                ReleaseActionBarHide()
            end
        end,

        releaseLoadingScreen = function(element)
            if HoldForParty() then
                element:ScheduleEvent("releaseLoadingScreen", 0.1)
                return
            end
            EotwProf("stage up; releasing the loading screen")
            pcall(function() dmhub.ReleaseLoadingScreen() end)
        end,

        thinkTime = 0.25,
        think = function(element)
            if mod.unloaded then
                element:DestroySelf()
                return
            end
            Refresh(element)
            element:FireEventTree("refreshCard")
        end,
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if stage ~= nil and stage.valid then
            stage.styles = ThemeEngine.MergeStyles(StageRules())
        end
    end)

    return stage
end

EncounterMontageStage.CreatePrep = CreatePrepStage

--- the mounted script stage ---------------------------------------------------
--
--What is actually presented, ONCE, for the whole run of stage beats. It owns
--everything the two beat kinds share and everything that must not blink when
--the script moves on: the opaque background, the scene art, the dim, the
--pools strip, the hidden action bar and the held loading screen. Inside it
--sits one body -- the montage's or the narrative's -- and a beat change swaps
--only that, so two beats naming the same [[scene]] cut with nothing moving
--but the cards.
--
--Why it has to be this way: GameHud destroys and re-creates a presented
--dialog whenever its args change, so carrying the beat index in the args made
--every beat change a full teardown -- a frame of bare map, which reads as a
--flicker. The args are constant now (EncounterMontage.Present) and the live
--beat is read from the document this panel already monitors.

--Drive a screen transition's CrossFade from 1 -> 0 and free it at the end.
--(The idiom is ThemeSettingsDialog's: the engine holds a snapshot of the
--screen over everything, we change what is underneath, and the snapshot
--dissolves away to reveal it.)
local function FadeOutScreenTransition(transition, duration)
    local startTime = dmhub.Time()
    local tick
    tick = function()
        if transition == nil then
            return
        end
        if mod.unloaded then
            pcall(function() transition:Destroy() end)
            return
        end
        local t = (dmhub.Time() - startTime) / duration
        if t >= 1 then
            pcall(function()
                transition:CrossFade(0)
                transition:Destroy()
            end)
            return
        end
        pcall(function() transition:CrossFade(1 - t) end)
        dmhub.Schedule(0.01, tick)
    end
    dmhub.Schedule(0.01, tick)
end

--The beat the script is on, as the host stamped it.
local function CurrentScriptBeat()
    local beat, index, script = nil, 1, nil
    pcall(function()
        script = EncounterMontage.FindMapScript()
        index = tonumber(EncounterMontage.GetDoc().data.beat) or 1
        beat = script.parse.beats[index]
    end)
    return beat, index, script
end

--The backdrop for whatever is on screen: a narrative section may override its
--beat's scene, and a montage round its beat's.
local function CurrentSceneImage(beat, index, script)
    if beat == nil or script == nil then
        return nil
    end
    if beat.kind == "narrative" then
        local runtime = rawget(_G, "EncounterNarrative")
        if runtime == nil then
            return nil
        end
        --Only let a SECTION pick the scene while the live narrative state is
        --this beat's. Across a handover the previous beat's state is briefly
        --still on the document, and borrowing its section would swap the
        --backdrop to something that is not on screen and straight back again.
        local section = nil
        local state = runtime.GetState()
        if state ~= nil and state.beatIndex == index then
            section = runtime.CurrentSection()
        end
        return runtime.SceneImage(script, beat, section)
    end
    if beat.kind == "encounter" and beat.sceneTag == nil then
        --the encounter beat almost never names a [[scene]] of its own, and
        --the only thing it puts on the stage is the Tactical Preparation
        --screen. Borrow the last backdrop the script hung, so the party
        --prepares in the place the story left them rather than in the dark.
        for i = (tonumber(index) or 1), 1, -1 do
            local earlier = script.parse.beats[i]
            if earlier ~= nil and earlier.sceneTag ~= nil then
                return EncounterMontage.SceneImage(script, earlier)
            end
        end
        return nil
    end
    if beat.kind == "montage" then
        --a round may hang its own scene (day, then night); only trust the
        --live state's round while it is this beat's.
        local round = 1
        pcall(function()
            local m = EncounterMontage.GetState()
            if m ~= nil and m.beatIndex == index then
                round = m.round or 1
            end
        end)
        return EncounterMontage.MontageSceneImage(script, beat, round)
    end
    return EncounterMontage.SceneImage(script, beat)
end

--Other players' mouse cursors. The engine shares cursors as positions on the
--map, which mean nothing under a full-screen stage, so while the stage is up
--it switches this client to screen-space sharing: our pointer goes out as a
--screen position and everyone else's on the same surface is drawn over the
--stage. REF COUNTED like the action-bar hide, so a stage rebuilt before the
--old one is freed does not blink the mode off.
local CURSOR_SURFACE = "eotwstage"
local m_cursorHolders = 0

local function AcquireScreenCursors()
    m_cursorHolders = m_cursorHolders + 1
    pcall(function() dmhub.screenSpaceCursorSurface = CURSOR_SURFACE end)
end

local function ReleaseScreenCursors()
    m_cursorHolders = math.max(0, m_cursorHolders - 1)
    dmhub.Schedule(0.15, function()
        --after a Lua reload the NEW copy's stage owns the mode; leave it.
        if mod.unloaded or m_cursorHolders > 0 then
            return
        end
        pcall(function()
            if dmhub.screenSpaceCursorSurface == CURSOR_SURFACE then
                dmhub.screenSpaceCursorSurface = nil
            end
        end)
    end)
end

local function CreateScriptStage(args)
    local backdrop = CreateBackdrop()
    local dim = CreateDim()
    local pools = CreatePoolsPanel()
    local m_kind = nil
    local m_scene = nil
    local m_dismissed = false
    local m_holdsCursors = false
    local m_holdsActionBar = false
    local m_staleHideSent = false
    local m_staleCheckScheduled = false

    --one child, sized to fill: the montage's body or the narrative's.
    local bodyHolder = gui.Panel{
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        flow = "vertical",
    }

    --The script has handed the map back: go, but go like a cut-scene. Snapshot
    --the screen, hide ourselves underneath it (revealing the battlefield the
    --encounter beat has already set up), then dissolve the snapshot away. The
    --host takes the panel down for real once the dissolve has played
    --(EncounterMontage.DismissStage), so there is no rush here.
    local function Dismiss(element)
        if m_dismissed then
            return
        end
        m_dismissed = true
        --the battlefield shows through from here, so go back to map cursors now.
        if m_holdsCursors then
            m_holdsCursors = false
            ReleaseScreenCursors()
        end
        --and the action bar comes back with the map, even if the host never
        --takes this panel down.
        if m_holdsActionBar then
            m_holdsActionBar = false
            ReleaseActionBarHide()
        end
        local started = false
        pcall(function()
            local transition
            transition = dmhub.StartScreenTransition(function()
                if element ~= nil and element.valid then
                    element:SetClass("hidden", true)
                end
                FadeOutScreenTransition(transition, EncounterMontage.STAGE_DISMISS_SECONDS or 0.8)
            end)
            started = transition ~= nil
        end)
        if not started and element ~= nil and element.valid then
            --an engine without the transition bridge: just go.
            element:SetClass("hidden", true)
        end
    end

    --The host normally takes the stage down within a second of the dismiss
    --stamp. A stage still up long after (the host tick stopped first, e.g. a
    --test or dev encounter outside an EotW game) would come back on every
    --launch, so the host clears it. A hidden panel stops thinking, so the
    --check schedules itself rather than waiting for Refresh.
    local function ClearIfStale(element, dismissAt)
        if m_staleHideSent or not dmhub.isDMOrPlayerHost then
            return
        end
        local staleAfter = (EncounterMontage.STAGE_DISMISS_SECONDS or 0.8) + (EncounterMontage.STAGE_DISMISS_TIMEOUT or 4) + 5
        local age = dmhub.serverTime - dismissAt
        if age > staleAfter then
            m_staleHideSent = true
            printf("EotW: clearing a script stage dismissed %.0fs ago that was never taken down", age)
            EncounterMontage.Hide()
        elseif not m_staleCheckScheduled then
            m_staleCheckScheduled = true
            dmhub.Schedule(staleAfter - age + 0.5, function()
                m_staleCheckScheduled = false
                if mod.unloaded or not element.valid then
                    return
                end
                local at = EncounterMontage.DismissAt()
                if at ~= nil then
                    ClearIfStale(element, at)
                end
            end)
        end
    end

    local function Refresh(element)
        local dismissAt = EncounterMontage.DismissAt()
        if dismissAt ~= nil then
            Dismiss(element)
            ClearIfStale(element, dismissAt)
            return
        end

        local beat, index, script = CurrentScriptBeat()
        local kind = beat ~= nil and beat.kind or nil
        --the encounter beat owns the stage only while the party is spending
        --its Intelligence; everything else it does happens BEHIND the stage.
        if kind == "encounter" then
            local prep = rawget(_G, "EncounterPrep")
            if prep ~= nil and prep.IsLive() then
                kind = "prep"
            end
        end
        if kind ~= "montage" and kind ~= "narrative" and kind ~= "prep" then
            --a beat that does not own the stage, or a script we cannot read:
            --hold what is up rather than tearing the surface down. The host
            --hides the stage when it really means to hand the map back.
            return
        end

        if kind ~= m_kind then
            m_kind = kind
            if kind == "narrative" then
                bodyHolder.children = { CreateNarrativeStage{ embedded = true } }
            elseif kind == "prep" then
                bodyHolder.children = { CreatePrepStage{ embedded = true } }
            else
                bodyHolder.children = { CreateStage{ embedded = true } }
            end
        end

        local scene = CurrentSceneImage(beat, index, script)
        if kind == "prep" and scene == nil then
            --the preparation screen belongs to the encounter beat, which
            --usually declares no [[scene]] of its own. Keep whatever the
            --beat before it hung there rather than dropping to bare black
            --for the last screen before the fight.
            scene = m_scene
        end
        if scene ~= m_scene then
            m_scene = scene
            SetBackdropScene(backdrop, scene)
        end
    end

    local stage
    stage = gui.Panel{
        --The backdrop, the dim and the pools strip used to hang under a stage
        --root that carried these; keep them in the same style scope now that
        --they live out here. The body inside sets them again for its own
        --subtree, which costs nothing -- they are the same rules.
        styles = ThemeEngine.MergeStyles(StageRules()),
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        flow = "vertical",
        bgimage = "panels/square.png",
        bgcolor = "#05070a",
        swallowPress = true,

        --backdrop, dim and pools all float, so bodyHolder is the only child
        --in the flow and takes the whole surface.
        children = Classes(backdrop, dim, bodyHolder, pools, CreditOf(backdrop)),

        monitorGame = EncounterMontage.DocPath(),
        refreshGame = function(element)
            Refresh(element)
        end,

        create = function(element)
            --claimed before the first Refresh, so a stage created already
            --dismissed hands them straight back instead of holding them.
            m_holdsActionBar = true
            AcquireActionBarHide()
            m_holdsCursors = true
            AcquireScreenCursors()
            Refresh(element)
            --Entering an EotW game holds the loading screen until the opening
            --beat is on screen (EncounterOfTheWeek.md, the loading-screen
            --hold). We are it: let the screen fade over us, a beat later so
            --the first layout is in. Harmless when nothing is held.
            EotwProf("stage created")
            element:ScheduleEvent("releaseLoadingScreen", 0.1)
        end,

        destroy = function(element)
            if m_holdsActionBar then
                m_holdsActionBar = false
                ReleaseActionBarHide()
            end
            if m_holdsCursors then
                m_holdsCursors = false
                ReleaseScreenCursors()
            end
        end,

        releaseLoadingScreen = function(element)
            if HoldForParty() then
                element:ScheduleEvent("releaseLoadingScreen", 0.1)
                return
            end
            EotwProf("stage up; releasing the loading screen")
            pcall(function() dmhub.ReleaseLoadingScreen() end)
        end,

        thinkTime = 0.25,
        think = function(element)
            if mod.unloaded then
                element:DestroySelf()
                return
            end
            Refresh(element)
        end,
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if stage ~= nil and stage.valid then
            stage.styles = ThemeEngine.MergeStyles(StageRules())
        end
    end)

    return stage
end

EncounterMontageStage.CreateScriptStage = CreateScriptStage

--- the story screen --------------------------------------------------------

--The encounter's ending, read by each player on their own between the
--victory (or defeat) screen and the trip home: the script's "# Conclusion"
--or "# Defeat" text over that section's [[scene]] (else the last backdrop
--the script hung), and one button that takes the player home. Local to this
--client -- nobody waits for anybody. args:
--  outcome    = "victory" | "defeat"
--  title      = the encounter's name, shown under the outcome
--  section    = the parsed story section ({text, sceneTag, sceneLine})
--  script     = the map script the section came from (for its scene art)
--  onContinue = called once, when the player presses on (or the screen is
--               closed some other way)
--  choice     = optional { text, note, onChoose }: a second, first-placed
--               button (a series' "Continue to Part 2"); onChoose runs before
--               onContinue. note is a line shown above the buttons.
--               With stay = true the choice does not leave: its button
--               turns into busyText and the player waits on this screen (the
--               party going on together) until the caller closes it; the
--               other button still takes them home. chosen = true opens it
--               already chosen. status() is polled for the line above the
--               buttons (nil keeps the note). With no text there is no choice
--               button at all: the player waits on this screen, as if stayed.
--Returns the screen.
function EncounterMontageStage.ShowStoryScreen(args)
    local section = args.section
    local defeat = args.outcome == "defeat"
    local m_continued = false
    local m_stayed = false

    local scene = nil
    if args.script ~= nil then
        scene = EncounterMontage.SceneImage(args.script, section)
        local beats = args.script.parse ~= nil and args.script.parse.beats or {}
        for i = #beats, 1, -1 do
            if scene ~= nil then
                break
            end
            if beats[i].sceneTag ~= nil then
                scene = EncounterMontage.SceneImage(args.script, beats[i])
            end
        end
    end

    local backdrop = CreateBackdrop()
    local dim = CreateDim()

    local button
    local function Continue()
        if m_continued then
            return
        end
        m_continued = true
        if button ~= nil and button.valid then
            button.text = args.busyText or T("stage.story.returning")
            button:SetClass("disabled", true)
        end
        if args.onContinue ~= nil then
            args.onContinue()
        end
    end

    --args.buttonText / busyText: an authoring test ends the test instead.
    button = gui.Button{
        text = args.buttonText or T("stage.story.return_button"),
        halign = "center",
        valign = "top",
        tmargin = 18,
        width = 280,
        height = 48,
        fontSize = 22,
        click = function(element)
            audio.FireSoundEvent("Mouse.Click")
            Continue()
        end,
    }

    local buttons = button
    local choice = args.choice
    if choice ~= nil then
        local function ShowStayed(element)
            m_stayed = true
            element.text = choice.busyText or choice.text
            element:SetClass("disabled", true)
        end
        --a choice with no text has no button: this player waits for someone
        --else to decide (the series host), so the screen stays like a
        --stayed one until the caller closes it.
        if choice.text == nil then
            m_stayed = true
        end
        local choiceButton = gui.Button{
            classes = {cond(choice.text == nil, "collapsed", nil)},
            text = choice.text or "",
            valign = "top",
            tmargin = 18,
            rmargin = 16,
            width = 320,
            height = 48,
            fontSize = 22,
            create = function(element)
                if choice.stay and choice.chosen then
                    ShowStayed(element)
                end
            end,
            click = function(element)
                if m_continued or m_stayed then
                    return
                end
                audio.FireSoundEvent("Mouse.Click")
                pcall(choice.onChoose)
                if choice.stay then
                    ShowStayed(element)
                    return
                end
                element:SetClass("disabled", true)
                Continue()
            end,
        }
        buttons = gui.Panel{
            width = "auto",
            height = "auto",
            flow = "vertical",
            halign = "center",
            valign = "top",
            gui.Label{
                classes = {cond(choice.note == nil, "collapsed", nil)},
                text = choice.note or "",
                fontSize = 18,
                italics = true,
                color = "#efe4cc",
                width = "auto",
                height = "auto",
                halign = "center",
                tmargin = 14,
                thinkTime = 0.5,
                think = function(element)
                    if choice.status == nil then
                        return
                    end
                    local text = nil
                    pcall(function() text = choice.status() end)
                    text = text or choice.note or ""
                    if element.text ~= text then
                        element.text = text
                    end
                    element:SetClass("collapsed", text == "")
                end,
            },
            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                choiceButton,
                button,
            },
        }
    end

    local body = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        halign = "center",
        valign = "center",
        gui.Label{
            classes = {"eotwStageRound"},
            text = cond(defeat, T("stage.story.defeat"), T("stage.story.victory")),
            halign = "center",
            valign = "top",
            tmargin = 48,
            color = cond(defeat, "#e04545", "#ffd66b"),
            uppercase = true,
        },
        gui.Label{
            classes = {"eotwStageTitle", cond(args.title == nil or args.title == "", "collapsed", nil)},
            text = args.title or "",
            halign = "center",
            valign = "top",
            bmargin = 14,
        },
        gui.Panel{
            classes = {"eotwTurnPanel"},
            width = 900,
            maxWidth = "80%",
            height = "auto",
            maxHeight = "60%",
            flow = "vertical",
            halign = "center",
            valign = "top",
            bgimage = "panels/square.png",
            pad = 24,
            borderBox = true,
            vscroll = true,
            gui.Label{
                classes = {"eotwNarrativeText"},
                text = EncounterScript.VisibleText(section.text or ""),
                halign = "center",
                bmargin = 0,
            },
        },
        buttons,
    }

    local screen
    screen = gui.Panel{
        styles = ThemeEngine.MergeStyles(StageRules()),
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        flow = "vertical",
        bgimage = "panels/square.png",
        bgcolor = "#05070a",
        swallowPress = true,
        children = Classes(backdrop, dim, body, CreditOf(backdrop)),

        captureEscape = true,
        escape = function(element)
            --waiting for the party: Escape must not send the player home.
            if m_stayed then
                return
            end
            Continue()
        end,

        create = function(element)
            if scene ~= nil then
                SetBackdropScene(backdrop, scene)
            end
        end,

        --closed by anything else (a HUD rebuild): the player still goes home,
        --unless they are staying for the next part (the caller closes the
        --screen when it starts).
        destroy = function(element)
            if m_stayed then
                return
            end
            Continue()
        end,
    }

    gui.ShowModal(screen)
    return screen
end

pcall(function()
    GameHud.RegisterPresentableDialog{
        id = DIALOG_ID,
        keeplocal = false,
        create = function(args)
            return CreateScriptStage(args or {})
        end,
    }
end)

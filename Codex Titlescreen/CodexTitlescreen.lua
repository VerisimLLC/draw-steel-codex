
local mod = dmhub.GetModLoading()

local g_directlyLaunchingGame = false

local g_titlescreen = nil

for _, str in ipairs(dmhub.commandLineArguments) do
    if str == "--gameid" then
        g_directlyLaunchingGame = true
    end
end

if g_directlyLaunchingGame then
    return
end

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

--A Local (Offline) game whose data lives on another computer cannot be
--entered from here: connecting would make the local server create a fresh
--empty game.db and serve an empty game, which bounces back to the
--titlescreen -- and once that empty db exists, hasLocalData reports the
--game as present on this machine, so the play gate never engages again.
--Every EnterGame call site must check this before entering.
local function GameHasNoLocalData(game)
    return game ~= nil and game.storage == 3 and not game.hasLocalData
end

local function FindLobbyGame(gameid)
    if gameid == nil then
        return nil
    end
    for _, g in ipairs(lobby.games or {}) do
        if g.gameid == gameid then
            return g
        end
    end
    return nil
end

--Framed-panel modal for titlescreen messages, following the stall-modal /
--ShowPromoteLocalGameDialog pattern (gui.ShowModal() doesn't show up in the
--titlescreen's own modal stack). Used for the offline-game-on-another-
--computer explanation and for errors fired from C# via ShowTitlescreenError.
local function ShowTitlescreenMessageDialog(root, title, message)
    if root == nil or not root.valid then
        return
    end

    local modal
    modal = gui.Panel {
        floating = true,
        width = "100%",
        height = "100%",
        bgimage = "panels/square.png",
        bgcolor = "#000000b0",

        gui.Panel {
            classes = { "framedPanel" },
            styles = {
                Styles.Default,
                Styles.Panel,
            },
            bgimage = true,
            halign = "center",
            valign = "center",
            width = 640,
            height = "auto",
            minHeight = 280,
            flow = "vertical",
            vpad = 24,

            gui.Label {
                text = title,
                fontSize = 36,
                bold = true,
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "top",
                color = "white",
                tmargin = 12,
            },

            gui.Label {
                text = message,
                fontSize = 20,
                width = "80%",
                height = "auto",
                halign = "center",
                textAlignment = "center",
                color = "white",
                vmargin = 16,
            },

            gui.Button {
                text = "Close",
                halign = "center",
                valign = "bottom",
                bmargin = 12,
                escapeActivates = true,
                click = function(element)
                    modal:DestroySelf()
                end,
            },
        },
    }

    root:AddChild(modal)
end

local OFFLINE_GAME_ELSEWHERE_TITLE = "Game Data Not On This Computer"
local OFFLINE_GAME_ELSEWHERE_MESSAGE =
    "This offline game keeps its data on the computer where it was created, " ..
    "so it can't be played from here. Open the game on that computer and " ..
    "press Invite Players to deploy it online so you can access it anywhere."

--Mirror of CodexTitleBar.lua's "dev:storepreview" setting. Settings are
--keyed by id, so re-declaring it here just gives read access to the same
--value. Gates the store banner on the selection screen along with the rest
--of the shop UI.
local g_devStorePreviewSetting = setting{
    id = "dev:storepreview",
    default = false,
    storage = "preference",
}

--Selection-screen layout when the store banner is shown: the Director/Player
--card container (normally 1200 wide = two 500-wide cards + a 200 gap) narrows
--to pull the cards closer together, shrinks, and shifts up. The banner's
--width is derived from the container's scaled width so its edges always align
--exactly with the cards' outer edges.
local g_selectionCardsBannerWidth = 1133 --500+500 cards + 133 gap (2/3 of the normal 200)
local g_selectionCardsBannerScale = 0.92
local g_selectionCardsBannerY = -86
local g_selectionBannerWidth = math.floor(g_selectionCardsBannerWidth * g_selectionCardsBannerScale + 0.5)
local g_selectionBannerHeight = 200

--Dice sets showcased in the store banner's mini dice preview (assetids from
--the shop's Dice items). Each is rendered as its own idle-spinning preview die
--via a "#DicePreview:<assetid>:<seq>" bgimage (the same pooled mechanism the
--shop tiles use), so no shared preview scene is involved and the two sets spin
--independently. Noxa is the larger, forward-center die; Sea of Stars is the
--smaller one tucked in behind it, so the pair reads as an overlapping arc.
local g_storeBannerDiceNoxa = "62e2ade2-95a6-493b-81bb-3f9f08cc8312"
local g_storeBannerDiceSeaOfStars = "8a2a0ab2-d9e2-4ee4-a215-a480033ef6a6"

--Per-set banner art: when the rollable d10 on the banner's right seeds a
--dice set (see MakeStoreBannerRollDie), the banner's background art
--cross-fades to that set's banner. Keyed by the dice set assetid -- the
--same id the roll die seeds by -- so a set with no entry here simply falls
--back to the default art. The images live in Assets/UIImages/panels/shop/
--(same 1044x202 layout as the default art) and ship via
--import-ui-images.ps1 + a build, like any other UI image.
local g_storeBannerDefaultArt = "panels/shop/title-storebanner.png"
local g_storeBannerArtByAsset = {
    ["28c8efb2-81d9-416a-996a-436f8b09e840"] = "panels/shop/soulkiller-banner.png",   --Soulkiller Dice
    ["8a2a0ab2-d9e2-4ee4-a215-a480033ef6a6"] = "panels/shop/sea-of-stars-banner.png", --Sea of Stars
    ["c9606a08-22a6-49f0-ab2e-3d137ed7c874"] = "panels/shop/llianar-banner.png",      --Llianar
    ["67dcc6a6-e39c-4e36-8f12-67be4b6b51c2"] = "panels/shop/terran-steel-banner.png", --Terran Steel
    ["a1dd7e1a-585e-4203-9fb1-bb3477da32ce"] = "panels/shop/zodiakol-banner.png",     --Zodiakol
}

--Linear gradient across the banner art: dark at the far left (backing the
--mini dice showcase, as before) and fading to a substantial block of black
--on the right, where the rollable d10 and its "Drag to Roll" caption sit.
--Shared by the banner panel's own bgimage and its cross-fade art layer so
--the incoming art composites identically over the outgoing art.
local g_storeBannerGradient = {
    type = "linear",
    point_a = { x = 0, y = 0.5 },
    point_b = { x = 1, y = 0.5 },
    stops = {
        { position = 0.0,  color = "#000000ff" },
        { position = 0.28, color = "#ffffffff" },
        { position = 0.68, color = "#ffffffff" },
        { position = 0.88, color = "#000000ff" },
        { position = 1.0,  color = "#000000ff" },
    },
}

--Builds one spinning, drag-to-spin preview die for the store banner showcase.
--opts: assetid (dice set), size (px, square), and placement (halign/valign/x/y).
--The die idle-spins on its own (pooled preview scene); grabbing it spins it
--from the cursor via dice.SetPreviewDragging -- mirroring the shop banner die
--(CodexShopScreen's spinnable dieHit). The SetPreviewDragging call is
--pcall-guarded so a Lua-only reload against an older binary still shows the
--spinning die, just not draggable.
local function MakeStoreBannerDie(opts)
    --Key shared by the bgimage and the drag calls: "<assetid>:<seq>". The seq
    --("storebanner") only needs to keep this preview's pooled entry distinct;
    --the two dice already differ by assetid.
    local key = string.format("%s:storebanner", opts.assetid)
    return gui.Panel{
        floating = true,
        interactable = true,
        draggable = true,
        --Spin only -- never reposition the panel on drag (the die spins in place).
        dragMove = false,
        --Keep the normal cursor while draggable so it doesn't flash the
        --"forbidden" drag cursor (a draggable panel with no drop target).
        hoverCursor = "default",
        --Pooled preview RT: transparent outside the die, premultiplied alpha
        --(needs bgcolor set and blend = "premultiplied", like the shop banner die).
        bgimage = "#DicePreview:" .. key,
        bgcolor = "white",
        blend = "premultiplied",
        width = opts.size,
        height = opts.size,
        halign = opts.halign or "center",
        valign = opts.valign or "center",
        x = opts.x or 0,
        y = opts.y or 0,

        beginDrag = function(element)
            --Grabbing a banner die to spin it. deduplicate collapses a burst of
            --regrabs while fidgeting into a single event.
            track("shopTitleBannerDiceSpin", {
                assetid = opts.assetid,
                deduplicate = 5,
            })
            pcall(function() dice.SetPreviewDragging(key, true) end)
        end,
        --Release: stop feeding cursor input; the spin coasts and decays to idle.
        drag = function(element)
            pcall(function() dice.SetPreviewDragging(key, false) end)
        end,
    }
end

--All Dice shop items currently live on the store: the pool the banner's
--rollable d10 rotates through. Recomputed on every (re)seed so it tracks
--store changes, and returns {} until the shop items have downloaded (the
--cage's think below just retries until the pool is non-empty). Sorted by
--name (id tiebreak) so the rotation order is deterministic regardless of
--the engine's shop-item iteration order.
local function StoreBannerRollableDiceItems()
    local result = {}
    pcall(function()
        for _, item in pairs(assets.shopItems) do
            if item.itemType == "Dice" and item.onsale and item.assetid ~= nil and item.assetid ~= "" then
                result[#result + 1] = item
            end
        end
        table.sort(result, function(a, b)
            if a.name ~= b.name then
                return a.name < b.name
            end
            return a.id < b.id
        end)
    end)
    return result
end

--Whether the store banner's rollable die should have a live resting die
--right now. The resting preview die is a real 3D object compositing over
--the whole UI, so it must be cleared whenever the banner isn't visibly on
--screen: on the other titlescreen states, while the titlescreen is hidden
--behind the character sheet, while the banner is collapsed
--(dev:storepreview off), and while a full-screen shop dialog covers it.
local function StoreBannerDieEligible(element)
    if not element.valid or not element:HasClass("selection-screen") then
        return false
    end
    if not g_devStorePreviewSetting:Get() then
        return false
    end
    if g_titlescreen ~= nil and g_titlescreen.valid and g_titlescreen:HasClass("titlescreenHidden") then
        return false
    end
    local shopOpen = false
    pcall(function() shopOpen = ShopDiceBanner.ShopScreenOpen() end)
    return not shopOpen
end

--Builds the rollable d10 for the store banner's right-side black area: an
--invisible dice-preview cage (like the shop details view's "try dice"
--cages) with a "Drag to Roll" caption. A real 3D d10 rests on the cage; a
--click or drag throws a full-screen preview roll. The FIRST seed of the
--session picks a random on-sale dice set; after that, each executed roll
--reseeds with the NEXT set in the name-sorted live-store rotation, so
--repeated rolls walk the whole catalog deterministically. Reseeds that
--are not rolls -- the banner coming back into view, too-weak drags --
--keep the current set. Every executed roll is tracked
--(shopTitleBannerDiceRoll) with the dice set that was rolled.
--
--The cage seeds/clears itself to match the banner's actual visibility (see
--StoreBannerDieEligible): the titlescreenStateChanged event fired by
--SetTitlescreenState covers screen switches instantly, the dev:storepreview
--monitor covers the banner's collapse gate, and a slow think reconciles the
--rest (shop dialogs opening/closing over the banner, the shop-item list
--arriving after the core assets download). All engine calls are
--pcall-guarded so a Lua-only reload against an older binary degrades
--gracefully rather than erroring.
local function MakeStoreBannerRollDie()
    --gui.DicePreview is the dedicated dice-preview cage panel type (the
    --DicePreview* input methods and previewPanel roll-scoping only work on
    --it); fall back to a plain panel on an older binary (Lua-only reload).
    --(gui is engine userdata, so index via pcall rather than rawget.)
    local diceCageCtor = gui.Panel
    pcall(function() diceCageCtor = gui.DicePreview or gui.Panel end)

    return gui.Panel{
        floating = true,
        halign = "right",
        valign = "center",
        rmargin = 12,
        width = 240,
        height = "100%",
        flow = "vertical",

        styles = {
            { selectors = {"bannerTryDie"}, transitionTime = 0.1 },
            { selectors = {"bannerTryDie", "hover"}, scale = 1.15, brightness = 1.25 },
        },

        diceCageCtor{
            classes = {"bannerTryDie"},
            bgimage = true,
            bgcolor = "white",
            --Oversized invisible cage: the die renders over it and anchors to
            --its world centre, so a bigger panel just widens the click/drag
            --hitbox without moving the die. Lifted slightly (negative y = up)
            --so the die sits above the caption label instead of covering it.
            width = 150,
            height = 108,
            halign = "center",
            valign = "center",
            y = -14,
            floating = true,
            draggable = true,
            dragMove = false,
            --Keep the normal cursor while draggable (no drop target), like
            --the showcase dice on the banner's left.
            hoverCursor = "default",
            data = { item = nil, seeded = false, reseedPending = false },

            --Invisible-but-interactable cage: the real 3D die renders over it.
            styles = {
                gui.Style{ opacity = 0 },
            },

            create = function(element)
                pcall(function() element:SetAsDicePreviewPanel(true) end)
                --Thrown dice roll out to the real screen edges rather than a
                --tight box around the cage (panel-scoped, unlike the shop's
                --process-global SetPreviewRollScreenBounds, so it never leaks
                --into other cages).
                pcall(function() element.dicePreviewScreenBounds = true end)
                --Pick up + drag lifts the die a little; a gentle release (no
                --hurl) drops it from that altitude so it lands with an impact.
                --A quick flick still tosses a full roll.
                pcall(function() element.dicePreviewLiftDrop = true end)
                --On binaries that support it, the resting die renders inside
                --the panel (so dialogs opened over the banner cover it) and
                --becomes a real 3D die while hovered, dragged or rolling.
                pcall(function() element.dicePreviewVirtual = true end)
                element:FireEvent("reconcileBannerDie")
            end,
            destroy = function(element)
                pcall(function() element:CancelDicePreviewRoll() end)
                pcall(function() element:SetAsDicePreviewPanel(false) end)
                pcall(function() dice.SetRollPreviewModel(nil) end)
            end,

            --Slow reconciliation: catches shop dialogs opening/closing over
            --the banner (nothing fires an event for those) and retries
            --seeding until the shop-item list has downloaded.
            thinkTime = 0.5,
            think = function(element)
                element:FireEvent("reconcileBannerDie")
            end,

            --Instant reconciliation on titlescreen screen switches (fired
            --tree-wide by SetTitlescreenState)...
            titlescreenStateChanged = function(element)
                element:FireEvent("reconcileBannerDie")
            end,
            --...and on the dev:storepreview gate that collapses the banner.
            multimonitor = { "dev:storepreview" },
            monitor = function(element)
                element:FireEvent("reconcileBannerDie")
            end,

            reconcileBannerDie = function(element)
                local eligible = StoreBannerDieEligible(element)
                if eligible == element.data.seeded then
                    return
                end
                if eligible then
                    element:FireEvent("seedBannerDie")
                else
                    element:FireEvent("clearBannerDie")
                end
            end,

            --Seed a resting d10, armed so a click or drag executes this
            --same local/silent roll (previewPanel scopes the seed and the
            --armed roll to this cage, leaving any other cage's dice alone).
            --advance is true when the reseed follows an executed roll: it
            --rotates to the next set; every other path keeps the current
            --set (or picks the random starting set on the very first seed).
            seedBannerDie = function(element, advance)
                if not element.valid then
                    return
                end
                element.data.reseedPending = false
                if not StoreBannerDieEligible(element) then
                    element:FireEvent("clearBannerDie")
                    return
                end

                local items = StoreBannerRollableDiceItems()
                if #items == 0 then
                    --Shop items haven't downloaded yet; the think retries.
                    element.data.seeded = false
                    return
                end

                --Deterministic rotation through the live store dice: find
                --the previous set in the name-sorted pool, then step to the
                --next one when this reseed follows an executed roll, or
                --stay put for non-roll reseeds (visibility flips, cancelled
                --drags). data.item survives clear/seed cycles, so the
                --rotation also holds across the banner hiding and coming
                --back. Taking the fresh pool entry (rather than reusing
                --prev) keeps the item's fields current with the store.
                local item = nil
                local prev = element.data.item
                if prev ~= nil then
                    for i, candidate in ipairs(items) do
                        if candidate.id == prev.id then
                            if advance then
                                item = items[i % #items + 1]
                            else
                                item = candidate
                            end
                            break
                        end
                    end
                end
                if item == nil then
                    --Very first seed of the session -- or the previous set
                    --has left the store: start (or re-anchor) at random.
                    item = items[math.random(#items)]
                end
                element.data.item = item

                --Tell the banner which set now rests on the cage, so its
                --background art can cross-fade to that set's banner art
                --(handled by storeBannerSetSeeded on the banner panel).
                element:FireEventOnParents("storeBannerSetSeeded", item)

                --Clear any existing resting die first so the freshly seeded
                --die always picks up the new set's look, then override the
                --roll appearance with the set (bypasses the equipped-dice
                --ownership check, so unowned sets can be rolled too).
                pcall(function() element:CancelDicePreviewRoll() end)
                pcall(function() dice.SetRollPreviewModel(item.assetid) end)
                element.data.seeded = true
                dmhub.Roll{
                    preview = true, ["local"] = true, silent = true,
                    previewPanel = element,
                    numDice = 1, numFaces = 10, numKeep = 0, description = "Try Dice",
                    complete = function()
                        --The seeded preview roll only executes when the user
                        --clicks or drags the cage, so a completion here is a
                        --real banner roll (cancel covers the too-weak-drag
                        --and teardown paths). Only a real roll advances the
                        --set rotation.
                        track("shopTitleBannerDiceRoll", {
                            itemid = item.id,
                            assetid = item.assetid,
                            setName = item.name,
                            dice = "1d10",
                        })
                        if element.valid then element:FireEvent("requestReseed", true) end
                    end,
                    cancel = function()
                        if element.valid then element:FireEvent("requestReseed") end
                    end,
                }
            end,

            clearBannerDie = function(element)
                element.data.seeded = false
                element.data.reseedPending = false
                pcall(function() element:CancelDicePreviewRoll() end)
                --Hand back the roll-appearance override -- but not while a
                --shop screen is open: the shop's details view owns the
                --override then and clears it itself when it closes.
                local shopOpen = false
                pcall(function() shopOpen = ShopDiceBanner.ShopScreenOpen() end)
                if not shopOpen then
                    pcall(function() dice.SetRollPreviewModel(nil) end)
                end
            end,

            --advance passes through to seedBannerDie: true when the reseed
            --follows an executed roll (rotate to the next set).
            requestReseed = function(element, advance)
                if not element.valid or element.data.reseedPending then
                    return
                end
                element.data.reseedPending = true
                element:ScheduleEvent("seedBannerDie", 0.6, advance)
            end,

            --Hover wobble + click/drag-to-roll, routed through the
            --panel-scoped DicePreview* methods so they only touch THIS
            --cage's die. The click handler consumes the click, so unlike
            --the banner background a click on the die rolls it rather than
            --opening the store.
            hover = function(element)
                pcall(function() element:DicePreviewMouseEnter() end)
            end,
            dehover = function(element)
                pcall(function() element:DicePreviewMouseLeave() end)
            end,
            click = function(element)
                pcall(function() element:DicePreviewClick() end)
            end,
            dragging = function(element)
                pcall(function() element:DicePreviewDragThink() end)
            end,
            drag = function(element)
                pcall(function() element:DicePreviewDragEnd() end)
            end,
        },

        gui.Label{
            text = "Drag to Roll",
            floating = true,
            halign = "center",
            valign = "bottom",
            width = "auto",
            height = "auto",
            fontSize = 16,
            fontFace = "book",
            color = "#cfcfcf",
            bmargin = 16,
        },
    }
end

local function ScaleDimensions(dim)
    return dim * math.max(1, (dmhub.screenDimensions.x / dmhub.screenDimensions.y) / (1920 / 1080))
end

local function ScaleDimensionsToFill(dim)
    local a = dmhub.screenDimensions.x / dmhub.screenDimensions.y
    local b = 1920 / 1080
    return dim * math.max(a/b, b/a)
end

local resistanceCurve = function(x)
    x = x * 2
    local negative = x < 0
    x = math.abs(x)
    local y = 1 - (1 - x) ^ 2
    if negative then
        y = -y
    end

    return y
end

local g_setRecommendedGraphics = setting{
    id = "setrecommendedgraphicssettings",
    storage = "preference",
    default = false,
}

if not g_setRecommendedGraphics:Get() then
    g_setRecommendedGraphics:Set(true)

    dmhub.SetSettingValue("backgroundfps", false)
    dmhub.SetSettingValue("perf:hdr", true)
    dmhub.SetSettingValue("perf:castshadows", true)
    local systemPower = dmhub.systemHardwareRating
    if systemPower < 1 then
        print("Setting recommended graphics settings for a low power system")
        dmhub.SetSettingValue("perf:postprocess", false)
        dmhub.SetSettingValue("perf:msaa", false)
        dmhub.SetSettingValue("blackbarsoff", false)
        dmhub.SetSettingValue("vsync", 0)
        dmhub.SetSettingValue("fps", 30)
    else
        print("Setting recommended graphics settings for a high power system")
        dmhub.SetSettingValue("perf:postprocess", true)
        dmhub.SetSettingValue("perf:msaa", true)
        dmhub.SetSettingValue("blackbarsoff", true)
        dmhub.SetSettingValue("vsync", 1)
        dmhub.SetSettingValue("fps", 60)
    end

    -- On Mac retina displays, default hidef off unless the system is clearly
    -- powerful. Apple Silicon always registers as integrated in systemPower,
    -- so use a more permissive threshold than the main systemPower < 1 gate.
    local pixelCount = dmhub.screenDimensions.x * dmhub.screenDimensions.y
    if dmhub.platform == "macOS" and pixelCount > 3000000 and systemPower < 1.2 then
        dmhub.SetSettingValue("hidef", false)
    else
        dmhub.SetSettingValue("hidef", true)
    end

end

local g_directorGamePageSetting = setting {
    id = "dirgamepage",
    storage = "preference",
    default = 1,
}

-- When enabled, the "Create New Campaign" dialog offers community game
-- types (e.g. Crows) in addition to the built-in Draw Steel options. These
-- install a community-authored module on top of the Draw Steel system module.
-- Stored as a per-user preference so it shows in the Settings panel.
local g_allowCommunityGameTypes = setting{
    id = "allowcommunitygametypes",
    description = "Allow Community Game Types",
    help = "When enabled, the Create New Campaign screen offers community-authored game types (such as Crows) in addition to the built-in Draw Steel campaigns. These install an extra community module on top of the standard Draw Steel rules.",
    storage = "preference",
    section = "General",
    editor = "check",
    default = false,
}

local g_playerGamePageSetting = setting {
    id = "playergamepage",
    storage = "preference",
    default = 1,
}

local g_streamerModeSetting = setting {
    id = "streamermode",
    description = "Streamer Mode",
    help = "When enabled, game codes are hidden",
    editor = "check",
    storage = "preference",
    section = "general",
    default = false,
}

local g_gamePageSetting = g_playerGamePageSetting

-- Maximum number of games a user may participate in at once. Admin
-- accounts get a higher cap (48); everyone else is limited to 24.
local function MaxGamesAllowed()
    if dmhub.isAdminAccount then
        return 48
    end
    return 24
end

local function TooManyGamesDialog(element)
    local modal
    modal = gui.Panel {
        classes = { "framedPanel" },
        styles = {
            Styles.Default,
            Styles.Panel,
        },
        width = 600,
        height = 300,
        halign = "center",
        valign = "center",
        bgimage = true,
        flow = "vertical",
        floating  = true,

        gui.Label {
            classes = { "title" },
            text = "Too Many Games",
            fontSize = 20,
            width = "auto",
            halign = "center",
            valign = "top",
            bold = true,
        },

        gui.Label {
            classes = { "dialogMessage" },
            text = "You are already participating in too many games. Leave or delete some games before creating more.",
            fontSize = 20,
            width = "auto",
            maxWidth = 500,
            textAlignment = "center",
            halign = "center",
        },


        gui.Button {
            classes = { "dialogButton" },
            text = "Close",
            halign = "center",
            valign = "bottom",
            scale = 1.4,
            bmargin = 15,
            click = function(element)
                modal:DestroySelf()
            end,
        },

    }

    element.root:AddChild(modal)
end


local function EditHero(element, character)
    -- Lobby characters never have a token on a map, so creature:RefreshToken
    -- (the usual ValidateAndRepair trigger) never fires for them. Heal any
    -- invalid state here so the character sheet doesn't open on corrupt data.
    if character.properties ~= nil and not character.properties:IsValid() then
        character:ModifyProperties{
            description = "Repair character",
            execute = function()
                character.properties:ValidateAndRepair(true)
            end,
        }
    end

    character:ShowSheet()

    g_titlescreen:SetClass("titlescreenHidden", true)
    print("TITLESCREEN:: HIDE")

    local handler
    handler = dmhub.RegisterEventHandler("characterSheetClosed", function()
        g_titlescreen:SetClass("titlescreenHidden", false)
        dmhub.DeregisterEventHandler(handler)
        print("TITLESCREEN:: SHOW")
        handler = nil

        -- Track character_create after the builder closes so ancestry/class/kit
        -- reflect the player's actual choices, not the defaults.
        local c = character
        if c ~= nil and c.valid then
            local classInfo = c.properties:GetClass()
            local kitTable = dmhub.GetTable("kits")
            local kitId = c.properties:try_get("kitid")
            track("character_create", {
                ancestry = c.properties:RaceOrMonsterType() or "",
                class = classInfo and classInfo.name or "",
                kit = (kitId and kitTable[kitId]) and kitTable[kitId].name or "",
                method = "titlescreen",
                dailyLimit = 5,
            })
        end
    end)
end

local function ImportForgeSteel(element)
    FSCIImporter.ImportCharacter(function(c)
        c:ModifyProperties {
            description = "Create Character",
            execute = function()
                c.properties.mtime = ServerTimestamp()
                c.properties.creatorid = dmhub.userid
            end,
        }
    end)
end

local function CreateHero(element)
    local heroType = nil
    local characterTypes = dmhub.GetTable(CharacterType.tableName)
    for k, v in pairs(characterTypes) do
        if (not (rawget(v, "hidden"))) and v.name == "Hero" then
            heroType = v
            break
        end
    end

    if heroType ~= nil then
        local charid = game.CreateCharacter("character", heroType)

        dmhub.Coroutine(function()
            for i = 1, 100 do
                local c = dmhub.GetCharacterById(charid)
                if c ~= nil then
                    if element ~= nil and element.valid then
                        c:ModifyProperties {
                            description = "Create Character",
                            execute = function()
                                c.properties.mtime = ServerTimestamp()
                                c.properties.originalid = charid
                                c.properties.creatorid = dmhub.userid
                            end,
                        }
                        EditHero(element, c)
                    end
                    return
                end

                coroutine.yield(0.01)
            end
        end)
    end
end

local function CreateJoinGameModal(tokenToImport)
    local resultPanel

    local function AlreadyInGame(gameid)
        local games = lobby.games
        for _, game in ipairs(games) do
            if game.gameid == gameid then
                return true
            end
        end

        return false
    end

    local m_password = ""

    -- Dialog-internal layout rules: every label is 80%-wide, left-aligned,
    -- 16pt; every input fills 80%-16 to leave room for the border. Theme
    -- tokens for font/color/border come from the {label} / {input} base
    -- rules that GetStyles() ships -- we only override geometry here.
    local m_dialogStylesExtras = {
        {
            selectors = { "label" },
            width = "80%",
            height = "auto",
            textAlignment = "left",
            halign = "center",
            fontSize = 16,
            vmargin = 4,
        },
        {
            selectors = { "input" },
            width = "80%-16",
            halign = "center",
            fontSize = 16,
        },
    }

    resultPanel = gui.Panel {
        width = "100%",
        height = "100%",
        bgimage = true,
        bgcolor = "clear",
        floating = true,
        gui.Panel {
            styles = ThemeEngine.MergeStyles(m_dialogStylesExtras),
            classes = { "framedPanel" },
            width = 800,
            height = 900,
            halign = "center",
            valign = "center",
            flow = "vertical",

            -- Live re-theming: MergeStyles is a one-shot snapshot; subscribe
            -- so the dialog recolors when the active theme/scheme changes
            -- without requiring re-open. Guard with .valid so the callback
            -- no-ops after the dialog closes.
            create = function(element)
                ThemeEngine.OnThemeChanged(mod, function()
                    if element.valid then
                        element.styles = ThemeEngine.MergeStyles(m_dialogStylesExtras)
                    end
                end)
            end,

            gui.Label {
                classes = { "dialogTitle" },
                text = "Join Game",
                halign = "center",
                valign = "top",
                width = "auto",
                height = "auto",
                fontSize = 32,
                textAlignment = "center",
            },

            gui.Divider {
                tmargin = 4,
                bmargin = 8,
            },

            gui.Label {
                text = "Invite Code:",
            },

            gui.Input {
                text = "",
                placeholderText = "Enter Invite Code...",
                fontSize = 18,
                vpad = 8,
                editlag = 0.25,
                change = function(element)
                end,
                edit = function(element)
                    if element.text ~= "" then
                        resultPanel:FireEventTree("searchingForGame")

                        local text = element.text
                        lobby:LookupGame(text, function(gameInfo)
                            if text == element.text then
                                resultPanel:FireEventTree("lookupGame", gameInfo, text)
                            end
                        end)
                    else
                        resultPanel:FireEventTree("clearLookup")
                    end
                end,
            },

            gui.Label {
                text = "(Ask your Director for this code)",
            },

            gui.Label {
                classes = { "collapsed" },
                valign = "center",
                fontSize = 16,
                text = "Searching",
                data = {
                    n = 0,
                },
                thinkTime = 0.1,
                think = function(element)
                    element.data.n = element.data.n + 1
                    element.text = "Searching" .. string.rep(".", element.data.n % 4)
                end,
                searchingForGame = function(element)
                    element:SetClass("collapsed", false)
                end,
                lookupGame = function(element)
                    element:SetClass("collapsed", true)
                end,
                clearLookup = function(element)
                    element:SetClass("collapsed", true)
                end,
            },

            gui.Label {
                classes = { "collapsed" },
                valign = "center",
                fontSize = 16,
                text = "This game could not be found. Please check the invite code and try again.",
                searchingForGame = function(element)
                    element:SetClass("collapsed", true)
                end,
                lookupGame = function(element, gameInfo)
                    element:SetClass("collapsed", false)
                    if gameInfo == nil then
                        element.text = "This game could not be found. Please check the invite code and try again."
                    elseif gameInfo.deleted then
                        element.text = "This game has been deleted."
                    elseif AlreadyInGame(gameInfo.gameid) then
                        element.text = "You are already in this game."
                    else
                        element:SetClass("collapsed", true)
                    end
                end,
                clearLookup = function(element)
                    element:SetClass("collapsed", true)
                end,
            },

            gui.Panel {
                classes = { "collapsed" },
                halign = "center",
                valign = "center",
                flow = "vertical",
                height = "auto",
                width = "80%",
                lookupGame = function(element, gameInfo)
                    element:SetClass("collapsed", gameInfo == nil or gameInfo.deleted or AlreadyInGame(gameInfo.gameid))
                end,
                searchingForGame = function(element)
                    element:SetClass("collapsed", true)
                end,
                clearLookup = function(element)
                    element:SetClass("collapsed", true)
                end,

                gui.Label {
                    fontSize = 28,
                    bold = true,
                    width = "100%",
                    textAlignment = "left",
                    lookupGame = function(element, gameInfo)
                        if gameInfo == nil then
                            return
                        end

                        element.text = gameInfo.description
                    end,
                },

                gui.Label {
                    fontSize = 16,
                    bold = true,
                    width = "100%",
                    textAlignment = "left",
                    lookupGame = function(element, gameInfo)
                        if gameInfo == nil then
                            return
                        end

                        element.text = string.format("Directed by %s", gameInfo.ownerDisplayName)
                    end,
                },

                gui.Label {
                    fontSize = 20,
                    width = "100%",
                    textAlignment = "left",
                    lookupGame = function(element, gameInfo)
                        if gameInfo == nil then
                            return
                        end

                        element.text = gameInfo.descriptionDetails
                    end,
                },

                gui.Panel {
                    bgcolor = "white",
                    width = "100%",
                    height = "56.25% width", --16:9 aspect ratio
                    lookupGame = function(element, gameInfo)
                        if gameInfo == nil then
                            return
                        end

                        element.data.coverart = gameInfo.coverart
                        element.thinkTime = 0.01
                    end,

                    think = function(element)
                        if element.data.coverart ~= nil then
                            element.bgimage = element.data.coverart
                        end
                    end,
                },
            },

            gui.Panel {
                classes = { "hidden" },
                flow = "horizontal",
                width = "80%",
                height = "auto",
                halign = "center",
                lookupGame = function(element, gameInfo)
                    element:SetClass("hidden",
                        gameInfo == nil or gameInfo.deleted or AlreadyInGame(gameInfo.gameid) or gameInfo.password == nil or
                        gameInfo.password == "")
                end,
                gui.Label {
                    fontSize = 16,
                    width = "auto",
                    minWidth = 140,
                    text = "Password:",
                    textAlignment = "left",
                    halign = "left",
                },
                gui.Input {
                    password = true,
                    width = 180,
                    height = 20,
                    placeholderText = "Enter Password...",
                    fontSize = 16,
                    halign = "left",
                    lookupGame = function(element, gameInfo)
                        if gameInfo == nil then
                            return
                        end

                        m_password = ""
                        element.text = ""
                    end,
                    edit = function(element)
                        m_password = element.text
                        element.parent.parent:FireEventTree("passwordUpdated")
                    end,
                },
            },

            gui.Button {
                text = "Join Game",
                classes = { "hidden" },
                fontSize = 22,
                width = "auto",
                height = "auto",
                hpad = 12,
                vpad = 8,
                halign = "center",
                valign = "bottom",
                lookupGame = function(element, gameInfo)
                    element:SetClass("hidden",
                        gameInfo == nil or gameInfo.deleted or AlreadyInGame(gameInfo.gameid) or
                        (gameInfo.password ~= nil and gameInfo.password ~= "" and gameInfo.password ~= m_password))
                    element.data.gameInfo = gameInfo
                end,
                passwordUpdated = function(element)
                    local gameInfo = element.data.gameInfo
                    if gameInfo == nil then
                        return
                    end
                    element:SetClass("hidden",
                        gameInfo == nil or gameInfo.deleted or AlreadyInGame(gameInfo.gameid) or
                        (gameInfo.password ~= nil and gameInfo.password ~= "" and gameInfo.password ~= m_password))
                end,
                searchingForGame = function(element)
                    element:SetClass("hidden", true)
                end,
                clearLookup = function(element)
                    element:SetClass("hidden", true)
                end,
                press = function(element)
                    local gameid = element.data.gameInfo.gameid

                    if GameHasNoLocalData(element.data.gameInfo) then
                        ShowTitlescreenMessageDialog(element.root, OFFLINE_GAME_ELSEWHERE_TITLE, OFFLINE_GAME_ELSEWHERE_MESSAGE)
                        return
                    end

                    if tokenToImport ~= nil then
                        tokenToImport:ModifyProperties {
                            description = "Joining Game",
                            execute = function()
                                tokenToImport.properties.mtime = ServerTimestamp()
                                tokenToImport.properties.joinedCampaign = gameid
                            end,
                        }
                    end

                    lobby:JoinGame(gameid)
                    local root = element.root

                    dmhub.Coroutine(function()
                        for i = 1, 100 do
                            local games = lobby.games
                            for _, game in ipairs(games) do
                                if game.gameid == gameid then
                                    if root ~= nil and root.valid then
                                        local callback
                                        if tokenToImport ~= nil then
                                            dmhub.CopyTokenToClipboard(tokenToImport)
                                            callback = function()
                                                dmhub.PasteTokenFromClipboard(core.Loc { x = 0, y = 0 })
                                            end
                                        end
                                        root:FireEventTree("overrideLoadingScreenArt", game.coverart, game.gameid)
                                        lobby:EnterGame(game.gameid, callback)
                                    end
                                    return
                                end
                            end

                            coroutine.yield(0.1)
                        end
                    end)

                    resultPanel:DestroySelf()
                end,
            },

            gui.Button {
                text = "Add Character to Game",
                classes = { "hidden" },
                fontSize = 22,
                width = "auto",
                height = "auto",
                hpad = 12,
                vpad = 8,
                halign = "center",
                valign = "bottom",
                lookupGame = function(element, gameInfo)
                    element:SetClass("hidden",
                        tokenToImport == nil or
                        gameInfo == nil or gameInfo.deleted or
                        (not AlreadyInGame(gameInfo.gameid)))
                    element.data.gameInfo = gameInfo
                end,
                searchingForGame = function(element)
                    element:SetClass("hidden", true)
                end,
                clearLookup = function(element)
                    element:SetClass("hidden", true)
                end,
                press = function(element)
                    local gameInfo = element.data.gameInfo
                    if gameInfo == nil or tokenToImport == nil then
                        return
                    end

                    if GameHasNoLocalData(gameInfo) then
                        ShowTitlescreenMessageDialog(element.root, OFFLINE_GAME_ELSEWHERE_TITLE, OFFLINE_GAME_ELSEWHERE_MESSAGE)
                        return
                    end

                    local gameid = gameInfo.gameid
                    -- Treat any DM (owner or co-DM) as adding "for the party" since
                    -- they have no player slot of their own to own the token.
                    local addingAsDM = gameInfo:IsDM()

                    tokenToImport:ModifyProperties {
                        description = "Joining Game",
                        execute = function()
                            tokenToImport.properties.mtime = ServerTimestamp()
                            tokenToImport.properties.joinedCampaign = gameid
                        end,
                    }

                    dmhub.CopyTokenToClipboard(tokenToImport)
                    local root = element.root
                    local callback = function()
                        local newCharId = dmhub.PasteTokenFromClipboard(core.Loc { x = 0, y = 0 })
                        print("AddCharacterToGame:: pasted charid =", tostring(newCharId), "addingAsDM =", tostring(addingAsDM))
                        if not addingAsDM or newCharId == nil then
                            return
                        end
                        -- The C# paste path clears partyid+ownerId on cross-game pastes
                        -- and only re-sets ownerId for non-DMs. For a DM-added lobby
                        -- character we route it to the player party so it isn't
                        -- orphaned as an unowned NPC. Retry briefly because the patch
                        -- and parties table can settle a tick after the load callback.
                        dmhub.Coroutine(function()
                            for i = 1, 50 do
                                local newToken = dmhub.GetCharacterById(newCharId)
                                local partyid = GetDefaultPartyID()
                                if newToken ~= nil and partyid ~= nil and partyid ~= "players" then
                                    newToken.partyId = partyid
                                    newToken:UploadToken("Add Character to Game")
                                    print("AddCharacterToGame:: assigned to player party", partyid)
                                    return
                                end
                                coroutine.yield(0.1)
                            end
                            print("AddCharacterToGame:: gave up waiting for token/party to settle")
                        end)
                    end

                    if root ~= nil and root.valid then
                        root:FireEventTree("overrideLoadingScreenArt", gameInfo.coverart, gameid)
                    end
                    lobby:EnterGame(gameid, callback)

                    resultPanel:DestroySelf()
                end,
            },

            gui.Button {
                classes = { "closeButton" },
                floating = true,
                halign = "right",
                valign = "top",
                press = function(element)
                    resultPanel:DestroySelf()
                end,
            }
        }
    }

    return resultPanel
end

local g_moduleOptions = {
    {
        id = "venla-deliantomb",
        text = "The Delian Tomb",
        descriptionDetails =
        "This is the classic starter adventure from Matt Colville's Running the Game series, expanded and updated for MCDM's new fantasy RPG Draw Steel! The Delian Tomb includes everything you need to get started including a step-by-step tutorial for both players and directors!",
        coverart = "panels/backgrounds/delian-tomb-bg.png",
    },
    {
        id = "mcdm-startermap",
        text = "Custom Campaign",
        descriptionDetails =
        "Forge your own adventure! We'll start you in a tavern with all the Draw Steel rules and you can take it from there.",
        coverart = "panels/backgrounds/mcdm-cinematic.jpeg",
    },
}

-- Community game types, only offered when the "Allow Community Game Types"
-- preference is enabled. Each entry's id is the module that gets installed as
-- the game's starting module (CreateGameDialog defaults startingModule to the
-- option's id), so it must be a published module that contains a starter map.
-- By default the Draw Steel system module (mcdm-drawsteel) is auto-injected
-- underneath so the community module layers on top of the base game; set
-- noSystemModule = true on an entry to suppress that injection and install the
-- community module standalone.
local g_communityModuleOptions = {
    {
        id = "codex-crowdex",
        text = "Crows",
        -- Crows ships as a self-contained game system, so we suppress the
        -- mcdm-drawsteel system-module injection and install only crowdex.
        noSystemModule = true,
        descriptionDetails =
        "Installs the community Crows module as a standalone game system. (Community playtest content.)",
        coverart = "panels/backgrounds/mcdm-cinematic.jpeg",
    },
}

local function CreateGameEditor(options)
    local mode = options.mode or "create"
    local resultPanel

    local m_game = options.game

    local m_uploadCoverArt = nil

    -- Dialog-internal layout rules: every label is 80%-wide, left-aligned,
    -- 16pt; every input fills 80%-16 to leave room for the border. Theme
    -- tokens for font/color/border come from the {label} / {input} base
    -- rules that GetStyles() ships -- we only override geometry here.
    local m_dialogStylesExtras = {
        {
            selectors = { "label" },
            width = "80%",
            height = "auto",
            textAlignment = "left",
            halign = "center",
            fontSize = 16,
            vmargin = 4,
        },
        {
            selectors = { "input" },
            width = "80%-16",
            halign = "center",
            fontSize = 16,
        },
    }

    print("CREATE EDITOR")

    resultPanel = gui.Panel {
        width = "100%",
        height = "100%",
        bgimage = true,
        bgcolor = "clear",
        floating = true,
        gui.Panel {
            styles = ThemeEngine.MergeStyles(m_dialogStylesExtras),
            classes = { "framedPanel" },
            width = 800,
            height = 900,
            halign = "center",
            valign = "center",
            flow = "vertical",

            -- Live re-theming: MergeStyles is a one-shot snapshot; subscribe
            -- so the dialog recolors when the active theme/scheme changes
            -- without requiring re-open. Guard with .valid so the callback
            -- no-ops after the dialog closes.
            create = function(element)
                ThemeEngine.OnThemeChanged(mod, function()
                    if element.valid then
                        element.styles = ThemeEngine.MergeStyles(m_dialogStylesExtras)
                    end
                end)
            end,

            gui.Label {
                classes = { "dialogTitle" },
                text = cond(mode == "create", "Create New Campaign", "Edit Campaign"),
                halign = "center",
                valign = "top",
                width = "auto",
                height = "auto",
                fontSize = 32,
                textAlignment = "center",
            },

            gui.Divider {
                tmargin = 4,
                bmargin = 8,
            },

            gui.Label {
                text = "Campaign Name:",
            },

            gui.Input {
                text = m_game.description,
                placeholderText = "Enter Campaign Name",
                fontSize = 22,
                vpad = 4,
                change = function(element)
                    m_game.description = element.text
                end,
            },

            gui.Label {
                text = "Campaign Description:",
                tmargin = 8,
            },

            gui.Input {
                text = m_game.descriptionDetails,
                placeholderText = "Enter Campaign Details",
                fontSize = 16,
                multiline = true,
                height = 60,
                characterLimit = 240,
                textAlignment = "topleft",
                change = function(element)
                    m_game.descriptionDetails = element.text
                end,
            },

            gui.Label {
                text = "Cover Art:",
                tmargin = 8,
            },

            --cover art
            gui.Panel {
                id = "coverart",
                bgimage = true,
                bgcolor = "clear",
                width = "80%",
                height = "56.25% width", --16:9 aspect ratio
                halign = "center",
                valign = "top",
                hmargin = 32,

                press = function(element)
                    dmhub.OpenFileDialog {
                        id = "CoverArt",
                        extensions = { "jpeg", "jpg", "png", "mp4", "webm", "webp" },
                        prompt = string.format("Choose image or video to use for your game's cover art"),
                        open = function(path)
                            local imageid
                            imageid = m_game:UploadCoverArt {
                                path = path,
                                upload = function()
                                end,
                                error = function(message)
                                    local modal
                                    modal = gui.Panel {
                                        classes = { "framedPanel" },
                                        styles = ThemeEngine.GetStyles(),
                                        width = 600,
                                        height = 600,
                                        floating = true,
                                        halign = "center",
                                        valign = "center",

                                        create = function(element)
                                            ThemeEngine.OnThemeChanged(mod, function()
                                                if element.valid then
                                                    element.styles = ThemeEngine.GetStyles()
                                                end
                                            end)
                                        end,

                                        gui.Label {
                                            classes = { "modalTitle" },
                                            text = "Error Uploading Cover Art",
                                        },

                                        gui.Label {
                                            classes = { "modalMessage" },
                                            text = message,
                                        },

                                        gui.Panel {
                                            width = "auto",
                                            height = "auto",
                                            halign = "center",
                                            valign = "bottom",
                                            vmargin = 16,
                                            gui.Button {
                                                text = "Close",
                                                halign = "center",
                                                click = function(element)
                                                    modal:DestroySelf()
                                                end,
                                            },
                                        },
                                    }

                                    element.root:AddChild(modal)
                                end,
                            }
                        end,


                    }
                end,

                styles = {
                    {
                        transitionTime = 0.1,
                        selectors = { "hover" },
                        brightness = 0.5,
                    },
                },

                gui.Panel{
                    interactable = false,
                    width = "100%",
                    height = "100%",
                    bgcolor = "white",
                    bgimage = m_game.coverart or "panels/backgrounds/delian-tomb-bg.png",
                    refreshGames = function(element)
                        element.bgimage = m_game.coverart or "panels/backgrounds/delian-tomb-bg.png"
                    end,
                },

                gui.Label {
                    gui.Label {
                        fontSize = 10,
                        floating = true,
                        bold = true,
                        valign = "bottom",
                        halign = "center",
                        text = "Ideal Image Size: 1920x1080",
                        color = "white",
                        opacity = 0.5,
                        vmargin = 2,
                        width = "auto",
                        height = "auto",
                    },
                    id = "coverartBand",
                    interactable = false,
                    width = "100%",
                    height = "25%",
                    valign = "center",
                    bgimage = "panels/square.png",
                    bgcolor = "black",
                    opacity = 0.9,
                    color = "white",
                    textAlignment = "center",
                    fontSize = 24,
                    text = "Choose Cover Art",
                    styles = {
                        {
                            selectors = { "#coverartBand" },
                            hidden = 1,
                        },
                        {
                            transitionTime = 0.1,
                            selectors = { "#coverartBand", "parent:hover" },
                            hidden = 0,
                        },
                    },
                },
            },

            -- Local games don't have a shareable invite code -- they live on
            -- a server process tied to this user's machine. Show "Offline
            -- Game" + a Deploy Online button in place of the copy-the-code
            -- panel. The deploy button kicks off the same local->DO promote
            -- flow the titlescreen's Invite Players button uses.
            gui.Label {
                tmargin = 8,
                text = cond(m_game.storage == 3, "Offline Game", "Invite Code:"),
            },

            -- Lua `and`/`or` short-circuits, so only the chosen branch's
            -- panel constructor actually runs here. Using cond() would
            -- eagerly evaluate both and leak an unattached panel.
            (m_game.storage == 3 and (
                -- IIFE so the Deploy Online button can share locals with
                -- its inline progress bar + status label for the promote
                -- flow. Clicking the button hides it, reveals the progress
                -- controls, and drives lobby:PromoteLocalGame. On success
                -- the surrounding editor is destroyed and a fresh editor
                -- for the newly-deployed online game replaces it, so the
                -- settings dialog naturally refreshes to the cloud variant
                -- (invite-code panel, etc.) without us having to shuffle
                -- individual fields.
                (function()
                    local deployButton
                    local progressLabel
                    local progressBar
                    local container

                    local function startDeploy()
                        deployButton:SetClass("hidden", true)
                        progressLabel:SetClass("hidden", false)
                        progressBar:SetClass("hidden", false)

                        lobby:PromoteLocalGame {
                            gameid = m_game.gameid,
                            progress = function(status, pct)
                                if container == nil or not container.valid then return end
                                if progressLabel.valid then progressLabel.text = status end
                                if progressBar.valid then progressBar:SetValue(pct or 0) end
                            end,
                            complete = function(success, newGameid, err)
                                if container == nil or not container.valid then return end
                                if success then
                                    if progressLabel.valid then progressLabel.text = "Done! Opening deployed game..." end
                                    if progressBar.valid then progressBar:SetValue(1) end
                                    dmhub.Schedule(0.5, function()
                                        if resultPanel == nil or not resultPanel.valid then return end
                                        local newGame = nil
                                        for _, g in ipairs(lobby.games or {}) do
                                            if g.gameid == newGameid then
                                                newGame = g
                                                break
                                            end
                                        end
                                        if newGame ~= nil then
                                            resultPanel.root:AddChild(CreateGameEditor { game = newGame })
                                        end
                                        resultPanel:DestroySelf()
                                    end)
                                else
                                    if progressLabel.valid then
                                        progressLabel.text = "Deployment failed: " .. (err or "unknown error")
                                        progressLabel:SetClass("danger", true)
                                    end
                                    if progressBar.valid then progressBar:SetClass("hidden", true) end
                                    if deployButton.valid then deployButton:SetClass("hidden", false) end
                                end
                            end,
                        }
                    end

                    deployButton = gui.Button {
                        text = "Deploy Online",
                        width = 360,
                        height = 36,
                        fontSize = 18,
                        halign = "center",
                        click = function(element) startDeploy() end,
                    }
                    progressLabel = gui.Label {
                        classes = { "hidden" },
                        text = "Preparing...",
                        fontSize = 12,
                        halign = "center",
                        textAlignment = "center",
                        width = 360,
                        height = "auto",
                        vmargin = 2,
                    }
                    progressBar = gui.ProgressBar {
                        classes = { "hidden" },
                        width = 360,
                        height = 24,
                        value = 0,
                        halign = "center",
                    }
                    container = gui.Panel {
                        width = 360,
                        height = "auto",
                        halign = "center",
                        vmargin = 0,
                        flow = "vertical",
                        deployButton,
                        progressLabel,
                        progressBar,
                    }
                    return container
                end)()
            )) or (
                gui.Panel {
                    -- Custom invite-code panel: themed @border for the frame
                    -- and @fg for the icon tint. The {bordered} class would
                    -- skip cornerRadius + beveledcorners, so we keep this as
                    -- a per-instance MergeStyles block routed through the
                    -- parent ThemeEngine cascade.
                    styles = ThemeEngine.MergeStyles{
                        {
                            selectors = { "infoPanel" },
                            bgimage = "panels/square.png",
                            bgcolor = "clear",
                            height = 60,
                            borderColor = "@border",
                            borderWidth = 2,
                            cornerRadius = 8,
                            beveledcorners = true,
                        },
                        {
                            selectors = { "infoPanel", "selectable", "hover" },
                            transitionTime = 0.2,
                            brightness = 1.5,
                        },
                        {
                            selectors = { "infoLabel" },
                            fontSize = 32,
                            minFontSize = 12,
                            textAlignment = "right",
                            hmargin = 24,
                            halign = "right",
                            valign = "center",
                            width = "60%",
                            height = "auto",
                        },
                        {
                            selectors = { "infoIcon" },
                            height = "70%",
                            width = "100% height",
                            bgcolor = "@fg",
                            halign = "left",
                            valign = "center",
                            hmargin = 16,
                        },
                        {
                            selectors = { "infoIcon", "parentSelectable", "parent:hover" },
                            brightness = 1.5,
                            transitionTime = 0.1,
                        },

                    },


                    classes = { "infoPanel", "selectable" },
                    height = 30,
                    width = "80%",
                    halign = "center",
                    vmargin = 0,
                    click = function(element)
                        local tooltip = gui.Tooltip { text = "Copied to Clipboard", valign = "top", borderWidth = 0 } (
                            element)
                        dmhub.CopyToClipboard(m_game.gameid)
                    end,

                    gui.Label {
                        classes = { "infoLabel" },
                        fontSize = 16,
                        minFontSize = 16,
                        width = "70%",
                        textAlignment = "center",
                        halign = "center",
                        text = m_game.gameid,
                    },

                    gui.Panel {
                        classes = { "infoIcon", "selectable", "parentSelectable" },
                        halign = "right",
                        bgimage = "icons/icon_app/icon_app_108.png",
                        hmargin = 8,
                        height = "70%",
                        width = "100% height",
                    },
                }
            ),

            gui.Label {
                tmargin = 8,
                text = "Password:",
            },

            gui.Input {
                characterLimit = lobby.maxGamePasswordLength,
                placeholderText = "(Optional) Enter a password here...",
                password = true,

                change = function(element)
                    m_game.password = element.text
                end,
            },

            gui.Panel {
                width = "80%",
                height = "auto",
                halign = "center",
                valign = "bottom",
                vmargin = 16,
                gui.Button {
                    text = "Confirm",
                    halign = "center",
                    height = 48,
                    width = 140,
                    fontSize = 26,
                    bold = true,
                    press = function(element)
                        if mode == "create" then
                            element.root:FireEventTree("overrideLoadingScreenArt", m_game.coverart, m_game.gameid)
                            lobby:EnterGame(m_game.gameid)
                        end
                        resultPanel:DestroySelf()
                    end,
                },

                gui.Button {
                    text = "Migrate to Durable Objects",
                    halign = "left",
                    valign = "bottom",
                    fontSize = 16,
                    height = 32,
                    width = 220,
                    -- Only visible to dev users on Firebase-backed games
                    hidden = (not dmhub.GetSettingValue("dev")) or (m_game.storage ~= 0),
                    press = function(element)
                        local migrateButton = element
                        local statusLabel
                        local modal
                        modal = gui.Panel {
                            classes = { "framedPanel" },
                            floating = true,
                            width = 600,
                            height = 240,
                            halign = "center",
                            valign = "center",
                            flow = "vertical",
                            styles = ThemeEngine.GetStyles(),

                            create = function(element)
                                ThemeEngine.OnThemeChanged(mod, function()
                                    if element.valid then
                                        element.styles = ThemeEngine.GetStyles()
                                    end
                                end)
                            end,

                            gui.Label {
                                classes = { "modalTitle" },
                                text = "Migrating to Durable Objects",
                                width = "auto",
                                fontSize = 24,
                                vmargin = 12,
                            },

                            gui.Label {
                                id = "migrationStatus",
                                text = "Starting...",
                                width = "auto",
                                height = "auto",
                                halign = "center",
                                valign = "center",
                                fontSize = 16,
                                create = function(element)
                                    statusLabel = element
                                end,
                            },

                            gui.Panel {
                                halign = "center",
                                valign = "bottom",
                                vmargin = 16,
                                width = "auto",
                                height = "auto",
                                gui.Button {
                                    id = "closeMigrationBtn",
                                    text = "Close",
                                    fontSize = 16,
                                    width = 120,
                                    height = 32,
                                    halign = "center",
                                    interactable = false,
                                    click = function(element)
                                        modal:DestroySelf()
                                        resultPanel:DestroySelf()
                                    end,
                                },
                            },
                        }

                        element.root:AddChild(modal)

                        -- Disable the migrate button while running
                        migrateButton.interactable = false

                        lobby:MigrateGameToDurableObjects(m_game.gameid, {
                            progress = function(status, pct)
                                if statusLabel ~= nil and statusLabel.valid then
                                    statusLabel.text = string.format("%s (%d%%)", status, math.floor(pct * 100))
                                end
                            end,
                            complete = function(success, err)
                                if statusLabel ~= nil and statusLabel.valid then
                                    if success then
                                        statusLabel.text = "Migration complete!"
                                        statusLabel:SetClass("success", true)
                                    else
                                        statusLabel.text = string.format("Migration failed: %s", err or "unknown")
                                        statusLabel:SetClass("danger", true)
                                    end
                                end
                                local closeBtn = modal:Get("closeMigrationBtn")
                                if closeBtn ~= nil then
                                    closeBtn.interactable = true
                                end
                            end,
                        })
                    end,
                },

                gui.Button {
                    text = "Restore Old Version...",
                    halign = "left",
                    valign = "bottom",
                    fontSize = 16,
                    height = 32,
                    width = 180,
                    -- PITR rollback is only wired up for Durable-Object-backed
                    -- games (release + staging). Local games don't run the
                    -- rollback endpoints, and Firebase games don't have PITR.
                    hidden = m_game.storage ~= 1 and m_game.storage ~= 2,
                    press = function(element)
                        RunRestoreOldVersionDialog(element.root, m_game)
                    end,
                },

                gui.Button {
                    text = "Delete Game",
                    halign = "right",
                    valign = "bottom",
                    fontSize = 16,
                    height = 32,
                    width = 116,
                    press = function(element)
                        local modal
                        modal = gui.Panel {
                            classes = { "framedPanel" },
                            floating = true,
                            width = 600,
                            height = 600,
                            halign = "center",
                            valign = "center",
                            flow = "none",
                            styles = ThemeEngine.GetStyles(),

                            create = function(element)
                                ThemeEngine.OnThemeChanged(mod, function()
                                    if element.valid then
                                        element.styles = ThemeEngine.GetStyles()
                                    end
                                end)
                            end,

                            gui.Label {
                                classes = { "modalTitle" },
                                text = "Delete Game?",
                                vmargin = 8,
                            },

                            gui.Label {
                                classes = { "modalMessage" },
                                text = "Do you really want to delete this game?",
                            },

                            gui.Panel {
                                valign = "bottom",
                                halign = "center",
                                flow = "horizontal",
                                width = "80%",
                                height = "auto",
                                vmargin = 8,
                                gui.Button {
                                    width = "auto",
                                    height = "auto",
                                    fontSize = 18,
                                    vpad = 6,
                                    hpad = 8,
                                    text = "Delete",
                                    halign = "center",
                                    click = function(element)
                                        m_game:Delete()
                                        modal:DestroySelf()
                                        resultPanel:DestroySelf()
                                    end,
                                },
                                gui.Button {
                                    width = "auto",
                                    height = "auto",
                                    fontSize = 18,
                                    vpad = 6,
                                    hpad = 8,
                                    text = "Cancel",
                                    halign = "center",
                                    escapeActivates = true,
                                    click = function(element)
                                        modal:DestroySelf()
                                    end,
                                },
                            },
                        }

                        element.root:AddChild(modal)
                    end,
                }
            },

            gui.Button {
                classes = { "closeButton" },
                floating = true,
                halign = "right",
                valign = "top",
                press = function(element)
                    resultPanel:DestroySelf()
                end,
            }
        }
    }

    return resultPanel
end



-- Show a modal dialog that runs MigrateGameToDurableObjects for the given
-- game and reports progress. Called from both the game-details panel
-- "Migrate to Durable Objects" button and the dev/admin context menu on
-- the game card. `root` is the root panel to attach the modal to.
function RunMigrateToDOModal(root, game)
    local statusLabel
    local modal
    modal = gui.Panel {
        classes = { "framedPanel" },
        floating = true,
        width = 600,
        height = 240,
        halign = "center",
        valign = "center",
        bgimage = true,
        flow = "vertical",
        styles = { Styles.Default, Styles.Panel },

        gui.Label {
            text = "Migrating to Durable Objects",
            width = "auto", height = "auto",
            halign = "center", valign = "top",
            fontSize = 24, vmargin = 12,
        },

        gui.Label {
            id = "migrationStatus",
            text = "Starting...",
            width = "auto", height = "auto",
            halign = "center", valign = "center",
            fontSize = 16,
            create = function(element) statusLabel = element end,
        },

        gui.Panel {
            halign = "center", valign = "bottom", vmargin = 16,
            width = "auto", height = "auto",
            gui.Button {
                id = "closeMigrationBtn",
                text = "Close",
                fontSize = 16, width = 120, height = 32,
                halign = "center", interactable = false,
                click = function(element) modal:DestroySelf() end,
            },
        },
    }
    root:AddChild(modal)

    lobby:MigrateGameToDurableObjects(game.gameid, {
        progress = function(status, pct)
            if statusLabel ~= nil and statusLabel.valid then
                statusLabel.text = string.format("%s (%d%%)", status, math.floor(pct * 100))
            end
        end,
        complete = function(success, err)
            if statusLabel ~= nil and statusLabel.valid then
                if success then
                    statusLabel.text = "Migration complete!"
                    statusLabel.color = "#88ff88"
                else
                    statusLabel.text = string.format("Migration failed: %s", err or "unknown")
                    statusLabel.color = "#ff8888"
                end
            end
            local closeBtn = modal:Get("closeMigrationBtn")
            if closeBtn ~= nil then closeBtn.interactable = true end
        end,
    })
end

-- Show the "Restore Old Version..." dialog. Lets the user pick a point in
-- the past (preset duration or custom day/time) OR a previously-saved
-- named bookmark, then performs a Cloudflare PITR rollback via
-- lobby:PerformRollback. The two-call rollback/finalize round-trip is
-- handled inside the C# bridge; this dialog only drives the target
-- selection and surfaces progress.
--
-- Cloudflare's PITR window is 30 days, so durations longer than that are
-- rejected up front with a friendly error message.
function RunRestoreOldVersionDialog(root, game)
    local DURATION_OPTIONS = {
        { id = "5m",    text = "5 minutes ago",  seconds = 5 * 60 },
        { id = "10m",   text = "10 minutes ago", seconds = 10 * 60 },
        { id = "20m",   text = "20 minutes ago", seconds = 20 * 60 },
        { id = "30m",   text = "30 minutes ago", seconds = 30 * 60 },
        { id = "1h",    text = "1 hour ago",     seconds = 60 * 60 },
        { id = "2h",    text = "2 hours ago",    seconds = 2 * 60 * 60 },
        { id = "3h",    text = "3 hours ago",    seconds = 3 * 60 * 60 },
        { id = "4h",    text = "4 hours ago",    seconds = 4 * 60 * 60 },
        { id = "6h",    text = "6 hours ago",    seconds = 6 * 60 * 60 },
        { id = "8h",    text = "8 hours ago",    seconds = 8 * 60 * 60 },
        { id = "12h",   text = "12 hours ago",   seconds = 12 * 60 * 60 },
        { id = "18h",   text = "18 hours ago",   seconds = 18 * 60 * 60 },
        { id = "1d",    text = "1 day ago",      seconds = 86400 },
        { id = "2d",    text = "2 days ago",     seconds = 2 * 86400 },
        { id = "3d",    text = "3 days ago",     seconds = 3 * 86400 },
        { id = "4d",    text = "4 days ago",     seconds = 4 * 86400 },
        { id = "5d",    text = "5 days ago",     seconds = 5 * 86400 },
        { id = "6d",    text = "6 days ago",     seconds = 6 * 86400 },
        { id = "7d",    text = "7 days ago",     seconds = 7 * 86400 },
        { id = "2w",    text = "2 weeks ago",    seconds = 14 * 86400 },
        { id = "3w",    text = "3 weeks ago",    seconds = 21 * 86400 },
        { id = "4w",    text = "4 weeks ago",    seconds = 28 * 86400 },
        { id = "custom",text = "Custom time...", seconds = nil },
    }
    local MAX_AGE_SECONDS = 30 * 86400

    local m_selectedDurationId = "5m"
    local m_customDate = nil           -- table {year, month, day, hour, min} when "custom" picked
    local m_selectedBookmarkId = nil   -- numeric id from the bookmarks list (overrides duration)

    local configurePanel
    local progressPanel
    local progressLabel
    local statusLabel
    local closeButton
    local submitButton
    local customDateRow
    local bookmarksList
    local bookmarksSection
    local modal

    -- Build the date input row. Returns the row panel + a closure that
    -- reads the current values into a table {year, month, day, hour, min}
    -- or returns nil + error string if invalid.
    local function MakeCustomDateRow()
        local nowTbl = os.date("*t")
        local yearInput, monthInput, dayInput, hourInput, minInput

        local function makeNumberInput(initial, w)
            return gui.Input {
                text = tostring(initial),
                fontSize = 16,
                width = w,
                height = 28,
                halign = "left",
                vmargin = 0,
                hmargin = 4,
            }
        end

        yearInput  = makeNumberInput(nowTbl.year,  64)
        monthInput = makeNumberInput(nowTbl.month, 40)
        dayInput   = makeNumberInput(nowTbl.day,   40)
        hourInput  = makeNumberInput(nowTbl.hour,  40)
        minInput   = makeNumberInput(nowTbl.min,   40)

        local function readCustomDate()
            local y = tonumber(yearInput.text)
            local mo = tonumber(monthInput.text)
            local d = tonumber(dayInput.text)
            local h = tonumber(hourInput.text)
            local mi = tonumber(minInput.text)
            if y == nil or mo == nil or d == nil or h == nil or mi == nil then
                return nil, "Please enter numbers in every date/time field."
            end
            if mo < 1 or mo > 12 then return nil, "Month must be between 1 and 12." end
            if d < 1 or d > 31 then return nil, "Day must be between 1 and 31." end
            if h < 0 or h > 23 then return nil, "Hour must be between 0 and 23." end
            if mi < 0 or mi > 59 then return nil, "Minute must be between 0 and 59." end
            return { year = y, month = mo, day = d, hour = h, min = mi }
        end

        local panel = gui.Panel {
            width = "80%",
            height = "auto",
            halign = "center",
            flow = "horizontal",
            vmargin = 6,
            classes = { "hidden" },

            gui.Label { text = "Year",  width = "auto", height = "auto", fontSize = 14, valign = "center" },
            yearInput,
            gui.Label { text = "Mo",    width = "auto", height = "auto", fontSize = 14, valign = "center", hmargin = 4 },
            monthInput,
            gui.Label { text = "Day",   width = "auto", height = "auto", fontSize = 14, valign = "center", hmargin = 4 },
            dayInput,
            gui.Label { text = "Hour",  width = "auto", height = "auto", fontSize = 14, valign = "center", hmargin = 4 },
            hourInput,
            gui.Label { text = "Min",   width = "auto", height = "auto", fontSize = 14, valign = "center", hmargin = 4 },
            minInput,
        }
        return panel, readCustomDate
    end

    local readCustomDate
    customDateRow, readCustomDate = MakeCustomDateRow()

    -- Build the list of named bookmarks (filled in by an async call after
    -- the dialog opens). Each row is clickable and selects that bookmark
    -- as the rollback target; selecting a row clears the duration choice.
    bookmarksList = gui.Panel {
        -- {bordered} supplies bgimage = true + 1px @border frame; we override
        -- the corner radius for the rounded-pocket look. The translucent
        -- black bgcolor stays inline as a deliberate keep -- there's no
        -- theme token for "inset pocket overlay," it's an aesthetic shadow
        -- under the scroll region.
        classes = { "bordered" },
        width = "80%",
        height = 140,
        halign = "center",
        flow = "vertical",
        vscroll = true,
        bgcolor = "#00000040",
        cornerRadius = 4,

        gui.Label {
            classes = { "fgMuted" },
            id = "bookmarksLoading",
            text = "Loading saved bookmarks...",
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
            fontSize = 14,
        },
    }

    local function FormatBookmarkTimestamp(ms)
        if ms == nil then return "?" end
        local secs = math.floor(ms / 1000)
        return os.date("%Y-%m-%d %H:%M:%S", secs)
    end

    local function PopulateBookmarks(rows, err)
        if bookmarksList == nil or not bookmarksList.valid then return end
        -- A 404 from the bookmarks endpoint means the server has no bookmark
        -- store for this game -- not a real error, just "no bookmarks." Hide
        -- the whole bookmark section so the user only sees the duration picker.
        if err ~= nil and string.find(tostring(err), "HTTP 404", 1, true) ~= nil then
            if bookmarksSection ~= nil and bookmarksSection.valid then
                bookmarksSection:SetClass("hidden", true)
            end
            return
        end
        local newChildren = {}
        if err ~= nil then
            newChildren[#newChildren + 1] = gui.Label {
                classes = { "danger" },
                text = "Could not load bookmarks: " .. tostring(err),
                width = "auto",
                height = "auto",
                halign = "center",
                fontSize = 14,
            }
        elseif rows == nil or #rows == 0 then
            newChildren[#newChildren + 1] = gui.Label {
                classes = { "fgMuted" },
                text = "No saved bookmarks for this game.",
                width = "auto",
                height = "auto",
                halign = "center",
                fontSize = 14,
            }
        else
            for _, bm in ipairs(rows) do
                local bmId = bm.id
                local kind = bm.kind or "user"
                local label = string.format("%s  -  %s%s",
                    bm.name or "(unnamed)",
                    FormatBookmarkTimestamp(bm.createdAt),
                    kind == "auto-undo" and "  [auto-undo]" or "")
                local row
                row = gui.Panel {
                    -- {hoverable} brightens the row on hover (token-free,
                    -- theme-tracking). The selected-state fill stays as a
                    -- translucent accent overlay -- there is no theme token
                    -- for a "row highlight tint" so it is a deliberate keep.
                    classes = { "hoverable" },
                    width = "95%",
                    height = 24,
                    halign = "left",
                    flow = "horizontal",
                    hpad = 6,
                    borderBox = true,
                    bgimage = "panels/square.png",
                    bgcolor = "clear",
                    styles = {
                        { selectors = { "selected" }, bgcolor = "#5588cc60" },
                    },
                    click = function(element)
                        -- Clear duration selection, mark this row selected.
                        m_selectedBookmarkId = bmId
                        m_selectedDurationId = nil
                        if bookmarksList ~= nil and bookmarksList.valid then
                            for _, child in ipairs(bookmarksList.children) do
                                child:SetClass("selected", child == element)
                            end
                        end
                        if statusLabel ~= nil and statusLabel.valid then
                            statusLabel.text = "Bookmark selected. Press Submit to roll back."
                            statusLabel:SetClass("danger", false)
                            statusLabel:SetClass("info", true)
                        end
                    end,

                    gui.Label {
                        -- interactable=false so the click reaches the row
                        -- Panel above instead of being swallowed by the label.
                        -- Auto-undo bookmarks get the themed `info` accent so
                        -- they stand out from regular user bookmarks.
                        classes = { kind == "auto-undo" and "info" or nil },
                        interactable = false,
                        text = label,
                        width = "auto",
                        height = "auto",
                        fontSize = 14,
                        valign = "center",
                    },
                }
                newChildren[#newChildren + 1] = row
            end
        end
        bookmarksList.children = newChildren
    end

    -- Build the timestamp (in ms since epoch) that we'll roll back to,
    -- given the current dialog state. Returns (ms, nil) on success or
    -- (nil, errorString) on validation failure.
    local function ResolveTimestampMs()
        local opt = nil
        for _, o in ipairs(DURATION_OPTIONS) do
            if o.id == m_selectedDurationId then opt = o break end
        end
        if opt == nil then
            return nil, "Pick a rollback time."
        end
        local nowSecs = os.time()
        if opt.id == "custom" then
            local date, err = readCustomDate()
            if date == nil then return nil, err end
            local targetSecs = os.time(date)
            if targetSecs == nil then
                return nil, "Could not parse that date. Try different values."
            end
            if targetSecs >= nowSecs then
                return nil, "Custom time must be in the past."
            end
            if (nowSecs - targetSecs) > MAX_AGE_SECONDS then
                return nil, "Rollback can only go back up to 30 days."
            end
            return targetSecs * 1000, nil
        else
            local targetSecs = nowSecs - opt.seconds
            return targetSecs * 1000, nil
        end
    end

    -- Submit handler. Builds the rollback options table and kicks off
    -- lobby:PerformRollback. Hides the configure controls, shows the
    -- progress panel until completion.
    local function DoSubmit()
        local options
        if m_selectedBookmarkId ~= nil then
            options = {
                bookmarkId = m_selectedBookmarkId,
                note = "Rollback initiated from settings dialog",
            }
        else
            local ms, err = ResolveTimestampMs()
            if ms == nil then
                statusLabel.text = err or "Invalid selection"
                statusLabel:SetClass("info", false)
                statusLabel:SetClass("danger", true)
                return
            end
            options = {
                timestampMs = ms,
                note = "Rollback initiated from settings dialog",
            }
        end

        configurePanel:SetClass("hidden", true)
        progressPanel:SetClass("hidden", false)
        progressLabel.text = "Starting rollback..."
        progressLabel:SetClass("success", false)
        progressLabel:SetClass("danger", false)
        submitButton:SetClass("hidden", true)
        closeButton.interactable = false
        closeButton.text = "Close"

        options.progress = function(status, pct)
            if progressLabel ~= nil and progressLabel.valid then
                progressLabel.text = string.format("%s (%d%%)", status, math.floor((pct or 0) * 100))
            end
        end
        options.complete = function(success, detail)
            if progressLabel ~= nil and progressLabel.valid then
                if success then
                    progressLabel.text = "Rollback complete!"
                    progressLabel:SetClass("danger", false)
                    progressLabel:SetClass("success", true)
                else
                    progressLabel.text = "Rollback failed: " .. tostring(detail or "unknown error")
                    progressLabel:SetClass("success", false)
                    progressLabel:SetClass("danger", true)
                end
            end
            if closeButton ~= nil and closeButton.valid then
                closeButton.interactable = true
            end
        end

        lobby:PerformRollback(game.gameid, options)
    end

    local explanation = gui.Label {
        text = "This restores the game to an earlier point in time using Cloudflare's " ..
               "point-in-time recovery. Choose how far back to go (up to 30 days) or " ..
               "pick a saved bookmark. Any changes made since that point will be lost. " ..
               "An 'undo' bookmark of the current state will be saved automatically so " ..
               "you can recover from a mistaken rollback.",
        width = "80%",
        height = "auto",
        halign = "center",
        textAlignment = "left",
        fontSize = 14,
        vmargin = 8,
    }

    local durationDropdown = gui.Dropdown {
        width = "80%",
        height = 32,
        halign = "center",
        fontSize = 16,
        options = DURATION_OPTIONS,
        idChosen = m_selectedDurationId,
        change = function(element)
            m_selectedDurationId = element.idChosen
            m_selectedBookmarkId = nil
            customDateRow:SetClass("hidden", element.idChosen ~= "custom")
            if bookmarksList ~= nil and bookmarksList.valid then
                for _, child in ipairs(bookmarksList.children) do
                    child:SetClass("selected", false)
                end
            end
        end,
    }

    statusLabel = gui.Label {
        text = "",
        width = "80%",
        height = "auto",
        halign = "center",
        fontSize = 14,
        vmargin = 4,
    }

    configurePanel = gui.Panel {
        width = "100%",
        height = "auto",
        halign = "center",
        flow = "vertical",
        vmargin = 4,

        explanation,

        gui.Label {
            text = "Roll back to:",
            width = "80%", height = "auto", halign = "center",
            fontSize = 16, textAlignment = "left", tmargin = 4,
        },
        durationDropdown,
        customDateRow,

        -- Header + list grouped so they can be hidden together if the server
        -- has no bookmark store for this game (404 on /admin/bookmarks/...).
        gui.Panel {
            width = "100%",
            height = "auto",
            halign = "center",
            flow = "vertical",
            create = function(element) bookmarksSection = element end,

            gui.Label {
                text = "Or restore to a saved bookmark (click a row, then press Submit):",
                width = "80%", height = "auto", halign = "center",
                fontSize = 16, textAlignment = "left", tmargin = 12,
            },
            bookmarksList,
        },

        statusLabel,
    }

    progressLabel = gui.Label {
        text = "",
        width = "80%",
        height = "auto",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        fontSize = 18,
    }

    progressPanel = gui.Panel {
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "center",
        flow = "vertical",
        classes = { "hidden" },

        progressLabel,
    }

    submitButton = gui.Button {
        text = "Submit",
        halign = "center",
        height = 40,
        width = 140,
        fontSize = 20,
        bold = true,
        hmargin = 8,
        click = function(element)
            DoSubmit()
        end,
    }

    closeButton = gui.Button {
        text = "Cancel",
        halign = "center",
        height = 40,
        width = 140,
        fontSize = 18,
        hmargin = 8,
        escapeActivates = true,
        click = function(element)
            modal:DestroySelf()
        end,
    }

    -- Dialog-internal extras: the date-number inputs need auto width and
    -- 16pt sizing; the {input} theme rule provides border/font/color via
    -- @tokens, so we only override geometry here.
    local m_dialogStylesExtras = {
        {
            selectors = { "input" },
            width = "auto",
            fontSize = 16,
        },
    }

    modal = gui.Panel {
        floating = true,
        width = "100%",
        height = "100%",
        bgcolor = "clear",
        bgimage = true,
        styles = ThemeEngine.MergeStyles(m_dialogStylesExtras),

        -- Live re-theming: MergeStyles is a one-shot snapshot; subscribe so
        -- the dialog recolors when the active theme/scheme changes. Guard
        -- with .valid so the callback no-ops after the dialog closes.
        create = function(element)
            ThemeEngine.OnThemeChanged(mod, function()
                if element.valid then
                    element.styles = ThemeEngine.MergeStyles(m_dialogStylesExtras)
                end
            end)
        end,

        gui.Panel {
            classes = { "framedPanel" },
            width = 800,
            height = 900,
            halign = "center",
            valign = "center",
            flow = "vertical",

            gui.Label {
                classes = { "dialogTitle" },
                text = "Restore Old Version",
                halign = "center",
                valign = "top",
                width = "auto",
                height = "auto",
                fontSize = 32,
                textAlignment = "center",
            },

            gui.Divider {
                tmargin = 4,
                bmargin = 8,
            },

            configurePanel,
            progressPanel,

            gui.Panel {
                width = "80%",
                height = "auto",
                halign = "center",
                valign = "bottom",
                flow = "horizontal",
                vmargin = 16,
                submitButton,
                closeButton,
            },

            gui.Button {
                classes = { "closeButton" },
                floating = true,
                halign = "right",
                valign = "top",
                press = function(element)
                    modal:DestroySelf()
                end,
            },
        },
    }

    root:AddChild(modal)

    -- Fire off the bookmark list query. Callback resolves asynchronously.
    lobby:ListRollbackBookmarks(game.gameid, function(rows, err)
        PopulateBookmarks(rows, err)
    end)
end

-- Show a modal dialog that runs MigrateGameToStagingDurableObjects for the
-- given game and reports progress. Used by the dev/admin context menu on
-- the game card. Unlike RunCloneToStagingModal, this migrates the existing
-- game (same gameid) to staging rather than creating a new copy.
function RunMigrateToStagingModal(root, game)
    local statusLabel
    local modal
    modal = gui.Panel {
        classes = { "framedPanel" },
        floating = true,
        width = 600,
        height = 240,
        halign = "center",
        valign = "center",
        bgimage = true,
        flow = "vertical",
        styles = { Styles.Default, Styles.Panel },

        gui.Label {
            text = "Migrating to Staging DO",
            width = "auto", height = "auto",
            halign = "center", valign = "top",
            fontSize = 24, vmargin = 12,
        },

        gui.Label {
            id = "migrationStatus",
            text = "Starting...",
            width = "auto", height = "auto",
            halign = "center", valign = "center",
            fontSize = 16,
            create = function(element) statusLabel = element end,
        },

        gui.Panel {
            halign = "center", valign = "bottom", vmargin = 16,
            width = "auto", height = "auto",
            gui.Button {
                id = "closeMigrationBtn",
                text = "Close",
                fontSize = 16, width = 120, height = 32,
                halign = "center", interactable = false,
                click = function(element) modal:DestroySelf() end,
            },
        },
    }
    root:AddChild(modal)

    lobby:MigrateGameToStagingDurableObjects(game.gameid, {
        progress = function(status, pct)
            if statusLabel ~= nil and statusLabel.valid then
                statusLabel.text = string.format("%s (%d%%)", status, math.floor(pct * 100))
            end
        end,
        complete = function(success, err)
            if statusLabel ~= nil and statusLabel.valid then
                if success then
                    statusLabel.text = "Migration to staging complete!"
                    statusLabel.color = "#88ff88"
                else
                    statusLabel.text = string.format("Migration failed: %s", err or "unknown")
                    statusLabel.color = "#ff8888"
                end
            end
            local closeBtn = modal:Get("closeMigrationBtn")
            if closeBtn ~= nil then closeBtn.interactable = true end
        end,
    })
end

-- Show a modal dialog that runs CloneGameToLocal for the given game,
-- producing a new offline (Local) game. Source may be Firebase, DO, or
-- DO Staging. Used by the dev/admin context menu.
function RunCloneToLocalModal(root, game)
    local statusLabel
    local modal
    modal = gui.Panel {
        classes = { "framedPanel" },
        floating = true,
        width = 600,
        height = 240,
        halign = "center",
        valign = "center",
        bgimage = true,
        flow = "vertical",
        styles = { Styles.Default, Styles.Panel },

        gui.Label {
            text = "Cloning to Offline Game",
            width = "auto", height = "auto",
            halign = "center", valign = "top",
            fontSize = 24, vmargin = 12,
        },

        gui.Label {
            id = "cloneStatus",
            text = "Starting...",
            width = "auto", height = "auto",
            halign = "center", valign = "center",
            fontSize = 16,
            create = function(element) statusLabel = element end,
        },

        gui.Panel {
            halign = "center", valign = "bottom", vmargin = 16,
            width = "auto", height = "auto",
            gui.Button {
                id = "closeCloneBtn",
                text = "Close",
                fontSize = 16, width = 120, height = 32,
                halign = "center", interactable = false,
                click = function(element) modal:DestroySelf() end,
            },
        },
    }
    root:AddChild(modal)

    lobby:CloneGameToLocal(game.gameid, {
        progress = function(status, pct)
            if statusLabel ~= nil and statusLabel.valid then
                statusLabel.text = string.format("%s (%d%%)", status, math.floor(pct * 100))
            end
        end,
        complete = function(success, newGameid, err)
            if statusLabel ~= nil and statusLabel.valid then
                if success then
                    statusLabel.text = string.format("Clone complete! New game: %s", newGameid or "?")
                    statusLabel.color = "#88ff88"
                else
                    statusLabel.text = string.format("Clone failed: %s", err or "unknown")
                    statusLabel.color = "#ff8888"
                end
            end
            local closeBtn = modal:Get("closeCloneBtn")
            if closeBtn ~= nil then closeBtn.interactable = true end
        end,
    })
end

-- Show a modal dialog that runs CloneDOGameToOtherEnvironment for the given
-- DO-backed game. The clone goes to the OTHER DO environment (release ->
-- staging, or staging -> release). Used by the dev/admin context menu.
function RunCloneDOToOtherEnvModal(root, game)
    -- storage: 1 = DurableObjects, 2 = DurableObjectsStaging
    local targetLabel
    if game.storage == 1 then
        targetLabel = "Staging DO"
    elseif game.storage == 2 then
        targetLabel = "Durable Objects"
    else
        targetLabel = "other DO env"
    end

    local statusLabel
    local modal
    modal = gui.Panel {
        classes = { "framedPanel" },
        floating = true,
        width = 600,
        height = 240,
        halign = "center",
        valign = "center",
        bgimage = true,
        flow = "vertical",
        styles = { Styles.Default, Styles.Panel },

        gui.Label {
            text = "Cloning to " .. targetLabel,
            width = "auto", height = "auto",
            halign = "center", valign = "top",
            fontSize = 24, vmargin = 12,
        },

        gui.Label {
            id = "cloneStatus",
            text = "Starting...",
            width = "auto", height = "auto",
            halign = "center", valign = "center",
            fontSize = 16,
            create = function(element) statusLabel = element end,
        },

        gui.Panel {
            halign = "center", valign = "bottom", vmargin = 16,
            width = "auto", height = "auto",
            gui.Button {
                id = "closeCloneBtn",
                text = "Close",
                fontSize = 16, width = 120, height = 32,
                halign = "center", interactable = false,
                click = function(element) modal:DestroySelf() end,
            },
        },
    }
    root:AddChild(modal)

    lobby:CloneDOGameToOtherEnvironment(game.gameid, {
        progress = function(status, pct)
            if statusLabel ~= nil and statusLabel.valid then
                statusLabel.text = string.format("%s (%d%%)", status, math.floor(pct * 100))
            end
        end,
        complete = function(success, newGameid, err)
            if statusLabel ~= nil and statusLabel.valid then
                if success then
                    statusLabel.text = string.format("Clone complete! New game: %s", newGameid or "?")
                    statusLabel.color = "#88ff88"
                else
                    statusLabel.text = string.format("Clone failed: %s", err or "unknown")
                    statusLabel.color = "#ff8888"
                end
            end
            local closeBtn = modal:Get("closeCloneBtn")
            if closeBtn ~= nil then closeBtn.interactable = true end
        end,
    })
end

-- Show a modal dialog that runs CloneFirebaseGameToStagingDO for the given
-- game and reports progress. Used by both the game-details panel button
-- and the dev/admin context menu on the game card.
function RunCloneToStagingModal(root, game)
    local statusLabel
    local modal
    modal = gui.Panel {
        classes = { "framedPanel" },
        floating = true,
        width = 600,
        height = 240,
        halign = "center",
        valign = "center",
        bgimage = true,
        flow = "vertical",
        styles = { Styles.Default, Styles.Panel },

        gui.Label {
            text = "Cloning to Staging DO",
            width = "auto", height = "auto",
            halign = "center", valign = "top",
            fontSize = 24, vmargin = 12,
        },

        gui.Label {
            id = "cloneStatus",
            text = "Starting...",
            width = "auto", height = "auto",
            halign = "center", valign = "center",
            fontSize = 16,
            create = function(element) statusLabel = element end,
        },

        gui.Panel {
            halign = "center", valign = "bottom", vmargin = 16,
            width = "auto", height = "auto",
            gui.Button {
                id = "closeCloneBtn",
                text = "Close",
                fontSize = 16, width = 120, height = 32,
                halign = "center", interactable = false,
                click = function(element) modal:DestroySelf() end,
            },
        },
    }
    root:AddChild(modal)

    lobby:CloneFirebaseGameToStagingDO(game.gameid, {
        progress = function(status, pct)
            if statusLabel ~= nil and statusLabel.valid then
                statusLabel.text = string.format("%s (%d%%)", status, math.floor(pct * 100))
            end
        end,
        complete = function(success, newGameid, err)
            if statusLabel ~= nil and statusLabel.valid then
                if success then
                    statusLabel.text = string.format("Clone complete! New game: %s", newGameid or "?")
                    statusLabel.color = "#88ff88"
                else
                    statusLabel.text = string.format("Clone failed: %s", err or "unknown")
                    statusLabel.color = "#ff8888"
                end
            end
            local closeBtn = modal:Get("closeCloneBtn")
            if closeBtn ~= nil then closeBtn.interactable = true end
        end,
    })
end


local function MakeGamePanel(gameIndex)
    local m_game = nil

    local addGameButton = gui.Panel {
        classes = { "hidden" },
        bgimage = true,
        bgcolor = "black",
        opacity = 0.9,
        width = "100%",
        height = "100%",

        press = function(element)
            element.root:FireEventTree("titlescreenCreateGame")
            audio.FireSoundEvent("Mouse.Click")
        end,

        hover = function ()
            audio.FireSoundEvent("Mouse.Hover")
        end,

        gui.Panel {
            bgimage = "ui-icons/Plus.png",
            bgcolor = "white",
            width = 96,
            height = 96,
            halign = "center",
            valign = "center",
            styles = {
                {
                    brightness = 0.8,
                },
                {
                    selectors = { "parent:hover" },
                    scale = 1.1,
                    brightness = 1,
                    transitionTime = 0.1,
                }
            }

        }
    }

    --make game king panel
    local gamePanel = gui.Panel {

        bgimage = true,
        bgcolor = "black",
        opacity = 0.9,
        width = "100%",
        height = "100%",


        flow = "horizontal",

        hover = function(element)
            element:SetClassTree("hovergame", true)
        end,

        dehover = function(element)
            element:SetClassTree("hovergame", false)
        end,

        -- Dev/admin context menu. Gives access to Clone-to-Staging and
        -- Migrate-to-DO from any game card, including games where the
        -- user is just a player (the regular buttons are only exposed
        -- from the game-details panel that only game owners can open).
        rightClick = function(element)
            if m_game == nil then return end
            if not (dmhub.GetSettingValue("dev") or dmhub.isAdminAccount) then return end

            local entries = {}

            if m_game.storage == 0 then
                -- Firebase-backed: offer clone and migrate
                table.insert(entries, {
                    text = "Clone to Staging DO",
                    click = function()
                        RunCloneToStagingModal(element.root, m_game)
                    end,
                })
                table.insert(entries, {
                    text = "Migrate to Staging DO",
                    click = function()
                        RunMigrateToStagingModal(element.root, m_game)
                    end,
                })
                table.insert(entries, {
                    text = "Migrate to Durable Objects",
                    click = function()
                        RunMigrateToDOModal(element.root, m_game)
                    end,
                })
            elseif m_game.storage == 1 then
                -- Release DO: offer cloning a copy to Staging DO
                table.insert(entries, {
                    text = "Clone to Staging DO",
                    click = function()
                        RunCloneDOToOtherEnvModal(element.root, m_game)
                    end,
                })
            elseif m_game.storage == 2 then
                -- Staging DO: offer cloning a copy to release Durable Objects
                table.insert(entries, {
                    text = "Clone to Durable Objects",
                    click = function()
                        RunCloneDOToOtherEnvModal(element.root, m_game)
                    end,
                })
            end

            -- Clone to an offline (Local) game is available from any online
            -- backend: Firebase, DO, or DO Staging.
            if m_game.storage == 0 or m_game.storage == 1 or m_game.storage == 2 then
                table.insert(entries, {
                    text = "Clone to Offline Game",
                    click = function()
                        RunCloneToLocalModal(element.root, m_game)
                    end,
                })
            end

            if #entries == 0 then return end

            element.popup = gui.ContextMenu {
                width = 260,
                entries = entries,
                click = function() element.popup = nil end,
            }
        end,

        refreshGames = function(element, orderedGames, baseIndex)
            local index = baseIndex + gameIndex
            m_game = orderedGames[index]
            if m_game == nil then
                element:SetClass("hidden", true)
                addGameButton:SetClass("hidden", #lobby.games >= MaxGamesAllowed())
                element:HaltEventPropagation()
                return
            end

            addGameButton:SetClass("hidden", true)
            element:SetClass("hidden", false)
        end,

        --game image panel
        gui.Panel {

            bgcolor = "white",
            width = "177.778% height",
            height = "100%",


            refreshGames = function(element)
                element.bgimage = m_game.coverart
            end,

            gui.Panel {
                -- playCampaignButton class supplies the @fg bgcolor tint
                -- via the Campaigns column's MergeStyles extras (multiplies
                -- the button.png texture with the active scheme's @fg).
                -- Hover/press brightness multipliers stay local to this
                -- panel.
                classes = { "playCampaignButton" },
                styles = {
                    {
                        selectors = { "~hovergame" },
                        opacity = 0,
                        transitionTime = 0.1,
                    },
                    {
                        selectors = { "hover", "~label" },
                        brightness = 1.4,
                        scale = 1.04,
                    },
                    {
                        selectors = { "press" },
                        brightness = 0.7,
                    },
                },

                bgimage = "panels/titlescreen/button.png",

                height = 131 * 0.4,
                width = 632 * 0.4,

                halign = "center",
                valign = "bottom",

                bmargin = 3,

                -- Hide Play for a local game whose data lives on another
                -- computer. Entering it would have the local server create a
                -- fresh empty game.db and serve an empty game.
                refreshGames = function(element)
                    element:SetClass("collapsed", m_game ~= nil and m_game.storage == 3 and not m_game.hasLocalData)
                end,

                hover = function ()

                    audio.FireSoundEvent("Mouse.Hover")

                end,

                press = function(element)
                    if m_game.storage == 3 and not m_game.hasLocalData then
                        return
                    end
                    element.root:FireEventTree("overrideLoadingScreenArt", m_game.coverart, m_game.gameid)
                    lobby:EnterGame(m_game.gameid)
                    audio.FireSoundEvent("Mouse.Click")
                end,

                gui.Label {
                    -- playCampaignLabel class supplies @fgInverse text
                    -- color via the Campaigns column's MergeStyles extras
                    -- (contrasts against the @fg-tinted button below).
                    classes = { "playCampaignLabel" },
                    text = "PLAY CAMPAIGN",
                    fontSize = 18,
                    fontFace = "newzald",
                    halign = "center",
                    valign = "center",
                    width = "auto",
                    height = "auto",
                    textAlignment = "center",
                    y = 2,
                }
            }
        },

        --game info king panel
        gui.Panel {

            halign = "right",
            width = "62%",
            height = "100%",

            gui.Panel {

                width = "100%",
                height = "100%",

                flow = "vertical",


                gui.Panel {

                    width = "100%",
                    height = "20%",

                    flow = "horizontal",
                    tmargin = 0,

                    gui.Label {

                        refreshGames = function(element)
                            element.text = string.upper(m_game.description)
                        end,

                        text = "The Delian Tomb",
                        fontSize = 30,
                        minFontSize = 12,
                        fontFace = "newzald",
                        bold = true,

                        halign = "left",
                        hpad = 5,
                        valign = "center",
                        textAlignment = "left",

                        width = "100%-100",
                        height = "100%",

                        flow = "horizontal",
                    },

                    --time the game has taken.
                    gui.Panel {
                        width = "auto",
                        height = "100%",
                        halign = "right",
                        flow = "horizontal",
                        hpad = 5,
                        gui.Label {
                            refreshGames = function(element)
                                local t = m_game.timePlayed
                                if t < 60 then
                                    element.text = "00:00"
                                    return
                                end

                                local minutes = math.floor(t / 60)
                                local hours = math.floor(minutes / 60)
                                minutes = minutes - hours * 60

                                element.text = string.format("%02d:%02d", hours, minutes)
                            end,
                            hmargin = 4,
                            fontSize = 25,
                            bold = true,
                            fontFace = "newzald",
                            halign = "center",
                            valign = "center",
                            textAlignment = "center",
                            width = "auto",
                            height = "auto",
                        },
                    }
                },

                gui.Label {
                    classes = { "fgMuted" },
                    refreshGames = function(element)
                        element:SetClass("collapsed", m_game.owner == dmhub.loginUserid)
                        element.text = string.format(tr("<i>directed by</i> <b>%s</b>"), m_game.ownerDisplayName)
                    end,
                    fontSize = 14,
                    tmargin = -8,
                    halign = "left",
                    valign = "top",
                    width = "auto",
                    height = "auto",
                    bold = false,
                    hpad = 5,
                    vpad = 2,
                },

                gui.Label {
                    classes = { "info" },
                    hidden = not dmhub.GetSettingValue("dev"),
                    refreshGames = function(element)
                        local storage = m_game.storage
                        local backend
                        if storage == 1 then
                            backend = "Durable Objects"
                        elseif storage == 2 then
                            backend = "Durable Objects (Staging)"
                        elseif storage == 3 then
                            backend = "Offline"
                        else
                            backend = "Firebase"
                        end
                        element.text = string.format("Backend: %s", backend)
                    end,
                    fontSize = 12,
                    halign = "left",
                    valign = "top",
                    width = "auto",
                    height = "auto",
                    hpad = 5,
                    tmargin = -4,
                },

                gui.Label {
                    refreshGames = function(element)
                        element.text = m_game.descriptionDetails
                    end,

                    text = "The Delian Tomb",
                    fontSize = 16,
                    fontFace = "newzald",

                    halign = "left",
                    hpad = 5,
                    valign = "top",
                    textAlignment = "topleft",

                    width = "100%",
                    height = "30%",

                    flow = "horizontal",
                },

                gui.Label {
                    -- gameIdPill class supplies @fg text color, @border
                    -- frame, and @surfaceLinear gradient via the Campaigns
                    -- column's MergeStyles extras. The rule re-resolves on
                    -- theme/scheme change via the column's OnThemeChanged.
                    classes = { "gameIdPill" },
                    textAlignment = "center",
                    fontSize = 14,
                    bold = true,
                    width = 360,
                    height = 36,
                    bgimage = true,
                    bgcolor = "white",                 -- image-tint-neutral so the gradient paints
                    borderWidth = 1,
                    beveledcorners = true,
                    cornerRadius = 10,
                    multimonitor = { "streamermode" },
                    valign = "bottom",
                    vmargin = 4,
                    hmargin = 4,
                    monitor = function(element)
                        element:FireEvent("refreshGames")
                    end,
                    refreshGames = function(element)
                        if m_game ~= nil then
                            -- Hide the gameid copy label for local games; the
                            -- id is a local-only GUID that nobody can join.
                            -- The "Invite Players" button shows in its place.
                            element:SetClass("hidden", m_game.storage == 3)

                            local gameid = m_game.gameid
                            if g_streamerModeSetting:Get() then
                                -- Mask the gameid with asterisks tinted to
                                -- @fg so the obscured text adapts to scheme.
                                -- ResolveTokens substitutes the literal hex
                                -- of the active @fg into the markup string.
                                gameid = ThemeEngine.ResolveTokens(string.format(
                                    "<alpha=#FF><mark=@fg><color=@fg>%s</alpha></mark></color>",
                                    string.rep("*", #m_game.gameid)))
                            end
                            element.text = gameid
                        end
                    end,

                    click = function(element)
                        local tooltip = gui.Tooltip { text = "Copied to Clipboard", valign = "top", borderWidth = 0 } (
                            element)
                        dmhub.CopyToClipboard(m_game.gameid)
                    end,

                    gui.Panel {
                        -- gameIdPillIcon class supplies @fg tint via the
                        -- Campaigns column's MergeStyles extras.
                        classes = { "gameIdPillIcon" },
                        halign = "left",
                        valign = "center",
                        height = "50%",
                        width = "100% height",
                        hmargin = 12,
                        bgimage = "icons/icon_app/icon_app_108.png",
                    },
                },

                -- "Invite Players" button that replaces the gameid-copy label
                -- for local games. Clicking it starts the promote-to-DO flow.
                -- Only shown when this machine actually has the game's data --
                -- a local game created on another computer (listed here from
                -- Firebase metadata but with no local data) can't be promoted
                -- from here; the message below is shown in its place.
                gui.Button {
                    text = "Invite Players",
                    width = 360,
                    height = 36,
                    fontSize = 18,
                    valign = "bottom",
                    y = -16,
                    hmargin = 4,
                    refreshGames = function(element)
                        element:SetClass("collapsed", m_game == nil or m_game.storage ~= 3 or not m_game.hasLocalData)
                    end,
                    click = function(element)
                        ShowPromoteLocalGameDialog(m_game, element.root)
                    end,
                },

                -- Shown in place of the Invite Players button for a local game
                -- whose data lives on a different computer. The local-only
                -- gameid is useless to anyone else, so instead of offering a
                -- non-functional Play/Invite we explain how to make the game
                -- reachable from here.
                gui.Label {
                    classes = { "fgMuted" },
                    text = "This game was created on a different computer. Press Invite Players from that computer to deploy it online so you can access it anywhere.",
                    fontSize = 14,
                    width = 460,
                    height = "auto",
                    textAlignment = "center",
                    halign = "center",
                    valign = "bottom",
                    y = -8,
                    hmargin = 4,
                    refreshGames = function(element)
                        element:SetClass("collapsed", m_game == nil or m_game.storage ~= 3 or m_game.hasLocalData)
                    end,
                },


            },


        },

        gui.Button {
            classes = { "settingsButton" },
            styles = {
                {
                    selectors = { "~hovergame" },
                    opacity = 0,
                    hidden = 1,
                    transitionTime = 0.1,
                },
                {
                    selectors = { "~titlescreenDirector" },
                    hidden = 1,
                },
            },

            halign = "right",
            valign = "bottom",
            width = 24,
            height = 24,
            hmargin = 4,
            vmargin = 4,
            floating = true,
            press = function(element)
                local panel = CreateGameEditor {
                    game = m_game,
                    mode = "edit",
                }

                element.root:AddChild(panel)
            end,
        },

        gui.Button {
            classes = { "deleteButton" },
            styles = {
                {
                    selectors = { "~titlescreenPlayer" },
                    hidden = 1,
                },
                {
                    selectors = { "~hovergame" },
                    hidden = 1,
                },
            },

            halign = "right",
            valign = "bottom",
            width = 16,
            height = 16,
            hmargin = 4,
            vmargin = 4,
            floating = true,
            press = function(element)
                local modal
                modal = gui.Panel {
                    classes = { "framedPanel" },
                    floating = true,
                    width = 600,
                    height = 600,
                    halign = "center",
                    valign = "center",
                    flow = "none",
                    styles = ThemeEngine.GetStyles(),

                    create = function(element)
                        ThemeEngine.OnThemeChanged(mod, function()
                            if element.valid then
                                element.styles = ThemeEngine.GetStyles()
                            end
                        end)
                    end,

                    gui.Label {
                        classes = { "modalTitle" },
                        text = "Leave Game?",
                        vmargin = 8,
                    },

                    gui.Label {
                        classes = { "modalMessage" },
                        text = "Do you really want to leave this game?",
                    },

                    gui.Panel {
                        valign = "bottom",
                        halign = "center",
                        flow = "horizontal",
                        width = "80%",
                        height = "auto",
                        vmargin = 8,
                        gui.Button {
                            width = "auto",
                            height = "auto",
                            fontSize = 18,
                            vpad = 6,
                            hpad = 8,
                            text = "Leave Game",
                            halign = "center",
                            click = function(element)
                                m_game:Leave()
                                element.root:FireEventTree("refreshLobby")
                                modal:DestroySelf()
                            end,
                        },

                        gui.Button {
                            width = "auto",
                            height = "auto",
                            fontSize = 18,
                            vpad = 6,
                            hpad = 8,
                            text = "Cancel",
                            halign = "center",
                            escapeActivates = true,
                            click = function(element)
                                modal:DestroySelf()
                            end,
                        },
                    },
                }

                element.root:AddChild(modal)
            end,
        },



    }

    local resultPanel = gui.Panel {
        width = "100%",
        height = 176,
        bmargin = 10,
        gamePanel,
        addGameButton,
    }

    return resultPanel
end

--- Shows the "Deploy Game Online" confirmation dialog and, on confirm,
--- kicks off the local-to-DO promotion flow. Uses the framed-panel modal
--- pattern from the titlescreen (same as the "Leave Game?" dialog), because
--- gui.ShowModal() doesn't show up in the titlescreen's own modal stack.
---
--- The modal morphs in place between two phases -- confirm (title + body +
--- Deploy/Cancel) and progress (title + status + progress bar + Close) --
--- rather than destroying itself and spawning a separate loading screen,
--- which would flicker and briefly leave nothing on screen.
function ShowPromoteLocalGameDialog(game, root)
    if game == nil or game.storage ~= 3 then
        return
    end

    local gameid = game.gameid

    local modal
    local confirmPhase
    local progressPhase
    local statusLabel
    local progressBar
    local closeButton

    local function startDeploy()
        confirmPhase:SetClass("hidden", true)
        progressPhase:SetClass("hidden", false)

        lobby:PromoteLocalGame {
            gameid = gameid,
            progress = function(status, pct)
                if modal == nil or not modal.valid then return end
                if statusLabel ~= nil and statusLabel.valid then
                    statusLabel.text = status
                end
                if progressBar ~= nil and progressBar.valid then
                    progressBar:SetValue(pct or 0)
                end
            end,
            complete = function(success, newGameid, err)
                if modal == nil or not modal.valid then return end
                if success then
                    if statusLabel ~= nil and statusLabel.valid then
                        statusLabel.text = "Done! Opening new game..."
                    end
                    if progressBar ~= nil and progressBar.valid then
                        progressBar:SetValue(1)
                    end
                    dmhub.Schedule(0.5, function()
                        if modal == nil or not modal.valid then return end
                        local parent = modal.root
                        local games = lobby.games or {}
                        for _, g in ipairs(games) do
                            if g.gameid == newGameid then
                                parent:AddChild(CreateGameEditor { game = g })
                                break
                            end
                        end
                        modal:DestroySelf()
                    end)
                else
                    if statusLabel ~= nil and statusLabel.valid then
                        statusLabel.text = "Deployment failed: " .. (err or "unknown error")
                        statusLabel.selfStyle.color = "red"
                    end
                    if progressBar ~= nil and progressBar.valid then
                        progressBar:SetClass("hidden", true)
                    end
                    if closeButton ~= nil and closeButton.valid then
                        closeButton:SetClass("hidden", false)
                    end
                end
            end,
        }
    end

    confirmPhase = gui.Panel {
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        flow = "vertical",

        gui.Label {
            text = "Deploy Game Online?",
            width = "auto",
            height = "auto",
            halign = "center",
            fontSize = 28,
            valign = "top",
            vmargin = 16,
        },

        gui.Label {
            text = "Inviting players will deploy this game online to Durable Objects. " ..
                "The game will get a new game ID, and all its data will be copied to the cloud. " ..
                "The local copy will be deleted once the online copy is verified.",
            width = "80%",
            height = "auto",
            halign = "center",
            valign = "center",
            textAlignment = "center",
            textWrap = true,
            fontSize = 16,
        },

        gui.Panel {
            valign = "bottom",
            halign = "center",
            flow = "horizontal",
            width = "80%",
            height = "auto",
            vmargin = 16,
            gui.Button {
                width = "auto",
                height = "auto",
                fontSize = 18,
                vpad = 6,
                hpad = 12,
                text = "Deploy Online",
                halign = "center",
                hmargin = 12,
                click = function(element) startDeploy() end,
            },

            gui.Button {
                width = "auto",
                height = "auto",
                fontSize = 18,
                vpad = 6,
                hpad = 12,
                text = "Cancel",
                halign = "center",
                hmargin = 12,
                escapeActivates = true,
                click = function(element)
                    modal:DestroySelf()
                end,
            },
        },
    }

    progressPhase = gui.Panel {
        classes = { "hidden" },
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        flow = "vertical",

        gui.Label {
            text = "Deploying Game Online",
            textAlignment = "center",
            fontSize = 24,
            bold = true,
            width = "auto",
            height = "auto",
            halign = "center",
            vmargin = 16,
        },

        gui.Label {
            text = "Preparing...",
            textAlignment = "center",
            fontSize = 12,
            width = "80%",
            height = 40,
            halign = "center",
            valign = "center",
            create = function(element) statusLabel = element end,
        },

        gui.ProgressBar {
            width = 480,
            height = 24,
            value = 0,
            halign = "center",
            vmargin = 8,
            create = function(element) progressBar = element end,
        },

        gui.Button {
            classes = { "hidden" },
            width = "auto",
            height = "auto",
            fontSize = 18,
            vpad = 6,
            hpad = 12,
            text = "Close",
            halign = "center",
            valign = "bottom",
            vmargin = 12,
            create = function(element) closeButton = element end,
            click = function(element)
                modal:DestroySelf()
            end,
        },
    }

    modal = gui.Panel {
        classes = { "framedPanel" },
        floating = true,
        width = 640,
        height = 360,
        halign = "center",
        valign = "center",
        bgimage = true,
        flow = "none",
        styles = {
            Styles.Default,
            Styles.Panel,
        },

        confirmPhase,
        progressPhase,
    }

    root:AddChild(modal)
end

function CreateGameLoadingScreen(moduleInfo, backend)
    local resultPanel

    resultPanel = gui.Panel {
        width = "100%",
        height = "100%",
        bgimage = true,
        bgcolor = "clear",
        floating = true,
        gui.Panel {
            styles = {
                Styles.Default,
                Styles.Panel,
            },

            classes = { "framedPanel" },
            bgimage = true,
            width = 800,
            height = 900,
            halign = "center",
            valign = "center",
            flow = "vertical",

            gui.Label {
                halign = "center",
                valign = "center",
                width = 160,
                height = "auto",
                fontSize = 18,
                text = "Creating Game",
                data = {
                    n = 0,
                },
                createdGame = function(element, gameid)
                    element.data.gameid = gameid
                end,
                thinkTime = 0.2,
                think = function(element)
                    element.data.n = (element.data.n + 1) % 4
                    local dots = string.rep(".", element.data.n)
                    element.text = "Creating Game" .. dots

                    if element.data.gameid ~= nil then
                        local gameid = element.data.gameid

                        local games = lobby.games or {}
                        for i, game in ipairs(games) do
                            print("CreateGame: Checking game", game.gameid, game.description, "vs", gameid)
                            if game.gameid == gameid then
                                local panel = CreateGameEditor {
                                    game = game,
                                }

                                print("CreateGame: Add panel")
                                resultPanel.root:AddChild(panel)
                                resultPanel:DestroySelf()

                                return
                            end
                        end
                    end
                end,
                error = function(element, message)
                    element.text = message
                    element.selfStyle.color = "red"
                end,
            },

            gui.Button{
				classes = {"closeButton"},
                floating = true,
                halign = "right",
                valign = "top",
                press = function(element)
                    resultPanel:DestroySelf()
                end,
            },
        }
    }


    lobby:CreateGame {
        description = moduleInfo.text,
        descriptionDetails = moduleInfo.descriptionDetails,
        coverart = moduleInfo.coverart,
        -- The "No Module" option carries an explicit empty startingModule (an
        -- empty string is truthy in Lua, so it wins over the id fallback) plus
        -- noSystemModule = true to suppress the mcdm-drawsteel injection.
        startingModule = moduleInfo.startingModule or moduleInfo.id,
        noSystemModule = moduleInfo.noSystemModule == true,
        backend = backend or "local",
        create = function(gameid)
            if resultPanel == nil or not resultPanel.valid then
                return
            end
            print("CreateGame: Callback in lua called", gameid)

            resultPanel:FireEventTree("createdGame", gameid)
        end,
        error = function(message)
            if resultPanel ~= nil and resultPanel.valid then
                resultPanel:FireEventTree("error", message)
            end
        end,
    }

    return resultPanel
end

function CreateGameDialog()
    -- Build the module list for this dialog. Admins get an extra "No Module"
    -- option that creates an empty game with no starter map and no system
    -- (mcdm-drawsteel) module -- it enters a blank map with zero modules.
    -- startingModule = "" tells C# to skip the starter-map install;
    -- noSystemModule = true tells C# to set GameDetails.noSystemModule so the
    -- system module is never injected.
    local m_moduleOptions = {}
    for _, module in ipairs(g_moduleOptions) do
        m_moduleOptions[#m_moduleOptions + 1] = module
    end
    -- Community game types (e.g. Crows) are offered only when the user has
    -- opted in via the "Allow Community Game Types" preference.
    if g_allowCommunityGameTypes:Get() then
        for _, module in ipairs(g_communityModuleOptions) do
            m_moduleOptions[#m_moduleOptions + 1] = module
        end
    end
    if dmhub.isAdminAccount then
        m_moduleOptions[#m_moduleOptions + 1] = {
            id = "__nomodule__",
            text = "No Module (Admin)",
            descriptionDetails = "Admin only: create an empty game with no starting map and no game-system module. The game enters a blank map with zero modules installed.",
            coverart = "panels/square.png",
            startingModule = "",
            noSystemModule = true,
        }
    end

    local m_moduleid = m_moduleOptions[1].id
    local GetModule = function()
        for i, module in ipairs(m_moduleOptions) do
            if module.id == m_moduleid then
                return module
            end
        end
        return nil
    end

    local resultPanel

    resultPanel = gui.Panel {
        width = "100%",
        height = "100%",
        bgimage = true,
        bgcolor = "clear",
        floating = true,
        gui.Panel {
            styles = ThemeEngine.GetStyles(),
            classes = { "framedPanel" },
            width = 800,
            height = 900,
            halign = "center",
            valign = "center",
            flow = "vertical",

            -- Live re-theming: GetStyles() is a one-shot snapshot; subscribe
            -- so the dialog recolors when the active theme/scheme changes
            -- without requiring re-open. Guard with .valid so the callback
            -- no-ops after the dialog closes.
            create = function(element)
                ThemeEngine.OnThemeChanged(mod, function()
                    if element.valid then
                        element.styles = ThemeEngine.GetStyles()
                    end
                end)
            end,

            gui.Label {
                classes = { "dialogTitle" },
                text = "Create New Campaign",
                halign = "center",
                valign = "top",
                width = "auto",
                height = "auto",
                fontSize = 32,
                textAlignment = "center",
            },

            gui.Divider {
                tmargin = 4,
                bmargin = 8,
            },

            gui.Label {
                text = "Choose Module:",
                width = "80%",
                height = "auto",
                fontSize = 20,
                textAlignment = "left",
                halign = "center",
            },

            gui.Dropdown {
                width = "80%",
                height = 32,
                halign = "center",
                fontSize = 20,
                options = m_moduleOptions,
                idChosen = m_moduleid,
                change = function(element)
                    m_moduleid = element.idChosen
                    resultPanel:FireEventTree("refreshModule")
                end,
            },

            gui.Label {
                fontSize = 28,
                width = "80%",
                height = 36,
                halign = "center",
                bold = true,
                tmargin = 8,
                refreshModule = function(element)
                    element.text = GetModule().text
                end,
            },

            gui.Panel {
                width = "80%",
                height = "56.25% width", --16:9 aspect ratio
                bgcolor = "white",
                halign = "center",
                vmargin = 4,
                refreshModule = function(element)
                    element.bgimage = GetModule().coverart
                end,
            },

            gui.Label {
                width = "80%",
                height = "auto",
                halign = "center",
                fontSize = 16,
                refreshModule = function(element)
                    element.text = GetModule().descriptionDetails
                end,
            },

            gui.Panel {
                width = "80%",
                height = 32,
                halign = "center",
                flow = "horizontal",
                vmargin = 4,
                hidden = not dmhub.GetSettingValue("dev"),

                gui.Label {
                    text = "Storage Backend:",
                    width = "auto",
                    height = "auto",
                    fontSize = 16,
                    valign = "center",
                    rmargin = 8,
                },
                gui.Dropdown {
                    width = 200,
                    height = 28,
                    fontSize = 16,
                    valign = "center",
                    options = { { id = "local", text = "Offline" }, { id = "durableobjects", text = "Durable Objects" }, { id = "durableobjects-staging", text = "Durable Objects (Staging)" }, { id = "firebase", text = "Firebase" } },
                    idChosen = "local",
                    create = function(element)
                        if dmhub.GetSettingValue("dev") then
                            resultPanel.data.backend = "local"
                        end
                    end,
                    change = function(element)
                        resultPanel.data.backend = element.idChosen
                    end,
                },
            },

            gui.Button {
                halign = "center",
                valign = "bottom",
                width = 240,
                height = 40,
                fontSize = 24,
                vmargin = 8,
                bold = true,
                text = "Create Campaign",
                click = function(element)
                    local backend = resultPanel.data and resultPanel.data.backend or "local"
                    local loadingScreen = CreateGameLoadingScreen(GetModule(), backend)
                    element.root:AddChild(loadingScreen)
                    resultPanel:DestroySelf()
                end,
            },

            gui.Button {
                classes = { "closeButton" },
                floating = true,
                halign = "right",
                valign = "top",
                press = function(element)
                    resultPanel:DestroySelf()
                end,
            },
        }
    }

    resultPanel:FireEventTree("refreshModule")
    return resultPanel
end

local function MakeHeroPanel(heroIndex)
    local resultPanel

    local m_character = nil


    local addIcon = gui.Panel {
        classes = { "hiddenWithCharacter" },
        bgimage = "ui-icons/Plus.png",
        bgcolor = "white",
        floating = true,
        width = 96,
        height = 96,
        halign = "center",
        valign = "center",
        styles = {
            {
                brightness = 0.8,
            },
            {
                selectors = { "parent:hover" },
                scale = 1.1,
                brightness = 1,
                transitionTime = 0.1,
            }
        },

        hover = function ()
            audio.FireSoundEvent("Mouse.Hover")
        end,

        press = function ()
            audio.FireSoundEvent("Mouse.Click")
        end,

    }


    local avatarPanel = gui.Panel {
        classes = { "hiddenWithNoCharacter" },
        bgimage = true,
        bgcolor = "white",
        width = string.format("%f%% height", Styles.portraitWidthPercentOfHeight),
        height = "100%",
        refreshCharacter = function(element, character)
            local portrait = character.offTokenPortrait
            element.bgimage = portrait
            element.selfStyle.imageRect = character:GetPortraitRectForAspect(Styles.portraitWidthPercentOfHeight * 0.01,
                portrait)
        end,

        gui.Panel {
            -- viewHeroButton class supplies @fg bgcolor tint (multiplies
            -- the narrow button.png texture). Hover/press brightness
            -- multipliers stay local. Mirror of playCampaignButton.
            classes = { "viewHeroButton" },
            styles = {
                {
                    selectors = { "~hoverchar" },
                    opacity = 0,
                    transitionTime = 0.1,
                },
                {
                    selectors = { "hover", "~label" },
                    brightness = 1.4,
                    scale = 1.04,
                },
                {
                    selectors = { "press" },
                    brightness = 0.7,
                },
            },

            bgimage = "panels/titlescreen/button-narrow.png",

            height = 131 * 0.4,
            width = 336 * 0.4,
            halign = "center",
            valign = "bottom",

            bmargin = 3,

            press = function(element)
                EditHero(element, m_character)
                audio.FireSoundEvent("Mouse.Click")
            end,

            hover = function ()
                audio.FireSoundEvent("Mouse.Hover")
            end,

            gui.Label {
                -- viewHeroLabel class supplies @fgStrong text color
                -- for contrast against the dark center of the tinted
                -- button.png below.
                classes = { "viewHeroLabel" },
                text = "VIEW",
                fontSize = 18,
                fontFace = "newzald",
                halign = "center",
                valign = "center",
                width = "auto",
                height = "auto",
                textAlignment = "center",
                y = 2,
            }
        }
    }

    local nameLabel = gui.Label {
        classes = { "hiddenWithNoCharacter" },
        width = "100%-32",
        height = "auto",
        lmargin = 4,
        fontSize = 24,
        minFontSize = 8,
        bold = true,
        uppercase = true,
        valign = "top",
        halign = "left",
        textAlignment = "left",
        refreshCharacter = function(element, character)
            element.text = character.name or "Unnamed"
        end,
    }

    local detailsLabel = gui.Label {
        classes = { "hiddenWithNoCharacter" },
        width = "100%-32",
        height = "auto",
        lmargin = 4,
        fontSize = 16,
        minFontSize = 8,
        valign = "top",
        halign = "left",
        textAlignment = "left",
        refreshCharacter = function(element, token)

            local ancestry = token.properties:RaceOrMonsterType()

            local className = ""
            local subclassName = ""
            local classesTable = dmhub.GetTable('classes')

            local classes = token.properties:get_or_add("classes", {})
            for i, entry in ipairs(classes) do
                local classInfo = classesTable[entry.classid]
                if classInfo ~= nil then
                    className = classInfo.name
                    break
                end
            end

            local classes = token.properties:GetSubclasses()
            for i, entry in ipairs(classes) do
                subclassName = entry.name
                break
            end

            element.text = string.format("%s\n%s\n%s", ancestry, className, subclassName)
        end,
    }

    local joinGameButton = gui.Button {
        classes = { "hiddenWithNoCharacter" },
        width = "90%",
        fontSize = 18,
        height = 30,
        halign = "center",
        valign = "bottom",
        text = "JOIN A CAMPAIGN",
        click = function(element)
            element.root:FireEventTree("titlescreenCreateGame", m_character)
        end,
        refreshCharacter = function(element, token, game)
            element:SetClass("collapsed", game ~= nil)
        end,
    }

    local playingInCampaignBanner = gui.Panel {
        -- playingInCampaignBanner class supplies @bgAlt bgcolor via the
        -- Heroes column's MergeStyles extras. The {banner} class stays
        -- for the existing hover-brightness rules below.
        classes = { "collapsed", "banner", "playingInCampaignBanner" },
        width = "94%",
        height = "20% width",
        bgimage = true,
        valign = "bottom",
        halign = "center",
        flow = "horizontal",
        styles = {
            {
                selectors = { "hover", "banner" },
                brightness = 1.5,
            },
            {
                selectors = { "parent:hover", "parent:banner" },
                brightness = 1.5,
            },
        },
        press = function(element)
            if element.data.game then
                if GameHasNoLocalData(element.data.game) then
                    ShowTitlescreenMessageDialog(element.root, OFFLINE_GAME_ELSEWHERE_TITLE, OFFLINE_GAME_ELSEWHERE_MESSAGE)
                    return
                end
                element.root:FireEventTree("overrideLoadingScreenArt", element.data.game.coverart, element.data.game.gameid)
                lobby:EnterGame(element.data.game.gameid)
            end
        end,
        refreshCharacter = function(element, token, game)
            element.data.game = game
            element:SetClass("collapsed", game == nil)
        end,
        gui.Panel {
            width = string.format("%f%% height", (1920 / 1080) * 100),
            height = "100%",
            halign = "left",
            bgcolor = "white",
            bgimage = true,
            refreshCharacter = function(element, token, game)
                if game ~= nil then
                    element.bgimage = game.coverart
                end
            end,
        },
        gui.Panel {
            width = "60%",
            height = "100%",
            flow = "vertical",
            gui.Label {
                classes = { "playingInCampaignBannerTitle" },
                text = "Playing in Campaign",
                fontSize = 16,
                minFontSize = 8,
                width = "auto",
                height = "auto",
                valign = "center",
            },
            gui.Label {
                classes = { "playingInCampaignBannerName" },
                fontSize = 16,
                minFontSize = 8,
                valign = "center",
                textWrap = false,
                maxWidth = "100%",
                width = "auto",
                height = "auto",
                refreshCharacter = function(element, token, game)
                    if game ~= nil then
                        element.text = game.description
                    end
                end,
            }
        }
    }

    local deleteButton = gui.Button {
        classes = { "deleteButton", "parentHover", "hiddenWithNoCharacter" },
        floating = true,
        width = 16,
        height = 16,
        halign = "right",
        valign = "top",
        rmargin = 2,
        tmargin = 2,
        press = function(element)
            local modal
            modal = gui.Panel {
                classes = { "framedPanel" },
                floating = true,
                styles = ThemeEngine.GetStyles(),
                width = 600,
                height = 600,
                halign = "center",
                valign = "center",

                create = function(element)
                    ThemeEngine.OnThemeChanged(mod, function()
                        if element.valid then
                            element.styles = ThemeEngine.GetStyles()
                        end
                    end)
                end,

                gui.Label {
                    classes = { "modalTitle" },
                    text = "Delete Character?",
                    vmargin = 8,
                },

                gui.Label {
                    classes = { "modalMessage" },
                    text = "Do you want to delete this character? This action cannot be undone.",
                },

                gui.Panel {
                    halign = "center",
                    valign = "bottom",
                    flow = "horizontal",
                    width = "80%",
                    height = "auto",
                    gui.Button {
                        text = "Cancel",
                        fontSize = 24,
                        halign = "center",
                        click = function(element)
                            modal:DestroySelf()
                        end,
                    },
                    gui.Button {
                        text = "Delete",
                        fontSize = 24,
                        halign = "center",
                        click = function(element)
                            local classInfo = m_character.properties:GetClass()
                            track("character_delete", {
                                class = classInfo and classInfo.name or "",
                                ancestry = m_character.properties:RaceOrMonsterType() or "",
                                level = m_character.properties:CharacterLevel(),
                                dailyLimit = 5,
                            })
                            game.DeleteCharacters({ m_character.charid })
                            modal:DestroySelf()
                        end,
                    },
                },
            }

            element.root:AddChild(modal)
            print("Delete Character:", m_character.charid)
        end,
    }

    resultPanel = gui.Panel {
        width = "48%",
        height = 176,
        halign = "center",
        bmargin = 10,
        bgimage = true,
        bgcolor = "black",
        opacity = 0.9,
        flow = "horizontal",

        styles = {
            {
                selectors = { "hiddenWithNoCharacter", "nocharacter" },
                hidden = 1,
            },
            {
                selectors = { "hiddenWithCharacter", "~nocharacter" },
                hidden = 1,
            },
        },

        press = function(element)
            if element:HasClass("nocharacter") then
                CreateHero(element)
            end
        end,

        -- Dev/admin right-click menu: opens the live data debug console
        -- focused on this character. Only shown for admins or when the
        -- "dev" setting is on. The titlescreen gives no other way to
        -- inspect the token data behind a character card, so this fills
        -- the "(Debug) Open Token Data" gap that exists in-game.
        rightClick = function(element)
            if m_character == nil then return end
            if not (dmhub.GetSettingValue("dev") or dmhub.isAdminAccount) then return end

            element.popup = gui.ContextMenu {
                width = 260,
                entries = {
                    {
                        text = "Open Token Data",
                        click = function()
                            dmhub.OpenDebugConsole("/characters/" .. m_character.charid, "game")
                        end,
                    },
                },
                click = function() element.popup = nil end,
            }
        end,

        hover = function(element)
            element:SetClassTree("hoverchar", true)
        end,
        dehover = function(element)
            element:SetClassTree("hoverchar", false)
        end,

        characters = function(element, chars, games)
            local c = chars[heroIndex]
            m_character = c


            element:SetClassTree("nocharacter", c == nil)
            if c ~= nil then
                local joinedCampaign = rawget(c.properties, "joinedCampaign")
                local joinedGame = nil
                for _, game in ipairs(games) do
                    if game.gameid == joinedCampaign then
                        joinedGame = game
                        break
                    end
                end


                element:FireEventTree("refreshCharacter", c, joinedGame)
            end
        end,


        addIcon,
        avatarPanel,
        gui.Panel {
            flow = "vertical",
            halign = "right",
            width = "67%",
            height = "100%",

            nameLabel,
            detailsLabel,
            joinGameButton,
            playingInCampaignBanner,
        },
        deleteButton,
    }

    return resultPanel
end

function CreateTitlescreen(dialog, options)
    local titlescreen

    local m_loadingScreenArt = nil
    local m_loadingGameId = nil

    local m_currentSearch = nil

    local m_states = { "starting-screen", "selection-screen", "games-screen" }
    local function SetTitlescreenState(state)
        for _, s in ipairs(m_states) do
            titlescreen:SetClassTree(s, s == state)
        end

        --Let panels that manage live state keyed off the current screen
        --react immediately (the store banner's rollable die seeds/clears
        --its real 3D resting die on this).
        titlescreen:FireEventTree("titlescreenStateChanged", state)

        m_currentSearch = nil

        TopBar.UninstallSearchHandler(titlescreen.data.searchHandler)
        titlescreen.data.searchHandler = nil
        if state == "games-screen" then
            titlescreen.data.searchHandler = TopBar.InstallSearchHandler(function(text)
                m_currentSearch = text
                if m_currentSearch == "" then
                    m_currentSearch = nil
                end
                titlescreen:FireEventTree("refreshLobby")
            end)
        else
        end
    end

    local m_games = {}

    local function DirectorMode()
        return titlescreen:HasClass("titlescreenDirector")
    end

    local function GetNumPages()
        return math.ceil(#m_games / 4)
    end

    local function PageBaseIndex()
        local npage = clamp(round(g_gamePageSetting:Get()), 1, GetNumPages())
        return (npage - 1) * 4
    end

    local RefreshAllPanels
    RefreshAllPanels = function(t)
        t.selfStyle = t.selfStyle --force style recompute
        t.children = t.children
        for i, panel in ipairs(t.children) do
            RefreshAllPanels(panel)
        end
    end

    titlescreen = gui.Panel {
        id = "titlescreenRoot",
        classes = { 'main-panel', 'starting-screen' },

        styles = {
            Styles.Default,
            {
                selectors = { "hideOnStartingScreen", "starting-screen" },
                hidden = 1,
            },
            {
                selectors = { "hideOnSelectionScreen", "selection-screen" },
                hidden = 1,
            },
            {
                selectors = { "hideOnDirector", "titlescreenDirector" },
                hidden = 1,
            },
            {
                selectors = { "parent:main-panel", "parent:titlescreenHidden" },
                hidden = 1,
            }
        },

        width = 1920 * (dmhub.screenDimensions.x / dmhub.screenDimensions.y),
        height = 1080,

        screenResized = function(element)
            RefreshAllPanels(element)
            element.selfStyle.width = 1920 * (dmhub.screenDimensions.x / dmhub.screenDimensions.y)
        end,

        halign = 'center',
        valign = 'bottom',


        --brightness = 0.3,


        flow = "vertical",

        create = function(element)
            SetTitlescreenState("starting-screen")
            --element:SetClassTree("starting-screen", false)
            --element:SetClass("selection-screen", false)
            --element:SetClass("games-screen", true)
        end,

        destroy = function(element)
            TopBar.UninstallSearchHandler(element.data.searchHandler)
            element.data.searchHandler = nil
        end,

        titlescreenCreateGame = function(element, tokenToImport)
            if #lobby.games >= MaxGamesAllowed() then
                TooManyGamesDialog(element)
                return
            end

            if DirectorMode() then
                local loadingScreen = CreateGameDialog()
                element.root:AddChild(loadingScreen)
            else
                local modal = CreateJoinGameModal(tokenToImport)
                element.root:AddChild(modal)
            end
        end,


        overrideLoadingScreenArt = function(element, artid, gameid)
            if artid ~= nil then
                m_loadingScreenArt = artid
            end
            if gameid ~= nil then
                m_loadingGameId = gameid
            end
            print("EVENT::: overrideLoadingScreenArt", artid, gameid)
        end,

        loginFailed = function(element, message)
            print("EVENT::: loginFailed")
        end,


        beginLoading = function(element)
            print("EVENT::: beginLoading")
            -- Leaving the titlescreen to enter a game: drop the live metadata
            -- monitors for the page's games (they'll be re-established from
            -- refreshLobby when we return).
            lobby:SetVisibleGames({})
            if element.data.searchHandler ~= nil then
                TopBar.UninstallSearchHandler(element.data.searchHandler)
                element.data.searchHandler = nil
            end

            if m_loadingScreenArt ~= nil then
                if element.data.loadingScreen ~= nil then
                    element.data.loadingScreen:DestroySelf()
                    element.data.loadingScreen = nil
                end

                local quote = CodexQuotes.SelectQuote()
                local quoteText = ""
                if quote ~= nil then
                    quoteText = string.format("<i>%s</i>\n- %s", quote.quote, quote.speaker)
                end

                -- Show an error with Retry/Cancel if the load stalls past this many seconds.
                -- The outer watcher panel must stay active (no "hidden" class) so its think
                -- keeps firing: SheetPanel.cs disables gameObject for any panel with hidden>=1,
                -- and SheetManager.cs only calls Think() on panels with activeInHierarchy.
                -- The visible error modal is a child with the "hidden" class, unhidden on stall.
                local STALL_TIMEOUT_SECONDS = 60
                local stallPanel
                stallPanel = gui.Panel {
                    floating = true,
                    halign = "center",
                    valign = "center",
                    width = "100%",
                    height = "100%",
                    bgimage = "panels/square.png",
                    bgcolor = "#00000000",
                    interactable = false,

                    data = {
                        elapsed = 0,
                        shown = false,
                    },

                    thinkTime = 1,
                    think = function(element)
                        if element.data.shown then return end
                        element.data.elapsed = element.data.elapsed + 1
                        if element.data.elapsed >= STALL_TIMEOUT_SECONDS then
                            element.data.shown = true
                            element.bgcolor = "#000000b0"
                            element.interactable = true
                            local modal = element:Get("stallModal")
                            if modal ~= nil then
                                modal:SetClass("hidden", false)
                            end
                        end
                    end,

                    gui.Panel {
                        id = "stallModal",
                        classes = { "framedPanel", "hidden" },
                        styles = {
                            Styles.Default,
                            Styles.Panel,
                        },
                        bgimage = true,
                        halign = "center",
                        valign = "center",
                        width = 640,
                        height = "auto",
                        minHeight = 320,
                        flow = "vertical",
                        vpad = 24,

                        gui.Label {
                            text = "Couldn't Load Game",
                            fontSize = 36,
                            bold = true,
                            width = "auto",
                            height = "auto",
                            halign = "center",
                            valign = "top",
                            color = "white",
                            tmargin = 12,
                        },

                        gui.Label {
                            text = "We couldn't reach the game server. Check your internet connection and try again.",
                            fontSize = 20,
                            width = "80%",
                            height = "auto",
                            halign = "center",
                            textAlignment = "center",
                            color = "white",
                            vmargin = 16,
                        },

                        gui.Panel {
                            width = "auto",
                            height = "auto",
                            halign = "center",
                            valign = "bottom",
                            flow = "horizontal",
                            bmargin = 12,

                            gui.Button {
                                text = "Retry",
                                halign = "center",
                                hmargin = 12,
                                click = function(btn)
                                    --Retrying a Local game whose data lives on
                                    --another computer would just recreate an
                                    --empty local db and stall again; leave and
                                    --explain instead.
                                    if GameHasNoLocalData(FindLobbyGame(m_loadingGameId)) then
                                        ShowTitlescreenMessageDialog(btn.root, OFFLINE_GAME_ELSEWHERE_TITLE, OFFLINE_GAME_ELSEWHERE_MESSAGE)
                                        dmhub.LeaveGame()
                                        return
                                    end
                                    local modal = stallPanel:Get("stallModal")
                                    if modal ~= nil then
                                        modal:SetClass("hidden", true)
                                    end
                                    stallPanel.bgcolor = "#00000000"
                                    stallPanel.interactable = false
                                    stallPanel.data.elapsed = 0
                                    stallPanel.data.shown = false
                                    if m_loadingGameId ~= nil then
                                        lobby:EnterGame(m_loadingGameId)
                                    end
                                end,
                            },

                            gui.Button {
                                text = "Cancel",
                                halign = "center",
                                hmargin = 12,
                                click = function(btn)
                                    dmhub.LeaveGame()
                                end,
                            },
                        },
                    },
                }

                local loadingScreen = gui.Panel {
                    classes = { "loadingScreen" },
                    width = ScaleDimensionsToFill(1920),
                    height = ScaleDimensionsToFill(1080),

                    imageLoaded = function(element)
                        if element.bgsprite == nil then
                            return
                        end

                        local src_w = element.bgsprite.dimensions.x
                        local src_h = element.bgsprite.dimensions.y

                        local dst_w = ScaleDimensionsToFill(1920)
                        local dst_h = ScaleDimensions(1080)

                        print("ASPECT::", dst_w/dst_h, "vs", src_w/src_h)

                        if dst_w/dst_h > src_w/src_h then
                            --the destination is wider than the source. Fit to width.
                            local new_src_h = src_w * (dst_h / dst_w)
                            local letterbox = 1 - new_src_h/src_h

                            local rect = {
                                x1 = 0,
                                y1 = letterbox*0.5,
                                x2 = 1,
                                y2 = 1 - letterbox*0.5,
                            }

                            element.selfStyle.imageRect = rect

                        elseif dst_w/dst_h < src_w/src_h then
                            --the destination is taller than the source. Fit to height.
                            local new_src_w = src_h * (dst_w / dst_h)
                            local letterbox = 1 - new_src_w/src_w
                            local rect = {
                                x1 = letterbox*0.5,
                                y1 = 0,
                                x2 = 1 - letterbox*0.5,
                                y2 = 1,
                            }

                            element.selfStyle.imageRect = rect
                        else
                            element.selfStyle.imageRect = {
                                x1 = 0,
                                y1 = 0,
                                x2 = 1,
                                y2 = 1,
                            }
                        end



                    end,
                    halign = "center",
                    valign = "center",
                    floating = true,
                    bgimage = m_loadingScreenArt,
                    bgimageAlpha = "panels/gamescreen/loadingscreen4.png",
                    fadeAwayAndDie = function(element)
                        element:SetClass("dying", true)
                        element:ScheduleEvent("destroySelf", 0.4)
                    end,
                    destroySelf = function(element)
                        element:DestroySelf()
                    end,

                    styles = {
                        {
                            selectors = { "loadingScreen" },
                            bgcolor = "#ffffffff",
                            alphaThresholdFade = 0.1,
                            alphaThreshold = 1,
                        },

                        {
                            classes = { "loadingScreen", "create" },
                            bgcolor = "#ffffff00",
                            alphaThreshold = -0.1,
                            transitionTime = 0.3,
                        },
                        {
                            classes = { "loadingScreen", "dying" },
                            bgcolor = "#ffffff00",
                            alphaThreshold = -0.1,
                            transitionTime = 0.4,
                        },
                    },


                    -- Viewport-sized container so the loading-quote banner stays
                    -- in the visible screen area at any aspect ratio. loadingScreen
                    -- is oversized by ScaleDimensionsToFill on widescreens, which
                    -- would otherwise push this bottom-anchored banner below the
                    -- screen. (Mirrors the ProgressDice container below.)
                    gui.Panel {
                        floating = true,
                        width = 1080 * (dmhub.screenDimensions.x / dmhub.screenDimensions.y),
                        height = 1080,
                        halign = "center",
                        valign = "center",

                    gui.Panel {
                        flow = "vertical",
                        width = 1200,
                        height = "auto",
                        halign = "center",
                        valign = "bottom",
                        bmargin = 80,

                        gui.Divider {
                            vmargin = 0,
                            height = 2,
                            y = 3.5,
                        },

                        gui.Panel {
                            classes = { "loadingQuoteBanner" },
                            -- Theme-aware banner: the scheme's @bg paints in the
                            -- middle of a horizontal alpha mask, darkening the
                            -- cover art behind the quote and fading to clear at
                            -- the edges. Label color falls through to the theme
                            -- default ({label} -> @fgStrong) for legibility.
                            styles = ThemeEngine.MergeStyles{
                                {
                                    selectors = { "loadingQuoteBanner" },
                                    bgimage = "panels/square.png",
                                    bgcolor = "@bg",
                                    gradient = "@maskHorizontal",
                                },
                            },

                            halign = "center",
                            height = "auto",
                            vpad = 15,
                            minHeight = 60,
                            vmargin = 0,
                            width = "68%",

                            gui.Label {
                                text = quoteText,
                                fontSize = 20,
                                width = "auto",
                                height = "auto",
                                textAlignment = "left",
                                halign = "center",
                                valign = "center",
                                maxWidth = 600,
                                markdown = true,
                            },
                        },

                        gui.Divider {
                            vmargin = 0,
                            height = 2,
                            y = -3.5,
                        },
                    },
                    },

                    -- Viewport-sized container so the ProgressDice stays
                    -- in the visible screen area at any aspect ratio.
                    gui.Panel {
                        floating = true,
                        width = 1080 * (dmhub.screenDimensions.x / dmhub.screenDimensions.y),
                        height = 1080,
                        halign = "center",
                        valign = "center",

                        gui.ProgressDice{
                            floating = true,
                            halign = "right",
                            valign = "bottom",
                            hmargin = 28,
                            vmargin = 28,
                            width = 96,
                            height = 96,
                            thinkTime = 0.01,
                            think = function(element)
                                local progress = dmhub.gameLoadingProgress or 0
                                element:FireEventTree("progress", progress)
                            end,
                        },
                    },

                    stallPanel,
                }

                titlescreen:AddChild(loadingScreen)
                element.data.loadingScreen = loadingScreen
            end
        end,

        endLoading = function(element)
            print("EVENT::: endLoading")
            if element.data.loadingScreen ~= nil then
                element.data.loadingScreen:FireEvent("fadeAwayAndDie")
                element.data.loadingScreen = nil
            end
        end,

        returnFromGame = function(element)
            --make the loading screen show.
            element:FireEvent("beginLoading")
        end,

        returnFromGameComplete = function(element)
            element:FireEvent("endLoading")
        end,

        --Fired from C# via GameHarness.ShowTitlescreenError (e.g. the
        --malformed-game bounce). This used to be a print-only stub, so load
        --failures bounced back to the titlescreen with no visible
        --explanation.
        error = function(element, message)
            print("EVENT::: ERROR", message)
            if message ~= nil and message ~= "" then
                ShowTitlescreenMessageDialog(titlescreen, "Couldn't Load Game", message)
            end
        end,

        gui.Panel {
            width = 1920,
            height = 1080,
            halign = "center",
            valign = "center",
            flow = "vertical",
            endLoading = function(element)
                element:SetClass("hidden", true)
            end,
            returnFromGameComplete = function(element)
                element:SetClass("hidden", false)
            end,
            gui.Panel {
                classes = { "background" },

                bgimage = "panels/backgrounds/delian-tomb-bg.png",
                bgcolor = 'white',

                autosizeimage = true,
                width = 1.05 * ScaleDimensionsToFill(1920),
                height = 1.05 * ScaleDimensionsToFill(1080),

                screenResized = function(element)
                    element.selfStyle.width = 1.05 * ScaleDimensionsToFill(1920)
                    element.selfStyle.height = 1.05 * ScaleDimensionsToFill(1080)
                end,

                halign = 'center',
                valign = 'center',

                floating = true,

                thinkTime = 0.01,
                think = function(element)
                    local x = clamp(resistanceCurve(element.parent.mousePoint.x - 0.5), -1, 1)
                    local y = clamp(resistanceCurve(-(element.parent.mousePoint.y - 0.5)), -1, 1)

                    x = x * 6
                    y = y * 6

                    if element.data.x == nil then
                        element.data.x = x
                        element.data.y = y
                    end

                    element.data.x = element.data.x * 0.9 + x * 0.1
                    element.data.y = element.data.y * 0.9 + y * 0.1


                    local t = math.min(1, element.aliveTime)

                    if element.data.endtime == nil and not element:HasClass("starting-screen") then
                        element.data.endtime = element.aliveTime
                    end

                    if element.data.endtime ~= nil then
                        local dt = element.aliveTime - element.data.endtime
                        t = math.max(0, 1 - dt / 2)
                        if t <= 0 then
                            element.thinkTime = nil
                        end
                    end

                    element.x = element.data.x * t
                    element.y = element.data.y * t
                end,

                gui.Panel {
                    classes = { "starting-screen" },
                    bgimage = "panels/backgrounds/delian-tomb-bg-blur.png",
                    bgcolor = 'white',
                    width = "100%",
                    height = "100%",
                    brightness = 0.3,
                    click = function(element)
                        element.root:FireEventTree("titlescreenClick")
                    end,
                    styles = {
                        {
                            selectors = { "starting-screen" },
                            opacity = 0,
                            transitionTime = 1,
                        },
                        {
                            opacity = 1,
                            transitionTime = 0.4,
                        },
                    },
                },
            },

            gui.Button {
                -- Scoped ThemeEngine cascade so the {button} class picks up
                -- @bg/@border/@fg tokens (matches the Dropdown pattern in this
                -- file). The parent titlescreen root still uses Styles.Default.
                styles = ThemeEngine.GetStyles("default", "default"),
                classes = { "hideOnStartingScreen", "hideOnSelectionScreen" },
                halign = "left",
                valign = "top",
                floating = true,
                text = "<<Back",
                width = "auto",
                height = "auto",
                pad = 6,
                borderBox = true,
                hmargin = 8,
                vmargin = 24,
                captureEscape = true,
                escape = function(element)
                    element:FireEvent("press")
                end,
                press = function(element)
                    SetTitlescreenState("selection-screen")
                end,
            },

            --top king panel
            gui.Panel {

                classes = { 'king-panel' },

                bgimage = true,

                width = "100%",
                height = "10%",

                flow = "horizontal",

                styles = {

                    {
                        classes = { 'king-panel' },
                        hidden = 1,
                    },

                    {
                        classes = { 'parent:starting-screen', 'king-panel' },
                        hidden = 0,
                    },


                },

                --empty
                gui.Panel {


                    width = "30%",
                    height = "100%",


                },

                --top title "tactical heroic fantasy"
                gui.Panel {

                    bgimage = true,

                    width = "40%",
                    height = "100%",


                    gui.Panel {

                        bgimage = "panels/titlescreen/tacticaltext.png",
                        bgcolor = "white",

                        halign = "center",
                        valign = "bottom",
                        width = 1150 * 0.5,
                        height = 60 * 0.5,



                    },



                },


                --buttons
                gui.Panel {


                    width = "30%",
                    height = "100%",


                },


            },

            --draw steel king panel
            gui.Panel {

                classes = { 'king-panel' },


                width = "100%",
                height = "13%",

                styles = {

                    {
                        classes = { 'king-panel' },
                        hidden = 1,
                    },

                    {
                        classes = { 'parent:starting-screen', 'king-panel' },
                        hidden = 0,
                    },


                },

                gui.Panel {

                    bgimage = "panels/titlescreen/drawsteeltext.png",
                    bgcolor = "white",

                    halign = "center",
                    valign = "bottom",
                    width = 1670 * 0.5,
                    height = 235 * 0.5,




                },


            },

            --codex and swords king panel
            gui.Panel {

                classes = { 'king-panel' },

                bgimage = true,

                width = "100%",
                height = "7%",

                flow = "horizontal",

                styles = {

                    {
                        classes = { 'king-panel' },
                        hidden = 1,
                    },

                    {
                        classes = { 'parent:starting-screen', 'king-panel' },
                        hidden = 0,
                    },


                },

                gui.Panel {


                    width = "35%",
                    height = "100%",



                },

                gui.Panel {

                    bgimage = true,

                    width = "30%",
                    height = "100%",


                    gui.Panel {

                        bgimage = "panels/titlescreen/sword2.png",
                        bgcolor = "white",

                        halign = "right",

                        width = 304 * 0.5,
                        height = 177 * 0.5,



                    },

                    gui.Panel {

                        bgimage = "panels/titlescreen/codextext.png",
                        bgcolor = "white",

                        halign = "center",
                        width = 608 * 0.5,
                        height = 177 * 0.5,




                    },

                    gui.Panel {

                        bgimage = "panels/titlescreen/sword1.png",
                        bgcolor = "white",

                        halign = "left",

                        width = 304 * 0.5,
                        height = 177 * 0.5,



                    },



                },


                gui.Panel {


                    width = "35%",
                    height = "100%",



                },

            },

            --middle empty panel
            gui.Panel {


                width = "100%",
                height = "60%",



            },

            --bottom king panel
            gui.Panel {

                classes = { 'king-panel' },
                bgimage = true,

                width = "100%",
                height = "10%",

                flow = "horizontal",

                styles = {

                    {
                        classes = { 'king-panel' },
                        hidden = 1,
                    },

                    {
                        classes = { 'parent:starting-screen', 'king-panel' },
                        hidden = 0,
                    },


                },







            },

            gui.Panel {

                classes = { 'king-panel', cond(g_devStorePreviewSetting:Get(), "makeRoomForShopBanner") },

                bgimage = true,
                --bgcolor = "white",

                --width lives in the styles below (not inline) so the
                --makeRoomForShopBanner variant can narrow it; inline
                --properties always override styles.
                height = 700,

                floating = true,

                halign = "center",
                valign = "center",

                --When the store banner is shown at the bottom of the screen,
                --pull the Director/Player cards closer together, shrink them
                --a little, and shift them to make room for it.
                multimonitor = { "dev:storepreview" },
                monitor = function(element)
                    element:SetClass("makeRoomForShopBanner", g_devStorePreviewSetting:Get())
                end,

                styles = {

                    {
                        classes = { 'king-panel' },
                        hidden = 1,
                        width = 1200,
                    },

                    {
                        classes = { 'parent:selection-screen', 'king-panel' },
                        hidden = 0,
                    },

                    {
                        classes = { 'king-panel', 'makeRoomForShopBanner' },
                        width = g_selectionCardsBannerWidth,
                        scale = g_selectionCardsBannerScale,
                        y = g_selectionCardsBannerY,
                    },


                },

                gui.Panel {

                    bgimage = "panels/titlescreen/directorsselect.png",
                    bgcolor = "white",
                    width = 500,
                    height = 700,

                    floating = true,

                    halign = "left",
                    valign = "center",


                    border = 1.5,
                    borderColor = "white",
                    cornerRadius = 2,

                    flow = "vertical",

                    classes = { "directorsselectsparent" },
                    styles = {
                        {
                            selectors = { "directorsselectsparent", "hover" },
                            --scale = 1.015,
                            transitionTime = 0.12,
                            imageRect = { x1 = 0.02, x2 = 0.98, y1 = 0.02, y2 = 0.98 },
                        }
                    },

                    hover = function ()
                    
                        audio.FireSoundEvent("Mouse.Hover")

                    end,

                    click = function(element)
                        g_gamePageSetting = g_directorGamePageSetting
                        SetTitlescreenState("games-screen")
                        titlescreen:SetClassTree("titlescreenDirector", true)
                        titlescreen:SetClassTree("titlescreenPlayer", false)
                        titlescreen:FireEventTree("refreshLobby")
                        audio.FireSoundEvent("Mouse.Click")
                    end,

                    gui.Panel {

                        bgimage = true,

                        height = "85%",
                        width = "100%",

                    },

                    gui.Panel {

                        bgimage = true,

                        height = "15%",
                        width = "100%",

                        gui.Panel {

                            bgimage = "panels/titlescreen/button.png",
                            bgcolor = "white",

                            height = 131 * 0.6,
                            width = 632 * 0.6,

                            halign = "center",
                            valign = "bottom",

                            bmargin = 3,

                            


                            gui.Label {

                                text = "DIRECTOR",
                                fontSize = 30,
                                fontFace = "newzald",
                                color = "white",
                                halign = "center",
                                valign = "center",
                                textAlignment = "center",
                                y = 5,
                                width = "auto",
                            }

                        }

                    }



                },

                gui.Panel {

                    bgimage = "panels/titlescreen/playersselect.png",
                    bgcolor = "white",
                    width = 500,
                    height = 700,

                    floating = true,

                    halign = "right",
                    valign = "center",


                    border = 1.5,
                    borderColor = "white",
                    cornerRadius = 2,

                    hover = function ()
                        audio.FireSoundEvent("Mouse.Hover")
                    end,

                    click = function(element)
                        g_gamePageSetting = g_playerGamePageSetting
                        SetTitlescreenState("games-screen")
                        titlescreen:SetClassTree("titlescreenDirector", false)
                        titlescreen:SetClassTree("titlescreenPlayer", true)
                        titlescreen:FireEventTree("refreshLobby")
                        audio.FireSoundEvent("Mouse.Click")
                    end,

                    flow = "vertical",

                    classes = { "playersselectparent" },
                    styles = {
                        {
                            selectors = { "playersselectparent", "hover" },
                            --scale = 1.015,
                            transitionTime = 0.12,
                            imageRect = { x1 = 0.02, x2 = 0.98, y1 = 0.02, y2 = 0.98 },
                        },
                    },

                    gui.Panel {

                        bgimage = true,

                        height = "85%",
                        width = "100%",

                    },

                    gui.Panel {

                        bgimage = true,

                        height = "15%",
                        width = "100%",



                        gui.Panel {

                            bgimage = "panels/titlescreen/button.png",
                            bgcolor = "white",

                            height = 131 * 0.6,
                            width = 632 * 0.6,

                            halign = "center",
                            valign = "bottom",

                            bmargin = 3,

                            gui.Label {

                                text = "PLAYER",
                                fontSize = 30,
                                fontFace = "newzald",
                                color = "white",
                                width = "auto",
                                halign = "center",
                                valign = "center",
                                textAlignment = "center",
                                y = 5,
                            }

                        }

                    }



                }

            },

            --Store banner across the bottom of the selection screen. Plain
            --white placeholder for now until real advertising art is ready.
            --Gated behind the same dev:storepreview flag as the rest of the
            --shop UI; the Director/Player card container above makes room for
            --it (makeRoomForShopBanner) under the same gate.
            gui.Panel {

                --'storeBannerZoom' drives the hover zoom below; it is listed
                --before the cond so a nil (storepreview on) can't truncate the
                --array and drop it.
                classes = { 'king-panel', 'shop-banner', 'storeBannerZoom', cond(g_devStorePreviewSetting:Get(), nil, "collapsed") },

                bgimage = g_storeBannerDefaultArt,
                bgcolor = "white",

                --Linear gradient across the art (shared with the cross-fade
                --layer below; see g_storeBannerGradient for the shape).
                --gradient = g_storeBannerGradient,

                --The banner art currently committed to our own bgimage (or
                --being faded to). Used to skip no-op fades when the newly
                --seeded set maps to the art already showing (e.g. two
                --consecutive sets that both fall back to the default art).
                data = { bannerArt = g_storeBannerDefaultArt },

                --The rollable d10 seeded a new dice set (fired up from the
                --cage via FireEventOnParents): cross-fade the banner art to
                --that set's banner, when it has one and it isn't already up.
                storeBannerSetSeeded = function(element, item)
                    local art = g_storeBannerArtByAsset[tostring(item.assetid)] or g_storeBannerDefaultArt
                    if art == element.data.bannerArt then
                        return
                    end
                    element.data.bannerArt = art
                    element:FireEventTree("storeBannerArtChanged", art)
                end,

                borderWidth = 1.5,
                borderColor = "white",


                width = g_selectionBannerWidth,
                height = g_selectionBannerHeight,

                floating = true,

                halign = "center",
                valign = "bottom",
                bmargin = 60,

                multimonitor = { "dev:storepreview" },
                monitor = function(element)
                    element:SetClass("collapsed", not g_devStorePreviewSetting:Get())
                end,

                --The whole banner is a button into the store. A click anywhere on
                --it (background, the STORE button, or a tap on the showcase dice)
                --bubbles here and opens the shop, hosted on the titlescreen root
                --the same way CodexTitleBar's OpenShopScreen does at the title
                --screen. Dragging a showcase die fires beginDrag/drag (never
                --click), so spinning the dice does NOT open the store. The
                --rollable d10 on the right has its own click handler (a click
                --rolls it), so it never opens the store either.
                hover = function(element)
                    audio.FireSoundEvent("Mouse.Hover")
                end,

                click = function(element)
                    track("shopTitleBannerClick", {})
                    audio.FireSoundEvent("Mouse.Click")
                    titlescreen:AddChild(CreateShopScreen{ titlescreen = titlescreen, inventory = false })
                end,

                styles = {

                    {
                        classes = { 'king-panel' },
                        hidden = 1,
                    },

                    {
                        classes = { 'parent:selection-screen', 'king-panel' },
                        hidden = 0,
                    },

                    --Hover zoom, mirroring the Director/Player cards: inset the
                    --bgimage UVs a touch so the art scales up to fill, eased over
                    --a short transition. Only the background art zooms; the dice,
                    --gradient and border are unaffected.
                    {
                        selectors = { "storeBannerZoom", "hover" },
                        transitionTime = 0.12,
                        imageRect = { x1 = 0.02, x2 = 0.98, y1 = 0.02, y2 = 0.98 },
                    },
                },

                --Cross-fade art layer: a full-banner floating panel sitting
                --over the banner's own bgimage and under everything else on
                --the banner (first child = drawn behind all later siblings).
                --On a set change the incoming art loads here at opacity 0
                --(invisible panels still load their bgimage, so this doubles
                --as a preload), fades in over the outgoing art, and once
                --fully opaque is committed to the banner's own bgimage --
                --identical pixels, so releasing this layer afterwards causes
                --no visible change regardless of how the opacity eases back.
                gui.Panel{
                    classes = { "storeBannerFadeLayer" },
                    floating = true,
                    interactable = false,
                    width = "100%",
                    height = "100%",
                    halign = "center",
                    valign = "center",
                    bgimage = g_storeBannerDefaultArt,
                    bgcolor = "white",
                    gradient = g_storeBannerGradient,

                    --fadeSeq stamps each art change; the scheduled fade
                    --begin/commit events carry the stamp and bail when a
                    --newer change has superseded them, so a stale commit can
                    --never overwrite a newer fade's art.
                    data = { art = nil, fadeSeq = 0 },

                    styles = {
                        { selectors = { "storeBannerFadeLayer" }, opacity = 0 },
                        {
                            selectors = { "storeBannerFadeLayer", "bannerFadeIn" },
                            opacity = 1,
                            transitionTime = 0.6,
                        },
                        --Track the banner's hover zoom (storeBannerZoom above)
                        --so the two art layers stay pixel-aligned when a fade
                        --crosses a hover.
                        {
                            selectors = { "storeBannerFadeLayer", "parent:hover" },
                            transitionTime = 0.12,
                            imageRect = { x1 = 0.02, x2 = 0.98, y1 = 0.02, y2 = 0.98 },
                        },
                    },

                    storeBannerArtChanged = function(element, art)
                        element.data.art = art
                        element.data.fadeSeq = element.data.fadeSeq + 1
                        --Snap invisible and swap in the new art while
                        --transparent, then start the fade a beat later so the
                        --texture has a few frames to decode (a same-frame
                        --swap-and-show can flash stale white).
                        element:SetClass("bannerFadeIn", false)
                        element.bgimage = art
                        element:ScheduleEvent("bannerFadeBegin", 0.1, element.data.fadeSeq)
                    end,

                    bannerFadeBegin = function(element, seq)
                        if seq ~= element.data.fadeSeq then
                            return
                        end
                        element:SetClass("bannerFadeIn", true)
                        --Commit shortly after the 0.6s opacity transition
                        --has landed.
                        element:ScheduleEvent("bannerFadeCommit", 0.7, seq)
                    end,

                    bannerFadeCommit = function(element, seq)
                        if seq ~= element.data.fadeSeq then
                            return
                        end
                        --Fully opaque: commit the art to the banner's own
                        --bgimage (already decoded here, so no load flash)
                        --and release this layer back to invisible.
                        local banner = element.parent
                        if banner ~= nil and banner.valid then
                            banner.bgimage = element.data.art
                        end
                        element:SetClass("bannerFadeIn", false)
                    end,
                },

                gui.Panel{
                    halign = "left",
                    width = "30%",
                    height = "100%",

                    flow = "vertical",
                    --Mini dice showcase: two independent spinning preview dice
                    --arranged as an arc -- Noxa forward and centered (the larger
                    --die), Sea of Stars smaller, up-and-right, and drawn behind
                    --it. Both idle-spin and can be grabbed to spin (see
                    --MakeStoreBannerDie). The container is transparent; the
                    --floating dice are allowed to sit within it.
                    gui.Panel{
                        width = "100%",
                        height = "60%",
                        valign = "center",
                        clip = false,

                        --Back die first so it draws behind the front die.
                        --Tucked in close to the larger front die and a little
                        --lower, so the two overlap and the front die reads as
                        --sitting in front of it.
                        MakeStoreBannerDie{
                            assetid = g_storeBannerDiceSeaOfStars,
                            size = 123,
                            halign = "center",
                            valign = "center",
                            x = 42,
                            y = -13,
                        },
                        MakeStoreBannerDie{
                            assetid = g_storeBannerDiceNoxa,
                            size = 173,
                            halign = "center",
                            valign = "center",
                            x = -27,
                            y = 15,
                        },
                    },
                    gui.Label{
                        valign = "bottom",
                        halign = "center",
                        width = "auto",
                        height = "auto",
                        fontSize = 24,
                        fontFace = "book",
                        text = "5 NEW DICE!",
                        bmargin = 8,
                    },
                },

                --Store button: a labelled affordance styled like the
                --DIRECTOR/PLAYER card buttons (panels/titlescreen/button.png at
                --the same 0.6 scale). It has no click of its own -- a click here
                --bubbles up to the banner's click above (which opens the store),
                --so there is a single open-store handler and no double-open.
                gui.Panel{
                    floating = true,
                    bgimage = "panels/titlescreen/button.png",
                    bgcolor = "white",
                    height = 131 * 0.6,
                    width = 632 * 0.6,
                    halign = "center",
                    valign = "bottom",
                    hmargin = 28,
                    bmargin = 0,

                    gui.Label{
                        text = "STORE",
                        fontSize = 30,
                        fontFace = "newzald",
                        color = "white",
                        halign = "center",
                        valign = "center",
                        textAlignment = "center",
                        y = 5,
                        width = "auto",
                        interactable = false,
                    },
                },

                --Rollable d10 in the black gradient area on the right: a real
                --3D die resting on an invisible dice-preview cage. Starts in a
                --random on-sale dice set; click or drag throws a full-screen
                --roll, and each roll rotates to the next live-store set.
                MakeStoreBannerRollDie(),

            },

            gui.Panel {


                classes = { 'king-panel' },

                flow = "vertical",

                width = 1900,
                height = 980,

                valign = "center",
                halign = "center",
                floating = true,
                styles = {

                    {
                        classes = { 'king-panel' },
                        hidden = 1,
                    },

                    {
                        classes = { 'parent:games-screen', 'king-panel' },
                        hidden = 0,
                    },


                },

                gui.Panel {

                    width = "100%",
                    height = "8%",


                },


                gui.Panel {

                    bgimage = true,
                    bgcolor = "clear",
                    width = "100%",
                    height = "88%",
                    halign = "center",

                    flow = "horizontal",

                    (function()
                        -- Heroes column extras layered on top of the base
                        -- theme via MergeStyles. Mirrors the Campaigns column
                        -- pattern: shared header-icon rule + per-card VIEW
                        -- button rules + banner rules. Re-themes live via
                        -- the column's OnThemeChanged below.
                        local m_heroesExtras = {
                            -- + icon in the HEROES header strip (mirror of
                            -- Campaigns' headerActionIcon rule; we redefine
                            -- here because we're a separate cascade root).
                            {
                                selectors = { "panel", "headerActionIcon" },
                                bgcolor = "@fg",
                            },
                            {
                                selectors = { "panel", "headerActionIcon", "parent:hover" },
                                bgcolor = "@fgInverse",
                            },
                            -- VIEW button on each hero card: same scheme as
                            -- PLAY CAMPAIGN -- button.png (narrow variant)
                            -- multiplied by @fg, label in @fgStrong for
                            -- contrast against the dark button center.
                            {
                                selectors = { "panel", "viewHeroButton" },
                                bgcolor = "@fg",
                            },
                            {
                                selectors = { "label", "viewHeroLabel" },
                                color = "@fgStrong",
                            },
                            -- "Playing in Campaign" banner: dark themed
                            -- surface with a strong title and accent-colored
                            -- campaign name. @info reads warm-gold in default
                            -- (close to the legacy #bc9b7b) and adapts.
                            {
                                selectors = { "panel", "playingInCampaignBanner" },
                                bgcolor = "@bgAlt",
                            },
                            {
                                selectors = { "label", "playingInCampaignBannerTitle" },
                                color = "@fgStrong",
                            },
                            {
                                selectors = { "label", "playingInCampaignBannerName" },
                                color = "@info",
                            },
                        }

                        return gui.Panel {
                        classes = { "hideOnDirector" },

                        -- Scoped ThemeEngine cascade for the Heroes column,
                        -- mirrors the Campaigns column. Catches the HEROES
                        -- header strip and the 8 hero cards below.
                        styles = ThemeEngine.MergeStyles(m_heroesExtras),

                        bgimage = true,
                        bgcolor = "clear",
                        width = "44%",
                        height = "100%",
                        halign = "center",

                        flow = "vertical",

                        -- Live re-theming: MergeStyles is a one-shot
                        -- snapshot; subscribe so the column recolors when
                        -- the active theme/scheme changes.
                        create = function(element)
                            ThemeEngine.OnThemeChanged(mod, function()
                                if element.valid then
                                    element.styles = ThemeEngine.MergeStyles(m_heroesExtras)
                                end
                            end)
                        end,

                        gui.Panel {

                            width = "100%",
                            height = "15%",

                            flow = "horizontal",

                            gui.Label {

                                text = "HEROES",
                                fontSize = 70,
                                fontFace = "book",

                                halign = "center",
                                valign = "center",
                                textAlignment = "center",

                                width = "85%",
                                height = "100%",

                                flow = "horizontal",

                                --add hero button.
                                gui.Button {
                                    width = 48,
                                    height = 48,
                                    halign = "right",
                                    valign = "center",
                                    beveledcorners = true,
                                    cornerRadius = 8,
                                    y = -10,

                                    hover = function(element)
                                        gui.Tooltip("Create a Hero")(element)
                                    end,

                                    monitorGame = "/characters",
                                    refreshGame = function(element)
                                        local chars = table.values(dmhub.GetAllCharacters())
                                        element:SetClass("hidden", #chars >= 8)
                                    end,

                                    press = CreateHero,

                                    gui.Panel {
                                        -- See Campaigns column: headerActionIcon
                                        -- class supplies @fg rest / @fgInverse
                                        -- hover via the Heroes column's
                                        -- MergeStyles extras.
                                        classes = { "headerActionIcon" },
                                        width = "80%",
                                        height = "80%",
                                        halign = "center",
                                        valign = "center",
                                        bgimage = "ui-icons/Plus.png",
                                    },

                                },

                                --FS import button.
                                gui.Button {
                                    width = 48,
                                    height = 48,
                                    halign = "right",
                                    valign = "center",
                                    beveledcorners = true,
                                    cornerRadius = 8,
                                    text = "FS",
                                    fontSize = 30,
                                    y = -10,

                                    hover = function(element)
                                        gui.Tooltip("Import a Hero from Forge Steel")(element)
                                    end,

                                    monitorGame = "/characters",
                                    refreshGame = function(element)
                                        local chars = table.values(dmhub.GetAllCharacters())
                                        element:SetClass("hidden", #chars >= 8)
                                    end,

                                    press = ImportForgeSteel,
                                },
                            }
                        },


                        gui.Panel {
                            flow = "horizontal",
                            wrap = true,
                            width = "100%",
                            height = "auto",

                            styles = {
                                {
                                    selectors = { "parentHover" },
                                    hidden = 1,
                                },
                                {
                                    selectors = { "parent:hover", "parentHover" },
                                    hidden = 0,
                                },
                            },

                            lobbyGameLoaded = function(element)
                                element.monitorGame = "/characters"
                                element:FireEvent("refreshGame")
                            end,

                            refreshGame = function(element)
                                local chars = table.values(dmhub.GetAllCharacters())
                                table.sort(chars, function(a, b)
                                    local ca = rawget(a.properties, "ctime") or 0
                                    local cb = rawget(b.properties, "ctime") or 0
                                    if type(ca) ~= "number" or type(cb) ~= "number" then
                                        printf("ERROR ctime sort: a.charid=%s ca=%s(%s) b.charid=%s cb=%s(%s)", tostring(a.charid), tostring(ca), type(ca), tostring(b.charid), tostring(cb), type(cb))
                                        return false
                                    end
                                    return ca < cb
                                end)
                                local games = lobby.games
                                element:FireEventTree("characters", chars, games)
                            end,

                            beginLoading = function(element)
                                element.monitorGame = nil
                            end,

                            returnFromGame = function(element)
                                --start monitoring, but give it a second to allow the game to exit.
                                element:ScheduleEvent("startMonitoring", 1)
                            end,

                            startMonitoring = function(element)
                                lobby:EnterLobbyGame(function()
                                    print("LOBBYGAME:: ENTERED!")
                                    g_titlescreen:FireEventTree("returnFromGameComplete")
                                end)

                                element.monitorGame = "/characters"
                            end,

                            refreshLobby = function(element)
                                element:FireEvent("refreshGame")
                            end,

                            create = function(element)
                            end,


                            MakeHeroPanel(1),
                            MakeHeroPanel(2),
                            MakeHeroPanel(3),
                            MakeHeroPanel(4),
                            MakeHeroPanel(5),
                            MakeHeroPanel(6),
                            MakeHeroPanel(7),
                            MakeHeroPanel(8),
                        },
                    }
                    end)(),

                    gui.Panel {

                        bgimage = true,
                        bgcolor = "clear",
                        width = "6%",
                        height = "100%",
                        halign = "center",

                        flow = "vertical",


                    },

                    (function()
                        -- Column-scoped extras layered on top of the base
                        -- theme via MergeStyles. The gameid invite-code pill
                        -- in MakeGamePanel adopts these (4 instances; class
                        -- routing lets them re-theme live via the column's
                        -- OnThemeChanged below rather than each pill carrying
                        -- its own subscription).
                        local m_campaignsExtras = {
                            -- Pill background: @surfaceLinear matches the
                            -- framedPanel sheen (closest theme analogue to the
                            -- legacy rich-black gradient). @border for the
                            -- frame, @fg for the text.
                            {
                                selectors = { "label", "gameIdPill" },
                                color = "@fg",
                                borderColor = "@border",
                                gradient = "@surfaceLinear",
                            },
                            -- App icon inside the pill: tinted to @fg so it
                            -- matches the pill text.
                            {
                                selectors = { "panel", "gameIdPillIcon" },
                                bgcolor = "@fg",
                            },
                            -- + / search icons in the CAMPAIGNS header.
                            -- These need an explicit class so the rule beats
                            -- the base {panel} rule (DefaultStyles.lua:223)
                            -- on specificity -- otherwise the icon paints
                            -- @bg (same as the button background) and reads
                            -- invisible at rest.
                            {
                                selectors = { "panel", "headerActionIcon" },
                                bgcolor = "@fg",
                            },
                            {
                                selectors = { "panel", "headerActionIcon", "parent:hover" },
                                bgcolor = "@fgInverse",
                            },
                            -- PLAY CAMPAIGN button on each game card: the
                            -- panels/titlescreen/button.png texture is
                            -- multiplied by @fg so it tints with the active
                            -- scheme. The button.png has a dark center
                            -- (designed for light text), so the label sits
                            -- on top in @fgStrong (the lightest foreground
                            -- token) -- @fgInverse would be near-black-on-
                            -- dark and disappear. Hover/press brightness
                            -- multipliers stay on the panel itself.
                            {
                                selectors = { "panel", "playCampaignButton" },
                                bgcolor = "@fg",
                            },
                            {
                                selectors = { "label", "playCampaignLabel" },
                                color = "@fgStrong",
                            },
                        }

                        return gui.Panel {

                        -- Scoped ThemeEngine cascade for the Campaigns
                        -- column: themes the CAMPAIGNS header strip and the
                        -- 4 game cards (MakeGamePanel) below. The
                        -- titlescreen root above us is still legacy
                        -- Styles.Default; this root catches everything in
                        -- the column without altering anything else.
                        styles = ThemeEngine.MergeStyles(m_campaignsExtras),

                        width = "44%",
                        height = "100%",
                        halign = "center",

                        flow = "vertical",

                        -- Live re-theming: MergeStyles is a one-shot
                        -- snapshot; subscribe so the column recolors when
                        -- the active theme/scheme changes. Guard with
                        -- .valid so the callback no-ops if the column has
                        -- been destroyed.
                        create = function(element)
                            element:FireEvent("think")
                            ThemeEngine.OnThemeChanged(mod, function()
                                if element.valid then
                                    element.styles = ThemeEngine.MergeStyles(m_campaignsExtras)
                                end
                            end)
                        end,

                        data = {
                            updateid = -1,
                        },

                        -- Report the games on the current page to the engine so
                        -- it keeps a live metadata subscription open only for
                        -- what's visible (the other games were pulled once at
                        -- startup). Fires on every list rebuild (refreshLobby)
                        -- and page change, since both broadcast refreshGames.
                        refreshGames = function(element, games, baseIndex)
                            games = games or {}
                            baseIndex = baseIndex or 0
                            local visible = {}
                            for i = 1, 4 do
                                local g = games[baseIndex + i]
                                if g ~= nil then
                                    visible[#visible + 1] = g.gameid
                                end
                            end
                            lobby:SetVisibleGames(visible)
                        end,

                        refreshLobby = function(element)
                            local orderedGames = {}
                            local directorMode = DirectorMode()

                            print("REFRESH WITH DIRECTOR =", directorMode)

                            for i, game in ipairs(lobby.games or {}) do
                                local owner = (game.owner == dmhub.loginUserid)
                                if owner == directorMode and (m_currentSearch == nil or game:MatchesSearch(m_currentSearch)) then
                                    orderedGames[#orderedGames + 1] = game
                                end
                            end

                            m_games = orderedGames
                            element.root:FireEventTree("refreshGames", orderedGames, PageBaseIndex())
                        end,

                        gui.Panel {

                            width = "100%",
                            height = "15%",

                            flow = "horizontal",

                            gui.Label {

                                text = "CAMPAIGNS",
                                fontSize = 70,
                                fontFace = "book",

                                halign = "center",
                                valign = "center",
                                textAlignment = "center",

                                width = "85%",
                                height = "100%",

                                flow = "horizontal",

                                --add game button.
                                gui.Button {
                                    width = 48,
                                    height = 48,
                                    halign = "right",
                                    valign = "center",
                                    beveledcorners = true,
                                    cornerRadius = 8,
                                    y = -10,

                                    press = function(element)
                                        if #lobby.games >= MaxGamesAllowed() then
                                            TooManyGamesDialog(element)

                                            return
                                        end

                                        element.root:FireEventTree("titlescreenCreateGame")
                                    end,

                                    gui.Panel {
                                        -- headerActionIcon class supplies
                                        -- @fg rest / @fgInverse hover via
                                        -- the Campaigns column's MergeStyles
                                        -- extras (class selector beats the
                                        -- base {panel} rule on specificity).
                                        classes = { "headerActionIcon" },
                                        width = "80%",
                                        height = "80%",
                                        halign = "center",
                                        valign = "center",
                                        bgimage = "ui-icons/Plus.png",
                                    },

                                },

                                --search button.
                                gui.Button {
                                    width = 48,
                                    height = 48,
                                    halign = "right",
                                    valign = "center",
                                    beveledcorners = true,
                                    cornerRadius = 8,
                                    y = -10,

                                    press = function(element)
                                        print("LOBBYGAME:: ENTERING...")
                                        TopBar.FocusSearchBar()
                                        --lobby:EnterLobbyGame(function()
                                        --    print("LOBBYGAME:: ENTERED!!")
                                        --end)
                                    end,

                                    gui.Panel {
                                        -- See the + button above:
                                        -- headerActionIcon class supplies
                                        -- @fg rest / @fgInverse hover via
                                        -- the Campaigns column's
                                        -- MergeStyles extras.
                                        classes = { "headerActionIcon" },
                                        width = "80%",
                                        height = "80%",
                                        halign = "center",
                                        valign = "center",
                                        bgimage = "icons/icon_tool/icon_tool_42.png",
                                    },

                                },
                            }


                        },

                        MakeGamePanel(1),
                        MakeGamePanel(2),
                        MakeGamePanel(3),
                        MakeGamePanel(4),
                    }
                    end)(),

                    --paging panel
                    gui.Panel {
                        styles = ThemeEngine.GetStyles(),
                        classes = {"bgAlt"},
                        floating = true,
                        minWidth = 100,
                        width = "auto",
                        height = 60,
                        flow = "horizontal",
                        halign = "right",
                        valign = "bottom",
                        rmargin = 20,
                        y = 68,
                        opacity = 0.8,
                        refreshGames = function(element, games, baseIndex)
                            if GetNumPages() <= 1 then
                                element:SetClass("hidden", true)
                            else
                                element:SetClass("hidden", false)
                            end
                        end,

                        gui.Button {
                            classes = {"pagingArrow", "sizeL"},
                            valign = "center",
                            halign = "center",
                            refreshGames = function(element, games, baseIndex)
                                local numPages = GetNumPages()
                                local npage = clamp(round(g_gamePageSetting:Get()), 1, numPages)
                                print("REFRESH::", npage, "/", numPages)
                                element:SetClass("hidden", npage <= 1)
                            end,
                            press = function(element)
                                g_gamePageSetting:Set(g_gamePageSetting:Get() - 1)
                                element.root:FireEventTree("refreshGames", m_games, PageBaseIndex())
                            end,
                        },

                        gui.Label {
                            textAlignment = "center",
                            width = "auto",
                            minWidth = 60,
                            height = 50,
                            fontSize = 20,
                            halign = "center",
                            valign = "center",
                            refreshGames = function(element)
                                local numPages = GetNumPages()
                                local npage = clamp(round(g_gamePageSetting:Get()), 1, numPages)
                                print("REFRESH::", npage, "/", numPages)
                                element.text = string.format("Page\n%d/%d", npage, numPages)
                            end,
                        },

                        gui.Button {
                            classes = {"pagingArrow", "right", "sizeL"},
                            halign = "center",
                            valign = "center",
                            refreshGames = function(element)
                                local numPages = GetNumPages()
                                local npage = clamp(round(g_gamePageSetting:Get()), 1, numPages)
                                element:SetClass("hidden", npage >= numPages)
                            end,
                            press = function(element)
                                g_gamePageSetting:Set(g_gamePageSetting:Get() + 1)
                                element.root:FireEventTree("refreshGames", m_games, PageBaseIndex())
                            end,
                        },
                    },

                },
            },

            --[[hacky debug log panel
            gui.Panel {
                bgimage = true,
                bgcolor = "black",
                floating = true,
                vmargin = 32,
                width = 500,
                height = 300,
                vscroll = true,
                valign = "bottom",
                gui.Label {
                    halign = "left",
                    valign = "top",
                    width = 500,
                    height = "auto",
                    fontSize = 14,
                    thinkTime = 0.1,
                    think = function(element)
                        local log = dmhub.debugLog
                        if #log == element.data.nlog then
                            return
                        end

                        element.data.nlog = #log

                        local startIndex = 1
                        if #log > 100 then
                            startIndex = #log - 100
                        end

                        local res = ""
                        for i = startIndex, #log do
                            local s = log[i]
                            if type(s) == "table" then
                                s = s.message
                            end
                            res = res .. s .. "\n"
                        end
                        element.text = res
                    end,
                },
            }
            --]]
        },
    }

    local initialScreen
    initialScreen = gui.Panel {
        bgimage = "panels/backgrounds/delian-tomb-bg.png",
        nostretch = true,
        floating = true,

        autosizeimage = true,
        width = 1.05 * ScaleDimensionsToFill(1920),
        height = 1.05 * ScaleDimensionsToFill(1080),

        screenResized = function(element)
            element.selfStyle.width = 1.05 * (1920 / dmhub.uiVerticalScale)
            element.selfStyle.height = "56.25% width"
        end,

        lobbyGameLoaded = function(element)
            dmhub.Schedule(0.7, function()
                if initialScreen ~= nil and initialScreen.valid then
                    initialScreen:SetClassTree("destroying", true)
                end
            end)


            dmhub.Schedule(1, function()
                if initialScreen ~= nil and initialScreen.valid then
                    initialScreen:DestroySelf()
                    initialScreen = nil
                end
            end)
        end,


        valign = "center",
        halign = "center",
        --saturation = 0.5,
        bgcolor = '#888888ff',
        styles = {
            {
                selectors = { "destroying" },
                transitionTime = 0.3,
                opacity = 0,
            }
        }
    }

    titlescreen:AddChild(initialScreen)

    local progressDice = gui.ProgressDice{
        styles = {
            {
                selectors = {"loaded", "hover"},
                brightness = 1.2,
            },
            {
                selectors = {"fade"},
                transitionTime = 0.2,
                opacity = 0,
                uiscale = 2,
            },

        },
        floating = true,
        width = 128,
        height = 128,
        halign = "center",
        valign = "center",
        progress = 0.0,
        thinkTime = 0.01,
        think = function(element)
            local progress = dmhub.gameLoadingProgress or 0
            element:FireEventTree("progress", progress)
            if progress >= 1 then
                if element.data.loadingFinished == nil then
                    element.data.loadingFinished = element.aliveTime
                end

                -- Any-key-to-continue: require one frame of no keys depressed
                -- after loading finishes, then fire press on next key down.
                if not element.data.triggered then
                    local key = dmhub.DetectBindableKeystroke()
                    if element.data.keyReleased then
                        if key ~= nil then
                            element:FireEvent("press")
                        end
                    elseif key == nil then
                        element.data.keyReleased = true
                    end
                end

                local t = element.aliveTime - element.data.loadingFinished
                element:SetClass("loaded", true)
                if element:HasClass("hover") then
                    element.selfStyle.scale = 1.05
                else
                    element.selfStyle.scale = 1 + math.sin(t * 10) * 0.05
                end
            end
        end,

        titlescreenClick = function(element)
            element:FireEvent("press")
        end,

        press = function(element)
            if (dmhub.gameLoadingProgress or 0) >= 1 and not element.data.triggered then
                element.data.triggered = true
                SetTitlescreenState("selection-screen")
                element:SetClassTree("fade", true)
                if element.data.pressAnyKeyLabel ~= nil then
                    element.data.pressAnyKeyLabel:SetClass("fade", true)
                    element.data.pressAnyKeyLabel.thinkTime = nil
                end
                element:ScheduleEvent("destroySelf", 0.2)
                element.thinkTime = nil
                audio.FireSoundEvent("Mouse.Click")
            end
        end,

        hover = function ()
            audio.FireSoundEvent("Mouse.Hover")
        end,

        destroySelf = function(element)
            element:DestroySelf()
        end,
    }

    titlescreen:AddChild(progressDice)

    local pressAnyKeyLabel = gui.Label{
        bgimage = true,
        bgcolor = "white",
        gradient = gui.Gradient{
            point_a = {x = 0, y = 0},
            point_b = {x = 1, y = 0},
            stops = {
                {
                    position = 0,
                    color = "#00000000",
                },
                {
                    position = 0.2,
                    color = "#000000DD",
                },
                {
                    position = 0.8,
                    color = "#000000DD",
                },
                {
                    position = 1,
                    color = "#00000000",
                },
            }

        },
        hpad = 160,
        vpad = 40,
        floating = true,
        text = "PRESS ANY KEY",
        fontFace = "Book",
        fontSize = 60,
        color = "white",
        halign = "center",
        valign = "bottom",
        vmargin = 80,
        width = "auto",
        height = "auto",
        interactable = false,
        styles = {
            {
                opacity = 0,
            },
            {
                selectors = {"loaded"},
                transitionTime = 0.5,
                opacity = 1,
            },
            {
                selectors = {"fade"},
                transitionTime = 0.2,
                opacity = 0,
                hidden = 1,
            },
        },
        thinkTime = 0.1,
        think = function(element)
            if (dmhub.gameLoadingProgress or 0) >= 1 then
                element:SetClass("loaded", true)
            end
        end,
    }

    titlescreen:AddChild(pressAnyKeyLabel)

    -- Fade the label when the user advances past the titlescreen.
    progressDice.data.pressAnyKeyLabel = pressAnyKeyLabel

    dialog.sheet = titlescreen
    titlescreen.data.dialog = dialog
    g_titlescreen = titlescreen
    _G.CodexTitlescreenRoot = titlescreen
end

local ShowTermsOfService = function(titlescreen, args)
    local dialog = titlescreen.data.dialog
	args = args or {}
	local forceAccept = args.forceAccept

	local termsDialog
	termsDialog = gui.Panel{
        id = "termsOfService",
        floating = true,
		halign = "center",
		valign = "center",
		width = dialog.width,
		height = dialog.height,

		styles = {
            Styles.Default,
			Styles.Panel,
		},
		classes = {"framedPanel"},

		flow = "vertical",

		gui.Label{
			color = Styles.textColor,
			fontSize = 28,
			width = "auto",
			height = "auto",
			halign = "center",
			valign = "center",
            text = "Terms of Service",
			--text = cond(forceAccept, "We've updated our Terms of Use...", "Draw Steel Codex Terms of Service"),
		},

		gui.Panel{
			width = "80%",
			height = "60%",
			vscroll = true,
			halign = "center",
			valign = "center",
			gui.Label{
				textAlignment = "topleft",
				markdown = true,
				fontSize = 16,
				width = "100%-16",
				height = "auto",
				halign = "left",
				valign = "top",
				text = termsAndOngoingEffectsText,
			},
		},

		gui.Panel{
			halign = "center",
			valign = "center",
			flow = "horizontal",
			width = 600,

			gui.Button{
				classes = {"loginButton", cond(not forceAccept, "collapsed")},
				text = "Decline & Exit",
                halign = "center",
                fontSize = 24,
                width = 240,
                height = 30,
				click = function(element)
					termsDialog:DestroySelf()
					dmhub.QuitApplication()
				end,
			},

			gui.Button{
				classes = {"loginButton"},
				text = cond(forceAccept, "I Agree", "Close"),
                halign = "center",
                fontSize = 24,
                width = 240,
                height = 30,
				click = function(element)
					termsDialog:DestroySelf()
					if args.onaccept then
						args.onaccept()
					end
				end,
			},

		}
	}

	titlescreen:AddChild(termsDialog)
end


if rawget(_G, "TitlescreenVersion") ~= 2 then
    TitlescreenVersion = 2

    dmhub.debugLog = {}


    print("LOBBYGAME:: ENTERING...")
    dmhub.RecreateTitlescreen()

    if dmhub.termsOfServiceUpToDate then
        lobby:EnterLobbyGame(function()
            dmhub.TermsOfServiceAccepted()
            g_titlescreen:FireEventTree("lobbyGameLoaded")
        end)
    else
        ShowTermsOfService(g_titlescreen, {
            forceAccept = true,
            onaccept = function()
                lobby:EnterLobbyGame(function()
                    dmhub.TermsOfServiceAccepted()
                    g_titlescreen:FireEventTree("lobbyGameLoaded")
                end)
            end,
        })
    end

end

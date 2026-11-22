local mod = dmhub.GetModLoading()

--Loyalty collars: the explosive iron collars every war dog wears.
--
--A creature with the Loyalty Collar modifier (put on the war dogs' Loyalty Collar traits)
--shows the collar as its token frame, with a green light blinking once a second. While a
--minion squad owes deaths (its red death skulls are up) every collar in the squad blinks
--orange. While the collar is about to go off (the creature is at 0 Stamina, or a minion whose
--death has been confirmed) the light blinks red, fast. The trait's triggered ability carries a Loyalty
--Collar Explosion behavior that blows the collar up on every client: an explosion on the
--token, the token hidden inside it, and char marks left on the floor.
--
--The collar is drawn with token.frameOverride, which is display only: each client works it
--out from the creature's modifiers, and the token's saved appearance is never touched.
--The Condemned campaign (CondemnedCode/Condemned.lua) puts the same collar on heroes by hand.

local FRAME_ID = "loyalty-collar"
--textures from tools/token-frames/make_iron_collar_frame.py; the image records are in the
--data repo (data/images), so every game has them.
local COLLAR_ALBEDO = "87106cdd-1392-457d-a135-d8c9113905f2"
local COLLAR_NORMAL = "c3b2c430-6e63-4ec7-bdeb-afa6281c87ed"
local COLLAR_ROUGHNESS = "b5337890-62b8-4319-a75f-bc50cb1ffb1f"
local COLLAR_MATCAP = "5c910265-afc5-4c70-bc33-b857a1382c2a"
--a white glow sprite, tinted and blinked over the collar's light.
local LED_GLOW = "f828afd1-8271-454d-8a84-89c645e30844"

local REMOTE_EVENT = "loyaltyCollarExplosion"

--sound events defined in Draw Steel Audio/AudioMain.lua.
local SOUND_EXPLOSION = "Ability.Explosion_Medium_Short"
local EXPLOSION_VOLUME = 1.5
local EXPLOSION_EFFECT = "Explosion 1"
--the effect's scale on a 1x1 creature; it grows with the creature's width in squares.
local EXPLOSION_SCALE = 1.25
--seconds from the explosion starting to the fireball covering the token, when it is hidden.
local VANISH_DELAY = 0.13

--the green light: one short blink a second.
local BLINK_PERIOD = 1.0
local BLINK_ON_TIME = 0.15
--the orange light of a squad that owes deaths: quicker blinks.
local ALERT_PERIOD = 0.5
local ALERT_ON_TIME = 0.18
--the red light of a collar about to go off: fast, hard blinks.
local ARMED_PERIOD = 0.25
local ARMED_ON_TIME = 0.12

--the light's centre as a fraction of the frame texture (+y up), printed by the texture
--generator, scaled by the frame's footprint in token sheet units.
local FRAME_SIZE = 98
local LED_FX = -0.3223
local LED_FY = -0.3223
local LED_GLOW_SIZE = 11
--a lit light is near-white at its centre with the colour in the glow around it.
local LED_CORE_FRACTION = 0.45
local LED_BRIGHTNESS = 2.5
local LED_GREEN = "#00ff20"
local LED_GREEN_CORE = "#e0ffe0"
local LED_ORANGE = "#ff7000"
local LED_ORANGE_CORE = "#ffe4c4"
local LED_RED = "#ff0000"
local LED_RED_CORE = "#ffd8cc"

--How the light looks in each state the collar can be in.
local g_ledStates = {
    normal = { color = LED_GREEN, core = LED_GREEN_CORE, period = BLINK_PERIOD, on = BLINK_ON_TIME },
    alert = { color = LED_ORANGE, core = LED_ORANGE_CORE, period = ALERT_PERIOD, on = ALERT_ON_TIME },
    armed = { color = LED_RED, core = LED_RED_CORE, period = ARMED_PERIOD, on = ARMED_ON_TIME },
}

TokenFrames.RegisterDefinition{
    id = FRAME_ID,
    name = "Loyalty Collar",
    albedo = COLLAR_ALBEDO,
    normal = COLLAR_NORMAL,
    roughness = COLLAR_ROUGHNESS,
    matcap = COLLAR_MATCAP,
    params = {
        normalStrength = 1.0,
        specStrength = 1.6,
        fresnelPower = 4.0,
        ambient = 0.45,
        matcapStrength = 1.0,
        rimStrength = 0.6,
        lightFollowsTimeOfDay = 0,
        lightDir = { x = -0.6, y = 0.7, z = 0.35 },
        sheenColor = "#9a9a9a",
    },
}

--------------------------------------------------------------------------------
-- The modifier
--------------------------------------------------------------------------------

CharacterModifier.RegisterType("loyaltycollar", "Loyalty Collar")

--No options: the modifier only marks its bearer as wearing a collar.
CharacterModifier.TypeInfo.loyaltycollar = {}

--- True if this creature wears a loyalty collar (has an active Loyalty Collar modifier).
--- @return boolean
function creature:HasLoyaltyCollar()
    for _, entry in ipairs(self:GetActiveModifiers()) do
        if entry.mod.behavior == "loyaltycollar" then
            return true
        end
    end
    return false
end

--True if abilityGuid is one of this creature's triggered abilities that explodes its collar.
--- @param c creature
--- @param abilityGuid false|string
--- @return boolean
local function IsCollarTrigger(c, abilityGuid)
    if not abilityGuid then
        return false
    end
    for _, entry in ipairs(c:GetActiveModifiers()) do
        local ability = entry.mod:try_get("triggeredAbility")
        if ability ~= nil and ability.guid == abilityGuid then
            for _, behavior in ipairs(ability.behaviors or {}) do
                if behavior.typeName == "ActivatedAbilityLoyaltyCollarExplosionBehavior" then
                    return true
                end
            end
        end
    end
    return false
end

--True while this creature's collar is about to go off. A minion's squad pool can still be
--above 0 when one of them dies, so a minion counts once its death is confirmed or its
--collar's death trigger is waiting to be used.
--- @param c creature
--- @return boolean
local function CollarArmed(c)
    if c:CurrentHitpoints() <= 0 then
        return true
    end
    if not c.minion then
        return false
    end
    if c.minionDead or c:try_get("_tmp_minionDeathPending") ~= nil then
        return true
    end
    local triggers = c:GetAvailableTriggers(true)
    if triggers ~= nil then
        for _, trigger in pairs(triggers) do
            if (not trigger.triggered) and IsCollarTrigger(c, trigger.abilityGuid) then
                return true
            end
        end
    end
    return false
end

--True while this minion's squad owes deaths: some member shows the red death skull (or
--would, but for an offered trigger). Every collar in the squad warns until they are taken.
--- @param c creature
--- @return boolean
local function SquadDeathOwed(c)
    if not c.minion or not c:has_key("_tmp_minionSquad") then
        return false
    end
    for _, tok in ipairs(c._tmp_minionSquad.tokens or {}) do
        if tok.valid and tok.properties ~= nil and not tok.properties.minionDead and TokenHud.MinionDeathOwed(tok) then
            return true
        end
    end
    return false
end

--Which light the collar shows: "armed", "alert" or "normal".
--- @param c creature
--- @return string
local function CollarState(c)
    if CollarArmed(c) then
        return "armed"
    end
    if SquadDeathOwed(c) then
        return "alert"
    end
    return "normal"
end

--------------------------------------------------------------------------------
-- The collar on the token
--------------------------------------------------------------------------------

local g_ledStyles = {
    {
        selectors = {"loyaltyCollarLed"},
        opacity = 0,
    },
    {
        selectors = {"loyaltyCollarLed", "on"},
        opacity = 1,
        brightness = LED_BRIGHTNESS,
    },
    --opacity does not cascade, so the core follows its parent's lit state itself.
    {
        selectors = {"loyaltyCollarLedCore"},
        opacity = 0,
    },
    {
        selectors = {"loyaltyCollarLedCore", "parent:on"},
        opacity = 1,
    },
}

--The explosion is loaded ahead of time on each map that has a collar: dmhub.PlayEffect drops
--a one-shot effect whose prefab is not loaded yet, but a looping one waits for its load, so a
--tiny short-lived looping copy far off the map pulls it in unseen.
local g_explosionWarmMap = nil

--- @param floorIndex number
local function WarmExplosion(floorIndex)
    if g_explosionWarmMap == game.currentMapId then
        return
    end
    g_explosionWarmMap = game.currentMapId
    dmhub.PlayEffect{
        id = EXPLOSION_EFFECT,
        loc = core.Loc{ x = -5000, y = -5000, floorIndex = floorIndex },
        scale = 0.01,
        looping = true,
        ttl = 0.1,
    }
end

--charids whose collar exploded on this client; their light stays off.
local g_exploded = {}

--- @return Panel
local function CreateLed()
    local ledCore = gui.Panel{
        classes = {"loyaltyCollarLedCore"},
        interactable = false,
        halign = "center",
        valign = "center",
        width = LED_GLOW_SIZE * LED_CORE_FRACTION,
        height = LED_GLOW_SIZE * LED_CORE_FRACTION,
        bgimage = LED_GLOW,
        bgcolor = LED_GREEN_CORE,
    }

    return gui.Panel{
        classes = {"loyaltyCollarLed"},
        interactable = false,
        floating = true,
        halign = "center",
        valign = "center",
        x = LED_FX * FRAME_SIZE,
        y = -LED_FY * FRAME_SIZE,
        width = LED_GLOW_SIZE,
        height = LED_GLOW_SIZE,
        bgimage = LED_GLOW,
        bgcolor = LED_GREEN,
        data = {
            --a key of g_ledStates.
            state = "normal",
            --bumped whenever the blink restarts, so an older scheduled blink stops.
            gen = 0,
        },
        ledCore,

        create = function(element)
            --start each light at a random point in its cycle so they do not blink in step.
            element:ScheduleEvent("blink", math.random() * BLINK_PERIOD, element.data.gen)
        end,

        blink = function(element, gen)
            local d = element.data
            if gen ~= d.gen then
                return
            end
            local look = g_ledStates[d.state]
            element:SetClass("on", true)
            element:ScheduleEvent("blinkOff", look.on, gen)
            element:ScheduleEvent("blink", look.period, gen)
        end,

        blinkOff = function(element, gen)
            if gen == element.data.gen then
                element:SetClass("on", false)
            end
        end,

        --state is a key of g_ledStates. A warning state starts blinking at once.
        setState = function(element, state)
            local d = element.data
            if d.state == state then
                return
            end
            d.state = state
            local look = g_ledStates[state]
            element.selfStyle.bgcolor = look.color
            ledCore.selfStyle.bgcolor = look.core
            d.gen = d.gen + 1
            element:SetClass("on", false)
            element:ScheduleEvent("blink", cond(state == "normal", math.random() * look.period, 0), d.gen)
        end,
    }
end

TokenHud.RegisterPanel{
    id = "loyaltyCollar",
    create = function(token, sharedInfo)
        if token.isObject then
            return nil
        end

        local led = CreateLed()

        --Puts the collar on or takes it off this client's view of the token. Runs on every
        --hud refresh (the creature or its modifiers changed) and, while collared, on a
        --think: a minion's confirmed death is client-local and refreshes nothing.
        local function Update(element)
            local c = token.properties
            local collared = c ~= nil and c:HasLoyaltyCollar()
            token.frameOverride = cond(collared, FRAME_ID, nil)

            local showLed = collared and not g_exploded[token.charid]
            element:SetClass("collapsed", not showLed)
            local thinkTime = cond(showLed, 0.5, nil)
            if element.thinkTime ~= thinkTime then
                element.thinkTime = thinkTime
            end
            if showLed then
                ---@cast c creature
                led:FireEvent("setState", CollarState(c))
                WarmExplosion(token.loc.floor)
            end
        end

        return gui.Panel{
            classes = {"collapsed"},
            interactable = false,
            blocksGameInteraction = false,
            floating = true,
            halign = "center",
            valign = "center",
            width = 110,
            height = 110,
            styles = g_ledStyles,
            led,

            refresh = function(element)
                Update(element)
            end,

            think = function(element)
                Update(element)
            end,
        }
    end,
}

--------------------------------------------------------------------------------
-- The explosion
--------------------------------------------------------------------------------

--A small deterministic random number generator, so every client lays out the same marks
--from the same seed (the same scheme as BloodSpatter's).
--- @param seed string
--- @return fun(): number
local function MakeRandom(seed)
    local h = 2166136261
    for i = 1, #seed do
        h = ((h ~ string.byte(seed, i)) * 16777619) & 0xffffffff
    end
    local state = h
    if state == 0 then
        state = 0x9e3779b9
    end
    return function()
        state = state ~ ((state << 13) & 0xffffffff)
        state = state ~ (state >> 17)
        state = state ~ ((state << 5) & 0xffffffff)
        return state / 4294967296
    end
end

local g_scorches = { "blood/scorch-1.png", "blood/scorch-2.png", "blood/scorch-3.png", "blood/scorch-4.png" }
local g_soot = { "blood/soot-1.png", "blood/soot-2.png", "blood/soot-3.png" }
local SCORCH_RING = "blood/scorch-ring-1.png"
local SCORCH_STREAK = "blood/scorch-streak-1.png"
--opacity the marks settle at. Like blood they are client-local: gone after a map change.
local CHAR_REMAIN = 0.9

--Draws the burn left where a collar exploded: scorch rings, a field of blots, streaks
--blasted outward and soot flecks thrown wide, all scaled to the creature's width.
--info = {floorid, px, py, seed, tokenid, size}.
--- @param info table
local function DrawCharMarks(info)
    local floor = game.GetFloor(info.floorid)
    if floor == nil then
        return
    end

    local tag = "loyaltycollar:" .. info.seed
    local rand = MakeRandom(info.seed)
    local cx, cy = info.px, info.py
    local k = math.max(1, tonumber(info.size) or 1)

    local function Place(args)
        if args.angle == nil then
            args.angle = rand() * 360
        end
        if args.mirror == nil then
            args.mirror = rand() < 0.5
        end
        args.size = args.size * k
        args.flight = 0
        args.lifetime = 1.5
        args.remain = CHAR_REMAIN
        args.tag = tag
        floor:AddBloodSpatter(args)
    end

    local function Around(minDist, maxDist)
        local a = rand() * math.pi * 2
        local d = (minDist + (maxDist - minDist) * rand()) * k
        return cx + math.cos(a) * d, cy + math.sin(a) * d, a
    end

    Place{ image = SCORCH_RING, x = cx, y = cy, size = 1.9 }
    for _ = 1, 3 do
        local x, y = Around(0.1, 0.35)
        Place{ image = SCORCH_RING, x = x, y = y, size = 1.1 + rand() * 0.4, delay = rand() * 0.03 }
    end

    for _ = 1, 18 do
        local x, y = Around(0, 0.75)
        Place{ image = g_scorches[1 + math.floor(rand() * #g_scorches)], x = x, y = y, size = 0.4 + rand() * 0.5, delay = rand() * 0.04 }
    end

    for _ = 1, 10 do
        local x, y, a = Around(0.5, 0.85)
        Place{ image = SCORCH_STREAK, x = x, y = y, size = 0.7 + rand() * 0.4, angle = math.deg(a), delay = rand() * 0.03 }
    end

    for _ = 1, 30 do
        local x, y = Around(0.3, 1.3)
        Place{ image = g_soot[1 + math.floor(rand() * #g_soot)], x = x, y = y, size = 0.1 + rand() * 0.25, delay = rand() * 0.06 }
    end
end

--Plays a collar explosion on this client: the boom at the token's square, then the token
--hidden and the floor charred once the fireball covers it. The trigger's own Remove
--Creature behavior takes the creature off the map. info = {tokenid, x, y, floor, floorid,
--px, py, mapid, seed, size}: px, py is the token's centre (on a square's corner for a 2x2)
--and size its width in squares.
--- @param info table
local function PlayExplosion(info)
    if info.mapid ~= game.currentMapId then
        return
    end

    g_exploded[info.tokenid] = true
    audio.FireSoundEvent(SOUND_EXPLOSION, { volume = EXPLOSION_VOLUME })
    dmhub.PlayEffect{
        id = EXPLOSION_EFFECT,
        loc = core.Loc{ x = info.x, y = info.y, floorIndex = info.floor },
        pos = core.Vector2(info.px, info.py),
        scale = EXPLOSION_SCALE * math.max(1, tonumber(info.size) or 1),
    }

    dmhub.Schedule(VANISH_DELAY, function()
        if mod.unloaded then
            return
        end
        local charid = info.tokenid
        local tok = dmhub.GetTokenById(charid)
        if tok ~= nil then
            tok.animation:SetVisible(false)
            --if the creature is not removed after all, do not leave it invisible.
            dmhub.Schedule(5, function()
                if mod.unloaded then
                    return
                end
                g_exploded[charid] = nil
                local t = dmhub.GetTokenById(charid)
                if t ~= nil and not t.despawned then
                    t.animation:SetVisible(true)
                end
            end)
        end
        DrawCharMarks(info)
    end)
end

dmhub.RegisterRemoteEvent(REMOTE_EVENT, function(info)
    if mod.unloaded or type(info) ~= "table" or info.tokenid == nil then
        return
    end
    PlayExplosion(info)
end)

--- @class ActivatedAbilityLoyaltyCollarExplosionBehavior: ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityLoyaltyCollarExplosionBehavior
--- @field summary string Short label shown in behavior lists.
ActivatedAbilityLoyaltyCollarExplosionBehavior = RegisterGameType("ActivatedAbilityLoyaltyCollarExplosionBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityLoyaltyCollarExplosionBehavior.summary = "Loyalty Collar Explosion"

ActivatedAbility.RegisterType
{
    id = "loyalty_collar_explosion",
    text = "Loyalty Collar Explosion",
    canHaveDC = false,
    createBehavior = function()
        return ActivatedAbilityLoyaltyCollarExplosionBehavior.new{
        }
    end,
}

function ActivatedAbilityLoyaltyCollarExplosionBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Loyalty Collar Explosion"
end

--The caster's collar explodes, as seen on every client. Visual only: the ability's other
--behaviors deal the damage and remove the creature.
function ActivatedAbilityLoyaltyCollarExplosionBehavior:Cast(ability, casterToken, targets, options)
    if casterToken == nil or not casterToken.valid then
        return
    end

    local loc = casterToken.loc
    local pos = casterToken.pos
    local info = {
        tokenid = casterToken.charid,
        x = loc.x,
        y = loc.y,
        floor = loc.floor,
        floorid = casterToken.floorid,
        px = pos.x,
        py = pos.y,
        mapid = game.currentMapId,
        seed = dmhub.GenerateGuid(),
        size = casterToken.creatureDimensions.x,
    }
    dmhub.BroadcastRemoteEvent(REMOTE_EVENT, dmhub.GenerateGuid(), info, true)
    PlayExplosion(info)
end

function ActivatedAbilityLoyaltyCollarExplosionBehavior:EditorItems(parentPanel)
    return {}
end

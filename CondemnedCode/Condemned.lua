local mod = dmhub.GetModLoading()

--Loyalty collars for The Condemned. The Director locks a black iron collar onto a hero
--from a button in the top-right map button bar. The collar is a lit token frame; the
--hero's own frame is saved on the creature and put back when the collar comes off.
--A green light on the collar blinks once a second (or stays lit; the Director picks for
--all collars at once in the panel). The Director can explode a collar:
--it beeps, the hero is engulfed in an explosion and despawned, and char marks are left
--on the floor. The panel remembers blown-up heroes and can restore them. Holding the
--Shock button electrocutes a collared hero (visual only; see the Shock section).
--Every client plays the animations; only the Director's client changes game data.

local COLLAR_FRAME_ID = "condemned-loyalty-collar"
--textures from tools/token-frames/make_iron_collar_frame.py, uploaded to this game.
local COLLAR_ALBEDO = "87106cdd-1392-457d-a135-d8c9113905f2"
local COLLAR_NORMAL = "c3b2c430-6e63-4ec7-bdeb-afa6281c87ed"
local COLLAR_ROUGHNESS = "b5337890-62b8-4319-a75f-bc50cb1ffb1f"
local COLLAR_MATCAP = "5c910265-afc5-4c70-bc33-b857a1382c2a"
--a pre-lit flat render of the collar, shown during the attach/remove animation.
local COLLAR_OVERLAY = "7fbf68e9-9db1-4c22-9ffd-4789a3d49449"
--a white glow sprite, tinted and blinked over the collar's LED lens.
local LED_GLOW = "f828afd1-8271-454d-8a84-89c645e30844"

--the hero's frame from before the collar, stored on the creature.
local SAVED_FIELD = "condemnedCollarSaved"
local REMOTE_EVENT = "condemnedCollar"
--shared document: exploded[charid] = where a blown-up hero was, for char marks and Restore.
local DOC_ID = "condemnedCollars"

--sound events defined in Draw Steel Audio/AudioMain.lua.
local SOUND_LOCK = "Ability.Collar_Attach"
local SOUND_UNLOCK = "Ability.Collar_Remove"
local SOUND_BEEP = "Ability.Collar_DetonateBeep"
local SOUND_EXPLOSION = "Ability.Explosion_Medium_Short"
--multiplies the explosion event's own volume, so the collar's boom is louder without
--changing the shared sound's mix.
local EXPLOSION_VOLUME = 1.5

local EXPLOSION_EFFECT = "Explosion 1"
local EXPLOSION_SCALE = 1.25

--animation timings, in seconds.
local SNAP_TIME = 0.45
local HOLD_TIME = 1.1
local FADE_TIME = 0.4
local RELEASE_DELAY = 0.15
local BLINK_PERIOD = 1.0
--how long the light stays lit for each blink; it switches hard on and off.
local BLINK_ON_TIME = 0.15
local ALARM_ON_TIME = 0.3
--the detonation: three warning blinks, each with a beep, this far apart, then the
--explosion, then the hero vanishes once the fireball covers the token. A second apart,
--the beeps line up with the Explode countdown's "3, 2, 1".
local ALARM_INTERVAL = 1.0
--during the Explode countdown the light gives one longer red blink a second.
local COUNTDOWN_ON_TIME = 0.3
local ALARM_BLINKS = 3
local EXPLODE_TIME = ALARM_INTERVAL * ALARM_BLINKS
local VANISH_DELAY = 0.13

--overlay size in token sheet units, matched by eye to the lit frame's footprint.
local OVERLAY_SIZE = 98
--the LED lens centre as a fraction of the frame texture (+y up), printed by the
--texture generator, and the size of the glow drawn over it.
local LED_FX = -0.3223
local LED_FY = -0.3223
local LED_GLOW_SIZE = 11

local LED_GREEN = "#00ff20"
local LED_RED = "#ff0000"
--a lit LED looks near-white at its centre with the colour in the glow around it; a
--tint alone cannot make red read as bright, so a pale-hot core sits on the glow.
local LED_GREEN_CORE = "#e0ffe0"
local LED_RED_CORE = "#ffd8cc"
--solid orange while the hero is being shocked.
local LED_ORANGE = "#ff8a00"
local LED_ORANGE_CORE = "#ffe2b8"
local LED_CORE_FRACTION = 0.45
--brightness multiplier while lit, so the glow reads as a light rather than a dot.
local LED_BRIGHTNESS = 2.5

local collarDefinition = {
    id = COLLAR_FRAME_ID,
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

local tokenFrames = rawget(_G, "TokenFrames")
if tokenFrames ~= nil and tokenFrames.RegisterDefinition ~= nil then
    tokenFrames.RegisterDefinition(collarDefinition)
else
    dmhub.tokenFrames:Register(collarDefinition)
end

--charid -> true while that hero's collar animation or detonation is running on this client.
local g_busy = {}

---@param token CharacterToken
---@return boolean
local function IsCollared(token)
    return token.portraitFrameMaterial == COLLAR_FRAME_ID
end

--the blown-up heroes, keyed by charid.
---@return table<string, table>
local function GetExploded()
    local doc = mod:GetDocumentSnapshot(DOC_ID)
    return doc.data.exploded or {}
end

---@param token CharacterToken
local function ApplyCollar(token)
    if IsCollared(token) then
        return
    end

    local saved = {
        frame = token.portraitFrame,
        material = token.portraitFrameMaterial,
        hueShift = token.portraitFrameHueShift,
        saturation = token.portraitFrameSaturation,
        brightness = token.portraitFrameBrightness,
    }

    token:ModifyProperties{
        description = "Attach Loyalty Collar",
        execute = function()
            token.properties[SAVED_FIELD] = saved
        end,
    }

    token.portraitFrame = COLLAR_ALBEDO
    token.portraitFrameMaterial = COLLAR_FRAME_ID
    token.portraitFrameHueShift = 0
    token.portraitFrameSaturation = 1
    token.portraitFrameBrightness = 1
    token:UploadAppearance()
end

---@param token CharacterToken
local function RemoveCollar(token)
    if not IsCollared(token) then
        return
    end

    local saved = token.properties:try_get(SAVED_FIELD)
    if saved ~= nil then
        token.portraitFrame = saved.frame
        token.portraitFrameMaterial = saved.material or ""
        token.portraitFrameHueShift = saved.hueShift or 0
        token.portraitFrameSaturation = saved.saturation or 1
        token.portraitFrameBrightness = saved.brightness or 1
    else
        token.portraitFrame = nil
        token.portraitFrameMaterial = ""
    end
    token:UploadAppearance()

    token:ModifyProperties{
        description = "Remove Loyalty Collar",
        execute = function()
            token.properties[SAVED_FIELD] = nil
        end,
    }
end

--------------------------------------------------------------------------------
-- Attach / remove animation
--------------------------------------------------------------------------------

local g_overlayStyles = {
    {
        selectors = {"condemnedCollar"},
        scale = 1,
        opacity = 1,
        brightness = 1,
    },
    {
        selectors = {"condemnedCollar", "open"},
        scale = 1.8,
        opacity = 0,
        transitionTime = SNAP_TIME,
    },
    {
        selectors = {"condemnedCollar", "glint"},
        brightness = 3,
        transitionTime = 0.35,
    },
    {
        selectors = {"condemnedCollar", "fade"},
        opacity = 0,
        transitionTime = FADE_TIME,
    },
}

--Plays the collar overlay on this client. info = {tokenid, attach}. onChange, if given,
--runs at the moment the token's look should switch (when the collar lands, or as it
--starts to open).
local function PlayCollarAnimation(info, onChange)
    local token = dmhub.GetTokenById(info.tokenid)
    if token == nil or token.sheet == nil then
        if onChange ~= nil then
            onChange()
        end
        return
    end

    local charid = info.tokenid
    g_busy[charid] = true

    local overlay = gui.Panel{
        classes = {"condemnedCollar"},
        interactable = false,
        floating = true,
        halign = "center",
        valign = "center",
        width = OVERLAY_SIZE,
        height = OVERLAY_SIZE,
        bgimage = COLLAR_OVERLAY,
        bgcolor = "white",
        styles = g_overlayStyles,

        landed = function(element)
            audio.FireSoundEvent(SOUND_LOCK)
            element:PulseClass("glint")
            if onChange ~= nil then
                onChange()
            end
            element:ScheduleEvent("fadeOut", HOLD_TIME)
        end,

        fadeOut = function(element)
            element:SetClass("fade", true)
            element:ScheduleEvent("finish", FADE_TIME)
        end,

        release = function(element)
            element:SetClass("open", true)
            element:ScheduleEvent("finish", SNAP_TIME)
        end,

        finish = function(element)
            g_busy[charid] = nil
            element:DestroySelf()
        end,

        destroy = function(element)
            g_busy[charid] = nil
        end,
    }

    token.sheet:AddChild(overlay)

    if info.attach then
        overlay:PulseClass("open")
        overlay:ScheduleEvent("landed", SNAP_TIME)
    else
        audio.FireSoundEvent(SOUND_UNLOCK)
        if onChange ~= nil then
            onChange()
        end
        overlay:ScheduleEvent("release", RELEASE_DELAY)
    end
end

--------------------------------------------------------------------------------
-- The blinking light
--------------------------------------------------------------------------------

local g_ledStyles = {
    {
        selectors = {"condemnedLed"},
        opacity = 0,
    },
    {
        selectors = {"condemnedLed", "on"},
        opacity = 1,
        brightness = LED_BRIGHTNESS,
    },
    {
        selectors = {"condemnedLed", "alarmOn"},
        opacity = 1,
        brightness = LED_BRIGHTNESS,
        scale = 1.4,
    },
    --opacity does not cascade, so the core follows its parent's lit state itself.
    {
        selectors = {"condemnedLedCore"},
        opacity = 0,
    },
    {
        selectors = {"condemnedLedCore", "parent:on"},
        opacity = 1,
    },
    {
        selectors = {"condemnedLedCore", "parent:alarmOn"},
        opacity = 1,
    },
}

--The Director's choice for how a green light behaves on every collar: "blink" (the
--default) or "constant" (stays lit). Stored as ledMode in the shared doc; red and orange
--lights ignore it. g_ledConstant mirrors it on this client, refreshed by the upkeep loop.
local LED_MODE_BLINK = "blink"
local LED_MODE_CONSTANT = "constant"
local g_ledConstant = false

---@return string
local function GetLedMode()
    local doc = mod:GetDocumentSnapshot(DOC_ID)
    return doc.data.ledMode or LED_MODE_BLINK
end

--charid -> the glow panel on that hero's token sheet, on this client.
local g_leds = {}
--charid -> {id, endsAt} while an Explode countdown is running on that hero's collar, in
--this client's clock, so a light rebuilt mid-countdown picks the countdown back up.
local g_ledCountdowns = {}

---@param token CharacterToken
---@return Panel
local function CreateLed(token)
    local core = gui.Panel{
        classes = {"condemnedLedCore"},
        interactable = false,
        halign = "center",
        valign = "center",
        width = LED_GLOW_SIZE * LED_CORE_FRACTION,
        height = LED_GLOW_SIZE * LED_CORE_FRACTION,
        bgimage = LED_GLOW,
        bgcolor = LED_GREEN_CORE,
    }

    return gui.Panel{
        classes = {"condemnedLed"},
        interactable = false,
        floating = true,
        halign = "center",
        valign = "center",
        x = LED_FX * OVERLAY_SIZE,
        y = -LED_FY * OVERLAY_SIZE,
        width = LED_GLOW_SIZE,
        height = LED_GLOW_SIZE,
        bgimage = LED_GLOW,
        bgcolor = LED_GREEN,
        styles = g_ledStyles,
        data = {
            alarm = false,
            --the Explode countdown the light is showing, if any.
            countdown = nil,
            --bumped whenever the green blink restarts, so an older scheduled blink
            --from before a countdown does not run a second chain alongside it.
            blinkGen = 0,
            --bumped when a detonation alarm starts or is defused, so a defused alarm's
            --remaining beeps are dropped.
            alarmGen = 0,
            --true while the hero is being shocked: the light holds solid orange.
            shocking = false,
        },
        children = { core },

        create = function(element)
            element:SetClass("on", g_ledConstant)
            --start each light at a random point in its cycle so they do not blink in step.
            element:ScheduleEvent("blink", math.random() * BLINK_PERIOD, element.data.blinkGen)
        end,

        --the green blink chain. It keeps running in constant mode (it just holds the
        --light on), so switching back to blinking needs no restart.
        blink = function(element, gen)
            local d = element.data
            if d.alarm or gen ~= d.blinkGen then
                return
            end
            --while shocked the light holds on; the chain keeps going for afterwards.
            if not d.shocking then
                element:SetClass("on", true)
                if not g_ledConstant then
                    element:ScheduleEvent("blinkOff", BLINK_ON_TIME)
                end
            end
            element:ScheduleEvent("blink", BLINK_PERIOD, gen)
        end,

        blinkOff = function(element)
            if not element.data.shocking and not g_ledConstant then
                element:SetClass("on", false)
            end
        end,

        --the Director switched between blinking and constant; only a green light changes.
        ledMode = function(element)
            local d = element.data
            if d.alarm or d.shocking then
                return
            end
            element:SetClass("on", g_ledConstant)
        end,

        --back to normal after a countdown, a defused alarm or a shock: solid orange if
        --still being shocked, otherwise the green blink.
        rest = function(element)
            local d = element.data
            d.alarm = false
            d.countdown = nil
            element:SetClass("alarmOn", false)
            if d.shocking then
                element.selfStyle.bgcolor = LED_ORANGE
                core.selfStyle.bgcolor = LED_ORANGE_CORE
                element:SetClass("on", true)
            else
                element.selfStyle.bgcolor = LED_GREEN
                core.selfStyle.bgcolor = LED_GREEN_CORE
                element:SetClass("on", g_ledConstant)
            end
            d.blinkGen = d.blinkGen + 1
            element:ScheduleEvent("blink", BLINK_PERIOD, d.blinkGen)
        end,

        shockStart = function(element)
            element.data.shocking = true
            if not element.data.alarm then
                element:FireEvent("rest")
            end
        end,

        shockEnd = function(element)
            element.data.shocking = false
            if not element.data.alarm then
                element:FireEvent("rest")
            end
        end,

        --the Explode countdown: the light turns red and blinks once as each second
        --starts (3, 2, 1), until the detonation alarm takes over or it is disarmed.
        countdown = function(element, id, remaining)
            local d = element.data
            d.alarm = true
            d.countdown = id
            element:SetClass("on", false)
            element.selfStyle.bgcolor = LED_RED
            core.selfStyle.bgcolor = LED_RED_CORE
            for n = math.ceil(remaining), 1, -1 do
                element:ScheduleEvent("countdownBlink", math.max(0, remaining - n), id)
            end
        end,

        countdownBlink = function(element, id)
            if element.data.countdown ~= id then
                return
            end
            element:SetClass("alarmOn", true)
            element:ScheduleEvent("alarmOff", COUNTDOWN_ON_TIME)
        end,

        --the countdown was cancelled before its alarm started.
        disarm = function(element, id)
            if element.data.countdown ~= id then
                return
            end
            element:FireEvent("rest")
        end,

        --the detonation: ALARM_BLINKS red blinks, each with a beep.
        alarm = function(element)
            local d = element.data
            d.alarm = true
            d.countdown = nil
            d.alarmGen = d.alarmGen + 1
            element:SetClass("on", false)
            element.selfStyle.bgcolor = LED_RED
            core.selfStyle.bgcolor = LED_RED_CORE
            for i = 0, ALARM_BLINKS - 1 do
                element:ScheduleEvent("alarmBlink", i * ALARM_INTERVAL, d.alarmGen)
            end
        end,

        --the detonation was cancelled during its alarm.
        defuse = function(element)
            element.data.alarmGen = element.data.alarmGen + 1
            element:FireEvent("rest")
        end,

        alarmBlink = function(element, gen)
            if gen ~= element.data.alarmGen then
                return
            end
            audio.FireSoundEvent(SOUND_BEEP)
            element:SetClass("alarmOn", true)
            element:ScheduleEvent("alarmOff", ALARM_ON_TIME)
        end,

        alarmOff = function(element)
            element:SetClass("alarmOn", false)
        end,
    }
end

--detonation seeds that were cancelled during their alarm; their explosion never comes.
local g_defused = {}

--Runs a defuse message on this client: info = {tokenid, seed}.
local function PlayDefuse(info)
    g_defused[info.seed] = true
    local led = g_leds[info.tokenid]
    if led ~= nil and led.valid then
        led:FireEvent("defuse")
    end
end

--Runs an Explode countdown message on this client: kind "countdown" {tokenid, id,
--remaining} turns the collar light red, kind "disarm" {tokenid, id} turns it back.
local function PlayCountdownLight(info)
    local charid = info.tokenid
    local led = g_leds[charid]
    if info.kind == "countdown" then
        g_ledCountdowns[charid] = { id = info.id, endsAt = dmhub.Time() + info.remaining }
        if led ~= nil and led.valid then
            led:FireEvent("countdown", info.id, info.remaining)
        end
    else
        local countdown = g_ledCountdowns[charid]
        if countdown ~= nil and countdown.id == info.id then
            g_ledCountdowns[charid] = nil
        end
        if led ~= nil and led.valid then
            led:FireEvent("disarm", info.id)
        end
    end
end

--------------------------------------------------------------------------------
-- Char marks
--------------------------------------------------------------------------------

--A small deterministic random number generator, so every client lays out the same
--marks from the same seed (the same scheme as BloodSpatter's).
---@param seed string
---@return fun(): number
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
--opacity the marks settle at; they stay until the hero is restored.
local CHAR_REMAIN = 0.9

---@param charid string
---@return string
local function CharTag(charid)
    return "condemned:" .. charid
end

--Draws the burn left where a hero exploded: big scorch rings, a field of blots,
--streaks blasted outward and soot flecks thrown wide. Client-local; the shared
--document is what makes every client draw it.
---@param entry table
local function DrawCharMarks(entry)
    local floor = game.GetFloor(entry.floorid)
    if floor == nil then
        return
    end

    local tag = CharTag(entry.charid)
    floor:ClearBloodSpatter(tag)

    local rand = MakeRandom(entry.seed or entry.charid)
    local cx, cy = entry.px, entry.py

    local function Place(args)
        if args.angle == nil then
            args.angle = rand() * 360
        end
        if args.mirror == nil then
            args.mirror = rand() < 0.5
        end
        args.flight = 0
        args.lifetime = 1.5
        args.remain = CHAR_REMAIN
        args.tag = tag
        floor:AddBloodSpatter(args)
    end

    local function Around(minDist, maxDist)
        local a = rand() * math.pi * 2
        local d = minDist + (maxDist - minDist) * rand()
        return cx + math.cos(a) * d, cy + math.sin(a) * d, a
    end

    --sized to the explosion: dense near the centre, little thrown far out.
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

--charid -> floorid of the char marks this client has drawn on the current map.
local g_drawnMarks = {}
local g_drawnMapId = nil
--charid -> time marks were drawn from a detonation, before the shared record of it
--arrives; such marks are not cleared for lack of a record in the meantime.
local g_pendingMarks = {}
local PENDING_MARKS_GRACE = 10

--Brings this client's char marks in line with the shared document.
local function SyncCharMarks()
    local mapid = game.currentMapId
    if mapid ~= g_drawnMapId then
        --a map change wipes client-local marks, so everything is redrawn.
        g_drawnMarks = {}
        g_drawnMapId = mapid
    end

    local exploded = GetExploded()
    for charid, entry in pairs(exploded) do
        g_pendingMarks[charid] = nil
        if entry.mapid == mapid and g_drawnMarks[charid] == nil then
            g_drawnMarks[charid] = entry.floorid
            DrawCharMarks(entry)
        end
    end

    for charid, floorid in pairs(g_drawnMarks) do
        local entry = exploded[charid]
        local pending = g_pendingMarks[charid]
        if pending ~= nil and dmhub.Time() - pending > PENDING_MARKS_GRACE then
            g_pendingMarks[charid] = nil
            pending = nil
        end
        if pending == nil and (entry == nil or entry.mapid ~= mapid) then
            g_drawnMarks[charid] = nil
            local floor = game.GetFloor(floorid)
            if floor ~= nil then
                floor:ClearBloodSpatter(CharTag(charid))
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Detonation
--------------------------------------------------------------------------------

--dmhub.PlayEffect drops a one-shot effect whose prefab is not loaded yet, so the
--explosion is loaded ahead of time: a looping effect does wait for its load, so a
--tiny, short-lived looping copy far off the map pulls it in without being seen.
local g_explosionWarmMap = nil

---@param floorIndex number
local function WarmExplosion(floorIndex)
    pcall(function()
        dmhub.PlayEffect{
            id = EXPLOSION_EFFECT,
            loc = core.Loc{ x = -5000, y = -5000, floorIndex = floorIndex },
            scale = 0.01,
            looping = true,
            ttl = 0.1,
        }
    end)
end

--Plays the countdown, beeps and explosion on this client, then hides the token and
--chars the floor the moment the fireball covers it. The Director's despawn lands at the
--same time; hiding first means nobody sees the engine's despawn fade.
--info = {tokenid, x, y, floor, floorid, px, py, seed}.
local function PlayDetonation(info)
    g_ledCountdowns[info.tokenid] = nil
    WarmExplosion(info.floor)
    local led = g_leds[info.tokenid]
    if led ~= nil and led.valid then
        led:FireEvent("alarm")
    else
        for i = 0, ALARM_BLINKS - 1 do
            dmhub.Schedule(i * ALARM_INTERVAL, function()
                if not mod.unloaded and not g_defused[info.seed] then
                    audio.FireSoundEvent(SOUND_BEEP)
                end
            end)
        end
    end

    --the explosion is placed at the map square rather than on the token, so it
    --outlives the token's removal.
    dmhub.Schedule(EXPLODE_TIME, function()
        if mod.unloaded or g_defused[info.seed] then
            return
        end
        audio.FireSoundEvent(SOUND_EXPLOSION, { volume = EXPLOSION_VOLUME })
        dmhub.PlayEffect{
            id = EXPLOSION_EFFECT,
            loc = core.Loc{ x = info.x, y = info.y, floorIndex = info.floor },
            scale = EXPLOSION_SCALE,
        }
    end)

    dmhub.Schedule(EXPLODE_TIME + VANISH_DELAY, function()
        if mod.unloaded or g_defused[info.seed] then
            return
        end
        local charid = info.tokenid
        local tok = dmhub.GetTokenById(charid)
        if tok ~= nil then
            tok.animation:SetVisible(false)
            --if the despawn never arrives, do not leave the token invisible here.
            dmhub.Schedule(5, function()
                local t = dmhub.GetTokenById(charid)
                if t ~= nil and not t.despawned then
                    t.animation:SetVisible(true)
                end
            end)
        end

        if info.seed ~= nil and info.floorid ~= nil and info.mapid == game.currentMapId then
            g_pendingMarks[charid] = dmhub.Time()
            g_drawnMarks[charid] = info.floorid
            DrawCharMarks{ charid = charid, floorid = info.floorid, px = info.px, py = info.py, seed = info.seed }
        end
    end)
end

---@param token CharacterToken
---@param info table the detonation info, whose burn site every client has drawn
local function Despawn(token, info)
    local charid = token.charid

    local doc = mod:GetDocumentSnapshot(DOC_ID)
    doc:BeginChange()
    doc.data.exploded = doc.data.exploded or {}
    doc.data.exploded[charid] = {
        charid = charid,
        name = token.name,
        x = info.x,
        y = info.y,
        floor = info.floor,
        floorid = info.floorid,
        px = info.px,
        py = info.py,
        mapid = info.mapid,
        seed = info.seed,
    }
    doc:CompleteChange("Loyalty collar detonated", {undoable = false})

    --a hero removed on its own turn would leave combat with no End Turn button.
    local removeBehavior = rawget(_G, "ActivatedAbilityRemoveCreatureBehavior")
    local initiativeQueue = rawget(_G, "InitiativeQueue")
    if removeBehavior ~= nil and initiativeQueue ~= nil then
        pcall(function()
            removeBehavior.EndTurnIfEntryEmptied({[initiativeQueue.GetInitiativeId(token)] = true})
        end)
    end

    token.despawned = true
end

--Starts the detonation and returns its info (whose seed Defuse takes), or nil if the
--hero cannot be blown up right now.
---@param token CharacterToken
---@return table|nil
local function BlowUp(token)
    local charid = token.charid
    if g_busy[charid] or not IsCollared(token) then
        return nil
    end
    g_busy[charid] = true

    local pos = token.pos
    local info = {
        kind = "detonate",
        tokenid = charid,
        x = token.loc.x,
        y = token.loc.y,
        floor = token.loc.floor,
        floorid = token.floorid,
        px = pos.x,
        py = pos.y,
        mapid = game.currentMapId,
        seed = dmhub.GenerateGuid(),
    }
    dmhub.BroadcastRemoteEvent(REMOTE_EVENT, dmhub.GenerateGuid(), info, true)
    PlayDetonation(info)

    dmhub.Schedule(EXPLODE_TIME + VANISH_DELAY, function()
        if g_defused[info.seed] then
            return
        end
        g_busy[charid] = nil
        if mod.unloaded then
            return
        end
        local tok = dmhub.GetTokenById(charid)
        if tok ~= nil then
            Despawn(tok, info)
        end
    end)
    return info
end

--Director: calls off a detonation during its alarm, before the explosion.
---@param charid string
---@param info table what BlowUp returned
local function Defuse(charid, info)
    local defuse = { kind = "defuse", tokenid = charid, seed = info.seed }
    dmhub.BroadcastRemoteEvent(REMOTE_EVENT, dmhub.GenerateGuid(), defuse, true)
    PlayDefuse(defuse)
    g_busy[charid] = nil
end

--------------------------------------------------------------------------------
-- Shock
--------------------------------------------------------------------------------

--While the Director holds the Shock button, the collared hero is electrocuted: lightning
--strikes over the collar, faster and faster, each strike flipping their portrait to a
--photo negative; the portrait shakes harder the longer it goes on, and a bar beside the
--token fills. A long shock leaves them steaming afterwards. Purely visual.
--The Director's client sends a heartbeat while the button is held; every client runs the
--whole effect itself from those (a client that stops hearing them lets go on its own).

--sprites from tools/token-frames/make_shock_textures.py, uploaded to this game.
local SHOCK_BOLTS = {
    "939e5c97-c928-4667-bb1e-efd6bd3456c7",
    "05c020e4-16fd-47b2-99da-a15c9f20399d",
    "283c4106-7578-4165-a289-828954cdef91",
    "049155d1-6274-41c5-b553-bc5d5bcc68a0",
    "ba577db3-a3a2-4b69-8a06-1f7c0ab116a4",
    "728ca99d-6620-4134-9101-d4dfee44edce",
}
local STEAM_PUFFS = {
    "7ccf6250-4854-4d75-8b6d-657774e4a3f7",
    "e830bfd8-fe41-41f5-bace-b35c8b2a9e9c",
    "e469536e-3560-4131-a648-2811594aa1ea",
}
--the collar band as a mottled mask, in the collar frame's texture space.
local HEAT_RING = "9972cfd0-a247-45b7-b721-258f385231f8"
--the bolt sprites cover this multiple of the collar overlay, centred on the token.
local BOLT_PAD = 1.25
local BOLT_SLOTS = 3
--the portrait copy's diameter, as a fraction of the collar overlay: just inside the band.
local PORTRAIT_FRACTION = 0.79

local SOUND_SHOCK = "attack.hit_lightning"

--seconds of holding to fill the bar.
local SHOCK_FULL_TIME = 5
--Overload: a skull sits on top of the bar and turns red when the bar is full. Held this
--many more seconds with the skull red, the collar explodes (exactly like Explode).
local OVERLOAD_TIME = 3
local SKULL_ICON = "phosphor/skull-fill.png"
local SKULL_SIZE = 14
local SKULL_COLOR = "#e6e6e6"
local SKULL_RED = "#ff2a1a"
--Damage: one Stamina for each whole second the shock was held past the half-way mark,
--dealt in one go when the shock ends.
local SHOCK_DAMAGE_NOTE = "Loyalty Collar"
--seconds between strikes: slow at first, a near-continuous buzz once the bar is full.
local STRIKE_INTERVAL_START = 0.55
local STRIKE_INTERVAL_FULL = 0.07
--how long each strike's lightning and negative stay up (capped by the interval).
local STRIKE_TIME = 0.12
--the floor flash is capped to this rate, so a fast buzz does not stack them. The zap
--sound plays on every strike.
local STRIKE_LIGHT_GAP = 0.14
--how far the portrait shakes inside the collar, as a fraction of the image shown:
--at the start of a shock and when the bar is full.
local SHAKE_START = 0.006
local SHAKE_FULL = 0.06
--the Director's heartbeat interval while held, and how long a client waits without one
--before treating the shock as released (the release message was lost).
local SHOCK_HEARTBEAT = 0.25
local SHOCK_TIMEOUT = 1.0

--Steam comes mostly after the shock ends: the hero smoulders. A shock that filled less
--than STEAM_MIN_LEVEL of the bar leaves none; a full one steams for STEAM_TIME_FULL
--seconds. Past STEAM_WISP_LEVEL a few faint wisps rise during the shock itself.
local STEAM_MIN_LEVEL = 0.25
local STEAM_WISP_LEVEL = 0.6
local STEAM_TIME_FULL = 5.0
--seconds each puff takes to rise and fade (randomized between the two).
local PUFF_LIFE_MIN = 3.5
local PUFF_LIFE_MAX = 5.0

--Near the top of the bar the collar heats up: the black iron takes on a dull red glow,
--which cools away after the shock ends. Heat starts at HEAT_LEVEL of the bar and reaches
--full at the top; it takes HEAT_RISE seconds to catch up and HEAT_FADE to cool from full.
local HEAT_LEVEL = 0.85
local HEAT_RISE = 1.0
local HEAT_FADE = 3.0
local HEAT_COLOR = "#8a1c08"
local HEAT_MAX_OPACITY = 0.75

local BAR_WIDTH = 8
local BAR_HEIGHT = 70
--colours the bar fill passes through as it fills: blue, then yellow, then red.
local BAR_COLORS = { {0x3a, 0x9c, 0xff}, {0xff, 0xd8, 0x30}, {0xff, 0x30, 0x10} }

local g_shockStyles = {
    {
        selectors = {"condemnedShockPortrait"},
        opacity = 0,
    },
    {
        selectors = {"condemnedShockPortrait", "on"},
        opacity = 1,
    },
    {
        selectors = {"condemnedShockPortrait", "inverted"},
        inversion = 1,
        --the panel shader inverts in linear colour, which washes everything to white;
        --scaling the colour up before the inversion puts the contrast back.
        contrast = 2.2,
        saturation = 1.6,
        brightness = 0.9,
    },
    {
        selectors = {"condemnedShockBolt"},
        opacity = 0,
        brightness = 1.8,
    },
    {
        selectors = {"condemnedShockBolt", "on"},
        opacity = 1,
    },
    --no transitions: the bar is gone the moment the shock stops. Opacity does not
    --cascade, so the fill follows the bar's shown state itself.
    {
        selectors = {"condemnedShockBar"},
        opacity = 0,
    },
    {
        selectors = {"condemnedShockBar", "shown"},
        opacity = 1,
    },
    {
        selectors = {"condemnedShockBarFill"},
        opacity = 0,
    },
    {
        selectors = {"condemnedShockBarFill", "parent:shown"},
        opacity = 1,
    },
    {
        selectors = {"condemnedShockSkull"},
        opacity = 0,
    },
    {
        selectors = {"condemnedShockSkull", "parent:shown"},
        opacity = 1,
    },
}

--charid -> the shock effect panel on that hero's token sheet, on this client.
local g_shockRigs = {}
--sessions this client has been told are over; a late heartbeat must not restart them.
local g_stoppedShocks = {}
--charid -> {id, start} while this (Director's) client is holding the Shock button.
local g_shockHeld = {}

---@param level number 0..1
---@return string
local function BarColor(level)
    local t = level * (#BAR_COLORS - 1)
    local i = math.min(#BAR_COLORS - 1, math.floor(t) + 1)
    local f = t - (i - 1)
    local a, b = BAR_COLORS[i], BAR_COLORS[i + 1]
    local function mix(k)
        return math.floor(a[k] + (b[k] - a[k]) * f + 0.5)
    end
    return string.format("#%02x%02x%02x", mix(1), mix(2), mix(3))
end

---@param a number
---@param b number
---@param t number
---@return number
local function Lerp(a, b, t)
    return a + (b - a) * t
end

--One puff of steam. The rig moves it every frame (see UpdateSteamPuff) rather than with
--style transitions, so it only ever drifts upward. opacity is the puff's peak opacity.
---@param opacity number
---@return Panel
local function CreateSteamPuff(opacity)
    local size = 90 + 50 * math.random()
    local life = Lerp(PUFF_LIFE_MIN, PUFF_LIFE_MAX, math.random())
    return gui.Panel{
        interactable = false,
        floating = true,
        halign = "center",
        valign = "center",
        width = size,
        height = size,
        bgimage = STEAM_PUFFS[math.random(1, #STEAM_PUFFS)],
        bgcolor = "#f4f6f8",
        --a touch over full brightness, so the steam reads against pale floors.
        brightness = 1.2,
        opacity = 0,
        rotate = math.random() * 360,
        data = {
            born = dmhub.Time(),
            life = life,
            peak = opacity,
            x0 = (math.random() * 2 - 1) * 28,
            y0 = 10 - math.random() * 40,
            rise = 150 + 110 * math.random(),
            drift = (math.random() * 2 - 1) * 40,
            sway = 4 + 8 * math.random(),
            phase = math.random() * math.pi * 2,
        },
    }
end

--Moves a puff along its path: it rises fast then slows, sways a little, swells, fades
--in quickly and thins away slowly. Returns false once it has finished.
---@param puff Panel
---@param now number
---@return boolean
local function UpdateSteamPuff(puff, now)
    local d = puff.data
    local t = (now - d.born) / d.life
    if t >= 1 then
        puff:DestroySelf()
        return false
    end
    local s = puff.selfStyle
    s.y = d.y0 - d.rise * (1 - (1 - t) ^ 1.7)
    s.x = d.x0 + d.drift * t + math.sin(d.phase + t * 5) * d.sway * t
    s.scale = 0.6 + 1.7 * t
    s.opacity = d.peak * math.min(1, t / 0.12) * (1 - t) ^ 1.5
    return true
end

--The shock effect on one token: a shaking copy of the portrait that strobes to a
--negative, lightning sprites, steam and the charge bar. It runs itself from
--shockOn/shockOff events and removes itself once the shock is over and the steam gone.
---@param token CharacterToken
---@return Panel
local function CreateShockRig(token)
    local charid = token.charid

    --a copy of the portrait, clipped to a circle and lined up exactly with the real one,
    --so its image can shake inside the collar. (The token's own masked portrait cannot be
    --reused: its mask comes from the collar.) The real portrait fills the whole
    --OVERLAY_SIZE square under the frame, so the copy shows the matching middle of it.
    local portraitSize = OVERLAY_SIZE * PORTRAIT_FRACTION
    local rect = token.portraitRect
    local inset = PORTRAIT_FRACTION / 2
    local rcx, rcy = (rect.x1 + rect.x2) / 2, (rect.y1 + rect.y2) / 2
    local rhw, rhh = (rect.x2 - rect.x1) * inset, (rect.y2 - rect.y1) * inset

    local portrait = gui.Panel{
        classes = {"condemnedShockPortrait"},
        interactable = false,
        floating = true,
        halign = "center",
        valign = "center",
        width = portraitSize,
        height = portraitSize,
        cornerRadius = portraitSize / 2,
        bgimage = token.portrait,
        bgcolor = "white",
        imageRect = { x1 = rcx - rhw, y1 = rcy - rhh, x2 = rcx + rhw, y2 = rcy + rhh },
    }

    --the red-hot glow over the collar band, faded in by the heat.
    local heatRing = gui.Panel{
        interactable = false,
        floating = true,
        halign = "center",
        valign = "center",
        width = OVERLAY_SIZE,
        height = OVERLAY_SIZE,
        bgimage = HEAT_RING,
        bgcolor = HEAT_COLOR,
        brightness = 1.3,
        opacity = 0,
    }

    local bolts = {}
    for i = 1, BOLT_SLOTS do
        bolts[i] = gui.Panel{
            classes = {"condemnedShockBolt"},
            interactable = false,
            floating = true,
            halign = "center",
            valign = "center",
            width = OVERLAY_SIZE * BOLT_PAD,
            height = OVERLAY_SIZE * BOLT_PAD,
            bgimage = SHOCK_BOLTS[1],
            bgcolor = "white",
        }
    end

    local steamLayer = gui.Panel{
        interactable = false,
        floating = true,
        halign = "center",
        valign = "center",
        width = 1,
        height = 1,
    }

    local fill = gui.Panel{
        classes = {"condemnedShockBarFill"},
        interactable = false,
        halign = "center",
        valign = "bottom",
        width = BAR_WIDTH - 2,
        height = 0,
        bgimage = "panels/square.png",
        bgcolor = BarColor(0),
    }

    --sits just above the bar; turns red and throbs once the bar is full.
    local skull = gui.Panel{
        classes = {"condemnedShockSkull"},
        interactable = false,
        floating = true,
        halign = "center",
        valign = "top",
        y = -(SKULL_SIZE + 3),
        width = SKULL_SIZE,
        height = SKULL_SIZE,
        bgimage = SKULL_ICON,
        bgcolor = SKULL_COLOR,
    }

    local bar = gui.Panel{
        classes = {"condemnedShockBar"},
        interactable = false,
        floating = true,
        halign = "center",
        valign = "center",
        x = OVERLAY_SIZE / 2 + 6,
        width = BAR_WIDTH,
        height = BAR_HEIGHT,
        borderBox = true,
        pad = 1,
        bgimage = "panels/square.png",
        bgcolor = "#000000c0",
        border = 1,
        borderColor = "#ffffff80",
        children = { fill, skull },
    }

    local children = { portrait, heatRing }
    for _, bolt in ipairs(bolts) do
        children[#children + 1] = bolt
    end
    children[#children + 1] = steamLayer
    children[#children + 1] = bar

    --the live steam puffs, moved every think.
    local puffs = {}

    return gui.Panel{
        interactable = false,
        floating = true,
        halign = "center",
        valign = "center",
        width = 1,
        height = 1,
        styles = g_shockStyles,
        --fast enough for the shake and the steam to move smoothly.
        thinkTime = 0.03,
        data = {
            active = false,
            session = nil,
            held = 0,
            lastBeat = 0,
            lastThink = dmhub.Time(),
            releasedAt = 0,
            --how much steam (0..1) and for how long once the shock has ended.
            steam = 0,
            steamTime = 0,
            nextStrike = 0,
            strikeEnds = 0,
            nextSound = 0,
            nextPuff = 0,
            --0..1: how red hot the collar is.
            heat = 0,
            skullRed = false,
        },
        children = children,

        --session identifies one press of the button; held is how long it has been held.
        shockOn = function(element, session, held)
            local d = element.data
            local now = dmhub.Time()
            if session ~= d.session then
                d.session = session
                d.held = held
                d.nextStrike = now
            else
                d.held = math.max(d.held, held)
            end
            if not d.active then
                local led = g_leds[charid]
                if led ~= nil and led.valid then
                    led:FireEvent("shockStart")
                end
            end
            d.active = true
            d.lastBeat = now
            d.steam = 0
            portrait:SetClass("on", true)
            bar:SetClass("shown", true)
        end,

        shockOff = function(element)
            local d = element.data
            if not d.active then
                return
            end
            d.active = false
            d.releasedAt = dmhub.Time()
            local led = g_leds[charid]
            if led ~= nil and led.valid then
                led:FireEvent("shockEnd")
            end
            local level = math.min(1, d.held / SHOCK_FULL_TIME)
            d.steam = math.max(0, (level - STEAM_MIN_LEVEL) / (1 - STEAM_MIN_LEVEL))
            d.steamTime = STEAM_TIME_FULL * d.steam
            portrait:SetClass("on", false)
            portrait:SetClass("inverted", false)
            for _, bolt in ipairs(bolts) do
                bolt:SetClass("on", false)
            end
            bar:SetClass("shown", false)
        end,

        think = function(element)
            local d = element.data
            local now = dmhub.Time()
            local dt = now - d.lastThink
            d.lastThink = now

            if d.active then
                if now - d.lastBeat > SHOCK_TIMEOUT then
                    element:FireEvent("shockOff")
                else
                    d.held = d.held + dt
                end
            end

            local level = math.min(1, d.held / SHOCK_FULL_TIME)
            fill.selfStyle.height = (BAR_HEIGHT - 2) * level
            fill.selfStyle.bgcolor = BarColor(level)

            --the skull goes red at the top of the bar and throbs faster as the overload
            --runs towards the explosion.
            if d.active and d.held >= SHOCK_FULL_TIME then
                local overload = math.min(1, (d.held - SHOCK_FULL_TIME) / OVERLOAD_TIME)
                local rate = Lerp(3, 10, overload)
                local beat = 0.5 + 0.5 * math.sin((d.held - SHOCK_FULL_TIME) * rate * math.pi)
                d.skullRed = true
                skull.selfStyle.bgcolor = SKULL_RED
                skull.selfStyle.brightness = 1.3 + 0.7 * beat
                skull.selfStyle.scale = 1.15 + 0.25 * beat
            elseif d.skullRed then
                d.skullRed = false
                skull.selfStyle.bgcolor = SKULL_COLOR
                skull.selfStyle.brightness = 1
                skull.selfStyle.scale = 1
            end

            if d.active then
                --strikes come faster the longer the shock goes on. Each one throws up
                --fresh lightning and flips the portrait to a negative for a moment.
                local interval = Lerp(STRIKE_INTERVAL_START, STRIKE_INTERVAL_FULL, level ^ 0.7)
                if now >= d.nextStrike then
                    d.nextStrike = now + interval * (0.75 + 0.5 * math.random())
                    d.strikeEnds = now + math.min(STRIKE_TIME, interval * 0.6)
                    portrait:SetClass("inverted", true)
                    local live = 1 + math.floor(level * (BOLT_SLOTS - 1) + 0.5)
                    for i, bolt in ipairs(bolts) do
                        if i <= live then
                            bolt.bgimage = SHOCK_BOLTS[math.random(1, #SHOCK_BOLTS)]
                            bolt.selfStyle.rotate = math.random() * 360
                        end
                        bolt:SetClass("on", i <= live)
                    end

                    audio.FireSoundEvent(SOUND_SHOCK)
                    if now >= d.nextSound then
                        d.nextSound = now + STRIKE_LIGHT_GAP
                        local tok = dmhub.GetTokenById(charid)
                        if tok ~= nil then
                            pcall(function()
                                tok.animation:Light{ color = "#4a9dff", radius = 1.6, innerRadius = 0.1, duration = 0.18, fadein = 0.02, fadeout = 0.12 }
                            end)
                        end
                    end
                elseif now >= d.strikeEnds and portrait:HasClass("inverted") then
                    portrait:SetClass("inverted", false)
                    for _, bolt in ipairs(bolts) do
                        bolt:SetClass("on", false)
                    end
                end

                --the portrait judders inside the collar, harder as the bar fills and
                --hardest on a strike.
                local shake = Lerp(SHAKE_START, SHAKE_FULL, level)
                if now < d.strikeEnds then
                    shake = shake * 1.5
                end
                local ox = (math.random() * 2 - 1) * shake * (rhw * 2)
                local oy = (math.random() * 2 - 1) * shake * (rhh * 2)
                portrait.selfStyle.imageRect = { x1 = rcx - rhw + ox, y1 = rcy - rhh + oy, x2 = rcx + rhw + ox, y2 = rcy + rhh + oy }

                --a few faint wisps once the shock has gone on a while.
                if level >= STEAM_WISP_LEVEL and now >= d.nextPuff then
                    local puff = CreateSteamPuff(0.25)
                    steamLayer:AddChild(puff)
                    puffs[#puffs + 1] = puff
                    d.nextPuff = now + 0.35 + 0.2 * math.random()
                end
            elseif d.steam > 0 then
                --after the shock: the hero smoulders, thickly at first, then thinning out.
                local progress = (now - d.releasedAt) / math.max(0.01, d.steamTime)
                if progress < 1 and now >= d.nextPuff then
                    local puff = CreateSteamPuff(Lerp(0.85, 0.4, progress) * (0.5 + 0.5 * d.steam))
                    steamLayer:AddChild(puff)
                    puffs[#puffs + 1] = puff
                    d.nextPuff = now + Lerp(0.07, 0.35, progress)
                end
            end

            --heat climbs towards what the bar calls for while shocked; cools once released.
            if d.active then
                local target = math.max(0, (level - HEAT_LEVEL) / (1 - HEAT_LEVEL))
                if d.heat < target then
                    d.heat = math.min(target, d.heat + dt / HEAT_RISE)
                end
            elseif d.heat > 0 then
                d.heat = math.max(0, d.heat - dt / HEAT_FADE)
            end
            heatRing.selfStyle.opacity = HEAT_MAX_OPACITY * d.heat

            local live = {}
            for _, puff in ipairs(puffs) do
                if puff.valid and UpdateSteamPuff(puff, now) then
                    live[#live + 1] = puff
                end
            end
            puffs = live

            if not d.active and #puffs == 0 and d.heat <= 0 and now - d.releasedAt > d.steamTime then
                element:DestroySelf()
            end
        end,

        destroy = function(element)
            if g_shockRigs[charid] == element then
                g_shockRigs[charid] = nil
            end
        end,
    }
end

--Runs a shock message on this client. info = {tokenid, session, on, held}.
local function PlayShock(info)
    local charid = info.tokenid
    local rig = g_shockRigs[charid]
    if not info.on then
        g_stoppedShocks[info.session] = true
        if rig ~= nil and rig.valid then
            rig:FireEvent("shockOff")
        end
        return
    end

    if g_stoppedShocks[info.session] then
        return
    end
    if rig == nil or not rig.valid then
        local tok = dmhub.GetTokenById(charid)
        if tok == nil or tok.sheet == nil then
            return
        end
        rig = CreateShockRig(tok)
        tok.sheet:AddChild(rig)
        g_shockRigs[charid] = rig
    end
    rig:FireEvent("shockOn", info.session, info.held or 0)
end

--Director: send the current state of a held Shock button to everyone, and play it here.
--Heartbeats may drop (the timeout covers that); the start and the release must not.
---@param charid string
---@param on boolean
---@param reliable boolean
local function SendShock(charid, on, reliable)
    local session = g_shockHeld[charid]
    if session == nil then
        return
    end
    local info = { kind = "shock", tokenid = charid, session = session.id, on = on, held = dmhub.Time() - session.start }
    dmhub.BroadcastRemoteEvent(REMOTE_EVENT, session.id, info, reliable)
    PlayShock(info)
end

local StopShock

--Deals the shock's damage in one go: a Stamina per whole second held past half the bar.
---@param charid string
---@param held number seconds the button was held
local function ApplyShockDamage(charid, held)
    local amount = math.floor(held - SHOCK_FULL_TIME / 2)
    local tok = dmhub.GetTokenById(charid)
    if amount <= 0 or tok == nil then
        return
    end
    tok:ModifyProperties{
        description = "Loyalty Collar shock",
        execute = function()
            --typed damage, so lightning immunity and weakness apply.
            tok.properties:InflictDamageInstance(amount, "lightning", {}, SHOCK_DAMAGE_NOTE, {})
        end,
    }
end

---@param charid string
local function StartShock(charid)
    if g_shockHeld[charid] ~= nil then
        return
    end
    --detonation is BlowUp's info once an overload has started the alarm; exploded is
    --set when the explosion has actually gone off.
    local session = { id = dmhub.GenerateGuid(), start = dmhub.Time(), detonation = nil, exploded = false }
    g_shockHeld[charid] = session
    SendShock(charid, true, true)

    --held to the top and then OVERLOAD_TIME more: the collar blows. The alarm starts
    --early so the explosion lands as the overload runs out; letting go before then
    --defuses it (see StopShock).
    dmhub.Schedule(SHOCK_FULL_TIME + OVERLOAD_TIME - EXPLODE_TIME, function()
        if mod.unloaded or g_shockHeld[charid] ~= session then
            return
        end
        local tok = dmhub.GetTokenById(charid)
        if tok ~= nil then
            session.detonation = BlowUp(tok)
        end
    end)
    dmhub.Schedule(SHOCK_FULL_TIME + OVERLOAD_TIME, function()
        if mod.unloaded or g_shockHeld[charid] ~= session or session.detonation == nil then
            return
        end
        session.exploded = true
        StopShock(charid)
    end)
end

---@param charid string
function StopShock(charid)
    local session = g_shockHeld[charid]
    if session == nil then
        return
    end
    if session.detonation ~= nil and not session.exploded then
        Defuse(charid, session.detonation)
    end
    SendShock(charid, false, true)
    g_shockHeld[charid] = nil
    ApplyShockDamage(charid, dmhub.Time() - session.start)
end

--Brings a blown-up hero back where they stood, at full stamina and still collared,
--and clears their char marks.
---@param charid string
local function Restore(charid)
    local entry = GetExploded()[charid]
    local token = dmhub.GetCharacterById(charid)
    if entry == nil or token == nil or entry.mapid ~= game.currentMapId then
        return
    end

    token:ModifyProperties{
        description = "Restore hero",
        execute = function()
            local props = token.properties
            props.damage_taken = 0
            props:SetTemporaryHitpoints(0)
            props:ResetDeathSavingThrowStatus()
        end,
    }

    --despawned must be cleared before any move; see CorpseComponent:Respawn.
    token.despawned = false
    if token.loc.x ~= entry.x or token.loc.y ~= entry.y or token.loc.floor ~= entry.floor then
        token:ChangeLocation(core.Loc{ x = entry.x, y = entry.y, floorIndex = entry.floor }:WithGroundLevelAltitude())
    end

    if not IsCollared(token) then
        ApplyCollar(token)
    end

    --the token takes a moment to come back onto the map. Until it does, the hero stays
    --recorded as exploded, so the panel never sees them as neither exploded nor present.
    g_busy[charid] = true
    local tries = 0
    local function Finish()
        if mod.unloaded then
            return
        end
        tries = tries + 1
        if dmhub.GetTokenById(charid) == nil and tries < 50 then
            dmhub.Schedule(0.1, Finish)
            return
        end

        g_busy[charid] = nil
        local doc = mod:GetDocumentSnapshot(DOC_ID)
        doc:BeginChange()
        doc.data.exploded[charid] = nil
        doc:CompleteChange("Restore hero", {undoable = false})

        --replay the collar locking on.
        local info = { kind = "collar", tokenid = charid, attach = true }
        dmhub.BroadcastRemoteEvent(REMOTE_EVENT, dmhub.GenerateGuid(), info, true)
        PlayCollarAnimation(info)
    end
    dmhub.Schedule(0.1, Finish)
end

dmhub.RegisterRemoteEvent(REMOTE_EVENT, function(info)
    if mod.unloaded or type(info) ~= "table" or info.tokenid == nil then
        return
    end
    if info.kind == "detonate" then
        PlayDetonation(info)
    elseif info.kind == "shock" then
        PlayShock(info)
    elseif info.kind == "countdown" or info.kind == "disarm" then
        PlayCountdownLight(info)
    elseif info.kind == "defuse" then
        PlayDefuse(info)
    else
        PlayCollarAnimation(info)
    end
end)

---@param token CharacterToken
---@param attach boolean
local function SetCollar(token, attach)
    if g_busy[token.charid] or IsCollared(token) == attach then
        return
    end

    local info = { kind = "collar", tokenid = token.charid, attach = attach }
    dmhub.BroadcastRemoteEvent(REMOTE_EVENT, dmhub.GenerateGuid(), info, true)
    PlayCollarAnimation(info, function()
        local tok = dmhub.GetTokenById(info.tokenid)
        if tok == nil then
            return
        end
        if attach then
            ApplyCollar(tok)
        else
            RemoveCollar(tok)
        end
    end)
end

--------------------------------------------------------------------------------
-- Explosives on the map (the Emperor Busts)
--------------------------------------------------------------------------------

--Map objects lined with explosives, listed in the collar panel under "Explosives on
--Map". Each is an instance of an explosive object asset whose Appearance shows image
--0 intact and 1 ruined. A bust goes off from the panel's Detonate button, or from its
--own aura when a creature comes within 1 square (the aura's Lua Script calls
--CondemnedExplosives.TriggerNear). The object's Appearance is the shared record of
--whether it has gone off, so explosives need no document of their own.
local EXPLOSIVE_ASSETS = {
    --Emperor Bust, in the game's Abbey object folder.
    ["92ade2e0-b2fd-4c22-8638-91c6f6e11d0c"] = true,
}
local EXPLOSIVE_EVENT = "condemnedExplosive"
local EXPLOSIVE_DAMAGE = 10
--creatures within this many squares of the explosive take the damage.
local EXPLOSIVE_RADIUS = 1

---@param obj LuaObjectInstance
---@return LuaObjectComponentField|nil
local function ImageNumberField(obj)
    local app = obj:GetComponent("Appearance")
    if app == nil then
        return nil
    end
    for _, field in ipairs(app.fields) do
        if field.id == "imageNumber" then
            return field
        end
    end
    return nil
end

---@param obj LuaObjectInstance
---@return boolean
local function IsDetonated(obj)
    local field = ImageNumberField(obj)
    return field ~= nil and field:GetValue(1) ~= 0
end

--Every explosive on the current map, sorted by name.
---@return {objid: string, floorid: string, name: string, obj: LuaObjectInstance}[]
local function CollectExplosives()
    local result = {}
    local map = game.currentMap
    if map == nil then
        return result
    end
    for _, floor in ipairs(map.floors) do
        --a floor listed before its details arrive (entering the game) has no objects yet.
        for objid, obj in pairs(floor.valid and floor.objects or {}) do
            if EXPLOSIVE_ASSETS[obj.assetid] then
                result[#result + 1] = { objid = objid, floorid = obj.floorid, name = tostring(obj.name or "Explosive"), obj = obj }
            end
        end
    end
    table.sort(result, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.objid < b.objid
    end)
    return result
end

---@param floorid string
---@param objid string
---@return LuaObjectInstance|nil
local function GetExplosive(floorid, objid)
    local floor = game.GetFloor(floorid)
    if floor == nil then
        return nil
    end
    return floor.objects[objid]
end

--The square an explosive sits on. Objects are positioned by their centre, in the same
--space as token locs.
---@param obj LuaObjectInstance
---@return integer, integer
local function ExplosiveSquare(obj)
    return math.floor(obj.x + 0.5), math.floor(obj.y + 0.5)
end

--Tokens live on a floor's primary layer; an object may sit on one of its layers.
---@param floorid string
---@return string
local function TokenFloorId(floorid)
    local floor = game.GetFloor(floorid)
    if floor ~= nil and floor.parentFloor ~= nil and floor.parentFloor ~= "" then
        return floor.parentFloor
    end
    return floorid
end

--True if any square the token occupies is within EXPLOSIVE_RADIUS of (x, y).
---@param token CharacterToken
---@param x integer
---@param y integer
---@return boolean
local function InBlast(token, x, y)
    for _, loc in ipairs(token.locsOccupying or { token.loc }) do
        if math.abs(loc.x - x) <= EXPLOSIVE_RADIUS and math.abs(loc.y - y) <= EXPLOSIVE_RADIUS then
            return true
        end
    end
    return false
end

---@param objid string
---@return string
local function ExplosiveMarkKey(objid)
    return "explosive:" .. objid
end

--objid -> floorid of the char marks this client has drawn around explosives.
local g_explosiveMarks = {}
local g_explosiveMarksMapId = nil
--objid -> time this client drew marks from a blast, before the object's ruined state
--arrives; until then the marks are not cleared for the bust still looking intact.
local g_explosiveMarksPending = {}

---@param objid string
local function ClearExplosiveMarks(objid)
    g_explosiveMarksPending[objid] = nil
    local floorid = g_explosiveMarks[objid]
    g_explosiveMarks[objid] = nil
    local floor = floorid and game.GetFloor(floorid)
    if floor ~= nil then
        floor:ClearBloodSpatter(CharTag(ExplosiveMarkKey(objid)))
    end
end

--Brings this client's char marks in line with which explosives have gone off. The
--marks are seeded by the object id, so every client draws the same burn.
local function SyncExplosiveMarks()
    local mapid = game.currentMapId
    if mapid ~= g_explosiveMarksMapId then
        g_explosiveMarks = {}
        g_explosiveMarksMapId = mapid
    end

    local detonated = {}
    for _, e in ipairs(CollectExplosives()) do
        if IsDetonated(e.obj) then
            detonated[e.objid] = true
            g_explosiveMarksPending[e.objid] = nil
            if g_explosiveMarks[e.objid] == nil then
                g_explosiveMarks[e.objid] = e.floorid
                DrawCharMarks{ charid = ExplosiveMarkKey(e.objid), floorid = e.floorid, px = e.obj.x, py = e.obj.y, seed = e.objid }
            end
        end
    end

    for objid, _ in pairs(g_explosiveMarks) do
        local pending = g_explosiveMarksPending[objid]
        if pending ~= nil and dmhub.Time() - pending > PENDING_MARKS_GRACE then
            pending = nil
        end
        if not detonated[objid] and pending == nil then
            ClearExplosiveMarks(objid)
        end
    end
end

--Every client: the collars' explosion and boom at the explosive, then the char marks
--once the fireball covers it. info = {objid, x, y, floor, floorid, px, py, mapid}.
local function PlayExplosiveBlast(info)
    if info.mapid ~= game.currentMapId then
        return
    end
    audio.FireSoundEvent(SOUND_EXPLOSION, { volume = EXPLOSION_VOLUME })
    dmhub.PlayEffect{
        id = EXPLOSION_EFFECT,
        loc = core.Loc{ x = info.x, y = info.y, floorIndex = info.floor },
        scale = EXPLOSION_SCALE,
    }
    dmhub.Schedule(VANISH_DELAY, function()
        if mod.unloaded or info.mapid ~= game.currentMapId then
            return
        end
        g_explosiveMarksPending[info.objid] = dmhub.Time()
        g_explosiveMarks[info.objid] = info.floorid
        DrawCharMarks{ charid = ExplosiveMarkKey(info.objid), floorid = info.floorid, px = info.px, py = info.py, seed = info.objid }
    end)
end

--objid -> true while this (Director's) client is setting that explosive off.
local g_explosiveBusy = {}

--Director: blows the explosive up. Every creature within 1 square takes the damage,
--the object turns to its ruined art and goes inactive (which switches its aura off).
---@param floorid string
---@param objid string
local function DetonateExplosive(floorid, objid)
    local obj = GetExplosive(floorid, objid)
    if obj == nil or g_explosiveBusy[objid] or IsDetonated(obj) or ImageNumberField(obj) == nil then
        return
    end
    g_explosiveBusy[objid] = true

    local x, y = ExplosiveSquare(obj)
    local name = tostring(obj.name or "Explosive")
    local info = {
        kind = "detonate",
        objid = objid,
        x = x,
        y = y,
        floor = obj.floorIndex,
        floorid = floorid,
        px = obj.x,
        py = obj.y,
        mapid = game.currentMapId,
    }
    dmhub.BroadcastRemoteEvent(EXPLOSIVE_EVENT, dmhub.GenerateGuid(), info, true)
    PlayExplosiveBlast(info)

    --the bust breaks and the blast lands as the fireball covers it.
    dmhub.Schedule(VANISH_DELAY, function()
        g_explosiveBusy[objid] = nil
        if mod.unloaded then
            return
        end
        local o = GetExplosive(floorid, objid)
        local field = o and ImageNumberField(o)
        if o == nil or field == nil then
            return
        end
        field:SetValue(1, 1)
        field:Upload()
        o.inactive = true
        o:Upload()

        local tokenFloorId = TokenFloorId(floorid)
        for _, tok in ipairs(dmhub.allTokens) do
            if tok.valid and tok.floorid == tokenFloorId and InBlast(tok, x, y) then
                local props = tok.properties
                local dead = false
                pcall(function() dead = props:IsDead() end)
                if not dead then
                    tok:ModifyProperties{
                        description = name .. " explodes",
                        execute = function()
                            props:TakeDamage(EXPLOSIVE_DAMAGE, name .. " explodes", {})
                        end,
                    }
                end
            end
        end
    end)
end

--Director: puts a blown-up explosive back, intact and armed.
---@param floorid string
---@param objid string
local function RestoreExplosive(floorid, objid)
    local obj = GetExplosive(floorid, objid)
    local field = obj and ImageNumberField(obj)
    if obj == nil or field == nil or g_explosiveBusy[objid] then
        return
    end
    field:SetValue(0, 1)
    field:Upload()
    obj.inactive = false
    obj:Upload()

    local info = { kind = "restore", objid = objid, mapid = game.currentMapId }
    dmhub.BroadcastRemoteEvent(EXPLOSIVE_EVENT, dmhub.GenerateGuid(), info, true)
    ClearExplosiveMarks(objid)
end

dmhub.RegisterRemoteEvent(EXPLOSIVE_EVENT, function(info)
    if mod.unloaded or type(info) ~= "table" or info.objid == nil then
        return
    end
    if info.kind == "detonate" then
        PlayExplosiveBlast(info)
    elseif info.kind == "restore" then
        ClearExplosiveMarks(info.objid)
    elseif info.kind == "request" and dmhub.isDM and info.mapid == game.currentMapId then
        --an aura went off on a player's client; the Director's client does the work.
        DetonateExplosive(info.floorid, info.objid)
    end
end)

--The aura fires when a move is committed, while the token is still at the start of its
--path; the blast waits until the token is seen to reach the explosive. A token that
--stops short (or never starts moving) sets it off once it has stood still this long.
local ARRIVAL_IDLE_TIME = 0.75
local ARRIVAL_TIMEOUT = 15
local ARRIVAL_POLL = 0.05

--objid -> true while a triggered explosive waits for its token to arrive.
local g_explosiveArming = {}

--Calls back once the token's on-screen position is next to square (x, y).
---@param token CharacterToken
---@param x integer
---@param y integer
---@param callback fun()
local function WhenTokenArrives(token, x, y, callback)
    local charid = token.charid
    --a big token's centre stands further out when it is next to the explosive.
    local squares = #(token.locsOccupying or { token.loc })
    local reach = EXPLOSIVE_RADIUS + (math.sqrt(squares) - 1) / 2 + 0.1
    local deadline = dmhub.Time() + ARRIVAL_TIMEOUT
    local idleSince = nil

    local function Check()
        if mod.unloaded then
            return
        end
        local tok = dmhub.GetTokenById(charid)
        if tok == nil or dmhub.Time() > deadline then
            callback()
            return
        end

        local pos = tok.pos
        if math.abs(pos.x - x) <= reach and math.abs(pos.y - y) <= reach then
            callback()
            return
        end

        if tok.isMoving then
            idleSince = nil
        elseif idleSince == nil then
            idleSince = dmhub.Time()
        elseif dmhub.Time() - idleSince >= ARRIVAL_IDLE_TIME then
            callback()
            return
        end
        dmhub.Schedule(ARRIVAL_POLL, Check)
    end
    Check()
end

--Called from an explosive's aura script with the creature that just came within 1
--square. Sets off the intact explosive next to it once the creature gets there; any
--client may call it.
CondemnedExplosives = {
    ---@param token CharacterToken
    TriggerNear = function(token)
        if mod.unloaded or token == nil or not token.valid then
            return
        end
        for _, e in ipairs(CollectExplosives()) do
            if TokenFloorId(e.floorid) == token.floorid and not IsDetonated(e.obj) then
                local x, y = ExplosiveSquare(e.obj)
                if InBlast(token, x, y) then
                    if g_explosiveArming[e.objid] then
                        return
                    end
                    g_explosiveArming[e.objid] = true
                    local floorid, objid, mapid = e.floorid, e.objid, game.currentMapId
                    WhenTokenArrives(token, x, y, function()
                        g_explosiveArming[objid] = nil
                        if mapid ~= game.currentMapId then
                            return
                        end
                        if dmhub.isDM then
                            DetonateExplosive(floorid, objid)
                        else
                            local info = { kind = "request", objid = objid, floorid = floorid, mapid = mapid }
                            dmhub.BroadcastRemoteEvent(EXPLOSIVE_EVENT, dmhub.GenerateGuid(), info, true)
                        end
                    end)
                    return
                end
            end
        end
    end,
}

--------------------------------------------------------------------------------
-- Per-client upkeep: lights on collared tokens, char marks, old collar art
--------------------------------------------------------------------------------

local function Upkeep()
    local constant = GetLedMode() == LED_MODE_CONSTANT
    if constant ~= g_ledConstant then
        g_ledConstant = constant
        for _, led in pairs(g_leds) do
            if led.valid then
                led:FireEvent("ledMode")
            end
        end
    end

    local seen = {}
    for _, tok in ipairs(dmhub.allTokens) do
        if IsCollared(tok) then
            local charid = tok.charid
            seen[charid] = true

            if g_explosionWarmMap ~= game.currentMapId then
                g_explosionWarmMap = game.currentMapId
                WarmExplosion(tok.loc.floor)
            end

            --the light lives on the token sheet, which is rebuilt now and then.
            local led = g_leds[charid]
            if (led == nil or not led.valid) and tok.sheet ~= nil then
                led = CreateLed(tok)
                tok.sheet:AddChild(led)
                g_leds[charid] = led
                local countdown = g_ledCountdowns[charid]
                if countdown ~= nil and countdown.endsAt > dmhub.Time() then
                    led:FireEvent("countdown", countdown.id, countdown.endsAt - dmhub.Time())
                end
                local rig = g_shockRigs[charid]
                if rig ~= nil and rig.valid and rig.data.active then
                    led:FireEvent("shockStart")
                end
            end

            --collars put on before the art was last regenerated still show the old
            --albedo, which no longer matches the frame's normal map.
            if dmhub.isDM and tok.portraitFrame ~= COLLAR_ALBEDO then
                tok.portraitFrame = COLLAR_ALBEDO
                tok:UploadAppearance()
            end
        end
    end

    --a countdown whose detonate or disarm message never arrived must not linger.
    for charid, countdown in pairs(g_ledCountdowns) do
        if dmhub.Time() > countdown.endsAt + 5 then
            g_ledCountdowns[charid] = nil
        end
    end

    for charid, led in pairs(g_leds) do
        if not seen[charid] then
            if led.valid then
                led:DestroySelf()
            end
            g_leds[charid] = nil
        end
    end

    SyncCharMarks()

    --an explosive can go off with no collar on the map, so it warms the explosion too.
    if g_explosionWarmMap ~= game.currentMapId then
        local explosives = CollectExplosives()
        if #explosives > 0 then
            g_explosionWarmMap = game.currentMapId
            WarmExplosion(explosives[1].obj.floorIndex)
        end
    end
    SyncExplosiveMarks()
end

dmhub.Coroutine(function()
    while not mod.unloaded do
        local ok, err = pcall(Upkeep)
        if not ok then
            print("Condemned: upkeep failed:", err)
            coroutine.yield(5)
        end
        coroutine.yield(0.25)
    end
end)

--------------------------------------------------------------------------------
-- The Loyalty Collars panel
--------------------------------------------------------------------------------

--The heroes the panel lists: hero tokens on the current map, plus heroes blown up
--on this map. One list sorted by name, so a hero keeps its place whatever happens to it.
---@return {charid: string, token: CharacterToken, name: string}[]
local function CollectRowEntries()
    local result = {}
    local listed = {}
    for _, tok in ipairs(dmhub.allTokens) do
        local ok, isHero = pcall(function() return tok.properties ~= nil and tok.properties:IsHero() end)
        if ok and isHero then
            listed[tok.charid] = true
            result[#result + 1] = { charid = tok.charid, token = tok, name = tok.name or "" }
        end
    end

    for charid, entry in pairs(GetExploded()) do
        if not listed[charid] and entry.mapid == game.currentMapId then
            local tok = dmhub.GetCharacterById(charid)
            if tok ~= nil then
                result[#result + 1] = { charid = charid, token = tok, name = entry.name or tok.name or "" }
            end
        end
    end

    table.sort(result, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.charid < b.charid
    end)
    return result
end

--------------------------------------------------------------------------------
-- Explode countdown
--------------------------------------------------------------------------------

--Explode does not go off at once: the Director's row counts down from 3 with a Cancel
--button, and only then does the detonation (BlowUp) start. The countdown lives here
--rather than in the row, so closing the panel does not quietly drop it.
local COUNTDOWN_SECONDS = 3

--charid -> {id, endsAt, firing, detonation} while a countdown runs on this (Director's)
--client. detonation is BlowUp's info once the alarm has started; firing is set once
--the explosion has gone off and it can no longer be cancelled.
local g_countdowns = {}

--Tells every client (this one included) to start or stop the red countdown blink.
---@param charid string
---@param kind string "countdown" or "disarm"
---@param id string
local function SendCountdownLight(charid, kind, id)
    local info = { kind = kind, tokenid = charid, id = id, remaining = COUNTDOWN_SECONDS }
    dmhub.BroadcastRemoteEvent(REMOTE_EVENT, dmhub.GenerateGuid(), info, true)
    PlayCountdownLight(info)
end

---@param charid string
local function StartCountdown(charid)
    if g_countdowns[charid] ~= nil or g_busy[charid] then
        return
    end
    StopShock(charid)

    local countdown = { id = dmhub.GenerateGuid(), endsAt = dmhub.Time() + COUNTDOWN_SECONDS, firing = false, detonation = nil }
    g_countdowns[charid] = countdown
    --the light only needs its own red countdown blink when the countdown outlasts the
    --detonation alarm; otherwise the alarm's blinks would double up with it.
    if COUNTDOWN_SECONDS > EXPLODE_TIME then
        SendCountdownLight(charid, "countdown", countdown.id)
    end

    --the detonation's alarm beeps play at the end, so the explosion lands as the
    --countdown reaches zero. It can still be cancelled (defused) until then.
    dmhub.Schedule(COUNTDOWN_SECONDS - EXPLODE_TIME, function()
        if mod.unloaded or g_countdowns[charid] ~= countdown then
            return
        end
        local tok = dmhub.GetTokenById(charid)
        if tok ~= nil then
            countdown.detonation = BlowUp(tok)
        end
        if countdown.detonation == nil then
            g_countdowns[charid] = nil
            SendCountdownLight(charid, "disarm", countdown.id)
        end
    end)

    dmhub.Schedule(COUNTDOWN_SECONDS, function()
        if mod.unloaded or g_countdowns[charid] ~= countdown then
            return
        end
        countdown.firing = true
        --keeps the row on "Detonating!" until the hero is gone.
        dmhub.Schedule(VANISH_DELAY + 0.5, function()
            if g_countdowns[charid] == countdown then
                g_countdowns[charid] = nil
            end
        end)
    end)
end

---@param charid string
local function CancelCountdown(charid)
    local countdown = g_countdowns[charid]
    if countdown ~= nil and not countdown.firing then
        g_countdowns[charid] = nil
        if countdown.detonation ~= nil then
            Defuse(charid, countdown.detonation)
        else
            SendCountdownLight(charid, "disarm", countdown.id)
        end
    end
end

--Row layout widths; the countdown view lines its Cancel button up with Explode.
local STATUS_WIDTH = 76
local MAIN_BUTTON_WIDTH = 112
local SHOCK_BUTTON_WIDTH = 72
local EXPLODE_BUTTON_WIDTH = 84
local BUTTON_GAP = 6

--Styles for the row: Explode in danger red, and the countdown text.
local g_rowStyles = {
    {
        selectors = {"condemnedExplode"},
        bgcolor = "#c73131",
        borderColor = "#ff7a6a",
        color = "white",
        priority = 10,
    },
    {
        selectors = {"condemnedExplode", "hover", "~disabled"},
        bgcolor = "#e8413a",
        borderColor = "#ffb0a0",
        color = "white",
        priority = 10,
    },
    {
        selectors = {"condemnedCountdown"},
        color = "#ff5a4a",
        priority = 10,
    },
}

--One row per hero. A row follows its hero through every state: uncollared,
--collared, and blown up (despawned, kept in the shared document). Rows never collapse
--themselves (a collapsed panel stops thinking); the list adds and removes them.
---@param token CharacterToken
---@param fallbackName string
---@return Panel
local function CreateHeroRow(token, fallbackName)
    local charid = token.charid

    local portrait = gui.CreateTokenImage(token, {
        width = 44,
        height = 44,
        valign = "center",
    })

    local statusLabel = gui.Label{
        classes = {"sizeS"},
        width = STATUS_WIDTH,
        height = "auto",
        valign = "center",
        text = "",
    }

    local mainButton = gui.Button{
        classes = {"sizeS"},
        width = MAIN_BUTTON_WIDTH,
        valign = "center",
        text = "Attach Collar",
        click = function(element)
            if not dmhub.isDM or element:HasClass("disabled") then
                return
            end
            local tok = dmhub.GetTokenById(charid)
            if tok ~= nil then
                SetCollar(tok, not IsCollared(tok))
            elseif GetExploded()[charid] ~= nil then
                Restore(charid)
            end
        end,
    }

    local explodeButton = gui.Button{
        --hidden rather than collapsed, so every row keeps the same layout.
        classes = {"sizeS", "hidden", "condemnedExplode"},
        width = EXPLODE_BUTTON_WIDTH,
        valign = "center",
        lmargin = BUTTON_GAP,
        text = "Explode",
        click = function(element)
            if not dmhub.isDM or element:HasClass("disabled") then
                return
            end
            if dmhub.GetTokenById(charid) ~= nil then
                StartCountdown(charid)
            end
        end,
    }

    --press and hold: the shock lasts as long as the button is held down.
    local shockButton = gui.Button{
        classes = {"sizeS", "hidden"},
        width = SHOCK_BUTTON_WIDTH,
        valign = "center",
        lmargin = BUTTON_GAP,
        text = "Shock",
        thinkTime = SHOCK_HEARTBEAT,
        press = function(element)
            if not dmhub.isDM or element:HasClass("disabled") then
                return
            end
            StartShock(charid)
        end,
        unpress = function(element)
            StopShock(charid)
        end,
        --sends the heartbeat, and lets go if the release was missed (e.g. the mouse
        --came up somewhere else).
        think = function(element)
            if g_shockHeld[charid] == nil then
                return
            end
            if not element:GetMouseButton(0) or element:HasClass("disabled") then
                StopShock(charid)
            else
                SendShock(charid, true, false)
            end
        end,
        destroy = function(element)
            StopShock(charid)
        end,
    }

    --the normal controls; swapped for the countdown while one runs.
    local controls = gui.Panel{
        width = "auto",
        height = "100%",
        flow = "horizontal",
        children = {
            statusLabel,
            mainButton,
            shockButton,
            explodeButton,
        },
    }

    --as wide as everything left of Explode, so Cancel lands exactly where Explode was.
    local countdownLabel = gui.Label{
        classes = {"sizeS", "bold", "condemnedCountdown"},
        width = STATUS_WIDTH + MAIN_BUTTON_WIDTH + BUTTON_GAP + SHOCK_BUTTON_WIDTH,
        height = "auto",
        valign = "center",
        text = "",
    }

    local cancelButton = gui.Button{
        classes = {"sizeS"},
        width = EXPLODE_BUTTON_WIDTH,
        valign = "center",
        lmargin = BUTTON_GAP,
        text = "Cancel",
        click = function(element)
            CancelCountdown(charid)
        end,
    }

    local countdownPanel = gui.Panel{
        classes = {"collapsed"},
        width = "auto",
        height = "100%",
        flow = "horizontal",
        children = { countdownLabel, cancelButton },
    }

    return gui.Panel{
        width = "100%",
        height = 52,
        flow = "horizontal",
        --fast enough that the countdown ticks over close to each second.
        thinkTime = 0.1,
        styles = g_rowStyles,
        data = {
            state = nil,
        },

        create = function(element)
            element:FireEvent("think")
        end,

        think = function(element)
            local tok = dmhub.GetTokenById(charid)
            local state
            if tok ~= nil then
                state = cond(IsCollared(tok), "collared", "free")
            elseif GetExploded()[charid] ~= nil then
                state = "exploded"
            else
                state = "gone"
            end

            --a countdown takes over the row until the hero is blown up or it is cancelled.
            local countdown = g_countdowns[charid]
            if state == "exploded" or state == "gone" then
                countdown = nil
            end
            controls:SetClass("collapsed", countdown ~= nil)
            countdownPanel:SetClass("collapsed", countdown == nil)
            if countdown ~= nil then
                if countdown.firing then
                    countdownLabel.text = "Detonating!"
                else
                    local n = math.max(1, math.ceil(countdown.endsAt - dmhub.Time()))
                    countdownLabel.text = string.format("Detonating in %d...", n)
                end
                cancelButton:SetClass("hidden", countdown.firing)
            end

            local busy = g_busy[charid] == true or state == "gone"
            mainButton:SetClass("disabled", busy)
            explodeButton:SetClass("disabled", busy)
            --while held, an overload's own detonation must not disable (and so release) it.
            shockButton:SetClass("disabled", (busy and g_shockHeld[charid] == nil) or state ~= "collared")

            if state ~= element.data.state then
                element.data.state = state
                if state == "collared" then
                    statusLabel.text = "Collared"
                    mainButton.text = "Remove Collar"
                elseif state == "exploded" then
                    statusLabel.text = "Destroyed"
                    mainButton.text = "Restore"
                else
                    statusLabel.text = ""
                    mainButton.text = "Attach Collar"
                end
                explodeButton:SetClass("hidden", state ~= "collared")
                shockButton:SetClass("hidden", state ~= "collared")
                local t = tok or dmhub.GetCharacterById(charid)
                if t ~= nil then
                    portrait:FireEventTree("token", t)
                end
            end
        end,

        children = {
            portrait,
            gui.Label{
                classes = {"sizeS"},
                width = 160,
                height = "auto",
                valign = "center",
                lmargin = 8,
                text = token.name or fallbackName or "(unnamed)",
            },
            controls,
            countdownPanel,
        },
    }
end

--One row per explosive on the map: its art, name (click to look at it), status, and
--Detonate or Restore. Like the hero rows, rows follow state on their own.
---@param entry {objid: string, floorid: string, name: string, obj: LuaObjectInstance}
---@return Panel
local function CreateExplosiveRow(entry)
    local objid = entry.objid
    local floorid = entry.floorid

    local statusLabel = gui.Label{
        classes = {"sizeS"},
        width = STATUS_WIDTH,
        height = "auto",
        valign = "center",
        text = "",
    }

    local detonateButton = gui.Button{
        classes = {"sizeS", "condemnedExplode"},
        width = MAIN_BUTTON_WIDTH,
        valign = "center",
        text = "Detonate",
        click = function(element)
            if not dmhub.isDM or element:HasClass("disabled") then
                return
            end
            DetonateExplosive(floorid, objid)
        end,
    }

    local restoreButton = gui.Button{
        classes = {"sizeS", "collapsed"},
        width = MAIN_BUTTON_WIDTH,
        valign = "center",
        text = "Restore",
        click = function(element)
            if not dmhub.isDM or element:HasClass("disabled") then
                return
            end
            RestoreExplosive(floorid, objid)
        end,
    }

    local floor = game.GetFloor(floorid)
    local floorName = floor and tostring(floor.description or "") or ""

    return gui.Panel{
        width = "100%",
        height = 52,
        flow = "horizontal",
        thinkTime = 0.25,
        styles = g_rowStyles,
        data = {
            detonated = nil,
        },

        create = function(element)
            element:FireEvent("think")
        end,

        --outline the explosive on the map while its row is hovered (buttons included:
        --they do not take the hover away from the row).
        hover = function(element)
            local obj = GetExplosive(floorid, objid)
            if obj ~= nil then
                obj.editorFocus = true
            end
        end,

        dehover = function(element)
            local obj = GetExplosive(floorid, objid)
            if obj ~= nil then
                obj.editorFocus = false
            end
        end,

        --closing the popup under the mouse must not leave the outline behind.
        destroy = function(element)
            local obj = GetExplosive(floorid, objid)
            if obj ~= nil and obj.editorFocus then
                obj.editorFocus = false
            end
        end,

        think = function(element)
            local obj = GetExplosive(floorid, objid)
            local detonated = obj ~= nil and IsDetonated(obj)
            local busy = obj == nil or g_explosiveBusy[objid] == true
            detonateButton:SetClass("disabled", busy)
            restoreButton:SetClass("disabled", busy)
            if detonated ~= element.data.detonated then
                element.data.detonated = detonated
                statusLabel.text = cond(detonated, "Exploded", "Armed")
                detonateButton:SetClass("collapsed", detonated)
                restoreButton:SetClass("collapsed", not detonated)
            end
        end,

        children = {
            gui.Panel{
                width = 44,
                height = 44,
                valign = "center",
                bgimage = entry.obj.displayImageId,
                bgcolor = "white",
            },
            gui.Panel{
                width = 160,
                height = "auto",
                valign = "center",
                lmargin = 8,
                flow = "vertical",
                children = {
                    gui.Label{
                        classes = {"sizeS"},
                        width = "100%",
                        height = "auto",
                        text = entry.name,
                        hover = gui.Tooltip("Show on the map"),
                        click = function(element)
                            local obj = GetExplosive(floorid, objid)
                            if obj ~= nil then
                                obj:CenterCamera{smooth = true}
                            end
                        end,
                    },
                    gui.Label{
                        classes = {"sizeXs"},
                        width = "100%",
                        height = "auto",
                        text = floorName,
                    },
                },
            },
            statusLabel,
            detonateButton,
            restoreButton,
        },
    }
end

local function CreateCollarPanel()
    --keeps one row per listed hero, in name order, adding and removing rows as heroes
    --arrive, leave or are blown up. Existing rows are reused so they keep their state.
    local listPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        thinkTime = 0.25,
        data = {
            rows = {},
            key = nil,
        },

        create = function(element)
            element:FireEvent("think")
        end,

        think = function(element)
            local entries = CollectRowEntries()
            local ids = {}
            for i, e in ipairs(entries) do
                ids[i] = e.charid
            end
            local key = table.concat(ids, ",")
            if key == element.data.key then
                return
            end
            element.data.key = key

            local rows = element.data.rows
            local children = {}
            local keep = {}
            for _, e in ipairs(entries) do
                local row = rows[e.charid]
                if row == nil or not row.valid then
                    row = CreateHeroRow(e.token, e.name)
                    rows[e.charid] = row
                end
                keep[e.charid] = true
                children[#children + 1] = row
            end
            for charid, _ in pairs(rows) do
                if not keep[charid] then
                    rows[charid] = nil
                end
            end

            if #children == 0 then
                children[1] = gui.Label{
                    classes = {"sizeS"},
                    width = "auto",
                    height = "auto",
                    text = "No heroes on this map.",
                }
            end

            element.children = children
        end,
    }

    --how the green light behaves on every collar, shared with all clients via the doc.
    local ledModeRow = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        bmargin = 8,
        children = {
            gui.Label{
                classes = {"sizeS"},
                width = "auto",
                height = "auto",
                valign = "center",
                rmargin = 8,
                text = "Collar light:",
            },
            gui.Dropdown{
                classes = {"sizeS"},
                width = 140,
                height = 24,
                valign = "center",
                options = {
                    { id = LED_MODE_BLINK, text = "Blinking" },
                    { id = LED_MODE_CONSTANT, text = "Constant" },
                },
                idChosen = GetLedMode(),
                monitorGame = mod:GetDocumentPath(DOC_ID),
                refreshGame = function(element)
                    ---@cast element Dropdown
                    element.idChosen = GetLedMode()
                end,
                change = function(element)
                    ---@cast element Dropdown
                    local mode = element.idChosen
                    if not dmhub.isDM or mode == GetLedMode() then
                        return
                    end
                    local doc = mod:GetDocumentSnapshot(DOC_ID)
                    doc:BeginChange()
                    doc.data.ledMode = mode
                    doc:CompleteChange("Collar light", {undoable = false})
                end,
            },
        },
    }

    --"Explosives on Map": shown only while the current map has explosives on it. Rows
    --are kept per object, the same way as the hero list.
    local explosiveList = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        data = {
            rows = {},
        },
    }

    --the title collapses rather than the section: a collapsed panel stops thinking, and
    --the section's think is what notices explosives arriving on the map.
    local explosivesTitle = gui.Label{
        classes = {"sizeL", "bold", "collapsed"},
        width = "auto",
        height = "auto",
        tmargin = 10,
        bmargin = 6,
        text = "Explosives on Map",
    }

    local explosivesSection = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        thinkTime = 0.25,
        data = {
            key = nil,
        },

        create = function(element)
            element:FireEvent("think")
        end,

        think = function(element)
            local entries = CollectExplosives()
            local ids = {}
            for i, e in ipairs(entries) do
                ids[i] = e.objid
            end
            local key = table.concat(ids, ",")
            if key == element.data.key then
                return
            end
            element.data.key = key

            local rows = explosiveList.data.rows
            local children = {}
            local keep = {}
            for _, e in ipairs(entries) do
                local row = rows[e.objid]
                if row == nil or not row.valid then
                    row = CreateExplosiveRow(e)
                    rows[e.objid] = row
                end
                keep[e.objid] = true
                children[#children + 1] = row
            end
            for objid, _ in pairs(rows) do
                if not keep[objid] then
                    rows[objid] = nil
                end
            end
            explosiveList.children = children
            explosivesTitle:SetClass("collapsed", #children == 0)
        end,

        children = {
            explosivesTitle,
            explosiveList,
        },
    }

    --the map button bar does not pass a themed cascade to its popups, so the popup
    --roots its own. A panel's styles only reach its descendants, so the framed
    --surface is a child of the styled root.
    return gui.Panel{
        styles = ThemeEngine.GetStyles(),
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "bottom",
        children = {
            gui.Panel{
                classes = {"framedPanel"},
                width = 620,
                height = "auto",
                flow = "vertical",
                borderBox = true,
                hpad = 12,
                vpad = 10,
                children = {
                    gui.Label{
                        classes = {"sizeL", "bold"},
                        width = "auto",
                        height = "auto",
                        bmargin = 6,
                        text = "Loyalty Collars",
                    },
                    ledModeRow,
                    listPanel,
                    explosivesSection,
                },
            },
        },
    }
end

local mapButtons = rawget(_G, "MapButtons")
if mapButtons ~= nil then
    mapButtons.Register("condemned:collars", {
        name = "Loyalty Collars",
        icon = "phosphor/lock-simple-fill.png",
        tooltip = "Loyalty Collars",
        directorOnly = true,
        click = function(element)
            if mod.unloaded then
                return
            end
            element.popup = CreateCollarPanel()
        end,
    })
end

--------------------------------------------------------------------------------
-- The Cauldron's security doors
--------------------------------------------------------------------------------

--a function of its own: the file's main chunk is at Lua's 200-local limit, and a
--do block would not help (its locals still count against the main chunk).
;(function()

    --The Cauldron prison map has an energy door on every cell: a force field across the
    --doorway and a lit power conduit running to it from the spider lock in the middle of
    --the room. Each part is its own map object, keyworded "cauldron-doors" and "cellNN"
    --(NN = 01-16, clockwise from the north wall). A door is open when its objects are
    --disabled (inactive): players no longer see them and the field stops blocking.
    --The Security Doors map button appears only on a map that has these objects.

    local DOORS_KEYWORD = "cauldron-doors"
    local DOORS_BUTTON_ID = "condemned:cauldron-doors"

    --display names; any other number is shown as "Cell NN".
    local DOOR_NAMES = {
        ["01"] = "North Conduit",
        ["02"] = "Large Cell NE",
        ["09"] = "Main Gate",
        ["16"] = "Large Cell NW",
    }

    --the panel is a schematic of the room: rows of {left, centre, right} door numbers
    --(nil leaves the slot empty), top of the map first.
    local DOOR_LAYOUT = {
        { "16", "01", "02" },
        { "15", nil, "03" },
        { "14", nil, "04" },
        { "13", nil, "05" },
        { "12", nil, "06" },
        { "11", nil, "07" },
        { "10", nil, "08" },
        { nil, "09", nil },
    }

    local DOOR_TILE_WIDTH = 180
    local DOOR_TILE_HEIGHT = 44
    local DOOR_TILE_GAP = 8

    local g_doorStyles = {
        {
            selectors = {"condemnedDoorTile"},
            bgcolor = "#14181c",
            borderColor = "#3a4248",
            borderWidth = 1,
            cornerRadius = 4,
        },
        {
            selectors = {"condemnedDoorTile", "sealed"},
            bgcolor = "#0d2a31",
            borderColor = "#36d6f0",
        },
        {
            selectors = {"condemnedDoorTile", "partial"},
            borderColor = "#d9a640",
        },
        {
            selectors = {"condemnedDoorTile", "hover"},
            borderColor = "#c8f6ff",
        },
        {
            selectors = {"condemnedDoorLight"},
            bgcolor = "#3a4248",
            cornerRadius = 7,
        },
        {
            selectors = {"condemnedDoorLight", "parent:sealed"},
            bgcolor = "#5ff0ff",
        },
        {
            selectors = {"condemnedDoorLight", "parent:partial"},
            bgcolor = "#d9a640",
        },
    }

    ---@alias CauldronDoorRef {floorid: string, objid: string, kind: string}
    ---@alias CauldronDoor {n: string, refs: CauldronDoorRef[]}

    --Every door on the current map, keyed by its two-digit number. Each door lists the
    --objects that make it up, by floor and object id (looked up fresh when used), and
    --whether each is the "line" (conduit) or the "field".
    ---@return table<string, CauldronDoor>
    local function CollectCauldronDoors()
        local doors = {}
        local map = game.currentMap
        if map == nil then
            return doors
        end
        for _, floor in ipairs(map.floors) do
            --a floor listed before its details arrive (entering the game) has no objects yet.
            for objid, obj in pairs(floor.valid and floor.objects or {}) do
                local keywords = obj.keywords
                if type(keywords) == "table" and keywords[DOORS_KEYWORD] then
                    for word, _ in pairs(keywords) do
                        local n = string.match(tostring(word), "^cell(%d%d)$")
                        if n ~= nil then
                            local door = doors[n]
                            if door == nil then
                                door = { n = n, refs = {} }
                                doors[n] = door
                            end
                            door.refs[#door.refs + 1] = {
                                floorid = floor.floorid,
                                objid = objid,
                                kind = cond(keywords["cauldron-fields"], "field", "line"),
                            }
                        end
                    end
                end
            end
        end
        return doors
    end

    ---@param ref CauldronDoorRef
    ---@return LuaObjectInstance|nil
    local function DoorObject(ref)
        local floor = game.GetFloor(ref.floorid)
        if floor == nil then
            return nil
        end
        return floor.objects[ref.objid]
    end

    --"sealed" when every part is active, "open" when every part is disabled, else "partial".
    ---@param door CauldronDoor
    ---@return string
    local function DoorState(door)
        local active, inactive = 0, 0
        for _, ref in ipairs(door.refs) do
            local obj = DoorObject(ref)
            if obj ~= nil then
                if obj.inactive then
                    inactive = inactive + 1
                else
                    active = active + 1
                end
            end
        end
        if inactive == 0 then
            return "sealed"
        elseif active == 0 then
            return "open"
        end
        return "partial"
    end

    --Doors fade rather than snap. Every client plays the fade locally by setting the
    --object's Appearance opacity and brightness without uploading them; only the
    --Director's client changes the saved state (inactive).
    local DOOR_EVENT = "condemnedDoors"
    local DOOR_FADE_TIME = 0.9
    --brightness multiplier at the peak of the power-down flare (the Appearance max is 2).
    local DOOR_FLARE = 1.9
    --the share of the fade spent flaring up before the light drains away.
    local DOOR_FLARE_SHARE = 0.3
    --the field follows its conduit by this much, and each door in Seal All / Open All
    --follows the one before by DOOR_RIPPLE.
    local DOOR_STAGGER = 0.25
    local DOOR_RIPPLE = 0.06
    --sealing: the objects are enabled first (at opacity 0) and fade in after this long,
    --so the enable has reached every client before the fade starts.
    local DOOR_SEAL_LEAD = 0.25
    --the Director sees a disabled object at 40% opacity, so its fade ends there.
    local DIRECTOR_GHOST_OPACITY = 0.4

    --objid -> id of the fade currently driving that object; a newer fade takes over.
    local g_doorFades = {}
    --door number -> "down" or "up" while a click's fade is running, so it cannot be
    --clicked again and its tile can say what it is doing.
    local g_doorBusy = {}

    local function EaseOutCubic(t)
        return 1 - (1 - t) ^ 3
    end

    --The look of a door at u (0 = fully on, 1 = fully off) on the way off; sealing plays
    --it backwards. Brightness surges to the flare, then the light drains as it settles.
    ---@param u number
    ---@param floorOpacity number
    ---@return number opacity, number brightness
    local function DoorFadeCurve(u, floorOpacity)
        if u < DOOR_FLARE_SHARE then
            local k = EaseOutCubic(u / DOOR_FLARE_SHARE)
            return 1, 1 + (DOOR_FLARE - 1) * k
        end
        local k = (u - DOOR_FLARE_SHARE) / (1 - DOOR_FLARE_SHARE)
        local brightness = DOOR_FLARE - (DOOR_FLARE - 1) * EaseOutCubic(k)
        local opacity = 1 - (1 - floorOpacity) * (k * k)
        return opacity, brightness
    end

    ---@param obj LuaObjectInstance
    ---@return LuaObjectComponentField|nil opacity, LuaObjectComponentField|nil brightness
    local function AppearanceFields(obj)
        local app = obj:GetComponent("Appearance")
        if app == nil then
            return nil, nil
        end
        local opacity, brightness = nil, nil
        for _, field in ipairs(app.fields) do
            if field.id == "opacity" then
                opacity = field
            elseif field.id == "brightness" then
                brightness = field
            end
        end
        return opacity, brightness
    end

    --The fade needs an Appearance component on every part. The Director adds any that
    --are missing (when the panel opens, so they have synced before the first click).
    ---@param doors table<string, CauldronDoor>
    local function EnsureDoorAppearance(doors)
        if not dmhub.isDM then
            return
        end
        for _, door in pairs(doors) do
            for _, ref in ipairs(door.refs) do
                local obj = DoorObject(ref)
                if obj ~= nil and obj:GetComponent("Appearance") == nil then
                    obj:AddComponentFromJson(dmhub.GenerateGuid(), {
                        ["@class"] = "ObjectComponentAppearance",
                        opacity = 1,
                        brightness = 1,
                    })
                    obj:Upload()
                end
            end
        end
    end

    --Plays one object's fade on this client. open = fading out. A fade out holds at the
    --end until the object is actually disabled, so it never pops back to full before the
    --Director's change arrives; then the saved look is restored.
    ---@param ref CauldronDoorRef
    ---@param open boolean
    ---@param delay number
    local function FadeDoorObject(ref, open, delay)
        local id = dmhub.GenerateGuid()
        g_doorFades[ref.objid] = id
        local floorOpacity = cond(dmhub.isDM, DIRECTOR_GHOST_OPACITY, 0)

        dmhub.Coroutine(function()
            local function current()
                return not mod.unloaded and g_doorFades[ref.objid] == id
            end

            local obj = DoorObject(ref)
            if obj == nil then
                return
            end
            local opacity, brightness = AppearanceFields(obj)
            if opacity == nil or brightness == nil then
                return
            end

            --sealing: stay invisible until this part's turn.
            if not open then
                opacity:SetValue(floorOpacity)
                brightness:SetValue(1)
            end
            if delay > 0 then
                coroutine.yield(delay)
            end

            local start = dmhub.Time()
            while current() do
                local u = math.min(1, (dmhub.Time() - start) / DOOR_FADE_TIME)
                local o, b = DoorFadeCurve(cond(open, u, 1 - u), floorOpacity)
                opacity:SetValue(o)
                brightness:SetValue(b)
                if u >= 1 then
                    break
                end
                coroutine.yield(0.01)
            end

            if open then
                local waitUntil = dmhub.Time() + 3
                while current() and dmhub.Time() < waitUntil do
                    obj = DoorObject(ref)
                    if obj == nil or obj.inactive then
                        break
                    end
                    coroutine.yield(0.05)
                end
            end

            if current() then
                opacity:SetValue(1)
                brightness:SetValue(1)
                g_doorFades[ref.objid] = nil
            end
        end)
    end

    --info = { mapid, open, parts = { {floorid, objid, kind, delay}, ... } }
    ---@param info table
    local function PlayDoorFade(info)
        if info.mapid ~= game.currentMapId or type(info.parts) ~= "table" then
            return
        end
        for _, part in ipairs(info.parts) do
            FadeDoorObject(part, info.open == true, tonumber(part.delay) or 0)
        end
    end

    dmhub.RegisterRemoteEvent(DOOR_EVENT, function(info)
        if mod.unloaded or type(info) ~= "table" then
            return
        end
        PlayDoorFade(info)
    end)

    --Opens (fades out, then disables) or seals (enables, then fades in) every part of a
    --door, conduit first. Director only. Setting inactive saves and syncs by itself.
    ---@param door CauldronDoor
    ---@param open boolean
    ---@param ripple number extra delay before this door starts, for Seal All / Open All
    local function SetDoorOpen(door, open, ripple)
        if not dmhub.isDM or g_doorBusy[door.n] then
            return
        end

        local parts = {}
        for _, ref in ipairs(door.refs) do
            local obj = DoorObject(ref)
            if obj ~= nil and obj.inactive ~= open then
                local delay = ripple + cond(ref.kind == "field", DOOR_STAGGER, 0) + cond(open, 0, DOOR_SEAL_LEAD)
                parts[#parts + 1] = { floorid = ref.floorid, objid = ref.objid, kind = ref.kind, delay = delay }
            end
        end
        if #parts == 0 then
            return
        end

        g_doorBusy[door.n] = cond(open, "down", "up")
        local info = { mapid = game.currentMapId, open = open, parts = parts }
        dmhub.BroadcastRemoteEvent(DOOR_EVENT, dmhub.GenerateGuid(), info, true)
        PlayDoorFade(info)

        local finish = 0
        for _, part in ipairs(parts) do
            --opening disables a part once its fade has finished; sealing enables it
            --straight away (it is held invisible until its fade begins).
            local at = cond(open, part.delay + DOOR_FADE_TIME, ripple)
            finish = math.max(finish, part.delay + DOOR_FADE_TIME)
            dmhub.Schedule(at, function()
                if mod.unloaded then
                    return
                end
                local obj = DoorObject(part)
                if obj ~= nil and obj.inactive ~= open then
                    obj.inactive = open
                end
            end)
        end
        dmhub.Schedule(finish, function()
            g_doorBusy[door.n] = nil
        end)
    end

    ---@param door CauldronDoor
    ---@param focus boolean
    local function FocusDoor(door, focus)
        for _, ref in ipairs(door.refs) do
            local obj = DoorObject(ref)
            if obj ~= nil and obj.editorFocus ~= focus then
                obj.editorFocus = focus
            end
        end
    end

    --One door in the schematic. Click to open or seal it; hovering outlines its field and
    --conduit on the map.
    ---@param door CauldronDoor
    ---@param lmargin number
    local function CreateDoorTile(door, lmargin)
        local stateLabel = gui.Label{
            classes = {"sizeXs"},
            width = "100%",
            height = "auto",
            text = "",
        }

        return gui.Panel{
            classes = {"condemnedDoorTile"},
            bgimage = true,
            width = DOOR_TILE_WIDTH,
            height = DOOR_TILE_HEIGHT,
            lmargin = lmargin,
            flow = "horizontal",
            hpad = 10,
            borderBox = true,
            thinkTime = 0.25,
            data = {
                state = nil,
            },
            linger = gui.Tooltip("Click to open or seal this door and its power conduit."),

            create = function(element)
                element:FireEvent("think")
            end,

            think = function(element)
                local state = DoorState(door)
                local busy = g_doorBusy[door.n]
                local key = state .. "/" .. tostring(busy)
                if key == element.data.state then
                    return
                end
                element.data.state = key
                element:SetClass("sealed", state == "sealed")
                element:SetClass("partial", state == "partial")
                if busy == "down" then
                    stateLabel.text = "Powering down..."
                elseif busy == "up" then
                    stateLabel.text = "Powering up..."
                elseif state == "sealed" then
                    stateLabel.text = "Sealed - powered"
                elseif state == "open" then
                    stateLabel.text = "Open - no power"
                else
                    stateLabel.text = "Partly open"
                end
            end,

            click = function(element)
                if not dmhub.isDM then
                    return
                end
                --a partly open door is sealed first, so one click always fixes it.
                SetDoorOpen(door, DoorState(door) == "sealed", 0)
                element:FireEvent("think")
            end,

            hover = function(element)
                FocusDoor(door, true)
            end,

            dehover = function(element)
                FocusDoor(door, false)
            end,

            --closing the popup under the mouse must not leave the outline behind.
            destroy = function(element)
                FocusDoor(door, false)
            end,

            children = {
                gui.Panel{
                    classes = {"condemnedDoorLight"},
                    bgimage = true,
                    width = 14,
                    height = 14,
                    valign = "center",
                    rmargin = 10,
                    interactable = false,
                },
                gui.Panel{
                    width = DOOR_TILE_WIDTH - 50,
                    height = "auto",
                    valign = "center",
                    flow = "vertical",
                    interactable = false,
                    children = {
                        gui.Label{
                            classes = {"sizeS", "bold"},
                            width = "100%",
                            height = "auto",
                            text = DOOR_NAMES[door.n] or ("Cell " .. door.n),
                        },
                        stateLabel,
                    },
                },
            },
        }
    end

    local function CreateDoorsPanel()
        local doors = CollectCauldronDoors()
        EnsureDoorAppearance(doors)

        local rows = {}
        for _, layout in ipairs(DOOR_LAYOUT) do
            local slots = {}
            for i = 1, 3 do
                local door = doors[layout[i] or ""]
                local lmargin = cond(i > 1, DOOR_TILE_GAP, 0)
                if door ~= nil then
                    slots[#slots + 1] = CreateDoorTile(door, lmargin)
                else
                    slots[#slots + 1] = gui.Panel{
                        width = DOOR_TILE_WIDTH,
                        height = DOOR_TILE_HEIGHT,
                        lmargin = lmargin,
                    }
                end
            end
            rows[#rows + 1] = gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                bmargin = DOOR_TILE_GAP,
                children = slots,
            }
        end

        local summary = gui.Label{
            classes = {"sizeS"},
            width = "auto",
            height = "auto",
            bmargin = 8,
            thinkTime = 0.5,
            text = "",
            create = function(element)
                element:FireEvent("think")
            end,
            think = function(element)
                local total, open = 0, 0
                for _, door in pairs(doors) do
                    total = total + 1
                    if DoorState(door) ~= "sealed" then
                        open = open + 1
                    end
                end
                element.text = string.format("%d of %d doors open", open, total)
            end,
        }

        --doors that change go one after another, clockwise from the north wall.
        local function SetAll(open)
            local numbers = {}
            for n, _ in pairs(doors) do
                numbers[#numbers + 1] = n
            end
            table.sort(numbers)
            local ripple = 0
            for _, n in ipairs(numbers) do
                local door = doors[n]
                local state = DoorState(door)
                if state ~= cond(open, "open", "sealed") then
                    SetDoorOpen(door, open, ripple)
                    ripple = ripple + DOOR_RIPPLE
                end
            end
        end

        --the map button bar does not pass a themed cascade to its popups, so the popup
        --roots its own (see CreateCollarPanel).
        return gui.Panel{
            styles = ThemeEngine.GetStyles(),
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "bottom",
            children = {
                gui.Panel{
                    classes = {"framedPanel"},
                    --exactly the three-tile schematic plus the side padding.
                    width = 3 * DOOR_TILE_WIDTH + 2 * DOOR_TILE_GAP + 2 * 12,
                    height = "auto",
                    flow = "vertical",
                    borderBox = true,
                    hpad = 12,
                    vpad = 10,
                    styles = g_doorStyles,
                    children = {
                        gui.Label{
                            classes = {"sizeL", "bold"},
                            width = "auto",
                            height = "auto",
                            text = "Cauldron Security Doors",
                        },
                        summary,
                        gui.Panel{
                            width = "auto",
                            height = "auto",
                            flow = "vertical",
                            children = rows,
                        },
                        gui.Panel{
                            width = "auto",
                            height = "auto",
                            flow = "horizontal",
                            tmargin = 4,
                            children = {
                                gui.Button{
                                    classes = {"sizeS"},
                                    width = 120,
                                    text = "Seal All",
                                    click = function(element)
                                        SetAll(false)
                                    end,
                                },
                                gui.Button{
                                    classes = {"sizeS"},
                                    width = 120,
                                    lmargin = DOOR_TILE_GAP,
                                    text = "Open All",
                                    click = function(element)
                                        SetAll(true)
                                    end,
                                },
                            },
                        },
                    },
                },
            },
        }
    end

    --The button is registered only while the current map has security doors. The map
    --button registry outlives a reload of this file, so drop any registration left by
    --the previous load before the watcher decides afresh.
    if mapButtons ~= nil then
        mapButtons.Unregister(DOORS_BUTTON_ID)

        dmhub.Coroutine(function()
            local shown = false
            local lastMap = nil
            local lastCheck = -1000
            while not mod.unloaded do
                --rescan on a map change, and every few seconds for doors added or removed.
                local mapid = game.currentMapId
                if mapid ~= lastMap or dmhub.Time() - lastCheck > 3 then
                    lastMap = mapid
                    lastCheck = dmhub.Time()
                    local ok, doors = pcall(CollectCauldronDoors)
                    local has = ok and next(doors) ~= nil
                    if has ~= shown then
                        shown = has
                        if has then
                            mapButtons.Register(DOORS_BUTTON_ID, {
                                name = "Security Doors",
                                icon = "phosphor/lightning.png",
                                tooltip = "Security Doors",
                                directorOnly = true,
                                click = function(element)
                                    if mod.unloaded then
                                        return
                                    end
                                    element.popup = CreateDoorsPanel()
                                end,
                            })
                        else
                            mapButtons.Unregister(DOORS_BUTTON_ID)
                        end
                    end
                end
                coroutine.yield(0.5)
            end
        end)
    end
end)()

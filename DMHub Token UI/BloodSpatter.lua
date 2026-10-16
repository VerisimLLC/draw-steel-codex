local mod = dmhub.GetModLoading()

--Blood spatter: when a creature takes damage, blood sprays out of it away from
--whoever hurt it, splats onto the ground and fades away. Off unless the Director
--turns on the Show Blood game setting.
--
--Networking: none of its own. Damage already reaches every client as a damage
--entry on the creature (creature:RecordDamageEntry), which TokenUI's damageentry
--handler shows once per client -- the floating number, the flash, the hit sound --
--and then calls BloodSpatter.Emit. The client that deals the damage stamps the
--entry with the direction away from the attacker (bloodAngle), and every random
--choice is seeded from the entry's id, so every client throws the same blood to
--the same places.
--
--Typed damage can leave its own marks instead: BloodSpatter.damageEffects maps a
--damage type (fire, acid, cold, corruption, lightning) to the decal sets it draws on
--a hit and under a corpse, and whether it bleeds as well. Types not in the table
--just bleed.
--
--A corpse object left by a dead creature (ActivatedAbilityRemoveCreatureBehavior
--:LeaveCorpse) also marks the ground: BloodSpatter.EmitCorpse draws a pool and spray
--(or the killing damage type's marks) around it whenever the corpse appears on a
--client, seeded from the corpse's object id, sized by the creature and by how far
--below zero its stamina went. Those marks fade a little and then stay for as long as
--the corpse does: the engine's corpse component calls CorpseComponent's OnAppear /
--OnMoved / OnDisappear hooks (AbilityRemoveCreature.lua), which add and remove them
--by tag.
--
--Drawing is the engine's BloodSpatterRenderer (MapFloorLua:AddBloodSpatter): the
--flight, splat and fade all happen in its shader, so a spatter costs nothing per
--frame. Like footprints the blood is client-local and gone after a restart or a
--map change. The art is built into the app under Assets/UIImages/blood.

--- @class BloodSpatter
BloodSpatter = {}

--the corpses currently shown on this client, by object id (see EmitCorpse), so
--turning Show Blood on or off can add or take away their blood at once.
--- @type table<string, {component: CorpseComponent, obj: LuaObjectInstance}>
local g_shownCorpses = {}

local g_showBlood = setting{
    id = "blood:show",
    description = "Show Blood",
    help = "When a creature takes damage, blood sprays out of it away from its attacker and spatters the ground, more for bigger hits. The blood fades away after a minute. A corpse lies in its own blood for as long as it is on the map.",
    editor = "check",
    default = false,
    storage = "game",
    section = "game",
    classes = {"dmonly"},
    onchange = function()
        for _,entry in pairs(g_shownCorpses) do
            BloodSpatter.RefreshCorpse(entry.component, entry.obj)
        end
    end,
}

--A player's own opt-out: with Show Blood on, this client draws none of it (blood,
--typed-damage marks, corpse pools). Does nothing while Show Blood is off.
local g_hideGore
g_hideGore = setting{
    id = "blood:hidegore",
    description = "Hide Blood & Gore",
    help = "Hide blood spatter, damage marks and corpse pools on your screen, even when the Director has turned on Show Blood. Has no effect while Show Blood is off.",
    editor = "check",
    default = false,
    storage = "preference",
    section = "game",
    onchange = function()
        --take away what is already on the ground at once, not only new blood.
        if g_hideGore:Get() == true then
            local map = game.currentMap
            if map ~= nil then
                for _,floor in ipairs(map.floors) do
                    floor:ClearBloodSpatter()
                end
            end
        end
        for _,entry in pairs(g_shownCorpses) do
            BloodSpatter.RefreshCorpse(entry.component, entry.obj)
        end
    end,
}

--No editor, so it never shows in the settings panel; the default is what every game
--uses unless something sets it from Lua.
local g_fadeTime = setting{
    id = "blood:fadetime",
    description = "Blood Fade Time",
    help = "How long spattered blood takes to fade away.",
    default = 60,
    storage = "game",
    enum = {
        {value = 15, text = "15 seconds"},
        {value = 30, text = "30 seconds"},
        {value = 60, text = "1 minute"},
        {value = 120, text = "2 minutes"},
        {value = 300, text = "5 minutes"},
        {value = 600, text = "10 minutes"},
    },
}

--the radius of a medium (1x1) creature's token; blood scales with token size.
local MediumRadius = 0.32

--damage past this makes no more blood.
local MaxIntensity = 40

local function Image(name)
    return string.format("blood/%s.png", name)
end

local g_splatters = {
    Image("splatter-1"), Image("splatter-2"), Image("splatter-3"), Image("splatter-4"),
    Image("splatter-5"), Image("splatter-6"), Image("splatter-7"), Image("splatter-8"),
    Image("splatter-small-1"), Image("splatter-small-2"), Image("splatter-small-3"),
    Image("drops-1"),
}

local g_bigSplatters = { Image("splatter-big-1"), Image("splatter-big-2"), Image("splatter-big-3") }

--the marks typed damage leaves instead of (or as well as) blood, generated by
--tools/blood-decals/make_damage_decals.py and drawn in their own colours. Which set
--a damage type uses, and how, is BloodSpatter.damageEffects below.
local g_scorches = { Image("scorch-1"), Image("scorch-2"), Image("scorch-3"), Image("scorch-4") }
local g_soot = { Image("soot-1"), Image("soot-2"), Image("soot-3") }
local g_scorchRing = Image("scorch-ring-1")
local g_scorchStreak = Image("scorch-streak-1")
local g_acid = { Image("acid-1"), Image("acid-2"), Image("acid-3"), Image("acid-4") }
local g_acidDrips = { Image("acid-drip-1"), Image("acid-drip-2"), Image("acid-drip-3") }
local g_acidRing = Image("acid-ring-1")
local g_frost = { Image("frost-1"), Image("frost-2"), Image("frost-3"), Image("frost-4") }
local g_shards = { Image("shard-1"), Image("shard-2"), Image("shard-3") }
local g_frostRing = Image("frost-ring-1")
local g_rot = { Image("rot-1"), Image("rot-2"), Image("rot-3"), Image("rot-4") }
local g_rotNodes = { Image("rot-node-1"), Image("rot-node-2"), Image("rot-node-3") }
local g_rotRing = Image("rot-ring-1")
local g_bolts = { Image("bolt-1"), Image("bolt-2"), Image("bolt-3") }
local g_pools = { Image("pool-1"), Image("pool-2"), Image("pool-3"), Image("pool-4") }
local g_streak = Image("streak-1")

--A small deterministic random number generator (FNV-1a seed, xorshift32), so
--every client draws the same sequence from the same damage entry id.
--- @param seed string
--- @return fun(): number returns a number in [0, 1)
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

--- @param list string[]
--- @param rand fun(): number
--- @return string
local function Pick(list, rand)
    return list[1 + math.floor(rand() * #list)]
end

--What a creature bleeds: its bloodColor body trait (creature:GetBodyTrait), picked on
--its Appearance tab or inherited from its ancestry or a form it has taken. Unset means
--red. recolor is passed to AddBloodSpatter: it repaints the red blood art in that
--color, keeping its shading.
BloodSpatter.defaultColor = "red"
BloodSpatter.noneColor = "none"
BloodSpatter.colors = {
    {id = "red", text = "Red"},
    {id = "green", text = "Green", recolor = "#5cd629"},
    {id = "none", text = "None"},
}

local g_colorsById = {}
for _,c in ipairs(BloodSpatter.colors) do
    g_colorsById[c.id] = c
end

--- A bloodColor value as one of the BloodSpatter.colors ids (unset or unknown = red).
--- @param id nil|string
--- @return string
local function ColorId(id)
    if id == nil or g_colorsById[id] == nil then
        return BloodSpatter.defaultColor
    end
    return id
end

--- What the creature bleeds right now, following any form it has taken.
--- @param props Creature
--- @return string one of the BloodSpatter.colors ids
function BloodSpatter.GetColorId(props)
    return ColorId(props:GetBodyTrait("bloodColor"))
end

--- What the creature bleeds in its own body (its pick, else its ancestry's): what its
--- Appearance tab shows.
--- @param props Creature
--- @return string one of the BloodSpatter.colors ids
function BloodSpatter.GetNaturalColorId(props)
    return ColorId(props:GetNaturalBodyTrait("bloodColor"))
end

--- @return {id: string, text: string}[]
function BloodSpatter.GetColorOptions()
    local result = {}
    for _,c in ipairs(BloodSpatter.colors) do
        result[#result+1] = {id = c.id, text = c.text}
    end
    return result
end

--- Whether the game has Show Blood on, regardless of this player's Hide Blood & Gore.
--- Use it for game data (a creature's Blood pick, the angle stamped on damage) that
--- other clients need even when this one draws no blood.
--- @return boolean
function BloodSpatter.GameEnabled()
    return g_showBlood:Get() == true
end

--- Whether this client draws blood: Show Blood is on and this player has not hidden it.
--- @return boolean
function BloodSpatter.Enabled()
    return BloodSpatter.GameEnabled() and g_hideGore:Get() ~= true
end

--The direction, in degrees counterclockwise from +x, pointing from the attacker
--through the target: the way blood from the wound flies. nil if either token
--can't be found or they share a spot.
--- @param target Creature
--- @param attackerid string
--- @return number|nil
function BloodSpatter.AngleAwayFrom(target, attackerid)
    local targetToken = dmhub.LookupToken(target)
    local attackerToken = dmhub.GetCharacterById(attackerid)
    if targetToken == nil or attackerToken == nil or targetToken.floorid ~= attackerToken.floorid then
        return nil
    end

    local tpos = targetToken.pos
    local apos = attackerToken.pos
    if tpos == nil or apos == nil then
        return nil
    end

    local dx, dy = tpos.x - apos.x, tpos.y - apos.y
    if dx*dx + dy*dy < 0.0001 then
        return nil
    end

    --whole degrees: the angle rides along in the synced damage entry.
    return math.floor(math.deg(math.atan(dy, dx)) + 0.5)
end

--- What a damage type leaves on the ground. hit is drawn when a creature takes that
--- damage (instead of its blood), corpse under a creature it killed. Each is a layout
--- for the generic emitters below: a main blot at the creature, optional streaks
--- radiating from it, small flecks around it, and (corpse only) a ring under the body.
--- blood, when set, draws the creature's blood as well, reduced to that fraction and
--- tinted (frozen blood is dark and scarce). Damage types not listed just bleed.
--- @class BloodSpatter.MarkLayout
--- @field blot nil|string[] images for the main mark (and the blots around a corpse); nil for none (lightning is only its bolts)
--- @field fleck string[] images for the small flecks
--- @field streak nil|string|string[] image(s) for streaks radiating outward; rotated to point away
--- @field streakCount nil|number how many streaks (default 1 on a hit, 2 on a corpse; a corpse adds more for overkill)
--- @field ring nil|string corpse only: the image under the body
--- @field blotSize nil|number the main mark's size in tiles for a medium creature (default 0.9 hit, 0.35..0.7 corpse blots)
--- @field ringSize nil|number corpse only: the ring's size in tiles for a medium creature (default 1.5)
--- @field fleckSize nil|number the flecks' base size (default 0.15)
--- @class BloodSpatter.DamageEffect
--- @field hit BloodSpatter.MarkLayout
--- @field corpse BloodSpatter.MarkLayout
--- @field blood nil|{scale: number, color: string} also bleed, this much of the usual amount, tinted
--- @type table<string, BloodSpatter.DamageEffect>
BloodSpatter.damageEffects = {
    fire = {
        hit = {blot = g_scorches, fleck = g_soot},
        corpse = {ring = g_scorchRing, blot = g_scorches, streak = g_scorchStreak, fleck = g_soot},
    },
    acid = {
        hit = {blot = g_acid, fleck = g_acidDrips, blotSize = 0.8},
        corpse = {ring = g_acidRing, blot = g_acid, fleck = g_acidDrips, ringSize = 1.7},
    },
    cold = {
        hit = {blot = g_frost, fleck = g_shards, blotSize = 1.1, fleckSize = 0.12},
        corpse = {ring = g_frostRing, blot = g_frost, fleck = g_shards, ringSize = 1.8, blotSize = 0.6, fleckSize = 0.12},
        blood = {scale = 0.35, color = "#70708c"},
    },
    corruption = {
        hit = {blot = g_rot, fleck = g_rotNodes, blotSize = 1.0},
        corpse = {ring = g_rotRing, blot = g_rot, fleck = g_rotNodes, ringSize = 1.7, blotSize = 0.6},
    },
    --lightning is just the forked burn: no blot under the creature, no ring under the corpse.
    lightning = {
        hit = {streak = g_bolts, streakCount = 2, fleck = g_soot},
        corpse = {streak = g_bolts, streakCount = 3, fleck = g_soot},
    },
}

--- The effect for a damage type, or nil if that damage just draws blood.
--- @param damageType string|nil
--- @return BloodSpatter.DamageEffect|nil
function BloodSpatter.GetDamageEffect(damageType)
    if damageType == nil then
        return nil
    end
    return BloodSpatter.damageEffects[string.lower(tostring(damageType))]
end

--- @param images string|string[]
--- @param rand fun(): number
--- @return string
local function PickImage(images, rand)
    if type(images) == "table" then
        return Pick(images, rand)
    end
    return images
end

--- What every emitter below needs to know about where and how big to draw.
--- @class BloodSpatter.Site
--- @field floor MapFloorLua
--- @field rand fun(): number
--- @field x number
--- @field y number
--- @field radius number the creature's token radius in tiles
--- @field scale number the creature's size relative to a medium creature (0.6..3)
--- @field lifetime number seconds to fade
--- @field remain nil|number opacity kept after the fade (corpses)
--- @field tag nil|string group tag (corpses)

--- Places one mark through AddBloodSpatter with the site's fade, group and tint.
--- @param site BloodSpatter.Site
--- @param args table AddBloodSpatter options (x, y, image, size, ... ); the site fills the rest
local function Place(site, args)
    if args.angle == nil then
        args.angle = site.rand()*360
    end
    if args.mirror == nil then
        args.mirror = site.rand() < 0.5
    end
    if args.flight == nil then
        args.flight = 0
    end
    args.lifetime = site.lifetime
    args.remain = site.remain
    args.tag = site.tag
    site.floor:AddBloodSpatter(args)
end

--- The marks a hit leaves: the main mark under the creature shoved a little away from
--- the attacker, streaks along the blow if the layout has them, and flecks fanned
--- around the direction of the blow.
--- @param site BloodSpatter.Site
--- @param layout BloodSpatter.MarkLayout
--- @param intensity number the damage, capped at MaxIntensity
--- @param dirAngle number degrees, the way the blow travelled
local function EmitHitMarks(site, layout, intensity, dirAngle)
    local rand = site.rand
    local radius, scale = site.radius, site.scale
    if layout.blot ~= nil then
        local dr = math.rad(dirAngle)
        local shove = radius*(0.2 + 0.3*rand())
        Place(site, {
            image = PickImage(layout.blot, rand),
            x = site.x + math.cos(dr)*shove,
            y = site.y + math.sin(dr)*shove,
            size = scale*((layout.blotSize or 0.9) + intensity*0.03),
        })
    end

    if layout.streak ~= nil then
        for _ = 1, (layout.streakCount or 1) do
            local a = dirAngle + (rand() - 0.5)*70
            local ar = math.rad(a)
            local len = scale*(0.9 + intensity*0.02)
            Place(site, {
                image = PickImage(layout.streak, rand),
                x = site.x + math.cos(ar)*(radius*0.3 + len*0.45),
                y = site.y + math.sin(ar)*(radius*0.3 + len*0.45),
                size = len,
                angle = a,
                mirror = rand() < 0.5,
                delay = 0.02*rand(),
            })
        end
    end

    local count = math.max(2, math.min(10, math.floor(1 + intensity*0.3)))
    local reach = scale*(0.4 + intensity*0.03)
    local fleckSize = layout.fleckSize or 0.15
    for _ = 1, count do
        local a = dirAngle + (rand() + rand() - 1)*120
        local ar = math.rad(a)
        local dist = radius*0.6 + reach*rand()
        Place(site, {
            image = PickImage(layout.fleck, rand),
            x = site.x + math.cos(ar)*dist,
            y = site.y + math.sin(ar)*dist,
            size = scale*(fleckSize + 0.25*rand()),
            delay = rand()*0.2,
        })
    end
end

--- The marks a dead creature lies in: a ring under the body, blots around it, streaks
--- radiating out if the layout has them, and flecks further off. mess (0..1, from
--- overkill) widens everything and adds streaks.
--- @param site BloodSpatter.Site
--- @param layout BloodSpatter.MarkLayout
--- @param mess number
local function EmitCorpseMarks(site, layout, mess)
    local rand = site.rand
    local radius, scale = site.radius, site.scale
    local cx, cy = site.x, site.y
    local reach = radius + scale*(0.5 + 1.0*mess)

    if layout.ring ~= nil then
        Place(site, {image = layout.ring, x = cx, y = cy, size = scale*((layout.ringSize or 1.5) + 0.5*mess)})
    end

    if layout.blot ~= nil then
        local blotSize = layout.blotSize or 0.35
        for _ = 1, math.floor(3*scale + 6*mess + 0.5) do
            local ar = math.rad(rand()*360)
            local dist = radius*0.5 + (reach - radius*0.5)*rand()
            Place(site, {
                image = PickImage(layout.blot, rand),
                x = cx + math.cos(ar)*dist,
                y = cy + math.sin(ar)*dist,
                size = scale*(blotSize + blotSize*rand()),
                delay = rand()*0.1,
            })
        end
    end

    if layout.streak ~= nil then
        for _ = 1, (layout.streakCount or 2) + math.floor(mess*3 + 0.5) do
            local a = rand()*360
            local ar = math.rad(a)
            local dist = radius*0.8 + reach*0.35
            Place(site, {
                image = PickImage(layout.streak, rand),
                x = cx + math.cos(ar)*dist,
                y = cy + math.sin(ar)*dist,
                size = scale*(0.9 + 0.5*mess),
                angle = a,
                mirror = rand() < 0.5,
                delay = 0.05*rand(),
            })
        end
    end

    local fleckSize = layout.fleckSize or 0.12
    for _ = 1, math.floor(4*scale + 4*mess) do
        local ar = math.rad(rand()*360)
        local dist = reach*(0.5 + 0.6*rand())
        Place(site, {
            image = PickImage(layout.fleck, rand),
            x = cx + math.cos(ar)*dist,
            y = cy + math.sin(ar)*dist,
            size = scale*(fleckSize + 0.2*rand()),
            delay = rand()*0.2,
        })
    end
end

--- The blood a hit sprays: droplets fanned around the direction of the blow, most
--- landing well clear of the creature; a big splash, a streak and a pool for heavier
--- hits. amount scales how much (1 = the usual); color tints it.
--- @param site BloodSpatter.Site
--- @param bloodColor {id: string, recolor: nil|string}
--- @param damage number
--- @param dirAngle number
--- @param spread number degrees either side of dirAngle the droplets fan over
--- @param amount number
--- @param color nil|string
local function EmitBlood(site, bloodColor, damage, dirAngle, spread, amount, color)
    local rand = site.rand
    local radius, scale = site.radius, site.scale*amount
    local intensity = math.min(damage, MaxIntensity)*amount
    local dirRad = math.rad(dirAngle)
    local dirx, diry = math.cos(dirRad), math.sin(dirRad)

    --how far past the creature's edge the blood can fly.
    local reach = scale*(0.5 + intensity*0.05)

    local function Throw(image, angleDeg, dist, size, delay, extra)
        local a = math.rad(angleDeg)
        local cx, cy = math.cos(a), math.sin(a)
        local args = {
            --droplets leave from inside the token, so they seem to burst out of it.
            fromx = site.x + cx*radius*0.3,
            fromy = site.y + cy*radius*0.3,
            x = site.x + cx*dist,
            y = site.y + cy*dist,
            image = image,
            size = size,
            delay = delay,
            flight = 0.1 + dist*0.08,
            recolor = bloodColor.recolor,
            color = color,
        }
        for k,v in pairs(extra or {}) do
            args[k] = v
        end
        Place(site, args)
    end

    local count = math.max(amount < 1 and 1 or 3, math.min(18, math.floor((2 + intensity*0.5)*amount)))
    for _ = 1, count do
        local angle = dirAngle + (rand() + rand() - 1)*spread
        local dist = radius + reach*(0.15 + 0.85*rand()^0.8)
        local size = scale*(0.25 + 0.4*rand())
        Throw(Pick(g_splatters, rand), angle, dist, size, rand()*0.08)
    end

    --a solid hit leaves one big splash just behind the creature.
    if damage*amount >= 8 then
        local angle = dirAngle + (rand() - 0.5)*spread*0.5
        Throw(Pick(g_bigSplatters, rand), angle, radius + reach*0.35, scale*(0.8 + intensity*0.03), 0.02)
    end

    --a heavy one a long smear along the line of the blow...
    if damage*amount >= 12 then
        Throw(g_streak, dirAngle, radius + reach*0.5, scale*(1.0 + intensity*0.02), 0.04, {angle = dirAngle, mirror = false})
    end

    --...and a pool welling up where the creature stands.
    if damage*amount >= 15 then
        local dist = radius*0.5
        Place(site, {
            x = site.x + dirx*dist,
            y = site.y + diry*dist,
            image = Pick(g_pools, rand),
            size = scale*(0.7 + intensity*0.015),
            delay = 0.35,
            recolor = bloodColor.recolor,
            color = color,
        })
    end
end

--- The blood a corpse lies in: a pool under the body and spatter thrown out around it,
--- big splashes and a smear for a messy death. amount and color as for EmitBlood.
--- @param site BloodSpatter.Site
--- @param bloodColor {id: string, recolor: nil|string}
--- @param mess number
--- @param amount number
--- @param color nil|string
local function EmitCorpseBlood(site, bloodColor, mess, amount, color)
    local rand = site.rand
    local radius, scale = site.radius, site.scale*amount
    local cx, cy = site.x, site.y
    local count = math.floor((6*scale*scale + 14*mess*scale)*amount + 0.5)
    local reach = radius + scale*(0.4 + 1.2*mess)

    local function Splat(image, x, y, size, delay, flight, angle, mirror)
        Place(site, {
            x = x,
            y = y,
            fromx = cx,
            fromy = cy,
            image = image,
            angle = angle,
            size = size,
            mirror = mirror,
            delay = delay,
            flight = flight,
            recolor = bloodColor.recolor,
            color = color,
        })
    end

    --the pool under the body, larger the messier the death.
    Splat(Pick(g_pools, rand), cx + (rand() - 0.5)*radius*0.3, cy + (rand() - 0.5)*radius*0.3, scale*(1.1 + 0.6*mess), 0, 0)

    for _ = 1, count do
        local ar = math.rad(rand()*360)
        local dist = radius*0.4 + (reach - radius*0.4)*rand()^0.7
        Splat(Pick(g_splatters, rand), cx + math.cos(ar)*dist, cy + math.sin(ar)*dist, scale*(0.25 + 0.4*rand()), rand()*0.15, 0.1 + dist*0.08)
    end

    --a violent end adds big splashes and smears trailing away from the body.
    for _ = 1, math.floor(mess*3*amount + 0.5) do
        local ar = math.rad(rand()*360)
        local dist = radius + reach*0.4*rand()
        Splat(Pick(g_bigSplatters, rand), cx + math.cos(ar)*dist, cy + math.sin(ar)*dist, scale*(0.7 + 0.5*mess), rand()*0.1, 0.1 + dist*0.08)
    end
    if mess*amount >= 0.5 then
        local a = rand()*360
        local ar = math.rad(a)
        local dist = radius + reach*0.5
        Splat(g_streak, cx + math.cos(ar)*dist, cy + math.sin(ar)*dist, scale*(1.0 + 0.6*mess), 0.05, 0.1 + dist*0.08, a, false)
    end
end

--Draws the wound for one damage entry: the damage type's marks if it has an effect
--(and its reduced blood, if the effect bleeds too), else the creature's blood.
--Called by TokenUI's damageentry handler, on every client, as the damage number
--appears.
--- @param token CharacterToken
--- @param entry {id: string, damage: number|nil, bloodAngle: number|nil, damage_type: string|nil}
function BloodSpatter.Emit(token, entry)
    local damage = tonumber(entry.damage) or 0
    if damage <= 0 or not BloodSpatter.Enabled() then
        return
    end

    if token == nil or not token.valid or token.isObject or token.properties == nil then
        return
    end

    --a hidden creature must not give itself away to players through its wounds.
    if token.invisibleToPlayers and not dmhub.isDM then
        return
    end

    local floor = game.GetFloor(token.floorid)
    local center = token.pos
    if floor == nil or center == nil then
        return
    end

    local radius = token.radiusInTiles
    --- @type BloodSpatter.Site
    local site = {
        floor = floor,
        rand = MakeRandom(entry.id or ""),
        x = center.x,
        y = center.y,
        radius = radius,
        scale = math.max(0.6, math.min(3, radius/MediumRadius)),
        lifetime = tonumber(g_fadeTime:Get()) or 60,
    }

    --no attacker (a condition, a fall with nobody to blame): blood goes every way.
    local dirAngle = tonumber(entry.bloodAngle)
    local spread = 40
    if dirAngle == nil then
        dirAngle = site.rand()*360
        spread = 180
    end

    local bloodColor = g_colorsById[BloodSpatter.GetColorId(token.properties)]
    local bleeds = bloodColor.id ~= BloodSpatter.noneColor

    local effect = BloodSpatter.GetDamageEffect(entry.damage_type)
    if effect ~= nil then
        EmitHitMarks(site, effect.hit, math.min(damage, MaxIntensity), dirAngle)
        if effect.blood ~= nil and bleeds then
            EmitBlood(site, bloodColor, damage, dirAngle, spread, effect.blood.scale, effect.blood.color)
        end
        return
    end

    if bleeds then
        EmitBlood(site, bloodColor, damage, dirAngle, spread, 1, nil)
    end
end

--How long a corpse's marks take to settle, and the opacity they settle at and keep.
local CorpseFadeTime = 300
local CorpseRemain = 0.6

--- The tag a corpse's marks are added under, so they can be removed with the corpse.
--- @param obj LuaObjectInstance
--- @return string
local function CorpseTag(obj)
    return "corpse:" .. tostring(obj.id)
end

--- Draws what a corpse lies in: the marks of the damage that killed it if that type
--- has an effect (plus reduced blood if it bleeds too), else its blood. Called from
--- CorpseComponent's OnAppear hook on every client that shows the corpse object, so it
--- runs after any map load or rejoin as well as when the creature dies. Seeded from the
--- corpse's object id, so every client draws the same; the marks keep CorpseRemain of
--- their opacity for as long as the corpse is on the map (ClearCorpse removes them).
--- @param component CorpseComponent
--- @param obj LuaObjectInstance
function BloodSpatter.EmitCorpse(component, obj)
    if obj == nil or not obj.valid then
        return
    end

    g_shownCorpses[obj.id] = {component = component, obj = obj}

    if not BloodSpatter.Enabled() then
        return
    end

    local floor = game.GetFloor(obj.floorid)
    if floor == nil then
        return
    end

    local tag = CorpseTag(obj)
    floor:ClearBloodSpatter(tag)

    local radius = tonumber(component:try_get("bloodRadius")) or MediumRadius
    local overkill = math.max(0, tonumber(component:try_get("overkill")) or 0)
    --- @type BloodSpatter.Site
    local site = {
        floor = floor,
        rand = MakeRandom(tag),
        x = obj.x,
        y = obj.y,
        radius = radius,
        scale = math.max(0.6, math.min(3, radius/MediumRadius)),
        lifetime = CorpseFadeTime,
        remain = CorpseRemain,
        tag = tag,
    }

    --a creature killed well past zero is a much messier sight.
    local mess = math.min(overkill, MaxIntensity)/MaxIntensity

    local bloodColor = g_colorsById[ColorId(component:try_get("bloodColor"))]
    local bleeds = bloodColor.id ~= BloodSpatter.noneColor

    --corpses left before damageType was stored carry the older charred flag.
    local damageType = component:try_get("damageType")
    if damageType == nil and component:try_get("charred") == true then
        damageType = "fire"
    end

    local effect = BloodSpatter.GetDamageEffect(damageType)
    if effect ~= nil then
        EmitCorpseMarks(site, effect.corpse, mess)
        if effect.blood ~= nil and bleeds then
            EmitCorpseBlood(site, bloodColor, mess, effect.blood.scale, effect.blood.color)
        end
        return
    end

    if bleeds then
        EmitCorpseBlood(site, bloodColor, mess, 1, nil)
    end
end


--- Removes a corpse's blood: the corpse has gone from this client's map (or moved,
--- before EmitCorpse throws it again).
--- @param obj LuaObjectInstance
function BloodSpatter.ClearCorpse(obj)
    if obj == nil then
        return
    end

    g_shownCorpses[obj.id] = nil

    local floor = game.GetFloor(obj.floorid)
    if floor ~= nil then
        floor:ClearBloodSpatter(CorpseTag(obj))
    end
end

--- Redraws (or removes) a shown corpse's blood after Show Blood or Hide Blood & Gore changes.
--- @param component CorpseComponent
--- @param obj LuaObjectInstance
function BloodSpatter.RefreshCorpse(component, obj)
    if obj == nil or not obj.valid then
        g_shownCorpses[obj and obj.id or ""] = nil
        return
    end

    if BloodSpatter.Enabled() then
        BloodSpatter.EmitCorpse(component, obj)
    else
        local floor = game.GetFloor(obj.floorid)
        if floor ~= nil then
            floor:ClearBloodSpatter(CorpseTag(obj))
        end
    end
end

--The client dealing the damage records which way the blood flies, so every
--client throws it the same way even if the tokens are still animating there.
local g_baseRecordDamageEntry = creature.RecordDamageEntry

--- @param options {id: nil|string, damage: number, attackerid: string|nil, damage_type: string|nil, heal: number, sound: nil|string, bloodAngle: nil|number}
function creature:RecordDamageEntry(options)
    if options.bloodAngle == nil and options.attackerid ~= nil and (tonumber(options.damage) or 0) > 0 and BloodSpatter.GameEnabled() then
        options.bloodAngle = BloodSpatter.AngleAwayFrom(self, options.attackerid)
    end
    return g_baseRecordDamageEntry(self, options)
end

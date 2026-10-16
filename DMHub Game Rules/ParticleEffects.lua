local mod = dmhub.GetModLoading()

--Particle effect recipes: named, layered particle looks (fire, smoke...) built from
--dmhub.CreateParticleSystem, so zones, tokens and scripts share one tuned version of
--each look instead of copying option tables around.
--
--A recipe is a list of layers; each layer is a CreateParticleSystem options table
--(image, type, rate, lifetime, colors, sizes...). ParticleEffects.Create places every
--layer either over a set of tiles ({locs = ...}) or riding a token
--({followToken = token}), and returns one group handle for all of them.
--
--Everything is client-local, like the underlying particle systems: call it on every
--client that should see the effect (zone scripts and the token visual driver do).

ParticleEffects = {
    --- @type table<string, {id: string, name: string, layers: table[]}>
    recipes = {},
}

--- Registers (or replaces) a recipe.
--- @param recipe {id: string, name: string, layers: table[]}
function ParticleEffects.Register(recipe)
    ParticleEffects.recipes[recipe.id] = recipe
end

--Units: rotation and rotationOverLifetime go to Unity unconverted, so they are RADIANS
--(rotationOverLifetime in radians per second). 0.15 is a gentle ~9 degrees a second; a
--value like 15 spins particles at ~860 degrees a second.

--Option keys that describe placement; recipe layers never carry them.
local g_placementKeys = { locs = true, loc = true, position = true, pos = true, floorIndex = true, followToken = true }

--Builds one layer's options for a placement. Sizes (and a token's producer radius)
--scale linearly; a token layer's rate scales with area since a circle producer's rate
--is per second, while tile layers' rates are already per unit of area.
local function LayerOptions(layer, placement, scale)
    local options = {}
    for k,v in pairs(layer) do
        if k ~= "tokenRadius" then
            options[k] = v
        end
    end

    for k,v in pairs(placement) do
        if g_placementKeys[k] then
            options[k] = v
        end
    end

    if options.birthSize ~= nil then options.birthSize = options.birthSize * scale end
    if options.deathSize ~= nil then options.deathSize = options.deathSize * scale end

    if placement.followToken ~= nil then
        options.producerShape = "Circle"
        options.producerRadius = (layer.tokenRadius or 0.3) * scale
        if options.rate ~= nil then
            options.rate = options.rate * scale * scale
        end
    end

    return options
end

--- @class ParticleEffectGroup
--- @field handles ParticleSystemHandleLua[]
--- @field alive boolean
--- @field placement {locs: nil|Loc[], loc: nil|Loc, followToken: nil|string|CharacterToken} The group's own copy of where the effect sits.
--- @field recipe table The recipe (layers) the group was built from.
--- @field scale number Size multiplier.
local ParticleEffectGroup = {}
ParticleEffectGroup.__index = function(t, key)
    if key == "alive" then
        for _,handle in ipairs(rawget(t, "handles")) do
            if not handle.alive then
                return false
            end
        end
        return true
    end
    return ParticleEffectGroup[key]
end

--- Stops every layer. Safe to call more than once.
function ParticleEffectGroup:Stop()
    for _,handle in ipairs(self.handles) do
        handle:Stop()
    end
end

--Splits tiles by the altitude of the ground under each one, so an effect over a
--raised patch parallaxes with that ground (the parallax option is a height in
--tiles). Returns a list of {altitude, locs}, lowest first.
local function GroupLocsByGroundAltitude(locs)
    local byAltitude = {}
    local altitudes = {}
    for _,loc in ipairs(locs) do
        local altitude = loc.withGroundAltitude.altitude or 0
        local group = byAltitude[altitude]
        if group == nil then
            group = { altitude = altitude, locs = {} }
            byAltitude[altitude] = group
            altitudes[#altitudes+1] = altitude
        end
        group.locs[#group.locs+1] = loc
    end
    table.sort(altitudes)
    local result = {}
    for _,altitude in ipairs(altitudes) do
        result[#result+1] = byAltitude[altitude]
    end
    return result
end

--Creates every layer for one placement, appending the handles to the group.
local function CreateLayers(group, recipe, placement, scale, parallax)
    for _,layer in ipairs(recipe.layers) do
        local options = LayerOptions(layer, placement, scale)
        if parallax ~= nil then
            options.parallax = parallax
        end
        local handle = dmhub.CreateParticleSystem(options)
        if handle ~= nil then
            group.handles[#group.handles+1] = handle
        end
    end
end

--Builds the handles for a group's placement. A tile placement gets one set of
--layers per distinct ground altitude among its tiles.
local function BuildGroup(group)
    local placement = group.placement
    if placement.locs ~= nil then
        for _,byAltitude in ipairs(GroupLocsByGroundAltitude(placement.locs)) do
            local sub = {}
            for k,v in pairs(placement) do
                sub[k] = v
            end
            sub.locs = byAltitude.locs
            CreateLayers(group, group.recipe, sub, group.scale, byAltitude.altitude)
        end
    else
        CreateLayers(group, group.recipe, placement, group.scale, nil)
    end
end

--- Moves the effect onto a new set of tiles (tile placements only). The layers
--- are rebuilt, since the tiles may now sit on different ground heights.
--- @param locs Loc[]
function ParticleEffectGroup:SetLocs(locs)
    self:Stop()
    self.handles = {}
    self.placement.locs = locs
    BuildGroup(self)
end

--- Creates a recipe's particle systems. A tile placement ({locs = ...}) follows the
--- height of the ground under each tile, so fire on a raised patch parallaxes with it.
--- @param id string Recipe id.
--- @param placement {locs: nil|Loc[], loc: nil|Loc, followToken: nil|string|CharacterToken}
--- @param scale nil|number Size multiplier (default 1); use it to fit a bigger creature.
--- @return ParticleEffectGroup|nil
function ParticleEffects.Create(id, placement, scale)
    local recipe = ParticleEffects.recipes[id]
    if recipe == nil then
        return nil
    end

    local ownPlacement = {}
    for k,v in pairs(placement) do
        ownPlacement[k] = v
    end

    local group = setmetatable({ handles = {}, recipe = recipe, placement = ownPlacement, scale = scale or 1 }, ParticleEffectGroup)
    BuildGroup(group)
    return group
end

--------------------------------------------------------------------------------
-- Built-in recipes.
--------------------------------------------------------------------------------

local IMAGE_FIRE = "ae67afec-58db-4654-86e9-8a19810ced1c"
local IMAGE_SOFT = "4550b2a0-49df-43f3-bcca-3805ebb7f84f"
local IMAGE_PUFF = "32bc28c1-ca12-42f4-814f-6a03df7f6d17"
local IMAGE_SPARK = "b9cb59b9-ddad-423b-b528-f154c7600b80"

--Ground fire seen from above, calm rather than roaring: a faint, even char layer
--darkens the ground so the additive flames have contrast on bright maps; a few slow,
--long-lived flame puffs and hot cores glow and fade in place; rare sparks and smoke
--rise off the fire. Rising is verticalSpeed: the parallax particle shader turns
--height into drift away from the camera centre, so smoke seems to waft up toward the
--viewer. Smoke and sparks sort above tokens so they drift over creatures in the fire.
--Tuned on a daylit grass map.
ParticleEffects.Register{
    id = "burning-ground",
    name = "Burning Ground",
    layers = {
        --char
        {
            image = IMAGE_SOFT, type = "Default", sortLayer = "EffectsAboveObjects", sortingOrder = 0,
            rate = 6, lifetime = { val = 2, maxVal = 3 }, speed = 0, verticalSpeed = 0,
            opacity = 0.05, fadein = 0.5, fadeout = 0.5,
            birthColor = { r = 0.22, g = 0.07, b = 0.02, a = 1 }, deathColor = { r = 0.12, g = 0.04, b = 0.02, a = 1 },
            birthSize = 1.8, deathSize = 1.9,
            worldSpace = true, maxParticles = 4000,
        },
        --flames
        {
            image = IMAGE_PUFF, type = "Additive", sortLayer = "EffectsAboveObjects", sortingOrder = 1,
            rate = 2.5, lifetime = { val = 3, maxVal = 4.5 }, speed = 0, verticalSpeed = 0.06,
            opacity = 0.85, fadein = 1, fadeout = 1.8,
            birthColor = { r = 1, g = 0.75, b = 0.3, a = 1 }, deathColor = { r = 1, g = 0.22, b = 0.03, a = 1 },
            birthSize = 1.1, deathSize = 0.7,
            rotation = { val = 0, maxVal = 6.28 }, rotationOverLifetime = { val = -0.15, maxVal = 0.15 },
            noiseStrength = { val = 0.01, maxVal = 0.02 }, noiseFrequency = 1, noiseScroll = { val = 0.05, maxVal = 0.1 },
            worldSpace = true, maxParticles = 4000,
        },
        --hot cores
        {
            image = IMAGE_FIRE, type = "Additive", sortLayer = "EffectsAboveObjects", sortingOrder = 2,
            rate = 2, lifetime = { val = 2, maxVal = 3.5 }, speed = 0, verticalSpeed = 0.06,
            opacity = 0.9, fadein = 0.8, fadeout = 1.4,
            birthColor = { r = 1, g = 0.95, b = 0.6, a = 1 }, deathColor = { r = 1, g = 0.5, b = 0.1, a = 1 },
            birthSize = 0.8, deathSize = 0.45,
            rotation = { val = 0, maxVal = 6.28 }, rotationOverLifetime = { val = -0.1, maxVal = 0.1 },
            worldSpace = true, maxParticles = 4000,
        },
        --sparks
        {
            image = IMAGE_SPARK, type = "Additive", sortLayer = "EffectsAboveTokens", sortingOrder = 0,
            rate = 0.6, lifetime = { val = 2, maxVal = 3 }, speed = { val = 0, maxVal = 0.05 }, verticalSpeed = 0.3,
            opacity = 1, fadein = 0.1, fadeout = 0.8,
            birthColor = { r = 1, g = 0.7, b = 0.2, a = 1 }, deathColor = { r = 1, g = 0.3, b = 0.02, a = 1 },
            birthSize = 0.07, deathSize = 0.02,
            noiseStrength = { val = 0.03, maxVal = 0.08 }, noiseFrequency = 0.7, noiseScroll = { val = 0.05, maxVal = 0.15 },
            worldSpace = true, maxParticles = 1000,
        },
        --smoke
        {
            image = IMAGE_PUFF, type = "Default", sortLayer = "EffectsAboveTokens", sortingOrder = 1,
            rate = 0.5, lifetime = { val = 4, maxVal = 6 }, speed = { val = 0.02, maxVal = 0.08 }, verticalSpeed = 0.25,
            opacity = 0.22, fadein = 1, fadeout = 2,
            birthColor = { r = 0.6, g = 0.57, b = 0.55, a = 1 }, deathColor = { r = 0.5, g = 0.5, b = 0.5, a = 1 },
            birthSize = 0.6, deathSize = 2.4,
            rotation = { val = 0, maxVal = 6.28 }, rotationOverLifetime = { val = -0.1, maxVal = 0.1 },
            noiseStrength = { val = 0.03, maxVal = 0.08 }, noiseFrequency = 0.4, noiseScroll = { val = 0.05, maxVal = 0.1 },
            worldSpace = true, maxParticles = 1000,
        },
    },
}

--A creature on fire: the same calm flames, cores and sparks on a small circle riding
--the token (drawn just above its art), plus a wisp of rising smoke, without the char
--layer. Particles are emitted in world space, so a moving creature leaves a short
--trail of fire behind it.
ParticleEffects.Register{
    id = "burning-creature",
    name = "Burning Creature",
    layers = {
        --flames
        {
            image = IMAGE_PUFF, type = "Additive", tokenRadius = 0.3,
            rate = 5, lifetime = { val = 2, maxVal = 3 }, speed = 0, verticalSpeed = 0.12,
            opacity = 0.85, fadein = 0.7, fadeout = 1.2,
            birthColor = { r = 1, g = 0.75, b = 0.3, a = 1 }, deathColor = { r = 1, g = 0.22, b = 0.03, a = 1 },
            birthSize = 0.75, deathSize = 0.45,
            rotation = { val = 0, maxVal = 6.28 }, rotationOverLifetime = { val = -0.15, maxVal = 0.15 },
            noiseStrength = { val = 0.01, maxVal = 0.02 }, noiseFrequency = 1, noiseScroll = { val = 0.05, maxVal = 0.1 },
            worldSpace = true, maxParticles = 1000,
        },
        --hot cores
        {
            image = IMAGE_FIRE, type = "Additive", tokenRadius = 0.25, sortingOrder = 1,
            rate = 3, lifetime = { val = 1.5, maxVal = 2.5 }, speed = 0, verticalSpeed = 0.12,
            opacity = 0.9, fadein = 0.6, fadeout = 1,
            birthColor = { r = 1, g = 0.95, b = 0.6, a = 1 }, deathColor = { r = 1, g = 0.5, b = 0.1, a = 1 },
            birthSize = 0.6, deathSize = 0.35,
            rotation = { val = 0, maxVal = 6.28 }, rotationOverLifetime = { val = -0.1, maxVal = 0.1 },
            worldSpace = true, maxParticles = 1000,
        },
        --sparks
        {
            image = IMAGE_SPARK, type = "Additive", tokenRadius = 0.35, sortingOrder = 2,
            rate = 1.2, lifetime = { val = 1.5, maxVal = 2.5 }, speed = { val = 0, maxVal = 0.05 }, verticalSpeed = 0.3,
            opacity = 1, fadein = 0.1, fadeout = 0.8,
            birthColor = { r = 1, g = 0.7, b = 0.2, a = 1 }, deathColor = { r = 1, g = 0.3, b = 0.02, a = 1 },
            birthSize = 0.06, deathSize = 0.02,
            noiseStrength = { val = 0.03, maxVal = 0.08 }, noiseFrequency = 0.7, noiseScroll = { val = 0.05, maxVal = 0.15 },
            worldSpace = true, maxParticles = 300,
        },
        --smoke
        {
            image = IMAGE_PUFF, type = "Default", tokenRadius = 0.2, sortingOrder = 3,
            rate = 1, lifetime = { val = 3, maxVal = 4.5 }, speed = { val = 0.02, maxVal = 0.06 }, verticalSpeed = 0.25,
            opacity = 0.15, fadein = 0.8, fadeout = 1.5,
            birthColor = { r = 0.6, g = 0.57, b = 0.55, a = 1 }, deathColor = { r = 0.5, g = 0.5, b = 0.5, a = 1 },
            birthSize = 0.4, deathSize = 1.4,
            rotation = { val = 0, maxVal = 6.28 }, rotationOverLifetime = { val = -0.1, maxVal = 0.1 },
            noiseStrength = { val = 0.03, maxVal = 0.08 }, noiseFrequency = 0.4, noiseScroll = { val = 0.05, maxVal = 0.1 },
            worldSpace = true, maxParticles = 300,
        },
    },
}

--A creature smoldering: sparks and wisps of smoke, no flames.
ParticleEffects.Register{
    id = "smoldering-creature",
    name = "Smoldering Creature",
    layers = {
        {
            image = IMAGE_SPARK, type = "Additive", tokenRadius = 0.35,
            rate = 5, lifetime = { val = 0.8, maxVal = 1.6 }, speed = { val = 0.05, maxVal = 0.2 }, verticalSpeed = 0.8,
            opacity = 1, fadein = 0.05, fadeout = 0.5,
            birthColor = { r = 1, g = 0.7, b = 0.2, a = 1 }, deathColor = { r = 1, g = 0.3, b = 0.02, a = 1 },
            birthSize = 0.06, deathSize = 0.02,
            noiseStrength = { val = 0.1, maxVal = 0.25 }, noiseFrequency = 0.7, noiseScroll = { val = 0.2, maxVal = 0.4 },
            worldSpace = true, maxParticles = 500,
        },
        {
            image = IMAGE_PUFF, type = "Default", tokenRadius = 0.25, sortingOrder = 1,
            rate = 3, lifetime = { val = 1.5, maxVal = 2.5 }, speed = 0, verticalSpeed = 0.5,
            opacity = 0.35, fadein = 0.3, fadeout = 0.7,
            birthColor = { r = 0.3, g = 0.28, b = 0.26, a = 1 }, deathColor = { r = 0.2, g = 0.2, b = 0.2, a = 1 },
            birthSize = 0.35, deathSize = 0.9,
            rotation = { val = 0, maxVal = 6.28 }, rotationOverLifetime = { val = -0.2, maxVal = 0.2 },
            worldSpace = true, maxParticles = 500,
        },
    },
}

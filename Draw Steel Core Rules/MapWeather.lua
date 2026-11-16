local mod = dmhub.GetModLoading()

-- ===========================================================================
-- Weather
-- ===========================================================================
-- The built-in weather effects. A weather effect is a Map Script (MapScript.lua)
-- tagged "weather": it is attached in the Weather section of Map Settings, runs
-- on every client viewing the map, and is visual only. It covers the floor
-- being viewed except its Sheltered zones (dmhub.CreateWeatherShelter): the
-- atmosphere always fades out there, and particles do when created with
-- shelterMask = true, which the shared prelude below sets.
--
-- Each one draws with three client-local engine effects:
--   * dmhub.CreateParticleSystem{ followView = true, ... }: particles over
--     whatever part of the map is on screen (rain, snow, embers). Rain and
--     snow set fallHeight, so they come down from above toward the ground.
--   * dmhub.CreateWorldAtmosphere{ ... }: a colour grade, drifting fog and a
--     heat shimmer over the whole map image.
-- It creates them in onActivate, adjusts them in onParamsChanged (so a slider
-- changes the weather without restarting it) and stops them in onDeactivate.
--
-- To write a new one, copy a script below into a Map Script in the compendium
-- (Rules > Map Scripts) and keep tags = { "weather" }. The code runs in its own
-- chunk, so each script carries its own helpers.

--Shared opening lines of every built-in: Start/Stop, written once. A weather
--script only supplies Look(params), which returns the options for its
--particle system (or a list of them, or nil for none) and for its
--atmosphere (or nil).
local g_prelude = [==[
local function Lerp(a, b, t)
    return a + (b - a) * t
end

--blends white toward a colour, as an {r, g, b} table.
local function Tint(color, amount)
    local c = core.Color(color)
    return { r = Lerp(1, c.r, amount), g = Lerp(1, c.g, amount), b = Lerp(1, c.b, amount), a = 1 }
end

local Look

--creates the effects the first time and adjusts them after that.
local function Apply(ctx)
    local particles, atmosphere = Look(ctx.params)
    local state = ctx.state

    --one table of options is one particle system; a list of them is several
    --layers (snow uses three for depth). The layer count must not change with
    --the params.
    local layers = particles or {}
    if particles ~= nil and particles[1] == nil then
        layers = { particles }
    end
    state.particles = state.particles or {}
    state.layerCount = #layers
    for i, options in ipairs(layers) do
        local system = state.particles[i]
        if system ~= nil and system.alive then
            system:Set(options)
        else
            --over whatever is on screen, but not over the empty space around the map,
            --and not inside Sheltered zones.
            options.followView = true
            options.onMapOnly = true
            options.shelterMask = true
            state.particles[i] = dmhub.CreateParticleSystem(options)
        end
    end

    if atmosphere ~= nil then
        if state.atmosphere ~= nil and state.atmosphere.alive then
            state.atmosphere:Set(atmosphere)
        else
            state.atmosphere = dmhub.CreateWorldAtmosphere(atmosphere)
        end
    end
end

--Creating a particle system fails while a game is still loading (the map's
--floors do not exist yet), so a weather attached before load would show no
--particles. Every second, recreate any layer that is missing or has died.
local function KeepAlive(ctx)
    local systems = ctx.state.particles or {}
    for i = 1, ctx.state.layerCount or 0 do
        local system = systems[i]
        if system == nil or not system.alive then
            Apply(ctx)
            return
        end
    end
end

local function Stop(ctx)
    for _, system in ipairs(ctx.state.particles or {}) do
        system:Stop()
    end
    ctx.state.particles = nil
    if ctx.state.atmosphere ~= nil then
        ctx.state.atmosphere:Stop(1)
        ctx.state.atmosphere = nil
    end
end
]==]

--info: { id, name, description, params (source text), look (source text of
--the body of Look(p)) }.
local function RegisterWeather(info)
    local code = string.format([==[
%s
Look = function(p)
%s
end

return {
    name = %q,
    description = %q,
    tags = { "weather" },

    params = {
%s
    },

    onActivate = Apply,
    onParamsChanged = Apply,
    onDeactivate = Stop,
    think = KeepAlive,
    thinkInterval = 1,
}
]==], g_prelude, info.look, info.name, info.description, info.params)

    MapScript.RegisterBuiltin{
        id = info.id,
        name = info.name,
        description = info.description,
        code = code,
    }
end

RegisterWeather{
    id = "builtin:weather-rain",
    name = "Rain",
    description = "Rain falling across the map, under an overcast sky.",
    params = [==[
        { id = "intensity", name = "Rainfall", type = "number", editor = "slider", default = 0.5, min = 0.05, max = 1 },
        { id = "wind", name = "Wind", type = "number", editor = "slider", default = 0, min = -1, max = 1 },
        { id = "splash", name = "Splashes", type = "number", editor = "slider", default = 0.4, min = 0, max = 1 },
        { id = "overcast", name = "Overcast", type = "number", editor = "slider", default = 0.5, min = 0, max = 1 },
]==],
    look = [==[
    local fall = 20 + 12 * p.intensity
    --Where a drop lands it leaves a ring that spreads and fades. That is the end
    --of the drop's own life, so the life is that much longer.
    local splash = p.splash or 0
    local splashTime = 0
    if splash > 0 then
        splashTime = 0.25 + 0.15 * splash
    end
    local particles = {
        viewMargin = 8,
        rate = 0.3 + 3.2 * p.intensity,
        lifetime = { val = 0.45 + splashTime, maxVal = 0.75 + splashTime },
        speed = 0,
        splash = splashTime,
        splashSize = 0.25 + 0.6 * splash,
        splashOpacity = 0.5 + 0.7 * splash,
        --Each drop comes down from high above the map to the spot where it lands,
        --drawn as a streak of its movement. With no wind the rain falls toward the
        --center of the view; wind carries it sideways and moves that point off-center.
        fallHeight = 40,
        streak = 0.08,
        velocity = { x = p.wind * 5, y = 0 },
        --With parallax turned off nothing can fall toward the ground: the rain
        --then slants across the map instead, each drop a streak leaning its way.
        flatVelocity = { x = p.wind * 14, y = -fall },
        aspect = 12,
        rotation = math.atan(p.wind * 14, fall),
        birthSize = 0.09,
        deathSize = 0.09,
        opacity = 0.3 + 0.3 * p.intensity,
        fadein = 0.05,
        --a splash does its own fading.
        fadeout = splashTime > 0 and 0 or 0.15,
        birthColor = "#d5e4ff",
        deathColor = "#d5e4ff",
        maxParticles = 8000,
        ignoreParallax = true,
    }
    local atmosphere = {
        tint = Tint("#8d9db8", p.overcast * 0.8),
        saturation = 1 - 0.35 * p.overcast,
        brightness = 1 - 0.15 * p.overcast,
        fogColor = "#8c98a6",
        fogDensity = 0.18 * p.overcast * p.intensity,
        fogScale = 14,
        fogPatchiness = 0.3,
        fogVelocity = { x = p.wind * 2, y = -0.5 },
    }
    return particles, atmosphere
]==],
}

RegisterWeather{
    id = "builtin:weather-snow",
    name = "Snow",
    description = "Snowflakes drifting down across the map in cold light.",
    params = [==[
        { id = "intensity", name = "Snowfall", type = "number", editor = "slider", default = 0.4, min = 0.05, max = 1 },
        { id = "wind", name = "Wind", type = "number", editor = "slider", default = 0, min = -1, max = 1 },
        { id = "chill", name = "Cold Light", type = "number", editor = "slider", default = 0.5, min = 0, max = 1 },
]==],
    look = [==[
    local gust = math.abs(p.wind)

    --One layer of flakes. A particle system gives every flake the same size, so
    --depth comes from three layers: many small dim slow flakes far below the
    --viewer, fewer mid ones, and a few large faint fast ones close to the eye.
    --near is 0 (far) to 1 (close).
    --cap is the most flakes the layer may have alive at once; the far layer
    --needs a high one so a blizzard over a zoomed-out view is not cut short.
    local function Layer(near, rate, size, opacity, life, cap)
        return {
            image = "4550b2a0-49df-43f3-bcca-3805ebb7f84f",
            viewMargin = 6,
            rate = rate,
            lifetime = { val = life, maxVal = life * 1.7 },
            speed = 0,
            --Flakes float down from above to where they settle, carried by the
            --wind. Close flakes start higher, so they sweep past faster.
            fallHeight = Lerp(7, 24, near),
            velocity = { x = p.wind * Lerp(2, 4.5, near), y = -0.4 * gust },
            --with parallax turned off they drift down the map instead.
            flatVelocity = { x = p.wind * Lerp(3.5, 7, near), y = -Lerp(0.9, 2.4, near) * (1 + gust) },
            noiseStrength = { val = Lerp(0.2, 0.6, near), maxVal = Lerp(0.6, 1.4, near) },
            noiseFrequency = 0.4,
            noiseScroll = 0.3,
            birthSize = size,
            deathSize = size * 0.7,
            opacity = opacity,
            fadein = 0.5,
            fadeout = 1,
            birthColor = "#ffffff",
            deathColor = "#eef4ff",
            maxParticles = cap,
            ignoreParallax = true,
        }
    end

    --Snowfall is the number of flakes, from a few stray ones to a blizzard
    --(about 15 times as many). It does not touch the fog or colour.
    local particles = {
        Layer(0, 0.04 + 2.4 * p.intensity, 0.11, 0.6, 3.5, 20000),
        Layer(0.45, 0.02 + 0.9 * p.intensity, 0.19, 0.85, 3, 8000),
        Layer(1, 0.005 + 0.12 * p.intensity, 0.4, 0.35, 2, 2000),
    }
    local atmosphere = {
        tint = Tint("#a9c4e8", p.chill * 0.7),
        saturation = 1 - 0.3 * p.chill,
        brightness = 1 + 0.05 * p.chill,
        fogColor = "#e6eef7",
        fogDensity = 0.15 * p.chill,
        fogScale = 12,
        fogPatchiness = 0.45,
        fogVelocity = { x = p.wind * 1.5, y = -0.3 },
    }
    return particles, atmosphere
]==],
}

RegisterWeather{
    id = "builtin:weather-fog",
    name = "Fog",
    description = "Banks of fog drifting slowly over the map.",
    params = [==[
        { id = "density", name = "Density", type = "number", editor = "slider", default = 0.5, min = 0.05, max = 1 },
        { id = "patchiness", name = "Patchiness", type = "number", editor = "slider", default = 0.6, min = 0, max = 1 },
        { id = "size", name = "Bank Size (tiles)", type = "number", editor = "slider", default = 8, min = 2, max = 30 },
        { id = "drift", name = "Drift", type = "number", editor = "slider", default = 0.4, min = 0, max = 3 },
        { id = "color", name = "Color", type = "color", default = "#c9d2d8" },
]==],
    look = [==[
    --A battle map has to stay readable through it: even full Density leaves the
    --thickest banks at about half opacity, and the engine's Patchiness opens clear
    --gaps between them. (Was 0.15 + 0.6 * density, a veil over the whole map.)
    local atmosphere = {
        saturation = 1 - 0.2 * p.density,
        fogColor = p.color,
        fogDensity = 0.05 + 0.45 * p.density,
        fogScale = p.size,
        fogPatchiness = p.patchiness,
        fogVelocity = { x = p.drift, y = p.drift * 0.35 },
    }
    return nil, atmosphere
]==],
}

RegisterWeather{
    id = "builtin:weather-heatwave",
    name = "Heat Wave",
    description = "The air shimmers with heat, bending everything on the map a little.",
    params = [==[
        { id = "intensity", name = "Heat", type = "number", editor = "slider", default = 0.5, min = 0.05, max = 1 },
]==],
    look = [==[
    local atmosphere = {
        tint = Tint("#ffe2b8", 0.5 * p.intensity),
        saturation = 1 + 0.1 * p.intensity,
        brightness = 1 + 0.06 * p.intensity,
        heatStrength = 1 + 4 * p.intensity,
        heatFrequency = 0.45,
        heatSpeed = 0.5 + 0.6 * p.intensity,
    }
    return nil, atmosphere
]==],
}

RegisterWeather{
    id = "builtin:weather-fiery-hell",
    name = "Fiery Hell",
    description = "The whole map glows orange-red, the air warps with heat and embers rise.",
    params = [==[
        { id = "intensity", name = "Glow", type = "number", editor = "slider", default = 0.6, min = 0.05, max = 1 },
        { id = "heat", name = "Heat Haze", type = "number", editor = "slider", default = 0.5, min = 0, max = 1 },
        { id = "embers", name = "Embers", type = "number", editor = "slider", default = 0.5, min = 0, max = 1 },
        { id = "color", name = "Color", type = "color", default = "#ff6a24" },
]==],
    look = [==[
    local particles = {
        image = "b9cb59b9-ddad-423b-b528-f154c7600b80",
        type = "Additive",
        viewMargin = 4,
        rate = 0.12 * p.embers,
        lifetime = { val = 2.5, maxVal = 5 },
        speed = 0,
        velocity = { x = 0.5, y = 1.4 },
        verticalSpeed = 0.5,
        noiseStrength = { val = 0.4, maxVal = 1.1 },
        noiseFrequency = 0.5,
        noiseScroll = 0.4,
        birthSize = 0.4,
        deathSize = 0.08,
        opacity = 0.9,
        fadein = 0.3,
        fadeout = 1.2,
        birthColor = "#ffc45e",
        deathColor = "#ff3b0a",
        maxParticles = 3000,
    }
    local atmosphere = {
        tint = Tint(p.color, 0.3 + 0.6 * p.intensity),
        saturation = 1 + 0.2 * p.intensity,
        contrast = 1 + 0.15 * p.intensity,
        fogColor = "#6e1505",
        fogDensity = 0.3 * p.intensity,
        fogScale = 10,
        fogPatchiness = 0.85,
        fogVelocity = { x = 0.3, y = 0.6 },
        heatStrength = 5 * p.heat,
        heatFrequency = 0.4,
        heatSpeed = 0.8,
    }
    return particles, atmosphere
]==],
}

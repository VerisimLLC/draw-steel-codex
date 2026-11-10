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
--particle system (or nil for none) and for its atmosphere (or nil).
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

    if particles ~= nil then
        if state.particles ~= nil and state.particles.alive then
            state.particles:Set(particles)
        else
            --over whatever is on screen, but not over the empty space around the map,
            --and not inside Sheltered zones.
            particles.followView = true
            particles.onMapOnly = true
            particles.shelterMask = true
            state.particles = dmhub.CreateParticleSystem(particles)
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

local function Stop(ctx)
    if ctx.state.particles ~= nil then
        ctx.state.particles:Stop()
        ctx.state.particles = nil
    end
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
        { id = "wind", name = "Wind", type = "number", editor = "slider", default = 0.3, min = -1, max = 1 },
        { id = "overcast", name = "Overcast", type = "number", editor = "slider", default = 0.5, min = 0, max = 1 },
]==],
    look = [==[
    local fall = 20 + 12 * p.intensity
    local particles = {
        viewMargin = 8,
        rate = 0.3 + 3.2 * p.intensity,
        lifetime = { val = 0.45, maxVal = 0.75 },
        speed = 0,
        --Each drop comes down from high above the map to the spot where it lands,
        --drawn as a streak of its movement; the wind carries it sideways.
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
        fadeout = 0.15,
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
        { id = "wind", name = "Wind", type = "number", editor = "slider", default = 0.2, min = -1, max = 1 },
        { id = "chill", name = "Cold Light", type = "number", editor = "slider", default = 0.5, min = 0, max = 1 },
]==],
    look = [==[
    local gust = math.abs(p.wind)
    local particles = {
        image = "4550b2a0-49df-43f3-bcca-3805ebb7f84f",
        viewMargin = 6,
        rate = 0.1 + 0.7 * p.intensity,
        lifetime = { val = 3, maxVal = 5 },
        speed = 0,
        --Flakes float down from above to where they settle, carried by the wind.
        fallHeight = 12,
        velocity = { x = p.wind * 3, y = -0.4 * gust },
        --with parallax turned off they drift down the map instead.
        flatVelocity = { x = p.wind * 5, y = -(1.2 + 1.5 * gust) },
        noiseStrength = { val = 0.3, maxVal = 0.8 },
        noiseFrequency = 0.4,
        noiseScroll = 0.3,
        birthSize = 0.22,
        deathSize = 0.15,
        opacity = 0.9,
        fadein = 0.5,
        fadeout = 1,
        birthColor = "#ffffff",
        deathColor = "#eef4ff",
        maxParticles = 8000,
        ignoreParallax = true,
    }
    local atmosphere = {
        tint = Tint("#a9c4e8", p.chill * 0.7),
        saturation = 1 - 0.3 * p.chill,
        brightness = 1 + 0.05 * p.chill,
        fogColor = "#e6eef7",
        fogDensity = 0.3 * p.intensity * p.chill,
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
    local atmosphere = {
        saturation = 1 - 0.35 * p.density,
        fogColor = p.color,
        fogDensity = 0.15 + 0.6 * p.density,
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

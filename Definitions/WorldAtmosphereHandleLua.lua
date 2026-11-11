---@meta

--- @class WorldAtmosphereOptions The options of a world atmosphere; see dmhub.CreateWorldAtmosphere.
--- @field tint Color|nil
--- @field saturation number|nil
--- @field brightness number|nil
--- @field contrast number|nil
--- @field fogColor Color|nil
--- @field fogDensity number|nil
--- @field fogScale number|nil
--- @field fogPatchiness number|nil
--- @field fogVelocity Vector2Arg|nil
--- @field heatStrength number|nil
--- @field heatFrequency number|nil
--- @field heatSpeed number|nil
--- @field fadeIn number|nil

--- A local handle to a world atmosphere created by dmhub.CreateWorldAtmosphere. The effect is removed when Stop()/Destroy() is called or the client changes maps.
--- @class WorldAtmosphereHandleLua
--- @field alive boolean True while the atmosphere is active on this client. False once Stop() has been called, even while it fades out.
WorldAtmosphereHandleLua = {}

--- Changes any creation option on the live atmosphere. Omitted fields keep their current values.
--- @param options WorldAtmosphereOptions
--- @return nil
function WorldAtmosphereHandleLua:Set(options) end

--- Removes the atmosphere, fading it out over fadeOut seconds (default 1; 0 removes it at once). Safe to call more than once.
--- @param fadeOut number|nil
--- @return nil
function WorldAtmosphereHandleLua:Stop(fadeOut) end

--- Removes the atmosphere at once. Safe to call more than once.
function WorldAtmosphereHandleLua:Destroy() end

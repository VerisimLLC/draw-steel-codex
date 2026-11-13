---@meta

--- A local handle to a sheltered area created by dmhub.CreateWeatherShelter. It is removed when Destroy() is called or the client changes maps.
--- @class WeatherShelterHandleLua
--- @field alive boolean True while the shelter exists on this client.
WeatherShelterHandleLua = {}

--- Replaces the shelter's tiles. The shelter moves to the floor of the first loc.
--- @param locs Loc[]
--- @return nil
function WeatherShelterHandleLua:SetLocs(locs) end

--- Removes the shelter. Safe to call more than once.
function WeatherShelterHandleLua:Destroy() end

---@meta

--- Charge routes remembered by CharacterToken:FindChargeRoutes. Make one with dmhub.CreateChargeRouteCache for a planning pass and drop it as soon as anything on the map may have moved.
--- @class LuaChargeRouteCache
--- @field count number (Read-only) The number of routes remembered, valid or not.
LuaChargeRouteCache = {}

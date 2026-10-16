---@meta

--- A handle to an effect started with token:BroadcastEffect. Stop() on the client that started it ends the effect on every client.
--- @class NetworkedEffectHandleLua
--- @field alive boolean (read-only) False once the effect has been stopped or has finished on this client, or if this client did not play it (it could not see the token). True while it plays or is still loading.
NetworkedEffectHandleLua = {}

--- Stop the effect: emission stops immediately and live particles fade out. Called on the client that started the effect, it also stops the effect on every other client.
function NetworkedEffectHandleLua:Stop() end

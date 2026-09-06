---@meta

--- Handle to an active email-status listener. Call Stop() to unsubscribe (e.g. when the settings panel is destroyed).
--- @class LuaEmailConfirmationMonitor
LuaEmailConfirmationMonitor = {}

--- Stops listening for email-status changes.
function LuaEmailConfirmationMonitor:Stop() end

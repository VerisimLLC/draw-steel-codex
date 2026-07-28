--- @class LuaEmailConfirmationMonitor Handle to an active email-status listener. Call Stop() to unsubscribe (e.g. when the settings panel is destroyed).
LuaEmailConfirmationMonitor = {}

--- Stop: Stops listening for email-status changes.
--- @return nil
function LuaEmailConfirmationMonitor:Stop()
	-- dummy implementation for documentation purposes only
end

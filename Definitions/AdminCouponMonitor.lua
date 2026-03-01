--- @class AdminCouponMonitor Monitors gift codes associated with a specific store item. Fires events as codes are discovered and loaded.
--- @field events EventSourceLua Gets the event source that fires 'code' events with the current table of loaded coupon entries.
AdminCouponMonitor = {}

--- Destroy: Stops monitoring and releases the data store subscription.
--- @return nil
function AdminCouponMonitor:Destroy()
	-- dummy implementation for documentation purposes only
end

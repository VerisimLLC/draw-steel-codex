---@meta

--- Monitors gift codes associated with a specific store item. Fires events as codes are discovered and loaded.
--- @class AdminCouponMonitor
--- @field events EventSourceLua Gets the event source that fires 'code' events with the current table of loaded coupon entries.
AdminCouponMonitor = {}

--- Stops monitoring and releases the data store subscription.
function AdminCouponMonitor:Destroy() end

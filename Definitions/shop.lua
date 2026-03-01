--- @class shop Provides access to the DMHub store, including inventory management, checkout, and gift code operations.
--- @field events EventSourceLua Gets the event source for store-related events such as inventory refreshes.
--- @field inventoryItems {[string]: ShopItemInstance} Gets a table of all inventory item instances owned by the current user, keyed by item instance ID.
shop = {}

--- ItemInInventory: Returns true if the user's inventory contains an item with the given item ID.
--- @param itemid string
--- @return boolean
function shop:ItemInInventory(itemid)
	-- dummy implementation for documentation purposes only
end

--- AcknowledgeNewInventoryItems: Acknowledges and returns any new inventory items the user has not yet seen. Returns nil if there are no new items.
--- nil|{[string]: ShopItemInstance}
function shop:AcknowledgeNewInventoryItems()
	-- dummy implementation for documentation purposes only
end

--- CheckoutSubscription: Opens the subscription checkout page in a browser. Tiers: 0 = none/cancel, 2 = premium basic, 3 = premium plus.
--- @param tier number
--- @return nil
function shop:CheckoutSubscription(tier)
	-- dummy implementation for documentation purposes only
end

--- Checkout: Opens the checkout page in a browser for the given cart items. Supports an optional gift configuration in args.
--- @param items {[string]: any} Table of item IDs to purchase.
--- @param args nil|{gift: table} Optional arguments including gift recipient info.
function shop:Checkout(items, args)
	-- dummy implementation for documentation purposes only
end

--- QueryGiftCode: Queries a gift code from the store. Calls callback with a StoreCouponEntry on success (or nil if invalid), or errorCallback on failure.
--- @param code string The gift code to query.
--- @param callback fun(entry: nil|StoreCouponEntry) Called with the coupon entry on success.
--- @param errorCallback fun(error: string) Called with an error message on failure.
function shop:QueryGiftCode(code, callback, errorCallback)
	-- dummy implementation for documentation purposes only
end

--- AdminSetGiftCodeNote: Sets an admin note on an existing gift code. Requires admin permissions.
--- @param code string
--- @param note string
--- @return nil
function shop:AdminSetGiftCodeNote(code, note)
	-- dummy implementation for documentation purposes only
end

--- AdminCreateGiftCode: Creates a new gift code with the given data. Requires admin permissions.
--- @param code string The gift code string.
--- @param data {itemid: string, [string]: any} Table containing at least an itemid field.
function shop:AdminCreateGiftCode(code, data)
	-- dummy implementation for documentation purposes only
end

--- MonitorItemGiftCodes: Creates and returns an AdminCouponMonitor that watches for gift codes associated with the given item ID.
--- @param itemid string The item ID to monitor gift codes for.
--- @return AdminCouponMonitor
function shop:MonitorItemGiftCodes(itemid)
	-- dummy implementation for documentation purposes only
end

--- RetrieveGiftCodes: Retrieves all gift codes owned by the current user. Returns the number of codes being queried. Calls callback for each code, errorCallback on error, and completeCallback when all codes are retrieved.
--- @param callback fun(entry: StoreCouponEntry) Called for each successfully retrieved gift code.
--- @param errorCallback fun(error: string) Called for each gift code that fails to load.
--- @param completeCallback fun(entries: table) Called when all gift codes have been retrieved.
function shop:RetrieveGiftCodes(callback, errorCallback, completeCallback)
	-- dummy implementation for documentation purposes only
end

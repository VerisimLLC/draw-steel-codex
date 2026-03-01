--- @class ShopItemLua Lua interface for a shop item, providing read/write access to its name, price, images, and other metadata.
--- @field name string The display name of this shop item.
--- @field details string The detailed description text of this shop item.
--- @field keywords string Comma-separated keywords for searching.
--- @field artistid string The identifier of the artist who created this item.
--- @field price number The price in tokens.
--- @field autoInstall boolean Whether this module auto-installs when purchased.
--- @field hasBundle boolean True if this shop item includes a bundle of other items.
--- @field bundle table<string, boolean> A table of bundled item IDs mapped to true. Read/write.
--- @field images string[] List of image asset identifiers for this shop item's gallery.
--- @field itemType string The type of this shop item as a string ('Dice', 'Module', 'Bundle', 'Bandwidth', 'None').
--- @field assetid string The underlying asset identifier this item grants access to.
--- @field units number The number of units for quantity-based items (e.g. bandwidth).
--- @field onsale boolean True if this item is currently on sale.
--- @field ctime number The creation timestamp of this shop item.
ShopItemLua = {}

--- Upload: Uploads changes to this shop item to the cloud.
--- @return nil
function ShopItemLua:Upload()
	-- dummy implementation for documentation purposes only
end

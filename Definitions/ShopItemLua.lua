--- @class ShopItemLua Lua interface for a shop item, providing read/write access to its name, price, images, and other metadata.
--- @field name string The display name of this shop item.
--- @field details string The detailed description text of this shop item.
--- @field keywords string Comma-separated keywords for searching.
--- @field artistid string The identifier of the artist who created this item.
--- @field price number The price in tokens.
--- @field autoInstall boolean Whether this module auto-installs when purchased.
--- @field hasBundle boolean True if this shop item includes a bundle of other items.
--- @field bundle table<string, boolean> A table of bundled item IDs mapped to true. Read/write.
--- @field hasAnimatedTokens boolean True if this is an AnimatedTokens item that grants one or more animated tokens.
--- @field animatedTokens table<string, boolean> A table of animated-token spine registry names (e.g. 'lightbender') mapped to true, granted by this item. Read/write. Only meaningful for AnimatedTokens-type items.
--- @field images string[] List of image asset identifiers for this shop item's gallery.
--- @field itemType string The type of this shop item as a string ('Dice', 'Module', 'Bundle', 'Bandwidth', 'AnimatedTokens', 'None').
--- @field assetid string The underlying asset identifier this item grants access to.
--- @field units number The number of units for quantity-based items (e.g. bandwidth).
--- @field diceBanner table The featured-dice banner customization for this Dice item: a table with backgroundImage, foregroundImage (Core-asset image guids; empty means that layer is transparent), diceScale, dieX, dieY, dieSize (dice transform), spinDirection (degrees the idle spin axis is rotated about the screen-normal Z axis; 0 = default vertical spin, 180 = reversed, 90 = tumbling -- speed stays constant), textPlacement ('left'/'right'/'topleft'/'topright'/'bottomleft'/'bottomright') and textOffsetX/textOffsetY. Reading returns a full table, or nil if never configured. Writing a table stores it; writing nil clears it. Only meaningful for Dice-type items.
--- @field dicePreview table The small shop-tile preview customization for this Dice item: the same table shape as diceBanner (backgroundImage, foregroundImage, diceScale, dieX, dieY, dieSize, spinDirection; the text fields are stored but tiles draw no text overlay). Reading returns a full table, or nil if never configured (tiles then derive their look from diceBanner). Writing a table stores it; writing nil clears it back to automatic. Only meaningful for Dice-type items.
--- @field onsale boolean True if this item is currently on sale.
--- @field preview boolean True if this item is in preview on the store: shown in the customer-facing shop only to users with the dev:storeitempreview preference enabled. Mutually exclusive with onsale; the admin UI clears it when an item goes live or leaves the store.
--- @field hidden boolean True if this item is soft-hidden from the admin shop list. An item that is on the store (onsale or preview) is never hidden.
--- @field featured boolean True if this item is featured in the shop. Only items that are live on the store (onsale) can be featured.
--- @field ctime number The creation timestamp of this shop item.
ShopItemLua = {}

--- Upload: Uploads changes to this shop item to the cloud.
--- @return nil
function ShopItemLua:Upload()
	-- dummy implementation for documentation purposes only
end

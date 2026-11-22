---@meta

--- Represents an instance of a purchased shop item in a user's inventory.
--- @class ShopItemInstance
--- @field shopItem any The underlying ShopItem definition for this instance.
--- @field itemid string The shop item identifier.
--- @field ctime number The creation/purchase timestamp.
--- @field bundleid string
--- @field borrowed boolean True if this item is not in this account's own inventory but borrowed, read-only, from the main account of a "New Player Window".
--- @field promoId string The id of the Patreon promo that granted this item, or nil if it came from a purchase, a gift code, or anything else. See shop:GetUnacknowledgedPromoGrants.
ShopItemInstance = {}

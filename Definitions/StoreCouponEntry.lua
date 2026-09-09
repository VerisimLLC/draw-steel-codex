---@meta

--- Represents a store coupon entry, including its item, redemption status, and associated metadata.
--- @class StoreCouponEntry
--- @field mtime number The redemption timestamp as a number (alias for redeemTime).
--- @field ctime number The creation timestamp as a number.
--- @field itemid string The store item identifier this coupon is for.
--- @field checkoutid string The checkout session identifier.
--- @field redeemed boolean True if the coupon has been redeemed.
--- @field createTimestamp number Unix timestamp when the coupon was created.
--- @field redeemTime number Unix timestamp when the coupon was redeemed.
--- @field redeemUserFullName string Display name of the user who redeemed this coupon.
--- @field redeemUserId string User ID of the user who redeemed this coupon.
--- @field redeemInstanceId string The instance ID of the item this coupon was redeemed into.
--- @field admin boolean True if this coupon was created by DMHub admins rather than purchased by a user.
--- @field adminNote string Admin note attached to admin-created coupons.
--- @field code string The coupon code string (not serialized).
StoreCouponEntry = {}

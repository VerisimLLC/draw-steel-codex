local mod = dmhub.GetModLoading()

--Timed sales on shop items. A sale is three ShopItem fields: salePrice (US
--cents), saleStart and saleEnd (unix seconds, end exclusive). While a sale runs
--the store shows the normal price struck through, the sale price, and "Sale".
--The Steam checkout cloud function (steamPurchaseInit) charges the sale price
--by the server's own clock, so what is shown here is what Steam is asked for.
--
--Every store surface reads prices through ShopSale.Price / ShopSale.PriceText
--so a sale shows up everywhere at once.

---@class ShopSaleInfo
---@field price number sale price in US cents
---@field start number unix seconds
---@field finish number unix seconds (exclusive)

ShopSale = {}

local g_strikeColor = "#8c8c8cff"
local g_saleColor = "#f0b84aff"

--The sale fields only exist on a new enough engine. On an older one the read
--errors, and every item simply has no sale.
---@param item ShopItemLua
---@return ShopSaleInfo|nil
function ShopSale.Read(item)
    if item == nil then
        return nil
    end
    local result = nil
    pcall(function()
        result = {
            price = item.salePrice or 0,
            start = item.saleStart or 0,
            finish = item.saleEnd or 0,
        }
    end)
    if result == nil or result.price <= 0 then
        return nil
    end
    return result
end

--True if the item's engine has the sale fields, so the admin editor can hide
--itself on an older build where writes would silently do nothing.
---@param item ShopItemLua
---@return boolean
function ShopSale.Supported(item)
    local ok = pcall(function() return item.salePrice end)
    return ok
end

--A sale only counts while it is running and actually cheaper than the price.
---@param item ShopItemLua
---@param now? number unix seconds; defaults to this computer's clock
---@return boolean
function ShopSale.IsActive(item, now)
    local sale = ShopSale.Read(item)
    if sale == nil or item.price <= 0 or sale.price >= item.price then
        return false
    end
    now = now or os.time()
    return sale.start <= now and now < sale.finish
end

--What the item costs right now, in US cents.
---@param item ShopItemLua
---@return number
function ShopSale.Price(item)
    if ShopSale.IsActive(item) then
        return ShopSale.Read(item).price
    end
    return item.price
end

--US cents as "$12.34".
---@param cents number
---@return string
function ShopSale.FormatCents(cents)
    return string.format("$%d.%02d", math.tointeger(math.floor(cents/100)), math.tointeger(cents%100))
end

--The price as rich text. During a sale: the normal price struck through, the
--sale price, then "Sale". Otherwise just the price, or the free text.
--opts.suffix is appended to each dollar amount (the store cards use "US");
--opts.free is the text for a free item (default "FREE");
--opts.plain = true gives just the current price with no strike or Sale tag
--(for Add to Cart buttons).
---@param item ShopItemLua
---@param opts? {suffix: string|nil, free: string|nil, plain: boolean|nil}
---@return string
function ShopSale.PriceText(item, opts)
    opts = opts or {}
    local suffix = opts.suffix or ""
    if item.price <= 0 then
        return opts.free or "FREE"
    end

    if not ShopSale.IsActive(item) then
        return ShopSale.FormatCents(item.price) .. suffix
    end

    local salePrice = ShopSale.Read(item).price
    if opts.plain then
        return ShopSale.FormatCents(salePrice) .. suffix
    end

    return string.format("<color=%s><s>%s%s</s></color>  %s%s  <color=%s><b>Sale</b></color>",
        g_strikeColor, ShopSale.FormatCents(item.price), suffix,
        ShopSale.FormatCents(salePrice), suffix,
        g_saleColor)
end

--Admin helpers: sale dates are entered as YYYY-MM-DD in the admin's local
--time. The start date begins at local midnight; the end date is inclusive, so
--the sale runs until the midnight after it.

--Parses "YYYY-MM-DD" to unix seconds at local midnight, or nil.
---@param text string
---@return number|nil
function ShopSale.ParseDate(text)
    local y, m, d = string.match(text or "", "^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*$")
    if y == nil then
        return nil
    end
    local year, month, day = math.tointeger(tonumber(y)) or 0, math.tointeger(tonumber(m)) or 0, math.tointeger(tonumber(d)) or 0
    if month < 1 or month > 12 or day < 1 or day > 31 then
        return nil
    end
    local t = os.time{ year = year, month = month, day = day, hour = 0, min = 0, sec = 0 }
    --os.time rolls Feb 31 over into March; refuse dates that do not exist.
    local check = os.date("*t", t) --[[@as osdate]]
    if check.year ~= year or check.month ~= month or check.day ~= day then
        return nil
    end
    return t
end

--Unix seconds to "YYYY-MM-DD" in local time.
---@param t number
---@return string
function ShopSale.FormatDate(t)
    return os.date("%Y-%m-%d", math.floor(t)) --[[@as string]]
end

--Local midnight after the given day's midnight (handles DST-length days).
---@param t number unix seconds at local midnight
---@return number
function ShopSale.NextDay(t)
    local d = os.date("*t", math.floor(t)) --[[@as osdate]]
    return os.time{ year = d.year, month = d.month, day = d.day + 1, hour = 0, min = 0, sec = 0 }
end

--The day before, for showing an exclusive end time as the inclusive end date.
---@param t number
---@return number
function ShopSale.PrevDay(t)
    local d = os.date("*t", math.floor(t)) --[[@as osdate]]
    return os.time{ year = d.year, month = d.month, day = d.day - 1, hour = 0, min = 0, sec = 0 }
end

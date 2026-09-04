--- A fish species: the named, sized creature a scoring cast produces
--- Lives in the Director-editable FishSpecies compendium table.
--- @class FishSpecies
--- @field id string GUID identifier (engine-managed for table items)
--- @field name string Display name
--- @field waterType string An FSHConstants.WATER_TYPE key
--- @field band string An FSHConstants.BAND key
--- @field icon string Icon path
--- @field color string Hex tint applied to the icon
--- @field flavor string Optional one-line description
--- @field tableName string Data table name ("FishSpecies")
FishSpecies = RegisterGameType("FishSpecies")

FishSpecies.tableName = "FishSpecies"

FishSpecies.name = "New Fish"
FishSpecies.waterType = "fresh"
FishSpecies.band = "tiny"
FishSpecies.icon = "phosphor/fish-simple.png"
FishSpecies.color = "#8fd4b0"
FishSpecies.flavor = ""

--- Creates a new species instance
--- @param args table|nil Optional field overrides (Compendium calls this as CreateNew{})
--- @return FishSpecies instance The new species instance
function FishSpecies.CreateNew(args)
    args = args or {}
    return FishSpecies.new(args)
end

--- Gets the identifier of this species
--- @return string id GUID id of this species
function FishSpecies:GetID()
    return self:try_get("id") or ""
end

--- Gets the display name of this species
--- @return string name The species name
function FishSpecies:GetName()
    return self.name or ""
end

--- Sets the display name of this species
--- @param name string The new name
--- @return FishSpecies self For chaining
function FishSpecies:SetName(name)
    self.name = name or ""
    return self
end

--- Gets the water type this species is found in
--- @return string waterType An FSHConstants.WATER_TYPE key
function FishSpecies:GetWaterType()
    return self.waterType or FSHConstants.WATER_TYPE.FRESH.key
end

--- Sets the water type this species is found in
--- @param waterType string An FSHConstants.WATER_TYPE key
--- @return FishSpecies self For chaining
function FishSpecies:SetWaterType(waterType)
    if FishSpecies._isValidWaterType(waterType) then
        self.waterType = waterType
    end
    return self
end

--- Gets the size band of this species
--- @return string band An FSHConstants.BAND key
function FishSpecies:GetBand()
    return self.band or FSHConstants.BAND.TINY.key
end

--- Sets the size band of this species
--- @param band string An FSHConstants.BAND key
--- @return FishSpecies self For chaining
function FishSpecies:SetBand(band)
    if FishSpecies._isValidBand(band) then
        self.band = band
    end
    return self
end

--- Gets the icon path for this species
--- @return string icon The icon path
function FishSpecies:GetIcon()
    return self.icon or FSHConstants.GENERIC_FISH.icon
end

--- Sets the icon path for this species
--- @param icon string The icon path
--- @return FishSpecies self For chaining
function FishSpecies:SetIcon(icon)
    self.icon = icon or FSHConstants.GENERIC_FISH.icon
    return self
end

--- Gets the colour tint for this species
--- @return string color Hex colour
function FishSpecies:GetColor()
    return self.color or FSHConstants.GENERIC_FISH.color
end

--- Sets the colour tint for this species
--- @param color string Hex colour
--- @return FishSpecies self For chaining
function FishSpecies:SetColor(color)
    self.color = color or FSHConstants.GENERIC_FISH.color
    return self
end

--- Gets the flavor line for this species
--- @return string flavor The flavor text
function FishSpecies:GetFlavor()
    return self.flavor or ""
end

--- Sets the flavor line for this species
--- @param flavor string The flavor text
--- @return FishSpecies self For chaining
function FishSpecies:SetFlavor(flavor)
    self.flavor = flavor or ""
    return self
end

--- Determines which size band a point total falls in
--- @param points number The final total of a scoring cast
--- @return string band An FSHConstants.BAND key
function FishSpecies.BandForPoints(points)
    points = math.floor(points or 0)

    for _, band in ipairs(FSHConstants.BAND) do
        local range = FSHConstants.BAND_POINTS[band.key]
        if range and points >= range.min and (range.max == nil or points <= range.max) then
            return band.key
        end
    end

    --Only reachable below the lowest band, which is not a catch.
    return FSHConstants.BAND.TINY.key
end

--- Gets the live species matching a water type and band
--- @param waterType string An FSHConstants.WATER_TYPE key
--- @param band string An FSHConstants.BAND key
--- @return FishSpecies[] entries The matching species
function FishSpecies.Entries(waterType, band)
    local entries = {}

    local speciesTable = dmhub.GetTable(FishSpecies.tableName) or {}
    for _, species in unhidden_pairs(speciesTable) do
        if species:GetWaterType() == waterType and species:GetBand() == band then
            entries[#entries + 1] = species
        end
    end

    return entries
end

--- Gets the live species for a water type, grouped by band and sorted by name
--- @param waterType string An FSHConstants.WATER_TYPE key
--- @return table grouped Map of band key to sorted FishSpecies array
function FishSpecies.GroupedByBand(waterType)
    local grouped = {}

    for _, band in ipairs(FSHConstants.BAND) do
        local entries = FishSpecies.Entries(waterType, band.key)
        table.sort(entries, function(a, b) return a:GetName() < b:GetName() end)
        grouped[band.key] = entries
    end

    return grouped
end

--- Picks a species for a landed cast
--- Returns a by-value snapshot rather than a table reference, so a Director
--- editing the species table later can never rewrite a recorded catch.
--- @param waterType string An FSHConstants.WATER_TYPE key
--- @param points number The final total of the cast
--- @return table snapshot Fields name, icon, color, and band
function FishSpecies.Select(waterType, points)
    local band = FishSpecies.BandForPoints(points)
    local candidates = FishSpecies.Entries(waterType, band)

    if #candidates == 0 then
        return {
            name = FSHConstants.GENERIC_FISH.name,
            icon = FSHConstants.GENERIC_FISH.icon,
            color = FSHConstants.GENERIC_FISH.color,
            band = band
        }
    end

    local pick = candidates[math.random(#candidates)]
    return {
        name = pick:GetName(),
        icon = pick:GetIcon(),
        color = pick:GetColor(),
        band = band
    }
end

--- Picks a band-appropriate icon, used to give a newly added species a sensible
--- starting look rather than a fixed default
--- @param band string An FSHConstants.BAND key
--- @param index number Position within the band, one-based
--- @return string icon The icon path
function FishSpecies.IconFor(band, index)
    local pool = FSHConstants.SPECIES_ICONS[band]
    if pool == nil or #pool == 0 then
        return FSHConstants.GENERIC_FISH.icon
    end
    return pool[((index - 1) % #pool) + 1]
end

--- Nudges a band's base colour a little per species so entries within one band
--- still read as individuals
--- @param waterType string An FSHConstants.WATER_TYPE key
--- @param band string An FSHConstants.BAND key
--- @param index number Position within the band, one-based
--- @return string color Hex colour
function FishSpecies.ColorFor(waterType, band, index)
    local palette = FSHConstants.SPECIES_COLORS[waterType]
    local base = palette ~= nil and palette[band] or nil
    if base == nil then
        return FSHConstants.GENERIC_FISH.color
    end

    local function channel(value, multiplier)
        local shifted = value + (((index * multiplier) % 21) - 10)
        return math.max(0, math.min(255, shifted))
    end

    local r = channel(tonumber(base:sub(2, 3), 16), 37)
    local g = channel(tonumber(base:sub(4, 5), 16), 53)
    local b = channel(tonumber(base:sub(6, 7), 16), 71)

    return string.format("#%02x%02x%02x", r, g, b)
end

--- Validates a water type
--- @param waterType string The water type to validate
--- @return boolean valid True if the water type is valid
function FishSpecies._isValidWaterType(waterType)
    for _, valid in ipairs(FSHConstants.WATER_TYPE) do
        if waterType == valid.key then
            return true
        end
    end
    return false
end

--- Validates a size band
--- @param band string The band to validate
--- @return boolean valid True if the band is valid
function FishSpecies._isValidBand(band)
    for _, valid in ipairs(FSHConstants.BAND) do
        if band == valid.key then
            return true
        end
    end
    return false
end

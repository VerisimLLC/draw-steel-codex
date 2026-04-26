local mod = dmhub.GetModLoading()

--- ThemeEngine — UI theming engine for Draw Steel Codex.
--- Registries for color schemes and themes, a resolver with sigil-based substitution,
--- a cache keyed by the resolved (theme, scheme) pair, and an OnThemeChanged event.
--- Default content (default theme, default color scheme) and settings-UI wiring
--- are handled elsewhere; this file is the engine only.
---
--- Color and font properties in style rules may reference named values via the
--- @name sigil. The engine resolves these at GetStyles() time using property-typed
--- resolution: color/bgcolor/borderColor -> colors table; fontFace -> fonts table.
--- @class ThemeEngine
ThemeEngine = {} --RegisterGameType("ThemeEngine")

-- =============================================================================
-- Private state
-- =============================================================================

local _colorSchemes = {}         -- schemeId -> stored color-scheme spec
local _themes = {}               -- themeId -> stored theme spec

local _activeThemeId = nil
local _activeSchemeId = nil

local _cache = {}                -- "themeId|schemeId" -> resolved styles array
local _loggedUnresolved = {}     -- set of "domain:name" keys already logged

-- =============================================================================
-- Constants
-- =============================================================================

local COLOR_PROPS = { color = true, bgcolor = true, borderColor = true }
local FONT_PROPS = { fontFace = true }
local GRADIENT_PROPS = { gradient = true }

local UNRESOLVED_COLOR = "#FF00FF"  -- magenta, loud in UI
local UNRESOLVED_FONT = "Berling"     -- known safe fallback

local DEFAULT_THEME_ID = "default"
local DEFAULT_SCHEME_ID = "default"

local THEME_CHANGED_EVENT = "ThemeEngine.ThemeChanged"

-- =============================================================================
-- Font catalog (hardcoded — DMHub owns which font files exist)
-- =============================================================================
-- Kept in alphabetical order by `name`. Add new entries in the right slot so
-- ListFontFaces returns them sorted without runtime sorting.

local FONT_CATALOG = {
    {
        name = "Berling",
        style = "serif",
        uses = { "body", "label", "input" },
        description = "Codex default serif for long-form text, labels, and form inputs.",
    },
    {
        name = "Book",
        style = "serif",
        uses = { "heading", "numeric" },
        description = "Serif with strong numerals; used in dice panels and the initiative bar.",
    },
    {
        name = "Cambria",
        style = "serif",
        uses = { "body" },
        description = "Classic serif body face.",
    },
    {
        name = "Colvillain",
        style = "display",
        uses = { "heading", "decorative" },
        description = "Ornate display face for thematic headers in the game HUD.",
    },
    {
        name = "Courier",
        style = "mono",
        uses = { "code" },
        description = "Monospace face for code editors, debug logs, and regex matchers.",
    },
    {
        name = "CrimsonText",
        style = "serif",
        uses = { "body" },
        description = "Classic book-weight serif suitable for body text.",
    },
    {
        name = "DrawSteelGlyphs",
        style = "symbol",
        uses = { "glyph" },
        description = "Draw Steel ability-tier and system glyph set.",
    },
    {
        name = "DrawSteelPotencies",
        style = "symbol",
        uses = { "glyph" },
        description = "Draw Steel potency glyph set.",
    },
    {
        name = "Dubai",
        style = "sans",
        uses = { "body", "label" },
        description = "Humanist sans used in settings and character panels.",
    },
    {
        name = "Inter",
        style = "sans",
        uses = { "body", "label", "input" },
        description = "Modern UI sans-serif widely used across character sheets.",
    },
    {
        name = "Newzald",
        style = "serif",
        uses = { "heading", "display", "numeric" },
        description = "Serif with display weight and strong numerals; headings and titles.",
    },
    {
        name = "SellYourSoul",
        style = "display",
        uses = { "decorative", "heading" },
        description = "Stylized display face for dramatic headings and overlays.",
    },
    {
        name = "SupernaturalKnight",
        style = "display",
        uses = { "decorative", "heading" },
        description = "Decorative display face for the initiative bar and emotes.",
    },
    {
        name = "Tengwar",
        style = "symbol",
        uses = { "obfuscated" },
        description = "Fantasy alphabet face for obfuscating in-character chat.",
    },
    {
        name = "Varta",
        style = "sans",
        uses = { "numeric", "label" },
        description = "Clean sans with clear numerals; used in the initiative bar.",
    },
}

-- Case-insensitive lookup index built once at load time.
local FONT_CATALOG_BY_LOWER = {}
for _, entry in ipairs(FONT_CATALOG) do
    FONT_CATALOG_BY_LOWER[string.lower(entry.name)] = entry
end

-- =============================================================================
-- Logging
-- =============================================================================

local function _log(msg)
    print("THEME_ENGINE::", msg)
end

--- Log an unresolved reference once per (domain, name) pair per session.
--- @param domain string "color" | "font" | "theme" | "colorScheme"
--- @param name string The unresolved id or token name
local function _logUnresolved(domain, name)
    local key = domain .. ":" .. tostring(name)
    if _loggedUnresolved[key] then return end
    _loggedUnresolved[key] = true
    _log("unresolved " .. domain .. " reference: " .. tostring(name))
end

-- =============================================================================
-- Resolver helpers
-- =============================================================================

--- Build the effective theme inheritance chain for resolution.
--- Chain order: default theme (if registered), ancestors top-down, effective theme.
--- Guards against cycles and handles missing ids silently.
--- @param themeId string|nil
--- @return table[] chain
local function _buildChain(themeId)
    local chain = {}
    local seen = {}

    local default = _themes[DEFAULT_THEME_ID]
    if default then
        chain[#chain + 1] = default
        seen[DEFAULT_THEME_ID] = true
    end

    if themeId == nil then
        return chain
    end

    local effective = _themes[themeId]
    if not effective then
        if themeId ~= DEFAULT_THEME_ID then
            _logUnresolved("theme", themeId)
        end
        return chain
    end

    -- Walk inherit chain bottom-up, stopping on cycles or missing parents.
    local ancestors = {}
    local current = nil
    if effective.inherit then
        current = _themes[effective.inherit]
        if not current then
            _logUnresolved("theme", effective.inherit)
        end
    end
    while current and not seen[current.id] do
        seen[current.id] = true
        ancestors[#ancestors + 1] = current
        if current.inherit then
            local parent = _themes[current.inherit]
            if not parent then
                _logUnresolved("theme", current.inherit)
            end
            current = parent
        else
            current = nil
        end
    end

    -- Append ancestors top-down.
    for i = #ancestors, 1, -1 do
        chain[#chain + 1] = ancestors[i]
    end

    if not seen[effective.id] then
        chain[#chain + 1] = effective
    end

    return chain
end

--- Resolve a value, substituting @name references based on the active property domain.
--- Recurses into tables (gradient stops, border sub-tables, etc.) and preserves metatables.
--- Never mutates the input.
--- @param value any
--- @param domain string|nil "colors" | "fonts" | "gradients" | nil
--- @param tables table { colors = {...}, fonts = {...}, gradients = {...} }
--- @return any
local function _resolveValue(value, domain, tables)
    if type(value) == "string" then
        if value:sub(1, 1) == "@" then
            local name = value:sub(2)
            if domain == "colors" then
                local v = tables.colors[name]
                if v == nil then
                    _logUnresolved("color", name)
                    return UNRESOLVED_COLOR
                end
                return v
            elseif domain == "fonts" then
                local v = tables.fonts[name]
                if v == nil then
                    _logUnresolved("font", name)
                    return UNRESOLVED_FONT
                end
                return v
            elseif domain == "gradients" then
                local spec = tables.gradients[name]
                if spec == nil then
                    _logUnresolved("gradient", name)
                    return nil
                end
                -- Resolve @name refs inside the spec (stops' color keys, etc.),
                -- then build the framework's Gradient object from the plain table.
                return gui.Gradient(_resolveValue(spec, nil, tables))
            else
                -- Not a themable property; leave the literal in place.
                return value
            end
        end
        return value
    elseif type(value) == "table" then
        local cloned = {}
        for k, v in pairs(value) do
            local nextDomain
            if COLOR_PROPS[k] then
                nextDomain = "colors"
            elseif FONT_PROPS[k] then
                nextDomain = "fonts"
            elseif GRADIENT_PROPS[k] then
                nextDomain = "gradients"
            else
                nextDomain = domain
            end
            cloned[k] = _resolveValue(v, nextDomain, tables)
        end
        local mt = getmetatable(value)
        if mt then setmetatable(cloned, mt) end
        return cloned
    end
    return value
end

--- Walk a raw styles array, cloning each rule and substituting @name references.
--- The `selectors` array is treated as literal — never substituted.
--- @param rawStyles table[]
--- @param tables table { colors, fonts, gradients }
--- @return table[]
local function _buildResolvedStyles(rawStyles, tables)
    local out = {}
    for _, rule in ipairs(rawStyles) do
        local cloned = {}
        for k, v in pairs(rule) do
            if k == "selectors" then
                cloned.selectors = v
            else
                local domain
                if COLOR_PROPS[k] then
                    domain = "colors"
                elseif FONT_PROPS[k] then
                    domain = "fonts"
                elseif GRADIENT_PROPS[k] then
                    domain = "gradients"
                end
                cloned[k] = _resolveValue(v, domain, tables)
            end
        end
        out[#out + 1] = cloned
    end
    return out
end

--- Merge color tables: default scheme first, then effective scheme overrides.
--- @param schemeId string|nil
--- @return table
local function _buildColorTable(schemeId)
    local out = {}

    local default = _colorSchemes[DEFAULT_SCHEME_ID]
    if default and default.colors then
        for k, v in pairs(default.colors) do
            out[k] = v
        end
    end

    if schemeId == nil then
        return out
    end

    local effective = _colorSchemes[schemeId]
    if not effective then
        if schemeId ~= DEFAULT_SCHEME_ID then
            _logUnresolved("colorScheme", schemeId)
        end
        return out
    end

    if effective.colors then
        for k, v in pairs(effective.colors) do
            out[k] = v
        end
    end

    return out
end

--- Merge gradient specs: default scheme first, then effective scheme overrides.
--- Unresolved-scheme logging is handled by `_buildColorTable`; this function stays silent.
--- @param schemeId string|nil
--- @return table
local function _buildGradientTable(schemeId)
    local out = {}

    local default = _colorSchemes[DEFAULT_SCHEME_ID]
    if default and default.gradients then
        for k, v in pairs(default.gradients) do
            out[k] = v
        end
    end

    if schemeId == nil then
        return out
    end

    local effective = _colorSchemes[schemeId]
    if not effective or not effective.gradients then
        return out
    end

    for k, v in pairs(effective.gradients) do
        out[k] = v
    end

    return out
end

--- Merge fonts tables across the theme inheritance chain.
--- @param chain table[]
--- @return table
local function _buildFontsTable(chain)
    local out = {}
    for _, theme in ipairs(chain) do
        if theme.fonts then
            for k, v in pairs(theme.fonts) do
                out[k] = v
            end
        end
    end
    return out
end

--- Resolve explicit arguments + active state into an effective (themeId, schemeId) pair.
--- Explicit overrides bypass the user's active color scheme selection. When nothing
--- is selected at any layer, falls back to the default theme and default color scheme
--- so callers always get a deterministic, renderable pair.
--- @param themeIdArg string|nil
--- @param schemeIdArg string|nil
--- @return string themeId
--- @return string schemeId
local function _resolveEffectivePair(themeIdArg, schemeIdArg)
    local themeId = themeIdArg or _activeThemeId
    local schemeId

    if themeIdArg ~= nil then
        -- Explicit theme override: use theme's colorScheme unless schemeId also given.
        if schemeIdArg ~= nil then
            schemeId = schemeIdArg
        else
            local theme = _themes[themeId]
            schemeId = theme and theme.colorScheme or nil
        end
    else
        -- No theme override: respect user's active scheme, else theme's colorScheme.
        if schemeIdArg ~= nil then
            schemeId = schemeIdArg
        elseif _activeSchemeId ~= nil then
            schemeId = _activeSchemeId
        else
            local theme = themeId and _themes[themeId] or nil
            schemeId = theme and theme.colorScheme or nil
        end
    end

    return themeId or DEFAULT_THEME_ID, schemeId or DEFAULT_SCHEME_ID
end

local function _cacheKey(themeId, schemeId)
    return (themeId or "_") .. "|" .. (schemeId or "_")
end

local function _fireThemeChanged()
    EventUtils.FireGlobalEvent(THEME_CHANGED_EVENT)
end

--- Return true if the given color scheme id is currently referenced by active state:
--- either the user's active override or the active theme's `colorScheme` field.
--- @param id string
--- @return boolean
local function _isColorSchemeInUse(id)
    if id == _activeSchemeId then
        return true
    end
    if _activeThemeId ~= nil then
        local theme = _themes[_activeThemeId]
        if theme and theme.colorScheme == id then
            return true
        end
    end
    return false
end

--- Return true if the given theme id appears anywhere in the active theme's
--- inherit chain (the chain that would be walked for rendering right now).
--- @param id string
--- @return boolean
local function _isThemeInActiveChain(id)
    if _activeThemeId == nil then
        return false
    end
    local seen = {}
    local current = _themes[_activeThemeId]
    while current and not seen[current.id] do
        if current.id == id then
            return true
        end
        seen[current.id] = true
        current = current.inherit and _themes[current.inherit] or nil
    end
    return false
end

--- Shallow-clone a font catalog entry so callers can't mutate the hardcoded data.
--- @param entry table
--- @return table
local function _cloneFontEntry(entry)
    local usesCopy = {}
    for i, u in ipairs(entry.uses) do
        usesCopy[i] = u
    end
    return {
        name        = entry.name,
        displayName = entry.displayName or entry.name,
        style       = entry.style,
        uses        = usesCopy,
        description = entry.description,
    }
end

-- =============================================================================
-- Public API — Registration
-- =============================================================================

--- Register a color scheme. Returns false if the id is already registered; the
--- existing registration is left untouched.
---
--- `gradients` is an optional map of gradient specs keyed by name. Each spec is a
--- plain table (not a `gui.Gradient`); the engine wraps it with `gui.Gradient` at
--- resolve time. Stops inside the spec may use `@name` refs to colors in the same
--- scheme — those resolve during style resolution against the merged color table.
--- @param spec table { id, name, description, colors = { name = hex, ... }, gradients? = { name = spec, ... } }
--- @return boolean registered
function ThemeEngine.RegisterColorScheme(spec)
    if _colorSchemes[spec.id] then
        return false
    end
    _colorSchemes[spec.id] = {
        id = spec.id,
        name = spec.name,
        description = spec.description,
        colors = spec.colors or {},
        gradients = spec.gradients or {},
    }
    return true
end

--- Register a color scheme from a small set of anchor colors.
--- Current implementation: treats anchors as the full color table. Derivation rules
--- will be filled in once the canonical color key set is settled.
--- @param spec table { id, name, description, colors = { <anchors> }, gradients? = { name = spec, ... } }
--- @return boolean registered
function ThemeEngine.RegisterSimpleColorScheme(spec)
    -- TODO: Map the simple colors into the full scheme
    return ThemeEngine.RegisterColorScheme({
        id = spec.id,
        name = spec.name,
        description = spec.description,
        colors = spec.colors,
        gradients = spec.gradients,
    })
end

--- Deregister a color scheme by id. Silent no-op if the id isn't registered.
---
--- Refuses (with a log) to remove:
---   * the default color scheme — it's the ultimate fallback and must remain present;
---   * any scheme currently in use — the user's active override or the scheme
---     referenced by the active theme's `colorScheme` field.
---
--- Because removal can only affect entries that aren't on-screen, nothing visible
--- changes and OnThemeChanged is not fired. The resolved-styles cache is still
--- cleared so a later re-registration of the same id can't return stale content.
--- @param id string
--- @return boolean removed
function ThemeEngine.DeregisterColorScheme(id)
    if id == DEFAULT_SCHEME_ID then
        _log("refused to deregister the default color scheme")
        return false
    end
    if _isColorSchemeInUse(id) then
        _log("refused to deregister color scheme in use: " .. tostring(id))
        return false
    end
    if not _colorSchemes[id] then
        return false
    end
    _colorSchemes[id] = nil
    _cache = {}
    return true
end

--- Register a theme. Returns false if the id is already registered; the existing
--- registration is left untouched.
---
--- Font values in the `fonts` map are validated against the hardcoded font catalog.
--- Unknown names are logged once per unique name but do not prevent registration —
--- this matches the engine's "loud but non-fatal" policy for missing references.
--- @param spec table { id, name, description, inherit?, colorScheme, fonts?, styles }
--- @return boolean registered
function ThemeEngine.RegisterTheme(spec)
    if _themes[spec.id] then
        return false
    end

    if spec.fonts then
        for _, face in pairs(spec.fonts) do
            if type(face) == "string" and not ThemeEngine.IsKnownFontFace(face) then
                _logUnresolved("fontFace", face)
            end
        end
    end

    _themes[spec.id] = {
        id = spec.id,
        name = spec.name,
        description = spec.description,
        inherit = spec.inherit,
        colorScheme = spec.colorScheme,
        fonts = spec.fonts or {},
        styles = spec.styles or {},
    }
    return true
end

--- Deregister a theme by id. Silent no-op if the id isn't registered.
---
--- Refuses (with a log) to remove:
---   * the default theme — it's the ultimate fallback and must remain present;
---   * the active theme or any theme in its inherit chain — removing a link in
---     the chain that's currently rendering would visibly break the UI.
---
--- Because removal can only affect entries that aren't on-screen, nothing visible
--- changes and OnThemeChanged is not fired. The resolved-styles cache is still
--- cleared so a later re-registration of the same id can't return stale content.
--- @param id string
--- @return boolean removed
function ThemeEngine.DeregisterTheme(id)
    if id == DEFAULT_THEME_ID then
        _log("refused to deregister the default theme")
        return false
    end
    if _isThemeInActiveChain(id) then
        _log("refused to deregister theme in active chain: " .. tostring(id))
        return false
    end
    if not _themes[id] then
        return false
    end
    _themes[id] = nil
    _cache = {}
    return true
end

-- =============================================================================
-- Public API — Activation & inspection
-- =============================================================================

--- Set the active theme. Unknown ids are accepted silently; the resolver handles
--- missing-id fallback. Fires OnThemeChanged if the value actually changed.
--- @param themeId string|nil
function ThemeEngine.SetActiveTheme(themeId)
    if _activeThemeId == themeId then return end
    _activeThemeId = themeId
    _fireThemeChanged()
end

--- Set the active color scheme override. Pass nil to clear the override (use the
--- theme's default colorScheme). Fires OnThemeChanged if the value actually changed.
--- @param schemeId string|nil
function ThemeEngine.SetActiveColorScheme(schemeId)
    if _activeSchemeId == schemeId then return end
    _activeSchemeId = schemeId
    _fireThemeChanged()
end

--- @return string|nil
function ThemeEngine.GetActiveTheme()
    return _activeThemeId
end

--- @return string|nil
function ThemeEngine.GetActiveColorScheme()
    return _activeSchemeId
end

--- Register a callback to run whenever the active theme or active color scheme changes.
--- The callback receives no arguments. The returned entry has a `Deregister()` method
--- for explicit unsubscribe; the handler is also automatically removed when the caller's
--- mod unloads.
--- @param callingMod table The caller's mod object, from `dmhub.GetModLoading()`
--- @param callback fun()
--- @return table entry { guid, handlerfn, Deregister }
function ThemeEngine.OnThemeChanged(callingMod, callback)
    return EventUtils.RegisterGlobalEventHandler(callingMod, THEME_CHANGED_EVENT, callback)
end

--- List registered themes for UI pickers.
--- @return table[] themes Array of { id, name, description }
function ThemeEngine.ListThemes()
    local out = {}
    for _, theme in pairs(_themes) do
        out[#out + 1] = {
            id = theme.id,
            name = theme.name,
            description = theme.description,
        }
    end
    return out
end

--- List registered color schemes for UI pickers.
--- @return table[] schemes Array of { id, name, description }
function ThemeEngine.ListColorSchemes()
    local out = {}
    for _, scheme in pairs(_colorSchemes) do
        out[#out + 1] = {
            id = scheme.id,
            name = scheme.name,
            description = scheme.description,
        }
    end
    return out
end

-- =============================================================================
-- Public API — Font catalog (read-only)
-- =============================================================================

--- Check whether a font face is in the hardcoded DMHub catalog. Case-insensitive.
--- @param name string
--- @return boolean
function ThemeEngine.IsKnownFontFace(name)
    if type(name) ~= "string" then return false end
    return FONT_CATALOG_BY_LOWER[string.lower(name)] ~= nil
end

--- List catalog entries, optionally filtered by style and/or use tag.
--- Returns a fresh array of entry copies; mutating the result does not affect the catalog.
--- The catalog itself is kept alphabetical, so results are already sorted by name.
---
--- Filter fields (all optional):
---   style — scalar; match when entry.style == style.
---   use   — scalar; match when use is present in entry.uses.
---   Both, when supplied, apply together (AND).
--- @param filter table|nil { style?, use? }
--- @return table[]
function ThemeEngine.ListFontFaces(filter)
    local wantStyle = filter and filter.style or nil
    local wantUse   = filter and filter.use   or nil

    local out = {}
    for _, entry in ipairs(FONT_CATALOG) do
        local keep = true

        if wantStyle ~= nil and entry.style ~= wantStyle then
            keep = false
        end

        if keep and wantUse ~= nil then
            local found = false
            for _, u in ipairs(entry.uses) do
                if u == wantUse then
                    found = true
                    break
                end
            end
            if not found then keep = false end
        end

        if keep then
            out[#out + 1] = _cloneFontEntry(entry)
        end
    end

    return out
end

-- =============================================================================
-- Public API — Resolution
-- =============================================================================

--- Get the resolved styles array for the current (or overridden) theme/scheme pair.
---
--- With no arguments, uses the active theme and active color scheme (falling back
--- to the theme's declared colorScheme when no user override is set).
---
--- Supplying themeIdOverride switches to deterministic rendering: the user's active
--- color scheme override is ignored, and the scheme comes from that theme's own
--- colorScheme field unless schemeIdOverride is also supplied. This is the
--- intended path for "Reset" buttons that must always render readably.
---
--- Results are memoized per resolved (theme, scheme) pair. Registrations are
--- immutable (duplicate ids are rejected), so cached entries remain valid across
--- SetActive* calls.
--- @param themeIdOverride? string|nil
--- @param schemeIdOverride? string|nil
--- @return table[] styles
function ThemeEngine.GetStyles(themeIdOverride, schemeIdOverride)
    local themeId, schemeId = _resolveEffectivePair(themeIdOverride, schemeIdOverride)

    local key = _cacheKey(themeId, schemeId)
    local cached = _cache[key]
    if cached then return cached end

    local chain = _buildChain(themeId)

    local rawStyles = {}
    for _, theme in ipairs(chain) do
        if theme.styles then
            for _, rule in ipairs(theme.styles) do
                rawStyles[#rawStyles + 1] = rule
            end
        end
    end

    local tables = {
        colors = _buildColorTable(schemeId),
        gradients = _buildGradientTable(schemeId),
        fonts = _buildFontsTable(chain),
    }

    local resolved = _buildResolvedStyles(rawStyles, tables)
    _cache[key] = resolved
    return resolved
end

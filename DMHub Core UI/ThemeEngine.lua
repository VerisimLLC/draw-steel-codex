local mod = dmhub.GetModLoading()

--- ThemeEngine -- UI theming engine for Draw Steel Codex.
--- Registries for color schemes and themes, a resolver with sigil-based
--- substitution, a cache keyed by the resolved (theme, scheme) pair, and an
--- OnThemeChanged event. Default content (default theme, default color scheme)
--- and settings-UI wiring are handled elsewhere; this file is the engine only.
---
--- Color, font, and gradient properties in style rules may reference named
--- values via the `@name` sigil. The engine resolves these at GetStyles() time
--- using property-typed resolution:
---   color / bgcolor / borderColor  -> colors table
---   fontFace                       -> fonts table
---   gradient                       -> gradients table
---
--- Naming conventions used by the registered content (see DefaultStyles.lua):
--- a single rule with no exceptions -- camelCase everywhere.
---   Tokens (color and gradient names): `bg`, `bgAlt`, `accentHover`,
---     `surfaceRadial`, `barTrack`. Referenced as `@bgAlt` etc.
---   Selectors (CSS class names): `enumSlider`, `formRow`, `iconButton`,
---     `multiselectChip`, etc. The engine binary already emits camelCase
---     state classes (`hover`, `press`, `selected`, `expandedTop`, ...)
---     and the gui-wrapper layer (`Gui.lua`) names its emitted classes
---     camelCase too, so picking camelCase as the single convention
---     means zero exceptions to maintain.
---   `parent:*` / `~classname` are selector grammar (parent-state and
---     negation), not class names; they're untouched by the rule.
---
--- Kind-class buttons (icon-only): a small set of registered class names
--- (see `gui.iconButtonClasses` in Gui.lua) make `gui.Button` take the
--- icon-only render path and let `parent:<kind>` rules in the iconButton
--- family supply the bgimage. Use these instead of bespoke constructors:
---   gui.Button{ classes = {"pagingArrow"} }            -- previous arrow
---   gui.Button{ classes = {"pagingArrow", "right"} }   -- next arrow
--- The `pagingArrow` kind class is the canonical replacement for the
--- legacy `gui.PaginButton` helper -- there is no `gui.PaginButton`; route
--- paging chevrons through `gui.Button` + the `pagingArrow` class so the
--- chrome, hit-target, hover/press cascade, and bgimage all come from the
--- iconButton theme rules in DefaultStyles.lua.
--- @class ThemeEngine
ThemeEngine = {} --RegisterGameType("ThemeEngine")

-- =============================================================================
-- Private state
-- =============================================================================

local _colorSchemes = {}         -- schemeId -> stored color-scheme spec
local _themes = {}               -- themeId -> stored theme spec

local _activeThemeId = nil
local _activeSchemeId = nil

-- Persistent storage for the user's active theme and color scheme
-- selections. No section/editor/description, so they don't appear in
-- the settings UI. storage = "preference" -- per-user, persists across
-- games on this machine.
local _activeThemeSetting = setting{
    id = "themeengine.activetheme",
    storage = "preference",
    default = "default",
}
local _activeSchemeSetting = setting{
    id = "themeengine.activecolorscheme",
    storage = "preference",
    default = "default",
}

-- User-created color schemes are persisted (as a JSON array) on the user's
-- account, so they follow the user across machines, separate from the built-in
-- schemes registered by DefaultStyles.lua. The account object (and thus this
-- setting) loads as a unit before the codex mod runs, so LoadUserColorSchemes()
-- at load time sees them. The creator UI is only reachable when logged in, so
-- there is always an account to read from / write to.
local _userSchemesSetting = setting{
    id = "themeengine.userschemes",
    storage = "account",
    default = "[]",
}

-- Reserved scheme id used by the theme-creator UI for its live preview while
-- the user is still editing (before they save).
local PREVIEW_SCHEME_ID = "__usercreate_preview__"

local _cache = {}                -- "themeId|schemeId" -> resolved styles array
local _loggedUnresolved = {}     -- set of "domain:name" keys already logged

-- =============================================================================
-- Constants
-- =============================================================================

local COLOR_PROPS = {
    color = true,
    bgcolor = true,
    borderColor = true,
    scrollHandleColor = true
}
local FONT_PROPS = { fontFace = true }
local GRADIENT_PROPS = { gradient = true }

local UNRESOLVED_COLOR = "#FF00FF"  -- magenta, loud in UI
local UNRESOLVED_FONT = "Berling"     -- known safe fallback

local DEFAULT_THEME_ID = "default"
local DEFAULT_SCHEME_ID = "default"

local THEME_CHANGED_EVENT = "ThemeEngine.ThemeChanged"

-- =============================================================================
-- Available fonts (engine-supplied)
-- =============================================================================

-- Lazy-built case-insensitive set of font names from gui.availableFonts.
-- Built on first access so we don't depend on engine load order at module init.
local _availableFontsLower = nil

local function _buildAvailableFontsSet()
    local set = {}
    local list = gui.availableFonts
    if type(list) == "table" then
        for _, name in ipairs(list) do
            if type(name) == "string" then
                set[string.lower(name)] = true
            end
        end
    end
    return set
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

--- Validate a font name against gui.availableFonts. Case-insensitive.
--- Unknown names log once and return UNRESOLVED_FONT (Berling).
--- Non-strings pass through unchanged.
--- @param name any
--- @return any
local function _validateFontFace(name)
    if type(name) ~= "string" then return name end
    if _availableFontsLower == nil then
        _availableFontsLower = _buildAvailableFontsSet()
    end
    if _availableFontsLower[string.lower(name)] then
        return name
    end
    _logUnresolved("fontFace", name)
    return UNRESOLVED_FONT
end

--- Coerce a theme id to a registered one. Nil and unknown ids both
--- become DEFAULT_THEME_ID. Unknown ids are logged once.
--- @param id string|nil
--- @return string
local function _normalizeThemeId(id)
    if id == nil then return DEFAULT_THEME_ID end
    if _themes[id] then return id end
    if id ~= DEFAULT_THEME_ID then
        _logUnresolved("theme", id)
    end
    return DEFAULT_THEME_ID
end

--- Coerce a color scheme id to a registered one. Nil and unknown ids
--- both become DEFAULT_SCHEME_ID. Unknown ids are logged once.
--- @param id string|nil
--- @return string
local function _normalizeSchemeId(id)
    if id == nil then return DEFAULT_SCHEME_ID end
    if _colorSchemes[id] then return id end
    if id ~= DEFAULT_SCHEME_ID then
        _logUnresolved("colorScheme", id)
    end
    return DEFAULT_SCHEME_ID
end

-- =============================================================================
-- Resolver helpers
-- =============================================================================

--- Build the effective theme chain for resolution.
--- Every non-default theme inherits only from default, so the chain is
--- at most two entries: [default] (if effective IS default or no
--- effective was given) or [default, effective] otherwise.
--- @param themeId string|nil
--- @return table[] chain
local function _buildChain(themeId)
    local chain = {}

    local default = _themes[DEFAULT_THEME_ID]
    if default then
        chain[#chain + 1] = default
    end

    if themeId == nil or themeId == DEFAULT_THEME_ID then
        return chain
    end

    local effective = _themes[themeId]
    if not effective then
        _logUnresolved("theme", themeId)
        return chain
    end

    chain[#chain + 1] = effective
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
                return _validateFontFace(v)
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
        if domain == "fonts" then
            return _validateFontFace(value)
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
--- The `selectors` array is treated as literal -- never substituted.
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

--- Merge fonts tables: default theme's fonts first, then effective theme's
--- fonts overlaid on top. The chain passed in is always [default, effective]
--- (or just [default] if effective IS default).
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

    return _normalizeThemeId(themeId), _normalizeSchemeId(schemeId)
end

local function _cacheKey(themeId, schemeId)
    return (themeId or "_") .. "|" .. (schemeId or "_")
end

local function _fireThemeChanged()
    local eu = rawget(_G, "EventUtils")
    if eu then
        eu.FireGlobalEvent(THEME_CHANGED_EVENT)
    end
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

--- Return true if the given theme id is the currently-active theme.
--- (After flattening, the "active chain" is just [default, active]; the
--- default theme is handled separately in DeregisterTheme.)
--- @param id string
--- @return boolean
local function _isThemeInActiveChain(id)
    return _activeThemeId ~= nil and id == _activeThemeId
end

-- =============================================================================
-- Public API -- Registration
-- =============================================================================

--- Register a color scheme. Returns false if the id is already registered; the
--- existing registration is left untouched.
---
--- `gradients` is an optional map of gradient specs keyed by name. Each spec is a
--- plain table (not a `gui.Gradient`); the engine wraps it with `gui.Gradient` at
--- resolve time. Stops inside the spec may use `@name` refs to colors in the same
--- scheme -- those resolve during style resolution against the merged color table.
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
---   * the default color scheme -- it's the ultimate fallback and must remain present;
---   * any scheme currently in use -- the user's active override or the scheme
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
--- Every non-default theme inherits implicitly from the default theme. There is
--- no `inherit` chain -- the resolution chain is always [default, effective].
---
--- Font values in the `fonts` map are validated against the hardcoded font catalog.
--- Unknown names are logged once per unique name but do not prevent registration --
--- this matches the engine's "loud but non-fatal" policy for missing references.
--- @param spec table { id, name, description, colorScheme, fonts?, styles }
--- @return boolean registered
function ThemeEngine.RegisterTheme(spec)
    if _themes[spec.id] then
        return false
    end

    _themes[spec.id] = {
        id = spec.id,
        name = spec.name,
        description = spec.description,
        colorScheme = spec.colorScheme,
        fonts = spec.fonts or {},
        styles = spec.styles or {},
    }
    return true
end

--- Deregister a theme by id. Silent no-op if the id isn't registered.
---
--- Refuses (with a log) to remove:
---   * the default theme -- it's the ultimate fallback and must remain present;
---   * the currently active theme -- removing it while it's rendering would
---     visibly break the UI.
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
-- Public API -- Activation & inspection
-- =============================================================================

--- Set the active theme. Stores the id as given without validation; resolution
--- happens at read time (GetActiveTheme / GetStyles fall back to default for
--- unknown or nil ids). Fires OnThemeChanged if the stored value actually changed.
--- @param themeId string|nil
function ThemeEngine.SetActiveTheme(themeId)
    if _activeThemeId == themeId then return end
    _activeThemeId = themeId
    _activeThemeSetting:Set(themeId or "default")
    _fireThemeChanged()
end

--- Set the active color scheme. Stores the id as given without validation;
--- resolution happens at read time (GetActiveColorScheme / GetStyles fall back
--- to default for unknown or nil ids). Fires OnThemeChanged if the stored value
--- actually changed.
--- @param schemeId string|nil
function ThemeEngine.SetActiveColorScheme(schemeId)
    if _activeSchemeId == schemeId then return end
    _activeSchemeId = schemeId
    _activeSchemeSetting:Set(schemeId or "default")
    _fireThemeChanged()
end

--- Returns the active theme id, guaranteed to be a registered id.
--- @return string
function ThemeEngine.GetActiveTheme()
    return _normalizeThemeId(_activeThemeId)
end

--- Returns the active color scheme id, guaranteed to be a registered id.
--- @return string
function ThemeEngine.GetActiveColorScheme()
    return _normalizeSchemeId(_activeSchemeId)
end

--- Restore the persisted active theme / scheme ids verbatim. Unknown ids are
--- preserved here -- the read path coerces them to default at resolution time,
--- which means the user's stored preference survives even when the registering
--- mod isn't loaded yet (or at all in the current session).
function ThemeEngine.RestoreActiveSelection()
    _activeThemeId = _activeThemeSetting:Get()
    _activeSchemeId = _activeSchemeSetting:Get()
    _fireThemeChanged()
end

-- =============================================================================
-- Public API -- User-created color schemes (persisted per-user)
-- =============================================================================

-- The color tokens the theme-creator UI exposes for editing. Status colors
-- (success / info / warning / danger) and implStatus* are intentionally left
-- out so they stay semantically consistent across schemes.
ThemeEngine.userColorKeys = {
    "bg", "bgAlt", "bgInverse",
    "fg", "fgStrong", "fgMuted", "fgInverse",
    "border", "borderInverse",
    "accent", "accentHover",
    "disabled",
}

-- Hard cap on how many custom color schemes a user may create. Enforced as a
-- backstop in SaveUserColorScheme and gated in the creator UI (the "Create
-- New..." entry is hidden once the user is at the cap).
ThemeEngine.maxUserColorSchemes = 6

-- Upsert a user color scheme directly into the registry, bypassing the
-- duplicate-id guard and the in-use deregister refusal so an existing custom
-- scheme can be edited in place. Clears the resolved-styles cache.
local function _upsertUserDef(def)
    _colorSchemes[def.id] = {
        id = def.id,
        name = def.name,
        description = def.description or "Custom color scheme.",
        colors = def.colors or {},
        gradients = {},
    }
    _cache = {}
end

--- Returns the array of persisted user color-scheme defs ({id, name, colors}).
--- Guarded against missing / malformed stored data.
--- @return table[]
function ThemeEngine.GetUserColorSchemes()
    local raw = _userSchemesSetting:Get()
    if type(raw) ~= "string" or raw == "" then
        return {}
    end
    local parsed = dmhub.FromJson(raw)
    if not parsed.success or type(parsed.result) ~= "table" then
        return {}
    end
    return parsed.result
end

--- True if id names a user-created (deletable) scheme, as opposed to a built-in.
--- @param id string
--- @return boolean
function ThemeEngine.IsUserColorScheme(id)
    for _, d in ipairs(ThemeEngine.GetUserColorSchemes()) do
        if d.id == id then
            return true
        end
    end
    return false
end

--- Returns the fully-resolved color table for a scheme (the merged
--- [default, scheme] colors). Used to seed a new custom theme from the
--- currently-chosen palette. Unknown / nil ids resolve to the default palette.
--- @param schemeId string|nil
--- @return table map of token -> hex
function ThemeEngine.GetColorSchemeColors(schemeId)
    return _buildColorTable(schemeId)
end

--- Persist and (re-)register a user color scheme. If a def with the same id
--- already exists it is overwritten (edit in place, always allowed). Adding a
--- NEW scheme beyond ThemeEngine.maxUserColorSchemes is refused. Fires the
--- theme-changed event so any open UI reflects the new colors immediately.
--- @param def table { id, name, description?, colors }
--- @return boolean saved -- false if the per-user cap was hit (new schemes only)
function ThemeEngine.SaveUserColorScheme(def)
    local list = ThemeEngine.GetUserColorSchemes()
    local replaced = false
    for i, d in ipairs(list) do
        if d.id == def.id then
            list[i] = def
            replaced = true
            break
        end
    end
    if not replaced then
        if #list >= ThemeEngine.maxUserColorSchemes then
            -- At the cap; refuse to add a new scheme. Editing an existing one
            -- (the replaced branch above) is always allowed.
            return false
        end
        list[#list + 1] = def
    end
    _userSchemesSetting:Set(dmhub.ToJson(list))
    _upsertUserDef(def)
    _fireThemeChanged()
    return true
end

--- Remove a user color scheme. If it was the active scheme, the active
--- selection falls back to default. No-op for the default scheme.
--- @param id string
function ThemeEngine.DeleteUserColorScheme(id)
    if id == DEFAULT_SCHEME_ID then
        return
    end
    local list = ThemeEngine.GetUserColorSchemes()
    local out = {}
    for _, d in ipairs(list) do
        if d.id ~= id then
            out[#out + 1] = d
        end
    end
    _userSchemesSetting:Set(dmhub.ToJson(out))

    _colorSchemes[id] = nil
    _cache = {}

    if _activeSchemeId == id then
        ThemeEngine.SetActiveColorScheme(DEFAULT_SCHEME_ID)
    end
    _fireThemeChanged()
end

--- Register every persisted user color scheme. Called once at load (from
--- DefaultStyles.lua) before RestoreActiveSelection so a saved active scheme
--- pick resolves to the real scheme rather than falling back to default.
function ThemeEngine.LoadUserColorSchemes()
    for _, def in ipairs(ThemeEngine.GetUserColorSchemes()) do
        if type(def) == "table" and type(def.id) == "string" then
            _upsertUserDef(def)
        end
    end
end

-- =============================================================================
-- Public API -- Live preview scheme (used by the theme-creator UI)
-- =============================================================================

--- Register / update a transient color scheme used only for previewing
--- in-progress edits. Returns its reserved id so the caller can pass it to
--- GetStyles(themeId, schemeId). Clears the cache so the preview re-resolves.
--- @param colors table map of token -> hex
--- @return string previewSchemeId
function ThemeEngine.SetPreviewColorScheme(colors)
    _colorSchemes[PREVIEW_SCHEME_ID] = {
        id = PREVIEW_SCHEME_ID,
        name = "Preview",
        description = "Transient preview scheme.",
        colors = colors or {},
        gradients = {},
    }
    _cache = {}
    return PREVIEW_SCHEME_ID
end

--- Remove the transient preview scheme. Safe to call when none exists.
function ThemeEngine.ClearPreviewColorScheme()
    if _colorSchemes[PREVIEW_SCHEME_ID] ~= nil then
        _colorSchemes[PREVIEW_SCHEME_ID] = nil
        _cache = {}
    end
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

-- Ids beginning with "__" are reserved for internal / transient registrations
-- (e.g. the creator's live-preview scheme) and must never surface in UI pickers.
local function _isInternalId(id)
    return type(id) == "string" and string.sub(id, 1, 2) == "__"
end

--- List registered themes for UI pickers. Internal "__"-prefixed ids are skipped.
--- @return table[] themes Array of { id, name, description }
function ThemeEngine.ListThemes()
    local out = {}
    for _, theme in pairs(_themes) do
        if not _isInternalId(theme.id) then
            out[#out + 1] = {
                id = theme.id,
                name = theme.name,
                description = theme.description,
            }
        end
    end
    return out
end

--- List registered color schemes for UI pickers. Internal "__"-prefixed ids are skipped.
--- @return table[] schemes Array of { id, name, description }
function ThemeEngine.ListColorSchemes()
    local out = {}
    for _, scheme in pairs(_colorSchemes) do
        if not _isInternalId(scheme.id) then
            out[#out + 1] = {
                id = scheme.id,
                name = scheme.name,
                description = scheme.description,
            }
        end
    end
    return out
end

-- =============================================================================
-- Public API -- Resolution
-- =============================================================================

local _getStylesHits = 0
local _getStylesMisses = 0
local _getStylesReportEvery = 50

-- MergeStyles measurement (identity-only). Each call's customStyles table
-- address is the hash key. Tells us whether callers reuse styles tables
-- (cacheable cheaply by identity) vs. rebuild them every call (caching by
-- identity is moot; would need content hashing or caller refactoring).
local _mergeStylesCalls = 0
local _mergeStylesHashCounts = {}
local _mergeStylesHashIds = {}
local _mergeStylesNextId = 1

local function _reportGetStylesCache()
    local total = _getStylesHits + _getStylesMisses
    if total > 0 and total % _getStylesReportEvery == 0 then
        print(string.format(
            "THC:: GETSTYLECACHE:: total=%d hits=%d misses=%d (hit rate %.1f%%)",
            total, _getStylesHits, _getStylesMisses,
            100 * _getStylesHits / total
        ))
    end
end

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
    if cached then
        _getStylesHits = _getStylesHits + 1
        _reportGetStylesCache()
        return cached
    end

    _getStylesMisses = _getStylesMisses + 1
    _reportGetStylesCache()

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

--- Merge a caller-supplied styles array on top of the active theme's resolved styles.
---
--- The custom rules are run through the same @name resolver the engine uses for
--- registered theme rules, so they can reference @fg / @success / @accentHover /
--- @surfaceRadial / etc. and follow scheme switches when the caller re-invokes
--- MergeStyles after an OnThemeChanged event.
---
--- The base (theme) styles come first, custom rules are appended last, so on
--- equal-specificity selector matches the custom rule wins. For finer control,
--- callers can still set `priority = N` on individual custom rules.
---
--- The base styles array is the same memoized array returned by GetStyles().
--- The custom resolution is recomputed each call (uncached) -- typical custom
--- arrays are small and the @name resolver is cheap.
---
--- Always uses the active theme/scheme pair; no overrides. Callers needing
--- override semantics can compose manually via GetStyles(theme, scheme) plus
--- their own resolution loop, but no caller has needed that yet.
--- @param customStyles table[]|nil Array of rule tables (selectors + properties).
--- @return table[] styles
function ThemeEngine.MergeStyles(customStyles)
    local base = ThemeEngine.GetStyles()
    if customStyles == nil or #customStyles == 0 then
        return base
    end

    _mergeStylesCalls = _mergeStylesCalls + 1
    -- Identity key. Using the table reference directly avoids a tostring()
    -- call that would otherwise hit any __tostring metamethod the engine
    -- installs on style tables (which serializes the whole structure).
    _mergeStylesHashCounts[customStyles] = (_mergeStylesHashCounts[customStyles] or 0) + 1
    if _mergeStylesHashIds[customStyles] == nil then
        _mergeStylesHashIds[customStyles] = _mergeStylesNextId
        _mergeStylesNextId = _mergeStylesNextId + 1
    end

    local themeId, schemeId = _resolveEffectivePair(nil, nil)
    local chain = _buildChain(themeId)
    local tables = {
        colors = _buildColorTable(schemeId),
        gradients = _buildGradientTable(schemeId),
        fonts = _buildFontsTable(chain),
    }

    local resolvedCustom = _buildResolvedStyles(customStyles, tables)

    local merged = {}
    for _, r in ipairs(base) do
        merged[#merged + 1] = r
    end
    for _, r in ipairs(resolvedCustom) do
        merged[#merged + 1] = r
    end
    return merged
end

--- Resolve `@`-token references in a caller-supplied styles array against the
--- active scheme, without bundling the base theme. Use this when a panel just
--- needs its own local rules to follow the active scheme, and the panel sits
--- downstream of an ancestor that already owns the full theme cascade via
--- `ThemeEngine.MergeStyles`.
---
--- Difference vs. MergeStyles:
---   * MergeStyles   -> base theme + resolved custom (for cascade roots)
---   * MergeTokens -> resolved custom only (for downstream extras)
---
--- Callers that need scheme switches to recolor live should subscribe to
--- OnThemeChanged and reassign their panel.styles after re-resolving.
--- @param customStyles table[]|nil Array of rule tables (selectors + properties).
--- @return table[]|nil resolved
function ThemeEngine.MergeTokens(customStyles)
    if customStyles == nil or #customStyles == 0 then
        return customStyles
    end

    local themeId, schemeId = _resolveEffectivePair(nil, nil)
    local chain = _buildChain(themeId)
    local tables = {
        colors = _buildColorTable(schemeId),
        gradients = _buildGradientTable(schemeId),
        fonts = _buildFontsTable(chain),
    }

    return _buildResolvedStyles(customStyles, tables)
end

--- Resolve `@tokenName` color references embedded in an arbitrary string
--- against the active scheme. Useful for TextMeshPro markup like
--- `"<color=@danger>warning</color>"` where the property-level resolver
--- doesn't reach (it only walks rule tables, not strings inside text).
---
--- Each `@<name>` is replaced with the active scheme's resolved hex for that
--- color token. Unknown tokens log a warning and substitute UNRESOLVED_COLOR.
--- Non-string inputs pass through unchanged.
---
--- Only color tokens are substituted. Fonts and gradients aren't useful in
--- text markup, so they're not handled here.
--- @param text string|any The string to resolve. Non-strings return unchanged.
--- @return string|any resolved
function ThemeEngine.ResolveTokens(text)
    if type(text) ~= "string" then
        return text
    end
    local _, schemeId = _resolveEffectivePair(nil, nil)
    local colors = _buildColorTable(schemeId)
    return (string.gsub(text, "@([%a][%w]*)", function(name)
        local v = colors[name]
        if v == nil then
            _logUnresolved("color", name)
            return UNRESOLVED_COLOR
        end
        return v
    end))
end

-- =============================================================================
-- Theme safety enforcement
-- Hidden preference (no name / description / editor, so it does not show up in
-- the settings dialog). Toggle from chat with `/safetheme true|false`; the
-- macro with no argument prints the current value. Default: true.
-- =============================================================================

local _enforceSafetySetting = setting{
    id = "themeengine.enforcesafety",
    storage = "preference",
    default = false,
}

--- Returns true if theme safety enforcement is currently on.
--- @return boolean
function ThemeEngine.ForceSafety()
    return _enforceSafetySetting:Get()
end

if devmode() then
    Commands.RegisterMacro{
        name = "themecache",
        summary = "dump GetStyles + MergeStyles measurement counters",
        doc = "Usage: /themecache\nPrints GetStyles cache hit/miss counters plus MergeStyles call distribution by customStyles table identity (top 5). Devmode only.",
        command = function(str)
            local total = _getStylesHits + _getStylesMisses
            local rate = total > 0 and (100 * _getStylesHits / total) or 0
            print(string.format(
                "THC:: GETSTYLECACHE:: total=%d hits=%d misses=%d (hit rate %.1f%%)",
                total, _getStylesHits, _getStylesMisses, rate
            ))

            local uniqueHashes = 0
            local entries = {}
            for hash, count in pairs(_mergeStylesHashCounts) do
                uniqueHashes = uniqueHashes + 1
                entries[#entries + 1] = { hash = hash, count = count }
            end
            table.sort(entries, function(a, b) return a.count > b.count end)

            local repeatRate = _mergeStylesCalls > 0
                and (100 * (_mergeStylesCalls - uniqueHashes) / _mergeStylesCalls) or 0
            print(string.format(
                "THC:: MERGESTYLES:: total=%d unique=%d (repeat rate %.1f%%)",
                _mergeStylesCalls, uniqueHashes, repeatRate
            ))

            local topN = math.min(5, #entries)
            for i = 1, topN do
                print(string.format(
                    "THC:: MERGESTYLES:: top %d count=%d id=#%d",
                    i, entries[i].count, _mergeStylesHashIds[entries[i].hash] or -1
                ))
            end
        end,
    }
end

Commands.RegisterMacro{
    name = "safetheme",
    summary = "toggle theme safety enforcement",
    doc = "Usage: /safetheme [true|false]\nWith no argument, prints the current value. With true or false, sets it.",
    command = function(str)
        local arg = (str or ""):match("^%s*(%S+)%s*$")
        if arg == nil then
            SendTitledChatMessage(tostring(_enforceSafetySetting:Get()), "safetheme", "#ccccff", dmhub.userid)
            return
        end
        local lower = arg:lower()
        if lower == "true" then
            _enforceSafetySetting:Set(true)
            SendTitledChatMessage("true", "safetheme", "#ccccff", dmhub.userid)
        elseif lower == "false" then
            _enforceSafetySetting:Set(false)
            SendTitledChatMessage("false", "safetheme", "#ccccff", dmhub.userid)
        else
            SendTitledChatMessage(string.format("unknown value '%s' (expected true or false). Current: %s", arg, tostring(_enforceSafetySetting:Get())), "safetheme", "#cc4444", dmhub.userid)
        end
    end,
}

# Creating a Theme and Color Scheme

A reference for building your **own** color scheme and theme for the Draw Steel
Codex Theme Engine: the exact keywords each one accepts, and a description of
where and how the engine uses them.

> **Status.** The Theme Engine is still stabilizing. The keyword set below is
> the current contract, but it can still change and a change may break custom
> content. Treat this as "here is how it works today," not "this is frozen."
> When you need ground truth, the canonical registrations live in
> `DMHub Core UI/DefaultStyles.lua` -- reading that file shows you exactly how
> the built-in scheme and theme are built.

---

## 1. The mental model: two separate things

| | Color Scheme | Theme |
|---|---|---|
| Answers | "what are the colors?" | "what do widgets look like?" |
| Holds | named colors + named gradients | named fonts + style rules (selectors -> properties) |
| Registered with | `ThemeEngine.RegisterColorScheme{...}` | `ThemeEngine.RegisterTheme{...}` |
| References the other? | no | yes -- a theme names a default `colorScheme`, and its style rules pull colors via `@name` |

A theme is the *shape* of the UI (sizes, borders, fonts, which selector gets
what). A color scheme is the *palette* plugged into it. They are chosen
independently by the user, so a theme must never hardcode a hex value -- it
refers to color-scheme entries by name (`@accent`, `@bg`, ...).

**Everything inherits from `default`.** Every non-default scheme and theme is
resolved as `[default, yours]`: any color, gradient, font, or selector you do
not define falls back to the default one. You only specify what differs.

---

## 2. Color Scheme

```lua
ThemeEngine.RegisterColorScheme{
    id          = "my-scheme",          -- unique string id (stored in user prefs)
    name        = "My Scheme",          -- display name in the picker
    description = "Short summary.",
    colors      = { ... },              -- see keyword table below
    gradients   = { ... },              -- optional; see below
}
```

Returns `false` (and changes nothing) if the `id` is already registered.

### 2.1 Color keywords

Every key is optional -- omit one and the default scheme's value is used. Values
are hex strings (`"#RRGGBB"` or `"#RRGGBBAA"`). The defaults below are the
built-in `default` scheme.

| Key | Default | Where / how it is used |
|---|---|---|
| `bg` | `#080B09` | Primary canvas. Default fill for panels, inputs, dropdowns, button rests, dock frames. The "back wall." |
| `bgAlt` | `#191A18` | Secondary surface to set a region apart without a border: card bodies, odd-row striping, selected dock tab, closed dropdown. |
| `bgInverse` | `#9C9C9C` | Inverted surface: hover/selected fill on text buttons, dropdown options, modal dialogs. Pair with `fgInverse`. |
| `fg` | `#CECECE` | Default text/glyph color: body labels, button text at rest, dropdown text, icon-button tint. |
| `fgStrong` | `#EFEFEF` | Escalated text: headings, form-row labels, modal titles. Default `label` color. |
| `fgMuted` | `#9F9F9B` | De-emphasized text: disabled labels, non-selected tab text, placeholder-feel content. |
| `fgPending` | `#999999` | Provisional / not-yet-committed values (the `{label, pending}` variant). |
| `fgInverse` | `#040404` | Text on `bgInverse` surfaces. Always paired with `bgInverse`. |
| `border` | `#DFDFDF` | Default frame: input/button borders at rest, card frames, dialog frames, table separators. |
| `borderInverse` | `#666666` | Frame for inverse-state surfaces (button hover frame, faded inputs). |
| `accent` | `#999999` | The "click me" color: links, tooltip indicators, drag-target highlight. Not the generic button hover. |
| `accentHover` | `#DDDDDD` | Hover variant of `accent`. Pair with `accent` in hover rules. |
| `success` | `#6BA84F` | Healthy / good / completed (also healthy stamina). |
| `info` | `#E9C868` | Neutral information / row highlight / drag-ghost rest. |
| `warning` | `#E08A2E` | Caution / winded / not-yet-critical. |
| `danger` | `#C73131` | Destructive / dying / bad. Delete-button hover, remove indicators. |
| `disabled` | `#343434` | Disabled control fill. |
| `implStatus0`..`implStatus4` | magenta/red/bronze/silver/gold | Ability/feature implementation indicators. |

**Conventions worth following:** keep `success` / `info` / `warning` / `danger`
visually consistent across schemes -- callers rely on them for signal. Leave
`implStatus0..4` alone unless one is unreadable on your surfaces; users expect
those to mean the same thing everywhere.

### 2.2 Gradient keywords

`gradients` is an optional map. Each value is a plain spec table (not a
`gui.Gradient`); the engine wraps it at resolve time. Stop colors may use
`@name` references to colors **in the merged scheme**.

```lua
gradients = {
    surfaceLinear = {
        point_a = {x = 0, y = 0},
        point_b = {x = 1, y = 1},
        stops = {
            {position = 0, color = "#3A2B1E"},
            {position = 1, color = "@bg"},     -- @name refs allowed in stops
        },
    },
}
```

| Key | Where / how it is used |
|---|---|
| `surfaceLinear` | Diagonal sheen (top-left light -> bottom-right dark). Dialogs, framed surfaces, context menus, tab containers. |
| `surfaceRadial` | Center-bright vignette. Large content / hero surfaces. Add `type = "radial"`. |
| `barTrack` | Left-to-right horizontal track. **Used in the application title bar** -- change with care. |
| `maskHorizontal` / `maskVertical` | Alpha-fade utilities (transparent edges, opaque middle) for soft-fading list/scroll edges. |

Spec fields: `point_a` / `point_b` (`{x,y}` direction), `stops`
(`{position, color}` array), and `type = "radial"` for radial gradients
(linear is the default when `type` is omitted).

---

## 3. Theme

```lua
ThemeEngine.RegisterTheme{
    id          = "my-theme",
    name        = "My Theme",
    description = "Short summary.",
    colorScheme = "my-scheme",   -- the scheme this theme defaults to pairing with
    fonts       = { ... },       -- see keyword table below
    styles      = { ... },       -- array of selector rules; see section 4
}
```

Returns `false` (and changes nothing) if the `id` is already registered.
`colorScheme` is only the *default* pairing -- the user can override the active
scheme independently in settings.

### 3.1 Font keywords

Each value must be a font face name the engine knows about (it is validated;
an unknown name is logged once and falls back to `Berling`). Omit a key to
inherit the default theme's font.

| Key | Default | Where / how it is used |
|---|---|---|
| `heading` | `Berling` | Heading-weight text. |
| `label` | `Berling` | Default label/body font (most text). |
| `input` | `LiberationSans` | Text entered into inputs. |
| `number` | `Newzald` | Numeric displays (the `{label, number}` variant). |
| `mono` | `Courier` | Fixed-width: code/script/formula display (`{monospace}`). |

Fonts are referenced from style rules as `fontFace = "@label"` etc. (see next
section).

### 3.2 Style rules

`styles` is an array of rule tables. Each rule has a `selectors` array
(literal class / primitive names -- never substituted) plus the visual
properties to apply when an element matches all of those selectors:

```lua
styles = {
    {
        selectors = {"label"},
        fontFace  = "@label",
        fontSize  = 14,
        color     = "@fgStrong",
    },
    {
        selectors = {"label", "number"},
        fontFace  = "@number",
    },
}
```

You do **not** need to redefine the whole vocabulary. Because resolution is
`[default, yours]`, a rule you supply with the same `selectors` overrides the
default rule for those selectors; everything you omit keeps working. The
practical way to author a theme is: start empty, add only the selector rules
you want to look different (see `default-rounded` in `DefaultStyles.lua`, which
overrides nothing but `cornerRadius`).

**The selector vocabulary itself** -- every class name (`panel`, `label`,
`button`, `formRow`, `dialog`, `framedPanel`, `tab`, the size classes, the
state classes, ...) -- is large and is not duplicated here. Two sources:

- `draw-steel-codex/DefaultStyles.md` -- prescriptive guide: which selector and
  which color token to reach for, organized by widget family.
- `DMHub Core UI/DefaultStyles.lua` -- the actual rules. Read this when you
  want to see exactly how a given widget is built so you can override it
  faithfully. It is sectioned: `1. BASICS`, `2. FORMS`, `3. CARDS`,
  `4. DIALOGS`, `5. UTILITIES`, plus dock and drag-and-drop sections.

---

## 4. Referencing scheme values from a theme (the `@name` sigil)

Inside a style rule, a string starting with `@` is a reference resolved against
the active scheme. **Which table it resolves against is decided by the property
name**, not by you:

| Property | Resolves against | Example |
|---|---|---|
| `color`, `bgcolor`, `borderColor`, `scrollHandleColor` | scheme **colors** | `color = "@fgStrong"` |
| `fontFace` | theme **fonts** | `fontFace = "@mono"` |
| `gradient` | scheme **gradients** | `gradient = "@surfaceLinear"` |
| anything else | not themable | the literal value is kept as-is |

Rules:

- `@name` only resolves in the property domains above. Writing `@bg` on a
  non-color property ships the literal string `"@bg"`.
- An unresolved color reference renders **magenta `#FF00FF`** and logs a
  warning once; an unresolved font falls back to `Berling`. If you see
  magenta, the token name is wrong or undefined in the active scheme.
- `selectors` are never substituted -- they are literal match names.
- Gradient stop colors *are* resolved, so a gradient spec can pull scheme
  colors via `@name`.

Hex values are still allowed where a value is intentionally
scheme-independent (e.g. `"white"` for image-tint-neutral surfaces, `"clear"`
for transparent), but a theme should otherwise always go through `@name`.

---

## 5. Activating and inspecting

| Call | Purpose |
|---|---|
| `ThemeEngine.SetActiveTheme(id)` | Make a theme active. Persists to user prefs, fires the change event. |
| `ThemeEngine.SetActiveColorScheme(id)` | Make a scheme active (independent of theme). |
| `ThemeEngine.GetActiveTheme()` / `GetActiveColorScheme()` | Current ids, normalized to a registered id (falls back to `default`). |
| `ThemeEngine.ListThemes()` / `ListColorSchemes()` | `{id, name, description}` arrays for building pickers. |
| `ThemeEngine.OnThemeChanged(mod, fn)` | Subscribe to theme/scheme changes (auto-removed on mod unload). |
| `ThemeEngine.DeregisterTheme(id)` / `DeregisterColorScheme(id)` | Remove a registration. Refused for `default` or anything currently in use. |

Ids are stored in user preferences verbatim, so a user's choice survives even
across sessions where the registering mod has not loaded yet -- it simply
falls back to `default` until your registration runs again.

---

## 6. Minimal worked example

A scheme that only re-tints surfaces and accent, and a theme that only changes
one selector -- everything else inherits from `default`:

```lua
ThemeEngine.RegisterColorScheme{
    id          = "midnight",
    name        = "Midnight",
    description = "Cool dark blues.",
    colors = {
        bg          = "#0A0E14",
        bgAlt       = "#141A24",
        accent      = "#5AA0E0",
        accentHover = "#9CCBF2",
        -- fg, border, status, etc. all inherit from default
    },
}

ThemeEngine.RegisterTheme{
    id          = "midnight",
    name        = "Midnight",
    description = "Midnight theme.",
    colorScheme = "midnight",
    styles = {
        {
            selectors = {"framedPanel"},
            gradient  = "@surfaceLinear",   -- pulls midnight's (or default's) gradient
            borderColor = "@accent",
        },
        -- every other selector inherits from the default theme
    },
}
```

---

## 7. Where to look next

- `DMHub Core UI/DefaultStyles.lua` -- the canonical scheme + theme. The source
  of truth for the selector vocabulary and how each widget is styled.
- `draw-steel-codex/DefaultStyles.md` -- prescriptive "which token / class do I
  reach for" guide.
- `draw-steel-codex/ThemeEngine.md` -- the engine API and intended usage
  (`GetStyles` / `MergeStyles` / `MergeTokens`, `@token` syntax, live
  re-theming, deprecated controls).

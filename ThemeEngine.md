# Theme Engine

Codex core and custom module developers should use the Theme Engine to ensure that their UI is consistently styled and colored in a way that aligns with the user's preferences.

Module developers can also create their own custom themes and color schemes.

**IMPORTANT:** Please do not try to create custom themes or color schemes yet. We're still early days. Things *will* change and those changes *will break your work*.
We understand that lots of folks will be eager to create their own themes & color schemes. We are, too! We'll let you know as soon as it's safe to do this!

## Developer Usage

The **best** path to theming your UI is:

1. In your topmost panel / window, use `styles = ThemeEngine.GetStyles()`.
2. In your components, apply appropriate class names from the theme engine to your controls.
3. Never use a constant color for anything; always use a class.
4. Generally use inline properties to control specific layout, etc.

**Preformance!** Using ThemeEngine.GetStyles() ensures that you use a cached theme + color scheme if one exists, and caches it for the next use if it's not already cached. The other paths always parse so they are considerably less performant.

This path ensures that your UI will leverage any theme and color scheme that the end-user chooses.

Sometimes, you will need to add **custom behaviors** through styles instead of inlining properties or writing event handlers. When you do this:

1. Ensure any colors and font faces you use leverage the `@` tokens in the theme and color scheme dictionary. Never use hardcoded colors.
2. Taking #1 above into account, create your styles block.
3. In your topmost panel / window, use `styles = ThemeEngine.MergeStyles(myCustomStyles)`.

Rarely, you might want to **apply styling to a single control** in a way that overrides the styling it inherits from its parent. This is rarely needed -- prefer the higher-level paths above. But if you do need it:

1. Ensure any colors and font faces you use leverage the `@` tokens in the theme and color scheme dictionary. Never use hardcoded colors.
2. Taking #1 above into account, create your styles block.
3. In the control in which you want to override styles, use `styles = ThemeEngine.MergeTokens(myCustomStyles)`.

### Live re-theming (subscribing to theme changes)

`GetStyles()` / `MergeStyles()` / `MergeTokens()` return a one-shot snapshot resolved against the *current* theme + color scheme. When the user switches theme or scheme, your panel will not recolor unless you re-resolve and reassign `panel.styles`.

Subscribe with `ThemeEngine.OnThemeChanged(mod, callback)`:

```lua
local mod = dmhub.GetModLoading()

local panel = gui.Panel{
    styles = ThemeEngine.GetStyles(),
    -- ... children, classes, etc.
}

ThemeEngine.OnThemeChanged(mod, function()
    if panel ~= nil and panel.valid then
        panel.styles = ThemeEngine.GetStyles()
    end
end)
```

Use `MergeStyles(myCustomStyles)` or `MergeTokens(myCustomStyles)` in place of `GetStyles()` when you have custom rules — the same call you used at construction. The callback receives no arguments. Always guard with `panel.valid` so a stale callback doesn't touch a destroyed panel.

The handler is auto-deregistered when your mod unloads; `OnThemeChanged` also returns an entry with a `Deregister()` method if you need to unsubscribe earlier.

### requireConfirm for delete buttons

Callers using `gui.Button{ classes = {"deleteButton"} }` can opt into a confirmation modal:

```lua
gui.Button{ classes = {"deleteButton"}, requireConfirm = true, click = onDelete }
```

Pass `requireConfirm = true` together with a `click` (or `press`) handler and the user sees a "Confirm Delete" modal before the handler fires.

### Icon assets and theme tinting

`bgcolor` on a `bgimage`-bearing panel is a tint *multiplier*, not a replacement. For an icon to fully retint with the active scheme's `@fg` (or `@fgInverse` when selected, etc.), the source PNG must be a **white silhouette with alpha**. PNGs that bake in their own color (gold, blue, etc.) will desaturate against the tint instead of recoloring, and the icon will look "stuck" on the asset's native color across themes.

### @token references in custom styles

When writing custom styles (for `MergeStyles` or `MergeTokens`), reference scheme colors and fonts via `@`-prefixed tokens so your UI re-themes with the active color scheme:

```lua
{ selectors = {"myCustomThing"}, color = "@fg", bgcolor = "@bgAlt" }
```

The token list (`@fg`, `@bg`, `@accent`, `@danger`, etc.) lives in the color-scheme block of `DMHub Core UI / DefaultStyles.lua`.

### @token references inside text markup

The cascade resolver only walks rule tables, so `@tokenName` references baked into a text string (e.g. TextMeshPro inline-color markup) are not substituted automatically. For those cases, call `ThemeEngine.ResolveTokens(text)` to replace each `@tokenName` in the string with the active scheme's resolved hex:

```lua
local entry = ThemeEngine.ResolveTokens(
    string.format('%s <color=@danger>(x%d)</color>', name, count)
)
```

- Non-string inputs pass through unchanged.
- Unknown tokens log a warning once and substitute `UNRESOLVED_COLOR` (magenta) -- same fallback the property resolver uses.
- Only color tokens are substituted; fonts and gradients aren't useful inside text markup so they aren't handled.
- Resolution is per-call (no cache). Run it at the format site, typically inside the same handler that produces the markup string. If the active scheme changes after the string is set on a label, re-run the format call to pick up the new colors.

## Deprecated Controls

Please try to avoid using the following controls, using the suggested alternative instead.

| Deprecated Control | Use Instead |
|--|--|
| gui.AddButton | gui.Button{ classes = { addButton }} |
| gui.Border, gui.PrettyBorder | gui.Panel{ classes = { bordered }} |
| gui.CloseButton | gui.Button{ classes = { closeButton }} |
| gui.CopyButton | gui.Button{ classes = { copyButton }} |
| gui.DeleteButton | gui.Button{ classes = { deleteButton }} |
| gui.FancyButton | gui.Button |
| gui.HudIconButton | gui.Button{ classes = { sizeM }, icon = "image" } |
| gui.IconButton | gui.Button{ icon = iconName } |
| gui.PrettyButton | gui.Button |
| gui.SetEditor | gui.Multiselect |
| gui.SettingsButton | gui.Button{ classes = { settingsButton }} |
| gui.SimpleIconButton | gui.Button { icon = iconName } |

### Expand/collapse triangle: gui.ExpandoArrow

For expand/collapse rows, use `gui.ExpandoArrow` instead of hand-rolling a `gui.Panel{ classes = {"triangle"} }` with custom rotate styles. It packages the proven inline-`bgimage` + local-`styles` pattern (cascade rotate doesn't animate in DMHub UI) and inherits `bgcolor` / sizing / hover from the active theme.

```lua
local arrow = gui.ExpandoArrow{
    click = function(element)
        local nowExpanded = not element:HasClass("expanded")
        element:SetClass("expanded", nowExpanded)
        contentPanel:SetClass("collapsed", not nowExpanded)
    end,
}
```

Pass `classes = {"expanded"}` to load already-expanded; pass `nil` (or omit) to load collapsed.

## Color Scheme

Color schemes are intentionally simple to ensure consistency and relationship between colors in the UI.

Please review the `default` color scheme in `DMHub Core UI / DefaultStyles.lua` to see the available colors and gradients.

Note that for custom development, you need only specify differences from `default` in your color scheme. If you do not include one of the values from default, the Theme Engine will use the value from default for you.

## Theme (incl. Font Faces)

Themes are relatively broad in scope. They consist of fonts and styles. They have four named font use cases and numerous styles.

Please review the `default` theme in `DMHub Core UI / DefaultStyles.lua` to see the available fonts and class selectors. The file is sectioned for navigation: `1. BASICS` (panel/label/button/input/dropdown), `2. FORMS`, `3. CARDS`, `4. DIALOGS`, `5. UTILITIES`.

A second built-in theme `default-rounded` (display name "Default Rounded") inherits everything from `default` and only overrides `cornerRadius` on bordered surfaces (10px on panel-class surfaces, 5px on interactive controls). Selectable via the devmode Theme Test panel; it's a useful demonstration of "themes only override what they need."

When creating custom schemes, remember that, like Color Schemes, the Theme Engine will use the default entries if your theme excludes them.

The styles are built to be composable, so if you want a large, bold label you could use `gui.Label{ classes = {"sizeL", "bold"}, ...}`.

Many class rules conjunct with a primitive (`label`, `panel`, `input`, `dropdown`, `button`, `iconButton`) -- e.g. `gui.Label{ classes = {"form"} }` matches `{label, form}` to pick the form-label rule. Combining classes (`sizeL` + `bold`, etc.) composes styling without inventing new selectors.

Interesting classes:

| Class / Selector | Applies To | When To Use |
|--|--|--|
|bordered|any|Adds a 1px border (themed `@border`) and a paintable surface to any element. On an icon button (`gui.Button{ icon = ... }`) the icon insets to 80% so it doesn't crowd the border.|
|selected|button, iconButton|Marks a button as selected. Inverts chrome (`@bgInverse` / `@borderInverse`) and icon tint (`@fgInverse`). Toggle with `:SetClass("selected", true/false)`.|
|image|panel|Ensure the bgcolor is white so the image shows properly.|
|portraitImage|panel|Opinionated about sizing for portraits.|
|surfaceLinear, surfaceRadial, barTrack|panel|Paint the named scheme gradient on a panel. Use for header strips, framed surfaces, progress-bar tracks.|
|sizeXxs, sizeXs, sizeS, sizeM,<br>sizeL, sizeXl, sizeXxl|label, button|Default sizing.|
|bold, noBold|anything|Make text bold or not bold.|
|number|label|The label holds only a number.|
|disabled|button, checkbox, input|Appear disabled.|
|flipped|iconButton|Flips the icon horizontally.|
|addButton, closeButton, copyButton,<br>deleteButton, settingsButton|button (with `icon = …` or alone)|Iconographic button kinds. Each supplies its own glyph; pair with a size class.|
|withSuccess, withInfo,<br>withWarning, withDanger|iconButton|Tint the icon's hover state with the matching scheme status color.|
|tabBar|panel|Container for a row of tabs.|
|tab|label, button|A single tab inside a tabBar.|
|tableLabel|label|Header label in a table.|
|row|panel|Row in a table.|
|row, headerRow|panel|Header row in a table.|
|row, evenRow - or oddRow|panel|Zebra-stripe a table row.|
|formRow|panel|A row in a form, label left, control right.|
|form|label, input, dropdown, etc.|Apply to items in formRow.|
|formStackedRow|panel|A row in a form, label top, control bottom.|
|formStacked|label, input, dropdown, etc.|Apply to items in formRow.|
|featureCard*|panel,etc|Bordered, collapsible cards like the feature editors in Compendium.|
|dialog|panel|Styling for a panel launched as a dialog.|
|modalTitle|label|Title label inside a `dialog` / `modalDialog`. Center-aligned, bold, themed `@fgStrong`, default fontSize 28.|
|modalMessage|label|Body message label inside a modal. Center-aligned, themed `@fg`, default fontSize 18, 80% width.|
|launchablePanel|panel|Style a panel launched as a launchable panel.|
|hidden|any|Hides the control but does not collapse the area it was in.|
|collapsed|any|Hides the control and collapses the area it was in.|
|collapseAnim|any|As collapsed, but with animation.|
|success, info, warning, danger|any|Tint foreground to the matching scheme status color.|
|bgSuccess, bgInfo, bgWarning, bgDanger|any|Tint background to the matching scheme status color.|
|borderSuccess, borderInfo, borderWarning, borderDanger|any|Tint the border to the matching scheme status color (compose with `bordered` or another bordered class).|

# UI Best Practices

This document is the reference for building UI in the DMHub Lua framework. It covers available controls, the style system, layout, events, and coding standards.

## Overview

UI is declarative: you construct trees of panels using `gui.Panel{}`, `gui.Label{}`, etc. Each constructor takes a table of properties, event handlers, and child panels. Panels support CSS-like styling through class selectors and style tables, and communicate via a custom event system.

---

## Controls Reference

### Core Controls

**gui.Panel** -- container and layout element. Everything is built from panels.

Key properties:
- Layout: `flow` ("vertical"/"horizontal"/"none"), `width`, `height`, `halign`, `valign`
- Spacing: `pad`, `hpad`, `vpad`, `margin`, `hmargin`, `vmargin`, `tmargin`, `bmargin`, `lmargin`, `rmargin`, `borderBox`
- Visual: `bgcolor`, `bgimage`, `border`, `borderColor`, `borderWidth`, `cornerRadius`, `opacity`
- Behavior: `vscroll` (scrollable), `interactable`, `classes`, `styles`, `data`
- Inline-only: `floating`, `rotate` (NEVER put these in styles)

Key methods:
- `SetClass(name, bool)` / `HasClass(name)` -- toggle/check CSS-like classes
- `SetClassTree(name, bool)` -- set class on element and all descendants
- `FireEvent(name, ...)` -- fire event on this element only
- `FireEventTree(name, ...)` -- fire event on this element and all descendants
- `AddChild(panel)` / `DestroySelf()` -- modify hierarchy
- `HaltEventPropagation()` -- stop FireEventTree from going deeper
- `AddClass(name)` / `RemoveClass(name)` -- explicit add/remove
- `PulseClass(name)` -- briefly add then remove (used for fade-in animations)

Key fields:
- `children` -- table of child panels (can be reassigned, but see **Orphaned Panels** below)
- `parent` -- parent panel reference
- `data` -- custom data storage table
- `selfStyle` -- mutable inline style overrides (use sparingly)
- `valid` -- boolean, still alive in the UI tree
- `text` -- (labels/inputs) get/set text content

```lua
gui.Panel{
    classes = {"container"},
    flow = "vertical",
    width = "100%",
    height = "auto",
    gui.Label{ classes = {"title"}, text = "HEADER" },
}
```

**gui.Label** -- text display.

Key properties: `text`, `fontSize`, `fontFace`, `color`, `textAlignment` ("left"/"center"/"right"), `bold`, `italic`, `textWrap`, `markdown`, `strikethrough`, `editable` (makes it user-editable), `numeric` (restricts to numbers when editable).

Events: `change` fires when user edits (if `editable = true`).

**gui.Input** -- text entry field.

Key properties: `text`, `placeholderText`, `editlag` (delay in seconds before `edit` event fires).

Events: `edit` (fires during typing after editlag), `change` (value committed), `confirm` (Enter pressed), `focus`, `defocus`.

### Button Controls

- **gui.EnhIconButton** -- icon button with `bgimage`. Used for toolbar and action buttons.
- **gui.IconButton** -- icon button with built-in hover/press states. Properties: `icon`, `tooltip`, `press`, `flipped` (mirror image).
- **gui.Button** -- styled text button with optional `icon` and `tooltip`.
- **gui.CloseButton** -- X-icon close button.
- **gui.DeleteItemButton** -- styled delete button with press state.
- **gui.AddButton** -- plus-sign button for adding items.
- **gui.SimpleIconButton** -- generic icon button with close-button styling.
- **gui.DiamondButton** -- diamond-shaped button.
- **gui.FancyButton** / **gui.PrettyButton** -- decorative styled buttons.
- **gui.HudIconButton** -- HUD-style icon button.

### Selection Controls

**gui.Check** -- checkbox.
- Properties: `value` (boolean), `text`, `placement` ("left"/"right"), `fontSize`, `tooltip`
- Methods: `GetValue()`, `SetValue(val, firechange)`
- Events: `change`

**gui.Slider** -- numeric slider.
- Properties: `minValue`, `maxValue`, `value`, `sliderWidth`, `labelWidth`, `labelFormat`, `round`, `defaultValue` (double-click reset)
- Methods: `getValue()`, `setValue(val, fireevent)`
- Events: `change`

**gui.Dropdown** -- selection dropdown.

**gui.ColorPicker** -- color picker with channel sliders.
- Properties: `value` (color), `hasAlpha`
- Methods: `getColor()`, `setColor(val, fireevent)`
- Events: `change`, `confirm`

### Navigation Controls

**gui.CollapseArrow** -- expand/collapse arrow indicator. Uses `collapseSet` class to flip via scale. Always use this -- never build custom expand/collapse arrows.

```lua
gui.CollapseArrow{
    classes = {"expando"},
    setCollapse = function(element, collapsed)
        element:SetClass("collapseSet", collapsed)
    end,
}
```

**gui.PagingArrow** -- left/right paging arrow. Property: `facing` (-1 for left, 1 for right).

### Display Controls

**gui.Tooltip(text)** -- returns a function. Call as `gui.Tooltip(text)(element)` in `linger` handlers. See Tooltip Patterns section.

**gui.TooltipFrame(panel)** -- wraps a custom panel as a tooltip.

**gui.StatsHistoryTooltip{entries=...}** -- tooltip showing stat change history.

**gui.MCDMDivider{layout="..."}** -- decorative divider. Layouts: "line", "dot", "peak", "v", "vdot".

**gui.Divider** -- simple horizontal line divider.

**gui.Diamond** -- diamond shape (45-degree rotated square). Properties: `borderWidth`, `borderColor`.

**gui.ProgressBar** -- fill bar. Properties: `value` (0-1), `fontSize`. Methods: `GetValue()`, `SetValue()`.

**gui.CreateTokenImage(token, options)** -- renders a character/creature token portrait. Properties: `idprefix`, `classes`, `interactable`.

**gui.VisibilityPanel** -- eye icon toggle for visibility state. Properties: `visible` (boolean). Toggles between open/closed eye icons.

### Other Controls

These are available but less commonly used: `gui.SearchInput`, `gui.FancyInput`, `gui.TreeNode`, `gui.ContextMenu`, `gui.ContextMenuItem`, `gui.Border`, `gui.PrettyBorder`, `gui.DialogBorder`, `gui.LoadingIndicator`, `gui.PercentSlider`, `gui.CurrencyEditor`, `gui.AudioEditor`, `gui.Curve`.

---

## Panel Rendering

Panels must have a `bgimage` to draw anything on screen. Without one, a panel is an invisible grouping container (though `gui.Label` still renders its text).

Set `bgimage = true` as shorthand for a plain filled rectangle (equivalent to `bgimage = "panels/square.png"`). Use a path string for a specific image asset.

```lua
-- This panel is visible and draws its bgcolor:
gui.Panel{
    bgimage = true,
    bgcolor = "#333333",
    width = 100, height = 40,
}

-- This panel is invisible -- it only groups its children:
gui.Panel{
    bgcolor = "#333333",  -- has no effect without bgimage
    width = 100, height = 40,
}
```

### Outlined Box

```lua
gui.Panel{
    bgimage = "panels/square.png",
    bgcolor = "clear",
    borderWidth = 1,
    borderColor = "#966D4B",
    cornerRadius = 6,
}
```

---

## Panels Must Be Parented Immediately

Every panel created with `gui.Panel{}` (or `gui.Label{}`, etc.) **must** be attached to a parent by the end of the frame it was created in. If a panel is created but never set as a child of another panel or returned as part of a panel tree, the engine raises an error:

> Panel ID-XXXXX was created but not attached to a parent.

This means you cannot speculatively create panels "just in case" and discard them. If you need a panel only sometimes, guard the creation with a conditional so the panel is never allocated unless it will be used.

---

## Avoid Recreating Panels

Panel creation is expensive. Never rebuild a panel tree on every data change. Instead, prefer event-driven updates to modify existing panels in place.

**Bad** -- rebuilds the roll info panel on every document tick:
```lua
refreshGame = function(element)
    local panel = CreateExpensivePanel(data)
    element.children = { panel }
end
```

**Good** -- only rebuild when the state actually changes:
```lua
refreshGame = function(element)
    if data.state ~= lastState then
        lastState = data.state
        local panel = CreateExpensivePanel(data)
        element.children = { panel }
    end
end
```

**Better** -- fire events into the existing panel to update it:
```lua
refreshGame = function(element)
    existingPanel:FireEventTree("updateData", data)
end
```

This is especially important for panels with live event subscriptions (e.g. dice event listeners). Replacing such a panel destroys the subscriptions and breaks in-progress animations.

---

## Style System

### Definition Format

Styles are arrays of dictionaries. Each dictionary has a `selectors` array and one or more property values:

```lua
MyStyles.Component = {
    {   -- Base panel styling
        selectors = {"panel", "my-class"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        fontSize = 14,
    },
    {   -- Active variant -- cascades over base when "active" class is set
        selectors = {"panel", "my-class", "active"},
        bgcolor = "#966D4B",
    },
    {   -- Hover state
        selectors = {"panel", "my-class", "hover"},
        brightness = 1.5,
        transitionTime = 0.2,
    },
}
```

### Selector Syntax

- **Class selectors**: `{"className"}` or `{"class1", "class2"}` -- AND logic, element must match all classes
- **State pseudo-selectors**: `"hover"`, `"press"`, `"focus"` -- built-in interaction states
- **Parent state**: `"parent:hover"`, `"parent:press"`, `"parent:hover-linger"`, `"parent:selected"` -- style based on parent's state
- **Negation**: `"~className"` -- matches when class is NOT present
- **Element type prefix**: `{"panel", ...}`, `{"label", ...}`, `{"input", ...}` -- matches element type

**Important**: `gui.Table` / `gui.TableRow` have built-in `"row"` and `"label"` selectors that cascade to children correctly via `SetClassTree`. Plain `gui.Panel` with custom class names does not cascade the same way. When you need style changes to propagate through a subtree, use `gui.Table` / `gui.TableRow` or apply styles to each child explicitly.

### Applying Styles

Pass a style table to the `styles` property of the root panel of a component. Styles cascade to all descendants that match the selectors:

```lua
gui.Panel{
    styles = MyStyles.Component,
    classes = {"panel", "my-class"},
    gui.Label{ classes = {"label", "my-class", "title"}, text = "Title" },
}
```

### Merging Style Tables

To combine style arrays from multiple components:

```lua
function MergeStyles(styles)
    local result = {}
    for _, styleArray in ipairs(styles) do
        for _, entry in ipairs(styleArray) do
            result[#result + 1] = entry
        end
    end
    return result
end
```

### Favor Styles and Cascading

Put as much as possible in style tables. Use class selectors and cascading (base + variant selectors) to handle state changes rather than setting properties in code. This keeps visual definitions centralized and maintainable.

**What goes where**:

- **In styles (strongly preferred)**: layout (width, height, margin, padding, flow, alignment), fonts (fontSize, fontFace, color), borders, backgrounds, transitions -- essentially ALL visual properties
- **Inline only (NEVER in styles)**: `floating`, `rotate` -- these must be declared as inline properties on the panel
- **selfStyle**: Use ONLY when it is impossible to achieve the result with classes/styles. For example, a dynamically computed width percentage that cannot be expressed as a fixed set of class variants. If you can toggle a class instead, always do that.

### Inline Properties Override Styles

Properties set directly on a panel (inline) always take precedence over entries in `styles`, regardless of selectors. This means hover/state styles cannot override an inline property.

```lua
-- WRONG: bgcolor is set inline, so the hover style is ignored
gui.Panel{
    bgimage = true,
    bgcolor = "clear",
    styles = {
        { selectors = {"hover"}, bgcolor = "white" },  -- never applies!
    },
}

-- CORRECT: move the default bgcolor into styles so hover can override it
gui.Panel{
    bgimage = true,
    styles = {
        { bgcolor = "clear" },
        { selectors = {"hover"}, bgcolor = "white" },
    },
}
```

### Available Style Properties

Layout: `width`, `height`, `flow`, `halign`, `valign`, `pad`, `hpad`, `vpad`, `margin`, `hmargin`, `vmargin`, `tmargin`, `bmargin`, `lmargin`, `rmargin`, `maxWidth`, `maxHeight`, `borderBox`

Visual: `bgcolor`, `bgimage`, `bgslice`, `border`, `borderColor`, `borderWidth`, `cornerRadius`, `gradient`, `opacity`, `brightness`, `shadow`, `hueshift`

Text: `color`, `fontSize`, `fontFace`, `textAlignment`, `bold`, `italic`, `strikethrough`, `textWrap`

Interaction: `collapsed` (hides element), `transitionTime` (animation duration), `scale`

Image: `imageRect` (clip region, 0-1 normalized), `bgslice` (9-slice borders)

---

## Constants and Sizing

### Organization

Use hierarchical tables organized by domain:

```lua
local MySizes = {}
MySizes.Panels = { fullWidth = 340, summaryNames = 140 }
MySizes.Fonts = { panelTitle = 14, charName = 28, charLevel = 18 }
MySizes.HealthBar = { segmentHeight = 10, diamondSize = 12 }
```

### Colors

Define named locals at the top of the file using hex strings:

```lua
local GOLD = "#966D4B"
local CREAM = "#FFFEF8"
local TEAL_HEAL = "#2D6A4F"
```

Append hex alpha for transparency: `GOLD .. "0F"` for 6% opacity.

### Dynamic Font Sizing

For variable-length text, scale the font down to fit:

```lua
local function _fitFontSize(baseSize, maxChars, len)
    if len <= maxChars then return baseSize end
    return math.max(12, math.floor(baseSize * maxChars / len))
end
```

---

## Panel Construction

### Inline Declarations

All child panels must be declared inline within their parent. Do not extract child panels into local variables.

```lua
-- PREFER: children declared inline
gui.Panel{
    classes = {"container"},
    gui.Label{ classes = {"title"}, text = "HEADER" },
    gui.Label{ classes = {"value"}, text = "0" },
}

-- AVOID unless strictly necessary: children extracted to variables
local title = gui.Label{ classes = {"title"}, text = "HEADER" }
local value = gui.Label{ classes = {"value"}, text = "0" }
gui.Panel{ classes = {"container"}, title, value }
```

### Inter-Panel Communication

Since panels are inlined, use custom events to communicate between siblings:

```lua
gui.Panel{
    gui.Label{
        classes = {"title"},
        setTitle = function(element, text) element.text = text end,
    },
    gui.CollapseArrow{
        setCollapse = function(element, collapsed)
            element:SetClass("collapseSet", collapsed)
        end,
    },
}
-- The parent can fire: element:FireEventTree("setTitle", "NEW TITLE")
```

Never use the `children` array to reach a specific control. This code will not be robust, and will break with future edits. **Always** use custom events via `FireEventTree` to communicate with children.

### Data Tables

Store panel state in the `data` table, not in closure upvalues:

```lua
gui.Panel{
    data = { token = nil, collapsed = false },
    refreshCharacter = function(element, token)
        element.data.token = token
        -- always read state from element.data
    end,
}
```

### Dynamic Children

Swap the entire `children` array to rebuild content:

```lua
local children = {}
for _, item in ipairs(items) do
    children[#children + 1] = createRow(item)
end
element.children = children
```

### Conditional Children

Nil entries in a children array are skipped, so use inline conditionals:

```lua
gui.Panel{
    children = {
        headerPanel,
        showDetails and detailsPanel or nil,
        footerPanel,
    },
}
```

### Input Tables and DeepCopy

When a helper function receives an options table, `DeepCopy` it before mutating to avoid side effects on the caller:

```lua
function CreateMyPanel(args)
    local options = DeepCopy(args or {})
    options.bgimage = true
    return gui.Panel(options)
end
```

---

## Layout

### Flow

- `"vertical"` -- stack children top-to-bottom (default)
- `"horizontal"` -- arrange children left-to-right
- `"none"` -- absolute positioning (children use `x`, `y`, `halign`, `valign`)

### Sizing Expressions

- Pixels: `width = 100`
- Percentage: `width = "50%"`
- Percent minus pixels: `width = "100%-8"` (useful for margins within a container)
- Auto: `width = "auto"` (fit to content)
- Remaining space: `height = "100% available"` (fill space after siblings)
- Aspect ratio: `width = "100% height"` (width equals the element's height)

### Spacing

- Inner (padding): `pad` (all), `hpad` (left+right), `vpad` (top+bottom)
- Outer (margin): `margin` (all), `hmargin`, `vmargin`, `tmargin`, `bmargin`, `lmargin`, `rmargin`

**Box sizing:** By default (content-box behavior), `hpad` and `vpad` add to the element's rendered size -- they do not shrink the content area. This means an element with `width = 200` and `hpad = 10` will render 220px wide (200 content + 10 on each side), which is rarely the intent.

**Always set `borderBox = true` on new panels that use padding.** This makes the specified width/height include padding, so the element stays the size you declared and the content area shrinks inward instead. This matches CSS `box-sizing: border-box` and avoids overflow surprises.

```lua
-- CORRECT: borderBox makes padding shrink the content area inward.
-- The panel renders exactly 200px wide; content area is 180px.
gui.Panel{ width = 200, hpad = 10, borderBox = true }

-- LEGACY: without borderBox, the panel renders 220px wide (200 + 2*10).
-- Avoid this pattern in new code.
gui.Panel{ width = 200, hpad = 10 }

-- ALSO WORKS: manually subtract padding from width.
-- Use borderBox = true instead when possible.
gui.Panel{ width = "100%-20", hpad = 10 }
```

The same applies to `vpad` and `height`. `borderBox` works with both fixed pixel widths and percentage widths.

### Scrolling

Set `vscroll = true` on a container panel to enable vertical scrolling.

### Border Syntax

Borders can be uniform or per-edge:

```lua
border = 1                                          -- 1px all edges
border = { x1 = 0, y1 = 1, x2 = 0, y2 = 0 }      -- 1px bottom only
cornerRadius = 6                                     -- uniform radius
cornerRadius = { x1 = 0, x2 = 0, y1 = 4, y2 = 4 } -- bottom corners only
```

### Wrap

`wrap = true` -- children wrap to the next line (horizontal flow).

---

## Event System

### Built-in Events

**Interaction**: `press`, `rightClick`, `hover`, `dehover`, `linger` (fires after hovering for a delay), `doubleclick`

**Input**: `edit` (during typing, respects `editlag`), `change` (value committed), `confirm` (Enter key), `focus`, `defocus`

**Lifecycle**: `create` (panel initialized), `destroy` (panel removed)

**Document monitoring**: Set `monitorGame = documentPath` on a panel, then handle `refreshGame` to react to shared document changes.

### Custom Events

Any property name on a panel can be an event handler function. The engine defines domain events (e.g., `refreshCharacter`, `refreshToken`, `setToken`) that fire automatically on character/token changes. You can define your own custom events (e.g., `setTitle`, `setCollapse`, `update`) and fire them manually.

```lua
gui.Panel{
    updateDisplay = function(element, newValue)
        element.text = tostring(newValue)
    end,
}
```

### FireEvent vs FireEventTree

- `element:FireEvent("name", ...)` -- fires on the calling element only
- `element:FireEventTree("name", ...)` -- fires on the calling element AND all descendants

**Beware infinite loops**: `FireEventTree` fires on the calling element too. If the handler itself calls `FireEventTree` with the same event name, it will recurse infinitely.

Call `element:HaltEventPropagation()` inside a handler to stop `FireEventTree` from propagating further down that branch.

### Monitoring Data Changes

| Field | Paired callback | Watches |
|---|---|---|
| `monitorGame = path` | `refreshGame` | Shared documents (cross-client sync) |
| `monitor = id` | `events.monitor` | Settings by ID |

```lua
gui.Panel{
    monitorGame = mod:GetDocumentSnapshot("docId").path,
    refreshGame = function(element)
        local doc = mod:GetDocumentSnapshot("docId")
        -- update UI from doc.data
    end,
}
```

Keep `refreshGame` lightweight since it fires on every remote change.

---

## Show and Hide

Use `collapsed` (not a `visible` property) to hide/show elements:

```lua
element.collapsed = 1   -- Hidden, takes no layout space
element.collapsed = 0   -- Visible
```

Or toggle via class:

```lua
element:SetClass("collapsed", not visible)
```

`collapsed` works with `transitionTime` in styles for animated show/hide.

---

## Transitions and Animation

Add `transitionTime` to style selectors to animate property changes:

```lua
styles = {
    { selectors = {"panel"}, opacity = 0.5, transitionTime = 0.3 },
    { selectors = {"panel", "hover"}, opacity = 1.0, transitionTime = 0.1 },
}
```

---

## Periodic Work with thinkTime

Set `thinkTime` to call a `think` handler at a regular interval:

```lua
gui.Panel{
    thinkTime = 1.0,
    think = function(element)
        -- called every 1 second
    end,
}
```

Set `element.thinkTime = 0` to stop the timer. Adjust dynamically as needed.

---

## Deferred Positioning

Panel dimensions (`renderedWidth`, `renderedHeight`) are not available until after the first render. Use `dmhub.Schedule` with a small delay for positioning that depends on rendered size:

```lua
create = function(element)
    dmhub.Schedule(0.05, function()
        if element.valid then
            element.x = element.parent.renderedWidth
        end
    end)
end,
```

---

## Validity Checks

Panels can be destroyed asynchronously. Always check `element.valid` before accessing a panel from a deferred callback or stored reference:

```lua
dmhub.Schedule(1.0, function()
    if panel ~= nil and panel.valid then
        panel.text = "updated"
    end
end)
```

---

## Orphaned Panels

**When a panel is removed from the UI tree (orphaned), the engine automatically destroys it.** This means you cannot remove a panel from its parent and later re-add it -- the panel will be invalid after removal.

This commonly happens when assigning `element.children = { ... }` -- any previous children not included in the new list are orphaned and destroyed. Do **not** store references to panels and attempt to swap them back in later.

Instead, use the `collapsed` class to show/hide panels while keeping them in the tree:

```lua
-- WRONG: swapping children destroys the removed panels
showSettings = function(element)
    element.children = { settingsPanel }  -- chatPanel is now destroyed!
end,
closeSettings = function(element)
    element.children = { chatPanel }      -- ERROR: chatPanel is invalid
end,

-- RIGHT: toggle visibility, all panels stay in the tree
showSettings = function(element)
    chatArea:SetClass("collapsed", true)
    settingsArea:SetClass("collapsed", false)
end,
closeSettings = function(element)
    chatArea:SetClass("collapsed", false)
    settingsArea:SetClass("collapsed", true)
end,
```

This applies to any scenario where you want to switch between views -- always keep both views as children and toggle `collapsed` rather than swapping the children list.

---

## Module Lifecycle Cleanup

Register cleanup handlers so long-lived panels are destroyed when a mod unloads:

```lua
local mod = dmhub.GetModLoading()
mod.unloadHandlers[#mod.unloadHandlers+1] = function()
    if dialog ~= nil and dialog.valid then
        dialog:DestroySelf()
    end
end
```

Also guard scheduled callbacks with `mod.unloaded`:

```lua
dmhub.Schedule(delay, function()
    if mod.unloaded then return end
    -- do work
end)
```

---

## Scrollable Lists with Virtual Children

For large lists, use `Scrollable` with `expose` to lazy-load children only when they scroll into view:

```lua
expose = function(element)
    if element.data.child == nil then
        element.data.child = createExpensiveChild()
        element.children = { element.data.child }
    end
end,
```

---

## Interactivity Control

- `interactable = false` blocks mouse input but keeps the panel visible.
- `element:MakeNonInteractiveRecursive()` disables interaction on an entire subtree (useful for read-only displays of interactive templates).

---

## Tooltip Patterns

```lua
-- Simple text tooltip in a linger handler
linger = function(element)
    gui.Tooltip("Help text")(element)
end,

-- Conditional tooltip (check validity first)
linger = function(element)
    if element.data.token and element.data.token.valid then
        gui.Tooltip("Info about this token")(element)
    end
end,

-- Tooltip as direct linger property (non-dynamic)
linger = gui.Tooltip("Static tooltip text"),

-- Custom panel tooltip
linger = function(element)
    element.tooltip = gui.TooltipFrame(gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        gui.Label{ text = "Custom content", width = "auto", height = "auto" },
    })
end,

-- Markdown tooltip (using a helper that creates a styled panel)
linger = function(element)
    element.tooltip = MyTooltip(markdownString)
end,
```

---

## Common Recipes

### Collapse/Expand with CollapseArrow

```lua
gui.Panel{
    data = { collapsed = false },
    gui.Panel{
        classes = {"header"},
        press = function(element)
            local outer = element.parent
            outer.data.collapsed = not outer.data.collapsed
            outer:FireEventTree("setCollapse", outer.data.collapsed)
        end,
        gui.Label{
            classes = {"title"},
            text = "SECTION TITLE",
        },
        gui.CollapseArrow{
            classes = {"expando"},
            setCollapse = function(element, collapsed)
                element:SetClass("collapseSet", collapsed)
            end,
        },
    },
    -- Content rows respond to the same setCollapse event:
    -- setCollapse = function(element, collapsed)
    --     element:SetClass("collapsed", collapsed)
    -- end,
}
```

### Conditional Class Styling

Define base and variant selectors in styles, then toggle variant classes at runtime:

```lua
-- In the style table
{ selectors = {"label", "value"}, color = DIM },
{ selectors = {"label", "value", "positive"}, color = TEAL },
{ selectors = {"label", "value", "negative"}, color = RED },

-- In an event handler
element:SetClass("positive", val > 0)
element:SetClass("negative", val < 0)
```

---

## Rules

1. **Favor styles and class cascading** for all visual properties. Keep visuals centralized in style tables.
2. **Use selfStyle ONLY** when classes/styles cannot express the result (e.g., a dynamically computed value with no fixed set of variants).
3. **floating and rotate** are always inline properties, never in styles.
4. **Inline all child panel declarations** -- no local variables for panels.
5. **Use FireEventTree with custom events** for inter-panel communication between inlined panels.
6. **Beware FireEventTree infinite loops** -- it fires on the calling element too. Use FireEvent for self-only.
7. **Use gui.CollapseArrow** -- never build custom expand/collapse arrows.
8. **Use gui.Tooltip(text)(element)** in linger handlers for tooltips.
9. **All magic numbers** go in a constants table.
10. **Store panel state in data tables**, not closure upvalues.
11. **ASCII only** in Lua source files -- no unicode punctuation.

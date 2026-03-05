# UI Best Practices

Guidelines for building UI panels in DMHub using the `gui` global.
All UI is built with `gui.Panel`, `gui.Label`, `gui.Input`, etc. -- declarative tables
of style properties and event callbacks.

---

## Style Application

### Inline (direct properties)

Pass style fields directly in the panel constructor:

```lua
gui.Panel{
    width = 100,
    height = 50,
    bgcolor = "black",
    halign = "center",
    valign = "center",
}
```

### Named styles with selectors

Define a styles table and attach it to a panel. Styles apply when the panel's classes
match the selector list (all selectors must match -- AND logic):

```lua
local SlotStyles = {
    gui.Style{
        selectors = { "slot" },
        width = 76,
        height = 76,
        bgcolor = "black",
        borderWidth = 4,
        borderColor = "white",
    },
    gui.Style{
        selectors = { "slot", "selected" },
        bgcolor = "#ffffff",
        color = "black",
    },
    gui.Style{
        selectors = { "slot", "hover", "~expended" },  -- hover AND NOT expended
        brightness = 1.5,
    },
}

gui.Panel{
    classes = "slot",
    styles = SlotStyles,
}
```

### selfStyle (post-creation overrides)

Modify a single property on a panel after creation without rebuilding styles:

```lua
element.selfStyle.halign = "right"
element.selfStyle.fontSize = 14
```

---

## Layout

### flow

Controls the direction children are stacked. Default is vertical.

| Value | Effect |
|-------|--------|
| `"vertical"` | Stack children top to bottom (default) |
| `"horizontal"` | Stack children left to right |

```lua
gui.Panel{ flow = "horizontal" }  -- horizontal row
```

### halign / valign

Align the panel itself within its parent, or align its children.

| Field | Values |
|-------|--------|
| `halign` | `"left"`, `"center"`, `"right"` |
| `valign` | `"top"`, `"center"`, `"bottom"` |

### width / height

| Value | Meaning |
|-------|---------|
| number | Fixed pixel size |
| `"50%"` | Percentage of parent |
| `"auto"` | Fit content (unreliable -- prefer explicit sizes or percentages) |

`minWidth`, `maxWidth`, `minHeight`, `maxHeight` are also supported.

### wrap

```lua
gui.Panel{ flow = "horizontal", wrap = true }
-- Children wrap to the next row when they overflow
```

---

## Colors

| Field | Purpose |
|-------|---------|
| `bgcolor` | Background fill |
| `color` | Text / foreground color |
| `borderColor` | Border color |

**Format options:**

```lua
bgcolor = "black"          -- named color
bgcolor = "#ffffff"        -- hex RGB
bgcolor = "#ffffff77"      -- hex RGBA (77 = ~47% opaque)
bgcolor = "#ff000000"      -- fully transparent red
```

---

## Typography

| Field | Type | Description |
|-------|------|-------------|
| `fontSize` | number | Font size in points |
| `minFontSize` | number | Minimum size when text auto-shrinks to fit |
| `bold` | boolean | Bold weight |
| `italic` | boolean | Italic style |
| `textAlignment` | string | `"left"`, `"center"`, `"right"` -- for multi-line text |
| `textOverflow` | string | `"truncate"` clips text; `"wrap"` wraps to next line |
| `characterLimit` | number | Hard truncation after N characters |

```lua
gui.Label{
    fontSize = 14,
    minFontSize = 8,   -- shrinks if text doesn't fit at 14
    bold = true,
    color = "white",
    textAlignment = "center",
    textOverflow = "truncate",
    maxHeight = 30,
}
```

---

## Spacing

| Field | Applies to |
|-------|-----------|
| `padding` | All four sides |
| `hpadding` | Left + right |
| `vpadding` | Top + bottom |
| `margin` | All four sides (space outside the panel) |
| `hmargin` | Left + right margin |
| `vmargin` | Top + bottom margin |

---

## Borders and Images

```lua
gui.Panel{
    borderWidth = 4,
    borderColor = "white",
    bgimage = "panels/square.png",
}
```

**Gradient background:**

```lua
gui.Panel{
    gradient = gui.Gradient{
        point_a = {x=0, y=0},
        point_b = {x=0, y=1},   -- vertical: top to bottom
        stops = {
            { position = 0, color = "#000000" },
            { position = 1, color = "#444444" },
        },
    },
}
```

---

## Effects and Animation

| Field | Type | Description |
|-------|------|-------------|
| `hidden` | `0` or `1` | Visibility flag (0 = visible, 1 = hidden) |
| `opacity` | `0.0`-`1.0` | Transparency (1 = fully opaque) |
| `brightness` | number | `0.5` = dark, `1.0` = normal, `2.0` = bright |
| `transitionTime` | number | Animate property changes over N seconds |

```lua
-- Fade in
gui.Panel{
    opacity = 0,
    transitionTime = 0.5,
}
element.opacity = 1   -- triggers 0.5s fade
```

---

## Class Selectors

### Applying classes

```lua
-- At construction time:
gui.Panel{ classes = "slot selected" }     -- space-separated string
gui.Panel{ classes = { "slot", "selected" } }  -- array

-- Dynamically:
element:AddClass("selected")
element:RemoveClass("selected")
element:SetClass("selected", isSelected)   -- preferred for toggle
```

### Selector logic

- Multiple selectors in a `selectors` array are ANDed together
- Prefix with `~` to negate: `"~expended"` means "does NOT have class expended"

```lua
-- Applies when panel has "slot" AND "hover" AND does NOT have "expended"
gui.Style{ selectors = { "slot", "hover", "~expended" }, brightness = 1.5 }
```

### Selector precedence

1. Named styles (lowest)
2. Inline panel properties
3. `selfStyle` modifications (highest)

---

## Events

Key event callbacks on panels:

| Event | Fires when |
|-------|-----------|
| `create` | Panel is first created |
| `think` | Every frame (use sparingly) |
| `click` | Panel is clicked |
| `change` | Input value changes |
| `prepare` | `ShowDialog` is called (roll dialog context) |
| `refreshGame` | Monitored game state changes |
| `monitorGame` | Set to a document path to watch for changes |
| `monitorstate` | Set to a key to watch for state changes |

```lua
gui.Panel{
    monitorGame = mod:GetDocumentPath("myDoc"),
    refreshGame = function(element)
        local doc = mod:GetDocumentSnapshot("myDoc")
        element.children = { BuildUI(doc.data) }
    end,
}
```

**Important:** Always set `element.children` inside an event handler (like `refreshGame` or
`create`), not at the top level of a panel definition, unless the children are static.

---

## Common Patterns

### Centered container

```lua
gui.Panel{
    width = "100%",
    height = "100%",
    halign = "center",
    valign = "center",
    flow = "vertical",
}
```

### Horizontal button bar

```lua
gui.Panel{
    flow = "horizontal",
    halign = "center",
    valign = "center",
    height = 36,
    hpadding = 4,
}
```

### Vertical scrollable list

```lua
gui.Panel{
    flow = "vertical",
    vscroll = true,
    width = "100%",
    height = "100%",
}
```

### Responsive text label

```lua
gui.Label{
    width = "95%",
    height = "auto",
    fontSize = 16,
    minFontSize = 10,
    textOverflow = "truncate",
    maxHeight = 50,
    halign = "center",
    textAlignment = "center",
}
```

### Styled interactive panel (button-like)

```lua
local BtnStyles = {
    gui.Style{ selectors = {"btn"},         bgcolor = "#333333", borderColor = "white", borderWidth = 2 },
    gui.Style{ selectors = {"btn","hover"},  brightness = 1.5 },
    gui.Style{ selectors = {"btn","press"},  brightness = 0.6 },
}

gui.Panel{
    classes = "btn",
    styles = BtnStyles,
    width = 100,
    height = 40,
    halign = "center",
    valign = "center",
    click = function(element) ... end,
}
```

---

## Gotchas

- **`width = "auto"` is unreliable.** Prefer explicit pixel sizes or percentages. Use `maxHeight`
  to cap auto-height labels.
- **Borders add to layout.** A 4px border on a 76x76 panel leaves 68x68 for its content.
- **Use `SetClass` for dynamic toggles**, not `classes`. `classes` is only read at construction.
- **Set `element.children` inside `create` or `refreshGame`**, not at the top level of the
  constructor, unless children are fully static. Setting children at the top level bypasses
  the event system and can cause stale data.
- **`prepare` in roll dialogs.** The `prepare` event fires when `ShowDialog` is called.
  Always nil-check `options.modifiers` and `creature` inside prepare -- they may not be
  set the first time prepare fires.
- **Percentage widths are relative to the parent container.** If the parent has no explicit
  width, percentages on children may resolve to 0.

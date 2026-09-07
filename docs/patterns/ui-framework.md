# UI Framework

DMHub's UI is built with declarative panel trees. You construct UI by nesting `gui.Panel{}`, `gui.Label{}`, `gui.Input{}` and other controls inside each other.

## Basic panel structure

```lua
gui.Panel{
    classes = {"recovery-chip"},
    flow = "horizontal",
    press = function(element)
        -- handle click
    end,
    hover = function(element)
        gui.Tooltip("Some tooltip text")(element)
    end,
    gui.Label{
        classes = {"recovery-chip-label"},
        text = "End: Bleeding",
    },
}
```

*Source: `Draw_Steel_Ability_Behaviors_aef5/AbilityRecoverSelection.lua`*

Panels are Lua tables passed to `gui.Panel{}`. Children are nested directly inside the table.

## Key style properties

| Property | Type | Description |
|----------|------|-------------|
| `width` / `height` | number or string | Size (pixels or `"100%"`) |
| `x` / `y` | number | Position offset |
| `halign` / `valign` | string | Alignment: `"left"`, `"center"`, `"right"` / `"top"`, `"center"`, `"bottom"` |
| `flow` | string | Layout direction: `"vertical"` (default), `"horizontal"` |
| `bgcolor` | string | Background color (hex or name) |
| `bgimage` | string | Background image path |
| `borderColor` | string | Border color |
| `cornerRadius` | number | Rounded corners |
| `classes` | table | CSS-like class names for styling |

## Classes and styling

Styles are applied via class selectors, similar to CSS:

```lua
{
    selectors = {'slot', 'maneuver'},
    bgcolor = "white",
    gradient = gui.Gradient{
        point_a = {x=0, y=0},
        point_b = {x=1, y=1},
        stops = {
            {position = 0, color = "#000000"},
            {position = 1, color = "#666666"},
        },
    }
},
```

*Source: `Draw_Steel_UI_bd58/DSActionBar.lua`*

Toggle classes dynamically with:

```lua
element:SetClass("selected", true)   -- add class
element:SetClass("selected", false)  -- remove class
```

## Event callbacks

| Callback | When it fires |
|----------|--------------|
| `click` / `press` | User clicks the element |
| `hover` | Mouse enters the element |
| `create` | Element is first created |
| `think` | Called every frame (use `thinkTime` to control frequency) |
| `refreshGame` | When monitored game state changes |
| `change` | For inputs, when the value changes |

## Reactive patterns

### Monitor game state

Use `monitorGame` + `refreshGame` to react to [Shared Document](shared-documents.md) changes:

```lua
gui.Panel{
    monitorGame = mod:GetDocumentSnapshot("myDoc").path,
    refreshGame = function(element)
        local doc = mod:GetDocumentSnapshot("myDoc")
        -- update UI from doc.data
    end,
}
```

### Polling with `think`

For continuous updates (animations, timers):

```lua
gui.Panel{
    thinkTime = 0.01,
    think = function(self)
        local doc = mod:GetDocumentSnapshot("drawsteel")
        if doc.data.finished then
            -- handle state
        end
    end,
}
```

*Source: `Draw_Steel_UI_bd58/DSInitiativeRoll.lua`*

## Common controls

| Control | Usage |
|---------|-------|
| `gui.Panel{}` | Container / layout |
| `gui.Label{}` | Text display |
| `gui.Input{}` | Text input field |
| `gui.Check{}` | Checkbox |
| `gui.Slider{}` | Slider control |

## Events between panels

Fire events to communicate between panels:

```lua
element:FireEvent("myEvent", data)          -- to self and parents
element:FireEventTree("myEvent", data)      -- to self and all children
```

## Further reading

The full control reference with every widget type and style property is in [UI_BEST_PRACTICES.md](https://github.com/VerisimLLC/draw-steel-codex/blob/main/UI_BEST_PRACTICES.md) in the repo root.

## Key points

- UI is **declarative** — construct trees of `gui.Panel{}` with nested children
- **Style** with `classes` and selector-based style tables (like CSS)
- **React to state** with `monitorGame`/`refreshGame` or `think` callbacks
- **Toggle classes** with `element:SetClass(name, bool)`
- **Communicate** between panels with `FireEvent` and `FireEventTree`

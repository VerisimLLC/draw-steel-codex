# UI & Panels

The Draw Steel Codex UI is organized into **dockable panels** (the sidebar tools a Director or player interacts with) and **HUD overlays** (the in-game heads-up display shown during play). Two module directories own this layer:

| Directory | Files | Purpose |
|---|---|---|
| `DMHub Core Panels/` | 50 Lua files | Sidebar panels -- Chat, Character, Map tools, Journal, Compendium, etc. |
| `DMHub Game Hud/` | 22 Lua files | In-game HUD -- action bar, initiative tracker, roll dialogs, macros |
| `ChatPanel/` | 3 Lua files | Chat subsystem split out (`ChatPanel.lua`, `ActionLogPanel.lua`, `InCharacterChat.lua`) |

---

## The DockablePanel System

Every sidebar panel registers itself through `DockablePanel.Register`. This call declares the panel's metadata and a factory function that builds its UI tree.

```lua
DockablePanel.Register {
    name = "Journal",
    icon = "icons/standard/Icon_App_Journal.png",
    vscroll = false,
    dmonly = false,
    minHeight = 160,
    content = function()
        return CreateJournalPanel()
    end,
}
```

| Field | Type | Purpose |
|---|---|---|
| `name` | string | Display name and lookup key |
| `icon` | string | Asset path for the tab icon |
| `dmonly` | boolean | If `true`, only the Director sees this panel |
| `vscroll` | boolean | Enable built-in vertical scrolling |
| `minHeight` | number | Minimum pixel height when docked |
| `content` | function | Factory that returns a `gui.Panel` tree |

The framework in `DMHub Core UI/DockablePanel.lua` manages two independent dock configurations -- one for players (`dockablepanelsplayer_v1`) and one for the Director (`dockablepanelsgm_v2`). It picks the right config at runtime via:

```lua
function GetDockablePanelsSetting()
    return cond(dmhub.isDM, dockablePanelsDMSetting, dockablePanelsPlayerSetting)
end
```

Both configs are stored as `pergamepreference` settings, so each game session can have its own panel layout.

---

## Major Panels at a Glance

| Panel file | Name | Notes |
|---|---|---|
| `CharacterPanel.lua` | Character | Registers two panels (player + DM views) |
| `Journal.lua` | Journal | Rich document browser; integrates with `DocumentSystem/` |
| `MapsPanel.lua` | Maps | Map list and import |
| `Objects.lua` | Objects | Token and object browser |
| `Terrain.lua` | Terrain | Registers 3 panels (terrain, walls, doors) |
| `DrawingPanel.lua` | Drawing | Freehand drawing tools |
| `Floors.lua` | Floors | Multi-floor management |
| `Weather.lua` | Weather | Weather effects control |
| `TimeOfDay.lua` | Time of Day | Lighting / time-of-day slider |
| `Audio.lua` | Audio | Ambient sound and music |
| `GameControls.lua` | Game Controls | Session-wide game settings |
| `GoblinScriptEditor.lua` | GoblinScript Editor | Formula editor and debugger |
| `AIPanel.lua` | AI Assistant | AI-powered content generation |

!!! tip "Finding a panel"
    Search for `DockablePanel.Register` across `DMHub Core Panels/` to get a complete list of every registered panel and its options.

---

## The Game HUD

Files in `DMHub Game Hud/` build the overlay that appears during active play. The central coordinator is `GameHud.lua`, which manages an **interaction queue** -- a FIFO of callbacks that fire only when the player is not mid-cast or in a modal dialog:

```lua
function GameHud:QueueInteraction(f)
    self.interactionQueue[#self.interactionQueue+1] = f
end
```

### Key HUD Files

| File | Purpose |
|---|---|
| `ActionBar.lua` | The bottom-of-screen ability bar |
| `InitiativeBar.lua` | Turn-order tracker |
| `RollDialog.lua` | Dice roll display and confirmation |
| `RollOnTableDialog.lua` | Random table roll popup |
| `RequireDCDialog.lua` | Difficulty-check prompt |
| `RestDialog.lua` | Rest / recovery dialog |
| `DeathScreen.lua` | Death / dying overlay |
| `Macros.lua` | Macro execution from the HUD |
| `ModalDialog.lua` | Generic modal dialog host |
| `RulerTool.lua` | Distance measurement overlay |
| `Keybinds.lua` | Keyboard shortcut registration |
| `Interactive.lua` / `InteractiveSign.lua` | Clickable map objects |
| `Journal.lua` | HUD-side journal quick-view |
| `FullscreenDisplay.lua` | Full-screen image / handout display |

!!! note "HUD vs. Panels"
    Panels live in the dockable sidebar and persist across scenes. HUD elements are transient overlays tied to the current gameplay moment (rolling dice, picking targets, viewing initiative).

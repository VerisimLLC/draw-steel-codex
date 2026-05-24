# Game Recorder Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a dockable developer panel in the Draw Steel Codex that drives the existing dev-only `recorder` global - manual start/stop/cancel, include-UI and audio toggles, advanced resolution/fps, live status, and one-click auto-recording of the current combat turn or round.

**Architecture:** A single new Lua file registers one `DockablePanel` (dev-gated). The panel reads/writes sticky `setting{}` preferences for its toggles, calls `recorder:BeginRecording/EndRecording/CancelRecording`, watches `monitorGame = "/initiativeQueue"` to auto-stop at the end of the current turn/round, and uses a `think` loop for the live `mm:ss` timer. While recording in include-UI mode it collapses to a small `REC` pill so it stays out of the captured frame. Lua-only - no engine/C# changes.

**Tech Stack:** Draw Steel Codex Lua (DMHub mod). UI via the `gui.*` framework; panels registered with `DockablePanel.Register`. No build step (Lua hot-reloads). State persists via `setting{ storage="preference" }`.

---

## IMPORTANT: verification model (read first)

This codebase has **no command-line test runner** - codex Lua is verified live in a running DMHub. Each task below ends with an **in-app verification** step instead of automated tests. Use the `dmhub` MCP tools:

- `mcp__dmhub__check_connection` / `mcp__dmhub__lua_status` - confirm DMHub is up and Lua loaded.
- `mcp__dmhub__reload_lua` - hot-reload the codex after editing a `.lua` file.
- `mcp__dmhub__get_console_log` - read Lua errors/prints (check after every reload).
- `mcp__dmhub__execute_lua` - run snippets to inspect/drive state (e.g. read `recorder.recording`, `dmhub.initiativeQueue`).
- `mcp__dmhub__inspect_ui` / `mcp__dmhub__screenshot_panel` / `mcp__dmhub__screenshot` - confirm the panel renders.

**Prerequisites for verification:** DMHub running in the Unity editor or an admin build (so the `recorder` global is non-nil), MCP connected. Opening the panel: in DMHub, open the **Development Tools** dock menu and select **Game Recorder** (the same menu that lists "Audio Dev", "Character Inspector", etc.). Truly confirming a captured MP4 (plays, has/omits audio) is a manual step called out where relevant.

**Codex constraints (apply to every task):**
- **ASCII only** in `.lua` files - no em dashes, curly quotes, or ellipses. Use `-`, `"`, `...`.
- **Forward-declare self-referencing locals** before a `gui.Panel` whose event handlers reference them.
- Every file starts with `local mod = dmhub.GetModLoading()`.
- Guard scheduled closures with `if mod.unloaded then return end`.

---

## File Structure

> **REVISION 2026-05-24 (host file changed):** Registering a brand-new Lua file through DMHub's mod system proved unreliable in this environment, so the feature is being implemented by **appending to `Development Utilities/DevTools.lua`** (already registered and loaded) instead of a new `GameRecorderPanel.lua`. **Everywhere a task below says `GameRecorderPanel.lua`, read `Development Utilities/DevTools.lua` (append to the END of the file).** Reuse DevTools.lua's existing `local mod = dmhub.GetModLoading()` and its `track(...)` helper - do NOT redefine them. **Task 1's file-creation/registration steps are obsolete**; instead append the Task 1 Step 2 skeleton (minus its own `local mod`/`track`) to the end of DevTools.lua.

| File | Responsibility |
|---|---|
| `Development Utilities/DevTools.lua` (**modify - append**) | The entire feature: settings, panel registration, recording control, auto-record monitor, REC pill. Appended after the existing "Development Info" panel; reuses the file's existing `mod` and `track`. |

No `main.lua` change and no new file - DevTools.lua is already required and loaded.

---

## Task 1: Create and register the file, with a minimal dev-gated panel

**Files:**
- Create: `Development Utilities/GameRecorderPanel.lua` (user creates + registers via DMHub)
- Modify: `main.lua` (user adds the `require`, in the Development Utilities block, after `DockablePanel` is available)

- [ ] **Step 1: USER creates and registers the file**

This step is performed by the user (Lisa) in DMHub, because new Lua files only load when registered through the DMHub module system. Ask the user to:
1. In DMHub, add a new Lua file named `GameRecorderPanel.lua` to the **Development Utilities** module (the same module that contains `AudioDev.lua`, `CharacterInspector.lua`, `DevTools.lua`).
2. Confirm a matching `require(...)` line was added to `main.lua` (it will look like the other Development Utilities requires, e.g. `require("Development Utilities_XXXX.GameRecorderPanel")` with that module's hex suffix), placed after the core UI / `DockablePanel` requires.

Do not proceed until the user confirms the file exists and `main.lua` requires it.

- [ ] **Step 2: Write the minimal panel content**

Replace the file's contents with:

```lua
local mod = dmhub.GetModLoading()

local function track(eventType, fields)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    fields.type = eventType
    fields.userid = dmhub.userid
    fields.gameid = dmhub.gameid
    fields.version = dmhub.version
    analytics.Event(fields)
end

local CreateGameRecorderPanel

DockablePanel.Register{
    name = "Game Recorder",
    icon = mod.images.chatIcon,
    minHeight = 200,
    vscroll = true,
    devonly = true,
    folder = "Development Tools",
    content = function()
        track("panel_open", {
            panel = "Game Recorder",
            dailyLimit = 30,
        })
        return CreateGameRecorderPanel()
    end,
}

CreateGameRecorderPanel = function()
    if recorder == nil then
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            gui.Label{
                width = "auto",
                height = "auto",
                halign = "left",
                fontSize = 14,
                color = "#cccccc",
                text = "Game Recorder is unavailable in this build (developer/admin only).",
            },
        }
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Label{
            width = "auto",
            height = "auto",
            halign = "left",
            fontSize = 16,
            bold = true,
            text = "Game Recorder",
        },
    }
end
```

- [ ] **Step 3: Reload and verify in-app**

Run (MCP): `mcp__dmhub__reload_lua`, then `mcp__dmhub__get_console_log`.
Expected: no Lua errors mentioning `GameRecorderPanel`.
Then open **Development Tools -> Game Recorder** in DMHub and run `mcp__dmhub__screenshot_panel` (panel name "Game Recorder").
Expected: a docked panel titled "Game Recorder" showing the heading label (or, in a non-dev build, the "unavailable" note).

- [ ] **Step 4: Commit**

```bash
cd "C:/MCDM/draw-steel-codex"
git add "Development Utilities/GameRecorderPanel.lua" main.lua
git commit -m "feat(recorder): register dev-gated Game Recorder panel skeleton"
```

---

## Task 2: Options zone with persisted Include-UI and Record-audio toggles

**Files:**
- Modify: `Development Utilities/GameRecorderPanel.lua`

- [ ] **Step 1: Add the setting objects**

Immediately after the `track` function and before `local CreateGameRecorderPanel`, add:

```lua
local g_includeUISetting = setting{
    id = "recorder:includeUI",
    description = "Game Recorder: include UI in capture",
    storage = "preference",
    default = true,
}

local g_audioSetting = setting{
    id = "recorder:audio",
    description = "Game Recorder: record audio",
    storage = "preference",
    default = true,
}
```

- [ ] **Step 2: Build the Options zone inside the panel**

Replace the body of `CreateGameRecorderPanel` (the part after the `recorder == nil` guard) with a vertical root panel that contains a labelled "Options" zone:

```lua
    local resultPanel

    local function OptionsZone()
        return gui.Panel{
            classes = {"recorder-zone"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            borderWidth = 1,
            borderColor = "#555555",
            cornerRadius = 6,
            pad = 8,
            borderBox = true,
            vmargin = 4,
            gui.Label{
                width = "auto",
                height = "auto",
                halign = "left",
                fontSize = 10,
                uppercase = true,
                color = "#999999",
                text = "Options",
            },
            gui.Check{
                text = "Include UI",
                value = g_includeUISetting:Get(),
                fontSize = 14,
                width = "auto",
                height = "auto",
                halign = "left",
                change = function(element)
                    g_includeUISetting:Set(element.value)
                end,
            },
            gui.Check{
                text = "Record audio",
                value = g_audioSetting:Get(),
                fontSize = 14,
                width = "auto",
                height = "auto",
                halign = "left",
                change = function(element)
                    g_audioSetting:Set(element.value)
                end,
            },
        }
    end

    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Label{
            width = "auto",
            height = "auto",
            halign = "left",
            fontSize = 16,
            bold = true,
            vmargin = 2,
            text = "Game Recorder",
        },
        OptionsZone(),
    }

    return resultPanel
```

- [ ] **Step 3: Reload and verify persistence**

Run (MCP): `mcp__dmhub__reload_lua`, `mcp__dmhub__get_console_log` (expect no errors), then `mcp__dmhub__screenshot_panel` ("Game Recorder").
Expected: an "Options" box with two checkboxes, both checked by default.
Then toggle "Record audio" off in the UI and verify it stuck:
Run (MCP): `mcp__dmhub__execute_lua` with `print(dmhub.GetSettingValue("recorder:audio"))`.
Expected: prints `false`. Re-open the panel (or reload) and confirm the checkbox is still unchecked.

- [ ] **Step 4: Commit**

```bash
cd "C:/MCDM/draw-steel-codex"
git add "Development Utilities/GameRecorderPanel.lua"
git commit -m "feat(recorder): persisted Include-UI and Record-audio toggles"
```

---

## Task 3: Status zone - manual Start/Stop/Cancel, live timer, last-saved footer

**Files:**
- Modify: `Development Utilities/GameRecorderPanel.lua`

This task adds the recording controller helpers and the status/footer UI. The helpers and UI are defined inside `CreateGameRecorderPanel` so they share its closure.

- [ ] **Step 1: Add state, helpers, and forward declarations at the top of the panel body**

Inside `CreateGameRecorderPanel`, after the `recorder == nil` guard and before `local function OptionsZone()`, add:

```lua
    -- transient recording state (panel-local; never serialized)
    local m_startTime = nil        -- os.time() at recording start, or nil when idle
    local m_lastSavedPath = nil    -- path from the last successful complete(path)
    local m_lastError = nil        -- last error message, shown until next start

    -- forward declarations for panels referenced by helpers/handlers
    local resultPanel

    local function BuildOptions()
        local options = {}
        options.ui = g_includeUISetting:Get()
        options.audio = g_audioSetting:Get()
        options.complete = function(path)
            m_lastSavedPath = path
            m_startTime = nil
        end
        options.error = function(msg)
            m_lastError = msg
            m_startTime = nil
        end
        return options
    end

    local function StartRecording()
        if recorder.recording then
            return
        end
        m_lastError = nil
        m_startTime = os.time()
        recorder:BeginRecording(BuildOptions())
    end

    local function StopAndSave()
        if not recorder.recording then
            return
        end
        recorder:EndRecording{
            complete = function(path)
                m_lastSavedPath = path
                m_startTime = nil
            end,
            error = function(msg)
                m_lastError = msg
                m_startTime = nil
            end,
        }
    end

    local function DiscardRecording()
        if not recorder.recording then
            return
        end
        recorder:CancelRecording()
        m_startTime = nil
    end

    local function FormatElapsed()
        if m_startTime == nil then
            return "00:00"
        end
        local secs = os.time() - m_startTime
        if secs < 0 then secs = 0 end
        return string.format("%02d:%02d", math.floor(secs / 60), secs % 60)
    end
```

- [ ] **Step 2: Add the Status zone and Footer builders**

Inside `CreateGameRecorderPanel`, after `OptionsZone` (or anywhere among the builder locals), add:

```lua
    local function StatusZone()
        return gui.Panel{
            classes = {"recorder-zone"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            borderWidth = 1,
            borderColor = "#aa3333",
            cornerRadius = 6,
            pad = 8,
            borderBox = true,
            vmargin = 4,
            halign = "center",

            -- live status line: "Idle" or "REC mm:ss"
            gui.Label{
                width = "auto",
                height = "auto",
                halign = "center",
                fontSize = 15,
                bold = true,
                color = "#dddddd",
                text = "Idle",
                thinkTime = 0.25,
                think = function(element)
                    if recorder.recording then
                        element.text = "REC  " .. FormatElapsed()
                        element.color = "#ee3344"
                    elseif m_lastError ~= nil then
                        element.text = "Error: " .. m_lastError
                        element.color = "#eebb33"
                    else
                        element.text = "Idle"
                        element.color = "#dddddd"
                    end
                end,
            },

            -- button row: Start (idle) / Stop + Cancel (recording)
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                vmargin = 4,

                gui.Button{
                    text = "Start Recording",
                    width = 150,
                    height = 30,
                    fontSize = 14,
                    hmargin = 4,
                    thinkTime = 0.25,
                    think = function(element)
                        element:SetClass("collapsed", recorder.recording)
                    end,
                    click = function()
                        StartRecording()
                    end,
                },
                gui.Button{
                    text = "Stop",
                    width = 80,
                    height = 30,
                    fontSize = 14,
                    hmargin = 4,
                    thinkTime = 0.25,
                    think = function(element)
                        element:SetClass("collapsed", not recorder.recording)
                    end,
                    click = function()
                        StopAndSave()
                    end,
                },
                gui.Button{
                    text = "Cancel",
                    width = 80,
                    height = 30,
                    fontSize = 14,
                    hmargin = 4,
                    thinkTime = 0.25,
                    think = function(element)
                        element:SetClass("collapsed", not recorder.recording)
                    end,
                    click = function()
                        DiscardRecording()
                    end,
                },
            },
        }
    end

    local function FooterZone()
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "center",
            vmargin = 4,
            gui.Label{
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                fontSize = 11,
                color = "#999999",
                maxWidth = 220,
                textWrap = false,
                text = "Last saved: (none yet)",
                think = function(element)
                    if m_lastSavedPath ~= nil then
                        element.text = "Last saved: " .. m_lastSavedPath
                    else
                        element.text = "Last saved: (none yet)"
                    end
                end,
                thinkTime = 0.5,
            },
            gui.Button{
                text = "Open folder",
                width = 90,
                height = 22,
                fontSize = 11,
                hmargin = 6,
                halign = "right",
                valign = "center",
                thinkTime = 0.5,
                think = function(element)
                    element:SetClass("collapsed", m_lastSavedPath == nil)
                end,
                click = function()
                    if m_lastSavedPath == nil then return end
                    local dir = string.match(m_lastSavedPath, "^(.*)[/\\][^/\\]*$")
                    if dir ~= nil then
                        -- NOTE: dmhub.OpenURL is domain-restricted; a file:// URL may be
                        -- rejected. If this button does nothing, leave the footer purely
                        -- informational - the engine already reveals the Recordings folder
                        -- in the OS file browser when a recording is saved. See the spec's
                        -- Open Questions (section 9).
                        dmhub.OpenURL("file://" .. dir)
                    end
                end,
            },
        }
    end
```

- [ ] **Step 3: Add the new zones to the root panel**

Update the `resultPanel = gui.Panel{ ... }` children list to include the status zone (above options) and the footer (below options):

```lua
    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Label{
            width = "auto",
            height = "auto",
            halign = "left",
            fontSize = 16,
            bold = true,
            vmargin = 2,
            text = "Game Recorder",
        },
        StatusZone(),
        OptionsZone(),
        FooterZone(),
    }
```

- [ ] **Step 4: Reload and verify start/stop**

Run (MCP): `mcp__dmhub__reload_lua`, `mcp__dmhub__get_console_log` (expect no errors).
Open the panel, click **Start Recording**, then `mcp__dmhub__screenshot_panel` ("Game Recorder").
Expected: status shows `REC mm:ss` counting up; Start hides, Stop + Cancel appear.
Run (MCP): `mcp__dmhub__execute_lua` with `print(recorder.recording)` -> expect `true`.
Click **Stop**; screenshot again. Expected: status returns to "Idle", footer shows `Last saved: .../Recordings/recording-....mp4`.
**Manual:** open that MP4 and confirm it plays.
Then test discard: Start, click **Cancel**, confirm `recorder.recording` is `false` and no new file was written.

- [ ] **Step 5: Commit**

```bash
cd "C:/MCDM/draw-steel-codex"
git add "Development Utilities/GameRecorderPanel.lua"
git commit -m "feat(recorder): manual start/stop/cancel with live timer and last-saved footer"
```

---

## Task 4: Advanced expander - fps / width / height overrides

**Files:**
- Modify: `Development Utilities/GameRecorderPanel.lua`

- [ ] **Step 1: Add the advanced setting objects**

Next to the other settings (after `g_audioSetting`), add three string-valued preferences (empty string = "use engine default"):

```lua
local g_fpsSetting = setting{
    id = "recorder:fps",
    description = "Game Recorder: fps override (blank = default)",
    storage = "preference",
    default = "",
}

local g_widthSetting = setting{
    id = "recorder:width",
    description = "Game Recorder: width override (blank = default)",
    storage = "preference",
    default = "",
}

local g_heightSetting = setting{
    id = "recorder:height",
    description = "Game Recorder: height override (blank = default)",
    storage = "preference",
    default = "",
}
```

- [ ] **Step 2: Feed the overrides into BuildOptions**

In `BuildOptions` (Task 3, Step 1), before `return options`, add parsing that only sets a field when the user entered a positive number:

```lua
        local fps = tonumber(g_fpsSetting:Get())
        if fps ~= nil and fps > 0 then
            options.fps = math.floor(fps)
        end
        local width = tonumber(g_widthSetting:Get())
        if width ~= nil and width > 0 then
            options.width = math.floor(width)
        end
        local height = tonumber(g_heightSetting:Get())
        if height ~= nil and height > 0 then
            options.height = math.floor(height)
        end
```

- [ ] **Step 3: Add the collapsible Advanced zone builder**

Add this builder inside `CreateGameRecorderPanel` (among the other builders). It uses a clickable header that toggles a `collapsed` class on the fields panel. Forward-declare `fieldsPanel` so the header's click handler can reference it:

```lua
    local function AdvancedZone()
        local fieldsPanel

        local function NumberInput(labelText, settingObj)
            return gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                valign = "center",
                vmargin = 2,
                gui.Label{
                    text = labelText,
                    width = 70,
                    height = "auto",
                    halign = "left",
                    fontSize = 13,
                    color = "#cccccc",
                },
                gui.Input{
                    width = 80,
                    height = 20,
                    fontSize = 13,
                    halign = "left",
                    placeholderText = "default",
                    text = settingObj:Get(),
                    characterLimit = 5,
                    editlag = 0.2,
                    edit = function(element)
                        settingObj:Set(element.text)
                    end,
                },
            }
        end

        fieldsPanel = gui.Panel{
            classes = {"collapsed"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            NumberInput("FPS", g_fpsSetting),
            NumberInput("Width", g_widthSetting),
            NumberInput("Height", g_heightSetting),
        }

        return gui.Panel{
            classes = {"recorder-zone"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            borderWidth = 1,
            borderColor = "#555555",
            cornerRadius = 6,
            pad = 8,
            borderBox = true,
            vmargin = 4,
            gui.Label{
                width = "auto",
                height = "auto",
                halign = "left",
                fontSize = 12,
                color = "#bbbbbb",
                text = "> Advanced",
                data = { expanded = false },
                click = function(element)
                    element.data.expanded = not element.data.expanded
                    element.text = (element.data.expanded and "v Advanced") or "> Advanced"
                    fieldsPanel:SetClass("collapsed", not element.data.expanded)
                end,
            },
            fieldsPanel,
        }
    end
```

- [ ] **Step 4: Add AdvancedZone to the root panel**

Insert `AdvancedZone(),` into the `resultPanel` children list, after `OptionsZone(),` and before `FooterZone(),`.

- [ ] **Step 5: Reload and verify**

Run (MCP): `mcp__dmhub__reload_lua`, `mcp__dmhub__get_console_log` (expect no errors).
Open the panel; click **> Advanced**; screenshot. Expected: the FPS/Width/Height inputs appear; clicking again collapses them.
Set FPS to `60`, then verify it is passed through: run `mcp__dmhub__execute_lua` with:
```lua
print(dmhub.GetSettingValue("recorder:fps"))
```
Expected: prints `60`. Clear the field and confirm it prints an empty string (so the option is omitted and the engine default applies).

- [ ] **Step 6: Commit**

```bash
cd "C:/MCDM/draw-steel-codex"
git add "Development Utilities/GameRecorderPanel.lua"
git commit -m "feat(recorder): advanced fps/width/height overrides"
```

---

## Task 5: REC pill - collapse the panel while recording with UI on

**Files:**
- Modify: `Development Utilities/GameRecorderPanel.lua`

Goal: when recording starts with Include-UI on, hide the full panel body and show a small `REC mm:ss` + Stop pill, so the panel does not appear large in the captured frame. Restore on stop/cancel.

- [ ] **Step 1: Track UI mode and wrap the body in a referenced panel**

In the state block (Task 3, Step 1), add a flag recording whether the current capture includes UI:

```lua
    local m_recordingWithUI = false
```

In `StartRecording`, set it from the option just before `BeginRecording`:

```lua
        m_recordingWithUI = g_includeUISetting:Get()
```

Forward-declare the body and pill panels with the other forward declarations:

```lua
    local m_bodyPanel
    local m_pillPanel
```

- [ ] **Step 2: Add the RecPill builder**

Add inside `CreateGameRecorderPanel`:

```lua
    local function RecPill()
        m_pillPanel = gui.Panel{
            classes = {"collapsed"},
            width = "auto",
            height = "auto",
            flow = "horizontal",
            valign = "center",
            halign = "center",
            borderWidth = 1,
            borderColor = "#aa3333",
            bgcolor = "#000000aa",
            cornerRadius = 6,
            pad = 6,
            borderBox = true,
            gui.Label{
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                fontSize = 14,
                bold = true,
                color = "#ee3344",
                text = "REC  00:00",
                hmargin = 4,
                thinkTime = 0.25,
                think = function(element)
                    element.text = "REC  " .. FormatElapsed()
                end,
            },
            gui.Button{
                text = "Stop",
                width = 70,
                height = 26,
                fontSize = 13,
                hmargin = 4,
                click = function()
                    StopAndSave()
                end,
            },
        }
        return m_pillPanel
    end
```

- [ ] **Step 3: Wrap existing zones in a body panel and drive the collapse**

Change the root so the heading/status/options/advanced/footer live inside `m_bodyPanel`, and the root holds both the body and the pill plus a `think` that swaps them:

```lua
    m_bodyPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Label{
            width = "auto",
            height = "auto",
            halign = "left",
            fontSize = 16,
            bold = true,
            vmargin = 2,
            text = "Game Recorder",
        },
        StatusZone(),
        OptionsZone(),
        AdvancedZone(),
        FooterZone(),
    }

    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        thinkTime = 0.25,
        think = function(element)
            local collapsedToPill = recorder.recording and m_recordingWithUI
            m_bodyPanel:SetClass("collapsed", collapsedToPill)
            m_pillPanel:SetClass("collapsed", not collapsedToPill)
        end,
        RecPill(),
        m_bodyPanel,
    }

    return resultPanel
```

- [ ] **Step 4: Reload and verify**

Run (MCP): `mcp__dmhub__reload_lua`, `mcp__dmhub__get_console_log` (expect no errors).
Ensure "Include UI" is checked. Click **Start Recording**; `mcp__dmhub__screenshot_panel` ("Game Recorder").
Expected: the full body is hidden and only the `REC mm:ss` + Stop pill shows. Click **Stop** on the pill; screenshot. Expected: the full panel body returns.
Uncheck "Include UI", Start again; expected: the body stays visible (board-only capture is not in frame, so no need to hide). Stop.

- [ ] **Step 5: Commit**

```bash
cd "C:/MCDM/draw-steel-codex"
git add "Development Utilities/GameRecorderPanel.lua"
git commit -m "feat(recorder): collapse to REC pill while recording with UI"
```

---

## Task 6: Auto-record the current turn or round

**Files:**
- Modify: `Development Utilities/GameRecorderPanel.lua`

Semantics: clicking a button starts recording immediately and auto-stops at the END of the current turn/round. No retroactive capture. Buttons are disabled outside combat.

- [ ] **Step 1: Add combat/initiative helpers and auto-stop state**

In the **state block** (Task 3, Step 1 - above the helpers), add the auto-record state:

```lua
    local m_autoScope = nil        -- nil | "turn" | "round"
    local m_autoBaselineId = nil   -- the turn-id or round-id captured at start
```

`StopAndSave` and `DiscardRecording` (defined in Task 3) call `ClearAuto`, which is defined below them. In Lua a `local function` is only visible after its definition, so `ClearAuto` MUST be **forward-declared** before those functions or the call resolves to a nil global at runtime. Add this forward declaration alongside the other forward declarations (next to `local resultPanel` / `local m_bodyPanel` / `local m_pillPanel`, i.e. ABOVE `BuildOptions`):

```lua
    local ClearAuto
```

Then add these helpers among the other helpers. Note `ClearAuto` is an **assignment** (no `local`, since it was forward-declared); the rest are new locals:

```lua
    local function CombatActive()
        local q = dmhub.initiativeQueue
        return q ~= nil and (not q.hidden) and q.gameMode == "combat"
    end

    local function CurrentTurnId()
        local q = dmhub.initiativeQueue
        if q == nil then return nil end
        return q:GetTurnId()
    end

    local function CurrentRoundId()
        local q = dmhub.initiativeQueue
        if q == nil then return nil end
        return q:GetRoundId()
    end

    local function StartAuto(scope)
        if recorder.recording or not CombatActive() then
            return
        end
        m_autoScope = scope
        if scope == "round" then
            m_autoBaselineId = CurrentRoundId()
        else
            m_autoBaselineId = CurrentTurnId()
        end
        StartRecording()
    end

    ClearAuto = function()
        m_autoScope = nil
        m_autoBaselineId = nil
    end
```

- [ ] **Step 2: Clear auto-scope on manual stop/cancel**

Replace the Task 3 `StopAndSave` and `DiscardRecording` functions with these versions, which clear the auto-scope first so manually stopping an auto-recording does not leave a stale scope:

```lua
    local function StopAndSave()
        ClearAuto()
        if not recorder.recording then
            return
        end
        recorder:EndRecording{
            complete = function(path)
                m_lastSavedPath = path
                m_startTime = nil
            end,
            error = function(msg)
                m_lastError = msg
                m_startTime = nil
            end,
        }
    end

    local function DiscardRecording()
        ClearAuto()
        if not recorder.recording then
            return
        end
        recorder:CancelRecording()
        m_startTime = nil
    end
```

- [ ] **Step 3: Add the AutoRecordZone builder**

```lua
    local function AutoRecordZone()
        return gui.Panel{
            classes = {"recorder-zone"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            borderWidth = 1,
            borderColor = "#555555",
            cornerRadius = 6,
            pad = 8,
            borderBox = true,
            vmargin = 4,
            gui.Label{
                width = "auto",
                height = "auto",
                halign = "left",
                fontSize = 10,
                uppercase = true,
                color = "#999999",
                text = "Auto-record (combat)",
            },
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "left",
                vmargin = 2,
                gui.Button{
                    text = "Record this turn",
                    width = 130,
                    height = 28,
                    fontSize = 13,
                    hmargin = 4,
                    thinkTime = 0.25,
                    think = function(element)
                        element:SetClass("disabled", recorder.recording or not CombatActive())
                    end,
                    click = function(element)
                        if element:HasClass("disabled") then return end
                        StartAuto("turn")
                    end,
                },
                gui.Button{
                    text = "Record this round",
                    width = 140,
                    height = 28,
                    fontSize = 13,
                    hmargin = 4,
                    thinkTime = 0.25,
                    think = function(element)
                        element:SetClass("disabled", recorder.recording or not CombatActive())
                    end,
                    click = function(element)
                        if element:HasClass("disabled") then return end
                        StartAuto("round")
                    end,
                },
            },
            gui.Label{
                width = "100%",
                height = "auto",
                halign = "left",
                fontSize = 10,
                color = "#777777",
                text = "",
                thinkTime = 0.5,
                think = function(element)
                    if not CombatActive() then
                        element.text = "Start combat to enable auto-record."
                    elseif m_autoScope ~= nil then
                        element.text = "Auto-recording this " .. m_autoScope .. "; stops at its end."
                    else
                        element.text = ""
                    end
                end,
            },
        }
    end
```

- [ ] **Step 4: Add the initiative monitor + AutoRecordZone to the root panel**

Add `monitorGame` and `refreshGame` to `resultPanel` (the root from Task 5), and add `AutoRecordZone()` into `m_bodyPanel` (after `OptionsZone()` / `AdvancedZone()`):

```lua
    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        monitorGame = "/initiativeQueue",
        refreshGame = function(element)
            if m_autoScope == nil or not recorder.recording then
                return
            end
            local currentId
            if m_autoScope == "round" then
                currentId = CurrentRoundId()
            else
                currentId = CurrentTurnId()
            end
            -- stop when the turn/round boundary changes, or combat ends
            if (not CombatActive()) or currentId == nil or currentId ~= m_autoBaselineId then
                StopAndSave()
            end
        end,
        thinkTime = 0.25,
        think = function(element)
            local collapsedToPill = recorder.recording and m_recordingWithUI
            m_bodyPanel:SetClass("collapsed", collapsedToPill)
            m_pillPanel:SetClass("collapsed", not collapsedToPill)
        end,
        RecPill(),
        m_bodyPanel,
    }
```

`m_bodyPanel` children become: heading, `StatusZone()`, `OptionsZone()`, `AdvancedZone()`, `AutoRecordZone()`, `FooterZone()`.

- [ ] **Step 5: Reload and verify (requires an active combat)**

Run (MCP): `mcp__dmhub__reload_lua`, `mcp__dmhub__get_console_log` (expect no errors).
Outside combat: open the panel, screenshot - expect both auto-record buttons greyed/disabled and the hint "Start combat to enable auto-record."
Confirm the monitor path is firing: with the panel open during combat, run `mcp__dmhub__execute_lua`:
```lua
local q = dmhub.initiativeQueue
print("active", q ~= nil and (not q.hidden) and q.gameMode == "combat")
if q ~= nil then print("turnId", q:GetTurnId(), "roundId", q:GetRoundId()) end
```
Expected: `active true` and non-nil ids during a live combat turn.
In combat: click **Record this turn** - expect recording starts immediately. Advance the turn in DMHub (end the current turn). Expected: recording auto-stops and the footer shows a new saved file. Repeat with **Record this round** across a full round.
If the boundary does not trigger, verify the monitor path: the research identified `"/initiativeQueue"`; if `refreshGame` never fires, try monitoring the storage path instead and re-test (see Open Questions in the spec).

- [ ] **Step 6: Commit**

```bash
cd "C:/MCDM/draw-steel-codex"
git add "Development Utilities/GameRecorderPanel.lua"
git commit -m "feat(recorder): auto-record current turn or round via initiative monitor"
```

---

## Task 7: Lifecycle hardening - save on panel teardown, unloaded guards

**Files:**
- Modify: `Development Utilities/GameRecorderPanel.lua`

- [ ] **Step 1: Save an in-progress recording if the panel is destroyed**

Add a `destroy` handler to `resultPanel` so closing/undocking the panel mid-recording does not leak an open recording. Add this field to the root `gui.Panel{ ... }` (alongside `think`/`refreshGame`):

```lua
        destroy = function(element)
            if recorder ~= nil and recorder.recording then
                ClearAuto()
                recorder:EndRecording{
                    complete = function(path) end,
                    error = function(msg) end,
                }
            end
        end,
```

- [ ] **Step 2: Guard the panel build against a torn-down module**

This panel uses only synchronous handlers, but if any deferred scheduling is added later it must guard on `mod.unloaded`. Add a comment marker and a defensive guard at the top of `CreateGameRecorderPanel` (after the `recorder == nil` check):

```lua
    -- All recorder calls below are guarded by recorder ~= nil (checked above).
    -- Any future dmhub.Schedule(...) closures MUST start with: if mod.unloaded then return end
```

- [ ] **Step 3: Reload and verify teardown saves**

Run (MCP): `mcp__dmhub__reload_lua`, `mcp__dmhub__get_console_log` (expect no errors).
Start a recording (Include UI on or off). While `recorder.recording` is `true`, close the Game Recorder panel (or undock + close it) in DMHub.
Run (MCP): `mcp__dmhub__execute_lua` with `print(recorder.recording)` -> expect `false` (recording was finalized, not left open).
**Manual:** confirm a new MP4 exists in the Recordings folder.
Re-open the panel and confirm no console errors and normal idle state.

- [ ] **Step 4: Commit**

```bash
cd "C:/MCDM/draw-steel-codex"
git add "Development Utilities/GameRecorderPanel.lua"
git commit -m "feat(recorder): finalize recording on panel teardown; harden guards"
```

---

## Final verification (maps to spec section 8)

Run through the spec's verification list end to end in one session:

1. Panel appears under Development Tools; shows the unavailable note when `recorder` is nil (non-dev build).
2. Start -> Stop yields a playable MP4 in `Recordings/`; footer shows the filename.
3. Include-UI off -> board-only (no overlay UI); on -> overlay UI present.
4. Audio toggle: `ffmpeg -i clip.mp4` shows an audio stream when on, none when off.
5. Advanced FPS/resolution honored; cleared -> engine defaults.
6. "Record this turn" / "Record this round" bracket exactly one turn / round.
7. Auto-record buttons disabled outside combat.
8. REC pill replaces the body while recording with UI on; restores on stop.
9. Cancel discards (no new file).
10. Closing the panel mid-recording finalizes (saves) the recording.

## Notes for the executing engineer

- **Styling is approximate.** Colors/margins above are reasonable defaults; match `DefaultStyles.md` / sibling dev panels (`AudioDev.lua`, `CharacterInspector.lua`) where the codebase has established tokens (e.g. `Styles.Cream03`). The `disabled` and `collapsed` classes are standard gui classes; confirm `disabled` dims the button as expected, otherwise dim manually via `element:SetClass` + a style.
- **`monitorGame = "/initiativeQueue"`** is from research and is the one open risk; Task 6 Step 5 includes a fallback check. No codex panel currently uses this path, so verify it fires before relying on it.
- **`os.time()`** gives 1-second timer resolution, which is fine for a recording clock. Do not switch to a higher-resolution engine clock unless needed.
- Keep everything ASCII; run `mcp__dmhub__get_console_log` after every reload - a non-ASCII byte or a forward-reference mistake will show up there immediately.

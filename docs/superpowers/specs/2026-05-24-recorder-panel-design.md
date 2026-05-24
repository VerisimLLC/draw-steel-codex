# Game Recorder Panel - Design Spec

**Date:** 2026-05-24
**Status:** Approved design, pending implementation plan
**Repo:** `draw-steel-codex` (Lua only - no engine build)
**Builds on:**
- `dmhubclient/docs/superpowers/specs/2026-05-23-dev-turn-recorder-design.md` (the `recorder` primitive; this panel is its section 11 "player-facing clip UI" + "auto turn-bracketing" follow-ups)
- `dmhubclient/docs/superpowers/specs/2026-05-24-recorder-audio-design.md` (the `audio` option)

## 1. Goal & Scope

Give developers a dockable on-screen window to drive the existing dev-only `recorder` global, instead of only the F9 hotkey / raw Lua calls. Add the ability to auto-bracket a recording to the current combat turn or round.

Everything here is **Lua-only**, built on the recorder API that already ships. No C# / engine changes.

### In scope
- A dockable dev panel ("Game Recorder", `folder = "Development Tools"`, `devonly = true`).
- **Manual capture:** Start / Stop / Cancel.
- **Include UI** toggle -> `ui` option (full-screen composited vs board-only).
- **Record audio** toggle -> `audio` option (full mix on/off).
- **Advanced** expander (collapsed by default): resolution (`width`/`height`) and `fps` overrides; when untouched, the engine defaults apply.
- **Live status:** idle vs `REC mm:ss` elapsed, driven by `recorder.recording`.
- **Last saved:** read-only path from the `complete(path)` callback + an "Open folder" affordance (the engine already reveals the Recordings folder on save).
- **Auto-record:** "Record this turn" / "Record this round" - start immediately, auto-stop at the end of the current turn / round.
- **REC pill:** while recording with Include-UI on, the panel collapses to a small draggable `REC mm:ss` + Stop pill so it does not dominate the captured frame; it restores on stop.

### Out of scope (future, each needs an engine change -> separate spec)
- **Custom save path / output directory** - the engine hardcodes `<persistentDataPath>/Recordings/` and exposes no Lua binary-file move; redirecting output needs a C# `outputDir` option.
- **Screen-region (cropped) capture** - no crop/viewport mechanism exists in the recorder; needs a C# change.
- **Per-category audio selection** (music vs SFX vs dice) - the listener only exposes the full mix; needs C# mixer routing (already deferred by the audio spec).
- **Retroactive / ring-buffer capture** ("save the last N seconds") - the semantics in section 5 start at the moment of click; no go-back.

## 2. Background - what already exists

- **`recorder` global** (developer-only; present in the editor and admin builds, `nil` otherwise). Shipped API (per `draw-steel-codex/Definitions/GameRecorderLua.lua` + the audio spec):
  ```lua
  recorder:BeginRecording{ ui=true, audio=true, fps=30, width=nil, height=nil,
                           complete=function(path) end, error=function(msg) end }
  recorder:EndRecording{ complete=function(path) end, error=function(msg) end }
  recorder:CancelRecording()
  local active = recorder.recording   -- read-only bool
  ```
  Saves `recording-<timestamp>.mp4` to `<persistentDataPath>/Recordings/` and reveals the folder. A second concurrent `BeginRecording` is a no-op in the engine. There is no Lua consumer of `recorder` today; this panel is the first.
- **`DockablePanel.Register`** is the panel registration idiom. Reference dev panels: `Development Utilities/AudioDev.lua`, `CharacterInspector.lua`, `RandomTestPanel.lua`, `DevTools.lua`. The `devonly = true` flag plus `folder = "Development Tools"` is the standard dev gate + grouping. Each uses the local `track("panel_open", {...})` telemetry helper.
- **Initiative / turn / round state** lives in the shared per-map game document. From Lua: `dmhub.initiativeQueue` (nil outside combat) with `round` (number), `currentTurn` (initiative-id or `false`), and stable change keys `GetTurnId()` -> `"<guid>-<round>-<currentTurn>-<turnsTaken>"` and `GetRoundId()` -> `"<guid>-<round>"`. Combat is "active" only when the queue is non-nil, `not hidden`, and `gameMode == "combat"`. A UI panel observes changes via `monitorGame = "/initiativeQueue"` -> `refreshGame` (fires on every client for every turn/round transition). Confirmed against `MCDMInitiativeQueue.lua` and the engine patch handler.
- **Settings** persist via `setting{ id=..., storage="preference", default=... }`.

## 3. Components

All in a single new file (per the codex no-new-files rule, the user creates and registers it).

| Component | Where | Role |
|---|---|---|
| New file `GameRecorderPanel.lua` | `Development Utilities/` | Hosts the panel registration and all panel logic. Registered in `main.lua` in the Development Utilities block (user does this). |
| `DockablePanel.Register{ name = "Game Recorder", ... }` | same file | `devonly = true`, `folder = "Development Tools"`. `content` returns the root panel. |
| Root panel | same file | Owns transient recording/auto-record state, the `think` status loop, and the `monitorGame` initiative watch. |
| Sticky settings | same file | `recorder:includeUI` and `recorder:audio` (both `storage = "preference"`, default `true`); optionally `recorder:fps`, `recorder:width`, `recorder:height` for the Advanced expander. |

No engine code, no new `Definitions/` stub (the `recorder` stub already exists).

## 4. Panel UI (layout: "Grouped zones")

Vertical flow of labelled zones (matches the approved mockup):

1. **Status zone** (border emphasised while active):
   - Idle: a primary "Start Recording" button.
   - Recording: `REC mm:ss` (live), a **Stop** button (save) and a **Cancel** button (discard).
2. **Options zone:**
   - "Include UI" checkbox -> `includeUI` setting.
   - "Record audio" checkbox -> `audio` setting.
   - **Advanced** disclosure (collapsed): FPS input + width/height inputs. Empty/unchanged -> omit from the options table so engine defaults apply.
3. **Auto-record (combat) zone:**
   - "Record this turn" and "Record this round" buttons.
   - Disabled (greyed, non-interactive) when combat is not active. A short hint explains why when disabled.
4. **Footer:** `Last saved: <filename>` (from the last `complete(path)`), with an "Open folder" affordance. Empty until the first save this session.

### REC pill (Include-UI captures)
When recording starts with `includeUI == true`, the panel body collapses to a compact draggable pill showing `REC mm:ss` + a Stop button, so the panel does not fill the captured frame. On stop/cancel the panel restores to full layout. With `includeUI == false` (board-only capture, panel not in frame) the panel may stay expanded; collapsing is harmless either way, so the pill behaviour keys off `includeUI`.

## 5. Auto-record (current turn / current round)

**Semantics (corrected):** start *now*, stop at the end of the current unit.

- **Record this turn:** on click, snapshot `id0 = queue:GetTurnId()`, call the normal start path immediately, and mark auto-stop scope = "turn". When `monitorGame` `refreshGame` fires and `queue:GetTurnId() ~= id0` (the turn changed) - or the queue becomes inactive (nil / hidden / non-combat) or `currentTurn == false` - stop and save.
- **Record this round:** identical, snapshotting `GetRoundId()`; stop when `GetRoundId()` changes (round incremented) or combat goes inactive.
- No "armed and waiting" state - recording is live from the click. Manual **Stop**/**Cancel** still work and clear the auto-stop scope.
- The auto-record buttons are disabled unless combat is active at click time.

**Detection:** a sub-panel (or the root panel) carries `monitorGame = "/initiativeQueue"`; its `refreshGame` reads `dmhub.initiativeQueue`, compares the stored snapshot id against the current id, and triggers the stop when they differ. **Monitoring is panel-scoped** - it only runs while the panel is open/docked. Acceptable: you have the panel open to use the recorder. If the panel is closed mid-auto-recording, treat teardown like a normal stop-and-save (see section 6).

## 6. Lifecycle & error handling

- **Start while recording** -> no-op (engine also guards); reflect the already-active state in the status zone.
- **Stop / Cancel with nothing active** -> no-op.
- **`recorder == nil`** (non-dev build, or recorder unavailable) -> panel shows an "unavailable in this build" note and renders no controls. Guard every call site with `recorder ~= nil`.
- **`error(msg)` callback** -> surface the message in the status zone and reset to idle; never leave the status stuck on `REC`.
- **Combat ends mid-auto-recording** (queue becomes nil / hidden / leaves combat) -> stop and save; clear auto-stop scope.
- **Panel closed / unloaded mid-recording** -> on the panel's destroy/teardown, if a recording is active, end-and-save (do not silently leak an open recording). Guard scheduled closures with `mod.unloaded`.
- **Timer** -> derive elapsed from a start timestamp captured at begin; the `think` loop formats `mm:ss`. Do not assume `think` cadence is exact.

## 7. Settings & persistence

- `recorder:includeUI` (preference, default true), `recorder:audio` (preference, default true).
- Advanced: `recorder:fps`, `recorder:width`, `recorder:height` (preference; empty = use engine defaults). Only include a field in the options table when the user has set it.
- Toggles persist across sessions; recording/auto-record state is transient (panel-local, not serialized).

## 8. Verification (manual - capture is not unit-testable)

1. Open the panel (editor or admin build); confirm it appears under Development Tools and is absent / shows the unavailable note when `recorder` is nil.
2. Start -> Stop produces a playable MP4 in `Recordings/`; the footer shows the filename and Open folder reveals it.
3. Toggle Include UI off -> recording is board-only (no overlay UI); on -> overlay UI present.
4. Toggle Record audio: `ffmpeg -i clip.mp4` shows an audio stream when on, none when off.
5. Advanced: set FPS/resolution -> output reflects them; cleared -> engine defaults.
6. During combat, "Record this turn" starts immediately and auto-stops at the end of that turn (one turn captured); same for "Record this round" across one round.
7. Outside combat, the auto-record buttons are disabled.
8. While recording with Include UI on, the panel collapses to the REC pill and restores on stop.
9. Cancel discards without saving (no new file).
10. Close the panel mid-recording -> the in-progress recording is saved, not leaked.

## 9. Open implementation questions (resolve in the plan)

- Exact "Open folder" affordance from Lua (the engine already reveals the folder on save; confirm whether a re-reveal is callable from Lua, otherwise the footer is informational + relies on the save-time reveal).
- Whether the REC pill should be draggable within the docked panel or float; pick the simplest that keeps it out of the captured frame.
- Confirm the disabled-state styling/idiom for the auto-record buttons matches other codex panels.

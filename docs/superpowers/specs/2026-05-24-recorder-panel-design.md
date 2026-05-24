# Game Recorder Panel - Design Spec

**Date:** 2026-05-24
**Status:** Approved design, pending implementation plan
**Repo:** `draw-steel-codex` (Lua only - no engine build)
**Builds on:**
- `dmhubclient/docs/superpowers/specs/2026-05-23-dev-turn-recorder-design.md` (the `recorder` primitive; this panel is its section 11 "player-facing clip UI" + "auto turn-bracketing" follow-ups)
- `dmhubclient/docs/superpowers/specs/2026-05-24-recorder-audio-design.md` (the `audio` option)

> **As-built revision (2026-05-24):** Implemented and shipped. Notable changes from the original design: (1) the panel was appended to `Development Utilities/DevTools.lua` rather than a new file (registering a new codex file via DMHub's mod UI proved unreliable - see the plan's revision note); (2) the Include-UI / Record-audio toggles use a custom `[X]`/`[ ]` clickable row instead of `gui.Check` (the default checkbox state was not legible); (3) auto-record now takes a **Count** of turns/rounds (see section 5), generalizing the original "this turn/round"; (4) button show/hide is driven by rebuilding a parent panel's children, because a `think` / `SetClass("collapsed")` placed directly on a `gui.Button` did not reliably toggle visibility; (5) the engine's on-screen "REC" overlay (`GameRecorder.cs` OnGUI) was removed as a small companion C# change - committed and pushed, but not yet built (the engine has unrelated pre-existing compile errors).

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
- **Auto-record:** a **Count** field (default 1) plus "Record turns" / "Record rounds" buttons. Records from the moment of click until that many turn/round *ends* (1 = until the current turn/round ends). If no turn is active yet, recording starts and the status shows "Waiting for a turn to start..."; auto-stops after the Nth end, or if combat ends.
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
   - A **Count** number input (default 1) and "Record turns" / "Record rounds" buttons that record that many turn/round ends.
   - When combat is not active, the buttons are replaced by a hint ("Start combat to enable auto-record."). A live status line shows "Waiting for a turn to start..." or "Auto-recording: N turns/rounds remaining." while active.
4. **Footer:** `Last saved: <filename>` (from the last `complete(path)`), with an "Open folder" affordance. Empty until the first save this session.

### REC pill (Include-UI captures)
When recording starts with `includeUI == true`, the panel body collapses to a compact draggable pill showing `REC mm:ss` + a Stop button, so the panel does not fill the captured frame. On stop/cancel the panel restores to full layout. With `includeUI == false` (board-only capture, panel not in frame) the panel may stay expanded; collapsing is harmless either way, so the pill behaviour keys off `includeUI`.

## 5. Auto-record (count of turns / rounds)

**Semantics:** record from the moment of click until N turn (or round) *ends*. The **Count** input (default 1) sets N; 1 = until the current turn/round ends.

- **Record turns / Record rounds:** on click, capture the current `GetTurnId()` (or `GetRoundId()`) as the last-seen id, set the remaining-ends counter to N, and start recording immediately.
- **Counting ends:** each time the observed id changes *away from a non-nil value*, one turn/round has ended -> decrement the counter. A `nil -> id` transition is a turn/round *starting* (the wait-for-turn case) and is NOT counted. When the counter reaches 0, stop and save. If combat goes inactive (queue nil / hidden / non-combat), stop and save whatever was captured.
- **Wait-for-turn:** if no turn is active at click time (`GetTurnId()` is nil, e.g. the choosing-turn moment), recording still starts from now and the status shows "Waiting for a turn to start..."; counting begins once a real turn is in progress. (Round-ids are always non-nil during combat, so rounds never wait.) This also avoids the zero-length-recording save error that an instant nil-baseline stop would cause.
- Manual **Stop**/**Cancel** clear the auto counter. The auto-record buttons exist only while combat is active.

**Detection:** the root panel carries `monitorGame = "/initiativeQueue"` (its `refreshGame` runs the end-check immediately on any turn/round change) AND runs the same check from its `think` loop (~0.25s) as a reliable safety net, since the `monitorGame` path was not independently verified. Both call one shared `CheckAutoStop` helper. **Monitoring is panel-scoped** - it runs while the panel is open/docked. If the panel is closed mid-recording, teardown does a normal stop-and-save (see section 6).

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
6. During combat, set Count=1 and "Record turns" -> records until the current turn ends; Count=2 -> until two turn-ends. "Record rounds" stops at round-ends. Clicking with no active turn shows "Waiting for a turn to start..." then records the turn (no save error).
7. Outside combat, the auto-record buttons are disabled.
8. While recording with Include UI on, the panel collapses to the REC pill and restores on stop.
9. Cancel discards without saving (no new file).
10. Close the panel mid-recording -> the in-progress recording is saved, not leaked.

## 9. Open implementation questions (resolve in the plan)

- Exact "Open folder" affordance from Lua (the engine already reveals the folder on save; confirm whether a re-reveal is callable from Lua, otherwise the footer is informational + relies on the save-time reveal).
- Whether the REC pill should be draggable within the docked panel or float; pick the simplest that keeps it out of the captured frame.
- Confirm the disabled-state styling/idiom for the auto-record buttons matches other codex panels.

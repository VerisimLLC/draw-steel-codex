# Measuring Tool -- Design Brief

**Status: PARKED mid-Phase-4 (round 1, decision P1 unanswered).** Nothing below
the Decision Ledger is settled. Do not implement from this document yet.

Scope: two features chosen 2026-08-15 -- **pinned measurements** and
**elevation-aware distance**.

**To resume:** the open question is P1 -- whether a pin is a durable map
annotation (option A, reuses the area-template object path, nearly free) or a
transient client-side overlay (option B, needs a C# pin channel, recommended).
Everything else in the decision map waits on that answer. The panel UI work that
happened after this was parked is unrelated to these two features and shipped
separately.

---

## 1. Framing

**Problem.** A measurement is destroyed the instant you release the mouse, and on
any map with height the number it reported was wrong anyway.

**For whom.**
- *Director / power user* (DM running a live encounter): wants to check several
  spans in sequence, compare them, and keep one on screen while doing something
  else. Currently re-drags every time.
- *Set-and-forget user* (player checking "can I reach?"): wants one correct
  number with no configuration. Currently cannot keep a measurement on screen at
  all -- Persist on Map is DM-gated.

**Why now.** The panel was just reworked (dockable, responsive) and two of its
three checkboxes are settings the user rarely revisits, which surfaced the
question of what the panel is actually *for* beyond mode selection.

**Done looks like.** A player can check a distance that accounts for height, and
either party can keep a measurement visible without spawning map furniture.

---

## 2. Verified engine reality

Every claim anchored. Verified 2026-08-15 against the running client and source.

### What exists today

| Capability | Detail | Anchor |
|---|---|---|
| 8 shapes | Ruler, Rectangle, Circle, Cone, Square, Line, Polygon, CrossSection -- all keybound | `Settings.lua:1800`, `MeasureTool.cs:22` |
| Multi-segment paths | `waypoints` summed into `len` / `lenTiles` | `MeasureTool.cs:44,72` |
| Live share | "Display to others" broadcasts; remote measures project onto other clients | `MeasureTool.cs:324` |
| Cross-section | Live side-on terrain diagram, incl. remote projection | `MeasureTool.cs:520` |
| Snap | None / Center / Corner | `MeasureTool.cs:276` |
| `PlayerMeasureInfo` | Complete serializable record: guid, mapid, tool, a, b, waypoints, color, coneAngle, lineWidth, floorIndex | `MeasureTool.cs:17-66` |

### Constraints found (these shape the options)

1. **"Persist on Map" is not a saved measurement.** It spawns a real map
   `ObjectInstance` carrying an `ObjectComponentAreaTemplate` (shape,
   targetPoint, waypoints, colour, coneAngle), sourced from a cloud asset with
   keyword `areatemplate`. It is DM-gated on `isDMPossiblyImpersonating`, and
   `inactive = !measure:share`. -- `MeasureTool.cs:526-575`
2. **No lightweight persistent-render channel exists.**
   `MeasureTool.AddPersistentMeasure` has exactly one caller,
   `LevelObjectAreaTemplate.cs:255` -- persistent rendering is downstream of a
   placed object, not an independent channel. -- `MeasureTool.cs:437`
3. **The measure tool has no Lua API.** `LuaMeasureTool` is, verbatim, "a
   placeholder with no exposed members". -- `MeasureTool.cs:9-13`
4. **The area-template Lua bridge is near-empty.**
   `LuaObjectComponentAreaTemplate` exposes only `GetFilledLocs()` -- no shape,
   colour, label, or removal. -- `LevelObjectAreaTemplate.cs:1102`
5. **Distance discards elevation.** `LenTiles` computes from `dx`/`dy` only; `z`
   is never read, so tile distance is purely planar on a map with height. The
   cross-section tool exists as a workaround for the symptom, but the *number*
   was never fixed. -- `MeasureTool.cs:111-117`
6. **Dimension forms**: this engine build accepts pixels, percentages, and the
   `"100%-<px>"` complement only. `sp`/`em` raise "Unrecognized dimension
   string"; `"100%-2em"` fails silently. Relevant to any new panel UI. --
   verified by live probe, recorded in `RulerTool.lua`

**Net:** constraints 2-4 mean anything that lives in the Lua panel needs new C#
bridge work first. That is the phasing gate on the whole feature set.

---

## 3. Decision map

### Pinned measurements

| # | Decision | Status |
|---|---|---|
| P1 | Render path / data model -- reuse area-template objects, new local-only channel, or new shared record | **round 1, open** |
| P2 | Audience -- DM-only, players too; can others see a pin | open |
| P3 | Surface -- where the pin list lives; map-only vs panel list | open |
| P4 | Controls -- how to pin, how to clear one vs all | open |
| P5 | Labelling -- does a pin permanently show its number on the map | open |
| P6 | Lifetime -- until dismissed / map change / session end | open |
| P7 | States -- empty, first-run, late joiner, map switch, floor switch, hot-reload | open |
| P8 | Relationship to existing "Persist on Map" -- merge, replace, or coexist | open |
| P9 | Copy -- all user-facing strings | open |
| P10 | Accessibility -- colour never the sole signifier; non-drag path | open |
| P11 | Phasing | open |

### Elevation-aware distance

| # | Decision | Status |
|---|---|---|
| E1 | Rule -- what vertical distance *should* be under Draw Steel | open |
| E2 | Change the existing number, or show both planar and true | open |
| E3 | Scope -- ruler only, or every shape's range check | open |
| E4 | Regression risk -- what else reads `lenTiles` | open |
| E5 | Does the ability/targeting system already have its own answer to reconcile with | open |

---

## 4. Decision ledger

*(date -- decision -- one-line rationale)*

- 2026-08-15 -- Design pinned measurements and elevation-aware distance; defer
  "measure from selected token" and a full-surface rework -- user pick.
- 2026-08-15 -- No chronological measurement history/log -- the answer is
  consumed instantly; a log of already-used numbers administers the tool rather
  than serving the session (Hodent *motivation*). Pinning serves the three real
  needs behind the request (re-check, compare, keep visible).

---

## 5. Open questions

- E1/E5 need a rules answer and a code scan before options are worth writing.
- Whether players spawning map objects is acceptable at all (gates P1 option A).

---

## 6. Out of scope / rejected

- **Chronological measurement history** -- rejected, see ledger.
- Measurement export, area/volume totals -- low value, not raised by users.
- Engine dimension-parser fix for `sp`/`em` -- separate concern, noted only
  because it constrains new panel UI.

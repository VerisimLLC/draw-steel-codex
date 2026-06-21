---
name: dice
description: |
  Author, edit, and publish custom 3D dice with the DMHub Dice Studio, driving a live
  connected instance over the MCP bridge. Use when the user asks to change the dice they
  are editing -- swap the surface material, set textures/colors/parameters, tune the
  built-in shader, font, border, or player-facing icon colors; add particle effects to
  dice lifecycle events; write or attach a custom dice Lua script; configure teleport/portal
  movement; or load/save/upload a dice set. Also use to put dice live on the shop (set
  keywords="dice", mark on-sale) and to upload/size featured-dice banner art. Trigger on
  "/dice", "dice studio", "edit my dice", "change the dice material/texture/color",
  "make the dice glow", "add a particle effect to the dice", "write a dice script",
  "upload/publish my dice", "put my dice on the store", or "make a dice banner".
metadata:
  author: draw-steel-codex
  version: "1.0.0"
---

# Dice Studio Authoring (/dice)

You help the user author custom 3D dice in DMHub's **Dice Studio**, saving their work locally.
You drive a **live, running** DMHub instance over the MCP bridge (`mcp__dmhub__*`) by executing
Lua against the `dicestudio` global and other engine globals. You make and save changes; the
**user** tests them, and you do not publish/upload unless they explicitly ask (see the
operating policy below). You do not need DMHub engine
(C#) source access -- everything you need is in this skill. If you *do* have the engine repo
checked out, the authoritative deep-dives are `Assets/DICE_STUDIO_REFERENCE.md` (authoring)
and `Assets/DICE_REFERENCE.md` (rolling + custom scripts), but treat them as optional.

## Assumptions

- **The MCP bridge is available** and DMHub is running. Always call
  `mcp__dmhub__check_connection` first; if it is not connected, stop and tell the user
  rather than trying to start it.
- **The Dice Studio panel is open**, so the engine has already called
  `dicestudio:Activate()` and bound a live editable `DiceSet`. (If `dicestudio` errors as
  not-activated, ask the user to open Dice Studio, or call `dicestudio:Activate()` yourself.)
- The user is **signed in as an admin** if they intend to upload/publish (upload and image
  asset upload are both admin-gated). Editing and saving locally do not require admin.

## How you operate

> **Operating policy (read this first -- it governs everything below):**
>
> 1. **Do not test your own changes -- look only, then hand off to the user.** You MAY
>    *look*: screenshot the screen (`mcp__dmhub__screenshot` /
>    `mcp__dmhub__screenshot_panel`) and inspect state with `print(...)` to understand the
>    current set before you edit. But after you make a change, **describe what you changed
>    and ask the user to test it** (roll dice, watch their preview). Do NOT spawn preview
>    dice, test-fire effects or sounds, roll dice, or otherwise exercise the change to verify
>    it yourself. The user tests; you author.
> 2. **Save locally; never upload.** Persist edits with `dicestudio:Save()` / `SaveAs()`
>    only. Do NOT call `dicestudio:Upload()`, publish dice to the shop, or upload banner
>    art. If a requested change genuinely cannot be done without uploading an asset (e.g. a
>    custom **texture** the user imported -- section 2g), stop and ask the user before
>    uploading anything.

- Run Lua with `mcp__dmhub__execute_lua`. Inspect with `print(...)`; the output and any Lua
  error come back to you, so iterate. Keep ASCII only inside any Lua you write or save (the
  DMHub Lua runtime rejects non-ASCII bytes -- no em dashes, curly quotes, or ellipses).
- **Make changes incrementally**, especially destructive ones (clearing a script, changing
  the surface material -- which resets that material's properties to defaults). Make the
  edit, save locally, then tell the user what to test.
- This skill edits **Lua** (dice scripts, and any codex Lua). It does **not** edit engine
  C#. When something genuinely requires an engine change, make a clear written
  recommendation to the user (see "When an engine change is needed").

## Mental model

There are three copies of a dice set, and you must keep them straight:

1. **The live editable set** -- the `dicestudio` global wraps it. Every edit you make
   (material, textures, font, script, particles, ...) mutates this in memory immediately.
2. **The local file on disk** -- `dicestudio:Save()` / `SaveAs(name)` writes the live set to
   `{persistentDataPath}/DiceStudio/{name}/data.json`. This is the source of truth that
   survives restarts and is what `Load(name)` reads back.
3. **The cloud document** -- `dicestudio:Upload()` (admin only) pushes the saved set to
   `/CoreAssetsCurrent/dice/{guid}` so every client can download it. This is what a shop
   item points at via its `assetid`. **Per the operating policy you do NOT do this** unless
   the user explicitly asks you to publish; documented here only so you understand the model.

A normal authoring session is: load or create a set -> edit the live set -> **save locally**.
Stop there and ask the user to test. Do not upload.

### Live refresh (so the user's open preview reflects your edit)

Mutating `dicestudio.*` does not by itself re-render an already-spawned preview die. After an
edit, you may bump the equipped-dice setting and signal the material change -- exactly as the
panel's internal `RefreshDice()` does -- so that whatever preview the *user* already has open
updates for them to look at:

```lua
local function RefreshDicePreview()
    local save = dmhub.GetSettingValue("diceequipped")
    dmhub.SetSettingValue("diceequipped", "xxx")
    dmhub.SetSettingValue("diceequipped", save)
    dicestudio:UpdateMaterial()   -- bumps updateseq; preview dice re-init next frame
end
```

**Do not spawn preview dice to test your own work.** `dicestudio:SpawnPreview(n)` exists
(faces in {3,4,6,8,10,12,20,100}; calling again with the same face count removes it), but per
the operating policy you do not put preview dice on the playfield to verify changes yourself.
If the user wants a preview die, they can spawn it; or, only if they ask you to set one up,
do so and tell them -- then remove any you added when done.

**Panel-widget staleness caveat:** when you drive `dicestudio` from script, a 3D preview die
updates via `RefreshDicePreview()`, but the open panel's sliders/dropdowns will not re-read
until their refresh events fire. If the user reports the panel showing stale values, have
them re-pick the set in the "Dice:" dropdown (which fires `newmaterial`/`refreshDice` across
the panel).

## 1. Inspect the current set

Always start by reading current state so you change the right thing:

```lua
print("name(canSave):", dicestudio.canSave, "uploaded:", dicestudio.uploaded)
print("surface material:", dicestudio.surfaceMaterialName)   -- nil if none
print("font:", dicestudio.font, "border:", dicestudio.border)
print("special movement:", dicestudio.specialMovement)       -- none|teleport|portal
print("script len:", #(dicestudio.script or ""))
-- local files available to load:
for _,f in ipairs(dicestudio:GetLocalFiles()) do print("local:", f.id, f.text) end
-- available surface materials (the approved allow-list, baked into the build):
for _,m in ipairs(dicestudio.availableMaterials) do print("material:", m.displayName) end
```

## 2. Materials and parameters

A die's look is built from several layers. From outermost authoring control to innermost:

### 2a. Built-in material (always present)

The engine's built-in dice shader -- surface texture/tint, matcap, normals, metallic,
smoothness, font and border tints/extrusion, and master alpha. Edit via the `"builtin"`
property bag. Properties are keyed by **shader property name** (the stable identifier):

```lua
local p = dicestudio:GetMaterialProperties("builtin")
p:SetColor("_SurfaceTint", "#cc2222ff")
p:SetFloat("_SurfaceMetallic", 0.8)
p:SetFloat("_SurfaceSmoothness", 0.6)
p:SetColor("_FontGlowColor", "#ffd700ff")
RefreshDicePreview()
```

Built-in shader properties (name -> what it does; Float/Range are 0..1 unless noted):

| Property | Type | Meaning |
|---|---|---|
| `_SurfaceTexture` | Texture | Surface albedo texture |
| `_MatcapTexture` | Texture | Surface matcap (lit-sphere). Setting it also writes `_EnableMatcap`=1 |
| `_SurfaceNormals` | Texture | Surface normal map |
| `_SurfaceNormalStrength` | Float | Normal map strength (default 1) |
| `_SurfaceTint` | Color | Surface color |
| `_CageTint` | Color | Border/cage color |
| `_FontTint` | Color | Number color |
| `_FontBrightness` | Range 0..2 | Self-illuminate numbers in font tint (0 = scene-lit only) |
| `_FontGlowColor` | Color | Programmatic landing-result glow color |
| `_FontMatcapTexture` | Texture | Paint numbers with a matcap (sets `_EnableFontMatcap`) |
| `_FontMatcapPower` | Range 0..2 | Font matcap brightness (default 1) |
| `_SurfaceMetallic` / `_CageMetallic` / `_FontMetallic` | Float | Metallic per region |
| `_SurfaceSmoothness` / `_CageSmoothness` / `_FontSmoothness` | Float | Smoothness per region |
| `_CageNormalStrength` | Float | Border extrusion |
| `_FontNormalStrength1` | Float | Font extrusion (default 1) |
| `_MasterAlpha` | Float | Die-wide opacity (default 1) |

### 2b. Surface material override (optional)

An extra material layered on top of the built-in shader's surface. Pick one by name from the
approved list. **Selecting a material resets its property bag to the material's defaults** --
warn the user before switching if they have tuned it.

```lua
-- select by display name from dicestudio.availableMaterials:
local function SelectSurfaceMaterial(name)
    for _,m in ipairs(dicestudio.availableMaterials) do
        if m.displayName == name then dicestudio.material = m; return true end
    end
    return false
end
SelectSurfaceMaterial("MatCapDiceMaterial")
RefreshDicePreview()

dicestudio.material = nil          -- clear the override
dicestudio.hideBaseMaterial = true -- hide base entirely (no numbers/cage), show only surface
```

Then tune it through the `"material"` bag:

```lua
local m = dicestudio:GetMaterialProperties("material")
m:SetColor("_MatcapColor", "#88ccffff")
m:SetFloat("_MatcapIntensity", 1.5)
RefreshDicePreview()
```

Two curated materials ship with hand-authored property lists; any other material in the list
falls back to reflected shader controls. The curated ones:

- **`MatCapDiceMaterial`** -- matcap-based. Notable props: `_MatcapColor` (Color),
  `_Matcap`/`_Matcap2` (Matcap textures), `_MatcapMask`/`_Matcap2Mask` (mask textures),
  `_Matcap0NormalMap` (+`_Matcap0NormalMapScale`), `_MatcapHueShift` (0..1),
  `_MatcapEmissionStrength` (0..20), `_MatcapIntensity` (0..5, default 1), `_MatcapBorder`
  (0..5), `_MatcapReplace`/`_MatcapMultiply`/`_MatcapAdd` (0..1 blend), `_Matcap2Enable`
  (Bool, gates the `_Matcap2*` rows).
- **`PBRTexturedDiceMaterial`** -- PBR texture set (ambientCG / Poly Haven style). Props:
  `_BaseMap` (albedo), `_BaseColor` (tint), `_NormalMap` (GL convention) + `_NormalStrength`
  (0..3) + `_NormalFlipY` (Bool, tick for DX maps), `_RoughnessMap` + `_RoughnessScale`
  (0..2), `_Brightness` (0..3), `_Ambient` (0..1), `_SpecStrength` (0..2), `_HeightMap` +
  `_ParallaxScale` (0..0.15) + `_ParallaxSteps` (1..32) + `_OcclusionFromHeight` (0..1),
  `_Tiling` (0.1..8). The normal/roughness/height maps are decoded linear; the normal map
  must be raw RGB OpenGL ("_NormalGL"); tick Flip Normal Y for a DX map.

The list of approved materials is baked into the build -- you cannot add a new material from
Lua (see "When an engine change is needed").

### 2c. Per-die-type surface overrides

Each die type (d3/d4/d6/d8/d10/d12/d20; d100 shares the d10 slot) can override the default
surface material. No override = inherits the default `material`.

```lua
print(dicestudio:HasMaterialForType(20))            -- bool
dicestudio:SetMaterialForType(20, someDiceMaterial) -- set; nil clears the override
local pp = dicestudio:GetMaterialPropertiesForType(20) -- this die's effective surface props
pp:SetColor("_MatcapColor", "#ff0000ff")
```

### 2d. Text material, font, border

```lua
local t = dicestudio:GetMaterialProperties("text")   -- the face-number material
dicestudio.font   = "<one of dicestudio.fontOptions>"
dicestudio.border = "<one of dicestudio.borderOptions, or 'None'>"
```

### 2e. Player-facing icon colors (`dicePanelStyles`)

These tint the 2D dice icons players see in chat/roll panels (not the 3D dice). Read/write
`{bgcolor, trimcolor, color}`:

```lua
local s = dicestudio.dicePanelStyles
s.bgcolor   = "#202020ff"
s.trimcolor = "#888888ff"
s.color     = "#ffffffff"
dicestudio.dicePanelStyles = s
```

### 2f. Preview size, special movement, animation curves

```lua
dicestudio.previewScale = 4         -- size of preview dice in the studio

-- Special movement (see also the Particles section's Portal effect binding):
dicestudio.specialMovement = "teleport"   -- "none" | "teleport" | "portal"
dicestudio.teleportVelocity = 1.5   -- speed at/below which the jump triggers
dicestudio.teleportDistance = 0.333 -- fraction (0..1) of playfield width jumped
dicestudio.teleportDuration = 0.1   -- slide seconds (lower = faster)
-- Portal mode tunables: portalCreationTime, portalFlashPeriod, portalFlashIntensity

-- Animation curves drive a material property from die speed or elapsed time:
local c = dicestudio:AddCurve()     -- returns a DiceCurveLua; set its curve + input
```

### 2g. Textures -- CRITICAL upload rule

A texture property holds an **image asset id**. Built-in library textures (the matcap /
normal / mask sets the studio ships) can be assigned by their library id directly -- prefer
these, since they need no upload. For a **custom** texture the user imports, you would have to
upload it as a **Core cloud image asset** and assign the returned guid -- otherwise other
clients who download the dice set cannot resolve the texture (dice upload pushes only the dice
JSON, not the referenced images). **That is an upload**, so per the operating policy do not do
it silently: tell the user a custom texture requires uploading an image asset and get their
OK before calling `assets:UploadImageAsset`.

```lua
-- Upload a custom texture so shipped dice can resolve it everywhere:
assets:UploadImageAsset{
    core = true,                       -- REQUIRED for dice that will be uploaded/shared
    path = "C:/path/to/texture.png",   -- a real file path the user gave you
    description = "Dice texture: my-set",
    upload = function(guid)
        dicestudio:GetMaterialProperties("builtin"):SetTexture("_SurfaceTexture", guid)
        RefreshDicePreview()
    end,
    error = function(msg) print("upload failed:", msg) end,
}
```

`SetTexture(prop, value, index)` accepts an optional 1-based `index` (1..6 = d4,d6,d8,d10,
d12,d20) for per-die-size texture arrays; `HasTextureArray`/`CreateTextureArray`/
`DestroyTextureArray` manage array mode. Pass `nil`/`""` to clear a texture.

## 3. Load / Save (local only)

```lua
-- Load a local set into the editor (id from GetLocalFiles):
dicestudio:Load("My Dice")

-- Pull an already-uploaded cloud set down to a local file (keeps its cloud name+id).
-- id from dice.GetAllDice().
local localName = dicestudio:DownloadCloudDice("<cloud-guid>")

-- Save the live set LOCALLY (this is how you persist every change):
if dicestudio.canSave then dicestudio:Save() else dicestudio:SaveAs("My Dice") end
```

`SaveAs(name)` creates a **fresh** file (and clears the cloud id) -- use it for a brand-new
set; use plain `Save()` to update the set you loaded. After saving, tell the user what to
test.

**Do not upload.** `dicestudio:Upload()` exists (admin-only; pushes the saved set to
`/CoreAssetsCurrent/dice/{guid}` for all clients) but the operating policy is local-save-only
-- do not call it as part of making changes. If the user *explicitly* asks you to publish,
confirm that intent first, then upload; otherwise never.

## 4. Dice scripting (custom per-die Lua)

A set can carry one custom Lua script (`dicestudio.script`) that the engine runs **once per
die instance** as a sandboxed coroutine on every client that renders the die (roller, replay
viewers, studio preview). It is purely visual -- no networking, no persistence beyond the
set. The source must **end with `return function(die) ... end`**.

Validate before assigning; the result is `""` if it compiles:

```lua
local src = [[
return function(die)
    while die.alive do
        if die.rolling then
            die.hue = math.min(1, die.speed / 18)   -- shift hue with tumbling speed
        elseif die.state == "result" and die.isMax then
            die.color = "#ffd700"                    -- glow gold on a natural max
        end
        Wait()                                       -- yield one frame
    end
end
]]
local err = dicestudio:ValidateScript(src)
if err == "" then
    dicestudio.script = src    -- assigning live-rebinds preview dice
    RefreshDicePreview()
else
    print("script error:", err)
end

dicestudio.script = ""         -- clear the script
```

**Sandbox:** only pure-Lua stdlib (`math`/`table`/`string`/`coroutine`), a few safe
primitives (`ipairs`/`pairs`/`type`/`tostring`/`pcall`/`print`/...), and `Wait()`. There is
**no** `dmhub`/`game`/`gui`/`io`/`os`/`require`/`load`/`debug` and no `_G` escape. Never write
a busy loop without `Wait()` -- it hangs the client.

**The `die` handle.** Read: `die.state` (waiting/rolling/result/exiting), `die.rolling`/
`die.settled`/`die.preview`, `die.face`/`die.faceError`/`die.isMax`, `die.numFaces`/
`die.maxFace`/`die.category`, `die.speed` (smoothed) / `die.rawSpeed` (spiky, for impacts) /
`die.spin` / `die.velocity`, `die.position`/`die.height`, `die.time`/`die.timeRemaining`,
`die.guid`/`die.alive`. Write (sticky, re-applied each frame): `die.hue`/`die.saturation`/
`die.brightness`, `die.color` (sets `_SurfaceTint`), `die.alpha`, `die.material:SetColor/
SetFloat/GetColor/GetFloat(name, ...)` (base material), `die.surface:...` (surface override
material), and `die:ClearOverrides()` to revert.

**Particles from a script (more flexible than event bindings).**
`die:PlayEffect{ id = "<EffectName>", ... }` spawns a named library effect on the die and
returns a handle. Guard it so it fires once (on a state change), not every frame:

```lua
return function(die)
    local fx
    while die.alive do
        if die.settled and die.isMax and fx == nil then
            fx = die:PlayEffect{ id = "Sparkles", scale = 1.5 }
            fx:SetColor("_TintColor", "#ffd700ff")
        end
        if fx and fx.alive then fx:SetFloat("_HueShift", die.time % 1) end
        Wait()
    end
end
```

`PlayEffect` args: `scale`, `speed` (particle sim-speed), `hue`/`brightness`/`tint`, `rotate`
(X degrees), `attach` (default true; false leaves the effect where the die was),
`layer` ("above" default | "below"), `trail = true` (leave particles behind as the die moves
-- the TravelTail streak). The handle exposes `SetFloat`/`SetColor` for any particle-shader
prop plus `hue`/`brightness`/`tint`/`opacity` (compose off a baseline), `Scale`, `Rotate`,
`Stop()`, `alive`. Effect names are the same catalog as the Particles picker -- see below.

## 5. Particles (lifecycle event bindings)

Bind one or more named effect prefabs to dice **lifecycle events**. Each binding has its own
tunables. Events: `Appearance`, `BounceHit`, `Disappear`, `Reappear`, `Exit` (these are
*pulse* one-shots), `RollWaiting`, `TravelTail` (*state* effects attached for the die's
life), and `Portal` (used when `specialMovement == "portal"`).

```lua
-- discover what effects are available for an event:
for _,n in ipairs(dicestudio:GetEventEffectOptions("Appearance")) do print(n) end

-- add an effect to an event; returns a binding you can tune:
local b = dicestudio:AddEventEffect("Appearance", "Sparkles")
b.scale = 1.5; b.speed = 1; b.hueShift = 0; b.brightness = 1; b.tint = "#ffffffff"
b.xRotation = 0                 -- 0/90/180/270 to flip z-up vs y-up prefabs
b.layerPlacement = "auto"       -- "auto" | "above" | "below"
RefreshDicePreview()

-- list / clear:
for _,bind in ipairs(dicestudio:GetEventEffectList("BounceHit")) do print(bind.effectName) end
dicestudio:RemoveEventEffect(b)             -- remove one binding
dicestudio:ClearEventEffects("Appearance")  -- remove all on an event
```

`dicestudio:FirePreviewEffect("<Event>")` test-fires a bound effect on preview dice -- but
per the operating policy **do not use it to test your own work**. Bind the effect, save, and
ask the user to roll and confirm how the effect looks (trail effects like `TravelTail` only
read properly on a die actually in flight, which is the user's to judge).

Use the script-based `die:PlayEffect` (section 4) when you need conditional logic the static
event bindings can't express (fire only on a max, animate the effect's hue over time, etc.).

### Sounds (parallel system)

One sound per event, fixed rows: `ThrowStart` (per-roll), `Appearance`, `BounceHit`,
`Disappear`, `Reappear`, `Exit`. `dicestudio:GetSoundEventOptions()` lists choices;
`SetEventSound(event, name)` / `GetEventSound`, `SetEventSoundVolume(event, 0..2)`. A
`FirePreviewSound(event)` exists but -- like the visual test-fire -- **do not use it to test
yourself**; set the sound, save, and ask the user to listen.

## 6. Putting dice live on the shop

> **Off by default.** Everything in this section uploads/publishes (the dice set, the shop
> item, product images), which the operating policy forbids unless the user *explicitly* asks
> you to put dice on the store. If they do, confirm the intent, then proceed; otherwise skip
> this section entirely. It is documented for that explicit case only.

Shop items live in the admin Shop screen (Compendium > Assets > Shop) but you can drive them
from Lua. A dice product is a shop item with `itemType="Dice"` and `assetid` pointing at the
uploaded dice guid. To make it **appear under the shop's "Dice" filter set `keywords="dice"`
exactly** (the shop category filter matches the keyword string literally). To make it
purchasable set `onsale=true` ("Live on store").

```lua
-- find an existing item by name, or create one:
local item
for id,it in pairs(assets.shopItems) do if it.name == "My Dice Set" then item = it end end
if item == nil then
    item = assets.CreateLocalShopItem()
    item.name = "My Dice Set"
end

item.itemType = "Dice"
item.assetid  = "<uploaded dice cloud guid>"   -- from dicestudio.Upload / dice.GetAllDice
item.keywords = "dice"                          -- REQUIRED to show under the Dice category
item.price    = 499                             -- US cents (0 or less = FREE)
item.details  = "Roll in style with this exclusive dice set."
item.onsale   = true                            -- live on store (confirm with the user!)
item:Upload()
```

Other fields: `artistid`, `images` (array of Core image guids for the product gallery -- same
`assets:UploadImageAsset{core=true}` path), gift codes (admin). Confirm with the user before
flipping `onsale = true` -- that publishes the product to all shoppers.

## 7. Featured-dice banner art

> **Off by default.** Banner art is uploaded as Core image assets and written onto a
> published shop item -- both uploads. Per the operating policy, only do this when the user
> explicitly asks for a shop banner; otherwise skip.

A Dice item can carry a banner shown at the top of the shop when featured. It is two layers
plus a live die composited between them, with placeable advertising text. **Upload art at
1232 x 706** (`ShopDiceBanner.artWidth` x `artHeight`):

- **Background layer** -- painted *behind* the dice (opaque).
- **Foreground layer** -- painted *over* the dice (e.g. hands holding them) -- use **PNG
  transparency**. Leave a layer empty/clear to let the dice render directly over whatever is
  behind.

Both must be **Core** image assets (the catalog entry referencing them is global). Upload and
write the banner config onto the item:

```lua
assets:UploadImageAsset{
    core = true,
    path = "C:/path/to/banner-bg.png",
    description = "ShopBanner: " .. item.id,
    upload = function(guid)
        local cfg = ShopDiceBanner.ReadItemConfig(item)   -- current/normalized config
        cfg.backgroundImage = guid
        -- cfg.foregroundImage = <another uploaded guid>
        cfg.diceScale  = 2          -- 0.5..8
        cfg.dieX = 0.5; cfg.dieY = 0.5   -- 0..1 normalized placement
        cfg.dieSize = 0             -- 0 = auto; otherwise box size in px
        cfg.textPlacement = "left"  -- topleft|topright|left|right|bottomleft|bottomright
        cfg.textOffsetX = 0; cfg.textOffsetY = 0   -- -500..500 / -350..350
        item.diceBanner = cfg
        item:Upload()
    end,
    error = function(msg) print("banner upload failed:", msg) end,
}
```

Sizing advice for the user: author at exactly 1232 x 706 (it displays ~1080 wide, scaled).
Keep the focal area centered-ish since the live dice composite on top; put readable detail
where it will not collide with the dice or the chosen text placement; export the foreground
as PNG with a clean alpha channel.

## When an engine change is needed

You can do almost everything from Lua. A few things require a DMHub engine (C#) change +
rebuild, which the user may not be able to do. When you hit one, **stop and write a clear
recommendation** rather than attempting a workaround:

- **Adding a new surface material to the approved list** -- the `availableMaterials` list is
  baked from `Assets/DiceStudio/DiceStudio.asset` and needs a new `.mat` plus a dev build.
- **New built-in shader properties / new lifecycle events / new curve targets** -- engine
  shader/enum changes.
- **A particle effect prefab that is not in `GetEventEffectOptions`** -- effect prefabs are
  registered engine-side.

Phrase it as: "This needs an engine change (X). Here is exactly what to add and why. I can't
do it from Lua." Give the file and the change so an engine maintainer can act on it.

## Pre-flight checklist before you hand off

- `mcp__dmhub__check_connection` succeeded and the edit ran without a Lua error.
- You did **not test the change yourself** -- no spawned preview dice, no test-fired effects
  or sounds, no rolls. You only *looked* (screenshot/inspect) where needed to understand the
  set before editing.
- Any dice **script** passed `ValidateScript` (returned `""`) and ends with
  `return function(die) ... end`, ASCII only.
- You **saved locally** with `Save`/`SaveAs`, and you did **not** `Upload()` or publish to
  the shop (unless the user explicitly asked you to and you confirmed the intent first).
- You told the user exactly what changed and **what to test** (e.g. "roll a few d20s and tell
  me how the trail looks"), and were honest about anything only they can confirm.
```
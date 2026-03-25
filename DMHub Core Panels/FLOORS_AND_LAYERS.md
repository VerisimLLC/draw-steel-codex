# Floors, Layers, and Map Import Architecture

## Floor/Layer Hierarchy

DMHub maps use a **flat list with parent references** to model a floor/layer hierarchy.

### Data Structures

**MapManifest** (the map definition):
- `floors`: Ordered `List<string>` of floor IDs (both primary floors AND layers)
- `dimMin` / `dimMax`: `Loc` (integer tile coordinates) defining the map canvas bounds
- `groundLevel`: Index into `floors` marking where "above ground" starts

**MapFloor** (a single floor or layer):
- `parentFloor`: `string` -- If null/empty, this is a **primary floor**. If set to another floor's ID, this is a **layer** on that floor.
- `description`: Floor display name (e.g., "Ground Floor")
- `layerDescription`: Layer-specific display name (e.g., "Map Layer", "Roof")
- `objects`: `Dictionary<string, ObjectInstance>` -- all objects on this floor/layer
- `tokens`: `Dictionary<string, TokenInfo>` -- tokens on this floor
- `map`: `GameMap` -- map geometry/terrain data
- `vision`: `VisionSettings`
- `roof`, `roofShowWhenInside`, `visionMultiplier`, etc.

### Primary Floor vs Layer

| Aspect | Primary Floor | Layer |
|---|---|---|
| `parentFloor` | nil/empty | Parent floor's ID |
| `isPrimaryLayerOnFloor` | true | false |
| In `floorsWithoutLayers` | yes | no |
| In `floors` | yes | yes |
| In `GetLayersForFloor(id)` | yes (if self) | yes (if parent matches) |
| Used for | Walls, vision, geometry | Visual layers (map image, roof, fog) |

### How Floors Are Stored

All floors and layers are stored in a single ordered list (`mapManifest.floors`). Layers must be **contiguous** with their parent floor. Layers are inserted **before** their parent floor in the list.

Example floor list for a 2-floor building:
```
[0] Layer "Map Layer"    (parentFloor = floor-id-1)   <-- map image for Floor 1
[1] Floor "Floor 1"      (parentFloor = nil)           <-- primary floor
[2] Layer "Map Layer"    (parentFloor = floor-id-2)   <-- map image for Floor 2
[3] Floor "Floor 2"      (parentFloor = nil)           <-- primary floor
```

`groundLevel = 4` means all floors are above ground.

## Map Import: Complete Pipeline

### Step 1: User Selects Files

`mod.shared.ImportMap(options)` opens the import wizard. User drops image files (or UVTT files). Multiple files create multi-floor maps.

### Step 2: User Configures Grid (MapImport.lua)

The `gui.MapImport` panel (backed by C# `SheetMapImport`) lets the user:
- Place 3 control points to define grid square size (grid mode)
- Or enter pixel dimensions directly (gridless mode)
- Or enter map dimensions in tiles (map dimensions mode)

### Step 3: C# Creates Assets (SheetMapImport.OnConfirm)

For each file path, the C# engine:

1. Creates an `ObjectAsset` with a `"Map"` component (`ObjectComponentMap`):
   ```csharp
   ObjectAsset {
       description = filename,
       imageId = uploadedImageId,
       components = {
           "Map": ObjectComponentMap {
               controlPoints = [3 normalized points],  // 0.0-1.0 on image
               scaling = tileScaling,                   // user's scaling multiplier
               mapType = "squares" | "flattop" | "pointtop",
           }
       }
   }
   ```

2. Uploads the image and asset to the cloud

3. Calls the Lua callback with an `info` table:
   ```lua
   info = {
       objids = {"guid1", "guid2", ...},   -- asset IDs, one per file
       width = 20.0,                        -- map width in tiles (textureDim.x / tileSize.x * scaling)
       height = 18.0,                       -- map height in tiles
       mapSettings = {                      -- tile type settings
           ["maplayout:tiletype"] = "squares",
       },
       uvttData = {...},                    -- optional, for UVTT imports
   }
   ```

### Step 4: Lua Creates the Map (FinishMapImport)

`mod.shared.FinishMapImport(mapName, info)` does:

1. **Creates floor entries** -- TWO per imported layer:
   ```lua
   -- Entry 1: Map image layer (child)
   { description = "Floor 1", layerDescription = "Map Layer", parentFloor = 2 }
   -- Entry 2: Primary floor (parent)
   { description = "Floor 1" }
   ```

2. **Creates the map**: `game.CreateMap{description=name, groundLevel=#floors, floors=floors}`

3. **Sets dimensions** centered on origin (0,0):
   ```lua
   map.dimensions = {
       x1 = -ceil(w/2) + 1,   -- e.g., w=20 -> x1=-9
       y1 = -ceil(h/2) + 1,   -- e.g., h=18 -> y1=-8
       x2 = ceil(w/2) - 1,    -- x2=9
       y2 = ceil(h/2),         -- y2=9
   }
   ```

4. **Spawns map objects** via `ImportMapToFloorCo` for each floor

### Step 5: Map Object Spawned (ImportMapToFloorCo)

```lua
local obj = info.floor:SpawnObjectLocal(info.objid)
obj.x = 0    -- center of map
obj.y = 0
obj:Upload()
```

The map image object is placed at **(0, 0)** which is the center of the symmetrically-bounded map canvas.

## Coordinate System

### Map Dimensions (Tile Grid)

`map.dimensions` returns `{x1, y1, x2, y2}` where:
- `x1, y1` = top-left corner (minimum bounds)
- `x2, y2` = bottom-right corner (maximum bounds)
- **+X = right, +Y = down** on screen
- These are **integer tile coordinates**

**Important**: The getter adds +1 to dimMax (`dimMax.x+1, dimMax.y+1`) to make the bounds exclusive. The setter stores the values directly. So `x2 - x1` gives the tile width.

### Object Position (World Space)

Object `(x, y)` is in **floating-point world coordinates**:
- Stored as `Vector2 pos` on `ObjectInstance`
- Position represents the object's **center** (adjusted by sprite pivot)
- `(0, 0)` is the world origin, typically the center of a symmetrically-bounded map
- Independent of map dimensions -- objects can be anywhere

### Object Area

`obj.area` returns `{x1, y1, x2, y2}` -- the sprite's axis-aligned bounding box in world space, computed from position + sprite size + scale + pivot.

## ObjectComponentMap: How Map Images Render

The `ObjectComponentMap` component on a map object controls rendering:

1. **controlPoints**: 3 normalized (0-1) coordinates on the image defining grid calibration
2. From these, the engine computes `_tileDim` (normalized tile size) and `_mapPivot` (center point)
3. The sprite is scaled so `1/_tileDim.x` tiles fit horizontally and `1/_tileDim.y` vertically
4. The sprite pivot is set to `_mapPivot` so the object's world position aligns with the grid

**Key fields:**
- `controlPoints`: `List<Vector2>` -- the 3 calibration points
- `scaling`: `int` -- tile scaling multiplier
- `mapType`: `string` -- "squares", "flattop", "pointtop"
- `locked`: `bool` -- prevents moving the map (default true)
- `sublayer`: `string` -- rendering layer (Objects, EffectsAboveGround, etc.)

## Adding a Floor to an Existing Map

To add a new floor with a map image to an existing map:

1. **Create the primary floor**: `map:CreateFloor()` (appends to end, synchronous)
2. **Create a map layer on it**: `map:CreateFloor{parentFloor = primaryFloor.floorid}` (inserts before parent, synchronous)
3. **Spawn the map image onto the layer**: `layer:SpawnObjectLocal(assetId)`
4. **Position the object**: Set `obj.x, obj.y` to the center of the desired tile region
5. **Expand map dimensions** if the new floor extends beyond current bounds

### Object Center Calculation

For a new floor placed with top-left at tile `(offsetX, offsetY)` and size `floorW x floorH`:
```lua
obj.x = offsetX + floorW / 2
obj.y = offsetY + floorH / 2
```

### Dimension Expansion

```lua
local dim = map.dimensions
map.dimensions = {
    x1 = math.min(dim.x1, offsetX),
    y1 = math.min(dim.y1, offsetY),
    x2 = math.max(dim.x2, offsetX + floorW),
    y2 = math.max(dim.y2, offsetY + floorH),
}
```

## Lua API Quick Reference

```lua
-- Floor access
map.floors                           -- All floors + layers (ordered)
map.floorsWithoutLayers              -- Primary floors only
map:GetLayersForFloor(floorid)       -- Layers of a floor (includes self)
map:CreateFloor()                    -- New primary floor (synchronous)
map:CreateFloor{parentFloor = id}    -- New layer on floor (synchronous)

-- Floor properties
floor.floorid                        -- Unique ID
floor.parentFloor                    -- nil if primary, parent ID if layer
floor.isPrimaryLayerOnFloor          -- true if primary
floor.actualFloor                    -- parent ID if layer, self if primary
floor.description                    -- Floor name
floor.layerDescription               -- Layer name
floor.objects                        -- Dictionary of objects on floor

-- Object spawning
floor:SpawnObjectLocal(assetid)      -- Spawn object, returns LuaObjectInstance
obj.x, obj.y                        -- World position (center)
obj.area                             -- {x1,y1,x2,y2} bounding box
obj:Upload()                         -- Sync changes to server

-- Map dimensions
map.dimensions                       -- {x1,y1,x2,y2} tile bounds
map:Upload(description)              -- Sync map changes
```

local mod = dmhub.GetModLoading()

-- Putting puzzles in places and taking them out again: the object under a map
-- point, a drawn door near it, making an object a lock (or placing a lock object
-- on empty floor), clearing a lock, taking a puzzle tag off a page or the table
-- or the rail, and checking that each home a puzzle's index entry lists is
-- still there. The Puzzles panel
-- and the placement drags (PuzzleList.lua) use these; the homes themselves are
-- in PuzzleFramework.lua (Puzzle.Homes).

PuzzlePlace = {}

--The library objects a puzzle can be placed as on empty floor.
PuzzlePlace.LOCK_OBJECT = "c76535e1-65b6-4b36-bc7a-9643ef18387b" --Puzzle switch
PuzzlePlace.COMBINATION_OBJECT = "f51e0878-f4ac-4e68-807c-67d79d164b09" --Combination lock

--The engine only offers Interact within the component's own range; a lock does
--its own range check (PuzzleLock.lua), so the engine's is lifted.
local ENGINE_DISTANCE = 100000
--A drop within this of an object's bounds is on the object, so thin doors count.
local OBJECT_PAD = 0.5
--Bounds smaller than this (glows, scratches) count only with the point inside.
local TINY = 0.1
--A drop within this of a drawn door's edge is on the door.
local DOOR_RADIUS = 0.75

---@class PuzzleLockRef
---@field key string the component's key on the object
---@field component any the LuaObjectComponent
---@field lock PuzzleLockInteractive

--The Puzzle Lock components on an object.
---@param floorid string
---@param objid string
---@return PuzzleLockRef[]
function PuzzlePlace.Locks(floorid, objid)
    local result = {}
    local obj = game.LookupObject(floorid, objid)
    if obj == nil or not obj.valid then
        return result
    end
    for key, component in pairs(obj.components or {}) do
        local ok, lock = pcall(function()
            local props = component.properties
            if props ~= nil and props.typeName == "InteractiveContainer" and props:has_key("object")
                and props.object.typeName == "PuzzleLockInteractive" then
                return props.object
            end
            return nil
        end)
        if ok and lock ~= nil then
            result[#result + 1] = { key = key, component = component, lock = lock }
        end
    end
    return result
end

--True when the object still has a lock for this puzzle.
---@param floorid string
---@param objid string
---@param id string
---@return boolean
function PuzzlePlace.HasLock(floorid, objid, id)
    for _, ref in ipairs(PuzzlePlace.Locks(floorid, objid)) do
        if ref.lock.puzzleid == id then
            return true
        end
    end
    return false
end

---@param docid string
---@return any
local function Page(docid)
    return (dmhub.GetTable(CustomDocument.tableName) or {})[docid]
end

--The tag keys on a page that show this puzzle and are still in its text.
---@param page any
---@param id string
---@return string[]
local function LiveTagKeys(page, id)
    local result = {}
    local text = page:GetTextContent() or ""
    for key in pairs(Puzzle.PageTags(page, id)) do
        if string.find(text, "[[" .. key, 1, true) ~= nil then
            result[#result + 1] = key
        end
    end
    table.sort(result)
    return result
end

--True when a home is still there: the object still has this puzzle's lock, the
--page still holds the tag. Deleting tag text or a component sends no event, so
--the panel asks each time it builds.
---@param id string
---@param home PuzzleHome
---@return boolean
function PuzzlePlace.HomeLive(id, home)
    if home.kind == "lock" then
        return home.floorid ~= nil and home.objid ~= nil and PuzzlePlace.HasLock(home.floorid, home.objid, id)
    elseif home.kind == "journal" then
        local page = home.docid ~= nil and Page(home.docid) or nil
        if page == nil then
            return false
        end
        for _, key in ipairs(LiveTagKeys(page, id)) do
            if home.tag == nil or key == home.tag then
                return true
            end
        end
        return false
    elseif home.kind == "table" then
        return Tabletop.HasDocItem(PuzzlePlace.EntryId(id))
    elseif home.kind == "rail" then
        return IconRailKeySlot(PuzzlePlace.RailKey(id)) ~= nil
    end
    return false
end

--A short name for a home: "Chest (Vault floor)", "Handout 3".
---@param home PuzzleHome
---@return string
function PuzzlePlace.HomeName(home)
    if home.kind == "lock" then
        local obj = home.floorid ~= nil and home.objid ~= nil and game.LookupObject(home.floorid, home.objid) or nil
        local name = obj ~= nil and obj.valid and obj.description or nil
        if type(name) ~= "string" or name == "" then
            name = "Object"
        end
        local floor = home.floorid ~= nil and game.GetFloor(home.floorid) or nil
        local floorName = floor ~= nil and floor.description or nil
        if type(floorName) == "string" and floorName ~= "" then
            return string.format("%s (%s)", name, floorName)
        end
        return name
    elseif home.kind == "journal" then
        local page = home.docid ~= nil and Page(home.docid) or nil
        return page ~= nil and tostring(page.description) or "A page"
    elseif home.kind == "table" then
        return "your table"
    elseif home.kind == "rail" then
        return "your icon rail"
    end
    return "Somewhere"
end

--------------------------------------------------------------------------------
-- Finding what is under a map point
--------------------------------------------------------------------------------

---@param area any
---@return number x1, number y1, number x2, number y2
local function Bounds(area)
    local x1, y1, x2, y2 = area.x1, area.y1, area.x2, area.y2
    return math.min(x1, x2), math.min(y1, y2), math.max(x1, x2), math.max(y1, y2)
end

--The object a drop at (x, y) lands on: the smallest whose bounds, padded half a
--tile, hold the point. Tiny effect objects count only with the point inside.
---@param floorid string
---@param x number
---@param y number
---@return any|nil obj the LuaObjectInstance
function PuzzlePlace.ObjectAt(floorid, x, y)
    local floor = game.GetFloor(floorid)
    if floor == nil then
        return nil
    end
    local best, bestSize = nil, nil
    for _, obj in pairs(floor.objects or {}) do
        local ok, x1, y1, x2, y2 = pcall(function()
            local area = obj.area
            if area == nil then
                error("no area")
            end
            return Bounds(area)
        end)
        if ok and obj.valid then
            local w, h = x2 - x1, y2 - y1
            local pad = cond(w < TINY or h < TINY, 0, OBJECT_PAD)
            if x >= x1 - pad and x <= x2 + pad and y >= y1 - pad and y <= y2 + pad then
                local size = math.max(w, TINY) * math.max(h, TINY)
                if bestSize == nil or size < bestSize then
                    best, bestSize = obj, size
                end
            end
        end
    end
    return best
end

---@param px number
---@param py number
---@param ax number
---@param ay number
---@param bx number
---@param by number
---@return number
local function SegmentDistance(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local t = 0
    if len2 > 0 then
        t = math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2))
    end
    local cx, cy = ax + t * dx, ay + t * dy
    return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
end

---@class PuzzleDoorHit
---@field x number the door's middle
---@field y number
---@field distance number

--The drawn door (a wall segment, not an object) nearest (x, y) within reach.
---@param floorid string
---@param x number
---@param y number
---@return PuzzleDoorHit|nil
function PuzzlePlace.DoorAt(floorid, x, y)
    local floor = game.GetFloor(floorid)
    if floor == nil then
        return nil
    end
    local ok, ops = pcall(function() return floor:GetDoorOperations() end)
    if not ok or ops == nil then
        return nil
    end
    local best = nil
    for _, door in ipairs(ops) do
        for _, path in ipairs(door.paths or {}) do
            local sx, sy, n = 0, 0, 0
            for i = 1, #path - 1, 2 do
                sx, sy, n = sx + path[i], sy + path[i + 1], n + 1
            end
            for i = 1, #path - 3, 2 do
                local d = SegmentDistance(x, y, path[i], path[i + 1], path[i + 2], path[i + 3])
                if d <= DOOR_RADIUS and (best == nil or d < best.distance) and n > 0 then
                    best = { x = sx / n, y = sy / n, distance = d }
                end
            end
        end
    end
    return best
end

--------------------------------------------------------------------------------
-- Making and clearing locks
--------------------------------------------------------------------------------

--Make an object a lock for a puzzle: an existing Puzzle Lock component on it is
--pointed at the puzzle, otherwise one is added. Returns false when the object
--is gone.
---@param floorid string
---@param objid string
---@param id string
---@param placed "component"|"object"|nil for a lock moving between puzzles: what placing it first added
---@return boolean ok, string|nil oldId the puzzle the object's lock showed before
function PuzzlePlace.LockObject(floorid, objid, id, placed)
    local obj = game.LookupObject(floorid, objid)
    if obj == nil or not obj.valid then
        return false, nil
    end
    local refs = PuzzlePlace.Locks(floorid, objid)
    local oldId = nil
    if #refs > 0 then
        local ref = refs[1]
        oldId = cond(ref.lock.puzzleid ~= "", ref.lock.puzzleid, nil)
        ref.component:BeginChanges()
        ref.lock.puzzleid = id
        ref.component:CompleteChanges("Lock with a puzzle")
    else
        --AddComponent's return has no properties; the new component is the
        --key the object did not have before.
        local before = {}
        for key in pairs(obj.components or {}) do
            before[key] = true
        end
        obj:AddComponent("Interactive")
        local component = nil
        for key, c in pairs(obj.components or {}) do
            if not before[key] then
                component = c
            end
        end
        if component == nil then
            return false, nil
        end
        component.properties:Construct("PuzzleLock")
        component.properties.object.puzzleid = id
        obj:Upload()
        pcall(function() component:SetAndUploadProperties{ distance = ENGINE_DISTANCE } end)
        placed = "component"
    end
    Puzzle.IndexPuzzle(id, { kind = "lock", floorid = floorid, objid = objid, placed = placed })
    return true, oldId
end

--Point an object's lock at another puzzle (nil: a new one of its own). The
--lock's targets and range go with it; the old puzzle loses this lock and home.
---@param id string the puzzle the lock shows now
---@param floorid string
---@param objid string
---@param otherId string|nil
---@return string newId
function PuzzlePlace.MoveLock(id, floorid, objid, otherId)
    local newId = otherId or ("lock_" .. Puzzle.SafeId(dmhub.GenerateGuid()))
    local lockKey = Puzzle.LockKey(floorid, objid)
    local placed = nil
    for key, home in pairs(Puzzle.Homes(id)) do
        if home.kind == "lock" and home.floorid == floorid and home.objid == objid then
            placed = home.placed
            Puzzle.RemoveHome(id, key)
        end
    end
    local oldLocks = Puzzle.ReadConfig(id).locks
    local lock = type(oldLocks) == "table" and oldLocks[lockKey] or nil
    if type(lock) == "table" then
        oldLocks[lockKey] = nil
        Puzzle.SetConfig(id, { locks = oldLocks })
        local newLocks = Puzzle.ReadConfig(newId).locks
        if type(newLocks) ~= "table" then
            newLocks = {}
        end
        newLocks[lockKey] = lock
        Puzzle.SetConfig(newId, { locks = newLocks })
    end
    PuzzlePlace.LockObject(floorid, objid, newId, placed)
    return newId
end

--Place a lock object for a puzzle on empty floor. A combination lock puzzle gets
--the Combination lock object; the rest the Puzzle switch. Returns the object.
---@param floorid string
---@param x number
---@param y number
---@param id string
---@return any|nil
function PuzzlePlace.PlaceLockObject(floorid, x, y, id)
    local floor = game.GetFloor(floorid)
    if floor == nil then
        return nil
    end
    local assetid = cond(Puzzle.GetTypeId(id) == "combination", PuzzlePlace.COMBINATION_OBJECT, PuzzlePlace.LOCK_OBJECT)
    local obj = floor:SpawnObjectLocal(assetid)
    if obj == nil then
        return nil
    end
    obj.x = x
    obj.y = y
    for _, component in pairs(obj.components or {}) do
        pcall(function()
            local props = component.properties
            if props ~= nil and props.typeName == "InteractiveContainer" and props:has_key("object")
                and props.object.typeName == "PuzzleLockInteractive" then
                props.object.puzzleid = id
            end
        end)
    end
    obj:Upload()
    Puzzle.IndexPuzzle(id, { kind = "lock", floorid = floorid, objid = obj.objid, placed = "object" })
    return obj
end

--Take a puzzle off an object: what placing it added goes (the lock object, or
--the component), a lock the Director set up by hand keeps its component with no
--puzzle. The puzzle's targets for that lock are dropped.
---@param id string
---@param home PuzzleHome
function PuzzlePlace.ClearLock(id, home)
    local floorid, objid = home.floorid, home.objid
    if floorid == nil or objid == nil then
        return
    end
    local obj = game.LookupObject(floorid, objid)
    if obj ~= nil and obj.valid then
        if home.placed == "object" then
            obj:Destroy()
        else
            for _, ref in ipairs(PuzzlePlace.Locks(floorid, objid)) do
                if ref.lock.puzzleid == id then
                    if home.placed == "component" then
                        obj:RemoveComponent(ref.key)
                        obj:Upload()
                    else
                        ref.component:BeginChanges()
                        ref.lock.puzzleid = ""
                        ref.component:CompleteChanges("Clear puzzle lock")
                    end
                end
            end
        end
    end
    if Puzzle.Exists(id) then
        local locks = Puzzle.ReadConfig(id).locks
        local lockKey = Puzzle.LockKey(floorid, objid)
        if type(locks) == "table" and locks[lockKey] ~= nil then
            locks[lockKey] = nil
            Puzzle.SetConfig(id, { locks = locks })
        end
    end
end

--Take a puzzle's tags off a page (all of them, or the one the home names).
---@param id string
---@param home PuzzleHome
function PuzzlePlace.ClearPage(id, home)
    local page = home.docid ~= nil and Page(home.docid) or nil
    if page == nil then
        return
    end
    local original = DeepCopy(page)
    local text = page:GetTextContent() or ""
    local changed = false
    for key in pairs(Puzzle.PageTags(page, id)) do
        if home.tag == nil or key == home.tag then
            --the tag's own line goes with it; a tag inside a line leaves the line.
            local pattern = "%[%[" .. key:gsub("%p", "%%%0") .. "[^%]]*%]%]"
            local before = text
            text = text:gsub("\n[ \t]*" .. pattern .. "[ \t]*\n", "\n")
            text = text:gsub("^[ \t]*" .. pattern .. "[ \t]*\n?", "")
            text = text:gsub(pattern, "")
            if text ~= before then
                changed = true
            end
            page.annotations[key] = nil
        end
    end
    if changed then
        page:SetTextContent(text)
        page:Upload(original)
    end
end

--Take a puzzle out of one of its places, and the place out of its homes.
---@param id string
---@param key string
function PuzzlePlace.RemoveHome(id, key)
    local home = Puzzle.Homes(id)[key]
    if home == nil then
        return
    end
    if home.kind == "lock" then
        PuzzlePlace.ClearLock(id, home)
    elseif home.kind == "journal" then
        PuzzlePlace.ClearPage(id, home)
    elseif home.kind == "table" then
        Tabletop.RemoveDocItem(PuzzlePlace.EntryId(id))
    elseif home.kind == "rail" then
        IconRailKeyPurge(PuzzlePlace.RailKey(id))
    end
    Puzzle.RemoveHome(id, key)
end

--Take a puzzle out of every place it lives. The puzzle stays in the panel.
---@param id string
function PuzzlePlace.RemoveEverywhere(id)
    for key in pairs(Puzzle.Homes(id)) do
        PuzzlePlace.RemoveHome(id, key)
    end
end

--Remove a puzzle for good: no lock is left pointing at it (a lock object would
--otherwise quietly start a fresh puzzle under the old id), then its board,
--status and index entry are cleared. Pages keep their tags.
---@param id string
function PuzzlePlace.Forget(id)
    local objects = {}
    for _, home in pairs(Puzzle.Homes(id)) do
        if home.kind == "lock" and home.floorid ~= nil and home.objid ~= nil then
            objects[#objects + 1] = { home.floorid, home.objid }
        end
    end
    local locks = Puzzle.Exists(id) and Puzzle.ReadConfig(id).locks or nil
    for _, lock in pairs(type(locks) == "table" and locks or {}) do
        if type(lock) == "table" and lock.floorid ~= nil and lock.objid ~= nil then
            objects[#objects + 1] = { lock.floorid, lock.objid }
        end
    end
    for _, o in ipairs(objects) do
        for _, ref in ipairs(PuzzlePlace.Locks(o[1], o[2])) do
            if ref.lock.puzzleid == id then
                ref.component:BeginChanges()
                ref.lock.puzzleid = ""
                ref.component:CompleteChanges("Clear puzzle lock")
            end
        end
    end
    Puzzle.Forget(id)
end

--Encounter of the Week: markup-zone setup and reveals.
--
--Two script features live here, both keyed by an ENVIRONMENTAL KEYWORD name
--(the zone type an author painted with the Map Markup panel, e.g. "Trap"):
--
--  * Encounter setup instructions -- a "Label: Place <n> <Object> objects in
--    <Zone> zones [and delete other <Zone> zones]" paragraph under
--    "# Encounter" (parsed by EncounterScript.ParseSetupInstruction). The
--    host runs every instruction ONCE, right before the encounter beat spawns
--    its monsters (RunEncounterSetup): <n> tiles are drawn at random from all
--    the <Zone> zones on the map, one <Object> (an object asset, by name) is
--    placed on each, and with the delete clause every <Zone> tile that was
--    not drawn is removed from its zone record -- so the only <Zone> zones
--    left on the map are the ones with an object in them.
--  * Zone reveals -- a montage/narrative clause "Reveal Traps during the next
--    combat" (effect kind "revealzones", banked by EncounterMontage.ApplyEffects
--    as doc.data.revealZones[zone]). When the encounter beat comes,
--    ApplyPendingReveals (host) flips playerVisible on every <Zone> zone on
--    the map and stamps doc.data.zonesRevealed[zone]; every client's driver
--    tick then adds the keyword to its own mapoverlay:shownzones preference
--    (ClientTick), so the players see the zones striped on the map without
--    touching the overlay menu themselves.
--
--Document state (top level of the eotwscript document, next to initiative):
--  data.zoneSetup = { at, entries = { { label, kind, object, objectId, zone,
--                     keywordid, qty, placed = { {objid, floorid, x, y}, ... },
--                     error = nil | "..." }, ... },
--                     original = { [zoneid] = { floorid, record } } }
--                   -- every zone record the setup rewrote or removed, as it
--                      was, so a test reset can put the map back.
--  data.revealZones = { [zone] = { entryName, at } }   -- banked by the clause
--  data.zonesRevealed = { [zone] = { keywordid, at, entryName,
--                         original = { [zoneid] = { floorid, record } } } }
--                   -- applied; clients switch their overlay on from this.
--  data.revealObjects = { [name] = { name, entryName, at } }  -- banked by
--                       "reveal the <Object> object"
--  data.objectsRevealed = { [name] = { name, entryName, at,
--                         switched = { {objid, floorid}, ... } } }
--                   -- applied: the inactive objects switched on.
--  data.startZones = { [zone] = { entryName, at } }  -- "the <Zone> zone
--                    becomes a starting area"; the start-zone confinement
--                    reads it (and the zone is revealed like any other).
--
--Everything is idempotent against the document, so the host tick may call
--the two host entry points every 0.5s until the beat moves on.

local mod = dmhub.GetModLoading()

EncounterZones = rawget(_G, "EncounterZones") or {}

local function Doc()
    return EncounterMontage.GetDoc()
end

local function lower(s)
    return string.lower(tostring(s or ""))
end

--- keywords and zones ---------------------------------------------------------

--The environmental keyword whose name matches (case-insensitive, and the
--plural "traps" for a keyword named "Trap"). id, keyword or nil.
function EncounterZones.FindKeyword(name)
    name = lower(name)
    for k, v in unhidden_pairs(dmhub.GetTable("environmentalKeywords") or {}) do
        local n = lower(v.name)
        if n == name or n .. "s" == name or n == name .. "s" then
            return k, v
        end
    end
    return nil
end

--Every markup zone record of the keyword on the current map:
--{ { floor, floorid, floorIndex, zoneid, record }, ... }. Matches by keyword
--id, with the record's keywordName as a fallback (the same heal-by-name rule
--MapMarkup and the Start-zone lookup use). Surfaces and holes carry a
--category and are never zones.
function EncounterZones.ZoneRecords(name)
    local map = game.currentMap
    if map == nil then
        return {}
    end
    name = lower(name)
    local keywordid = EncounterZones.FindKeyword(name)
    local result = {}
    for _, floor in ipairs(map.floors or {}) do
        local zones, floorIndex, floorid = nil, nil, nil
        pcall(function()
            zones = floor.markupZones
            floorIndex = floor.floorIndex
            floorid = floor.floorid
        end)
        if zones ~= nil and floorIndex ~= nil and floorIndex >= 0 then
            for zoneid, record in pairs(zones) do
                if type(record) == "table" and record.category == nil then
                    local kn = lower(record.keywordName)
                    if (keywordid ~= nil and record.keyword == keywordid) or kn == name or kn == name .. "s" then
                        result[#result + 1] = { floor = floor, floorid = floorid, floorIndex = floorIndex, zoneid = zoneid, record = record }
                    end
                end
            end
        end
    end
    table.sort(result, function(a, b) return a.zoneid < b.zoneid end)
    return result
end

--A fresh deep copy of a zone record: the engine's markupZones getter hands
--back the stored table itself, and mutating it in place corrupts undo.
local function CopyRecord(record)
    if type(record) ~= "table" then
        return record
    end
    local result = {}
    for k, v in pairs(record) do
        result[k] = CopyRecord(v)
    end
    return result
end

local function FloorById(floorid)
    local map = game.currentMap
    for _, floor in ipairs((map and map.floors) or {}) do
        if floor.floorid == floorid then
            return floor
        end
    end
    return nil
end

--- objects ---------------------------------------------------------------------

--An object asset by name (case-insensitive; a visible asset beats a hidden
--duplicate). id, node or nil. An object node's display name is its
--`description` field (what the Objects panel shows); `name` is not exposed.
function EncounterZones.FindObjectAsset(name)
    local want = lower(name)
    local hiddenMatch = nil
    for id, node in pairs(assets.allObjects or {}) do
        local isFolder, shown = false, nil
        pcall(function() isFolder = node.isfolder == true end)
        pcall(function() shown = node.description end)
        if not isFolder and type(shown) == "string" and lower(shown) == want then
            if not node.hidden then
                return id, node
            end
            hiddenMatch = hiddenMatch or { id = id, node = node }
        end
    end
    if hiddenMatch ~= nil then
        return hiddenMatch.id, hiddenMatch.node
    end
    return nil
end

local function FindObjectInstance(floorid, objid)
    local floor = FloorById(floorid)
    if floor == nil then
        return nil
    end
    local obj = nil
    pcall(function() obj = floor.objects[objid] end)
    return obj
end

--- encounter setup (host) -----------------------------------------------------

--Run one "placeobjects" instruction. Returns the entry recorded on the
--document. Every zone record it touches is copied into `original` first.
local function PlaceObjects(instruction, original)
    local entry = {
        label = instruction.label,
        kind = instruction.kind,
        object = instruction.object,
        zone = instruction.zone,
        qty = instruction.qty,
        deleteOthers = instruction.deleteOthers == true,
        placed = {},
    }

    local objectId = EncounterZones.FindObjectAsset(instruction.object)
    if objectId == nil then
        entry.error = string.format("no object asset named '%s'", tostring(instruction.object))
        return entry
    end
    entry.objectId = objectId

    local zones = EncounterZones.ZoneRecords(instruction.zone)
    entry.keywordid = EncounterZones.FindKeyword(instruction.zone)
    if #zones == 0 then
        entry.error = string.format("the map has no '%s' zones", tostring(instruction.zone))
        return entry
    end

    --every tile of every zone of the keyword, in a stable order, then a
    --uniform draw without replacement.
    local tiles = {}
    for zi, z in ipairs(zones) do
        for li, l in ipairs(z.record.locs or {}) do
            tiles[#tiles + 1] = { zone = zi, index = li, x = math.floor(l.x), y = math.floor(l.y) }
        end
    end
    if #tiles == 0 then
        entry.error = string.format("the '%s' zones cover no tiles", tostring(instruction.zone))
        return entry
    end
    local want = math.min(instruction.qty, #tiles)
    if want < instruction.qty then
        entry.warning = string.format("only %d %s tiles for %d objects", #tiles, tostring(instruction.zone), instruction.qty)
    end
    local chosen = {}
    for i = 1, want do
        local pick = math.random(i, #tiles)
        tiles[i], tiles[pick] = tiles[pick], tiles[i]
        chosen[#chosen + 1] = tiles[i]
    end

    --place the objects (tile-center convention: Loc (x,y) is centered on
    --world (x,y)).
    local keptByZone = {}
    for _, tile in ipairs(chosen) do
        local z = zones[tile.zone]
        keptByZone[tile.zone] = keptByZone[tile.zone] or {}
        table.insert(keptByZone[tile.zone], { x = tile.x, y = tile.y })
        local obj = z.floor:SpawnObjectLocal(objectId, { posx = tile.x, posy = tile.y })
        if obj == nil then
            entry.error = string.format("SpawnObjectLocal returned nil for '%s'", tostring(instruction.object))
        else
            obj:Upload()
            entry.placed[#entry.placed + 1] = { objid = obj.objid, floorid = z.floorid, x = tile.x, y = tile.y }
        end
    end

    --trim the zones to the drawn tiles.
    if instruction.deleteOthers then
        for zi, z in ipairs(zones) do
            local kept = keptByZone[zi]
            original[z.zoneid] = original[z.zoneid] or { floorid = z.floorid, record = CopyRecord(z.record) }
            if kept == nil then
                z.floor:RemoveMarkupZone(z.zoneid)
            elseif #kept < #(z.record.locs or {}) then
                local record = CopyRecord(z.record)
                record.locs = kept
                z.floor:SetMarkupZone(z.zoneid, record)
            end
        end
    end
    return entry
end

--Host: run the encounter beat's setup instructions exactly once. Safe to
--call every tick: the document remembers it ran. Returns true once the
--setup is on the document (this call or an earlier one).
function EncounterZones.RunEncounterSetup(beat)
    local doc = Doc()
    if doc.data.zoneSetup ~= nil then
        return true
    end
    local instructions = (beat and beat.setup) or {}
    local setup = { at = dmhub.serverTime, entries = {}, original = {} }
    if #instructions > 0 then
        ElevateToHostPermissions()
        local ok, err = pcall(function()
            for _, instruction in ipairs(instructions) do
                if instruction.kind == "placeobjects" then
                    local entry = PlaceObjects(instruction, setup.original)
                    setup.entries[#setup.entries + 1] = entry
                    if entry.error ~= nil then
                        printf("EotW zones: setup '%s' failed: %s", tostring(instruction.label), entry.error)
                    else
                        printf("EotW zones: setup '%s': placed %d x '%s' in %s zones%s%s", tostring(instruction.label),
                            #entry.placed, tostring(instruction.object), tostring(instruction.zone),
                            cond(instruction.deleteOthers, " and trimmed the other zones", ""),
                            cond(entry.warning ~= nil, " (" .. tostring(entry.warning) .. ")", ""))
                    end
                elseif instruction.kind == "bystanders" then
                    --nothing to place: GatherCombatSides reads these when
                    --combat starts.
                    setup.entries[#setup.entries + 1] = { label = instruction.label, kind = "bystanders", text = instruction.text }
                else
                    setup.entries[#setup.entries + 1] = { label = instruction.label, kind = "unknown", text = instruction.text, error = "unrecognized instruction" }
                    printf("EotW zones: setup '%s' is not understood: %s", tostring(instruction.label), tostring(instruction.text))
                end
            end
        end)
        DropHostPermissions()
        if not ok then
            printf("EotW zones: encounter setup failed: %s", tostring(err))
            setup.error = tostring(err)
        end
    end
    doc:BeginChange()
    doc.data.zoneSetup = setup
    doc:CompleteChange("Encounter zone setup", { undoable = false })
    return true
end

--- reveals ---------------------------------------------------------------------

--Bank a reveal (called by ApplyEffects inside its open change on the doc).
function EncounterZones.BankReveal(doc, zone, entryName)
    doc.data.revealZones = doc.data.revealZones or {}
    doc.data.revealZones[zone] = { entryName = entryName, at = dmhub.serverTime }
end

--Host: make every banked zone type visible to the players. Idempotent --
--an applied reveal moves from revealZones to zonesRevealed.
function EncounterZones.ApplyPendingReveals()
    local doc = Doc()
    local pending = doc.data.revealZones
    if type(pending) ~= "table" or next(pending) == nil then
        return
    end
    local revealed = {}
    ElevateToHostPermissions()
    local ok, err = pcall(function()
        for zone, info in pairs(pending) do
            local keywordid = EncounterZones.FindKeyword(zone)
            local original = {}
            local count = 0
            for _, z in ipairs(EncounterZones.ZoneRecords(zone)) do
                if z.record.playerVisible ~= true then
                    original[z.zoneid] = { floorid = z.floorid, record = CopyRecord(z.record) }
                    local record = CopyRecord(z.record)
                    record.playerVisible = true
                    z.floor:SetMarkupZone(z.zoneid, record)
                end
                count = count + 1
            end
            revealed[zone] = { keywordid = keywordid, at = dmhub.serverTime, entryName = info.entryName, original = original }
            printf("EotW zones: revealed %d %s zone(s) to the players", count, tostring(zone))
        end
    end)
    DropHostPermissions()
    if not ok then
        printf("EotW zones: reveal failed: %s", tostring(err))
        return
    end
    doc:BeginChange()
    doc.data.zonesRevealed = doc.data.zonesRevealed or {}
    for zone, info in pairs(revealed) do
        doc.data.zonesRevealed[zone] = info
    end
    doc.data.revealZones = nil
    doc:CompleteChange("Encounter zones revealed", { undoable = false })
end

--- object reveals and extra start zones ---------------------------------------

--Every object on the current map whose name (or description) is `name`,
--case-insensitive: { { obj, floorid }, ... }.
local function ObjectsNamed(name)
    local want = lower(name)
    local result = {}
    local map = game.currentMap
    for _, floor in ipairs((map and map.floors) or {}) do
        local objects = nil
        pcall(function() objects = floor.objects end)
        for _, obj in pairs(objects or {}) do
            local shown, desc = nil, nil
            pcall(function() shown = obj.name end)
            pcall(function() desc = obj.description end)
            if (type(shown) == "string" and lower(shown) == want) or (type(desc) == "string" and lower(desc) == want) then
                result[#result + 1] = { obj = obj, floorid = floor.floorid }
            end
        end
    end
    return result
end

--Host: switch on every object a montage clause revealed ("reveal the
--Treasure Chest object"). The author leaves such an object inactive (Object
--Properties -> deactivate) so it is not on the map unless the party earns
--it. Idempotent: an applied reveal moves from revealObjects to
--objectsRevealed, with what it switched on so a test reset can switch it off.
function EncounterZones.ApplyPendingObjectReveals()
    local doc = Doc()
    local pending = doc.data.revealObjects
    if type(pending) ~= "table" or next(pending) == nil then
        return
    end
    local revealed = {}
    ElevateToHostPermissions()
    local ok, err = pcall(function()
        for key, info in pairs(pending) do
            local switched = {}
            local found = ObjectsNamed(info.name or key)
            for _, entry in ipairs(found) do
                if entry.obj.inactive then
                    entry.obj.inactive = false
                    entry.obj:Upload()
                    switched[#switched + 1] = { objid = entry.obj.objid, floorid = entry.floorid }
                end
            end
            revealed[key] = { name = info.name, entryName = info.entryName, at = dmhub.serverTime, switched = switched }
            printf("EotW zones: revealed %d '%s' object(s) (%d found on the map)", #switched, tostring(info.name or key), #found)
        end
    end)
    DropHostPermissions()
    if not ok then
        printf("EotW zones: object reveal failed: %s", tostring(err))
        return
    end
    doc:BeginChange()
    doc.data.objectsRevealed = doc.data.objectsRevealed or {}
    for key, info in pairs(revealed) do
        doc.data.objectsRevealed[key] = info
    end
    doc.data.revealObjects = nil
    doc:CompleteChange("Encounter objects revealed", { undoable = false })
end

--The extra zone types a montage clause opened for the heroes to start in
--("the Start2 zone becomes a starting area"), lower-cased. Read by every
--client's start-zone confinement.
function EncounterZones.UnlockedStartZones()
    local result = {}
    pcall(function()
        local zones = Doc().data.startZones
        if type(zones) == "table" then
            for zone, _ in pairs(zones) do
                result[#result + 1] = zone
            end
        end
    end)
    table.sort(result)
    return result
end

--- every client: the overlay --------------------------------------------------

--mapoverlay:shownzones is a ';'-joined list of keyword ids (a per-user
--preference; zone types default hidden). Returns true when it changed.
local function ShowZoneType(keywordid)
    local str = tostring(dmhub.GetSettingValue("mapoverlay:shownzones") or "")
    local ids = {}
    for id in string.gmatch(str, "[^;]+") do
        if id == keywordid then
            return false
        end
        ids[#ids + 1] = id
    end
    ids[#ids + 1] = keywordid
    dmhub.SetSettingValue("mapoverlay:shownzones", table.concat(ids, ";"))
    return true
end

--each reveal stamp is applied to this client's preference once, so a user
--who turns the type back off afterwards is not fought.
local m_appliedReveals = {}

function EncounterZones.ClientTick()
    local revealed = nil
    pcall(function() revealed = Doc().data.zonesRevealed end)
    if type(revealed) ~= "table" then
        return
    end
    for zone, info in pairs(revealed) do
        local keywordid = info.keywordid or EncounterZones.FindKeyword(zone)
        local stamp = tostring(info.at)
        if keywordid ~= nil and m_appliedReveals[keywordid] ~= stamp then
            m_appliedReveals[keywordid] = stamp
            if ShowZoneType(keywordid) then
                printf("EotW zones: showing %s zones on the map overlay", tostring(zone))
            end
        end
    end
end

--- test reset -----------------------------------------------------------------

--Undo everything this module put on the map: delete the placed objects and
--restore every zone record the setup or a reveal rewrote or removed. Must be
--called under the host elevation (ResetTest holds it); the caller clears the
--document fields afterwards.
function EncounterZones.ResetMap(doc)
    local setup = doc.data.zoneSetup
    if type(setup) == "table" then
        local removed = 0
        for _, entry in ipairs(setup.entries or {}) do
            for _, placed in ipairs(entry.placed or {}) do
                local obj = FindObjectInstance(placed.floorid, placed.objid)
                if obj ~= nil then
                    obj:Destroy()
                    removed = removed + 1
                end
            end
        end
        for zoneid, info in pairs(setup.original or {}) do
            local floor = FloorById(info.floorid)
            if floor ~= nil then
                floor:SetMarkupZone(zoneid, CopyRecord(info.record))
            end
        end
        printf("EotW zones: reset removed %d placed object(s) and restored the zones", removed)
    end
    local revealed = doc.data.zonesRevealed
    if type(revealed) == "table" then
        for _, info in pairs(revealed) do
            for zoneid, orig in pairs(info.original or {}) do
                --a zone the setup also rewrote was restored above, in full.
                if not (type(setup) == "table" and setup.original ~= nil and setup.original[zoneid] ~= nil) then
                    local floor = FloorById(orig.floorid)
                    if floor ~= nil then
                        floor:SetMarkupZone(zoneid, CopyRecord(orig.record))
                    end
                end
            end
        end
    end
    local objectsRevealed = doc.data.objectsRevealed
    if type(objectsRevealed) == "table" then
        for _, info in pairs(objectsRevealed) do
            for _, switched in ipairs(info.switched or {}) do
                local obj = FindObjectInstance(switched.floorid, switched.objid)
                if obj ~= nil and not obj.inactive then
                    obj.inactive = true
                    obj:Upload()
                end
            end
        end
    end
    m_appliedReveals = {}
end

function EncounterZones.ClearDocState(doc)
    doc.data.zoneSetup = nil
    doc.data.revealZones = nil
    doc.data.zonesRevealed = nil
    doc.data.revealObjects = nil
    doc.data.objectsRevealed = nil
    doc.data.startZones = nil
end

--- dev command -----------------------------------------------------------------

pcall(function()
    Commands.RegisterMacro{
        name = "eotwzones",
        summary = "run or inspect the Encounter of the Week zone setup and reveals",
        doc = "Usage: /eotwzones setup | reveal <zone> | apply | state | reset\nsetup runs the current map script's # Encounter setup instructions (e.g. placing traps) right here; reveal <zone> banks a reveal of that zone type; apply flips banked reveals live; state prints the zone state; reset deletes the placed objects and restores the zones (the script document keeps everything else).",
        command = function(str)
            local arg = string.lower(string.gsub(str or "", "^%s*(.-)%s*$", "%1"))
            local doc = Doc()
            if arg == "setup" then
                local script = EncounterMontage.FindMapScript(true)
                local beat = nil
                for _, b in ipairs(script.parse.beats) do
                    if b.kind == "encounter" then
                        beat = b
                        break
                    end
                end
                if beat == nil then
                    print("EotW zones: this map's script has no encounter beat")
                    return
                end
                if doc.data.zoneSetup ~= nil then
                    print("EotW zones: setup already ran; /eotwzones reset first")
                    return
                end
                EncounterZones.RunEncounterSetup(beat)
                print(json(doc.data.zoneSetup))
            elseif string.match(arg, "^reveal%s+%S") then
                local zone = string.match(arg, "^reveal%s+(.+)$")
                doc:BeginChange()
                EncounterZones.BankReveal(doc, zone, "dev command")
                doc:CompleteChange("Bank zone reveal", { undoable = false })
                printf("EotW zones: banked a reveal of %s zones", zone)
            elseif arg == "apply" then
                EncounterZones.ApplyPendingReveals()
                EncounterZones.ClientTick()
            elseif arg == "reset" then
                ElevateToHostPermissions()
                local ok, err = pcall(EncounterZones.ResetMap, doc)
                DropHostPermissions()
                if not ok then
                    printf("EotW zones: reset failed: %s", tostring(err))
                end
                doc:BeginChange()
                EncounterZones.ClearDocState(doc)
                doc:CompleteChange("Zone test reset", { undoable = false })
            else
                print(json{ zoneSetup = doc.data.zoneSetup, revealZones = doc.data.revealZones, zonesRevealed = doc.data.zonesRevealed })
            end
        end,
    }
end)

local mod = dmhub.GetModLoading()

--============================================================================
--MapTools: exactly ONE map-editing tool is armed at a time.
--
--Every panel that edits the map arms a tool the engine polls each frame:
--
--  Building Editor   dmhub.GetSelectedFloor / GetSelectedWall
--  Terrain Editor    dmhub.GetSelectedTerrain
--  Effects Editor    dmhub.GetSelectedEffect
--  Objects           dmhub.ObjectEditingEnabled / GetSelectedObject
--  Whiteboard        dmhub.GetActiveWhiteboardTool
--  Elevation Editor  dmhub.GetHeightEditingInfo
--  Map Markup        all of the above, chained, plus custom map tools
--
--That used to be mutually exclusive for free, because "armed" meant "holds
--GUI focus" and focus is exclusive. Map Markup and the Elevation Editor then
--moved to an EXPLICIT latch (the markup arming rework; report W9BJHDAQ):
--losing focus no longer disarms them, for good reasons - but it also means
--two tools can now be armed at once, and the ENGINE breaks that tie by
--PRIORITY, not by what the user last picked up. GameController.selectedLayer
--reads terrain, then building, then effects; height editing pre-empts
--building strokes (FinishRect / FinishEllipse); a custom map tool suppresses
--all of them (DMSheetHud.isCustomToolActive). So an armed Map Markup panel
--sitting in a background tab quietly turned the Effects Editor into a
--wall-drawing tool, with nothing on screen to say why.
--
--This registry restores the invariant explicitly: arming is a CLAIM, and a
--claim puts every other tool down. Losing GUI focus on its own still means
--nothing - clicking the chat panel or a character sheet leaves your tool
--exactly where it was - but arming another MAP tool disarms this one, and
--visibly: a disarm handler must clear its panel's armed indicator and give
--up focus, so the panel that stopped being live looks like it.
--============================================================================

--Idempotent across single-file reloads: the registry outlives this chunk, so
--reloading it must not orphan the panels that registered against the old
--table. Reading an undeclared global raises in this runtime, hence rawget.
MapTools = rawget(_G, "MapTools") or {}

--id -> disarm function.
MapTools.owners = MapTools.owners or {}

--The id that currently owns the map, or nil when nothing is armed.
MapTools.current = MapTools.current or nil

--Re-entrancy guard. A disarm handler drops GUI focus and fires panel events,
--either of which can land back in Claim; the cascade must not re-order
--ownership half way through it.
MapTools.claiming = false

--Register a participant.
--
--`disarm` must put the tool down AND make that visible: clear the armed
--indicator, give up GUI focus if it holds it. It is called for every
--participant except the claimant, whether or not that participant believes
--it is armed, so it has to be safe to call on an already-disarmed tool and
--on one whose panel no longer exists.
function MapTools.Register(id, disarm)
    MapTools.owners[id] = disarm
end

function MapTools.Unregister(id)
    MapTools.owners[id] = nil
    if MapTools.current == id then
        MapTools.current = nil
    end
end

--"I am armed now." Puts every other registered tool down.
function MapTools.Claim(id)
    if MapTools.claiming or MapTools.current == id then
        return
    end

    MapTools.claiming = true
    MapTools.current = id

    --Snapshot the ids first: a disarm handler may register or unregister
    --participants, and mutating owners while iterating it is undefined.
    local ids = {}
    for otherId,_ in pairs(MapTools.owners) do
        ids[#ids+1] = otherId
    end

    for _,otherId in ipairs(ids) do
        if otherId ~= id then
            local disarm = MapTools.owners[otherId]
            if disarm ~= nil then
                disarm()
            end
        end
    end

    MapTools.claiming = false
end

--"I put my tool down." Only clears ownership if we still hold it: a tool
--being disarmed BY someone else's claim must not wipe the new owner on its
--way out, and the order of focus events between two panels is not fixed.
function MapTools.Release(id)
    if MapTools.current == id then
        MapTools.current = nil
    end
end

--True if some OTHER tool owns the map. Not a gate anyone needs today (a
--claim disarms directly), but the honest way for a poll-based caller to ask.
function MapTools.OwnedByOther(id)
    return MapTools.current ~= nil and MapTools.current ~= id
end

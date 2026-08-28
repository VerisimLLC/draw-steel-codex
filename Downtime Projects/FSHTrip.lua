local mod = dmhub.GetModLoading()

--- One hero's fishing outing, from starting to fish until the shop closes
--- Each Trip lives in its own document keyed by the hero, written only by the
--- client that started it. That single-writer rule is what keeps concurrent
--- Trips from racing each other.
--- @class FSHTrip
FSHTrip = RegisterGameType("FSHTrip")

FSHTrip.STATUS = {
    DTConstant.CreateNew("casting", 1, "Casting"),
    DTConstant.CreateNew("event", 2, "Resolving Event"),
    DTConstant.CreateNew("shopping", 3, "Shopping"),
    DTConstant.CreateNew("closed", 4, "Closed")
}

FSHTrip.STATUS.CASTING = FSHTrip.STATUS[1]
FSHTrip.STATUS.EVENT = FSHTrip.STATUS[2]
FSHTrip.STATUS.SHOPPING = FSHTrip.STATUS[3]
FSHTrip.STATUS.CLOSED = FSHTrip.STATUS[4]

--- Results a single cast can produce.
FSHTrip.RESULT = {
    DTConstant.CreateNew("catch", 1, "Catch"),
    DTConstant.CreateNew("gotaway", 2, "The one that got away"),
    DTConstant.CreateNew("breakthrough", 3, "Breakthrough")
}

FSHTrip.RESULT.CATCH = FSHTrip.RESULT[1]
FSHTrip.RESULT.GOTAWAY = FSHTrip.RESULT[2]
FSHTrip.RESULT.BREAKTHROUGH = FSHTrip.RESULT[3]

--- Characteristics the Fishing project allows, best of which is derived at
--- Trip start. Ties break in this order.
FSHTrip.CHARACTERISTICS = {
    DTConstants.CHARACTERISTICS.AGILITY.key,
    DTConstants.CHARACTERISTICS.REASON.key,
    DTConstants.CHARACTERISTICS.INTUITION.key
}

--- Gets the document name for a hero's Trip
--- @param charid string The hero's token id
--- @return string documentName The document name
function FSHTrip.DocumentName(charid)
    return string.format("fsh_trip_%s", charid or "")
end

--- Gets the path for document monitoring in UI
--- @param charid string The hero's token id
--- @return string path The document path for monitoring
function FSHTrip.GetDocumentPath(charid)
    return mod:GetDocumentSnapshot(FSHTrip.DocumentName(charid)).path
end

--- Gets a hero's Trip record
--- @param charid string The hero's token id
--- @return table|nil trip The Trip, or nil when the hero has never fished
function FSHTrip.Get(charid)
    if charid == nil or charid == "" then
        return nil
    end

    local doc = mod:GetDocumentSnapshot(FSHTrip.DocumentName(charid))
    if doc.data == nil or type(doc.data) ~= "table" or doc.data.charid == nil then
        return nil
    end

    return doc.data
end

--- Determines whether a hero has a Trip still running
--- A closed Trip is history: it keeps its document so its summary can be shown,
--- but it no longer blocks the hero from starting another.
--- @param charid string The hero's token id
--- @return boolean live True when the Trip is still going
function FSHTrip.IsLive(charid)
    local trip = FSHTrip.Get(charid)
    return trip ~= nil and trip.status ~= FSHTrip.STATUS.CLOSED.key
end

--- Determines whether this client may drive a hero's Trip
--- Two clients controlling the same hero must not both advance the Trip, so the
--- client that started it owns it for its whole life.
--- @param charid string The hero's token id
--- @return boolean owned True when this client started the Trip
function FSHTrip.IsOwnedByThisClient(charid)
    local trip = FSHTrip.Get(charid)
    return trip ~= nil and trip.runByUserId == dmhub.userid
end

--- Whether a Trip holds a state that can be shown and carried on from
--- Almost every stuck Trip is not broken: it has a status, a stringer and a
--- next move, and only needs someone able to make it. A record whose status is
--- missing or unrecognised has none of that, and is the one kind worth throwing
--- away rather than repairing.
--- @param charid string The character's id
--- @return boolean usable True when there is no Trip, or one that makes sense
function FSHTrip.IsUsable(charid)
    local trip = FSHTrip.Get(charid)
    if trip == nil then
        return true
    end

    for _, status in ipairs(FSHTrip.STATUS) do
        if trip.status == status.key then
            return true
        end
    end

    return false
end

--- Hands a stranded Trip to the player looking at it
--- The single-writer rule keeps two clients from advancing one Trip, but it
--- also strands a Trip whose client has gone: nobody can drive it and nobody
--- can start another. This moves the writer rather than relaxing the rule, and
--- clears any roll the departed client was waiting on, which would otherwise
--- hold the Trip still under its new owner. Nothing that happened is lost - the
--- stringer, the points and the events are all where they were.
--- @param charid string The character's id
--- @return boolean claimed
function FSHTrip.Reset(charid)
    if FSHTrip.Get(charid) == nil then
        return false
    end

    FSHTrip._write(charid, function(data)
        data.runByUserId = dmhub.userid
        data.actionId = nil
        data.eventActionId = nil
    end)

    return true
end

--- Picks the characteristic a hero fishes with
--- The rules allow Agility, Reason, or Intuition and no player would ever pick
--- anything but their best, so the module derives it and shows which it used.
--- @param creature any The hero
--- @return string attrid The characteristic key
--- @return number value The characteristic modifier
function FSHTrip.DeriveCharacteristic(creature)
    local bestId = FSHTrip.CHARACTERISTICS[1]
    local bestValue = nil

    for _, attrid in ipairs(FSHTrip.CHARACTERISTICS) do
        local value = tonumber(creature:GetAttribute(attrid):Modifier()) or 0
        if bestValue == nil or value > bestValue then
            bestId = attrid
            bestValue = value
        end
    end

    return bestId, bestValue or 0
end

--- Lists the skills a hero may fish with
--- Every skill the character has, with no filtering by skill group: fishing has
--- no same-skill restriction and the table enjoys seeing someone fish with
--- Blacksmithing.
--- @param creature any The hero
--- @return DropdownOption[] options List of { id, text } skill options
function FSHTrip.SkillOptions(creature)
    local options = {}

    for _, skill in ipairs(Skill.SkillsInfo) do
        if creature:ProficientInSkill(skill) then
            options[#options + 1] = {
                id = skill.id or skill.name,
                text = skill.name
            }
        end
    end

    table.sort(options, function(a, b) return a.text < b.text end)

    return options
end

--- The downtime rolls a character has left to fish with
--- A follower's rolls are held on the hero they follow, keyed by follower id,
--- so who is asked depends on who is paying.
--- @param charid string The character's id
--- @param rollHolderId string|nil Who holds the counter, the character themselves when nil
--- @return number rolls
function FSHTrip.RollsAvailable(charid, rollHolderId)
    rollHolderId = rollHolderId or charid

    local holder = dmhub.GetCharacterById(rollHolderId)
    if holder == nil or holder.properties == nil then
        return 0
    end

    local info = holder.properties:GetDowntimeInfo()
    if info == nil then
        return 0
    end

    if rollHolderId == charid then
        return info:GetAvailableRolls()
    end

    return info:GetFollowerRolls(charid)
end

--- Determines whether a character may start fishing right now
--- A Trip costs a downtime roll, so having one is part of being able to start.
--- The roll is not taken here: it comes off the first cast.
--- @param charid string The character's id
--- @param rollHolderId string|nil Who holds their downtime rolls
--- @return boolean available True when Start Fishing should be live
--- @return string reason Why not, when unavailable
function FSHTrip.CanStart(charid, rollHolderId)
    if not FSHWater.IsOpen() then
        return false, "No water is open."
    end

    if FSHTrip.IsLive(charid) then
        return false, "This hero is already fishing."
    end

    if FSHTrip.RollsAvailable(charid, rollHolderId) < 1 then
        return false, "No downtime rolls left."
    end

    return true, ""
end

--- Takes the downtime roll a Trip costs, once per Trip
--- Charged on the first cast rather than at the start, so a Trip opened and
--- abandoned costs nothing: nothing can be gained before a cast. Goldenrod
--- recasts through the same door, and the flag is what keeps it free.
--- @param charid string The character's id
--- @return boolean paid True when the Trip is paid up
--- @return string reason Why not, when it is not
function FSHTrip.SpendRoll(charid)
    local trip = FSHTrip.Get(charid)
    if trip == nil then
        return false, "There is no Trip."
    end

    if trip.rollSpent then
        return true, ""
    end

    local rollHolderId = trip.rollHolderId or charid

    --Asked again here rather than trusted from the start: the roll may have
    --gone to a project while the Trip sat open.
    if FSHTrip.RollsAvailable(charid, rollHolderId) < 1 then
        return false, "No downtime rolls left."
    end

    local holder = dmhub.GetCharacterById(rollHolderId)
    if holder == nil then
        return false, "That character is not available."
    end

    DTProjectEditor.AdjustDowntimeRolls(holder, charid, -1)

    FSHTrip._write(charid, function(data)
        data.rollSpent = true
    end)

    return true, ""
end

--- Starts a Trip, capturing the water and the hero's approach
--- Overwrites any previous Trip for this hero wholesale, so a hero's document
--- always describes their current outing and never accumulates.
--- @param token any The character's token
--- @param skill table|nil The chosen skill as { id, name }, or nil for none
--- @param rollHolderId string|nil Who holds their downtime rolls; themselves when nil
--- @return boolean started True when the Trip began
--- @return string reason Why not, when it did not
function FSHTrip.Start(token, skill, rollHolderId)
    if token == nil or not token.valid then
        return false, "That hero is not available."
    end

    local charid = token.id
    local canStart, reason = FSHTrip.CanStart(charid, rollHolderId)
    if not canStart then
        return false, reason
    end

    local attrid, attrValue = FSHTrip.DeriveCharacteristic(token.properties)

    local doc = mod:GetDocumentSnapshot(FSHTrip.DocumentName(charid))
    local sessionId = FSHWater.GetSessionID()

    --Starting a Trip replaces the document, so what earlier Trips amounted to
    --has to be carried across or the Director loses everything but the last
    --one. History belongs to the water session, which is one Respite: a Trip
    --from an earlier session is not this Respite's business.
    local history = {}
    local previous = doc.data
    if type(previous) == "table" and previous.sessionId == sessionId then
        for _, entry in ipairs(previous.history or {}) do
            history[#history + 1] = entry
        end
    end

    doc:BeginChange()
    doc.data = {
        sessionId = sessionId,
        history = history,
        charid = charid,
        runByUserId = dmhub.userid,
        --A follower fishes on their hero's counter, so who pays is settled
        --when the Trip opens rather than worked out again at every cast.
        rollHolderId = rollHolderId or charid,
        rollSpent = false,
        waterName = FSHWater.GetName(),
        waterType = FSHWater.GetWaterType(),
        characteristic = {
            id = attrid,
            value = attrValue
        },
        skill = skill,
        status = FSHTrip.STATUS.CASTING.key,
        casts = {},
        points = cond(FSHConstants.DEBUG_MODE, FSHConstants.DEBUG_STARTING_POINTS, 0),
        events = {},
        purchases = {},
        openedAt = dmhub.serverTime
    }
    doc:CompleteChange("Start fishing trip", { undoable = false })

    --Goldenrod allows one reroll per Trip, so the marker is handed out at the
    --start of each one and taken back when it is spent or the Trip ends.
    if FSHTrip.HasTitle(token.properties, FSHConstants.titleGoldenrod) then
        FSHTrip.SetGoldenrodReroll(charid, true)
    end

    --Start writes the document itself rather than going through _write, so it
    --has to say so on its own.
    FSHTrip._announceChange()

    return true, ""
end

--- Appends a resolved cast and moves the Trip on
--- The cast is already final when it arrives here: every reroll resolves inside
--- the roll dialog, so nothing recorded is ever revised.
--- @param charid string The hero's token id
--- @param cast table The cast record
--- @return boolean recorded True when the cast was stored
function FSHTrip.AddCast(charid, cast)
    local trip = FSHTrip.Get(charid)
    if trip == nil then
        return false
    end

    --A fish handed over by an event is not a cast the player made: it lands
    --while the Trip is still settling that event, so it cannot be held to the
    --casting phase the way a real cast is.
    local fromEvent = cast.fromEvent == true
        and trip.status == FSHTrip.STATUS.EVENT.key

    if trip.status ~= FSHTrip.STATUS.CASTING.key and not fromEvent then
        return false
    end

    local casts = {}
    for _, existing in ipairs(trip.casts or {}) do
        casts[#casts + 1] = existing
    end

    cast.seq = #casts + 1
    casts[#casts + 1] = cast

    local points = (trip.points or 0) + (cast.points or 0)

    --A catch keeps the line in the water; anything else ends casting. A
    --breakthrough owes an event before the shop can open. An event's own fish
    --leaves the phase alone: the event is still settling, and resolving it is
    --what opens the shop.
    local status = trip.status
    if not fromEvent then
        status = FSHTrip.STATUS.CASTING.key
        if cast.result == FSHTrip.RESULT.BREAKTHROUGH.key then
            status = FSHTrip.STATUS.EVENT.key
        elseif cast.result == FSHTrip.RESULT.GOTAWAY.key then
            status = FSHTrip.STATUS.SHOPPING.key
        end
    end

    FSHTrip._write(charid, function(data)
        data.casts = casts
        data.points = points
        data.status = status
    end)

    if cast.result == FSHTrip.RESULT.CATCH.key then
        FSHTrip.RecordCatch(charid, cast)
    end

    return true
end

--- Adds points to a Trip from something other than a cast
--- @param charid string The hero's token id
--- @param points number The points to add
function FSHTrip.AddPoints(charid, points)
    local trip = FSHTrip.Get(charid)
    if trip == nil then
        return
    end

    local total = (trip.points or 0) + (points or 0)
    FSHTrip._write(charid, function(data)
        data.points = total
    end)
end

--- Records the action request a cast is waiting on, or clears it
--- Held on the Trip rather than in a local so a reload mid-cast does not strand
--- the request with nobody left to harvest it.
--- @param charid string The hero's token id
--- @param actionId string|nil The action request id, or nil to clear
function FSHTrip.SetActionId(charid, actionId)
    FSHTrip._write(charid, function(data)
        data.actionId = actionId
    end)
end

--- Whether a hero currently holds a title
--- @param creature any The hero
--- @param titleid string The title's guid
--- @return boolean held True when the hero has it
function FSHTrip.HasTitle(creature, titleid)
    if titleid == nil or titleid == "" then
        return false
    end
    return creature:GetTitles()[titleid] == true
end

--- Whether a hero still has their Goldenrod reroll for this Trip
--- The marker effect's presence is the budget: a Trip is not a round, an
--- encounter, or a respite, so no platform resource can count it.
--- @param charid string The hero's token id
--- @return boolean available True when the reroll is unspent
function FSHTrip.HasGoldenrodReroll(charid)
    local token = dmhub.GetCharacterById(charid)
    if token == nil or not token.valid then
        return false
    end

    local marker = FSHConstants.effectGoldenrodReroll
    if marker == "" then
        return false
    end

    for _, effect in ipairs(token.properties:try_get("ongoingEffects", {})) do
        if effect:try_get("ongoingEffectid") == marker then
            return true
        end
    end

    return false
end

--- Grants or clears the Goldenrod reroll marker
--- @param charid string The hero's token id
--- @param granted boolean Whether the reroll should be available
function FSHTrip.SetGoldenrodReroll(charid, granted)
    local marker = FSHConstants.effectGoldenrodReroll
    if marker == "" then
        return
    end

    local token = dmhub.GetCharacterById(charid)
    if token == nil or not token.valid then
        return
    end

    token:ModifyProperties{
        description = "Fishing Goldenrod reroll",
        undoable = false,
        execute = function()
            if granted then
                token.properties:ApplyOngoingEffect(marker, "indefinite")
            else
                token.properties:RemoveOngoingEffect(marker)
            end
        end
    }
end

--- Drops the most recent cast so it can be rolled again
--- Goldenrod replaces a cast outright, including its effect on whether casting
--- continues, so the Trip goes back to casting with the old points removed.
--- @param charid string The hero's token id
--- @return boolean removed True when a cast was dropped
function FSHTrip.RemoveLastCast(charid)
    local trip = FSHTrip.Get(charid)
    if trip == nil then
        return false
    end

    local casts = {}
    for _, existing in ipairs(trip.casts or {}) do
        casts[#casts + 1] = existing
    end

    local dropped = table.remove(casts)
    if dropped == nil then
        return false
    end

    local points = math.max(0, (trip.points or 0) - (dropped.points or 0))

    FSHTrip._write(charid, function(data)
        data.casts = casts
        data.points = points
        data.status = FSHTrip.STATUS.CASTING.key
    end)

    return true
end

--- Records the action request an event is waiting on, or clears it
--- @param charid string The hero's token id
--- @param actionId string|nil The action request id, or nil to clear
function FSHTrip.SetEventActionId(charid, actionId)
    FSHTrip._write(charid, function(data)
        data.eventActionId = actionId
    end)
end

--- Records a rolled event on a Trip
--- @param charid string The hero's token id
--- @param event table The event record
function FSHTrip.AddEvent(charid, event)
    local trip = FSHTrip.Get(charid)
    if trip == nil then
        return
    end

    local events = {}
    for _, existing in ipairs(trip.events or {}) do
        events[#events + 1] = existing
    end
    events[#events + 1] = event

    FSHTrip._write(charid, function(data)
        data.events = events
        data.eventActionId = nil
    end)
end

--- Marks the Trip's pending event answered
--- @param charid string The hero's token id
--- @param applied string[] What the module did
--- @param owed string[] What a human still owes
function FSHTrip.ResolveEvent(charid, applied, owed)
    local trip = FSHTrip.Get(charid)
    if trip == nil then
        return
    end

    local events = {}
    for _, existing in ipairs(trip.events or {}) do
        if existing.resolved ~= true then
            local merged = {}
            for key, value in pairs(existing) do
                merged[key] = value
            end

            local mergedApplied = {}
            for _, line in ipairs(existing.applied or {}) do
                mergedApplied[#mergedApplied + 1] = line
            end
            for _, line in ipairs(applied or {}) do
                mergedApplied[#mergedApplied + 1] = line
            end

            local mergedOwed = {}
            for _, line in ipairs(existing.owed or {}) do
                mergedOwed[#mergedOwed + 1] = line
            end
            for _, line in ipairs(owed or {}) do
                mergedOwed[#mergedOwed + 1] = line
            end

            merged.applied = mergedApplied
            merged.owed = mergedOwed
            merged.resolved = true
            existing = merged
        end
        events[#events + 1] = existing
    end

    FSHTrip._write(charid, function(data)
        data.events = events
    end)
end

--- The largest catch anyone in the campaign has landed
--- Counts only the heroes the standings actually list. A bestiary is full of
--- hero-typed tokens nobody plays, and a record held by one of those would be
--- unbeatable for a reason no one at the table could see.
--- @return number points The biggest catch, or zero when nobody has fished
function FSHTrip.CampaignBestCatch()
    local best = 0

    for _, token in ipairs(DTBusinessRules.GetAllHeroTokens()) do
        if token.playerControlled then
            local fishing = token.properties:GetFishingRecord()
            local biggest = fishing ~= nil and fishing.biggest or nil
            if biggest ~= nil and (biggest.points or 0) > best then
                best = biggest.points
            end
        end
    end

    return best
end

--- Writes a landed catch into the hero's lifetime record and announces it
--- Read before written: whether this beat anything can only be told against
--- the totals as they stood a moment ago.
--- @param charid string The hero's token id
--- @param cast table The cast that landed
function FSHTrip.RecordCatch(charid, cast)
    local token = dmhub.GetCharacterById(charid)
    if token == nil or not token.valid then
        return
    end

    local trip = FSHTrip.Get(charid)
    local species = cast.species ~= nil and cast.species.name or "fish"
    local points = cast.points or 0

    local fishing = token.properties:GetFishingRecord() or {}
    local previousPersonal = fishing.biggest ~= nil and (fishing.biggest.points or 0) or 0
    local previousCampaign = FSHTrip.CampaignBestCatch()

    local downtimeInfo = token.properties:GetDowntimeInfo()
    if downtimeInfo == nil then
        return
    end

    token:ModifyProperties{
        description = "Record fishing catch",
        undoable = false,
        execute = function()
            downtimeInfo:RecordFishingCatch(points, species,
                trip ~= nil and trip.waterName or "")
        end
    }

    --One banner per moment: beating the campaign says everything beating your
    --own would have, so the larger claim wins rather than both firing.
    if points > previousCampaign and previousCampaign > 0 then
        FSHTrip.Announce(token, "Campaign Record",
            string.format("%s landed a %d %s", token.name or "A hero", points, species))
    elseif points > previousPersonal and previousPersonal > 0 then
        FSHTrip.Announce(token, "Personal Best",
            string.format("%s landed a %d %s", token.name or "A hero", points, species))
    end
end

--- Puts a moment in front of the whole table
--- Uses the same banner a critical hit and Hesitation Is Weakness use, so
--- fishing borrows the table's existing vocabulary rather than inventing one.
--- @param token any The hero's token
--- @param text string The headline
--- @param subtitle string The detail
function FSHTrip.Announce(token, text, subtitle)
    if token == nil or not token.valid then
        return
    end

    DramaticBanner.Show{
        tokenid = token.charid,
        text = text,
        subtitle = subtitle
    }
end

--- Records a purchase and takes its cost out of the Trip's points
--- @param charid string The hero's token id
--- @param name string What was bought
--- @param cost number What it cost
function FSHTrip.AddPurchase(charid, name, cost)
    local trip = FSHTrip.Get(charid)
    if trip == nil then
        return
    end

    local purchases = {}
    for _, existing in ipairs(trip.purchases or {}) do
        purchases[#purchases + 1] = existing
    end
    purchases[#purchases + 1] = {
        name = name,
        cost = cost
    }

    local points = math.max(0, (trip.points or 0) - (cost or 0))

    FSHTrip._write(charid, function(data)
        data.purchases = purchases
        data.points = points
    end)
end

--- Moves a Trip to a new status
--- @param charid string The hero's token id
--- @param status string An FSHTrip.STATUS key
function FSHTrip.SetStatus(charid, status)
    FSHTrip._write(charid, function(data)
        data.status = status
    end)
end

--- Closes a Trip, losing unspent points and updating the hero's record
--- @param charid string The hero's token id
--- @return table|nil summary What the Trip amounted to
function FSHTrip.Close(charid)
    local trip = FSHTrip.Get(charid)
    if trip == nil or trip.status == FSHTrip.STATUS.CLOSED.key then
        return nil
    end

    local catches = 0
    local largest = nil
    for _, cast in ipairs(trip.casts or {}) do
        if cast.result == FSHTrip.RESULT.CATCH.key then
            catches = catches + 1
            if largest == nil or (cast.points or 0) > (largest.points or 0) then
                largest = {
                    points = cast.points,
                    species = cast.species ~= nil and cast.species.name or "fish"
                }
            end
        end
    end

    local bought = {}
    for _, purchase in ipairs(trip.purchases or {}) do
        bought[#bought + 1] = purchase.name
    end

    local summary = {
        catches = catches,
        largest = largest,
        bought = bought,
        lost = trip.points or 0
    }

    --GetTokenById only finds tokens placed on the map. A hero can finish a Trip
    --while off-map, so look the character up instead or the record never lands.
    local token = dmhub.GetCharacterById(charid)
    if token ~= nil and token.valid then
        local downtimeInfo = token.properties:GetDowntimeInfo()
        if downtimeInfo ~= nil then
            token:ModifyProperties{
                description = "Record fishing trip",
                undoable = false,
                execute = function()
                    downtimeInfo:RecordFishingTrip()
                end
            }
        end
    end

    --An unspent reroll does not survive the outing that granted it.
    FSHTrip.SetGoldenrodReroll(charid, false)

    local closedAt = dmhub.serverTime

    FSHTrip._write(charid, function(data)
        data.status = FSHTrip.STATUS.CLOSED.key
        data.summary = summary
        data.closedAt = closedAt

        --The next Trip replaces this document, so what happened here is filed
        --before it can be overwritten. What the Director still owes lives in
        --the events, which is why they are kept whole rather than summarised.
        local history = {}
        for _, entry in ipairs(data.history or {}) do
            history[#history + 1] = entry
        end
        history[#history + 1] = {
            --Carried so a filed Trip renders through the same row as a live
            --one: the log row looks its character up by id.
            charid = charid,
            status = FSHTrip.STATUS.CLOSED.key,
            openedAt = data.openedAt,
            closedAt = closedAt,
            waterName = data.waterName,
            waterType = data.waterType,
            characteristic = data.characteristic,
            skill = data.skill,
            casts = data.casts,
            events = data.events,
            purchases = data.purchases,
            summary = summary,
        }
        data.history = history
    end)

    return summary
end

--- Every Trip a character has run in this water session, oldest first
--- The live Trip comes last when there is one, so the Director reads a Respite
--- in the order it happened rather than in the order the documents were built.
--- @param charid string The character's id
--- @return table[] trips The finished Trips, plus the one still running
function FSHTrip.SessionTrips(charid)
    local trip = FSHTrip.Get(charid)
    if trip == nil then
        return {}
    end

    local trips = {}
    for _, entry in ipairs(trip.history or {}) do
        trips[#trips + 1] = entry
    end

    --A closed Trip is already in the history, so taking it again would show it
    --twice.
    if trip.status ~= FSHTrip.STATUS.CLOSED.key then
        trips[#trips + 1] = trip
    end

    --The log row shows whose Trip it was from this, the way the Water Log
    --stamps it on the way past.
    local token = dmhub.GetCharacterById(charid)
    local name = (token ~= nil and token.name) or "Unnamed Hero"
    for _, entry in ipairs(trips) do
        entry.tokenName = name
        entry.charid = entry.charid or charid
    end

    return trips
end

--- Lists the Trips belonging to the current water session
--- Closed Trips from an earlier session drop away when the Director opens new
--- water, which is what clears the Water Log without deleting any history.
--- @param includeClosed boolean Whether to include Trips that have finished
--- @return table trips The matching Trips
function FSHTrip.TripsThisSession(includeClosed)
    local sessionId = FSHWater.GetSessionID()
    local trips = {}

    if sessionId == "" then
        return trips
    end

    for _, token in ipairs(DTBusinessRules.GetAllHeroTokens()) do
        local trip = FSHTrip.Get(token.id)
        if trip ~= nil and trip.sessionId == sessionId then
            local closed = trip.status == FSHTrip.STATUS.CLOSED.key
            if includeClosed or not closed then
                trip.tokenName = token.name or "Unnamed Hero"
                trips[#trips + 1] = trip
            end
        end
    end

    return trips
end

--- Throws a Trip away so the character can start another
--- The way out of a Trip that cannot be finished: one being run from a client
--- that has since gone, or one waiting on an answer nobody can give. Deletes
--- rather than closes - an abandoned Trip is not a Trip taken, so it earns no
--- record and no summary. A roll already spent on it stays spent, since the
--- casts it paid for happened; one never cast on was never charged. Ownership
--- is deliberately not checked: the player stuck behind a Trip is usually not
--- the client running it.
--- @param charid string The character's id
--- @return boolean abandoned
function FSHTrip.Abandon(charid)
    local doc = mod:GetDocumentSnapshot(FSHTrip.DocumentName(charid))
    if doc.data == nil or type(doc.data) ~= "table" or doc.data.charid == nil then
        return false
    end

    doc:BeginChange()
    doc.data = {}
    doc:CompleteChange("Abandon fishing trip", { undoable = false })

    FSHTrip._announceChange()

    return true
end

--- DESTRUCTIVE Clears every hero's Trip, leaving nobody fishing
--- Trip documents are not history worth keeping: the record on the character is
--- what persists. This wipes the lot so a session can start from nothing.
--- @return number cleared The number of Trips removed
function FSHTrip.ClearAll()
    if not dmhub.isDM then
        return 0
    end

    local cleared = 0

    --Followers fish too, and their Trips live on their own documents. Walking
    --heroes alone left a follower mid-Trip after everything else was wiped.
    local ids = {}
    for _, token in ipairs(DTBusinessRules.GetAllHeroTokens()) do
        ids[#ids + 1] = token.id

        local session = rawget(_G, "RSPSession")
        if session ~= nil then
            for _, followerId in ipairs(session.FollowersOf(token.id, true)) do
                ids[#ids + 1] = followerId
            end
        end
    end

    for _, id in ipairs(ids) do
        local doc = mod:GetDocumentSnapshot(FSHTrip.DocumentName(id))
        if doc.data ~= nil and type(doc.data) == "table" and doc.data.charid ~= nil then
            doc:BeginChange()
            doc.data = {}
            doc:CompleteChange("Clear fishing trip", { undoable = false })
            cleared = cleared + 1
        end
    end

    return cleared
end

--- Applies a change to a Trip document
--- Reads the current record and writes a rebuilt table: handing a document back
--- a table it already owns does not reliably carry the new fields.
--- @param charid string The hero's token id
--- @param Apply fun(data: table) Mutates the rebuilt record
function FSHTrip._write(charid, Apply)
    local doc = mod:GetDocumentSnapshot(FSHTrip.DocumentName(charid))
    if doc.data == nil or type(doc.data) ~= "table" then
        return
    end

    local rebuilt = {}
    for key, value in pairs(doc.data) do
        rebuilt[key] = value
    end

    Apply(rebuilt)

    doc:BeginChange()
    doc.data = rebuilt
    doc:CompleteChange("Update fishing trip", { undoable = false })

    FSHTrip._announceChange()
end

--- Tells the Respite that a Trip moved
--- Trips live in their own documents, which the Respite does not watch, so a
--- breakthrough would otherwise sit unseen on the Director's roster until some
--- unrelated write woke it. Every write to a Trip comes through _write or
--- Start, so those two are the whole of it.
function FSHTrip._announceChange()
    local session = rawget(_G, "RSPSession")
    if session ~= nil and session.Active() ~= nil then
        session.Ping()
    end
end

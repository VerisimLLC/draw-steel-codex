local mod = dmhub.GetModLoading()

--- The Fishing Events table
--- A breakthrough sends the outing here instead of scoring. The module rolls,
--- puts the full text in front of the player, and is explicit about what it
--- applied and what a human still has to run: several of these results are
--- fiction the Director adjudicates, not mechanics.
--- @class FSHEvents
FSHEvents = RegisterGameType("FSHEvents")

--- How a result is handled.
FSHEvents.HANDLING = {
    DTConstant.CreateNew("surface", 1, "Director's to run"),
    DTConstant.CreateNew("applied", 2, "Applied"),
    DTConstant.CreateNew("prompt", 3, "Needs an answer")
}

--- The table itself, verbatim from Draw Steel chapter 11.
FSHEvents.TABLE = {
    [1] = {
        name = "The talking fish",
        handling = "surface",
        text = "While fishing, the hero reels in a talking fish. The fish informs the hero of any events that have occurred within 10 squares of the body of water where they were caught over the last week, or provides one piece of Forbidden Knowledge (see the Discover Lore project), as the Director determines."
    },
    [2] = {
        name = "The note in the bottle",
        handling = "prompt",
        text = "While fishing, the hero reels in a note in a bottle. The note is written in Anjali and binds the reader into a deal with a powerful devil if read out loud. This gives the devil ownership of the reader's soul in exchange for rolling an additional d10 on all future Fishing project rolls."
    },
    [3] = {
        name = "The rumoured rod",
        handling = "surface",
        text = "While the hero is fishing, passersby inform them of a rumor of a magic fishing rod that allows the fisher to double the size of the fish they reel in. The Director can decide whether the rumor is true, and if so, where the rod might be found."
    },
    [4] = {
        name = "The angulotl daybringer",
        handling = "surface",
        text = "While fishing, the hero reels in an angulotl daybringer (see Draw Steel: Monsters). The angulotl is insulted by the hero catching them, and threatens to summon heavy thunderstorms and drown the region in a flood. However, they can be negotiated with, and might provide the hero with one serving of an amazing meal if they stay on good terms."
    },
    [5] = {
        name = "Half a treasure",
        handling = "surface",
        text = "While fishing, the hero reels in half of a mysterious ancient treasure of the Director's choice. If the other half is found, both halves magically meld together to restore the treasure."
    },
    [6] = {
        name = "Fond memories",
        handling = "applied",
        text = "While fishing, the hero is energized by fond memories of their life up to that point. They gain an edge on Presence tests until the end of their next respite."
    },
    [7] = {
        name = "Master of Reels",
        handling = "applied",
        text = "The hero reaches a new fishing milestone, gaining the Master of Reels title: whenever you deal damage to a target who is 2 or more squares away from you and that target isn't also force moved, you can pull the target a number of squares equal to your Agility, Reason, or Intuition score (your choice)."
    },
    [8] = {
        name = "Relaxing meditation",
        handling = "surface",
        text = "While fishing, the hero engages in relaxing meditation that grants an automatic breakthrough on another project they're working on. Alternatively, they gain insight that grants an automatic breakthrough on another hero's project of their choice."
    },
    [9] = {
        name = "The ancient fish",
        handling = "prompt",
        text = "While fishing, the hero is pulled into the water by an ancient fish and must make a hard Might test. On a success, the hero reels in a humongous fish worth 100 points. On a failure, they end the current respite with 1 fewer Recoveries than usual."
    },
    [10] = {
        name = "The underwater cavern",
        handling = "surface",
        text = "While fishing, the hero notes what appears to be an underwater cavern. If the cavern is explored, it reveals a treasure of the Director's choice guarded by a revenant knight fulfilling their duty until their captain returns."
    }
}

--- Might tests already answered, by action id. Same reason as
--- FSHCast._harvested: client-local, never cleared.
FSHEvents._harvested = {}

--- The points an ancient fish is worth on a successful event 9.
FSHEvents.ANCIENT_FISH_POINTS = 100

--- TEMPORARY, FOR TESTING. Zero rolls normally; anything else forces that
--- result. Remove along with the window's picker once the table is trusted.
FSHEvents.testRoll = 0

--- TEMPORARY, FOR TESTING. Options for the forced-result picker
--- @return DropdownOption[] options List of { id, text } options
function FSHEvents.TestRollOptions()
    local options = {
        { id = "0", text = "Random" }
    }

    for roll = 1, 10 do
        options[#options + 1] = {
            id = tostring(roll),
            text = string.format("%d -- %s", roll, FSHEvents.TABLE[roll].name)
        }
    end

    return options
end

--- Puts a resolved breakthrough in front of the table
--- Held until the event is settled rather than fired the moment the dice land:
--- "Breakthrough!" on its own says nothing, and what actually happened is only
--- known once the table has been rolled and any question answered.
--- @param charid string The hero's token id
--- @param event table The resolved event
function FSHEvents.Announce(charid, event)
    local token = dmhub.GetCharacterById(charid)
    if token == nil or not token.valid then
        return
    end

    --The applied line is the specific outcome where there is one; the event's
    --name covers the results a human runs.
    local outcome = event.name or "Something else"
    local applied = event.applied or {}
    if applied[1] ~= nil then
        outcome = applied[1]
    end

    FSHTrip.Announce(token, "Fishing Breakthrough!",
        string.format("%s -- %s", token.name or "A hero", outcome))
end

--- Rolls on the events table for a Trip
--- The roll rides the public pipeline with the hero's token, so the table sees
--- it happen the same way it sees every other roll.
--- @param charid string The hero's token id
function FSHEvents.Roll(charid)
    local trip = FSHTrip.Get(charid)
    if trip == nil or trip.status ~= FSHTrip.STATUS.EVENT.key then
        return
    end

    if trip.eventActionId ~= nil or FSHEvents.Pending(trip) ~= nil then
        return
    end

    if not FSHTrip.IsOwnedByThisClient(charid) then
        return
    end

    local token = dmhub.GetCharacterById(charid)
    if token == nil or not token.valid then
        return
    end

    --A forced result skips the die rather than rolling one and then
    --contradicting it on screen. Gated so a picker left set cannot reach a
    --real table.
    if FSHConstants.DEBUG_MODE and FSHEvents.testRoll > 0 then
        FSHEvents.Apply(charid, FSHEvents.testRoll)
        return
    end

    dmhub.Roll{
        guid = dmhub.GenerateGuid(),
        roll = "1d10",
        description = "Fishing Events",
        tokenid = token.id,
        complete = function(rollInfo)
            FSHEvents.Apply(charid, rollInfo.total or 1)
        end
    }
end

--- The event still waiting on an answer, if any
--- @param trip table The Trip
--- @return table|nil event The unresolved event
function FSHEvents.Pending(trip)
    for _, event in ipairs(trip.events or {}) do
        if event.resolved ~= true then
            return event
        end
    end
    return nil
end

--- Records a rolled event and applies whatever the module can
--- @param charid string The hero's token id
--- @param roll number The d10 result
function FSHEvents.Apply(charid, roll)
    roll = math.max(1, math.min(10, math.floor(roll or 1)))

    local entry = FSHEvents.TABLE[roll]
    local event = {
        roll = roll,
        name = entry.name,
        text = entry.text,
        handling = entry.handling,
        applied = {},
        owed = {},
        resolved = entry.handling ~= "prompt"
    }

    local token = dmhub.GetCharacterById(charid)

    if roll == 6 and token ~= nil and token.valid then
        FSHEvents._applyOngoingEffect(token, FSHConstants.effectFondMemories)
        event.applied[#event.applied + 1] =
            "An edge on Presence tests, until the end of your next respite."
    elseif roll == 7 and token ~= nil and token.valid then
        FSHEvents._grantTitle(token, FSHConstants.titleMasterOfReels)
        event.applied[#event.applied + 1] =
            "The Master of Reels title. Choose its characteristic on your character sheet."
    end

    if entry.handling == "surface" then
        event.owed[#event.owed + 1] = "The Director runs this one."
    end

    FSHTrip.AddEvent(charid, event)

    --Nothing left to answer means this is already the whole story.
    if event.resolved then
        FSHEvents.Announce(charid, event)
        FSHTrip.SetStatus(charid, FSHTrip.STATUS.SHOPPING.key)
    end
end

--- Answers event 2: whether the note is read aloud
--- @param charid string The hero's token id
--- @param readAloud boolean Whether the hero reads it
function FSHEvents.AnswerNote(charid, readAloud)
    local token = dmhub.GetCharacterById(charid)

    local applied = {}
    if readAloud and token ~= nil and token.valid then
        FSHEvents._grantTitle(token, FSHConstants.titleDevilsBargain)
        applied[#applied + 1] =
            "The devil owns your soul. Every future cast rolls an additional d10."
    else
        applied[#applied + 1] = "The note goes back in the bottle. Nothing changes."
    end

    FSHEvents._resolve(charid, applied, {})
end

--- Asks the hero's player for the hard Might test event 9 demands
--- This is an ordinary attribute test, so it uses the platform's built-in check
--- rather than anything fishing-specific: no fishing modifier belongs on it.
--- @param charid string The hero's token id
--- @return boolean asked True when a request went out
function FSHEvents.RequestMightTest(charid)
    local trip = FSHTrip.Get(charid)
    if trip == nil or trip.eventActionId ~= nil then
        return false
    end

    if not FSHTrip.IsOwnedByThisClient(charid) then
        return false
    end

    local check = RollCheck.new{
        type = "attribute",
        id = DTConstants.CHARACTERISTICS.MIGHT.key,
        text = "Might",
        explanation = "Pulled under by an ancient fish",
        silent = false,
        options = {}
    }

    local actionId = dmhub.SendActionRequest(RollRequest.new{
        title = "The ancient fish",
        checks = { check },
        tokens = { [charid] = {} }
    })

    if actionId == nil then
        return false
    end

    FSHTrip.SetEventActionId(charid, actionId)

    return true
end

--- Harvests the Might test once the player has rolled it
--- @param charid string The hero's token id
function FSHEvents.Pump(charid)
    local trip = FSHTrip.Get(charid)
    if trip == nil or trip.eventActionId == nil then
        return
    end

    if not FSHTrip.IsOwnedByThisClient(charid) then
        return
    end

    --One answer per test, however many copies of the Trip are on screen. See
    --FSHCast._harvested: the same double-tick applies here, and answering the
    --ancient fish twice would hand out the fish twice.
    if FSHEvents._harvested[trip.eventActionId] then
        return
    end

    local request = dmhub.GetPlayerActionRequest(trip.eventActionId)
    if request == nil then
        FSHTrip.SetEventActionId(charid, nil)
        return
    end

    local info = request.info.tokens[charid]
    local status = info ~= nil and info.status or nil

    if status == "cancel" then
        dmhub.CancelActionRequest(trip.eventActionId)
        FSHTrip.SetEventActionId(charid, nil)
        return
    end

    if status ~= "complete" then
        return
    end

    FSHEvents._harvested[trip.eventActionId] = true

    dmhub.CancelActionRequest(trip.eventActionId)
    FSHTrip.SetEventActionId(charid, nil)

    FSHEvents.AnswerAncientFish(charid, info.result or 0)
end

--- Whether this character will be rested by the Respite that is running
--- Only a participant is: everyone else keeps whatever they had spent, so their
--- Recovery has to come off now rather than waiting for a rest that will never
--- reach them.
--- @param charid string The character's id
--- @return boolean
local function RestedByThisRespite(charid)
    local session = rawget(_G, "RSPSession")
    if session == nil or session.Active() == nil then
        return false
    end
    return session.IsParticipating(charid) == true
end

--- Takes Recoveries off a character, sharing included
--- Deliberately unclamped: ConsumeResource bills a Bloodbound Band partner when
--- the hero has none left, and being told your fishing cost someone else a
--- Recovery is a better moment at the table than a debt quietly lapsing.
--- @param token any The hero's token
--- @param count number How many to take
local function SpendRecoveries(token, count)
    if token == nil or not token.valid or count <= 0 then
        return
    end

    token:ModifyProperties{
        description = "Pulled under by an ancient fish",
        undoable = false,
        execute = function()
            token.properties:ConsumeResource(
                CharacterResource.recoveryResourceId, "long", count,
                "Pulled under by an ancient fish")
        end
    }
end

--- Takes a character's parked Recovery debt, once the Respite has rested them
--- @param charid string The character's id
--- @param count number How many Recoveries are owed
function FSHEvents.TakeOwedRecoveries(charid, count)
    SpendRecoveries(dmhub.GetCharacterById(charid), math.floor(count or 0))
end

--- Answers event 9 from the result of the hard Might test
--- A failure costs a Recovery, and when that lands depends on who is fishing.
--- A participant is about to be rested, and usage recorded before that rest is
--- stamped with the old refresh id and ignored - so their debt is parked on the
--- water and taken in the activity's onRested. Anyone else is charged now.
--- @param charid string The hero's token id
--- @param total number The Might test total
function FSHEvents.AnswerAncientFish(charid, total)
    total = math.floor(total or 0)

    local trip = FSHTrip.Get(charid)
    local applied = {}
    local owed = {}

    if total >= 17 then
        local species = FishSpecies.Select(
            trip ~= nil and trip.waterType or FSHConstants.WATER_TYPE.FRESH.key,
            FSHEvents.ANCIENT_FISH_POINTS)

        FSHTrip.AddCast(charid, {
            dice = {},
            total = FSHEvents.ANCIENT_FISH_POINTS,
            points = FSHEvents.ANCIENT_FISH_POINTS,
            result = FSHTrip.RESULT.CATCH.key,
            species = species,
            fromEvent = true
        })

        applied[#applied + 1] = string.format(
            "You land it: %s, worth %d points.", species.name,
            FSHEvents.ANCIENT_FISH_POINTS)
    else
        local token = dmhub.GetCharacterById(charid)
        local maxRecoveries = 0
        if token ~= nil and token.valid and token.properties ~= nil then
            maxRecoveries =
                token.properties:GetResources()[CharacterResource.recoveryResourceId] or 0
        end

        if maxRecoveries <= 0 then
            --Followers have none, so there is nothing the fish can take.
            applied[#applied + 1] =
                "You are hauled out soaked, with no Recoveries to lose."
        elseif RestedByThisRespite(charid) then
            FSHWater.OweRecovery(charid)
            applied[#applied + 1] =
                "You end this Respite with one fewer Recovery than usual."
        else
            SpendRecoveries(token, 1)
            applied[#applied + 1] = "It costs you a Recovery."
        end

        if total <= 11 then
            owed[#owed + 1] = "The Director also owes you a consequence."
        end
    end

    FSHEvents._resolve(charid, applied, owed)
end

--- Marks the pending event answered and opens the shop
--- @param charid string The hero's token id
--- @param applied string[] What the module did
--- @param owed string[] What a human still owes
function FSHEvents._resolve(charid, applied, owed)
    FSHTrip.ResolveEvent(charid, applied, owed)

    --Announced from the lines just written rather than re-reading the Trip: a
    --document write is not visible to a read in the same breath.
    local trip = FSHTrip.Get(charid)
    local pending = trip ~= nil and FSHEvents.Pending(trip) or nil
    FSHEvents.Announce(charid, {
        name = pending ~= nil and pending.name or nil,
        applied = applied
    })

    --An event can hand over points, so the shop only opens once it is settled.
    FSHTrip.SetStatus(charid, FSHTrip.STATUS.SHOPPING.key)
end

--- Grants a title, if the hero does not already hold it
--- @param token any The hero's token
--- @param titleid string The title's guid
function FSHEvents._grantTitle(token, titleid)
    if titleid == nil or titleid == "" then
        return
    end

    token:ModifyProperties{
        description = "Grant fishing title",
        undoable = false,
        execute = function()
            token.properties:AddTitle(titleid)
        end
    }
end

--- Applies an ongoing effect to a hero
--- @param token any The hero's token
--- @param effectid string The effect's guid
function FSHEvents._applyOngoingEffect(token, effectid)
    if effectid == nil or effectid == "" then
        return
    end

    --Duration is a parameter rather than a property of the effect, and the two
    --fishing awards that expire do so at the end of the next respite.
    token:ModifyProperties{
        description = "Apply fishing effect",
        undoable = false,
        execute = function()
            token.properties:ApplyOngoingEffect(effectid, "until_rest")
        end
    }
end

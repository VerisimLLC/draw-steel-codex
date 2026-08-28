local mod = dmhub.GetModLoading()

--- One cast of the line
--- The cast is asked for through the platform's action request, the same route
--- any requested roll takes, so the player rolls in the normal dialog and hero
--- token rerolls work without the module doing anything.
--- @class FSHCast
FSHCast = RegisterGameType("FSHCast")

--- A final total at or below this is the one that got away.
FSHCast.GOT_AWAY_MAX = 11

--- Rolls already harvested, by action id. Client-local and never cleared: an
--- action id is a guid, so the entries are worth a few bytes each and a code
--- reload starts the table over.
FSHCast._harvested = {}

--- Overrides breakthrough detection so the rarest branches can be reached on
--- demand. Honoured only while FSHConstants.DEBUG_MODE is on.
FSHCast.TEST_MODE = {
    DTConstant.CreateNew("normal", 1, "Normal"),
    DTConstant.CreateNew("force", 2, "Breakthrough"),
    DTConstant.CreateNew("suppress", 3, "Always catch")
}

FSHCast.testMode = "normal"

--- The player-facing roll. Two independent axes meet here: `rollType` picks the
--- dialog, while GetModifiers passes types from the modifier pipeline's own
--- vocabulary. A cast is a test with special handling, so it sweeps the Tests
--- scope for Skilled, plus the fishing scope for what the titles grant.
RollCheck.RegisterCustom{
    id = FSHConstants.rollCheckId,
    rollType = "power_roll_custom",

    Describe = function(check, isplayer)
        return check.info.explanation
    end,

    GetRoll = function(check, creature)
        return "2d10 + " .. creature:AttributeMod(check.info.attrid)
    end,

    GetModifiers = function(check, creature)
        local roll = check:GetRoll(creature)
        local options = {
            attribute = check.info.attrid,
            skills = check.skills
        }

        local result = creature:GetModifiersForPowerRoll(roll,
            FSHConstants.modifierRollType, options)

        --Skilled is offered rather than applied: the pipeline cannot know the
        --skill was chosen for this cast, so proficiency is confirmed here.
        local skillsTable = GetTableCached("Skills")
        for _, skillid in ipairs(check.skills or {}) do
            local skill = skillsTable[skillid]
            if skill ~= nil and creature:ProficientInSkill(skill) then
                for _, entry in ipairs(result) do
                    if entry.modifier.name == "Skilled" then
                        entry.hint.result = true
                    end
                end
            end
        end

        --Fishing's own capabilities live on their own scope so they never
        --surface on an unrelated roll.
        for _, entry in ipairs(creature:GetModifiersForPowerRoll(roll,
            FSHConstants.fishingRollType, options)) do
            result[#result + 1] = entry
        end

        for _, entry in pairs(check:try_get("modifiers", {})) do
            result[#result + 1] = entry
        end

        return result
    end,

    ShowDialog = function(check, dialogOptions)
        --Presentation axis: this keeps the chat card's project-roll handling,
        --which suppresses the tier badges a project roll does not have.
        dialogOptions.rollProperties = RollProperties.new{
            type = "project_power_roll"
        }
        return GameHud.instance.rollDialog.data.ShowDialog(dialogOptions)
    end,
}

--- Converts a completed roll into points
--- The dialog already applies each edge as +2 and each bane as -2, so the total
--- is taken as given. The minimum is always 1 regardless of penalties.
--- @param info table The harvested roll
--- @return number points The size of the fish
function FSHCast.Points(info)
    return math.max(1, info.result or 0)
end

--- Classifies a harvested roll and builds the cast record
--- @param trip table The Trip
--- @param info table The harvested roll
--- @return table cast The cast record
function FSHCast.Resolve(trip, info)
    local points = FSHCast.Points(info)

    local cast = {
        dice = info.dice or {},
        total = info.result or 0,
        natural = info.naturalRoll or 0
    }

    local breakthrough = info.isCrit == true
    local gotAway = points <= FSHCast.GOT_AWAY_MAX

    --Suppress holds the casting phase open by taking away both ways out, so
    --the only way to finish is to put the picker back to Normal. Gated so a
    --picker left set cannot reach a real table.
    if FSHConstants.DEBUG_MODE then
        if FSHCast.testMode == "force" then
            breakthrough = true
        elseif FSHCast.testMode == "suppress" then
            breakthrough = false
            gotAway = false
        end
    end

    --Precedence matters: a breakthrough scores nothing even when the total is
    --high, so it is read before the total is considered at all.
    if breakthrough then
        cast.result = FSHTrip.RESULT.BREAKTHROUGH.key
        cast.points = 0
        return cast
    end

    if gotAway then
        cast.result = FSHTrip.RESULT.GOTAWAY.key
        cast.points = 0
        return cast
    end

    cast.result = FSHTrip.RESULT.CATCH.key
    cast.points = points
    cast.species = FishSpecies.Select(trip.waterType, points)

    return cast
end

--- Asks the hero's player to cast
--- @param charid string The hero's token id
--- @return boolean asked True when a request went out
--- @return string reason Why not, when none did
function FSHCast.Cast(charid)
    local trip = FSHTrip.Get(charid)
    if trip == nil or trip.status ~= FSHTrip.STATUS.CASTING.key then
        return false, "This hero is not casting."
    end

    if trip.actionId ~= nil then
        return false, "That cast is still in the air."
    end

    if not FSHTrip.IsOwnedByThisClient(charid) then
        return false, "This Trip is being run from another client."
    end

    --A Trip costs one downtime roll, taken on the first cast. Nothing goes out
    --unpaid: refusing here is what keeps a Trip from outrunning the rolls the
    --Respite handed out.
    local paid, why = FSHTrip.SpendRoll(charid)
    if not paid then
        return false, why
    end

    local skills = {}
    if trip.skill ~= nil and trip.skill.id ~= nil and trip.skill.id ~= "" then
        skills[1] = trip.skill.id
    end

    local attrid = trip.characteristic ~= nil and trip.characteristic.id or "rea"
    local title = "Fishing"
    local explanation = string.format("Fishing cast (%s)",
        DTConstants.GetDisplayText(DTConstants.CHARACTERISTICS, attrid))

    local check = RollCheck.new{
        type = FSHConstants.rollCheckId,
        id = FSHConstants.rollCheckId,
        text = title,
        explanation = explanation,
        skills = skills,
        modifiers = {},
        info = {
            attrid = attrid,
            explanation = explanation
        }
    }

    local actionId = dmhub.SendActionRequest(RollRequest.new{
        title = title,
        checks = { check },
        tokens = { [charid] = {} },
        --A cast is read, not admired: the see-through frame sits over whatever
        --map is behind it, and the stringer is hard enough to follow already.
        solidDialog = true
    })

    if actionId == nil then
        return false, "The roll could not be requested."
    end

    FSHTrip.SetActionId(charid, actionId)

    return true, ""
end

--- Spends the Goldenrod reroll on the most recent cast
--- The new result fully replaces the old one, including whether casting
--- continues, so the previous cast is dropped before the new roll is asked for.
--- @param charid string The hero's token id
--- @return boolean rerolled True when a reroll was started
--- @return string reason Why not, when it was not
function FSHCast.Goldenrod(charid)
    local trip = FSHTrip.Get(charid)
    if trip == nil or trip.actionId ~= nil then
        return false, "That cast is still in the air."
    end

    if not FSHTrip.IsOwnedByThisClient(charid) then
        return false, "This Trip is being run from another client."
    end

    if #(trip.casts or {}) == 0 then
        return false, "There is nothing to reroll."
    end

    if not FSHTrip.HasGoldenrodReroll(charid) then
        return false, "The Goldenrod reroll is already spent."
    end

    --Spent whatever the new roll turns out to be: the rules give one reroll per
    --Trip and the result stands.
    FSHTrip.SetGoldenrodReroll(charid, false)
    FSHTrip.RemoveLastCast(charid)

    return FSHCast.Cast(charid)
end

--- Harvests a cast whose roll has landed
--- Called from the panel's tick: the request is answered on whichever client
--- controls the hero, so the result has to be collected rather than returned.
--- @param charid string The hero's token id
function FSHCast.Pump(charid)
    local trip = FSHTrip.Get(charid)
    if trip == nil or trip.actionId == nil then
        return
    end

    --Only the client that asked harvests, so two clients never record the same
    --cast twice.
    if not FSHTrip.IsOwnedByThisClient(charid) then
        return
    end

    --One harvest per roll. The Trip can be shown in more than one place on a
    --client and every copy ticks, and a document write is not visible to a read
    --in the same breath, so without this two of them can each see the same
    --completed roll and record the cast twice.
    if FSHCast._harvested[trip.actionId] then
        return
    end

    local request = dmhub.GetPlayerActionRequest(trip.actionId)

    --A request cleared out from under us takes its roll with it. Treat it as
    --never having been asked so the player can cast again.
    if request == nil then
        FSHTrip.SetActionId(charid, nil)
        return
    end

    local info = request.info.tokens[charid]
    local status = info ~= nil and info.status or nil

    if status == "cancel" then
        dmhub.CancelActionRequest(trip.actionId)
        FSHTrip.SetActionId(charid, nil)
        return
    end

    if status ~= "complete" then
        return
    end

    FSHCast._harvested[trip.actionId] = true

    dmhub.CancelActionRequest(trip.actionId)

    local cast = FSHCast.Resolve(trip, info)
    FSHTrip.SetActionId(charid, nil)
    FSHTrip.AddCast(charid, cast)
end

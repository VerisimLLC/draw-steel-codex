--- The project roll request.
--- This file's dialog is gone: project rolls go through the game's own roll
--- dialog via DTProjectEditor.PerformProjectRoll, which is what brings titles,
--- complications and kit modifiers to bear on them. What stays is the request
--- itself, which never belonged to that dialog - it drives RollCheck and
--- dmhub.SendActionRequest directly, and DTProjectEditor is its only caller.
--- It extends creature rather than living in this file's own namespace, which
--- is exactly why deleting the dialog took it out by accident once already.

-- @param casterToken - The token making the roll
-- @param options - Table with:
--   attrid: attribute ID (default "mgt")
--   explanation: description of the roll
--   title: title for the roll dialog
--   callback: function(result, boons, banes) - called when roll completes
--   silent: whether to skip showing dialog (default false)
--   skills: array of skill IDs to check for proficiency
--   languages: array of language IDs to check for language penalties
--   modifiers: optional modifiers that should be included in this roll
-- @return result table {result, boons, banes} or nil if canceled
function creature:RequestProjectRoll(casterToken, options)
    options = options or {}
    
    local attrid = options.attrid or "mgt"
    local explanation = options.explanation or "Project Roll"
    explanation = explanation..string.format(" (%s)", attrid)
    local title = options.title or explanation

    local check = RollCheck.new{
        type = "project_power_roll",
        id = "project_power_roll",
        text = title,
        explanation = explanation,
        skills = options.skills or {},
        languages = options.languages or {},
        modifiers = options.modifiers or {},
        info = {
            attrid = attrid,
            explanation = explanation,
        }
    }
    
    local tokens = {}
    tokens[casterToken.id] = {}
    
    -- Send the request and wait for response
    local actionid = dmhub.SendActionRequest(RollRequest.new{
        title = title,
        checks = {check},
        tokens = tokens,
    })
    
    local resultTable = {}
    
    if options.silent then
		AwaitRequestedActionCoroutine(actionid, resultTable)
	else
		gamehud:ShowRollSummaryDialog(actionid, resultTable)
	end
    
    -- Wait for roll to complete
    while resultTable.result == nil do
		coroutine.yield(0.1)
	end
    
    -- Check if canceled
    if not resultTable.result or resultTable.action == nil then
        return nil
    end

    local action = resultTable.action
    if action.info == nil or action.info.tokens == nil then
        return nil
    end
    
    -- Extract the roll data for this token
    -- The structure is action.info.tokens[tokenId] = {result, boons, banes, status}
    local tokenResult = action.info.tokens[casterToken.id]
    if tokenResult == nil then
        return nil
    end

    --A cancelled or abandoned request still carries a token entry; it just has
    --no roll in it. Without this the caller records a roll of nothing, which
    --then clamps to 1 point of progress the hero never earned.
    if tokenResult.status ~= "complete" then
        return nil
    end
    
    local result = tokenResult.result or 0
    local boons = tokenResult.boons or 0
    local banes = tokenResult.banes or 0

    -- Call the callback if provided
    if options.callback then
        options.callback(result, boons, banes)
    end

    return {
        boons = boons,
        banes = banes,
        total = result,
        naturalRoll = tokenResult.naturalRoll or 0,
        --Breakthrough reads this rather than naturalRoll >= 19: a modifier that
        --appends a die makes the natural total unreliable, and this is measured
        --from the highest two faces.
        isCrit = tokenResult.isCrit == true,
        dice = tokenResult.dice or {},
        rollid = tokenResult.rollid or "",
        modifiersUsed = tokenResult.modifiersUsed or {},
    }
end
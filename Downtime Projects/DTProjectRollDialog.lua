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
--- Project event dialog
--- A project that stops at a milestone owes the table a roll. This rolls it -
--- either here or by asking the hero's player - shows what came up, and then
--- resolves the stop by setting the next milestone and putting the project
--- back to work.
--- @class DTEventRollDialog
DTEventRollDialog = RegisterGameType("DTEventRollDialog")

--- The row text behind a dice total, read the way RollOnTableProperties does
--- @param tableRef RollTableReference The events table reference
--- @param total number The dice total rolled
--- @return string|nil text The row's text, nil when the total is off the table
local function EventTextForTotal(tableRef, total)
    local t = tableRef:GetTable()
    if t == nil then return nil end

    local rowIndex = t:RowIndexFromDiceResult(total)
    if rowIndex == nil or t.rows[rowIndex] == nil then return nil end

    for _, item in ipairs(t.rows[rowIndex].value.items) do
        local str = item:ToString()
        if str ~= nil then return str end
    end

    return nil
end

--- Shows the project event dialog
--- @param args table project The project stopped at a milestone, heroToken The
---        token whose sheet this was opened from and who is asked to roll
function DTEventRollDialog.ShowDialog(args)
    local project = args ~= nil and args.project or nil
    local heroToken = args ~= nil and args.heroToken or nil
    if project == nil or heroToken == nil then
        return
    end

    local tableRef = RollTableReference.CreateRef(
        DTConstants.EVENTS_TABLE, DTConstants.EVENTS_TABLE_ID)
    local eventsTable = tableRef:GetTable()
    if eventsTable == nil then
        return
    end

    --Forward-declared so the handlers below capture them as upvalues.
    local resultLabel
    local milestoneInput

    local function SetResult(text)
        if resultLabel == nil or not resultLabel.valid then
            return
        end
        local hasText = text ~= nil and #text > 0
        resultLabel.text = hasText and text or "No event rolled yet."
        resultLabel:SetClass("fgMuted", not hasText)
    end

    --The Director rolls it themself, with dice rather than the game's table
    --dialog. That dialog is an embedded panel: given a tableRef it mounts into
    --the hud's standaloneRollHost, which sits below both the character sheet and
    --the modal layer, so from in here it rolls where nobody can see it. Dice are
    --drawn by the engine and answer to no layer, and the table's own
    --RollOnTableProperties still puts the event text on the chat card.
    local function DirectorRoll()
        local rollInfo = eventsTable:CalculateRollInfo()
        if rollInfo == nil then
            return
        end

        dmhub.Roll{
            roll = rollInfo.roll,
            description = eventsTable.name,
            tokenid = heroToken.id,
            creature = heroToken.properties,
            properties = RollOnTableProperties.new{ tableRef = tableRef },
            complete = function(info)
                SetResult(EventTextForTotal(tableRef, info.total))
            end,
        }
    end

    --Hands the roll to the hero's player and waits for it to come back.
    local function RequestRoll()
        local check = RollCheck.new{
            type = "table",
            id = "custom",
            group = "custom",
            text = eventsTable.name,
            tableRef = tableRef,
            rollProperties = RollOnTableProperties.new{ tableRef = tableRef },
        }

        local tokens = {}
        tokens[heroToken.id] = {}

        dmhub.Coroutine(function()
            local resultTable = {}
            local actionid = dmhub.SendActionRequest(RollRequest.new{
                title = "Project Event",
                checks = {check},
                tokens = tokens,
            })

            AwaitRequestedActionCoroutine(actionid, resultTable)
            while resultTable.result == nil do
                coroutine.yield(0.1)
            end

            --A cancelled or abandoned request still carries a token entry; it
            --just has no roll in it.
            local action = resultTable.action
            local tokenResult = nil
            if action ~= nil and action.info ~= nil and action.info.tokens ~= nil then
                tokenResult = action.info.tokens[heroToken.id]
            end
            if tokenResult == nil or tokenResult.status ~= "complete" then
                return
            end

            SetResult(EventTextForTotal(tableRef, tokenResult.result or 0))
        end)
    end

    --Resolving the stop is the whole point of the dialog: the next milestone
    --goes in and the project goes back to work.
    local function Resolve()
        local value = math.max(0, math.floor(tonumber(milestoneInput.text) or 0))

        heroToken:ModifyProperties{
            description = "Resolve Downtime Project Milestone",
            undoable = false,
            execute = function()
                project:SetMilestoneThreshold(value)
                    :SetStatus(DTConstants.STATUS.ACTIVE.key)
            end,
        }

        gui.CloseModal()

        dmhub.Schedule(0.1, function()
            DTSettings.Touch()
            DTShares.Touch()
        end)
    end

    resultLabel = gui.Label{
        classes = {"form", "fgMuted"},
        width = "100%-16",
        height = "auto",
        halign = "left",
        valign = "top",
        textWrap = true,
        text = "No event rolled yet.",
    }

    milestoneInput = gui.Input{
        classes = {"input", "form"},
        width = 100,
        textAlignment = "center",
        text = tostring(DTBusinessRules.CalcNextMilestone(project) or 0),
    }

    gui.ShowModal(gui.Panel{
        styles = ThemeEngine.GetStyles(),
        classes = {"dialog"},
        width = 560,
        height = 520,
        flow = "vertical",

        children = {
            gui.Label{
                classes = {"modalTitle"},
                text = "Roll A Project Event",
            },

            gui.Panel{
                width = "94%",
                height = "auto",
                halign = "center",
                flow = "horizontal",
                vmargin = 8,

                children = {
                    gui.Button{
                        classes = {"sizeL"},
                        text = "Request Roll",
                        hmargin = 8,
                        click = function()
                            RequestRoll()
                        end,
                    },

                    gui.Button{
                        classes = {"sizeL"},
                        text = "Roll",
                        hmargin = 8,
                        click = function()
                            DirectorRoll()
                        end,
                    },
                },
            },

            --A d100 row can run long, so the text scrolls rather than pushing
            --the milestone field off the bottom of the dialog.
            gui.Panel{
                width = "94%",
                height = 150,
                halign = "center",
                vmargin = 8,
                vscroll = true,

                children = {resultLabel},
            },

            gui.MCDMDivider{
                layout = "peak",
                width = "90%",
                vmargin = 8,
            },

            gui.Panel{
                classes = {"formRow"},
                width = "94%",
                halign = "center",
                vmargin = 8,

                children = {
                    gui.Label{
                        classes = {"label", "form"},
                        text = "Next Milestone:",
                    },

                    milestoneInput,
                },
            },

            gui.Panel{
                width = "94%",
                height = 72,
                halign = "center",
                valign = "bottom",
                flow = "horizontal",

                children = {
                    gui.Button{
                        classes = {"sizeL"},
                        text = "Cancel",
                        valign = "top",
                        hmargin = 8,
                        click = function()
                            gui.CloseModal()
                        end,
                    },

                    gui.Button{
                        classes = {"sizeL"},
                        text = "Resolve",
                        valign = "top",
                        hmargin = 8,
                        click = function()
                            Resolve()
                        end,
                    },
                },
            },
        },
    })
end

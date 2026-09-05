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
    explanation = explanation..string.format(" (%s)",
        DTConstants.GetDisplayText(DTConstants.CHARACTERISTICS, attrid))
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

local WIDTH = 560
local RESULT_HEIGHT = 150

-- Sized to its contents rather than eyeballed: the two form rows carry a 26
-- high control, the roll buttons are 35, the result panel is RESULT_HEIGHT,
-- and each of the four takes vmargin 8 top and bottom. The shell adds a 40
-- header, a 60 footer and its padding at both ends.
local HEIGHT = (26 + 16) + (35 + 16) + (RESULT_HEIGHT + 16) + (26 + 16) + 40 + 60 + 24

local HERO_NAME_LIMIT = 24

--- The subtitle is a single line, so a name past the limit is cut and marked
--- rather than left to crowd out the project title beside it.
--- @param name string|nil
--- @return string
local function ShortHeroName(name)
    if name == nil or name == "" then
        return "Unknown Hero"
    end

    if #name <= HERO_NAME_LIMIT then
        return name
    end

    return trim(name:sub(1, HERO_NAME_LIMIT)) .. "..."
end

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

--- Drops the shared "Downtime Event:" prefix from an event table's name. Every
--- table in the list carries it, so it is noise under a field already labelled
--- Event Table. The compendium keeps the full names.
--- @param options table List of { id, text } pairs from DTHelpers.GetEventTableOptions
--- @return table options The same list with shortened text
local function StripEventTablePrefix(options)
    local result = {}

    for _, option in ipairs(options) do
        local text = option.text
        if string.starts_with(text, DTConstants.EVENTS_TABLE_PREFIX) then
            text = trim(text:sub(#DTConstants.EVENTS_TABLE_PREFIX + 1))
        end

        result[#result + 1] = {
            id = option.id,
            text = text,
        }
    end

    return result
end

--- The event table a project starts the dialog on: the one named on the activity
--- the project came from, falling back to Crafting and Research when the project
--- has no activity, the activity names no table, or that table is no longer offered.
--- @param project DTProject The project stopped at a milestone
--- @param options table The event table dropdown options
--- @return string tableId The GUID of the event table to select
local function DefaultEventTableId(project, options)
    local activityId = project:GetActivityID()
    if activityId ~= "" then
        local activity = (dmhub.GetTable(DowntimeActivity.tableName) or {})[activityId]
        if activity ~= nil then
            local tableId = activity:GetEventTableId()
            if tableId ~= "" and DTHelpers.OptionsContain(options, tableId) then
                return tableId
            end
        end
    end

    return DTConstants.EVENTS_TABLE_ID
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

    local tableOptions = StripEventTablePrefix(DTHelpers.GetEventTableOptions())
    local selectedTableId = DefaultEventTableId(project, tableOptions)

    --Both roll paths read the table through here, so they always roll whatever
    --the dropdown currently shows rather than a reference captured at open time.
    local function CurrentTableRef()
        return RollTableReference.CreateRef(DTConstants.EVENTS_TABLE, selectedTableId)
    end

    if CurrentTableRef():GetTable() == nil then
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
        local tableRef = CurrentTableRef()
        local eventsTable = tableRef:GetTable()
        if eventsTable == nil then
            return
        end

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
        local tableRef = CurrentTableRef()
        local eventsTable = tableRef:GetTable()
        if eventsTable == nil then
            return
        end

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

    local dlg = DialogShell.CreateNew{
        title = "Roll A Project Event",
        subtitle = string.format("%s for %s", project:GetTitle(),
            ShortHeroName(heroToken.name)),
        width = WIDTH,
        height = HEIGHT,
        footerCells = {50, 50},
        close = "modal",
        escape = true,
    }

    dlg:SetWorkingContent{
        gui.Panel{
            classes = {"formRow"},
            width = "94%",
            halign = "center",
            vmargin = 8,

            gui.Label{
                classes = {"label", "form"},
                text = "Event Table:",
            },

            gui.Dropdown{
                classes = {"dropdown", "form"},
                width = 280,
                options = tableOptions,
                idChosen = selectedTableId,
                change = function(element)
                    selectedTableId = element.idChosen
                end,
            },
        },

        gui.Panel{
            width = "94%",
            height = "auto",
            halign = "center",
            flow = "horizontal",
            vmargin = 8,

            --Handing the roll to a player is the Director's move. A player who
            --has been given these controls is already the one rolling, so they
            --get the one button and it takes the middle of the row alone.
            dmhub.isDM and gui.Button{
                classes = {"sizeL"},
                text = "Request Roll",
                hmargin = 8,
                click = function()
                    RequestRoll()
                end,
            } or nil,

            gui.Button{
                classes = {"sizeL"},
                text = "Roll",
                hmargin = 8,
                halign = (not dmhub.isDM) and "center" or nil,
                click = function()
                    DirectorRoll()
                end,
            },
        },

        --A d100 row can run long, so the text scrolls rather than pushing
        --the milestone field off the bottom of the dialog.
        gui.Panel{
            width = "94%",
            height = RESULT_HEIGHT,
            halign = "center",
            vmargin = 8,
            vscroll = true,

            resultLabel,
        },

        gui.Panel{
            classes = {"formRow"},
            width = "94%",
            halign = "center",
            vmargin = 8,

            gui.Label{
                classes = {"label", "form"},
                text = "Next Milestone:",
            },

            milestoneInput,
        },
    }

    dlg:AddFooterButton{
        slot = "left",
        text = "Cancel",
        click = function(shell)
            shell:Close()
        end,
    }

    dlg:AddFooterButton{
        slot = "right",
        text = "Resolve",
        click = function(shell)
            Resolve()
            shell:Close()
        end,
    }

    gui.ShowModal(dlg:Root())
end

RollCheck.RegisterCustom{
    id = "project_power_roll",
    rollType = "power_roll_custom",
    Describe = function(check, isplayer)
        return check.info.explanation
    end,
    GetRoll = function(check, creature)
        return "2d10 + " .. creature:AttributeMod(check.info.attrid)
    end,
    GetModifiers = function(check, creature)
        --Modifiers included from the Roll
        local rollModifiers = check:try_get("modifiers", {})
        local result = creature:GetModifiersForPowerRoll(check:GetRoll(creature), "project_roll", {attribute = check.info.attrid, skills = check.skills})

        local skillsTable = GetTableCached("Skills")
        for _, skillid in ipairs(check.skills or {}) do
            local skill = skillsTable[skillid]
            if creature:ProficientInSkill(skill) then
                for _,mod in ipairs(result) do
                    if mod.modifier.name == "Skilled" then
                        mod.hint.result = true
                    end
                end
            end
        end

        local langs = creature:LanguagesKnown()
        local languagesTable = GetTableCached("languages")
        local relatedLanguages = GetTableCached("languageRelations")

        local languageKnown = false
        local languageRelated = false

        for _, lang in ipairs(check.languages or {}) do
            if langs[lang] then
                languageKnown = true
                break
            elseif relatedLanguages[lang] then
                for related, _ in pairs(relatedLanguages[lang].related) do
                    if langs[related] then
                        languageRelated = true
                        break
                    end
                end
            end
        end

        for _, mod in pairs(result) do
            if not languageKnown and not languageRelated then
                if mod.modifier.name == "Unknown Language" then
                    mod.hint.result = true
                    mod.hint.justification = {"<color=#FF0000>You do not know the language(s) of the project source.</color>"}
                end
            elseif not languageKnown and languageRelated then
                if mod.modifier.name == "Related Language" then
                    mod.hint.result = true
                    mod.hint.justification = {"<color=#FF0000>You do not know the project source language(s), but you know a related language.</color>"}
                end
            end
        end

        --Add roll modifiers to the result
        for _, mod in pairs(rollModifiers ) do
            result[#result+1] = mod
        end

        return result
    end,
    ShowDialog = function(check, dialogOptions)
        dialogOptions.rollProperties = RollProperties.new{
            type = "project_power_roll",
        }
        return GameHud.instance.rollDialog.data.ShowDialog(dialogOptions)
    end,
}

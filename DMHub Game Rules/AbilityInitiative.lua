local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityInitiativeBehavior:ActivatedAbilityBehavior
--- @field summary string Short label shown in behavior lists.
ActivatedAbilityInitiativeBehavior = RegisterGameType("ActivatedAbilityInitiativeBehavior", "ActivatedAbilityBehavior")


ActivatedAbility.RegisterType
{
	id = 'change_initiative',
	text = 'Manipulate Combat Order',
	createBehavior = function()
		return ActivatedAbilityInitiativeBehavior.new{
		}
	end
}


ActivatedAbilityInitiativeBehavior.summary = 'Manipulate Combat Order'

function ActivatedAbilityInitiativeBehavior:Cast(ability, casterToken, targets, options)
    local mode = self:try_get("mode", "begin_turn")
    if mode == "begin_turn" then
        if #targets > 0 then
            local token = targets[1].token
            if token ~= nil then
                dmhub.Schedule(0.01, function()
                    local initiativeid = dmhub.initiativeQueue.GetInitiativeId(token)
                    dmhub.initiativeQueue.playersTurn = dmhub.initiativeQueue:IsEntryPlayer(initiativeid)
                    dmhub.initiativeQueue:SelectTurn(initiativeid)
                    dmhub:UploadInitiativeQueue()

                    local tokens = GameHud.GetTokensForInitiativeId(GameHud.instance, GameHud.instance.initiativeInterface, initiativeid)
                    for i,tok in ipairs(tokens) do
                        if tok.properties ~= nil then
                            tok.properties:BeginTurn()
                        end
                    end
                end)

                ability:CommitToPaying(casterToken, options)
            end
        end
    elseif mode == "set_priority" then
        for _,target in ipairs(targets) do
            local token = target.token
            if token ~= nil then

                local initiativeid = dmhub.initiativeQueue.GetInitiativeId(token)
                dmhub.initiativeQueue:SetPriority(initiativeid)
                dmhub:UploadInitiativeQueue()

                ability:CommitToPaying(casterToken, options)
            end
        end

    elseif mode == "add_to_initiative" then
        local casterid = InitiativeQueue.GetInitiativeId(casterToken)
        local isplayer = dmhub.initiativeQueue:IsEntryPlayer(casterid)
        local q = dmhub.initiativeQueue
        if q == nil or q.hidden then
            return
        end

        local changes = false
        for _,target in ipairs(targets) do
            local token = target.token
            if token ~= nil then
                token:ModifyProperties{
                    description = "Added to Initiative",
                    execute = function()
                        token.properties.initiativeGrouping = dmhub.GenerateGuid()
                    end
                }

                local entry = q:SetInitiative(token.properties.initiativeGrouping, 0, 0)
                entry.player = isplayer
                changes = true
            end
        end

        if changes then
            dmhub:UploadInitiativeQueue()
        end

    elseif mode == "skip_turn" then
        if #targets > 0 then
            local token = targets[1].token
            if token ~= nil then
                local q = dmhub.initiativeQueue
                if q == nil or q.hidden then return end
                local initiativeid = InitiativeQueue.GetInitiativeId(token)
                local allTokens = InitiativeQueue.GetTokensForInitiativeId(initiativeid)

                if token.valid and token.properties ~= nil then
                    token:ModifyProperties{
                        description = "Skip Turn",
                        execute = function()
                            token.properties:MarkTurnSkipped(initiativeid)
                            token.properties:ConsumeResource(
                                CharacterResource.actionResourceId, "turn", 1)
                            token.properties:ConsumeResource(
                                CharacterResource.maneuverResourceId, "turn", 1)
                            local speed = token.properties:CurrentMovementSpeed()
                            if speed > 0 then
                                token.properties.moveDistance = speed
                                token.properties.moveDistanceRoundId = q:GetTurnId()
                            end
                        end,
                    }
                end

                -- Only auto-advance when this creature is the sole entry in initiative.
                -- If others share the entry, they still need to act.
                if #allTokens <= 1 then
                    dmhub.Schedule(0.1, function()
                        if mod.unloaded then return end
                        GameHud.instance:NextInitiative(function()
                            dmhub:UploadInitiativeQueue()
                        end)
                    end)
                end

                ability:CommitToPaying(casterToken, options)
            end
        end
    end
end

function ActivatedAbilityInitiativeBehavior:EditorItems(parentPanel)

	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Mode:",
        },
        gui.Dropdown{
            options = {
                {
                    id = "begin_turn",
                    text = "Begin Turn",
                },
                {
                    id = "set_priority",
                    text = "Set Priority",
                },
                {
                    id = "add_to_initiative",
                    text = "Add to Combat as Caster Ally",
                },
                {
                    id = "skip_turn",
                    text = "Skip Turn",
                },
            },
            idChosen = self:try_get("mode", "begin_turn"),
            change = function(element)
                self.mode = element.idChosen
            end,
        },
    }

	return result
end

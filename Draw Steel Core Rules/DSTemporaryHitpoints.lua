local mod = dmhub.GetModLoading()

function creature:GrantTemporaryStamina(amount, note)
	if self:TemporaryHitpoints() > amount then
		return
	end

	self:SetTemporaryHitpoints(amount, note)

    self:DispatchEvent("gaintempstamina", {})
end


--- @class ActivatedAbilityTemporaryStaminaChatMessage
--- @field ability ActivatedAbility
ActivatedAbilityTemporaryStaminaChatMessage = RegisterGameType("ActivatedAbilityTemporaryStaminaChatMessage")
ActivatedAbilityTemporaryStaminaChatMessage.amount = 0
ActivatedAbilityTemporaryStaminaChatMessage.chatMessage = ""
ActivatedAbilityTemporaryStaminaChatMessage.casterid = ""
ActivatedAbilityTemporaryStaminaChatMessage.targetids = {}

function ActivatedAbilityTemporaryStaminaChatMessage:Render(message)
    local token = self:GetCasterToken()

    if token == nil or (not token.valid) then
        return gui.Panel{
            width = 0, height = 0,
        }
    end

    local targetTokenPanels = {}
    for _,tok in ipairs(self:GetTargetTokens()) do
        if tok.valid then
            targetTokenPanels[#targetTokenPanels+1] = gui.CreateTokenImage(tok, {
                width = 28,
                height = 28,
                valign = "center",
                halign = "left",
                interactable = true,
                hover = gui.Tooltip(tok.name),
            })
        end
    end

    local detailLabel = gui.Label{
        classes = {"action-log-detail"},
        text = self.chatMessage,
    }

    local staminaLabel = gui.Label{
        classes = {"action-log-subtext"},
        text = string.format("%d temporary stamina", self.amount),
    }

    local targetsPanel = nil
    if #targetTokenPanels > 0 then
        targetsPanel = gui.Panel{
            floating = true,
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "top",
            flow = "horizontal",
            wrap = true,
            maxWidth = 90,
            rmargin = 6,
            tmargin = 2,
            children = targetTokenPanels,
        }
    end

    local card = CreateActionLogCard{
        token = token,
        content = {detailLabel, staminaLabel, targetsPanel},
    }

    local resultPanel = gui.Panel{
        classes = {"chat-message-panel"},
        flow = "vertical",
        width = "100%",
        height = "auto",
        refreshMessage = function(element, message)
        end,
        card,
    }

    return resultPanel
end

function ActivatedAbilityTemporaryStaminaChatMessage:GetCasterToken()
    return dmhub.GetCharacterById(self.casterid)
end

--- @return CharacterToken[]
function ActivatedAbilityTemporaryStaminaChatMessage:GetTargetTokens()
    local result = {}
    for i,tokenid in ipairs(self.targetids) do
        result[#result+1] = dmhub.GetCharacterById(tokenid)
    end
    return result
end



--- @class ActivatedAbilityGrantTemporaryStaminaBehavior:ActivatedAbilityBehavior
--- @field amount nil|string GoblinScript expression for the temporary stamina amount to grant.
--- Behavior that grants temporary stamina (temporary hit points) to the target.
ActivatedAbilityGrantTemporaryStaminaBehavior = RegisterGameType("ActivatedAbilityGrantTemporaryStaminaBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
	id = 'grant_temporary_stamina',
	text = 'Grant Temporary Stamina',
	createBehavior = function()
		return ActivatedAbilityGrantTemporaryStaminaBehavior.new{
		}
	end
}

ActivatedAbilityGrantTemporaryStaminaBehavior.summary = 'Grant Temporary Stamina'
ActivatedAbilityGrantTemporaryStaminaBehavior.stamina = 5
ActivatedAbilityGrantTemporaryStaminaBehavior.chatMessage = ""


function ActivatedAbilityGrantTemporaryStaminaBehavior:Cast(ability, casterToken, targets, options)
    if #targets == 0 then
        return
    end

    local logMessage = nil
    if self.chatMessage ~= "" then
        logMessage = ActivatedAbilityTemporaryStaminaChatMessage.new{
            ability = ability,
            amount = 0,
            chatMessage = self.chatMessage,
            casterid = casterToken.id,
            targetids = {},
        }
        for _,target in ipairs(targets) do
            logMessage.targetids[#logMessage.targetids+1] = target.token.id
        end
    end

    local granted = false

    for _,target in ipairs(targets) do
        local roll = dmhub.EvalGoblinScript(self.stamina, casterToken.properties:LookupSymbol(options.symbols), string.format("Grant stamina roll for %s", ability.name))
        if tonumber(roll) == nil then
            local result = nil
            local canceled = false
            local rollid = gamehud.rollDialog.data.ShowDialog{
                title = "Grant Stamina",
                description = string.format("Roll to grant stamina"),
                roll = roll,
                creature = casterToken.properties,
                skipDeterministic = true,
                type = "custom",

                cancelRoll = function()
                    canceled = true
                end,
                completeRoll = function(rollInfo)
                    result = rollInfo.total
                end,
            }

            while canceled == false and result == nil do
                coroutine.yield(0.1)
            end

            if tonumber(result) == nil then
                break
            end

            roll = result
        end

        if logMessage ~= nil then
            logMessage.amount = tonumber(roll)
        end

        ability.RecordTokenMessage(target.token, options, string.format("%d temporary stamina", tonumber(roll)))
        target.token:ModifyProperties{
            description = "Grant Temporary Stamina",
            execute = function()
                target.token.properties:GrantTemporaryStamina(tonumber(roll))
            end,
        }
        granted = true
    end

    if logMessage ~= nil and logMessage.amount > 0 then
        chat.SendCustom(logMessage)
    end

    if granted then
        ability:CommitToPaying(casterToken, options)
    end
end

function ActivatedAbilityGrantTemporaryStaminaBehavior:EditorItems(parentPanel)
    local result = {}

    self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Log Message:",
        },
        gui.Input{
            classes = {"formInput"},
            text = self.chatMessage,
            events = {
                change = function(element)
                    self.chatMessage = element.text
                end
            }
        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Stamina:",
        },
        gui.GoblinScriptInput{
            value = self.stamina,
            change = function(element)
                self.stamina = element.value
            end,

			documentation = {
				help = string.format("This GoblinScript determines the amount of temporary stamina to grant"),
				output = "roll",
				examples = {
					{
						script = "8",
						text = "8 temporary stamina is granted.",
					},
					{
						script = "2*Reason",
						text = "Twice the caster's Reason is granted as temporary stamina.",
					},
					{
						script = "2d6",
						text = "2d6 Temporary Stamina is granted.",
					},
				},
				subject = creature.helpSymbols,
				subjectDescription = "The creature that is using the ability.",
				symbols = ActivatedAbility.helpCasting,
			},
        }
    }

    return result
end
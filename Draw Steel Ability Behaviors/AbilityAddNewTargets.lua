local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityAddNewTargetsBehavior:ActivatedAbilityBehavior
ActivatedAbilityAddNewTargetsBehavior = RegisterGameType("ActivatedAbilityAddNewTargetsBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityAddNewTargetsBehavior.summary = 'Manipulate Targets'

ActivatedAbility.RegisterType
{
	id = 'manipulate_targets',
	text = 'Manipulate Targets',
	createBehavior = function()
		local targetingAbility = ActivatedAbility.Create()
		targetingAbility.name = "Choose Additional Targets"
		targetingAbility.targetType = "target"
		targetingAbility.range = "5"
		targetingAbility.numTargets = "1"
		targetingAbility.behaviors = {}
		return ActivatedAbilityAddNewTargetsBehavior.new{
			targetingAbility = targetingAbility,
		}
	end,
}

ActivatedAbilityAddNewTargetsBehavior.promptText = ''
ActivatedAbilityAddNewTargetsBehavior.targetMode = 'add'

function ActivatedAbilityAddNewTargetsBehavior:Cast(ability, casterToken, targets, options)
	ability:CommitToPaying(casterToken, options)

	local targetingAbility = self.targetingAbility:MakeTemporaryClone()
	targetingAbility.countsAsCast = false
	targetingAbility.skippable = true

	if self.promptText ~= '' then
		targetingAbility.promptOverride = StringInterpolateGoblinScript(self.promptText, casterToken.properties:LookupSymbol{})
	end

	-- Add a single instant behavior that captures the chosen targets via closure.
	local capturedTargets = nil

	local captureBehavior = ActivatedAbilityBehavior.new{
		instant = true,
	}
	captureBehavior.Cast = function(behaviorSelf, captureAbility, captureCasterToken, captureTargets, captureOptions)
		capturedTargets = captureTargets or {}
	end

	targetingAbility.behaviors = { captureBehavior }

	local symbols = options.symbols or {}

	-- Use ExecuteInvoke which properly handles the action bar invoke lifecycle:
	ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(casterToken, targetingAbility, casterToken, "prompt", symbols, {})

	-- Merge or replace targets based on targetMode.
	if capturedTargets ~= nil and #capturedTargets > 0 and options.targets ~= nil then
		if self.targetMode == 'replace' then
			-- Clear existing targets and replace with new ones.
			for i = #options.targets, 1, -1 do
				options.targets[i] = nil
			end
			for _, newTarget in ipairs(capturedTargets) do
				options.targets[#options.targets + 1] = newTarget
			end
		else
			-- Add new targets to the existing list.
			for _, newTarget in ipairs(capturedTargets) do
				local isDuplicate = false
				if not self:try_get("allowDuplicates", false) then
					for _, existingTarget in ipairs(options.targets) do
						if existingTarget.token ~= nil and newTarget.token ~= nil and existingTarget.token.charid == newTarget.token.charid then
							isDuplicate = true
							break
						end
					end
				end
				if not isDuplicate then
					options.targets[#options.targets + 1] = newTarget
				end
			end
		end
	end
end

function ActivatedAbilityAddNewTargetsBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

	result[#result+1] = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			classes = {"formLabel"},
			text = "Prompt Text:",
		},
		gui.Input{
			classes = {"formInput"},
			text = self.promptText,
			multiline = true,
			width = 300,
			height = "auto",
			maxHeight = 140,
			change = function(element)
				self.promptText = element.text
			end,
		}
	}

	result[#result+1] = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			classes = {"formLabel"},
			text = "Target Mode:",
		},
		gui.Dropdown{
			classes = {"formDropdown"},
			options = {
				{ text = "Add to Targets", id = "add" },
				{ text = "Replace Targets", id = "replace" },
			},
			idChosen = self.targetMode,
			change = function(element)
				self.targetMode = element.idChosen
			end,
		}
	}

	result[#result+1] = gui.Check{
		text = "Allow Duplicate Targets",
		value = self:try_get("allowDuplicates", false),
		change = function(element)
			self.allowDuplicates = element.value
		end,
	}

	result[#result+1] = gui.PrettyButton{
		width = 200,
		height = 50,
		text = "Edit Targeting",
		click = function(element)
			element.root:AddChild(self.targetingAbility:ShowEditActivatedAbilityDialog())
		end,
	}

	return result
end

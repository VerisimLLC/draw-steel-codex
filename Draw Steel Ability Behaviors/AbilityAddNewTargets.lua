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
	if #targets == 0 then
		return
	end

	ability:CommitToPaying(casterToken, options)

	local symbols = options.symbols or {}

	-- Build the list of origin tokens to invoke targeting from.
	-- Each target from applyto becomes an origin (e.g. burst centered on it).
	-- If no targets, fall back to the caster.
	local originTokens = {}
	if targets ~= nil and #targets > 0 then
		for _, target in ipairs(targets) do
			if target.token ~= nil then
				originTokens[#originTokens+1] = target.token
			end
		end
	end
	if #originTokens == 0 then
		originTokens[1] = casterToken
	end

	-- Invoke targeting once per origin token, accumulating all captured targets.
	local allCapturedTargets = {}

	for _, originToken in ipairs(originTokens) do
		-- Add a single instant behavior that captures the chosen targets via closure.
		-- Functions survive DeepCopy by reference, so the closure is shared with
		-- the action bar's cloned copy of the ability.
		local capturedTargets = nil

		local captureBehavior = ActivatedAbilityBehavior.new{
			instant = true,
		}
		captureBehavior.Cast = function(behaviorSelf, captureAbility, captureCasterToken, captureTargets, captureOptions)
			capturedTargets = captureTargets or {}
		end

		-- Fresh clone each iteration so the action bar gets a clean ability.
		local invokeAbility = self.targetingAbility:MakeTemporaryClone()
		invokeAbility.countsAsCast = false
		invokeAbility.skippable = true
		invokeAbility.behaviors = { captureBehavior }

		if self.promptText ~= '' then
			invokeAbility.promptOverride = StringInterpolateGoblinScript(self.promptText, casterToken.properties:LookupSymbol{})
		end

		-- Pass originToken as caster so the action bar centers targeting
		-- (bursts, areas, etc.) on that token's position.
		ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(originToken, invokeAbility, originToken, "prompt", symbols, {})

		if capturedTargets ~= nil then
			for _, t in ipairs(capturedTargets) do
				allCapturedTargets[#allCapturedTargets+1] = t
			end
		end
	end

	-- Merge or replace targets based on targetMode.
	if #allCapturedTargets > 0 and options.targets ~= nil then
		if self.targetMode == 'replace' then
			-- Clear existing targets and replace with new ones.
			for i = #options.targets, 1, -1 do
				options.targets[i] = nil
			end
			for _, newTarget in ipairs(allCapturedTargets) do
				options.targets[#options.targets + 1] = newTarget
			end
		else
			-- Add new targets to the existing list.
			for _, newTarget in ipairs(allCapturedTargets) do
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

local mod = dmhub.GetModLoading()

--- @class AttackTriggeredAbility:ActivatedAbility
--- @field new fun(o?: table): AttackTriggeredAbility
--- An ActivatedAbility variant that fires automatically when an attack is made.
AttackTriggeredAbility = RegisterGameType("AttackTriggeredAbility", "ActivatedAbility")


function AttackTriggeredAbility.Create(options)
	local args = ActivatedAbility.StandardArgs()

	if options ~= nil then
		for k,v in pairs(options) do
			args[k] = v
		end
	end

	return AttackTriggeredAbility.new(args)
end

function AttackTriggeredAbility:AttackHitWhileInCoroutine(attackerToken, targetToken)
	self:Cast(attackerToken, {
		{
			loc = targetToken.loc,
			token = targetToken,
		}
	}, {
		alreadyInCoroutine = true
	})
end

function AttackTriggeredAbility:TargetTypeEditor()

	local resultPanel
	resultPanel = gui.Panel{
		flow = "vertical",
		height = "auto",
		width = "100%",

		gui.Panel{
			classes = "formPanel",
			gui.Label{
				classes = "formLabel",
				text = "Name:",
			},
			gui.Input{
				classes = "formInput",
				text = self.name,
				change = function(element)
					self.name = element.text
				end,
			},
		},

		gui.Panel{
			classes = "formPanel",
			gui.Label{
				classes = "formLabel",
				text = "Target Filter:",
			},
			gui.Input{
				classes = "formInput",
				text = self.targetFilter,
				change = function(element)
					self.targetFilter = element.text
				end,
			},
		},

	}

	return resultPanel
	
end

function AttackTriggeredAbility:GenerateEditor()
	

	local resultPanel
	resultPanel = gui.Panel{
		classes = "abilityEditor",
		styles = {
			Styles.Form,
			{
				classes = {"formPanel"},
				width = 340,
			},
			{
				classes = {"formLabel"},
				halign = "left",
			},
			{
				classes = {"abilityEditor"},
				width = '100%',
				height = 'auto',
				flow = "horizontal",
				valign = "top",
			},
			{
				classes = "mainPanel",
				width = "40%",
				height = "auto",
				flow = "vertical",
				valign = "top",
			},
		},
		gui.Panel{
			id = "leftPanel",
			classes = "mainPanel",
			self:BehaviorEditor(),
		},

	}

	return resultPanel
end



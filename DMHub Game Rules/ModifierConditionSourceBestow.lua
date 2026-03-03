local mod = dmhub.GetModLoading()


CharacterModifier.RegisterType('conditionsourcebestow', "Reciprocal Condition")

CharacterModifier.TypeInfo.conditionsourcebestow = {

	init = function(modifier)
		modifier.sourceConditionid = 'none'
		modifier.conditionid = 'none'
		modifier.maxRange = 1
	end,

	-- No bestowConditions handler. This modifier does NOT bestow on the creature
	-- that owns it. Instead, Creature.lua's VisitConditionCasterSource reads it
	-- from the target's active modifiers and bestows on the CASTER.

	createEditor = function(modifier, element)
		local Refresh

		local firstRefresh = true

		Refresh = function()
			if firstRefresh then
				firstRefresh = false
			else
				element:FireEvent("refreshModifier")
			end

			local children = {}
			children[#children+1] = modifier:FilterConditionEditor()

			local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)

			-- "When I have condition:" dropdown
			local sourceOptions = {
				{
					id = "none",
					text = "(None)",
				}
			}

			for key,conditionInfo in pairs(conditionsTable or {}) do
				if conditionInfo:try_get("hidden", false) == false then
					sourceOptions[#sourceOptions+1] = {
						id = key,
						text = conditionInfo.name,
					}
				end
			end

			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				children = {
					gui.Label{
						text = 'When I have condition:',
						classes = {'formLabel'},
					},
					gui.Dropdown{
						selfStyle = {
							height = 30,
							width = 260,
							fontSize = 16,
						},
						options = sourceOptions,
						sort = true,

						idChosen = modifier.sourceConditionid,

						events = {
							change = function(element)
								modifier.sourceConditionid = element.idChosen
								Refresh()
							end,
						},
					},
				}
			}

			-- "Bestow on condition source:" dropdown
			local targetOptions = {
				{
					id = "none",
					text = "(None)",
				}
			}

			for key,conditionInfo in pairs(conditionsTable or {}) do
				if conditionInfo:try_get("hidden", false) == false then
					targetOptions[#targetOptions+1] = {
						id = key,
						text = conditionInfo.name,
					}
				end
			end

			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				children = {
					gui.Label{
						text = 'Bestow on condition source:',
						classes = {'formLabel'},
					},
					gui.Dropdown{
						selfStyle = {
							height = 30,
							width = 260,
							fontSize = 16,
						},
						options = targetOptions,
						sort = true,

						idChosen = modifier.conditionid,

						events = {
							change = function(element)
								modifier.conditionid = element.idChosen
								Refresh()
							end,
						},
					},
				}
			}

			-- "Max range:" numeric input (0 = any distance)
			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				children = {
					gui.Label{
						text = 'Max range (0 = any):',
						classes = {'formLabel'},
					},
					gui.Input{
						selfStyle = {
							height = 30,
							width = 80,
							fontSize = 16,
						},
						text = tostring(modifier.maxRange),
						events = {
							change = function(element)
								modifier.maxRange = tonumber(element.text) or 0
								Refresh()
							end,
						},
					},
				}
			}

			element.children = children
		end

		Refresh()
	end,
}

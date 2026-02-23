local mod = dmhub.GetModLoading()

--This file implements the main roll prompt dialog that appears when you get a dice roll prompt.

setting{
	id = "privaterolls",
	description = "Default Roll Visibility",
	storage = "preference",
	default = "visible",
	editor = "dropdown",
	section = "Game",

	enum = {
		{
			value = "visible",
			text = "Visible to Everyone",
		},
		{
			value = "dm",
			text = cond(dmhub.isDM, "Visible to Director only", "Visible to you and Director"),
		}
	}
}

setting{
	id = "privaterolls:save",
	description = "Save roll visibility preferences",
	storage = "preference",
	default = true,
	editor = "check",
}

local g_rollOptionsDM = {
	{
		id = "visible",
		text = "Visible to Everyone",
	},
	{
		id = "dm",
		text = "Visible to Director only",
	},
}

local g_rollOptionsPlayer = {
	{
		id = "visible",
		text = "Visible to Everyone",
	},
	{
		id = "dm",
		text = "Visible to you and Director",
	},
}

function GameHud.CreateRollDialog(self)

	--the creature doing the roll
	local creature = nil

	--creature targeted by the roll.
	local targetCreature = nil

	--a table of multiple tokens targeted by this roll.
	local m_multitargets = nil

	local m_symbols = nil

	local rollType = ''
	local rollSubtype = ''
	local rollProperties = nil

	local resultPanel
	local CalculateRollText

	local rollAllPrompts = nil
	local rollActive = nil
	local beginRoll = nil
	local completeRoll = nil
	local cancelRoll = nil

	local m_shown = 0
    local m_richStatus = nil

	local OnShow = function(richStatus)
		chat.events:Push()
		chat.events:Listen(resultPanel)
        if m_richStatus ~= nil then
            dmhub.PopUserRichStatus(m_richStatus)
            m_richStatus = nil
        end

        m_richStatus = dmhub.PushUserRichStatus(richStatus)

		m_shown = m_shown+1
	end

	local OnHide = function()
        if m_richStatus ~= nil then
            dmhub.PopUserRichStatus(m_richStatus)
            m_richStatus = nil
        end

		if m_shown > 0 then
			chat.events:Pop()
			m_shown = m_shown-1
		end

		if m_shown <= 0 then
			--relinquish the coroutine owning this panel.
			resultPanel.data.coroutineOwner = nil
		end
	end

	local styles = {
		Styles.Panel,
		{
			selectors = {'framedPanel'},
			width = 800,
			height = 600,
			halign = "center",
			valign = "center",
			bgcolor = 'white',
		},
		{
			selectors = {'main-panel'},
			width = '100%-32',
			height = '100%-32',
			flow = 'vertical',
			halign = 'center',
			valign = 'center',
		},
		{
			selectors = {'buttonPanel'},
			width = '100%',
			height = 60,
			flow = 'horizontal',
			valign = 'bottom',
		},
		{
			selectors = {'title'},
			width = 'auto',
			height = 'auto',
			color = 'white',
			halign = 'center',
			valign = 'top',
			fontSize = 28,
		},
		{
			selectors = {'explanation'},
			width = 'auto',
			height = 'auto',
			color = 'white',
			halign = 'center',
			valign = 'top',
			fontSize = 20,
		},
		{
			selectors = {'roll-input'},
			width = '90%',
			halign = 'center',
			priority = 20,
			fontSize = 22,
			height = 34,
			valign = 'center',
		},
		{
			selectors = {'checkbox'},
			height = 30,
			width = 'auto',
		},
		{
			selectors = {'checkbox-label'},
			fontSize = 26,
		},
		{
			selectors = {'modifiers-panel'},
			flow = 'vertical',
			height = 'auto',
			width = 'auto',
		},

		Styles.AdvantageBar,
	}

	local title = gui.Label{
		id = "rollDialogTitle",
		classes = {'title'},
		color = Styles.textColor,
	}

	local explanation = gui.Label{
		classes = {'explanation'},
	}

	local ShowTargetHints

	local rollInput = gui.Input{
		classes = {'roll-input'},
		events = {
			edit = function(element)
				chat.PreviewChat(string.format('/roll %s', element.text))
				ShowTargetHints(element.text)
			end,
			change = function(element)
				chat.PreviewChat(string.format('/roll %s', element.text))
			end,
		},
	}


	local autoRollCheck = gui.Check{
		text = "Auto-roll",
		value = false,
		valign = "bottom",
	}
	local autoHideCheck = gui.Check{
		text = "Auto-hide",
		value = false,
		valign = "bottom",
	}
	local autoQuickCheck = gui.Check{
		text = "Auto-quick",
		value = false,
		valign = "bottom",
	}

	local rollAllPromptsCheck = gui.Check{
		text = "Roll all prompts",
		value = true,
		valign = "bottom",
	}

	local autoRollId = nil

	local autoRollPanel = gui.Panel{
		valign = "bottom",
		width = "80%",
		height = "auto",
		flow = "vertical",
		autoHideCheck,
		autoQuickCheck,
		autoRollCheck,
	}

	local prerollCheck = gui.Check{
		text = "Pre-roll dice",
		value = dmhub.GetSettingValue("preroll"),
		valign = "bottom",
		vmargin = 6,
		change = function(element)
			dmhub.SetSettingValue("preroll", element.value)
			CalculateRollText()
		end,
		textCalculated = function(element)
			element:SetClass("collapsed", (not dmhub.isDM))
		end,
	}

	local updateRollVisibility
	local hideRollDropdown = gui.Dropdown{
		width = 300,
		height = 32,
		valign = "center",
		fontSize = 18,
		idChosen = dmhub.GetSettingValue("privaterolls"),
		options = cond(dmhub.isDM, g_rollOptionsDM, g_rollOptionsPlayer),
		valign = "bottom",
		prepare = function(element)
			element.idChosen = dmhub.GetSettingValue("privaterolls")
		end,

		change = function(element)
			updateRollVisibility:FireEvent("prepare")
		end,
	}

	updateRollVisibility = gui.Check{
		text = "Use roll visibility setting for all rolls",
		valign = "bottom",
		value = dmhub.GetSettingValue("privaterolls:save"),
		prepare = function(element)
			updateRollVisibility:SetClass("hidden", hideRollDropdown.idChosen == dmhub.GetSettingValue("privaterolls"))
		end,
	}

	local m_options

	--a selectors which allows alternate roll options to be selected, e.g. choosing between an Athletics and Acrobatics check.
	local alternateRollsBar


	--targets we record damage or other things about.
	local targetHints = nil

	ShowTargetHints = function(rollText)
		for i,hint in ipairs(targetHints or {}) do
			local str = rollText

			if m_multitargets ~= nil and m_multitargets[i] ~= nil then
				local boons = m_multitargets[i].boons
				if boons ~= nil and boons > 0 then
					str = string.format("%s + %dd4", str, boons)
				elseif boons ~= nil and boons < 0 then
					str = string.format("%s - %dd4", str, -boons)
				end
			end

			if hint.half then
				str = str .. " HALF"
			end
			
			creature.UploadExpectedCreatureDamage(hint.charid, resultPanel.data.rollid, str)
		end
	end

	local RemoveTargetHints = function()
		for _,hint in ipairs(targetHints or {}) do
			creature.UploadExpectedCreatureDamage(hint.charid, resultPanel.data.rollid, nil)
		end
	end

	local rollDisabledLabel
	local rollDiceButton
	local cancelButton

	local modifierChecks = {}
	local modifierDropdowns = {}
	local criticalHit
	local inspirationCheck
	local advantageBar
	local advantageElements = {}
	local advantageOptions = {'Disadvantage', 'Normal', 'Advantage'}
	local advantageState = 2
	local advantageStateLocked = false

	local m_boons = 0

	local boonBar

	local activeModifiers = {}

	local SetAdvantageState

	local m_customContainer
	local m_tableContainer


	--this is the current 'base roll' that is being calculated based on.
	local baseRoll = '1d6'
	CalculateRollText = function()
		activeModifiers = {}

		local rollDisallowed = nil

		local roll = baseRoll

		if rollProperties ~= nil then
			rollProperties:ResetMods()
			for i,element in ipairs(modifierChecks) do
				if element.value then
					element.data.mod.modifier:ModifyRollProperties(element.data.mod.context, creature, rollProperties)
				end
			end

			if not m_customContainer:HasClass("collapsed") then
				m_customContainer:FireEventTree("refreshMods")
			end

			if not m_tableContainer:HasClass("collapsed") then
				m_tableContainer:FireEventTree("refreshMods")
			end
		end

		if GameSystem.UseBoons then
			roll = GameSystem.ApplyBoons(roll, m_boons)
		end

		local isd20roll = rollType == 'd20' or rollType == 'check'

		--do modifiers on the raw goblin script here.
		if creature and isd20roll then
			for i,element in ipairs(modifierChecks) do
				if element.data.mod.modFromTarget then
					--pass
				elseif element.value then
					roll = element.data.mod.modifier:ModifyD20RollEarly(element.data.mod.context, creature, rollSubtype, roll)
				end
			end
		end


		if creature then
			local syms = {
				target = GenerateSymbols(targetCreature)
			}

			if m_symbols ~= nil then
				for k,v in pairs(m_symbols) do
					syms[k] = v
				end
			end
			roll = dmhub.NormalizeRoll(roll, creature:LookupSymbol(syms), "Calculate roll")
		end

		local afterCritMods = {}

		if creature then
			for i,element in ipairs(modifierChecks) do
				local show = true
				if rollType == 'damage' then
					show = (not element.data.mod.modifier:CriticalHitsOnly()) or criticalHit.value
					element:SetClass('collapsed-anim', not show)
				end

				if show and element.value then
					--call this generic function which might be modified by mods.
					roll = element.data.mod.modifier:ApplyToRoll(element.data.mod.context, creature, targetCreature, rollType, roll)

					if rollType == 'damage' then
						if element.data.mod.modFromTarget then
							roll = element.data.mod.modifier:ModifyDamageAgainstUs(element.data.mod.context, targetCreature, creature, roll)

						elseif element.data.mod.modifier:CriticalHitsOnly() then
							afterCritMods[#afterCritMods+1] = element.data.mod
						else
							roll = element.data.mod.modifier:ModifyDamageRoll(element.data.mod, creature, targetCreature, roll)
						end
					end

					if isd20roll then
						if element.data.mod.modFromTarget then
							roll = element.data.mod.modifier:ModifyAttackAgainstUs(element.data.mod.context, targetCreature, creature, roll)
						else
							roll = element.data.mod.modifier:ModifyD20Roll(element.data.mod.context, creature, rollSubtype, roll)
						end
					end
					activeModifiers[#activeModifiers+1] = element.data.mod.modifier
				end
			end

			for i,dropdown in ipairs(modifierDropdowns) do
				for j,option in ipairs(dropdown.data.mod.modifierOptions) do
					if option.id == dropdown.idChosen and option.mod ~= nil then
						if rollType == 'damage' then
							roll = option.mod:ModifyDamageRoll(option, creature, targetCreature, roll)
						end

						if isd20roll then
							roll = option.mod:ModifyD20Roll(option.context, creature, rollSubtype, roll)
						end
						activeModifiers[#activeModifiers+1] = option.mod

						if option.disableRoll then
							rollDisallowed = option.disableRoll
						end
					end
				end
			end
		end

		if rollDisallowed ~= nil then
			rollDisabledLabel:SetClass("collapsed-anim", false)
			rollDisabledLabel.text = rollDisallowed
		else
			rollDisabledLabel:SetClass("collapsed-anim", true)
		end

		rollDiceButton:SetClass("hidden", rollDisallowed ~= nil)


		if inspirationCheck.value then
			roll = roll .. " advantage"
		end

		if advantageStateLocked then
			if advantageOptions[advantageState] == 'Advantage' then
				roll = dmhub.ForceRollAdvantage(roll, 'advantage')
			elseif advantageOptions[advantageState] == 'Disadvantage' then
				roll = dmhub.ForceRollAdvantage(roll, 'disadvantage')
			else
				roll = dmhub.ForceRollAdvantage(roll, 'normal')
			end
		else
			local adv = dmhub.GetRollAdvantage(roll)
			if adv == "disadvantage" then
				SetAdvantageState(1)
			elseif adv == "advantage" then
				SetAdvantageState(3)
			else
				SetAdvantageState(2)
			end
		end

		local rollInfo = dmhub.ParseRoll(roll, creature)

	--if criticalHit.value then
	--	for catname,category in pairs(rollInfo.categories) do
	--		for i,group in ipairs(category.groups) do
	--			group.numDice = group.numDice * 2
	--		end
	--	end
	--end

		local newText = dmhub.RollToString(rollInfo)

		if #afterCritMods > 0 then
			for i,mod in ipairs(afterCritMods) do
				newText = mod.modifier:ModifyDamageRoll(mod, creature, targetCreature, newText)
			end

			rollInfo = dmhub.ParseRoll(newText, creature)
			newText = dmhub.RollToString(rollInfo)
		end

		if m_multitargets ~= nil then
			local extraboons = 0
			local extrabanes = 0
			for i,target in ipairs(m_multitargets) do
				if target.boons > 0 then
					extraboons = math.max(extraboons, target.boons)
				else
					extrabanes = math.max(extrabanes, -target.boons)
				end
			end

			if extraboons > 0 then
				newText = string.format("%s %dd4 [extraboons]", newText, extraboons)
			end

			if extrabanes > 0 then
				newText = string.format("%s -%dd4 [extrabanes]", newText, extrabanes)
			end
		end

		if dmhub.isDM and dmhub.GetSettingValue("preroll") then
			local cats = dmhub.RollInstantCategorized(newText)
			newText = ""
			for k,n in pairs(cats) do
				newText = string.format("%s%s%s [%s]", newText, cond(newText == "", "", " "), n, k)
			end

			newText = dmhub.RollToString(dmhub.ParseRoll(newText, creature))
		end

		if GameSystem.CombineNegativesForRolls then
			newText = dmhub.NormalizeRoll(newText, nil, nil, {"NormalizeNegatives"})
		end

		if newText ~= rollInput.text then
			rollInput.text = newText
		else
			rollInput:FireEvent('change')
		end

		ShowTargetHints(newText)

		resultPanel:FireEventTree("textCalculated")
	end

	local rerollFudgedButton = gui.IconButton{
		icon = "panels/hud/clockwise-rotation.png",
		halign = "right",
		valign = "center",
		style = {
			width = 32,
			height = 32,
		},
		click = function(element)
			CalculateRollText()
		end,
		textCalculated = function(element)
			element:SetClass("hidden", (not dmhub.isDM) or (not dmhub.GetSettingValue("preroll")))
		end,
	}

	local rollInputContainer = gui.Panel{
		width = "auto",
		flow = "horizontal",
		width = '80%',
		halign = 'center',
		height = 34,
		valign = 'center',
		rollInput,
		rerollFudgedButton,
	}

	local tableStyles = {
		Styles.Table,
		gui.Style{
			selectors = {"label"},
			pad = 6,
			fontSize = 20,
			width = "auto",
			height = "auto",
			color = Styles.textColor,
			valign = "center",
		},
		gui.Style{
			selectors = {"row"},
			width = "auto",
			height = "auto",
			bgimage = "panels/square.png",
			borderColor = Styles.textColor,
			borderWidth = 1,
		},
		gui.Style{
			selectors = {"row", "oddRow"},
			bgcolor = "#222222ff",
		},
		gui.Style{
			selectors = {"row", "evenRow"},
			bgcolor = "#444444ff",
		},
	}

	m_customContainer = gui.Panel{
		width = "80%",
		height = "auto",
		halign = "center",
		valign = "bottom",
		flow = "vertical",
		styles = tableStyles,
	}

	m_tableContainer = gui.Table{
		width = "60%",
		height = "auto",
		halign = "center",
		valign = "bottom",
		flow = "vertical",
		styles = tableStyles,
	}

	local multitokenContainer = gui.Panel{
		width = 600,
		height = 80,
		halign = "center",
		valign = "bottom",
		flow = "horizontal",
		prepare = function(element, options)
			if m_multitargets == nil or #m_multitargets <= 1 then
				element:SetClass("collapsed", true)
				return
			end

			element:SetClass("collapsed", false)

			local children = {}

			for i,target in ipairs(m_multitargets) do
				local boonLabel = gui.Label{
					fontSize = 12,
					color = cond(target.text == nil, Styles.textColor, "#9999ffff"),
					width = "auto",
					height = 16,
					halign = "center",
					valign = "top",
					prepare = function(element)
						if target.boons == 0 then
							element.text = "--"
						elseif target.boons == 1 then
							element.text = "1 Boon"
						elseif target.boons == -1 then
							element.text = "1 Bane"
						elseif target.boons > 0 then
							element.text = string.format("%d Boons", target.boons)
						else
							element.text = string.format("%d Banes", -target.boons)
						end
					end,

					hover = function(element)
						if target.text ~= nil then
							gui.Tooltip(target.text)(element)
						end
					end,
				}

				local tokenPanel = gui.Panel{
					width = 80,
					height = 80,
					flow = "vertical",

					gui.CreateTokenImage(target.token, {
						halign = "center",
						valign = "top",
						width = 48,
						height = 48,

					}),

					boonLabel,

					gui.Panel{
						flow = "horizontal",
						width = 80,
						height = 16,

						gui.Button{
							borderWidth = 1,
							hmargin = 0,
							vmargin = 0,
							width = 34,
							height = 14,
							halign = "center",
							fontSize = 10,
							text = "+Boon",
							click = function(element)
								target.boons = target.boons + 1
								boonLabel:FireEvent("prepare")
								CalculateRollText()
							end,
						},

						gui.Button{
							borderWidth = 1,
							hmargin = 0,
							vmargin = 0,
							width = 34,
							height = 14,
							halign = "center",
							fontSize = 10,
							text = "+Bane",
							click = function(element)
								target.boons = target.boons - 1
								boonLabel:FireEvent("prepare")
								CalculateRollText()
							end,
						},
					}
				}

				children[#children+1] = tokenPanel
			end

			element.children = children
		end,
	}

	criticalHit = gui.Check{
		text = 'Critical Hit',
		events = {
			change = function(element)
				CalculateRollText()
			end,
			prepare = function(element, options)
				element:SetClass('collapsed-anim', options.type ~= 'damage' or options.critical == nil or GameSystem.CriticalHitsModifyDamage == false)
				element.SetValue(element, options.critical == true, false)
			end,
		},
	}

	inspirationCheck = gui.Check{
		text = "Use Inspiration",
		events = {
			change = function(element)
				CalculateRollText()
			end,
			prepare = function(element, options)
				element:SetClass('collapsed-anim', options.type ~= 'd20' or creature == nil or not creature:HasInspiration())
				element.SetValue(element, false)
			end,
		},
	}

	SetAdvantageState = function(n, locked)
		advantageStateLocked = locked
		advantageState = n
		for i,element in ipairs(advantageElements) do
			element:SetClass('selected', i == n)
			element:SetClass('locked', i == n and locked)
		end
	end

	for i,option in ipairs(advantageOptions) do
		local lockIcon = gui.Panel{
			classes = {'advantage-element-lock-icon'},
			bgimage = 'game-icons/padlock.png',
		}
		local nIndex = i
		advantageElements[#advantageElements+1] = gui.Label{
			bgimage = 'panels/square.png',
			classes = {'advantage-element'},
			text = option,
			click = function(element)
				SetAdvantageState(nIndex, cond(advantageStateLocked and advantageState == nIndex, false, true))
				CalculateRollText()
			end,

			lockIcon,
		}
	end

	alternateRollsBar = gui.Panel{
		classes = {'advantage-bar'},
		prepare = function(element, options)
			if options.alternateOptions == nil or #options.alternateOptions <= 1 then
				element:SetClass("collapsed-anim", true)
				return
			end

			local chooseAlternate = options.chooseAlternate
			local children = {}
			for optionIndex,alternate in ipairs(options.alternateOptions) do
				children[#children+1] = gui.Label{
					bgimage = 'panels/square.png',
					classes = {'advantage-element', cond(options.alternateChosen == optionIndex, "selected")},
					text = alternate.text,
					click = function(element)
						chooseAlternate(optionIndex)
					end,
				}
				
			end

			element.children = children
			element:SetClass("collapsed-anim", false)
		end,
	}

	if GameSystem.UseBoons then
		boonBar = gui.Panel{
			width = 400,
			height = "auto",
			halign = "center",
			valign = "top",
			flow = "horizontal",

			prepare = function(element, options)
				element:SetClass("collapsed", not GameSystem.AllowBoonsForRoll(options))
				m_boons = 0
			end,

			gui.Button{
				width = 120,
				height = 32,
				text = "+ Edge",
				halign = "left",
				click = function(element)
					if m_boons < 2 then
						m_boons = m_boons + 1
						CalculateRollText()
					end
				end,
			},

			gui.Button{
				width = 120,
				height = 32,
				text = "+ Bane",
				halign = "right",
				click = function(element)
					if m_boons > -2 then
						m_boons = m_boons - 1
						CalculateRollText()
					end
				end,
			},
		}
	end

	advantageBar = gui.Panel{
		classes = {'advantage-bar'},
		children = advantageElements,
		prepare = function(element, options)
			element:SetClass('collapsed-anim', options.type ~= 'd20' and options.type ~= 'save' and options.type ~= 'check')
			SetAdvantageState(2)
		end,
	}

	local modifiersPanel = gui.Panel{
		classes = {'modifiers-panel'},
		criticalHit,
		events = {
			prepare = function(element, options)


				modifierChecks = {}
				modifierDropdowns = {}
				if creature == nil or options.modifiers == nil then
					element.children = {criticalHit}
					element:SetClass('collapsed-anim', true)
					return
				end

				element:SetClass('collapsed-anim', false)

				local addedCritical = false

				local children = {}

				for i,mod in ipairs(options.modifiers) do
					if mod.modifier then
						local ischecked = false
						local force = mod.modifier:try_get("force", false)
						if force then
							ischecked = true
						elseif mod.hint ~= nil then
							ischecked = mod.hint.result
						end

						local check --gui.Check that will come out of this.

						local tooltip = mod.modifier:GetSummaryText()
						for i,justification in ipairs(mod.hint.justification) do
							tooltip = string.format("%s\n<color=%s>%s", tooltip, cond(ischecked, '#aaffaa', '#ffaaaa'), justification)
						end

						local text = mod.modifier.name
						if mod.modFromTarget then
							text = string.format("Target is %s", text)
						end

						local upcastPanels = nil
						local upcastCells = nil

						--is the resource for this modifier an upcastable resource (spell slot) and we should let them select
						--which slot to use from a table of icons.
						local upcastable = mod.modifier:IsResourceCostUpcastable()
						if upcastable then
							mod.modifier:get_or_add("_tmp_symbols", {}).upcast = 0

							--these variables should all initialize fine based on IsResourceCostUpcastable being true.
							local resourceid = mod.modifier.resourceCost
							local resourceTable = dmhub.GetTable("characterResources")
							local baseResource = resourceTable[resourceid]

							local baseLevel = baseResource:GetSpellSlot()

							local resourcesAvailable = creature:GetResources()

							--lists of lists of resources, each a row of ascending order resources.
							local rows = {}

							local slotResources = {}

							for k,v in pairs(resourcesAvailable) do
								local resourceInfo = resourceTable[k]
								if resourceInfo ~= nil and resourceInfo:GetSpellSlot() ~= nil and resourceInfo:GetSpellSlot() >= baseLevel then
									slotResources[k] = resourceInfo
									if resourceInfo:GetSpellSlot() == baseLevel then
										rows[#rows+1] = {resourceInfo}
									end
								end
							end

							for _,row in ipairs(rows) do
								local foundNew = true
								local count = 0
								while foundNew and count < 100 do

									foundNew = false
									for _,resourceInfo in pairs(slotResources) do
										if resourceInfo.levelsFrom == row[#row].id then
											row[#row+1] = resourceInfo
											foundNew = true
										end
									end


									count = count + 1
								end
							end

							table.sort(rows, function(a,b) return a[1] == baseResource end)

							upcastCells = {}
							upcastPanels = {}
							for _,row in ipairs(rows) do
								local cells = {}

								for nupcast,cell in ipairs(row) do
									local maxResources = resourcesAvailable[cell.id] 
									local curResources = math.max(0, maxResources - creature:GetResourceUsage(cell.id, cell.usageLimit))
									local cellPanel = gui.Panel{
										classes = {"cell", cond(cell == baseResource, "selected")},
										flow = "vertical",
										width = "auto",
										height = "auto",
										bgimage = "panels/square.png",
										bgcolor = "clear",
										styles = {
											{
												selectors = {"cell", "hover"},
												borderWidth = 2,
												borderColor = "#ffffff99",
											},
											{
												selectors = {"cell", "selected"},
												borderWidth = 2,
												borderColor = "white",
											},
										},

										press = function(element)
											for _,p in ipairs(upcastCells) do
												p:SetClass("selected", p == element)
											end

											check.data.mod.modifier.consumeResourceOverride = cell.id
											check.data.mod.modifier:get_or_add("_tmp_symbols", {}).upcast = nupcast-1

											CalculateRollText()
										end,

										gui.Panel{
											width = 32,
											height = 32,
											classes = {cond(curResources == 0, "expended", "normal")},
											styles = cell:CreateStyles(),
										},
										gui.Label{
											height = 16,
											width = 32,
											fontSize = 12,
											textAlignment = "center",
											color = cond(curResources == 0, "#ffffff77", "white"),
											text = string.format("%d/%d", curResources, maxResources),
										}
									}
									cells[#cells+1] = cellPanel
									upcastCells[#upcastCells+1] = cellPanel
								end

								local rowPanel = gui.Panel{
									classes = {cond(ischecked, nil, "collapsed-anim")},
									height = 32,
									width = "auto",
									flow = "horizontal",
									children = cells,
								}

								upcastPanels[#upcastPanels+1] = rowPanel
							end

						else --end of upcastable section.

							--non upcastable resource usage gets an availability description.
							local availability = mod.modifier:DescribeResourceAvailability(creature)
							if availability then
								text = string.format("%s (%s)", text, availability)
							end

						end 


						local classes = nil

						if force then
							classes = {"collapsed-anim"}
						end

						if mod.modifier:CriticalHitsOnly() then
							if addedCritical == false then
								children[#children+1] = criticalHit
								addedCritical = true
							end

							if not options.critical then
								classes = {"collapsed-anim"}
							end
						end

						check = gui.Check{
							classes = classes,
							text = text,
							value = ischecked,
							data = {
								mod = mod,
							},
							events = {
								change = function(element)
									CalculateRollText()
									if upcastPanels ~= nil then
										for _,p in ipairs(upcastPanels) do
											p:SetClass("collapsed-anim", not element.value)
										end
									end
								end,
								linger = gui.Tooltip{
									text = tooltip,
									maxWidth = 600,
								},
							},
						}

						children[#children+1] = check
						modifierChecks[#modifierChecks+1] = check

						if upcastPanels ~= nil then
							for _,p in ipairs(upcastPanels) do
								children[#children+1] = p
							end
						end

					elseif mod.check then
						--this is a checkbox that is passed in that we will pass the results of straight out.

						local check = gui.Check{
							text = mod.text,
							value = mod.value,
							data = {
								mod = mod,
							},
							events = {
								change = function(element)
									element.data.mod.change(element.value)
								end,
								linger = function(element)
									if mod.tooltip ~= nil then
										gui.Tooltip{
											text = element.data.mod.tooltip,
											maxWidth = 600,
										}(element)
									end
								end,
							},
						}

						children[#children+1] = check
					elseif mod.modifierOptions then
						local dropdown = gui.Dropdown{
							width = 300,
							height = 26,
							valign = "center",
							fontSize = 18,
							idChosen = mod.hint.result,
							options = mod.modifierOptions,
							data = {
								mod = mod,
							},
							change = function(element)
								CalculateRollText()
							end,
						}

						local panel = gui.Panel{
							flow = "horizontal",
							height = 36,
							width = "80%",
							gui.Label{
								text = mod.text .. ":",
								classes = "explanation",
								halign = "left",
								valign = "center",
								width = 120,
							},
							linger = gui.Tooltip{
								text = mod.tooltip,
								maxWidth = 600,
							},
							dropdown,
						}

						modifierDropdowns[#modifierDropdowns+1] = dropdown
						children[#children+1] = panel
					end
				end

				if addedCritical == false then
					children[#children+1] = criticalHit
					addedCritical = true
				end

				element.children = children
			end
		},
	}

	local CancelRollDialog = function()
		RemoveTargetHints()
		if cancelRoll ~= nil then
			if not rollAllPromptsCheck:HasClass("collapsed-anim") and rollAllPromptsCheck.value and rollAllPrompts ~= nil then
				rollAllPrompts()
			end
			cancelRoll()
		end
		resultPanel:SetClass('hidden', true)
		chat.PreviewChat('')
		OnHide()
	end

	rollDiceButton = gui.PrettyButton{
				text = 'Roll Dice',
				style = {
					width = 200,
					height = 50,
					halign = 'right',
				},
				events = {
					click = function(element)
						resultPanel:FireEvent('submit')
					end,
					enter = function(element)
						element:FireEvent("click")
					end,
				}
			}

	cancelButton = gui.PrettyButton{
				text = 'Cancel',
				escapeActivates = true,
				escapePriority = EscapePriority.EXIT_ROLL_DIALOG,
				style = {
					width = 200,
					height = 50,
					halign = 'right',
				},
				events = {
					click = function(element)
						CancelRollDialog()
					end,
				}
			}

	rollDisabledLabel = gui.Label{
		classes = {'explanation', "collapsed-anim"},
		color = "#ffaaaaff",
		valign = "bottom",
	}

	local buttonPanel = gui.Panel{
		classes = {'buttonPanel'},
		children = {
			rollDiceButton,
			cancelButton,
		},
	}

	local mainPanel = gui.Panel{
		classes = {'main-panel'},
		children = {
			title,
			gui.Divider{ width = "50%" },
			explanation,
			alternateRollsBar,
			modifiersPanel,
			inspirationCheck,
			advantageBar,
			boonBar,
			m_tableContainer,
			m_customContainer,
			rollInputContainer,
			multitokenContainer,
			autoRollPanel,
			prerollCheck,
			hideRollDropdown,
			updateRollVisibility,
			rollAllPromptsCheck,
			rollDisabledLabel,
			buttonPanel,
		}
	}

	local delayRoll = 0
	local rollIsSilent = false

	resultPanel = gui.Panel{
		classes = {'framedPanel', 'hidden'},

		styles = styles,

		children = {
			mainPanel,
		},

		data = {

			rollid = nil,

			coroutineOwner = nil,

			ShowDialog = function(options)


				if not resultPanel.valid then
					return
				end

				--deep copy any modifiers so we can freely modify them.
				options.modifiers = DeepCopy(options.modifiers or {})
                table.sort(options.modifiers, function(a,b)
                    if a.modifier ~= nil and b.modifier == nil then
                        return true
                    end

                    if a.modifier == nil and b.modifier ~= nil then
                        return false
                    end

                    if a.modifier == nil then
                        return false
                    end

                    return a.modifier.priority < b.modifier.priority
                end)

				if coroutine.GetCurrentId() ~= nil then
					if resultPanel.data.coroutineOwner == nil then
						resultPanel.data.coroutineOwner = coroutine.GetCurrentId()
					else
						while resultPanel.data.coroutineOwner ~= coroutine.GetCurrentId() and coroutine.IsCoroutineWithIdStillRunning(resultPanel.data.coroutineOwner) do
							coroutine.yield(0.01)
						end

						resultPanel.data.coroutineOwner = coroutine.GetCurrentId()
					end
				end

				if options.delay ~= nil then

					local a,b = coroutine.running()

					if dmhub.inCoroutine then
						local t = dmhub.Time()
						while dmhub.Time() < t + delay do
							coroutine.yield(0.02)
						end
					else

						local delay = options.delay

						local optionsCopy = {}
						for k,v in pairs(options) do
							optionsCopy[k] = v
						end
						
						optionsCopy.rollid = dmhub.GenerateGuid()
						optionsCopy.delay = nil

						dmhub.Schedule(delay, function()
							if resultPanel.valid then
								resultPanel.data.ShowDialog(optionsCopy)
							end
						end)


						return optionsCopy.rollid
					end
				end

				if dmhub.inCoroutine then
					while not resultPanel:HasClass("hidden") do
						coroutine.yield(0.02)

						if not resultPanel.valid then
							return
						end
					end
				elseif not resultPanel:HasClass("hidden") then
					local rollid = dmhub.GenerateGuid()
					--not in a coroutine so just reschedule this.
					dmhub.Schedule(1.0, function()
						if resultPanel.valid then
							local optionsCopy = {}
							for k,v in pairs(options) do
								optionsCopy[k] = v
							end
							
							optionsCopy.rollid = rollid

							resultPanel.data.ShowDialog(optionsCopy)
						end
					end)

					return rollid
				end

				if options.skipDeterministic and dmhub.IsRollDeterministic(options.roll) then
					--this is a quick, happy path that we try to take if the roll is deterministic and we don't need to show the dialog.
					--This is used to avoid the significant performance cost of creating the UI elements.

					local activeModifiers = false
					for _,mod in ipairs(options.modifiers or {}) do
						if mod.modifier then

							local ischecked = false
							local force = mod.modifier:try_get("force", false)
							if force then
								ischecked = true
							elseif mod.hint ~= nil then
								ischecked = mod.hint.result
							end

							if ischecked then
								activeModifiers = true
								break
							end
						end
					end

					if not activeModifiers then

						local guid = dmhub.GenerateGuid()

						local tokenid = nil
						if options.creature ~= nil then
							tokenid = dmhub.LookupTokenId(creature)
						end

						dmhub.Roll{
							guid = guid,
							description = options.description,
							tokenid = tokenid,
							silent = true,
							instant = true,
							roll = options.roll,
							creature = options.creature,
							properties = options.rollProperties,
							complete = function(rollInfo)
								if options.completeRoll ~= nil then
									options.completeRoll(rollInfo)
								end
							end
						}

						return guid
					end
				end

				if options.tableRef ~= nil then
					--delegate table rolls to the specialized dialog for them.
					return resultPanel.data.rollOnTableDialog.data.ShowDialog(options)
				end

				if options.PopulateTable ~= nil then
					m_tableContainer:SetClass("collapsed", false)
					options.PopulateTable(m_tableContainer)
				else
					m_tableContainer:SetClass("collapsed", true)
				end

				if options.PopulateCustom ~= nil then
					m_customContainer:SetClass("collapsed", false)
					options.PopulateCustom(m_customContainer)
				else
					m_customContainer:SetClass("collapsed", true)
				end

				rollDiceButton.hasFocus = true

				m_symbols = options.symbols

				resultPanel.data.rollid = options.rollid or dmhub.GenerateGuid()
				rollIsSilent = false
				delayRoll = 0

                local richStatus = "Rolling dice"
                if options.title then
                    richStatus = string.format("Rolling %s", options.title)
                end

				if resultPanel:HasClass('hidden') then
					resultPanel:SetClass('hidden', false)
					OnShow(richStatus)
				end

				if not options.nofadein then
					resultPanel:PulseClass("fadein")
				end

				m_options = options

				targetHints = options.targetHints


				advantageStateLocked = false
				rollType = options.type
				rollSubtype = options.subtype
				rollProperties = options.rollProperties

				creature = options.creature
				targetCreature = options.targetCreature
				m_multitargets = options.multitargets

				title.text = options.title or 'Roll Dice'
				explanation.text = options.explanation or ''
				if rollInput.text == options.roll then
					--force the edit event if we already have this set.
					rollInput:FireEvent('edit')
				end

				rollAllPrompts = options.rollAllPrompts
				rollActive = options.rollActive
				beginRoll = options.beginRoll
				completeRoll = options.completeRoll
				cancelRoll = options.cancelRoll

				resultPanel:FireEventTree('prepare', options)

				baseRoll = options.roll
				CalculateRollText()

				if options.numPrompts ~= nil and options.numPrompts > 1 then
					rollAllPromptsCheck.value = true
					rollAllPromptsCheck.data.SetText(string.format("Roll all %d prompts", options.numPrompts))
					rollAllPromptsCheck:SetClass("collapsed-anim", false)
				else
					rollAllPromptsCheck.value = false
					rollAllPromptsCheck:SetClass("collapsed-anim", true)
				end

				if options.skipDeterministic and dmhub.IsRollDeterministic(rollInput.text) and dmhub.IsRollDeterministic(options.roll) then
					rollIsSilent = true
					if options.delayInstant ~= nil then
						delayRoll = options.delayInstant
					end
					rollDiceButton:FireEventTree("click")
				elseif options.autoroll == true or dmhub.GetSettingValue("autorollall") or (options.creature ~= nil and options.creature._tmp_aicontrol > 0) then
					if options.delayInstant ~= nil then
						delayRoll = options.delayInstant or 0.05
					else
						--TODO: Work out why instant rolls have a problem if we don't include a small delay.
						delayRoll = 0.05
					end
					rollDiceButton:FireEventTree("click")
				elseif options.autoroll == "cancel" then
					cancelButton:FireEventTree("click")
				elseif options.autoroll ~= nil then

					local autoroll = dmhub.GetSettingValue(string.format("%s:autoroll", options.autoroll.id))
					local hideFromPlayers = dmhub.GetSettingValue(string.format("%s:hideFromPlayers", options.autoroll.id))
					local quickRoll = dmhub.GetSettingValue(string.format("%s:quickRoll", options.autoroll.id))

					autoRollPanel:SetClass("collapsed-anim", false)
					autoRollCheck.value = autoroll or false
					autoRollCheck.data.SetText(string.format("Auto-roll %s in future", options.autoroll.text))
					autoHideCheck.data.SetText(string.format("Hide %s from players", options.autoroll.text))
					autoQuickCheck.data.SetText(string.format("Skip rolling animation for %s", options.autoroll.text))
					autoRollId = options.autoroll.id

					autoHideCheck.value = hideFromPlayers or false
					autoQuickCheck.value = quickRoll or false


					if autoroll then
						rollDiceButton:FireEventTree("click")
					end
				else
					autoRollPanel:SetClass("collapsed-anim", true)
					autoRollId = nil
				end

				return resultPanel.data.rollid
			end,

			IsShown = function()
				return not resultPanel:HasClass('hidden')
			end,

			Cancel = function()
				CancelRollDialog()
			end,
		},

		events = {
			submit = function(element)

				RemoveTargetHints()

				resultPanel:SetClass('hidden', true)
				OnHide()

				local dmonly = false
				local instant = false

				if autoRollId ~= nil then
					
					dmonly = autoHideCheck.value
					instant = autoQuickCheck.value

					dmhub.SetSettingValue(string.format("%s:autoroll", autoRollId), autoRollCheck.value)
					dmhub.SetSettingValue(string.format("%s:hideFromPlayers", autoRollId), autoHideCheck.value)
					dmhub.SetSettingValue(string.format("%s:quickRoll", autoRollId), autoQuickCheck.value)

				end

				if hideRollDropdown.idChosen == "dm" then
					dmonly = true
				end

				if hideRollDropdown.idChosen ~= dmhub.GetSettingValue("privaterolls") and updateRollVisibility.value then
					--update the setting for private rolls from now on.
					dmhub.SetSettingValue("privaterolls", hideRollDropdown.idChosen)
				end

				dmhub.SetSettingValue("privaterolls:save", updateRollVisibility.value)

				local inspirationUsed = inspirationCheck.value

				if rollAllPrompts ~= nil and rollAllPromptsCheck.value then
					rollAllPrompts()
				end

				--we must save off anything from the surrounding scope since this dialog might be reused after this.
				local activeRollFn = rollActive
				local beginRollFn = beginRoll
				local completeRollFn = completeRoll
				local creatureUsed = creature
				local modifiersUsed = DeepCopy(activeModifiers)

				local tokenid = nil
				
				if creature ~= nil then
					tokenid = dmhub.LookupTokenId(creature)
				end

				rollProperties = rollProperties or RollProperties.new{}
				if not criticalHit:HasClass("collapsed-anim") then
					rollProperties.criticalHitDamage = criticalHit.value
				end

				local activeRoll = dmhub.Roll{
					guid = resultPanel.data.rollid,
					description = m_options.description,
					amendable = m_options.amendable,
					tokenid = tokenid,
					silent = rollIsSilent,
					delay = delayRoll,
					dmonly = dmonly,
					instant = instant,
					roll = rollInput.text,
					creature = creature,
					properties = rollProperties,
					begin = function(rollInfo)
						if beginRollFn ~= nil then
							beginRollFn(rollInfo)
						end
					end,
					complete = function(rollInfo)
						local resourceConsumed = false
						for i,modifier in ipairs(modifiersUsed) do
							local consume = modifier:ConsumeResource(creatureUsed)
							resourceConsumed = consume or resourceConsumed
						end

						local ongoingEffects = {}
						for i,modifier in ipairs(modifiersUsed) do
							local newOngoingEffects = modifier:ApplyOngoingEffectsToSelfOnRoll(creature)
							if newOngoingEffects ~= nil then
								for j,c in ipairs(newOngoingEffects) do
									ongoingEffects[#ongoingEffects+1] = c
								end
							end
						end

						if resourceConsumed or #ongoingEffects > 0 or inspirationUsed then
							local creatureToken = dmhub.LookupToken(creatureUsed)
							if creatureToken ~= nil then
								creatureUsed:SetInspiration(false)
								for i,cond in ipairs(ongoingEffects) do
									creatureUsed:ApplyOngoingEffect(cond.ongoingEffect, cond.duration, nil, {
										untilEndOfTurn = cond.durationUntilEndOfTurn,
									})
								end
								creatureToken:Upload('Used resource')
							end
						end

						if completeRollFn ~= nil then
							completeRollFn(rollInfo)
						end
					end
				}

				if activeRollFn ~= nil then
					activeRollFn(activeRoll)
				end

				chat.PreviewChat('')
			end,
		},
	}

	return resultPanel
end

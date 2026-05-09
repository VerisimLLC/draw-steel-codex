local mod = dmhub.GetModLoading()

--this file implements summoning behavior for abilities.

--- @class ActivatedAbilitySummonBehavior : ActivatedAbilityBehavior
ActivatedAbilitySummonBehavior = RegisterGameType("ActivatedAbilitySummonBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
	id = 'summon',
	text = 'Summon Creatures',
	createBehavior = function()
		return ActivatedAbilitySummonBehavior.new{
		}
	end
}

ActivatedAbilitySummonBehavior.summary = 'Summons Creatures'
ActivatedAbilitySummonBehavior.numSummons = "1"
ActivatedAbilitySummonBehavior.allCreaturesTheSame = false
ActivatedAbilitySummonBehavior.bestiaryFilter = "beast.cr = 1 and beast.type is beast"
ActivatedAbilitySummonBehavior.monsterType = "custom"
ActivatedAbilitySummonBehavior.hasReplaceCaster = true --display 'replace caster' in menu.
ActivatedAbilitySummonBehavior.replaceCaster = false
ActivatedAbilitySummonBehavior.casterControls = true
ActivatedAbilitySummonBehavior.casterChoosesCreatures = true
ActivatedAbilitySummonBehavior.groupInitiativeWithCaster = true
ActivatedAbilitySummonBehavior.shareSurgesWithSummoner = false
ActivatedAbilitySummonBehavior.shareHeroicResourceWithSummoner = false
ActivatedAbilitySummonBehavior.choosePlacement = false
ActivatedAbilitySummonBehavior.summonRange = "1"

--duplicate mode fields
ActivatedAbilitySummonBehavior.duplicateMode = false
ActivatedAbilitySummonBehavior.copyStamina = false
ActivatedAbilitySummonBehavior.copyEffects = false
ActivatedAbilitySummonBehavior.copyConditions = false
ActivatedAbilitySummonBehavior.copyFeatures = false
ActivatedAbilitySummonBehavior.copyResistances = false
ActivatedAbilitySummonBehavior.copyAbilities = false
ActivatedAbilitySummonBehavior.copyTriggers = false
ActivatedAbilitySummonBehavior.duplicateTargetOrigin = "duplicate"


setting{
	id = "summoncrcheck",
	storage = "preference",
	default = true,
}

setting{
	id = "summonallsame",
	storage = "preference",
	default = true,
}


function ActivatedAbilitySummonBehavior:SummarizeBehavior(ability, creatureLookup)
	if self.duplicateMode then
		return "Duplicate Token"
	end
	return "Summon Creatures"
end

--- Displays the squad-selection dialog for a Summoner caster.
--- Returns nil if cancelled, otherwise a result table with the chosen squad and warning flags.
--- @param casterToken CharacterToken
--- @param monsterType string The canonical monster_type of the creature being summoned.
--- @param numSummons number How many creatures will be summoned into this squad.
--- @param maxMinions number MaximumMinions attribute (0 means unlimited).
--- @param maxSquads number MaxMinionSquads attribute (0 means unlimited).
--- @return table|nil result { squadName, isNew, exceededMinions, exceededSquads } or nil if cancelled.
function ActivatedAbilitySummonBehavior.ShowSquadChoiceDialog(casterToken, monsterType, numSummons, maxMinions, maxSquads)
    local SQUAD_CAP = 8

    local caster = casterToken.properties
    local squadsByType = caster:GetSummonedSquadsByType(monsterType)
    local allSquads = caster:GetSummonedSquadsByType(nil)
    local liveEntries = caster:GetLiveSummonedEntries()

    local existingSquadNames = {}
    for name,_ in pairs(squadsByType) do
        existingSquadNames[#existingSquadNames+1] = name
    end
    table.sort(existingSquadNames)

    local totalSquadCount = 0
    for _ in pairs(allSquads) do
        totalSquadCount = totalSquadCount + 1
    end

    local currentMinionCount = #liveEntries

    -- If no same-type squad exists the caster has no choice but to open a new squad,
    -- so we skip the dialog entirely and auto-assign a fresh squad name.
    local hasExistingSameTypeSquad = #existingSquadNames > 0
    if not hasExistingSameTypeSquad then
        local autoSquadName = monster.FindFreshSquadName(monsterType)
        local exceededMinions = (maxMinions > 0 and currentMinionCount + numSummons > maxMinions)
        return {
            squadName = autoSquadName,
            isNew = true,
            exceededMinions = exceededMinions,
            exceededSquads = false,
        }
    end

    local chosenSquadName = nil
    local chosenIsNew = false
    local canceled = false
    local finished = false
    local optionPanels = {}

    local function ComputeWarnings()
        local exceededMinions = false
        local exceededSquads = false
        if maxMinions > 0 and currentMinionCount + numSummons > maxMinions then
            exceededMinions = true
        end
        if chosenIsNew and hasExistingSameTypeSquad and maxSquads > 0 and totalSquadCount + 1 > maxSquads then
            exceededSquads = true
        end
        return exceededMinions, exceededSquads
    end

    local minionStatusLabel
    local squadStatusLabel

    local function FormatMinionStatus()
        local projected = currentMinionCount + numSummons
        if maxMinions > 0 then
            return string.format("Minions: %d -> %d / %d", currentMinionCount, projected, maxMinions), projected > maxMinions
        end
        return string.format("Minions: %d -> %d", currentMinionCount, projected), false
    end

    local function FormatSquadStatus(isNewSelection)
        local projected = totalSquadCount + (isNewSelection and 1 or 0)
        local exceeded = isNewSelection and hasExistingSameTypeSquad and maxSquads > 0 and projected > maxSquads
        if maxSquads > 0 then
            return string.format("Squads: %d -> %d / %d", totalSquadCount, projected, maxSquads), exceeded
        end
        return string.format("Squads: %d -> %d", totalSquadCount, projected), exceeded
    end

    local function RefreshStatusLabels()
        if minionStatusLabel ~= nil and minionStatusLabel.valid then
            local text, exceeded = FormatMinionStatus()
            minionStatusLabel.text = text
            minionStatusLabel:SetClass("exceeded", exceeded)
        end
        if squadStatusLabel ~= nil and squadStatusLabel.valid then
            local text, exceeded = FormatSquadStatus(chosenIsNew)
            squadStatusLabel.text = text
            squadStatusLabel:SetClass("exceeded", exceeded)
        end
    end

    local function BuildOptionRow(labelText, noteText, isNew, squadName, warn)
        local row
        row = gui.Panel{
            classes = {"squadOption", cond(warn, "warn")},
            flow = "horizontal",
            gui.Label{
                classes = {"sizeM"},
                text = labelText,
                textAlignment = "left",
                halign = "left",
                width = "60%",
                height = "auto",
            },
            gui.Label{
                classes = {"sizeS", "squadOptionNote"},
                text = noteText or "",
                textAlignment = "left",
                halign = "left",
                width = "auto",
                height = "auto",
            },
            press = function(element)
                for _,p in ipairs(optionPanels) do
                    p:SetClass("selected", p == element)
                end
                chosenSquadName = squadName
                chosenIsNew = isNew
                RefreshStatusLabels()
            end,
        }
        return row
    end

    local exceedsMinionCap = (maxMinions > 0 and currentMinionCount + numSummons > maxMinions)

    for _,name in ipairs(existingSquadNames) do
        local info = squadsByType[name]
        local newTotal = info.count + numSummons
        local warn = newTotal > SQUAD_CAP or exceedsMinionCap
        local note = string.format("(%d/%d minions)", info.count, SQUAD_CAP)
        local row = BuildOptionRow(name, note, false, name, warn)
        optionPanels[#optionPanels+1] = row
    end

    local newSquadName = monster.FindFreshSquadName(monsterType)
    local newWarn = exceedsMinionCap or (hasExistingSameTypeSquad and maxSquads > 0 and totalSquadCount + 1 > maxSquads)
    local newRow = BuildOptionRow(string.format("New squad: %s", newSquadName), nil, true, newSquadName, newWarn)
    optionPanels[#optionPanels+1] = newRow

    -- Default selection: the first existing same-type squad (if any), otherwise the new-squad option.
    -- Over-cap squads are still selectable; the warning colors communicate the state.
    local defaultIndex
    if #existingSquadNames > 0 then
        defaultIndex = 1
        chosenSquadName = existingSquadNames[1]
        chosenIsNew = false
    else
        defaultIndex = #optionPanels
        chosenSquadName = newSquadName
        chosenIsNew = true
    end
    optionPanels[defaultIndex]:SetClass("selected", true)

    local initialMinionText, initialMinionExceeded = FormatMinionStatus()
    local initialSquadText, initialSquadExceeded = FormatSquadStatus(chosenIsNew)

    minionStatusLabel = gui.Label{
        classes = {"sizeS", "statusLabel", cond(initialMinionExceeded, "exceeded")},
        text = initialMinionText,
        textAlignment = "center",
        halign = "center",
        valign = "top",
        width = 560,
        height = "auto",
        vmargin = 2,
    }

    squadStatusLabel = gui.Label{
        classes = {"sizeS", "statusLabel", cond(initialSquadExceeded, "exceeded")},
        text = initialSquadText,
        textAlignment = "center",
        halign = "center",
        valign = "top",
        width = 560,
        height = "auto",
        vmargin = 2,
    }

    gamehud:ModalDialog{
        title = "Assign to Squad",
        buttons = {
            {
                text = "Assign",
                click = function()
                    finished = true
                end,
            },
            {
                text = "Cancel",
                escapeActivates = true,
                click = function()
                    finished = true
                    canceled = true
                end,
            },
        },

        styles = ThemeEngine.MergeTokens{
            {
                selectors = {"squadOption"},
                height = 28,
                width = 560,
                halign = "center",
                valign = "top",
                hmargin = 20,
                vmargin = 2,
                vpad = 4,
                bgimage = true,
                bgcolor = "clear",
            },
            { selectors = {"squadOption","warn"},            bgcolor = "@danger" },
            { selectors = {"squadOption","hover"},           bgcolor = "@bgAlt" },
            { selectors = {"squadOption","warn","hover"},    bgcolor = "@danger", brightness = 1.3 },
            { selectors = {"squadOption","selected"},        bgcolor = "@accent" },
            { selectors = {"squadOption","warn","selected"}, bgcolor = "@danger", brightness = 1.5 },

            { selectors = {"statusLabel"},                   color = "@fgMuted" },
            { selectors = {"statusLabel","exceeded"},        color = "@danger" },

            { selectors = {"squadOptionNote"},               color = "@fgMuted" },
            { selectors = {"squadOptionNote","parent:warn"}, color = "@warning" },
        },

        width = 650,
        height = 500,
        flow = "vertical",


        children = {
            gui.Label{
                classes = {"sizeM"},
                text = string.format("Summoning %d %s%s - choose a squad:", numSummons, monsterType, cond(numSummons == 1, "", "s")),
                textAlignment = "center",
                halign = "center",
                valign = "top",
                width = 600,
                height = "auto",
                vmargin = 6,
            },
            minionStatusLabel,
            squadStatusLabel,
            gui.Panel{
                flow = "vertical",
                vscroll = true,
                valign = "top",
                width = 600,
                halign = "center",
                height = 340,
                children = optionPanels,
            },
        },
    }

    while not finished do
        coroutine.yield(0.1)
    end

    if canceled then
        return nil
    end

    local exceededMinions, exceededSquads = ComputeWarnings()
    return {
        squadName = chosenSquadName,
        isNew = chosenIsNew,
        exceededMinions = exceededMinions,
        exceededSquads = exceededSquads,
    }
end

function ActivatedAbilitySummonBehavior.ShowCreatureChoiceDialog(choices, dialogOptions)
	dialogOptions = dialogOptions or {}
	local chosenOption = nil
	local canceled = false
	local finished = false
	local optionPanels = {}

	local minCR = nil
	local maxCR = 0
	local maxPrettyCR = "0"

	local allSameCheck = nil
	if dialogOptions.index ~= nil and dialogOptions.index < dialogOptions.numSummons and (not dialogOptions.allCreaturesTheSame) then
		allSameCheck = gui.Check{
			classes = {"sizeS"},
			halign = "right",
			valign = "bottom",
			hmargin = 32,
			width = 460,
			height = 30,
			text = string.format("Use this choice for all %s summons", json(1+dialogOptions.numSummons - dialogOptions.index)),
			value = dmhub.GetSettingValue("summonallsame"),
			change = function(element)
				dmhub.SetSettingValue("summonallsame", element.value)
			end,
		}
	end

	for i,option in ipairs(choices) do
		local cr = option.properties:CR()
		if cr > maxCR then
			maxCR = cr
			maxPrettyCR = option.properties:PrettyCR()
		end

		if minCR == nil or cr < minCR then
			minCR = cr
		end
	end

	for i,option in ipairs(choices) do
		local panel = gui.Panel{
			classes = {"option"},
			flow = "horizontal",
			data = {
				CR = option.properties:CR()
			},
			gui.Label{
				classes = {"sizeM"},
				text = option.properties.monster_type,
				textAlignment = "left",
				halign = "left",
				width = "60%",
				height = "auto",
			},
			gui.Label{
				classes = {"sizeM"},
				text = string.format("Level %s", option.properties:PrettyCR()),
				textAlignment = "left",
				halign = "left",
				width = "auto",
				height = "auto",
			},
			press = function(element)
				for _,p in ipairs(optionPanels) do
					p:SetClass("selected", p == element)
				end

				chosenOption = choices[i]
			end,
		}

		if chosenOption == nil and option.properties:CR() == maxCR then
			panel:SetClass("selected", true)
			chosenOption = option
		end

		optionPanels[#optionPanels+1] = panel
	end

	local ShowMaxCROnly = function(val)
		for _,panel in ipairs(optionPanels) do
			if val then
				panel:SetClass("collapsed", panel.data.CR < maxCR)
			else
				panel:SetClass("collapsed", false)
			end
		end
	end

	ShowMaxCROnly(dmhub.GetSettingValue("summoncrcheck"))

	gamehud:ModalDialog{
		title = dialogOptions.title or "Summon Creature",
        valign = "top",
        tmargin = 12,
		buttons = {
			{
				text = dialogOptions.buttonText or "Summon",
				click = function()
					finished = true
				end,
			},
			{
				text = "Cancel",
				escapeActivates = true,
				click = function()
					finished = true
					canceled = true
				end,
			},
		},

		styles = ThemeEngine.MergeTokens{
			{
				selectors = {"option"},
				height = 24,
				width = 500,
				halign = "center",
				valign = "top",
				hmargin = 20,
				vmargin = 0,
				vpad = 4,
				bgimage = true,
				bgcolor = "clear",
			},
			{ selectors = {"option","hover"},    bgcolor = "@bgAlt" },
			{ selectors = {"option","selected"}, bgcolor = "@accent" },
		},

		width = 650,
		height = 700,
		flow = "vertical",

		children = {

			gui.Panel{
                classes = {"bordered"},
				width = 600,
				height = 500,
				valign = "top",
				halign = "center",
                vpad = 8,
				flow = "vertical",
				vscroll = true,
				children = optionPanels,
			},
			gui.Check{
				classes = {"sizeS", cond(minCR == maxCR, "hidden")},
				halign = "right",
				valign = "bottom",
				hmargin = 32,
				width = 460,
				height = 30,
				text = string.format("Show only Level %s creatures", maxPrettyCR),
				value = dmhub.GetSettingValue("summoncrcheck"),
				change = function(element)
					dmhub.SetSettingValue("summoncrcheck", element.value)
					ShowMaxCROnly(element.value)
				end,
			},
			allSameCheck,
		}
	}

	while not finished do
		coroutine.yield(0.1)
	end

	if canceled then
		return nil
	end

	if allSameCheck ~= nil and allSameCheck.valid then
		dialogOptions.allSame = allSameCheck.value
	end

	return chosenOption
end


function ActivatedAbilitySummonBehavior:CastDuplicate(ability, casterToken, targets, args)
    local summonedTokens = {}

    local initiativeGrouping = nil
    if self.groupInitiativeWithCaster then
        initiativeGrouping = InitiativeQueue.GetInitiativeId(casterToken)
    end

    --targets comes from ApplyToTargets, which determines the SOURCE tokens to duplicate.
    --args.targets holds the original ability targets (the locations the player chose).
    --When applyto = "caster", targets = {{token = casterToken}} with no loc,
    --so we use the original target locs for spawn positions.
    local spawnLocs = {}
    if args.targets ~= nil then
        for _,t in ipairs(args.targets) do
            if t.loc ~= nil then
                spawnLocs[#spawnLocs+1] = t.loc
            end
        end
    end

    for i,target in ipairs(targets) do
        local sourceToken = target.token
        if sourceToken == nil then
            print("DUPLICATE:: target has no token, skipping")
            goto continue_duplicate
        end

        --use the original target loc for spawn position if available,
        --otherwise fall back to the source token's location.
        local loc = spawnLocs[i] or spawnLocs[1] or target.loc or sourceToken.loc

        local token = nil
        local isMonster = sourceToken.properties:try_get("__typeName") == "monster"

        if isMonster then
            --monsters can be duplicated directly from their bestiary entry
            local bestiaryId = sourceToken.bestiaryId
            if bestiaryId == nil or bestiaryId == "" then
                print("DUPLICATE:: monster has no bestiaryId, skipping")
                goto continue_duplicate
            end

            token = game.SpawnTokenFromBestiaryLocally(bestiaryId, loc.withGroundAltitude, {
                fitLocation = true,
            })

            if token == nil then
                print("DUPLICATE:: failed to spawn monster token from bestiary")
                goto continue_duplicate
            end
        else
            --character creatures (heroes, followers, etc.) are spawned as
            --monster tokens and have properties copied from the source.
            local newCharId = game.CreateCharacter("monster")
            local newChar = nil
            for attempt = 1, 100 do
                newChar = dmhub.GetCharacterById(newCharId)
                if newChar ~= nil then
                    break
                end
                coroutine.yield(0.1)
            end

            if newChar == nil then
                print("DUPLICATE:: timed out waiting for character creation")
                goto continue_duplicate
            end

            --start with default monster properties, then selectively copy
            --from the source based on settings. The token keeps its own
            --monster base so property types remain consistent.
            local props = newChar.properties
            props.monster_type = sourceToken.properties:try_get("name", "Duplicate")
            props.description = sourceToken.properties:try_get("description", "")

            local srcProps = sourceToken.properties
            local srcMaxHp = srcProps:MaxHitpoints()
            if self.copyStamina then
                props.damage_taken = srcProps.damage_taken
                props.max_hitpoints = srcMaxHp
            end
            if self.copyFeatures then
                props.attributes = DeepCopy(srcProps.attributes)
                props.max_hitpoints = srcMaxHp
                props.walkingSpeed = srcProps:try_get("walkingSpeed", 5)
                props.skillRatings = DeepCopy(srcProps:try_get("skillRatings", {}))
                props.savingThrowRatings = DeepCopy(srcProps:try_get("savingThrowRatings", {}))
                props.innateAttacks = DeepCopy(srcProps:try_get("innateAttacks", {}))
                props.characterFeatures = DeepCopy(srcProps:try_get("characterFeatures", {}))
                props.equipment = DeepCopy(srcProps:try_get("equipment", {}))
            end
            if self.copyResistances then
                props.resistances = DeepCopy(srcProps:try_get("resistances", {}))
                props.innateConditionImmunities = DeepCopy(srcProps:try_get("innateConditionImmunities", {}))
            end
            if self.copyAbilities then
                --for characters, abilities come from class features and modifiers,
                --not just innateActivatedAbilities. Gather all computed abilities
                --and store them as innate on the monster duplicate.
                local sourceAbilities = srcProps:GetActivatedAbilities{excludeGlobal = true}
                props.innateActivatedAbilities = DeepCopy(sourceAbilities)
            end
            if self.copyTriggers then
                props.availableTriggers = DeepCopy(srcProps:try_get("availableTriggers", {}))
            end
            if self.copyConditions then
                props.inflictedConditions = DeepCopy(sourceToken.properties.inflictedConditions)
            end
            if self.copyEffects then
                props.ongoingEffects = DeepCopy(sourceToken.properties.ongoingEffects)
            end

            props.isDuplicate = true
            props.duplicateSourceId = sourceToken.charid

            newChar:UploadToken()
            game.UpdateCharacterTokens()
            newChar:ChangeLocation(core.Loc{x = loc.x, y = loc.y}.withGroundAltitude)

            --wait for the token to be fully created and available on the map,
            --following the same pattern as follower creation in DSFollower.lua.
            for attempt = 1, 100 do
                token = dmhub.GetTokenById(newCharId)
                if token ~= nil then
                    break
                end
                coroutine.yield(0.1)
            end

            if token == nil then
                print("DUPLICATE:: timed out waiting for spawned character token")
                goto continue_duplicate
            end
        end

        token.ownerId = casterToken.ownerId
        token.summonerid = casterToken.charid

        if initiativeGrouping ~= nil then
            token.properties.initiativeGrouping = initiativeGrouping
        end

        --for monsters, selectively copy from the source onto the fresh
        --bestiary spawn. Character duplicates are already set up above.
        if isMonster then
            token:ModifyProperties{
                description = "Duplicate Token",
                execute = function()
                    token.properties.isDuplicate = true
                    token.properties.duplicateSourceId = sourceToken.charid

                    local srcProps = sourceToken.properties
                    local srcMaxHp = srcProps:MaxHitpoints()
                    if self.copyStamina then
                        token.properties.damage_taken = srcProps.damage_taken
                        token.properties.max_hitpoints = srcMaxHp
                    end
                    if self.copyConditions then
                        token.properties.inflictedConditions = DeepCopy(srcProps.inflictedConditions)
                    end
                    if self.copyEffects then
                        token.properties.ongoingEffects = DeepCopy(srcProps.ongoingEffects)
                    end
                    if self.copyFeatures then
                        token.properties.attributes = DeepCopy(srcProps.attributes)
                        token.properties.max_hitpoints = srcMaxHp
                        token.properties.walkingSpeed = srcProps:try_get("walkingSpeed", 5)
                        token.properties.skillRatings = DeepCopy(srcProps:try_get("skillRatings", {}))
                        token.properties.savingThrowRatings = DeepCopy(srcProps:try_get("savingThrowRatings", {}))
                        token.properties.innateAttacks = DeepCopy(srcProps:try_get("innateAttacks", {}))
                        token.properties.characterFeatures = DeepCopy(srcProps:try_get("characterFeatures", {}))
                        token.properties.equipment = DeepCopy(srcProps:try_get("equipment", {}))
                    end
                    if self.copyResistances then
                        token.properties.resistances = DeepCopy(srcProps:try_get("resistances", {}))
                        token.properties.innateConditionImmunities = DeepCopy(srcProps:try_get("innateConditionImmunities", {}))
                    end
                    if self.copyAbilities then
                        local sourceAbilities = srcProps:GetActivatedAbilities{excludeGlobal = true}
                        token.properties.innateActivatedAbilities = DeepCopy(sourceAbilities)
                    end
                    if self.copyTriggers then
                        token.properties.availableTriggers = DeepCopy(srcProps:try_get("availableTriggers", {}))
                    end
                end,
            }
        end

        --copy full appearance (portrait, frame, zoom, offset, etc.) from source
        local appearanceData = sourceToken:SerializeAppearanceToString()
        if appearanceData ~= nil and appearanceData ~= "" then
            token:SerializeAppearanceFromString(appearanceData)
        end

        token.partyid = sourceToken.partyid

        local dupCharId = token.charid
        summonedTokens[#summonedTokens+1] = dupCharId

        token:UploadToken("Duplicate Token")
        game.UpdateCharacterTokens()
        coroutine.yield(0.1)

        ::continue_duplicate::
    end

    --inject spawned duplicates into the target list so subsequent behaviors
    --can target them (e.g. to apply ongoing effects onto the duplicates).
    if #summonedTokens > 0 and args.targets ~= nil and self.duplicateTargetOrigin ~= "source" then
        --ensure all tokens are fully available before injecting
        game.UpdateCharacterTokens()
        coroutine.yield(0.2)
        game.UpdateCharacterTokens()

        --resolve all summoned tokens by charid
        local resolvedTokens = {}
        for _,charid in ipairs(summonedTokens) do
            local resolved = dmhub.GetTokenById(charid)
            if resolved ~= nil then
                resolvedTokens[#resolvedTokens+1] = resolved
            else
                print("DUPLICATE:: could not resolve token for target injection", charid)
            end
        end

        if self.duplicateTargetOrigin == "duplicate" then
            --replace all existing targets with the duplicates
            for i = #args.targets, 1, -1 do
                args.targets[i] = nil
            end
            for _,resolved in ipairs(resolvedTokens) do
                args.targets[#args.targets+1] = {token = resolved, loc = resolved.loc}
            end
        elseif self.duplicateTargetOrigin == "both" then
            --keep existing targets and add the duplicates
            for _,resolved in ipairs(resolvedTokens) do
                args.targets[#args.targets+1] = {token = resolved, loc = resolved.loc}
            end
        end
    end

    if ability:RequiresConcentration() and casterToken.properties:HasConcentration() then
        casterToken:ModifyProperties{
            description = "Concentrate on duplicates",
            execute = function()
                local concentration = casterToken.properties:MostRecentConcentration()
                local summonid = concentration:get_or_add("summonid", {})
                for _,charid in ipairs(summonedTokens) do
                    summonid[#summonid+1] = charid
                end
            end,
        }
    end

    game.UpdateCharacterTokens()
    coroutine.yield(0.1)

    --final re-resolution: ensure all injected targets have valid token refs
    --before subsequent behaviors try to use them.
    if args.targets ~= nil then
        for _,t in ipairs(args.targets) do
            if t.token ~= nil then
                local fresh = dmhub.GetTokenById(t.token.charid)
                if fresh ~= nil then
                    t.token = fresh
                end
            end
        end
    end

    ability:CommitToPaying(casterToken, args)
end

--- Prompts the user to place summons. When squadCtx is provided, also renders an
--- inline squad chip bar.
--- @param casterToken CharacterToken
--- @param rangeTiles number max distance in tiles from casterToken.loc.
--- @param index number which summon
--- @param total number total summons being placed.
--- @param isMinion boolean true if the creature being placed is a minion.
--- @param squadCtx table|nil persistent squad-selection state (see Cast()).
--- @param creatureCtx table|nil persistent creature-selection state with .choices and .selectedCreature.
--- @return Loc|nil pickedLoc, table|nil squadResult, table|nil pickedCreature.
function ActivatedAbilitySummonBehavior.PromptPlacementLoc(casterToken, rangeTiles, index, total, isMinion, squadCtx, creatureCtx)
    local SQUAD_CAP = 8

    local origin = casterToken.loc
    local validLocs = origin:LocsInRadius(rangeTiles)

    local pickedLoc = nil
    local pickedSquadResult = nil
    local pickedCreature = nil
    local cancelled = false

    local rangeMarker = dmhub.MarkLocs{
        locs = validLocs,
        color = "#22cc66",
    }
    local hoverMarker = nil

    local function destroyHoverMarker()
        if hoverMarker ~= nil then
            hoverMarker:Destroy()
            hoverMarker = nil
        end
    end

    local function isInRange(loc)
        return loc ~= nil and origin:DistanceInTiles(loc) <= rangeTiles
    end

    local pickerContent
    local commitWithSquadSelection

    if squadCtx == nil then
        pickerContent = gui.Label{
            halign = "center",
            width = "auto",
            minWidth = 200,
            textAlignment = "center",
            height = "auto",
            bold = true,
            fontSize = 16,
            text = string.format("Place %s %d of %d (Esc to cancel)", isMinion and "minion" or "creature", index, total),
        }
    else
        local headerLabel
        local statusLabel
        local squadBarPanel

        local function CurrentCreatureName()
            if creatureCtx ~= nil and creatureCtx.selectedCreature ~= nil then
                return creatureCtx.selectedCreature.properties.monster_type or (isMinion and "minion" or "creature")
            end
            return isMinion and "minion" or "creature"
        end

        local function SyncMonsterTypeFromCreatureCtx()
            if creatureCtx ~= nil and creatureCtx.selectedCreature ~= nil then
                local newType = creatureCtx.selectedCreature.properties.monster_type
                if squadCtx.monsterType ~= newType then
                    squadCtx.monsterType = newType
                    squadCtx.nextFreshName = nil
                end
            end
        end

        -- Build (or rebuild) the squad chip list, status text, and commit closure
        -- based on the current squadCtx.monsterType. Returns the chip panels.
        local function BuildSquadView()
            local caster = casterToken.properties
            local squadsByType = caster:GetSummonedSquadsByType(squadCtx.monsterType)
            local allSquads = caster:GetSummonedSquadsByType(nil)
            local liveEntries = caster:GetLiveSummonedEntries()

            local baselineMinionCount = #liveEntries
            local baselineSquadCount = 0
            for _ in pairs(allSquads) do baselineSquadCount = baselineSquadCount + 1 end

            local totalPlacedSoFar = 0
            for _,c in pairs(squadCtx.placedBySquad) do totalPlacedSoFar = totalPlacedSoFar + c end
            local newSquadsOpenedSoFar = 0
            for _ in pairs(squadCtx.newSquadsOpened) do newSquadsOpenedSoFar = newSquadsOpenedSoFar + 1 end

            local projectedMinionsAfterThis = baselineMinionCount + totalPlacedSoFar + 1
            local exceedsMinionCap = (squadCtx.maxMinions > 0 and projectedMinionsAfterThis > squadCtx.maxMinions)

            local sameTypeNames = {}
            local sameTypeBaselineCount = {}
            for name,info in pairs(squadsByType) do
                sameTypeNames[#sameTypeNames+1] = name
                sameTypeBaselineCount[name] = info.count
            end
            for name,_ in pairs(squadCtx.newSquadsOpened) do
                if squadsByType[name] == nil and squadCtx.newSquadsType[name] == squadCtx.monsterType then
                    sameTypeNames[#sameTypeNames+1] = name
                    sameTypeBaselineCount[name] = 0
                end
            end
            table.sort(sameTypeNames)

            if squadCtx.nextFreshName == nil then
                squadCtx.nextFreshName = monster.FindFreshSquadName(squadCtx.monsterType)
            end
            local newSquadName = squadCtx.nextFreshName

            local hasExistingSameTypeNow = #sameTypeNames > 0

            local optionPanels = {}
            local sameTypePanelByName = {}

            for _,name in ipairs(sameTypeNames) do
                local placedHere = squadCtx.placedBySquad[name] or 0
                local currentCount = sameTypeBaselineCount[name] + placedHere
                local projectedSquad = currentCount + 1
                local capturedName = name
                local warnLines = {}
                if projectedSquad > SQUAD_CAP then
                    warnLines[#warnLines+1] = string.format("Squad would have %d minions, exceeding the cap of %d.", projectedSquad, SQUAD_CAP)
                end
                if exceedsMinionCap then
                    warnLines[#warnLines+1] = string.format("Total minions would be %d, exceeding your maximum of %d.", projectedMinionsAfterThis, squadCtx.maxMinions)
                end
                local warnText = table.concat(warnLines, "\n")
                local warn = warnText ~= ""
                local rowArgs = {
                    classes = {"advantage-element", cond(warn, "summon-squad-warn")},
                    text = string.format("%s (%d/%d)", name, currentCount, SQUAD_CAP),
                    press = function(element)
                        squadCtx.selectedSquadName = capturedName
                        squadCtx.selectedIsNew = false
                        for _,p in ipairs(optionPanels) do p:SetClass("selected", false) end
                        element:SetClass("selected", true)
                    end,
                }
                if warn then
                    rowArgs.hover = function(element)
                        gui.Tooltip{ text = warnText, color = "#ff6666", textAlignment = "center" }(element)
                    end
                end
                local panel = gui.Label(rowArgs)
                optionPanels[#optionPanels+1] = panel
                sameTypePanelByName[name] = panel
            end

            local newWarnLines = {}
            if hasExistingSameTypeNow and squadCtx.maxSquads > 0 and (baselineSquadCount + newSquadsOpenedSoFar + 1) > squadCtx.maxSquads then
                newWarnLines[#newWarnLines+1] = string.format("Opening this squad would put you at %d squads, exceeding your maximum of %d.", baselineSquadCount + newSquadsOpenedSoFar + 1, squadCtx.maxSquads)
            end
            if exceedsMinionCap then
                newWarnLines[#newWarnLines+1] = string.format("Total minions would be %d, exceeding your maximum of %d.", projectedMinionsAfterThis, squadCtx.maxMinions)
            end
            local newWarnText = table.concat(newWarnLines, "\n")
            local newWarn = newWarnText ~= ""
            local newRowArgs = {
                classes = {"advantage-element", cond(newWarn, "summon-squad-warn")},
                text = "+ New squad",
                press = function(element)
                    squadCtx.selectedSquadName = newSquadName
                    squadCtx.selectedIsNew = true
                    for _,p in ipairs(optionPanels) do p:SetClass("selected", false) end
                    element:SetClass("selected", true)
                end,
            }
            if newWarn then
                newRowArgs.hover = function(element)
                    gui.Tooltip{ text = newWarnText, color = "#ff6666", textAlignment = "center" }(element)
                end
            else
                local capturedName = newSquadName
                newRowArgs.hover = function(element)
                    gui.Tooltip(string.format("Open a new squad: %s", capturedName))(element)
                end
            end
            local newPanel = gui.Label(newRowArgs)
            optionPanels[#optionPanels+1] = newPanel

            -- Reconcile carried-over selection: a previous "+ New" pick may now be an existing
            -- same-type chip; or the previously-selected name may not exist for this monster type.
            if squadCtx.selectedSquadName ~= nil and squadCtx.selectedIsNew then
                if sameTypePanelByName[squadCtx.selectedSquadName] ~= nil then
                    squadCtx.selectedIsNew = false
                elseif squadCtx.selectedSquadName ~= newSquadName then
                    squadCtx.selectedSquadName = nil
                    squadCtx.selectedIsNew = false
                end
            end
            if squadCtx.selectedSquadName ~= nil and not squadCtx.selectedIsNew and sameTypePanelByName[squadCtx.selectedSquadName] == nil then
                squadCtx.selectedSquadName = nil
            end

            if squadCtx.selectedSquadName == nil then
                if #sameTypeNames > 0 then
                    squadCtx.selectedSquadName = sameTypeNames[1]
                    squadCtx.selectedIsNew = false
                else
                    squadCtx.selectedSquadName = newSquadName
                    squadCtx.selectedIsNew = true
                end
            end

            if squadCtx.selectedIsNew then
                newPanel:SetClass("selected", true)
            elseif sameTypePanelByName[squadCtx.selectedSquadName] ~= nil then
                sameTypePanelByName[squadCtx.selectedSquadName]:SetClass("selected", true)
            end

            local minionPart
            if squadCtx.maxMinions > 0 then
                minionPart = string.format("Minions: %d -> %d / %d", baselineMinionCount + totalPlacedSoFar, projectedMinionsAfterThis, squadCtx.maxMinions)
            else
                minionPart = string.format("Minions: %d -> %d", baselineMinionCount + totalPlacedSoFar, projectedMinionsAfterThis)
            end
            local squadPart
            if squadCtx.maxSquads > 0 then
                squadPart = string.format("Squads: %d / %d", baselineSquadCount + newSquadsOpenedSoFar, squadCtx.maxSquads)
            else
                squadPart = string.format("Squads: %d", baselineSquadCount + newSquadsOpenedSoFar)
            end
            local statusText = string.format("%s    %s", minionPart, squadPart)

            commitWithSquadSelection = function()
                if squadCtx.selectedSquadName == nil then
                    return nil
                end
                local exceededMinions = exceedsMinionCap
                local exceededSquads = squadCtx.selectedIsNew and hasExistingSameTypeNow and squadCtx.maxSquads > 0 and (baselineSquadCount + newSquadsOpenedSoFar + 1) > squadCtx.maxSquads
                return {
                    squadName = squadCtx.selectedSquadName,
                    isNew = squadCtx.selectedIsNew,
                    exceededMinions = exceededMinions,
                    exceededSquads = exceededSquads,
                }
            end

            return optionPanels, statusText
        end

        local function ApplyCreatureChange()
            SyncMonsterTypeFromCreatureCtx()
            local optionPanels, statusText = BuildSquadView()
            if squadBarPanel ~= nil and squadBarPanel.valid then
                squadBarPanel.children = optionPanels
            end
            if statusLabel ~= nil and statusLabel.valid then
                statusLabel.text = statusText
            end
            if headerLabel ~= nil and headerLabel.valid then
                headerLabel.text = string.format("Place %s %d of %d", CurrentCreatureName(), index, total)
            end
        end

        SyncMonsterTypeFromCreatureCtx()
        local initialOptionPanels, initialStatusText = BuildSquadView()

        local creatureBarPanel = nil
        if creatureCtx ~= nil and #creatureCtx.choices > 1 then
            local creatureChips = {}
            for _,opt in ipairs(creatureCtx.choices) do
                local capturedOpt = opt
                local optName = opt.properties.monster_type or "creature"
                local hoverText = nil
                if opt.properties.PrettyCR ~= nil then
                    hoverText = string.format("Level %s", opt.properties:PrettyCR())
                end
                local chipArgs = {
                    classes = {"advantage-element", cond(creatureCtx.selectedCreature == opt, "selected")},
                    text = optName,
                    press = function(element)
                        if creatureCtx.selectedCreature == capturedOpt then
                            return
                        end
                        creatureCtx.selectedCreature = capturedOpt
                        for _,c in ipairs(creatureChips) do c:SetClass("selected", false) end
                        element:SetClass("selected", true)
                        ApplyCreatureChange()
                    end,
                }
                if hoverText ~= nil then
                    chipArgs.hover = function(element)
                        gui.Tooltip(hoverText)(element)
                    end
                end
                creatureChips[#creatureChips+1] = gui.Label(chipArgs)
            end
            creatureBarPanel = gui.Panel{
                classes = {"advantage-bar"},
                width = "auto",
                maxWidth = 760,
                height = "auto",
                halign = "center",
                flow = "horizontal",
                wrap = true,
                bgcolor = "clear",
                vmargin = 4,
                children = creatureChips,
            }
        end

        headerLabel = gui.Label{
            halign = "center",
            width = "auto",
            height = "auto",
            bold = true,
            fontSize = 16,
            textAlignment = "center",
            text = string.format("Place %s %d of %d", CurrentCreatureName(), index, total),
            vmargin = 2,
        }
        statusLabel = gui.Label{
            halign = "center",
            width = "auto",
            height = "auto",
            fontSize = 13,
            color = "#cccccc",
            textAlignment = "center",
            text = initialStatusText,
            vmargin = 2,
        }
        squadBarPanel = gui.Panel{
            classes = {"advantage-bar"},
            width = "auto",
            maxWidth = 760,
            height = "auto",
            halign = "center",
            flow = "horizontal",
            wrap = true,
            bgcolor = "clear",
            vmargin = 6,
            children = initialOptionPanels,
        }

        local pickerChildren = { headerLabel, statusLabel }
        if creatureBarPanel ~= nil then
            pickerChildren[#pickerChildren+1] = creatureBarPanel
        end
        pickerChildren[#pickerChildren+1] = squadBarPanel
        pickerChildren[#pickerChildren+1] = gui.Label{
            halign = "center",
            width = "auto",
            height = "auto",
            fontSize = 10,
            color = "#888888",
            textAlignment = "center",
            text = "Esc to cancel",
            vmargin = 2,
        }

        pickerContent = gui.Panel{
            width = "auto",
            height = "auto",
            flow = "vertical",
            halign = "center",
            valign = "center",
            interactable = true,
            styles = {
                Styles.AdvantageBar,
                {
                    selectors = {"advantage-element"},
                    width = "auto",
                    minWidth = 120,
                    maxWidth = 220,
                    height = 26,
                    fontSize = 14,
                    hpad = 12,
                    margin = 3,
                },
                {
                    selectors = {"advantage-element","summon-squad-warn"},
                    color = "#ffaa66",
                },
                {
                    selectors = {"advantage-element","summon-squad-warn","hover","~selected"},
                    bgcolor = "#ffaa6644",
                },
                {
                    selectors = {"advantage-element","summon-squad-warn","press"},
                    bgcolor = "#ffaa66",
                    color = "black",
                },
            },
            children = pickerChildren,
        }
    end

    local picker
    picker = gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        halign = "left",
        valign = "top",
        bgcolor = "clear",
        interactable = true,
        mapfocus = true,
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_DIALOG,

        gui.TooltipFrame(pickerContent, { vmargin = 85 }),

        mappress = function(element, loc, point)
            if not isInRange(loc) then
                return
            end
            if commitWithSquadSelection ~= nil then
                local r = commitWithSquadSelection()
                if r == nil then
                    return
                end
                pickedSquadResult = r
            end
            if creatureCtx ~= nil then
                pickedCreature = creatureCtx.selectedCreature
            end
            pickedLoc = loc
        end,

        maphover = function(element, loc, point)
            destroyHoverMarker()
            if loc == nil then
                return
            end
            hoverMarker = dmhub.MarkLocs{
                locs = { loc },
                color = isInRange(loc) and "#ffffffcc" or "#cc2222cc",
            }
        end,

        escape = function(element)
            cancelled = true
        end,

        destroy = function(element)
            destroyHoverMarker()
            if rangeMarker ~= nil then
                rangeMarker:Destroy()
                rangeMarker = nil
            end
        end,
    }

    gamehud.popupPanel:AddChild(picker)

    while pickedLoc == nil and not cancelled do
        coroutine.yield(0.1)
    end

    picker:DestroySelf()

    if cancelled then
        return nil, nil, nil
    end
    return pickedLoc, pickedSquadResult, pickedCreature
end

function ActivatedAbilitySummonBehavior:Cast(ability, casterToken, targets, args)
    if self.duplicateMode then
        self:CastDuplicate(ability, casterToken, targets, args)
        return
    end

    for _,target in ipairs(targets) do
        local newOwner = ""
        if self.casterControls then
            newOwner = casterToken.ownerId
        end

        --build the candidate creature list first, before rolling numSummons or
        --asking for placement, so we can expose the chosen creature as a symbol
        local choices = {}
        if self.monsterType == "custom" then
            for k,monster in pairs(assets.monsters) do
                if not assets:GetMonsterNode(k).hidden then
                    args.symbols.beast = GenerateSymbols(monster.properties)
                    if monster.properties:has_key("monster_type") and ExecuteGoblinScript(self.bestiaryFilter, GenerateSymbols(casterToken.properties, args.symbols), 0, string.format("Bestiary filter for %s summons filter %s", ability.name, monster.properties.monster_type)) ~= 0 then
                        choices[#choices+1] = monster
                    end
                end
            end
        else
            local monster = assets.monsters[self.monsterType]
            if monster ~= nil then
                choices[#choices+1] = monster
            end
        end

        args.symbols.beast = nil

        dmhub.Debug(string.format("SUMMON:: CHOICES: %d", #choices))
        if #choices == 0 then
            return
        end

        table.sort(choices, function(a,b) return a.properties.monster_type < b.properties.monster_type end)

        local preCheckSummonerMaxMinions = casterToken.properties:CalculateNamedCustomAttribute("MaximumMinions")
        local preCheckSummonerMaxSquads = casterToken.properties:CalculateNamedCustomAttribute("MaxMinionSquads")
        local preCheckIsSummoner = (not casterToken.properties.minion) and (preCheckSummonerMaxMinions > 0 or preCheckSummonerMaxSquads > 0)
        local willPickCreatureInline = preCheckIsSummoner and self.casterChoosesCreatures and self.choosePlacement and (not self.replaceCaster) and #choices > 1

        --pre-pick the chosen creature so its symbols are available to numSummons
        --and to subsequent behaviors
        local chosenOption
        if #choices == 1 then
            chosenOption = choices[1]
        elseif willPickCreatureInline then
            --skip the upfront modal; the player will pick each creature inline during placement.
            --use the first sorted choice as a default so symbols and numSummons can resolve.
            chosenOption = choices[1]
        elseif self.casterChoosesCreatures then
            local dialogOptions = { index = 1, numSummons = 1, allCreaturesTheSame = self.allCreaturesTheSame }
            chosenOption = ActivatedAbilitySummonBehavior.ShowCreatureChoiceDialog(choices, dialogOptions)
            if chosenOption == nil then
                return
            end
        else
            chosenOption = choices[math.random(#choices)]
        end

        --expose the chosen creature on the shared symbol table so numSummons
        --and subsequent behaviors can reference Summon.<attribute>.
        args.symbols.summon = GenerateSymbols(chosenOption.properties)

        local finishedRoll = false
        local numSummons = nil

        gamehud.rollDialog.data.ShowDialog{
            title = 'Roll for Number of Summons',
            description = string.format("%s Summons", ability.name),
            roll = dmhub.EvalGoblinScript(self.numSummons, GenerateSymbols(casterToken.properties, args.symbols), 0, string.format("Summons number of creatures for %s", ability.name)),
            creature = casterToken.properties,
            skipDeterministic = true,
            type = 'numSummons',
            cancelRoll = function()
                finishedRoll = true
            end,
            completeRoll = function(rollInfo)
                finishedRoll = true
                numSummons = rollInfo.total
            end
        }

        while not finishedRoll do
            coroutine.yield(0.1)
        end

        dmhub.Debug(string.format("SUMMON:: %s", json(numSummons)))
        if numSummons == nil or numSummons <= 0 then
            return
        end

        local manualPlacement = self.choosePlacement and (not self.replaceCaster)
        local rangeTiles = 0
        if manualPlacement then
            rangeTiles = dmhub.EvalGoblinScript(self.summonRange, GenerateSymbols(casterToken.properties, args.symbols), 0, string.format("Summon placement range for %s", ability.name)) or 0
            rangeTiles = math.max(0, math.floor(rangeTiles))
            if rangeTiles <= 0 then
                manualPlacement = false
            end
        end

        local summonedTokens = {}
        local summonerEntries = {}

        local summonerMaxMinions = casterToken.properties:CalculateNamedCustomAttribute("MaximumMinions")
        local summonerMaxSquads = casterToken.properties:CalculateNamedCustomAttribute("MaxMinionSquads")
        local isSummoner = (not casterToken.properties.minion) and (summonerMaxMinions > 0 or summonerMaxSquads > 0)
        local cachedSquadResult = nil
        local placementSquadCtx = nil
        local placementCreatureCtx = nil
        local warningExceededMinions = false
        local warningExceededSquads = false

        -- For Summoner casters with manual placement, fold the creature-type choice
        -- into the inline placement picker so it can change per-summon.
        local creatureChoiceInline = isSummoner and manualPlacement and self.casterChoosesCreatures and #choices > 1

        local allSame = false

        local initiativeGrouping = nil
        if self.groupInitiativeWithCaster then
            initiativeGrouping = InitiativeQueue.GetInitiativeId(casterToken)
        end

        for j=1,numSummons do

            if j == 1 then
                --use the pre-picked chosenOption from before the numSummons roll.

            elseif self.allCreaturesTheSame or allSame then
                --all creatures are the same so just maintain the chosen option.

            elseif creatureChoiceInline then
                --creature is picked inside the inline placement picker below.

            elseif #choices > 1 and not self.casterChoosesCreatures then
                chosenOption = choices[math.random(#choices)]

            elseif #choices > 1 and self.casterChoosesCreatures then
                local dialogOptions = { index = j, numSummons = numSummons, allCreaturesTheSame = self.allCreaturesTheSame }
                chosenOption = ActivatedAbilitySummonBehavior.ShowCreatureChoiceDialog(choices, dialogOptions)
                if chosenOption == nil then
                    return
                end

                if dialogOptions.allSame then
                    allSame = true
                end
            end

            local squadNameForSpawn = nil

            local loc
            if self.replaceCaster then
                if isSummoner then
                    local squadResult
                    if cachedSquadResult ~= nil then
                        squadResult = cachedSquadResult
                    else
                        local shared = self.allCreaturesTheSame or allSame
                        local dialogCount = shared and numSummons or 1
                        squadResult = ActivatedAbilitySummonBehavior.ShowSquadChoiceDialog(casterToken, chosenOption.properties.monster_type, dialogCount, summonerMaxMinions, summonerMaxSquads)
                        if squadResult == nil then
                            return
                        end
                        if shared then
                            cachedSquadResult = squadResult
                        end
                        if squadResult.exceededMinions then warningExceededMinions = true end
                        if squadResult.exceededSquads then warningExceededSquads = true end
                    end
                    squadNameForSpawn = squadResult.squadName
                end
                loc = casterToken.loc
            elseif manualPlacement then
                local squadCtxArg = nil
                if isSummoner then
                    if placementSquadCtx == nil then
                        placementSquadCtx = {
                            maxMinions = summonerMaxMinions,
                            maxSquads = summonerMaxSquads,
                            selectedSquadName = nil,
                            selectedIsNew = false,
                            placedBySquad = {},
                            newSquadsOpened = {},
                            newSquadsType = {},
                            nextFreshName = nil,
                        }
                    end
                    placementSquadCtx.monsterType = chosenOption.properties.monster_type
                    squadCtxArg = placementSquadCtx
                end
                local creatureCtxArg = nil
                if creatureChoiceInline then
                    if placementCreatureCtx == nil then
                        placementCreatureCtx = {
                            choices = choices,
                            selectedCreature = chosenOption,
                        }
                    end
                    creatureCtxArg = placementCreatureCtx
                end
                local isMinion = chosenOption ~= nil and chosenOption.properties ~= nil and chosenOption.properties:try_get("minion", false)
                local pickedLoc, squadResult, pickedCreature = ActivatedAbilitySummonBehavior.PromptPlacementLoc(casterToken, rangeTiles, j, numSummons, isMinion, squadCtxArg, creatureCtxArg)
                if pickedLoc == nil then
                    --user cancelled; stop placing further summons but keep what's already there.
                    break
                end
                loc = pickedLoc
                if pickedCreature ~= nil then
                    chosenOption = pickedCreature
                    args.symbols.summon = GenerateSymbols(chosenOption.properties)
                end
                if squadResult ~= nil then
                    squadNameForSpawn = squadResult.squadName
                    if squadResult.exceededMinions then warningExceededMinions = true end
                    if squadResult.exceededSquads then warningExceededSquads = true end
                    placementSquadCtx.placedBySquad[squadResult.squadName] = (placementSquadCtx.placedBySquad[squadResult.squadName] or 0) + 1
                    if squadResult.isNew and not placementSquadCtx.newSquadsOpened[squadResult.squadName] then
                        placementSquadCtx.newSquadsOpened[squadResult.squadName] = true
                        placementSquadCtx.newSquadsType[squadResult.squadName] = placementSquadCtx.monsterType
                        placementSquadCtx.nextFreshName = nil
                    end
                end
            else
                if isSummoner then
                    local squadResult
                    if cachedSquadResult ~= nil then
                        squadResult = cachedSquadResult
                    else
                        local shared = self.allCreaturesTheSame or allSame
                        local dialogCount = shared and numSummons or 1
                        squadResult = ActivatedAbilitySummonBehavior.ShowSquadChoiceDialog(casterToken, chosenOption.properties.monster_type, dialogCount, summonerMaxMinions, summonerMaxSquads)
                        if squadResult == nil then
                            return
                        end
                        if shared then
                            cachedSquadResult = squadResult
                        end
                        if squadResult.exceededMinions then warningExceededMinions = true end
                        if squadResult.exceededSquads then warningExceededSquads = true end
                    end
                    squadNameForSpawn = squadResult.squadName
                end
                loc = target.loc
            end

            local token = game.SpawnTokenFromBestiaryLocally(chosenOption.id, loc.withGroundAltitude, {
                fitLocation = not self.replaceCaster,
            })
            token.ownerId = newOwner

            token.summonerid = casterToken.charid

            if self.shareSurgesWithSummoner then
                token.properties.sharesSurgesWithSummoner = true
            end

            if self.shareHeroicResourceWithSummoner then
                token.properties.sharesHeroicResourceWithSummoner = true
            end

            if squadNameForSpawn ~= nil then
                token.properties.minionSquad = squadNameForSpawn
                summonerEntries[#summonerEntries+1] = {
                    charid = token.charid,
                    squad = squadNameForSpawn,
                    monsterType = chosenOption.properties.monster_type,
                }
            end

            if initiativeGrouping ~= nil then
                token.properties.initiativeGrouping = initiativeGrouping
            end

            local notes = token.properties:get_or_add("notes", {})
            notes[#notes+1] = {
                title = "Summoned",
                text = string.format("Summoned by %s", casterToken.description),
            }

            summonedTokens[#summonedTokens+1] = token

            if self.casterControls then
                --if the caster controls the summoned tokens then they mimic its appearance.
                local summonerHasFrame = casterToken.portraitFrame ~= nil and casterToken.portraitFrame ~= ""
                local tokenHasFrame = token.portraitFrame ~= nil and token.portraitFrame ~= ""

                if summonerHasFrame == tokenHasFrame then
                    token.portraitFrame = casterToken.portraitFrame
                    token.portraitFrameHueShift = casterToken.portraitFrameHueShift
                end

                --if the caster controls the summoned tokens then they inherit the caster's party.
                token.partyid = casterToken.partyid
            end

            token:UploadToken("Summon Creature")
            game.UpdateCharacterTokens()

            --assign the token to the target so we can refer to it in subsequent behaviors.
            local tok = dmhub.GetTokenById(token.charid)
            target.token = tok
            print("TOKEN:: ASSIGN", tok)
        end

        if #summonedTokens > 0 then
            if ability:RequiresConcentration() and casterToken.properties:HasConcentration() then
                casterToken:ModifyProperties{
                    description = "Concentrate on summons",
                    execute = function()
                        local concentration = casterToken.properties:MostRecentConcentration()
                        local summonid = concentration:get_or_add("summonid", {})
                        for _,token in ipairs(summonedTokens) do
                            summonid[#summonid+1] = token.charid
                        end
                    end,
                }
            end

            if isSummoner and #summonerEntries > 0 then
                casterToken:ModifyProperties{
                    description = "Register summons",
                    execute = function()
                        for _,entry in ipairs(summonerEntries) do
                            casterToken.properties:RegisterSummonedMinion(entry.charid, entry.squad, entry.monsterType)
                        end
                    end,
                }
            end

            if warningExceededMinions then
                chat.Send(string.format("%s exceeded their MaximumMinions limit of %d.", casterToken.description, summonerMaxMinions))
            end
            if warningExceededSquads then
                chat.Send(string.format("%s exceeded their MaxMinionSquads limit of %d.", casterToken.description, summonerMaxSquads))
            end

            dmhub.Debug(string.format("SUMMON:: DONE"))
            game.UpdateCharacterTokens()

            --we summoned, so consume resources.
            ability:CommitToPaying(casterToken, args)
        end
    end
end

function ActivatedAbilitySummonBehavior:EditorItems(parentPanel)
	local result = {}

	result[#result+1] = gui.Check{
		text = "Duplicate Mode",
		value = self.duplicateMode,
		minWidth = 300,
		change = function(element)
			self.duplicateMode = element.value
			parentPanel:FireEvent("refreshBehavior")
		end,
	}

	if self.duplicateMode then
		self:ApplyToEditor(parentPanel, result)
		self:FilterEditor(parentPanel, result)

		result[#result+1] = gui.Check{
			text = "Copy Stamina",
			value = self.copyStamina,
			minWidth = 300,
			change = function(element)
				self.copyStamina = element.value
			end,
		}

		result[#result+1] = gui.Check{
			text = "Copy Effects",
			value = self.copyEffects,
			minWidth = 300,
			change = function(element)
				self.copyEffects = element.value
			end,
		}

		result[#result+1] = gui.Check{
			text = "Copy Conditions",
			value = self.copyConditions,
			minWidth = 300,
			change = function(element)
				self.copyConditions = element.value
			end,
		}

		result[#result+1] = gui.Check{
			text = "Copy Features",
			value = self.copyFeatures,
			minWidth = 300,
			change = function(element)
				self.copyFeatures = element.value
			end,
		}

		result[#result+1] = gui.Check{
			text = "Copy Resistances",
			value = self.copyResistances,
			minWidth = 300,
			change = function(element)
				self.copyResistances = element.value
			end,
		}

		result[#result+1] = gui.Check{
			text = "Copy Abilities",
			value = self.copyAbilities,
			minWidth = 300,
			change = function(element)
				self.copyAbilities = element.value
			end,
		}

		result[#result+1] = gui.Check{
			text = "Copy Triggers",
			value = self.copyTriggers,
			minWidth = 300,
			change = function(element)
				self.copyTriggers = element.value
			end,
		}

		result[#result+1] = gui.Panel{
			classes = "formPanel",
			gui.Label{
				classes = "formLabel",
				text = "Targeting Origin:",
			},
			gui.Dropdown{
				classes = {"formDropdown"},
				options = {
					{id = "duplicate", text = "Duplicate Token"},
					{id = "source", text = "Source Token"},
					{id = "both", text = "Both"},
				},
				idChosen = self.duplicateTargetOrigin,
				change = function(element)
					self.duplicateTargetOrigin = element.idChosen
				end,
			},
		}

		result[#result+1] = gui.Check{
			text = "Caster controls duplicate",
			minWidth = 300,
			value = self.casterControls,
			change = function(element)
				self.casterControls = element.value
			end,
		}

		result[#result+1] = gui.Check{
			text = "Group with caster",
			minWidth = 300,
			value = self.groupInitiativeWithCaster,
			change = function(element)
				self.groupInitiativeWithCaster = element.value
			end,
		}
	else
		self:SummonEditor(parentPanel, result, {numSummons = true, casterControls = true})
	end

	return result
end

-- @options: { haveTargetCreature = bool? }
function ActivatedAbilityBehavior:SummonEditor(parentPanel, list, options)

	options = options or {}

	if options.numSummons then
		local numSummonsHelpSymbols = DeepCopy(ActivatedAbility.helpCasting)
		numSummonsHelpSymbols.summon = {
			name = "Summon",
			type = "creature",
			desc = "The creature being summoned. Resolved from the player's selection (or random pick) before this script runs, so its custom attributes (e.g. Summon.SummonNum, Summon.SummonCost) are available here.",
			examples = {"Summon.SummonNum", "Summon.SummonCost + 1"},
		}

		list[#list+1] = gui.Panel{
			classes = "formPanel",
			gui.Label{
				classes = "formLabel",
				text = "Num. Summons:",
			},
			gui.GoblinScriptInput{
				value = self.numSummons,
				change = function(element)
					self.numSummons = element.value
				end,

				documentation = {
					domains = parentPanel.data.parentAbility.domains,
					help = string.format("This GoblinScript is used to determine the number of creatures that can be summoned with this ability."),
					output = "number",
					examples = {
						{
							script = "1",
							text = "1 creature will be summoned. Using a simple number is a common use of this script.",
						},
						{
							script = "3 + upcast",
							text = "3 creatures will be summoned with an additional creature for every level the spell slot used for this spell is above the spell's level.",
						},
						{
							script = "Summon.SummonNum",
							text = "Number of summons is read from the chosen creature's 'Summon Num' custom attribute. Useful for Heroic summons where each stat block defines its own party size.",
						},
					},
					subject = creature.helpSymbols,
					subjectDescription = "The creature using the ability",
					symbols = numSummonsHelpSymbols,
				},

			},
		}

		list[#list+1] = gui.Check{
			text = "Choose placement for each creature",
			value = self.choosePlacement,
			minWidth = 300,
			change = function(element)
				self.choosePlacement = element.value
				element.parent:FireEventTree("refreshChoosePlacement")
			end,
		}

		list[#list+1] = gui.Panel{
			classes = {"formPanel", cond(not self.choosePlacement, "hidden")},
			refreshChoosePlacement = function(element)
				element:SetClass("hidden", not self.choosePlacement)
			end,
			gui.Label{
				classes = "formLabel",
				text = "Range:",
			},
			gui.GoblinScriptInput{
				value = self.summonRange,
				change = function(element)
					self.summonRange = element.value
				end,

				documentation = {
					domains = parentPanel.data.parentAbility.domains,
					help = string.format("This GoblinScript is used to determine the maximum distance, in squares, from the caster within which the player may place each summoned creature."),
					output = "number",
					examples = {
						{
							script = "3",
							text = "The player chooses placement for each creature within 3 squares of the caster.",
						},
						{
							script = "1 + Charges",
							text = "The play can place 1 creature + the number of channeled resources used.",
						},
					},
					subject = creature.helpSymbols,
					subjectDescription = "The creature using the ability",
					symbols = ActivatedAbility.helpCasting,
				},
			},
		}
	end

    local monsterOptions = {}
    for k,monster in pairs(assets.monsters) do
        if not assets:GetMonsterNode(k).hidden then
			if monster and monster.properties and monster.properties:try_get("monster_type") ~= nil then
				monsterOptions[#monsterOptions+1] = {
					id = k,
					text = monster.properties.monster_type,
				}
			end
        end
    end

    table.sort(monsterOptions, function(a,b) return a.text < b.text end)
    table.insert(monsterOptions, 1, {id = "custom", text = "Custom Filter"})

    list[#list+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Monster Type",
        },
        gui.Dropdown{
            classes = {"formDropdown"},
            options = monsterOptions,
            idChosen = self.monsterType,
            hasSearch = true,
            change = function(element)
                self.monsterType = element.idChosen
                element.parent.parent:FireEventTree("refreshMonsterType")
            end,
        }
    }

	local bestiaryFilterHelpSymbols = DeepCopy(ActivatedAbility.helpCasting)
	bestiaryFilterHelpSymbols[#bestiaryFilterHelpSymbols+1] = {
		name = "Beast",
		type = "creature",
		desc = "This is the monster from the Bestiary that is being examined to see if it is possible to use with this ability.",
		examples = {"Beast.CR <= 1"},
	}

	if options.haveTargetCreature then
		bestiaryFilterHelpSymbols[#bestiaryFilterHelpSymbols+1] = {
			name = "Target",
			type = "creature",
			desc = "The target creature that we are transforming.",
			examples = {"Beast.CR <= Target.CR"},
		}
	end

	list[#list+1] = gui.Panel{
		classes = {"formPanel", cond(self.monsterType ~= "custom", "hidden")},
        refreshMonsterType = function(element)
            if self.monsterType == "custom" then
                element:SetClass("hidden", false)
            else
                element:SetClass("hidden", true)
            end
        end,
		gui.Label{
			classes = "formLabel",
			text = "Bestiary Filter",
		},
		gui.GoblinScriptInput{
			value = self.bestiaryFilter,
			change = function(element)
				self.bestiaryFilter = element.value
			end,

			documentation = {
				domains = parentPanel.data.parentAbility.domains,
				help = string.format("This GoblinScript is used to determine which creatures from the Bestiary can be summoned using this ability. The GoblinScript will be used once for every creature found in the bestiary. If the result is <b>true</b>, then that creature will be included in the list of creatures that can be summoned with this ability. If the result is <b>false</b>, then that creature will not be included."),
				output = "boolean",
				examples = {
					{
						script = "Beast.CR <= 1 and Beast.Type is Fey",
						text = "Creatures with a challenge rating less than or equal to 1 that are Fey can be summoned with this ability.",
					},
					{
						script = "((Beast.CR = 1/2 and mode = 1) or\n(Beast.CR = 1 and mode = 2) or\n(Beast.CR = 2 and mode = 3))\nand Beast.Type is Beast",
						text = "Creatures are included in the list depending upon the mode that the player is choosing to use for this ability. You could use this in conjuction with the Number of Summons field being dependent upon the mode to make an ability where the player could, for instance, summon 8 CR 1/2 creatures, 4 CR 1 creatures, or 2 CR 2 creatures.",
					},
				},
				subject = creature.helpSymbols,
				subjectDescription = "The creature casting the ability is the main subject. The beast that is being considered is found as an additional field, Beast.",
				symbols = bestiaryFilterHelpSymbols,
			},

		},
	}

    if self.hasReplaceCaster then
        list[#list+1] = gui.Check{
            text = "Replace Caster",
            value = self.replaceCaster,
            minWidth = 300,
            change = function(element)
                self.replaceCaster = element.value
            end,
        }
    end

	list[#list+1] = gui.Check{
		text = "Caster Chooses Creature Types",
		value = self.casterChoosesCreatures,
        minWidth = 300,
		change = function(element)
			self.casterChoosesCreatures = element.value
		end,
	}

	list[#list+1] = gui.Check{
		text = "All creatures the same",
		value = self.allCreaturesTheSame,
        minWidth = 300,
		change = function(element)
			self.allCreaturesTheSame = element.value
		end,
	}

	if options.casterControls then
		list[#list+1] = gui.Check{
			text = "Caster controls summons",
            minWidth = 300,
			value = self.casterControls,
			change = function(element)
				self.casterControls = element.value
			end,
		}

        list[#list+1] = gui.Check{
            text = "Group with caster",
            minWidth = 300,
            value = self.groupInitiativeWithCaster,
            change = function(element)
                self.groupInitiativeWithCaster = element.value
            end,
        }
	end

    list[#list+1] = gui.Check{
        text = "Summons Share Surges",
        minWidth = 300,
        value = self.shareSurgesWithSummoner,
        change = function(element)
            self.shareSurgesWithSummoner = element.value
        end,
    }

    list[#list+1] = gui.Check{
        text = "Summons Share Heroic Resource",
        minWidth = 300,
        value = self.shareHeroicResourceWithSummoner,
        change = function(element)
            self.shareHeroicResourceWithSummoner = element.value
        end,
    }

end

local mod = dmhub.GetModLoading()

--this implements the "transform" behavior for activated abilities.

--- @class ActivatedAbilityTransformBehavior:ActivatedAbilityBehavior
--- @field summary string Short label shown in behavior lists.
--- @field allCreaturesTheSame boolean If true, all targets transform into the same creature.
--- @field monsterType string Source for the transform target: "custom" or a monster category filter.
--- @field bestiaryFilter string GoblinScript filter used to select eligible transformation targets.
--- @field casterChoosesCreatures boolean If true, the caster picks the creature form.
--- @field replaceCaster boolean If true, the caster is replaced by the transformed creature.
--- @field hasReplaceCaster boolean Internal: controls whether "replace caster" option is shown in the editor.
ActivatedAbilityTransformBehavior = RegisterGameType("ActivatedAbilityTransformBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
	id = 'transform',
	text = 'Transform Creatures',
	createBehavior = function()
		return ActivatedAbilityTransformBehavior.new{
		}
	end
}

ActivatedAbilityTransformBehavior.summary = "Transform Creature"
ActivatedAbilityTransformBehavior.allCreaturesTheSame = false
ActivatedAbilityTransformBehavior.monsterType = "custom"
ActivatedAbilityTransformBehavior.bestiaryFilter = "beast.cr = 1 and beast.type is beast"
ActivatedAbilityTransformBehavior.casterChoosesCreatures = true
ActivatedAbilityTransformBehavior.replaceCaster = true
ActivatedAbilityTransformBehavior.hasReplaceCaster = true --do not display 'replace caster' in menu.


function ActivatedAbilityTransformBehavior:ShowTransformChoiceDialog(choices, dialogOptions)
    dialogOptions = dialogOptions or {}
    local finished = false
    local canceled = false
    local chosenOption = nil

    -- Current sort mode: "name" or "level".
    local sortMode = "name"

    -- Pre-select the highest CR creature.
    local maxCR = 0
    for _, option in ipairs(choices) do
        local cr = option.properties:CR()
        if cr > maxCR then
            maxCR = cr
            chosenOption = option
        end
    end

    -- Sort function based on current mode.
    local function sortChoices()
        if sortMode == "level" then
            table.sort(choices, function(a, b)
                local crA = a.properties:CR()
                local crB = b.properties:CR()
                if crA ~= crB then
                    return crA > crB
                end
                return a.properties.monster_type < b.properties.monster_type
            end)
        else
            table.sort(choices, function(a, b)
                return a.properties.monster_type < b.properties.monster_type
            end)
        end
    end

    sortChoices()

    -- Reference to the chips container so we can rebuild on sort change.
    local chipsContainer = nil

    local function buildChipPanels()
        local chipPanels = {}
        for i, option in ipairs(choices) do
            local capturedOption = option
            local displayName = option.properties.monster_type
            local levelText = string.format("Level %s", option.properties:PrettyCR())

            chipPanels[#chipPanels+1] = gui.Panel{
                classes = {"transform-chip"},
                flow = "horizontal",

                press = function(element)
                    -- Single-select: clear all sibling chips first.
                    for _, sibling in ipairs(element.parent.children) do
                        sibling:SetClass("transform-chip-selected", false)
                    end
                    element:SetClass("transform-chip-selected", true)
                    chosenOption = capturedOption
                end,

                create = function(element)
                    if capturedOption == chosenOption then
                        element:SetClass("transform-chip-selected", true)
                    end
                end,

                hover = function(element)
                    local rendered = capturedOption.properties:Render({width = 480}, {asset = capturedOption})
                    if rendered ~= nil then
                        element.tooltip = gui.TooltipFrame(rendered, {width = 500, halign = "right", valign = "center", pad = 8})
                    end
                end,

                gui.Label{
                    classes = {"transform-chip-label"},
                    text = displayName,
                },
                gui.Label{
                    classes = {"transform-chip-level"},
                    text = levelText,
                },
            }
        end
        return chipPanels
    end

    local function refreshChips()
        if chipsContainer ~= nil and chipsContainer.valid then
            chipsContainer.children = buildChipPanels()
        end
    end

    -- Assemble main content.
    local mainChildren = {}

    mainChildren[#mainChildren+1] = gui.Label{
        classes = {"transform-title"},
        text = string.upper(dialogOptions.title or "Choose Transformation"),
    }

    mainChildren[#mainChildren+1] = gui.Label{
        classes = {"transform-instruction"},
        text = "Select a creature form",
    }

    -- Sort controls.
    mainChildren[#mainChildren+1] = gui.Panel{
        classes = {"transform-sort-row"},

        gui.Label{
            classes = {"transform-sort-label"},
            text = "Sort:",
        },
        gui.Panel{
            classes = {"transform-sort-chip"},
            press = function(element)
                sortMode = "name"
                element:SetClass("transform-sort-active", true)
                local levelChip = element.parent.children[3]
                if levelChip ~= nil then
                    levelChip:SetClass("transform-sort-active", false)
                end
                sortChoices()
                refreshChips()
            end,
            create = function(element)
                element:SetClass("transform-sort-active", sortMode == "name")
            end,
            gui.Label{
                classes = {"transform-sort-chip-label"},
                text = "Name",
            },
        },
        gui.Panel{
            classes = {"transform-sort-chip"},
            press = function(element)
                sortMode = "level"
                element:SetClass("transform-sort-active", true)
                local nameChip = element.parent.children[2]
                if nameChip ~= nil then
                    nameChip:SetClass("transform-sort-active", false)
                end
                sortChoices()
                refreshChips()
            end,
            create = function(element)
                element:SetClass("transform-sort-active", sortMode == "level")
            end,
            gui.Label{
                classes = {"transform-sort-chip-label"},
                text = "Level",
            },
        },
    }

    mainChildren[#mainChildren+1] = gui.Panel{ classes = {"transform-divider"} }

    local chipsWrap = gui.Panel{
        classes = {"transform-chips-wrap"},
        create = function(element)
            chipsContainer = element
        end,
        children = buildChipPanels(),
    }

    mainChildren[#mainChildren+1] = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        maxHeight = 420,
        vscroll = true,
        chipsWrap,
    }

    mainChildren[#mainChildren+1] = gui.Panel{ classes = {"transform-divider"} }

    mainChildren[#mainChildren+1] = gui.Panel{
        classes = {"transform-button-row"},
        gui.Panel{
            classes = {"transform-submit"},
            press = function(element)
                finished = true
                gui.CloseModal()
            end,
            gui.Label{
                classes = {"transform-button-label"},
                text = dialogOptions.buttonText or "Transform",
            },
        },
        gui.Panel{
            classes = {"transform-cancel"},
            escapeActivates = true,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            press = function(element)
                finished = true
                canceled = true
                gui.CloseModal()
            end,
            gui.Label{
                classes = {"transform-button-label"},
                text = "Cancel",
            },
        },
    }

    local resultPanel = gui.Panel{
        flow = "vertical",
        bgimage = "panels/square.png",
        bgcolor = "#040807",
        border = 1,
        borderColor = "#5C3D10",
        cornerRadius = 6,
        width = 480,
        height = "auto",
        pad = 12,

        styles = {
            {
                selectors = {"label", "transform-title"},
                fontFace = "Berling",
                fontSize = 18,
                color = "#5C6860",
                width = "auto",
                height = "auto",
                halign = "left",
                bmargin = 2,
            },
            {
                selectors = {"label", "transform-instruction"},
                fontFace = "Berling",
                fontSize = 12,
                color = "#C49A5A",
                width = "100%",
                height = "auto",
                halign = "left",
                bmargin = 2,
            },
            {
                selectors = {"panel", "transform-sort-row"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "left",
                valign = "center",
                tmargin = 4,
                bmargin = 2,
            },
            {
                selectors = {"label", "transform-sort-label"},
                fontFace = "Berling",
                fontSize = 12,
                color = "#5C6860",
                width = "auto",
                height = "auto",
                valign = "center",
                rmargin = 6,
            },
            {
                selectors = {"panel", "transform-sort-chip"},
                width = "auto",
                height = "auto",
                hpad = 8,
                vpad = 3,
                margin = 2,
                flow = "horizontal",
                bgimage = "panels/square.png",
                border = 1,
                borderColor = "#5C6860",
                bgcolor = "clear",
                cornerRadius = 4,
            },
            {
                selectors = {"panel", "transform-sort-chip", "hover"},
                brightness = 1.3,
                transitionTime = 0.15,
            },
            {
                selectors = {"panel", "transform-sort-chip", "transform-sort-active"},
                borderColor = "#C49A5A",
                bgcolor = "#2A1E0E",
            },
            {
                selectors = {"label", "transform-sort-chip-label"},
                fontFace = "Berling",
                fontSize = 11,
                color = "#FFFEF8",
                width = "auto",
                height = "auto",
                valign = "center",
            },
            {
                selectors = {"panel", "transform-divider"},
                width = "100%",
                height = 1,
                bgimage = "panels/square.png",
                bgcolor = "#5C3D10",
                vmargin = 8,
            },
            {
                selectors = {"panel", "transform-chips-wrap"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                wrap = true,
                bmargin = 2,
            },
            {
                selectors = {"panel", "transform-chip"},
                height = "auto",
                minHeight = 22,
                width = "auto",
                halign = "left",
                valign = "top",
                hpad = 8,
                vpad = 4,
                margin = 3,
                flow = "horizontal",
                bgimage = "panels/square.png",
                border = 1,
                borderColor = "#5C6860",
                bgcolor = "clear",
                cornerRadius = 4,
            },
            {
                selectors = {"panel", "transform-chip", "hover"},
                brightness = 1.3,
                transitionTime = 0.15,
            },
            {
                selectors = {"panel", "transform-chip", "transform-chip-selected"},
                borderColor = "#966D4B",
                bgcolor = "#5C3D10",
            },
            {
                selectors = {"label", "transform-chip-label"},
                fontFace = "Berling",
                fontSize = 13,
                color = "#FFFEF8",
                width = "auto",
                height = "auto",
                valign = "center",
                rmargin = 6,
            },
            {
                selectors = {"label", "transform-chip-level"},
                fontFace = "Berling",
                fontSize = 11,
                color = "#C49A5A",
                width = "auto",
                height = "auto",
                valign = "center",
            },
            {
                selectors = {"panel", "transform-button-row"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                tmargin = 4,
            },
            {
                selectors = {"panel", "transform-submit"},
                width = 130,
                height = 30,
                halign = "right",
                rmargin = 8,
                bgimage = "panels/square.png",
                bgcolor = "#040807",
                border = 1,
                borderColor = "#966D4B",
                cornerRadius = 4,
            },
            {
                selectors = {"panel", "transform-submit", "hover"},
                brightness = 1.25,
                transitionTime = 0.1,
            },
            {
                selectors = {"panel", "transform-cancel"},
                width = 130,
                height = 30,
                halign = "right",
                bgimage = "panels/square.png",
                bgcolor = "#040807",
                border = 1,
                borderColor = "#5C6860",
                cornerRadius = 4,
            },
            {
                selectors = {"panel", "transform-cancel", "hover"},
                brightness = 1.25,
                transitionTime = 0.1,
            },
            {
                selectors = {"label", "transform-button-label"},
                fontFace = "Berling",
                fontSize = 13,
                color = "#FFFEF8",
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
            },
        },

        children = mainChildren,
    }

    gui.ShowModal(resultPanel)

    while not finished do
        coroutine.yield(0.1)
    end

    if canceled then
        return nil
    end

    return chosenOption
end


function ActivatedAbilityTransformBehavior:Cast(ability, casterToken, targets, args)


	if self:try_get("ongoingEffect") == nil then
		printf("TRANSFORM:: NO EFFECT")
		return
	end


	local summonedTokens = {}

	local chosenOption = nil

	for j,target in ipairs(targets) do

		local choices = {}
		if self.monsterType == "custom" then
			for k,monster in pairs(assets.monsters) do
				if not assets:GetMonsterNode(k).hidden then
					args.symbols.beast = GenerateSymbols(monster.properties)
					args.symbols.target = GenerateSymbols(target.token.properties)
					if monster.properties:has_key("monster_type") and ExecuteGoblinScript(self.bestiaryFilter, GenerateSymbols(casterToken.properties, args.symbols), 0, string.format("Bestiary filter for %s transform filter %s", ability.name, monster.properties.monster_type)) ~= 0 then
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

		args.symbols.target = nil
		args.symbols.beast = nil

		printf("TRANSFORM:: %s; same: %s / targets = %s", json(#choices), json(self.allCreaturesTheSame), json(#targets))

		table.sort(choices, function(a,b) return a.properties.monster_type < b.properties.monster_type end)

		if #choices ~= 0 then

			if j ~= 1 and self.allCreaturesTheSame and chosenOption ~= nil then
				--all creatures are the same so just maintain the chosen option.
				printf("TRANSFORM:: ALL THE SAME")

			elseif #choices > 1 and not self.casterChoosesCreatures then
				printf("TRANSFORM:: RANDOM")
				chosenOption = choices[math.random(#choices)]

			elseif #choices > 1 and self.casterChoosesCreatures then
				printf("TRANSFORM:: SHOW DIALOG")
				chosenOption = self:ShowTransformChoiceDialog(choices, {title = "Choose Transformation", buttonText = "Transform"})
				if chosenOption == nil then
					return
				end
			else
				chosenOption = choices[1]
			end

			local casterInfo = {
				tokenid = casterToken.id
			}
			if ability:RequiresConcentration() and casterToken.properties:HasConcentration() then
				casterInfo.concentrationid = casterToken.properties:MostRecentConcentration().id
			end

			--Okay to always provide a monsters temporary hitpoints when transforming?
			local tempHitpoints = nil
			if chosenOption and chosenOption.properties ~= nil then
				tempHitpoints = chosenOption.properties:TemporaryHitpoints()
			end

			if target.token.properties ~= nil then
				target.token:ModifyProperties{
					description = "Transform Creature",
					execute = function()
						local newEffect = target.token.properties:ApplyOngoingEffect(self.ongoingEffect, self:try_get("duration"), casterInfo, {
							transformid = chosenOption.id,
							untilEndOfTurn = self.durationUntilEndOfTurn,
							temporary_hitpoints = tempHitpoints,
							tempHitpointsEndEffect = tempHitpoints == nil,
						})
					end
				}
			end
		end
	end

	--we transformed creatures, so consume resources.
    ability:CommitToPaying(casterToken, args)
end

--build the fields used to edit a transform behavior.
function ActivatedAbilityTransformBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
	self:SummonEditor(parentPanel, result, { haveTargetCreature = true })
	self:OngoingEffectEditor(parentPanel, result, {transform = true})
	return result
end

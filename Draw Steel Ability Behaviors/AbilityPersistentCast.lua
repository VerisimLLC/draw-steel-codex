local mod = dmhub.GetModLoading()

local T = UIText.T

--- @class Persistence: GameType
--- @field new fun(o?: table): Persistence
--- @field guid string Unique id of this persistence entry.
--- @field abilityName string Name of the ability being kept up.
Persistence = RegisterGameType("Persistence")
Persistence.name = ""

--- @class ActivatedAbilityPersistenceControlBehavior:ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityPersistenceControlBehavior
ActivatedAbilityPersistenceControlBehavior = RegisterGameType("ActivatedAbilityPersistenceControlBehavior", "ActivatedAbilityBehavior")

--- @class ActivatedAbilityPersistenceCastBehavior:ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityPersistenceCastBehavior
--- @field token CharacterToken The token that keeps the ability persisting.
--- @field ability ActivatedAbility The persistent ability to recast.
--- @field targets? {token: CharacterToken}[] Targets to recast on; nil when the ability has none.
ActivatedAbilityPersistenceCastBehavior = RegisterGameType("ActivatedAbilityPersistenceCastBehavior", "ActivatedAbilityBehavior")

RegisterGoblinScriptSymbol(creature, {
	name = "Number of Persistent Abilities",
	type = "number",
	desc = "The number of persistent abilities that this creature has active.",
	examples = {'self.Number of Persistent Abilities < 1'},
	calculate = function(c)
        local persistentAbilities = c:try_get("persistentAbilities", {})
        return #persistentAbilities
	end,
})

RegisterGoblinScriptSymbol(creature, {
	name = "Persistent Abilities",
	type = "set",
	desc = "Persistent abilities that this creature currently has active.",
	examples = {'self.Persistent Abilities has "Behold the Mystery"'},
	calculate = function(c)
        local persistentAbilities = c:try_get("persistentAbilities", {})

        local results = {}
        for _, ability in pairs(persistentAbilities) do
            results[#results+1] = ability.abilityName
        end

        return StringSet.new {
            strings = results,
        }
	end,
})

ActivatedAbilityPersistenceControlBehavior.summary = "Persistence Control"
ActivatedAbilityPersistenceControlBehavior.triggerOnly = true
ActivatedAbilityPersistenceControlBehavior.mono = false

ActivatedAbility.RegisterType
{
	id = 'persistenceControl',
	text = 'Persistence Control',
	createBehavior = function()
		return ActivatedAbilityPersistenceControlBehavior.new{
		}
	end
}

function ActivatedAbilityPersistenceControlBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
	return result
end

--- What maintaining a persistent ability does, for the persistence dialog: the
--- "**Persistent N:**" line of its rules text, or failing that its prompt text or
--- the name of its persistence mode. nil when none of these say anything.
--- @param entry Persistence
--- @param caster creature
--- @return string|nil
local function DescribePersistence(entry, caster)
    local ability = entry:try_get("ability")
    if type(ability) ~= "table" or getmetatable(ability) == nil then
        --the stored copy did not survive; use the caster's own ability instead.
        ability = nil
        for _, candidate in ipairs(caster:GetActivatedAbilities{excludeGlobal = true}) do
            if candidate.name == entry.abilityName then
                ability = candidate
                break
            end
        end
        if ability == nil then
            return nil
        end
    end
    ---@cast ability ActivatedAbility

    --The colon may be inside or outside the bold.
    local text = string.match(ability.description or "", "%*%*Persistent%s+%d+%s*:?%s*%*%*:?%s*([^\r\n]+)")
    if text ~= nil then
        return StringInterpolateGoblinScript((string.gsub(trim(text), "%*%*", "")), caster)
    end

    local persistence = ability:Persistence()
    if type(persistence.promptText) == "string" and trim(persistence.promptText) ~= "" then
        return trim(persistence.promptText)
    end

    local mode = persistence.mode or "recast"
    if mode ~= "none" then
        for _, modeInfo in ipairs(ActivatedAbility.PersistenceModes) do
            if modeInfo.id == mode then
                return modeInfo.text
            end
        end
    end

    return nil
end

function ActivatedAbilityPersistenceControlBehavior:Cast(ability, casterToken, targets, options)

    local finished = false
    local canceled = false

    --Persistent recasts whose every target is already dead or gone have nothing
    --left to maintain; end them now, before the persistence cost is settled, so
    --the caster is not charged essence for them. Multi-target entries survive
    --while any target still lives (see creature:PersistentAbilityTargetsAllDead).
    local autoEnded = casterToken.properties:AutoEndPersistentAbilitiesWithDeadTargets()
    if #autoEnded > 0 then
        casterToken:ModifyProperties{
            description = "Persistent Ability Ended",
            undoable = false,
            execute = function()
                casterToken.properties:FloatLabel(string.format(tr("%s ended: target dead"), table.concat(autoEnded, ", ")), "#C49A5A")
            end,
        }
    end

    --Nothing left to decide: behave as if the trigger had never fired.
    if #(casterToken.properties:try_get("persistentAbilities") or {}) == 0 then
        return
    end

    local caster = casterToken.properties
    local casterClasses = caster:GetClassesAndSubClasses()
    local startOfTurnFormula = 0
    for _, classInfo in pairs(casterClasses) do
        local heroicResource = classInfo.class:get_or_add("heroicResourceChecklist", {})
        for _, resourceInfo in pairs(heroicResource) do
            if string.lower(resourceInfo.name or "") == "start of turn" then
                startOfTurnFormula = resourceInfo.quantity or 0
            end
        end
    end

    --a formula that does not reduce to a number counts as 0.
    local startOfTurnHeroicResource = tonumber(dmhub.EvalGoblinScript(startOfTurnFormula, caster:LookupSymbol(), string.format("Calculating Start of Turn Resources"))) or 0

    local persistenceAbilities = casterToken.properties:try_get("persistentAbilities") or {}

    -- Track which abilities are selected to KEEP (start with all selected).
    local keepAbilities = {}
    for _, ab in pairs(persistenceAbilities) do
        keepAbilities[ab.guid] = true
    end

    -- References so rows can trigger a refresh.
    local costLabelElement = nil
    local mustEndElement = nil
    local confirmElement = nil

    local function essenceGained()
        local result = startOfTurnHeroicResource
        for _, ab in pairs(persistenceAbilities) do
            if keepAbilities[ab.guid] then
                result = result - (ab.cost or 0)
            end
        end
        return result
    end

    --A hero may not lose essence to persistent abilities. Under strict resource
    --rules a player cannot confirm until they end enough of them; otherwise the
    --red gain is only a warning. Ending them all always leaves a gain of 0 or more.
    local function confirmBlocked()
        return StrictActionEconomyEnforced() and essenceGained() < 0
    end

    local function refreshCostLabel()
        if costLabelElement ~= nil then
            local gained = essenceGained()
            costLabelElement.text = string.format("Essence Gained: %d", gained)
            costLabelElement:SetClass("danger", gained < 0)
        end
        if mustEndElement ~= nil then
            mustEndElement:SetClass("collapsed", not confirmBlocked())
        end
        if confirmElement ~= nil then
            confirmElement:SetClass("disabled", confirmBlocked())
        end
    end

    -- Build one row for each persistent ability.
    local resourceName = caster:GetHeroicResourceName()
    local rowPanels = {}
    for _, persistAbility in pairs(persistenceAbilities) do
        local capturedAbility = persistAbility
        local description = DescribePersistence(capturedAbility, caster)

        rowPanels[#rowPanels+1] = gui.Panel{
            classes = {"bordered", "hoverable"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            hpad = 12,
            vpad = 8,
            vmargin = 4,
            borderBox = true,

            press = function(element)
                if keepAbilities[capturedAbility.guid] then
                    keepAbilities[capturedAbility.guid] = nil
                else
                    keepAbilities[capturedAbility.guid] = true
                end
                element:FireEventTree("refreshPersisting")
                refreshCostLabel()
            end,

            create = function(element)
                element:FireEventTree("refreshPersisting")
            end,

            refreshPersisting = function(element)
                local keep = keepAbilities[capturedAbility.guid] == true
                element:SetClass("bgAlt", keep)
                element:SetClass("borderAccent", keep)
            end,

            hover = function(element)
                local abilities = casterToken.properties:GetActivatedAbilities{excludeGlobal = true}
                for _, ab in ipairs(abilities) do
                    if ab.name == capturedAbility.abilityName then
                        element.tooltip = CreateAbilityTooltip(ab, {
                            token = casterToken,
                            halign = "right",
                            width = 500,
                        })
                        break
                    end
                end
            end,

            gui.Panel{
                width = "100%-100",
                height = "auto",
                flow = "vertical",
                valign = "center",
                gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    gui.Label{
                        classes = {"sizeM", "bold"},
                        halign = "left",
                        valign = "center",
                        text = capturedAbility.abilityName,
                    },
                    gui.Label{
                        classes = {"sizeS", "fgMuted"},
                        halign = "left",
                        valign = "center",
                        lmargin = 8,
                        text = T("persistence.cost", {cost = capturedAbility.cost or 0, resource = resourceName}),
                    },
                },
                description ~= nil and gui.Label{
                    classes = {"sizeS", "fg"},
                    width = "100%",
                    halign = "left",
                    textAlignment = "left",
                    tmargin = 2,
                    text = description,
                } or nil,
            },
            gui.Label{
                classes = {"sizeM", "bold"},
                width = 100,
                halign = "right",
                valign = "center",
                textAlignment = "right",
                refreshPersisting = function(element)
                    local keep = keepAbilities[capturedAbility.guid] == true
                    if keep then
                        element.text = T("persistence.persisting")
                    else
                        element.text = T("persistence.ending")
                    end
                    element:SetClass("danger", not keep)
                end,
            },
        }
    end

    -- Assemble main content.
    local mainChildren = {}

    mainChildren[#mainChildren+1] = gui.Label{
        classes = {"dialogTitle"},
        text = ability.name or "Persistence Control",
    }

    mainChildren[#mainChildren+1] = gui.Label{
        classes = {"sizeS"},
        width = "100%",
        textAlignment = "center",
        tmargin = 8,
        text = T("persistence.instruction"),
    }

    mainChildren[#mainChildren+1] = gui.Label{
        classes = {"sizeM", "bold"},
        halign = "center",
        vmargin = 8,

        create = function(element)
            costLabelElement = element
            refreshCostLabel()
        end,
    }

    mainChildren[#mainChildren+1] = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        children = rowPanels,
    }

    mainChildren[#mainChildren+1] = gui.Label{
        classes = {"sizeS", "danger", "collapsed"},
        width = "100%",
        textAlignment = "center",
        tmargin = 8,
        text = T("persistence.must_end"),

        create = function(element)
            mustEndElement = element
            refreshCostLabel()
        end,
    }

    mainChildren[#mainChildren+1] = gui.Button{
        classes = {"sizeM"},
        halign = "center",
        tmargin = 10,
        text = T("persistence.confirm"),

        create = function(element)
            confirmElement = element
            refreshCostLabel()
        end,

        click = function(element)
            if confirmBlocked() then
                return
            end

            -- End any persistent abilities that were NOT selected to keep. Ending one
            -- removes it from persistenceAbilities, so gather the ids first.
            local endGuids = {}
            for _, ab in pairs(persistenceAbilities) do
                if not keepAbilities[ab.guid] then
                    endGuids[#endGuids+1] = ab.guid
                end
            end
            for _, guid in ipairs(endGuids) do
                casterToken.properties:EndPersistentAbilityById(guid, "chose")
            end

            local earnedEssence = essenceGained()

            local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}
            for id, effect in pairs(ongoingEffectsTable) do
                if string.lower(effect.name) == "essence at start" then
                    casterToken:ModifyProperties{
                        description = "Set Start of Turn Essence",
                        execute = function()
                            casterToken.properties:ApplyOngoingEffect(id, nil, {tokenid = casterToken.charid}, {stacks = earnedEssence + 1})
                            --The effect lowers the start-of-turn gain by the cost just
                            --paid; record the full gain so the persistent abilities panel
                            --can still compare costs against it this turn.
                            casterToken.properties.persistenceGainAtStart = startOfTurnHeroicResource
                        end,
                    }
                    break
                end
            end

            finished = true
            gui.CloseModal()
        end,
    }

    local resultPanel = gui.Panel{
        classes = {"framedPanel"},
        --Modals sit outside the HUD's style cascade, so pull the theme in here.
        styles = ThemeEngine.GetStyles(),
        flow = "vertical",
        draggable = true,
        drag = function(element)
            element.x = element.xdrag
            element.y = element.ydrag
        end,
        width = 600,
        height = "auto",
        pad = 16,
        borderBox = true,

        --Closed some other way than Confirm: leave everything as it was.
        destroy = function(element)
            if not finished then
                finished = true
                canceled = true
            end
        end,

        children = mainChildren,
    }

    local themeHandler = ThemeEngine.OnThemeChanged(mod, function()
        if resultPanel.valid then
            resultPanel.styles = ThemeEngine.GetStyles()
        end
    end)

    gui.ShowModal(resultPanel)

    while not finished do
        coroutine.yield(0.1)
    end

    themeHandler:Deregister()

    if canceled then
        return
    end

end

function ActivatedAbilityPersistenceCastBehavior:Cast(ability, casterToken, targets, options)
    ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(self.token, self.ability, self.token, 'inherit', {}, { targets = self.targets })
end

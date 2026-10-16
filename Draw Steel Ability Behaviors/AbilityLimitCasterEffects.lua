local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityLimitCasterEffectsBehavior:ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityLimitCasterEffectsBehavior
--- Keeps the number of creatures carrying one of the caster's ongoing effects within a cap by
--- removing the oldest ones to make room for this cast's targets (Shadow "Careful Observation":
--- one observed creature at 3rd level, two at 7th, three at 10th). Put it before the
--- behavior that applies the effect.
--- @field ongoingEffect string Id of the ongoing effect being counted.
--- @field maxFormula string GoblinScript on the caster: the most creatures that may carry the effect.
ActivatedAbilityLimitCasterEffectsBehavior = RegisterGameType("ActivatedAbilityLimitCasterEffectsBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType{
    id = 'limit_caster_effects',
    text = 'Limit Active Effects',
    createBehavior = function()
        return ActivatedAbilityLimitCasterEffectsBehavior.new{
            applyto = "caster",
            maxFormula = "1",
        }
    end,
}

ActivatedAbilityLimitCasterEffectsBehavior.summary = 'Limit Active Effects'
ActivatedAbilityLimitCasterEffectsBehavior.maxFormula = "1"

--- @param ability ActivatedAbility
--- @param casterToken CharacterToken
--- @param targets table
--- @param options table
function ActivatedAbilityLimitCasterEffectsBehavior:Cast(ability, casterToken, targets, options)
    local effectid = self:try_get("ongoingEffect")
    if effectid == nil then
        return
    end

    local max = ExecuteGoblinScript(self:try_get("maxFormula", "1"), casterToken.properties:LookupSymbol(options.symbols or {}), 1, "Limit active effects")
    max = math.floor(tonumber(max) or 1)

    --Creatures this cast is about to (re)apply the effect to.
    local incoming = {}
    local incomingCount = 0
    for _, target in ipairs(options.targets or targets) do
        if target.token ~= nil and not incoming[target.token.charid] then
            incoming[target.token.charid] = true
            incomingCount = incomingCount + 1
        end
    end

    --Everyone else the caster currently has the effect on. Ordered by when the effect was
    --applied (its server timestamp): seq only orders effects on one creature, so it is
    --just a tie-break here. An effect applied moments ago still holds the placeholder
    --string until the server answers, so a timestamp that is not a number is the newest.
    local existing = {}
    for _, tok in ipairs(dmhub.allTokens) do
        if tok.valid and tok.properties ~= nil and not incoming[tok.charid] then
            for _, info in ipairs(tok.properties:ActiveOngoingEffects()) do
                if info.ongoingEffectid == effectid and info:try_get("casterInfo") ~= nil and info.casterInfo.tokenid == casterToken.charid then
                    existing[#existing+1] = { token = tok, seq = info.seq, time = tonumber(info.timestamp) or math.huge }
                end
            end
        end
    end
    table.sort(existing, function(a, b)
        if a.time ~= b.time then
            return a.time < b.time
        end
        return a.seq < b.seq
    end)

    local allowedExisting = math.max(0, max - incomingCount)
    local removeCount = #existing - allowedExisting
    for i = 1, removeCount do
        local entry = existing[i]
        entry.token:ModifyProperties{
            description = "Observation replaced",
            execute = function()
                entry.token.properties:RemoveOngoingEffectBySeq(entry.seq)
            end,
        }
    end
end

--- @param parentPanel Panel
--- @return Panel[]
function ActivatedAbilityLimitCasterEffectsBehavior:EditorItems(parentPanel)
    local result = {}
    self:ApplyToEditor(parentPanel, result)

    local choices = {}
    for k, effect in unhidden_pairs(dmhub.GetTable(CharacterOngoingEffect.tableName) or {}) do
        choices[#choices+1] = { id = k, text = effect.name }
    end
    table.sort(choices, function(a, b) return a.text < b.text end)
    table.insert(choices, 1, { id = "none", text = "Choose an effect..." })

    result[#result+1] = gui.Panel{
        classes = { "formPanel" },
        gui.Label{ classes = { "formLabel" }, text = "Effect:" },
        gui.Dropdown{
            classes = { "formDropdown" },
            options = choices,
            hasSearch = true,
            idChosen = self:try_get("ongoingEffect", "none"),
            change = function(element)
                ---@cast element Dropdown
                if element.idChosen ~= "none" then
                    self.ongoingEffect = element.idChosen --[[@as string]]
                end
            end,
        },
    }

    result[#result+1] = gui.Panel{
        classes = { "formPanel" },
        gui.Label{ classes = { "formLabel" }, text = "Max Creatures:" },
        gui.GoblinScriptInput{
            classes = { "formInput" },
            value = self:try_get("maxFormula", "1"),
            change = function(element)
                self.maxFormula = element.value
            end,
            documentation = {
                help = "The most creatures that may carry the effect from this caster at once.",
                output = "number",
                subject = creature.helpSymbols,
                subjectDescription = "The caster",
                examples = { { script = "3 when Level >= 10 else 2 when Level >= 7 else 1", text = "Careful Observation limit." } },
            },
        },
    }
    return result
end

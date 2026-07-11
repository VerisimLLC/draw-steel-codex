local mod = dmhub.GetModLoading()


RegisterGameType("ActivatedAbilityForcedMovementLocBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
	id = 'forcedmovementloc',
	text = 'Forced Movement Origin',
	createBehavior = function()
		return ActivatedAbilityForcedMovementLocBehavior.new{
            type = "aura",
		}
	end
}

ActivatedAbilityForcedMovementLocBehavior.summary = 'Forced Movement Origin'
ActivatedAbilityForcedMovementLocBehavior.creatureRange = ""
ActivatedAbilityForcedMovementLocBehavior.creatureFilter = ""

function ActivatedAbilityForcedMovementLocBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Forced Movement Origin"
end


function ActivatedAbilityForcedMovementLocBehavior:Cast(ability, casterToken, targets, options)
    if self.type == "target" then
        --the ability's current (first) target is the origin. Run this while the
        --targets are still e.g. a wall square object -- before a later
        --manipulate_targets behavior replaces them with creatures -- so pushes
        --originate from the object (e.g. the Wallmaster's Dead End).
        local target = targets ~= nil and targets[1] or nil
        if target == nil or target.token == nil or not target.token.valid then
            print("ORIGIN:: no target to use as origin")
            return
        end

        options.symbols.forcedMovementOrigin = target.token.loc
        print("ORIGIN:: set origin =", target.token.loc.str)
    elseif self.type == "aura" then
        local aura = options.symbols.aura
        if aura == nil or aura:GetArea() == nil then
            print("Origin: aura not found")
            return
        end

        local origin = aura:GetArea().origin
        options.symbols.forcedMovementOrigin = origin
        print("ORIGIN:: set origin =", origin.str)
    elseif self.type == "creature" then
        local rangeFormula = self:try_get("creatureRange", "")
        local rangeLimit = nil
        if trim(rangeFormula) ~= "" then
            rangeLimit = tonumber(ExecuteGoblinScript(rangeFormula, casterToken.properties:LookupSymbol{}, nil, "Forced Movement Origin Range"))
        end

        local filterFormula = self:try_get("creatureFilter", "")
        local hasFilter = trim(filterFormula) ~= ""

        local candidates = {}
        for _,tok in ipairs(dmhub.allTokens) do
            if tok.valid then
                local pass = true

                if rangeLimit ~= nil and casterToken.loc:DistanceInTiles(tok.loc) > rangeLimit then
                    pass = false
                end

                if pass and hasFilter then
                    local symbols = {
                        caster = casterToken.properties:LookupSymbol{},
                        target = tok.properties:LookupSymbol{},
                        enemy = (not casterToken:IsFriend(tok)),
                    }
                    if not GoblinScriptTrue(ExecuteGoblinScript(filterFormula, tok.properties:LookupSymbol(symbols), 1, "Forced Movement Origin Filter")) then
                        pass = false
                    end
                end

                if pass then
                    candidates[#candidates+1] = tok
                end
            end
        end

        if #candidates == 0 then
            print("Origin: no creature candidates")
            return
        end

        local chosenLoc = nil
        local done = false
        print("ORIGIN:: prompting for creature, candidates=", #candidates, "range=", tostring(rangeLimit))
        GameHud.instance.actionBarPanel:FireEventTree("chooseTargetToken", {
            sourceToken = casterToken,
            radius = rangeLimit,
            targets = candidates,
            prompt = "Choose Origin Creature",
            choose = function(targetToken)
                print("ORIGIN:: choose fired ->", targetToken and targetToken.charid)
                if targetToken ~= nil and targetToken.valid then
                    chosenLoc = targetToken.loc
                end
                done = true
            end,
            cancel = function()
                print("ORIGIN:: cancel fired")
                done = true
            end,
        })

        while not done do
            coroutine.yield(0.1)
        end

        if chosenLoc ~= nil then
            options.symbols.forcedMovementOrigin = chosenLoc
            print("ORIGIN:: set origin =", chosenLoc.str)
        end
    end
end


function ActivatedAbilityForcedMovementLocBehavior:EditorItems(parentPanel)
    local result = {}

    result[#result + 1] = gui.Panel {
        classes = { "formPanel" },
        gui.Label {
            classes = { "formLabel" },
            text = "Origin:",
        },

        gui.Dropdown {
            idChosen = self.type or "aura",
            options = {
                { id = 'aura', text = 'Center of Aura' },
                { id = 'creature', text = 'A Creature' },
                { id = 'target', text = 'First Target' },
            },
            change = function(element)
                self.type = element.idChosen
                parentPanel:FireEventTree("refreshOriginType")
            end,
        }
    }

    result[#result + 1] = gui.Panel {
        classes = { "formPanel", cond(self.type == "creature", nil, "collapsed") },
        refreshOriginType = function(element)
            element:SetClass("collapsed", self.type ~= "creature")
        end,
        gui.Label {
            classes = { "formLabel" },
            text = "Range:",
        },
        gui.GoblinScriptInput {
            classes = "formInput",
            value = self:try_get("creatureRange", ""),
            change = function(element)
                self.creatureRange = element.value
            end,

            documentation = {
                help = "Maximum distance (in tiles) from the caster that a candidate origin creature may be. Leave blank for no range limit.",
                output = "number",
                examples = {
                    {
                        script = "5",
                        text = "Limit selection to creatures within 5 tiles of the caster.",
                    },
                    {
                        script = "Might",
                        text = "Limit the range to the caster's Might score.",
                    },
                },
                subject = creature.helpSymbols,
                subjectDescription = "The caster of this ability.",
                symbols = ActivatedAbility.helpCasting,
            },
        },
    }

    result[#result + 1] = gui.Panel {
        classes = { "formPanel", cond(self.type == "creature", nil, "collapsed") },
        refreshOriginType = function(element)
            element:SetClass("collapsed", self.type ~= "creature")
        end,
        gui.Label {
            classes = { "formLabel" },
            text = "Target Filter:",
        },
        gui.GoblinScriptInput {
            classes = "formInput",
            value = self:try_get("creatureFilter", ""),
            change = function(element)
                self.creatureFilter = element.value
            end,

            documentation = {
                help = "GoblinScript that decides which creatures are valid target candidates. Leave blank to allow any creature.",
                output = "boolean",
                examples = {
                    {
                        script = "enemy",
                        text = "Only allow enemies of the caster as the target.",
                    },
                    {
                        script = "not enemy",
                        text = "Only allow allies (non-enemies) of the caster as the target.",
                    },
                    {
                        script = "type is not undead",
                        text = "Disallow undead creatures .",
                    },
                },
                subject = creature.helpSymbols,
                subjectDescription = "A candidate creature on the battlefield.",
                symbols = {
                    caster = {
                        name = "Caster",
                        type = "creature",
                        desc = "The caster of this ability.",
                    },
                    enemy = {
                        name = "Enemy",
                        type = "boolean",
                        desc = "True if the subject is an enemy of the caster. Otherwise False.",
                    },
                    target = {
                        name = "Target",
                        type = "creature",
                        desc = "The candidate creature. Same as the subject.",
                    },
                },
            },
        },
    }

    return result
end
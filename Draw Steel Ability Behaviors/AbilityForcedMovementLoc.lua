local mod = dmhub.GetModLoading()


--- @class ActivatedAbilityForcedMovementLocBehavior: ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityForcedMovementLocBehavior
ActivatedAbilityForcedMovementLocBehavior = RegisterGameType("ActivatedAbilityForcedMovementLocBehavior", "ActivatedAbilityBehavior")

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

--"Center of Aura" options, for a trigger that does not come from the aura itself (e.g. an
--ongoing effect's "attacked" trigger that pulls toward the area placed around its owner):
--  auraName: when no aura is in the cast's symbols, find a map aura with this name (the
--    Aura definition's name or the instance's name) that was placed around the creature
--    running this ability. See FindNamedAurasAroundCreature for the matching rule.
--  requireLineOfEffect: drop every target with no line of effect to any square of the
--    area, so later behaviors (the pull) skip them. With no area at all, every target is
--    dropped.
ActivatedAbilityForcedMovementLocBehavior.auraName = ""
ActivatedAbilityForcedMovementLocBehavior.requireLineOfEffect = false

function ActivatedAbilityForcedMovementLocBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Forced Movement Origin"
end

--- Map auras named auraName that were placed around this creature. An aura placed by an
--- ability on a creature target records that creature (AuraInstance.anchorTokenId). Auras
--- with no such record (placed before it existed, or onto an area) count when the
--- creature currently stands in them.
--- @param auraName string
--- @param creatureToken CharacterToken
--- @return AuraInstance[]
local function FindNamedAurasAroundCreature(auraName, creatureToken)
    local wanted = string.lower(trim(auraName))
    local anchored = {}
    local unanchored = {}
    for _,entry in ipairs(Aura.GetMapAnchoredAuras()) do
        local instance = entry.instance
        local auraDef = instance:try_get("aura")
        local defName = auraDef ~= nil and string.lower(auraDef.name or "") or ""
        local instanceName = string.lower(instance:try_get("name", ""))
        local area = instance:GetArea()
        if (defName == wanted or instanceName == wanted) and area ~= nil and not instance:HasExpired() then
            local anchorid = instance:try_get("anchorTokenId")
            if anchorid == creatureToken.charid then
                anchored[#anchored+1] = instance
            elseif anchorid == nil and area:ContainsToken(creatureToken) then
                unanchored[#unanchored+1] = instance
            end
        end
    end

    if #anchored > 0 then
        return anchored
    end
    return unanchored
end

--- True if the token has line of effect to at least one square of the area.
--- @param token CharacterToken
--- @param area LuaShape
--- @return boolean
local function HasLineOfEffectToArea(token, area)
    --GetPierceWalls is a count; pass a boolean so 0 does not read as "pierce".
    local pierce = token.properties:GetPierceWalls() > 0
    for _,loc in ipairs(area.locations or {}) do
        if token:GetLineOfSight(loc, pierce) > 0 then
            return true
        end
    end
    return false
end

--- Removes a target from the cast's shared target list (as the Fizzle behavior does), so
--- the behaviors after this one no longer apply to it.
local function DropTarget(targets, options, target)
    local lists = { options.targets }
    if targets ~= options.targets then
        lists[#lists+1] = targets
    end
    for _,list in ipairs(lists) do
        for i = #list, 1, -1 do
            local t = list[i]
            if t == target or (target.token ~= nil and t.token ~= nil and target.token.charid == t.token.charid) then
                table.remove(list, i)
            end
        end
    end
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
        options.symbols.forcedMovementOriginTokenId = target.token.charid
        print("ORIGIN:: set origin =", target.token.loc.str)
    elseif self.type == "aura" then
        local aura = options.symbols.aura
        local auraName = self:try_get("auraName", "")
        if (aura == nil or aura:GetArea() == nil) and trim(auraName) ~= "" then
            self:CastNamedAura(casterToken, targets, options, auraName)
            return
        end

        if aura == nil or aura:GetArea() == nil then
            print("Origin: aura not found")
            return
        end

        if self:try_get("requireLineOfEffect", false) then
            local area = aura:GetArea()
            for _,target in ipairs(table.shallow_copy(targets)) do
                if target.token == nil or not HasLineOfEffectToArea(target.token, area) then
                    DropTarget(targets, options, target)
                end
            end
        end

        local origin = aura:GetArea().origin
        options.symbols.forcedMovementOrigin = origin
        options.symbols.forcedMovementOriginTokenId = nil
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
        local chosenTokenId = nil
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
                    chosenTokenId = targetToken.charid
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
            options.symbols.forcedMovementOriginTokenId = chosenTokenId
            print("ORIGIN:: set origin =", chosenLoc.str)
        end
    end
end


--- "Center of Aura" with no aura in the symbols: find the named aura(s) placed around the
--- creature running this ability and pull toward the center square of the area. With
--- several such areas, each target is measured against the ones it has line of effect to
--- (all of them when requireLineOfEffect is off), and the origin is the nearest of those
--- to the first remaining target. Finding no area drops every target, so nothing is moved
--- toward the creature by mistake.
--- @param casterToken CharacterToken
--- @param targets table
--- @param options table
--- @param auraName string
function ActivatedAbilityForcedMovementLocBehavior:CastNamedAura(casterToken, targets, options, auraName)
    local auras = FindNamedAurasAroundCreature(auraName, casterToken)
    local requireLoE = self:try_get("requireLineOfEffect", false)

    local chosenArea = nil
    for _,target in ipairs(table.shallow_copy(targets)) do
        local best = nil
        local bestDistance = nil
        if target.token ~= nil and target.token.valid then
            for _,instance in ipairs(auras) do
                local area = instance:GetArea()
                if area ~= nil and ((not requireLoE) or HasLineOfEffectToArea(target.token, area)) then
                    local center = TriggeredAbility.AreaCenterLoc(area) or area.origin
                    local distance = target.token:Distance(center)
                    if bestDistance == nil or distance < bestDistance then
                        best = area
                        bestDistance = distance
                    end
                end
            end
        end

        if best == nil then
            DropTarget(targets, options, target)
        elseif chosenArea == nil then
            chosenArea = best
        end
    end

    if chosenArea == nil then
        print("ORIGIN:: no aura named", auraName, "around", casterToken.charid, "reachable by the targets")
        return
    end

    local origin = TriggeredAbility.AreaCenterLoc(chosenArea) or chosenArea.origin
    options.symbols.forcedMovementOrigin = origin
    options.symbols.forcedMovementOriginTokenId = nil
    print("ORIGIN:: set origin from named aura =", origin.str)
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
                ---@cast element Dropdown
                self.type = element.idChosen
                parentPanel:FireEventTree("refreshOriginType")
            end,
        }
    }

    --"Center of Aura" from a trigger the aura does not own: name the aura to look for.
    result[#result + 1] = gui.Panel {
        classes = { "formPanel", cond((self.type or "aura") == "aura", nil, "collapsed") },
        refreshOriginType = function(element)
            element:SetClass("collapsed", (self.type or "aura") ~= "aura")
        end,
        gui.Label {
            classes = { "formLabel" },
            text = "Aura Name:",
        },
        gui.Input {
            classes = "formInput",
            text = self:try_get("auraName", ""),
            placeholderText = "Only when not triggered by the aura",
            change = function(element)
                self.auraName = element.text
            end,
        },
    }

    result[#result + 1] = gui.Check {
        classes = { cond((self.type or "aura") == "aura", nil, "collapsed") },
        text = "Targets need line of effect to the aura",
        value = self:try_get("requireLineOfEffect", false),
        refreshOriginType = function(element)
            element:SetClass("collapsed", (self.type or "aura") ~= "aura")
        end,
        change = function(element)
            self.requireLineOfEffect = element.value
        end,
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

local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityRelocateAuraBehavior:ActivatedAbilityBehavior
--- A selectable ability behavior that relocates one of the caster's placed auras (by name) to the
--- ability's targeted location. Mirrors the built-in "Can relocate" aura option (see
--- ActivatedAbilityMoveAuraBehavior in DMHub Game Rules/Aura.lua), but usable from any ability.
--- The host ability must use a point/area target type so that options.targetArea is populated.
--- @field summary string Short label shown in the behavior list in the ability editor.
--- @field auraName string Name of the caster's aura to relocate (matched against AuraInstance.name).
RegisterGameType("ActivatedAbilityRelocateAuraBehavior", "ActivatedAbilityBehavior")

-- Register this behavior so it can be selected and added to any ability in the ability editor.
ActivatedAbility.RegisterType{
    id = 'relocate_aura',
    text = 'Relocate Aura',
    createBehavior = function()
        return ActivatedAbilityRelocateAuraBehavior.new{ auraName = "" }
    end,
}

-- Default field values (see @field annotations above).
ActivatedAbilityRelocateAuraBehavior.summary = 'Relocate Aura'
ActivatedAbilityRelocateAuraBehavior.auraName = ""

--- Returns the human-readable summary shown for this behavior in the ability editor.
--- @param ability ActivatedAbility The ability that owns this behavior.
--- @param creatureLookup table Map of creature ids to creatures (unused here).
--- @return string
function ActivatedAbilityRelocateAuraBehavior:SummarizeBehavior(ability, creatureLookup)
    if self.auraName ~= "" then
        return string.format("Relocate aura: %s", self.auraName)
    end
    return "Relocate Aura"
end

--- Executes the behavior: finds the caster's placed aura matching auraName and moves it to the
--- ability's target location, replicating the slide animation used by the built-in relocate option.
--- Does not consume resources -- the host ability's normal cast/cost flow handles payment.
--- @param ability ActivatedAbility The ability being cast.
--- @param casterToken CharacterToken The token casting the ability (owns the aura).
--- @param targets table[] The ability's resolved targets (unused; we relocate to the target area).
--- @param options table Cast options; options.targetArea provides the destination (xpos/ypos).
--- @return nil
function ActivatedAbilityRelocateAuraBehavior:Cast(ability, casterToken, targets, options)
    -- Need a target location to move to, and a valid caster that can own auras.
    if options.targetArea == nil or casterToken == nil or casterToken.properties == nil then
        return
    end

    -- Find a matching placed aura owned by the caster. Try an exact name match first, then fall
    -- back to a case-insensitive match. Only auras that have actually been placed on the map
    -- (those with an "object" reference) can be relocated.
    local auras = casterToken.properties:try_get("auras", {})
    local match = nil
    local wanted = self.auraName
    for _, a in ipairs(auras) do
        if a.name == wanted and a:try_get("object") ~= nil then
            match = a
            break
        end
    end
    if match == nil then
        local lower = string.lower(wanted)
        for _, a in ipairs(auras) do
            if string.lower(a.name) == lower and a:try_get("object") ~= nil then
                match = a
                break
            end
        end
    end
    if match == nil then
        return
    end

    -- Resolve the placed map object that represents the aura.
    local obj = game.LookupObject(match.object.floorid, match.object.objid)
    if obj == nil then
        return
    end

    dmhub.BeginTransaction()

    -- Destination coordinates come from the ability's targeted area.
    local destx = options.targetArea.xpos
    local desty = options.targetArea.ypos

    -- Record the movement delta on the Aura component so the engine plays the slide animation
    -- from the old position to the new one.
    local objAura = obj:GetComponent("Aura")
    if objAura ~= nil then
        objAura:SetAndUploadProperties{
            moveTimestamp = dmhub.serverTime,
            movex = destx - obj.x,
            movey = desty - obj.y,
        }
    end

    -- Move the object to the destination and upload the change.
    obj:SetAndUploadPos(destx, desty)

    dmhub.EndTransaction()
end

--- Builds the editor UI for this behavior: a single text input for the aura's name.
--- @param parentPanel Panel The parent editor panel (unused here).
--- @return Panel[] The list of editor panels to display.
function ActivatedAbilityRelocateAuraBehavior:EditorItems(parentPanel)
    local result = {}
    result[#result+1] = gui.Panel{
        classes = { "formPanel" },
        gui.Label{ classes = { "formLabel" }, text = "Aura Name:" },
        gui.Input{
            classes = { "formInput" },
            text = self:try_get("auraName", ""),
            placeholderText = "Name of the aura to move",
            change = function(element)
                self.auraName = element.text
            end,
        },
    }
    return result
end

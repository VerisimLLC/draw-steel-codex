local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityReaction: GameType
--- @field type string Reaction trigger type id (e.g. "none", "onAttacked", "onDamaged").
ActivatedAbilityReaction = RegisterGameType("ActivatedAbilityReaction")

ActivatedAbilityReaction.type = "none"

ActivatedAbilityReaction.types = {
    {
        id = "none",
        text = "None",
    },
    {
        id = "move_out_of_reach",
        text = "Enemy moves out of reach",
    },
}

local g_nullReaction = ActivatedAbilityReaction.new{}

function ActivatedAbility:GetReactionInfo()
    return self:try_get("reactionInfo", g_nullReaction)
end

function ActivatedAbility:GetOrAddReactionInfo()
    if self:has_key("reactionInfo") == false then
        self.reactionInfo = ActivatedAbilityReaction.new{}
    end

    return self.reactionInfo
end

function creature:ActivateReaction(ability, targets)
	local token = dmhub.LookupToken(self)
    if token == nil then
        return
    end

    if not ability:CanAfford(token) then
        return
    end

    token:ModifyProperties{
        description = "Activate Reaction",
        execute = function()
            local activeReactions = self:get_or_add("activeReactions", {})

            for i=#activeReactions, 1, -1 do
                local reaction = activeReactions[i]
                if TimestampAgeInSeconds(reaction.timestamp) > 60 then
                    table.remove(activeReactions, i)
                end
            end

            activeReactions[#activeReactions + 1] = {
                guid = dmhub.GenerateGuid(),
                ability = ability.name,
                targets = targets,
                timestamp = ServerTimestamp(),
            }
        end,
    }
end

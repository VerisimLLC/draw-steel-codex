local mod = dmhub.GetModLoading()

local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityLimitBehavior:ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityLimitBehavior
--- @field summary string Short label shown in behavior lists.
--- @field key string Guid keying this limit's use count in the caster's abilityUses.
ActivatedAbilityLimitBehavior = RegisterGameType("ActivatedAbilityLimitBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityLimitBehavior.summary = 'Limit Ability Uses'

ActivatedAbility.RegisterType
{
    id = "limit",
    text = "Limit Ability Uses",
    createBehavior = function()
        return ActivatedAbilityLimitBehavior.new{
            key = dmhub.GenerateGuid(),
            refresh = "encounter",
        }
    end,
}

function ActivatedAbilityLimitBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Limit Ability Uses"
end

function ActivatedAbilityLimitBehavior:Cast(ability, casterToken, targets, options)
    if #targets == 0 then
        print("LIMIT:: NO TARGETS")
        options.abort = true
        return
    end

    local refreshid = casterToken.properties:GetResourceRefreshId(self.refresh)

    local key = self.key
    if self:try_get("keyOverride", "") ~= "" then
        key = self.keyOverride
    end

    print("LIMIT:: CHECKING", casterToken.name, key, "refresh", self.refresh, "id", refreshid)

    local abilityUses = casterToken.properties:try_get("abilityUses", {})
    if abilityUses[key] ~= nil and casterToken.properties:IsResourceUsageCurrent(self.refresh, abilityUses[key].refreshid) then
        --already used this ability in this refresh
        print("LIMIT:: LIMITING ABILITY")
        --TODO: maybe allow a stop count?
        options.stopProcessing = true
        return
    end
        print("LIMIT:: PROCEEDING", key)

    casterToken:ModifyProperties{
        description = "Limit ability uses",
        execute = function()
            abilityUses[key] = {refreshid = refreshid}
            casterToken.properties.abilityUses = abilityUses
        end,
    }
end

function ActivatedAbilityLimitBehavior:EditorItems(parentPanel)
	local result = {}

	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Refresh:",
        },
        CharacterResource.RefreshTypeEditor{
            value = self:try_get("refresh", "never"),
            change = function(refreshType)
                self.refresh = refreshType
            end,
        }
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Unique ID:",
        },
        gui.Input{
            characterLimit = 32,
            text = self:try_get("keyOverride"),
            change = function(element)
                self.keyOverride = element.text
            end,
        }
    }

	return result
end


local mod = dmhub.GetModLoading()

--- @class TeleportChatMessage: GameType
--- @field new fun(o?: table): TeleportChatMessage
--- Action log card recording that a token teleported, naming the ability responsible.
--- @field tokenid string
--- @field squares number
--- @field abilityName string
TeleportChatMessage = RegisterGameType("TeleportChatMessage")
TeleportChatMessage.tokenid = ""
TeleportChatMessage.squares = 0
TeleportChatMessage.abilityName = ""

--- @return nil|CharacterToken
function TeleportChatMessage:GetToken()
    return dmhub.GetCharacterById(self.tokenid)
end

--- @param selfInput TeleportChatMessage
--- @param message table
--- @return nil|Panel
function TeleportChatMessage.Render(selfInput, message)
    local token = selfInput:GetToken()
    if token == nil or (not token.valid) then
        return nil
    end

    local detailLabel = gui.Label{
        classes = {"action-log-detail", "sizeXs", "fg"},
        text = string.format("Teleported %d %s", selfInput.squares, cond(selfInput.squares == 1, "square", "squares")),
    }
    local abilityLabel = gui.Label{
        classes = {"action-log-subtext", "sizeXxs", "fgMuted"},
        text = selfInput.abilityName,
    }

    return gui.Panel{
        classes = {"chat-message-panel"},
        flow = "vertical",
        width = "100%",
        height = "auto",
        refreshMessage = function(element, message) end,
        CreateActionLogCard{
            token = token,
            content = {detailLabel, abilityLabel},
        },
    }
end

--- @class ActivatedAbilityTeleportToLineEndBehavior:ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityTeleportToLineEndBehavior
--- Teleports the caster to the first unoccupied square at the far end of a line ability
--- (Shadow "Shadowfall"). Runs with applyto = caster after the power roll, so the caster
--- reappears only once every creature in the line has taken its damage. The end square is
--- used if it is free; otherwise the search walks back along the line toward the caster.
ActivatedAbilityTeleportToLineEndBehavior = RegisterGameType("ActivatedAbilityTeleportToLineEndBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType{
    id = 'teleport_to_line_end',
    text = 'Teleport To Line End',
    createBehavior = function()
        return ActivatedAbilityTeleportToLineEndBehavior.new{
            applyto = "caster",
        }
    end,
}

ActivatedAbilityTeleportToLineEndBehavior.summary = 'Teleport To Line End'

--True if tok could stand at loc without sharing any square with another creature.
--- @param tok CharacterToken
--- @param loc Loc
--- @return boolean
local function LocIsFreeForToken(tok, loc)
    local locs = tok:LocsOccupyingWhenAt(loc)
    if locs == nil or #locs == 0 then
        return false
    end
    for _, occLoc in ipairs(locs) do
        if not occLoc.isOnMap then
            return false
        end
        for _, other in ipairs(dmhub.GetTokensAtLoc(occLoc) or {}) do
            if other.charid ~= tok.charid then
                return false
            end
        end
    end
    return true
end

--- @param ability ActivatedAbility
--- @param creatureLookup table
--- @return string
function ActivatedAbilityTeleportToLineEndBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Teleport to the first unoccupied square at the end of the line"
end

--- @param ability ActivatedAbility
--- @param casterToken CharacterToken
--- @param targets table
--- @param options table
function ActivatedAbilityTeleportToLineEndBehavior:Cast(ability, casterToken, targets, options)
    local locs = options.targetArea and options.targetArea.locations
    if locs == nil or #locs == 0 then
        casterToken.properties:FloatLabel("Needs a line target", "red")
        return
    end

    --Furthest square first, then back toward the caster until one is free.
    local ordered = {}
    for _, loc in ipairs(locs) do
        ordered[#ordered+1] = loc
    end
    table.sort(ordered, function(a, b)
        return a:DistanceInTiles(casterToken.loc) > b:DistanceInTiles(casterToken.loc)
    end)

    local dest = nil
    for _, loc in ipairs(ordered) do
        if LocIsFreeForToken(casterToken, loc) then
            dest = loc
            break
        end
    end

    if dest == nil then
        casterToken.properties:FloatLabel("No room to reappear", "red")
        return
    end

    --Reuse the normal teleport so spaces-moved, opportunity-attack and teleport-event
    --handling stay identical. The relocate behavior replaces its target with the line's
    --end square when it sees a line area, so hide the area while it runs.
    local distance = casterToken:Distance(dest)
    local savedArea = options.targetArea
    options.targetArea = nil
    local relocate = ActivatedAbilityRelocateCreatureBehavior.new{ movementType = "teleport", applyto = "caster" }
    local ok, err = pcall(function()
        relocate:Cast(ability, casterToken, { { loc = dest } }, options)
    end)
    options.targetArea = savedArea
    if not ok then
        print("TeleportToLineEnd:: ERROR", err)
    elseif distance > 0 then
        --Action log card under the ability's damage: "Teleported 6 squares (Shadowfall)".
        local squares = math.floor(distance + 0.5)
        chat.SendCustom(TeleportChatMessage.new{
            tokenid = casterToken.charid,
            squares = squares,
            abilityName = ability.name,
        })
    end
end

--- @param parentPanel Panel
--- @return Panel[]
function ActivatedAbilityTeleportToLineEndBehavior:EditorItems(parentPanel)
    local result = {}
    self:ApplyToEditor(parentPanel, result)
    return result
end

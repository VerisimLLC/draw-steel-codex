--- Companion aura sync: push a creature's current auras when its Companion connects.
---
--- Why this exists: the engine emits the `creature.auras` channel event only when
--- an aura is (re)computed (the [AuraTrack] "refill" path). A creature's auras are
--- computed at map-load -- before its Companion window ever connects -- so a freshly
--- opened Companion receives nothing and shows an empty "Auras, Conditions & Effects"
--- section. This handler fills that gap by sending a one-time snapshot whenever a
--- Companion connects. The change-driven path still handles live updates after that.
---
--- The payload shape matches what the Companion's AuraChip renders
--- (name / description / source / guid). See CharacterSheet.jsx in the companion repo.

--- Build and send the auras affecting `session`'s creature to that Companion window.
--- @param session table a companion session (has .characterId, :IsConnected(), :SendEvent())
local function SendCompanionAuraSnapshot(session)
    if session == nil or session.characterId == nil then
        return
    end

    -- Resolve characterId -> token. For monsters token.id == charid (GetTokenById
    -- hits directly); for player heroes characterId is the hero id, so fall back
    -- to scanning tokens by charid.
    local token = dmhub.GetTokenById(session.characterId)
    if token == nil then
        for _, t in ipairs(dmhub.GetTokens()) do
            if tostring(t.charid) == session.characterId then
                token = t
                break
            end
        end
    end
    if token == nil or token.properties == nil then
        return
    end

    local auras = {}
    for i, info in ipairs(token.properties:GetAurasAffecting(token) or {}) do
        local auraInstance = info.auraInstance

        -- Name the caster so the Companion can show "(from X)".
        local source
        if auraInstance.casterid then
            local caster = dmhub.GetTokenById(auraInstance.casterid)
            if caster ~= nil then
                source = caster.name
            end
        end

        auras[#auras + 1] = {
            guid = auraInstance:try_get("guid") or ("affecting-" .. i),
            name = auraInstance.aura.name,
            description = auraInstance.aura:GetDescription(),
            source = source,
        }
    end

    session:SendEvent("creature.auras", {
        characterId = session.characterId,
        auras = auras,
    })
end

-- Register once at load. `dmhub.companionChannel` is a core engine member, so it is
-- present by the time CodeMods load; guard defensively all the same.
if dmhub.companionChannel ~= nil then
    dmhub.companionChannel:OnCompanionConnected(SendCompanionAuraSnapshot)
end

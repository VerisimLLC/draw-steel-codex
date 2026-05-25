--- Companion sync: push a creature's auras and authoritative derived stats to
--- its Companion window, on connect and as they change.
---
--- Why this exists: the engine pushes `creature.auras` / `creature.stats` over the
--- Codex channel only when recomputed, so a freshly opened Companion (whose state
--- was computed at map-load, before it connected) shows stale/empty values. These
--- handlers send a snapshot of both on connect, and a coalesced poll re-pushes stats
--- whenever they change (e.g. a token moves in/out of an aura that buffs recovery
--- value or speed). Auras can't be derived by the Companion at all (they depend on
--- the live map); derived stats can be, but drift when an aura/effect the Companion
--- doesn't model is active, so DMHub is the source of truth when connected.
---
--- Live updates use poll-and-diff rather than an event hook because DMHub exposes no
--- Lua event for aura-coverage / derived-stat changes (aura recompute is C#-side).
--- The poll only SENDS when a value actually changed, so the channel sees on-change
--- traffic, not periodic spam.
---
--- Payload shapes match what the Companion renders:
---   creature.auras: { characterId, auras:[{ guid, name, description, source }] }
---   creature.stats: { characterId, stats:{ …displayed derived numbers… } }
--- See CharacterSheet.jsx / authoritativeStats.js in the companion repo, and
--- docs/superpowers/specs/2026-05-20-companion-stat-sync-design.md.

--- Resolve a session's characterId to its token. For monsters token.id == charid
--- (GetTokenById hits directly); for player heroes characterId is the hero id, so
--- fall back to scanning tokens by charid. Returns nil if not found.
local function ResolveCompanionToken(session)
    if session == nil or session.characterId == nil then
        return nil
    end
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
        return nil
    end
    return token
end

--- Build and send the auras affecting `session`'s creature to that Companion window.
local function SendCompanionAuraSnapshot(session)
    local token = ResolveCompanionToken(session)
    if token == nil then return end

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

--- Gather DMHub's authoritative derived stats for a token into the `creature.stats`
--- payload shape. These are the same accessors DMHub's own character sheet uses, so
--- the Companion matches DMHub exactly when connected.
local function BuildStatSnapshot(token)
    local c = token.properties
    local recoveryId = CharacterResource.recoveryResourceId
    return {
        maxStamina = c:MaxHitpoints(),
        currentStamina = c:CurrentHitpoints(),
        tempStamina = c:TemporaryHitpoints(),
        windedThreshold = math.floor(c:MaxHitpoints() / 2),
        dyingThreshold = c:BloodiedThreshold(),
        recoveryValue = c:RecoveryAmount(),
        recoveriesMax = c:GetResources()[recoveryId] or 0,
        recoveriesUsed = c:GetResourceUsage(recoveryId, "long") or 0,
        speed = c:CurrentMovementSpeed(),
        stability = c:Stability(),
        disengage = c:CalculateNamedCustomAttribute("Disengage Speed"),
        might = c:GetAttribute("mgt"):Value(),
        agility = c:GetAttribute("agl"):Value(),
        reason = c:GetAttribute("rea"):Value(),
        intuition = c:GetAttribute("inu"):Value(),
        presence = c:GetAttribute("prs"):Value(),
        heroicResource = { name = c:GetHeroicResourceName(), value = c:GetHeroicOrMaliceResources() or 0 },
        surges = c:try_get("surges", 0),
        victories = c:try_get("victories", 0),
    }
end

--- Stable string fingerprint of a stat snapshot, for change detection.
local function StatSignature(s)
    local hr = s.heroicResource or {}
    return table.concat({
        s.maxStamina, s.currentStamina, s.tempStamina, s.windedThreshold, s.dyingThreshold,
        s.recoveryValue, s.recoveriesMax, s.recoveriesUsed,
        s.speed, s.stability, s.disengage,
        s.might, s.agility, s.reason, s.intuition, s.presence,
        tostring(hr.name), tostring(hr.value), s.surges, s.victories,
    }, "|")
end

-- characterId -> last-sent stat signature. Lets the poll send only on change.
local lastStatSig = {}

--- Push the authoritative derived-stat snapshot to `session`'s Companion window and
--- record its signature so the poll won't immediately re-send the same values.
local function SendStatSnapshot(session)
    local token = ResolveCompanionToken(session)
    if token == nil then return end
    local stats = BuildStatSnapshot(token)
    lastStatSig[session.characterId] = StatSignature(stats)
    session:SendEvent("creature.stats", { characterId = session.characterId, stats = stats })
end

local POLL_INTERVAL = 0.3

-- Live-update poll: re-push a connected creature's stats whenever a value changes
-- (DMHub exposes no Lua event for aura-coverage / derived-stat changes). Sends only
-- on change (diffed via StatSignature), so the channel sees on-change traffic.
local function PollStatChanges()
    local cc = dmhub.companionChannel
    if cc ~= nil and cc:IsAvailable() then
        for _, session in ipairs(cc:GetSessions()) do
            if session:IsConnected() then
                local token = ResolveCompanionToken(session)
                if token ~= nil then
                    local stats = BuildStatSnapshot(token)
                    local sig = StatSignature(stats)
                    if lastStatSig[session.characterId] ~= sig then
                        lastStatSig[session.characterId] = sig
                        session:SendEvent("creature.stats", { characterId = session.characterId, stats = stats })
                    end
                end
            end
        end
    end
    dmhub.Schedule(POLL_INTERVAL, PollStatChanges)
end

-- Register once at load. `dmhub.companionChannel` is a core engine member, so it is
-- present by the time CodeMods load; guard defensively all the same.
if dmhub.companionChannel ~= nil then
    dmhub.companionChannel:OnCompanionConnected(function(session)
        SendCompanionAuraSnapshot(session)
        SendStatSnapshot(session)
    end)
    -- Start the live-update poll (covers already-connected sessions, and stat
    -- changes that have no Lua change event, e.g. aura coverage).
    dmhub.Schedule(POLL_INTERVAL, PollStatChanges)
end

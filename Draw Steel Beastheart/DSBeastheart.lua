local mod = dmhub.GetModLoading()

local CALL_RANGE_TILES = 3

--- Find a vacant on-map tile adjacent to the given token. Tiles already
--- occupied by tokens (other than ignoreToken) are skipped, as are tiles
--- the caster has no line of sight to (so the companion does not appear on
--- the far side of a wall). Returns nil if no vacant adjacent tile is found.
--- @param casterToken CharacterToken
--- @param ignoreToken CharacterToken|nil
--- @return Loc|nil
local function FindVacantAdjacentLoc(casterToken, ignoreToken)
    local origin = casterToken.loc
    local pierceWalls = casterToken.properties:GetPierceWalls()
    local candidates = origin:LocsInRadius(1)
    for _,loc in ipairs(candidates) do
        if (not loc:Equals(origin)) and loc.isOnMap then
            local tokens = dmhub.GetTokensAtLoc(loc)
            local occupied = false
            if tokens ~= nil then
                for _,t in ipairs(tokens) do
                    if t ~= ignoreToken and t ~= casterToken then
                        occupied = true
                        break
                    end
                end
            end
            if not occupied and casterToken:GetLineOfSight(loc, pierceWalls) > 0 then
                return loc
            end
        end
    end
    return nil
end

--- Wire a freshly-spawned companion token to its beastheart: same owner,
--- party, initiative grouping; record companionid on the beastheart.
--- Stamps companionBestiaryId on the spawned token so later Calls can detect
--- if the beastheart's chosen companion type has changed.
local function LinkCompanion(beastheartToken, companionToken, bestiaryId)
    companionToken.ownerId = beastheartToken.ownerId
    companionToken.summonerid = beastheartToken.charid
    companionToken.properties.initiativeGrouping = InitiativeQueue.GetInitiativeId(beastheartToken)
    companionToken.properties.companionBestiaryId = bestiaryId
    companionToken.partyid = beastheartToken.partyid
    companionToken:UploadToken("Summoned")

    beastheartToken:ModifyProperties{
        description = "Summoned a companion",
        execute = function()
            beastheartToken.properties.companionid = companionToken.charid
        end,
    }

    game.UpdateCharacterTokens()
end

--- Soft-release the beastheart's current companion (if any) so the next Call
--- spawns fresh. The companion token is despawned, not destroyed -- see
--- creature:ReleaseCompanion in DSCompanion.lua.
local function DespawnCompanion(beastheartToken)
    beastheartToken.properties:ReleaseCompanion(beastheartToken)
end

--- Bring the beastheart's companion to a vacant adjacent tile. If no companion
--- token currently exists, spawn one from the bestiary using the beastheart's
--- chosen companion type and link it. If a companion token already exists,
--- verify it matches the beastheart's currently-chosen companion type: if it
--- does, teleport it; if it does not (e.g. the player switched species), the
--- old companion is despawned and a fresh one is summoned.
local function CallCompanion(beastheartToken)
    if beastheartToken == nil or not beastheartToken.valid then return end

    local companionType = beastheartToken.properties:GetCompanionType()
    if companionType == nil then return end

    local companionToken = beastheartToken.properties:GetCompanionToken()
    if companionToken ~= nil then
        local stampedId = companionToken.properties:try_get("companionBestiaryId")
        if stampedId ~= companionType then
            DespawnCompanion(beastheartToken)
            companionToken = nil
        end
    end

    local destination = FindVacantAdjacentLoc(beastheartToken, companionToken)
    if destination == nil then
        return
    end

    if companionToken ~= nil then
        companionToken:Teleport(destination, false)
        return
    end

    local newToken = game.SpawnTokenFromBestiaryLocally(companionType, destination, {
        fitLocation = true,
    })
    if newToken == nil then return end

    LinkCompanion(beastheartToken, newToken, companionType)
end

--- Build the Companion section for the character details panel. It is hidden
--- (collapsed) for any creature that has no companion type chosen, and shows
--- the chosen companion's name otherwise. Refresh path is intentionally cheap
--- for the common no-companion case: a single GetCompanionType() call +
--- SetClass.
local function BuildCompanionSection()
    local m_token = nil

    local m_nameLabel = gui.Label{
        width = "auto",
        height = "auto",
        textAlignment = "left",
        fontSize = 16,
        color = "white",
        text = "",
    }

    local m_callButton
    m_callButton = gui.Button{
        classes = {"sizeXxs", "collapsed"},
        vmargin = 0,
        hmargin = 4,
        text = "Call",
        halign = "left",
        click = function(element)
            CallCompanion(m_token)
            element.parent:FireEvent("refreshCharacter", m_token)
        end,
    }

    local m_selectButton
    m_selectButton = gui.Button{
        classes = {"sizeXxs", "collapsed"},
        width = "auto",
        vmargin = 0,
        hmargin = 4,
        hpad = 3,
        text = "Select",
        halign = "left",
        click = function(element)
            if m_token == nil or not m_token.valid or m_token.properties == nil then return end
            local companionToken = m_token.properties:GetCompanionToken()
            if companionToken == nil or not companionToken.loc.isOnMap then return end
            dmhub.SelectToken(companionToken.charid)
            dmhub.CenterOnToken(companionToken.charid)
        end,
    }

    return TacPanel.CollapsiblePanel{
        sectionId = "companion",
        classes = {"collapsed"},
        altBg = false,
        title = "COMPANION",

        refreshCharacter = function(element, token)
            m_token = token
            if token == nil or not token.valid or token.properties == nil then
                element:SetClass("collapsed", true)
                return
            end

            local companionType = token.properties:GetCompanionType()
            if companionType == nil then
                element:SetClass("collapsed", true)
                return
            end

            local monster = assets.monsters[companionType]
            local name = (monster and monster.name) or "Companion"

            element:SetClass("collapsed", false)
            m_nameLabel.text = name

            local companionToken = token.properties:GetCompanionToken()
            local onMap = companionToken ~= nil and companionToken.loc.isOnMap
            local nearby = companionToken ~= nil
                and companionToken.loc:DistanceInTiles(token.loc) <= CALL_RANGE_TILES
            m_callButton:SetClass("collapsed", nearby)
            m_selectButton:SetClass("collapsed", not onMap)
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            m_nameLabel,
            m_callButton,
            m_selectButton,
        },
    }
end

TacPanel.RegisterSection("companion", BuildCompanionSection, {after = "persistentabilities"})

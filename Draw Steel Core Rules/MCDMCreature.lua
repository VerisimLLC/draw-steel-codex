local mod = dmhub.GetModLoading()

--- @field creature.minion boolean
creature.minion = false

--- @field creature.minionDead boolean
creature.minionDead = false

--- @field creature.initiativeGrouping false|string
creature.initiativeGrouping = false

--- @alias SquadInfo table


--- @field creature._tmp_minionSquad SquadInfo

function creature:MinionSquad()
    if self:has_key("minionSquad") then
        return self.minionSquad
    end

    if self.minion then
        return string.format("%s Squad 1", self.monster_type)
    end

    return nil
end

local g_baseInvalidate = creature.Invalidate
function creature:Invalidate()
    g_baseInvalidate(self)

    if mod.unloaded then
        return
    end

    self._tmp_calculatedAttributes = nil
    self._tmp_adjacentLocs = nil
    self._tmp_occupiedLocs = nil
    self._tmp_flankfromanydirection = nil
    self._tmp_grantsFlanking = nil
    self._tmp_highestCharacteristic = nil
    self._tmp_maxSurgeCount = nil
end

local g_creatureSingleMaxHitpoints = creature.MaxHitpoints
function creature.MaxHitpoints(self, modifiers)
    if (not mod.unloaded) and self.minion and self:has_key("_tmp_minionSquad") then
        local squad = self:MinionSquad()
        if squad ~= nil then
            local liveMinions = self._tmp_minionSquad.liveMinions or 0
            return liveMinions * g_creatureSingleMaxHitpoints(self)
        end
    end

    return g_creatureSingleMaxHitpoints(self, modifiers)
end

function creature:SingleMinionMaxStamina()
    return g_creatureSingleMaxHitpoints(self)
end

function creature:Potency()
    return self:HighestCharacteristic()
end

function creature:BaseNamedCustomAttribute(id)
    id = string.lower(id:gsub("%s+", ""))
    local customAttr = CustomAttribute.attributeInfoByLookupSymbol[id]
    if customAttr == nil then
        return 0
    end

    return customAttr:CalculateBaseValue(self)
end

function creature:DescribeModificationsToNamedCustomAttribute(id)
    id = string.lower(id:gsub("%s+", ""))
    local customAttr = CustomAttribute.attributeInfoByLookupSymbol[id]
    if customAttr == nil then
        return {}
    end

    local baseValue = customAttr:CalculateBaseValue(self)
    local result = self:DescribeModifications(customAttr.id, baseValue)
    return result
end

function creature:CalculateNamedCustomAttribute(id)
    local cacheKey = id
    local cache = self:try_get("_tmp_calculatedAttributes")
    if cache == nil then
        cache = {}
        self._tmp_calculatedAttributes = cache
    end

    local cachedValue = cache[cacheKey]
    if cachedValue ~= nil then
        return cachedValue
    end

    id = string.lower(id:gsub("%s+", ""))
    local customAttr = CustomAttribute.attributeInfoByLookupSymbol[id]
    if customAttr == nil then
        cache[cacheKey] = 0
        return 0
    end

    local result = self:GetCustomAttribute(customAttr)
    cache[cacheKey] = result
    return result
end

function creature:AllowNegativeResources()
    return self:CalculateNamedCustomAttribute("Negative Heroic Resource")
end

--@param attrid string
--@return number|nil
function creature:AttributeForPotencyResistance(attrid)
    local customAttr = CustomAttribute.attributeInfoByLookupSymbol
    [string.lower(creature.attributesInfo[attrid].description) .. "potencyresistance"]
    local value = nil
    if customAttr ~= nil then
        local result = self:GetCustomAttribute(customAttr)
        return result
    else
        local attr = self:GetAttribute(attrid)
        if attr ~= nil then
            return attr:Modifier()
        end
    end

    return nil
end

--@param attrid string
--@return { key: string, value: string}[]
function creature:AttributeForPotencyResistanceDescription(attrid)
    local customAttr = CustomAttribute.attributeInfoByLookupSymbol
    [string.lower(creature.attributesInfo[attrid].description) .. "potencyresistance"]
    if customAttr ~= nil then
        local baseValue = customAttr:CalculateBaseValue(self)
        local result = self:DescribeModifications(customAttr.id, baseValue)
        return result
    end

    return nil
end

function creature:CarefulMovementSpeed()
    local customAttr = CustomAttribute.attributeInfoByLookupSymbol["disengagespeed"]
    if customAttr ~= nil then
        local result = self:GetCustomAttribute(customAttr)
        return math.min(self:CurrentMovementSpeed(), result)
    end
    return math.min(self:CurrentMovementSpeed(), 1)
end

function creature:DescribeForcedMovementBonus(moveType)
    local result = {}

    for _, attrname in ipairs({ "Forced Movement Bonus", moveType .. " Bonus" }) do
        local mods = self:DescribeModificationsToNamedCustomAttribute(attrname)
        if mods ~= nil then
            for _, mod in ipairs(mods) do
                result[#result + 1] = mod
            end
        end
    end

    return result
end

function creature:ForcedMovementBonus(moveType)
    local result = 0

    local customAttr = CustomAttribute.attributeInfoByLookupSymbol["forcedmovementbonus"]
    if customAttr ~= nil then
        result = result + self:GetCustomAttribute(customAttr)
    end

    local customAttr = CustomAttribute.attributeInfoByLookupSymbol[moveType .. "bonus"]
    if customAttr ~= nil then
        result = result + self:GetCustomAttribute(customAttr)
    end

    return result
end

function creature:HighestCharacteristic()
    if not self:has_key("_tmp_highestCharacteristic") then
        local highest = nil
        for _, attrid in ipairs(creature.attributeIds) do
            local value = self:AttributeMod(attrid)
            if highest == nil or value > highest then
                highest = value
            end
        end

        self._tmp_highestCharacteristic = highest
    end

    return self._tmp_highestCharacteristic
end

function creature:ConsumeSurges(ncount, note)
    local surgeid = CharacterResource.nameToId["Surges"]
    if surgeid == nil then
        return
    end

    self:AddUnboundedResource(surgeid, -ncount, note or "Consumed Surges")
end

function creature:GetAvailableSurges()
    local surgeid = CharacterResource.nameToId["Surges"]
    if surgeid == nil then
        return 0
    end

    local result = self:GetUnboundedResourceQuantity(surgeid)
    return result
end

function creature:GetMaxSurgeCount()
    if not self:has_key("_tmp_maxSurgeCount") then
        local customAttr = CustomAttribute.attributeInfoByLookupSymbol["maximumsurges"]
        if customAttr == nil then
            self._tmp_maxSurgeCount = 3
        else
            self._tmp_maxSurgeCount = self:GetCustomAttribute(customAttr)
        end
    end

    return self._tmp_maxSurgeCount
end

local g_minionSquadTables = {}

local g_baseRefreshToken = creature.RefreshToken

function creature:GetFollowers()
    return {}
end

function character:GetFollowers()
    return self:get_or_add("followers", {})
end

creature._tmp_retainer = false
function creature:IsRetainer()
    return false
end

function monster:IsRetainer()
    return self:try_get("retainer", false)
end

function creature:Retainers()
    return {}
end

function character:Retainers()
    local retainers = {}
    local followers = self:GetFollowers()

    for _, follower in ipairs(followers) do
        if follower and follower.type == "retainer" then
            local retainerToken = dmhub.GetTokenById(follower.retainerToken)
            if retainerToken ~= nil then
                retainers[#retainers + 1] = retainerToken
            end
        end
    end

    return retainers
end

function creature:IsHero()
    return false
end

function character:IsHero()
    return true
end

function creature:GetMentor()
    return
end

function monster:GetMentor()
    local token = dmhub.LookupToken(self)
    if token == nil then
        return nil
    end
    local partyMembers = dmhub.GetCharacterIdsInParty(token.partyid) or {}

    for _, charid in pairs(partyMembers) do
        local charToken = dmhub.GetTokenById(charid)
        if charToken ~= nil then
            local followers = charToken.properties:GetFollowers()
            for _, follower in ipairs(followers) do
                if follower.retainerToken == token.charid then
                    return charToken.properties
                end
            end
        end
    end

    return
end

function creature:HeroicResourceHighWaterMarkForTurn()
    local quantity = 0

    local resources = self:try_get("resources")
    if resources ~= nil then
        local heroicResource = resources[CharacterResource.heroicResourceId]
        if heroicResource ~= nil then
            quantity = heroicResource.unbounded or 0
        end
    end

    if self:has_key("_tmp_heroicResourceTurnId") then
        local q = dmhub.initiativeQueue
        if q ~= nil and (not q.hidden) and q:GetTurnId() == self._tmp_heroicResourceTurnId then
            local currentHeroicResource = self:try_get("_tmp_heroicResourceForTurn") or 0
            return math.max(currentHeroicResource, quantity)
        end
    end

    return quantity
end

function creature:RefreshToken(token)
    if (not mod.unloaded) and self.minion then
        self:RefreshSquadInfo(token)
    end

    if (not mod.unloaded) then
        self:RefreshConditionCasterInfo(token)
    end

    if (not mod.unloaded) and (not self.minion) and self.initiativeGrouping then
        self:RefreshInitiativeGrouping(token)
    end

    if (not mod.unloaded) then
        self:RefreshBoundOngoingEffects(token)
    end

    if self:IsMonster() then
        self._tmp_retainer = token.playerControlled
    end

    -- Set up initiative grouping for retainers with their mentor
    -- Should this be moved to RefreshInitiativeGrouping?
    if (not mod.unloaded) and self:IsRetainer() then
        local mentor = self:GetMentor()
        if mentor then
            local mentorToken = dmhub.LookupToken(mentor)
            if mentorToken then
                local mentorInitiativeId = InitiativeQueue.GetInitiativeId(mentorToken)
                if self.initiativeGrouping ~= mentorInitiativeId then
                    self.initiativeGrouping = mentorInitiativeId
                end
            end
        end
    end

    g_baseRefreshToken(self, token)

    if self:IsHero() then
        --find this character's heroic resources high water mark for the turn.
        local resources = self:try_get("resources")
        if resources ~= nil then
            local heroicResource = resources[CharacterResource.heroicResourceId]
            if heroicResource ~= nil then
                local quantity = heroicResource.unbounded
                if quantity ~= nil then
                    local turnid = nil
                    local q = dmhub.initiativeQueue
                    if q ~= nil and not q.hidden then
                        local turnid = q:GetTurnId()
                        local currentTurnId = self:try_get("_tmp_heroicResourceTurnId")
                        if currentTurnId ~= turnid then
                            self._tmp_heroicResourceForTurn = 0
                            self._tmp_heroicResourceTurnId = turnid
                        end

                        local currentHeroicResource = self:try_get("_tmp_heroicResourceForTurn") or 0
                        if quantity > currentHeroicResource then
                            self._tmp_heroicResourceForTurn = quantity
                        end
                    end
                end
            end
        end
    end

    if not mod.unloaded then
        self:RefreshInitiativeInfo(token)

        local givesCoverAttr = CustomAttribute.LookupCustomAttributeBySymbol("givescover")
        if givesCoverAttr ~= nil then
            local givesCover = self:GetCustomAttribute(givesCoverAttr) or 0
            self._tmp_givesCover = givesCover > 0
        end
    end
end

function creature:RefreshInitiativeInfo(token)
    local q = dmhub.initiativeQueue
    if q == nil or q.hidden then
        self._tmp_initiativeStatus = nil
    else
        local initiativeid = InitiativeQueue.GetInitiativeId(token)
        local initiativeEntry = q:GetFirstInitiativeEntry()
        if initiativeEntry ~= nil and initiativeEntry.initiativeid == initiativeid then
            self._tmp_initiativeStatus = "OurTurn"
        elseif not q:HasInitiative(initiativeid) then
            self._tmp_initiativeStatus = "NonCombatant"
        elseif q:HasHadTurn(initiativeid) then
            self._tmp_initiativeStatus = "Done"
        elseif q:ChoosingTurn() and q:IsPlayersTurn() == q:IsEntryPlayer(initiativeid) and (q:has_key("priorityids") == false or q:EntriesUnmoved()[initiativeid]) then
            self._tmp_initiativeStatus = "ActiveAndReady"
        else
            self._tmp_initiativeStatus = "Active"
        end
    end
end

local g_groupIndex = 0
local g_lastGroupIdGameUpdate = nil
local g_lastGroupId = nil
local g_lastSquadId = nil
local g_lastSquadMonsterType = nil
local g_lastSquadGameUpdate = nil

local g_OnCreateFromBestiary = monster.OnCreateFromBestiary

function monster.OnCreateFromBestiary(self, token, groupid)
    g_OnCreateFromBestiary(self, token, groupid)

    if mod.unloaded then
        return
    end

    if g_lastGroupIdGameUpdate ~= dmhub.gameupdateid then
        g_groupIndex = 0
    end

    self.initiativeGrouping = groupid
    if groupid ~= g_lastGroupId then
        g_groupIndex = g_groupIndex + 1
    end

    --get the encounter this is being spawned from (if any).
    local assignToSquad = self.minion
    local encounter = dmhub.GetSelectedEncounter()
    if encounter ~= nil and (encounter.groups or {})[g_groupIndex] ~= nil then
        local group = encounter.groups[g_groupIndex]
        if group.minHeroes then
            --mark that this monster should only appear with that number of heroes.
            self.minHeroes = group.minHeroes
        end

        if not assignToSquad then
            --see if this is grouped with minions in which case make it a captain.
            for monsterid, _ in pairs(group.monsters or {}) do
                local monsterInfo = assets.monsters[monsterid]
                if monsterInfo ~= nil and monsterInfo.properties:IsMonster() and monsterInfo.properties.minion then
                    assignToSquad = true
                    break
                end
            end
        end
    end

    if assignToSquad then
        --clear out any squad information for minions.
        self.squadpos = nil

        if g_lastGroupId ~= groupid or g_lastSquadMonsterType ~= self.monster_type or g_lastSquadGameUpdate ~= dmhub.gameupdateid then
            --we are a new minion type or the game has been updated, so reset the last squad id.
            g_lastSquadId = nil
            g_lastSquadMonsterType = nil
            g_lastSquadGameUpdate = 0
        end

        --try to assign our minion to a fresh squad of undamaged minions.
        if g_lastSquadId == nil then
            g_lastSquadId = monster.FindFreshSquadName(self.monster_type)
        end

        self.minionSquad = g_lastSquadId
    end

    g_lastGroupId = groupid
    g_lastGroupIdGameUpdate = dmhub.gameupdateid
end

function monster.FindFreshSquadName(monster_type)
    for i = 1, 1000 do
        local squadid = string.format("%s Squad %d", monster_type, i)
        local minionSquad = g_minionSquadTables[squadid]
        if minionSquad == nil then
            g_minionSquadTables[squadid] = {
                name = squadid,
            }
            g_lastSquadId = squadid
            g_lastSquadMonsterType = monster_type
            g_lastSquadGameUpdate = dmhub.gameupdateid
            --this is a fresh squad to put our minion into.
            return squadid
        end
    end

    return "Squad"
end

--get info about the squad we are in.
function creature:GetMinionSquadInfo()
    local squadid = self:MinionSquad()
    if squadid == nil then
        return nil
    end

    return g_minionSquadTables[squadid]
end

-- When a minion dies, we see if we need to demote their captain.
function creature:MinionDeath()
    if self:has_key("_tmp_minionSquad") == false then
        return
    end

    if self._tmp_minionSquad.liveMinions > 1 then
        --we still have more minions so don't remove the captain yet.
        return
    end

    --there are no more minions in this squad. Try to remove the captain's status and destroy the squad.

    g_minionSquadTables[self:MinionSquad()] = nil

    local captain = self._tmp_minionSquad.captain
    if captain == nil or (not captain.valid) then
        return
    end

    captain:ModifyProperties {
        description = "Remove captain",
        undoable = false,
        combine = true,
        execute = function()
            captain.properties.minionSquad = nil
        end,
    }
end

--- Refresh info about the squad.
--- @param token CharacterToken
function creature:RefreshSquadInfo(token)
    if not self.minion then
        return
    end

    --create a shared table for our minion squad.
    local squad = self:MinionSquad()
    if self:has_key("_tmp_minionSquad") == false or self._tmp_minionSquad.name ~= squad then
        local minionSquad = g_minionSquadTables[squad]

        if minionSquad == nil then
            minionSquad = {
                name = squad,
            }
            g_minionSquadTables[squad] = minionSquad
        end

        self._tmp_minionSquad = minionSquad
    end

    if self._tmp_minionSquad.updateid ~= dmhub.gameupdateid then
        self._tmp_minionSquad.updateid = dmhub.gameupdateid
        self._tmp_minionSquad.tokens = {}
        self._tmp_minionSquad.captain = nil

        local squad = self:MinionSquad()
        local tokens = dmhub.GetTokens {
            haveProperties = true,
        }

        local liveMinions = 0
        local damage_taken_charid = self._tmp_minionSquad.damage_taken_charid or nil
        local damage_taken = self._tmp_minionSquad.damage_taken or 0
        local damage_taken_seq = self._tmp_minionSquad.damage_taken_seq or 0
        local damage_taken_minion_count = self._tmp_minionSquad.liveMinions or nil
        local damage_time = self._tmp_minionSquad.damage_time or 0
        local damage_time_pending = false
        local num_recently_damaged = 0

        for _, tok in ipairs(tokens) do
            if tok.properties:MinionSquad() == squad then
                if tok.properties.minion then
                    self._tmp_minionSquad.tokens[#self._tmp_minionSquad.tokens + 1] = tok
                    if (not tok.properties.minionDead) and tok.properties.minion then
                        liveMinions = liveMinions + 1
                    end

                    if tok.properties:has_key("squadpos") then
                        self._tmp_minionSquad.pos = tok.properties.squadpos
                    end

                    if damage_taken_charid and damage_taken_seq > 0 and damage_taken_charid == tok.charid and tok.properties:try_get("damage_taken_seq", 0) < damage_taken_seq then
                        --damage taken seq has gone down for this minion so some kind of revert has happened.
                        --rerun this entire function. This is a super rare event so okay to do this.
                        self._tmp_minionSquad.damage_taken_seq = nil
                        self._tmp_minionSquad.damage_taken_charid = nil
                        self:RefreshSquadInfo(token)
                        return
                    end

                    if tok.properties:has_key("damage_taken_seq") and tok.properties.damage_taken_seq > damage_taken_seq then
                        damage_taken_seq = tok.properties.damage_taken_seq
                        damage_taken = tok.properties.damage_taken
                        damage_taken_charid = tok.charid
                        damage_taken_minion_count = tok.properties:try_get("damage_taken_minion_count")
                    end

                    if damage_time_pending or type(tok.properties.minionDamageTime) ~= "number" then
                        damage_time_pending = true
                    elseif tok.properties.minionDamageTime >= damage_time then
                        damage_time = tok.properties.minionDamageTime
                        if tok.properties.minionDamageTime > damage_time then
                            num_recently_damaged = 0
                        end
                        num_recently_damaged = num_recently_damaged + 1
                    end
                else
                    self._tmp_minionSquad.captain = tok
                end
            end
        end

        if damage_taken_minion_count == nil then
            damage_taken_minion_count = liveMinions
        end

        local health_single = g_creatureSingleMaxHitpoints(self)

        if damage_taken_minion_count > liveMinions then
            damage_taken = damage_taken - (damage_taken_minion_count - liveMinions) * health_single
            if damage_taken < 0 then
                damage_taken = 0
            end
        end

        local newHasCaptain = self._tmp_minionSquad.captain ~= nil and self._tmp_minionSquad.captain.valid and
        (not self._tmp_minionSquad.captain.properties:IsDead())
        local needInvalidate = self._tmp_minionSquad.hasCaptain ~= newHasCaptain

        self._tmp_minionSquad.hasCaptain = newHasCaptain
        self._tmp_minionSquad.liveMinions = liveMinions
        self._tmp_minionSquad.health_single = health_single
        self._tmp_minionSquad.maximum_health = health_single * liveMinions
        self._tmp_minionSquad.damage_taken = damage_taken
        self._tmp_minionSquad.damage_taken_seq = damage_taken_seq
        self._tmp_minionSquad.damage_taken_charid = damage_taken_charid
        self._tmp_minionSquad.color = DrawSteelMinion.GetSquadColor(squad)
        self._tmp_minionSquad.damage_time = damage_time
        self._tmp_minionSquad.damage_time_pending = damage_time_pending
        self._tmp_minionSquad.num_recently_damaged = num_recently_damaged

        if needInvalidate then
            for _, tok in ipairs(self._tmp_minionSquad.tokens) do
                tok.properties:Invalidate()
            end
        end
    end

    if self._tmp_minionSquad.tokens[1].charid == token.charid then
        local onCurrentFloor = false
        local curFloor = dmhub.floorid
        for _, tok in ipairs(self._tmp_minionSquad.tokens) do
            if tok.valid and tok.floorid == curFloor then
                onCurrentFloor = true
                break
            end
        end
        if onCurrentFloor then
            DrawSteelMinion.SquadHud(curFloor, self._tmp_minionSquad)
        end
    end
end

--override moved and make it so when we move if we are pending initiative
--that indicates we automatically declare it our turn.
local g_baseMoved = creature.Moved
function creature:Moved(path)
    g_baseMoved(self, path)

    if mod.unloaded then
        return
    end

    --no longer make just moving auto claim turn?
    --self:TryClaimTurn()
end

--when using an action or a maneuver we also are claiming the turn if
local g_baseConsumeResource = creature.ConsumeResource
function creature:ConsumeResource(key, refreshType, quantity, note)
    g_baseConsumeResource(self, key, refreshType, quantity, note)

    if mod.unloaded then
        return
    end

    local resourceTable = dmhub.GetTable(CharacterResource.tableName)
    local resourceInfo = resourceTable[key]
    if resourceInfo ~= nil and (resourceInfo.name == "Action" or resourceInfo.name == "Maneuver") then
        self:TryClaimTurn()
    end
end

--function to claim our turn if we are ready to go for initiative.
function creature:TryClaimTurn()
    local token = dmhub.LookupToken(self)
    if token == nil then
        return
    end

    local q = dmhub.initiativeQueue
    if q ~= nil and (not q.hidden) then
        --if we are ready to go into initiative then assume this starts our turn.
        local initiativeid = InitiativeQueue.GetInitiativeId(token)
        local initiativeEntry = initiativeid == q:GetFirstInitiativeEntry()
        if q:HasInitiative(initiativeid) and (not q:HasHadTurn(initiativeid)) and q:ChoosingTurn() and q:IsPlayersTurn() == q:IsEntryPlayer(initiativeid) then
            q:SelectTurn(initiativeid)
            dmhub:UploadInitiativeQueue()
        end
    end
end

--- @return boolean
function creature:IsHero()
    return false
end

--- @return boolean
function character:IsHero()
    return true
end

--- @return Loc[]
function creature:OccupiedLocs()
    if rawget(self, "_tmp_occupiedLocs") == nil then
        local token = dmhub.LookupToken(self)
        if token ~= nil then
            self._tmp_occupiedLocs = token.locsOccupying
        else
            self._tmp_occupiedLocs = {}
        end
    end

    return self._tmp_occupiedLocs
end

--- @return Loc[]
function creature:AdjacentLocations()
    if rawget(self, "_tmp_adjacentLocsxx") == nil then
        local token = dmhub.LookupToken(self)
        if token ~= nil then
            self._tmp_adjacentLocs = MCDMLocUtils.GetTokenAdjacentLocsInOpposingPairs(token)
        else
            self._tmp_adjacentLocs = {}
        end
    end

    return self._tmp_adjacentLocs
end

CustomAttribute.RegisterAttribute {
    id = "flankfromanydirection",
    text = "Flank From Any Direction",
    attributeType = "number",
    category = "Basic Attributes",
}

function creature:FlankFromAnyDirection()
    local result = self:try_get("_tmp_flankfromanydirection")
    if result ~= nil then
        return result ~= 0
    end

    self._tmp_flankfromanydirection = self:CalculateAttribute("flankfromanydirection", 0)
    return self._tmp_flankfromanydirection ~= 0
end

creature.RegisterSymbol {
    symbol = "object",
    lookup = function(c)
        local token = dmhub.LookupToken(c)
        if token ~= nil and token.valid then
            return token.isObject
        end
        return false
    end,
    help = {
        name = "Object",
        type = "boolean",
        desc = "If this 'creature' is actually an object, this will be true.",
        seealso = {},
    },
}

creature.RegisterSymbol{
    symbol = "playerallied",
    lookup = function(c)
        local token = dmhub.LookupToken(c)
        if token ~= nil and token.valid and token.playerControlled then
            return true
        end

        local initiativeid = InitiativeQueue.GetInitiativeId(token)
        if initiativeid ~= nil and dmhub.initiativeQueue ~= nil and not dmhub.initiativeQueue.hidden then
            return dmhub.initiativeQueue:IsEntryPlayer(initiativeid)
        end

        return false
    end,
    help = {
        name = "Player Allied",
        type = "boolean",
        desc = "If this creature is a player or allied with the players this will be true.",
        seealso = {},
    },
}

creature.RegisterSymbol {
    symbol = "dying",
    lookup = function(c)
        return c:IsDying()
    end,
    help = {
        name = "Dying",
        type = "boolean",
        desc = "If this creature is dying this will be true.",
        seealso = {},
    },
}

creature.RegisterSymbol {
    symbol = "hero",
    lookup = function(c)
        return c:IsHero()
    end,
    help = {
        name = "Hero",
        type = "boolean",
        desc = "If this creature is a hero this will be true.",
        seealso = {},
    },
}

creature.RegisterSymbol {
    symbol = "heroicresourcesavailabletospend",
    lookup = function(c)
        return c:GetHeroicOrMaliceResourcesAvailableToSpend()
    end,
    help = {
        name = "Heroic Resources Available to Spend",
        type = "number",
        desc = "The number of heroic resources this creature has available to spend. It accounts for things like the Talent's resources being able to be negative.",
        seealso = { "Resources" },
    }
}


creature.RegisterSymbol {
    symbol = "heroicresourcesthisturn",
    lookup = function(c)
        return c:HeroicResourceHighWaterMarkForTurn()
    end,
    help = {
        name = "Heroic Resources This Turn",
        type = "number",
        desc = "The highest number of heroic resources this creature has had this turn. This is the high water mark for the turn and will not go down until the next turn.",
        seealso = { "Resources" },
    }
}

creature.RegisterSymbol {
    symbol = "retainer",
    lookup = function(c)
        return c:IsRetainer()
    end,
    help = {
        name = "Retainer",
        type = "boolean",
        desc = "If this creature is a retainer, this will be true.",
        seealso = {},
    },
}

creature.RegisterSymbol {
    symbol = "mentor",
    lookup = function(c)
        return c:GetMentor()
    end,
    help = {
        name = "Mentor",
        type = "creature",
        desc = "The mentor of this Retainer. Only valid if Retainer is true.",
        seealso = {},
    },
}

function creature:RecoveriesAvailableToSpend()

	local usage = self:GetResourceUsage(CharacterResource.recoveryResourceId, "long") or 0
	local max = self:GetResources()[CharacterResource.recoveryResourceId] or 0
	local quantity = max - usage

    local recoverySharing = self:ShareRecoveriesWith()
    if recoverySharing ~= nil then
        local mytoken = dmhub.LookupToken(self)
        for i,token in ipairs(recoverySharing) do
            if mytoken and token.charid ~= mytoken.charid then
                local usage = token.properties:GetResourceUsage(CharacterResource.recoveryResourceId, "long") or 0
                local max = token.properties:GetResources()[CharacterResource.recoveryResourceId] or 0
                quantity = quantity + (max - usage)
            end
        end
    end

    return quantity
end

function creature:CalcuatePotencyValue(potency)
    return self:CalculatePotencyValue(potency)
end

function creature:CalculatePotencyValue(potency)
    local potencyBonus = self:CalculateNamedCustomAttribute("Potency Bonus")
    if tonumber(potency) ~= nil then
        return tonumber(potency) + potencyBonus
    end
    local potencyValue = self:Potency()
    if potency ~= nil then
        local potencyType = string.lower(potency)
        if potencyType == "weak" then
            return potencyValue - 2 + potencyBonus
        elseif potencyType == "average" then
            return potencyValue - 1 + potencyBonus
        elseif potencyType == "strong" then
            return potencyValue + potencyBonus
        end
    end
    return potencyValue + potencyBonus
end

creature.RegisterSymbol{
    symbol = "recoveriesavailabletospend",
    lookup = function(c)
        return c:RecoveriesAvailableToSpend()
    end,
    help = {
        name = "Recoveries Available to Spend",
        type = "number",
        desc = "The number of recoveries this creature has available to spend. It accounts for things like Bloodbound Band allowing use of other hero's recoveries.",
        seealso = { "Resources" },
    }
}

creature.RegisterSymbol {
    symbol = "dead",
    lookup = function(c)
        return c:IsDead()
    end,
    help = {
        name = "Dead",
        type = "boolean",
        desc = "If this creature is dead this will be true.",
        seealso = {},
    }
}

creature.RegisterSymbol {
    symbol = "hascaptain",
    lookup = function(c)
        return c.minion and c:has_key("_tmp_minionSquad") and c._tmp_minionSquad.captain ~= nil and
        c._tmp_minionSquad.captain.valid and (not c._tmp_minionSquad.captain.properties:IsDead())
    end,
    help = {
        name = "HasCaptain",
        type = "boolean",
        desc = "If this creature is a minion and the squad they are in has a captain this will be true.",
        seealso = {},
    }
}

creature.RegisterSymbol {
    symbol = "squadcaptain",
    lookup = function(c)
        return c.minion and c:has_key("_tmp_minionSquad") and c._tmp_minionSquad.captain ~= nil and
        c._tmp_minionSquad.captain.valid and (not c._tmp_minionSquad.captain.properties:IsDead()) and
        c._tmp_minionSquad.captain.properties
    end,
    help = {
        name = "Squad Captain",
        type = "creature",
        desc = "If we have a captain, this will return the captain of the squad this creature is a member of.",
        seealso = {},
    }
}

creature.RegisterSymbol {
    symbol = "takenturnthisround",
    lookup = function(c)
        local q = dmhub.initiativeQueue
        if q == nil or q.hidden then
            return false
        end

        local tok = dmhub.LookupToken(c)
        if tok == nil or (not tok.valid) then
            return false
        end

        local initiativeid = q.GetInitiativeId(tok)
        return q:HasHadTurn(initiativeid)
    end,
}

creature.RegisterSymbol {
    symbol = "passespotency",
    lookup = function(c)
        return function(characteristicid, val)
            if type(characteristicid) ~= "string" then
                return false
            end
            if type(val) ~= "number" then
                val = 0
            end
            local attrid = GameSystem.AttributeByFirstLetter[string.lower(characteristicid)] or "-"
            local result = (c:AttributeForPotencyResistance(attrid) or 0) >= (val or 0)
            return result
        end
    end,

    help = {
        name = "Passes Potency",
        type = "function",
        desc = "Given a characteristic id and a potency value, returns true if this creature passes the potency check for that characteristic.",
    },
}

creature.RegisterSymbol {
    symbol = "weak",
    lookup = function(c)
        return c:CalculatePotencyValue("Weak")
    end,
    help = {
        name = "Weak",
        type = "number",
        desc = "This creature's weak potency. Equal to their highest characteristic - 2.",
    }
}

creature.RegisterSymbol {
    symbol = "average",
    lookup = function(c)
        return c:CalculatePotencyValue("Average")
    end,
    help = {
        name = "Average",
        type = "number",
        desc = "This creature's average potency. Equal to their highest characteristic - 1.",
    }
}

creature.RegisterSymbol {
    symbol = "strong",
    lookup = function(c)
        return c:CalculatePotencyValue("Strong")
    end,
    help = {
        name = "Strong",
        type = "number",
        desc = "This creature's strong potency. Equal to their highest characteristic.",
    }
}

creature.RegisterSymbol {
    symbol = "highestcharacteristic",
    lookup = function(c)
        return c:HighestCharacteristic()
    end,
    help = {
        name = "Highest Characteristic",
        type = "number",
        desc = "This creature's highest characteristic. This is the highest of their characteristics.",
    },
}

creature.RegisterSymbol {
    symbol = "captain",
    lookup = function(c)
        return (not c.minion) and c:has_key("_tmp_minionSquad")
    end,
    help = {
        name = "Captain",
        type = "boolean",
        desc = "Is this creature a captain of a squad?",
        seealso = {},
    }
}

creature.RegisterSymbol {
    symbol = "minion",
    lookup = function(c)
        return c.minion
    end,
    help = {
        name = "Minion",
        type = "boolean",
        desc = "Is this creature a minion?",
        seealso = {},
    }
}

creature.RegisterSymbol {
    symbol = "solo",
    lookup = function(c)
        return string.find(string.lower(c:try_get("role", "")), "solo") ~= nil
    end,
    help = {
        name = "Solo",
        type = "boolean",
        desc = "Is this creature a solo?",
        seealso = {},
    }
}

creature.RegisterSymbol {
    symbol = "saveendseffects",
    lookup = function(c)
        if c:has_key("inflictedConditions") then
            local conditions = c.inflictedConditions
            for _, cond in ipairs(conditions) do
                if cond.duration == "save" then
                    return true
                end
            end
        end

        return false
    end,
    help = {
        name = "Save Ends Effects",
        type = "boolean",
        desc = "Does this creature have any save ends effects?",
    }
}

creature.RegisterSymbol {
    symbol = "leader",
    lookup = function(c)
        return string.find(string.lower(c:try_get("role", "")), "leader") ~= nil
    end,
    help = {
        name = "Leader",
        type = "boolean",
        desc = "Is this creature a leader?",
        seealso = {},
    }
}

creature.RegisterSymbol {
    symbol = "flankedby",
    lookup = function(c)
        return function(otherCreature, secondCreature)
            if otherCreature == secondCreature then
                return false
            end
            local tok = dmhub.LookupToken(otherCreature)
            if tok == nil then
                return false
            end
            if not c:FlankedBy(tok) then
                return false
            end

            if secondCreature ~= nil then
                local secondTok = dmhub.LookupToken(secondCreature)
                if secondTok == nil then
                    return false
                end

                if not c:FlankedBy(secondTok) then
                    return false
                end

                if #c:GetFlankingTokens({ tok, secondTok }) < 2 then
                    return false
                end
            end

            return true
        end
    end,

    help = {
        name = "Flanked By",
        type = "function",
        desc = "Given another creature, tells us if this creature is flanked by that creature. Can be given two creatures in which case it will return true if those two creatures are co-flanking this creature (They must not only be flanking but be flanking with each other).",
        seealso = {},
    },
}

creature.RegisterSymbol {
    symbol = "flanked",
    lookup = function(c)
        return #c:GetFlankingTokens() > 0
    end,

    help = {
        name = "Flanked",
        type = "boolean",
        desc = "Returns true if this creature is currently being flanked.",
        seealso = {},
    },
}

creature.RegisterSymbol {
    symbol = "immunities",
    lookup = function(c)
        return function(damageType)
            if damageType == nil then
                return 0
            end
            local immunities = c:DamageResistance(damageType, {})
            if immunities and immunities.dr ~= nil then
                return tonumber(immunities.dr) or 0
            end
            return 0
        end
    end,
    help = {
        name = "Immunities",
        type = "function",
        desc = "Given a damage type, will return a creatures total immunity. Will provide a negative when they have a weakness.",
        examples = {'Target.Immunities("Fire") > 5'},
    },
}


local function GetEnemyCreaturesAtLoc(token, allowedTokenIds, loc, result)
    local tokensAtLoc = dmhub.GetTokensAtLoc(loc)
    if tokensAtLoc ~= nil then
        for _, otherTok in ipairs(tokensAtLoc) do
            if token.charid ~= otherTok.charid and (allowedTokenIds == nil or allowedTokenIds[otherTok.charid]) and token:IsFriend(otherTok) == false and otherTok:GetLineOfSight(token) > 0 and (not otherTok.properties:IsDead()) then
                local alreadyFound = false
                for _, existing in ipairs(result) do
                    if existing.charid == otherTok.charid then
                        alreadyFound = true
                        break
                    end
                end

                if not alreadyFound then
                    result[#result + 1] = otherTok
                end
            end
        end
    end
end

local function GetFlankingCreaturesFromOpposingSides(token, allowedTokenIds, locs_a, locs_b, result)
    local enemies_a = {}
    local enemies_b = {}
    for _, loc in ipairs(locs_a) do
        GetEnemyCreaturesAtLoc(token, allowedTokenIds, loc, enemies_a)
    end

    if #enemies_a == 0 then
        return
    end

    for _, loc in ipairs(locs_b) do
        GetEnemyCreaturesAtLoc(token, allowedTokenIds, loc, enemies_b)
    end

    if #enemies_b == 0 then
        return
    end

    if #enemies_a == 1 and #enemies_b == 1 and enemies_a[1].charid == enemies_b[1].charid then
        return
    end

    for _, a in ipairs(enemies_a) do
        local alreadyFound = false
        for _, b in ipairs(result) do
            if a.charid == b.charid then
                alreadyFound = true
                break
            end
        end
        if not alreadyFound then
            result[#result + 1] = a
        end
    end

    for _, a in ipairs(enemies_b) do
        local alreadyFound = false
        for _, b in ipairs(result) do
            if a.charid == b.charid then
                alreadyFound = true
                break
            end
        end
        if not alreadyFound then
            result[#result + 1] = a
        end
    end
end

local function GetLocsAdjacentToToken(token)
    local locs = token.locsOccupying
    if locs == nil or #locs == 0 then
        return {}
    end
    local topLeft = locs[1]
    local bottomRight = locs[1]

    for _, loc in ipairs(locs) do
        if loc.x < topLeft.x or loc.y < topLeft.y then
            topLeft = loc
        end

        if loc.x > bottomRight.x or loc.y > bottomRight.y then
            bottomRight = loc
        end
    end

    topLeft = topLeft:dir(-1, -1)
    bottomRight = bottomRight:dir(1, 1)

    local w = bottomRight.x - topLeft.x
    local h = bottomRight.y - topLeft.y

    local result = {}

    local p = topLeft
    for i = 1, w do
        result[#result + 1] = p
        p = p:dir(1, 0)
    end

    for i = 1, h do
        result[#result + 1] = p
        p = p:dir(0, 1)
    end

    for i = 1, w do
        result[#result + 1] = p
        p = p:dir(-1, 0)
    end

    for i = 1, h do
        result[#result + 1] = p
        p = p:dir(0, -1)
    end

    result[#result + 1] = p

    return result
end

local function GetEnemiesAdjacentToToken(token)
    local locs = GetLocsAdjacentToToken(token)
    local result = {}
    for _, loc in ipairs(locs) do
        GetEnemyCreaturesAtLoc(token, nil, loc, result)
    end

    return result
end

function creature:GetFlankingTokens(tokensOverride)
    local token = dmhub.LookupToken(self)
    if token == nil or (not token.valid) then
        return {}
    end

    if self:ImmuneFromFlanking() then
        return {}
    end

    local adjacentEnemies = tokensOverride or GetEnemiesAdjacentToToken(token)
    if #adjacentEnemies <= 1 then
        return {}
    end

    --remove any enemies that we don't have line of sight to or that can't grant flanking.
    for i = #adjacentEnemies, 1, -1 do
        local los = adjacentEnemies[i]:GetLineOfSight(token)
        if los <= 0 or not adjacentEnemies[i].properties:CanGrantFlanking() then
            table.remove(adjacentEnemies, i)
        end
    end

    if #adjacentEnemies <= 1 then
        return {}
    end

    for _, enemy in ipairs(adjacentEnemies) do
        local allflanking = enemy.properties:FlankFromAnyDirection()
        if allflanking then
            return adjacentEnemies
        end
    end

    local grantedFlanking = {}
    for i, enemy in ipairs(adjacentEnemies) do
        local grantFlanking = enemy.properties:GrantFlankingToAllies()
        if grantFlanking then
            grantedFlanking = DeepCopy(adjacentEnemies)
            grantedFlanking[i].properties._tmp_grantsFlanking = token.charid
        end
    end

    local allowedTokenIds = {}
    for _, enemy in ipairs(adjacentEnemies) do
        allowedTokenIds[enemy.charid] = true
    end

    local result = {}

    local locs = token.locsOccupying
    local topLeft = locs[1]
    local bottomRight = locs[1]

    for _, loc in ipairs(locs) do
        if loc.x < topLeft.x or loc.y < topLeft.y then
            topLeft = loc
        end

        if loc.x > bottomRight.x or loc.y > bottomRight.y then
            bottomRight = loc
        end
    end

    topLeft = topLeft:dir(-1, -1)
    bottomRight = bottomRight:dir(1, 1)

    GetFlankingCreaturesFromOpposingSides(token, allowedTokenIds, { topLeft }, { bottomRight }, result)
    GetFlankingCreaturesFromOpposingSides(token, allowedTokenIds, { topLeft:dir(bottomRight.x - topLeft.x) },
        { bottomRight:dir(topLeft.x - bottomRight.x) }, result)

    local topLocs = {}
    local botLocs = {}
    for i = 1, bottomRight.x - topLeft.x - 1 do
        topLocs[#topLocs + 1] = topLeft:dir(i, 0)
        botLocs[#botLocs + 1] = bottomRight:dir(-i, 0)
    end

    GetFlankingCreaturesFromOpposingSides(token, allowedTokenIds, topLocs, botLocs, result)

    local leftLocs = {}
    local rightLocs = {}
    for i = 1, bottomRight.y - topLeft.y - 1 do
        leftLocs[#leftLocs + 1] = topLeft:dir(0, i)
        rightLocs[#rightLocs + 1] = bottomRight:dir(0, -i)
    end

    GetFlankingCreaturesFromOpposingSides(token, allowedTokenIds, leftLocs, rightLocs, result)

    for _, enemy in ipairs(grantedFlanking) do
        local found = false
        for _, tok in ipairs(result) do
            if tok.charid == enemy.charid then
                found = true
                enemy.properties._tmp_grantsFlanking = nil
                break
            end
        end
        if not found then
            result[#result + 1] = enemy
        end
    end

    return result
end

function creature:FlankedBy(otherToken)
    local token = dmhub.LookupToken(self)
    local flanking = self:GetFlankingTokens()
    for _, tok in ipairs(flanking) do
        if tok.properties:try_get("_tmp_grantsFlanking", "") ~= token.charid and tok.charid == otherToken.charid then
            return true
        end
    end

    return false
end

function creature:CanGrantFlanking()
    return self:CanUseTriggeredAbilities() and self:CalculateNamedCustomAttribute("Cannot Grant Flanking") == 0
end

function creature:ImmuneFromFlanking()
    local flankingAttr = CustomAttribute.LookupCustomAttributeBySymbol("flankingimmunity")
    if flankingAttr == nil then
        return false
    end
    return (self:GetCustomAttribute(flankingAttr) or 0) >= 1
end

function creature:GrantFlankingToAllies()
    return self:CalculateNamedCustomAttribute("Grant Flanking to Allies") > 0
end

function creature:Echelon()
    return math.min(4, math.ceil(self:CharacterLevel() / 3))
end

function creature:Keywords()
    return {}
end

function creature:GetNumDeathSavingThrowSuccesses()
    return 0
end

function creature:GetNumDeathSavingThrowFailures()
    return 0
end

--- @return boolean
function creature:IsDeadOrDying()
    return self:IsDead()
end

--- @return boolean
function creature:IsDying()
    return false
end

--- @return boolean
function creature:IsDown()
    return self:IsDead()
end

--- @return boolean
function character:IsDead()
    return self:CurrentHitpoints() <= -self:BloodiedThreshold()
end

--- @return boolean
function monster:IsDead()
    return self:CurrentHitpoints() <= 0
end

CustomAttribute.RegisterAttribute { id = "extraturns", text = "Extra Turns", attributeType = "number", category = "Basic Attributes" }

function creature:TurnsPerRound()
    return 1 + self:CalculateAttribute("extraturns", 0)
end

CustomAttribute.RegisterAttribute { id = "forcedmoveresistance", text = "Stability", attributeType = "number", category = "Forced Movement" }

--- @return number
function creature:BaseForcedMoveResistance()
    return self.stability
end

--- @return number
function creature:BaseReach()
    return self.reach
end

--- @return number
function creature:BaseWeight()
    return self.weight
end

--- @return number
function creature:Stability()
    return math.tointeger(math.max(0, self:CalculateAttribute("forcedmoveresistance", self:BaseForcedMoveResistance())))
end

--- If the creature can teleport.
--- @return boolean
function creature:CanTeleport()
    local movementSpeeds = self:try_get("movementSpeeds", {})
    if movementSpeeds ~= nil then
        return (movementSpeeds["teleport"] or 0) > 0
    end

    return false
end

creature.stability = 0
creature.reach = 1
creature.range = 0
creature.weight = 1
creature.creatureSize = "1M"

CustomAttribute.RegisterAttribute { id = "creaturesizewhenforcemoved", text = "Size When Force Moved", attributeType = "number", category = "Forced Movement" }

function creature:CreatureSizeWhenBeingForceMoved()
    local token = dmhub.LookupToken(self)
    local size = 3
    if token ~= nil and token.valid then
        size = token.creatureSizeNumber
    else
        size = self:GetBaseCreatureSizeNumber() or size
    end

    return self:CalculateAttribute("creaturesizewhenforcemoved", size)
end

creature.RegisterSymbol {
    symbol = "sizewhenforcemoved",
    lookup = function(c)
        return c:CreatureSizeWhenBeingForceMoved()
    end,
    help = {
        name = "SizeWhenForceMoved",
        type = "number",
        desc = "The size of the creature when force moved.",
        seealso = {},
    }
}

CustomAttribute.RegisterAttribute { id = "reach", text = "Reach", attributeType = "number", category = "Combat" }
function creature:GetReach()
    return self:CalculateAttribute("reach", self:BaseReach())
end

function creature:BonusRange()
    local customAttr = CustomAttribute.attributeInfoByLookupSymbol.bonusrange
    if customAttr ~= nil then
        return self:GetCustomAttribute(customAttr)
    end

    return 0
end

creature.RegisterSymbol {
    symbol = "aurasaffecting",
    lookup = function(c)
        local result = {}
        local token = dmhub.LookupToken(c)
        if token == nil then
            return StringSet.new {
                strings = result,
            }
        end

        local aurasTouching = token.properties:GetAurasAffecting(token) or {}
        for i, info in ipairs(aurasTouching) do
            result[#result + 1] = info.auraInstance.aura.name
        end

        return StringSet.new {
            strings = result,
        }
    end,
    help = {
        name = "Auras Affecting",
        type = "set",
        desc = "The names of auras affecting this creature.",
        seealso = {},
    }
}

creature.RegisterSymbol {
    symbol = "aurascaster",
    lookup = function(c)
        return function(auraname)
			auraname = string.lower(auraname)
            local token = dmhub.LookupToken(c)

            if token then
                local aurasTouching = token.properties:GetAurasAffecting(token) or {}
                for i, info in ipairs(aurasTouching) do
                    if string.lower(info.auraInstance.aura.name) == auraname and info.auraInstance.casterid then
                        local casterToken = dmhub.GetTokenById(info.auraInstance.casterid)
                        print("Caster::", creature.GetTokenDescription(casterToken))
                        if casterToken ~= nil then
                            return casterToken.properties
                        end
                    end
                end
            end
            return
        end
    end,
    help = {
        name = "AurasCaster",
        type = "function",
        desc = "Given the name of an aura will return the creature that's controlling it.",
        seealso = {},
    }
}

creature.RegisterSymbol {
    symbol = "reach",
    lookup = function(c)
        return c:GetReach()
    end,
    help = {
        name = "Reach",
        type = "number",
        desc = "The reach of the creature.",
        seealso = {},
    }
}

CustomAttribute.RegisterAttribute { id = "weight", text = "Weight", attributeType = "number", category = "Basic Attributes" }

creature.RegisterSymbol {
    symbol = "weight",
    lookup = function(c)
        return c:GetWeight()
    end,
    help = {
        name = "Weight",
        type = "number",
        desc = "The weight of the creature.",
        seealso = {},
    }
}

function creature:GetWeight()
    return self:CalculateAttribute("weight", self:BaseWeight())
end

function creature:GrappleTN()
    return 7 + self:CalculateAttribute("mgt", 0)
end

function creature:BloodiedThreshold()
    return math.floor(self:MaxHitpoints() / 2)
end

CustomAttribute.RegisterAttribute { id = "recoveryvalue", text = "Recovery Value", attributeType = "number", category = "Basic Attributes" }

creature.RegisterSymbol {
    symbol = "recoveryvalue",
    lookup = function(c)
        return c:RecoveryAmount()
    end,
    help = {
        name = "Recovery Value",
        type = "number",
        desc = "The Recovery Value of the creature.",
        seealso = {},
    }
}

creature.RegisterSymbol {
    symbol = "stamina",
    lookup = function(c)
        return c:CurrentHitpoints()
    end,
    help = {
        name = "Stamina",
        type = "number",
        desc = "The Stamina of the creature.",
        seealso = { "Maximum Stamina", "Recovery Value" },
    }
}

creature.RegisterSymbol {
    symbol = "maximumstamina",
    lookup = function(c)
        return c:MaxHitpoints()
    end,
    help = {
        name = "Maximum Stamina",
        type = "number",
        desc = "The Maximum Stamina of the creature.",
        seealso = { "Stamina", "Recovery Value" },
    }
}

function creature:RecoveryAmount()
    local baseValue = math.floor(self:MaxHitpoints() / 3)
    return self:CalculateAttribute("recoveryvalue", baseValue)
end

function creature.ResistanceEntries(self)
    local entries = self:CalculateResistances()
    if #entries <= 0 then
        return {}
    end

    local items = {}

    --handle damage reduction portion.
    local damageReductionEntries = {}
    for _, entry in ipairs(entries) do
        if entry.apply == 'Damage Reduction' then
            local keywordDescription = "Damage"

            if entry:try_get("keywords") ~= nil then
                for keyword, _ in pairs(entry.keywords) do
                    if keywordDescription == "Damage" then
                        keywordDescription = keyword
                    else
                        keywordDescription = keywordDescription .. "/" .. keyword
                    end
                end
            end

            local damageTypeDescription = ""

            if entry:has_key("damageType") and string.lower(entry.damageType) ~= "all" then
                damageTypeDescription = entry.damageType .. " "
            end

            --upper case the first character of damage type description.
            if damageTypeDescription ~= "" then
                damageTypeDescription = string.upper(string.sub(damageTypeDescription, 1, 1)) ..
                string.sub(damageTypeDescription, 2)
            end

            items[#items + 1] = {
                text = string.format("%s%s %s %d.", damageTypeDescription, keywordDescription,
                    cond(entry:try_get("dr", 0) < 0, "weakness", "immunity"), math.abs(entry:try_get("dr", 0))),
                entry = entry,
            }
        end
    end

    return items
end

function creature.ResistanceDescription(self)
    local result = ""
    for _, entry in ipairs(self:ResistanceEntries()) do
        if result ~= "" then
            result = result .. "\n"
        end
        result = result .. entry.text
    end

    return result
end

function creature:AbilityCategorySingular(abilityCategory)
    return abilityCategory
end

function character:AbilityCategorySingular(abilityCategory)
    if abilityCategory == "Basic Attack" then
        return "Free Strike"
    end

    return abilityCategory
end

function creature:AbilityCategoryPlural(abilityCategory)
    return abilityCategory
end

function character:AbilityCategoryPlural(abilityCategory)
    if abilityCategory == "Basic Attack" then
        return "Free Strikes"
    end

    if abilityCategory == "Ability" then
        return "Abilities"
    end

    local classes = self:GetClassesAndSubClasses()
    if #classes > 0 then
        local entry = classes[1].class:try_get("abilityCategoryNames", {})[abilityCategory]
        if entry ~= nil then
            return entry.plural or abilityCategory
        end
    end

    return abilityCategory
end

function creature:GetResourceName(resourceid)
    if resourceid == CharacterResource.heroicResourceId then
        return self:GetHeroicResourceName()
    end

    local resourceTable = dmhub.GetTable("characterResources") or {}
    local resource = resourceTable[resourceid]
    return resource.name
end

function character:GetClass()
    local classes = self:try_get("classes")
    if classes == nil or #classes == 0 then
        return nil
    end

    local classesTable = dmhub.GetTable('classes')
    return classesTable[classes[1].classId]
end

function creature:GetSubclasses()
    return {}
end

function character:GetSubclasses()
    local result = {}
    local classes = self:GetClassesAndSubClasses()
    for i, entry in ipairs(classes) do
        if entry.class.isSubclass then
            result[#result + 1] = entry.class
        end
    end

    return result
end

function creature:GetHeroicResourceName()
    return "Heroic Resource"
end

function monster:GetHeroicResourceName()
    return "Malice"
end

function character:GetHeroicResourceName()
    local classInfo = self:GetClass()
    if classInfo ~= nil then
        return classInfo.heroicResourceName
    end

    return "Heroic Resource"
end

function creature:GetHeroicOrMaliceId()
    return CharacterResource.heroicResourceId
end

function character:GetHeroicOrMaliceId()
    return CharacterResource.heroicResourceId
end

function monster:GetHeroicOrMaliceId()
    return CharacterResource.maliceResourceId
end

function creature:IsHero()
    return false
end

function character:IsHero()
    return true
end

function creature:IsStrained()
    return self:CalculateNamedCustomAttribute("Strained") > 0
end

--We modify the important GetActivatedAbilities function.
--options:
--  excludeGlobal: no global modifiers.
--  bindCaster: make sure the abilities all have _tmp_boundCaster set so they can resolve who their caster is.
--  allLoadouts: get abilities from all loadouts, not just the equipped loadout.
--  characterSheet: is getting for display on character sheets.
--  manualTriggers: gets the manual version of triggered abilities.
--
--An important property is that innate abilities are not clones unless bindCaster is true. This allows the character sheet
--and other parts of the app to modify the innate abilities to update the creature.
local g_defaultExcludeKeywords = { "Companion" }
function creature:GetActivatedAbilities(options)
    options = options or {}

    local excludeKeywords = options.excludeKeywords or g_defaultExcludeKeywords

    local result = {}

    local boundCaster = self
    if not options.bindCaster then
        boundCaster = nil
    end

    self:FillMonsterActivatedAbilities(options, result)

    local kit = self:Kit()
    if kit ~= nil then
        for _, a in ipairs(kit:SignatureAbilities()) do
            local ability = a
            if options.bindCaster and (not options.characterSheet) then
                ability = ability:MakeTemporaryClone()
                ability._tmp_boundCaster = self
            end
            result[#result + 1] = ability
        end
    end

    for i, a in ipairs(self.innateActivatedAbilities) do
        local ability = a
        if options.bindCaster and (not options.characterSheet) then
            ability = ability:MakeTemporaryClone()
            ability._tmp_boundCaster = self
        end
        result[#result + 1] = ability
    end

    local modifiers = self:GetActiveModifiers()

    for i, mod in ipairs(modifiers) do
        if (not mod._global) or (not options.excludeGlobal) then
            mod.mod:FillActivatedAbilities(mod, self, result)
        end
    end
    
    if self:has_key("ongoingEffects") then
        for i, cond in ipairs(self.ongoingEffects) do
            if cond:try_get('endAbility') ~= nil and not cond:Expired() then
                result[#result + 1] = cond.endAbility
            elseif cond:try_get("stolenAbility") ~= nil and not cond:Expired() then
                result[#result + 1] = cond.stolenAbility
            end
        end
    end

    for i, aura in ipairs(self:try_get("auras", {})) do
        --aura:FillActivatedAbilities(self, result)
    end

    if options.manualTriggers then
        local triggeredAbilities = self:GetTriggeredAbilities()
        for i, trigger in ipairs(triggeredAbilities) do
            if trigger.ability:try_get("hasManualVersion", false) then
                --- @type TriggeredAbility
                local ability = trigger.ability:GenerateManualVersion()
                result[#result + 1] = ability
            end
        end
    end

    --lookup any objects existing with affinity to our character (e.g. auras we control) and see if they provide us with abilities.
    local charid = dmhub.LookupTokenId(self)
    if charid ~= nil then
        local objects = game.GetObjectsWithAffinityToCharacter(charid)
        for _, obj in ipairs(objects) do
            for _, entry in ipairs(obj.attachedRulesObjects) do
                entry:FillActivatedAbilities(self, result)
            end
        end
    end

    local gearTable = dmhub.GetTable('tbl_Gear')
    for k, info in pairs(self:try_get('inventory', {})) do
        local itemInfo = gearTable[k]
        if itemInfo ~= nil and itemInfo:has_key("consumable") then
            ability = itemInfo.consumable:MakeTemporaryClone()
            ability._tmp_boundCaster = self
            result[#result + 1] = ability
        end
    end

    local hasMeleeAndRanged = false

    local reach = self:GetReach()

    --reach of greater than 1 modifies melee abilities to have a bonus to their range.
    if reach > 1 and (not options.characterSheet) then
        for i = 1, #result do
            local ability = result[i]
            if ability:HasKeyword("Melee") then
                ability = ability:MakeTemporaryClone()
                result[i] = ability
                ability.rangeBonusFromReach = reach - 1
            end
        end
    end

    --split out into melee and ranged abilities.
    if not options.characterSheet then
        for i = 1, #result do
            local ability = result[i]:BifurcateIntoMeleeAndRanged(self)
            result[i] = ability
        end
    end


    --let our modifiers modify the abilities we are returning.
    local j = 1
    local nitems = #result
    for i = 1, #result do
        local ability = result[i]
        if ability._tmp_temporaryClone or (not options.characterSheet) then
            for i, mod in ipairs(modifiers) do
                ability = mod.mod:ModifyAbility(mod, self, ability)
                if ability == nil then
                    break
                end

                local variations = ability:GetVariations()
                if variations ~= nil then
                    for i = 1, #variations do
                        mod.mod:ModifyAbility(mod, self, variations[i])
                    end
                end
            end
        end

        if ability ~= nil then
            result[j] = ability
            j = j + 1
        end
    end

    while j <= nitems do
        result[j] = nil
        j = j + 1
    end

    local j = 1
    while j <= #result do
        local exclude = false
        local ability = result[j]
        if ability:has_key("keywords") then
            for _, keyword in ipairs(excludeKeywords) do
                if ability:HasKeyword(keyword) then
                    exclude = true
                    break
                end
            end
        end

        if exclude then
            table.remove(result, j)
        else
            j = j + 1
        end
    end

    return result
end

function character:GetClass()
    local classes = self:try_get("classes")
    if classes == nil or #classes == 0 then
        return nil
    end


    local classesTable = dmhub.GetTable(Class.tableName)
    return classesTable[classes[1].classid]
end

function character:BaseHitpoints()
    local c = self:GetClass()
    if c == nil then
        return 1
    end

    return dmhub.EvalGoblinScriptDeterministic(c.hitpointsCalculation, self:LookupSymbol {}, 1, "Base hitpoints")
end

function creature:RollOngoingEffectSave(id, abilityOptions)
    abilityOptions = abilityOptions or {}
    abilityOptions.symbols = abilityOptions.symbols or {}

    local ongoingEffects = self:try_get("ongoingEffects", {})
    local index = nil
    local instance = nil

    for i, effect in ipairs(ongoingEffects) do
        if effect.id == id then
            index = i
            instance = effect
            break
        end
    end

    if index == nil then
        return
    end

    local token = dmhub.LookupToken(self)
    if token == nil then
        return
    end

    local t = dmhub.GetTable(CharacterOngoingEffect.tableName)
    local ongoingEffectEntry = t[instance.ongoingEffectid]
    if ongoingEffectEntry == nil then
        return
    end

    local abilityTemplate = MCDMUtils.GetStandardAbility("Save vs Ongoing Effect")
    local ability = abilityTemplate:MakeTemporaryClone()
    MCDMUtils.DeepReplace(ability, "<<condition>>", ongoingEffectEntry.name)
    for _, behavior in ipairs(ability.behaviors) do
        if behavior:has_key("ongoingEffect") then
            behavior.ongoingEffect = instance.ongoingEffectid
        end
    end

    ability:Cast(token, { { token = token } }, abilityOptions)
end

function creature:RollConditionSave(condid, abilityOptions)
    abilityOptions = abilityOptions or {}
    abilityOptions.symbols = abilityOptions.symbols or {}

    local entry = self:try_get("inflictedConditions", {})[condid]
    if entry == nil or entry.duration == "eoe" then
        return
    end

    local token = dmhub.LookupToken(self)
    if token == nil then
        return
    end

    if entry.duration == "eot" then
        token:ModifyProperties {
            description = "Purge condition",
            execute = function()
                self:InflictCondition(condid, { purge = true })
            end,
        }
        return
    end

    local conditionTable = dmhub.GetTable(CharacterCondition.tableName)
    local conditionInfo = conditionTable[condid]
    local abilityTemplate = MCDMUtils.GetStandardAbility("Save")
    local ability = abilityTemplate:MakeTemporaryClone()
    MCDMUtils.DeepReplace(ability, "<<condition>>", conditionInfo.name)

    --this is from when saves could be associated with an ability.
    --MCDMUtils.DeepReplace(ability, "<<attribute>>", entry.duration)

    ability:Cast(token, { { token = token } }, abilityOptions)
end

creature.RegisterSymbol {
    symbol = "temporarystamina",
    --- @param c creature
    lookup = function(c)
        return c:TemporaryHitpoints()
    end,
    help = {
        name = "Temporary Stamina",
        type = "number",
        desc = "The creature's current temporary stamina.",
        seealso = { "stamina" },
    }
}

creature.RegisterSymbol {
    symbol = "lastdamagedby",
    lookup = function(c)
        return function(other)
            local result = nil
            if type(other) == "string" then
                result = c:LastDamagedBy(other)
            end

            return result or 0
        end
    end,
    help = {
        name = "LastDamagedBy",
        type = "function",
        desc = "The numeric timestamp when this creature last damaged you.",
        seealso = {},
    }
}

creature.RegisterSymbol {
    symbol = "endturntimestamp",
    lookup = function(c)
        return c:GetEndTurnTimestamp()
    end,
    help = {
        name = "End Turn Timestamp",
        type = "number",
        desc = "The numeric timestamp when this creature ended its last turn.",
        seealso = {},
    }
}

creature.RegisterSymbol {
    symbol = "ConditionCount",
    lookup = function(c)
        local result = {}
		local conditions = {}
		local ongoingEffects = c:ActiveOngoingEffects()
		if #ongoingEffects > 0 then
			local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}
			for i,cond in ipairs(ongoingEffects) do
				local ongoingEffectInfo = ongoingEffectsTable[cond.ongoingEffectid]
				--if this ongoing effect has an underlying condition then record us having that condition since conditions can also have modifiers.
				if ongoingEffectInfo.condition ~= 'none' then
					conditions[ongoingEffectInfo.condition] = 1
				end
			end
		end

        --get bestowed conditions.
        for i,modifier in ipairs(c:GetActiveModifiers()) do
            if modifier.mod:CanBestowConditions() and modifier.mod:PassesFilter(c) then
                modifier.mod:BestowConditions(modifier, c, conditions)
            end
        end

		--we have a table of conditions based on ongoing effects, add any of their modifiers.
		local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
		for k,_ in pairs(conditions) do
			local conditionInfo = conditionsTable[k]
			result[#result+1] = conditionInfo.name
		end

		local inflictedConditions = c:get_or_add("inflictedConditions", {})
		for condid,_ in pairs(inflictedConditions) do
			result[#result+1] = conditionsTable[condid].name
		end
        
        return #result
    end,
    help = {
        name = "ConditionCount",
        type = "number",
        desc = "The number of active conditions on this creature.",
        seealso = {},
    }
}

--override default InflictCondition to include MCDM condition rules.

--- Inflict a condition on a creature. (Or purge the condition using the 'purge' argument.)
--- @param conditionid string
--- @param args {duration:string, force: nil|boolean, purge: nil|boolean, riders: nil|(string[]), sourceDescription: string, casterInfo:nil|{tokenid:string, timestamp: string|number|nil}, cast: ActivatedAbilityCast}
function creature:InflictCondition(conditionid, args)
    local immunities = self:GetConditionImmunities()

    --this creature is immune to the condition.
    if immunities[conditionid] and (not args.purge) then
        return
    end

    local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
    local conditionInfo = conditionsTable[conditionid]

    local inflictedConditions = self:get_or_add("inflictedConditions", {})

    if args.purge and inflictedConditions[conditionid] == nil then
        return
    end

    local entry = inflictedConditions[conditionid] or {}
    inflictedConditions[conditionid] = entry

    if entry.duration ~= "eoe" or args.force then
        entry.stacks = 1
        entry.sourceDescription = args.sourceDescription
        entry.duration = args.duration
        entry.casterInfo = args.casterInfo
        if entry.casterInfo ~= nil then
            entry.casterInfo.timestamp = ServerTimestamp()

            if conditionInfo.trackCaster and conditionInfo:try_get("maxInstancesFormula", "") ~= "" then
                --make sure we aren't over the max instances.
                local casterToken = dmhub.GetTokenById(entry.casterInfo.tokenid)
                if casterToken ~= nil then
                    local caster = casterToken.properties
                    local maxInstances = dmhub.EvalGoblinScriptDeterministic(conditionInfo.maxInstancesFormula,
                        caster:LookupSymbol {}, 1, "Max instances of condition")
                    if maxInstances > 0 then
                        caster:CheckConditionInstances(conditionid, maxInstances, dmhub.LookupTokenId(self))
                    end
                end
            end
        end
    end

    if args.riders then
        entry.riders = entry.riders or {}
        for _, rider in ipairs(args.riders) do
            if not table.contains(entry.riders, rider) then
                entry.riders[#entry.riders + 1] = rider
            end
        end
    end

    if not args.purge then
        if args.cast ~= nil then
            args.cast:RecordInflictedCondition(conditionid, dmhub.LookupTokenId(self))
        end

        local attacker = nil
        if args.casterInfo ~= nil then
            local attackerToken = dmhub.GetTokenById(args.casterInfo.tokenid)
            if attackerToken ~= nil then
                attacker = attackerToken.properties
            end
        end
        self:DispatchEvent("inflictcondition", {
            attacker = attacker,
            hasattacker = attacker ~= nil,
            condition = conditionInfo.name,
        })

        audio.DispatchSoundEvent(conditionInfo:SoundEvent())
    else
        --the condition gets purged if we are purging it.
        local entry = inflictedConditions[conditionid]
        if entry ~= nil and entry.riders then
            local ridersTable = dmhub.GetTable(CharacterCondition.ridersTableName)

            --see if there is a rider that is removed instead of the entire condition being removed.
            for i, rider in ipairs(entry.riders) do
                local riderInfo = ridersTable[rider]
                if riderInfo ~= nil and riderInfo.removeThisInsteadOfCondition then
                    table.remove(entry.riders, i)
                    entry.duration = "eoe"
                    return
                end
            end
        end
        inflictedConditions[conditionid] = nil
    end

    self.inflictedConditions = inflictedConditions
end

function creature:GetInflictedConditionCasterTime(conditionid, casterid)
    local inflictedConditions = self:try_get("inflictedConditions", {})
    local entry = inflictedConditions[conditionid]
    if entry == nil then
        return nil
    end

    local casterInfo = entry.casterInfo
    if casterInfo == nil then
        return nil
    end

    if casterInfo.tokenid == casterid then
        return casterInfo.timestamp
    end

    return nil
end

function creature:GetOngoingEffectCasterTime(conditionid, casterid)
    local items = self:try_get('ongoingEffects', {})
    for i, cond in ipairs(items) do
        if cond.typeName == "CharacterOngoingEffectInstance" and not cond:Expired() then
            local casterInfo = cond:try_get("casterInfo")
            if casterInfo ~= nil then
                local ongoingEffectInfo = dmhub.GetTable(CharacterOngoingEffect.tableName)[cond.ongoingEffectid]
                if ongoingEffectInfo ~= nil and ongoingEffectInfo.condition == conditionid and ongoingEffectInfo.countsTowardInstanceLimit then
                    return cond.timestamp
                end
            end
        end
    end

    return nil
end

function creature:GetConditionCasterTime(conditionid, casterid)
    local a = self:GetOngoingEffectCasterTime(conditionid, casterid)

    local b = self:GetInflictedConditionCasterTime(conditionid, casterid)
    local conditionInfo = dmhub.GetTable(CharacterCondition.tableName)[conditionid]

    if type(a) == "string" then
        return math.huge
    end
    if type(b) == "string" then
        return math.huge
    end

    return math.max(a or 0, b or 0)
end

function creature:IsCasterOfConditions()
    return self:has_key("_tmp_conditionCasterSource")
end

--- @param visitor function(conditionid:string, targetToken:CharacterToken)
function creature:VisitConditionCasterSource(visitor)
    local conditionCasterSource = self:try_get("_tmp_conditionCasterSource")
    if conditionCasterSource == nil then
        return
    end

    for conditionid, tokenMap in pairs(conditionCasterSource) do
        for tokenid, _ in pairs(tokenMap) do
            local targetToken = dmhub.GetTokenById(tokenid)
            if targetToken ~= nil then
                local timestamp = targetToken.properties:GetConditionCasterTime(conditionid, dmhub.LookupTokenId(self))
                if timestamp ~= nil and timestamp > 0 then
                    visitor(conditionid, targetToken)
                end
            end
        end
    end
end

--- @param conditionid string
--- @param maxInstances number
--- @param newTokenid string
function creature:CheckConditionInstances(conditionid, maxInstances, newTokenid)
    local conditionCasterSource = self:try_get("_tmp_conditionCasterSource")
    if conditionCasterSource == nil then
        return
    end


    local tokenMap = conditionCasterSource[conditionid] or {}
    local count = 1
    for key, value in pairs(tokenMap) do
        if key ~= newTokenid then
            count = count + 1
        end
    end

    if count > maxInstances then
        local casterTokenid = dmhub.LookupTokenId(self)
        local instances = {}
        for key, value in pairs(tokenMap) do
            if key ~= newTokenid then
                local timestamp = 0
                local targetToken = dmhub.GetTokenById(key)
                if targetToken ~= nil then
                    timestamp = targetToken.properties:GetConditionCasterTime(conditionid, casterTokenid)
                end

                if timestamp ~= 0 then
                    instances[#instances + 1] = {
                        timestamp = timestamp,
                        tokenid = key,
                    }
                else
                    tokenMap[key] = nil
                end
            end
        end

        table.sort(instances, function(a, b)
            return a.timestamp < b.timestamp
        end)

        local numRemove = (#instances + 1) - maxInstances
        for i = 1, numRemove do
            if instances[i] ~= nil then
                local targetToken = dmhub.GetTokenById(instances[i].tokenid)
                if targetToken ~= nil then
                    tokenMap[instances[i].tokenid] = nil
                    targetToken:ModifyProperties {
                        description = "Purge condition",
                        undoable = false,
                        execute = function()
                            targetToken.properties:PurgeCondition(conditionid)
                        end,
                    }
                end
            end
        end
    end
end

--try to purge a condition, both from ongoing effects and from inflicted conditions.
function creature:PurgeCondition(condid)
    self:InflictCondition(condid, { purge = true })

    local ongoingEffects = self:ActiveOngoingEffects(true)
    for i = #ongoingEffects, 1, -1 do
        local ongoingEffectInfo = dmhub.GetTable(CharacterOngoingEffect.tableName)[ongoingEffects[i].ongoingEffectid]
        if ongoingEffectInfo ~= nil and ongoingEffectInfo.condition == condid then
            self:RemoveOngoingEffect(ongoingEffects[i].ongoingEffectid)
        end
    end
end

--- @param token CharacterToken
function creature:RefreshConditionCasterInfo(token)
    local inflictedConditions = self:try_get("inflictedConditions")
    if inflictedConditions ~= nil then
        for key, conditionInfo in pairs(inflictedConditions) do
            local casterInfo = conditionInfo.casterInfo
            if casterInfo ~= nil then
                local casterToken = dmhub.GetTokenById(casterInfo.tokenid)
                if casterToken ~= nil then
                    casterToken.properties:NotifyConditionCaster(token, key)
                end
            end
        end
    end

    local items = self:try_get('ongoingEffects', {})
    for i, cond in ipairs(items) do
        if cond.typeName == "CharacterOngoingEffectInstance" and not cond:Expired() then
            local casterInfo = cond:try_get("casterInfo")
            if casterInfo ~= nil then
                local ongoingEffectInfo = dmhub.GetTable(CharacterOngoingEffect.tableName)[cond.ongoingEffectid]
                if ongoingEffectInfo ~= nil and ongoingEffectInfo.condition ~= "none" and ongoingEffectInfo.countsTowardInstanceLimit then
                    local conditionInfo = dmhub.GetTable(CharacterCondition.tableName)[ongoingEffectInfo.condition]
                    if conditionInfo ~= nil and conditionInfo.trackCaster then
                        local casterToken = dmhub.GetTokenById(casterInfo.tokenid)
                        if casterToken ~= nil then
                            casterToken.properties:NotifyConditionCaster(token, ongoingEffectInfo.condition)
                        end
                    end
                end
            end
        end
    end
end

--- function which notifies that we casted a condition on the given token.
--- token CharacterToken
--- conditionid string
function creature:NotifyConditionCaster(token, conditionid)
    local conditionCasterSource = self:get_or_add("_tmp_conditionCasterSource", {})
    conditionCasterSource[conditionid] = conditionCasterSource[conditionid] or {}
    conditionCasterSource[conditionid][token.charid] = dmhub.ngameupdate
end

--- @param conditionid string
--- @param casterInfo {tokenid:string}
function creature:SetInflictedConditionSource(conditionid, casterInfo)
    local inflictedConditions = self:get_or_add("inflictedConditions", {})
    local entry = inflictedConditions[conditionid]
    if entry == nil then
        return
    end
    entry.casterInfo = casterInfo
end

--- @param conditionid string
--- @param riderid string
--- @param value boolean
--- @return boolean
function creature:SetConditionRider(conditionid, riderid, value)
    local inflictedConditions = self:try_get("inflictedConditions")
    if inflictedConditions == nil or inflictedConditions[conditionid] == nil then
        return false
    end

    local info = inflictedConditions[conditionid]
    if info.riders == nil then
        info.riders = {}
    end

    if value then
        if table.contains(info.riders, riderid) then
            return false
        end

        info.riders[#info.riders + 1] = riderid
        return true
    else
        return table.remove_value(info.riders, riderid)
    end
end

function creature:GetConditionRiders(conditionid)
    local inflictedConditions = self:try_get("inflictedConditions")
    if inflictedConditions == nil then
        return nil
    end

    local entry = inflictedConditions[conditionid]
    if entry == nil then
        return nil
    end

    return entry.riders
end

--- @param conditionid string indexes conditions table.
--- @param riderid string indexes condition riders table.
--- @return boolean
function creature:ConditionHasRider(conditionid, riderid)
    local inflictedConditions = self:try_get("inflictedConditions")
    if inflictedConditions == nil or inflictedConditions[conditionid] == nil or inflictedConditions[conditionid].riders == nil then
        return false
    end

    return table.contains(inflictedConditions[conditionid].riders, riderid)
end

--- Get the duration the given condition will last on the creature, or nil if it doesn't have this condition.
--- @param conditionid string
--- @return nil|string
function creature:ConditionDuration(conditionid)
    local inflictedConditions = self:try_get("inflictedConditions", {})
    local entry = inflictedConditions[conditionid]
    if entry == nil then
        return nil
    end

    return entry.duration
end

creature.RegisterSymbol {
    symbol = "conditionstacks",
    lookup = function(c)
        return function(condName)
            local inflictedConditions = c:try_get("inflictedConditions", {})
            local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
            for k, v in pairs(conditionsTable) do
                if not v:try_get("hidden", false) and string.lower(v.name) == string.lower(condName) then
                    local entry = inflictedConditions[k]
                    if entry ~= nil then
                        return entry.stacks
                    end
                end
            end

            local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}

            local result = 0

            --try looking at ongoing effects.
            local ongoingEffects = c:ActiveOngoingEffects()
            for _, effect in ipairs(ongoingEffects) do
                local effectInfo = ongoingEffectsTable[effect.ongoingEffectid]
                if effectInfo ~= nil and string.lower(effectInfo.name) == string.lower(condName) then
                    result = result + effect.stacks
                end
            end

            return result
        end
    end,

    help = {
        name = "Condition Stacks",
        type = "number",
        desc = "The number of stacks of the given condition the creature has.",
        seealso = {},
    },
}

function creature:PowerRollBonus()
    return 0
end

creature.RegisterSymbol {
    symbol = "powerrollbonus",
    lookup = function(c)
        return c:PowerRollBonus()
    end,

    help = {
        name = "Power Roll Bonus",
        type = "number",
        desc = "The bonus that monsters get to their power rolls. Zero for heroes.",
        seealso = {},
    },
}

function creature:GetModifiersForPowerRoll(roll, rollType, options)
    options = options or {}
    local result = {}
    local modifiers = self:GetActiveModifiers()
    for _, mod in ipairs(modifiers) do
        local m = mod.mod:DescribeModifyPowerRoll(mod, self, rollType, options)
        if m ~= nil then
            m.hint = m.modifier:HintModifyPowerRolls(mod, self, rollType, options)
            if m.hint ~= nil then
                result[#result + 1] = m
            end
        end
    end

    return result
end

function creature:RollCustomPowerTableTest(title, characteristics, skills, tiers)
    local attrid = nil
    local bestModifier = nil
    for id, _ in pairs(characteristics) do
        local attr = self:GetAttribute(id)
        if attr ~= nil then
            local modifier = self:GetAttribute(id):Modifier()
            if bestModifier == nil or modifier > bestModifier then
                bestModifier = modifier
                attrid = id
            end
        end
    end

    local attrInfo = creature.attributesInfo[attrid]

    local rollProperties = RollPropertiesPowerTable.new {
        tiers = tiers,
        fullyImplemented = true,
    }

    local rollType = "test_power_roll"
    local roll = string.format("2d10 + %d", self:GetAttribute(attrid):Modifier())
    local modifiers = self:GetModifiersForPowerRoll(roll, rollType, { attribute = attrid, title = title })
    for i, mod in ipairs(modifiers) do
        if mod.modifier.name == "Skilled" then
            local skillNames = {}
            local found = false
            for _, skillid in ipairs(skills) do
                local skillInfo = dmhub.GetTable(Skill.tableName)[skillid]
                if skillInfo ~= nil and self:ProficientInSkill(skillInfo) then
                    found = true
                    mod.modifier = DeepCopy(mod.modifier)
                    mod.modifier.name = string.format(tr("Skilled in %s"), skillInfo.name)
                    mod.modifier.description = string.format(tr("Skill in %s gives you +2 on this roll"), skillInfo.name)
                    mod.modifier.activationCondition = true
                    mod.hint.result = true
                    break
                elseif skillInfo ~= nil then
                    skillNames[#skillNames + 1] = skillInfo.name
                end
            end
            print("SKILLED::", json(mod))
            if (not found) and #skillNames > 0 then
                mod.modifier = DeepCopy(mod.modifier)
                mod.modifier.description = string.format(tr("Not skilled in %s"), table.concat(skillNames, " or "))
            end
        end
    end

    GameHud.instance.rollDialog.data.ShowDialog {
        title = title,
        description = title,
        creature = self,

        type = rollType,
        roll = roll,
        modifiers = modifiers,

        rollProperties = rollProperties,
        PopulateCustom = ActivatedAbilityPowerRollBehavior.GetPowerTablePopulateCustom(rollProperties),

        completeRoll = function(rollInfo)
        end,

        cancelRoll = function()
        end,
    }
end

function creature:ShowCharacteristicRollDialog(attrid)
    local attrInfo = creature.attributesInfo[attrid]

    local rollProperties = RollPropertiesPowerTable.new {
        tiers = {
            "Tier 1 Result",
            "Tier 2 Result",
            "Tier 3 Result",
        }
    }

    local rollType = "test_power_roll"
    local roll = string.format("2d10 + %d", self:GetAttribute(attrid):Modifier())
    local modifiers = self:GetModifiersForPowerRoll(roll, rollType, { attribute = attrid })

    GameHud.instance.rollDialog.data.ShowDialog {
        title = string.format("%s Test", attrInfo.description),
        description = string.format("%s Test", attrInfo.description),
        creature = self,

        type = rollType,
        roll = roll,
        modifiers = modifiers,

        rollProperties = rollProperties,
        PopulateCustom = ActivatedAbilityPowerRollBehavior.GetPowerTablePopulateCustom(rollProperties),

        completeRoll = function(rollInfo)
        end,

        cancelRoll = function()
        end,
    }
end

--hitpoints handling overridden. We include handling of minions.
local g_creatureCurrentHitpoints = creature.CurrentHitpoints
function creature.CurrentHitpoints(self)
    if (not mod.unloaded) and self.minion and self:has_key("_tmp_minionSquad") then
        local damage_taken = self._tmp_minionSquad.damage_taken or 0
        local maxhp = self:MaxHitpoints()
        return maxhp - damage_taken
    end

    return g_creatureCurrentHitpoints(self)
end

local g_creatureSetCurrentHitpoints = creature.SetCurrentHitpoints
function creature.SetCurrentHitpoints(self, amount, note)
    if (not mod.unloaded) and self.minion and self:has_key("_tmp_minionSquad") then
        local token = dmhub.LookupToken(self)
        if token ~= nil then
            local damage_taken_seq = self._tmp_minionSquad.damage_taken_seq + 1
            local damage_taken = self:MaxHitpoints() - amount
            if damage_taken < 0 then
                damage_taken = 0
            end

            local tokenCount = 0
            for _, tok in ipairs(self._tmp_minionSquad.tokens) do
                if tok ~= nil and tok.valid then
                    tokenCount = tokenCount + 1
                end
            end

            self._tmp_minionSquad.damage_taken = damage_taken
            self._tmp_minionSquad.damage_time_pending = true

            for _, tok in ipairs(self._tmp_minionSquad.tokens) do
                if tok ~= nil and tok.valid then
                    tok:ModifyProperties {
                        description = note,
                        combine = true,
                        undoable = false,
                        execute = function()
                            tok.properties.damage_taken = damage_taken
                            tok.properties.damage_taken_seq = damage_taken_seq
                            tok.properties.damage_taken_minion_count = tokenCount
                        end,
                    }
                end
            end
        end

        return
    end

    g_creatureSetCurrentHitpoints(self, amount, note)
end

local g_creatureSetTemporaryHitpoints = creature.SetTemporaryHitpoints
function creature.SetTemporaryHitpoints(self, amount, note, options)
    g_creatureSetTemporaryHitpoints(self, amount, note, options)

    if mod.unloaded then
        return
    end
end

--removes temporary hitpoints, returning the overflow amount.
local g_creatureRemoveTemporaryHitpoints = creature.RemoveTemporaryHitpoints
function creature:RemoveTemporaryHitpoints(amount, note)
    return g_creatureRemoveTemporaryHitpoints(self, amount, note)
end

local g_creatureTemporaryHitpoints = creature.TemporaryHitpoints
function creature.TemporaryHitpoints(self)
    return g_creatureTemporaryHitpoints(self)
end

local g_creatureTemporaryHitpointsStr = creature.TemporaryHitpointsStr
function creature.TemporaryHitpointsStr(self)
    return g_creatureTemporaryHitpointsStr(self)
end

creature.minionDamageTime = 0

function creature.TakeDamage(self, amount, note, info)
    info = info or {}
    if type(amount) == 'string' then
        amount = dmhub.RollInstant(amount)
    end

    if type(amount) ~= 'number' then
        return
    end

    if amount <= 0 and note == nil then
        return
    end

    if amount < 0 then
        amount = 0
    end

    local attackerid = nil
    if info.attacker ~= nil then
        attackerid = dmhub.LookupTokenId(info.attacker)
    end

    if attackerid ~= nil and attackerid == dmhub.LookupTokenId(self) then
        attackerid = nil
        
        print("ATTACKER:: pusher:", info.pusher)
        local pusher = info.pusher or (info.ability ~= nil and info.ability.name == "Fall Damage" and rawget(self, "_tmp_lastpusher"))
        if pusher ~= nil then
            if type(pusher) == "function" then
                pusher = pusher("self")
            end

            attackerid = dmhub.LookupTokenId(pusher)
            info.damagetype = "push"
            if info.ability ~= nil then
                if info.ability.name == "Collision" then
                    info.damagetype = "collide"
                elseif info.ability.name == "Fall Damage" then
                    info.damagetype = "fall"
                end
            end
        end
    end

    print("ATTACKER:: attacker", dmhub.LookupTokenId(self), "vs", attackerid)
    self:RecordDamageEntry {
        damage = amount,
        damage_type = info.damagetype,
        attackerid = attackerid,
        sound = info.damagesound,
    }

    if self.minion then
        if info.keywords ~= nil and info.keywords:Has("area") then
            --area damage can't do more than a single minion's max hitpoints.
            amount = math.min(self:SingleMinionMaxStamina(), amount)
        end

        self:SetCurrentHitpoints(self:CurrentHitpoints() - amount, note)

        self.minionDamageTime = ServerTimestamp()

        local eventArg = shallow_copy_table(info)
        if eventArg.attacker == self then
            --we don't ever regard us as attacking ourselves. This would make conditions doing damage to us trigger an attack on ourselves.
            eventArg.attacker = nil
        end
        eventArg.damage = amount
        eventArg.damagetype = eventArg.damagetype or "none"
        eventArg.hasattacker = eventArg.attacker ~= nil
        eventArg.surges = info.surges or 0
        eventArg.edges = 0
        eventArg.banes = 0
        if info.cast then
            eventArg.edges = info.cast.boonsApplied
            eventArg.banes = info.cast.banesApplied
        end
        if (not info.doesNotTrigger) and amount > 0 then
        print("LOSEHITPOINTS:: DO LOSE", info.doesNotTrigger)
            self:DispatchEvent("losehitpoints", eventArg)
        end

        if eventArg.attacker == nil or dmhub.LookupTokenId(eventArg.attacker) == dmhub.LookupTokenId(self) then
            self._tmp_lastattacker = eventArg.pusher
                    print("ATTACKER::", dmhub.LookupTokenId(self:try_get("_tmp_lastattacker")))
        else
            self._tmp_lastattacker = eventArg.attacker
                    print("ATTACKER::", dmhub.LookupTokenId(self:try_get("_tmp_lastattacker")))
        end
        self._tmp_lastdamagetype = eventArg.damagetype

        if eventArg.attacker ~= nil and (not info.doesNotTrigger) then
            local attacker = eventArg.attacker
            local args = {
                target = self,
                damage = amount,
                damagetype = eventArg.damagetype,
                keywords = eventArg.keywords,
                surges = eventArg.surges,
                edges = eventArg.edges,
                banes = eventArg.banes,
                hasability = eventArg.hasability,
                ability = eventArg.ability,
            }
            attacker:DispatchEvent("dealdamage", args)
        end

        return
    end

    local isWindedAtStart = self:CurrentHitpoints() <= self:MaxHitpoints() / 2
    local isBelowZeroAtStart = self:CurrentHitpoints() <= 0
    local isDeadAtStart = self:IsDead()

    local original_amount = amount

    local instadeath = false

    if amount > 0 then
        if self:IsUnconsciousButStable() then
            self:ResetDeathSavingThrowStatus()
        elseif isDeadAtStart then
            if amount >= self:MaxHitpoints() then
                self:AddDeathSavingThrowFailure(3)
            else
                self:AddDeathSavingThrowFailure()
            end
        end

        amount = self:RemoveTemporaryHitpoints(amount, note or string.format("%d Damage", original_amount))

        if amount >= self:MaxHitpoints() + self:CurrentHitpoints() then
            instadeath = true
        end
    end

    self.damage_taken = self.damage_taken + amount
    local damage_taken_maybe_negative = self.damage_taken
    self:CheckBelowZeroHitpoints()

    local eventArg = shallow_copy_table(info)
    if eventArg.attacker == self then
        --we don't ever regard us as attacking ourselves. This would make conditions doing damage to us trigger an attack on ourselves.
        eventArg.attacker = nil
    end
    eventArg.damage = amount
    eventArg.damagetype = eventArg.damagetype or "untyped"
    eventArg.hasattacker = eventArg.attacker ~= nil
    eventArg.surges = info.surges or 0
    eventArg.edges = 0
    eventArg.banes = 0
    if info.cast then
        eventArg.edges = info.cast.boonsApplied
        eventArg.banes = info.cast.banesApplied
    end

    if (not info.doesNotTrigger) and original_amount > 0 then
        self:DispatchEvent("losehitpoints", eventArg)
    end

    --handle firing audio events.
    local isWindedNow = self:CurrentHitpoints() <= self:MaxHitpoints() / 2
    local isBelowZeroNow = self:CurrentHitpoints() <= 0
    local isDeadNow = self:IsDead()

    if isDeadNow then
        if not isDeadAtStart then
            if self:IsHero() then
                audio.DispatchSoundEvent("Notify.Status_Dead_Hero", {})
            else
                audio.DispatchSoundEvent("Notify.Status_Dead_Enemy", {})
            end
        end
    elseif isBelowZeroNow then
        if not isBelowZeroAtStart then
            audio.DispatchSoundEvent("Notify.Status_Dying_Hero", {})
            self:DispatchEvent("dying", eventArg)
            print("DYING:: FIRED")
        end
    elseif isWindedNow and not isWindedAtStart then
        self:DispatchEvent("winded", eventArg)
        audio.DispatchSoundEvent("Condition.Winded", {})
            print("DYING:: WINDED")
    end

    if eventArg.attacker == nil or dmhub.LookupTokenId(eventArg.attacker) == dmhub.LookupTokenId(self) then
        self._tmp_lastattacker = eventArg.pusher
        print("ATTACKER::", dmhub.LookupTokenId(self:try_get("_tmp_lastattacker")))
    else
        self._tmp_lastattacker = eventArg.attacker
        print("ATTACKER::", dmhub.LookupTokenId(self:try_get("_tmp_lastattacker")))
    end

    if eventArg.attacker ~= nil and not (info.doesNotTrigger) then
        local attacker = eventArg.attacker
        local args = {
            target = self,
            damage = amount,
            damagetype = eventArg.damagetype,
            keywords = eventArg.keywords,
            surges = eventArg.surges,
            edges = eventArg.edges,
            banes = eventArg.banes,
            hasability = eventArg.hasability,
            ability = eventArg.ability,
        }
        attacker:DispatchEvent("dealdamage", args)
    end



    --if this caused us to start dying we should set dying status.
    if (not isDeadAtStart) and self:IsDead() then
        if self:IsDead() then
            self:RemoveAurasOnDeath()

            if self:IsDead() then
                self:ResetDeathSavingThrowStatus()
            end

            self:DispatchEvent("zerohitpoints", eventArg)

            eventArg.victim = self
            eventArg.hasattacker = eventArg.attacker ~= nil

            if eventArg.attacker ~= nil then
                --NOTE: We have to TriggerEvent here not DispatchEvent because
                --DispatchEvent does not currently have support for dispatching
                --creature objects and other self-referential objects.
                eventArg.attacker:TriggerEvent("kill", eventArg)
            end

            eventArg.victim = nil
            eventArg.attacker = nil
            eventArg.hasattacker = nil
            eventArg.subject = nil

            self:DispatchEvent("creaturedeath", eventArg)

            self:CancelConcentration()

            if instadeath then
                self:AddDeathSavingThrowFailure(3)
            end
        end
    end

    if (not isBelowZeroAtStart) and self:CurrentHitpoints() <= 0 then
        self:StartOnDying()
    end

    local attackerid = nil
    if info.attacker ~= nil then
        local attackerTok = dmhub.LookupToken(info.attacker)
        if attackerTok ~= nil then
            attackerid = attackerTok.charid
        end
    end

    local statHistory = self:GetStatHistory("stamina")
    self:GetStatHistory("stamina"):Append {
        attackerid = attackerid,
        note = note or string.format("%d Damage", original_amount),
        set = self:CurrentHitpoints(),
        disposition = "bad",
    }
end

function creature.Heal(self, amount, note)
    local canHeal = (self:CalculateNamedCustomAttribute("Cannot Regain Stamina") == 0)
    if not canHeal then
        self:FloatLabel("Cannot Regain Stamina", "#ff0000")
        return
    end

    if type(amount) == 'string' then
        amount = dmhub.RollInstant(amount)
    end

    if type(amount) ~= 'number' then
        return
    end

    if amount <= 0 then
        return
    end

    if self.minion then
        self:SetCurrentHitpoints(math.min(self:MaxHitpoints(), self:CurrentHitpoints() + amount), note)
        return
    end

    self:CheckBelowZeroHitpoints()

    self.damage_taken = self.damage_taken - amount
    if self.damage_taken < 0 then
        self.damage_taken = 0
    end

    self:ResetDeathSavingThrowStatus()

    self:GetStatHistory("stamina"):Append {
        note = note or string.format("%d Healing", amount),
        set = self:CurrentHitpoints(),
        disposition = "good",
    }

    self:RecordDamageEntry {
        heal = amount,
    }


    self:DispatchEvent("regainhitpoints", {})
end

--this is called by the engine to tell the 'cost' of moving through
--another token. We can return "difficult" to signal difficult terrain.
--return true to mean we can move through with no cost. false means
--we cannot move through.
function creature:CostToMoveThroughToken(otherToken)
    local ourToken = dmhub.LookupToken(self)
    if ourToken ~= nil and (not otherToken:IsFriend(ourToken)) then
        local enemyBlocks = otherToken.properties:CalculateNamedCustomAttribute("Block Enemy Movement")
        if enemyBlocks > 0 then
            --we cannot move through an enemy.
            return false
        end
        local freeMove = self:CalculateNamedCustomAttribute("Freely Move Through Enemies")
        if freeMove > 0 then
            --we can move through enemies freely.
            return true
        end
        --moving through an enemy is regarded as difficult terrain.
        return "difficult"
    end

    --moving through a friend is fine.
    return true
end

--- @param flags {shifting: boolean} if true, the creature is shifting.
--- @return boolean true if the creature can navigate difficult terrain, false if it cannot.
function creature:CanNavigateDifficultTerrain(flags)
    if flags.shifting then
        local canShift = self:CalculateNamedCustomAttribute("Can Shift In Difficult Terrain")
        return GoblinScriptTrue(canShift)
    end

    return true
end

--- @param token CharacterToken
--- @param info {type: string, amount: number, instances: number, aura: AuraInstance}
function creature:AuraDamage(token, info)
    token:ModifyProperties {
        description = info.aura.name,
        execute = function()
            for i = 1, info.instances do
                self:InflictDamageInstance(info.amount, info.type, {}, info.aura.name, { damagesound = "Attack.Enviro" })
            end
        end,
    }
end

function creature:CanMoveThroughWalls()
    local customAttr = CustomAttribute.attributeInfoByLookupSymbol["canmovethroughwalls"]
    if customAttr == nil then
        return false
    end

    local result = self:GetCustomAttribute(customAttr) > 0
    return result
end

function creature:IgnoreDifficultTerrain()
    local customAttr = CustomAttribute.attributeInfoByLookupSymbol["ignoredifficultterrain"]
    if customAttr == nil then
        return false
    end

    local result = self:GetCustomAttribute(customAttr) > 0
    return result
end

--- @param eventName string
--- @param info table
function creature:DispatchEventAndWait(eventName, info)
    -- Check if there are any triggers for this event first
    local mods = self:GetActiveModifiers()
    local hasTrigger = false
    for i,mod in ipairs(mods) do
        if mod.mod:HasTriggeredEvent(self, eventName) then
            hasTrigger = true
            break
        end
    end
    
    -- If no triggers, just dispatch normally and return immediately
    if not hasTrigger then
        self:DispatchEvent(eventName, info)
        return
    end
    
    -- If there are triggers, set up waiting mechanism
    local eventComplete = false

    EventUtils.RegisterGlobalEventHandler(mod, eventName, function(pass)
        eventComplete = pass
    end)

    self:DispatchEvent(eventName, info)

    while not eventComplete do
        coroutine.yield(0.1)
    end
end

function creature:PersistentAbilities()
    local result = {}

    for i, a in ipairs(self:try_get("persistentAbilities", {})) do

            local q = dmhub.initiativeQueue
            if q == nil or q.hidden then
                break
            elseif (q.round or 0) > (a.round or 0) or ((q.round or 0) == (a.round or 0) and (q.turn or 0) > (a.turn or 0)) then
                if a.ability == nil then
                    break
                end
                local ability = a.ability:MakeTemporaryClone()

                local persistence = ability:Persistence()
                local persistenceMode = persistence.mode

                if persistenceMode == "none" then
                    break
                end

                local newAbility = TriggeredAbility.Create()
                newAbility.trigger = "beginturn"
                newAbility.guid = dmhub.GenerateGuid()                
                newAbility.name = ability.name
                newAbility.resourceNumber = 0
                newAbility.targetType = "self"
                newAbility.iconid = ability.iconid
                newAbility.mandatory = false
                newAbility.abilityType = "none"
                newAbility.repeatTargets = false
                newAbility.whenActive = "combat"
                newAbility.castImmediately = true

                ability.persistence = nil
                ability.actionResourceId = cond(persistenceMode == "recast_maneuver", CharacterResource.maneuverResourceId, "none")

                --[[ if a.filter ~= nil then
                    ability.abilityFilter = {a.filter}
                end ]]

                local targeting = "prompt"

                local targets = nil

                local filterstr = ""
                if persistenceMode == "recast_target" then
                    targeting = "inherit"
                    targets = {}
                    for i,targetid in ipairs(a.targets or {}) do
                        if i == #a.targets then
                            filterstr = string.format("%s %s", filterstr, string.format("self.id = %s", Utils.HashGuidToNumber(targetid)))
                        else
                            filterstr = string.format("%s or %s", filterstr, string.format("self.id = %s", Utils.HashGuidToNumber(targetid)))
                        end
                    end
                    for _,targetid in ipairs(a.targets or {}) do
                        local targetToken = dmhub.GetTokenById(targetid)
                        if targetToken ~= nil then
                            targets[#targets+1] = {
                                token = targetToken,
                            }
                        end
                    end
                    ability.targetFilter = filterstr

                elseif persistenceMode == "recast_with_one_target" then
                    ability.numTargets = 1
                end

                ability.OnFinishCast = function(ability)
                    local q = dmhub.initiativeQueue
                    if q == nil or q.hidden then
                        return
                    end
                    local m_token = dmhub.LookupToken(self)
                    local persistentAbilities = self:try_get("persistentAbilities", {})
                    for _,entry in ipairs(persistentAbilities) do
                        if entry.name == ability.name then
                            m_token:ModifyProperties{
                                description = "Update Persistent Ability",
                                undoable = false,
                                execute = function()
                                    entry.turn = q.turn
                                    entry.round = q.round
                                end,
                            }
                        end
                    end
                end

                local invoke = ActivatedAbilityInvokeAbilityBehavior.new{
                    customAbility = ability,
                    promptText = string.format(tr("Persistence: Recast %s"), ability.name),
                    targeting = "prompt",
                    --targetingFormula = filterstr,
                    --targets = targets,
                }

                local persistCast = ActivatedAbilityPersistenceCastBehavior.new{
                    token = dmhub.LookupToken(self),
                    ability = ability,
                    targets = targets,
                }

                local behavior = newAbility:get_or_add("behaviors", {})
                behavior[#behavior + 1] = invoke

                local mod = CharacterModifier.new{
                    guid = dmhub.GenerateGuid(),
                    source = "Persistent Ability",
                    name = string.format("Persistent: %s", newAbility.name),
                    behavior = "trigger",
                    triggeredAbility = newAbility,
                    description = "",
                    domains = {},
                }

                result[#result + 1] = mod
            end
        end

    return result
end

creature.RegisterSymbol {
    symbol = "keywords",
    lookup = function(c)
        local keywords = table.keys(c:Keywords())

        --add any keywords from the object.
        local token = dmhub.LookupToken(c)
        if token ~= nil and token.valid and token.isObject then
            local component = token.objectComponent
            if component ~= nil then
                local levelObject = component.levelObject
                if levelObject ~= nil then
                    local otherKeywords = levelObject.keywords
                    if otherKeywords then
                        for k,_ in pairs(otherKeywords) do
                            if not table.contains(keywords, k) then
                                keywords[#keywords + 1] = k
                            end
                        end
                    end
                end
            end
        end

        return StringSet.new{
            strings = keywords,
        }
    end,
    help = {
        name = "Keywords",
        type = "string",
        desc = "The keywords associated with this creature.",
        seealso = {},
    }
}

creature.RegisterSymbol {
    symbol = "gamemode",
    lookup = function(c)
        local q = dmhub.initiativeQueue
        if q == nil then
            return "exploration"
        end

        return q.gameMode
    end,
    help = {
        name = "Game Mode",
        type = "string",
        desc = "The id of the game mode the game is currently in. Can be 'exploration', 'combat', 'respite', or 'downtime'.",
        seealso = {},
    }
}

creature.RegisterSymbol {
    symbol = "takenturn",
    lookup = function(c)
        local q = dmhub.initiativeQueue
        if q == nil or q.hidden then
            return true
        end

        local tok = dmhub.LookupToken(c)
        if tok == nil then
            return true
        end

        local id = q.GetInitiativeId(tok)
        if not q:HasInitiative(id) then
            return true
        end

        return q:HasHadTurn(id)
    end,
    help = {
        name = "Taken Turn",
        type = "boolean",
        desc = "Has this creature taken its turn this round?",
        seealso = {},
    }
}

creature.RegisterSymbol {
    symbol = "turnbeingchosen",
    lookup = function(c)
        local q = dmhub.initiativeQueue
        if q == nil or q.hidden then
            return false
        end

        local tok = dmhub.LookupToken(c)
        if tok == nil then
            return false
        end

        return q:ChoosingTurn()
    end,
    help = {
        name = "Turn Being Chosen",
        type = "boolean",
        desc = "Is the next turn for initiative currently being chosen?",
        seealso = {},
    }
}

function creature:Role()
    return "none"
end

function monster:Role()
    return self:try_get("role", "none")
end

function character:Role()
    return "hero"
end

creature.RegisterSymbol {
    symbol = "role",
    lookup = function(c)
        return c:Role()
    end,
    help = {
        name = "Role",
        type = "string",
        desc = "The role of the creature.",
        seealso = { "leader", "solo" },
    }
}

creature.RegisterSymbol {
    symbol = "inwater",

    lookup = function(c)
        return c:CurrentMoveType() == "swim"
    end,
    help = {
        name = "InWater",
        type = "boolean",
        desc = "Is this creature in water?",
        seealso = {},
    }
}

creature.RegisterSymbol{
    symbol = "boundcreatures",
    lookup = function(c)
        return function(effectName)
            effectName = string.lower(effectName)
            local ongoingEffects = c:try_get("ongoingEffects", {})
            local effectEntry = nil
            local t = dmhub.GetTable("characterOngoingEffects")
            for _, ongoingEffect in ipairs(ongoingEffects) do
                local effectInfo = t[ongoingEffect.ongoingEffectid]
                if effectInfo ~= nil and string.lower(effectInfo.name) == effectName then
                    effectEntry = ongoingEffect
                    break
                end
            end

            if effectEntry ~= nil and effectEntry.bondid then
                local tokens = creature.GetTokensWithBoundOngoingEffect(effectEntry.bondid)
                local tokenids = {}
                for _, token in ipairs(tokens) do
                    tokenids[#tokenids + 1] = token.charid
                end
                local set = CreatureSet.new{ creatures = tokenids }
                return set
            end

            return CreatureSet.new{}
        end
    end,

    help = {
        name = "BoundCreatures",
        type = "function",
        desc = "All of the creatures bound to this creature by the given ongoing effect",
        seealso = {},
        examples = {
            'BoundCreatures("Bloodbound")',
        },
    },
}

creature.RegisterSymbol{
    symbol = "boundongoingeffect",
    lookup = function(c)
        return function(other, effectName)
            other = Utils.ResolveGoblinScriptObject(other)
            if other == nil or type(other) ~= "table" then
                return false
            end
            effectName = string.lower(effectName)
            local ongoingEffects = c:try_get("ongoingEffects", {})
            local effectEntry = nil
            local t = dmhub.GetTable("characterOngoingEffects")
            for _, ongoingEffect in ipairs(ongoingEffects) do
                local effectInfo = t[ongoingEffect.ongoingEffectid]
                if effectInfo ~= nil and string.lower(effectInfo.name) == effectName then
                    effectEntry = ongoingEffect
                    break
                end
            end

            if effectEntry ~= nil and effectEntry.bondid then
                local otherEffects = other:try_get("ongoingEffects", {})
                for _, otherEffect in ipairs(otherEffects) do
                    if otherEffect.bondid == effectEntry.bondid then
                        return true
                    end
                end
            end

            return false
        end
    end,
    help = {
        name = "BoundOngoingEffect",
        type = "function",
        desc = "Is this creature bound by a named ongoing effect to another creature.",
        seealso = {},
        examples = {
            'Caster.BoundOngoingEffect(Target, "Bloodbound")',
        },
    }
}

function creature:StartOnDying()
    self:RemoveMatchingOngoingEffects(function(ongoingEffect)
        return ongoingEffect.removeOnEoEOrDying
    end)
end

function creature:EndCombat()
    local token = dmhub.LookupToken(self)
    token:ModifyProperties{
        description = "Remove Persistent Abilities",
        execute = function()
            local persistentAbilities = self:try_get("persistentAbilities", {})
            if #persistentAbilities > 0 then
                self.persistentAbilities = {}
            end
        end,
    }

    self:RemoveMatchingOngoingEffects(function(ongoingEffect)
        return ongoingEffect.removeOnEoEOrDying or ongoingEffect.removeOnEoE
    end)

    self:RemoveMatchingCondition(function(condition)
        return condition.duration == "eoe"
    end)

    if self:has_key("auras") then
		local expires = false
		for i,aura in ipairs(self.auras) do
			if aura:HasExpired() then
				expires = true
			end
		end

		if expires then
			local newAuras = {}
			for i,aura in ipairs(self.auras) do
				if aura:HasExpired() then
					aura:DestroyAura(self)
				else
					newAuras[#newAuras+1] = aura
				end
			end
			self.auras = newAuras
		end
	end

    if not self:has_key("temporary_hitpoints_effect") and self:TemporaryHitpoints() > 0 then
        local token = dmhub.LookupToken(self)
        token:ModifyProperties{
            description = "Remove Temporary Hit Points",
            execute = function()
                self.temporary_hitpoints = nil
            end,
        }
    end

    token:ModifyProperties{
        description = "Reset Heroic Resource",
        execute = function()
            local resources = self:try_get("resources")
            if resources ~= nil then
                local heroicResource = resources[CharacterResource.heroicResourceId]
                if heroicResource ~= nil then
                    heroicResource.unbounded = 0
                end
            end
        end,
    }

end

function creature:RemoveMatchingOngoingEffects(predicate)
    local removes = nil
    local ongoingEffects = self:try_get("ongoingEffects", {})
    for i = #ongoingEffects, 1, -1 do
        local ongoingEffect = ongoingEffects[i]
        if ongoingEffect.typeName == "CharacterOngoingEffectInstance" and predicate(ongoingEffect) then
            removes = removes or {}
            removes[#removes + 1] = i
        end
    end

    if removes ~= nil then
        local newOngoingEffects = {}
        for i = 1, #ongoingEffects do
            if not table.contains(removes, i) then
                newOngoingEffects[#newOngoingEffects + 1] = ongoingEffects[i]
            end
        end

        local token = dmhub.LookupToken(self)
        if token ~= nil then
            token:ModifyProperties {
                description = "End combat",
                execute = function()
                    self.ongoingEffects = newOngoingEffects
                end,
            }
        end
    end
end

function creature:RemoveMatchingCondition(predicate)
    local removes = nil
    local conditions = self:try_get("inflictedConditions", {})
    for condid, condition in pairs(conditions) do
        if predicate(condition) then
            removes = removes or {}
            removes[#removes + 1] = condid
        end
    end

    if removes ~= nil then
        local newConditions = {}
        for condid, condition in pairs(conditions) do
            if not table.contains(removes, condid) then
                newConditions[condid] = condition
            end
        end

        local token = dmhub.LookupToken(self)
        if token ~= nil then
            token:ModifyProperties {
                description = "Remove matching conditions",
                execute = function()
                    self.inflictedConditions = newConditions
                end,
            }
        end
    end
end

function creature.ScoreTokenImportance(tok)
    local score = -tok.properties:CharacterLevel()

    if tok.playerControlledAndPrimary then
        score = score - 1000
    end

    if tok.properties:IsHero() then
        score = score - 100
    end

    if tok.playerControlled then
        score = score - 50
    end

    if tok.properties.minion then
        score = score + 100
    end

    return score
end

local g_tileSize = 100
local g_initiativeGroupings = {}

local function GroupingHud(groupid)
    local floorid = dmhub.floorid
	local sheetParent = dmhub.GetWorldSpacePanel(floorid, "grouping-" .. groupid)
    
    if sheetParent ~= nil and sheetParent.sheet == nil then
        local m_lines = {}
        local m_sheet = gui.Panel{
            width = 1,
            height = 1,
            halign = "center",
            valign = "center",
            blocksGameInteraction = false,
            thinkTime = 0.01,
            think = function(element)
                local removes = nil
                local count = 0
                for _,token in pairs(g_initiativeGroupings[groupid].tokens) do
                    if token ~= nil and token.valid and token.floorid == floorid then
                        count = count + 1
                    else
                        removes = removes or {}
                        removes[#removes + 1] = token.charid
                    end
                end

                if removes ~= nil then
                    for _,charid in ipairs(removes) do
                        g_initiativeGroupings[groupid].tokens[charid] = nil
                    end
                end

                if count <= 1 then
                    sheetParent:Destroy()
                    return
                end

                local selectedTokens = dmhub.selectedOrPrimaryTokens

                local floor = game.GetFloor(floorid)

                local center = {x = 0, y = 0}
                local count = 0
                local tokenSelected = false
                for _,token in pairs(g_initiativeGroupings[groupid].tokens) do
                    if not tokenSelected then
                        for _,tok in ipairs(selectedTokens) do
                            if tok == token then
                                tokenSelected = true
                                break
                            end
                        end
                    end
                    local tokenPos = token.pos
                    tokenPos = floor:AdjustParallaxPositionOnGround(tokenPos.x, tokenPos.y)
                    center.x = center.x + tokenPos.x
                    center.y = center.y + tokenPos.y
                    count = count+1
                end

                if not tokenSelected then
                    --no tokens selected.
                    element.children = {}
                    m_lines = {}
                    return
                end

                center.x = center.x / count
                center.y = center.y / count

                local changes = false

                for key,token in pairs(g_initiativeGroupings[groupid].tokens) do
                    local tokenPos = token.pos
                    tokenPos = floor:AdjustParallaxPositionOnGround(tokenPos.x, tokenPos.y)

                    local dir = core.Vector2(center.x - tokenPos.x, center.y - tokenPos.y).unit
                    
                    --get the position on the edge.
                    tokenPos = {
                        x = tokenPos.x + dir.x * token.radiusInTiles,
                        y = tokenPos.y + dir.y * token.radiusInTiles,
                    }


                    local line = m_lines[key]
                    
                    if line == nil then
                        changes = true
                        line = gui.Panel{
                            bgimage = true,
                            bgcolor = "white",
                            halign = "center",
                            valign = "center",
                            opacity = 0.2,
                            width = 2,
                            height = 1,
                            blocksGameInteraction = false,
                        }
                        m_lines[key] = line
                    end

                    local dx = tokenPos.x - center.x
                    local dy = tokenPos.y - center.y
                    local angle = math.atan(dy, dx)
                    line.selfStyle.rotate = math.deg(angle) + 90
                    line.selfStyle.height = g_tileSize*math.sqrt(dx*dx + dy*dy)

                    line.selfStyle.x = (tokenPos.x + center.x)*g_tileSize*0.5
                    line.selfStyle.y = -(tokenPos.y + center.y)*g_tileSize*0.5
                end

                for key,line in pairs(m_lines) do
                    if g_initiativeGroupings[groupid].tokens[key] == nil then
                        changes = true
                        line:Destroy()
                        m_lines[key] = nil
                    end
                end

                if changes then
                    local children = {}
                    for _,line in pairs(m_lines) do
                        children[#children + 1] = line
                    end
                    element.children = children
                end
            end,
        }

        m_sheet:FireEvent("think")

        sheetParent.sheet = m_sheet
    end

end

function creature:RefreshInitiativeGrouping(token)
    if not token.canControl then
        return
    end
    local grouping = g_initiativeGroupings[self.initiativeGrouping] or {tokens = {}}
    g_initiativeGroupings[self.initiativeGrouping] = grouping

    local curFloor = dmhub.floorid
    if token.floorid ~= curFloor then
        return
    end

    local count = 0
    local removes = nil
    for charid,token in pairs(grouping.tokens) do
        if token == nil or not token.valid or (token.floorid ~= curFloor) then
            removes = removes or {}
            removes[#removes + 1] = charid
        else
            count = count + 1
        end
    end

    if removes ~= nil then
        for _,charid in ipairs(removes) do
            grouping.tokens[charid] = nil
        end
    end

    if grouping.tokens[token.charid] == nil then
        grouping.tokens[token.charid] = token
        count = count+1
    end

    if count > 1 then
        GroupingHud(self.initiativeGrouping)
    end



end

function  creature:GetTitles()
    return self:get_or_add("titles", {})
end

function creature:AddTitle(titleid)
    local titles = self:GetTitles()
    titles[titleid] = true
end

function creature:SetTitles(titles)
    self.titles = titles
end

function creature:Titles()
    local results = {}
    local titles = self:GetTitles()
    local t = dmhub.GetTable(Title.tableName) or {}
    for titleid,_ in pairs(titles) do
        local titleInfo = t[titleid]
        if titleInfo ~= nil then
            results[#results + 1] = titleInfo
        end
    end
    return results
end

dmhub.RegisterEventHandler("ClearTemporaryState", function()
    print("CLEARSTATE:: CLEARING STATE", #dmhub.allTokens)

end)
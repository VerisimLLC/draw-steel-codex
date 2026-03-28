local mod = dmhub.GetModLoading()

local function track(eventType, fields)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    fields.type = eventType
    fields.userid = dmhub.userid
    fields.gameid = dmhub.gameid
    fields.version = dmhub.version
    analytics.Event(fields)
end

-- The InitiativeQueue records the initiative of any tokens that have been given initiative. It is
-- stored in the Game Document and thus networked between systems. The initiative queue can be nil,
-- which means that there is currently no initiative and players move with free movement.
--
-- The core part of the InitiativeQueue is the entries, which are keyed by 'Initiative ID'.
-- Initiative ID is a string which can be either:
--   - a token id, in which case the initiative entry is for a single token, normally used for characters; or,
--   - a monster type name, with a MONSTER- prefix. In this case the initiative entry represents all monsters of that type.
--
-- The Initiative Queue also stores the current 'round', starting at 1. Generally when the initiative queue is created, it
-- will start at round 1, representing the first round of combat. Initiative entries store the round at which the associated tokens
-- get to move. The "current initiative entry" -- aka whose turn it is -- is the highest initiative that is eligible to move this round.
-- When a token ends their turn, their initiative entry has the current round incremented.

--- @class InitiativeQueue
InitiativeQueue = RegisterGameType("InitiativeQueue")

--- @class InitiativeQueueEntry
InitiativeQueueEntry = RegisterGameType("InitiativeQueueEntry")

function InitiativeQueue:GameModeInfo()
    return self.GameModesById[self.gameMode] or self.GameModesById["exploration"]
end

InitiativeQueue.GameModes = {}
InitiativeQueue.GameModesById = {}
InitiativeQueue.gameMode = "exploration"
InitiativeQueue.playersGoFirst = true
InitiativeQueue.playersTurn = false

function InitiativeQueue.RegisterGameMode(info)
    local targetIndex = #InitiativeQueue.GameModes + 1
    for i,mode in ipairs(InitiativeQueue.GameModes) do
        if mode.id == info.id then
            targetIndex = i
            break
        end
    end

    InitiativeQueue.GameModes[targetIndex] = info
    InitiativeQueue.GameModesById[info.id] = info
end

InitiativeQueue.RegisterGameMode{
    id = "exploration",
    text = "Exploration",
}

InitiativeQueue.RegisterGameMode{
    id = "combat",
    hasinitiative = true,
    text = "Draw Steel!",
}

InitiativeQueue.RegisterGameMode{
    id = "respite",
    text = "Respite",
}

InitiativeQueue.RegisterGameMode{
    id = "downtime",
    text = "Downtime",
}

dmhub.TokensAreFriendly = function(a,b)
	local initiative = dmhub.initiativeQueue
	if initiative == nil or initiative.hidden then
		return nil
	end

	local playera = initiative:IsEntryPlayer(InitiativeQueue.GetInitiativeId(a))
	local playerb = initiative:IsEntryPlayer(InitiativeQueue.GetInitiativeId(b))

	if playera == nil or playerb == nil then
		return nil
	end

	return playera == playerb
end

--just some default InitiativeQueueEntry values.
InitiativeQueueEntry.round = 0
InitiativeQueueEntry.turn = 0
InitiativeQueueEntry.initiative = 0
InitiativeQueueEntry.dexterity = 0
InitiativeQueueEntry.turnsPerRound = 1
InitiativeQueueEntry.turnsTaken = 0

--Create a new empty initiative queue. Called when the DM starts initiative.
function InitiativeQueue.Create()
	local playersGoFirst = math.random(1, 2) == 1
	return InitiativeQueue.new{
		guid = dmhub.GenerateGuid(),
        playersGoFirst = playersGoFirst,
		playersTurn = playersGoFirst,
		currentTurn = false,
		turn = 1,
		round = 1,
		hidden = false,
        gameMode = "combat",
		entries = CreateTable(),
	}
end

function InitiativeQueue:ChoosingTurn()
	return self.currentTurn == false
end

function InitiativeQueue.GetTokensForInitiativeId(initiativeid, allTokens)
    if allTokens == nil then
        allTokens = dmhub.allTokens
    end

	local result = {}

	if string.starts_with(initiativeid, 'MONSTER-') then
		local monsterType = string.sub(initiativeid, 9, -1)

		for k,tok in pairs(allTokens) do
			if tok.properties ~= nil and (tok.properties:GetMonsterType() == monsterType or tok.properties:MinionSquad() == monsterType) and (dmhub.isDM or not tok.invisibleToPlayers) then
				result[#result+1] = tok
			end
		end
    end

    local token = dmhub.GetTokenById(initiativeid)
    if token ~= nil and token.properties.initiativeGrouping ~= initiativeid then
        result[#result+1] = token
    end

    for k,tok in pairs(allTokens) do
        if tok.properties.initiativeGrouping == initiativeid then
            result[#result+1] = tok
        end
    end

	return result
end

function InitiativeQueue:EntriesUnmoved()

    local allTokens = dmhub.allTokens
	local result = {}
	for k,entry in pairs(self.entries) do
		if entry.round <= self.round and #self.GetTokensForInitiativeId(k, allTokens) > 0 then
			result[k] = entry
		end
	end

    --if we have priorityids then list them as the only ids remaining until
    --they are cleared.
    local priorityids = self:try_get("priorityids")
    if priorityids ~= nil then
        local havePriority = false
        for k,entry in pairs(result) do
            if priorityids[k] == true then
                havePriority = true
                break
            end
        end

        if havePriority then
            for k,entry in pairs(result) do
                if not priorityids[k] then
                    result[k] = nil
                end
            end
        end
    end

	return result
end

function InitiativeQueue:EntryUnmoved(entry)
	return entry.round <= self.round
end

function InitiativeQueue:BothSidesHaveUnmovedEntries()
	local entriesUnmoved = self:EntriesUnmoved()
    local hasPlayers = false
    local hasMonsters = false
    for k,entry in pairs(entriesUnmoved) do
        if self:IsEntryPlayer(k) then
            hasPlayers = true
        else
            hasMonsters = true
        end
    end

    return hasPlayers and hasMonsters
end

function InitiativeQueue:IsPlayersTurn()
	local hasPlayers = false
	local hasMonsters = false
	local entriesUnmoved = self:EntriesUnmoved()
	for k,entry in pairs(entriesUnmoved) do
		if self:IsEntryPlayer(k) then
			hasPlayers = true
		else
			hasMonsters = true
		end
	end

	if hasPlayers and not hasMonsters then
		return true
	end

	if hasMonsters and not hasPlayers then
		return false
	end

	return self.playersTurn
end

function InitiativeQueue:SelectTurn(initiativeid)
	local entry = self.entries[initiativeid]
	if entry == nil then
		print("Error: Initiativeid not found", initiativeid)
		return
	end

	entry.turn = self.turn
	self.turn = self.turn + 1
	entry.startTurnTimestamp = ServerTimestamp()

	self.currentTurn = initiativeid
end

--for a token give the initiative id. This is the token id if the token is a
--unique character, or the monster type if the token is a monster.
function InitiativeQueue.GetInitiativeId(token)
    if token.properties.initiativeGrouping then
        return token.properties.initiativeGrouping
    end

	local squadid = token.properties:MinionSquad()
	if squadid ~= nil then
		return 'MONSTER-' .. dmhub.SanitizeDatabaseKey(squadid)
	end

	return token.id
end

function InitiativeQueue:CancelTurn(initiativeid)
	local entry = self.entries[initiativeid]
	if entry ~= nil then
		entry.turn = self.turn + 1
	end

	self.turn = self.turn-1
	self.currentTurn = false
end

function InitiativeQueue:SetPriority(initiativeid)
    local priorityids = self:get_or_add("priorityids", {})
    priorityids[initiativeid] = true
end

function InitiativeQueue.SetTurnNotTaken(self, entry)
    entry.round = self.round
end

function InitiativeQueue.SetTurnTaken(self, entry)
	local tokens = self.GetTokensForInitiativeId(entry.initiativeid)
	if tokens ~= nil then
		for _,tok in ipairs(tokens) do
			if tok ~= nil then
				if tok.properties:TurnsPerRound() ~= entry.turnsPerRound then
					entry.turnsPerRound = tok.properties:TurnsPerRound()
				end
			end
		end
	end

	entry.endTurnTimestamp = ServerTimestamp()
	if entry.turnsPerRound > 1 then
		if entry.round < self.round then
			entry.turnsTaken = 0
			entry.round = self.round
		end
		entry.turnsTaken = entry.turnsTaken + 1
		if entry.turnsTaken >= entry.turnsPerRound then
			entry.round = self.round+1
			entry.turnsTaken = 0
		end
	else
		entry.round = self.round+1
	end
end

--End a token's turn and go to the next turn.
function InitiativeQueue.NextTurn(self, initiativeid)
    local priorityids = self:try_get("priorityids")
    if priorityids ~= nil then
        priorityids[initiativeid] = nil
    end

	--find this entry and increment the round it moves at.
	local entry = self.entries[initiativeid]
	if entry ~= nil then
        local startTimestamp = entry:try_get("startTurnTimestamp")
        local turnDuration = (startTimestamp ~= nil and type(startTimestamp) == "number") and TimestampAgeInSeconds(startTimestamp) or nil

        local isPlayer = self:IsEntryPlayer(initiativeid)
        local tokenName = "unknown"
        local isHero = false
        local tokens = self.GetTokensForInitiativeId(initiativeid)
        if tokens ~= nil and #tokens > 0 then
            local tok = tokens[1]
            if tok.properties:IsHero() then
                isHero = true
                local classInfo = tok.properties:GetClass()
                tokenName = classInfo and classInfo.name or "hero"
            else
                tokenName = tok.properties:try_get("monster_type", "monster")
            end
        end

        track("turn_end", {
            turnDurationSeconds = turnDuration and math.floor(turnDuration) or nil,
            tokenName = tokenName,
            isHero = isHero,
            isDirector = isPlayer == false,
            roundNumber = self.round,
            turnInRound = entry.turn,
            dailyLimit = 100,
        })

        InitiativeQueue.SetTurnTaken(self, entry)
	end

	self.currentTurn = false

	self.playersTurn = not self.playersTurn

    local allTokens = dmhub.allTokens
	--are there any more tokens that are going to move this round?
	--if not then increment the current round.
	for k,v in pairs(self.entries) do
		if #self.GetTokensForInitiativeId(k, allTokens) > 0 and v.round <= self.round then
			return false
		end
	end

	self:NextRound()
	return true
end

function InitiativeQueue.NextRound(self)
	self.playersTurn = self.playersGoFirst
	self.round = self.round+1
	self.turn = 1
    self.priorityids = nil

    local maliceInfo = {}
    local maliceGain = self:CalculateMaliceGain(maliceInfo)
    
    CharacterResource.SetMalice(CharacterResource.GetMalice() + maliceGain, string.format("+%d malice (Round %d, %d heroes present)", maliceGain, maliceInfo.round, maliceInfo.numHeroes))
    CharacterResource.SetVillainActions(1)

    audio.DispatchSoundEvent("UI.RoundStart")
end

function InitiativeQueue:CalculateMaliceGain(notes)
    local numHeroes = 0
    local allTokens = dmhub.allTokens
	for k,v in pairs(self.entries) do
        if self:IsEntryPlayer(k) then
            local tokens = self.GetTokensForInitiativeId(k, allTokens)
            for _,tok in ipairs(tokens) do
                if tok.properties:IsHero() and not tok.properties:IsDead() then
                    numHeroes = numHeroes + 1
                end
            end
        end
    end

    if notes ~= nil then
        notes.numHeroes = numHeroes
        notes.round = self.round
    end

    return numHeroes + self.round
end

--does this initiative id have an entry?
function InitiativeQueue.HasInitiative(self, initiativeid)
	local entry = self.entries[initiativeid]
	return entry ~= nil
end

function InitiativeQueue:IsEntryPlayer(initiativeid)
	local entry = self.entries[initiativeid]
	if entry == nil then
		return nil
	end

	if entry:has_key("player") then
		return entry.player
	end

	if string.starts_with(entry.initiativeid, 'MONSTER-') then
		return false
	end

	local token = dmhub.GetCharacterById(entry.initiativeid)
	if token == nil then
        if string.starts_with(entry.initiativeid, 'PLAYERS-') then
            return true
        end
		return false
	end

	return token.playerControlled
end

function InitiativeQueue:DescribeEntry(initiativeid)
	local entry = self.entries[initiativeid]
	if entry == nil or entry:has_key("description") == false then
		if string.startswith(entry.initiativeid, 'MONSTER-') then
			return string.sub(entry.initiativeid, 9)
		else
			local token = dmhub.GetCharacterById(entry.initiativeid)
			if token ~= nil then
				return token.description
			end
		end
		return "Unknown, possibly deleted character"
	end

	return entry.description
end

--set the initiative for a given initiative id, creating an entry if necessary.
--also optionally set the token's dexterity, which is used for tie breakers.
function InitiativeQueue.SetInitiative(self, initiativeid, value, dexterity)
	local entry = self.entries[initiativeid]
	if entry == nil then
		entry = InitiativeQueueEntry.new{
			round = self.round,
			initiativeid = initiativeid,
			initiative = value,
			dexterity = dexterity or 0,
		}

		if GameHud.instance ~= nil and GameHud.instance:has_key("initiativeInterface") then
			local tokens = self.GetTokensForInitiativeId(initiativeid)
			if tokens ~= nil and #tokens > 0 then
				entry.description = tokens[1].description

				local turnsPerRound = tokens[1].properties:TurnsPerRound()
				if turnsPerRound ~= InitiativeQueueEntry.turnsPerRound then
					entry.turnsPerRound = turnsPerRound
				end
			end
		end
	else
		entry.initiative = value
		if dexterity ~= nil then
			entry.dexterity = value
		end
	end

	self.entries[initiativeid] = entry
    return self.entries[initiativeid]
end

--remove an initiative entry, if it exists.
function InitiativeQueue.RemoveInitiative(self, initiativeid)
	self.entries[initiativeid] = nil
end

--given an entry in the initiative queue, return 'ord', a number which is higher
--the closer to the front of the initiative queue the entry is.
function InitiativeQueue:GetEntryOrd(entry)
    if entry == nil then
        return 0
    end
	local currentTurn = entry.initiativeid == self.currentTurn
	return cond(currentTurn, 10000000, 0) + -entry.round*1000 + self:GetEntryOrdAbsolute(entry)
end

function InitiativeQueue:GetEntryOrdAbsolute(entry)
    if entry == nil then
        return 0
    end
	local currentTurn = entry.initiativeid == self.currentTurn
	return entry.round + cond(currentTurn, 0.001, 0) - entry.turn*0.0001
end

--get the entry for the first item in the initiative queue -- i.e. whose turn it currently is.
function InitiativeQueue:GetFirstInitiativeEntry()
	return self.entries[self.currentTurn]
end

function InitiativeQueue:HasHadTurn(initiativeid)
	local entry = self.entries[initiativeid]
	if entry == nil then
		return nil
	end

	return entry.round > self.round
end

function InitiativeQueue:CurrentInitiativeId()
	if self.hidden or self:ChoosingTurn() then
		return nil
	end

	local entry = self:GetFirstInitiativeEntry()
	if entry ~= nil then
		return entry.initiativeid
	end

	return nil
end

--get the tokenid of the character whose turn it is currently.
function InitiativeQueue:CurrentPlayer()
	if self.hidden then
		return nil
	end

	local entry = self:GetFirstInitiativeEntry()

	if entry == nil or string.startswith(entry.initiativeid, 'MONSTER-') then
		return nil
	end

	return entry.initiativeid
end

--gets a unique ID for the round of combat this token considers it to be.
--This controls when resources for the token are refreshed. In DS they refresh on a round
--basis so it's just the round ID.
function InitiativeQueue:GetRoundIdForToken(token)
	if self.hidden then
		return nil
	end

	return self:GetRoundId()
end

--gets a unique ID for this round in this combat.
function InitiativeQueue:GetRoundId()
	if self.hidden then
		return nil
	end

	return string.format('%s-%d', self.guid, self.round)
end

--gets a unique ID for this turn in this combat.
function InitiativeQueue:GetTurnId()
	if self.hidden then
		return nil
	end

	local entry = self:GetFirstInitiativeEntry()
	if entry == nil or entry.initiativeid == nil then
		return nil
	end

	return string.format("%s-%s", self:GetRoundId(), entry.initiativeid)
end

--called by DMHub to query the current combat round. zero-based result.
function GetCombatRound(initiativeQueue)
	if initiativeQueue == nil or initiativeQueue.hidden then
		return 0
	end

	return initiativeQueue.round - 1
end


--make it so when we adde from the bestiary if initiative is active we roll initiative for them.
dmhub.RegisterEventHandler("spawnFromBestiary", function(charids)
    if dmhub.initiativeQueue ~= nil and not dmhub.initiativeQueue.hidden then

        local attempts = 20

        local addToInitiative
        addToInitiative = function()
            local tokens = {}
            for _,charid in ipairs(charids) do
                local token = dmhub.GetTokenById(charid)
                print("SPAWN:: FIND:", charid, token)
                if token == nil then
                    if attempts <= 0 then
                        return
                    end

                    attempts = attempts - 1
                    dmhub.Schedule(0.1, addToInitiative)
                    return
                end
                tokens[#tokens+1] = token
            end

            if #tokens > 0 then
                dmhub.selectedTokens = tokens
                Commands.rollinitiative()
            end
        end

        addToInitiative()
    end 
end)
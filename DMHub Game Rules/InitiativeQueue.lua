local mod = dmhub.GetModLoading()

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
--- @field guid string Unique identifier.
--- @field round number Current combat round (starts at 1).
--- @field hidden boolean If true, initiative is hidden from players.
--- @field entries table<string, InitiativeQueueEntry> Map of initiative id to entry.
--- Stores and manages the turn order for all tokens in an encounter.
--- Initiative id is either a token id (characters) or "MONSTER-<type>" (grouped monsters).
InitiativeQueue = RegisterGameType("InitiativeQueue")

--- @class InitiativeQueueEntry
--- @field round number The round at which this entry will next act (incremented when their turn ends).
--- @field initiative number Initiative roll result.
--- @field dexterity number Dexterity score used for tie-breaking.
--- @field initiativeid string The initiative id (token id or "MONSTER-<type>") for this entry.
--- @field description nil|string Optional display name override.
--- @field endTurnTimestamp nil|number Server timestamp recorded when this entry last ended its turn.
InitiativeQueueEntry = RegisterGameType("InitiativeQueueEntry")

--just some default InitiativeQueueEntry values.
InitiativeQueueEntry.round = 0
InitiativeQueueEntry.initiative = 0
InitiativeQueueEntry.dexterity = 0

--Create a new empty initiative queue. Called when the DM starts initiative.
function InitiativeQueue.Create()
	return InitiativeQueue.new{
		guid = dmhub.GenerateGuid(),
		round = 1,
		hidden = false,
		entries = CreateTable(),
	}
end

--for a token give the initiative id. This is the token id if the token is a
--unique character, or the monster type if the token is a monster.
function InitiativeQueue.GetInitiativeId(token)
	if dmhub.GetSettingValue("individualMonsterInitiative") == false and token.properties ~= nil and token.properties:GetMonsterType() ~= nil then
		return 'MONSTER-' .. dmhub.SanitizeDatabaseKey(token.properties:GetMonsterType())
	end

	return token.id
end

--End a token's turn and go to the next turn.
function InitiativeQueue.NextTurn(self, initiativeid)

	--find this entry and increment the round it moves at.
	local entry = self.entries[initiativeid]
	if entry ~= nil then
		entry.round = self.round+1
		entry.endTurnTimestamp = ServerTimestamp()
	end

	--are there any more tokens that are going to move this round?
	--if not then increment the current round.
	for k,v in pairs(self.entries) do
		if v.round <= self.round then
			return
		end
	end

	self.round = self.round+1
end

--does this initiative id have an entry?
function InitiativeQueue.HasInitiative(self, initiativeid)
	local entry = self.entries[initiativeid]
	return entry ~= nil
end

function InitiativeQueue:DescribeEntry(initiativeid)
	local entry = self.entries[initiativeid]
	if entry == nil then
		return "Unknown, possibly deleted character"
	end
	if entry:has_key("description") == false then
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
			local tokens = GameHud.instance:GetTokensForInitiativeId(GameHud.instance.initiativeInterface, initiativeid)
			if tokens ~= nil and #tokens > 0 then
				entry.description = tokens[1].description
			end
		end
	else
		entry.initiative = value
		if dexterity ~= nil then
			entry.dexterity = dexterity
		end
	end

	self.entries[initiativeid] = entry
end

--remove an initiative entry, if it exists.
function InitiativeQueue.RemoveInitiative(self, initiativeid)
	self.entries[initiativeid] = nil
end

--given an entry in the initiative queue, return 'ord', a number which is higher
--the closer to the front of the initiative queue the entry is.
function InitiativeQueue.GetEntryOrd(entry)
	return -entry.round*1000 + InitiativeQueue.GetEntryOrdAbsolute(entry)
end

function InitiativeQueue.GetEntryOrdAbsolute(entry)
	return entry.initiative*cond(GameSystem.LowerInitiativeIsFaster, -1, 1) + entry.dexterity*0.01
end

--get the entry for the first item in the initiative queue -- i.e. whose turn it currently is.
function InitiativeQueue:GetFirstInitiativeEntry()
	local result = nil
	local ord = 0
	local initiativeid = nil
	for k,entry in pairs(self.entries) do
		local newOrd = InitiativeQueue.GetEntryOrd(entry)
		if result == nil or newOrd > ord or (newOrd == ord and entry.initiativeid > initiativeid) then
			ord = newOrd
			result = entry
			initiativeid = entry.initiativeid
		end
	end

	return result
end

function InitiativeQueue:HasHadTurn(initiativeid)
	local entry = self.entries[initiativeid]
	if entry == nil then
		return nil
	end

	return entry.round > self.round
end

function InitiativeQueue:CurrentInitiativeId()
	if self.hidden then
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

--gets a unique ID for the next round the given token will take in combat.
function InitiativeQueue:GetRoundIdForToken(token)
	if self.hidden then
		return nil
	end


	if token ~= nil then
		local initiativeid = InitiativeQueue.GetInitiativeId(token)
		for k,entry in pairs(self.entries) do
			if k == initiativeid then

				--if it's our turn we return the id for next turn, since we want to refresh at the start of the turn, not the end.
				local thisturn = (self:GetFirstInitiativeEntry() == entry)
				return string.format('%s-%d', self.guid, entry.round + cond(thisturn, 1, 0))
			end
		end
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


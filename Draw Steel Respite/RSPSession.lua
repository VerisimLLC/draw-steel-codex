local mod = dmhub.GetModLoading()

--- One character's standing in a Respite.
--- @class RSPCharacter
--- @field participating boolean
--- @field done boolean
RSPCharacter = RegisterGameType("RSPCharacter")

RSPCharacter.participating = false
RSPCharacter.done = false

--- @param args nil|table
--- @return RSPCharacter
function RSPCharacter.CreateNew(args)
    return RSPCharacter.new(args or {})
end

--- The Respite in progress. It lives in this module's shared document, so the
--- Director and every player read and write one instance. No panel keeps a
--- copy: the document is the model and the panels are the view.
--- @class RSPSession
--- @field id string
--- @field phase string
--- @field daysElapsed number
--- @field activityCount number
--- @field nonParticipantsMayAct boolean
--- @field journal boolean write the Respite up when it ends
--- @field activities table<string, table> per-activity availability for this Respite
--- @field characters table<string, RSPCharacter>
--- @field commits table<string, boolean>
RSPSession = RegisterGameType("RSPSession")

RSPSession.phase = RSPConstants.phaseSetup
RSPSession.daysElapsed = 1
RSPSession.activityCount = 1
RSPSession.nonParticipantsMayAct = true
RSPSession.journal = true

mod:RegisterDocumentForCheckpointBackups(RSPConstants.sessionDoc)

--- @param args nil|table
--- @return RSPSession
function RSPSession.CreateNew(args)
    args = args or {}
    args.id = args.id or dmhub.GenerateGuid()
    args.activities = args.activities or {}
    args.characters = args.characters or {}
    args.commits = args.commits or {}
    return RSPSession.new(args)
end

--- @return LuaCodeModDocumentSnapshot
function RSPSession.Doc()
    return mod:GetDocumentSnapshot(RSPConstants.sessionDoc)
end

--- @return string monitorGame path for the session
function RSPSession.DocPath()
    return mod:GetDocumentPath(RSPConstants.sessionDoc)
end

--- @return RSPSession|nil
function RSPSession.Active()
    local doc = RSPSession.Doc()
    if doc == nil or doc.data == nil then
        return nil
    end
    return doc.data.session
end

--- The Respite in progress, starting one in Setup if there is none. Opening
--- the Director's window is what calls this, which is why Setup is a real
--- phase rather than local state waiting to be committed.
--- @return RSPSession
function RSPSession.Ensure()
    local session = RSPSession.Active()
    if session ~= nil then
        return session
    end

    local doc = RSPSession.Doc()
    doc:BeginChange()
    doc.data = doc.data or {}
    doc.data.session = RSPSession.CreateNew{}
    doc:CompleteChange("Begin respite setup")

    return doc.data.session
end

--- Mutate the Respite inside one document change.
--- @param description string
--- @param fn fun(session: RSPSession)
function RSPSession.Mutate(description, fn)
    local doc = RSPSession.Doc()
    local session = doc.data ~= nil and doc.data.session or nil
    if session == nil then
        return
    end

    doc:BeginChange()
    fn(session)
    doc:CompleteChange(description)
end

--- @return number
function RSPSession.DaysElapsed()
    local session = RSPSession.Active()
    return session ~= nil and session.daysElapsed or RSPConstants.daysMin
end

--- @return number
function RSPSession.ActivityCount()
    local session = RSPSession.Active()
    return session ~= nil and session.activityCount or RSPConstants.activitiesMin
end

--- @return boolean
function RSPSession.NonParticipantsMayAct()
    local session = RSPSession.Active()
    return session ~= nil and session.nonParticipantsMayAct or false
end

--- Days and activities move together. Setting the days resets the activity
--- allowance to match; setting the activities alone leaves the days be.
--- @param days number
function RSPSession.SetDaysElapsed(days)
    RSPSession.Mutate("Set respite days elapsed", function(session)
        session.daysElapsed = days
        session.activityCount = days
    end)
end

--- @param count number
function RSPSession.SetActivityCount(count)
    RSPSession.Mutate("Set respite downtime activities", function(session)
        session.activityCount = count
    end)
end

--- @param allowed boolean
function RSPSession.SetNonParticipantsMayAct(allowed)
    RSPSession.Mutate("Set respite non-participant downtime", function(session)
        session.nonParticipantsMayAct = allowed
    end)
end

--- @param charid string
--- @return boolean
function RSPSession.IsParticipating(charid)
    local session = RSPSession.Active()
    if session == nil then
        return false
    end
    local entry = session.characters[charid]
    return entry ~= nil and entry.participating or false
end

--- @param charid string
--- @param participating boolean
function RSPSession.SetParticipating(charid, participating)
    RSPSession.Mutate("Set respite participation", function(session)
        local entry = session.characters[charid]
        if entry == nil then
            entry = RSPCharacter.CreateNew{}
            session.characters[charid] = entry
        end
        entry.participating = participating
    end)
end

--- Players who could commit: everyone in the game who is not the Director and
--- is still in contact. The same predicate the online-users panel uses.
--- @return number
function RSPSession.ConnectedPlayerCount()
    local count = 0
    for _, userid in ipairs(dmhub.users) do
        if not dmhub.IsUserDM(userid) then
            local info = dmhub.GetSessionInfo(userid)
            if info ~= nil and not info.loggedOut and info.timeSinceLastContact <= 60 then
                count = count + 1
            end
        end
    end
    return count
end

--- Commits from players who are still connected, so a player who commits and
--- then drops cannot push the count past the total.
--- @return number
function RSPSession.CommittedCount()
    local session = RSPSession.Active()
    if session == nil then
        return 0
    end

    local count = 0
    for _, userid in ipairs(dmhub.users) do
        if not dmhub.IsUserDM(userid) and session.commits[userid] then
            local info = dmhub.GetSessionInfo(userid)
            if info ~= nil and not info.loggedOut and info.timeSinceLastContact <= 60 then
                count = count + 1
            end
        end
    end
    return count
end

--- Every player-controlled character in the game, on the map or off it, in
--- alphabetical order. The default party seeds explicitly so a hidden party
--- still contributes; characters in other parties only count when they have a
--- named owner, since playerControlled is also true for party-shared tokens.
--- @return string[] charids
function RSPSession.Roster()
    local result = {}
    local seen = {}
    local partyId = GetDefaultPartyID()

    local function Consider(charid, inDefaultParty)
        if charid == nil or seen[charid] then
            return
        end

        local token = dmhub.GetCharacterById(charid)
        if token == nil or token.properties == nil then
            return
        end

        if not inDefaultParty and token.playerControlledNotShared ~= true then
            return
        end

        -- Followers are characters in their own right and would otherwise
        -- turn up here. A Respite is taken by heroes.
        local isHero = false
        pcall(function()
            isHero = token.properties:IsHero()
        end)
        if not isHero then
            return
        end

        seen[charid] = true
        result[#result + 1] = charid
    end

    for _, charid in ipairs(dmhub.GetCharacterIdsInParty(partyId) or {}) do
        Consider(charid, true)
    end

    for pid, _ in unhidden_pairs(dmhub.GetTable(Party.tableName) or {}) do
        for _, charid in ipairs(dmhub.GetCharacterIdsInParty(pid) or {}) do
            Consider(charid, pid == partyId)
        end
    end

    for _, token in ipairs(dmhub.allTokens) do
        if token ~= nil and token.valid then
            Consider(token.charid, token.partyId == partyId)
        end
    end

    table.sort(result, function(a, b)
        local ta = dmhub.GetCharacterById(a)
        local tb = dmhub.GetCharacterById(b)
        return string.lower(ta.name or "") < string.lower(tb.name or "")
    end)

    return result
end

--- Put the Respite in front of the players.
function RSPSession.Offer()
    RSPSession.Mutate("Offer respite", function(session)
        session.phase = RSPConstants.phaseOffered
    end)
end

--- Take the Respite back to Setup. The terms and the participants stand; only
--- the phase moves, so stepping forward again returns to what was there.
function RSPSession.ReturnToSetup()
    RSPSession.Mutate("Withdraw respite offer", function(session)
        session.phase = RSPConstants.phaseSetup
    end)
end

--- @param userid string
--- @return boolean
function RSPSession.IsCommitted(userid)
    local session = RSPSession.Active()
    return session ~= nil and session.commits[userid] == true
end

--- @param userid string
--- @param committed boolean
function RSPSession.SetCommitted(userid, committed)
    RSPSession.Mutate("Set respite commitment", function(session)
        session.commits[userid] = committed or nil
    end)
end

--- The heroes this client may speak for. On the Director's client that is
--- everyone, which is why only the player surfaces call it.
--- @return string[] charids
function RSPSession.MyCharacters()
    local result = {}
    for _, charid in ipairs(RSPSession.Roster()) do
        local token = dmhub.GetCharacterById(charid)
        if token ~= nil and token.canControl then
            result[#result + 1] = charid
        end
    end
    return result
end

--- End the Respite and clear it away. With no session the Director falls back
--- to Setup and the players fall back to their idle pane.
function RSPSession.Complete()
    local doc = RSPSession.Doc()
    if doc == nil or doc.data == nil then
        return
    end
    doc:BeginChange()
    doc.data.session = nil
    doc:CompleteChange("Complete respite")
end

--- Raise the Respite on every player's screen. The host element is the
--- presenting panel; GameHud fires the event on its own parent panel.
--- @param hostPanel Panel
function RSPSession.PresentToPlayers(hostPanel)
    GameHud.PresentDialogToUsers(hostPanel, RSPConstants.dialogId, {})
end

--- Take the pushed copy off the players' screens. Their Game menu entry still
--- reaches the Respite; only the push is withdrawn.
function RSPSession.HideFromPlayers()
    GameHud.HidePresentedDialog()
end

--- Has the player behind this character committed? A character owned by the
--- party answers for the table rather than one player, so it only reads as
--- committed once every connected player has.
--- @param charid string
--- @return boolean
function RSPSession.IsCommittedFor(charid)
    local token = dmhub.GetCharacterById(charid)
    if token == nil then
        return false
    end

    local ownerId = token.ownerId
    if ownerId ~= nil and ownerId ~= "PARTY" then
        return RSPSession.IsCommitted(ownerId)
    end

    local total = RSPSession.ConnectedPlayerCount()
    return total > 0 and RSPSession.CommittedCount() >= total
end

--- Will players be able to do this activity during the Respite? An activity
--- nobody has touched is on: the Director opts out, not in. This is intent
--- for the Respite, not the activity's live state - nothing is opened until
--- the Respite starts.
--- @param key string an RSPActivity key
--- @return boolean
function RSPSession.IsActivityAvailable(key)
    local session = RSPSession.Active()
    if session == nil then
        return true
    end

    local activities = session:try_get("activities")
    if activities == nil or activities[key] == nil then
        return true
    end

    return activities[key].available ~= false
end

--- @param key string an RSPActivity key
--- @param available boolean
function RSPSession.SetActivityAvailable(key, available)
    RSPSession.Mutate("Set respite activity availability", function(session)
        local activities = session:try_get("activities")
        if activities == nil then
            activities = {}
            session.activities = activities
        end
        activities[key] = {available = available}
    end)
end

--- Begin the Respite proper. Players stop choosing and start doing, which is
--- also the moment the downtime activities are paid out.
function RSPSession.Start()
    RSPSession.GrantActivityRolls()
    RSPSession.Mutate("Start respite", function(session)
        session.phase = RSPConstants.phaseActive
    end)
end

--- @param charid string
--- @return boolean
function RSPSession.IsDone(charid)
    local session = RSPSession.Active()
    if session == nil then
        return false
    end
    local entry = session.characters[charid]
    return entry ~= nil and entry.done or false
end

--- @param charid string
--- @param done boolean
function RSPSession.SetDone(charid, done)
    RSPSession.Mutate("Set respite completion", function(session)
        local entry = session.characters[charid]
        if entry == nil then
            entry = RSPCharacter.CreateNew{}
            session.characters[charid] = entry
        end
        entry.done = done
    end)
end

--- The heroes this Respite covers: everyone when non-participants may act,
--- otherwise only those taking part.
--- @param charids string[] the heroes to filter
--- @return string[] charids
function RSPSession.CoveredHeroes(charids)
    if RSPSession.NonParticipantsMayAct() then
        return charids
    end

    local result = {}
    for _, charid in ipairs(charids) do
        if RSPSession.IsParticipating(charid) then
            result[#result + 1] = charid
        end
    end
    return result
end

--- A hero's artisan and sage followers, alphabetical. Followers are characters
--- in their own right, held by id on the hero. Reads the downtime module's
--- storage, so a game without it simply has no followers.
--- @param charid string the hero
--- @return string[] charids
function RSPSession.FollowersOf(charid)
    local result = {}

    local constants = rawget(_G, "DTConstants")
    if constants == nil then
        return result
    end

    local token = dmhub.GetCharacterById(charid)
    if token == nil or token.properties == nil then
        return result
    end

    local followers = token.properties:try_get(constants.FOLLOWERS_STORAGE_KEY)
    if followers == nil then
        return result
    end

    for followerId, _ in pairs(followers) do
        local follower = dmhub.GetCharacterById(followerId)
        local followerType = nil
        pcall(function()
            if follower.properties:IsFollower() then
                followerType = string.lower(follower.properties:try_get("followerType", ""))
            end
        end)

        if followerType == "artisan" or followerType == "sage" then
            result[#result + 1] = followerId
        end
    end

    table.sort(result, function(a, b)
        local ta = dmhub.GetCharacterById(a)
        local tb = dmhub.GetCharacterById(b)
        return string.lower(ta.name or "") < string.lower(tb.name or "")
    end)

    return result
end

--- Heroes with their followers indented beneath them, ready for a list.
--- @param charids string[] heroes, already in the order they should appear
--- @return table[] entries {charid, indent}
function RSPSession.EntriesWithFollowers(charids)
    local entries = {}
    for _, charid in ipairs(charids) do
        entries[#entries + 1] = {charid = charid, indent = false}
        for _, followerId in ipairs(RSPSession.FollowersOf(charid)) do
            entries[#entries + 1] = {charid = followerId, indent = true, owner = charid}
        end
    end
    return entries
end

--- Should the Respite be written up when it ends? Recorded now, acted on when
--- the closing report is built.
--- @return boolean
function RSPSession.JournalWanted()
    local session = RSPSession.Active()
    return session ~= nil and session.journal or false
end

--- @param wanted boolean
function RSPSession.SetJournalWanted(wanted)
    RSPSession.Mutate("Set respite journal record", function(session)
        session.journal = wanted
    end)
end

--- Is this character a hero the Respite covers, rather than a follower riding
--- along under one? Only heroes are marked complete.
--- @param charid string
--- @return boolean
function RSPSession.IsHeroInRespite(charid)
    for _, heroId in ipairs(RSPSession.CoveredHeroes(RSPSession.Roster())) do
        if heroId == charid then
            return true
        end
    end
    return false
end

--- A hero's own downtime rolls.
--- @param charid string
--- @return number
function RSPSession.HeroRolls(charid)
    local token = dmhub.GetCharacterById(charid)
    if token == nil or token.properties == nil then
        return 0
    end

    local rolls = 0
    pcall(function()
        local info = token.properties:GetDowntimeInfo()
        if info ~= nil then
            rolls = info:GetAvailableRolls()
        end
    end)
    return rolls
end

--- A follower's downtime rolls, which are kept on the hero they follow.
--- @param heroId string
--- @param followerId string
--- @return number
function RSPSession.FollowerRolls(heroId, followerId)
    local token = dmhub.GetCharacterById(heroId)
    if token == nil or token.properties == nil then
        return 0
    end

    local rolls = 0
    pcall(function()
        local info = token.properties:GetDowntimeInfo()
        if info ~= nil then
            rolls = info:GetFollowerRolls(followerId)
        end
    end)
    return rolls
end

--- A hero's rolls plus every roll held for their followers, which is what the
--- Director cares about: one number per hero.
--- @param charid string
--- @return number
function RSPSession.CombinedRolls(charid)
    local token = dmhub.GetCharacterById(charid)
    if token == nil or token.properties == nil then
        return 0
    end

    local rolls = RSPSession.HeroRolls(charid)
    pcall(function()
        local followers = token.properties:GetDowntimeFollowers()
        if followers ~= nil then
            rolls = rolls + followers:AggregateAvailableRolls()
        end
    end)
    return rolls
end

--- Hand out the Respite's downtime activities. Every covered hero and each of
--- their followers gets one roll per activity, so unticking non-participants
--- narrows who is paid as well as who appears.
function RSPSession.GrantActivityRolls()
    if not dmhub.isDM then
        return
    end

    local count = RSPSession.ActivityCount()
    if count <= 0 then
        return
    end

    for _, heroId in ipairs(RSPSession.CoveredHeroes(RSPSession.Roster())) do
        local token = dmhub.GetCharacterById(heroId)
        local followerIds = RSPSession.FollowersOf(heroId)

        if token ~= nil and token.properties ~= nil then
            token:ModifyProperties{
                description = "Grant respite downtime rolls",
                execute = function()
                    local info = token.properties:GetDowntimeInfo()
                    if info == nil then
                        return
                    end

                    info:GrantRolls(count)
                    for _, followerId in ipairs(followerIds) do
                        info:GrantFollowerRolls(followerId, count)
                    end
                end,
            }
        end
    end
end

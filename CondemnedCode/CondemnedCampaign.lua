local mod = dmhub.GetModLoading()

--------------------------------------------------------------------------------
-- The Condemned: the Campaign panel
--------------------------------------------------------------------------------
--The Director's record of the adventure's running numbers and branch choices: where
--the story has got to, who still wears a collar, intel and alarm, how each Condemned
--has treated Gerold's head, the Crysopolis and Part 3 choices, the Justice's Stamina
--in the finale, and which ending the table has earned. It opens from the "Campaign"
--button on the Director's icon rail (Condemned.lua registers the button).
--
--Sections unlock as the story reaches them. The story stage moves on when the
--Director presses Next, and by itself when one of the adventure's combats starts
--(see ENCOUNTER_STAGES). Reaching a stage can switch things on: the clocks, the
--players' Intel Tracker and the starting intel, the Justice's Stamina.
--
--Storage:
--  * CampaignState (DocumentSystem/CampaignTrackerPanel.lua) holds the named flags
--    and counters, the same keys the journal's exit cards write (intel_score,
--    alarm_level, documents_saved, khavettra_ally, letitia_rescued, ...), with its
--    ledger as the campaign log.
--  * The "condemnedCampaign" document holds what does not fit a flag or a counter:
--    the stage, per-hero collar records and Gerold standing, one-time grants claimed.
--  * Who wears a collar right now is the token frame, and who was blown up is the
--    "condemnedCollars" document, both owned by Condemned.lua (CondemnedCollars).

local DOC_ID = "condemnedCampaign"
local INTEL_ENABLED_FLAG = "intel_tracker_enabled"

--intel and alarm keep the Intel Tracker's own colours, so the two panels read as one.
local INTEL_COLOR = "#56b8b0"

--the Condemned journal's link colour (#8a6a2e on parchment), lightened to read on
--the app's dark panels.
local BOOK_LINK_COLOR = "#C9A063"
local BOOK_LINK_HOVER = "#E8C78C"
local ALARM_COLOR = "#e8a030"

local JUSTICE_START = 175
local JUSTICE_MAX = 200
local PANEL_WIDTH = 660
local PAGE_HEIGHT = 640

local PART_NAMES = {
    [1] = "Part 1: Secure the Route",
    [2] = "Part 2: Infiltrate the Crysopolis",
    [3] = "Part 3: Rescue the Asset",
    [4] = "Endings",
}

--------------------------------------------------------------------------------
-- The story, in book order
--------------------------------------------------------------------------------
--page = the journal page to open for the stage. note = what to run and track there.
--onReach (optional) runs once, on the Director's client, the first time the stage is
--reached; see RunReachEffects.
local STAGES = {
    { id = "cauldron", part = 1, name = "Out of the Cauldron", page = "Out of the Cauldron ...",
      note = "The prison and de Caserta's briefing, with the collar demonstration. Refusing the Call: blowing one collar gives the party a hero token." },
    { id = "heist", part = 1, name = "Plotting the Heist", page = "Plotting the Heist",
      note = "The one-hour clock starts. It only matters if they leave the neighbourhood, rest or do long work.",
      onReach = "part1clock" },
    { id = "abbey", part = 1, name = "The Abbey of Saint Iphicrates", page = "The Abbey of Saint Iphicrates",
      note = "Inner Sanctum and Hidden Basement, one combat. The script records the fire, Gerold's flight and the documents saved. No Victories for the fight itself." },
    { id = "return", part = 1, name = "Returning to de Caserta", page = "Returning to de Caserta",
      note = "2 Victories each if a document came back, otherwise 1. Then Gearing Up (three grenades and one gear each) and a respite." },
    { id = "head", part = 1, name = "Getting Ahead", page = "Getting Ahead",
      note = "Gerold's head goes with one Condemned. Keep note of how each of them treats him: Spider Gerold remembers." },
    { id = "briefing", part = 2, name = "Mission Briefing", page = "Mission Briefing",
      note = "Part 2 begins. The 48-hour clock starts; the party gets one respite in the Crysopolis.",
      onReach = "missionclock" },
    { id = "teleport", part = 2, name = "Return to the Abbey", page = "Return to the Abbey",
      note = "Sergeant Dalla takes them to the basement. Gerold begs them to take the Riojan Gold if it is still there." },
    { id = "hub", part = 2, name = "Entering the Crysopolis", page = "Combat: Entering the Crysopolis",
      note = "The Teleportation Hub. Violence here puts up wanted posters; any war dog that survives starts the alarm at 1. 1 Victory for getting out. Intel and alarm are now in play.",
      onReach = "intel" },
    { id = "lowercity", part = 2, name = "The Lower City", page = "The Crysopolis Revealed",
      note = "Gathering Intel, then the Exploring the Lower City montage (+5 / +3 / +1 intel; 1 Victory whatever the outcome)." },
    { id = "redoubt", part = 2, name = "Getting Inside the Redoubt", page = "Getting Inside the Redoubt",
      note = "The gate (6 + alarm intel) or the sewers (bluff, negotiate with the Dwarf Warden, or fight). 1 Victory for getting in." },
    { id = "khavettra", part = 2, name = "Safe Harbor", page = "Safe Harbor",
      note = "Khavettra: +3 intel, a safehouse respite and a chatbox if they work with him." },
    { id = "recordcontrol", part = 2, name = "Record Control", page = "Negotiation or Combat: Record Control",
      note = "Gerold is torn away into the Returns slot. Negotiate with the Archivist or fight him: 2 Victories either way." },
    { id = "armory", part = 3, name = "Entering the Armory", page = "Advanced Research",
      note = "Part 3. Continue the mission through the Armory (montage, Restricted Elevator), or abandon it and run for the Sky Harbor." },
    { id = "asset", part = 3, name = "Securing the Asset", page = "Combat: Securing the Asset",
      note = "The Factory Floor. The security door: 3 intel, a hard Pick the Lock, or break it. Lady Letitia is rescued when it opens. 1 Victory." },
    { id = "bluepowder", part = 3, name = "The Bluepowder Cache", page = "Combat: Bluepowder Cache Room",
      note = "Letitia will not leave until all three crate stacks are lit. 2 Victories." },
    { id = "skyharbor", part = 3, name = "Sky Harbor Airfield", page = "Combat: Sky Harbor Airfield",
      note = "If the bluepowder was lit, the Armory explodes at the end of round 2. Spider Gerold's Now Our Debts Are Paid reads how each target treated the head. 2 Victories." },
    { id = "finale", part = 3, name = "Flying the Cruiser", page = "Montage Test: Action Stations!",
      note = "Action Stations: three rounds; the Justice's Stamina is the party's health bar. The Medical station takes collars off.",
      onReach = "justice" },
    { id = "ending", part = 4, name = "Choice of Endings", page = "Choice of Endings",
      note = "The ending follows from Lady Letitia and the collars. Level 4 comes with Ending 3 or 4." },
}

local STAGE_INDEX = {}
for i, stage in ipairs(STAGES) do
    STAGE_INDEX[stage.id] = i
end

--An adventure combat going live moves the story to its stage (never backwards).
local ENCOUNTER_STAGES = {
    ["Inner Sanctum and Hidden Basement"] = "abbey",
    ["Entering the Crysopolis"] = "hub",
    ["Entering the Sewers"] = "redoubt",
    ["Fighting the Archivist"] = "recordcontrol",
    ["Securing the Asset"] = "asset",
    ["Bluepowder Cache Room"] = "bluepowder",
    ["Sky Harbor Airfield"] = "skyharbor",
    ["Flying the Cruiser"] = "finale",
}
local STRIKE_TEAM_ENCOUNTER = "War Dog Strike Team"

--------------------------------------------------------------------------------
-- The book: The Condemned v1.1 PDF
--------------------------------------------------------------------------------
--Page numbers below are the PDF's page indexes (what the viewer and the page
--renderer take). The printed page number is 3 less: index 60 is printed page 57.
local BOOK_ID = "f0243d98-6601-4e3f-9500-3b305fa48d26"
local BOOK_NAME = "The Condemned v1.1"
local BOOK_PAGE_OFFSET = 3

--where each story stage starts in the book: { pageIndex, heading, untilHeading }.
local STAGE_BOOK = {
    cauldron = { 7, "Out of the Cauldron" },
    heist = { 8, "Plotting the Heist" },
    abbey = { 9, "The Abbey of Saint Iphicrates" },
    ["return"] = { 15, "Returning to de Caserta" },
    head = { 15, "Getting Ahead" },
    briefing = { 17, "Mission Briefing" },
    teleport = { 18, "Return to the Abbey" },
    hub = { 18, "Combat: Entering the Crysopolis" },
    lowercity = { 22, "The Crysopolis Revealed" },
    redoubt = { 26, "Getting Inside the Redoubt" },
    khavettra = { 29, "Safe Harbor" },
    recordcontrol = { 31, "Negotiation or Combat: Record Control" },
    armory = { 34, "Advanced Research" },
    asset = { 35, "Combat: Securing the Asset" },
    bluepowder = { 39, "Combat: Bluepowder Cache Room" },
    skyharbor = { 41, "Combat: Sky Harbor Airfield" },
    finale = { 45, "Montage Test: Flying the Cruiser" },
    ending = { 49, "Choice of Endings", "Continuing the Campaign" },
}

--The player handouts (the book's handout appendix). Each is rendered to an image
--and shared with the players when the story reaches its stage; the players never
--get the PDF itself, which is the whole adventure.
local HANDOUTS = {
    { id = "antihero", title = "Creating an Antihero", page = 56, stage = "cauldron" },
    { id = "abbey", title = "Abbey of Saint Iphicrates", page = 57, stage = "heist" },
    { id = "gear", title = "Experimental Gear", page = 58, stage = "return" },
    { id = "crysopolis", title = "The Crysopolis", page = 60, stage = "briefing" },
    { id = "letitia", title = "Lady Letitia de Toera", page = 59, stage = "asset" },
    { id = "justice", title = "Flying the Justice on Wings of Iron", page = 61, stage = "finale" },
}
local HANDOUT_EVENT = "condemnedHandout"

--------------------------------------------------------------------------------
-- Intel and alarm, from the book
--------------------------------------------------------------------------------
--Earned intel. A source with group shares its "once" with the other results of the
--same roll (the Lower City montage pays out once, at one of three amounts).
local INTEL_SOURCES = {
    { id = "gerold", stage = "hub", amount = 2, label = "Gerold gives up the passwords",
      hint = "The first time they ask him (sweet-talk, threats or a bribe)." },
    { id = "lower5", group = "lowercity", stage = "lowercity", amount = 5, label = "Lower City: total success" },
    { id = "lower3", group = "lowercity", stage = "lowercity", amount = 3, label = "Lower City: partial success" },
    { id = "lower1", group = "lowercity", stage = "lowercity", amount = 1, label = "Lower City: total failure" },
    { id = "warden", stage = "redoubt", amount = 2, label = "The Dwarf Warden (Interest 4-5)" },
    { id = "khavettra", stage = "khavettra", amount = 3, label = "Working with Khavettra" },
    { id = "advance", stage = "recordcontrol", amount = 2, label = "The ADVANCE file",
      hint = "Searching the archive after fighting the Archivist. None if nobody can read." },
}

--Spends with a fixed price. effect (optional) runs after paying; see SPEND_EFFECTS.
local INTEL_SPENDS = {
    { id = "reroll", stage = "hub", cost = 1, label = "Reroll a test", hint = "They must use the new roll." },
    { id = "riojan", stage = "lowercity", cost = 1, label = "Four bottles of Riojan Gold", hint = "High Street.", effect = "riojan" },
    { id = "syringes", stage = "lowercity", cost = 1, label = "Four syringes", hint = "The Back Alleys. No more than 12 syringes." },
    { id = "flyer", stage = "redoubt", cost = 1, label = "Fly a flying machine", hint = "The Underwalks, within 10 squares." },
    { id = "bluff", stage = "redoubt", cost = 3, label = "Back up the bluff", hint = "Bluffing the dwarves, on a tier 2 result." },
    { id = "archivist", stage = "recordcontrol", cost = 2, label = "Pay the Archivist", hint = "Once per negotiation: counts as a tier 3 outcome." },
    { id = "archanswer", stage = "recordcontrol", cost = 1, label = "An Archivist follow-up", hint = "\"Volatile powder\" (ADVANCE) or \"the cruiser is empty\" (collars)." },
    { id = "device", stage = "recordcontrol", cost = 1, label = "Identify a library device" },
    { id = "elevator", stage = "armory", cost = 1, label = "The elevator passcode", hint = "Otherwise a War Dog Patrol, and its key." },
    { id = "door", stage = "asset", cost = 3, label = "The security door's password", hint = "No action needed. Letitia is behind it." },
    { id = "tier", stage = "finale", cost = 1, label = "+1 tier at an action station", hint = "Once per test." },
}

local SPEND_EFFECTS = {
    riojan = function()
        CampaignState.Apply({ { kind = "counter", key = "riojan_bottles", delta = 4 } }, "RIOJAN GOLD +4: bought on High Street", { director = true })
    end,
}

--What the alarm level does. Patrol = the encounter a montage total failure brings.
local ALARM_LEVELS = {
    [0] = { patrol = nil, text = "Ordinary streets; patrols chat and pay no attention." },
    [1] = { patrol = nil, text = "Still quiet, but Safe Harbor has a \"Wanted for mayhem\" poster up." },
    [2] = { patrol = "War Dog Squad", text = "Patrols out in force, random ID checks, gossip in the streets." },
    [3] = { patrol = "War Dog Patrol", text = "Patrols in force. The Archivist starts in the dark and goes first; the Factory Floor guards are ready." },
    [4] = { patrol = "War Dog Strike Team", text = "Patrols on every street; announcements warn about traitors." },
    [5] = { patrol = "War Dog Strike Team", text = "Patrols on every street; announcements warn about traitors." },
}

--Quick alarm changes the book names.
local ALARM_EVENTS = {
    { delta = 1, label = "Montage partial success" },
    { delta = 2, label = "Montage total failure", hint = "Then a patrol, unless they spend intel equal to the alarm." },
    { delta = 1, label = "Demolition", hint = "Leaving an objective; costs a blackpowder grenade." },
    { delta = 1, label = "Alarm device / ADVANCE Control tier 1" },
    { delta = 1, label = "Lower City total failure" },
    { delta = -1, label = "Lower City total success" },
}

--------------------------------------------------------------------------------
-- State access
--------------------------------------------------------------------------------

local function Doc()
    return mod:GetDocumentSnapshot(DOC_ID)
end

local function Data()
    return Doc().data
end

--Mutates the campaign document; fn receives its data table.
local function ChangeDoc(description, fn)
    local doc = Doc()
    doc:BeginChange()
    fn(doc.data)
    doc:CompleteChange(description)
end

local function Flag(key)
    return CampaignState.GetFlag(key)
end

local function Counter(key)
    return CampaignState.GetCounter(key)
end

--Records state changes with a log line only the Director sees: story beats and
--branch choices would spoil the adventure in the players' Intel Tracker ledger.
local function Log(writes, text)
    CampaignState.Apply(writes, text, { director = true })
end

local function SetFlag(key, value, text)
    Log({ { kind = "flag", key = key, value = value } }, text)
end

local function SetCounter(key, value, text)
    Log({ { kind = "counter", key = key, set = value } }, text)
end

local function StageNumber()
    return STAGE_INDEX[Data().stage or ""] or 1
end

local function Reached(stageid)
    return StageNumber() >= (STAGE_INDEX[stageid] or 1)
end

local function StageName(stageid)
    local stage = STAGES[STAGE_INDEX[stageid] or 1]
    return stage.name
end

local function Collars()
    return rawget(_G, "CondemnedCollars")
end

--------------------------------------------------------------------------------
-- The roster: the Condemned and their collars
--------------------------------------------------------------------------------

--charid -> the hero's collar status, worked out from the token and the records:
--  "detonated"  blown up (the collar panel's Explode, or Medical tier 1)
--  "collared"   wearing the collar right now
--  "removed"    taken off, recorded here (Medical station, or marked by hand)
--  "none"       no collar on the token and no removal recorded
local function CollarStatus(charid, token)
    local collars = Collars()
    local record = (Data().collars or {})[charid]
    if collars ~= nil and collars.GetExploded()[charid] ~= nil then
        return "detonated"
    end
    if record ~= nil and record.state == "detonated" then
        return "detonated"
    end
    if collars ~= nil and token ~= nil and collars.IsCollared(token) then
        return "collared"
    end
    if record ~= nil and record.state == "removed" then
        return "removed"
    end
    return "none"
end

local STATUS_TEXT = {
    collared = "Collared",
    removed = "Collar off",
    detonated = "Detonated",
    none = "No collar",
}
local STATUS_CLASS = {
    collared = "ccOk",
    removed = "ccInfo",
    detonated = "ccDanger",
    none = "ccWarn",
}

local function IsHero(token)
    local ok, hero = pcall(function() return token.properties ~= nil and token.properties:IsHero() end)
    return ok and hero == true
end

--The Condemned the panel tracks: heroes in the player party, heroes on this map,
--anyone wearing a collar anywhere in the game, and anyone with a collar record.
--The Director can drop a hero from the list (rosterHidden).
local g_rosterCache = nil
local g_rosterCacheTime = -100

local function Roster()
    if g_rosterCache ~= nil and dmhub.Time() - g_rosterCacheTime < 1.5 then
        return g_rosterCache
    end

    local data = Data()
    local hidden = data.rosterHidden or {}
    local seen = {}
    local result = {}
    local function Add(charid, token)
        if charid == nil or seen[charid] or hidden[charid] then
            return
        end
        token = token or dmhub.GetCharacterById(charid)
        if token == nil or not IsHero(token) then
            return
        end
        seen[charid] = true
        local name = token.name
        if name == nil or name == "" then
            name = "Unnamed hero"
        end
        result[#result + 1] = { charid = charid, token = token, name = name }
    end

    for _, charid in ipairs(dmhub.GetCharacterIdsInParty(GetDefaultPartyID()) or {}) do
        Add(charid)
    end
    for _, tok in ipairs(dmhub.allTokens) do
        Add(tok.charid, tok)
    end
    local collars = Collars()
    if collars ~= nil then
        for charid, tok in pairs(dmhub.GetAllCharacters() or {}) do
            if not seen[charid] and collars.IsCollared(tok) then
                Add(charid, tok)
            end
        end
        for charid, _ in pairs(collars.GetExploded()) do
            Add(charid)
        end
    end
    for charid, _ in pairs(data.collars or {}) do
        Add(charid)
    end
    for charid, _ in pairs(data.gerold or {}) do
        Add(charid)
    end

    table.sort(result, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.charid < b.charid
    end)

    g_rosterCache = result
    g_rosterCacheTime = dmhub.Time()
    return result
end

local function ForgetRosterCache()
    g_rosterCache = nil
end

--counts of each collar status over the roster.
local function CollarCounts()
    local counts = { collared = 0, removed = 0, detonated = 0, none = 0 }
    for _, entry in ipairs(Roster()) do
        local status = CollarStatus(entry.charid, entry.token)
        counts[status] = counts[status] + 1
    end
    return counts
end

--keeps the journal cards' collars_removed counter in step with the records.
local function SyncCollarsRemovedCounter(text)
    local n = CollarCounts().removed
    if Counter("collars_removed") ~= n then
        SetCounter("collars_removed", n, text or string.format("COLLARS REMOVED: %d", n))
    end
end

local function RecordCollar(charid, state, how)
    ChangeDoc("Collar record", function(data)
        data.collars = data.collars or {}
        if state == nil then
            data.collars[charid] = nil
        else
            data.collars[charid] = { state = state, how = how, t = dmhub.serverTimeMilliseconds }
        end
    end)
    ForgetRosterCache()
end

--------------------------------------------------------------------------------
-- The Medical station
--------------------------------------------------------------------------------

local MEDICAL_OPTIONS = {
    { id = "pick", text = "Medical station..." },
    { id = "t1", text = "Tier 1: the collar explodes" },
    { id = "t2", text = "Tier 2: off, the Justice takes 10" },
    { id = "t3", text = "Tier 3: off cleanly" },
    { id = "other", text = "Taken off another way" },
}

local function TakeCollarOff(entry, how, text)
    local collars = Collars()
    local token = dmhub.GetTokenById(entry.charid)
    if collars ~= nil and token ~= nil then
        collars.SetCollar(token, false)
    elseif collars ~= nil and entry.token ~= nil and collars.IsCollared(entry.token) then
        --not on this map, so there is no animation to play: just change the frame.
        collars.RemoveNow(entry.token)
    end
    RecordCollar(entry.charid, "removed", how)
    SyncCollarsRemovedCounter(text)
end

local function RunMedical(entry, result)
    local name = entry.name
    if result == "t1" then
        local collars = Collars()
        if collars ~= nil and dmhub.GetTokenById(entry.charid) ~= nil then
            collars.Detonate(entry.charid)
        end
        RecordCollar(entry.charid, "detonated", "Medical station, tier 1")
        Log({}, string.format("COLLAR: %s's collar exploded at the Medical station", name))
    elseif result == "t2" then
        TakeCollarOff(entry, "Medical station, tier 2", string.format("COLLAR: %s's collar came off (Medical station, tier 2)", name))
        Log({ { kind = "counter", key = "justice_stamina", delta = -10 } }, "JUSTICE -10: collar removal went wrong")
    elseif result == "t3" then
        TakeCollarOff(entry, "Medical station, tier 3", string.format("COLLAR: %s's collar came off cleanly", name))
    elseif result == "other" then
        TakeCollarOff(entry, "by hand", string.format("COLLAR: %s's collar is off", name))
    end
end

--------------------------------------------------------------------------------
-- Gerold's grudges
--------------------------------------------------------------------------------
--One number per Condemned: up for wine, sweet-talk and bribes, down for insults,
--shocks and muting. Spider Gerold's Now Our Debts Are Paid treats anyone at 0 or
--below (cruel or indifferent) as an enemy.

local function GeroldScore(charid)
    return (Data().gerold or {})[charid] or 0
end

local function GeroldStanding(score)
    if score > 0 then
        return "Kind", "ccOk"
    elseif score < 0 then
        return "Cruel", "ccDanger"
    end
    return "Indifferent", "ccWarn"
end

local function AdjustGerold(entry, delta)
    local after = GeroldScore(entry.charid) + delta
    ChangeDoc("Gerold remembers", function(data)
        data.gerold = data.gerold or {}
        data.gerold[entry.charid] = after
    end)
    Log({}, string.format("GEROLD: %s %s him (%+d, now %s)", entry.name,
        delta > 0 and "did right by" or "mistreated", after, (GeroldStanding(after))))
end

--------------------------------------------------------------------------------
-- Stage changes and what reaching a stage switches on
--------------------------------------------------------------------------------

local REACH_EFFECTS = {
    part1clock = function()
        if not Flag("part1_clock_started") then
            SetFlag("part1_clock_started", true, "CLOCK: the one-hour clock started")
        end
    end,
    missionclock = function()
        if not Flag("mission_clock_started") then
            SetFlag("mission_clock_started", true, "CLOCK: the 48-hour mission clock started")
        end
    end,
    intel = function()
        if not Flag(INTEL_ENABLED_FLAG) then
            SetFlag(INTEL_ENABLED_FLAG, true, "INTEL: the Intel Tracker is open to the players")
        end
        local saved = Counter("documents_saved")
        if saved > 0 then
            IntelTracker.Adjust(saved, string.format("Starting intel: %d document%s saved", saved, saved == 1 and "" or "s"))
        end
    end,
    justice = function()
        if Counter("justice_stamina") <= 0 then
            SetCounter("justice_stamina", JUSTICE_START, string.format("JUSTICE: %d of %d Stamina", JUSTICE_START, JUSTICE_MAX))
        end
    end,
}

--runs each reached stage's onReach the first time it is reached. Director only.
local function RunReachEffects()
    if not dmhub.isDM then
        return
    end
    local current = StageNumber()
    local done = Data().reached or {}
    local pending = {}
    for i = 1, current do
        local stage = STAGES[i]
        if stage.onReach ~= nil and not done[stage.id] then
            pending[#pending + 1] = stage
        end
    end
    if #pending == 0 then
        return
    end
    ChangeDoc("Story effects", function(data)
        data.reached = data.reached or {}
        for _, stage in ipairs(pending) do
            data.reached[stage.id] = true
        end
    end)
    for _, stage in ipairs(pending) do
        local effect = REACH_EFFECTS[stage.onReach]
        if effect ~= nil then
            effect()
        end
    end
end

local function SetStage(stageid, reason)
    local index = STAGE_INDEX[stageid]
    if index == nil or index == StageNumber() then
        return
    end
    ChangeDoc("Story stage", function(data)
        data.stage = stageid
    end)
    local text = "STORY: " .. STAGES[index].name
    if reason ~= nil then
        text = text .. " (" .. reason .. ")"
    end
    Log({}, text)
    RunReachEffects()
end

--moves the story forward to stageid; never back.
local function AdvanceTo(stageid, reason)
    local index = STAGE_INDEX[stageid]
    if index ~= nil and index > StageNumber() then
        SetStage(stageid, reason)
    end
end

--------------------------------------------------------------------------------
-- One-time intel grants and spends
--------------------------------------------------------------------------------

local function SourceClaimed(source)
    local claimed = Data().claimed or {}
    return claimed[source.group or source.id] ~= nil
end

local function ClaimSource(source)
    if SourceClaimed(source) then
        return
    end
    ChangeDoc("Intel claimed", function(data)
        data.claimed = data.claimed or {}
        data.claimed[source.group or source.id] = source.id
    end)
    IntelTracker.Adjust(source.amount, source.label)
end

local function UnclaimSource(source)
    local key = source.group or source.id
    local claimedId = (Data().claimed or {})[key]
    if claimedId == nil then
        return
    end
    for _, s in ipairs(INTEL_SOURCES) do
        if s.id == claimedId then
            IntelTracker.Adjust(-s.amount, "Taken back: " .. s.label)
        end
    end
    ChangeDoc("Intel unclaimed", function(data)
        data.claimed = data.claimed or {}
        data.claimed[key] = nil
    end)
end

local function Spend(cost, label, effect)
    if cost <= 0 or IntelTracker.Pool() < cost then
        return
    end
    IntelTracker.Adjust(-cost, label)
    if effect ~= nil and SPEND_EFFECTS[effect] ~= nil then
        SPEND_EFFECTS[effect]()
    end
end

--6 + alarm, at most 11, less one per skill the party brings (Forgery, Lie, Disguise).
local function RedoubtGateCost(reductions)
    return math.max(0, math.min(11, 6 + IntelTracker.Alarm()) - (reductions or 0))
end

--------------------------------------------------------------------------------
-- The book and the handouts
--------------------------------------------------------------------------------

---@return PDFDocumentAssetLua|nil
local function Book()
    local pdfs = assets.pdfDocumentsTable
    local book = pdfs[BOOK_ID]
    if book == nil then
        pcall(function()
            for _, pdf in pairs(pdfs) do
                if pdf.description == BOOK_NAME then
                    book = pdf
                end
            end
        end)
    end
    return book
end

local function PrintedPage(index)
    return index - BOOK_PAGE_OFFSET
end

--The rail button the Campaign popup hangs from, so a link can close the popup
--before opening the book or a handout (the popup would sit on top of them).
local g_popupOwner = nil

local function ClosePopup()
    if g_popupOwner ~= nil and g_popupOwner.valid then
        g_popupOwner.popup = nil
    end
    g_popupOwner = nil
end

--Opens the book on this client only (the Director's). With a heading it opens at
--that section of the page, scrolled into view and outlined for a moment; see
--PDFSectionRects in JournalPDFViewer.lua for how heading and untilHeading work.
local function OpenBook(index, heading, untilHeading)
    local book = Book()
    if book ~= nil then
        ClosePopup()
        local options = nil
        if heading ~= nil then
            options = { focus = { page = index, heading = heading, untilHeading = untilHeading } }
        end
        OpenPDFDocument(book, index, options)
    end
end

local function HandoutEntry(handout)
    return (Data().handouts or {})[handout.id]
end

local function HandoutShared(handout)
    local entry = HandoutEntry(handout)
    return entry ~= nil and entry.shared == true and entry.imageid ~= nil
end

--handout ids whose page is being rendered and uploaded on this client.
local g_handoutsUploading = {}

local function SetHandoutShared(handout, shared, imageid)
    ChangeDoc("Handout", function(data)
        data.handouts = data.handouts or {}
        local entry = data.handouts[handout.id] or {}
        if imageid ~= nil then
            entry.imageid = imageid
        end
        entry.shared = shared
        data.handouts[handout.id] = entry
    end)
    Log({}, string.format("HANDOUT: %s %s", handout.title, shared and "shared with the players" or "hidden from the players"))
end

--Shares (or hides) a handout. The first share renders the book page to an image
--and uploads it, so the players can see that one page without the PDF.
local function ShareHandout(handout, shared)
    local entry = HandoutEntry(handout)
    if not shared or (entry ~= nil and entry.imageid ~= nil) then
        SetHandoutShared(handout, shared)
        return
    end
    local book = Book()
    if book == nil or g_handoutsUploading[handout.id] then
        return
    end
    g_handoutsUploading[handout.id] = true
    local summary = book.doc.summary
    local width = 1400
    local height = 1818
    if summary ~= nil and summary.pageWidth ~= nil and summary.pageWidth > 0 then
        height = math.floor(width * summary.pageHeight / summary.pageWidth)
    end
    book.doc:RenderToData(handout.page, width, height, { x1 = 0, y1 = 0, x2 = 1, y2 = 1 }, function(data)
        if data == nil or mod.unloaded then
            g_handoutsUploading[handout.id] = nil
            return
        end
        assets:UploadImageAsset {
            data = data,
            description = "The Condemned - Handout: " .. handout.title,
            error = function(message)
                g_handoutsUploading[handout.id] = nil
                print("Condemned: could not upload the handout " .. handout.title .. ": " .. tostring(message))
            end,
            upload = function(imageid)
                g_handoutsUploading[handout.id] = nil
                if not mod.unloaded then
                    SetHandoutShared(handout, true, imageid)
                end
            end,
        }
    end)
end

--A handout page in a window of its own. Anyone can open a shared one.
local function ShowHandout(handout)
    local entry = HandoutEntry(handout)
    if entry == nil or entry.imageid == nil then
        return
    end
    ClosePopup()
    --tall enough to read the page's small print: as tall as the screen allows.
    local pageHeight = 960
    local pageWidth = math.floor(pageHeight * 0.77)
    local book = Book()
    local summary = book ~= nil and book.doc.summary or nil
    if summary ~= nil and summary.pageHeight ~= nil and summary.pageHeight > 0 then
        pageWidth = math.floor(pageHeight * summary.pageWidth / summary.pageHeight)
    end
    --the modal layer passes no themed cascade, so the window roots its own.
    local dialog = gui.Panel {
        styles = ThemeEngine.GetStyles(),
        width = "auto",
        height = "auto",
        children = {
            gui.Panel {
                classes = { "framedPanel" },
                width = pageWidth + 24,
                height = "auto",
                flow = "vertical",
                borderBox = true,
                pad = 12,
                children = {
                    gui.Panel {
                        flow = "horizontal",
                        width = "100%",
                        height = 30,
                        children = {
                            gui.Label {
                                text = "Handout: " .. handout.title,
                                width = "auto",
                                height = "auto",
                                halign = "left",
                                valign = "center",
                                fontSize = 18,
                                bold = true,
                            },
                            gui.Button {
                                classes = { "closeButton" },
                                halign = "right",
                                valign = "center",
                                press = function()
                                    gui.CloseModal()
                                end,
                            },
                        },
                    },
                    gui.Panel {
                        bgimage = entry.imageid,
                        bgcolor = "white",
                        width = pageWidth,
                        height = pageHeight,
                        halign = "center",
                        tmargin = 6,
                    },
                },
            },
        },
    }
    gui.ShowModal(dialog)
end

--"Show now": the Director pops a shared handout up on every player's screen.
local function ShowHandoutToPlayers(handout)
    dmhub.BroadcastRemoteEvent(HANDOUT_EVENT, dmhub.GenerateGuid(), { id = handout.id }, true)
end

dmhub.RegisterRemoteEvent(HANDOUT_EVENT, function(info)
    if mod.unloaded or dmhub.isDM or type(info) ~= "table" then
        return
    end
    for _, handout in ipairs(HANDOUTS) do
        if handout.id == info.id and HandoutShared(handout) then
            ShowHandout(handout)
        end
    end
end)

--------------------------------------------------------------------------------
-- The ending
--------------------------------------------------------------------------------
--Book rule (Choice of Endings): Letitia rescued x collars removed. The book does not
--say how the dead count; this counts the Condemned still alive.

local function EndingVerdict()
    local letitia = Flag("letitia_rescued")
    local counts = CollarCounts()
    local worn = counts.collared + counts.none
    local removed = counts.removed
    if not letitia then
        if removed == 0 then
            return "Ending 1: You Have Failed Me", "Lady Letitia was not rescued and every living Condemned still wears a collar."
        end
        return "Ending 2: Double Cross", string.format("Lady Letitia was not rescued, but %d of the Condemned got their collar off.", removed)
    end
    if worn > 0 or removed == 0 then
        return "Ending 3: Capital Agents", string.format("Lady Letitia is safe; %d of the Condemned still wear a collar.", worn)
    end
    return "Ending 3 or Ending 4: Freedom of the Skies", "Lady Letitia is safe and every collar is off: the players choose."
end

--------------------------------------------------------------------------------
-- Watching the table (Director only)
--------------------------------------------------------------------------------
--A combat from the adventure going live moves the story on, and a War Dog Strike Team
--counts toward the next one's extra commandos. Each live encounter is handled once.

local g_seenEncounter = nil

local function WatchLiveEncounter()
    local q = dmhub.initiativeQueue
    if q == nil or q.hidden then
        g_seenEncounter = nil
        return
    end
    local live = q:try_get("liveEncounter")
    if type(live) ~= "table" then
        return
    end
    local name = live:try_get("name")
    if type(name) ~= "string" then
        return
    end
    local key = name .. ":" .. tostring(live:try_get("onsetTimestamp") or "")
    if key == g_seenEncounter then
        return
    end
    g_seenEncounter = key

    if (Data().encounters or {})[key] then
        return
    end
    ChangeDoc("Combat noted", function(data)
        data.encounters = data.encounters or {}
        data.encounters[key] = true
    end)

    local stageid = ENCOUNTER_STAGES[name]
    if stageid ~= nil then
        AdvanceTo(stageid, "combat began")
    end
    if name == STRIKE_TEAM_ENCOUNTER then
        local earlier = Counter("strike_teams_fought")
        Log({ { kind = "counter", key = "strike_teams_fought", delta = 1 } },
            string.format("STRIKE TEAM: number %d (add %d war dog commandos)", earlier + 1, earlier * 2))
    end
end

--A hero recorded as having their collar off but wearing one again (put back from
--Loyalty Collars) has the record dropped, and collars_removed follows the records.
local function WatchCollars()
    local records = Data().collars or {}
    local collars = Collars()
    if collars == nil then
        return
    end
    for _, entry in ipairs(Roster()) do
        local record = records[entry.charid]
        if record ~= nil and record.state == "removed" and collars.IsCollared(entry.token) then
            RecordCollar(entry.charid, nil)
        end
    end
    SyncCollarsRemovedCounter()
end

--Each handout is shared once, when the story first reaches its stage. Hiding it
--afterwards sticks: the "auto" record stops it being shared again.
local function WatchHandouts()
    for _, handout in ipairs(HANDOUTS) do
        if Reached(handout.stage) and not (Data().handoutsAuto or {})[handout.id] then
            ChangeDoc("Handout unlocked", function(data)
                data.handoutsAuto = data.handoutsAuto or {}
                data.handoutsAuto[handout.id] = true
            end)
            if not HandoutShared(handout) then
                ShareHandout(handout, true)
            end
        end
    end
end

dmhub.Coroutine(function()
    local tick = 0
    while not mod.unloaded do
        coroutine.yield(1)
        tick = tick + 1
        if not mod.unloaded and dmhub.isDM and rawget(_G, "CampaignState") ~= nil then
            pcall(WatchLiveEncounter)
            if tick % 3 == 0 then
                pcall(WatchCollars)
                pcall(WatchHandouts)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Public API, for encounter scripts and the other Condemned files
--------------------------------------------------------------------------------

CondemnedCampaign = {
    Stage = function()
        return STAGES[StageNumber()].id
    end,
    Reached = Reached,
    SetStage = SetStage,
    AdvanceTo = AdvanceTo,
    SetFlag = SetFlag,
    SetCounter = SetCounter,
    GetFlag = Flag,
    GetCounter = Counter,
    Ending = EndingVerdict,
    --grants one of INTEL_SOURCES by id, once (the panel shows it as granted).
    ClaimIntel = function(sourceid)
        for _, source in ipairs(INTEL_SOURCES) do
            if source.id == sourceid then
                ClaimSource(source)
            end
        end
    end,
    --spends intel if the party has enough; returns whether it did.
    SpendIntel = function(cost, label)
        if IntelTracker.Pool() < cost then
            return false
        end
        Spend(cost, label)
        return true
    end,
}

--------------------------------------------------------------------------------
-- Styles
--------------------------------------------------------------------------------

local function BuildStyles()
    return {
        { selectors = { "ccTitle" }, color = "@fgStrong", priority = 5 },
        { selectors = { "ccTitle", "locked" }, color = "@fgMuted", priority = 6 },
        { selectors = { "ccMuted" }, color = "@fgMuted", priority = 5 },
        { selectors = { "ccStrong" }, color = "@fgStrong", priority = 5 },
        { selectors = { "ccRule" }, bgimage = "panels/square.png", bgcolor = "@border", opacity = 0.35 },
        { selectors = { "ccSeam" }, bgimage = "panels/square.png", bgcolor = "@border", opacity = 0.2 },
        { selectors = { "ccCard" }, bgimage = "panels/square.png", bgcolor = "@bgAlt", borderColor = "@accent" },
        { selectors = { "ccSeg" }, bgimage = "panels/square.png", bgcolor = "@bgAlt", borderColor = "@border", borderWidth = 1 },
        { selectors = { "ccSeg", "reached" }, bgcolor = "@fgMuted" },
        { selectors = { "ccSeg", "current" }, bgcolor = "@accent", borderColor = "@fgStrong" },
        { selectors = { "ccSeg", "hover" }, brightness = 1.5 },
        { selectors = { "ccPartLabel" }, color = "@fgMuted", priority = 5 },
        { selectors = { "ccPartLabel", "current" }, color = "@accent", priority = 6 },
        { selectors = { "ccChip" }, bgimage = "panels/square.png", bgcolor = "clear", borderWidth = 1, borderColor = "@border", color = "@fg", priority = 5 },
        { selectors = { "ccChip", "ccOk" }, borderColor = "@success", color = "@success", priority = 6 },
        { selectors = { "ccChip", "ccInfo" }, borderColor = "@info", color = "@info", priority = 6 },
        { selectors = { "ccChip", "ccWarn" }, borderColor = "@warning", color = "@warning", priority = 6 },
        { selectors = { "ccChip", "ccDanger" }, borderColor = "@danger", color = "@danger", priority = 6 },
        { selectors = { "ccIntel" }, color = INTEL_COLOR, priority = 6 },
        { selectors = { "ccAlarm" }, color = ALARM_COLOR, priority = 6 },
        { selectors = { "ccPip" }, bgimage = "panels/square.png", bgcolor = "clear", borderWidth = 1, borderColor = ALARM_COLOR },
        { selectors = { "ccPip", "filled" }, bgcolor = ALARM_COLOR },
        { selectors = { "ccPip", "hover" }, brightness = 1.6 },
        { selectors = { "ccBarTrack" }, bgimage = "panels/square.png", bgcolor = "@bg", borderWidth = 1, borderColor = "@border" },
        { selectors = { "ccBarFill" }, bgimage = "panels/square.png", bgcolor = "@success" },
        { selectors = { "ccBarFill", "low" }, bgcolor = "@warning" },
        { selectors = { "ccBarFill", "critical" }, bgcolor = "@danger" },
        { selectors = { "ccVerdict" }, color = "@accent", priority = 6 },
        { selectors = { "ccDangerButton" }, borderColor = "@danger", color = "@danger", priority = 10 },
        --links into the book and to handouts: underlined like journal links, in the
        --Condemned journal's bronze link colour lifted for a dark panel. (The scheme's
        --@accent, which plain links use, is the same cream as body text here.)
        { selectors = { "label", "link", "ccBookLink" }, color = BOOK_LINK_COLOR, priority = 6 },
        { selectors = { "label", "link", "ccBookLink", "hover" }, color = BOOK_LINK_HOVER, priority = 7 },
        { selectors = { "tab", "ccTabLocked" }, opacity = 0.4 },
    }
end

--------------------------------------------------------------------------------
-- UI building blocks
--------------------------------------------------------------------------------
--Every live element listens for "refreshCampaign", which the panel root sends down
--its tree whenever the campaign state or the campaign document changes.

local function Label(text, args)
    local options = {
        width = "auto",
        height = "auto",
        halign = "left",
        fontSize = 13,
        text = text,
    }
    for k, v in pairs(args or {}) do
        options[k] = v
    end
    return gui.Label(options)
end

local function Muted(text, args)
    args = args or {}
    args.classes = args.classes or { "ccMuted" }
    args.fontSize = args.fontSize or 11
    return Label(text, args)
end

local function Small(text, args)
    args = args or {}
    args.fontSize = args.fontSize or 12
    return Label(text, args)
end

local function Seam()
    return gui.Panel { classes = { "ccSeam" }, width = "100%", height = 1, vmargin = 2 }
end

--A link to a section of the book. ref = { title, pageIndex, heading, untilHeading }:
--title is the link text; heading (optional) picks the section to show and outline.
--Labels need a backing image to be clickable.
local function BookLink(ref, args)
    local title, index, heading, untilHeading = ref[1], ref[2], ref[3], ref[4]
    local options = {
        classes = { "link", "underline", "ccBookLink" },
        bgimage = "panels/square.png",
        bgcolor = "#00000001",
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        fontSize = 12,
        text = string.format("%s (p. %d)", title, PrintedPage(index)),
        hover = gui.Tooltip(heading ~= nil and ("Show this section of " .. BOOK_NAME) or ("Open " .. BOOK_NAME .. " at this page")),
        press = function()
            OpenBook(index, heading, untilHeading)
        end,
    }
    for k, v in pairs(args or {}) do
        options[k] = v
    end
    return gui.Label(options)
end

--"IN THE BOOK" and a wrapping row of section links; refs = { ref, ... } (see BookLink).
local function BookLinks(refs)
    local children = { Muted("IN THE BOOK", { bold = true, fontSize = 10, rmargin = 10, valign = "center", bmargin = 3 }) }
    for _, ref in ipairs(refs) do
        children[#children + 1] = BookLink(ref, { rmargin = 14, bmargin = 3 })
    end
    return gui.Panel {
        flow = "horizontal",
        wrap = true,
        width = "100%",
        height = "auto",
        bmargin = 6,
        children = children,
    }
end

--a small heading, with an optional book link (a BookLink ref) on the right.
local function SubHeading(text, ref)
    if ref == nil then
        return Muted(string.upper(text), { bold = true, tmargin = 8, bmargin = 3 })
    end
    --heading and link share the row's vertical centre.
    return gui.Panel {
        flow = "horizontal",
        width = "100%",
        height = 18,
        tmargin = 8,
        bmargin = 3,
        children = {
            Muted(string.upper(text), { bold = true, valign = "center" }),
            BookLink(ref, { halign = "right", valign = "center", fontSize = 11 }),
        },
    }
end

local function Row(children, args)
    local options = {
        flow = "horizontal",
        width = "100%",
        height = "auto",
        valign = "center",
        children = children,
    }
    for k, v in pairs(args or {}) do
        options[k] = v
    end
    return gui.Panel(options)
end

local function Button(text, width, press, args)
    local options = {
        classes = { "sizeS" },
        text = text,
        width = width,
        height = 24,
        fontSize = 12,
        halign = "left",
        valign = "center",
        press = press,
    }
    for k, v in pairs(args or {}) do
        options[k] = v
    end
    return gui.Button(options)
end

local function Chip(text, statusClass, args)
    local classes = { "ccChip" }
    if statusClass ~= nil then
        classes[#classes + 1] = statusClass
    end
    local options = {
        classes = classes,
        width = "auto",
        height = 18,
        hpad = 6,
        borderBox = true,
        cornerRadius = 4,
        fontSize = 11,
        bold = true,
        valign = "center",
        textAlignment = "center",
        text = text,
    }
    for k, v in pairs(args or {}) do
        options[k] = v
    end
    return gui.Label(options)
end

--sets a chip's text and status colour in place.
local function SetChip(chip, text, statusClass)
    chip.text = text
    for _, c in pairs(STATUS_CLASS) do
        chip:SetClass(c, c == statusClass)
    end
end

--A checkbox bound to a campaign flag. hint is a muted line under it.
local function FlagRow(key, label, hint)
    local check
    check = gui.Check {
        text = label,
        value = Flag(key),
        width = "auto",
        height = 22,
        minWidth = 0,
        fontSize = 13,
        halign = "left",
        change = function(element)
            local value = element.value == true
            if value == Flag(key) then
                return
            end
            SetFlag(key, value, string.format("%s: %s", string.upper(label), value and "yes" or "no"))
        end,
        refreshCampaign = function(element)
            if element.value ~= Flag(key) then
                element.value = Flag(key)
            end
        end,
    }
    local children = { check }
    if hint ~= nil then
        --indented under the label by padding, so the hint still wraps inside the page.
        children[#children + 1] = gui.Panel {
            width = "100%",
            height = "auto",
            borderBox = true,
            lpad = 26,
            bmargin = 2,
            children = { Muted(hint, { width = "100%" }) },
        }
    end
    return gui.Panel { flow = "vertical", width = "100%", height = "auto", vpad = 2, children = children }
end

--A "- value +" control bound to a campaign counter.
local function CounterRow(key, label, args)
    args = args or {}
    local min = args.min or 0
    local max = args.max
    local valueLabel = Label(tostring(Counter(key)), {
        width = 34,
        fontSize = 16,
        bold = true,
        textAlignment = "center",
        classes = args.valueClasses,
        refreshCampaign = function(element)
            element.text = tostring(Counter(key))
        end,
    })
    local function Bump(delta)
        local now = Counter(key)
        local after = now + delta
        if after < min then after = min end
        if max ~= nil and after > max then after = max end
        if after ~= now then
            SetCounter(key, after, string.format("%s: %d", string.upper(label), after))
        end
    end
    local children = {
        Label(label, { width = args.labelWidth or 220, valign = "center" }),
        gui.Button { classes = { "sizeXxs" }, halign = "left", text = "-", valign = "center", press = function() Bump(-(args.step or 1)) end },
        valueLabel,
        gui.Button { classes = { "sizeXxs" }, halign = "left", text = "+", valign = "center", press = function() Bump(args.step or 1) end },
    }
    if args.hint ~= nil then
        children[#children + 1] = Muted(args.hint, { lmargin = 10, width = "auto", valign = "center" })
    end
    return Row(children, { vpad = 3 })
end

--A dropdown bound to a value in the campaign document.
local function ChoiceRow(docKey, label, options, onChoose)
    local function Current()
        return Data()[docKey] or options[1].id
    end
    return Row({
        Label(label, { width = 220, valign = "center" }),
        gui.Dropdown {
            classes = { "sizeS" },
            width = 300,
            height = 24,
            fontSize = 12,
            halign = "left",
            valign = "center",
            options = options,
            idChosen = Current(),
            change = function(element)
                ---@cast element Dropdown
                local choice = element.idChosen
                if choice == Current() then
                    return
                end
                ChangeDoc(label, function(data)
                    data[docKey] = choice
                end)
                if onChoose ~= nil then
                    onChoose(choice)
                end
            end,
            refreshCampaign = function(element)
                ---@cast element Dropdown
                if element.idChosen ~= Current() then
                    element.idChosen = Current()
                end
            end,
        },
    }, { vpad = 3 })
end

--One tab's page: a heading with a summary on the right, then the page's controls.
--unlock = the stage it opens at; until then the page shows only when it opens.
--summary() returns the heading's right-hand text. The tab bar reads args back from
--the returned panel's data (id, title, unlock, summary).
local function Section(args)
    local body = gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",
        children = args.children,
    }

    local lockNote = Muted("", { fontSize = 13, tmargin = 12, width = "100%" })
    local title = Label(args.title, { classes = { "ccTitle" }, bold = true, fontSize = 15, valign = "center" })
    local summary = Muted("", { valign = "center", halign = "right", fontSize = 11 })

    local function Apply()
        local unlocked = args.unlock == nil or Reached(args.unlock)
        body:SetClass("collapsed", not unlocked)
        lockNote:SetClass("collapsed", unlocked)
        title:SetClass("locked", not unlocked)
        if not unlocked then
            summary.text = ""
            lockNote.text = "This opens when the story reaches " .. StageName(args.unlock) .. "."
        elseif args.summary ~= nil then
            local ok, text = pcall(args.summary)
            summary.text = ok and (text or "") or ""
        else
            summary.text = ""
        end
    end

    local children = {
        Row({ title, summary }, { height = 28 }),
        gui.Panel { classes = { "ccRule" }, width = "100%", height = 1, bmargin = 6 },
    }
    --the book links show even while the page is locked, so the Director can read ahead.
    if args.refs ~= nil then
        children[#children + 1] = BookLinks(args.refs)
    end
    children[#children + 1] = lockNote
    children[#children + 1] = body

    return gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",
        borderBox = true,
        hpad = 14,
        bpad = 12,
        data = { section = args },
        --summaries can follow token changes (a collar put back on) that never touch
        --campaign state, so they are also refreshed once a second.
        thinkTime = 1,
        think = function()
            Apply()
        end,
        create = function()
            Apply()
        end,
        refreshCampaign = function()
            Apply()
        end,
        children = children,
    }
end

--Collapses an element until a stage is reached.
local function UntilStage(stageid, panel)
    panel:SetClass("collapsed", not Reached(stageid))
    local wrapper = gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",
        children = { panel },
        refreshCampaign = function()
            panel:SetClass("collapsed", not Reached(stageid))
        end,
    }
    return wrapper
end

--------------------------------------------------------------------------------
-- The story header
--------------------------------------------------------------------------------

local function FindJournalPage(name)
    local docs = dmhub.GetTable(CustomDocument.tableName) or {}
    for _, doc in unhidden_pairs(docs) do
        if doc.description == name then
            return doc
        end
    end
    return nil
end

local function CreateStoryHeader()
    --the track: one segment per stage, grouped by Part.
    local segments = {}
    local partGroups = {}
    local partLabels = {}
    for part = 1, 4 do
        local groupChildren = {}
        for i, stage in ipairs(STAGES) do
            if stage.part == part then
                local seg = gui.Panel {
                    classes = { "ccSeg" },
                    width = part == 4 and 22 or 30,
                    height = 10,
                    rmargin = 2,
                    valign = "center",
                    hover = gui.Tooltip(string.format("%d. %s\nClick to set the story here.", i, stage.name)),
                    press = function()
                        SetStage(stage.id, "set by the Director")
                    end,
                }
                segments[i] = seg
                groupChildren[#groupChildren + 1] = seg
            end
        end
        local partLabel = Muted(part == 4 and "END" or ("PART " .. part), { classes = { "ccPartLabel" }, bold = true, fontSize = 10, bmargin = 2 })
        partLabels[part] = partLabel
        partGroups[#partGroups + 1] = gui.Panel {
            flow = "vertical",
            width = "auto",
            height = "auto",
            rmargin = 10,
            children = {
                partLabel,
                gui.Panel { flow = "horizontal", width = "auto", height = "auto", children = groupChildren },
            },
        }
    end

    local stageName = Label("", { fontSize = 18, bold = true, classes = { "ccStrong" } })
    local stageCounter = Muted("", { fontSize = 11, bold = true })
    --two lines' height whatever the note's length, so the popup does not move.
    local stageNote = Small("", { width = "100%", height = 32, valign = "top", classes = { "ccMuted" }, tmargin = 4 })

    local openButton = Button("Open page", 96, function()
        local doc = FindJournalPage(STAGES[StageNumber()].page)
        if doc ~= nil then
            doc:ShowDocument()
        end
    end)
    local bookButton = Button("Book", 76, function()
        local entry = STAGE_BOOK[STAGES[StageNumber()].id]
        if entry ~= nil then
            OpenBook(entry[1], entry[2], entry[3])
        end
    end, { lmargin = 6, hover = gui.Tooltip("Open " .. BOOK_NAME .. " where this part of the story starts") })
    local backButton = Button("Back", 60, function()
        local n = StageNumber()
        if n > 1 then
            SetStage(STAGES[n - 1].id, "stepped back")
        end
    end, { lmargin = 6 })
    local nextButton = Button("Next", 240, function()
        local n = StageNumber()
        if n < #STAGES then
            SetStage(STAGES[n + 1].id)
        end
    end, { lmargin = 6 })

    return gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",
        borderBox = true,
        hpad = 14,
        vpad = 10,
        classes = { "ccCard" },
        border = { x1 = 3 },
        create = function(element)
            element:FireEvent("refreshCampaign")
        end,
        refreshCampaign = function()
            local n = StageNumber()
            local stage = STAGES[n]
            for i, seg in ipairs(segments) do
                seg:SetClass("reached", i < n)
                seg:SetClass("current", i == n)
            end
            for part, label in pairs(partLabels) do
                label:SetClass("current", part == stage.part)
            end
            stageCounter.text = string.format("%s  -  STAGE %d OF %d", string.upper(PART_NAMES[stage.part]), n, #STAGES)
            stageName.text = stage.name
            stageNote.text = stage.note or ""
            openButton:SetClass("collapsed", FindJournalPage(stage.page) == nil)
            local bookEntry = STAGE_BOOK[stage.id]
            bookButton:SetClass("collapsed", bookEntry == nil or Book() == nil)
            if bookEntry ~= nil then
                bookButton.text = string.format("Book p. %d", PrintedPage(bookEntry[1]))
            end
            backButton:SetClass("collapsed", n <= 1)
            if n < #STAGES then
                nextButton:SetClass("collapsed", false)
                nextButton.text = "Next: " .. STAGES[n + 1].name
            else
                nextButton:SetClass("collapsed", true)
            end
        end,
        children = {
            Row(partGroups, { bmargin = 8 }),
            stageCounter,
            stageName,
            stageNote,
            Row({ openButton, bookButton, backButton, nextButton }, { tmargin = 8 }),
        },
    }
end

--------------------------------------------------------------------------------
-- Rosters
--------------------------------------------------------------------------------

--One row per hero on the roster. The first rows are built in the constructor rather
--than in a create event: rows a panel gives itself in create, inside the scrolling
--area, kept stale click areas once the area was scrolled (clicks fell through).
local function CreateRosterList(rowFactory)
    local function RosterKey(roster)
        local ids = {}
        for i, e in ipairs(roster) do
            ids[i] = e.charid
        end
        return table.concat(ids, ",")
    end

    --builds the list's children, reusing rows that already exist.
    local function BuildChildren(roster, oldRows)
        local children = {}
        local rows = {}
        for i, e in ipairs(roster) do
            local row = oldRows[e.charid]
            if row == nil or not row.valid then
                row = rowFactory(e)
            end
            rows[e.charid] = row
            if i > 1 then
                children[#children + 1] = Seam()
            end
            children[#children + 1] = row
        end
        if #children == 0 then
            children[1] = Muted("No heroes yet: put the Condemned in the player party, or collar them in Loyalty Collars.", { width = "100%", fontSize = 12 })
        end
        return children, rows
    end

    local roster = Roster()
    local initialChildren, initialRows = BuildChildren(roster, {})

    return gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",
        thinkTime = 1,
        data = { key = RosterKey(roster), rows = initialRows },
        children = initialChildren,
        think = function(element)
            local current = Roster()
            local key = RosterKey(current)
            if key == element.data.key then
                return
            end
            element.data.key = key
            local children, rows = BuildChildren(current, element.data.rows)
            element.data.rows = rows
            element.children = children
        end,
        refreshCampaign = function(element)
            element:FireEvent("think")
        end,
    }
end

--------------------------------------------------------------------------------
-- The collar record, in the Loyalty Collars panel
--------------------------------------------------------------------------------
--The Loyalty Collars panel (Condemned.lua) is the one place the Condemned are
--listed. It asks for these pieces through CondemnedCampaign.CollarPanelParts when it
--opens (Condemned.lua loads first, so it cannot call them directly): a summary at
--the top, a line under each hero row, and an "Elsewhere" group for the rest of the
--roster. They refresh themselves: the collars panel sends no campaign events.

--a roster entry for a hero, or a stand-in when the hero is not on the roster.
local function RosterEntry(charid)
    for _, e in ipairs(Roster()) do
        if e.charid == charid then
            return e
        end
    end
    local token = dmhub.GetCharacterById(charid)
    return { charid = charid, token = token, name = token ~= nil and token.name or "Hero" }
end

--true when the Loyalty Collars panel already has a row for the hero: on this map,
--or blown up on it.
local function OnThisMap(charid)
    if dmhub.GetTokenById(charid) ~= nil then
        return true
    end
    local collars = Collars()
    local exploded = collars ~= nil and collars.GetExploded()[charid] or nil
    return exploded ~= nil and exploded.mapid == game.currentMapId
end

local function MedicalDropdown(entry, width)
    return gui.Dropdown {
        classes = { "sizeS" },
        width = width or 170,
        height = 22,
        fontSize = 11,
        halign = "left",
        valign = "center",
        options = MEDICAL_OPTIONS,
        idChosen = "pick",
        change = function(element)
            ---@cast element Dropdown
            local result = element.idChosen
            element.idChosen = "pick"
            if result ~= "pick" then
                RunMedical(entry, result)
            end
        end,
    }
end

--the campaign's word on one hero's collar, for the line under their row.
--Returns the text, and which of "medical", "count" and "undo" to offer.
local function CollarNote(entry)
    local status = CollarStatus(entry.charid, entry.token)
    local record = (Data().collars or {})[entry.charid]
    local finale = Reached("finale")
    if status == "collared" then
        if finale then
            return "Medical station:", "medical"
        end
        return nil
    elseif status == "removed" then
        return string.format("Collar off for the ending (%s).", record ~= nil and record.how or "recorded"), "undo"
    elseif status == "detonated" then
        if record ~= nil and record.how ~= nil then
            return "Detonated: " .. record.how .. "."
        end
        return nil
    elseif finale then
        return "No collar on, but not counted as removed for the ending.", "count"
    end
    return nil
end

--The line under a hero's row in the Loyalty Collars panel. Collapses when there is
--nothing to add to the row.
local function CollarRowExtras(charid)
    local entry = RosterEntry(charid)
    local note = Muted("", { valign = "center", fontSize = 12, rmargin = 8 })
    local medical = MedicalDropdown(entry)
    local countButton = Button("Count as removed", 130, function()
        TakeCollarOff(entry, "by hand", string.format("COLLAR: %s's collar is off", entry.name))
    end, { hover = gui.Tooltip("Record this hero's collar as taken off: it counts for the ending.") })
    local undoButton = Button("Undo", 54, function()
        RecordCollar(entry.charid, nil)
        SyncCollarsRemovedCounter()
    end, { hover = gui.Tooltip("Forget the recorded removal.") })

    local panel
    local function Refresh()
        entry.token = dmhub.GetTokenById(charid) or entry.token
        local text, offer = CollarNote(entry)
        panel:SetClass("collapsed", text == nil)
        note.text = text or ""
        medical:SetClass("collapsed", offer ~= "medical")
        countButton:SetClass("collapsed", offer ~= "count")
        undoButton:SetClass("collapsed", offer ~= "undo")
    end

    panel = gui.Panel {
        styles = ThemeEngine.MergeTokens(BuildStyles()),
        flow = "horizontal",
        width = "100%",
        height = 26,
        lmargin = 52,
        bmargin = 4,
        thinkTime = 0.5,
        think = Refresh,
        children = { note, medical, countButton, undoButton },
    }
    Refresh()
    return panel
end

--The top of the Loyalty Collars panel: how many still wear a collar, what that
--means for the ending, and where the book explains it.
local function CollarSummary()
    local counts = Label("", { fontSize = 13, bold = true, classes = { "ccStrong" } })
    local ending = Label("", { fontSize = 12, classes = { "ccVerdict" }, width = "100%", tmargin = 2 })
    local method = Muted("The Archivist told them how: the Medical station succeeds automatically (tier 3).", { width = "100%", fontSize = 12, tmargin = 2 })

    local panel
    local function Refresh()
        local c = CollarCounts()
        local parts = { string.format("%d collared", c.collared) }
        if c.removed > 0 then parts[#parts + 1] = string.format("%d off", c.removed) end
        if c.detonated > 0 then parts[#parts + 1] = string.format("%d detonated", c.detonated) end
        if c.none > 0 then parts[#parts + 1] = string.format("%d without a collar", c.none) end
        counts.text = "The Condemned: " .. table.concat(parts, "  -  ")
        local finale = Reached("finale")
        ending:SetClass("collapsed", not finale)
        if finale then
            local title = EndingVerdict()
            ending.text = "The ending as it stands: " .. title
        end
        method:SetClass("collapsed", not (finale and Flag("collar_method_known")))
    end

    panel = gui.Panel {
        styles = ThemeEngine.MergeTokens(BuildStyles()),
        flow = "vertical",
        width = "100%",
        height = "auto",
        bmargin = 8,
        thinkTime = 0.5,
        think = Refresh,
        children = {
            counts,
            ending,
            method,
            gui.Panel {
                width = "100%",
                height = "auto",
                tmargin = 4,
                children = {
                    BookLinks {
                        { "The loyalty collars", 8, "Into the Fire" },
                        { "Refusing the Call", 9, "Sidebar: Refusing the Call" },
                        { "The Medical station", 47, "Station 4: Medical:", "Station 5" },
                        { "Choice of Endings", 49, "Choice of Endings", "Continuing the Campaign" },
                    },
                },
            },
        },
    }
    Refresh()
    return panel
end

--One hero who is not on this map: portrait, name, collar status, and the record
--(or, at the finale, the Medical station, which works on a hero anywhere).
local function CreateElsewhereRow(entry)
    local chip = Chip("", nil, { width = 86, halign = "left" })
    local detail = Muted("", { width = 170, halign = "left", valign = "center", fontSize = 11 })
    local medical = MedicalDropdown(entry, 170)
    local undoButton = Button("Undo", 54, function()
        RecordCollar(entry.charid, nil)
        SyncCollarsRemovedCounter()
    end, { lmargin = 6, hover = gui.Tooltip("Forget the recorded removal.") })
    local countButton = Button("Count as removed", 130, function()
        TakeCollarOff(entry, "by hand", string.format("COLLAR: %s's collar is off", entry.name))
    end, { lmargin = 6, hover = gui.Tooltip("Record this hero's collar as taken off: it counts for the ending.") })

    local function Refresh()
        local status = CollarStatus(entry.charid, entry.token)
        SetChip(chip, STATUS_TEXT[status], STATUS_CLASS[status])
        local record = (Data().collars or {})[entry.charid]
        local _, offer = CollarNote(entry)
        detail.text = (record ~= nil and record.how ~= nil and (status == "removed" or status == "detonated")) and record.how or ""
        detail:SetClass("collapsed", offer == "medical")
        medical:SetClass("collapsed", offer ~= "medical")
        undoButton:SetClass("collapsed", offer ~= "undo")
        countButton:SetClass("collapsed", offer ~= "count")
    end

    local row = gui.Panel {
        flow = "horizontal",
        width = "100%",
        height = 30,
        valign = "center",
        thinkTime = 0.5,
        think = Refresh,
        children = {
            gui.CreateTokenImage(entry.token, { width = 24, height = 24, halign = "left", valign = "center", rmargin = 8 }),
            Label(entry.name, { width = 200, halign = "left", valign = "center", fontSize = 13 }),
            chip,
            gui.Panel { width = 10, height = 1 },
            detail,
            medical,
            undoButton,
            countButton,
            gui.Button {
                icon = "phosphor/x-bold.png",
                width = 14,
                height = 14,
                halign = "right",
                valign = "center",
                hover = gui.Tooltip("Leave this hero out of the Condemned list."),
                press = function()
                    ChangeDoc("Roster", function(data)
                        data.rosterHidden = data.rosterHidden or {}
                        data.rosterHidden[entry.charid] = true
                    end)
                    ForgetRosterCache()
                end,
            },
        },
    }
    Refresh()
    return row
end

--"Elsewhere": the Condemned who are not on this map, folded away by default.
local ELSEWHERE_PREF = "condemned:collars:elsewhere"

--reopen (optional): places the popup afresh after folding or unfolding the group.
local function CollarElsewhere(reopen)
    local function Heroes()
        local result = {}
        for _, e in ipairs(Roster()) do
            if not OnThisMap(e.charid) then
                result[#result + 1] = e
            end
        end
        return result
    end
    local function Key(list)
        local ids = {}
        for i, e in ipairs(list) do
            ids[i] = e.charid
        end
        return table.concat(ids, ",")
    end

    local rows = {}
    local list = gui.Panel { flow = "vertical", width = "100%", height = "auto" }
    local title = Label("", { classes = { "ccTitle" }, bold = true, fontSize = 13, valign = "center" })
    local caret = gui.ExpandoArrow {
        bgimage = "phosphor/caret-down-fill.png",
        width = 12,
        height = 12,
        valign = "center",
        rmargin = 6,
    }
    local showEveryone = Button("Show everyone", 120, function()
        ChangeDoc("Roster", function(data)
            data.rosterHidden = {}
        end)
        ForgetRosterCache()
    end, { tmargin = 4, hover = gui.Tooltip("Bring back any hero you left out of the list.") })

    local body = gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",
        children = { list, showEveryone },
    }

    local panel
    local key = nil
    local function Refresh()
        local heroes = Heroes()
        local k = Key(heroes)
        if k ~= key then
            key = k
            local children = {}
            local kept = {}
            for i, e in ipairs(heroes) do
                local row = rows[e.charid]
                if row == nil or not row.valid then
                    row = CreateElsewhereRow(e)
                end
                kept[e.charid] = row
                if i > 1 then
                    children[#children + 1] = Seam()
                end
                children[#children + 1] = row
            end
            rows = kept
            list.children = children
        end
        title.text = string.format("Elsewhere (%d)", #heroes)
        local open = dmhub.GetPref(ELSEWHERE_PREF) == true
        caret:SetClass("expanded", open)
        body:SetClass("collapsed", not open)
        local anyHidden = next(Data().rosterHidden or {}) ~= nil
        showEveryone:SetClass("collapsed", not anyHidden)
        panel:SetClass("collapsed", #heroes == 0 and not anyHidden)
    end

    panel = gui.Panel {
        styles = ThemeEngine.MergeTokens(BuildStyles()),
        flow = "vertical",
        width = "100%",
        height = "auto",
        tmargin = 8,
        thinkTime = 1,
        think = Refresh,
        children = {
            gui.Panel {
                flow = "horizontal",
                width = "100%",
                height = 26,
                bgimage = "panels/square.png",
                bgcolor = "#00000001",
                press = function()
                    dmhub.SetPref(ELSEWHERE_PREF, dmhub.GetPref(ELSEWHERE_PREF) ~= true)
                    if reopen ~= nil then
                        --after this press has finished: reopening destroys this panel.
                        dmhub.Schedule(0.01, function()
                            if not mod.unloaded then
                                reopen()
                            end
                        end)
                    else
                        Refresh()
                    end
                end,
                children = {
                    caret,
                    title,
                    Muted("the Condemned on other maps", { valign = "center", lmargin = 10 }),
                },
            },
            gui.Panel { classes = { "ccRule" }, width = "100%", height = 1, bmargin = 4 },
            body,
        },
    }
    Refresh()
    return panel
end

--------------------------------------------------------------------------------
-- Section: intel and alarm
--------------------------------------------------------------------------------

local function CreateAlarmPips()
    local pips = {}
    for i = 1, IntelTracker.ALARM_MAX do
        pips[i] = gui.Panel {
            classes = { "ccPip" },
            width = 30,
            height = 12,
            rmargin = 4,
            valign = "center",
            hover = gui.Tooltip(string.format("Set the alarm to %d", i)),
            press = function()
                local now = IntelTracker.Alarm()
                local target = i
                if now == i then
                    target = i - 1
                end
                IntelTracker.BumpAlarm(target - now)
            end,
        }
    end
    return gui.Panel {
        flow = "horizontal",
        width = "auto",
        height = "auto",
        valign = "center",
        children = pips,
        refreshCampaign = function()
            local alarm = IntelTracker.Alarm()
            for i, pip in ipairs(pips) do
                pip:SetClass("filled", i <= alarm)
            end
        end,
    }
end

local function CreateIntelSourceButton(source)
    local button
    button = Button(string.format("+%d  %s", source.amount, source.label), 290, function()
        if SourceClaimed(source) then
            UnclaimSource(source)
        else
            ClaimSource(source)
        end
    end, {
        hover = gui.Tooltip((source.hint and (source.hint .. "\n") or "") .. "Once only. Click again to take it back."),
        refreshCampaign = function(element)
            local claimed = (Data().claimed or {})[source.group or source.id]
            local mine = claimed == source.id
            element:SetClass("selected", mine)
            element:SetClass("disabled", claimed ~= nil and not mine)
            element.text = string.format("%s%+d  %s", mine and "Granted: " or "", source.amount, source.label)
        end,
    })
    return UntilStage(source.stage, button)
end

local function CreateSpendButton(spend)
    local button = Button(string.format("-%d  %s", spend.cost, spend.label), 290, function()
        Spend(spend.cost, spend.label, spend.effect)
    end, {
        hover = gui.Tooltip(spend.hint or spend.label),
        refreshCampaign = function(element)
            element:SetClass("disabled", IntelTracker.Pool() < spend.cost)
        end,
    })
    return UntilStage(spend.stage, button)
end

--two buttons a line.
local function Pairs(widgets)
    local rows = {}
    for i = 1, #widgets, 2 do
        local children = { widgets[i] }
        if widgets[i + 1] ~= nil then
            children[2] = widgets[i + 1]
        end
        rows[#rows + 1] = Row(children, { vpad = 2 })
    end
    return gui.Panel { flow = "vertical", width = "100%", height = "auto", children = rows }
end

--Each Pairs cell is a fixed-width slot so the two columns line up.
local function Cell(widget)
    return gui.Panel { width = 304, height = "auto", children = { widget } }
end

local function CreateIntelSection()
    local intelNumber = Label("0", { fontSize = 40, bold = true, classes = { "ccIntel" }, valign = "center", rmargin = 14 })
    local alarmNumber = Label("0", { fontSize = 22, bold = true, classes = { "ccAlarm" }, valign = "center", rmargin = 10 })
    local alarmText = Small("", { width = "100%", tmargin = 4 })
    local patrolText = Small("", { width = "100%", classes = { "ccStrong" } })

    local gateReductions = 0
    local gateLabel = Small("", { valign = "center", width = 260 })
    local function RefreshGate()
        gateLabel.text = string.format("Redoubt gate: %d intel  (6 + alarm, max 11, -%d)", RedoubtGateCost(gateReductions), gateReductions)
    end

    local sources = {}
    for _, source in ipairs(INTEL_SOURCES) do
        sources[#sources + 1] = Cell(CreateIntelSourceButton(source))
    end
    local spends = {}
    for _, spend in ipairs(INTEL_SPENDS) do
        spends[#spends + 1] = Cell(CreateSpendButton(spend))
    end
    local alarmEvents = {}
    for _, ev in ipairs(ALARM_EVENTS) do
        alarmEvents[#alarmEvents + 1] = Cell(Button(string.format("%+d  %s", ev.delta, ev.label), 290, function()
            IntelTracker.BumpAlarm(ev.delta)
        end, { hover = gui.Tooltip(ev.hint or ev.label) }))
    end

    return Section {
        id = "intel",
        refs = {
            { "Gathering Intel", 22, "Gathering Intel" },
            { "Spending Intel", 22, "Spending Intel" },
            { "Crysopolis Alarm Level", 20, "Crysopolis Alarm Level" },
            { "Montage outcomes", 21, "Montage Test Outcomes" },
            { "Patrols", 21, "Montage Test Combat Encounters", "Crysopolis Road Map" },
            { "Handout: The Crysopolis", 60, "Handout: The Crysopolis", "" },
            { "Director Reference: Crysopolis Infiltration", 62, "Director Reference: Crysopolis", "" },
        },
        title = "Intel and Alarm",
        unlock = "hub",
        summary = function()
            return string.format("%d intel  -  alarm %d of %d", IntelTracker.Pool(), IntelTracker.Alarm(), IntelTracker.ALARM_MAX)
        end,
        children = {
            Row({
                intelNumber,
                gui.Panel {
                    flow = "vertical",
                    width = 150,
                    height = "auto",
                    valign = "center",
                    children = {
                        Muted("PARTY INTEL", { bold = true }),
                        Row({
                            gui.Button { classes = { "sizeXxs" }, halign = "left", text = "-", press = function() IntelTracker.Adjust(-1, "Intel adjusted") end },
                            gui.Button { classes = { "sizeXxs" }, halign = "left", text = "+", lmargin = 6, press = function() IntelTracker.Adjust(1, "Intel adjusted") end },
                        }, { tmargin = 4 }),
                    },
                },
                gui.Panel {
                    flow = "vertical",
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    children = {
                        Muted("ALARM", { bold = true }),
                        Row({ alarmNumber, CreateAlarmPips() }, { width = "auto" }),
                    },
                },
            }, {
                refreshCampaign = function()
                    intelNumber.text = tostring(IntelTracker.Pool())
                    local alarm = IntelTracker.Alarm()
                    alarmNumber.text = tostring(alarm)
                    local level = ALARM_LEVELS[alarm] or ALARM_LEVELS[0]
                    alarmText.text = level.text
                    if level.patrol ~= nil then
                        patrolText.text = string.format("A montage total failure brings a %s, or %d intel buys the password.", level.patrol, alarm)
                    else
                        patrolText.text = "A montage total failure brings no patrol yet (alarm under 2)."
                    end
                    RefreshGate()
                end,
            }),
            patrolText,
            alarmText,
            gui.Check {
                text = "The players can see the Intel Tracker",
                value = Flag(INTEL_ENABLED_FLAG),
                width = "auto",
                height = 22,
                minWidth = 0,
                fontSize = 12,
                tmargin = 6,
                change = function(element)
                    local value = element.value == true
                    if value ~= Flag(INTEL_ENABLED_FLAG) then
                        SetFlag(INTEL_ENABLED_FLAG, value, value and "INTEL: the Intel Tracker is open to the players" or "INTEL: the Intel Tracker is hidden")
                    end
                end,
                refreshCampaign = function(element)
                    if element.value ~= Flag(INTEL_ENABLED_FLAG) then
                        element.value = Flag(INTEL_ENABLED_FLAG)
                    end
                end,
            },

            SubHeading("Earn intel", { "Gathering Intel", 22, "Gathering Intel" }),
            Pairs(sources),

            SubHeading("Spend intel", { "Spending Intel", 22, "Spending Intel" }),
            Pairs(spends),
            UntilStage("redoubt", Row({
                gateLabel,
                gui.Button { classes = { "sizeXxs" }, halign = "left", text = "-", valign = "center", press = function()
                    gateReductions = math.max(0, gateReductions - 1)
                    RefreshGate()
                end, hover = gui.Tooltip("Remove a skill reduction") },
                gui.Button { classes = { "sizeXxs" }, halign = "left", text = "+", lmargin = 4, valign = "center", press = function()
                    gateReductions = math.min(3, gateReductions + 1)
                    RefreshGate()
                end, hover = gui.Tooltip("One less for each of Forgery, Lie and Disguise (up to 3)") },
                Button("Pay", 60, function()
                    Spend(RedoubtGateCost(gateReductions), "Entered the Redoubt by the gate")
                    ChangeDoc("Redoubt route", function(data)
                        data.redoubtRoute = "gate"
                    end)
                end, { lmargin = 10 }),
            }, { vpad = 3 })),
            Row({
                Small("Avoid a patrol: intel equal to the alarm", { valign = "center", width = 260 }),
                Button("Pay", 60, function()
                    Spend(IntelTracker.Alarm(), "The password: avoided a patrol")
                end, { lmargin = 52, refreshCampaign = function(element)
                    element:SetClass("disabled", IntelTracker.Alarm() <= 0 or IntelTracker.Pool() < IntelTracker.Alarm())
                end }),
            }, { vpad = 3 }),

            SubHeading("Alarm", { "Crysopolis Alarm Level", 20, "Crysopolis Alarm Level" }),
            Muted("Starts at 0, or 1 if any war dog from the Teleportation Hub survived.", { width = "100%", fontSize = 12, bmargin = 2 }),
            Pairs(alarmEvents),
        },
    }
end

--------------------------------------------------------------------------------
-- Section: Part 1
--------------------------------------------------------------------------------

local ABBEY_FIRE_TEXT = {
    [0] = "Nothing burning",
    [1] = "Tapestries alight, the clock is running",
    [2] = "Beyond putting out",
    [3] = "The abbey has collapsed",
}

local function CreatePartOneSection()
    return Section {
        id = "part1",
        refs = {
            { "Combat: Inner Sanctum", 10, "Combat: Inner Sanctum" },
            { "Carpet and Tapestries (fire)", 11, "Carpet and Tapestries" },
            { "Hidden Basement", 13, "Hidden Basement" },
            { "The teleporter", 13, "Teleporter" },
            { "Returning to de Caserta", 15, "Returning to de Caserta" },
        },
        title = "Part 1: The Abbey",
        unlock = "abbey",
        summary = function()
            return string.format("%d of 3 documents saved", Counter("documents_saved"))
        end,
        children = {
            CounterRow("documents_saved", "Coded documents saved", { min = 0, max = 3, hint = "Gerold burns one each turn." }),
            Small("", {
                width = "100%",
                classes = { "ccMuted" },
                refreshCampaign = function(element)
                    local saved = Counter("documents_saved")
                    element.text = string.format("Back at de Caserta: %d Victor%s each. Gerold's passcode paper has %d readable passcode%s; Part 2 starts with %d intel.",
                        saved > 0 and 2 or 1, saved > 0 and "ies" or "y", saved, saved == 1 and "" or "s", saved)
                end,
            }),
            Row({
                Label("The abbey fire", { width = 220, valign = "center" }),
                Small("", {
                    valign = "center",
                    refreshCampaign = function(element)
                        local stage = Counter("abbey_fire")
                        element.text = ABBEY_FIRE_TEXT[stage] or tostring(stage)
                    end,
                }),
            }, { vpad = 3 }),
            FlagRow("abbey_gerold_fled", "Gerold went down the statue shaft"),
            CounterRow("riojan_bottles", "Riojan Gold bottles carried", { min = 0, hint = "Three in the basement." }),
            FlagRow("part1_clock_started", "The one-hour clock is running"),
        },
    }
end

--------------------------------------------------------------------------------
-- Section: Gerold's head
--------------------------------------------------------------------------------

local function CreateGeroldRow(entry)
    local chip = Chip("", nil, { width = 84, halign = "left" })
    local score = Label("0", { width = 30, fontSize = 13, bold = true, textAlignment = "center", halign = "left", valign = "center" })
    return Row({
        gui.CreateTokenImage(entry.token, { width = 22, height = 22, halign = "left", valign = "center", rmargin = 8 }),
        Label(entry.name, { width = 230, halign = "left", valign = "center" }),
        chip,
        gui.Button { classes = { "sizeXxs" }, text = "-", lmargin = 12, halign = "left", valign = "center",
            hover = gui.Tooltip("Insulted, shocked or muted him"),
            press = function() AdjustGerold(entry, -1) end },
        score,
        gui.Button { classes = { "sizeXxs" }, text = "+", halign = "left", valign = "center",
            hover = gui.Tooltip("Wine, sweet-talk or a bribe"),
            press = function() AdjustGerold(entry, 1) end },
    }, {
        height = 28,
        create = function(element)
            element:FireEvent("refreshCampaign")
        end,
        refreshCampaign = function()
            local s = GeroldScore(entry.charid)
            local text, class = GeroldStanding(s)
            SetChip(chip, text, class)
            score.text = string.format("%+d", s)
        end,
    })
end

local function CarrierOptions()
    local options = { { id = "none", text = "Nobody yet" } }
    for _, entry in ipairs(Roster()) do
        options[#options + 1] = { id = entry.charid, text = entry.name }
    end
    return options
end

local function CreateGeroldSection()
    local carrier
    carrier = gui.Dropdown {
        classes = { "sizeS" },
        width = 300,
        height = 24,
        fontSize = 12,
        halign = "left",
        valign = "center",
        options = CarrierOptions(),
        idChosen = Data().geroldCarrier or "none",
        change = function(element)
            ---@cast element Dropdown
            local choice = element.idChosen
            if choice ~= (Data().geroldCarrier or "none") then
                ChangeDoc("Gerold's carrier", function(data)
                    data.geroldCarrier = choice
                end)
            end
        end,
        refreshCampaign = function(element)
            ---@cast element Dropdown
            element.options = CarrierOptions()
            element.idChosen = Data().geroldCarrier or "none"
        end,
    }

    return Section {
        id = "gerold",
        refs = {
            { "Gerold's Head", 16, "Gerold's Head" },
            { "Director Reference: Gerold's Head", 64, "Director Reference: Gerold's Head" },
            { "Interrogating Gerold", 64, "Interrogating Gerold", "" },
            { "Spider Gerold", 55, "Spider Gerold", "" },
        },
        title = "Gerold's Head",
        unlock = "head",
        summary = function()
            if Flag("gerold_departed") then
                return "taken by the Returns slot"
            end
            local kind, cruel = 0, 0
            for _, entry in ipairs(Roster()) do
                if GeroldScore(entry.charid) > 0 then kind = kind + 1 else cruel = cruel + 1 end
            end
            return string.format("%d kind  -  %d cruel or indifferent", kind, cruel)
        end,
        children = {
            Muted("\"Gerold holds grudges and remembers favors.\" He hates being silenced more than being shocked; a party that insults him often gets incomplete answers. At the Sky Harbor, Now Our Debts Are Paid slides a kind target toward safety and anyone cruel or indifferent toward danger.", { width = "100%", fontSize = 12, bmargin = 6 }),
            Row({ Label("Carried by", { width = 220, valign = "center" }), carrier }, { vpad = 3 }),
            CreateRosterList(CreateGeroldRow),
            Seam(),
            Row({
                Label("Riojan Gold", { width = 220, valign = "center" }),
                Button("Pour a bottle", 110, function()
                    if Counter("riojan_bottles") <= 0 then
                        return
                    end
                    Log({ { kind = "counter", key = "riojan_bottles", delta = -1 } }, "RIOJAN GOLD -1: poured into Gerold's valve")
                    local carrierId = Data().geroldCarrier
                    for _, entry in ipairs(Roster()) do
                        if entry.charid == carrierId then
                            AdjustGerold(entry, 1)
                        end
                    end
                end, {
                    hover = gui.Tooltip("He turns friendly, and Question Gerold succeeds automatically. Counts as a kindness from whoever carries him."),
                    refreshCampaign = function(element)
                        element:SetClass("disabled", Counter("riojan_bottles") <= 0)
                    end,
                }),
                Small("", { valign = "center", lmargin = 10, refreshCampaign = function(element)
                    element.text = string.format("%d bottle%s left", Counter("riojan_bottles"), Counter("riojan_bottles") == 1 and "" or "s")
                end }),
            }, { vpad = 3 }),
            FlagRow("gerold_departed", "Taken by the Archivist's Returns slot", "Record Control: he is ripped away before the talk-or-fight choice."),
        },
    }
end

--------------------------------------------------------------------------------
-- Section: the Crysopolis
--------------------------------------------------------------------------------

local REDOUBT_ROUTES = {
    { id = "unknown", text = "Not yet" },
    { id = "gate", text = "Through the gate (intel)" },
    { id = "negotiated", text = "Past the dwarves: negotiated or bluffed" },
    { id = "fought", text = "Past the dwarves: fought them" },
    { id = "other", text = "Another way in" },
}

local function CreateCrysopolisSection()
    return Section {
        id = "crysopolis",
        refs = {
            { "Mission Briefing", 17, "Mission Briefing" },
            { "Entering the Crysopolis", 18, "Combat: Entering the Crysopolis" },
            { "Escaping the War Dog Facility", 19, "Escaping the War Dog Facility" },
            { "The Redoubt Gate", 26, "The Redoubt Gate" },
            { "Entering the Sewers", 27, "Combat or Negotiation: Entering the Sewers" },
            { "Safe Harbor", 29, "Safe Harbor" },
            { "Meeting Khavettra", 29, "Meeting Khavettra", "" },
            { "Record Control", 31, "Negotiation or Combat: Record Control" },
            { "Fighting the Archivist", 32, "Fighting the Archivist" },
        },
        title = "Part 2: The Crysopolis",
        unlock = "briefing",
        summary = function()
            local bits = {}
            if Flag("respite_used") then bits[#bits + 1] = "respite used" else bits[#bits + 1] = "respite left" end
            if Flag("khavettra_ally") then bits[#bits + 1] = "Khavettra allied" end
            if Flag("khavettra_betrayed") then bits[#bits + 1] = "Khavettra betrayed" end
            return table.concat(bits, "  -  ")
        end,
        children = {
            FlagRow("mission_clock_started", "The 48-hour clock is running"),
            FlagRow("respite_used", "The party has taken its one respite", "At Khavettra's safehouse or another local's. Only one in the 48 hours."),
            UntilStage("hub", FlagRow("wanted_posters", "Wanted posters are up", "They used violence in the Teleportation Hub. Changes the read-aloud at the Redoubt gate.")),
            UntilStage("hub", CounterRow("strike_teams_fought", "War Dog Strike Teams fought", { min = 0, hint = "Each later one brings 2 more commandos per earlier fight." })),
            UntilStage("redoubt", ChoiceRow("redoubtRoute", "Into the Redoubt", REDOUBT_ROUTES, function(choice)
                local fought = choice == "fought"
                if fought ~= Flag("fought_the_dwarves") then
                    SetFlag("fought_the_dwarves", fought, fought and "REDOUBT: fought the dwarves" or "REDOUBT: did not fight the dwarves")
                end
                Log({}, "REDOUBT: " .. (choice == "unknown" and "route cleared" or choice))
            end)),
            UntilStage("khavettra", FlagRow("khavettra_ally", "Working with Khavettra", "+3 intel, a safehouse respite and a chatbox (an edge on Drive, Mechanics, Society and Timescape).")),
            UntilStage("recordcontrol", FlagRow("khavettra_betrayed", "Khavettra betrayed to the Archivist", "Unless the Archivist dies, Khavettra vanishes and the chatbox goes dead.")),
            UntilStage("recordcontrol", FlagRow("collar_method_known", "They know how to take the collars off", "The Archivist at Interest 3+: the Medical station succeeds automatically.")),
            UntilStage("recordcontrol", FlagRow("advance_location_known", "They know where ADVANCE is", "From the Archivist (Interest 3+, if asked) or the file if they fight him.")),
        },
    }
end

--------------------------------------------------------------------------------
-- Section: Part 3
--------------------------------------------------------------------------------

local LETITIA_FATES = {
    { id = "unknown", text = "Not found yet" },
    { id = "rescued", text = "Rescued, following the party" },
    { id = "barred", text = "Rescued, but no longer a retainer" },
    { id = "lost", text = "Captured or killed at the cache" },
}

local function CreatePartThreeSection()
    return Section {
        id = "part3",
        refs = {
            { "Advanced Research", 34, "Advanced Research" },
            { "Securing the Asset", 35, "Combat: Securing the Asset" },
            { "Iron Security Door", 36, "Iron Security Door", "Tactics" },
            { "Rescuing Lady Letitia", 38, "Rescuing Lady Letitia" },
            { "Bluepowder Cache Room", 39, "Combat: Bluepowder Cache Room" },
            { "Sky Harbor battle events", 43, "Battle Events" },
        },
        title = "Part 3: The Armory",
        unlock = "armory",
        summary = function()
            local bits = {}
            bits[#bits + 1] = Flag("letitia_rescued") and "Letitia rescued" or "Letitia not rescued"
            if Flag("bluepowder_lit") then bits[#bits + 1] = "bluepowder lit" end
            return table.concat(bits, "  -  ")
        end,
        children = {
            FlagRow("mission_abandoned", "They abandoned the mission", "One infiltration montage, then straight to the Sky Harbor."),
            UntilStage("asset", ChoiceRow("letitia", "Lady Letitia", LETITIA_FATES, function(choice)
                local rescued = choice == "rescued" or choice == "barred"
                if rescued ~= Flag("letitia_rescued") then
                    SetFlag("letitia_rescued", rescued, rescued and "LETITIA: rescued" or "LETITIA: not rescued")
                end
            end)),
            UntilStage("asset", Muted("She joins when the security door opens; whoever opened it controls her first. Barred from the cache, she comes along but is lost as a retainer.", { width = "100%", fontSize = 12, bmargin = 4 })),
            UntilStage("bluepowder", FlagRow("bluepowder_lit", "All three crate stacks are lit", "At the Sky Harbor the Armory explodes at the end of round 2: Squad B dies, and each creature within 10 rolls a d6 (3 or lower: 15 damage); the area is difficult terrain. Unlit: Squad B's ten war frogs join the fight.")),
            UntilStage("skyharbor", FlagRow("khavettra_aboard", "Khavettra made it aboard", "They waited for him (+1 hero token); leaving without him gets him killed.")),
        },
    }
end

--------------------------------------------------------------------------------
-- Section: Action Stations
--------------------------------------------------------------------------------

local function CreateJusticeBar()
    local fill = gui.Panel { classes = { "ccBarFill" }, width = "100%", height = "100%", halign = "left" }
    local text = Label("", { fontSize = 14, bold = true, halign = "center", valign = "center", floating = true, classes = { "ccStrong" } })
    return gui.Panel {
        classes = { "ccBarTrack" },
        width = "100%",
        height = 22,
        tmargin = 4,
        bmargin = 6,
        children = { fill, text },
        refreshCampaign = function()
            local hp = Counter("justice_stamina")
            local fraction = math.max(0, math.min(1, hp / JUSTICE_MAX))
            fill.selfStyle.width = string.format("%d%%", math.floor(fraction * 100 + 0.5))
            fill:SetClass("low", fraction <= 0.5 and fraction > 0.25)
            fill:SetClass("critical", fraction <= 0.25)
            text.text = string.format("THE JUSTICE  %d / %d", hp, JUSTICE_MAX)
        end,
    }
end

local function JusticeButton(delta, reason)
    return Button(string.format("%+d", delta), 52, function()
        local now = Counter("justice_stamina")
        local after = math.max(0, math.min(JUSTICE_MAX, now + delta))
        if after ~= now then
            Log({ { kind = "counter", key = "justice_stamina", set = after } },
                string.format("JUSTICE %+d: %s (%d)", after - now, reason, after))
        end
    end, { rmargin = 4, hover = gui.Tooltip(reason) })
end

local function CreateFinaleSection()
    return Section {
        id = "finale",
        refs = {
            { "Flying the Cruiser", 45, "Montage Test: Flying the Cruiser" },
            { "Action Stations!", 47, "Montage Test: Action Stations!" },
            { "The escape pod", 48, "If the Justice is Destroyed" },
            { "Handout: Flying the Justice", 61, "Handout: Flying the Justice on Wings of Iron", "" },
        },
        title = "Action Stations",
        unlock = "finale",
        summary = function()
            return string.format("the Justice %d / %d", Counter("justice_stamina"), JUSTICE_MAX)
        end,
        children = {
            Muted("Three rounds, each station once per round. Intel buys +1 tier on a test. The ship never moves: enemies are repositioned instead.", { width = "100%", fontSize = 12 }),
            CreateJusticeBar(),
            Row({
                Muted("DAMAGE", { bold = true, width = 60, valign = "center" }),
                JusticeButton(-1, "Damage"),
                JusticeButton(-5, "Damage"),
                JusticeButton(-10, "Damage (a botched collar removal, a cannon misfire)"),
                JusticeButton(-20, "Damage"),
                Muted("REPAIR", { bold = true, width = 60, valign = "center", lmargin = 14 }),
                JusticeButton(5, "Repair, tier 1 (the repairer takes 20 fire damage)"),
                JusticeButton(15, "Repair, tier 2"),
                JusticeButton(20, "Repair, tier 3"),
            }),
            FlagRow("escape_pod_used", "The escape pod launched", "At 0 Stamina: two seats by Power Grab; everyone else dies. With Letitia aboard, Capital is saved."),
        },
    }
end

--------------------------------------------------------------------------------
-- Section: the ending
--------------------------------------------------------------------------------

local function CreateEndingSection()
    local verdict = Label("", { fontSize = 16, bold = true, classes = { "ccVerdict" }, width = "100%" })
    local reason = Small("", { width = "100%", tmargin = 2 })
    return Section {
        id = "ending",
        refs = {
            { "Choice of Endings", 49, "Choice of Endings", "Continuing the Campaign" },
            { "Continuing the Campaign", 49, "Continuing the Campaign", "" },
        },
        title = "The Ending",
        unlock = "finale",
        summary = function()
            return (EndingVerdict())
        end,
        children = {
            gui.Panel {
                flow = "vertical",
                width = "100%",
                height = "auto",
                refreshCampaign = function()
                    local title, why = EndingVerdict()
                    verdict.text = title
                    reason.text = why
                end,
                children = { verdict, reason },
            },
            Muted("Letitia not rescued: Ending 1 if every collar is still on, Ending 2 if any came off. Letitia rescued: Ending 3, or the players' choice of 3 or 4 if every collar is off. The book doesn't say how the dead count; this counts the living. Level 4 comes with Ending 3 or 4.", { width = "100%", fontSize = 11, tmargin = 6 }),
        },
    }
end

--------------------------------------------------------------------------------
-- Section: the handouts
--------------------------------------------------------------------------------

--One row per handout: whether the players have it, and the Director's controls.
local function CreateHandoutRow(handout)
    local chip = Chip("", nil, { width = 96, halign = "left" })
    local viewButton = Button("View", 54, function()
        ShowHandout(handout)
    end, { lmargin = 4, hover = gui.Tooltip("See the handout as the players see it") })
    local shareButton = Button("Share", 62, function()
        ShareHandout(handout, not HandoutShared(handout))
    end, { lmargin = 4 })
    local showButton = Button("Show now", 80, function()
        ShowHandoutToPlayers(handout)
    end, { lmargin = 4, hover = gui.Tooltip("Open it on every player's screen") })

    return Row({
        Label(handout.title, { width = 228, valign = "center", fontSize = 14 }),
        chip,
        Button("Book", 54, function()
            OpenBook(handout.page, "Handout: " .. handout.title, "")
        end, { lmargin = 6, hover = gui.Tooltip(string.format("Open %s at page %d", BOOK_NAME, PrintedPage(handout.page))) }),
        viewButton,
        shareButton,
        showButton,
    }, {
        height = 34,
        thinkTime = 0.5,
        create = function(element)
            element:FireEvent("refreshCampaign")
        end,
        think = function(element)
            element:FireEvent("refreshCampaign")
        end,
        refreshCampaign = function()
            local shared = HandoutShared(handout)
            local entry = HandoutEntry(handout)
            if g_handoutsUploading[handout.id] then
                SetChip(chip, "Preparing...", "ccInfo")
            elseif shared then
                SetChip(chip, "Shared", "ccOk")
            elseif Reached(handout.stage) then
                SetChip(chip, "Not shared", "ccWarn")
            else
                SetChip(chip, "Not yet", nil)
            end
            shareButton.text = shared and "Hide" or "Share"
            shareButton:SetClass("disabled", g_handoutsUploading[handout.id] == true)
            viewButton:SetClass("collapsed", entry == nil or entry.imageid == nil)
            showButton:SetClass("collapsed", not shared)
        end,
    })
end

local function CreateHandoutsSection()
    local rows = {}
    for i, handout in ipairs(HANDOUTS) do
        if i > 1 then
            rows[#rows + 1] = Seam()
        end
        rows[#rows + 1] = CreateHandoutRow(handout)
        rows[#rows + 1] = Muted(string.format("Book page %d. Shared automatically when the story reaches %s.", PrintedPage(handout.page), StageName(handout.stage)), { width = "100%", bmargin = 4 })
    end
    return Section {
        id = "handouts",
        title = "Player Handouts",
        refs = { { "Appendix: Handouts", 56 } },
        summary = function()
            local n = 0
            for _, handout in ipairs(HANDOUTS) do
                if HandoutShared(handout) then n = n + 1 end
            end
            return string.format("%d of %d shared", n, #HANDOUTS)
        end,
        children = {
            Muted("The players never see the book: a shared handout is that one page, as a picture, in their Campaign Tracker (and The Crysopolis also in their Intel Tracker). Hide takes it away again.", { width = "100%", fontSize = 12, bmargin = 6 }),
            gui.Panel { flow = "vertical", width = "100%", height = "auto", children = rows },
        },
    }
end

--------------------------------------------------------------------------------
-- Section: the campaign log
--------------------------------------------------------------------------------

local function ResetCampaign()
    CampaignState.Reset()
    ChangeDoc("Reset the campaign", function(data)
        data.stage = "cauldron"
        data.collars = {}
        data.gerold = {}
        data.claimed = {}
        data.reached = {}
        data.encounters = {}
        data.geroldCarrier = nil
        data.redoubtRoute = nil
        data.letitia = nil
        --the rendered pages are kept (no need to upload them again), unshared.
        for _, entry in pairs(data.handouts or {}) do
            entry.shared = false
        end
        data.handoutsAuto = {}
    end)
    ForgetRosterCache()
end

local function CreateLogSection()
    local list = gui.Panel { flow = "vertical", width = "100%", height = "auto" }
    --true between the Reset button's first and second click.
    local resetArmed = false
    return Section {
        id = "log",
        refs = {
            { "Playing Antiheroes", 5, "Playing Antiheroes" },
            { "Power Grab", 6, "Power Grab" },
        },
        title = "Campaign Log",
        summary = function()
            return string.format("%d entries", #CampaignState.Get().ledger)
        end,
        children = {
            gui.Panel {
                flow = "vertical",
                width = "100%",
                height = "auto",
                children = { list },
                refreshCampaign = function()
                    local ledger = CampaignState.Get().ledger
                    local children = {}
                    for i = #ledger, math.max(1, #ledger - 23), -1 do
                        children[#children + 1] = Small(ledger[i].text or "", { width = "100%", vpad = 2 })
                    end
                    if #children == 0 then
                        children[1] = Muted("Nothing recorded yet.", { fontSize = 12 })
                    end
                    list.children = children
                end,
            },
            --confirmed by a second click rather than a modal: a modal would open behind
            --this popup.
            Row({
                Button("Reset campaign...", 240, function(element)
                    if resetArmed then
                        resetArmed = false
                        element.text = "Reset campaign..."
                        ResetCampaign()
                        return
                    end
                    resetArmed = true
                    element.text = "Click again to reset everything"
                    dmhub.Schedule(6, function()
                        if element.valid and resetArmed then
                            resetArmed = false
                            element.text = "Reset campaign..."
                        end
                    end)
                end, {
                    classes = { "sizeS", "ccDangerButton" },
                    hover = gui.Tooltip("Clears every flag, counter, intel, alarm, collar record, Gerold grudge and the log, and puts the story back at the start. Collars on tokens and detonated heroes are left as they are."),
                }),
            }, { tmargin = 8 }),
        },
    }
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

---@param owner Panel|nil the rail button the popup hangs from
local function CreatePanel(owner)
    g_popupOwner = owner
    if rawget(_G, "CampaignState") == nil or rawget(_G, "IntelTracker") == nil or IntelTracker.Adjust == nil then
        return gui.Panel {
            styles = ThemeEngine.GetStyles(),
            width = "auto",
            height = "auto",
            children = {
                gui.Panel {
                    classes = { "framedPanel" },
                    width = 360,
                    height = "auto",
                    borderBox = true,
                    pad = 12,
                    children = { Label("The campaign state system is not loaded.") },
                },
            },
        }
    end

    --one page per tab; every page is built now (so it follows state changes) and
    --only the chosen one is shown.
    local tabs = {
        { id = "abbey", title = "Abbey", unlock = "abbey", create = CreatePartOneSection },
        { id = "gerold", title = "Gerold", unlock = "head", create = CreateGeroldSection },
        { id = "intel", title = "Intel", unlock = "hub", create = CreateIntelSection },
        { id = "crysopolis", title = "Crysopolis", unlock = "briefing", create = CreateCrysopolisSection },
        { id = "armory", title = "Armory", unlock = "armory", create = CreatePartThreeSection },
        { id = "finale", title = "Finale", unlock = "finale", create = function()
            return gui.Panel {
                flow = "vertical",
                width = "100%",
                height = "auto",
                children = { CreateFinaleSection(), CreateEndingSection() },
            }
        end },
        { id = "handouts", title = "Handouts", create = CreateHandoutsSection },
        { id = "log", title = "Log", create = CreateLogSection },
    }

    local function Unlocked(tab)
        return tab.unlock == nil or Reached(tab.unlock)
    end

    local function ChosenTab()
        local chosen = dmhub.GetPref("condemned:campaign:tab")
        for _, tab in ipairs(tabs) do
            if tab.id == chosen and Unlocked(tab) then
                return chosen
            end
        end
        --the first open tab; Handouts and Log always are.
        for _, tab in ipairs(tabs) do
            if Unlocked(tab) then
                return tab.id
            end
        end
        return "log"
    end

    local pages = {}
    local tabLabels = {}
    local function ShowTab()
        local chosen = ChosenTab()
        for _, tab in ipairs(tabs) do
            pages[tab.id]:SetClass("collapsed", tab.id ~= chosen)
            tabLabels[tab.id]:SetClass("selected", tab.id == chosen)
            tabLabels[tab.id]:SetClass("ccTabLocked", not Unlocked(tab))
        end
    end

    local tabRow = {}
    local pageList = {}
    for _, tab in ipairs(tabs) do
        pages[tab.id] = tab.create()
        pageList[#pageList + 1] = pages[tab.id]
        local hint = tab.unlock ~= nil and ("Opens at " .. StageName(tab.unlock)) or nil
        tabLabels[tab.id] = gui.Label {
            classes = { "tab" },
            text = tab.title,
            width = "auto",
            height = 26,
            hpad = 10,
            fontSize = 13,
            textAlignment = "center",
            valign = "bottom",
            --says when a locked tab opens; an open tab needs no tooltip.
            hover = function(element)
                if hint ~= nil and not Unlocked(tab) then
                    gui.Tooltip(hint)(element)
                end
            end,
            press = function()
                if not Unlocked(tab) then
                    return
                end
                dmhub.SetPref("condemned:campaign:tab", tab.id)
                ShowTab()
            end,
        }
        tabRow[#tabRow + 1] = tabLabels[tab.id]
    end

    local content = gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",
        tpad = 8,
        children = pageList,
        create = function()
            ShowTab()
        end,
        refreshCampaign = function()
            ShowTab()
        end,
    }

    local root
    local function Refresh()
        if root ~= nil and root.valid then
            root:FireEventTree("refreshCampaign")
        end
    end

    --the map button bar does not pass a themed cascade to its popups, so the popup
    --roots its own (see the Loyalty Collars panel).
    root = gui.Panel {
        styles = ThemeEngine.MergeStyles(BuildStyles()),
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "bottom",
        monitorGame = CampaignState.Path(),
        refreshGame = Refresh,
        create = function()
            dmhub.Schedule(0.05, Refresh)
        end,
        children = {
            gui.Panel {
                width = 1,
                height = 1,
                monitorGame = mod:GetDocumentPath(DOC_ID),
                refreshGame = Refresh,
            },
            gui.Panel {
                classes = { "framedPanel" },
                width = PANEL_WIDTH,
                height = "auto",
                flow = "vertical",
                borderBox = true,
                vpad = 10,
                children = {
                    Row({
                        Label("The Condemned", { fontSize = 20, bold = true, classes = { "ccStrong" } }),
                        Muted("CAMPAIGN", { bold = true, lmargin = 10, valign = "center", fontSize = 12 }),
                    }, { borderBox = true, hpad = 14, bmargin = 8 }),
                    CreateStoryHeader(),
                    Row(tabRow, { borderBox = true, hpad = 14, tmargin = 8 }),
                    gui.Panel { classes = { "ccRule" }, width = "100%", height = 1 },
                    --a fixed page height: the popup re-centres on the rail button whenever
                    --its height changes, so a page-sized popup would jump on every tab.
                    --Pages are built to fit; the scroll is only a fallback.
                    gui.Panel {
                        flow = "vertical",
                        width = "100%",
                        height = PAGE_HEIGHT,
                        vscroll = true,
                        children = { content },
                    },
                },
            },
        },
    }
    return root
end

CondemnedCampaign.CreatePanel = CreatePanel

--The pieces the Loyalty Collars panel shows (see "The collar record" above).
--owner is that panel's rail button: book links close the popup before opening the
--book. reopen (optional) reopens the popup, to place it again after it grows.
CondemnedCampaign.CollarPanelParts = function(owner, reopen)
    g_popupOwner = owner
    return {
        summary = CollarSummary(),
        elsewhere = CollarElsewhere(reopen),
    }
end
CondemnedCampaign.CollarRowExtras = CollarRowExtras

--------------------------------------------------------------------------------
-- The players' side: shared handouts
--------------------------------------------------------------------------------
--Everyone's Campaign Tracker lists the handouts the Director has shared; each one
--opens as a picture of its book page.

--The links, built up front as well as on change: rows a panel only gives itself
--later, inside a scrolling panel, can keep stale click areas.
local function CreatePlayerHandoutsSection()
    local function BuildLinks()
        local children = {}
        for _, handout in ipairs(HANDOUTS) do
            if HandoutShared(handout) then
                children[#children + 1] = gui.Label {
                    classes = { "link", "underline", "ccBookLink" },
                    bgimage = "panels/square.png",
                    bgcolor = "#00000001",
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    fontSize = 14,
                    vmargin = 2,
                    text = "Handout: " .. handout.title,
                    press = function()
                        ShowHandout(handout)
                    end,
                }
            end
        end
        return children
    end

    local initial = BuildLinks()
    local list = gui.Panel { flow = "vertical", width = "100%", height = "auto", children = initial }
    --collapses while nothing is shared; the outer panel stays up to hear changes.
    local content = gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",
        bmargin = 10,
        children = {
            gui.Label {
                classes = { "fgMuted", "bold" },
                width = "auto",
                height = "auto",
                halign = "left",
                fontSize = 11,
                bmargin = 4,
                text = "THE CONDEMNED: HANDOUTS",
            },
            list,
        },
    }
    content:SetClass("collapsed", #initial == 0)
    return gui.Panel {
        styles = ThemeEngine.MergeTokens(BuildStyles()),
        flow = "vertical",
        width = "100%",
        height = "auto",
        monitorGame = mod:GetDocumentPath(DOC_ID),
        refreshGame = function()
            local children = BuildLinks()
            list.children = children
            content:SetClass("collapsed", #children == 0)
        end,
        children = { content },
    }
end

local campaignTracker = rawget(_G, "CampaignTracker")
if campaignTracker ~= nil and campaignTracker.RegisterSection ~= nil then
    campaignTracker.RegisterSection {
        id = "condemnedHandouts",
        ord = -20,
        create = CreatePlayerHandoutsSection,
    }
end

--The players' Intel Tracker links the handout that explains intel and alarm, once shared.
local intelTracker = rawget(_G, "IntelTracker")
if intelTracker ~= nil then
    intelTracker.ReferenceLink = function()
        for _, handout in ipairs(HANDOUTS) do
            if handout.id == "crysopolis" and HandoutShared(handout) then
                return {
                    color = BOOK_LINK_COLOR,
                    text = "Handout: The Crysopolis (what intel buys, the alarm)",
                    press = function()
                        ShowHandout(handout)
                    end,
                }
            end
        end
        return nil
    end
end

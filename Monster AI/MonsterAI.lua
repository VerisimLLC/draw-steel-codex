local mod = dmhub.GetModLoading()

---@class MonsterAI: GameType
--- @field new fun(o?: table): MonsterAI
MonsterAI = RegisterGameType("MonsterAI")
MonsterAI.moves = {} --a table of registered moves the ai can choose from.
MonsterAI.prompts = {} --a table of prompted abilities the ai knows how to use.
MonsterAI.triggerHandlersByGuid = {}
MonsterAI.triggerHandlersByMonsterAbility = {}
MonsterAI.triggerHandlersByAbility = {}
MonsterAI.triggerHandlersByMonsterText = {}
MonsterAI.triggerHandlersByText = {}
MonsterAI.token = false
MonsterAI.squadMembers = {}
MonsterAI.chargeProbeCache = false --per-frame memo used by ChargeProbe.
MonsterAI.chargeProbeCacheTime = -1
MonsterAI.squadCaptain = false
--A minion squad moves as one: each member sets off this many seconds after the one before.
MonsterAI.squadMoveStagger = 0.2
--The squad's battle cry: the caller's line, then two or three members shout an answer.
MonsterAI.squadCallLines = {
    melee = {"Attack together!", "Strike as one!", "Get 'em, boys!"},
    ranged = {"Fire at will!", "Take them down!", "Shoot them down like dogs!"},
}
MonsterAI.squadAnswerLines = {"Raaah!", "Get 'em!", "Together!", "Hyaaah!", "Now!", "Yes, boss!"}
MonsterAI.abilities = {}
MonsterAI.tactics = {}
MonsterAI.maliceAbilities = {}
MonsterAI.villainActions = {}
MonsterAI.deferredTriggerLog = {}
MonsterAI.paths = false
MonsterAI.log = {}
MonsterAI.active = false
MonsterAI.reactionStatus = false
MonsterAI.reactionFailure = false

--"The AI is waiting on a player" notice ----------------------------------
--
--Only the host's AI knows it is waiting (a hero's turn-claim trigger, an
--opportunity attack after a move, a trigger prompt holding a cast open), so
--it publishes what it waits on to this shared document and EVERY client
--shows it on the tip banner through the notice channel (Tip.notices in
--GameHud.lua): "Waiting for Shadow's Hesitation Is Weakness". The wait
--sites call SetWaiting/ClearWaiting; both are idempotent against the
--document so a wait loop can call them every iteration without churning
--writes. AI start and stop clear it so a crashed host never leaves a stale
--notice behind.
local WAITING_DOC = "monsterAIWaiting"

--Seconds a notice must persist before clients show it, so a wait that
--resolves instantly (a prompt answered at once) never flashes the banner.
local NOTICE_GRACE_SECONDS = 1

--subject (optional) names the hero being waited on: {charid, triggerid}.
--triggerid is the key of the hero's prompt in availableTriggers, when the
--wait is on one. The banner uses it to offer that hero's player Select and
--Dismiss buttons.
---@param subject nil|{charid: string, triggerid: nil|string}
function MonsterAI.SetWaiting(key, text, subject)
    if type(text) ~= "string" or text == "" then
        MonsterAI.ClearWaiting()
        return
    end
    local charid = subject ~= nil and subject.charid or nil
    local triggerid = subject ~= nil and subject.triggerid or nil
    local doc = mod:GetDocumentSnapshot(WAITING_DOC)
    if doc.data.key == key and doc.data.text == text
        and doc.data.charid == charid and doc.data.triggerid == triggerid then
        return
    end
    doc:BeginChange()
    doc.data.key = key
    doc.data.text = text
    doc.data.charid = charid
    doc.data.triggerid = triggerid
    doc:CompleteChange("Monster AI waiting: " .. text, {undoable = false})
end

function MonsterAI.ClearWaiting()
    local doc = mod:GetDocumentSnapshot(WAITING_DOC)
    if doc.data.key == nil and doc.data.text == nil and doc.data.charid == nil then
        return
    end
    doc:BeginChange()
    doc.data.key = nil
    doc.data.text = nil
    doc.data.charid = nil
    doc.data.triggerid = nil
    doc:CompleteChange("Monster AI waiting cleared", {undoable = false})
end

--The Monster AI panel's diagnostic status reads "Waiting for Shadow's player
--to answer Opportunity Attack" / "... reaction to finish: Opportunity
--Attack" (creature:GetAIActivityReactionStatus). The banner wants the
--player-facing "Waiting for Shadow's Opportunity Attack".
local function NoticeTextFromReactionStatus(status)
    if type(status) ~= "string" then
        return nil
    end
    local text = status:gsub("player to answer ", "")
    text = text:gsub("client to evaluate ", "")
    text = text:gsub("reaction to finish: (.*)$", "%1 to finish")
    return text
end

--Name a hero's undismissed trigger prompt while a monster's cast is held
--open by it: "Waiting for Shadow's Opportunity Attack", plus the notice
--subject (see SetWaiting). nil when no hero holds a prompt.
local function FindPlayerTriggerPromptNotice()
    for _,token in ipairs(dmhub.allTokens) do
        if token.playerControlled and token.properties ~= nil
            and MonsterAI.TokenIsLiveCombatant(token) then
            for key,trigger in pairs(token.properties:GetAvailableTriggers(true) or {}) do
                if not trigger.dismissed and not trigger.triggered
                    and type(trigger.abilityName) == "string" then
                    return string.format("Waiting for %s's %s", token.name, trigger.abilityName),
                        {charid = token.charid, triggerid = key}
                end
            end
        end
    end
    return nil
end

--Client side: every client (players included) polls the document through
--the tip banner's notice channel. Registered by direct table insert so this
--file does not depend on GameHud.lua having loaded first; GameHud.lua
--preserves an existing Tip.notices table.
Tip = rawget(_G, "Tip") or {}
Tip.notices = Tip.notices or {}
local m_noticeText = nil
local m_noticeSince = 0

--The banner buttons (see the notice channel in GameHud.lua). Only the player
--who answers the waited-on hero's prompts gets any: "Select <hero>" while the
--hero is not selected, and Dismiss when the wait is on a prompt they can
--dismiss, which dismisses the prompt itself. Everyone else gets no buttons.
local function WaitingNoticeControls(doc)
    local controls = {}
    local charid = doc.data.charid
    if type(charid) ~= "string" then
        return controls
    end
    local token = dmhub.GetTokenById(charid)
    --activeControllerId is nil when this user is the one best suited to
    --answer the token's prompts; canControlAsUser rules out a player host
    --whose control comes only from hosting the game.
    if token == nil or not token.valid or token.properties == nil
        or not token.canControlAsUser or token.activeControllerId ~= nil then
        return controls
    end

    local selected = false
    for _,tok in ipairs(dmhub.selectedTokens or {}) do
        if tok.charid == charid then
            selected = true
            break
        end
    end
    if not selected then
        controls.action = {
            text = string.format("Select %s", token.name or "hero"),
            press = function()
                dmhub.SelectToken(charid)
            end,
        }
    end

    local triggerid = doc.data.triggerid
    local trigger = type(triggerid) == "string"
        and token.properties:try_get("availableTriggers", {})[triggerid] or nil
    if trigger ~= nil and not trigger.dismissed and not trigger.triggered and trigger:CanDismiss() then
        controls.dismiss = function()
            token:ModifyProperties{
                undoable = false,
                description = "Trigger",
                execute = function()
                    local live = token.properties:try_get("availableTriggers", {})[triggerid]
                    if live ~= nil and not live.dismissed and not live.triggered then
                        live.triggered = false
                        live.dismissed = true
                        token.properties:DispatchAvailableTrigger(live)
                    end
                end,
            }
        end
    end
    return controls
end

Tip.notices["monster-ai-waiting"] = {
    id = "monster-ai-waiting",
    priority = 1000,
    text = function()
        local q = dmhub.initiativeQueue
        if q == nil or q.hidden then
            m_noticeText = nil
            return nil
        end
        local doc = mod:GetDocumentSnapshot(WAITING_DOC)
        local text = doc.data.text
        if type(text) ~= "string" or text == "" then
            m_noticeText = nil
            return nil
        end
        if text ~= m_noticeText then
            m_noticeText = text
            m_noticeSince = dmhub.Time()
        end
        if dmhub.Time() - m_noticeSince < NOTICE_GRACE_SECONDS then
            return nil
        end
        return text, WaitingNoticeControls(doc)
    end,
}

--"Is the AI running / busy" flag ------------------------------------------
--
--The AI runs only on the machine hosting the game, so no other client can see
--it. The host publishes a small status to this shared document, on change only,
--so every client can ask MonsterAI.IsAIRunningAnywhere / IsAIBusyAnywhere.
--Turn Rewind uses it to refuse rewinding while the AI plays. Not registered for
--checkpoints: a rewind must never roll it back.
--  running: the AI process is running on the publisher's machine
--  busy:    it is playing a monster's turn or is in the middle of an action
--  userid:  who published it (a status from a user who has gone offline, or
--           from this user's own crashed session, is ignored)
local STATUS_DOC = "monsterAIStatus"

--Seconds since a publisher's last contact before its status is treated as stale.
--Same recipe as the online roster (OnlineUsers.lua).
local STATUS_ONLINE_SECONDS = 140

--- @return boolean
local function AIRunningHere()
    return MonsterAI.active == true and MonsterAI.IsAIRunning ~= nil and MonsterAI.IsAIRunning() == true
end

--True while the current turn belongs to a non-player entry, which the AI plays
--whenever it is running.
--- @param q InitiativeQueue|nil
--- @return boolean
local function MonsterTurnUnderway(q)
    return q ~= nil and not q.hidden and not q:ChoosingTurn() and q:IsEntryPlayer(q.currentTurn) == false
end

--- True while the AI running on THIS client is playing a monster's turn or is in
--- the middle of an action (e.g. a monster's triggered free strike on a hero's turn).
--- @return boolean
function MonsterAI.BusyHere()
    if not AIRunningHere() then
        return false
    end
    if creature.GetAIActivityInProgress() ~= nil then
        return true
    end
    return MonsterTurnUnderway(dmhub.initiativeQueue)
end

--The status another client published, or nil if none is live. This client's own
--state is read directly, never from the document.
--- @return table|nil
local function RemoteStatus()
    local data = mod:GetDocumentSnapshot(STATUS_DOC).data
    local userid = data.userid
    if data.running ~= true or type(userid) ~= "string" or userid == dmhub.userid then
        return nil
    end
    local info = dmhub.GetSessionInfo(userid)
    if info == nil or info.loggedOut or (info.timeSinceLastContact or 0) >= STATUS_ONLINE_SECONDS then
        return nil
    end
    return data
end

--- True if the Monster AI is running on any client in the game.
--- @return boolean
function MonsterAI.IsAIRunningAnywhere()
    return AIRunningHere() or RemoteStatus() ~= nil
end

--- True while the Monster AI, on any client, is playing a monster's turn or is in
--- the middle of an action.
--- @return boolean
function MonsterAI.IsAIBusyAnywhere()
    if MonsterAI.BusyHere() then
        return true
    end
    local status = RemoteStatus()
    if status == nil then
        return false
    end
    --A monster turn can start a moment before the host's busy flag arrives.
    return status.busy == true or MonsterTurnUnderway(dmhub.initiativeQueue)
end

--Host side: publish the status whenever it changes. Any client whose own status is
--still in the document after its AI stopped (or after a crash and reload) clears it.
local function PublishStatus()
    local doc = mod:GetDocumentSnapshot(STATUS_DOC)
    local data = doc.data
    local running = AIRunningHere()
    if running then
        local busy = MonsterAI.BusyHere()
        if data.running == true and data.userid == dmhub.userid and (data.busy == true) == busy then
            return
        end
        doc:BeginChange()
        doc.data.running = true
        doc.data.busy = busy
        doc.data.userid = dmhub.userid
        doc:CompleteChange(cond(busy, "Monster AI busy", "Monster AI running"), {undoable = false})
    elseif data.running == true and data.userid == dmhub.userid then
        doc:BeginChange()
        doc.data.running = false
        doc.data.busy = false
        doc:CompleteChange("Monster AI stopped", {undoable = false})
    end
end

dmhub.Coroutine(function()
    while not mod.unloaded do
        local ok, err = pcall(PublishStatus)
        if not ok then
            print("MonsterAI:: status publish failed:", err)
        end
        coroutine.yield(0.2)
    end
end)

--Plan preview ("show me what the monster will do, then wait") ---------------
--
--Before each unit of a monster's turn (one move cycle: "run in and Sword Stab",
--then "run off and Hide"; or a whole minion squad's strike) the host publishes
--the plan to this shared document and waits. Every client shows it from the
--document: a ghost of each monster where it will stand, movement arrows there,
--orange attack arrows from there to its targets, and a preview card in the
--ability sidebar (who acts, how far they move, whom they target, the ability's
--card, then Proceed / Play Entire Turn and the "Monsters Pause Before Acting"
--check). Any player may press the buttons.
--Not registered for checkpoints: a rewind must never bring a preview back.
--  seq:       unique per preview
--  userid:    the host publishing it
--  actorName: who acts ("Clawfish Squad 1", "Goblin Assassin")
--  actors:    charids of the acting monsters (their portraits)
--  attacking: true when the unit attacks ("Advance" rather than "Move")
--  ability:   {charid, name} the ability whose card to show, or nil
--  moves:     {charid, to = loc.str, via = nil|loc.str} movement arrows
--  attacks:   {charid, from = loc.str, target = charid, label, friendly}
--             attack arrows (green for an ally, orange for an enemy)
--  targets:   charids of everyone the action affects, for the card
--  malice:    {cost, pool} for a Malice ability: what it spends of the pool
--  area:      an area ability's {shape = "Cube", locs = loc.str[], caught =
--             charids, x, y (the square to centre the camera on)}, or nil
--  continued: the seq of the preview someone pressed Proceed on
--  playTurn:  the seq of the preview someone pressed Play Entire Turn on
local PREVIEW_DOC = "monsterAIPreview"

--"Monsters Pause Before Acting" unchecked (on the preview card or in Settings):
--no previews for anyone until someone checks it again.
--  by:  the userid who unchecked it
--  run: g_runId of that user's client when they did
--It lapses when that user leaves or restarts the app, so pauses come back on
--each session. (Games from before this held {queue = guid}; that is ignored.)
local PREVIEW_OFF_DOC = "monsterAIPreviewOff"

--Tells this run of the app apart from earlier ones (a Lua reload makes a new one too).
local g_runId = dmhub.GenerateGuid()

--When the AI previews its plans. Read on the host, where the AI runs.
local g_previewSetting = setting{
    id = "monsterai:previewplans",
    description = "Show the Monster AI's plans and wait for Proceed",
    storage = "preference",
    default = "eotw",
    enum = {
        {value = "eotw", text = "In Encounter of the Week"},
        {value = "always", text = "Always"},
        {value = "never", text = "Never"},
    },
}

--Type it on the host: the AI runs there, and the setting is that machine's preference.
Commands.RegisterMacro{
    name = "aipreview",
    summary = "show the Monster AI's plans before it acts",
    doc = "Usage: /aipreview eotw | always | never\nBefore each monster action the AI shows its movement, its targets and the ability, and waits for anyone to press Proceed. eotw (the default) does this only in Encounter of the Week games. Type it on the machine hosting the game.",
    command = function(str)
        local arg = string.lower(string.gsub(str or "", "^%s*(.-)%s*$", "%1"))
        if arg == "on" then
            arg = "always"
        elseif arg == "off" then
            arg = "never"
        end
        if arg == "eotw" or arg == "always" or arg == "never" then
            g_previewSetting:Set(arg)
        end
        print(string.format("Monster AI plan previews: %s (now %s here); usage /aipreview eotw|always|never",
            g_previewSetting:Get(), MonsterAI.PreviewPlansEnabled() and "on" or "off"))
    end,
}

--- True when the AI on this client should preview each plan and wait for Proceed.
--- @return boolean
function MonsterAI.PreviewPlansEnabled()
    local value = g_previewSetting:Get()
    if value == "always" then
        return true
    elseif value == "never" then
        return false
    end
    --EncounterOfTheWeek loads after this mod, so look it up when asked.
    local eotw = rawget(_G, "EncounterOfTheWeekGame")
    local isEotw = false
    if eotw ~= nil then
        pcall(function() isEotw = eotw.IsEotwGame() == true end)
    end
    return isEotw
end

--- True when someone unchecked "Monsters Pause Before Acting" and it still holds:
--- they are still in the game, in the same run of the app.
--- @return boolean
function MonsterAI.PausesOff()
    local data = mod:GetDocumentSnapshot(PREVIEW_OFF_DOC).data
    local userid = data.by
    if type(userid) ~= "string" then
        return false
    end
    if userid == dmhub.userid then
        return data.run == g_runId
    end
    local info = dmhub.GetSessionInfo(userid)
    return info ~= nil and not info.loggedOut and (info.timeSinceLastContact or 0) < STATUS_ONLINE_SECONDS
end

--- Turn the pauses off (or back on) for everyone. Off lasts until someone turns
--- them back on, or this user leaves or restarts.
--- @param off boolean
function MonsterAI.SetPausesOff(off)
    local doc = mod:GetDocumentSnapshot(PREVIEW_OFF_DOC)
    if off and MonsterAI.PausesOff() then
        return
    end
    if not off and doc.data.by == nil and doc.data.queue == nil then
        return
    end
    doc:BeginChange()
    doc.data.queue = nil
    if off then
        doc.data.by = dmhub.userid
        doc.data.run = g_runId
    else
        doc.data.by = nil
        doc.data.run = nil
    end
    doc:CompleteChange(off and "Monsters stop pausing before acting" or "Monsters pause before acting",
        {undoable = false})
end

--The same switch in Settings > General > Encounter of the Week, so it can be
--changed at any time, not only while a preview card is up. Transient: the
--shared document is the real value, and the loop below keeps the two in step.
local g_pauseSetting
g_pauseSetting = setting{
    id = "monsterai:pausebeforeacting",
    description = "Monsters Pause Before Acting",
    help = "Before each monster action, show what the monster will do and wait for someone to press Proceed. Turning it off turns it off for the whole table until someone turns it back on.",
    storage = "transient",
    section = "EncounterOfTheWeek",
    editor = "check",
    default = true,
    onchange = function()
        MonsterAI.SetPausesOff(g_pauseSetting:Get() ~= true)
    end,
}

dmhub.Coroutine(function()
    while not mod.unloaded do
        local ok, err = pcall(function()
            --our own "off" from before a restart: pauses come back this session.
            local data = mod:GetDocumentSnapshot(PREVIEW_OFF_DOC).data
            if data.by == dmhub.userid and data.run ~= g_runId then
                MonsterAI.SetPausesOff(false)
            end
            local on = not MonsterAI.PausesOff()
            if (g_pauseSetting:Get() == true) ~= on then
                g_pauseSetting:Set(on)
            end
        end)
        if not ok then
            print("MonsterAI:: pause setting sync failed:", err)
        end
        coroutine.yield(0.2)
    end
end)

--Play Entire Turn: the rest of the current initiative entry's turn plays with
--no pauses. Kept on the host, keyed by the turn, so the next turn pauses again.
local g_playTurnKey = nil

local function CurrentTurnKey()
    local q = dmhub.initiativeQueue
    if q == nil or q.hidden then
        return nil
    end
    return string.format("%s:%s:%s", tostring(q.guid), tostring(q.round), tostring(q:CurrentInitiativeId()))
end

--- True when the AI should stop and preview its next plan: it runs as the
--- background process on this client, previews are enabled, nobody turned the
--- pauses off, and this turn is not being played through.
--- Checked before a preview is built, because building one costs planning work.
--- @return boolean
function MonsterAI.PlanPreviewsOn()
    if not AIRunningHere() or not MonsterAI.PreviewPlansEnabled() or MonsterAI.PausesOff() then
        return false
    end
    return g_playTurnKey == nil or g_playTurnKey ~= CurrentTurnKey()
end

--- Host: play the rest of the current turn without pausing (Play Entire Turn).
function MonsterAI.PlayRestOfTurnWithoutPauses()
    g_playTurnKey = CurrentTurnKey()
end

--- Take down whatever preview this client published. Safe to call any time.
function MonsterAI.ClearPlanPreview()
    local doc = mod:GetDocumentSnapshot(PREVIEW_DOC)
    if doc.data.seq == nil then
        return
    end
    doc:BeginChange()
    for k in pairs(doc.data) do
        doc.data[k] = nil
    end
    doc:CompleteChange("Monster AI plan preview cleared", {undoable = false})
end

--True when the players cannot see the token, so previewing it would give it away.
local function HiddenFromPlayers(token)
    if token == nil or not token.valid or token.properties == nil then
        return true
    end
    if token.invisibleToPlayers then
        return true
    end
    local hidden = false
    pcall(function() hidden = token.properties:HasNamedCondition("Hidden") end)
    return hidden
end

local function PreviewName(token)
    local name = nil
    if token ~= nil and token.valid then
        name = token.name
        if (type(name) ~= "string" or name == "") and token.properties ~= nil then
            name = token.properties:try_get("monster_type")
        end
    end
    if type(name) ~= "string" or name == "" then
        return "A monster"
    end
    return name
end

--Plans hold their targets as a token, {token = t, charge = loc}, or a list of
--either. Returns a list of {token, charge}.
local function PreviewTargets(value)
    local result = {}
    local function Add(entry)
        if type(entry) == "userdata" then
            result[#result+1] = {token = entry}
        elseif type(entry) == "table" and type(entry.token) == "userdata" then
            result[#result+1] = {token = entry.token, charge = entry.charge}
        end
    end
    if type(value) == "table" and value.token == nil then
        for _,entry in ipairs(value) do
            Add(entry)
        end
    else
        Add(value)
    end
    return result
end

--Answer the preview on screen: Proceed, or Play Entire Turn (playTurn).
local function AnswerPlanPreview(seq, playTurn)
    local doc = mod:GetDocumentSnapshot(PREVIEW_DOC)
    if doc.data.seq ~= seq or doc.data.continued == seq then
        return
    end
    doc:BeginChange()
    doc.data.continued = seq
    if playTurn then
        doc.data.playTurn = seq
    end
    doc:CompleteChange(playTurn and "Play the monsters' turn" or "Proceed with the monster's action",
        {undoable = false})
end

--The preview that should be on screen now, or nil. A preview left behind by a
--host whose AI has stopped (or crashed) is ignored.
local function LivePlanPreview()
    local data = mod:GetDocumentSnapshot(PREVIEW_DOC).data
    if type(data.seq) ~= "string" or data.continued == data.seq then
        return nil
    end
    if not MonsterAI.IsAIRunningAnywhere() then
        return nil
    end
    return data
end

--The preview card -------------------------------------------------------------
--Sits where the ability card appears when the cast starts (the ability sidebar
--on the right), at that card's width and in the same card style, so the
--preview reads as the top of the ability card.
local PREVIEW_CARD_WIDTH = 346

local g_previewStyles = {
    {
        selectors = {"aiPreviewCard"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        bgcolor = "@bgAlt",
        border = 1,
        borderColor = "@border",
        cornerRadius = 6,
        vmargin = 4,
        hpad = 14,
        vpad = 10,
        borderBox = true,
    },
    {
        selectors = {"aiPreviewRow"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        vmargin = 4,
    },
    {
        selectors = {"label", "aiPreviewName"},
        fontFace = "Newzald",
        fontSize = 22,
        color = "@fgStrong",
        --not "100% available": a hover relayout measured the label's height at a
        --near-zero width (nine wrapped lines), the card grew under the cursor,
        --the button slid away and unhovered, and the card flickered.
        width = "auto",
        maxWidth = 180,
        height = "auto",
        valign = "center",
        lmargin = 8,
        minFontSize = 14,
    },
    {
        selectors = {"label", "aiPreviewKey"},
        fontSize = 12,
        color = "@fgMuted",
        width = 80,
        height = "auto",
        valign = "center",
        bold = true,
    },
    {
        selectors = {"label", "aiPreviewValue"},
        fontSize = 16,
        color = "@fg",
        width = "100%-80",
        height = "auto",
        valign = "center",
    },
}

--Small token portraits in a wrapping row, named in their tooltips.
local function PreviewPortraits(charids, size)
    local children = {}
    for _,charid in ipairs(charids) do
        local token = dmhub.GetTokenById(charid)
        if token ~= nil and token.valid then
            local name = token.canLocalPlayerSeeName and token.name or nil
            local options = {
                width = size,
                height = size,
                rmargin = 4,
                bmargin = 2,
                valign = "center",
            }
            --set at creation: this runs in the preview coroutine, where writing
            --image.events afterwards would go through LuaStringMap's metamethods.
            if type(name) == "string" and name ~= "" then
                options.hover = function(element)
                    gui.Tooltip(name)(element)
                end
            end
            children[#children+1] = gui.CreateTokenImage(token, options)
        end
    end
    return children
end

--"Advance 4/3/1/1 spaces" from each arrow's path length, in squares.
local function PreviewMovementText(data, steps)
    if #steps == 0 then
        return data.attacking and "None: strikes from where it stands" or "None"
    end
    local counts = {}
    local total = 0
    for _,n in ipairs(steps) do
        counts[#counts+1] = tostring(n)
        total = total + n
    end
    local verb = data.attacking and "Advance" or "Move"
    local unit = (#steps == 1 and total == 1) and "space" or "spaces"
    return string.format("%s %s %s", verb, table.concat(counts, "/"), unit)
end

--The ability's own card, as the sidebar shows it when the cast begins.
local function PreviewAbilityCard(abilityInfo)
    if type(abilityInfo) ~= "table" or type(abilityInfo.charid) ~= "string" then
        return nil
    end
    local token = dmhub.GetTokenById(abilityInfo.charid)
    if token == nil or not token.valid or token.properties == nil then
        return nil
    end
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.name == abilityInfo.name then
            local ok, card = pcall(CreateAbilityTooltip, ability:GetActiveVariation(token), {
                token = token,
                width = PREVIEW_CARD_WIDTH,
                maxHeight = math.max(200, dmhub.screenDimensionsBelowTitlebar.y - 420),
            })
            if ok and card ~= nil then
                card:MakeNonInteractiveRecursive()
                return card
            end
            return nil
        end
    end
    return nil
end

local function BuildPlanPreviewPanel(data, steps)
    local seq = data.seq

    --Targets, in order, once each: the full list when the host sent one (it
    --includes a caster acting on itself), else the attack arrows' targets.
    local targetIds = {}
    local seen = {}
    for _,charid in ipairs(type(data.targets) == "table" and data.targets or {}) do
        if type(charid) == "string" and not seen[charid] then
            seen[charid] = true
            targetIds[#targetIds+1] = charid
        end
    end
    for _,attack in ipairs(data.attacks or {}) do
        if type(attack.target) == "string" and not seen[attack.target] then
            seen[attack.target] = true
            targetIds[#targetIds+1] = attack.target
        end
    end

    local infoRows = {
        --who acts
        gui.Panel{
            classes = {"aiPreviewRow"},
            gui.Panel{
                width = "auto",
                height = "auto",
                maxWidth = 150,
                flow = "horizontal",
                wrap = true,
                valign = "center",
                children = PreviewPortraits(data.actors or {}, 32),
            },
            gui.Label{
                classes = {"aiPreviewName"},
                text = data.actorName or "Monster",
            },
        },
    }
    --a Malice ability that moves no one has no movement to describe.
    if #steps > 0 or type(data.malice) ~= "table" then
        infoRows[#infoRows+1] = gui.Panel{
            classes = {"aiPreviewRow"},
            gui.Label{classes = {"aiPreviewKey"}, text = "MOVEMENT"},
            gui.Label{classes = {"aiPreviewValue"}, text = PreviewMovementText(data, steps)},
        }
    end
    local malice = data.malice
    if type(malice) == "table" and type(malice.cost) == "number" then
        local text = string.format("Spends %d", malice.cost)
        if type(malice.pool) == "number" then
            text = string.format("Spends %d (%d left)", malice.cost, math.max(0, malice.pool - malice.cost))
        end
        infoRows[#infoRows+1] = gui.Panel{
            classes = {"aiPreviewRow"},
            gui.Label{classes = {"aiPreviewKey"}, text = "MALICE"},
            gui.Label{classes = {"aiPreviewValue"}, text = text},
        }
    end
    local area = data.area
    if type(area) == "table" and type(area.locs) == "table" then
        --"Cube target": click it to look at the area; then whoever it catches.
        local centerx, centery = area.x, area.y
        local children = {
            gui.Panel{
                classes = {"bordered", "hoverable"},
                bgimage = true,
                width = "auto",
                height = "auto",
                hpad = 8,
                vpad = 3,
                rmargin = 6,
                bmargin = 2,
                borderBox = true,
                valign = "center",
                click = function()
                    if type(centerx) == "number" and type(centery) == "number" then
                        dmhub.CenterOnLoc{x = centerx, y = centery, smooth = true}
                    end
                end,
                gui.Label{
                    classes = {"aiPreviewValue"},
                    width = "auto",
                    text = string.format("%s target", area.shape or "Area"),
                },
            },
        }
        for _,portrait in ipairs(PreviewPortraits(area.caught or {}, 40)) do
            children[#children+1] = portrait
        end
        infoRows[#infoRows+1] = gui.Panel{
            classes = {"aiPreviewRow"},
            gui.Label{classes = {"aiPreviewKey"}, text = "TARGETS"},
            gui.Panel{
                width = "100%-80",
                height = "auto",
                flow = "horizontal",
                wrap = true,
                valign = "center",
                children = children,
            },
        }
    elseif #targetIds > 0 then
        infoRows[#infoRows+1] = gui.Panel{
            classes = {"aiPreviewRow"},
            gui.Label{classes = {"aiPreviewKey"}, text = "TARGETS"},
            gui.Panel{
                width = "100%-80",
                height = "auto",
                flow = "horizontal",
                wrap = true,
                valign = "center",
                children = PreviewPortraits(targetIds, #targetIds > 8 and 28 or 40),
            },
        }
    end

    return gui.Panel{
        styles = ThemeEngine.MergeStyles(g_previewStyles),
        width = PREVIEW_CARD_WIDTH,
        height = "auto",
        flow = "vertical",
        halign = "center",
        valign = "center",

        gui.Panel{
            classes = {"aiPreviewCard"},
            bgimage = "panels/square.png",
            children = infoRows,
        },

        PreviewAbilityCard(data.ability),

        gui.Panel{
            classes = {"aiPreviewCard"},
            bgimage = "panels/square.png",
            gui.Check{
                text = "Monsters Pause Before Acting",
                value = true,
                width = "100%",
                change = function(element)
                    if not element.value then
                        --off for everyone until someone checks it again (here or in
                        --Settings); this action goes ahead too.
                        MonsterAI.SetPausesOff(true)
                        AnswerPlanPreview(seq, false)
                    end
                end,
            },
            gui.Panel{
                classes = {"aiPreviewRow"},
                tmargin = 8,
                gui.Button{
                    classes = {"sizeM"},
                    text = "Proceed",
                    halign = "left",
                    click = function()
                        AnswerPlanPreview(seq, false)
                    end,
                },
                gui.Button{
                    classes = {"sizeM"},
                    text = "Play Entire Turn",
                    halign = "right",
                    click = function()
                        AnswerPlanPreview(seq, true)
                    end,
                },
            },
        },
    }
end

--What this client shows for the current preview, so it can take it down.
local g_previewDrawn = {seq = nil, markers = {}, panel = nil}

local function ClearDrawnPlanPreview()
    for _,marker in ipairs(g_previewDrawn.markers) do
        pcall(function() marker:Destroy() end)
    end
    local panel = g_previewDrawn.panel
    if panel ~= nil and panel.valid then
        panel:DestroySelf()
    end
    g_previewDrawn = {seq = nil, markers = {}, panel = nil}
end

local function DrawPlanPreview(data)
    local steps = {}
    for _,move in ipairs(data.moves or {}) do
        local token = dmhub.GetTokenById(move.charid)
        if token ~= nil and token.valid and type(move.to) == "string" then
            local to = core.Loc(move.to)
            --separate: each monster gets an arrow of its own (a whole squad shows
            --at once) instead of the one shared arrow a drag uses.
            local options = {separate = true}
            if type(move.via) == "string" then
                options.waypoints = {core.Loc(move.via)}
            end
            pcall(function()
                local result = token:MarkMovementArrow(to, options)
                if result ~= nil then
                    if result.marker ~= nil then
                        g_previewDrawn.markers[#g_previewDrawn.markers+1] = result.marker
                    end
                    if result.path ~= nil and result.path.numSteps > 0 then
                        steps[#steps+1] = result.path.numSteps
                    end
                end
            end)
            --a ghost of the monster where it will stand when it acts.
            pcall(function()
                local ghost = token:CreateGhost(to)
                if ghost ~= nil then
                    g_previewDrawn.markers[#g_previewDrawn.markers+1] = ghost
                end
            end)
        end
    end
    for _,attack in ipairs(data.attacks or {}) do
        local attacker = dmhub.GetTokenById(attack.charid)
        local target = dmhub.GetTokenById(attack.target)
        if attacker ~= nil and attacker.valid and target ~= nil and target.valid then
            pcall(function()
                local fromLoc = type(attack.from) == "string" and core.Loc(attack.from) or nil
                --orange, so attacks read apart from the red movement arrows;
                --green for an ally (a buff or a heal).
                local marker = dmhub.MarkLineOfSight(attacker, target,
                    attacker.properties:GetPierceWalls(), attack.friendly and "green" or "orange", nil, fromLoc)
                if marker ~= nil then
                    if type(attack.label) == "string" and attack.label ~= "" then
                        marker:AddLabel(attack.label, attack.friendly and "buff" or "debuff")
                    end
                    g_previewDrawn.markers[#g_previewDrawn.markers+1] = marker
                end
            end)
        end
    end

    --an area ability's area, outlined in the attack arrows' orange.
    local area = data.area
    if type(area) == "table" and type(area.locs) == "table" and #area.locs > 0 then
        pcall(function()
            local locs = {}
            for _,str in ipairs(area.locs) do
                locs[#locs+1] = core.Loc(str)
            end
            local marker = dmhub.MarkLocs{locs = locs, color = "#ff9a1a", style = "solid"}
            if marker ~= nil then
                g_previewDrawn.markers[#g_previewDrawn.markers+1] = marker
            end
        end)
    end

    --the card, in the ability sidebar.
    local gh = rawget(GameHud, "instance")
    local host = gh ~= nil and rawget(gh, "abilityDisplayPanel") or nil
    if host ~= nil and host.valid then
        local ok, panel = pcall(BuildPlanPreviewPanel, data, steps)
        if ok and panel ~= nil then
            host:AddChild(panel)
            g_previewDrawn.panel = panel
        elseif not ok then
            print("MonsterAI:: plan preview card failed:", panel)
        end
    end
end

--A roll this client must make (a trigger's roll prompted mid-preview, say)
--mounts in the same ability sidebar as the preview card, so the two would
--overlap. rawget: CharacterPanel belongs to the codex, not this mod.
local function RollDialogShown()
    local characterPanel = rawget(_G, "CharacterPanel")
    if characterPanel == nil or characterPanel.AnyRollDialogShown == nil then
        return false
    end
    local ok, shown = pcall(characterPanel.AnyRollDialogShown)
    return ok and shown == true
end

--Every client, the host included, shows the preview from the document.
dmhub.Coroutine(function()
    while not mod.unloaded do
        local ok, err = pcall(function()
            local data = LivePlanPreview()
            local seq = data ~= nil and data.seq or nil
            if seq ~= g_previewDrawn.seq then
                ClearDrawnPlanPreview()
                if data ~= nil then
                    g_previewDrawn.seq = seq
                    DrawPlanPreview(data)
                end
            end
            --the card steps aside while the roll is up and comes back after it;
            --the arrows stay on the map.
            local panel = g_previewDrawn.panel
            if panel ~= nil and panel.valid then
                panel:SetClass("collapsed", RollDialogShown())
            end
        end)
        if not ok then
            print("MonsterAI:: plan preview draw failed:", err)
        end
        coroutine.yield(0.1)
    end
    ClearDrawnPlanPreview()
end)

MonsterAI.maliceAbilityMinimumScore = 0.65
MonsterAI.maliceAbilityRepeatPenalty = 0.20
MonsterAI.areaTelegraphBlinks = 3
MonsterAI.areaTelegraphOnTime = 0.35
MonsterAI.areaTelegraphOffTime = 0.15

MonsterAI.activeTactics = {}

local g_moveResultExecuted = "executed"
local g_moveResultFailed = "failed"
local g_moveResultUnsafe = "unsafe"
local g_moveResultNone = "none"

--------------------------------------------------------------------------------
-- Profiler (dev only): where does Monster AI thinking time go?
-- Turn it on with /aiprofile on (the dev:aiprofile preference). Each monster
-- turn then prints an "AIPERF::" report to Player.log covering the initiative
-- choice that picked it and the turn itself. It measures:
--  * sections: named blocks that never yield (ProfBegin/ProfEnd), kept as a
--    call tree plus a flat list ranked by self time (time not spent inside a
--    nested section).
--  * slices: each stretch the AI runs before it yields back to the engine.
--    Nothing else on the main thread runs during a slice, so the longest
--    slice is the hitch a player sees.
--  * phases: wall-clock spans that may yield (the turn, one actor, one move's
--    execution), with the AI compute spent inside each.
--  * frames: the real interval between frames while a phase is open.
-- os.clock is wall time on Windows at 1ms resolution: one short call reads
-- as 0 or 1ms, but totals over many calls average out correctly.
--------------------------------------------------------------------------------
local function ProfNow()
    return os.clock()*1000
end

local function NewProfNode(name)
    return {name = name, count = 0, total = 0, self = 0, max = 0, children = {}}
end

--Everything gathered since the last report.
---@class MonsterAIProfile
---@field enabled boolean
---@field startedAt number
---@field root table call tree: {name, count, total, self, max, children}
---@field flat table<string, table> section name -> {count, total, self, max}
---@field counters table<string, number>
---@field stack table[] open sections, innermost last
---@field sliceDepth number 1 while the outermost AI resume is running
---@field sliceStart number
---@field sliceTop table<string, number>|nil top-level section time in this slice
---@field computeTotal number
---@field slices table
---@field openPhases table[]
---@field timeline table[]
---@field frames table
---@field pendingReport string|nil

---@param enabled boolean
---@return MonsterAIProfile
local function NewProfile(enabled)
    return {
        enabled = enabled,
        startedAt = ProfNow(),
        root = NewProfNode("all"),
        flat = {},
        counters = {},
        stack = {},
        sliceDepth = 0,
        sliceStart = 0,
        sliceTop = nil,
        computeTotal = 0,
        slices = {count = 0, total = 0, max = 0, over16 = 0, over50 = 0, over100 = 0, over250 = 0, longest = {}},
        openPhases = {},
        timeline = {},
        frames = {count = 0, total = 0, max = 0, over50 = 0, over100 = 0, over250 = 0},
        pendingReport = nil,
    }
end

local g_prof = NewProfile(false)
---@type string|nil
local g_lastProfileReport = nil
local g_frameMonitorRunning = false

local function ResetProfile()
    g_prof = NewProfile(g_prof.enabled)
end

local g_profileSetting
g_profileSetting = setting{
    id = "dev:aiprofile",
    description = "Profile the Monster AI (AIPERF:: reports in Player.log)",
    default = false,
    storage = "preference",
    onchange = function()
        g_prof.enabled = g_profileSetting:Get() == true
    end,
}
pcall(function()
    g_prof.enabled = g_profileSetting:Get() == true
end)

--Open a named section. A section must not yield; close it with ProfEnd.
--Returns nil when profiling is off, and ProfEnd accepts that.
---@param name string
---@return table|nil
local function ProfBegin(name)
    local prof = g_prof
    if not prof.enabled then
        return nil
    end
    local stack = prof.stack
    local parent = stack[#stack]
    local parentNode = parent ~= nil and parent.node or prof.root
    local node = parentNode.children[name]
    if node == nil then
        node = NewProfNode(name)
        parentNode.children[name] = node
    end
    local frame = {name = name, node = node, start = ProfNow(), child = 0, open = true}
    stack[#stack+1] = frame
    return frame
end

local function ProfAccumulate(entry, elapsed, selfTime)
    entry.count = entry.count + 1
    entry.total = entry.total + elapsed
    entry.self = entry.self + selfTime
    if elapsed > entry.max then
        entry.max = elapsed
    end
end

--Close a section. Also closes sections an error left open inside it. Safe to
--call more than once, so every exit path of a function can call it.
---@param frame table|nil
local function ProfEnd(frame)
    if frame == nil or not frame.open then
        return
    end
    local prof = g_prof
    local stack = prof.stack
    local now = ProfNow()
    while #stack > 0 do
        local top = stack[#stack]
        stack[#stack] = nil
        top.open = false
        local elapsed = now - top.start
        ProfAccumulate(top.node, elapsed, elapsed - top.child)
        local flat = prof.flat[top.name]
        if flat == nil then
            flat = {count = 0, total = 0, self = 0, max = 0}
            prof.flat[top.name] = flat
        end
        ProfAccumulate(flat, elapsed, elapsed - top.child)
        local parent = stack[#stack]
        if parent ~= nil then
            parent.child = parent.child + elapsed
        elseif prof.sliceTop ~= nil then
            prof.sliceTop[top.name] = (prof.sliceTop[top.name] or 0) + elapsed
        end
        if top == frame then
            break
        end
    end
end

--Add n to a named counter (tiles searched, probes fired, cache hits...).
---@param name string
---@param n? number
local function ProfCount(name, n)
    local prof = g_prof
    if prof.enabled then
        prof.counters[name] = (prof.counters[name] or 0) + (n or 1)
    end
end

--AI compute so far, including the slice now running.
local function ProfComputeNow()
    local prof = g_prof
    local result = prof.computeTotal
    if prof.sliceDepth > 0 then
        result = result + (ProfNow() - prof.sliceStart)
    end
    return result
end

--Open a wall-clock phase. Unlike a section, a phase may yield.
---@param name string
---@return table|nil
local function ProfPhaseBegin(name)
    local prof = g_prof
    if not prof.enabled then
        return nil
    end
    local entry = {name = name, depth = #prof.openPhases, wall = nil, compute = 0, maxSlice = 0, slices = 0}
    prof.timeline[#prof.timeline+1] = entry
    local phase = {
        prof = prof,
        entry = entry,
        start = ProfNow(),
        computeStart = ProfComputeNow(),
        slicesStart = prof.slices.count,
        maxSlice = 0,
    }
    prof.openPhases[#prof.openPhases+1] = phase
    return phase
end

---@param phase table|nil
---@param detail? string
local function ProfPhaseEnd(phase, detail)
    if phase == nil or phase.prof ~= g_prof or phase.closed then
        return
    end
    local prof = g_prof
    --close phases an error left open inside this one first.
    while #prof.openPhases > 0 and prof.openPhases[#prof.openPhases] ~= phase do
        ProfPhaseEnd(prof.openPhases[#prof.openPhases], "left open")
    end
    phase.closed = true
    if prof.openPhases[#prof.openPhases] == phase then
        prof.openPhases[#prof.openPhases] = nil
    end
    local entry = phase.entry
    entry.wall = ProfNow() - phase.start
    entry.compute = ProfComputeNow() - phase.computeStart
    entry.slices = prof.slices.count - phase.slicesStart
    entry.maxSlice = phase.maxSlice
    if prof.sliceDepth > 0 then
        entry.maxSlice = math.max(entry.maxSlice, ProfNow() - prof.sliceStart)
    end
    entry.detail = detail
end

--Sample real frame intervals while a phase is open. One coroutine at most.
local function EnsureFrameMonitor()
    if g_frameMonitorRunning then
        return
    end
    g_frameMonitorRunning = true
    dmhub.Coroutine(function()
        local last = ProfNow()
        while not mod.unloaded and g_prof.enabled do
            coroutine.yield(0)
            local now = ProfNow()
            local dt = now - last
            last = now
            if #g_prof.openPhases > 0 then
                local frames = g_prof.frames
                frames.count = frames.count + 1
                frames.total = frames.total + dt
                frames.max = math.max(frames.max, dt)
                if dt > 50 then frames.over50 = frames.over50 + 1 end
                if dt > 100 then frames.over100 = frames.over100 + 1 end
                if dt > 250 then frames.over250 = frames.over250 + 1 end
            end
        end
        g_frameMonitorRunning = false
    end)
end

local function ProfReportNow(label)
    local prof = g_prof
    local lines = {}
    local function add(fmt, ...)
        lines[#lines+1] = "AIPERF:: " .. string.format(fmt, ...)
    end

    local slices = prof.slices
    local frames = prof.frames
    add("===== Monster AI profile: %s =====", tostring(label))
    add("AI compute %.0fms in %d slices over %.1fs wall; longest slice %.0fms; slices >16ms: %d, >50ms: %d, >100ms: %d, >250ms: %d",
        slices.total, slices.count, (ProfNow() - prof.startedAt)/1000, slices.max,
        slices.over16, slices.over50, slices.over100, slices.over250)
    if frames.count > 0 then
        add("frames %d, mean %.1fms, longest %.0fms; >50ms: %d, >100ms: %d, >250ms: %d",
            frames.count, frames.total/frames.count, frames.max, frames.over50, frames.over100, frames.over250)
    end

    add("--- longest slices (the hitches) ---")
    for _,slice in ipairs(slices.longest) do
        add("%7.0fms  during [%s]  top: %s", slice.ms, slice.phase, slice.top)
    end

    add("--- phases (wall includes animation and waits; compute is AI work) ---")
    for _,entry in ipairs(prof.timeline) do
        add("%s%-60s wall %7.0fms  compute %7.0fms  slices %4d  longest slice %6.0fms%s",
            string.rep("  ", entry.depth), entry.name, entry.wall or -1, entry.compute,
            entry.slices, entry.maxSlice, entry.detail ~= nil and ("  " .. entry.detail) or "")
    end

    add("--- sections by self time (ms) ---")
    local flatNames = {}
    for name,_ in pairs(prof.flat) do
        flatNames[#flatNames+1] = name
    end
    table.sort(flatNames, function(a, b) return prof.flat[a].self > prof.flat[b].self end)
    add("%9s %9s %8s %7s %8s  %s", "self", "total", "count", "max", "avg(us)", "section")
    for i=1,math.min(40, #flatNames) do
        local entry = prof.flat[flatNames[i]]
        add("%9.0f %9.0f %8d %7.0f %8.1f  %s", entry.self, entry.total, entry.count, entry.max,
            entry.count > 0 and entry.total*1000/entry.count or 0, flatNames[i])
    end

    local counterNames = {}
    for name,_ in pairs(prof.counters) do
        counterNames[#counterNames+1] = name
    end
    table.sort(counterNames)
    if #counterNames > 0 then
        add("--- counters ---")
        for _,name in ipairs(counterNames) do
            add("%10d  %s", prof.counters[name], name)
        end
    end

    --The call tree, pruned to nodes worth at least 0.5% of the measured time.
    local rootTotal = 0
    for _,child in pairs(prof.root.children) do
        rootTotal = rootTotal + child.total
    end
    local threshold = math.max(2, rootTotal*0.005)
    add("--- call tree (inclusive ms / self ms / calls), nodes >= %.0fms ---", threshold)
    local function walk(node, depth)
        local children = {}
        for _,child in pairs(node.children) do
            if child.total >= threshold then
                children[#children+1] = child
            end
        end
        table.sort(children, function(a, b) return a.total > b.total end)
        for _,child in ipairs(children) do
            add("%s%s  %.0f / %.0f / %d", string.rep("  ", depth), child.name, child.total, child.self, child.count)
            if depth < 12 then
                walk(child, depth + 1)
            end
        end
    end
    walk(prof.root, 0)

    g_lastProfileReport = table.concat(lines, "\n")
    for _,line in ipairs(lines) do
        print(line)
    end
    ResetProfile()
end

--Ask for a report. Inside a slice it waits for the slice to end, so the
--slice's own time is counted and nothing is reset under running code.
---@param label string
local function ProfRequestReport(label)
    local prof = g_prof
    if not prof.enabled then
        return
    end
    if prof.sliceDepth > 0 then
        prof.pendingReport = label
    else
        ProfReportNow(label)
    end
end

--Called around each coroutine.resume of the AI. Only the outermost resume
--counts: nested RunYieldingFunction calls resume within the same slice.
local function ProfSliceBegin()
    local prof = g_prof
    if prof.sliceDepth > 0 or not prof.enabled then
        return false
    end
    EnsureFrameMonitor()
    prof.sliceDepth = 1
    prof.sliceStart = ProfNow()
    prof.sliceTop = {}
    prof.stack = {}
    return true
end

local function ProfSliceEnd()
    local prof = g_prof
    if prof.sliceDepth == 0 then
        return
    end
    --close anything left open across a yield or by an error.
    if #prof.stack > 0 then
        ProfEnd(prof.stack[1])
    end
    local elapsed = ProfNow() - prof.sliceStart
    prof.sliceDepth = 0
    prof.computeTotal = prof.computeTotal + elapsed
    local slices = prof.slices
    slices.count = slices.count + 1
    slices.total = slices.total + elapsed
    slices.max = math.max(slices.max, elapsed)
    if elapsed > 16 then slices.over16 = slices.over16 + 1 end
    if elapsed > 50 then slices.over50 = slices.over50 + 1 end
    if elapsed > 100 then slices.over100 = slices.over100 + 1 end
    if elapsed > 250 then slices.over250 = slices.over250 + 1 end
    for _,phase in ipairs(prof.openPhases) do
        phase.maxSlice = math.max(phase.maxSlice, elapsed)
    end

    local longest = slices.longest
    if elapsed >= 5 and (#longest < 12 or elapsed > longest[#longest].ms) then
        local topNames = {}
        for name,_ in pairs(prof.sliceTop or {}) do
            topNames[#topNames+1] = name
        end
        table.sort(topNames, function(a, b) return prof.sliceTop[a] > prof.sliceTop[b] end)
        local parts = {}
        for i=1,math.min(4, #topNames) do
            parts[#parts+1] = string.format("%s %.0fms", topNames[i], prof.sliceTop[topNames[i]])
        end
        local phase = prof.openPhases[#prof.openPhases]
        longest[#longest+1] = {
            ms = elapsed,
            phase = phase ~= nil and phase.entry.name or "no phase",
            top = #parts > 0 and table.concat(parts, ", ") or "no sections",
        }
        table.sort(longest, function(a, b) return a.ms > b.ms end)
        while #longest > 12 do
            longest[#longest] = nil
        end
    end
    prof.sliceTop = nil

    if prof.pendingReport ~= nil then
        local label = prof.pendingReport
        prof.pendingReport = nil
        ProfReportNow(label)
    end
end

--Wrap a method so each call is a section. Only for methods that never yield.
local function ProfWrapMethod(tbl, key, name)
    local fn = tbl[key]
    if type(fn) ~= "function" then
        return
    end
    tbl[key] = function(...)
        if not g_prof.enabled then
            return fn(...)
        end
        local frame = ProfBegin(name)
        local results = table.pack(fn(...))
        ProfEnd(frame)
        return table.unpack(results, 1, results.n)
    end
end

--Exported for the panel thread and band files.
MonsterAI.ProfBegin = ProfBegin
MonsterAI.ProfEnd = ProfEnd
MonsterAI.ProfCount = ProfCount
MonsterAI.ProfPhaseBegin = ProfPhaseBegin
MonsterAI.ProfPhaseEnd = ProfPhaseEnd
MonsterAI.ProfRequestReport = ProfRequestReport

---@return string|nil
function MonsterAI.ProfLastReport()
    return g_lastProfileReport
end

---@return boolean
function MonsterAI.ProfEnabled()
    return g_prof.enabled
end

Commands.RegisterMacro{
    name = "aiprofile",
    summary = "profile the Monster AI",
    doc = "Usage: /aiprofile on | off | report | reset\nWhile on, each monster turn prints an AIPERF:: timing report to Player.log (the initiative choice plus the turn). report prints what has been gathered so far; reset discards it.",
    command = function(str)
        local arg = string.lower(string.gsub(str or "", "^%s*(.-)%s*$", "%1"))
        if arg == "on" or arg == "off" then
            g_profileSetting:Set(arg == "on")
            g_prof.enabled = arg == "on"
            print(string.format("AIPERF:: profiling %s", arg))
        elseif arg == "report" then
            ProfReportNow("manual report")
        elseif arg == "reset" then
            ResetProfile()
            print("AIPERF:: profile reset")
        else
            print(string.format("AIPERF:: profiling is %s; usage /aiprofile on|off|report|reset",
                g_prof.enabled and "on" or "off"))
        end
    end,
}

-- Shared across per-turn AI instances, but never saved or synchronized.
local g_maliceEncounterId = nil
local g_maliceAbilitiesUsed = {}

local function MaliceAbilityHistory(queue)
    local encounterId = queue ~= nil and not queue.hidden and queue.guid or nil
    if encounterId ~= g_maliceEncounterId then
        g_maliceEncounterId = encounterId
        g_maliceAbilitiesUsed = {}
    end
    return g_maliceAbilitiesUsed
end

local function MaliceAbilityHistoryKey(ability)
    return ability:try_get("guid") or ability.name
end

local g_aiLogFieldOrder = {
    "turn",
    "round",
    "cycle",
    "actor",
    "actorId",
    "monster",
    "category",
    "move",
    "ability",
    "action",
    "prompt",
    "trigger",
    "score",
    "threshold",
    "reason",
    "plan",
    "from",
    "to",
    "targets",
    "result",
    "duration",
}

local g_aiLogCategoryNames = {
    ["Main Actions"] = "Main Action",
    ["Basic Strikes"] = "Basic Strike",
    ["Maneuvers"] = "Maneuver",
    ["Malice Abilities"] = "Malice Ability",
    ["Villain Actions"] = "Villain Action",
    ["Tactics"] = "Tactic",
}

local function AILogText(value)
    local result = tostring(value or "")
    result = string.gsub(result, "[\r\n\t]+", " ")
    result = string.gsub(result, "|", "/")
    result = string.gsub(result, '"', '\\"')
    return result
end

local function AILogValue(value)
    if type(value) == "number" then
        if value == math.floor(value) then
            return tostring(value)
        end
        return string.format("%.3f", value)
    elseif type(value) == "boolean" then
        return tostring(value)
    end
    return string.format('"%s"', AILogText(value))
end

function MonsterAI.TokenLogName(token)
    if token == nil then
        return "none"
    end

    local result = nil
    pcall(function()
        result = creature.GetTokenDescription(token)
    end)
    if result == nil or result == "" then
        result = token.charid or "unknown token"
    end
    return AILogText(result)
end

function MonsterAI.LocLogName(loc)
    if loc == nil then
        return "none"
    end

    local result = nil
    pcall(function()
        result = string.format("(%d,%d,%d)", loc.x, loc.y, loc.altitude or 0)
    end)
    return result or "unknown location"
end

function MonsterAI.TargetsLogName(targets)
    local result = {}
    for _,targetInfo in ipairs(targets or {}) do
        local token = nil
        local loc = nil
        pcall(function()
            token = targetInfo.token
            loc = targetInfo.loc
        end)
        if token == nil then
            local charid = nil
            pcall(function() charid = targetInfo.charid end)
            if charid ~= nil then
                token = targetInfo
            end
        end

        if token ~= nil and token.charid ~= nil then
            result[#result+1] = string.format("%s [%s]",
                MonsterAI.TokenLogName(token), AILogText(token.charid))
        elseif loc ~= nil then
            result[#result+1] = MonsterAI.LocLogName(loc)
        end
    end
    if #result == 0 then
        return "none"
    end
    return table.concat(result, ", ")
end

function MonsterAI.TargetScoresLogName(targets)
    local result = {}
    for _,targetInfo in ipairs(targets or {}) do
        if targetInfo.token ~= nil then
            local detail = string.format("%s edges=%s",
                MonsterAI.TokenLogName(targetInfo.token), tostring(targetInfo.edges or 0))
            if targetInfo.edgeReasons ~= nil and #targetInfo.edgeReasons > 0 then
                detail = detail .. " [" .. table.concat(targetInfo.edgeReasons, ", ") .. "]"
            end
            result[#result+1] = detail
        end
    end
    if #result == 0 then
        return "none"
    end
    return table.concat(result, "; ")
end

function MonsterAI.AbilitiesLogName(abilities)
    local result = {}
    for _,ability in ipairs(abilities or {}) do
        local abilityName = nil
        if type(ability) == "string" then
            abilityName = ability
        else
            pcall(function() abilityName = ability.name end)
        end
        result[#result+1] = AILogText(abilityName or ability)
    end
    if #result == 0 then
        return "none"
    end
    return table.concat(result, ", ")
end

function MonsterAI.AbilityActionLogName(ability)
    if ability == nil then
        return "Unknown Action"
    end
    if ability:try_get("villainAction") ~= nil or ability.categorization == "Villain Action" then
        return "Villain Action"
    end

    local resourceid = ability:ActionResource()
    if resourceid == CharacterResource.actionResourceId then
        return "Main Action"
    elseif resourceid == CharacterResource.maneuverResourceId then
        return "Maneuver"
    elseif resourceid == CharacterResource.freeManeuverResourceId then
        return "Free Maneuver"
    elseif resourceid == CharacterResource.triggerResourceId then
        return "Triggered Action"
    elseif resourceid == CharacterResource.villainActionId then
        return "Villain Action"
    elseif ability.categorization == "Malice" then
        return "Malice Ability"
    elseif ability.categorization == "Move" then
        return "Move"
    elseif resourceid == nil then
        return "Free Action"
    end

    local resources = dmhub.GetTable(CharacterResource.tableName) or {}
    local resourceInfo = resources[resourceid]
    if resourceInfo ~= nil and resourceInfo.name ~= nil then
        return resourceInfo.name
    end
    return string.format("Other Action (%s)", tostring(resourceid))
end

function MonsterAI.AbilityActionsLogName(abilities)
    local result = {}
    local seen = {}
    for _,ability in ipairs(abilities or {}) do
        local name = MonsterAI.AbilityActionLogName(ability)
        if not seen[name] then
            seen[name] = true
            result[#result+1] = name
        end
    end
    if #result == 0 then
        return "No Ability Action"
    end
    return table.concat(result, ", ")
end

function MonsterAI.MoveCategoryLogName(move)
    if move == nil then
        return "Unknown Move"
    end
    return g_aiLogCategoryNames[move.category] or move.category or "Main Action"
end

function MonsterAI.ScoringPlanLogName(scoringInfo)
    if type(scoringInfo) ~= "table" then
        return "none"
    end

    local result = {}
    if scoringInfo.loc ~= nil then
        result[#result+1] = "move-to " .. MonsterAI.LocLogName(scoringInfo.loc)
    end
    if scoringInfo.targetLoc ~= nil then
        result[#result+1] = "aim-at " .. MonsterAI.LocLogName(scoringInfo.targetLoc)
    elseif scoringInfo.center ~= nil then
        result[#result+1] = "center-on " .. MonsterAI.LocLogName(scoringInfo.center)
    end
    if scoringInfo.targets ~= nil then
        result[#result+1] = "targets " .. MonsterAI.TargetsLogName(scoringInfo.targets)
    end
    if scoringInfo.enemies ~= nil or scoringInfo.allies ~= nil then
        result[#result+1] = string.format("enemies=%s allies=%s",
            tostring(scoringInfo.enemies or 0), tostring(scoringInfo.allies or 0))
    end
    if scoringInfo.mode ~= nil then
        result[#result+1] = "mode=" .. tostring(scoringInfo.mode)
    end
    if scoringInfo.reason ~= nil then
        result[#result+1] = AILogText(scoringInfo.reason)
    end
    if #result == 0 then
        return "no additional plan details"
    end
    return table.concat(result, "; ")
end

function MonsterAI:LogDecision(event, fields)
    if self:try_get("_tmp_suppressDecisionLogs", false) then
        return
    end

    fields = fields or {}
    local values = {}
    local context = self:try_get("_tmp_aiLogContext") or {}
    for key,value in pairs(context) do
        values[key] = value
    end
    for key,value in pairs(fields) do
        values[key] = value
    end

    local parts = {"AI:: " .. event}
    local written = {}
    for _,key in ipairs(g_aiLogFieldOrder) do
        if values[key] ~= nil then
            parts[#parts+1] = string.format("%s=%s", key, AILogValue(values[key]))
            written[key] = true
        end
    end

    local remaining = {}
    for key,_ in pairs(values) do
        if not written[key] then
            remaining[#remaining+1] = key
        end
    end
    table.sort(remaining)
    for _,key in ipairs(remaining) do
        parts[#parts+1] = string.format("%s=%s", key, AILogValue(values[key]))
    end

    print(table.concat(parts, " | "))
end

function MonsterAI:SetLogContext(token, fields)
    local context = {}
    for key,value in pairs(fields or {}) do
        context[key] = value
    end
    if token ~= nil then
        context.actor = self.TokenLogName(token)
        context.actorId = token.charid
        if token.properties ~= nil then
            context.monster = token.properties:try_get("monster_type", "")
        end
    end
    self._tmp_aiLogContext = context
end

function MonsterAI:SetMoveLogContext(token, move)
    local context = {}
    for key,value in pairs(self:try_get("_tmp_aiLogContext") or {}) do
        context[key] = value
    end
    context.category = self.MoveCategoryLogName(move)
    context.move = move ~= nil and move.id or nil
    self:SetLogContext(token, context)
end

local function AIAbilityUnavailableReason(token, ability)
    local cost = ability:GetCost(token)
    local unavailable = {}
    local resources = dmhub.GetTable(CharacterResource.tableName) or {}
    for _,detail in ipairs(cost.details or {}) do
        if detail.canAfford == false then
            local resourceInfo = resources[detail.cost]
            local resourceName = resourceInfo ~= nil and resourceInfo.name or detail.cost or "resource"
            unavailable[#unavailable+1] = string.format("%s x%s",
                tostring(resourceName), tostring(detail.quantity or 1))
        end
    end
    if #unavailable > 0 then
        return "cannot afford " .. table.concat(unavailable, ", ")
    end
    return "ability:CanAfford returned false"
end

creature._tmp_ai_aidAttack = false

Commands.RegisterMacro{
    name = "playai",
    summary = "play AI turn",
    doc = "Usage: /playai\nPlays an AI turn for the current initiative entry. Requires an active initiative queue.",
    command = function(str)

        local ai = MonsterAI.new{}
        local queue = dmhub.initiativeQueue
        if queue == nil or queue.hidden then
            ai:LogDecision("TURN ABORTED", {reason = "no initiative queue is active"})
            return
        end

        local initiativeid = dmhub.initiativeQueue:CurrentInitiativeId()
        if not initiativeid then
            ai:LogDecision("TURN ABORTED", {reason = "initiative queue has no current entry"})
            return
        end

        ai:PlayTurn(initiativeid)
    end,
}

function MonsterAI.Sleep(seconds)
    if seconds <= 0 then
        return
    end
    local endTime = dmhub.Time() + seconds
    while dmhub.Time() < endTime do
        coroutine.yield(0.1)
    end
end

--Shared initiatives can contain monsters on opposite sides of the map. Focus
--a new actor unless its whole token is already inside the usable map view.
function MonsterAI:FocusCameraOnActor(token)
    if not self.TokenIsLiveCombatant(token)
        or self:try_get("_tmp_focusedActorId") == token.charid then
        return false
    end

    self._tmp_focusedActorId = token.charid
    local bounds = dmhub.cameraUsableBounds
    local pos = token.pos
    local halfSize = (token.tileSize or 1)*0.5
    if token.hasTokenOnThisMap and bounds ~= nil and pos ~= nil
        and pos.x - halfSize >= bounds.x1 and pos.x + halfSize <= bounds.x2
        and pos.y - halfSize >= bounds.y1 and pos.y + halfSize <= bounds.y2 then
        return false
    end

    if not dmhub.CenterOnToken(token.charid, {smooth = true}) then
        self._tmp_focusedActorId = nil
        return false
    end

    dmhub.SyncCamera{
        speed = 1,
    }
    self.Sleep(1)
    return true
end

-- A mounted rider plans and performs ordinary AI movement with the creature
-- carrying it. The rider remains the caster for every ability and target test.
function MonsterAI:GetMovementToken(token)
    if token == nil or not token.valid then
        return token
    end

    local movementToken = token.selfOrMount
    if movementToken ~= nil and movementToken.valid then
        return movementToken
    end

    return token
end

-- The game permits sufficiently different creature sizes to share a space.
-- AI movement may pass through creatures, but should not deliberately end there.
function MonsterAI:MovementLocOverlapsCreature(token, loc)
    local movementToken = self:GetMovementToken(token)
    if movementToken == nil or not movementToken.valid or loc == nil then
        return false
    end

    if movementToken.loc.str == loc.str then
        return false
    end

    local ourBottom = loc.altitude
    local ourTop = ourBottom + movementToken.tileSize - 1
    for _,occupiedLoc in ipairs(movementToken:LocsOccupyingWhenAt(loc)) do
        for _,other in ipairs(dmhub.GetTokensAtLoc(occupiedLoc) or {}) do
            if other.valid and not other.isObject and other.properties ~= nil
                and not other.properties:IsDead() then
                local otherMovementToken = self:GetMovementToken(other)
                local movesWithUs = otherMovementToken ~= nil
                    and otherMovementToken.valid
                    and otherMovementToken.charid == movementToken.charid
                local verticallyOverlaps = other.altitude <= ourTop
                    and other.altitude + other.tileSize - 1 >= ourBottom
                if not movesWithUs and verticallyOverlaps then
                    return true, other
                end
            end
        end
    end

    return false
end

--Monster AI zone directives (an Environmental Keyword's "Monster AI
--Directives"): which squares lie in a zone whose type has a given directive.
--Results are memoised per frame: the AI plans within a frame (see PlanningMemo).
local g_zoneDirectiveNames = {"avoid", "forceInto", "hold"}
local g_zoneDirectives = {time = -1}

local function ZoneDirectivesFrame()
    local now = dmhub.Time()
    if g_zoneDirectives.time ~= now then
        --filters: directive -> keyword id -> its entries' creature filters ("" = everyone).
        --accepts: directive -> charid -> set of keyword ids whose filters accept that creature.
        --holdSquares: Hold keyword id -> every square of its zones on the map.
        local frame = {time = now, any = {}, keywordIds = {}, squares = {}, movers = {},
            filters = {}, accepts = {}, holdSquares = {}}
        for _,name in ipairs(g_zoneDirectiveNames) do
            frame.keywordIds[name] = {}
            frame.filters[name] = {}
            frame.accepts[name] = {}
            --square key -> aura instances of this directive's zones there.
            frame.squares[name] = {}
        end
        for id,keyword in unhidden_pairs(dmhub.GetTable(EnvironmentalKeyword.tableName) or {}) do
            for _,entry in ipairs(keyword:GetAIDirectives()) do
                local name = entry.directive
                if frame.keywordIds[name] ~= nil then
                    frame.keywordIds[name][id] = true
                    frame.any[name] = true
                    local filters = frame.filters[name][id] or {}
                    filters[#filters+1] = trim(entry.filter or "")
                    frame.filters[name][id] = filters
                end
            end
        end
        g_zoneDirectives = frame
    end
    return g_zoneDirectives
end

local function DirectiveFootprint(token, loc)
    local dims = token.creatureDimensions
    if dims.x <= 1 and dims.y <= 1 then
        return {loc}
    end
    return token:LocsOccupyingWhenAt(loc)
end

local function DirectiveInstancesAt(frame, directive, loc)
    local cache = frame.squares[directive]
    local key = loc.xyfloorOnly.str
    local result = cache[key]
    if result == nil then
        result = {}
        local keywordIds = frame.keywordIds[directive]
        for _,instance in ipairs(EnvironmentalKeyword.AuraInstancesCoveringSquare(loc)) do
            local auraDef = instance:try_get("aura")
            local keywordid = auraDef ~= nil and auraDef:try_get("environmentalKeywordId") or nil
            if keywordid ~= nil and keywordIds[keywordid] then
                result[#result+1] = instance
            end
        end
        cache[key] = result
    end
    return result
end

local function InstanceKeywordId(instance)
    local auraDef = instance:try_get("aura")
    return auraDef ~= nil and auraDef:try_get("environmentalKeywordId") or nil
end

local function DirectiveFilterAccepts(filter, token)
    if filter == "" then
        return true
    end
    if token.properties == nil then
        return false
    end
    local ok, value = pcall(ExecuteGoblinScript, filter,
        token.properties:LookupSymbol{}, 0, "Monster AI directive filter")
    return ok and GoblinScriptTrue(value)
end

--The keyword ids whose entries for this directive apply to the creature. For
--Avoid, a mount also takes its riders' entries, since they steer it.
local function DirectiveKeywordsFor(frame, directive, token)
    local byChar = frame.accepts[directive]
    local result = byChar[token.charid]
    if result == nil then
        result = {}
        local subjects = {token}
        if directive == "avoid" then
            for _,rider in ipairs(token.riders or {}) do
                if rider.valid then
                    subjects[#subjects+1] = rider
                end
            end
        end
        for keywordid,filters in pairs(frame.filters[directive]) do
            for _,filter in ipairs(filters) do
                local accepted = false
                for _,subject in ipairs(subjects) do
                    if DirectiveFilterAccepts(filter, subject) then
                        accepted = true
                        break
                    end
                end
                if accepted then
                    result[keywordid] = true
                    break
                end
            end
        end
        byChar[token.charid] = result
    end
    return result
end

--- True when any zone type has this directive ("avoid", "forceInto", "hold"),
--- or, given subject, has one whose filter accepts that creature.
--- @param directive string
--- @param subject? CharacterToken
--- @return boolean
function MonsterAI.AnyDirectiveZones(directive, subject)
    local frame = ZoneDirectivesFrame()
    if frame.any[directive] ~= true then
        return false
    end
    return subject == nil or next(DirectiveKeywordsFor(frame, directive, subject)) ~= nil
end

--- True when the token, standing at loc (default: where it is), would be in
--- a zone whose type has the named Monster AI directive for subject.
--- @param directive string "avoid", "forceInto" or "hold"
--- @param token CharacterToken whose footprint is placed at loc
--- @param loc? Loc
--- @param subject? CharacterToken the AI creature whose directive filters are checked (default token)
--- @return boolean
function MonsterAI.InDirectiveZone(directive, token, loc, subject)
    local frame = ZoneDirectivesFrame()
    if not frame.any[directive] then
        return false
    end
    local keywords = DirectiveKeywordsFor(frame, directive, subject or token)
    if next(keywords) == nil then
        return false
    end
    for _,square in ipairs(DirectiveFootprint(token, loc or token.loc)) do
        for _,instance in ipairs(DirectiveInstancesAt(frame, directive, square)) do
            if keywords[InstanceKeywordId(instance)] then
                return true
            end
        end
    end
    return false
end

--"Avoid": a creature the AI drives treats every square of an Avoid zone as
--impassable, except the zones it already stands in, so it can still walk out
--of one. The block rides the engine's MoveToLocPermitted hook, which every
--non-forced path search consults (CalculatePathfindingArea, Move, charge
--routes, jumps), so forced movement can still put the creature there.

--A mount counts as AI-driven when the AI drives it or its rider.
local function AvoidDrivenByAI(token)
    if creature.IsTokenAIControlled(token.charid) then
        return true
    end
    for _,rider in ipairs(token.riders or {}) do
        if rider.valid and creature.IsTokenAIControlled(rider.charid) then
            return true
        end
    end
    return false
end

--Whether the AI drives this creature, the Avoid zone types whose filters
--accept it, and the zones of those it stands in now (re-read when its loc
--changes, as ExecuteWithTheoreticalMovementLoc does).
local function AvoidMoverState(frame, c)
    local state = frame.movers[c]
    if state == nil then
        local token = dmhub.LookupToken(c)
        state = {token = token, active = false, keywords = {}}
        if token ~= nil and token.valid and AvoidDrivenByAI(token) then
            state.keywords = DirectiveKeywordsFor(frame, "avoid", token)
            state.active = next(state.keywords) ~= nil
        end
        frame.movers[c] = state
    end
    if state.active then
        --active is only set when the token was found.
        local token = state.token --[[@as CharacterToken]]
        local locStr = token.loc.str
        if state.locStr ~= locStr then
            state.locStr = locStr
            state.standingIn = {}
            for _,square in ipairs(DirectiveFootprint(token, token.loc)) do
                for _,instance in ipairs(DirectiveInstancesAt(frame, "avoid", square)) do
                    state.standingIn[instance] = true
                end
            end
        end
    end
    return state
end

--"Hold": a zone type's Hold directive makes its zones a post for the creatures
--that entry's filter accepts (an empty filter accepts every creature the AI
--drives). A creature that can reach its post this turn only plans to end its
--movement there; one that cannot heads back before advancing on anyone.

--The Hold keyword ids whose filter accepts this creature.
local function HoldKeywordsFor(frame, token)
    return DirectiveKeywordsFor(frame, "hold", token)
end

--Every square of the map's zones of one Hold zone type, read from the zone records.
local function HoldZoneSquares(frame, keywordid)
    local result = frame.holdSquares[keywordid]
    if result == nil then
        result = {}
        local map = game.currentMap
        for _,floor in ipairs(map ~= nil and map.floors or {}) do
            local zones, floorIndex = nil, nil
            pcall(function()
                zones = floor.markupZones
                floorIndex = floor.floorIndex
            end)
            if zones ~= nil and floorIndex ~= nil and floorIndex >= 0 then
                for _,record in pairs(zones) do
                    --zone records have no category; surfaces and holes do.
                    if type(record) == "table" and record.category == nil and record.keyword == keywordid then
                        for _,l in ipairs(record.locs or {}) do
                            result[#result+1] = core.Loc{x = math.floor(l.x), y = math.floor(l.y), floorIndex = floorIndex}
                        end
                    end
                end
            end
        end
        frame.holdSquares[keywordid] = result
    end
    return result
end

--- Every square of the zones holding this creature: empty when no Hold zone
--- type accepts it or the map has no zone of one.
--- @param token CharacterToken
--- @return Loc[]
function MonsterAI.HoldSquares(token)
    local frame = ZoneDirectivesFrame()
    local result = {}
    if not frame.any.hold then
        return result
    end
    for keywordid,_ in pairs(HoldKeywordsFor(frame, token)) do
        for _,loc in ipairs(HoldZoneSquares(frame, keywordid)) do
            result[#result+1] = loc
        end
    end
    return result
end

--- True when a Hold zone on this map holds the creature.
--- @param token CharacterToken
--- @return boolean
function MonsterAI.Holds(token)
    local frame = ZoneDirectivesFrame()
    if not frame.any.hold then
        return false
    end
    for keywordid,_ in pairs(HoldKeywordsFor(frame, token)) do
        if #HoldZoneSquares(frame, keywordid) > 0 then
            return true
        end
    end
    return false
end

--- True when the creature, standing at loc (default: where it is), would be on
--- its post: in a zone of a Hold zone type that holds it.
--- @param token CharacterToken whose Hold filter is checked
--- @param loc? Loc
--- @param footprintToken? CharacterToken whose footprint is placed at loc (its mount; default token)
--- @return boolean
function MonsterAI.InHoldZone(token, loc, footprintToken)
    local frame = ZoneDirectivesFrame()
    if not frame.any.hold then
        return false
    end
    local keywords = HoldKeywordsFor(frame, token)
    if next(keywords) == nil then
        return false
    end
    footprintToken = footprintToken or token
    for _,square in ipairs(DirectiveFootprint(footprintToken, loc or footprintToken.loc)) do
        for _,instance in ipairs(DirectiveInstancesAt(frame, "hold", square)) do
            if keywords[InstanceKeywordId(instance)] then
                return true
            end
        end
    end
    return false
end

--- For movement planned outside the path search (jumps, shifts, teleports):
--- false when loc would take a creature off the post it stands on. A creature
--- already off its post may go anywhere.
--- @param token CharacterToken
--- @param loc Loc
--- @return boolean
function MonsterAI.HoldPermits(token, loc)
    if not MonsterAI.InHoldZone(token) then
        return true
    end
    return MonsterAI.InHoldZone(token, loc)
end

local g_baseMoveToLocPermitted = creature.MoveToLocPermitted
function creature:MoveToLocPermitted(loc)
    if not g_baseMoveToLocPermitted(self, loc) then
        return false
    end
    local frame = ZoneDirectivesFrame()
    if not frame.any.avoid then
        return true
    end
    local state = AvoidMoverState(frame, self)
    if not state.active then
        return true
    end
    for _,square in ipairs(DirectiveFootprint(state.token, loc)) do
        for _,instance in ipairs(DirectiveInstancesAt(frame, "avoid", square)) do
            if not state.standingIn[instance] and state.keywords[InstanceKeywordId(instance)] then
                return false
            end
        end
    end
    return true
end

function MonsterAI:CalculateMovementPaths(token, movementAllowanceDecis, flags)
    local movementToken = self:GetMovementToken(token)
    local prof = ProfBegin("engine: CalculatePathfindingArea")
    local paths = movementToken:CalculatePathfindingArea(movementAllowanceDecis, flags or {})
    ProfEnd(prof)
    prof = ProfBegin("path overlap filter")
    local rejectedKeys = {}
    local numPaths = 0
    for key,pathInfo in pairs(paths) do
        numPaths = numPaths + 1
        if self:MovementLocOverlapsCreature(token, pathInfo.loc) then
            rejectedKeys[#rejectedKeys+1] = key
        end
    end
    for _,key in ipairs(rejectedKeys) do
        paths[key] = nil
    end
    ProfEnd(prof)

    --Never plan to end inside an Avoid zone. The path search already keeps
    --the AI out of them, but one it stands in stays walkable so it can get
    --out; drop those squares unless nowhere outside is reachable.
    local insideKeys = {}
    local anyOutside = false
    for key,pathInfo in pairs(paths) do
        if MonsterAI.InDirectiveZone("avoid", movementToken, pathInfo.loc) then
            insideKeys[#insideKeys+1] = key
        else
            anyOutside = true
        end
    end
    if anyOutside then
        for _,key in ipairs(insideKeys) do
            paths[key] = nil
        end
        numPaths = numPaths - #insideKeys
    end

    --Hold: a creature that stands on its post, or can reach it, only plans to
    --end its movement there.
    if MonsterAI.Holds(token) then
        local offPostKeys = {}
        local onPost = MonsterAI.InHoldZone(token, nil, movementToken)
        for key,pathInfo in pairs(paths) do
            if MonsterAI.InHoldZone(token, pathInfo.loc, movementToken) then
                onPost = true
            else
                offPostKeys[#offPostKeys+1] = key
            end
        end
        if onPost then
            for _,key in ipairs(offPostKeys) do
                paths[key] = nil
            end
            numPaths = numPaths - #offPostKeys
            self:PlanningMemo().holdActive[token.charid] = true
        end
    end

    ProfCount("pathfinding areas", 1)
    ProfCount("pathfinding area tiles", numPaths - #rejectedKeys)
    return paths
end

function MonsterAI:CalculateRemainingMovementPaths(token, flags)
    local movementToken = self:GetMovementToken(token)
    local remainingMovement = math.max(0,
        movementToken.properties:CurrentMovementSpeed()
        - movementToken.properties:DistanceMovedThisTurn())
    return self:CalculateMovementPaths(token, remainingMovement*10, flags)
end

--The 4th return is the notice subject (see SetWaiting) for the hero the
--status names.
function MonsterAI:CountPendingActivityReactions(activityId)
    local result = 0
    local status, failure, subject
    for _,token in ipairs(dmhub.allTokens) do
        if token.valid and token.playerControlled and token.properties ~= nil then
            local ok, pending, description, err, reactionId = pcall(token.properties.GetAIActivityReactionStatus, token.properties, activityId)
            if not ok then err = "could not inspect reaction state: " .. tostring(pending); pending = 1; reactionId = nil end
            result = result + pending
            if pending > 0 then
                status = "Waiting for " .. token.name .. "'s " .. (description or "reaction")
                subject = {charid = token.charid, triggerid = reactionId}
            end
            if err ~= nil then failure = token.name .. ": " .. tostring(err) end
        end
    end
    return result, status, failure, subject
end

--Count squad deaths that still need a player confirmation. This mirrors the
--red-skull eligibility in DrawSteelTokenHud, except that an available trigger
--does not hide the debt here: after the skull is clicked, death triggers and
--the Monster Death removal must finish before movement can continue.
function MonsterAI:CountPendingMinionDeathConfirmations()
    local countedSquads = {}
    local result = 0
    for _,token in ipairs(dmhub.GetTokens{haveProperties = true}) do
        local props = token.properties
        if token.valid and props ~= nil and props.minion and not props.minionDead
            and props:has_key("_tmp_minionSquad") then
            local squad = props._tmp_minionSquad
            local healthSingle = squad.health_single or 0
            local damageTaken = squad.damage_taken or 0
            local gated = (props:CalculateNamedCustomAttribute("Gated Minion Deaths") or 0) > 0
            if not countedSquads[squad] and not gated and healthSingle > 0
                and damageTaken >= healthSingle then
                local deathOverflows = damageTaken
                    >= ((squad.num_recently_damaged or 0) + 1) * healthSingle
                local isDirectTarget = props.minionDamageTime == squad.damage_time

                --While damage timestamps are still arriving, the HUD withholds
                --the skull. Treat that as pending too so a cross-client update
                --cannot briefly look settled and release the movement barrier.
                if squad.damage_time_pending or isDirectTarget or deathOverflows then
                    countedSquads[squad] = true
                    local deathsOwed = math.floor(damageTaken / healthSingle)
                    local liveMinions = math.max(1, squad.liveMinions or deathsOwed)
                    result = result + math.min(liveMinions, deathsOwed)
                end
            end
        end
    end
    return result
end

function MonsterAI:WaitForMovementActivity(movementToken, activityId)
    while movementToken.valid and movementToken.isMoving do
        coroutine.yield(0.05)
    end
    return self:WaitForActivityReactions(activityId)
end

--Hold the AI until every player prompt the activity provoked is answered and
--resolved (and any minion death confirmations are in), publishing what it
--waits on through the shared notice. The activity is a monster move
--(opportunity attacks) or an ability cast (Repulsive Ward on the damage it
--dealt). Returns true when clear; false plus a reason when the AI was stopped
--or a reaction could not be confirmed (the AI is stopped with a modal).
function MonsterAI:WaitForActivityReactions(activityId)
    local pending, status, failure = self:CountPendingActivityReactions(activityId)
    local pendingMinionDeaths = self:CountPendingMinionDeathConfirmations()
    if pending == 0 and pendingMinionDeaths == 0 and failure == nil then
        return true
    end

    self:LogDecision("PLAYER REACTION WAIT START", {
        activity = activityId,
        pendingPlayerPrompts = pending,
        pendingMinionDeaths = pendingMinionDeaths,
        result = "waiting for player prompts and minion death confirmations",
    })

    local startedAt = dmhub.Time()
    local idleSince = nil
    local isAIRunning = rawget(MonsterAI, "IsAIRunning")
    local cancelWhenAIStops = MonsterAI.active and isAIRunning ~= nil
        and isAIRunning()
    while true do
        if mod.unloaded or (cancelWhenAIStops and not MonsterAI.active) then
            MonsterAI.reactionStatus = false
            MonsterAI.ClearWaiting()
            return false, mod.unloaded and "Monster AI module unloaded"
                or "Monster AI stop requested"
        end

        local subject
        pending, status, failure, subject = self:CountPendingActivityReactions(activityId)
        if failure ~= nil then
            MonsterAI.reactionStatus = false
            MonsterAI.ClearWaiting()
            MonsterAI.reactionFailure = "AI paused: " .. failure .. ". Check the reaction manually before restarting AI."
            self:LogDecision("PLAYER REACTION FAILED", {activity = activityId,
                reason = failure, result = "AI stopped; initiative remains on this monster"})
            MonsterAI.StopAI()
            pcall(function()
                gui.ModalMessage{title = "Monster AI Paused", message = MonsterAI.reactionFailure}
            end)
            return false, failure
        end
        pendingMinionDeaths = self:CountPendingMinionDeathConfirmations()
        MonsterAI.reactionStatus = status or (pendingMinionDeaths > 0 and "Waiting for minion death confirmations") or false
        MonsterAI.SetWaiting("reaction", NoticeTextFromReactionStatus(MonsterAI.reactionStatus),
            status ~= nil and subject or nil)
        if pending == 0 and pendingMinionDeaths == 0 then
            idleSince = idleSince or dmhub.Time()
            if dmhub.Time() - idleSince >= 0.3 then
                break
            end
        else
            idleSince = nil
        end
        coroutine.yield(0.1)
    end

    self:LogDecision("PLAYER REACTION WAIT FINISHED", {
        activity = activityId,
        result = "all player prompts and minion death confirmations resolved",
        duration = dmhub.Time() - startedAt,
    })
    MonsterAI.reactionStatus = false
    MonsterAI.ClearWaiting()
    return true
end

--Seconds a monster turn waits for its creatures to finish starting their turn.
--Normally well under a second; a turn start that errors early never reports
--back, and must not hold the table forever.
local g_turnStartWaitSeconds = 30

--- Holds a monster turn the AI just began until its start has played out, so
--- the monsters do not act while a hero is still answering a "Begin Turn"
--- trigger it set off (the Gunslinger's Showdown free strike).
--- turnStart is what the AI recorded when it began the turn:
---   activityId: the id passed to BeginTurn, which tags the turn start's events.
---   pending.count: how many of the turn's creatures have not finished BeginTurn.
--- Returns true when the turn may go ahead; false (plus a reason) when the AI
--- was stopped, or a hero's reaction could not be confirmed (the AI is paused).
--- Stops waiting on a creature that has not reported back after g_turnStartWaitSeconds.
--- @param turnStart {activityId: string, pending: {count: integer}}
--- @return boolean, string|nil
function MonsterAI:WaitForTurnStart(turnStart)
    if turnStart.pending.count > 0 then
        self:LogDecision("TURN START WAIT", {activity = turnStart.activityId,
            result = "waiting for start-of-turn triggers to fire"})
    end
    local startedAt = dmhub.Time()
    while turnStart.pending.count > 0 do
        if mod.unloaded or not MonsterAI.active then
            MonsterAI.ClearWaiting()
            return false, "Monster AI stop requested"
        end
        if dmhub.Time() - startedAt >= g_turnStartWaitSeconds then
            self:LogDecision("TURN START WAIT TIMEOUT", {activity = turnStart.activityId,
                pending = turnStart.pending.count, result = "playing the turn anyway"})
            break
        end
        MonsterAI.SetWaiting("turnstart", "Waiting for start-of-turn effects")
        coroutine.yield(0.1)
    end
    MonsterAI.ClearWaiting()

    --A trigger fired while another cast is resolving posts its prompt only once
    --that cast ends, so let casts settle before counting the heroes' prompts.
    self:WaitForAbilityIdle(5)
    return self:WaitForActivityReactions(turnStart.activityId)
end

function MonsterAI:MoveToken(token, loc, options, continueIfActorDies)
    --the board is about to change; forget planning answers (see PlanningMemo).
    self._tmp_planningMemo = nil
    local movementToken = self:GetMovementToken(token)
    local fromLoc = movementToken ~= nil and movementToken.loc or nil
    --Plans often keep the creature where it stands (movement-cost 0). Never ask
    --the engine to move there: it is not a move, and it used to nudge size 2+
    --creatures a square (NYQSV5BJ). No path is returned, as for a refused move.
    if self:MovementTokenIsAtLoc(token, loc) then
        self:LogDecision("MOVEMENT SKIPPED", {
            actor = self.TokenLogName(token),
            actorId = token ~= nil and token.charid or nil,
            to = self.LocLogName(loc),
            movementToken = movementToken ~= token and self.TokenLogName(movementToken) or nil,
            reason = "already at the destination",
        })
        return nil, true
    end
    local overlapsCreature, overlappingCreature = self:MovementLocOverlapsCreature(token, loc)
    if overlapsCreature then
        self:LogDecision("MOVEMENT REJECTED", {
            actor = self.TokenLogName(token),
            actorId = token ~= nil and token.charid or nil,
            from = self.LocLogName(fromLoc),
            to = self.LocLogName(loc),
            movementToken = movementToken ~= token and self.TokenLogName(movementToken) or nil,
            targets = self.TargetsLogName({{token = overlappingCreature}}),
            reason = "destination footprint overlaps another live creature",
        })
        if not continueIfActorDies then
            self._tmp_moveFailure = "movement destination overlaps another creature"
        end
        return nil, true
    end
    self:LogDecision("MOVEMENT START", {
        actor = self.TokenLogName(token),
        actorId = token ~= nil and token.charid or nil,
        from = self.LocLogName(fromLoc),
        to = self.LocLogName(loc),
        movementToken = movementToken ~= token and self.TokenLogName(movementToken) or nil,
        freeMovement = options ~= nil and options.freeMovement == true or nil,
    })
    local activityId = dmhub.GenerateGuid()
    local previousActivityId = creature.SetTokenAIActivity(movementToken.charid, activityId)
    local moveOk, result = pcall(function()
        return movementToken:Move(loc, options)
    end)
    creature.SetTokenAIActivity(movementToken.charid, previousActivityId)
    if not moveOk then
        error(result)
    end
    self:LogDecision("MOVEMENT ISSUED", {
        actor = self.TokenLogName(token),
        actorId = token ~= nil and token.charid or nil,
        from = self.LocLogName(fromLoc),
        to = self.LocLogName(loc),
        result = result ~= nil and "path accepted" or "no path returned",
    })

    if result ~= nil then
        local completed, reason = self:WaitForMovementActivity(movementToken, activityId)
        if not completed then
            self._tmp_abortTurn = reason
            error(reason)
        end
        if not self.TokenIsLiveCombatant(token) then
            if continueIfActorDies then
                self:LogDecision("MOVEMENT ACTOR LOST", {
                    actor = self.TokenLogName(token),
                    actorId = token ~= nil and token.charid or nil,
                    reason = "actor is no longer a live combatant after a player reaction",
                    result = "caller may continue with other actors",
                })
                return result, false
            end
            self._tmp_actorInterrupted = "actor is no longer a live combatant after a player reaction"
            error(self._tmp_actorInterrupted)
        end
    end
    if not continueIfActorDies and (options == nil or not options.straightline)
        and not self:MovementTokenIsAtLoc(token, loc) then
        self._tmp_moveFailure = "movement did not reach the planned destination"
    end
    return result, true
end

-- Engine Distance measures only the horizontal footprint. Draw Steel uses
-- free diagonals in 3D, measured between the creatures' occupied squares.
-- Absolute altitude includes floor elevation and mounted riders.
function MonsterAI.TargetDistance(actor, target)
    local actorBottom, targetBottom = actor.altitude, target.altitude
    local actorTop = actorBottom + math.max(1, actor.tileSize) - 1
    local targetTop = targetBottom + math.max(1, target.tileSize) - 1
    local vertical = math.max(0, targetBottom - actorTop, actorBottom - targetTop)
    return math.max(actor:Distance(target), vertical * dmhub.unitsPerSquare)
end

-- Use the real token volume (including riders) at a proposed destination.
function MonsterAI:TargetDistanceFromLoc(actor, target, loc)
    local distance
    self:ExecuteWithTheoreticalMovementLoc(actor, loc, function()
        distance = self.TargetDistance(actor, target)
    end)
    return distance
end

function MonsterAI:ExecuteWithTheoreticalMovementLoc(token, loc, fn)
    local movementToken = self:GetMovementToken(token)
    return movementToken:ExecuteWithTheoreticalLoc(loc, fn)
end

function MonsterAI:MovementTokenIsAtLoc(token, loc)
    local movementToken = self:GetMovementToken(token)
    return loc ~= nil and movementToken.loc.str == loc.str
end

local function OrderMountedRidersFirst(tokens)
    local tokensById = {}
    local ridersByMountId = {}
    for _,token in ipairs(tokens) do
        tokensById[token.charid] = token
    end

    for _,token in ipairs(tokens) do
        local mountId = token.mountedOn
        if mountId ~= nil and tokensById[mountId] ~= nil then
            ridersByMountId[mountId] = ridersByMountId[mountId] or {}
            ridersByMountId[mountId][#ridersByMountId[mountId]+1] = token
        end
    end

    local result = {}
    local emitted = {}
    local visiting = {}
    local function EmitToken(token)
        if emitted[token.charid] or visiting[token.charid] then
            return
        end

        visiting[token.charid] = true
        for _,rider in ipairs(ridersByMountId[token.charid] or {}) do
            EmitToken(rider)
        end
        visiting[token.charid] = nil
        emitted[token.charid] = true
        result[#result+1] = token
    end

    for _,token in ipairs(tokens) do
        EmitToken(token)
    end

    return result
end

-- Choose the leader for a shared initiative. Non-minions outrank minions,
-- squad captains outrank other non-minions, and EV breaks remaining ties.
function MonsterAI:FindMostSeniorInitiativeGroupMember(tokens)
    local best = nil
    local bestNonMinion = false
    local bestCaptain = false
    local bestEV = -math.huge

    for _,token in ipairs(tokens or {}) do
        if token ~= nil and token.valid and token.properties ~= nil
            and not token.properties:IsDead() then
            local nonMinion = not token.properties.minion
            local captain = nonMinion and token.properties:MinionSquad() ~= nil
            local ev = token.properties:EV()
            if best == nil
                or (nonMinion and not bestNonMinion)
                or (nonMinion == bestNonMinion and captain and not bestCaptain)
                or (nonMinion == bestNonMinion and captain == bestCaptain and ev > bestEV) then
                best = token
                bestNonMinion = nonMinion
                bestCaptain = captain
                bestEV = ev
            end
        end
    end

    return best
end

function MonsterAI:TelegraphAreaAbility(ability, area, symbols)
    local label = ability.name or "Area Ability"
    if symbols ~= nil and symbols.spellname ~= nil then
        label = symbols.spellname
    end

    for i = 1, self.areaTelegraphBlinks do
        local marker = area:Mark{
            color = "white",
            video = "divinationline.webm",
            label = label,
        }
        self.Sleep(self.areaTelegraphOnTime)
        marker:Destroy()
        self.Sleep(self.areaTelegraphOffTime)
    end
end

function MonsterAI:HandlePrompt(invokerToken, casterToken, abilityClone, symbols, options)
    local invokerMonsterType = invokerToken.properties:try_get("monster_type", "")
    self:LogDecision("PROMPT RECEIVED", {
        actor = self.TokenLogName(casterToken),
        actorId = casterToken ~= nil and casterToken.charid or nil,
        ability = abilityClone.name,
        prompt = string.format("%s:%s", invokerMonsterType, abilityClone.name),
        invoker = self.TokenLogName(invokerToken),
    })

    --the ability directly inserted the expected targets.
    local expectedEntry = self:try_get("_tmp_expectedPromptTarget")
    if expectedEntry ~= nil and expectedEntry.casterid == invokerToken.charid then
        self._tmp_expectedPromptTarget = nil

        --The expected targets were chosen for the position the caster PLANNED
        --to reach; if the preceding movement stopped short (collision, blocked
        --path), some may now be out of range and striking them would violate
        --the rules. Keep only targets legal from the caster's actual position.
        --If none remain, fall through to the registered prompt handler / DM.
        local targets = {}
        local range = abilityClone:GetRange(casterToken.properties)
        for _,target in ipairs(expectedEntry.targets or {}) do
            if target.token == nil or MonsterAI.TargetDistance(abilityClone:GetRangeSource(casterToken), target.token) <= range then
                targets[#targets+1] = target
            else
                self:LogDecision("PROMPT TARGET REJECTED", {
                    ability = abilityClone.name,
                    targets = self.TargetsLogName({target}),
                    reason = "planned target is now out of range",
                })
            end
        end

        if #targets > 0 then
            --line-of-sight rays so viewers can see who is being struck, the
            --same feedback ExecuteAbility draws for direct casts. The prompt
            --path has no cast-finished hook, so clean them up on a timer.
            local rays = {}
            for _,target in ipairs(targets) do
                if target.token ~= nil then
                    rays[#rays+1] = dmhub.MarkLineOfSight(casterToken, target.token, casterToken.properties:GetPierceWalls())
                end
            end
            if #rays > 0 then
                dmhub.Schedule(6, function()
                    for _,ray in ipairs(rays) do
                        ray:DestroyLineOfSight()
                    end
                end)
            end

            if expectedEntry.sleep then
                self.Sleep(expectedEntry.sleep)
            end
            options.targets = targets
            self:LogDecision("PROMPT RESOLVED", {
                ability = abilityClone.name,
                prompt = "expected targets",
                targets = self.TargetsLogName(targets),
                result = "automatic",
            })
            return "inherit"
        end
    end

    --try_get: the invoker can be an object token (e.g. a wall voxel
    --prompting for a target near it), whose TargetableObject
    --properties have no monster_type field.
    local qualifiedPrompt = string.format("%s:%s", invokerMonsterType, abilityClone.name)
    --Monster-qualified handlers get the first chance to answer shared wrapper
    --names. A nil result can then fall through to the generic handler.
    local handlers = {}
    local qualifiedHandler = self.prompts[qualifiedPrompt]
    local genericHandler = self.prompts[abilityClone.name]
    if qualifiedHandler ~= nil then
        handlers[#handlers+1] = {
            handler = qualifiedHandler,
            name = qualifiedHandler.id or qualifiedPrompt,
        }
    end
    if genericHandler ~= nil and genericHandler ~= qualifiedHandler then
        handlers[#handlers+1] = {
            handler = genericHandler,
            name = genericHandler.id or abilityClone.name,
        }
    end

    local attemptedHandlers = {}
    for _,entry in ipairs(handlers) do
        local handler = entry.handler
        attemptedHandlers[#attemptedHandlers+1] = entry.name
        local result = handler.handler(self, invokerToken, casterToken, abilityClone, symbols, options)
        if result ~= nil then
            local selectedAbility = result.abilityOverride or abilityClone
            if selectedAbility.targetType == "target" then
                local range = selectedAbility:GetRange(casterToken.properties, symbols)
                for _,target in ipairs(result.targets or {}) do
                    if target.token ~= nil and self.TargetDistance(selectedAbility:GetRangeSource(casterToken), target.token) > range then
                        self:LogDecision("PROMPT TARGET REJECTED", {
                            ability = selectedAbility.name,
                            reason = "target is outside range including altitude",
                        })
                        result = nil
                        break
                    end
                end
            end
        end
        if result ~= nil then
            for k,v in pairs(result) do
                options[k] = v
            end

            self:LogDecision("PROMPT RESOLVED", {
                ability = abilityClone.name,
                prompt = entry.name,
                targets = self.TargetsLogName(result.targets),
                result = result.abilityOverride ~= nil
                    and string.format("automatic with ability %s", result.abilityOverride.name)
                    or "automatic",
            })
            return "inherit"
        end
    end

    if #attemptedHandlers > 0 then
        self:LogDecision("PROMPT DEFERRED", {
            ability = abilityClone.name,
            prompt = table.concat(attemptedHandlers, ", "),
            reason = "registered handlers returned no automatic choice",
            result = "Director prompt",
        })
    else
        self:LogDecision("PROMPT DEFERRED", {
            ability = abilityClone.name,
            prompt = qualifiedPrompt,
            reason = "no registered AI prompt handler",
            result = "Director prompt",
        })
    end

    return "prompt"
end

--AI actions yield while movement, casts, and prompts resolve. Drive them in a
--child coroutine so an error can be returned without killing the AI process.
local function RunYieldingFunction(fn)
    local thread = coroutine.create(fn)
    while coroutine.status(thread) ~= "dead" do
        local outermostSlice = ProfSliceBegin()
        local ok, delay = coroutine.resume(thread)
        if outermostSlice then
            ProfSliceEnd()
        end
        if not ok then
            local err = delay
            pcall(function()
                err = debug.traceback(thread, tostring(delay))
            end)
            return false, err
        end
        if coroutine.status(thread) ~= "dead" then
            coroutine.yield(type(delay) == "number" and delay or 0.1)
        end
    end
    return true
end

function MonsterAI:RunYieldingFunction(fn)
    return RunYieldingFunction(fn)
end

--Run several yielding actions side by side and return once all have finished,
--starting each one `stagger` seconds after the one before. A minion squad uses
--this to move together. An error in one action does not abandon the others,
--whose tokens may be mid-move; the first error is raised once all are done.
function MonsterAI:RunConcurrently(fns, stagger)
    stagger = stagger or 0
    local threads, wakeAt = {}, {}
    local start = dmhub.Time()
    for i,fn in ipairs(fns) do
        threads[i] = coroutine.create(fn)
        wakeAt[i] = start + (i-1)*stagger
    end
    local firstError = nil
    while true do
        local now = dmhub.Time()
        local nextWake = nil
        for i,thread in ipairs(threads) do
            if coroutine.status(thread) ~= "dead" and now >= wakeAt[i] then
                local ok, delay = coroutine.resume(thread)
                if not ok then
                    if firstError == nil then
                        firstError = tostring(delay)
                        pcall(function()
                            firstError = debug.traceback(thread, tostring(delay))
                        end)
                    end
                elseif coroutine.status(thread) ~= "dead" then
                    wakeAt[i] = now + (type(delay) == "number" and delay or 0.1)
                end
            end
            if coroutine.status(thread) ~= "dead" then
                nextWake = math.min(nextWake or wakeAt[i], wakeAt[i])
            end
        end
        if nextWake == nil then
            break
        end
        coroutine.yield(math.max(0.01, nextWake - dmhub.Time()))
    end
    if firstError ~= nil then
        error(firstError, 0)
    end
end

--The control is kept in Creature.lua (creature.BeginAIControl), not on the
--token's properties, where an engine aura rebuild would wipe it mid-action.
function MonsterAI:BeginTokenControl(token)
    local promptCallback = function(invokerToken, casterToken, abilityClone, symbols, options)
        return self:HandlePrompt(invokerToken, casterToken, abilityClone, symbols, options)
    end

    local previousCallback = creature.BeginAIControl(token.charid, promptCallback)

    return {
        charid = token.charid,
        promptCallback = promptCallback,
        previousCallback = previousCallback,
    }
end

function MonsterAI:EndTokenControl(token, controlInfo)
    --keyed by the charid recorded at Begin, so a token that became invalid
    --mid-action still releases its control.
    creature.EndAIControl(controlInfo.charid, controlInfo.promptCallback, controlInfo.previousCallback)
end

function MonsterAI:FindTriggerHandler(token, triggerInfo)
    local function MatchingHandler(handler)
        if handler ~= nil and self.MoveMatchesMonster(token, handler, true) then
            return handler
        end
    end

    if type(triggerInfo.abilityGuid) == "string" then
        local handler = MatchingHandler(self.triggerHandlersByGuid[triggerInfo.abilityGuid])
        if handler ~= nil then
            return handler
        end
    end

    if type(triggerInfo.abilityName) == "string" then
        local monsterType = token.properties:try_get("monster_type", "")
        local qualifiedName = string.format("%s:%s", monsterType, triggerInfo.abilityName)
        local handler = MatchingHandler(self.triggerHandlersByMonsterAbility[qualifiedName])
        if handler ~= nil then
            return handler
        end

        handler = MatchingHandler(self.triggerHandlersByAbility[triggerInfo.abilityName])
        if handler ~= nil then
            return handler
        end
    end

    local triggerText = triggerInfo:GetText()
    if type(triggerText) == "string" then
        local monsterType = token.properties:try_get("monster_type", "")
        local qualifiedText = string.format("%s:%s", monsterType, triggerText)
        local handler = MatchingHandler(self.triggerHandlersByMonsterText[qualifiedText])
        if handler ~= nil then
            return handler
        end

        return MatchingHandler(self.triggerHandlersByText[triggerText])
    end
end

function MonsterAI:HandleAvailableTrigger(token, triggerInfo)
    if triggerInfo == nil or triggerInfo.triggered or triggerInfo.dismissed then
        return false
    end

    local registeredTrigger = self:FindTriggerHandler(token, triggerInfo)
    --Hostile cards are forced rules debts such as Bleeding damage and saves.
    --Human players get a red prompt, but an AI creature has no choice to make.
    local mandatoryTrigger = triggerInfo.hostile == true
    if registeredTrigger == nil and not mandatoryTrigger then
        return false
    end

    local triggerHandlerId = mandatoryTrigger and "Mandatory Trigger" or registeredTrigger.id

    self.token = token
    self:SetLogContext(token)
    local triggerText = triggerInfo:GetText()
    local triggerLogKey = string.format("%s:%s", token.charid, tostring(triggerInfo.id))
    self:LogDecision("TRIGGER CONSIDERED", {
        category = "Triggered Action",
        move = triggerHandlerId,
        ability = triggerInfo.abilityName,
        trigger = triggerText,
    })
    local decision = mandatoryTrigger and {activate = true}
        or registeredTrigger.handler(self, token, triggerInfo)
    if decision == true then
        decision = {activate = true}
    end

    if type(decision) ~= "table" or (not decision.activate and not decision.dismiss) then
        if not self.deferredTriggerLog[triggerLogKey] then
            self.deferredTriggerLog[triggerLogKey] = true
            self:LogDecision("TRIGGER DEFERRED", {
                category = "Triggered Action",
                move = triggerHandlerId,
                ability = triggerInfo.abilityName,
                trigger = triggerText,
                reason = "handler returned no activate or dismiss decision",
                result = "Director decision",
            })
        end
        return false
    end
    self.deferredTriggerLog[triggerLogKey] = nil

    self:LogDecision("TRIGGER DECIDED", {
        category = "Triggered Action",
        move = triggerHandlerId,
        ability = triggerInfo.abilityName,
        trigger = triggerText,
        targets = decision.expectedPrompt ~= nil
            and self.TargetsLogName(decision.expectedPrompt.targets) or nil,
        result = decision.dismiss and "dismiss" or "activate",
        mode = decision.mode,
    })

    if decision.expectedPrompt ~= nil then
        local expectedPrompt = table.shallow_copy(decision.expectedPrompt)
        expectedPrompt.casterid = expectedPrompt.casterid or token.charid
        self:SetTargetsForExpectedPrompt(expectedPrompt)
    end

    local startedAt = dmhub.Time()
    local ok, err = self:RunWithTokenControl(token, function()
        token:ModifyProperties{
            description = string.format("AI Trigger: %s", triggerHandlerId),
            undoable = false,
            execute = function()
                if decision.dismiss then
                    triggerInfo.dismissed = true
                elseif type(decision.mode) == "number" and decision.mode > 1 then
                    --ActiveTrigger stores alternate modes zero-based relative to the
                    --ability's mode list: true selects mode 1, 1 selects mode 2, etc.
                    triggerInfo.triggered = decision.mode - 1
                else
                    triggerInfo.triggered = true
                end

                token.properties:DispatchAvailableTrigger(triggerInfo)
            end,
        }

        --An accepted trigger may wait for the cast that caused it to finish before
        --starting its own cast. Keep AI prompt control installed until the prompt is
        --gone and all casts have been idle for a short grace period.
        local deadline = dmhub.Time() + 45
        local idleSince = nil
        while token.valid and token.properties ~= nil and dmhub.Time() < deadline do
            local availableTriggers = token.properties:GetAvailableTriggers() or {}
            local triggerPending = availableTriggers[triggerInfo.id] ~= nil
            local castPending = ActivatedAbility.CountActiveCasts() > 0
            if not triggerPending and not castPending then
                idleSince = idleSince or dmhub.Time()
                if dmhub.Time() - idleSince >= 0.3 then
                    break
                end
            else
                idleSince = nil
            end

            coroutine.yield(0.1)
        end
    end)

    if not ok then
        self:LogDecision("TRIGGER ERROR", {
            category = "Triggered Action",
            move = triggerHandlerId,
            ability = triggerInfo.abilityName,
            trigger = triggerText,
            reason = "execution failed: " .. tostring(err),
        })
        error(err)
    end

    self:LogDecision("TRIGGER FINISHED", {
        category = "Triggered Action",
        move = triggerHandlerId,
        ability = triggerInfo.abilityName,
        trigger = triggerText,
        result = decision.dismiss and "dismissed" or "activated",
        duration = dmhub.Time() - startedAt,
    })
    return true
end

function MonsterAI:PlayTurn(initiativeid)
    dmhub.Coroutine(function()
        --Everything a turn does -- moving monsters, casting their abilities --
        --is the HOST acting, not the user playing, so run the whole turn with
        --host permissions. On a player host (Encounter of the Week) this is
        --what keeps player rules enforcement from binding the AI; the engine
        --parks the elevation whenever this coroutine yields, so the user still
        --sees player vision and player UI throughout.
        ElevateToHostPermissions()
        self:PlayTurnSafely(initiativeid)
        DropHostPermissions()
    end)
end

function MonsterAI:PlayTurnSafely(initiativeid)
    local turnPhase = ProfPhaseBegin("turn")
    local ok, err = RunYieldingFunction(function()
        self:PlayTurnCoroutine(initiativeid)
    end)
    ProfPhaseEnd(turnPhase, ok and "completed" or ("error: " .. tostring(err)))
    ProfRequestReport(string.format("turn %s, round %s", tostring(initiativeid),
        tostring(dmhub.initiativeQueue ~= nil and dmhub.initiativeQueue.round or "?")))
    if ok then
        return true
    end

    local queue = dmhub.initiativeQueue
    pcall(function()
        self:SetLogContext(nil, {
            turn = initiativeid,
            round = queue ~= nil and queue.round or nil,
        })
        self:LogDecision("TURN ERROR", {
            reason = tostring(err),
            result = "recovering and advancing initiative",
        })
    end)

    --A failed action can leave a cast finishing asynchronously. Give it a short
    --grace period before advancing, but never let it strand the initiative.
    local idle = false
    RunYieldingFunction(function()
        idle = self:WaitForAbilityIdle(5)
    end)
    if not idle then
        pcall(function()
            self:LogDecision("TURN RECOVERY", {
                reason = "ability casts did not become idle within 5 seconds",
                result = "advancing initiative anyway",
            })
        end)
    end

    queue = dmhub.initiativeQueue
    if queue ~= nil and not queue.hidden and queue:CurrentInitiativeId() == initiativeid then
        local advanceOk, advanceErr = pcall(function()
            GameHud.instance:NextInitiative(function()
                dmhub:UploadInitiativeQueue()
            end)
        end)
        if not advanceOk then
            pcall(function()
                self:LogDecision("TURN RECOVERY ERROR", {
                    reason = tostring(advanceErr),
                    result = "initiative could not be advanced",
                })
            end)
        end
    end

    return false, err
end

function MonsterAI:FindSquadActionToken()
    --A critical hit may belong to a different minion than the squad's first actor.
    for _,member in ipairs(self.squadMembers) do
        if self.TokenIsLiveCombatant(member.token) then
            for _,ability in ipairs(member.token.properties:GetActivatedAbilities()) do
                if MonsterAI.IsMinionSignatureAbility(ability) and ability:CanAfford(member.token) then
                    return member.token
                end
            end
        end
    end
end

--- True when a minion squad may use this ability as its signature: it is tagged
--- "Signature Ability" and costs a main action, as every Draw Steel signature does.
--- The cost check keeps out maneuvers mis-tagged as signatures, such as the Quick
--- Snack a pollywog's aura grants its allies, which minions used to cast at heroes
--- once their real signature had spent the main action.
--- @param ability ActivatedAbility
--- @return boolean
function MonsterAI.IsMinionSignatureAbility(ability)
    return ability.categorization == "Signature Ability"
        and ability:ActionResource() == CharacterResource.actionResourceId
end

--The turn can move to another entry while the AI is mid-turn (a turn-grab
--ability, a host clicking the initiative bar). Once it has, the AI must stop:
--acting on would overlap the new creature's turn, and NextInitiative would
--end that creature's turn rather than this one (6TTFJWFP).
local g_abortTurnTaken = "the turn moved to another initiative entry"

local function TurnStillCurrent(initiativeid)
    local q = dmhub.initiativeQueue
    return q ~= nil and not q.hidden and q:CurrentInitiativeId() == initiativeid
end

--A monster that sat out a turn hidden is dull to play against, so every hidden monster
--the AI is about to play reveals itself first and then acts. Hidden This Turn still gives
--it the edge for the rest of the turn. Hiding again later in the turn works as usual.
--- @param tokens CharacterToken[]
function MonsterAI:RevealHiddenActors(tokens)
    local revealed = {}
    for _, token in ipairs(tokens) do
        if self.TokenIsLiveCombatant(token) and not token.playerControlled
            and token.properties:HasNamedCondition("Hidden") then
            token:ModifyProperties{
                description = "Reveal at start of turn",
                execute = function()
                    token.properties:LoseHidden()
                end,
            }
            revealed[#revealed+1] = {token = token}
        end
    end

    if #revealed > 0 then
        self:LogDecision("REVEAL HIDDEN", {
            targets = self.TargetsLogName(revealed),
        })
        --give players a beat to see who appeared before anyone moves, and let an
        --ambush banner (shown 0.4s after a reveal from hiding) play out.
        MonsterAI.Sleep(0.6)
        local bannerWait = DramaticBanner.TimeUntilDone()
        if bannerWait > 0 then
            MonsterAI.Sleep(bannerWait + 0.2)
        end
    end
end

function MonsterAI:PlayTurnCoroutine(initiativeid)
    local queue = dmhub.initiativeQueue
	self._tmp_abortTurn = nil
    self._tmp_rangedStrikers = {}

    self.log.analysis = self:Analysis()

    if queue ~= nil and (not queue.hidden) and initiativeid == queue:CurrentInitiativeId() then

        local tokens = InitiativeQueue.GetTokensForInitiativeId(initiativeid)
        tokens = OrderMountedRidersFirst(tokens or {})
        local turnTargets = {}
        for _,turnToken in ipairs(tokens) do
            turnTargets[#turnTargets+1] = {token = turnToken}
        end
        self:SetLogContext(nil, {
            turn = initiativeid,
            round = queue.round,
        })
        self:LogDecision("TURN START", {
            targets = self.TargetsLogName(turnTargets),
            tokenCount = #tokens,
        })

        self:RevealHiddenActors(tokens)

        self:HandleMaliceAbilityStartOfTurn(initiativeid, tokens, queue)
        self:SetLogContext(nil, {
            turn = initiativeid,
            round = queue.round,
        })

        local processedSquads = {}
        for i=1,#tokens do
            --stopped already: the start-of-turn Malice preview was abandoned.
            if self:try_get("_tmp_abortTurn") ~= nil then
                break
            end
            if not TurnStillCurrent(initiativeid) then
                self._tmp_abortTurn = g_abortTurnTaken
                break
            end
            local token = tokens[i]
            local alreadyProcessed = false
            local squadMembers = {}
            local squadid = nil
            self.squadCaptain = false
            self.squadMembers = squadMembers
            self.activeTactics = {}
            if self.TokenIsLiveCombatant(token) and token.properties.minion then
                squadid = token.properties:MinionSquad()
                local squadKey = squadid or token.charid
                if processedSquads[squadKey] then
                    self:SetLogContext(token, {
                        turn = initiativeid,
                        round = queue.round,
                    })
                    self:LogDecision("ACTOR SKIPPED", {
                        reason = "minion squad action was already processed",
                    })
                    alreadyProcessed = true
                else
                    --The coordinated action belongs to the squad, so remember it
                    --independently of whichever minion happens to start the work.
                    processedSquads[squadKey] = true
                    for j=1,#tokens do
                        local otherToken = tokens[j]
                        if self.TokenIsLiveCombatant(otherToken) and otherToken.properties.minion
                            and otherToken.properties:MinionSquad() == squadid then
                            squadMembers[#squadMembers+1] = {token = otherToken}
                        end
                    end
                end
            end

            if #squadMembers > 0 then
                for j=1,#tokens do
                    if self.TokenIsLiveCombatant(tokens[j]) and not tokens[j].properties.minion then
                        local minionSquad = tokens[j].properties:MinionSquad()
                        if minionSquad == squadid then
                            self.squadCaptain = tokens[j]
                            break
                        end
                    end
                end
            end

            if self.TokenIsLiveCombatant(token) and (not alreadyProcessed) then
                local controls = {}
                local actorPhase = ProfPhaseBegin(string.format("actor: %s%s", self.TokenLogName(token),
                    #squadMembers > 0 and string.format(" (squad of %d)", #squadMembers) or ""))
                local ok, actorErr = RunYieldingFunction(function()
                    self.token = token
                    self:SetLogContext(token, {
                        turn = initiativeid,
                        round = queue.round,
                    })
                    self:FocusCameraOnActor(token)
                    self.squad = squadMembers

                    if token.properties.minion then
                        self.squad = {}
                    else
                        self.squad = false
                    end

                    if #self.squadMembers > 0 then
                        for _,member in ipairs(self.squadMembers) do
                            if self.TokenIsLiveCombatant(member.token) then
                                controls[#controls+1] = {
                                    token = member.token,
                                    info = self:BeginTokenControl(member.token),
                                }
                            end
                        end
                    else
                        controls[#controls+1] = {
                            token = token,
                            info = self:BeginTokenControl(token),
                        }
                    end

                    self:SetupCombatants(token, queue)
                    self._tmp_synthesizedAbilitiesUsed = {}
                    self._tmp_synthesizedPlanningFailed = false
                    self._tmp_failedMoves = {}
                    self._tmp_failedChargePlans = {}
					self._tmp_actorInterrupted = nil

                    local tacticNames = table.keys(self.activeTactics)
                    table.sort(tacticNames)
                    self:LogDecision("ACTOR START", {
                        abilities = self.AbilitiesLogName(self.abilities),
                        activeTactics = #tacticNames > 0 and table.concat(tacticNames, ", ") or "none",
                        allies = #self.allyTokens,
                        enemies = #self.enemyTokens,
                        minion = token.properties.minion,
                        squadMembers = #self.squadMembers,
                    })

                    for cycle=1,6 do
                        local actingToken = token
                        if #self.squadMembers > 0 then
                            actingToken = self:FindSquadActionToken()
                            if actingToken == nil then
                                self:LogDecision("MOVE SEARCH FINISHED", {
                                    reason = "no surviving squad member has an affordable Signature Ability",
                                    result = "no legal move",
                                })
                                break
                            end
                        end
                        local cyclePhase = ProfPhaseBegin(string.format("cycle %d", cycle))
                        self:SetLogContext(actingToken, {
                            turn = initiativeid,
                            round = queue.round,
                            cycle = cycle,
                        })
                        self:SetupCombatants(actingToken, queue)
                        self.paths = self:CalculateRemainingMovementPaths(actingToken)
                        self:LogDecision("MOVE CYCLE START", {
                            reachableLocations = #table.values(self.paths),
                        })

                        local result = self:FindAndExecuteMove()
                        ProfPhaseEnd(cyclePhase, tostring(result))
                        self:LogDecision("MOVE CYCLE FINISHED", {
                            result = result,
                        })
                        if self:try_get("_tmp_abortTurn") == nil and not TurnStillCurrent(initiativeid) then
                            self._tmp_abortTurn = g_abortTurnTaken
                        end
                        if self:try_get("_tmp_abortTurn") ~= nil
                            or result == g_moveResultNone or result == g_moveResultUnsafe then
                            break
                        end
                    end
                end)
                ProfPhaseEnd(actorPhase, ok and "ok" or "error")

                for _,control in ipairs(controls) do
                    pcall(function()
                        self:EndTokenControl(control.token, control.info)
                    end)
                end
                self._tmp_expectedPromptTarget = nil

                pcall(function()
                    self:SetLogContext(token, {
                        turn = initiativeid,
                        round = queue.round,
                    })
                    if ok then
                        self:LogDecision("ACTOR FINISHED", {
                            result = self.TokenIsLiveCombatant(token)
                                and "completed" or "token became invalid",
                        })
                    else
                        self:LogDecision("ACTOR ERROR", {
                            reason = tostring(actorErr),
                            result = "remaining actions skipped; continuing turn",
                        })
                    end
                end)
            else
                if not alreadyProcessed then
                    self:SetLogContext(token, {
                        turn = initiativeid,
                        round = queue.round,
                    })
                    self:LogDecision("ACTOR SKIPPED", {
                        reason = not token.valid and "token is no longer valid"
                            or token.properties == nil and "token has no properties"
                            or "token is dead",
                    })
                end
            end

			if self:try_get("_tmp_abortTurn") ~= nil then
				break
			end
        end

        self:SetLogContext(nil, {
            turn = initiativeid,
            round = queue.round,
        })
		if self:try_get("_tmp_abortTurn") == nil and not TurnStillCurrent(initiativeid) then
			self._tmp_abortTurn = g_abortTurnTaken
		end
		if self:try_get("_tmp_abortTurn") ~= nil then
			self:LogDecision("TURN PAUSED", {
				reason = self._tmp_abortTurn,
				result = self._tmp_abortTurn == g_abortTurnTaken
					and "initiative left with the entry that took the turn"
					or "initiative left on the current monster",
			})
			return
		end
        self:LogDecision("TURN FINISHED", {
            result = "advancing initiative",
        })
        GameHud.instance:NextInitiative(function()
            dmhub:UploadInitiativeQueue()
        end)
        
        coroutine.yield(0.5)
    else
        self:SetLogContext(nil, {turn = initiativeid})
        self:LogDecision("TURN ABORTED", {
            --the `or` arms only run once queue == nil was false.
            reason = queue == nil and "no initiative queue"
                or (queue --[[@as InitiativeQueue]]).hidden and "initiative queue is hidden"
                or "initiative entry is no longer current",
        })
    end
end

local function FindAbilityByName(abilities, name)
    for _,ability in ipairs(abilities) do
        if ability.name == name then
            return ability
        end
    end

    return nil
end 

local function FindMaliceAbilityByName(token, name)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.name == name and ability.categorization == "Malice" then
            return ability
        end
    end
end

function MonsterAI.TokenIsLiveCombatant(token)
    return token ~= nil and token.valid and token.properties ~= nil
        and not token.properties:IsDead()
end

function MonsterAI:RefreshCombatants(queue, referenceToken)
    self.enemyTokens = {}
    self.allyTokens = {}
    local token = referenceToken or self.token
    if not self.TokenIsLiveCombatant(token) then
        return
    end

    for _,other in ipairs(dmhub.allTokens) do
        local initiativeid = InitiativeQueue.GetInitiativeId(other)
        if self.TokenIsLiveCombatant(other) and initiativeid ~= nil
            and queue ~= nil and queue.entries[initiativeid] ~= nil then
            if dmhub.TokensAreFriendly(token, other) then
                self.allyTokens[#self.allyTokens+1] = other
            else
                self.enemyTokens[#self.enemyTokens+1] = other

                local hasAidAttack = false
                for _,effect in ipairs(other.properties:ActiveOngoingEffects()) do
                    if effect.ongoingEffectid == "e234f1f4-9953-43bd-894c-d96adbb63f84" then
                        hasAidAttack = true
                        break
                    end
                end
                other.properties._tmp_ai_aidAttack = hasAidAttack
            end
        end
    end
end

function MonsterAI:SetupCombatants(token, queue)
    self.token = token
    local prof = ProfBegin("GetActivatedAbilities")
    self.abilities = token.properties:GetActivatedAbilities()
    ProfEnd(prof)
    self.activeTactics = {}

    for id,tactic in pairs(self.tactics) do
        if self.MoveMatchesMonster(token, tactic) then
            self.activeTactics[id] = tactic
        end
    end

    self:RefreshCombatants(queue)
end

local function InitiativeEntryHasLiveToken(initiativeid)
    for _,token in ipairs(InitiativeQueue.GetTokensForInitiativeId(initiativeid) or {}) do
        if token.valid and token.properties ~= nil and not token.properties:IsDead() then
            return true
        end
    end
    return false
end

local function CountFutureVillainActionWindows(queue, endedInitiativeId, ownerInitiativeId)
    local result = 0
    for initiativeid,entry in pairs(queue.entries) do
        if initiativeid ~= endedInitiativeId and initiativeid ~= ownerInitiativeId
            and entry.round <= queue.round and InitiativeEntryHasLiveToken(initiativeid) then
            result = result + 1
        end
    end
    return result
end

function MonsterAI:RunWithTokenControl(token, fn)
    local controlInfo = self:BeginTokenControl(token)
    local ok, err = RunYieldingFunction(fn)
    local cleanupOk, cleanupErr = pcall(function()
        self:EndTokenControl(token, controlInfo)
    end)
    self._tmp_expectedPromptTarget = nil
    if not cleanupOk then
        if ok then
            return false, cleanupErr
        end
        return false, string.format("%s; token control cleanup failed: %s",
            tostring(err), tostring(cleanupErr))
    end
    return ok, err
end

function MonsterAI:WaitForAbilityIdle(timeout)
    local deadline = dmhub.Time() + (timeout or 45)
    local idleSince = nil
    --While a cast is held open by a hero's trigger prompt, tell the table
    --whose prompt it is. Scanned at most twice a second; cleared on exit.
    local lastPromptScan = -math.huge
    local waitingSet = false
    while dmhub.Time() < deadline do
        if ActivatedAbility.CountActiveCasts() <= 0 then
            idleSince = idleSince or dmhub.Time()
            if dmhub.Time() - idleSince >= 0.3 then
                if waitingSet then MonsterAI.ClearWaiting() end
                return true
            end
        else
            idleSince = nil
            if dmhub.Time() - lastPromptScan >= 0.5 then
                lastPromptScan = dmhub.Time()
                local notice, subject = FindPlayerTriggerPromptNotice()
                if notice ~= nil then
                    MonsterAI.SetWaiting("cast", notice, subject)
                    waitingSet = true
                elseif waitingSet then
                    MonsterAI.ClearWaiting()
                    waitingSet = false
                end
            end
        end
        coroutine.yield(0.1)
    end
    if waitingSet then MonsterAI.ClearWaiting() end
    return false
end

local g_aiMinionDeathPendingTimeout = 125

local function AIMinionDeathPending(creatureProps)
    local confirmedAt = creatureProps:try_get("_tmp_minionDeathPending")
    return confirmedAt ~= nil and dmhub.Time() - confirmedAt < g_aiMinionDeathPendingTimeout
end

local function GetMinionLastAttacker(creatureProps)
    local attacker = creatureProps:try_get("_tmp_lastattacker")
    if type(attacker) == "function" then
        attacker = attacker("self")
    end
    return attacker
end

local function IsAIControlledAttacker(attacker)
    if attacker == nil then
        return false
    end

    local aiControlled = false
    pcall(function()
        aiControlled = attacker:IsAIControlled() == true
    end)
    return aiControlled
end

local function ConfirmAIMinionDeath(token, attacker)
    if token == nil or not token.valid or token.properties == nil
        or not token.properties.minion or token.properties.minionDead
        or AIMinionDeathPending(token.properties) then
        return false
    end

    token.properties._tmp_minionDeathPending = dmhub.Time()

    attacker = attacker or GetMinionLastAttacker(token.properties)
    if attacker ~= nil then
        --An overflow death can legally choose a squad member that was not the
        --direct damage target. Carry the killing attacker onto that minion so
        --kill triggers and the corpse attribution match the actual cast.
        token.properties._tmp_lastattacker = attacker
    end
    if attacker ~= nil then
        attacker:TriggerEvent("kill", {
            victim = token.properties,
            hasattacker = true,
            attacker = attacker,
        })
    end

    token.properties:TriggerEvent("creaturedeath", {
        hasattacker = attacker ~= nil,
        attacker = attacker,
    })
    token.properties:MinionDeath()
    return true
end

--Minion damage reduces the squad's shared Stamina pool, but the attacker must
--still choose the individual minions that die. Normally the Director does that
--by clicking the skulls created in DrawSteelTokenHud. AI casts have no ability
--prompt for that choice, so mirror the skull's eligibility and confirmation
--rules here while the attacking creatures are still under AI control.
function MonsterAI:ResolvePendingMinionDeaths(timeout)
    local deadline = dmhub.Time() + (timeout or 5)

    while true do
        local squads = {}
        for _,token in ipairs(dmhub.GetTokens{haveProperties = true}) do
            if token.valid and token.properties ~= nil and token.properties.minion
                and not token.properties.minionDead
                and token.properties:has_key("_tmp_minionSquad") then
                local squad = token.properties._tmp_minionSquad
                local entry = squads[squad]
                if entry == nil then
                    entry = {
                        squad = squad,
                        tokens = {},
                        attacker = nil,
                        attackerToken = nil,
                    }
                    squads[squad] = entry
                end

                entry.tokens[#entry.tokens+1] = token
                local attacker = GetMinionLastAttacker(token.properties)
                if IsAIControlledAttacker(attacker) then
                    entry.attacker = attacker
                    entry.attackerToken = dmhub.LookupToken(attacker)
                end
            end
        end

        local choices = {}
        local waiting = false
        for _,entry in pairs(squads) do
            local squad = entry.squad
            local healthSingle = squad.health_single or 0
            local damageTaken = squad.damage_taken or 0
            local deathsOwed = 0
            if healthSingle > 0 then
                deathsOwed = math.min(#entry.tokens, math.floor(damageTaken / healthSingle))
            end

            if entry.attacker ~= nil and deathsOwed > 0 then
                local pendingDeaths = 0
                for _,token in ipairs(entry.tokens) do
                    if AIMinionDeathPending(token.properties) then
                        pendingDeaths = pendingDeaths + 1
                    end
                end

                local deathsToChoose = deathsOwed - pendingDeaths
                if deathsToChoose > 0 then
                    if squad.damage_time_pending then
                        waiting = true
                    else
                        local candidates = {}
                        local numRecentlyDamaged = squad.num_recently_damaged or 0
                        local deathOverflows = damageTaken >= (numRecentlyDamaged + 1) * healthSingle

                        for _,token in ipairs(entry.tokens) do
                            local props = token.properties
                            local isDirectTarget = props.minionDamageTime == squad.damage_time
                            local gated = (props:CalculateNamedCustomAttribute("Gated Minion Deaths") or 0) > 0
                            local triggers = props:GetAvailableTriggers(true)
                            if not AIMinionDeathPending(props) and not gated
                                and (isDirectTarget or deathOverflows) and triggers == nil then
                                local distance = 999999
                                if entry.attackerToken ~= nil and entry.attackerToken.valid then
                                    distance = entry.attackerToken:Distance(token)
                                end
                                candidates[#candidates+1] = {
                                    token = token,
                                    direct = isDirectTarget,
                                    distance = distance,
                                }
                            end
                        end

                        table.sort(candidates, function(a, b)
                            if a.direct ~= b.direct then
                                return a.direct
                            end
                            if a.distance ~= b.distance then
                                return a.distance < b.distance
                            end
                            return a.token.charid < b.token.charid
                        end)

                        for i=1,math.min(deathsToChoose, #candidates) do
                            choices[#choices+1] = {
                                token = candidates[i].token,
                                attacker = entry.attacker,
                            }
                        end

                        if #candidates < deathsToChoose then
                            waiting = true
                        end
                    end
                end
            end
        end

        if #choices > 0 then
            for _,choice in ipairs(choices) do
                if ConfirmAIMinionDeath(choice.token, choice.attacker) then
                    self:LogDecision("MINION DEATH SELECTED", {
                        targets = self.TargetsLogName({{token = choice.token}}),
                        reason = "squad damage requires a minion death",
                    })
                end
            end
            self.Sleep(0.1)
        elseif waiting and dmhub.Time() < deadline then
            coroutine.yield(0.1)
        else
            return
        end
    end
end

function MonsterAI.MaliceAbilityMatchesMonster(token, maliceAbility, includeDisabled)
    if token == nil or not token.valid or token.properties == nil then
        return false
    end

    local monsterType = token.properties:try_get("monster_type", "")
    if not includeDisabled and maliceAbility.disabledForMonsters ~= nil
        and maliceAbility.disabledForMonsters[monsterType] then
        return false
    end

    if maliceAbility.monsterGroups ~= nil then
        local group = token.properties:MonsterGroup()
        if group == nil then
            return false
        end

        for _,groupNameOrId in ipairs(maliceAbility.monsterGroups) do
            if group.name == groupNameOrId or group.id == groupNameOrId then
                return true
            end
        end
        return false
    end

    return MonsterAI.MoveMatchesMonster(token, maliceAbility, includeDisabled)
end

function MonsterAI:HandleMaliceAbilityStartOfTurn(initiativeid, actingTokens, queue)
    local phase = ProfPhaseBegin("malice window")
    local result = self:HandleMaliceAbilityStartOfTurnInternal(initiativeid, actingTokens, queue)
    ProfPhaseEnd(phase)
    return result
end

function MonsterAI:HandleMaliceAbilityStartOfTurnInternal(initiativeid, actingTokens, queue)
    local usedAbilities = MaliceAbilityHistory(queue)
    if queue == nil or queue.hidden or initiativeid ~= queue:CurrentInitiativeId() then
        return false
    end

    self:SetLogContext(nil, {
        turn = initiativeid,
        round = queue.round,
    })
    self:LogDecision("MALICE WINDOW START", {
        malice = CharacterResource.GetMalice(),
        registrations = #table.values(self.maliceAbilities),
    })

    local bestCandidate = nil
    for _,registration in pairs(self.maliceAbilities) do
        local groupTokens = {}
        local eligibleCasters = {}
        for _,token in ipairs(actingTokens) do
            if token.valid and token.properties ~= nil and not token.properties:IsDead()
                and self.MaliceAbilityMatchesMonster(token, registration, true) then
                groupTokens[#groupTokens+1] = token
                if self.MaliceAbilityMatchesMonster(token, registration) then
                    eligibleCasters[#eligibleCasters+1] = token
                end
            end
        end

        if #groupTokens > 0 and #eligibleCasters == 0 then
            self:LogDecision("MALICE REJECTED", {
                category = self.MoveCategoryLogName(registration),
                move = registration.id,
                ability = registration.abilities ~= nil and registration.abilities[1] or nil,
                reason = "registration is disabled for every matching acting monster",
            })
        elseif #eligibleCasters > 0 and registration.abilities ~= nil and registration.abilities[1] ~= nil then
            local caster = nil
            ---@type ActivatedAbility
            local ability = nil
            local unavailableReasons = {}
            local unavailableByToken = {}
            local function RecordUnavailable(token, reason)
                if not unavailableByToken[token.charid] then
                    unavailableByToken[token.charid] = true
                    unavailableReasons[#unavailableReasons+1] = string.format("%s %s",
                        self.TokenLogName(token), reason)
                end
            end
            for pass=1,2 do
                for _,token in ipairs(eligibleCasters) do
                    if pass == 2 or not token.properties.minion then
                        local candidateAbility = FindMaliceAbilityByName(token, registration.abilities[1])
                        if candidateAbility == nil then
                            RecordUnavailable(token, "lacks " .. registration.abilities[1])
                        elseif not candidateAbility:CanAfford(token) then
                            RecordUnavailable(token, AIAbilityUnavailableReason(token, candidateAbility))
                        else
                            local filterFailure = candidateAbility:AbilityFilterFailureMessage(token.properties)
                            if filterFailure ~= nil then
                                RecordUnavailable(token, "blocked: " .. tostring(filterFailure))
                            else
                                caster = token
                                ability = candidateAbility
                                break
                            end
                        end
                    end
                end
                if caster ~= nil then
                    break
                end
            end

            if caster ~= nil then
                self:SetLogContext(caster, {
                    turn = initiativeid,
                    round = queue.round,
                })
                self:SetupCombatants(caster, queue)
                local context = {
                    actingTokens = actingTokens,
                    allyTokens = self.allyTokens,
                    enemyTokens = self.enemyTokens,
                    groupTokens = groupTokens,
                    initiativeId = initiativeid,
                    initiativeQueue = queue,
                    malice = CharacterResource.GetMalice(),
                    round = queue.round,
                }

                local scoreProf = ProfBegin("malice score: " .. tostring(registration.id))
                local ok, scoringInfo, scoringReason = pcall(
                    registration.score, registration, self, caster, ability, context)
                ProfEnd(scoreProf)
                if not ok then
                    self:LogDecision("MALICE ERROR", {
                        category = self.MoveCategoryLogName(registration),
                        move = registration.id,
                        ability = ability.name,
                        reason = "scoring failed: " .. tostring(scoringInfo),
                    })
                    self:LogMove(caster.properties.monster_type, registration.id, "Scoring failed: " .. tostring(scoringInfo))
                else
                    if type(scoringInfo) == "number" then
                        scoringInfo = {score = scoringInfo}
                    end

                    if type(scoringInfo) == "table" and type(scoringInfo.score) == "number" then
                        local score = math.max(0, math.min(1, scoringInfo.score))
                        local minimumScore = tonumber(registration.minimumScore) or self.maliceAbilityMinimumScore
                        local repeatPenalty = usedAbilities[MaliceAbilityHistoryKey(ability)]
                            and self.maliceAbilityRepeatPenalty or 0
                        local selectionScore = score - repeatPenalty
                        self:LogMove(caster.properties.monster_type, registration.id,
                            string.format("Score %.2f; threshold %.2f; repeat penalty %.2f; selection %.2f",
                                score, minimumScore, repeatPenalty, selectionScore))
                        self:LogDecision("MALICE CANDIDATE", {
                            category = self.MoveCategoryLogName(registration),
                            move = registration.id,
                            ability = ability.name,
                            action = self.AbilityActionLogName(ability),
                            score = score,
                            repeatPenalty = repeatPenalty,
                            selectionScore = selectionScore,
                            threshold = minimumScore,
                            plan = self.ScoringPlanLogName(scoringInfo),
                            result = score >= minimumScore and "eligible" or "below threshold",
                        })

                        -- Keep the quality threshold on the original score so repetition
                        -- remains an option when there is no worthwhile alternative.
                        if score >= minimumScore and (bestCandidate == nil or selectionScore > bestCandidate.score
                            or (selectionScore == bestCandidate.score and registration.id < bestCandidate.registration.id)) then
                            bestCandidate = {
                                ability = ability,
                                caster = caster,
                                context = context,
                                registration = registration,
                                score = selectionScore,
                                scoringInfo = scoringInfo,
                            }
                        end
                    else
                        self:LogMove(caster.properties.monster_type, registration.id,
                            "Could not use at the start of this turn", {onlyIfEmpty = true})
                        self:LogDecision("MALICE REJECTED", {
                            category = self.MoveCategoryLogName(registration),
                            move = registration.id,
                            ability = ability.name,
                            reason = scoringReason or "score callback returned no legal plan",
                        })
                    end
                end
            else
                self:LogDecision("MALICE REJECTED", {
                    category = self.MoveCategoryLogName(registration),
                    move = registration.id,
                    ability = registration.abilities[1],
                    reason = #unavailableReasons > 0
                        and table.concat(unavailableReasons, "; ")
                        or "no eligible caster has a legal, affordable ability",
                })
            end
        end
    end

    if bestCandidate == nil then
        self:SetLogContext(nil, {
            turn = initiativeid,
            round = queue.round,
        })
        self:LogDecision("MALICE WINDOW FINISHED", {
            result = "no Malice ability selected",
        })
        return false
    end

    local registration = bestCandidate.registration
    local caster = bestCandidate.caster
    self:SetLogContext(caster, {
        turn = initiativeid,
        round = queue.round,
        category = self.MoveCategoryLogName(registration),
        move = registration.id,
    })
    self:LogDecision("MALICE SELECTED", {
        ability = bestCandidate.ability.name,
        action = self.AbilityActionLogName(bestCandidate.ability),
        score = bestCandidate.score,
        plan = self.ScoringPlanLogName(bestCandidate.scoringInfo),
    })
    self:FocusCameraOnActor(caster)
    self:SetupCombatants(caster, queue)
    if self.PlanPreviewsOn() and not self:AwaitPlanPreview(
        self:BuildMalicePreview(caster, bestCandidate.ability, bestCandidate.scoringInfo)) then
        self:LogDecision("MALICE FINISHED", {
            ability = bestCandidate.ability.name,
            result = "not used: the turn stopped during its preview",
        })
        return false
    end
    local execute = registration.execute or function(_, ai, token, scoringInfo, ability, context)
        ai:ExecuteAbility(token, ability)
    end
    local ok, err = self:RunWithTokenControl(caster, function()
        execute(registration, self, caster, bestCandidate.scoringInfo, bestCandidate.ability, bestCandidate.context)
    end)

    if not ok then
        self:LogDecision("MALICE ERROR", {
            ability = bestCandidate.ability.name,
            reason = "execution failed: " .. tostring(err),
        })
        self:LogMove(caster.properties.monster_type, registration.id, "Execution failed: " .. tostring(err))
        return false
    end

    self:WaitForAbilityIdle()
    self:LogMove(caster.properties.monster_type, registration.id, "Executed at the start of the turn")
    self:LogDecision("MALICE FINISHED", {
        ability = bestCandidate.ability.name,
        result = "executed",
    })
    return true
end

function MonsterAI:ExecuteVillainActionCandidate(candidate)
    ---@type CharacterToken?
    local token = candidate.token
    local ability = candidate.ability
    local action = candidate.action
    self:SetLogContext(token, {
        turn = candidate.context.endedInitiativeId,
        round = candidate.context.round,
        category = self.MoveCategoryLogName(action),
        move = action.id,
    })
    if not self.active or token == nil or not token.valid or token.properties:IsDead() then
        self:LogDecision("VILLAIN ACTION CANCELLED", {
            ability = ability ~= nil and ability.name or nil,
            --the later `or` arms only run once token == nil was false.
            reason = not self.active and "Monster AI stopped"
                or token == nil and "caster is missing"
                or not (token --[[@as CharacterToken]]).valid and "caster is invalid"
                or "caster is dead",
        })
        return false
    end
    if CharacterResource.GetVillainActions() <= 0
        or VillainActionState.HasUsed(token.charid, candidate.slot)
        or not ability:CanAfford(token) then
        self:LogDecision("VILLAIN ACTION CANCELLED", {
            ability = ability.name,
            reason = CharacterResource.GetVillainActions() <= 0 and "no villain action budget remains"
                or VillainActionState.HasUsed(token.charid, candidate.slot) and "this villain action was already used"
                or AIAbilityUnavailableReason(token, ability),
        })
        return false
    end

    self:LogDecision("VILLAIN ACTION SELECTED", {
        ability = ability.name,
        action = self.AbilityActionLogName(ability),
        score = candidate.score,
        plan = self.ScoringPlanLogName(candidate.scoringInfo),
        slot = candidate.slot,
    })

    dmhub.CenterOnToken(token.charid, {smooth = true})
    local subtitle = string.gsub(candidate.slot, "3", "III")
    subtitle = string.gsub(subtitle, "2", "II")
    subtitle = string.gsub(subtitle, "1", "I")
    DramaticBanner.Show{
        tokenid = token.charid,
        text = ability.name or "",
        subtitle = subtitle,
    }
    self.Sleep(DramaticBanner.TimeUntilDone() + 0.2)

    if not self.active or not token.valid or CharacterResource.GetVillainActions() <= 0 then
        return false
    end

    self:SetupCombatants(token, candidate.context.initiativeQueue)
    local ok, err = self:RunWithTokenControl(token, function()
        action.execute(action, self, token, candidate.scoringInfo, ability, candidate.context)
    end)

    if not ok then
        self:LogDecision("VILLAIN ACTION ERROR", {
            ability = ability.name,
            reason = "execution failed: " .. tostring(err),
        })
        self:LogMove(token.properties.monster_type, action.id, "Execution failed: " .. tostring(err))
        return false
    end

    self:WaitForAbilityIdle()
    self:LogMove(token.properties.monster_type, action.id, "Executed villain action")
    self:LogDecision("VILLAIN ACTION FINISHED", {
        ability = ability.name,
        result = "executed",
    })
    return true
end

function MonsterAI:HandleVillainActionWindow(context)
    if not self.active or context == nil or context.initiativeQueue ~= dmhub.initiativeQueue then
        return
    end
    if CharacterResource.GetVillainActions() <= 0 then
        return
    end

    local round = context.round
    if type(round) ~= "number" or round < 1 or round > 3 then
        return
    end
    local slot = string.format("Villain Action %d", round)
    self:SetLogContext(nil, {
        turn = context.endedInitiativeId,
        round = round,
    })
    self:LogDecision("VILLAIN ACTION WINDOW START", {
        slot = slot,
        budget = CharacterResource.GetVillainActions(),
    })

    -- End-turn triggers get a short grace period to start and finish before a
    -- villain action is scored in the same between-turn window.
    self:WaitForAbilityIdle()
    if not self.active or CharacterResource.GetVillainActions() <= 0 then
        return
    end

    self.log.analysis = self:Analysis()
    local candidates = {}
    for _,token in ipairs(dmhub.allTokens) do
        local ownerInitiativeId = InitiativeQueue.GetInitiativeId(token)
        if token.valid and token.properties ~= nil and not token.properties:IsDead()
            and ownerInitiativeId ~= nil and ownerInitiativeId ~= context.endedInitiativeId
            and context.initiativeQueue.entries[ownerInitiativeId] ~= nil
            and context.initiativeQueue:IsEntryPlayer(ownerInitiativeId) == false then
            local abilities = token.properties:GetActivatedAbilities()
            for _,action in pairs(self.villainActions) do
                if self.MoveMatchesMonster(token, action) then
                    local ability = FindAbilityByName(abilities, action.abilities[1])
                    if ability ~= nil and ability:try_get("villainAction") == slot
                        and not VillainActionState.HasUsed(token.charid, slot)
                        and ability:CanAfford(token) then
                        self:SetLogContext(token, {
                            turn = context.endedInitiativeId,
                            round = round,
                        })
                        self:SetupCombatants(token, context.initiativeQueue)
                        local ok, scoringInfo, scoringReason = pcall(
                            action.score, action, self, token, ability, context)
                        if ok and type(scoringInfo) == "number" then
                            scoringInfo = {score = scoringInfo}
                        elseif not ok then
                            self:LogDecision("VILLAIN ACTION ERROR", {
                                category = self.MoveCategoryLogName(action),
                                move = action.id,
                                ability = ability.name,
                                reason = "scoring failed: " .. tostring(scoringInfo),
                            })
                            scoringInfo = nil
                        end

                        if type(scoringInfo) == "table" and type(scoringInfo.score) == "number" then
                            local score = math.max(0, math.min(1, scoringInfo.score))
                            local futureWindows = CountFutureVillainActionWindows(
                                context.initiativeQueue,
                                context.endedInitiativeId,
                                ownerInitiativeId)
                            local windowsIncludingNow = futureWindows + 1
                            local chance = 1 - math.pow(1 - score, 1 / windowsIncludingNow)
                            local roll = math.random()
                            local candidate = {
                                action = action,
                                ability = ability,
                                context = context,
                                forced = futureWindows == 0,
                                ownerInitiativeId = ownerInitiativeId,
                                roll = roll,
                                score = score,
                                scoringInfo = scoringInfo,
                                slot = slot,
                                token = token,
                                chance = chance,
                            }
                            candidates[#candidates+1] = candidate
                            self:LogMove(token.properties.monster_type, action.id, string.format(
                                "Score %.2f; chance %.2f; roll %.2f; %d window(s) including now%s",
                                score, chance, roll, windowsIncludingNow, cond(candidate.forced, "; forced", "")))
                            self:LogDecision("VILLAIN ACTION CANDIDATE", {
                                category = self.MoveCategoryLogName(action),
                                move = action.id,
                                ability = ability.name,
                                action = self.AbilityActionLogName(ability),
                                score = score,
                                plan = self.ScoringPlanLogName(scoringInfo),
                                chance = chance,
                                roll = roll,
                                remainingWindows = windowsIncludingNow,
                                result = candidate.forced and "forced in final window"
                                    or roll <= chance and "passed use roll"
                                    or "failed use roll",
                            })
                        elseif ok then
                            self:LogDecision("VILLAIN ACTION REJECTED", {
                                category = self.MoveCategoryLogName(action),
                                move = action.id,
                                ability = ability.name,
                                reason = scoringReason or "score callback returned no legal plan",
                            })
                        end
                    elseif ability ~= nil and ability:try_get("villainAction") == slot then
                        self:SetLogContext(token, {
                            turn = context.endedInitiativeId,
                            round = round,
                        })
                        self:LogDecision("VILLAIN ACTION REJECTED", {
                            category = self.MoveCategoryLogName(action),
                            move = action.id,
                            ability = ability.name,
                            reason = VillainActionState.HasUsed(token.charid, slot)
                                and "this villain action was already used"
                                or AIAbilityUnavailableReason(token, ability),
                        })
                    end
                end
            end
        end
    end

    local bestCandidate = nil
    local haveForcedCandidate = false
    for _,candidate in ipairs(candidates) do
        if candidate.forced then
            if not haveForcedCandidate or bestCandidate == nil or candidate.score > bestCandidate.score then
                bestCandidate = candidate
            end
            haveForcedCandidate = true
        elseif not haveForcedCandidate and candidate.roll <= candidate.chance then
            local candidateValue = candidate.score + math.random() * 0.05
            if bestCandidate == nil or candidateValue > bestCandidate.selectionValue then
                candidate.selectionValue = candidateValue
                bestCandidate = candidate
            end
        end
    end

    if bestCandidate ~= nil then
        self:ExecuteVillainActionCandidate(bestCandidate)
    else
        self:SetLogContext(nil, {
            turn = context.endedInitiativeId,
            round = round,
        })
        self:LogDecision("VILLAIN ACTION WINDOW FINISHED", {
            result = "no villain action selected",
        })
    end
end

function MonsterAI:FindClosestEnemy()
    local closestEnemy = nil
    local closestDistance = nil
    for _,enemy in ipairs(self.enemyTokens) do
        if self.TokenIsLiveCombatant(enemy) then
            local dist = MonsterAI.TargetDistance(self.token, enemy)
            if closestDistance == nil or dist < closestDistance then
                closestDistance = dist
                closestEnemy = enemy
            end
        end
    end

    return closestEnemy
end

-- Charge targets are empty landing squares, with absolute ground altitudes.
-- The generic straight-line arrow instead treats altitude as a vertical offset.
function MonsterAI:ChargeProbe(movementToken, enemy, distance, range)
    local memo = self:PlanningMemo()
    local origin = movementToken.loc
    local originStr = origin.str
    local cacheKey = table.concat({movementToken.id, originStr, enemy.id,
        enemy.loc.str, distance, range}, "|")
    local cached = memo.chargeProbes[cacheKey]
    if cached ~= nil then
        ProfCount("ChargeProbe cache hits")
        return cached or nil
    end
    ProfCount("ChargeProbe cache misses")

    --Every working no-jump route to a square within range of the enemy,
    --cheapest first. Enemies standing together share landing squares, so the
    --memo's route cache plans each route once.
    if not memo.chargeRoutes then
        memo.chargeRoutes = dmhub.CreateChargeRouteCache()
    end
    local prof = ProfBegin("engine: FindChargeRoutes")
    local routes = movementToken:FindChargeRoutes(enemy, range + movementToken.creatureDimensions.x,
        range, distance, memo.chargeRoutes)
    ProfEnd(prof)

    --The cheapest route whose landing truly reaches the enemy (height counts)
    --and that has not already failed this turn.
    local best = nil
    local failed = self:try_get("_tmp_failedChargePlans", {})
    local holdsPost = self:HoldConstrains(movementToken)
    for _,route in ipairs(routes) do
        local dest = route.dest
        local key = movementToken.id .. "|" .. originStr .. "|" .. dest.str
        if not failed[key] and self:TargetDistanceFromLoc(movementToken, enemy, dest) <= range
            and (not holdsPost or MonsterAI.InHoldZone(movementToken, dest)) then
            best = {dest = dest, chargeDist = dest:DistanceInTiles(origin), cost = route.cost}
            break
        end
    end
    memo.chargeProbes[cacheKey] = best or false
    return best
end

--Planning results that hold until the AI next yields or acts: target filters,
--line of sight and charge routes. The engine resumes the AI at most once a
--frame and nothing else runs while it plans, so an answer found earlier in
--the same frame is still right. The AI's own moves and casts can change the
--board without a yield, so MoveToken and ExecuteAbility clear it too.
function MonsterAI:PlanningMemo()
    local now = dmhub.Time()
    if self:try_get("_tmp_planningMemoTime") ~= now or self:try_get("_tmp_planningMemo") == nil then
        self._tmp_planningMemoTime = now
        self._tmp_planningMemo = {
            filters = {},
            lineOfSight = {},
            chargeProbes = {},
            --a LuaChargeRouteCache, made when the first charge is probed.
            chargeRoutes = false,
            --charid -> true once a path search kept that holder on its post.
            holdActive = {},
        }
    end
    return self._tmp_planningMemo
end

function MonsterAI:InvalidatePlanningMemo()
    self._tmp_planningMemo = nil
end

-- Revalidate immediately before moving, then use the planner's ground-relative
-- segment destination. Never feed an absolute altitude to straight-line Move.
function MonsterAI:ExecuteChargeMovement(token, dest, continueIfActorDies)
    local mover = self:GetMovementToken(token)
    local key = mover.id .. "|" .. mover.loc.str .. "|" .. dest.str
    local distance = mover.properties:CurrentMovementSpeed()
    local previousFailure = self:try_get("_tmp_moveFailure")
    local plan = mover:PlanCharge(dest, {
        chargeDistance = distance, chargeJumpDistance = 0, chargeJumpHeight = 0,
    })
    if plan ~= nil and plan.validCharge and not plan.requiresRoll
        and plan.path.destination.str == dest.str and #plan.chargeSegments == 1
        and not plan.chargeSegments[1].jump then
        local path, survived = self:MoveToken(token, plan.chargeSegments[1].loc, {
            straightline = true, movementType = "walk", moveThroughFriends = false,
            chargeDistance = distance, freeMovement = true, ignoreFalling = false,
        }, continueIfActorDies)
        if not survived then return false, false end
        if path ~= nil and self:MovementTokenIsAtLoc(token, dest) then
            self._tmp_moveFailure = previousFailure
            return true, true
        end
    end
    self._tmp_failedChargePlans = self:try_get("_tmp_failedChargePlans", {})
    self._tmp_failedChargePlans[key] = true
    self:InvalidatePlanningMemo()
    if not continueIfActorDies then
        self._tmp_moveFailure = "charge route failed validation or movement did not reach its landing square"
    end
    return false, true
end

-- Legacy straight-line probe for synthetic leap combos, which execute their own jump.
function MonsterAI:LeapProbe(movementToken, enemy)
    local now = dmhub.Time()
    if self.chargeProbeCacheTime ~= now then
        self.chargeProbeCache = {}
        self.chargeProbeCacheTime = now
    end

    local from = movementToken.loc
    local to = enemy.loc
    local key = string.format("%s|%d,%d,%d,%d|%d,%d,%d,%d", movementToken.id,
        from.x, from.y, from.floor, from.altitude,
        to.x, to.y, to.floor, to.altitude)

    local cached = self.chargeProbeCache[key]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end

    --false (not nil) is stored for "no charge line", so a negative result is
    --remembered rather than re-probed on every lookup.
    ---@type false|{dest: Loc, chargeDist: number}
    local probe = false
    local movementInfo = movementToken:MarkMovementArrow(to, {straightline = true, ignorecreatures = false, moveThroughFriends = true})
    if movementInfo ~= nil then
        local path = movementInfo.path
        --check that the move doesn't make us fall down.
        local altitude = game.currentFloor:GetAltitudeAtLoc(path.origin)
        local falls = false
        for _,step in ipairs(path.steps) do
            local fallDistance = altitude - game.currentFloor:GetAltitudeAtLoc(step)
            if fallDistance > 1 then
                falls = true
                break
            end
        end

        if not falls then
            probe = {
                dest = path.destination,
                chargeDist = path.destination:DistanceInTiles(path.origin),
            }
        end
    end

    self.chargeProbeCache[key] = probe
    if probe == false then
        return nil
    end
    return probe
end

--The reach a strike has at the end of a charge. Dual melee/ranged strikes
--must charge into their melee range.
function MonsterAI.StrikeChargeRange(token, ability, range)
    if ability.meleeAndRanged then
        return ability.meleeVariation:GetRange(token.properties)
    elseif ability:HasKeyword("Melee") and ability:HasKeyword("Ranged") then
        return ability:try_get("meleeRange", 1)
    end
    return range
end

--A Charge moves the creature once, to one landing square, and every target is
--struck from there. FindValidTargetsOfStrike plans a landing per target, so
--two targets of one strike could need two charges (NYQSV5BJ). This returns the
--candidates one plan can hit together: those in reach without charging, or
--those in reach of one shared landing (all given that landing as `charge`).
--The group whose best numTargets score highest wins, ties going to no charge.
--scoreOf(targetInfo) defaults to 1 + edges*0.1. Members come back best first;
--candidates that already agree on where to strike from are returned as given.
function MonsterAI:SelectChargeTargets(token, ability, candidates, numTargets, scoreOf, range)
    numTargets = numTargets or ability:GetNumTargets(token)
    if numTargets <= 1 or #candidates <= 1 then
        return candidates
    end

    local function LandingKey(target)
        return target.charge ~= nil and target.charge.str or ""
    end
    local firstKey = LandingKey(candidates[1])
    local agree = true
    for i=2,#candidates do
        if LandingKey(candidates[i]) ~= firstKey then
            agree = false
            break
        end
    end
    if agree then
        return candidates
    end

    scoreOf = scoreOf or function(target) return 1 + (target.edges or 0)*0.1 end
    range = range or ability:GetRange(token.properties)
    local chargeRange = MonsterAI.StrikeChargeRange(token, ability, range)
    local pierceWalls = token.properties:GetPierceWalls()

    --The first group strikes without charging; the rest each share a landing.
    local groups = {{members = {}}}
    local groupsByLanding = {}
    for _,target in ipairs(candidates) do
        if target.charge == nil then
            groups[1].members[#groups[1].members+1] = target
        elseif groupsByLanding[target.charge.str] == nil then
            local group = {landing = target.charge, members = {}}
            groupsByLanding[target.charge.str] = group
            groups[#groups+1] = group
        end
    end

    --A target planned from elsewhere joins a landing it can be struck from.
    for i=2,#groups do
        local group = groups[i]
        local landing = group.landing
        self:ExecuteWithTheoreticalMovementLoc(token, landing, function()
            for _,target in ipairs(candidates) do
                if LandingKey(target) == landing.str then
                    group.members[#group.members+1] = target
                elseif target.token ~= nil
                    and MonsterAI.TargetDistance(token, target.token) <= chargeRange
                    and token:GetLineOfSight(target.token, pierceWalls) > 0 then
                    local joined = shallow_copy_table(target)
                    joined.charge = landing
                    group.members[#group.members+1] = joined
                end
            end
        end)
    end

    local best, bestScore = nil, nil
    for _,group in ipairs(groups) do
        if #group.members > 0 then
            table.sort(group.members, function(a, b) return scoreOf(a) > scoreOf(b) end)
            local score = 0
            for i=1,math.min(numTargets, #group.members) do
                score = score + scoreOf(group.members[i])
            end
            if bestScore == nil or score > bestScore then
                best, bestScore = group, score
            end
        end
    end
    return best ~= nil and best.members or {}
end

function MonsterAI:FindValidTargetsOfStrike(token, ability, loc, range)

    local meleeAbility = ability:HasKeyword("Melee")
    local rangedAbility = ability:HasKeyword("Ranged")

    --Which enemies the ability may target is decided where the token really
    --stands, before it is moved to loc, so the answer is the same for every
    --square a planner tries. Work it out once per ability, enemy list and spot.
    local memo = self:PlanningMemo()
    local filtersByEnemyList = memo.filters[ability]
    if filtersByEnemyList == nil then
        filtersByEnemyList = {}
        memo.filters[ability] = filtersByEnemyList
    end
    local filtersBySpot = filtersByEnemyList[self.enemyTokens]
    if filtersBySpot == nil then
        filtersBySpot = {}
        filtersByEnemyList[self.enemyTokens] = filtersBySpot
    end
    local spotKey = token.charid .. "@" .. token.loc.str
    local filteredTokens = filtersBySpot[spotKey]
    if filteredTokens == nil then
        filteredTokens = {}
        for i=1,#self.enemyTokens do
            local enemy = self.enemyTokens[i]
            if self.TokenIsLiveCombatant(enemy) then
                local filterProf = ProfBegin("TargetPassesFilter")
                local canTarget = ability:TargetPassesFilter(token, enemy, {})
                ProfEnd(filterProf)
                if canTarget and enemy.properties:HasNamedCondition("Hidden") and ability:HasKeyword("Strike") then
                    local ignoreRange = token.properties:CalculateNamedCustomAttribute("Ignore Hidden Within Range") or 0
                    if ignoreRange <= 0 or MonsterAI.TargetDistance(token, enemy) > ignoreRange then
                        canTarget = false
                    end
                end
                if canTarget then
                    filteredTokens[#filteredTokens+1] = enemy
                end
            end
        end
        filtersBySpot[spotKey] = filteredTokens
    end

    --Line of sight from each square, shared by every ability planned there.
    local sightByLoc = memo.lineOfSight[token]
    if sightByLoc == nil then
        sightByLoc = {}
        memo.lineOfSight[token] = sightByLoc
    end
    local sightFromLoc = sightByLoc[loc]
    if sightFromLoc == nil then
        sightFromLoc = {}
        sightByLoc[loc] = sightFromLoc
    end

    ProfCount("strike target evaluations (tile x enemy)", #filteredTokens)
    local hasCharge = ability:HasKeyword("Charge") or ability.name == "Melee Free Strike"
    range = range or ability:GetRange(token.properties)
    local chargeRange = MonsterAI.StrikeChargeRange(token, ability, range)
    local result = {}
    local movementToken = self:GetMovementToken(token)
    self:ExecuteWithTheoreticalMovementLoc(token, loc, function()
        --A charge is only possible when the enemy is within movement + charge
        --range. The probe's destination always lies on the straight line from
        --here toward the enemy, so the acceptance test below (chargeDist <=
        --maxChargeDistance and targetDist <= chargeRange) implies
        --dist <= maxChargeDistance + chargeRange by the triangle inequality:
        --anything failing this gate could never have been accepted. It is worth
        --gating because probes are expensive and most of them are hopeless --
        --in a measured dwarf encounter 86% of the probes this function fired
        --were aimed at targets too far away to ever charge.
        local maxChargeDistance = ability:try_get("chargeDistanceOverride", movementToken.properties:CurrentMovementSpeed()) or 0
        local chargeReach = maxChargeDistance + chargeRange

        for i=1,#filteredTokens do
            local enemy = filteredTokens[i]
            local dist = MonsterAI.TargetDistance(token, enemy)

            local chargeLoc = nil
            if hasCharge and dist <= chargeReach then
                local probe
                if ability:try_get("chargeDistanceOverride") ~= nil then
                    -- Leap combos use this synthetic strike only to choose a jump target.
                    probe = self:LeapProbe(movementToken, enemy)
                else
                    probe = self:ChargeProbe(movementToken, enemy, maxChargeDistance, chargeRange)
                end
                if probe ~= nil then
                    local targetDist = self:TargetDistanceFromLoc(token, enemy, probe.dest)
                    -- A stopped or zero-length arrow is not a charge. Dual-mode
                    -- strikes must also finish inside their melee variation's range.
                    if probe.chargeDist > 0
                        and probe.chargeDist <= maxChargeDistance
                        and targetDist <= chargeRange then
                        dist = targetDist
                        chargeLoc = probe.dest
                    end
                end
            end

            if dist <= range then
                local los = sightFromLoc[enemy]
                if los == nil then
                    local losProf = ProfBegin("engine: GetLineOfSight")
                    los = token:GetLineOfSight(enemy, token.properties:GetPierceWalls())
                    ProfEnd(losProf)
                    sightFromLoc[enemy] = los
                end
                if los > 0 then

                    local edges = 0
                    local edgeReasons = {}

                    --obstruction.
                    if los < 1 then
                        edges = edges - 1
                        edgeReasons[#edgeReasons+1] = "obstruction -1"
                    end

                    local tokenLoc = chargeLoc or loc

                    for tacticid,tactic in pairs(self.activeTactics) do
                        local tacticProf = ProfBegin("tactic: " .. tacticid)
                        local score = tactic.score(self, token, tokenLoc, enemy, ability) or 0
                        ProfEnd(tacticProf)
                        edges = edges + score
                        if score ~= 0 then
                            edgeReasons[#edgeReasons+1] = string.format("%s %+.2f", tacticid, score)
                        end
                    end

                    --nearby enemies with ranged penalty
                    if rangedAbility and not meleeAbility then
                        local adjacentProf = ProfBegin("ranged adjacency check")
                        local hasNearbyEnemies = false
                        for _,enemyToken in ipairs(self.enemyTokens) do
                            if self:TargetDistanceFromLoc(token, enemyToken, tokenLoc) <= 1 then
                                hasNearbyEnemies = true
                                break
                            end
                        end
                        ProfEnd(adjacentProf)

                        if hasNearbyEnemies then
                            edges = edges - 1
                            edgeReasons[#edgeReasons+1] = "ranged while adjacent -1"
                        end
                    end

                    result[#result+1] = {
                        token = enemy,
                        loc = enemy.loc,
                        charge = chargeLoc,
                        edges = edges,
                        edgeReasons = edgeReasons,
                    }
                end
            end
        end

    end)

    if hasCharge then
        movementToken:ClearMovementArrow()
    end

    table.sort(result, function(a,b) return a.edges > b.edges end)

    return result
end

--Squad reservations ---------------------------------------------------------
--
--A squad plans every member before any of them moves, then they all move at
--once. So no two members end on the same square, and nobody charges through
--a square a squad-mate is heading for, each planned member claims squares here.
--`squares` are where members stand (a charger's start and landing); `lanes`
--are the squares a charge sweeps. Keys are "x,y,floor": altitude is ignored,
--which only errs toward keeping minions apart.

---@class MonsterAISquadReservations
---@field squares table<string, boolean>
---@field lanes table<string, boolean>

---@return MonsterAISquadReservations
function MonsterAI.NewSquadReservations()
    return {squares = {}, lanes = {}}
end

local function SquadSquareKey(x, y, floor)
    return string.format("%d,%d,%s", x, y, tostring(floor))
end

--The squares a token covers, as offsets from its anchor square. They are the
--same wherever it stands, so they are worked out once per member.
function MonsterAI:SquadFootprintOffsets(token)
    local mover = self:GetMovementToken(token)
    local offsets = {}
    for _,occupied in ipairs(mover:LocsOccupyingWhenAt(mover.loc)) do
        offsets[#offsets+1] = {occupied.x - mover.loc.x, occupied.y - mover.loc.y}
    end
    if #offsets == 0 then
        offsets[1] = {0, 0}
    end
    return offsets
end

local function SquadFootprintKeys(offsets, loc, keys)
    keys = keys or {}
    for _,offset in ipairs(offsets) do
        keys[#keys+1] = SquadSquareKey(loc.x + offset[1], loc.y + offset[2], loc.floor)
    end
    return keys
end

--The squares a straight charge from start to landing sweeps, footprint included.
local function SquadChargeLaneKeys(offsets, start, landing)
    local keys = {}
    local dx, dy = landing.x - start.x, landing.y - start.y
    local steps = math.max(1, 4*math.max(math.abs(dx), math.abs(dy)))
    for i=0,steps do
        local x = math.floor(start.x + dx*i/steps + 0.5)
        local y = math.floor(start.y + dy*i/steps + 0.5)
        for _,offset in ipairs(offsets) do
            keys[#keys+1] = SquadSquareKey(x + offset[1], y + offset[2], start.floor)
        end
    end
    return keys
end

local function AnySquadKeyReserved(set, keys)
    for _,key in ipairs(keys) do
        if set[key] then
            return true
        end
    end
    return false
end

--True when a member can end at destLoc, and charge from there to chargeLoc,
--without landing on or charging through a square a squad-mate has claimed.
function MonsterAI.SquadOptionIsFree(reserved, offsets, destLoc, chargeLoc)
    local destKeys = SquadFootprintKeys(offsets, destLoc)
    if AnySquadKeyReserved(reserved.squares, destKeys) or AnySquadKeyReserved(reserved.lanes, destKeys) then
        return false
    end
    if chargeLoc ~= nil then
        if AnySquadKeyReserved(reserved.squares, SquadChargeLaneKeys(offsets, destLoc, chargeLoc)) then
            return false
        end
        if AnySquadKeyReserved(reserved.lanes, SquadFootprintKeys(offsets, chargeLoc)) then
            return false
        end
    end
    return true
end

--Claim a planned member's squares: where it stops and, for a charge, its lane and landing.
function MonsterAI:ReserveSquadOption(reserved, token, option)
    local offsets = self:SquadFootprintOffsets(token)
    for _,key in ipairs(SquadFootprintKeys(offsets, option.loc)) do
        reserved.squares[key] = true
    end
    if option.charge ~= nil then
        for _,key in ipairs(SquadFootprintKeys(offsets, option.charge)) do
            reserved.squares[key] = true
        end
        for _,key in ipairs(SquadChargeLaneKeys(offsets, option.loc, option.charge)) do
            reserved.lanes[key] = true
        end
    end
end

--Each reachable target's cheapest strike option for one squad member. With
--`reserved`, squares and charge lanes squad-mates have claimed are skipped.
---@param reserved? MonsterAISquadReservations
function MonsterAI:FindSquadMemberStrikeOptions(squadMember, ability, reserved)
    squadMember.possibleTargets = {}
    local range = ability:GetRange(squadMember.token.properties)
    local numTargets = ability:GetNumTargets(squadMember.token)
    local offsets = reserved ~= nil and self:SquadFootprintOffsets(squadMember.token) or nil
    for _,info in pairs(squadMember.paths) do
        local destLoc = info.loc

        local targets = {}
        if offsets == nil or self.SquadOptionIsFree(reserved, offsets, destLoc, nil) then
            targets = self:FindValidTargetsOfStrike(squadMember.token, ability, destLoc, range)
        end
        for _,target in ipairs(targets) do
            --a charge from here that would cross a squad-mate's square is left out;
            --other squares can still reach this target.
            local blockedCharge = offsets ~= nil and target.charge ~= nil
                and not self.SquadOptionIsFree(reserved, offsets, destLoc, target.charge)
            local cost = info.cost
            cost = cost - target.edges * 5 --we love to get edges
            if target.charge ~= nil then
                --if charging, prefer to move in line with the charge
                local deltaMove = {x = target.charge.x - squadMember.token.loc.x, y = target.charge.y - squadMember.token.loc.y}
                local deltaCharge = {x = target.token.loc.x - target.charge.x, y = target.token.loc.y - target.charge.y}
                local dotProduct = deltaMove.x * deltaCharge.x + deltaMove.y * deltaCharge.y
                cost = cost - dotProduct*0.5
            end
            local existing = squadMember.possibleTargets[target.token.charid]
            if blockedCharge then
                --skipped
            elseif existing == nil then
                squadMember.possibleTargets[target.token.charid] = {
                    token = target.token,
                    charge = target.charge,
                    loc = destLoc,
                    cost = cost,
                }
            elseif existing.cost > cost then
                existing.loc = destLoc
                existing.cost = cost
                existing.charge = target.charge
            end
        end
    end

    return squadMember.possibleTargets
end

function MonsterAI:ExecuteSquadStrike(ability)
    local abilityName = ability.name
    local monsterType = self.token.properties:try_get("monster_type", "Minion")
    self:LogDecision("MOVE SELECTED", {
        category = "Main Action",
        move = "Minion Signature Ability",
        ability = abilityName,
        action = self.AbilityActionLogName(ability),
        result = string.format("coordinating %d minion(s)", #self.squadMembers),
    })
    local logMessage = nil
    local rays = {}
    local targetPairs = {}
    local assignedTargets = {}
    local assignedTargetIds = {}
    local advanced = false

    local function AffordableMemberAbility(memberToken)
        if not self.TokenIsLiveCombatant(memberToken) then
            return nil
        end
        local prof = ProfBegin("squad: AffordableMemberAbility")
        local memberAbility = FindAbilityByName(memberToken.properties:GetActivatedAbilities(), abilityName)
        if memberAbility ~= nil and memberAbility:CanAfford(memberToken) then
            ProfEnd(prof)
            return memberAbility
        end
        ProfEnd(prof)
    end

    --Reactions to a later member's movement can kill an attacker that already
    --has a pairing. Keep the shared plan limited to creatures still on the map.
    local function RefreshAssignments()
        local livePairs = {}
        local liveAssignedTargets = {}
        assignedTargetIds = {}
        for _,pair in ipairs(targetPairs) do
            local attacker = dmhub.GetTokenById(pair.a)
            local target = dmhub.GetTokenById(pair.b)
            if AffordableMemberAbility(attacker) ~= nil and self.TokenIsLiveCombatant(target) then
                --TokenIsLiveCombatant is false for a nil token.
                ---@cast target -nil
                livePairs[#livePairs+1] = pair
                liveAssignedTargets[pair.b] = (liveAssignedTargets[pair.b] or 0) + 1
                assignedTargetIds[#assignedTargetIds+1] = target.charid
            end
        end
        targetPairs = livePairs
        assignedTargets = liveAssignedTargets
    end

    --Choose where one member moves and whom it strikes, against the board as it
    --stands before anyone moves. Squad-mates planned earlier this round have
    --claimed their squares in `reserved`, and their pairs already count toward
    --the target limit. Never yields. Returns a plan, or nil and the reason:
    --"assigned" (already in the volley), "unable", "capped" or "unreachable".
    local function PlanMember(squadMember, reserved)
        local planProf = ProfBegin("squad: plan member")
        local memberToken = squadMember.token
        local memberAbility = AffordableMemberAbility(memberToken)
        for _,pair in ipairs(targetPairs) do
            if pair.a == memberToken.charid then
                ProfEnd(planProf)
                return nil, "assigned"
            end
        end
        if memberAbility == nil then
            ProfEnd(planProf)
            self:LogDecision("MINION ASSIGNMENT CANCELLED", {
                actor = self.TokenLogName(memberToken),
                actorId = memberToken ~= nil and memberToken.charid or nil,
                category = "Main Action",
                move = "Minion Signature Ability",
                ability = abilityName,
                reason = "squad member is dead or cannot afford the signature ability",
                result = "continuing with eligible squad members",
            })
            return nil, "unable"
        end

        local memberName = self.TokenLogName(memberToken)
        local memberId = memberToken.charid
        local queue = dmhub.initiativeQueue
        if queue ~= nil and not queue.hidden then
            --A reaction can remove cached allies while the squad is moving.
            --Rebuild the lists before planning.
            self:RefreshCombatants(queue, memberToken)
        end
        --Extra main actions do not restore movement already spent this turn.
        squadMember.paths = self:CalculateRemainingMovementPaths(memberToken)

        local options = self:FindSquadMemberStrikeOptions(squadMember, memberAbility, reserved)
        local bestOption = nil
        local bestScore = nil
        local targetLimitReached = false
        for _,option in pairs(options) do
            local assignedCount = assignedTargets[option.token.charid] or 0
            --Use the same repeat-target rule as manual squad targeting,
            --including abilities and creatures that waive the minion limit.
            if assignedCount > 0 and not memberAbility:CanTargetAdditionalTimes(
                memberToken, {targetPairs = targetPairs}, assignedTargetIds, option.token) then
                targetLimitReached = true
            else
                local score = option.cost + 10000*assignedCount
                if bestOption == nil or score < bestScore then
                    bestOption = option
                    bestScore = score
                end
            end
        end

        if bestOption == nil then
            ProfEnd(planProf)
            self:LogDecision("MINION ASSIGNMENT REJECTED", {
                actor = memberName,
                actorId = memberId,
                category = "Main Action",
                move = "Minion Signature Ability",
                ability = abilityName,
                reason = targetLimitReached and "all reachable targets have reached the squad target limit"
                    or "no legal target can be reached",
            })
            return nil, targetLimitReached and "capped" or "unreachable"
        end

        self:LogDecision("MINION ASSIGNMENT", {
            actor = memberName,
            actorId = memberId,
            category = "Main Action",
            move = "Minion Signature Ability",
            ability = abilityName,
            from = self.LocLogName(memberToken.loc),
            to = self.LocLogName(bestOption.loc),
            targets = self.TargetsLogName({{token = bestOption.token}}),
            plan = bestOption.charge ~= nil
                and string.format("charge through %s", self.LocLogName(bestOption.charge))
                or "strike from destination",
        })

        --Hold the square and the target slot now, so members planned after
        --this one go elsewhere. A pair that fails after movement is dropped.
        self:ReserveSquadOption(reserved, memberToken, bestOption)
        local pair = {a = memberId, b = bestOption.token.charid}
        targetPairs[#targetPairs+1] = pair
        assignedTargets[pair.b] = (assignedTargets[pair.b] or 0) + 1
        assignedTargetIds[#assignedTargetIds+1] = pair.b
        ProfEnd(planProf)
        return {
            token = memberToken,
            ability = memberAbility,
            option = bestOption,
            pair = pair,
            survived = true,
        }
    end

    --Every planned member moves together, each a beat after the last. Chargers
    --first move to where their charge starts, then all shout and charge together.
    local function MovePlans(plans)
        local moves = {}
        for _,plan in ipairs(plans) do
            --a member already in place (a sniper, or a charger starting where it
            --stands) has no move to make and would only delay the stagger.
            if not self:MovementTokenIsAtLoc(plan.token, plan.option.loc) then
                moves[#moves+1] = function()
                    local _, survived = self:MoveToken(plan.token, plan.option.loc,
                        {maxCost = 10000, ignoreFalling = false}, true)
                    plan.survived = survived
                end
            end
        end
        if #moves > 0 then
            self:RunConcurrently(moves, self.squadMoveStagger)
            self.Sleep(0.4)
        end

        local charges = {}
        for _,plan in ipairs(plans) do
            if plan.survived and plan.option.charge ~= nil and self.TokenIsLiveCombatant(plan.token) then
                self:SpeakNow(plan.token, "Charge!")
                charges[#charges+1] = function()
                    --A Charge's movement is part of the ability, not the creature's
                    --move action, so it does not consume the remaining move budget.
                    local reached, survived = self:ExecuteChargeMovement(plan.token, plan.option.charge, true)
                    plan.survived = survived and reached
                end
            end
        end
        if #charges > 0 then
            self.Sleep(0.3)
            self:RunConcurrently(charges, self.squadMoveStagger)
            self.Sleep(0.6)
        end
    end

    --After movement, keep the member's pair only if it can still make the strike.
    local function ConfirmPlan(plan)
        local memberToken = plan.token
        local targetToken = plan.option.token
        local rejectionReason = nil
        local distance, range, lineOfSight
        if not plan.survived or not self.TokenIsLiveCombatant(memberToken) then
            rejectionReason = "attacker died or charge failed while movement resolved"
        elseif not self.TokenIsLiveCombatant(targetToken) then
            rejectionReason = "target is no longer a live combatant"
        else
            distance = MonsterAI.TargetDistance(memberToken, targetToken)
            range = plan.ability:GetRange(memberToken.properties)
            lineOfSight = memberToken:GetLineOfSight(targetToken, memberToken.properties:GetPierceWalls())
            if distance > range then
                rejectionReason = "target is out of range after movement"
            elseif lineOfSight <= 0 then
                rejectionReason = "target has no line of sight after movement"
            end
        end

        if rejectionReason == nil then
            dmhub.Schedule(0.8, function()
                if self.TokenIsLiveCombatant(memberToken)
                    and self.TokenIsLiveCombatant(targetToken) then
                    rays[#rays+1] = dmhub.MarkLineOfSight(memberToken, targetToken,
                        memberToken.properties:GetPierceWalls())
                end
            end)
            return
        end

        for i,pair in ipairs(targetPairs) do
            if pair == plan.pair then
                table.remove(targetPairs, i)
                break
            end
        end
        RefreshAssignments()
        self:LogDecision("MINION ASSIGNMENT CANCELLED", {
            actor = self.TokenLogName(memberToken),
            actorId = memberToken.charid,
            category = "Main Action",
            move = "Minion Signature Ability",
            ability = abilityName,
            targets = self.TargetsLogName({{token = targetToken}}),
            reason = rejectionReason,
            from = self.LocLogName(memberToken.loc),
            to = self.LocLogName(plan.option.loc),
            distance = distance,
            range = range,
            lineOfSight = lineOfSight,
            result = "continuing with surviving squad members",
        })
    end

    --Round 1 plans the whole squad, calls the attack, and moves everyone at once.
    --Round 2 gives members that advanced, or whose plan failed (or whose target
    --slot a fallen squad-mate freed), a second chance to join the same volley
    --rather than save their action for a later one.
    local announced = false
    for round=1,2 do
        RefreshAssignments()
        local reserved = self.NewSquadReservations()
        local plans = {}
        local advancers = {}
        for _,squadMember in ipairs(self.squadMembers) do
            local plan, outcome = PlanMember(squadMember, reserved)
            if plan ~= nil then
                plans[#plans+1] = plan
            elseif outcome == "unreachable" and round == 1 then
                advancers[#advancers+1] = squadMember.token
            end
        end

        --The whole squad's plan is shown before anyone moves; members planned
        --again in round 2 (after the squad moved) go without another pause.
        if round == 1 and (#plans > 0 or #advancers > 0) and self.PlanPreviewsOn() then
            if not self:AwaitPlanPreview(self:BuildSquadPreview(plans, advancers, ability)) then
                return false
            end
        end

        if #plans > 0 then
            if not announced then
                announced = true
                self:AnnounceSquadStrike(plans, ability)
            end
            MovePlans(plans)
            for _,plan in ipairs(plans) do
                ConfirmPlan(plan)
            end
        end

        for _,memberToken in ipairs(advancers) do
            advanced = self:ExecuteAdvanceFallback(memberToken, true) or advanced
        end
    end
    RefreshAssignments()
    local casterToken = nil
    local castAbility = nil
    for _,pair in ipairs(targetPairs) do
        local candidate = dmhub.GetTokenById(pair.a)
        if self.TokenIsLiveCombatant(candidate) then
            --TokenIsLiveCombatant is false for a nil token.
            ---@cast candidate -nil
            castAbility = FindAbilityByName(candidate.properties:GetActivatedAbilities(), abilityName)
            if castAbility ~= nil and castAbility:CanAfford(candidate) then
                casterToken = candidate
                break
            end
        end
    end

    local executed = false
    if #targetPairs > 0 and casterToken ~= nil then
        --casterToken is only set once castAbility was found non-nil, and the loop then breaks.
        ---@cast castAbility -nil
        --The battle cry was called before the squad moved (AnnounceSquadStrike).
        local symbols = {
            targetPairs = targetPairs,
        }

        self.Sleep(1)

        local targetsAdded = {}
        local targets = {}
        for _,pair in ipairs(targetPairs) do
            if not targetsAdded[pair.b] then
                local targetToken = dmhub.GetTokenById(pair.b)
                targets[#targets+1] = { token = targetToken }
                targetsAdded[pair.b] = true
            end
        end

        self:ExecuteAbility(casterToken, castAbility, targets, {symbols = symbols, sleep = 2.0})
        executed = true
        logMessage = string.format("Executed on %d targets", #targets)
    elseif #targetPairs > 0 then
        logMessage = "No surviving attacker could cast the signature ability"
    else
        logMessage = "Could not find any targets"
    end

    for _,ray in ipairs(rays) do
        ray:DestroyLineOfSight()
    end

    if logMessage then
        self:LogMove(monsterType, "Minion Signature Ability", logMessage)
    end

    local finalTargets = {}
    for _,pair in ipairs(targetPairs) do
        finalTargets[#finalTargets+1] = {token = dmhub.GetTokenById(pair.b)}
    end
    self:LogDecision("MOVE FINISHED", {
        category = "Main Action",
        move = "Minion Signature Ability",
        ability = abilityName,
        targets = self.TargetsLogName(finalTargets),
        result = logMessage,
    })

    return executed or advanced
end

--- @param token CharacterToken
--- @param ability ActivatedAbility
--- @param scorefn? fun(targetToken: CharacterToken, edges: number|nil): number Value of striking targetToken with this many edges.
function MonsterAI:FindBestMoveToUseStrike(token, ability, scorefn)
    if scorefn ~= nil then
        --Memoise per target AND edge count: a target's edges change with the
        --square the monster strikes from, so the score can too.
        local scoreCache = {}
        local scoreInternal = scorefn
        scorefn = function(tok, edges)
            local key = tok.charid .. ":" .. tostring(edges)
            local score = scoreCache[key]
            if score == nil then
                score = scoreInternal(tok, edges)
                scoreCache[key] = score
            end
            return score
        end
    end
    local range = ability:GetRange(token.properties)
    local numTargets = ability:GetNumTargets(token)
    local bestScore = 0
    local bestMove = nil
    local bestTargets = nil
    local bestCost = nil
    for _,info in pairs(self.paths) do
        local destLoc = info.loc

        local targets = self:FindValidTargetsOfStrike(token, ability, destLoc, range)
        targets = self:SelectChargeTargets(token, ability, targets, numTargets,
            scorefn ~= nil and function(target) return scorefn(target.token, target.edges) end or nil, range)

        local score = math.min(numTargets, #targets)
        if scorefn ~= nil then
            score = 0
            table.sort(targets, function(a,b)
                return scorefn(a.token, a.edges) > scorefn(b.token, b.edges)
            end)
            for i=1,math.min(numTargets, #targets) do
                score = score + scorefn(targets[i].token, targets[i].edges)
            end
        else
            local maxEdges = nil
            for _,target in ipairs(targets) do
                if maxEdges == nil or target.edges > maxEdges then
                    maxEdges = target.edges
                end
            end

            score = score + (maxEdges or 0)*0.1
        end

        score = score - info.cost*0.001

        if score > bestScore then
            bestScore = score
            bestMove = destLoc
            bestTargets = targets
            bestCost = info.cost
        end
    end

    if bestMove ~= nil then
        local selectedTargets = {}
        for i=1,math.min(numTargets, #(bestTargets or {})) do
            --the loop runs zero times when bestTargets is nil.
            ---@cast bestTargets -nil
            selectedTargets[#selectedTargets+1] = bestTargets[i]
        end
        --Kept for the plan preview, which must show these targets rather than
        --guess its own (see FindAndExecuteMove).
        local strikePlans = self:try_get("_tmp_strikePlans")
        if strikePlans ~= nil then
            strikePlans[ability] = strikePlans[ability] or {}
            strikePlans[ability][bestMove.str] = selectedTargets
        end
        self:LogDecision("TARGET PLAN", {
            ability = ability.name,
            action = self.AbilityActionLogName(ability),
            score = bestScore,
            plan = string.format("move-to %s; movement-cost=%s; %s",
                self.LocLogName(bestMove), tostring(bestCost or 0),
                self.TargetScoresLogName(selectedTargets)),
            targets = self.TargetsLogName(selectedTargets),
            result = "legal strike plan",
        })
    else
        self:LogDecision("TARGET PLAN REJECTED", {
            ability = ability.name,
            action = self.AbilityActionLogName(ability),
            reason = "no reachable location has a legal strike target",
        })
    end

    return bestMove, bestScore
end

function MonsterAI:FindBestMoveToUseBurst(token, ability, scorefn)
    scorefn = scorefn or function() return 1 end
    local range = ability:GetRange(token.properties)
    local bestScore = nil
    local bestCost = nil
    local bestMove = nil
    local bestTargets = nil
    local allTokens = dmhub.allTokens
    local symbols = {mode = 1}
    for _,info in pairs(self.paths) do
        local score = 0
        local destLoc = info.loc
        local targets = {}

        self:ExecuteWithTheoreticalMovementLoc(token, destLoc, function()
            for _,targetToken in ipairs(allTokens) do
                if targetToken.valid and MonsterAI.TargetDistance(targetToken, token) <= range and ability:TargetPassesFilter(token, targetToken, symbols) then
                    score = score + scorefn(targetToken)
                    targets[#targets+1] = {token = targetToken}
                end
            end
        end)

        local cost = info.cost or 0
        if bestScore == nil or score > bestScore or (score == bestScore and cost < bestCost) then
            bestScore = score
            bestCost = cost
            bestMove = destLoc
            bestTargets = targets
        end
    end


    if bestMove ~= nil then
        self:LogDecision("TARGET PLAN", {
            ability = ability.name,
            action = self.AbilityActionLogName(ability),
            score = bestScore,
            plan = string.format("move-to %s; movement-cost=%s; burst",
                self.LocLogName(bestMove), tostring(bestCost or 0)),
            targets = self.TargetsLogName(bestTargets),
            result = "best burst plan",
        })
    else
        self:LogDecision("TARGET PLAN REJECTED", {
            ability = ability.name,
            action = self.AbilityActionLogName(ability),
            reason = "no reachable burst location",
        })
    end

    return bestMove, bestScore
end

-- Find the highest-scoring line area from a set of candidate endpoints.
-- Candidates can be tokens, locations, or tables containing targetLoc and an
-- optional locOverride. The latter supports placed lines whose origin differs
-- from the caster without making their candidate-generation rules generic.
function MonsterAI:FindBestLinePlan(token, ability, options)
    options = options or {}
    local candidates = options.candidates or self.enemyTokens or {}
    local scorefn = options.scorefn or function(target, candidate, symbols) return 1 end
    local symbols = options.symbols or {}
    local checklos = options.checklos
    if checklos == nil then
        checklos = true
    end

    local range = options.range or ability:GetRange(token.properties, symbols)
    local radius = options.radius or ability:GetRadius(token.properties, symbols)
    local best = nil

    for _,candidate in ipairs(candidates) do
        local targetLoc = candidate.targetLoc or candidate.loc or candidate
        local locOverride = candidate.locOverride or options.locOverride
        if targetLoc ~= nil and targetLoc.valid and targetLoc.isOnMap then
            local originLoc = locOverride or token.loc
            local area = dmhub.CalculateShape{
                shape = "line",
                targetPoint = token:PosAtLoc(targetLoc),
                token = token,
                range = range,
                radius = radius,
                locOverride = locOverride,
                checklos = checklos,
                altitude = originLoc.altitude * dmhub.unitsPerSquare,
            }

            local areaSymbols = {}
            for key,value in pairs(symbols) do
                areaSymbols[key] = value
            end
            areaSymbols.targetArea = area

            local targets = {}
            local score = 0
            for _,target in pairs(dmhub.tokenInfo.TokensInShape(area)) do
                if target.valid and ability:TargetPassesFilter(token, target, areaSymbols) then
                    targets[#targets+1] = {token = target}
                    score = score + (scorefn(target, candidate, areaSymbols) or 0)
                end
            end

            if best == nil or score > best.score then
                best = {
                    targetLoc = targetLoc,
                    locOverride = locOverride,
                    targets = targets,
                    numTargets = #targets,
                    score = score,
                    candidate = candidate,
                }
            end
        end
    end

    if options.logPlan ~= false and best ~= nil then
        self:LogDecision("TARGET PLAN", {
            ability = ability.name,
            action = self.AbilityActionLogName(ability),
            score = best.score,
            plan = string.format("line aimed at %s", self.LocLogName(best.targetLoc)),
            targets = self.TargetsLogName(best.targets),
            result = "best line plan",
        })
    elseif options.logPlan ~= false then
        self:LogDecision("TARGET PLAN REJECTED", {
            ability = ability.name,
            action = self.AbilityActionLogName(ability),
            reason = "no candidate line produced a legal area",
        })
    end

    return best
end

-- Synthesized moves are intentionally conservative. They are only considered
-- for fully automated offensive abilities whose targeting can be planned by
-- the generic AI without asking a player to make a semantic choice.
local g_synthesizedAbilityMinimumConfidence = 0.90
local g_synthesizedAbilitySupportedTargets = {
    target = true,
    all = true,
    cube = true,
    line = true,
}
local g_synthesizedAbilityExcludedCategories = {
    Malice = true,
    ["Malice Ability"] = true,
    Trigger = true,
    ["Triggered Ability"] = true,
    ["Villain Action"] = true,
}

local function SynthesizedAbilityKey(ability)
    return ability:GetID() or ability.name
end

local function SynthesizedMoveId(ability)
    return string.format("Synthesized: %s", ability.name)
end

local function TextDescribesDamage(text)
    if type(text) ~= "string" then
        return false
    end
    return string.find(string.lower(text), "%f[%a]damage%f[%A]") ~= nil
end

local function ResolveInvokedAbility(behavior)
    local abilityType = behavior:try_get("abilityType", "custom")
    if abilityType == "custom" then
        return behavior:try_get("customAbility")
    elseif abilityType == "standard" then
        local abilities = dmhub.GetTable("standardAbilities") or {}
        return abilities[behavior:try_get("standardAbility", "")]
    end
    return nil
end

local function BehaviorAppliesHarmToTargets(behavior)
    local applyto = behavior:try_get("applyto", "targets")
    return applyto == "targets"
        or applyto == "enemies"
        or applyto == "original_targets"
        or applyto == "hit_targets"
        or applyto == "failed_save_targets"
        or applyto == "passed_save_targets"
end

local function SynthesizedHarmConfidence(ability, visited)
    visited = visited or {}
    if visited[ability] then
        return nil
    end
    visited[ability] = true

    if ability:HasKeyword("Strike") then
        return 0.99, "Strike keyword"
    end

    local bestConfidence = nil
    local bestReason = nil
    for _,behavior in ipairs(ability:try_get("behaviors", {})) do
        local typeName = behavior.typeName
        local confidence = nil
        local reason = nil
        if typeName == "ActivatedAbilityDamageBehavior"
            and BehaviorAppliesHarmToTargets(behavior) then
            confidence = 0.97
            reason = "damage behavior"
        elseif typeName == "ActivatedAbilityPowerRollBehavior"
            and BehaviorAppliesHarmToTargets(behavior) then
            for _,tier in ipairs(behavior:try_get("tiers", {})) do
                if TextDescribesDamage(tier) then
                    confidence = 0.95
                    reason = "damaging power roll"
                    break
                end
            end
        elseif typeName == "ActivatedAbilityDrawSteelCommandBehavior"
            and BehaviorAppliesHarmToTargets(behavior)
            and TextDescribesDamage(behavior:try_get("rule", "")) then
            confidence = 0.93
            reason = "damage command"
        elseif typeName == "ActivatedAbilityInvokeAbilityBehavior" then
            local invokedAbility = ResolveInvokedAbility(behavior)
            local targeting = behavior:try_get("targeting", "prompt")
            if invokedAbility ~= nil and targeting ~= "self" then
                local invokedConfidence = SynthesizedHarmConfidence(invokedAbility, visited)
                if invokedConfidence ~= nil then
                    confidence = invokedConfidence - 0.03
                    reason = "damaging invoked ability"
                end
            end
        end

        if confidence ~= nil and (bestConfidence == nil or confidence > bestConfidence) then
            bestConfidence = confidence
            bestReason = reason
        end
    end

    return bestConfidence, bestReason
end

function MonsterAI:SynthesizedAbilityPromptsAreHandled(ability, visited)
    visited = visited or {}
    if visited[ability] then
        return true
    end
    visited[ability] = true

    if ability:RequiresPromptWhenCast() then
        return false, "requires a cast-time choice"
    end

    for _,behavior in ipairs(ability:try_get("behaviors", {})) do
        if behavior.typeName == "ActivatedAbilityInvokeAbilityBehavior" then
            if behavior:try_get("promptWhenResolving", false) then
                return false, "requires choosing invocation order"
            end
            if behavior:try_get("runOnController", false) then
                return false, "delegates an invoked ability to another controller"
            end

            local abilityType = behavior:try_get("abilityType", "custom")
            if abilityType == "named" or abilityType == "chooseClassAbility" then
                return false, "selects an invoked ability dynamically"
            end

            local invokedAbility = ResolveInvokedAbility(behavior)
            if invokedAbility == nil then
                return false, "has an unresolved invoked ability"
            end

            local targeting = behavior:try_get("targeting", "prompt")
            if targeting == "prompt" or targeting == "prompt_inherit" then
                local prompt = self.prompts[invokedAbility.name]
                if prompt == nil then
                    return false, string.format("has no AI prompt handler for %s", invokedAbility.name)
                end
            end

            --A handler flagged resolvesInvokedAbility carries out the invoked
            --ability itself, so the invoked ability's own prompts never come up.
            local resolvedByPrompt = false
            if targeting == "prompt" or targeting == "prompt_inherit" then
                resolvedByPrompt = self.prompts[invokedAbility.name].resolvesInvokedAbility == true
            end
            if not resolvedByPrompt then
                local handled, reason = self:SynthesizedAbilityPromptsAreHandled(invokedAbility, visited)
                if not handled then
                    return false, reason
                end
            end
        end
    end

    return true
end


--- options.ignoreImplementation skips the Gold-automation check, so the
--- bestiary assessment (MonsterAISupport.lua) can tell when automation is the
--- only thing keeping an ability from the generic AI.
--- @param options? {ignoreImplementation: boolean}
function MonsterAI:GetSynthesizedAbilityProfile(token, ability, options)
    local ignoreImplementation = options ~= nil and options.ignoreImplementation
    if not ignoreImplementation
        and ability:try_get("implementation", gui.ImplementationStatus.Unimplemented) < gui.ImplementationStatus.Gold then
        return nil, "is not fully automated"
    end
    if #ability:try_get("behaviors", {}) == 0 then
        return nil, "has no automated behaviors"
    end
    if not ability:IsDirectlyCastable() then
        return nil, "must synthesize its own sub-abilities"
    end
    if not g_synthesizedAbilitySupportedTargets[ability.targetType] then
        return nil, string.format("uses unsupported target type %s", tostring(ability.targetType))
    end
    if g_synthesizedAbilityExcludedCategories[ability.categorization] then
        return nil, string.format("is a %s", ability.categorization)
    end
    if ability:try_get("villainAction") ~= nil then
        return nil, "is a villain action"
    end

    local actionResource = ability:ActionResource()
    if actionResource == CharacterResource.triggerResourceId then
        return nil, "uses the triggered-action resource"
    elseif actionResource == CharacterResource.villainActionId then
        return nil, "uses the villain-action resource"
    end

    local promptsHandled, promptReason = self:SynthesizedAbilityPromptsAreHandled(ability)
    if not promptsHandled then
        return nil, promptReason
    end

    local confidence, reason = SynthesizedHarmConfidence(ability)
    if confidence == nil then
        return nil, "has no confidently harmful effect"
    end
    if ability.targetType ~= "target" then
        confidence = confidence - 0.02
    end
    if confidence < g_synthesizedAbilityMinimumConfidence then
        return nil, string.format("effect confidence %.2f is below threshold", confidence)
    end

    return {
        actionResource = actionResource,
        confidence = confidence,
        reason = reason,
        targetType = ability.targetType,
    }
end


function MonsterAI:GetClaimedAbilityNames(token)
    local result = {}
    for _,move in pairs(self.moves) do
        -- Disabled custom moves still claim their abilities. Otherwise disabling
        -- a handcrafted behavior would unexpectedly turn the ability back on
        -- through the fallback.
        if self.MoveMatchesMonster(token, move, true) then
            for _,abilityName in ipairs(move.abilities or {}) do
                result[abilityName] = true
            end
        end
    end
    return result
end


--The default target scores lean slightly toward the enemy with the most
--Stamina left, so monsters spread damage instead of focusing down a hero who
--is nearly out. It is current Stamina (temporary Stamina included), not a
--fraction of the maximum, so a full-health tank outranks a full-health
--squishy hero. The bonus grows targetStaminaBiasPerPoint per Stamina and stops
--at targetStaminaBiasMax, which is two edges' worth.
MonsterAI.targetStaminaBiasPerPoint = 0.004
MonsterAI.targetStaminaBiasMax = 0.2

---@param target CharacterToken
---@return number
function MonsterAI.TargetStaminaBias(target)
    if target.isObject or target.properties == nil then
        return 0
    end
    local stamina = math.max(0, target.properties:CurrentHitpoints())
    return math.min(MonsterAI.targetStaminaBiasMax,
        stamina*MonsterAI.targetStaminaBiasPerPoint)
end

local function SynthesizedDefaultTargetScore(targetInfo)
    local target = targetInfo.token
    if target.isObject or target.properties == nil then
        return 0.1
    end
    return 1 + (targetInfo.edges or 0)*0.1 + MonsterAI.TargetStaminaBias(target)
end

function MonsterAI:FindSynthesizedTargetPlan(token, ability)
    local range = ability:GetRange(token.properties)
    local numTargets = ability:GetNumTargets(token)
    local best = nil

    for _,pathInfo in pairs(self.paths or {}) do
        local candidates = {}
        local valid = self:FindValidTargetsOfStrike(token, ability, pathInfo.loc, range)
        valid = self:SelectChargeTargets(token, ability, valid, numTargets, SynthesizedDefaultTargetScore, range)
        for _,targetInfo in ipairs(valid) do
            candidates[#candidates+1] = {
                info = targetInfo,
                score = SynthesizedDefaultTargetScore(targetInfo),
            }
        end
        table.sort(candidates, function(a, b)
            return a.score > b.score
        end)

        local targets = {}
        local utility = 0
        for i=1,math.min(numTargets, #candidates) do
            targets[#targets+1] = candidates[i].info
            utility = utility + candidates[i].score
        end
        if #targets > 0 then
            utility = utility - (pathInfo.cost or 0)*0.001
            if best == nil or utility > best.utility then
                best = {
                    loc = pathInfo.loc,
                    targets = targets,
                    enemies = #targets,
                    utility = utility,
                }
            end
        end
    end

    return best
end


local function IsLiveSynthesizedTarget(target)
    return target ~= nil and target.valid and target.properties ~= nil
        and (target.isObject or not target.properties:IsDead())
end

local function CountSynthesizedTargets(token, targets)
    local enemies = 0
    local allies = 0
    for _,targetInfo in ipairs(targets or {}) do
        local target = targetInfo.token
        if IsLiveSynthesizedTarget(target) and not target.isObject then
            if target:IsFriend(token) then
                allies = allies + 1
            else
                enemies = enemies + 1
            end
        end
    end
    return enemies, allies
end

function MonsterAI:FindSynthesizedBurstPlan(token, ability)
    local range = ability:GetRange(token.properties)
    local symbols = {mode = 1}
    local best = nil

    for _,pathInfo in pairs(self.paths or {}) do
        local targets = {}
        self:ExecuteWithTheoreticalMovementLoc(token, pathInfo.loc, function()
            for _,target in ipairs(dmhub.allTokens) do
                if IsLiveSynthesizedTarget(target)
                    and MonsterAI.TargetDistance(target, token) <= range
                    and ability:TargetPassesFilter(token, target, symbols) then
                    targets[#targets+1] = {token = target}
                end
            end
        end)

        local enemies, allies = CountSynthesizedTargets(token, targets)
        local utility = enemies - allies*3 - (pathInfo.cost or 0)*0.001
        if enemies > 0 and allies == 0
            and (best == nil or utility > best.utility) then
            best = {
                loc = pathInfo.loc,
                targets = targets,
                enemies = enemies,
                allies = allies,
                utility = utility,
            }
        end
    end

    return best
end

function MonsterAI:SynthesizedBurstTargetsAtCurrentLoc(token, ability)
    local range = ability:GetRange(token.properties)
    local symbols = {mode = 1}
    local targets = {}
    for _,target in ipairs(dmhub.allTokens) do
        if IsLiveSynthesizedTarget(target)
            and MonsterAI.TargetDistance(target, token) <= range
            and ability:TargetPassesFilter(token, target, symbols) then
            targets[#targets+1] = {token = target}
        end
    end
    local enemies, allies = CountSynthesizedTargets(token, targets)
    return targets, enemies, allies
end


local function BuildSynthesizedArea(token, ability, shape, targetLoc, locOverride)
    local originLoc = locOverride or token.loc
    return dmhub.CalculateShape{
        shape = shape,
        targetPoint = token:PosAtLoc(targetLoc),
        token = token,
        range = ability:GetRange(token.properties),
        radius = ability:GetRadius(token.properties),
        locOverride = locOverride,
        checklos = shape == "line",
        altitude = cond(shape == "cube", targetLoc.altitude, originLoc.altitude) * dmhub.unitsPerSquare,
    }
end

function MonsterAI:SynthesizedTargetsInArea(token, ability, area)
    local targets = {}
    local symbols = {mode = 1, targetArea = area}
    for _,target in pairs(dmhub.tokenInfo.TokensInShape(area)) do
        if IsLiveSynthesizedTarget(target)
            and ability:TargetPassesFilter(token, target, symbols) then
            targets[#targets+1] = {token = target}
        end
    end
    local enemies, allies = CountSynthesizedTargets(token, targets)
    return targets, enemies, allies
end

function MonsterAI:FindSynthesizedCubePlan(token, ability)
    local best = nil
    local range = ability:GetRange(token.properties)
    local pierceWalls = token.properties:GetPierceWalls()

    for _,pathInfo in pairs(self.paths or {}) do
        local checked = {}
        self:ExecuteWithTheoreticalMovementLoc(token, pathInfo.loc, function()
            for _,enemy in ipairs(self.enemyTokens or {}) do
                --The caster needs line of effect to the cube's centre from the
                --planned spot; targets inside are then filtered from that centre.
                if IsLiveSynthesizedTarget(enemy)
                    and MonsterAI.TargetDistance(token, enemy) <= range
                    and not checked[enemy.loc.str]
                    and token:GetLineOfSight(enemy.loc, pierceWalls) > 0 then
                    checked[enemy.loc.str] = true
                    local area = BuildSynthesizedArea(token, ability, "cube", enemy.loc, pathInfo.loc)
                    local targets, enemies, allies = self:SynthesizedTargetsInArea(token, ability, area)
                    local utility = enemies - allies*3 - (pathInfo.cost or 0)*0.001
                    if enemies > 0 and allies == 0
                        and (best == nil or utility > best.utility) then
                        best = {
                            loc = pathInfo.loc,
                            center = enemy.loc,
                            targets = targets,
                            enemies = enemies,
                            allies = allies,
                            utility = utility,
                        }
                    end
                end
            end
        end)
    end

    return best
end


function MonsterAI:FindSynthesizedLinePlan(token, ability)
    local best = nil
    for _,pathInfo in pairs(self.paths or {}) do
        local candidates = {}
        for _,enemy in ipairs(self.enemyTokens or {}) do
            if IsLiveSynthesizedTarget(enemy) then
                candidates[#candidates+1] = {
                    targetLoc = enemy.loc,
                    locOverride = pathInfo.loc,
                }
            end
        end

        local plan = self:FindBestLinePlan(token, ability, {
            candidates = candidates,
            logPlan = false,
            scorefn = function(target)
                if target.isObject then
                    return 0
                end
                return cond(target:IsFriend(token), -3, 1)
            end,
        })
        if plan ~= nil then
            local enemies, allies = CountSynthesizedTargets(token, plan.targets)
            local utility = enemies - allies*3 - (pathInfo.cost or 0)*0.001
            if enemies > 0 and allies == 0
                and (best == nil or utility > best.utility) then
                best = {
                    loc = pathInfo.loc,
                    targetLoc = plan.targetLoc,
                    targets = plan.targets,
                    enemies = enemies,
                    allies = allies,
                    utility = utility,
                }
            end
        end
    end
    return best
end


function MonsterAI:FindSynthesizedAbilityPlan(token, ability, profile)
    if profile.targetType == "target" then
        return self:FindSynthesizedTargetPlan(token, ability)
    elseif profile.targetType == "all" then
        return self:FindSynthesizedBurstPlan(token, ability)
    elseif profile.targetType == "cube" then
        return self:FindSynthesizedCubePlan(token, ability)
    elseif profile.targetType == "line" then
        return self:FindSynthesizedLinePlan(token, ability)
    end
end


local function SynthesizedMaliceCost(token, ability)
    local result = 0
    local cost = ability:GetCost(token)
    for _,detail in ipairs(cost.details or {}) do
        if detail.cost == CharacterResource.maliceResourceId then
            result = result + (tonumber(detail.quantity) or 0)
        else
            for _,payment in ipairs(detail.paymentOptions or {}) do
                if payment.resourceid == CharacterResource.maliceResourceId then
                    result = result + (tonumber(payment.quantity) or 0)
                    break
                end
            end
        end
    end
    return result
end

local function ScoreSynthesizedAbilityPlan(token, ability, profile, plan)
    local score = 0.72
    if profile.actionResource == CharacterResource.actionResourceId then
        score = 0.80
    elseif profile.actionResource == CharacterResource.maneuverResourceId
        or profile.actionResource == CharacterResource.freeManeuverResourceId then
        score = 0.48
    elseif profile.actionResource == nil or profile.actionResource == "none" then
        score = 0.38
    end

    if ability.categorization == "Signature Ability" then
        score = math.max(score, 0.84)
    elseif ability.categorization == "Heroic Ability" then
        score = math.max(score, 0.81)
    end

    score = score + math.min(0.12, math.max(0, (plan.enemies or 1) - 1)*0.05)
    score = score + math.max(0, profile.confidence - g_synthesizedAbilityMinimumConfidence)*0.1
    score = score - math.min(0.18, SynthesizedMaliceCost(token, ability)*0.015)
    -- Handcrafted signature moves conventionally score 1.0. Keep fallback
    -- plans below that while still ranking them above generic free strikes.
    return math.min(0.94, score)
end

function MonsterAI:FindBestSynthesizedAbilityMove(token, abilities, claimedAbilities)
    local best = nil
    local used = self:try_get("_tmp_synthesizedAbilitiesUsed", {})
    local failedMoves = self:try_get("_tmp_failedMoves", {})

    for _,ability in ipairs(abilities) do
        local key = SynthesizedAbilityKey(ability)
        local moveid = SynthesizedMoveId(ability)
        if not claimedAbilities[ability.name] and not used[key] and not failedMoves[moveid] then
            local profile, profileReason = self:GetSynthesizedAbilityProfile(token, ability)
            local registration = {
                id = moveid,
                category = "Main Actions",
            }
            self:SetMoveLogContext(token, registration)
            if profile ~= nil then
                if profile.actionResource == CharacterResource.maneuverResourceId
                    or profile.actionResource == CharacterResource.freeManeuverResourceId then
                    registration.category = "Maneuvers"
                    self:SetMoveLogContext(token, registration)
                end
                if not ability:CanAfford(token) then
                    self:LogMove(token.properties.monster_type, moveid, "Could not afford", {onlyIfEmpty = true})
                    self:LogDecision("MOVE REJECTED", {
                        ability = ability.name,
                        action = self.AbilityActionLogName(ability),
                        reason = AIAbilityUnavailableReason(token, ability),
                    })
                else
                    local plan = self:FindSynthesizedAbilityPlan(token, ability, profile)
                    local maliceCost = SynthesizedMaliceCost(token, ability)
                    -- Without effect-specific knowledge, do not spend shared
                    -- Malice on an area ability that only reaches one enemy.
                    if plan ~= nil and not (profile.targetType ~= "target"
                        and maliceCost > 0 and (plan.enemies or 0) < 2) then
                        plan.score = ScoreSynthesizedAbilityPlan(token, ability, profile, plan)
                        plan.ability = ability
                        plan.profile = profile
                        self:LogMove(token.properties.monster_type, moveid, string.format(
                            "Score: %.2f (confidence %.2f; %s)",
                            plan.score, profile.confidence, profile.reason))
                        self:LogDecision("MOVE CANDIDATE", {
                            ability = ability.name,
                            action = self.AbilityActionLogName(ability),
                            score = plan.score,
                            plan = self.ScoringPlanLogName(plan),
                            reason = string.format("synthesized at %.2f confidence from %s",
                                profile.confidence, profile.reason),
                            result = "legal synthesized candidate",
                        })
                        if best == nil or plan.score > best.score then
                            best = plan
                        end
                    else
                        self:LogMove(token.properties.monster_type, moveid,
                            "Could not find a safe, worthwhile target plan", {onlyIfEmpty = true})
                        self:LogDecision("MOVE REJECTED", {
                            ability = ability.name,
                            action = self.AbilityActionLogName(ability),
                            reason = "could not find a safe, worthwhile synthesized target plan",
                        })
                    end
                end
            else
                self:LogDecision("MOVE REJECTED", {
                    ability = ability.name,
                    action = self.AbilityActionLogName(ability),
                    reason = "not eligible for synthesized AI: " .. tostring(profileReason),
                })
            end
        end
    end

    return best
end


local function MoveForSynthesizedPlan(ai, token, loc)
    if loc == nil or ai:MovementTokenIsAtLoc(token, loc) then
        ai.Sleep(0.2)
        return false
    end
    ai:MoveToken(token, loc, {maxCost = 10000, ignoreFalling = false})
    ai.Sleep(0.6)
    return true
end

function MonsterAI:ExecuteSynthesizedAbilityPlan(token, plan)
    local ability = plan.ability
    self._tmp_synthesizedAbilitiesUsed = self:try_get("_tmp_synthesizedAbilitiesUsed", {})
    self._tmp_synthesizedAbilitiesUsed[SynthesizedAbilityKey(ability)] = true

    local moved = MoveForSynthesizedPlan(self, token, plan.loc)
    if plan.profile.targetType == "target" then
        local candidates = self:FindValidTargetsOfStrike(token, ability, token.loc)
        candidates = self:SelectChargeTargets(token, ability, candidates, nil, SynthesizedDefaultTargetScore)
        table.sort(candidates, function(a, b)
            return SynthesizedDefaultTargetScore(a) > SynthesizedDefaultTargetScore(b)
        end)
        local targets = {}
        for i=1,math.min(ability:GetNumTargets(token), #candidates) do
            targets[#targets+1] = candidates[i]
        end
        if #targets == 0 then
            return moved
        end
        self:ExecuteAbility(token, ability, targets)
        return true
    elseif plan.profile.targetType == "all" then
        local _, enemies, allies = self:SynthesizedBurstTargetsAtCurrentLoc(token, ability)
        if enemies == 0 or allies > 0 then
            return moved
        end
        self:ExecuteAbility(token, ability)
        return true
    end

    local targetLoc = cond(plan.profile.targetType == "cube", plan.center, plan.targetLoc)
    local area = BuildSynthesizedArea(token, ability, plan.profile.targetType, targetLoc)
    local targets, enemies, allies = self:SynthesizedTargetsInArea(token, ability, area)
    if enemies == 0 or allies > 0 then
        return moved
    end

    local abilityClone = DeepCopy(ability)
    self:ExecuteAbility(token, abilityClone, targets, {
        symbols = {targetArea = area},
        targetArea = area,
    })
    return true
end

--Registered move ids in the order to score them. Moves that declare a
--maxScore come last, so a move that can no longer beat the best found is
--skipped instead of scored (a tie never replaces the best, so skipping it
--changes nothing). Each group keeps the order pairs() gives it.
function MonsterAI:MovesInScoringOrder()
    local uncapped = {}
    local capped = {}
    for moveid,move in pairs(self.moves) do
        if move.maxScore ~= nil then
            capped[#capped+1] = moveid
        else
            uncapped[#uncapped+1] = moveid
        end
    end
    for _,moveid in ipairs(capped) do
        uncapped[#uncapped+1] = moveid
    end
    return uncapped
end

function MonsterAI.MoveMatchesMonster(token, move, includeDisabled)
    if move.id == "Minion Signature Ability" then
        --minion signatures cannot be disabled.
        includeDisabled = true
    end
    local monster_type = token.properties:try_get("monster_type", "")
    if not includeDisabled then
        if move.disabledForMonsters ~= nil and move.disabledForMonsters[monster_type] then
            return false
        end
    end
    if move.monsters ~= nil then
        for i=1,#move.monsters do
            if move.monsters[i] == monster_type then
                return true
            end
        end
    else
        return true
    end

    return false
end

--Initiative choice --------------------------------------------------------
--Before every monster turn the AI picks which waiting initiative group goes
--next (MonsterAIThread in MonsterAIPanel.lua). That runs over every group
--still waiting, before every monster turn, so it checks reach rather than
--planning moves:
--  * a group that can strike an enemy this turn goes before one that cannot;
--  * among those, minion squads and creatures near death bid high;
--  * a random factor of 1 to 1.5 varies the order of similar groups.

--What a minion bids, and what a creature at death's door bids on top of the 1
--any other creature bids, so both outrank healthy creatures.
MonsterAI.initiativeMinionPriority = 4
MonsterAI.initiativeNearDeathPriority = 3
--A creature that cannot strike anyone this turn keeps this share of its bid,
--which puts it behind every creature that can (the lowest such bid is 1).
MonsterAI.initiativeCannotStrikeFactor = 0.1

--How close to death a creature is: 0 at 13 + twice its level Stamina or more,
--rising to 1 at 4 + its level.
function MonsterAI.TurnUrgency(token)
    local level = tonumber(token.properties:CharacterLevel()) or 1
    local urgencyStartsAt = 13 + level*2
    local fullyUrgentAt = 4 + level
    local stamina = token.properties:CurrentHitpoints()
    return math.max(0, math.min(1,
        (urgencyStartsAt - stamina) / (urgencyStartsAt - fullyUrgentAt)))
end

--A creature's bid to act next, before reach and randomness: a minion bids
--initiativeMinionPriority, anyone else 1 plus up to initiativeNearDeathPriority
--as it nears death.
function MonsterAI.TurnPriority(token)
    if token.properties.minion then
        return MonsterAI.initiativeMinionPriority
    end
    return 1 + MonsterAI.initiativeNearDeathPriority*MonsterAI.TurnUrgency(token)
end

--Whether the creature could strike an enemy this turn: from where it stands,
--after its remaining movement, or by moving and then charging. It ignores line
--of sight and anything that would block a charge, so it can be optimistic; the
--turn's own planning decides what really happens. Straight-line distance
--settles most creatures, and only those in between pay for a pathfinding area.
--Call SetupCombatants for the token first. Returns the answer and a reason.
---@param token CharacterToken
---@return boolean canStrike
---@return string reason
function MonsterAI:CanStrikeThisTurn(token)
    local props = token.properties
    local mover = self:GetMovementToken(token)
    local speed = mover.properties:CurrentMovementSpeed()
    local remainingMovement = math.max(0, speed - mover.properties:DistanceMovedThisTurn())

    --The farthest any affordable strike reaches without moving first; a charge
    --(as FindValidTargetsOfStrike plans one) adds the creature's speed.
    local reach = nil
    for _,ability in ipairs(self.abilities) do
        local isStrike = ability:HasKeyword("Strike") or ability.name == "Melee Free Strike"
            or ability.name == "Ranged Free Strike"
        if isStrike and ability:CanAfford(token) then
            local range = ability:GetRange(props)
            reach = math.max(reach or 0, range)
            if ability:HasKeyword("Charge") or ability.name == "Melee Free Strike" then
                local chargeRange = range
                if ability.meleeAndRanged then
                    chargeRange = ability.meleeVariation:GetRange(props)
                elseif ability:HasKeyword("Melee") and ability:HasKeyword("Ranged") then
                    chargeRange = ability:try_get("meleeRange", 1)
                end
                reach = math.max(reach, speed + chargeRange)
            end
        end
    end
    if reach == nil then
        return false, "no affordable strike"
    end

    local nearest = nil
    for _,enemy in ipairs(self.enemyTokens) do
        if self.TokenIsLiveCombatant(enemy) then
            local distance = MonsterAI.TargetDistance(token, enemy)
            if nearest == nil or distance < nearest then
                nearest = distance
            end
        end
    end
    if nearest == nil then
        return false, "no live enemies"
    end
    if nearest <= reach then
        return true, "an enemy is in reach where it stands"
    end
    --No route is shorter than the straight line, so this is out of reach.
    if nearest > remainingMovement + reach then
        return false, "every enemy is too far to reach this turn"
    end

    for _,info in pairs(self:CalculateRemainingMovementPaths(token)) do
        for _,enemy in ipairs(self.enemyTokens) do
            if self.TokenIsLiveCombatant(enemy)
                and self:TargetDistanceFromLoc(token, enemy, info.loc) <= reach then
                return true, "an enemy is in reach after moving"
            end
        end
    end
    return false, "no square it can move to has an enemy in reach"
end

function MonsterAI:HandleMoveExecutionFailure(moveid, abilityName, err)
    self._tmp_failedMoves = self:try_get("_tmp_failedMoves", {})
    self._tmp_failedMoves[moveid] = true
    self._tmp_expectedPromptTarget = nil

	if self:try_get("_tmp_abortTurn") ~= nil then
		self:LogDecision("MOVE ABORTED", {
			ability = abilityName,
			reason = self._tmp_abortTurn,
			result = "remaining turn paused",
		})
		return g_moveResultUnsafe
	end

	if self:try_get("_tmp_actorInterrupted") ~= nil then
		local reason = self._tmp_actorInterrupted
		self._tmp_actorInterrupted = nil
		self:LogDecision("MOVE INTERRUPTED", {
			ability = abilityName,
			reason = reason,
			result = "remaining actions skipped for this actor",
		})
		return g_moveResultUnsafe
	end

    pcall(function()
        self:LogMove(self.token.properties.monster_type, moveid,
            "Execution failed: " .. tostring(err))
    end)
    pcall(function()
        self:LogDecision("MOVE ERROR", {
            ability = abilityName,
            reason = "execution failed: " .. tostring(err),
            result = "move quarantined for this actor",
        })
    end)

    if not self:WaitForAbilityIdle(5) then
        self:LogDecision("MOVE RECOVERY ERROR", {
            ability = abilityName,
            reason = "ability casts did not become idle within 5 seconds",
            result = "remaining actions skipped for this actor",
        })
        return g_moveResultUnsafe
    end

    return g_moveResultFailed
end

-- Compare complete routes to legal spaces beside enemies, then take the furthest
-- affordable step on the winning route. Straight-line distance would get stuck
-- on the wrong side of walls and can prefer an enemy we cannot actually reach.
function MonsterAI:FindAdvancePlan(token, paths)
    local mover = self:GetMovementToken(token)
    local reachable = {}
    local canMove = false
    for _,info in pairs(paths) do
        reachable[info.loc.xyfloorOnly.str] = info
        if info.cost > 0 then canMove = true end
    end
    if not canMove then return nil end
    local best = nil
    for _,enemy in ipairs(self.enemyTokens) do
        if self.TokenIsLiveCombatant(enemy) then
            if MonsterAI.TargetDistance(mover, enemy) <= 1 and mover:GetLineOfSight(enemy) > 0 then
                mover:ClearMovementArrow()
                return nil
            end
            local size = math.max(1, mover.tileSize)
            local enemySize = math.max(1, enemy.tileSize)
            for x = -size,enemySize do
                for y = -size,enemySize do
                    if x == -size or x == enemySize or y == -size or y == enemySize then
                        local goal = enemy.loc:dir(x, y)
                        if not self:MovementLocOverlapsCreature(token, goal) then
                            local arrowProf = ProfBegin("engine: MarkMovementArrow")
                            local preview = mover:MarkMovementArrow(goal, {})
                            ProfEnd(arrowProf)
                            ---@type LuaPath?
                            local path = preview ~= nil and preview.path or nil
                            local reachableGoal = false
                            if path ~= nil and path.destination.xyfloorOnly.str == goal.xyfloorOnly.str then
                                self:ExecuteWithTheoreticalMovementLoc(token, path.destination, function()
                                    reachableGoal = MonsterAI.TargetDistance(mover, enemy) <= 1 and mover:GetLineOfSight(enemy) > 0
                                end)
                            end
                            if reachableGoal then
                                --reachableGoal is only set inside the path ~= nil branch above.
                                ---@cast path -nil
                                -- Engine previews reuse their path object. Keep only value locations.
                                local dest = nil
                                for _,step in ipairs(path.steps) do
                                    local info = reachable[step.xyfloorOnly.str]
                                    if info ~= nil and info.cost > 0 then dest = info.loc end
                                end
                                if dest ~= nil and (best == nil or path.cost < best.cost) then
                                    best = {loc = dest, enemy = enemy, cost = path.cost}
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    mover:ClearMovementArrow()
    return best
end

--previewed: the caller has already shown this advance (a squad strike shows its
--advancing members with the rest of the squad), so it is not previewed again.
function MonsterAI:ExecuteAdvanceFallback(token, previewed)
    local mover = self:GetMovementToken(token)
    local plan = self:FindAdvancePlan(token, self:CalculateRemainingMovementPaths(token))
    local advance = nil
    if plan == nil then
        advance = FindAbilityByName(token.properties:GetActivatedAbilities(), "Use Move Action")
        if advance == nil or not advance:CanAfford(token) then return false end
        plan = self:FindAdvancePlan(token,
            self:CalculateMovementPaths(token, math.max(0, mover.properties:CurrentMovementSpeed())*10))
    end
    if plan == nil then return false end

    if not previewed and self.PlanPreviewsOn() then
        --an advance attacks no one, whatever Use Move Action's targeting says.
        local preview = self:BuildPlanPreview(token, {advance}, {loc = plan.loc}, function() return {} end)
        preview.title = string.format("%s advances toward %s", PreviewName(token), PreviewName(plan.enemy))
        preview.moveOnly = true
        if not self:AwaitPlanPreview(preview) then
            return false
        end
    end

    self:LogDecision("ADVANCE FALLBACK", {
        actor = self.TokenLogName(token),
        ability = advance ~= nil and advance.name or nil,
        to = self.LocLogName(plan.loc),
        targets = self.TargetsLogName({{token = plan.enemy}}),
        plan = advance ~= nil and "convert main action to Advance" or "use remaining movement",
    })
    local origin = mover.loc.str
    if advance == nil then
        self:MoveToken(token, plan.loc, {maxCost = 10000, ignoreFalling = false}, true)
    else
        -- Advance invokes Move Speed. Use the real cast to pay the main action,
        -- and track its movement reactions just as MoveToken does.
        local activityId = dmhub.GenerateGuid()
        local previous = creature.SetTokenAIActivity(mover.charid, activityId)
        self:SetTargetsForExpectedPrompt{casterid = token.charid, targets = {{loc = plan.loc}}}
        local ok, err = RunYieldingFunction(function()
            self:ExecuteAbility(token, advance, {{token = token}}, {symbols = {mode = 1}})
        end)
        creature.SetTokenAIActivity(mover.charid, previous)
        self._tmp_expectedPromptTarget = nil
        if not ok then error(err) end
        local completed, reason = self:WaitForMovementActivity(mover, activityId)
        if not completed then
            self._tmp_abortTurn = reason
            error(reason)
        end
    end
    self.Sleep(0.5)
    return mover.valid and mover.loc.str ~= origin
end

--Move to the cheapest reachable square outside every Avoid zone, using the
--remaining movement. False when there is none.
function MonsterAI:ExecuteLeaveAvoidZone(token)
    local mover = self:GetMovementToken(token)
    local best = nil
    for _,info in pairs(self:CalculateRemainingMovementPaths(token)) do
        if info.cost > 0 and (best == nil or info.cost < best.cost)
            and not MonsterAI.InDirectiveZone("avoid", mover, info.loc) then
            best = info
        end
    end
    if best == nil then return false end

    if self.PlanPreviewsOn() then
        local preview = self:BuildPlanPreview(token, {}, {loc = best.loc}, function() return {} end)
        preview.title = string.format("%s moves out of a zone it avoids", PreviewName(token))
        preview.moveOnly = true
        if not self:AwaitPlanPreview(preview) then
            return false
        end
    end

    self:LogDecision("LEAVE AVOIDED ZONE", {
        actor = self.TokenLogName(token),
        to = self.LocLogName(best.loc),
        plan = "use remaining movement",
    })
    local origin = mover.loc.str
    self:MoveToken(token, best.loc, {maxCost = 10000, ignoreFalling = false}, true)
    self.Sleep(0.5)
    return mover.valid and mover.loc.str ~= origin
end

--- True when the creature must stay on its Hold post this turn: it stands on
--- it, or a path search this frame found it can reach it.
--- @param token CharacterToken
--- @return boolean
function MonsterAI:HoldConstrains(token)
    if not MonsterAI.Holds(token) then
        return false
    end
    return self:PlanningMemo().holdActive[token.charid] == true
        or MonsterAI.InHoldZone(token, nil, self:GetMovementToken(token))
end

--An ability that puts its caster on a chosen empty square (a teleport such as
--a zone's "step to the basin"): targets an empty space and relocates.
local function IsSelfRelocation(ability)
    if ability.targetType ~= "emptyspace" and ability.targetType ~= "anyspace" then
        return false
    end
    for _,behavior in ipairs(ability:try_get("behaviors", {})) do
        if behavior.typeName == "ActivatedAbilityRelocateCreatureBehavior" then
            return true
        end
    end
    return false
end

--A free square of the post within range of a self relocation, nearest an enemy.
local function FindHoldRelocation(self, token, ability, squares)
    local range = ability:GetRange(token.properties)
    local predicate = ability:TargetLocPassesFilterPredicate(token, {}) or function(_) return true end
    local best = nil
    for _,loc in ipairs(squares) do
        if token.loc:DistanceInTiles(loc) <= range and predicate(loc)
            and not self:MovementLocOverlapsCreature(token, loc)
            and MonsterAI.InHoldZone(token, loc) then
            local distance = 999
            for _,enemy in ipairs(self.enemyTokens) do
                if self.TokenIsLiveCombatant(enemy) then
                    distance = math.min(distance, self:TargetDistanceFromLoc(token, enemy, loc))
                end
            end
            if best == nil or distance < best.distance then
                best = {loc = loc, distance = distance}
            end
        end
    end
    return best
end

--Back to the Hold post: walk onto it if it is in reach (the square nearest an
--enemy), else teleport onto it with an affordable self relocation, else walk
--as far as the remaining movement goes along the shortest route to it.
function MonsterAI:ExecuteReturnToHoldZone(token)
    local mover = self:GetMovementToken(token)
    local squares = MonsterAI.HoldSquares(token)
    if #squares == 0 then
        return false
    end

    local paths = self:CalculateRemainingMovementPaths(token)
    local plan = nil
    for _,info in pairs(paths) do
        if info.cost > 0 and MonsterAI.InHoldZone(token, info.loc, mover) then
            local distance = 999
            for _,enemy in ipairs(self.enemyTokens) do
                if self.TokenIsLiveCombatant(enemy) then
                    distance = math.min(distance, self:TargetDistanceFromLoc(token, enemy, info.loc))
                end
            end
            if plan == nil or distance < plan.distance
                or (distance == plan.distance and info.cost < plan.cost) then
                plan = {loc = info.loc, distance = distance, cost = info.cost, how = "walk onto post"}
            end
        end
    end

    if plan == nil and mover == token then
        for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
            if IsSelfRelocation(ability) and ability:CanAfford(token) then
                local found = FindHoldRelocation(self, token, ability, squares)
                if found ~= nil then
                    plan = {loc = found.loc, ability = ability, how = "relocate with " .. ability.name}
                    break
                end
            end
        end
    end

    if plan == nil then
        --the nearest few squares by straight line, then the cheapest real route.
        local reachable = {}
        for _,info in pairs(paths) do
            reachable[info.loc.xyfloorOnly.str] = info
        end
        local byDistance = {}
        for _,loc in ipairs(squares) do
            byDistance[#byDistance+1] = {loc = loc, distance = mover.loc:DistanceInTiles(loc)}
        end
        table.sort(byDistance, function(a, b) return a.distance < b.distance end)
        for i=1,math.min(6, #byDistance) do
            local goal = byDistance[i].loc
            if not self:MovementLocOverlapsCreature(token, goal) then
                local preview = mover:MarkMovementArrow(goal, {})
                ---@type LuaPath?
                local path = preview ~= nil and preview.path or nil
                if path ~= nil and path.destination.xyfloorOnly.str == goal.xyfloorOnly.str then
                    local dest = nil
                    for _,step in ipairs(path.steps) do
                        local info = reachable[step.xyfloorOnly.str]
                        if info ~= nil and info.cost > 0 then dest = info.loc end
                    end
                    if dest ~= nil and (plan == nil or path.cost < plan.cost) then
                        plan = {loc = dest, cost = path.cost, how = "walk toward post"}
                    end
                end
            end
        end
        mover:ClearMovementArrow()
    end
    if plan == nil then
        return false
    end

    if self.PlanPreviewsOn() then
        local preview = self:BuildPlanPreview(token, plan.ability ~= nil and {plan.ability} or {},
            {loc = plan.loc}, function() return {} end)
        preview.title = string.format("%s returns to the zone it holds", PreviewName(token))
        preview.moveOnly = true
        if not self:AwaitPlanPreview(preview) then
            return false
        end
    end

    self:LogDecision("RETURN TO HELD ZONE", {
        actor = self.TokenLogName(token),
        ability = plan.ability ~= nil and plan.ability.name or nil,
        to = self.LocLogName(plan.loc),
        plan = plan.how,
    })
    local origin = mover.loc.str
    if plan.ability ~= nil then
        self:ExecuteAbility(token, plan.ability, {{loc = plan.loc}}, {sleep = 0.5})
    else
        self:MoveToken(token, plan.loc, {maxCost = 10000, ignoreFalling = false}, true)
        self.Sleep(0.5)
    end
    return mover.valid and mover.loc.str ~= origin
end

--Plan preview, host side --------------------------------------------------
--Each unit of a turn is described as a preview before it runs, then
--AwaitPlanPreview shows it to the table (see PREVIEW_DOC) and waits for
--Proceed. A preview is:
--  title:   banner text
--  actor:   the token whose plan it is (its card is shown; hidden actors are not previewed)
--  ability: the ability whose card to show, or nil
--  moves:   {token, to = Loc, via = nil|Loc} movement arrows
--  attacks: {token, from = Loc, target = token, label} attack arrows
--  area, areaCenter: an area ability's LuaShape and the square it is aimed at
--  moveOnly: true when it only moves (an advance), so the ability card alone is not worth a pause

--- Describe one move: the actor goes to plan.loc (unless already there) and
--- uses the last of `abilities` on the plan's targets. A plan that names no
--- targets gets the ones the standard execute picks after moving, or the ones
--- pickTargets(token, ability, loc) returns.
--- @param token CharacterToken
--- @param abilities nil|ActivatedAbility[]
--- @param plan nil|table the move's scoring info
--- @param pickTargets nil|fun(token: CharacterToken, ability: ActivatedAbility, loc: Loc): table|nil nil = use the default search
--- @return table preview
function MonsterAI:BuildPlanPreview(token, abilities, plan, pickTargets)
    abilities = abilities or {}
    local ability = abilities[#abilities]
    local mover = self:GetMovementToken(token) or token
    local planLoc = plan ~= nil and plan.loc or nil
    local moveTo = planLoc
    if moveTo ~= nil and self:MovementTokenIsAtLoc(token, moveTo) then
        moveTo = nil
    end

    local targets = {}
    if plan ~= nil then
        targets = PreviewTargets(plan.targets)
        if #targets == 0 then
            targets = PreviewTargets(plan.target)
        end
        --The targets the strike planner chose from this square while scoring
        --the move; the move's execute picks them the same way.
        if #targets == 0 and ability ~= nil and planLoc ~= nil and type(plan.strikePlans) == "table" then
            local byLoc = plan.strikePlans[ability]
            if byLoc ~= nil then
                targets = PreviewTargets(byLoc[planLoc.str])
            end
        end
    end
    if #targets == 0 and ability ~= nil then
        local from = planLoc or mover.loc
        local picked = pickTargets ~= nil and pickTargets(token, ability, from) or nil
        if picked ~= nil then
            targets = PreviewTargets(picked)
        elseif ability.targetType == "target" then
            local candidates = self:FindValidTargetsOfStrike(token, ability, from)
            candidates = self:SelectChargeTargets(token, ability, candidates)
            for i=1,math.min(ability:GetNumTargets(token), #candidates) do
                targets[#targets+1] = {token = candidates[i].token, charge = candidates[i].charge}
            end
        elseif ability.targetType == "all" then
            local range = ability:GetRange(token.properties)
            for _,enemy in ipairs(self.enemyTokens or {}) do
                if self.TokenIsLiveCombatant(enemy)
                    and self:TargetDistanceFromLoc(token, enemy, from) <= range then
                    targets[#targets+1] = {token = enemy}
                end
            end
        end
    end

    --A charge moves on from the planned square as part of the ability.
    local chargeLoc = nil
    for _,target in ipairs(targets) do
        if target.charge ~= nil then
            chargeLoc = target.charge
            break
        end
    end

    local preview = {actor = token, actors = {token}, actorName = PreviewName(token),
        ability = ability, moves = {}, attacks = {}, targets = {}}
    if chargeLoc ~= nil then
        preview.moves[1] = {token = mover, to = chargeLoc, via = moveTo}
    elseif moveTo ~= nil then
        preview.moves[1] = {token = mover, to = moveTo}
    end

    --An area ability shows its area, and whoever is caught in it, instead of
    --an attack arrow per target.
    if ability ~= nil then
        preview.area, preview.areaCenter = self:BuildPlanArea(token, ability, plan)
        if preview.area ~= nil then
            targets = {}
        end
    end

    local from = chargeLoc or planLoc or mover.loc
    local names = {}
    for _,target in ipairs(targets) do
        if self.TokenIsLiveCombatant(target.token) then
            if target.token.charid ~= token.charid then
                preview.attacks[#preview.attacks+1] = {
                    token = token,
                    from = from,
                    target = target.token,
                    label = ability ~= nil and ability.name or nil,
                    friendly = dmhub.TokensAreFriendly(token, target.token),
                }
            end
            preview.targets[#preview.targets+1] = target.token
            names[#names+1] = PreviewName(target.token)
        end
    end

    local abilityNames = {}
    for _,a in ipairs(abilities) do
        abilityNames[#abilityNames+1] = a.name
    end
    local title = PreviewName(token)
    if #abilityNames > 0 then
        title = title .. ": " .. table.concat(abilityNames, " + ")
    elseif #preview.moves > 0 then
        title = title .. " moves"
    end
    if #names > 0 then
        title = title .. " on " .. table.concat(names, ", ")
    end
    preview.title = title
    return preview
end

--Area target types the preview can rebuild, and the engine shape for each.
local g_previewAreaShapes = {cube = "cube", line = "line", cone = "cone", sphere = "sphere", cylinder = "cylinder"}

--A plan field that is already the area (a LuaShape), or nil.
local function PlanShapeField(plan)
    for _,key in ipairs({"area", "targetArea"}) do
        local value = plan[key]
        if type(value) == "userdata" then
            --only a LuaShape has locations; anything else fails the read below.
            ---@cast value LuaShape
            local ok, locs = pcall(function() return value.locations end)
            if ok and type(locs) == "table" then
                return value
            end
        end
    end
    return nil
end

--The square a plan aims its area at: the cube centre or the line's end.
local function PlanAreaPoint(plan)
    local point = plan.center or plan.targetLoc
    if point == nil and type(plan.cube) == "table" then
        point = plan.cube.loc
    end
    if point == nil and type(plan.line) == "table" then
        point = plan.line.targetLoc
    end
    return point
end

--- The area an area ability in this plan will cover, or nil when the ability
--- is not a placed area or the plan does not say where it goes. Built the way
--- the AI's own cube and line planners build it, from where the caster will
--- stand (plan.locOverride, else plan.loc) toward the square the plan aims at.
--- @param token CharacterToken
--- @param ability ActivatedAbility
--- @param plan nil|table
--- @return nil|LuaShape area
--- @return nil|Loc center the square it is aimed at, when the plan names one
function MonsterAI:BuildPlanArea(token, ability, plan)
    local shape = g_previewAreaShapes[ability.targetType]
    if shape == nil or plan == nil then
        return nil
    end
    local point = PlanAreaPoint(plan)
    local area = PlanShapeField(plan)
    if area ~= nil then
        return area, point
    end
    if point == nil then
        return nil
    end
    local casterLoc = plan.locOverride or plan.loc
    local altitudeLoc = shape == "cube" and point.withGroundAltitude or (casterLoc or token.loc)
    local ok, result = pcall(dmhub.CalculateShape, {
        shape = shape,
        targetPoint = token:PosAtLoc(point),
        token = token,
        range = ability:GetRange(token.properties),
        radius = ability:GetRadius(token.properties),
        locOverride = casterLoc,
        checklos = shape == "line",
        altitude = altitudeLoc.altitude * dmhub.unitsPerSquare,
    })
    if ok and result ~= nil then
        return result, point
    end
    return nil
end

--- Describe a start-of-turn Malice ability: its card, whom it affects, and
--- the Malice it spends. A plan that names its targets or its area shows
--- those; otherwise the targets are the ones the cast picks when it is given
--- none: everyone the ability's filter accepts (within range for a burst),
--- or the caster for a self ability.
--- @param caster CharacterToken
--- @param ability ActivatedAbility
--- @param scoringInfo nil|table
--- @return table preview
function MonsterAI:BuildMalicePreview(caster, ability, scoringInfo)
    local plan = type(scoringInfo) == "table" and scoringInfo or nil
    local preview = self:BuildPlanPreview(caster, {ability}, plan, function(token, castAbility)
        if castAbility.targetType == "self" then
            return {{token = token}}
        end
        if castAbility.targetType ~= "all" and castAbility.targetType ~= "map" then
            return nil
        end
        local range = nil
        if castAbility.targetType == "all" then
            range = castAbility:GetRange(token.properties)
        end
        local result = {}
        for _,other in ipairs(dmhub.allTokens) do
            if self.TokenIsLiveCombatant(other)
                and castAbility:TargetPassesFilter(token, other, {mode = 1})
                and (range == nil or MonsterAI.TargetDistance(other, token) <= range) then
                result[#result+1] = {token = other}
            end
        end
        return result
    end)
    preview.malice = {
        cost = SynthesizedMaliceCost(caster, ability),
        pool = CharacterResource.GetMalice(),
    }
    return preview
end

--- Describe a minion squad's strike: every member's move into position (and
--- charge), each member's attack, and where the members that cannot reach a
--- target will advance to.
--- @param plans table[] the squad's member plans ({token, ability, option = {loc, token, charge}})
--- @param advancers CharacterToken[] members that will advance instead
--- @param ability ActivatedAbility the squad's signature ability
--- @return table preview
function MonsterAI:BuildSquadPreview(plans, advancers, ability)
    local preview = {ability = ability, actors = {}, moves = {}, attacks = {}}
    local names = {}
    local named = {}
    for _,plan in ipairs(plans) do
        local member = plan.token
        preview.actor = preview.actor or member
        preview.actors[#preview.actors+1] = member
        local mover = self:GetMovementToken(member) or member
        local loc = plan.option.loc
        local moveTo = loc
        if moveTo ~= nil and self:MovementTokenIsAtLoc(member, moveTo) then
            moveTo = nil
        end
        local charge = plan.option.charge
        if charge ~= nil then
            preview.moves[#preview.moves+1] = {token = mover, to = charge, via = moveTo}
        elseif moveTo ~= nil then
            preview.moves[#preview.moves+1] = {token = mover, to = moveTo}
        end
        local target = plan.option.token
        preview.attacks[#preview.attacks+1] = {
            token = member,
            from = charge or loc or mover.loc,
            target = target,
            label = (plan.ability or ability).name,
        }
        if target ~= nil and target.valid and not named[target.charid] then
            named[target.charid] = true
            names[#names+1] = PreviewName(target)
        end
    end
    for _,member in ipairs(advancers) do
        preview.actor = preview.actor or member
        preview.actors[#preview.actors+1] = member
        pcall(function()
            local advancePlan = self:FindAdvancePlan(member, self:CalculateRemainingMovementPaths(member))
            if advancePlan ~= nil and not self:MovementTokenIsAtLoc(member, advancePlan.loc) then
                preview.moves[#preview.moves+1] = {token = self:GetMovementToken(member) or member, to = advancePlan.loc}
            end
        end)
    end

    local kind = nil
    if preview.actor ~= nil and preview.actor.properties ~= nil then
        kind = preview.actor.properties:try_get("monster_type")
    end
    if type(kind) ~= "string" or kind == "" then
        kind = PreviewName(preview.actor)
    end
    --the squad's own name ("Clawfish Squad 1"), as its Stamina bar shows it.
    local squadName = nil
    if preview.actor ~= nil and preview.actor.properties ~= nil then
        pcall(function() squadName = preview.actor.properties:MinionSquad() end)
    end
    preview.actorName = type(squadName) == "string" and squadName or (kind .. " squad")
    if #plans == 0 then
        preview.title = string.format("%s squad advances", kind)
        preview.moveOnly = true
    else
        preview.title = string.format("%s squad: %s", kind, ability.name)
        if #names > 0 then
            preview.title = preview.title .. " on " .. table.concat(names, ", ")
        end
    end
    return preview
end

--- The area for the preview document: its squares, the creatures caught in
--- it that the players can see, a square to centre the camera on, and the
--- ability's shape name ("Cube").
--- @param area LuaShape
--- @param center nil|Loc the square the area is aimed at (else the middle of its squares)
--- @param ability nil|ActivatedAbility
--- @return table
function MonsterAI:PlanAreaDocument(area, center, ability)
    local locs = {}
    local sumx, sumy = 0, 0
    for _,loc in ipairs(area.locations or {}) do
        locs[#locs+1] = loc.str
        sumx = sumx + loc.x
        sumy = sumy + loc.y
    end
    local caught = {}
    pcall(function()
        for _,other in pairs(dmhub.tokenInfo.TokensInShape(area)) do
            if self.TokenIsLiveCombatant(other) and not HiddenFromPlayers(other) then
                caught[#caught+1] = other.charid
            end
        end
    end)
    local centerx, centery = nil, nil
    if center ~= nil then
        centerx, centery = center.x, center.y
    elseif #locs > 0 then
        centerx, centery = math.floor(sumx/#locs + 0.5), math.floor(sumy/#locs + 0.5)
    end
    local shapeName = ability ~= nil and tostring(ability.targetType) or "area"
    return {
        shape = shapeName:sub(1, 1):upper() .. shapeName:sub(2),
        locs = locs,
        caught = caught,
        x = centerx,
        y = centery,
    }
end

--- Show `preview` to the table and wait until someone presses Proceed.
--- Returns true to go ahead, which is immediate when previews are off
--- (PlanPreviewsOn) or nothing the players can see would be shown.
--- Returns false when the AI stopped or the turn moved on while waiting; the
--- turn is then marked aborted so it ends without advancing initiative.
--- @param preview nil|table see BuildPlanPreview
--- @return boolean
function MonsterAI:AwaitPlanPreview(preview)
    if preview == nil or not MonsterAI.PlanPreviewsOn() then
        return true
    end

    local moves = {}
    for _,move in ipairs(preview.moves or {}) do
        if move.to ~= nil and not HiddenFromPlayers(move.token) then
            moves[#moves+1] = {
                charid = move.token.charid,
                to = move.to.str,
                via = move.via ~= nil and move.via.str or nil,
            }
        end
    end
    local attacks = {}
    for _,attack in ipairs(preview.attacks or {}) do
        if attack.from ~= nil and not HiddenFromPlayers(attack.token)
            and self.TokenIsLiveCombatant(attack.target) then
            attacks[#attacks+1] = {
                charid = attack.token.charid,
                from = attack.from.str,
                target = attack.target.charid,
                label = attack.label,
                friendly = attack.friendly == true,
            }
        end
    end
    --A map-wide ability (Goblin Mode on every goblin) would draw an arrow to
    --half the board; past this many the card's portraits say who it affects.
    if #attacks > 8 then
        attacks = {}
    end
    local actors = {}
    for _,actor in ipairs(preview.actors or {}) do
        if not HiddenFromPlayers(actor) then
            actors[#actors+1] = actor.charid
        end
    end
    local actorHidden = HiddenFromPlayers(preview.actor)
    if actorHidden and #moves == 0 and #attacks == 0 then
        self:LogDecision("PLAN PREVIEW SKIPPED", {
            actor = self.TokenLogName(preview.actor),
            reason = "the players cannot see the acting monster",
        })
        return true
    end

    --every creature it affects, the caster included (an ability on itself).
    local targetIds = {}
    for _,target in ipairs(preview.targets or {}) do
        if not HiddenFromPlayers(target) then
            targetIds[#targetIds+1] = target.charid
        end
    end
    local card = preview.ability
    if actorHidden or preview.moveOnly then
        card = nil
    end
    --Nothing on the board and no card: the card would only say "Movement: None"
    --(an advance with nowhere to go, a squad with no one to strike).
    if #moves == 0 and #attacks == 0 and #targetIds == 0 and preview.area == nil
        and preview.malice == nil and card == nil then
        self:LogDecision("PLAN PREVIEW SKIPPED", {
            actor = self.TokenLogName(preview.actor),
            reason = "nothing to show: no movement, targets or ability",
        })
        return true
    end

    local queue = dmhub.initiativeQueue
    local initiativeid = queue ~= nil and queue:CurrentInitiativeId() or nil
    local seq = dmhub.GenerateGuid()
    local doc = mod:GetDocumentSnapshot(PREVIEW_DOC)
    doc:BeginChange()
    for k in pairs(doc.data) do
        doc.data[k] = nil
    end
    doc.data.seq = seq
    doc.data.userid = dmhub.userid
    doc.data.actorName = preview.actorName or PreviewName(preview.actor)
    doc.data.actors = actors
    doc.data.attacking = #attacks > 0
    --every client finds the ability on the actor by name to show its card.
    card = preview.ability
    if card ~= nil and not actorHidden then
        doc.data.ability = {charid = preview.actor.charid, name = card.name}
    end
    doc.data.moves = moves
    doc.data.attacks = attacks
    if preview.area ~= nil then
        doc.data.area = self:PlanAreaDocument(preview.area, preview.areaCenter, card)
    end
    doc.data.targets = targetIds
    if preview.malice ~= nil then
        doc.data.malice = preview.malice
    end
    doc:CompleteChange("Monster AI plan preview", {undoable = false})

    self:LogDecision("PLAN PREVIEW", {
        actor = self.TokenLogName(preview.actor),
        ability = card ~= nil and card.name or nil,
        plan = preview.title,
        result = "waiting for Proceed",
    })

    local startedAt = dmhub.Time()
    local reason = nil
    while true do
        if mod.unloaded or not MonsterAI.active then
            reason = "Monster AI stop requested"
            break
        end
        local q = dmhub.initiativeQueue
        if initiativeid ~= nil and (q == nil or q.hidden or q:CurrentInitiativeId() ~= initiativeid) then
            reason = g_abortTurnTaken
            break
        end
        local data = mod:GetDocumentSnapshot(PREVIEW_DOC).data
        --Cleared or replaced from under us: the AI restarted, or a second AI
        --thread is previewing too. Never take that as a go-ahead; stop instead.
        if data.seq ~= seq then
            reason = "plan preview was cleared or replaced"
            break
        end
        --Proceed, Play Entire Turn, or pauses turned off (card or Settings).
        if data.continued == seq or MonsterAI.PausesOff() then
            break
        end
        coroutine.yield(0.1)
    end

    local playTurn = mod:GetDocumentSnapshot(PREVIEW_DOC).data.playTurn == seq
    if reason == nil and playTurn then
        MonsterAI.PlayRestOfTurnWithoutPauses()
    end

    --Everything comes down before anything moves: the cast puts the ability's
    --own card up when it gets there. Only our own preview: one that replaced
    --it belongs to someone else.
    if mod:GetDocumentSnapshot(PREVIEW_DOC).data.seq == seq then
        pcall(MonsterAI.ClearPlanPreview)
    end

    self:LogDecision("PLAN PREVIEW FINISHED", {
        actor = self.TokenLogName(preview.actor),
        result = reason ~= nil and "turn stopped" or (playTurn and "play entire turn" or "proceed"),
        reason = reason,
        duration = dmhub.Time() - startedAt,
    })
    if reason ~= nil then
        self._tmp_abortTurn = reason
        return false
    end
    return true
end

function MonsterAI:FindAndExecuteMove()
    --Everything up to a move's execution is planning and never yields. Closed
    --before each RunYieldingFunction below (ProfEnd is safe to repeat).
    local chooseProf = ProfBegin("choose move")
    self._tmp_moveFailure = nil
    local token = self.token
    local searchContext = {}
    for key,value in pairs(self:try_get("_tmp_aiLogContext") or {}) do
        searchContext[key] = value
    end

    if not self.TokenIsLiveCombatant(token) then
        self:LogDecision("MOVE SEARCH ABORTED", {
            reason = "token is no longer a live combatant",
        })
        ProfEnd(chooseProf)
        return g_moveResultNone
    end

    if not token.properties:has_key("monster_type") then
        self:LogDecision("MOVE SEARCH ABORTED", {
            reason = "token has no monster type",
        })
        ProfEnd(chooseProf)
        return g_moveResultNone
    end

    local abilities = self.abilities
    local bestScore = {score = 0}
    local bestMove = nil
    local failedMoves = self:try_get("_tmp_failedMoves", {})
    self._tmp_failedMoves = failedMoves

    if token.properties.minion then
        local moveid = "Minion Signature Ability"
        if failedMoves[moveid] then
            self:LogDecision("MOVE REJECTED", {
                category = "Main Action",
                move = moveid,
                reason = "move failed earlier during this actor's turn",
            })
            ProfEnd(chooseProf)
            return g_moveResultNone
        end
        for _,ability in ipairs(abilities) do
            if MonsterAI.IsMinionSignatureAbility(ability) then
                if not ability:CanAfford(token) then
                    self:LogDecision("MOVE REJECTED", {
                        category = "Main Action",
                        move = "Minion Signature Ability",
                        ability = ability.name,
                        action = self.AbilityActionLogName(ability),
                        reason = AIAbilityUnavailableReason(token, ability),
                    })
                else
                    self:SetMoveLogContext(token, {
                        id = moveid,
                        category = "Main Actions",
                    })
                    local executed = false
                    ProfEnd(chooseProf)
                    local executePhase = ProfPhaseBegin("squad strike: " .. ability.name)
                    local ok, err = RunYieldingFunction(function()
                        executed = self:ExecuteSquadStrike(ability)
                    end)
                    ProfPhaseEnd(executePhase)
                    if not ok then
                        return self:HandleMoveExecutionFailure(moveid, ability.name, err)
                    end
                    return executed and g_moveResultExecuted or g_moveResultNone
                end
            end
        end

        self:LogDecision("MOVE SEARCH FINISHED", {
            reason = "minion has no affordable Signature Ability",
            result = "no legal move",
        })
        ProfEnd(chooseProf)
        return g_moveResultNone
    end

    for _,moveid in ipairs(self:MovesInScoringOrder()) do
        local move = self.moves[moveid]
        local registeredForMonster = self.MoveMatchesMonster(token, move, true)
        local matchesMonster = registeredForMonster and self.MoveMatchesMonster(token, move)

        local usingAbilities = {}
        if registeredForMonster and failedMoves[moveid] then
            matchesMonster = false
            self:SetMoveLogContext(token, move)
            self:LogDecision("MOVE REJECTED", {
                ability = self.AbilitiesLogName(move.abilities),
                reason = "move failed earlier during this actor's turn",
            })
        elseif registeredForMonster and not matchesMonster then
            self:SetMoveLogContext(token, move)
            self:LogDecision("MOVE REJECTED", {
                ability = self.AbilitiesLogName(move.abilities),
                reason = "disabled for this monster in the Monster AI panel",
            })
        elseif matchesMonster and move.abilities ~= nil then
            for i=1,#move.abilities do
                local ability = FindAbilityByName(abilities, move.abilities[i])
                if ability == nil then
                    self:SetMoveLogContext(token, move)
                    self:LogDecision("MOVE REJECTED", {
                        ability = move.abilities[i],
                        reason = "required ability is not present on the actor",
                    })
                    matchesMonster = false
                    break
                end

                local affordProf = ProfBegin("CanAfford")
                local canAfford = ability:CanAfford(token)
                ProfEnd(affordProf)
                if not canAfford then
                    self:SetMoveLogContext(token, move)
                    self:LogDecision("MOVE REJECTED", {
                        ability = ability.name,
                        action = self.AbilityActionLogName(ability),
                        reason = AIAbilityUnavailableReason(token, ability),
                    })
                    self:LogMove(self.token.properties.monster_type, moveid, "Could not afford", {onlyIfEmpty = true})
                    matchesMonster = false
                    break
                end

                usingAbilities[#usingAbilities+1] = ability
            end
        end

        --A move only replaces the best when it scores strictly higher.
        if matchesMonster and move.maxScore ~= nil and move.maxScore <= bestScore.score then
            ProfCount("moves skipped: cannot beat best")
            self:SetMoveLogContext(token, move)
            self:LogDecision("MOVE SKIPPED", {
                ability = self.AbilitiesLogName(usingAbilities),
                score = move.maxScore,
                reason = string.format("its maximum score cannot beat the best so far (%.3f)", bestScore.score),
            })
            self:LogMove(self.token.properties.monster_type, moveid,
                string.format("Skipped: cannot beat %.2f", bestScore.score), {onlyIfEmpty = true})
            matchesMonster = false
        end

        if matchesMonster then
            self:SetMoveLogContext(token, move)
            self:LogDecision("MOVE SCORING", {
                ability = self.AbilitiesLogName(usingAbilities),
                action = self.AbilityActionsLogName(usingAbilities),
                result = "all required abilities are present and affordable",
            })
            local scoreProf = ProfBegin("score: " .. tostring(moveid))
            --Score functions often return only {score, loc}, so the strike
            --planner's chosen targets are captured here for the preview.
            local strikePlans = {}
            self._tmp_strikePlans = strikePlans
            local ok, score, scoringReason = pcall(
                move.score, move, self, token,
                usingAbilities[1], usingAbilities[2], usingAbilities[3])
            self._tmp_strikePlans = nil
            ProfEnd(scoreProf)
            if not ok then
                failedMoves[moveid] = true
                self:LogDecision("MOVE ERROR", {
                    ability = self.AbilitiesLogName(usingAbilities),
                    reason = "scoring failed: " .. tostring(score),
                    result = "move quarantined for this actor",
                })
                self:LogMove(self.token.properties.monster_type, moveid,
                    "Scoring failed: " .. tostring(score))
            elseif type(score) == "table" and type(score.score) == "number" then
                self:LogMove(self.token.properties.monster_type, moveid, string.format("Score: %.2f", score.score))
                self:LogDecision("MOVE CANDIDATE", {
                    ability = self.AbilitiesLogName(usingAbilities),
                    action = self.AbilityActionsLogName(usingAbilities),
                    score = score.score,
                    plan = self.ScoringPlanLogName(score),
                    result = score.score > 0 and "legal candidate" or "non-positive score",
                })
            else
                self:LogMove(self.token.properties.monster_type, moveid, "Could not make move", {onlyIfEmpty = true})
                self:LogDecision("MOVE REJECTED", {
                    ability = self.AbilitiesLogName(usingAbilities),
                    reason = scoringReason or (score == nil
                        and "score callback returned no legal plan"
                        or "score callback returned no numeric score"),
                })
            end
            if type(score) == "table" and type(score.score) == "number"
                and score.score > bestScore.score then
                score.usingAbilities = usingAbilities
                score.strikePlans = strikePlans
                bestScore = score
                bestMove = move
            end
        end
    end

    local synthesizedMove = nil
    if not self:try_get("_tmp_synthesizedPlanningFailed", false) then
        local synthesizedOk, synthesizedResult = pcall(
            self.FindBestSynthesizedAbilityMove, self,
            token, abilities, self:GetClaimedAbilityNames(token))
        if synthesizedOk then
            synthesizedMove = synthesizedResult
        else
            self._tmp_synthesizedPlanningFailed = true
            self:LogDecision("MOVE ERROR", {
                move = "Synthesized Abilities",
                reason = "planning failed: " .. tostring(synthesizedResult),
                result = "synthesized moves quarantined for this actor",
            })
        end
    end
    if synthesizedMove ~= nil and synthesizedMove.score > bestScore.score then
        local moveid = SynthesizedMoveId(synthesizedMove.ability)
        local synthesizedRegistration = {
            id = moveid,
            category = "Main Actions",
        }
        if synthesizedMove.profile.actionResource == CharacterResource.maneuverResourceId
            or synthesizedMove.profile.actionResource == CharacterResource.freeManeuverResourceId then
            synthesizedRegistration.category = "Maneuvers"
        else
            synthesizedRegistration.category = "Main Actions"
        end
        self:SetMoveLogContext(token, synthesizedRegistration)
        self:LogDecision("MOVE SELECTED", {
            ability = synthesizedMove.ability.name,
            action = self.AbilityActionLogName(synthesizedMove.ability),
            score = synthesizedMove.score,
            plan = self.ScoringPlanLogName(synthesizedMove),
            result = "synthesized fallback outranked registered moves",
        })
        local executed = false
        ProfEnd(chooseProf)
        if self.PlanPreviewsOn() then
            local synthesizedPreview = self:BuildPlanPreview(token, {synthesizedMove.ability}, synthesizedMove,
                function(actor, ability, loc)
                    if synthesizedMove.profile.targetType ~= "target" then
                        return nil
                    end
                    --the targets ExecuteSynthesizedAbilityPlan picks after moving.
                    local candidates = self:FindValidTargetsOfStrike(actor, ability, loc)
                    candidates = self:SelectChargeTargets(actor, ability, candidates, nil, SynthesizedDefaultTargetScore)
                    table.sort(candidates, function(a, b)
                        return SynthesizedDefaultTargetScore(a) > SynthesizedDefaultTargetScore(b)
                    end)
                    local targets = {}
                    for i=1,math.min(ability:GetNumTargets(actor), #candidates) do
                        targets[#targets+1] = candidates[i]
                    end
                    return targets
                end)
            if not self:AwaitPlanPreview(synthesizedPreview) then
                return g_moveResultNone
            end
        end
        local executePhase = ProfPhaseBegin("execute: " .. moveid)
        local ok, err = RunYieldingFunction(function()
            executed = self:ExecuteSynthesizedAbilityPlan(token, synthesizedMove)
        end)
        ProfPhaseEnd(executePhase)
        if not ok then
            return self:HandleMoveExecutionFailure(
                moveid, synthesizedMove.ability.name, err)
        end
        self:LogMove(self.token.properties.monster_type, moveid,
            cond(executed, "Executed synthesized move", "Synthesized move could not complete"))
        self:LogDecision("MOVE FINISHED", {
            ability = synthesizedMove.ability.name,
            result = executed and "executed" or "could not complete",
        })
        if executed then
            return g_moveResultExecuted
        end
    elseif synthesizedMove ~= nil then
        local moveid = SynthesizedMoveId(synthesizedMove.ability)
        local synthesizedRegistration = {
            id = moveid,
            category = "Main Actions",
        }
        if synthesizedMove.profile.actionResource == CharacterResource.maneuverResourceId
            or synthesizedMove.profile.actionResource == CharacterResource.freeManeuverResourceId then
            synthesizedRegistration.category = "Maneuvers"
        end
        self:SetMoveLogContext(token, synthesizedRegistration)
        self:LogDecision("MOVE NOT SELECTED", {
            ability = synthesizedMove.ability.name,
            score = synthesizedMove.score,
            reason = string.format("score did not exceed selected registered move score %.3f", bestScore.score),
        })
    end

    if bestMove ~= nil then
        self:SetMoveLogContext(token, bestMove)
        self:LogDecision("MOVE SELECTED", {
            ability = self.AbilitiesLogName(bestScore.usingAbilities),
            action = self.AbilityActionsLogName(bestScore.usingAbilities),
            score = bestScore.score,
            plan = self.ScoringPlanLogName(bestScore),
            result = "highest-scoring legal registered move",
        })
        self:LogDecision("MOVE EXECUTION START", {
            ability = self.AbilitiesLogName(bestScore.usingAbilities),
        })
        local executeResult
        ProfEnd(chooseProf)
        if self.PlanPreviewsOn()
            and not self:AwaitPlanPreview(self:BuildPlanPreview(token, bestScore.usingAbilities, bestScore)) then
            return g_moveResultNone
        end
        local executePhase = ProfPhaseBegin("execute: " .. bestMove.id)
        local ok, err = RunYieldingFunction(function()
            executeResult = bestMove.execute(bestMove, self, token, bestScore,
                bestScore.usingAbilities[1], bestScore.usingAbilities[2],
                bestScore.usingAbilities[3])
        end)
        ProfPhaseEnd(executePhase)
        if not ok then
            return self:HandleMoveExecutionFailure(
                bestMove.id, self.AbilitiesLogName(bestScore.usingAbilities), err)
        end
        if executeResult == false or self:try_get("_tmp_moveFailure") ~= nil then
            return self:HandleMoveExecutionFailure(bestMove.id,
                self.AbilitiesLogName(bestScore.usingAbilities),
                self:try_get("_tmp_moveFailure", "execution returned false"))
        end
        self:LogMove(self.token.properties.monster_type, bestMove.id, "Executed move")
        self:LogDecision("MOVE FINISHED", {
            ability = self.AbilitiesLogName(bestScore.usingAbilities),
            result = "execution function completed",
        })
        return g_moveResultExecuted
    end

    --Off the post it holds with nothing better to do: head back before advancing.
    local returnId = "Return to held zone"
    if not failedMoves[returnId] and MonsterAI.Holds(token)
        and not MonsterAI.InHoldZone(token, nil, self:GetMovementToken(token)) then
        self:SetMoveLogContext(token, {id = returnId, category = "Movement"})
        local returned = false
        ProfEnd(chooseProf)
        local executePhase = ProfPhaseBegin("execute: " .. returnId)
        local ok, err = RunYieldingFunction(function()
            returned = self:ExecuteReturnToHoldZone(token)
        end)
        ProfPhaseEnd(executePhase)
        if not ok then
            return self:HandleMoveExecutionFailure(returnId, "Return to Zone", err)
        end
        if returned then return g_moveResultExecuted end
    end

    local advanceId = "Advance toward enemy"
    --A monster that already attacked at range this turn stays back.
    local firedAtRange = (self:try_get("_tmp_rangedStrikers") or {})[token.charid] == true
    if firedAtRange then
        self:LogDecision("MOVE NOT SELECTED", {
            move = advanceId,
            reason = "made a ranged strike this turn, so it keeps its distance",
        })
    end
    if not failedMoves[advanceId] and not firedAtRange then
        self:SetMoveLogContext(token, {id = advanceId, category = "Movement"})
        local advanced = false
        ProfEnd(chooseProf)
        local executePhase = ProfPhaseBegin("execute: " .. advanceId)
        local ok, err = RunYieldingFunction(function()
            advanced = self:ExecuteAdvanceFallback(token)
        end)
        ProfPhaseEnd(executePhase)
        if not ok then
            return self:HandleMoveExecutionFailure(advanceId, "Advance", err)
        end
        if advanced then return g_moveResultExecuted end
    end

    --Nothing else to do but still standing in an Avoid zone: step out.
    local leaveId = "Leave avoided zone"
    if not failedMoves[leaveId] and MonsterAI.InDirectiveZone("avoid", self:GetMovementToken(token)) then
        self:SetMoveLogContext(token, {id = leaveId, category = "Movement"})
        local left = false
        local executePhase = ProfPhaseBegin("execute: " .. leaveId)
        local ok, err = RunYieldingFunction(function()
            left = self:ExecuteLeaveAvoidZone(token)
        end)
        ProfPhaseEnd(executePhase)
        if not ok then
            return self:HandleMoveExecutionFailure(leaveId, "Leave Zone", err)
        end
        if left then return g_moveResultExecuted end
    end

    self:SetLogContext(token, searchContext)
    self:LogDecision("MOVE SEARCH FINISHED", {
        reason = "no move scored above zero",
        result = "no legal move",
    })
    ProfEnd(chooseProf)
    return g_moveResultNone
end

function MonsterAI:DistanceFromNearestEnemy(token)
    local result = 999
    for _,enemy in ipairs(self.enemyTokens) do
        if self.TokenIsLiveCombatant(enemy) then
            local dist = MonsterAI.TargetDistance(token, enemy)
            result = math.min(result, dist)
        end
    end
    return result
end

function MonsterAI:ExecuteAbility(casterToken, ability, targets, options)
    --the board is about to change; forget planning answers (see PlanningMemo).
    self._tmp_planningMemo = nil
    if self:try_get("_tmp_moveFailure") ~= nil then return false end

    if not ability:CanAfford(casterToken) then
        self:LogDecision("ABILITY CAST REJECTED", {
            actor = self.TokenLogName(casterToken),
            actorId = casterToken ~= nil and casterToken.charid or nil,
            ability = ability.name,
            action = self.AbilityActionLogName(ability),
            reason = AIAbilityUnavailableReason(casterToken, ability),
        })
        return
    end

    if targets ~= nil then
        local liveTargets = {}
        for _,targetInfo in ipairs(targets) do
            if targetInfo.token == nil or self.TokenIsLiveCombatant(targetInfo.token) then
                liveTargets[#liveTargets+1] = targetInfo
            end
        end
        targets = liveTargets
        if ability.targetType == "target" and #targets == 0 then
            self:LogDecision("ABILITY CAST REJECTED", {
                actor = self.TokenLogName(casterToken),
                actorId = casterToken ~= nil and casterToken.charid or nil,
                ability = ability.name,
                action = self.AbilityActionLogName(ability),
                reason = "no live targets remain",
            })
            return false
        end
    end

    options = options or {}
    local symbols = options.symbols or {}
    symbols.mode = symbols.mode or 1

    --Target filters read the symbols while cast behaviors read the options.
    --Keep both views on the exact area the AI selected.
    local targetArea = options.targetArea or symbols.targetArea
    if targetArea ~= nil then
        options.targetArea = targetArea
        symbols.targetArea = targetArea
    end
    local hasTargetArea = targetArea ~= nil or options.targetAreaList ~= nil

    if targets == nil then
        targets = {}

        if ability.targetType == "all" or ability.targetType == "map" then
            local range = nil
            if ability.targetType == "all" then
                range = ability:GetRange(casterToken.properties)
            end
            --Map abilities use their target filter across the whole map;
            --burst abilities also restrict targets to their range.
            for _,token in ipairs(dmhub.allTokens) do
                if self.TokenIsLiveCombatant(token)
                    and ability:TargetPassesFilter(casterToken, token, symbols)
                    and (range == nil or MonsterAI.TargetDistance(token, casterToken) <= range) then
                    targets[#targets+1] = { token = token }
                end
            end
        end
    elseif not hasTargetArea then
        --Placed areas already supply every creature inside the shape. Area
        --abilities report one target, so resizing would discard valid targets.
        local numTargets = ability:GetNumTargets(casterToken)
        --A charge strikes every target from one landing. When a band's target
        --list plans different landings, keep the targets one landing reaches,
        --in the order the caller ranked them.
        if symbols.targetPairs == nil then
            local rankById = {}
            for i,targetInfo in ipairs(targets) do
                if targetInfo.token ~= nil and rankById[targetInfo.token.charid] == nil then
                    rankById[targetInfo.token.charid] = i
                end
            end
            targets = self:SelectChargeTargets(casterToken, ability, targets, numTargets, function(targetInfo)
                local rank = targetInfo.token ~= nil and rankById[targetInfo.token.charid] or #targets
                return 1 - rank*0.001
            end)
        end
        table.resize_array(targets, numTargets)
    end

    --At most one charge per cast: the first landing wins, and any other
    --target's landing is dropped (the legality check below then decides).
    local chargeAttempted = false
    for _,target in ipairs(targets) do
        if target.charge ~= nil and chargeAttempted then
            target.charge = nil
        elseif target.charge ~= nil then
            chargeAttempted = true
            local token = casterToken
            if symbols.targetPairs ~= nil then
                for _,p in ipairs(symbols.targetPairs) do
                    token = dmhub.GetTokenById(p.a)
                end
            end
            local chargeLoc = target.charge
            target.charge = nil

            if not self:MovementTokenIsAtLoc(token, chargeLoc) then
                self.Sleep(1)
                self:Speech(token, "Charge!")
                self.Sleep(0.5)

                --freeMovement: the Charge's movement is part of the ability, not the
                --creature's move action (see the matching note in ExecuteSquadStrike).
                if not self:ExecuteChargeMovement(token, chargeLoc) then
                    return false
                end
                self.Sleep(1)
            end
        end
    end

    local function PairIsLegal(candidateAbility, actor, target)
        if not self.TokenIsLiveCombatant(actor)
            or not self.TokenIsLiveCombatant(target) then
            return false
        end
        local candidateRange = candidateAbility:GetRange(actor.properties, symbols)
        return MonsterAI.TargetDistance(candidateAbility:GetRangeSource(actor), target) <= candidateRange
            and candidateAbility:TargetPassesFilter(actor, target, symbols)
            and actor:GetLineOfSight(target, actor.properties:GetPierceWalls()) > 0
    end

    local function AbilityTargetsAreLegal(candidateAbility)
        if symbols.targetPairs ~= nil then
            for _,pair in ipairs(symbols.targetPairs) do
                if not PairIsLegal(candidateAbility, dmhub.GetTokenById(pair.a), dmhub.GetTokenById(pair.b)) then
                    return false
                end
            end
            return true
        end

        for _,targetInfo in ipairs(targets) do
            if targetInfo.token ~= nil
                and not PairIsLegal(candidateAbility, casterToken, targetInfo.token) then
                return false
            end
        end
        return true
    end

    --After a charge, strike whoever is still in reach rather than nobody: the
    --landing can differ from the plan, or a band can name a target it misses.
    if chargeAttempted and not ability.meleeAndRanged and symbols.targetPairs == nil
        and not AbilityTargetsAreLegal(ability) then
        local legal = {}
        local dropped = {}
        for _,targetInfo in ipairs(targets) do
            if targetInfo.token == nil or PairIsLegal(ability, casterToken, targetInfo.token) then
                legal[#legal+1] = targetInfo
            else
                dropped[#dropped+1] = targetInfo
            end
        end
        if #legal > 0 then
            self:LogDecision("ABILITY TARGETS DROPPED", {
                actor = self.TokenLogName(casterToken),
                actorId = casterToken ~= nil and casterToken.charid or nil,
                ability = ability.name,
                action = self.AbilityActionLogName(ability),
                targets = self.TargetsLogName(dropped),
                reason = "out of legal range or line of sight after the charge",
            })
            targets = legal
        end
    end

    -- Select the variation from the real post-movement position. A failed
    -- charge may fall back to ranged, but can never authorize a distant melee cast.
    if ability.meleeAndRanged then
        if AbilityTargetsAreLegal(ability.meleeVariation) then
            ability = ability.meleeVariation
        elseif AbilityTargetsAreLegal(ability.rangedVariation) then
            ability = ability.rangedVariation
        else
            self:LogDecision("ABILITY CAST REJECTED", {
                actor = self.TokenLogName(casterToken),
                actorId = casterToken ~= nil and casterToken.charid or nil,
                ability = ability.name,
                action = self.AbilityActionLogName(ability),
                targets = self.TargetsLogName(targets),
                reason = "no melee or ranged variation is legal from the actual position",
            })
            return false
        end
    elseif (chargeAttempted or (ability.targetType == "target" and not hasTargetArea))
        and not AbilityTargetsAreLegal(ability) then
        self:LogDecision("ABILITY CAST REJECTED", {
            actor = self.TokenLogName(casterToken),
            actorId = casterToken ~= nil and casterToken.charid or nil,
            ability = ability.name,
            action = self.AbilityActionLogName(ability),
            targets = self.TargetsLogName(targets),
            reason = "actual position does not leave every target in legal range and line of sight",
        })
        if chargeAttempted then
            self._tmp_moveFailure = "charge left target outside legal range or line of sight"
        end
        return false
    end

    if targetArea ~= nil and options.telegraphArea ~= false then
        self:TelegraphAreaAbility(ability, targetArea, symbols)
    end

    local rays = {}
    if symbols.targetPairs == nil then
        for _,target in ipairs(targets) do
            if target.token ~= nil then
                rays[#rays+1] = dmhub.MarkLineOfSight(casterToken, target.token, casterToken.properties:GetPierceWalls())
            end
        end
    end

    --A strike at a target past melee reach (or one with no melee use) is a
    --ranged attack. Checked here, before the cast moves anyone.
    local rangedStrike = false
    if (ability:HasKeyword("Strike") or ability.name == "Ranged Free Strike") and ability:HasKeyword("Ranged") then
        local reach = ability:HasKeyword("Melee") and ability:try_get("meleeRange", 1) or 0
        for _,target in ipairs(targets) do
            if target.token ~= nil and MonsterAI.TargetDistance(casterToken, target.token) > reach then
                rangedStrike = true
            end
        end
    end

    ability = ability:MakeTemporaryClone()

    --Keep multipleModes intact because behavior mode filters depend on it.
    --The AI already chose symbols.mode above, defaulting to mode 1, so only
    --the mode picker should be bypassed when this ability is invoked.
    options.modeResolved = true

    local startedAt = dmhub.Time()
    self:LogDecision("ABILITY CAST START", {
        actor = self.TokenLogName(casterToken),
        actorId = casterToken ~= nil and casterToken.charid or nil,
        ability = ability.name,
        action = self.AbilityActionLogName(ability),
        targets = self.TargetsLogName(targets),
        mode = symbols.mode,
        targetType = ability.targetType,
    })
    options.symbols = symbols
    options.targets = targets
    options.countsAsCast = true

    local finished = false

    local maliceQueue = dmhub.initiativeQueue
    local maliceHistory = nil
    local maliceKey = nil
    if ability.categorization == "Malice" and maliceQueue ~= nil and not maliceQueue.hidden then
        maliceHistory = MaliceAbilityHistory(maliceQueue)
        maliceKey = MaliceAbilityHistoryKey(ability)
    end

	local OnFinishCast = ability:try_get("OnFinishCast")
    ability.OnFinishCast = function (ability, options)
        if maliceHistory ~= nil and not options.abort and not options.atexit then
            --maliceKey is set together with maliceHistory above.
            ---@cast maliceKey -nil
            maliceHistory[maliceKey] = true
        end
        if OnFinishCast then
            OnFinishCast(ability, options)
        end
        
        finished = true
    end

    --Every event this cast raises on a hero (the damage it deals, the effects
    --it applies) is stamped with an AI activity by creature:DispatchEvent, so a
    --prompt it provokes -- the Talent's Repulsive Ward -- is a pending reaction
    --the wait below holds the AI on, exactly as an opportunity attack holds a
    --MoveToken. A caller that already opened an activity on the caster
    --(ExecuteAdvanceFallback) keeps its id; its own later wait is then a no-op.
    local previousActivityId = creature.GetTokenAIActivity(casterToken.charid)
    local activityId = previousActivityId or dmhub.GenerateGuid()
    --Casts nest (Dread March runs each marching undead's speech as its own
    --cast), so restore the outer cast's activity afterwards rather than
    --clearing it: cleared, the outer cast's later damage carried no activity
    --and the AI stopped waiting on the heroes' triggers (Ward of Nature's
    --Affection, 2026-10-18 playtest).
    local previousInProgress = creature.GetAIActivityInProgress()
    creature.SetTokenAIActivity(casterToken.charid, activityId)
    creature.SetAIActivityInProgress(activityId)

    local castOk, castErr = RunYieldingFunction(function()
        ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(casterToken, ability, casterToken, "inherit", symbols, options)

        while not finished do
            coroutine.yield(0.1)
        end
    end)

    creature.SetAIActivityInProgress(previousInProgress)
    creature.SetTokenAIActivity(casterToken.charid, previousActivityId)
    if not castOk then
        error(castErr)
    end

    if rangedStrike then
        local strikers = self:try_get("_tmp_rangedStrikers") or {}
        strikers[casterToken.charid] = true
        self._tmp_rangedStrikers = strikers
    end

    self:LogDecision("ABILITY CAST FINISHED", {
        actor = self.TokenLogName(casterToken),
        actorId = casterToken ~= nil and casterToken.charid or nil,
        ability = ability.name,
        action = self.AbilityActionLogName(ability),
        targets = self.TargetsLogName(targets),
        result = "OnFinishCast received",
        duration = dmhub.Time() - startedAt,
    })

    local completed, reason = self:WaitForActivityReactions(activityId)
    if not completed then
        self._tmp_abortTurn = reason
        error(reason)
    end
    self.Sleep(options.sleep or 1.0)

    self:ResolvePendingMinionDeaths()

    for _,ray in ipairs(rays) do
        ray:DestroyLineOfSight()
    end
end

function MonsterAI:FindReachableConcealment()
    local bestLoc = nil
    local bestScore = nil
    for _,info in pairs(self.paths) do
        local destLoc = info.loc

        if bestScore == nil or info.cost < bestScore then
            self:ExecuteWithTheoreticalMovementLoc(self.token, destLoc, function()
                if self.token.properties:IsConcealed() then
                    bestLoc = info.loc
                    bestScore = info.cost
                end
            end)
        end
    end

    return bestLoc
end

function MonsterAI:Speech(token, text, options)
    if not token.valid then
        return
    end
    if type(text) == "table" then
        text = text[math.random(1, #text)]
    end
    local ability = MCDMImporter.GetStandardAbility("Speech")
    --nil when the standardAbilities table has no "Speech" row; the speech is cosmetic, so skip it.
    if ability == nil then
        return
    end
    ability = ability:MakeTemporaryClone()

    MCDMUtils.DeepReplace(ability, "<<text>>", text)
    self:ExecuteAbility(token, ability, {}, options)
end

--The id of a language given by id or by name (case-insensitive), or nil.
--- @param idOrName string
--- @return string|nil
function MonsterAI.FindLanguageId(idOrName)
    local languages = dmhub.GetTable(Language.tableName) or {}
    if languages[idOrName] ~= nil then
        return idOrName
    end
    local wanted = string.lower(idOrName)
    for id, language in unhidden_pairs(languages) do
        if string.lower(tostring(language.name)) == wanted then
            return id
        end
    end
    return nil
end

--Show a speech bubble over a token straight away. Speech() casts an ability
--and waits for it, so several tokens could not talk at once; this writes the
--bubble directly, as the Character Speech behavior does. A creature that
--speaks no language says "...".
--options.language: a language id or name (e.g. "Caelian") to speak in
--instead of the creature's own, so players who know it can read the line.
function MonsterAI:SpeakNow(token, text, options)
    if not self.TokenIsLiveCombatant(token) then
        return
    end
    if type(text) == "table" then
        text = text[math.random(1, #text)]
    end
    local language = nil
    if options ~= nil and options.language ~= nil then
        language = MonsterAI.FindLanguageId(options.language)
    end
    if language == nil then
        language = token.properties:CurrentlySpokenLanguage()
        if language == nil then
            text = "..."
        end
    end
    token:ModifyProperties{
        description = "Speech",
        undoable = false,
        execute = function()
            token.properties:CharacterSpeech{
                text = text,
                langid = language,
            }
        end,
    }
end

--A squad's battle cry before it moves: the captain (or, without one, a
--planned member) calls the attack, then two or three others shout back together.
function MonsterAI:AnnounceSquadStrike(plans, ability)
    local speakers = {}
    for _,plan in ipairs(plans) do
        if self.TokenIsLiveCombatant(plan.token) then
            speakers[#speakers+1] = plan.token
        end
    end
    for i=#speakers,2,-1 do
        local j = math.random(1, i)
        speakers[i], speakers[j] = speakers[j], speakers[i]
    end

    local caller = nil
    if self.squadCaptain and self.TokenIsLiveCombatant(self.squadCaptain) then
        caller = self.squadCaptain
    else
        caller = table.remove(speakers)
    end
    if caller == nil then
        return
    end
    self:SpeakNow(caller, ability:HasKeyword("Melee") and self.squadCallLines.melee or self.squadCallLines.ranged)

    local answerCount = math.min(#speakers, math.random(2, 3))
    if answerCount > 0 then
        self.Sleep(0.35)
        local lines = {}
        for i,line in ipairs(self.squadAnswerLines) do
            lines[i] = line
        end
        for i=#lines,2,-1 do
            local j = math.random(1, i)
            lines[i], lines[j] = lines[j], lines[i]
        end
        for i=1,answerCount do
            self:SpeakNow(speakers[i], lines[(i-1) % #lines + 1])
        end
    end
    self.Sleep(0.8)
end

function MonsterAI:LogMove(monsterType, moveid, message, options)
    options = options or {}
    if self.log.analysis == nil then
        self.log.analysis = self:Analysis()
        self.log.updatedAnalysis = dmhub.GenerateGuid()
    end

    for _,entry in ipairs(self.log.analysis) do
        if entry.monsterType == monsterType then
            for _,move in ipairs(entry.moves) do
                if move.id == moveid then
                    move.log = move.log or {}
                    if #move.log > 0 and options.onlyIfEmpty then
                        return
                    end
                    move.log[#move.log+1] = message
                    return
                end
            end
        end
    end
end

MonsterAI.AbilityCategories = {
    "Malice Abilities",
    "Main Actions",
    "Basic Strikes",
    "Maneuvers",
    "Villain Actions",
    "Tactics",
}

local g_abilityCategoryOrder = {}
for i,cat in ipairs(MonsterAI.AbilityCategories) do
    g_abilityCategoryOrder[cat] = i
end

--- A move, tactic, Malice ability or villain action a monster type can use, as
--- listed in the Monster AI panel's analysis.
--- @class MonsterAIAnalysisMove
--- @field id string
--- @field category string
--- @field abilities string[]
--- @field monsterType? string
--- @field description? string
--- @field enabled? boolean
--- @field synthesized? boolean True for fallback moves generated from ability metadata.
--- @field log? string[] Decision messages appended by MonsterAI:LogMove.

--- @class MonsterAIAnalysisEntry
--- @field monsterType string
--- @field language? Language The language the monster currently speaks.
--- @field moves MonsterAIAnalysisMove[]

--- @return MonsterAIAnalysisEntry[]
function MonsterAI:Analysis()
    local result = {}
    local monstersSeen = {}
    local tokens = dmhub.allTokens
    local queue = dmhub.initiativeQueue
    if queue ~= nil and (not queue.hidden) then
        for _,tok in ipairs(tokens) do
            local monsterType = tok.properties:try_get("monster_type", nil)
            local initiativeid = InitiativeQueue.GetInitiativeId(tok)
            if monsterType ~= nil and initiativeid ~= nil and queue.entries[initiativeid] ~= nil and (not queue:IsEntryPlayer(initiativeid)) and (not monstersSeen[monsterType]) then
                monstersSeen[monsterType] = true

                local languageid = tok.properties:CurrentlySpokenLanguage()
                ---@type Language|nil
                local language = nil
                if languageid then
                    language = dmhub.GetTable(Language.tableName)[languageid]
                end

                local resultEntry = {
                    monsterType = monsterType,
                    language = language,
                    moves = {},
                }
                result[#result+1] = resultEntry

                for moveid,move in pairs(self.moves) do
                    if self.MoveMatchesMonster(tok, move, true) then
                        resultEntry.moves[#resultEntry.moves+1] = {
                            monsterType = monsterType,
                            id = moveid,
                            description = move.description,
                            category = move.category,
                            abilities = move.abilities,
                            enabled = move.enabled ~= false,
                        }
                    end
                end

                if not tok.properties.minion then
                    local claimedAbilities = self:GetClaimedAbilityNames(tok)
                    for _,ability in ipairs(tok.properties:GetActivatedAbilities()) do
                        if not claimedAbilities[ability.name] then
                            local profile = self:GetSynthesizedAbilityProfile(tok, ability)
                            if profile ~= nil then
                                resultEntry.moves[#resultEntry.moves+1] = {
                                    monsterType = monsterType,
                                    id = SynthesizedMoveId(ability),
                                    description = string.format(
                                        "Fallback AI generated at %.2f confidence from the ability's %s and targeting metadata.",
                                        profile.confidence, profile.reason),
                                    category = cond(profile.actionResource == CharacterResource.maneuverResourceId
                                        or profile.actionResource == CharacterResource.freeManeuverResourceId,
                                        "Maneuvers", "Main Actions"),
                                    abilities = {ability.name},
                                    enabled = true,
                                    synthesized = true,
                                }
                            end
                        end
                    end
                end

                for moveid,move in pairs(self.maliceAbilities) do
                    if self.MaliceAbilityMatchesMonster(tok, move, true) then
                        resultEntry.moves[#resultEntry.moves+1] = {
                            monsterType = monsterType,
                            id = moveid,
                            description = move.description,
                            category = move.category,
                            abilities = move.abilities,
                            enabled = move.enabled ~= false,
                        }
                    end
                end

                for moveid,move in pairs(self.tactics) do
                    if self.MoveMatchesMonster(tok, move, true) then
                        resultEntry.moves[#resultEntry.moves+1] = {
                            monsterType = monsterType,
                            id = moveid,
                            description = move.description,
                            category = move.category,
                            abilities = {},
                            enabled = move.enabled ~= false,
                        }
                    end
                end

                for moveid,move in pairs(self.villainActions) do
                    if self.MoveMatchesMonster(tok, move, true) then
                        resultEntry.moves[#resultEntry.moves+1] = {
                            monsterType = monsterType,
                            id = moveid,
                            description = move.description,
                            category = move.category,
                            abilities = move.abilities,
                            enabled = move.enabled ~= false,
                        }
                    end
                end

                table.sort(resultEntry.moves, function(a,b)
                    return (g_abilityCategoryOrder[a.category or "Maneuvers"] or 0) < (g_abilityCategoryOrder[b.category or "Maneuvers"] or 0)
                end)

                if tok.properties.minion then
                    local abilities = tok.properties:GetActivatedAbilities()
                    for _,ability in ipairs(abilities) do
                        if MonsterAI.IsMinionSignatureAbility(ability) then
                            resultEntry.moves[#resultEntry.moves+1] = {
                                id = "Minion Signature Ability",
                                category = "Main Actions",
                                description = "The Squad will move into a position that can maximize their number of targets and then use this ability.",
                                abilities = {ability.name},
                            }
                        end
                    end
                end
            end
        end
    end

    return result
end


--- @param options {casterid: string, targets: {token: nil|CharacterToken, loc: nil|Loc}[], sleep: nil|number}
function MonsterAI:SetTargetsForExpectedPrompt(options)
   self._tmp_expectedPromptTarget = options
end

function MonsterAI:IsMoveEnabledForMonster(monsterType, id)
    local move = self.moves[id] or self.tactics[id] or self.maliceAbilities[id] or self.villainActions[id]
    if move ~= nil then
        if move.disabledForMonsters ~= nil and move.disabledForMonsters[monsterType] then
            return false
        end
        return true
    end
    return false
end

function MonsterAI:SetMoveEnabledForMonster(monsterType, id, enabled)
    local move = self.moves[id] or self.tactics[id] or self.maliceAbilities[id] or self.villainActions[id]
    if move ~= nil then
        move.disabledForMonsters = move.disabledForMonsters or {}
        move.disabledForMonsters[monsterType] = not enabled
    end
end

--"file.lua:line" of the code that called a Register* function below, kept
--as registeredAt so the bestiary assessment (MonsterAISupport.lua) can point
--at the hand-written AI. Chunk names look like "Monster AI : MonsterAIGoblins".
local function RegistrationCallSite()
    local info = debug.getinfo(3, "Sl")
    if info == nil then
        return nil
    end
    local file = string.match(info.source or "", ":%s*(.-)%s*$") or info.short_src or "?"
    return string.format("%s.lua:%d", file, info.currentline or 0)
end

function MonsterAI:RegisterMove(args)
    if args.category == nil then
        args.category = "Main Actions"
    end
    args.registeredAt = RegistrationCallSite()
    self.moves[args.id] = args
end

function MonsterAI:RegisterMaliceAbility(args)
    args.category = "Malice Abilities"
    args.minimumScore = args.minimumScore or self.maliceAbilityMinimumScore
    args.registeredAt = RegistrationCallSite()
    self.maliceAbilities[args.id] = args
end

function MonsterAI:RegisterVillainAction(args)
    args.category = "Villain Actions"
    args.registeredAt = RegistrationCallSite()
    self.villainActions[args.id] = args
end

function MonsterAI:RegisterPrompt(args)
    args.registeredAt = RegistrationCallSite()
    for _,prompt in ipairs(args.prompts) do
        self.prompts[prompt] = args
    end
end

function MonsterAI:RegisterTrigger(args)
    args.registeredAt = RegistrationCallSite()
    for _,guid in ipairs(args.abilityGuids or {}) do
        self.triggerHandlersByGuid[guid] = args
    end

    for _,abilityName in ipairs(args.abilities or {}) do
        if args.monsters ~= nil then
            for _,monsterType in ipairs(args.monsters) do
                local qualifiedName = string.format("%s:%s", monsterType, abilityName)
                self.triggerHandlersByMonsterAbility[qualifiedName] = args
            end
        else
            self.triggerHandlersByAbility[abilityName] = args
        end
    end

    for _,triggerText in ipairs(args.triggers or {}) do
        if args.monsters ~= nil then
            for _,monsterType in ipairs(args.monsters) do
                local qualifiedText = string.format("%s:%s", monsterType, triggerText)
                self.triggerHandlersByMonsterText[qualifiedText] = args
            end
        else
            self.triggerHandlersByText[triggerText] = args
        end
    end
end

function MonsterAI:RegisterTactic(args)
    args.category = "Tactics"
    self.tactics[args.id] = args
end

--- /testai support: drive the AI machinery for a single named ability on the
--- selected token, without needing an active combat or the AI thread running.

local function TestAIMessage(message)
    print("AI TEST::", message)
    chat.Send("/testai: " .. message)
end

--grant whatever the token is missing to pay for the ability: malice or other
--global pools, action/maneuver/triggered action usage, per-ability charges.
--Returns a list of human readable descriptions of what was granted.
local function TestAIGrantResources(token, ability)
    local resourcesTable = dmhub.GetTable(CharacterResource.tableName)
    local grantedQuantities = {}
    local grantedNames = {}

    for attempt=1,3 do
        local cost = ability:GetCost(token)
        if cost.canAfford then
            break
        end

        local resourcesAvailable = token.properties:GetResources()
        local globalGrants = {}
        local creatureGrants = {}

        for _,detail in ipairs(cost.details or {}) do
            if detail.canAfford == false and detail.cost ~= nil then
                local resourceInfo = resourcesTable[detail.cost]
                local refreshType = detail.refreshType
                if refreshType == nil and resourceInfo ~= nil then
                    refreshType = resourceInfo.usageLimit
                end

                if refreshType ~= nil and refreshType ~= "none" then
                    local max
                    if refreshType == "global" then
                        max = CharacterResource.GetGlobalResource(detail.cost)
                    else
                        max = resourcesAvailable[detail.cost] or 0
                    end
                    if detail.maxCharges ~= nil then
                        max = detail.maxCharges
                    end

                    local usage = token.properties:GetResourceUsage(detail.cost, refreshType)
                    local needed = (detail.quantity or 1) - (max - usage)
                    if needed > 0 then
                        local grant = {
                            resourceid = detail.cost,
                            refreshType = refreshType,
                            quantity = needed,
                        }
                        if resourceInfo ~= nil then
                            grant.name = resourceInfo.name
                        else
                            grant.name = "charges of " .. ability.name
                        end
                        if refreshType == "global" then
                            globalGrants[#globalGrants+1] = grant
                        else
                            creatureGrants[#creatureGrants+1] = grant
                        end
                    end
                end
            end
        end

        if #globalGrants == 0 and #creatureGrants == 0 then
            break
        end

        local function RecordGrant(grant)
            if grantedQuantities[grant.name] == nil then
                grantedNames[#grantedNames+1] = grant.name
            end
            grantedQuantities[grant.name] = (grantedQuantities[grant.name] or 0) + grant.quantity
        end

        for _,grant in ipairs(globalGrants) do
            CharacterResource.SetGlobalResource(grant.resourceid, CharacterResource.GetGlobalResource(grant.resourceid) + grant.quantity, "/testai grant")
            RecordGrant(grant)
        end

        if #creatureGrants > 0 then
            token:ModifyProperties{
                description = "Grant resources for /testai",
                undoable = false,
                execute = function()
                    for _,grant in ipairs(creatureGrants) do
                        token.properties:RefreshResource(grant.resourceid, grant.refreshType, grant.quantity, "/testai grant")
                    end
                end,
            }
            for _,grant in ipairs(creatureGrants) do
                RecordGrant(grant)
            end
        end

        --GetResources() is cached per game-update tick, so a same-frame
        --re-check of GetCost would not see grants that raised a pool
        --(e.g. the villain action budget). Bust the cache before re-checking.
        token.properties:InvalidateResources()
    end

    local granted = {}
    for _,name in ipairs(grantedNames) do
        granted[#granted+1] = string.format("%d %s", grantedQuantities[name], name)
    end
    return granted
end

--out of combat there is no initiative queue to enumerate combatants from, so
--treat every live token on the map as a combatant instead.
local function TestAISetupOutOfCombat(ai, token)
    ai.token = token
    ai.abilities = token.properties:GetActivatedAbilities()
    ai.enemyTokens = {}
    ai.allyTokens = {}
    ai.activeTactics = {}

    for id,tactic in pairs(ai.tactics) do
        if MonsterAI.MoveMatchesMonster(token, tactic) then
            ai.activeTactics[id] = tactic
        end
    end

    for _,other in ipairs(dmhub.allTokens) do
        if other.valid and other.properties ~= nil and not other.properties:IsDead() then
            if dmhub.TokensAreFriendly(token, other) then
                ai.allyTokens[#ai.allyTokens+1] = other
            else
                ai.enemyTokens[#ai.enemyTokens+1] = other
            end
        end
    end
end

local function TestAIExecuteSquadStrike(ai, token, ability)
    local squadid = token.properties:MinionSquad()
    ai.squadMembers = {}
    ai.squadCaptain = false
    if squadid == nil then
        ai.squadMembers[1] = {token = token}
    else
        for _,other in ipairs(dmhub.allTokens) do
            if other.valid and other.properties ~= nil and (not other.properties:IsDead())
                and other.properties:MinionSquad() == squadid then
                if other.properties.minion then
                    ai.squadMembers[#ai.squadMembers+1] = {token = other}
                elseif not ai.squadCaptain then
                    ai.squadCaptain = other
                end
            end
        end
    end

    local controls = {}
    for _,member in ipairs(ai.squadMembers) do
        controls[#controls+1] = {token = member.token, info = ai:BeginTokenControl(member.token)}
    end

    local struck = false
    local ok, err = RunYieldingFunction(function()
        struck = ai:ExecuteSquadStrike(ability)
    end)

    for _,control in ipairs(controls) do
        ai:EndTokenControl(control.token, control.info)
    end
    ai._tmp_expectedPromptTarget = nil

    if not ok then
        TestAIMessage(string.format("squad strike with \"%s\" failed: %s", ability.name, tostring(err)))
    elseif not struck then
        TestAIMessage(string.format("the squad could not find any targets for \"%s\".", ability.name))
    end
end

--used when no registered AI move covers the ability: position with the
--generic strike/burst logic and cast, mirroring the generic fallback moves.
local function TestAIExecuteGeneric(ai, token, ability)
    local ok, err = ai:RunWithTokenControl(token, function()
        if ability.targetType == "all" then
            local loc, score = ai:FindBestMoveToUseBurst(token, ability, function(targetToken)
                if targetToken:IsFriend(token) then
                    return -1
                end
                return 1
            end)
            if loc ~= nil and (score or 0) > 0 then
                ai:MoveToken(token, loc, {maxCost = 10000, ignoreFalling = false})
                ai.Sleep(0.5)
            end
            ai:ExecuteAbility(token, ability)
        elseif ability.targetType == "target" then
            local loc = ai:FindBestMoveToUseStrike(token, ability)
            if loc == nil then
                TestAIMessage(string.format("could not find any position to use \"%s\" from.", ability.name))
                return
            end

            ai:MoveToken(token, loc, {maxCost = 10000, ignoreFalling = false})
            ai.Sleep(0.5)

            local targets = ai:FindValidTargetsOfStrike(token, ability, loc)
            ai:ExecuteAbility(token, ability, targets)
        else
            --self, map, line, cube, emptyspace, etc: cast in place and let
            --any location prompts fall through to the DM to resolve.
            ai:ExecuteAbility(token, ability)
        end
    end)

    if not ok then
        TestAIMessage(string.format("generic execution of \"%s\" failed: %s", ability.name, tostring(err)))
    end
end

Commands.RegisterMacro{
    name = "testai",
    summary = "test the AI with one ability",
    doc = "Usage: /testai <ability name> [tier1|tier2|tier3]\nMakes the Monster AI use the named ability, maneuver, or villain action with the selected token. Works in or out of combat and whether or not the AI is running. Grants any resources needed to execute (malice, actions, maneuvers, the villain action budget and used state, ability charges). Uses the registered AI move for the ability when one exists (even if disabled in the panel); otherwise falls back to a generic strike/burst execution. Minion signature abilities execute as a squad strike. Note: a villain action cast this way is marked used for the encounter by the normal cast pipeline.\n\nAdd tier1, tier2 or tier3 (before or after the ability name) to force every power roll made during the run to that tier -- the same as clicking that row on the power table after the dice land. The dice still roll; the result is overridden.",
    completions = function(args, argIndex)
        local result = {}

        --the tier argument may be given as a second word.
        if argIndex == 2 then
            result[#result+1] = {text = "tier1", summary = "force tier 1"}
            result[#result+1] = {text = "tier2", summary = "force tier 2"}
            result[#result+1] = {text = "tier3", summary = "force tier 3"}
            return result
        end

        if argIndex ~= 1 then return {} end
        local tokens = dmhub.selectedTokens
        if tokens == nil or #tokens == 0 then
            return result
        end
        local token = tokens[1]
        if token.properties == nil then
            return result
        end
        local abilities = nil
        pcall(function() abilities = token.properties:GetActivatedAbilities() end)
        for _,ability in ipairs(abilities or {}) do
            local summary = ability:try_get("villainAction")
            if summary == nil then
                summary = cond(ability.categorization ~= "none", ability.categorization, "ability")
            end
            result[#result+1] = {text = ability.name, summary = summary}
        end
        table.sort(result, function(a, b) return a.text < b.text end)
        return result
    end,
    command = function(str)
        --hosting capability, not chrome: the machine that runs the AI (a
        --player host included) must be able to drive it by hand.
        if not IsDMOrPlayerHost() then
            print("/testai: DM only.")
            return
        end

        local name = trim(str or "")

        --Optional tier1/tier2/tier3 argument, accepted at either end so both
        --`/testai Bury the Point tier3` and `/testai tier3 Bury the Point` work.
        --Parsed BEFORE the quote strip below, so a quoted ability name followed
        --by the tier word still unquotes. Lua patterns have no case-insensitive
        --classes, hence the spelled-out character sets.
        local forcedTier = nil
        local stripped, tierText = string.match(name, "^(.-)%s+[Tt][Ii][Ee][Rr]([123])$")
        if stripped == nil then
            tierText, stripped = string.match(name, "^[Tt][Ii][Ee][Rr]([123])%s+(.-)$")
        end
        if tierText ~= nil then
            forcedTier = tonumber(tierText)
            name = trim(stripped)
        end

        if string.sub(name, 1, 1) == "\"" and string.sub(name, -1) == "\"" and #name >= 2 then
            name = trim(string.sub(name, 2, #name - 1))
        end
        if name == "" then
            TestAIMessage("usage: /testai <ability name> [tier1|tier2|tier3]")
            return
        end

        --the AI plans on the board: a creature selected off it does not count.
        local tokens = {}
        for _, tok in ipairs(dmhub.selectedTokens) do
            if tok.onBoard then
                tokens[#tokens+1] = tok
            end
        end
        if #tokens == 0 then
            TestAIMessage("select a token first.")
            return
        end

        local token = tokens[1]
        if token.properties == nil then
            TestAIMessage("the selected token has no creature properties.")
            return
        end

        local tokenName = token.name
        if tokenName == nil or tokenName == "" then
            tokenName = token.properties:try_get("monster_type", "The selected token")
        end

        local abilities = nil
        pcall(function() abilities = token.properties:GetActivatedAbilities() end)
        abilities = abilities or {}

        local ability = nil
        for _,a in ipairs(abilities) do
            if string.lower(a.name) == string.lower(name) then
                ability = a
                break
            end
        end

        if ability == nil then
            TestAIMessage(string.format("%s has no ability, maneuver, or villain action named \"%s\".", tokenName, name))
            return
        end

        local granted = TestAIGrantResources(token, ability)
        if #granted > 0 then
            TestAIMessage(string.format("granted %s to %s.", table.concat(granted, ", "), tokenName))
        end

        if not ability:CanAfford(token) then
            --diagnose exactly which cost components are still short.
            local cost = ability:GetCost(token)
            local missing = {}
            local resourcesTable = dmhub.GetTable(CharacterResource.tableName)
            for _,detail in ipairs(cost.details or {}) do
                if detail.canAfford == false and detail.cost ~= nil then
                    local rname = detail.cost
                    local rinfo = resourcesTable[detail.cost]
                    if rinfo ~= nil then
                        rname = rinfo.name
                    end
                    missing[#missing+1] = string.format("%s x%s", rname, tostring(detail.quantity or 1))
                end
            end
            if cost.cannotMove then
                missing[#missing+1] = "movement"
            end
            if cost.outOfAmmo then
                missing[#missing+1] = "ammo"
            end
            local missingText = ""
            if #missing > 0 then
                missingText = " Missing: " .. table.concat(missing, ", ") .. "."
            end
            TestAIMessage(string.format("%s still cannot afford \"%s\" even after granting resources; aborting.%s", tokenName, ability.name, missingText))
            return
        end

        local ai = MonsterAI.new{}
        --instance-level flag: this one-shot run is active even when the AI thread is not.
        ai.active = true

        --The run itself. Named rather than inlined into dmhub.Coroutine so the
        --forced-tier flag below can be cleared on every exit path -- the body has
        --several early returns and can also throw.
        local RunTestAI = function()
            local queue = dmhub.initiativeQueue
            if queue ~= nil and queue.hidden then
                queue = nil
            end

            if queue ~= nil then
                ai:SetupCombatants(token, queue)
            else
                TestAISetupOutOfCombat(ai, token)
            end
            ai:SetLogContext(token, {turn = "/testai"})

            ai.log.analysis = ai:Analysis()
            ai.log.updatedAnalysis = dmhub.GenerateGuid()

            ai.paths = ai:CalculateRemainingMovementPaths(token)

            --minion signature abilities execute as a squad strike, like the AI turn loop does.
            if token.properties.minion and MonsterAI.IsMinionSignatureAbility(ability) then
                TestAIMessage(string.format("%s: executing \"%s\" as a squad strike.", tokenName, ability.name))
                TestAIExecuteSquadStrike(ai, token, ability)
                ai:WaitForAbilityIdle()
                return
            end

            local villainSlot = ability:try_get("villainAction")
            local context = nil
            if villainSlot ~= nil then
                local round = nil
                if queue ~= nil then
                    round = queue.round
                end
                round = round or tonumber(string.match(villainSlot, "%d+")) or 1
                context = {
                    initiativeQueue = queue,
                    endedInitiativeId = nil,
                    round = round,
                }

                --clear the used flag and make sure the shared villain action
                --budget is available so the cast pipeline can consume it normally.
                pcall(function()
                    VillainActionState.ClearUsed(token.charid, villainSlot)
                    if CharacterResource.GetVillainActions() <= 0 then
                        CharacterResource.SetVillainActions(1, "/testai grant")
                    end
                end)
            end

            local candidates = {}
            local lowerName = string.lower(ability.name)

            if villainSlot ~= nil then
                for _,action in pairs(ai.villainActions) do
                    if MonsterAI.MoveMatchesMonster(token, action, true) and action.abilities ~= nil
                        and action.abilities[1] ~= nil and string.lower(action.abilities[1]) == lowerName then
                        candidates[#candidates+1] = {move = action, usingAbilities = {ability}, isVillainAction = true}
                    end
                end
            else
                for _,move in pairs(ai.moves) do
                    local usesAbility = false
                    if MonsterAI.MoveMatchesMonster(token, move, true) and move.abilities ~= nil then
                        for i=1,#move.abilities do
                            if string.lower(move.abilities[i]) == lowerName then
                                usesAbility = true
                                break
                            end
                        end
                    end

                    if usesAbility then
                        --like FindAndExecuteMove, every ability the move lists must be
                        --present and affordable -- but grant resources to any that fall short.
                        local usingAbilities = {}
                        for i=1,#move.abilities do
                            local moveAbility = FindAbilityByName(ai.abilities, move.abilities[i])
                            if moveAbility ~= nil and not moveAbility:CanAfford(token) then
                                local comboGranted = TestAIGrantResources(token, moveAbility)
                                if #comboGranted > 0 then
                                    TestAIMessage(string.format("granted %s to %s for \"%s\".", table.concat(comboGranted, ", "), tokenName, moveAbility.name))
                                end
                            end
                            if moveAbility == nil or not moveAbility:CanAfford(token) then
                                usingAbilities = nil
                                break
                            end
                            usingAbilities[#usingAbilities+1] = moveAbility
                        end

                        if usingAbilities ~= nil then
                            candidates[#candidates+1] = {move = move, usingAbilities = usingAbilities}
                        end
                    end
                end
            end

            local best = nil
            for _,candidate in ipairs(candidates) do
                local move = candidate.move
                ai:SetMoveLogContext(token, move)
                ai:LogDecision("MOVE SCORING", {
                    ability = ai.AbilitiesLogName(candidate.usingAbilities),
                    action = ai.AbilityActionsLogName(candidate.usingAbilities),
                    result = "/testai candidate",
                })
                local ok, scoringInfo
                if candidate.isVillainAction then
                    ok, scoringInfo = pcall(move.score, move, ai, token, candidate.usingAbilities[1], context)
                else
                    ok, scoringInfo = pcall(move.score, move, ai, token, candidate.usingAbilities[1], candidate.usingAbilities[2], candidate.usingAbilities[3])
                end

                if not ok then
                    TestAIMessage(string.format("scoring of AI move \"%s\" failed: %s", move.id, tostring(scoringInfo)))
                elseif scoringInfo ~= nil then
                    if type(scoringInfo) == "number" then
                        scoringInfo = {score = scoringInfo}
                    end
                    if type(scoringInfo) == "table" and type(scoringInfo.score) == "number" then
                        candidate.scoringInfo = scoringInfo
                        ai:LogDecision("MOVE CANDIDATE", {
                            ability = ai.AbilitiesLogName(candidate.usingAbilities),
                            action = ai.AbilityActionsLogName(candidate.usingAbilities),
                            score = scoringInfo.score,
                            plan = ai.ScoringPlanLogName(scoringInfo),
                            result = "legal /testai candidate",
                        })
                        if best == nil or scoringInfo.score > best.scoringInfo.score then
                            best = candidate
                        end
                    end
                else
                    ai:LogDecision("MOVE REJECTED", {
                        ability = ai.AbilitiesLogName(candidate.usingAbilities),
                        reason = "score callback returned no legal plan for /testai",
                    })
                end
            end

            if best ~= nil then
                local move = best.move
                TestAIMessage(string.format("%s: executing AI move \"%s\" (score %.2f).", tokenName, move.id, best.scoringInfo.score))
                ai:SetMoveLogContext(token, move)
                ai:LogDecision("MOVE SELECTED", {
                    ability = ai.AbilitiesLogName(best.usingAbilities),
                    action = ai.AbilityActionsLogName(best.usingAbilities),
                    score = best.scoringInfo.score,
                    plan = ai.ScoringPlanLogName(best.scoringInfo),
                    result = "/testai selected this registered move",
                })
                local ok, err = ai:RunWithTokenControl(token, function()
                    if best.isVillainAction then
                        move.execute(move, ai, token, best.scoringInfo, best.usingAbilities[1], context)
                    else
                        move.execute(move, ai, token, best.scoringInfo, best.usingAbilities[1], best.usingAbilities[2], best.usingAbilities[3])
                    end
                end)
                ai:WaitForAbilityIdle()
                if not ok then
                    TestAIMessage(string.format("execution of AI move \"%s\" failed: %s", move.id, tostring(err)))
                    ai:LogDecision("MOVE ERROR", {
                        reason = "execution failed: " .. tostring(err),
                    })
                else
                    ai:LogDecision("MOVE FINISHED", {
                        ability = ai.AbilitiesLogName(best.usingAbilities),
                        result = "/testai execution completed",
                    })
                end
                return
            end

            if #candidates > 0 then
                TestAIMessage(string.format("the AI declined to use \"%s\" right now (no registered move found a valid opportunity).", ability.name))
                return
            end

            TestAIMessage(string.format("%s: no AI move is registered for \"%s\"; using generic execution.", tokenName, ability.name))
            ai:SetMoveLogContext(token, {
                id = "/testai generic: " .. ability.name,
                category = ability:ActionResource() == CharacterResource.maneuverResourceId
                    and "Maneuvers" or "Main Actions",
            })
            ai:LogDecision("MOVE SELECTED", {
                ability = ability.name,
                action = ai.AbilityActionLogName(ability),
                result = "/testai generic execution",
            })
            TestAIExecuteGeneric(ai, token, ability)
            ai:WaitForAbilityIdle()
        end

        dmhub.Coroutine(function()
            --Same as a real AI turn: this drives monsters as the host, so it runs
            --with host permissions (see MonsterAI:PlayTurn).
            ElevateToHostPermissions()

            --test:aiforcetier is read by ActivatedAbilityPowerRollBehavior:Cast
            --as each power roll resolves; it stamps overrideTier onto the roll,
            --which is exactly what clicking that tier row would have done. It
            --applies to every power roll made while set, so keep it set for the
            --run and no longer.
            if forcedTier ~= nil then
                dmhub.SetSettingValue("test:aiforcetier", forcedTier)
                TestAIMessage(string.format("forcing tier %d for every power roll in this run.", forcedTier))
            end

            --RunYieldingFunction drives the body in a nested coroutine and hands
            --back any error rather than letting it escape, so the clear below
            --always runs.
            local ok, err = RunYieldingFunction(RunTestAI)

            if forcedTier ~= nil then
                dmhub.SetSettingValue("test:aiforcetier", 0)
            end

            if not ok then
                TestAIMessage(string.format("run failed: %s", tostring(err)))
            end

            DropHostPermissions()
        end)
    end,
}

--Profiler sections for the planning methods (see the profiler at the top of
--this file). Every method here must never yield. Wrapped last so the wrappers
--see the final definitions; band files call through them by method lookup.
for _,methodName in ipairs{
    "CanStrikeThisTurn",
    "Analysis",
    "SetupCombatants",
    "RefreshCombatants",
    "CalculateMovementPaths",
    "MovementLocOverlapsCreature",
    "ExecuteWithTheoreticalMovementLoc",
    "TargetDistanceFromLoc",
    "FindValidTargetsOfStrike",
    "ChargeProbe",
    "LeapProbe",
    "FindBestMoveToUseStrike",
    "FindBestMoveToUseBurst",
    "FindBestLinePlan",
    "FindSquadMemberStrikeOptions",
    "FindSquadActionToken",
    "FindBestSynthesizedAbilityMove",
    "GetSynthesizedAbilityProfile",
    "GetClaimedAbilityNames",
    "FindAdvancePlan",
    "FindReachableConcealment",
    "LogDecision",
} do
    ProfWrapMethod(MonsterAI, methodName, methodName)
end

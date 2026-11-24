local mod = dmhub.GetModLoading()

--The built Great Forge in the Encounter of the Week town: a crafting
--workshop. Before a player may use it, Giddlebrick Thundlestrom of the
--Tinkerer's Guild has to be talked round:
--  * the first visit plays a conversation (EotwLeads.PlayConversation) whose
--    opening depends on the account's standing -- "defender" (won the
--    Forge's siege), "builder" (100+ Project Points into building it) or
--    "stranger" -- and ends with the hero's choice: push for a station (the
--    negotiation) or leave;
--  * the negotiation is Lisa's EotW negotiation, played here by
--    NegotiationScene / NegotiationSceneStage (Draw Steel V), from the script
--    in EotwTextForgeNegotiation.lua;
--  * the City (city-core.ts "The Great Forge workshop") keeps the result:
--    interest 3 opens the Forge, 4 also puts 100 points into the account's
--    first treasure and 5 puts 150, anything lower locks the Forge to this
--    player for a while (2: 1 hour, 1: 4 hours, 0: 24 hours), shown on the
--    town map as a clock and countdown. A visit after the lock goes straight
--    to the talk. "Take the deal" only shows from interest 3, so a player
--    cannot stop on an offer that turns them away.
--Once in, each hero crafts one treasure at a time: Gold echelon 1 treasures
--with a project goal, rolled with Downtime Activities on the hero's
--"forge-craft" project, collected into their pack when done.
--Design: EncounterOfTheWeek.md, "The Great Forge workshop".

EotwForge = rawget(_G, "EotwForge") or {}

local T = UIText.T

local TEXT = "#efe4cc"
local DIM = "#c9bfa9"
local GOLD = "#d9b56a"
local AMBER = "#ffd38a"
local RED = "#ff8888"
local GREEN = "#9fd38a"

--Bumped whenever the Forge's status changes; UIs poll it.
EotwForge.revision = 0

--forgeView as the City last sent it, for which account, and when (dmhub.Time).
local m_status = nil
local m_statusUser = nil
local m_fetchedAt = -1000
local m_fetching = false
--when the lock ends, on dmhub.Time()'s clock (the City sends the time left).
local m_lockEnds = nil
--how long a fetched status is trusted before the map asks again.
local STATUS_SECONDS = 60

--the last town panel the Forge was shown in (for /eotwforge talk).
local m_host = nil

local function Bump()
    EotwForge.revision = EotwForge.revision + 1
end

local function SetStatus(status)
    if type(status) ~= "table" then
        return
    end
    m_status = status
    m_statusUser = dmhub.loginUserid
    m_fetchedAt = dmhub.Time()
    local remaining = (tonumber(status.remainingMs) or 0) / 1000
    m_lockEnds = cond(remaining > 0, dmhub.Time() + remaining, nil)
    Bump()
end

--The account's Forge as last fetched (nil before the first answer):
--{built, standing, access, bonus, bonusPoints, lastInterest, tries, remainingMs, crafts}.
function EotwForge.Status()
    if m_statusUser ~= dmhub.loginUserid then
        return nil
    end
    return m_status
end

--Ask the City for the account's Forge. onDone(ok, statusOrMessage).
function EotwForge.Fetch(onDone)
    local conn = EotwRoster.Connection()
    if conn == nil or not conn.connected then
        if onDone ~= nil then
            onDone(false, T("great_forge.workshop.offline"))
        end
        return
    end
    m_fetching = true
    conn:Request{
        action = "forge-status",
        args = {},
        success = function(result)
            m_fetching = false
            SetStatus(result)
            EotwForge.ResumePending()
            if onDone ~= nil then
                onDone(true, result)
            end
        end,
        error = function(message)
            m_fetching = false
            m_fetchedAt = dmhub.Time()
            if onDone ~= nil then
                onDone(false, message)
            end
        end,
    }
end

--When the Forge's lock on this player ends (dmhub.Time()), or nil if it is
--not locked. The town map's node reads this every half second, which also
--keeps the status fresh while the Forge is built.
function EotwForge.LockedUntil()
    if not EotwRoster.GreatForgeBuilt() then
        return nil
    end
    local stale = m_statusUser ~= dmhub.loginUserid or dmhub.Time() - m_fetchedAt > STATUS_SECONDS
    if stale and not m_fetching then
        EotwForge.Fetch(nil)
    end
    if m_statusUser ~= dmhub.loginUserid or m_lockEnds == nil or m_lockEnds <= dmhub.Time() then
        return nil
    end
    return m_lockEnds
end

--"1:23:45" (or "4:05" under an hour) for a number of seconds.
function EotwForge.FormatTime(seconds)
    local left = math.max(0, math.ceil(seconds))
    local hours = math.floor(left / 3600)
    local minutes = math.floor((left % 3600) / 60)
    if hours == 0 then
        return string.format("%d:%02d", minutes, left % 60)
    end
    return string.format("%d:%02d:%02d", hours, minutes, left % 60)
end

--- reporting the talk ---------------------------------------------------------------

--A finished talk the City has not acknowledged: { negotiationid, interest }.
--Kept on this machine per account until it is, so a crash cannot drop it.
setting{
    id = "eotw:pendingForgeTalk",
    default = "",
    storage = "preference",
}

local function SendTalk(talk, onDone)
    local conn = EotwRoster.Connection()
    if conn == nil or not conn.connected then
        if onDone ~= nil then
            onDone(false, T("great_forge.workshop.offline"))
        end
        return
    end
    conn:Request{
        action = "forge-negotiated",
        args = { negotiationid = talk.negotiationid, interest = talk.interest },
        success = function(result)
            EotwDowntime.UI.SaveMine("eotw:pendingForgeTalk", nil)
            SetStatus(result.forge)
            if onDone ~= nil then
                onDone(true, result.forge)
            end
        end,
        error = function(message)
            --refused (locked, not built): it will never be taken.
            EotwDowntime.UI.SaveMine("eotw:pendingForgeTalk", nil)
            if onDone ~= nil then
                onDone(false, message)
            end
        end,
    }
end

--Send a talk left over from last time, if any. Called after each status fetch.
function EotwForge.ResumePending()
    local _, talk = EotwDowntime.UI.LoadMine("eotw:pendingForgeTalk")
    if type(talk) == "table" and type(talk.negotiationid) == "string" and type(talk.interest) == "number" then
        SendTalk(talk, function(ok)
            if ok then
                printf("EotW town: recorded a Great Forge talk left over from last time (interest %d)", talk.interest)
            end
        end)
    end
end

--- the negotiation ----------------------------------------------------------------

local m_beat = nil
local m_beatText = nil

--Giddlebrick's negotiation, parsed from its script (re-parsed if the script
--text changed, e.g. a writer's edit reloaded).
function EotwForge.Beat()
    local text = T("forge.negotiation.script")
    if m_beat == nil or text ~= m_beatText then
        local beat, warnings = NegotiationScene.Parse(text)
        m_beat = beat
        m_beatText = text
        for _, warning in ipairs(warnings) do
            printf("EotW town: Great Forge negotiation script: %s", warning)
        end
    end
    return m_beat
end

--The starting attitude by standing (David 2026-11-15).
local ATTITUDE_BY_STANDING = { defender = "open", builder = "neutral", stranger = "suspicious" }

--The heroes at home who can speak, as the negotiation wants them.
local function Speakers()
    local result = {}
    for _, entry in ipairs(EotwLeads.HeroesAtHome()) do
        result[#result+1] = { charid = entry.hero.heroid, name = entry.tok.name or "", ownerId = dmhub.loginUserid }
    end
    return result
end

--The roll dialog's chips for the test's skills: "Skilled in Persuade",
--forced on, when the hero is trained in one of them (as a montage test does).
local function ApplySkilledModifier(c, modifiers, skillids)
    for _, m in ipairs(modifiers) do
        if m.modifier.name == "Skilled" then
            local names = {}
            for _, skillid in ipairs(skillids) do
                local skillInfo = dmhub.GetTable(Skill.tableName)[skillid]
                if skillInfo ~= nil and c:ProficientInSkill(skillInfo) then
                    m.modifier = DeepCopy(m.modifier)
                    m.modifier.name = string.format(tr("Skilled in %s"), skillInfo.name)
                    m.modifier.description = string.format(tr("Skill in %s gives you +2 on this roll"), skillInfo.name)
                    m.modifier.activationCondition = true
                    m.hint.result = true
                    return
                elseif skillInfo ~= nil then
                    names[#names + 1] = skillInfo.name
                end
            end
            if #names > 0 then
                m.modifier = DeepCopy(m.modifier)
                m.modifier.description = string.format(tr("Not skilled in %s"), table.concat(names, " or "))
            end
        end
    end
end

--A town test in the game's own roll dialog: 2d10 + the best characteristic
--the argument names, the Skilled chip, the hero's features, and a chip for
--each knack edge or bane saying why ("Edge: your Wealth is 2+"). The tier
--table shows, and the player throws the dice. The card is made inside
--`parent` (the negotiation overlay): the title screen has no ability sidebar.
--dialogHolder.card is the card up now, if any.
local function ShowRoll(args, parent, dialogHolder)
    local tok = dmhub.GetCharacterById(args.heroid)
    if tok == nil or not tok.valid or tok.properties == nil or parent == nil or not parent.valid then
        args.send("rollCancelled", { rollSeq = args.rollSeq })
        return
    end
    local c = tok.properties
    local characteristics, skills = NegotiationScene.ParseTest(args.attr)
    local attrid, best = nil, nil
    for id, _ in pairs(characteristics) do
        local attr = c:GetAttribute(id)
        if attr ~= nil and (best == nil or attr:Modifier() > best) then
            attrid, best = id, attr:Modifier()
        end
    end
    local skillids = {}
    for _, skill in ipairs(skills) do
        skillids[#skillids + 1] = skill.id
    end
    local title = string.format("%s: %s", args.name or "", args.attr or "")
    local rollType = "test_power_roll"
    local roll = string.format("2d10 + %d", best or 0)
    local modifiers = {}
    if attrid ~= nil then
        modifiers = c:GetModifiersForPowerRoll(roll, rollType, { attribute = attrid, title = title, skills = skillids })
    end
    ApplySkilledModifier(c, modifiers, skillids)
    TestRiders.AppendModifiers(modifiers, args.verdict, rollType)

    --the card: the test drawn as an ability, with the compact roll dialog
    --embedded in it, as a montage test shows in the ability sidebar.
    local old = dialogHolder.card
    if old ~= nil and old.valid then
        old:DestroySelf()
    end
    local ability = ActivatedAbility.Create{ isTest = true, name = title }
    local card = CreateAbilityTooltip(ability, { token = tok, width = 346, maxHeight = 900 })
    if card == nil then
        args.send("rollCancelled", { rollSeq = args.rollSeq })
        return
    end
    --as the sidebar does: the card is a picture, except for the parts the
    --embedded dialog turns back on (its close button).
    card:MakeNonInteractiveRecursive()
    local holder = gui.Panel{
        floating = true,
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "center",
        rmargin = 40,
        card,
    }
    dialogHolder.card = holder
    parent:AddChild(holder)
    local function Close()
        dmhub.Schedule(0.05, function()
            if holder.valid then
                holder:DestroySelf()
            end
        end)
    end

    local dialog = GameHud.CreateEmbeddedRollDialog()
    card:FireEventTree("embedRollDialog", dialog)

    local rollProperties = RollPropertiesPowerTable.new{ tiers = args.tiers, fullyImplemented = true }
    local settled = false
    --one frame for the embedded dialog to lay out first, as the montage does.
    dmhub.Schedule(0.05, function()
        if mod.unloaded or not dialog.valid then
            return
        end
        dialog.data.ShowDialog{
            title = title,
            description = T("negscene.roll.description", { hero = args.heroName or tok.name or "", name = args.name or "" }),
            creature = c,
            ability = ability,
            type = rollType,
            roll = roll,
            modifiers = modifiers,
            --the single target (the roller) is what lets the edge/bane chips
            --move the tier shown.
            multitargets = { { token = tok, boons = 0, banes = 0, modifiers = modifiers, triggers = {} } },
            targetCreature = c,
            showDialogDuringRoll = true,
            --gives the roll its Accept Result step.
            amendable = true,
            --once the dice are thrown the result stands.
            noCancelOnceThrown = true,
            rollProperties = rollProperties,
            PopulateCustom = ActivatedAbilityPowerRollBehavior.GetPowerTablePopulateCustom(rollProperties),
            completeRoll = function(rollInfo)
                settled = true
                Close()
                if mod.unloaded or not args.stillWanted() then
                    return
                end
                local tier = 1
                pcall(function() tier = RollUtils.DiceResultToTier(rollInfo) end)
                args.send("rolled", {
                    rollSeq = args.rollSeq,
                    tier = tier,
                    total = math.floor(tonumber(rollInfo.total) or 0),
                    natural = math.floor(tonumber(rollInfo.naturalRoll) or 0),
                })
            end,
            --closed before the dice were thrown: the hero picks again.
            cancelRoll = function()
                if settled or mod.unloaded then
                    return
                end
                settled = true
                Close()
                args.send("rollCancelled", { rollSeq = args.rollSeq })
            end,
        }
    end)
end

--Play the negotiation over the town. onDone(forge) once it is over and the
--City has the result (forge = the new status, or nil if nothing was sent or
--the City refused it).
--opts.preview (dev): play it as this standing and tell the City nothing, so
--the account's access, lock and crafts are untouched.
---@param host Panel
---@param opts {backdrop: string|nil, preview: string|nil}|nil
---@param onDone fun(forge: table|nil)
function EotwForge.ShowNegotiation(host, opts, onDone)
    opts = opts or {}
    local beat = EotwForge.Beat()
    local status = EotwForge.Status()
    if opts.preview ~= nil then
        status = { standing = opts.preview }
    end
    if beat == nil or status == nil or #Speakers() == 0 then
        onDone(nil)
        return
    end
    local negotiationid = dmhub.GenerateGuid()
    --what the City answered, once the talk is over: false while waiting.
    local reported = nil
    local overlay = nil
    --each hero's knack facts, read once per talk (the stage asks per card).
    local factsByHero = {}
    --the roll card up now, if any (ShowRoll).
    local rollDialog = { card = nil }

    local session = NegotiationScene.LocalSession{
        Beat = function()
            return beat
        end,
        Heroes = Speakers,
        --offers below 3 turn the player away (city-core.ts forgeLockoutMs).
        minDealInterest = 3,
        ShowRoll = function(args)
            ShowRoll(args, overlay, rollDialog)
        end,
        --knack arguments ("|Allow:") and edges, by the same rules as a montage.
        Verdict = function(charid, argument)
            local facts = factsByHero[charid]
            if facts == nil then
                local tok = dmhub.GetCharacterById(charid)
                if tok == nil or tok.properties == nil then
                    facts = TestRiders.CompleteFacts({})
                else
                    facts = TestRiders.CreatureFacts(tok.properties)
                end
                factsByHero[charid] = facts
            end
            return TestRiders.Evaluate(argument.riders, facts)
        end,
        Track = function(event, fields)
            if opts.preview ~= nil then
                return
            end
            fields.standing = status.standing
            EotwAnalytics.Track("eotw_forge_" .. event, fields)
        end,
        --how it ended decides the Forge: leaving before anyone spoke changes
        --nothing; otherwise the interest reached is reported.
        Finish = function(m, outcome, offer, b)
            if opts.preview ~= nil then
                printf("EotW town (dev): preview over: %s, interest %s", tostring(outcome), tostring(m.interest))
                reported = { sent = false }
                return {}
            end
            if outcome == "left" and #(m.log or {}) == 0 then
                reported = { sent = false }
                return {}
            end
            local talk = { negotiationid = negotiationid, interest = m.interest }
            EotwDowntime.UI.SaveMine("eotw:pendingForgeTalk", talk)
            reported = { sent = true, done = false }
            SendTalk(talk, function(ok, result)
                reported.done = true
                reported.forge = cond(ok, result, nil)
                if not ok then
                    printf("EotW town: the City refused the Great Forge talk: %s", tostring(result))
                end
            end)
            return {}
        end,
    }
    session:Begin{ attitude = ATTITUDE_BY_STANDING[status.standing] or "suspicious", finalOptions = { "deal" } }

    local function Close()
        if overlay ~= nil and overlay.valid then
            overlay:DestroySelf()
        end
        --wait (briefly) for the City's answer.
        local tries = 0
        local function Wait()
            if mod.unloaded then
                return
            end
            if reported == nil or not reported.sent then
                onDone(nil)
            elseif reported.done or tries >= 20 then
                onDone(reported.forge)
            else
                tries = tries + 1
                dmhub.Schedule(0.5, Wait)
            end
        end
        Wait()
    end

    local npc = EotwLeads.GIDDLEBRICK.npc
    overlay = gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        bgimage = cond(opts.backdrop ~= nil, opts.backdrop, "panels/square.png"),
        bgcolor = cond(opts.backdrop ~= nil, "#555555ff", "#000000ee"),
        children = {
            gui.Panel{
                width = "100%",
                height = "100%",
                bgimage = "panels/square.png",
                bgcolor = "#000000b0",
                interactable = false,
            },
            gui.Panel{
                floating = true,
                width = "100%",
                height = "100%",
                vpad = 20,
                borderBox = true,
                NegotiationSceneStage.Create{
                    session = session,
                    selfHosted = true,
                    leave = true,
                    canAct = function(charid)
                        return true
                    end,
                    figure = function()
                        return EotwLeads.Figure(npc.portrait, nil, "center", npc.video, npc.videoAspect)
                    end,
                    createHeroCard = function(entry, cardOpts)
                        cardOpts.showStats = false
                        --every hero here is the player's own: no "The party" line.
                        cardOpts.subtitle = function()
                            return ""
                        end
                        return EotwHeroCard.CreateHeroCard(entry, cardOpts)
                    end,
                    styles = EotwHeroCard.rules,
                    onDone = function(result)
                        Close()
                    end,
                },
            },
        },
    }
    host:AddChild(overlay)
end

--- the first visit's conversation --------------------------------------------------

--Giddlebrick's opening for this standing, ending with the hero's choice:
--"push" (to the negotiation) or "leave".
local function Opening(standing)
    local key = cond(standing == "defender" or standing == "builder", standing, "stranger")
    local function L(name)
        return T("forge.talk." .. key .. "." .. name)
    end
    return {
        npc = EotwLeads.GIDDLEBRICK.npc,
        conversation = function(heroName, tok)
            return {
                { who = "npc", text = L("line1_npc") },
                { who = "hero", text = L("line2_hero") },
                { who = "npc", text = L("line3_npc") },
                { who = "choice", options = {
                    { text = L("push_hero"), result = "push" },
                    { text = L("leave_hero"), result = "leave", lines = {
                        { who = "npc", text = L("leave_npc") },
                    } },
                } },
            }
        end,
    }
end

--Opening the built Forge: what Giddlebrick does about this player.
--  access              nothing: the workshop is open;
--  locked              close the location again (the map shows the clock);
--  never pushed yet    the conversation, then the negotiation if they push;
--  pushed before       straight to the negotiation.
--close() closes the location (a Leave, or a talk that locked the Forge).
---@param host Panel|nil
---@param opts {backdrop: string|nil}|nil
---@param close fun()
function EotwForge.OnOpen(host, opts, close)
    if host == nil then
        return
    end
    m_host = host
    EotwForge.Fetch(function(ok, status)
        if mod.unloaded or not ok or type(status) ~= "table" or not status.built then
            return
        end
        if status.access then
            return
        end
        if (tonumber(status.remainingMs) or 0) > 0 then
            close()
            return
        end
        EotwForge.Approach(host, opts, close)
    end)
end

--Go to Giddlebrick (from OnOpen, or the workshop's Talk button): the
--conversation the first time, else straight to the negotiation.
function EotwForge.Approach(host, opts, close)
    local status = EotwForge.Status()
    if host == nil or not host.valid or status == nil or status.access then
        return
    end
    local heroes = EotwLeads.HeroesAtHome()
    if #heroes == 0 then
        return
    end

    local function AfterTalk(forge)
        if mod.unloaded then
            return
        end
        if forge == nil then
            return
        end
        if forge.access then
            EotwDowntime.UI.ShowBanner(host, T("great_forge.workshop.access_banner"),
                cond(forge.bonus, T("great_forge.workshop.access_bonus_subtitle"), T("great_forge.workshop.access_subtitle")))
        else
            EotwDowntime.UI.ShowBanner(host, T("great_forge.workshop.refused_banner"),
                T("great_forge.workshop.refused_subtitle", { time = EotwForge.FormatTime((tonumber(forge.remainingMs) or 0) / 1000) }))
            close()
        end
    end

    if (tonumber(status.tries) or 0) > 0 then
        EotwForge.ShowNegotiation(host, opts, AfterTalk)
        return
    end
    local pick = heroes[math.random(#heroes)]
    EotwAnalytics.Track("eotw_forge_intro", { heroid = pick.hero.heroid, standing = status.standing })
    EotwLeads.PlayConversation(host, Opening(status.standing), pick.hero.heroid, function(result)
        if mod.unloaded then
            return
        end
        if result == "push" then
            EotwForge.ShowNegotiation(host, opts, AfterTalk)
        else
            close()
        end
    end)
end

--Dev: the first visit as this standing (opening, then the negotiation if the
--hero pushes), reporting nothing to the City.
---@param host Panel
---@param standing string
function EotwForge.Preview(host, standing)
    local heroes = EotwLeads.HeroesAtHome()
    if #heroes == 0 then
        print("EotW town (dev): no hero at home to speak")
        return
    end
    local opts = { preview = standing }
    local pick = heroes[math.random(#heroes)]
    EotwLeads.PlayConversation(host, Opening(standing), pick.hero.heroid, function(result)
        if mod.unloaded then
            return
        end
        if result == "push" then
            EotwForge.ShowNegotiation(host, opts, function()
            end)
        else
            print("EotW town (dev): preview: the hero left")
        end
    end)
end

--- the treasures ------------------------------------------------------------------

--A treasure's project goal: the number its "Project Goal" text starts with.
---@param item equipment
---@return integer|nil
local function ProjectGoal(item)
    local text = item:try_get("projectGoal", "")
    local n = type(text) == "string" and tonumber(string.match(text, "^%s*(%d+)")) or nil
    if n == nil or n < 1 then
        return nil
    end
    return math.floor(n)
end

--Leveled treasures rated Silver or Bronze overall that are fully automated
--through 4th level (David 2026-11-18). Each one's implementationDetails says
--what is missing at 5th and 9th level. Reviewed 2026-11-18.
EotwForge.GOLD_BELOW_5TH = {
    ["aba29226-030c-4c1c-baa9-318c366b9b6d"] = true, --Abjurer's Bastion
    ["9e8eea25-436a-4a04-975e-d28a87dca2e8"] = true, --Bloodbound Band
    ["158b8282-86cd-48a4-bb23-9ea6d4c724fc"] = true, --Bloody Hand Wraps
    ["403089f6-e0d6-4b23-9e76-1b68e1f35445"] = true, --Brittlebreaker
    ["df49e435-f1e4-4a48-bba2-5f4b22db0307"] = true, --Chain of the Sea and Sky
    ["4f0bb297-f296-4c8b-a3c8-52b0b7fa4333"] = true, --Horned Champion (beastheart only)
    ["02d796d9-2e7f-4ab6-8125-b4e291e77af2"] = true, --Icemaker Maul
    ["3cc6178c-ff64-4c19-aa07-3a9ccf64f528"] = true, --Knife of Nine
    ["0fab2312-e2ab-4bf4-bb14-d71dfd9bd678"] = true, --Molten Constrictor
    ["5b591629-185c-4451-86d1-60e7c0ffc919"] = true, --Onerous Bow
    ["7ad4f615-5b3b-47ae-9c41-c2f0faed324d"] = true, --Steeltongue
    ["021fbd10-0dff-40af-94ca-629a700715f1"] = true, --Third Eye Seeker
    ["37303870-6a01-4f63-9111-dbd1a6fe6c0e"] = true, --Thunderhead Bident
    ["c3c028c1-d3ce-452a-84d7-440c18010012"] = true, --Wetwork
}

--Silver echelon 1 consumables and trinkets whose gaps don't matter with no
--Director (David 2026-11-19), like EotwMarket.EXTRA_STOCK. Each one's gap is
--in its implementationDetails. Reviewed 2026-11-19. Deadweight is left out:
--its free strike while falling is not built, so it only adds fall damage.
EotwForge.EXTRA_TREASURES = {
    ["5969d015-13fd-40e2-b2d5-be67a4169f5a"] = true, --Catapult Dust
    ["19280d26-b619-4441-90d5-1d23d0deb9da"] = true, --Giant's-Blood Flame
    ["b4ff06aa-75ae-4ed5-86e5-e6e22a29e09e"] = true, --Imp's Tongue
    ["a6d7f43e-fb4d-488c-b588-2aaa58c54a28"] = true, --Mirror Token
    ["229966c5-e4d5-419d-94e6-18dc9aba8159"] = true, --Portable Cloud
    ["d71a0de3-99de-4a96-b3f3-0a65a21ff9db"] = true, --Snapdragon
    ["b2f04f55-0275-4e4e-a6b4-23dc3ffce594"] = true, --Color Cloak - Red
    ["cf2b74c7-e511-45c2-b0be-517eddf0bdcc"] = true, --Divine Vine
    ["d20ae94a-9917-43be-b69b-38113b36fc97"] = true, --Gecko Gloves
    ["15987441-aa72-4fad-bc72-85b841c53e2b"] = true, --Speaking Scarab (companion only)
}

--What the Forge can craft (David 2026-11-15: Gold echelon 1 treasures for
--now, prerequisites ignored; imbuements left out; plus GOLD_BELOW_5TH and
--EXTRA_TREASURES): { {itemid, item, goal}, ... } by name.
function EotwForge.Treasures()
    local result = {}
    local gear = dmhub.GetTable("tbl_Gear") or {}
    for itemid, item in unhidden_pairs(gear) do
        local goal = ProjectGoal(item)
        --an imbuement (imbueTargetType) improves another treasure: it is
        --not an item a hero can be handed, so it is not offered.
        if goal ~= nil
            and item:try_get("imbueTargetType") == nil
            and item:try_get("hiddenFromPlayers", false) ~= true
            and (tonumber(item:try_get("echelon", 1)) or 1) == 1
            and (EotwForge.GOLD_BELOW_5TH[itemid] or EotwForge.EXTRA_TREASURES[itemid] or (tonumber(item:try_get("implementation", 1)) or 1) >= gui.ImplementationStatus.Gold) then
            result[#result+1] = { itemid = itemid, item = item, goal = goal }
        end
    end
    table.sort(result, function(a, b)
        return tostring(a.item.name) < tostring(b.item.name)
    end)
    return result
end

--The codex's own item card as a tooltip, or just the name.
local function ItemTooltip(element, item, name)
    local tooltipFn = rawget(_G, "CreateItemTooltip")
    if item ~= nil and tooltipFn ~= nil then
        local ok = pcall(function()
            element.tooltip = tooltipFn(item, { valign = "center", width = 360 }, nil)
        end)
        if ok then
            return
        end
    end
    gui.Tooltip(name)(element)
end

local function ItemIcon(item, size)
    local icon = item ~= nil and item:try_get("iconid", "") or ""
    return gui.Panel{
        interactable = false,
        width = size,
        height = size,
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#1d1913",
        borderWidth = 1,
        borderColor = GOLD,
        cornerRadius = 4,
        gui.Panel{
            interactable = false,
            width = "84%",
            height = "84%",
            halign = "center",
            valign = "center",
            bgimage = cond(icon ~= "", icon, "phosphor/sword-fill.png"),
            bgcolor = "white",
        },
    }
end

--The characteristic a hero rolls on a treasure: its best of the ones the
--treasure lists (any of the five when it lists none).
local function CraftCharacteristic(tok, item)
    local allowed = item ~= nil and item:try_get("projectRollCharacteristic") or nil
    local best, bestValue = nil, nil
    for attrid, _ in pairs(creature.attributesInfo or {}) do
        if type(allowed) ~= "table" or next(allowed) == nil or allowed[attrid] then
            local value = EotwDowntime.UI.CharacteristicValue(tok, attrid)
            if bestValue == nil or value > bestValue then
                best, bestValue = attrid, value
            end
        end
    end
    return best, bestValue or 0
end

--- the treasure picker --------------------------------------------------------------

--Choose what a hero crafts: every treasure on offer, with a search box and
--the item's card on hover. onStart(itemid, item, goal) when one is picked.
function EotwForge.ShowPicker(host, heroid, onStart)
    if host == nil or not host.valid then
        return
    end
    local tok = dmhub.GetCharacterById(heroid)
    local heroName = (tok ~= nil and tok.name) or T("great_forge.workshop.your_hero")
    local treasures = EotwForge.Treasures()
    local state = { filter = "", selected = nil }
    local dlg = nil
    local grid = nil
    local startButton = nil
    local Render

    local function Close()
        if dlg ~= nil and dlg.valid then
            dlg:DestroySelf()
        end
    end

    local function Card(entry)
        local item = entry.item
        local name = tostring(item.name)
        local selected = state.selected ~= nil and state.selected.itemid == entry.itemid
        return gui.Panel{
            classes = { "forgeTreasure", cond(selected, "selected", nil) },
            width = 196,
            height = 74,
            hmargin = 4,
            vmargin = 4,
            flow = "horizontal",
            hpad = 8,
            borderBox = true,
            bgimage = "panels/square.png",
            linger = function(element)
                ItemTooltip(element, item, name)
            end,
            press = function(element)
                audio.FireSoundEvent("Mouse.Click")
                state.selected = entry
                Render()
            end,
            ItemIcon(item, 44),
            gui.Panel{
                interactable = false,
                width = "100%-54",
                height = "auto",
                flow = "vertical",
                valign = "center",
                lmargin = 8,
                gui.Label{
                    interactable = false,
                    text = name,
                    fontSize = 15,
                    bold = true,
                    color = TEXT,
                    width = "100%",
                    height = "auto",
                    textWrap = true,
                },
                gui.Label{
                    interactable = false,
                    text = T("great_forge.workshop.goal", { goal = entry.goal }),
                    fontSize = 13,
                    color = DIM,
                    width = "100%",
                    height = "auto",
                },
            },
        }
    end

    Render = function()
        if grid == nil or not grid.valid then
            return
        end
        local filter = string.lower(state.filter or "")
        local cards = {}
        for _, entry in ipairs(treasures) do
            if filter == "" or string.find(string.lower(tostring(entry.item.name)), filter, 1, true) ~= nil then
                cards[#cards+1] = Card(entry)
            end
        end
        if #cards == 0 then
            cards[1] = gui.Label{ text = T("great_forge.workshop.picker_none"), fontSize = 16, italics = true, color = DIM, width = "auto", height = "auto", halign = "center", vmargin = 20 }
        end
        grid.children = cards
        if startButton ~= nil and startButton.valid then
            local entry = state.selected
            startButton:SetClass("collapsed", entry == nil)
            if entry ~= nil then
                startButton.text = T("great_forge.workshop.start_button", { item = tostring(entry.item.name) })
            end
        end
    end

    dlg = gui.Panel{
        floating = true,
        width = 900,
        height = 820,
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#14110dff",
        borderWidth = 2,
        borderColor = "#8c7a55",
        cornerRadius = 10,
        flow = "vertical",
        pad = 24,
        borderBox = true,
        styles = {
            Styles.Default,
            { selectors = { "forgeTreasure" }, bgcolor = "#1d1913", cornerRadius = 6, borderWidth = 1, borderColor = "#3a3125" },
            { selectors = { "forgeTreasure", "hover" }, borderColor = GOLD, brightness = 1.15 },
            { selectors = { "forgeTreasure", "selected" }, borderColor = AMBER, borderWidth = 2, bgcolor = "#2a2216" },
        },
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            Close()
        end,
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            gui.Panel{
                width = 30,
                height = 30,
                valign = "center",
                rmargin = 10,
                bgimage = "phosphor/flame-fill.png",
                bgcolor = GOLD,
            },
            gui.Label{
                text = T("great_forge.workshop.picker_title", { hero = heroName }),
                fontSize = 28,
                bold = true,
                color = TEXT,
                width = "100%-80",
                height = "auto",
                valign = "center",
            },
            gui.Panel{
                width = 22,
                height = 22,
                halign = "right",
                valign = "top",
                bgimage = "phosphor/x-bold.png",
                bgcolor = DIM,
                linger = gui.Tooltip(T("great_forge.workshop.close_tooltip")),
                press = function()
                    audio.FireSoundEvent("UI.WindowClose")
                    Close()
                end,
            },
        },
        gui.Label{
            text = T("great_forge.workshop.picker_intro"),
            fontSize = 15,
            italics = true,
            color = DIM,
            width = "100%",
            height = "auto",
            vmargin = 6,
        },
        gui.Input{
            width = 320,
            height = 32,
            fontSize = 16,
            halign = "left",
            bmargin = 8,
            placeholderText = T("great_forge.workshop.search"),
            editlag = 0.2,
            edit = function(element)
                state.filter = element.text
                Render()
            end,
        },
        gui.Panel{
            width = "100%",
            height = "100%-200",
            flow = "horizontal",
            wrap = true,
            vscroll = true,
            valign = "top",
            create = function(element)
                grid = element
                Render()
            end,
        },
        gui.Button{
            classes = { "collapsed" },
            halign = "center",
            valign = "bottom",
            tmargin = 10,
            text = "",
            fontSize = 20,
            width = 420,
            height = 46,
            create = function(element)
                startButton = element
                Render()
            end,
            click = function()
                local entry = state.selected
                if entry == nil then
                    return
                end
                audio.FireSoundEvent("Mouse.Click")
                Close()
                onStart(entry.itemid, entry.item, entry.goal)
            end,
        },
    }
    host:AddChild(dlg)
end

--- crafting -------------------------------------------------------------------------

local function Request(action, args, onDone)
    local conn = EotwRoster.Connection()
    if conn == nil or not conn.connected then
        onDone(false, T("great_forge.workshop.offline"))
        return
    end
    conn:Request{
        action = action,
        args = args,
        success = function(result)
            onDone(true, result)
        end,
        error = function(message)
            onDone(false, message)
        end,
    }
end

--Developer/admin only (the server refuses anyone else): forget this
--account's Forge standing (Giddlebrick talks, access, lockout) and its
--heroes' treasures, so the first visit plays again. onDone(ok, result),
--result = {deleted, forge} or the refusal message.
---@param onDone fun(ok: boolean, result: any)|nil
function EotwForge.DevReset(onDone)
    Request("dev-reset-forge", {}, function(ok, result)
        if ok and type(result) == "table" then
            SetStatus(result.forge)
        end
        if onDone ~= nil then
            onDone(ok, result)
        end
    end)
end

--Start a hero on a treasure.
function EotwForge.StartCraft(heroid, itemid, item, goal, onDone)
    Request("forge-start-craft", { heroid = heroid, itemid = itemid, itemName = tostring(item.name), goal = goal }, function(ok, result)
        if ok then
            SetStatus(result.forge)
            EotwAnalytics.Track("eotw_forge_start", { heroid = heroid, itemid = itemid, item = tostring(item.name), goal = goal })
        end
        onDone(ok, result)
    end)
end

--One roll on a hero's treasure: a Downtime Activity, or a breakthrough's
--free follow-up (breakthroughOf = its rollid). Kept until the City has it,
--as every project roll is (EotwDowntime.ResumePending sends it on).
--args = {heroid, breakthroughOf?, previewPanel?, begin = function(rollInfo,
--bonus)?, cancel?, rolled = function(natural, total)?, done = function(ok,
--resultOrMessage)}. With previewPanel (a gui.DicePreview cage) the dice are
--only armed: they rest there until the player clicks or throws them, as in
--EotwDowntime.Roll. done runs once the City has answered and the Forge's
--status has been fetched again.
function EotwForge.Roll(args)
    local heroid = args.heroid
    local tok = dmhub.GetCharacterById(heroid)
    local craft = EotwForge.Craft(heroid)
    if tok == nil or craft == nil then
        args.done(false, T("great_forge.workshop.not_ready"))
        return
    end
    local item = (dmhub.GetTable("tbl_Gear") or {})[craft.itemid]
    local attrid, bonus = CraftCharacteristic(tok, item)
    local roll = {
        rollid = dmhub.GenerateGuid(),
        projectid = "forge-craft",
        heroid = heroid,
        characteristic = attrid or "",
        skill = "",
        breakthroughOf = args.breakthroughOf,
    }
    dmhub.Roll{
        roll = string.format("2d10%+d", bonus),
        description = T("great_forge.workshop.roll_description", { hero = tok.name or "", item = craft.itemName or "" }),
        preview = args.previewPanel ~= nil,
        previewPanel = args.previewPanel,
        --a throw too weak to roll: the dice go back to rest.
        cancel = function()
            if not mod.unloaded and args.cancel ~= nil then
                args.cancel()
            end
        end,
        begin = function(rollInfo)
            if not mod.unloaded and args.begin ~= nil then
                args.begin(rollInfo, bonus)
            end
        end,
        complete = function(rollInfo)
            if mod.unloaded then
                return
            end
            roll.natural = math.floor(tonumber(rollInfo.naturalRoll) or 0)
            roll.total = math.floor(tonumber(rollInfo.total) or 0)
            --dev: /eotwdowntime breakthrough makes this roll a natural 20 too.
            if EotwDowntime.forceBreakthrough then
                EotwDowntime.forceBreakthrough = false
                roll.natural = 20
                roll.total = 20 + bonus
            end
            EotwDowntime.UI.SaveMine("eotw:pendingProjectRoll", roll)
            if args.rolled ~= nil then
                args.rolled(roll.natural, roll.total)
            end
            Request("project-roll", roll, function(ok, result)
                EotwDowntime.UI.SaveMine("eotw:pendingProjectRoll", nil)
                if ok then
                    EotwRoster.SetListedDowntime(heroid, result.downtime)
                    EotwAnalytics.Track("eotw_forge_roll", { heroid = heroid, itemid = craft.itemid, natural = roll.natural,
                        total = roll.total, completed = result.completed, breakthrough = result.breakthrough })
                end
                EotwForge.Fetch(function()
                    if not mod.unloaded then
                        args.done(ok, result)
                    end
                end)
            end)
        end,
    }
end

--The crafting roll dialog for one hero's treasure: the treasure, its
--progress bar and the roll's formula over a cage of real dice the player
--clicks or throws. Each roll's result shows in the middle and eases onto
--the bar. It stays open while the hero can roll again (Downtime left, or a
--breakthrough's free roll), then the dice give way to a Close button.
function EotwForge.ShowCraftDialog(host, heroid)
    if host == nil or not host.valid then
        return
    end
    local UI = EotwDowntime.UI

    local state = {
        rolling = false,
        resultText = "",
        resultDetail = "",
        breakthrough = false,
        completed = false,
        message = "",
        natural = 0,
        total = 0,
    }

    local dlg = nil
    local body = nil
    local hintLabel = nil
    local finishButton = nil
    local cage = nil
    --what the dice are armed for ("free:<rollid>" or "downtime"), nil = not armed.
    local armedSignature = nil

    local bar, barCtl = UI.ProgressBar(26)
    do
        local craft = EotwForge.Craft(heroid)
        barCtl.Set(craft ~= nil and tonumber(craft.points) or 0, craft ~= nil and tonumber(craft.goal) or 0)
    end

    local function HeroName()
        local tok = dmhub.GetCharacterById(heroid)
        return (tok ~= nil and tok.name) or T("great_forge.workshop.your_hero")
    end

    local Render

    local function Disarm()
        armedSignature = nil
        if cage ~= nil and cage.valid then
            pcall(function() cage:CancelDicePreviewRoll() end)
        end
    end

    local function Close()
        if state.rolling then
            return
        end
        barCtl.StopDice()
        Disarm()
        if dlg ~= nil and dlg.valid then
            dlg:DestroySelf()
        end
    end

    local function ArmDice(signature, free)
        Disarm()
        if cage == nil or not cage.valid then
            return
        end
        armedSignature = signature
        local craft = EotwForge.Craft(heroid)
        local itemName = craft ~= nil and craft.itemName or ""
        local goalBefore = craft ~= nil and tonumber(craft.goal) or 0
        EotwForge.Roll{
            heroid = heroid,
            breakthroughOf = free ~= nil and free.rollid or nil,
            previewPanel = cage,
            --the player threw the dice: the bar previews what they show as they tumble.
            begin = function(rollInfo, bonus)
                armedSignature = nil
                state.rolling = true
                state.message = ""
                state.resultText = "..."
                state.resultDetail = T("downtime.roll.dice_rolling")
                state.breakthrough = false
                if bar.valid then
                    barCtl.WatchDice(rollInfo.rolls, bonus)
                end
                Render()
            end,
            cancel = function()
                armedSignature = nil
                Render()
            end,
            rolled = function(natural, total)
                state.natural = natural
                state.total = total
                state.resultText = string.format("+%d", math.max(0, total))
                state.resultDetail = T("downtime.roll.result_natural", { natural = natural })
                state.breakthrough = natural >= EotwDowntime.BREAKTHROUGH_NATURAL
                if bar.valid then
                    barCtl.StopDice()
                    barCtl.Preview(math.max(0, total))
                end
                Render()
            end,
            done = function(ok, result)
                if not ok then
                    state.rolling = false
                    state.message = tostring(result)
                    if bar.valid then
                        barCtl.StopDice()
                        barCtl.Preview(nil)
                    end
                    Render()
                    return
                end
                local name = HeroName()
                if result.completed then
                    state.completed = true
                    state.resultDetail = cond(result.refunded,
                        T("great_forge.workshop.result_done_refunded", { natural = state.natural, item = itemName, hero = name }),
                        T("great_forge.workshop.result_done", { natural = state.natural, item = itemName }))
                end

                --the banners wait for the gain to settle on the bar.
                local function Announce()
                    if mod.unloaded then
                        return
                    end
                    if result.breakthrough and not result.completed then
                        UI.ShowBanner(host, T("great_forge.workshop.breakthrough_banner"),
                            T("great_forge.workshop.breakthrough_subtitle", { hero = name }))
                    elseif result.completed then
                        UI.ShowBanner(host, T("great_forge.workshop.done_banner", { item = itemName }),
                            T("great_forge.workshop.done_subtitle", { hero = name }))
                    end
                end

                if not bar.valid then
                    state.rolling = false
                    Announce()
                    return
                end
                --a finished craft fills the bar and stays full.
                local craftNow = EotwForge.Craft(heroid)
                local target = goalBefore
                if not result.completed then
                    target = craftNow ~= nil and tonumber(craftNow.points) or goalBefore
                end
                barCtl.AnimateTo(target, function()
                    state.rolling = false
                    Announce()
                    Render()
                end)
                Render()
            end,
        }
    end

    Render = function()
        if body == nil or not body.valid then
            return
        end
        local craft = EotwForge.Craft(heroid)
        local tok = dmhub.GetCharacterById(heroid)
        local downtime = EotwRoster.GetDowntime(heroid) or 0
        local away = EotwRoster.AwayHeroes()[heroid] ~= nil
        local free = craft ~= nil and (craft.open or {})[1] or nil

        if craft ~= nil and not craft.completed and not state.rolling and not barCtl.Busy() then
            barCtl.Update(tonumber(craft.points) or 0, tonumber(craft.goal) or 0)
        end

        local children = {}

        --the hero, their Downtime and the roll's formula.
        local heroRow = {
            UI.Portrait(tok, 36, 48),
            gui.Label{
                text = HeroName(),
                fontSize = 20,
                bold = true,
                color = TEXT,
                width = "auto",
                height = "auto",
                valign = "center",
                hmargin = 10,
            },
            UI.HammerChip(downtime),
        }
        if tok ~= nil and craft ~= nil then
            local item = (dmhub.GetTable("tbl_Gear") or {})[craft.itemid]
            local attrid = CraftCharacteristic(tok, item)
            if attrid ~= nil then
                local _, formula = EotwDowntime.RollBonus(tok, attrid, nil)
                heroRow[#heroRow+1] = gui.Label{
                    text = formula,
                    fontSize = 18,
                    color = TEXT,
                    width = "auto",
                    height = "auto",
                    halign = "right",
                    valign = "center",
                }
            end
        end
        children[#children+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 14,
            children = heroRow,
        }

        --the result of the last roll.
        children[#children+1] = gui.Panel{
            width = "100%",
            height = 110,
            flow = "vertical",
            tmargin = 14,
            gui.Label{
                classes = { cond(state.breakthrough, "visible", "collapsed") },
                text = T("downtime.roll.breakthrough_label"),
                fontFace = "display",
                fontSize = 30,
                color = AMBER,
                width = "auto",
                height = "auto",
                halign = "center",
            },
            gui.Label{
                text = state.resultText,
                fontSize = 40,
                bold = true,
                color = GOLD,
                width = "auto",
                height = "auto",
                halign = "center",
            },
            gui.Label{
                text = state.resultDetail,
                fontSize = 15,
                color = DIM,
                width = "auto",
                height = "auto",
                halign = "center",
            },
        }

        children[#children+1] = gui.Label{
            text = state.message,
            fontSize = 15,
            color = RED,
            width = "100%",
            height = 22,
            textAlignment = "center",
        }

        body.children = children

        local canRoll = craft ~= nil and not craft.completed and tok ~= nil and not away and (free ~= nil or downtime > 0)
        local finished = not state.rolling and not canRoll
        if finishButton ~= nil and finishButton.valid then
            finishButton:SetClass("collapsed", not finished)
        end

        local hint = ""
        if state.rolling then
            hint = ""
        elseif canRoll and free ~= nil then
            hint = T("downtime.roll.hint_free", { hero = HeroName() })
        elseif canRoll then
            hint = T("downtime.roll.hint_roll")
        elseif state.completed or (craft ~= nil and craft.completed) then
            hint = T("great_forge.workshop.done_subtitle", { hero = HeroName() })
        elseif away then
            hint = T("great_forge.workshop.away")
        elseif tok == nil or craft == nil then
            hint = T("great_forge.workshop.not_ready")
        else
            hint = T("great_forge.workshop.no_downtime")
        end
        if hintLabel ~= nil and hintLabel.valid then
            hintLabel.text = hint
        end

        if not state.rolling then
            if canRoll then
                local signature = cond(free ~= nil, "free:" .. tostring(free ~= nil and free.rollid or ""), "downtime")
                if signature ~= armedSignature then
                    ArmDice(signature, free)
                end
            elseif armedSignature ~= nil then
                Disarm()
            end
        end
    end

    local craftAtOpen = EotwForge.Craft(heroid)
    local itemAtOpen = craftAtOpen ~= nil and (dmhub.GetTable("tbl_Gear") or {})[craftAtOpen.itemid] or nil

    --A fixed size, as the project roll dialog: the top hangs from the top,
    --the hint and the dice sit on the bottom.
    dlg = gui.Panel{
        floating = true,
        width = 760,
        height = 620,
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#14110dff",
        borderWidth = 2,
        borderColor = "#8c7a55",
        cornerRadius = 10,
        flow = "none",
        pad = 24,
        borderBox = true,
        styles = { Styles.Default },
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            Close()
        end,
        data = { seen = -1 },
        thinkTime = 0.5,
        think = function(element)
            local rev = EotwForge.revision + EotwRoster.revision * 100000
            if element.data.seen ~= rev and not state.rolling then
                element.data.seen = rev
                Render()
            end
        end,

        --the top: the treasure, its bar, then the hero and the result.
        gui.Panel{
            floating = true,
            halign = "center",
            valign = "top",
            width = "100%",
            height = "auto",
            flow = "vertical",
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                bmargin = 10,
                gui.Panel{
                    width = 50,
                    height = 50,
                    valign = "center",
                    rmargin = 12,
                    bgimage = "panels/square.png",
                    bgcolor = "clear",
                    linger = function(element)
                        ItemTooltip(element, itemAtOpen, craftAtOpen ~= nil and craftAtOpen.itemName or "")
                    end,
                    ItemIcon(itemAtOpen, 50),
                },
                gui.Label{
                    text = T("great_forge.workshop.crafting", { item = craftAtOpen ~= nil and craftAtOpen.itemName or "" }),
                    fontSize = 28,
                    bold = true,
                    color = TEXT,
                    width = "100%-100",
                    height = "auto",
                    valign = "center",
                },
            },
            bar,
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                create = function(element)
                    body = element
                end,
            },
        },

        --the bottom: how to roll (or why not) over the dice.
        gui.Panel{
            floating = true,
            halign = "center",
            valign = "bottom",
            width = "100%",
            height = "auto",
            flow = "vertical",
            gui.Label{
                text = "",
                fontSize = 16,
                italics = true,
                color = AMBER,
                width = "100%",
                height = 46,
                textAlignment = "center",
                create = function(element)
                    hintLabel = element
                end,
            },
            --the dice rest here until clicked or thrown (built once: a rebuild
            --would drop the armed roll).
            gui.DicePreview{
                width = "70%",
                height = 120,
                halign = "center",
                bgimage = true,
                bgcolor = "white",
                styles = { gui.Style{ opacity = 0 } },
                draggable = true,
                dragMove = false,
                create = function(element)
                    ---@cast element DicePreview
                    cage = element
                    element:SetAsDicePreviewPanel(true)
                    pcall(function() element.dicePreviewScreenBounds = true end)
                    Render()
                end,
                destroy = function(element)
                    ---@cast element DicePreview
                    pcall(function() element:CancelDicePreviewRoll() end)
                    element:SetAsDicePreviewPanel(false)
                end,
                hover = function(element)
                    ---@cast element DicePreview
                    pcall(function() element:DicePreviewMouseEnter() end)
                end,
                dehover = function(element)
                    ---@cast element DicePreview
                    pcall(function() element:DicePreviewMouseLeave() end)
                end,
                click = function(element)
                    ---@cast element DicePreview
                    if armedSignature ~= nil then
                        pcall(function() element:DicePreviewClick() end)
                    end
                end,
                dragging = function(element)
                    ---@cast element DicePreview
                    pcall(function() element:DicePreviewDragThink() end)
                end,
                drag = function(element)
                    ---@cast element DicePreview
                    pcall(function() element:DicePreviewDragEnd() end)
                end,
            },
            --where the dice were, once there is nothing left to roll.
            gui.Button{
                classes = { "collapsed" },
                floating = true,
                halign = "center",
                valign = "bottom",
                bmargin = 34,
                text = T("downtime.roll.close_button"),
                fontSize = 24,
                width = 260,
                height = 54,
                create = function(element)
                    finishButton = element
                    Render()
                end,
                click = function()
                    Close()
                end,
            },
        },

        --close: an X in the top-right corner (not while dice are in the air).
        gui.Panel{
            floating = true,
            halign = "right",
            valign = "top",
            x = 10,
            y = -10,
            width = 22,
            height = 22,
            bgimage = "phosphor/x-bold.png",
            bgcolor = DIM,
            linger = gui.Tooltip(T("downtime.roll.close_tooltip")),
            press = function()
                if state.rolling then
                    return
                end
                audio.FireSoundEvent("UI.WindowClose")
                Close()
            end,
        },
    }
    UI.TrackDialog(dlg, function()
        barCtl.StopDice()
        Disarm()
        dlg:DestroySelf()
    end, function()
        return state.rolling
    end)
    host:AddChild(dlg)
end

--Collect a finished treasure: the City hands it over once, then it goes in
--the hero's pack and the hero is saved.
function EotwForge.Collect(heroid, onDone)
    local tok = dmhub.GetCharacterById(heroid)
    if tok == nil then
        onDone(false, T("great_forge.workshop.not_ready"))
        return
    end
    Request("forge-claim", { heroid = heroid }, function(ok, result)
        if not ok then
            onDone(false, result)
            return
        end
        if result.already or type(result.itemid) ~= "string" then
            EotwForge.Fetch(function()
                onDone(true, result)
            end)
            return
        end
        tok:ModifyProperties{
            description = "Collected a treasure from the Great Forge",
            undoable = false,
            execute = function()
                tok.properties:GiveItem(result.itemid, 1)
            end,
        }
        EotwAnalytics.Track("eotw_forge_collect", { heroid = heroid, itemid = result.itemid, item = result.itemName })
        --let the property write land before the export, as EotwMarket does.
        dmhub.Schedule(0.3, function()
            if mod.unloaded then
                return
            end
            EotwRoster.PushHero(heroid, function(pushed, message)
                EotwForge.Fetch(function()
                    onDone(true, result)
                end)
            end)
        end)
    end)
end

--Project Points per Downtime Activity a cancelled craft gives back (the
--City's FORGE_CANCEL_POINTS_PER_ROLL; the City decides, this only previews).
local CANCEL_POINTS_PER_ROLL = 40

--Downtime Activities cancelling this craft gives back: 1 per 40 points, partials nothing.
function EotwForge.CancelRefund(craft)
    return math.floor((tonumber(craft.points) or 0) / CANCEL_POINTS_PER_ROLL)
end

--Give up a hero's unfinished treasure. onDone(ok, resultOrMessage), result =
--{refunded, points, downtime, forge}.
function EotwForge.CancelCraft(heroid, onDone)
    local craft = EotwForge.Craft(heroid)
    Request("forge-cancel-craft", { heroid = heroid }, function(ok, result)
        if ok then
            SetStatus(result.forge)
            EotwRoster.SetListedDowntime(heroid, result.downtime)
            EotwAnalytics.Track("eotw_forge_cancel", { heroid = heroid, itemid = craft ~= nil and craft.itemid or nil,
                points = result.points, refunded = result.refunded })
        end
        onDone(ok, result)
    end)
end

--Asks before cancelling a hero's treasure, saying what comes back.
--onConfirm() runs on Yes.
local function ShowCancelConfirm(host, heroName, craft, onConfirm)
    if host == nil or not host.valid then
        return
    end
    local refund = EotwForge.CancelRefund(craft)
    local dlg
    local function Close()
        if dlg ~= nil and dlg.valid then
            dlg:DestroySelf()
        end
    end
    local function Button(text, run)
        return gui.Button{
            text = text,
            fontSize = 18,
            width = 180,
            height = 42,
            hmargin = 8,
            click = function()
                audio.FireSoundEvent("Mouse.Click")
                Close()
                if run ~= nil then
                    run()
                end
            end,
        }
    end
    dlg = gui.Panel{
        floating = true,
        width = 560,
        height = "auto",
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#14110dff",
        borderWidth = 2,
        borderColor = "#8c7a55",
        cornerRadius = 10,
        flow = "vertical",
        pad = 24,
        borderBox = true,
        styles = { Styles.Default },
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            Close()
        end,
        gui.Label{
            text = T("great_forge.workshop.cancel_title", { item = craft.itemName or "" }),
            fontSize = 26,
            bold = true,
            color = TEXT,
            width = "100%",
            height = "auto",
            textAlignment = "center",
        },
        gui.Label{
            text = cond(refund > 0,
                UIText.Plural("great_forge.workshop.cancel_refund", refund, { hero = heroName }),
                T("great_forge.workshop.cancel_no_refund", { hero = heroName })),
            fontSize = 17,
            color = DIM,
            width = "100%",
            height = "auto",
            textAlignment = "center",
            vmargin = 14,
        },
        gui.Panel{
            width = "auto",
            height = "auto",
            halign = "center",
            flow = "horizontal",
            Button(T("great_forge.workshop.cancel_confirm_button"), onConfirm),
            Button(T("great_forge.workshop.cancel_keep_button"), nil),
        },
    }
    host:AddChild(dlg)
end

--A hero's craft as last fetched, or nil.
function EotwForge.Craft(heroid)
    local status = EotwForge.Status()
    for _, craft in ipairs((status ~= nil and status.crafts) or {}) do
        if craft.heroid == heroid and not craft.delivered then
            return craft
        end
    end
    return nil
end

--- the workshop panel ---------------------------------------------------------------

local function Portrait(tok)
    return EotwDowntime.UI.Portrait(tok, 44, 58)
end

local function Bar(points, goal)
    local fraction = goal > 0 and math.min(1, points / goal) or 0
    return gui.Panel{
        interactable = false,
        width = "100%",
        height = 18,
        tmargin = 4,
        bgimage = "panels/square.png",
        bgcolor = "#0b0907",
        cornerRadius = 4,
        borderWidth = 1,
        borderColor = "#3a3125",
        gui.Panel{
            interactable = false,
            floating = true,
            halign = "left",
            width = string.format("%.1f%%", fraction * 100),
            height = "100%",
            bgimage = "panels/square.png",
            bgcolor = GOLD,
            cornerRadius = 4,
        },
        gui.Label{
            interactable = false,
            floating = true,
            text = T("great_forge.workshop.progress", { points = points, goal = goal }),
            fontSize = 13,
            bold = true,
            color = TEXT,
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
        },
    }
end

--One hero's row: who, what they are crafting and how far along, and the
--button for what they can do next.
local function HeroRow(host, hero, busy, setBusy)
    local tok = dmhub.GetCharacterById(hero.heroid)
    local name = (tok ~= nil and tok.name) or (hero.summary or {}).name or T("great_forge.workshop.your_hero")
    local away = EotwRoster.AwayHeroes()[hero.heroid] ~= nil
    local craft = EotwForge.Craft(hero.heroid)
    local downtime = EotwRoster.GetDowntime(hero.heroid) or 0
    local gear = dmhub.GetTable("tbl_Gear") or {}
    local item = craft ~= nil and gear[craft.itemid] or nil

    local status
    local buttonText = nil
    local blocked = nil
    local action = nil
    if tok == nil then
        status = T("great_forge.workshop.loading_hero")
    elseif away then
        status = T("great_forge.workshop.away")
        blocked = status
    end
    if craft == nil then
        status = status or T("great_forge.workshop.idle")
        buttonText = T("great_forge.workshop.choose_button")
        action = function()
            EotwForge.ShowPicker(host, hero.heroid, function(itemid, picked, goal)
                setBusy(true)
                EotwForge.StartCraft(hero.heroid, itemid, picked, goal, function(ok, result)
                    setBusy(false)
                    if not ok then
                        EotwDowntime.UI.ShowBanner(host, T("great_forge.workshop.error_banner"), tostring(result))
                    elseif type(result.craft) == "table" and result.craft.completed then
                        EotwDowntime.UI.ShowBanner(host, T("great_forge.workshop.done_banner", { item = tostring(picked.name) }),
                            T("great_forge.workshop.done_bonus_subtitle", { hero = name }))
                    end
                end)
            end)
        end
    elseif craft.completed then
        status = T("great_forge.workshop.finished", { item = craft.itemName })
        buttonText = T("great_forge.workshop.collect_button")
        action = function()
            setBusy(true)
            EotwForge.Collect(hero.heroid, function(ok, result)
                setBusy(false)
                if ok then
                    EotwDowntime.UI.ShowBanner(host, T("great_forge.workshop.collected_banner", { item = craft.itemName }),
                        T("great_forge.workshop.collected_subtitle", { hero = name }))
                else
                    EotwDowntime.UI.ShowBanner(host, T("great_forge.workshop.error_banner"), tostring(result))
                end
            end)
        end
    else
        status = status or T("great_forge.workshop.crafting", { item = craft.itemName })
        local free = (craft.open or {})[1]
        buttonText = cond(free ~= nil, T("great_forge.workshop.free_roll_button"), T("great_forge.workshop.work_button"))
        if free == nil and downtime < 1 then
            blocked = blocked or T("great_forge.workshop.no_downtime")
        end
        --the roll dialog: the player throws the dice and sees each result.
        action = function()
            EotwForge.ShowCraftDialog(host, hero.heroid)
        end
    end
    if busy then
        blocked = blocked or T("great_forge.workshop.busy")
    end

    local details = {
        gui.Label{
            text = name,
            fontSize = 18,
            bold = true,
            color = TEXT,
            width = "100%",
            height = "auto",
            textWrap = false,
            minFontSize = 12,
        },
        gui.Label{
            text = status,
            fontSize = 13,
            color = cond(craft ~= nil, AMBER, DIM),
            width = "100%",
            height = "auto",
        },
    }
    if craft ~= nil then
        details[#details+1] = Bar(tonumber(craft.points) or 0, tonumber(craft.goal) or 0)
    end

    local itemBox = nil
    if craft ~= nil then
        itemBox = gui.Panel{
            width = 50,
            height = 50,
            valign = "center",
            lmargin = 8,
            bgimage = "panels/square.png",
            bgcolor = "clear",
            linger = function(element)
                ItemTooltip(element, item, craft.itemName or "")
            end,
            ItemIcon(item, 50),
        }
    end

    --right-click an unfinished treasure to give it up for some Downtime back.
    local rightClick = nil
    if craft ~= nil and not craft.completed and tok ~= nil and not away then
        rightClick = function(element)
            if busy then
                return
            end
            element.popup = gui.ContextMenu{
                width = 220,
                entries = {
                    {
                        text = T("great_forge.workshop.cancel_menu"),
                        click = function()
                            element.popup = nil
                            ShowCancelConfirm(host, name, craft, function()
                                setBusy(true)
                                EotwForge.CancelCraft(hero.heroid, function(ok, result)
                                    setBusy(false)
                                    if not ok then
                                        EotwDowntime.UI.ShowBanner(host, T("great_forge.workshop.error_banner"), tostring(result))
                                    end
                                end)
                            end)
                        end,
                    },
                },
                click = function() element.popup = nil end,
            }
        end
    end

    return gui.Panel{
        width = "100%",
        height = 84,
        flow = "horizontal",
        vmargin = 2,
        hpad = 8,
        borderBox = true,
        bgimage = "panels/square.png",
        bgcolor = "#1d1913",
        cornerRadius = 6,
        opacity = cond(away, 0.5, 1),
        rightClick = rightClick,
        children = {
            Portrait(tok),
            itemBox or gui.Panel{ width = 0, height = 0 },
            gui.Panel{
                width = "100%-260",
                height = "auto",
                flow = "vertical",
                valign = "center",
                lmargin = 10,
                children = details,
            },
            gui.Button{
                text = buttonText or "",
                fontSize = 15,
                width = 130,
                height = 34,
                halign = "right",
                valign = "center",
                opacity = cond(blocked == nil and action ~= nil, 1, 0.4),
                linger = function(element)
                    if blocked ~= nil then
                        gui.Tooltip(blocked)(element)
                    end
                end,
                click = function()
                    if blocked ~= nil or action == nil then
                        return
                    end
                    audio.FireSoundEvent("Mouse.Click")
                    action()
                end,
            },
        },
    }
end

--The built Forge's card: Giddlebrick's answer so far, then each hero's
--treasure. host mounts dialogs; opts.backdrop is the negotiation's
--backdrop; close() closes the location.
---@param host Panel|nil
---@param opts {backdrop: string|nil}|nil
---@param close fun()
---@return Panel
function EotwForge.Panel(host, opts, close)
    local body = nil
    local busy = false
    local Rebuild

    local function SetBusy(value)
        busy = value
        Rebuild()
    end

    local function Note(text)
        return gui.Label{ text = text, fontSize = 16, italics = true, color = DIM, width = "100%", height = "auto", halign = "center", textAlignment = "center", vmargin = 20 }
    end

    Rebuild = function()
        if body == nil or not body.valid then
            return
        end
        local status = EotwForge.Status()
        local rows = {}
        if status == nil then
            rows[1] = Note(T("great_forge.workshop.loading"))
        elseif not status.access then
            local remaining = (tonumber(status.remainingMs) or 0) / 1000
            local lockEnds = EotwForge.LockedUntil()
            if lockEnds ~= nil then
                rows[1] = Note(T("great_forge.workshop.locked", { time = EotwForge.FormatTime(lockEnds - dmhub.Time()) }))
            elseif #EotwLeads.HeroesAtHome() == 0 then
                rows[1] = Note(T("great_forge.workshop.no_heroes_home"))
            else
                rows[1] = Note(T("great_forge.workshop.no_access"))
                rows[2] = gui.Button{
                    text = T("great_forge.workshop.talk_button"),
                    fontSize = 18,
                    width = 260,
                    height = 44,
                    halign = "center",
                    click = function()
                        audio.FireSoundEvent("Mouse.Click")
                        EotwForge.Approach(host, opts, close)
                    end,
                }
            end
            if remaining > 0 and lockEnds == nil then
                EotwForge.Fetch(nil)
            end
        else
            if status.bonus then
                --a server from before bonusPoints only gave 100.
                local points = tonumber(status.bonusPoints) or 100
                rows[#rows+1] = gui.Label{ text = T("great_forge.workshop.bonus", { points = points }), fontSize = 15, bold = true, color = GREEN, width = "100%", height = "auto", bmargin = 6 }
            end
            for _, hero in ipairs(EotwRoster.GetHeroes() or {}) do
                rows[#rows+1] = HeroRow(host, hero, busy, SetBusy)
            end
            if EotwRoster.GetHeroes() == nil then
                rows[#rows+1] = Note(T("great_forge.workshop.loading"))
            elseif #rows == 0 then
                rows[1] = Note(T("great_forge.workshop.no_heroes"))
            end
        end
        body.children = rows
    end

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        data = { seen = -1, lockShown = nil },
        thinkTime = 0.5,
        think = function(element)
            local rev = EotwForge.revision + EotwRoster.revision * 100000
            --a lock's text counts down too.
            local lockEnds = EotwForge.Status() ~= nil and EotwForge.LockedUntil() or nil
            local lockShown = lockEnds ~= nil and math.ceil(lockEnds - dmhub.Time()) or nil
            if element.data.seen ~= rev or element.data.lockShown ~= lockShown then
                element.data.seen = rev
                element.data.lockShown = lockShown
                Rebuild()
            end
        end,
        gui.Label{
            text = T("great_forge.workshop.title"),
            fontSize = 26,
            bold = true,
            color = TEXT,
            width = "auto",
            height = "auto",
        },
        gui.Label{
            text = T("great_forge.workshop.intro"),
            fontSize = 15,
            italics = true,
            color = DIM,
            width = "100%",
            height = "auto",
            vmargin = 8,
        },
        gui.Panel{
            width = "100%",
            height = "100%-120",
            flow = "vertical",
            vscroll = true,
            rpad = 12,
            borderBox = true,
            create = function(element)
                body = element
                Rebuild()
            end,
        },
    }
end

--- dev commands -------------------------------------------------------------------

local DEV_USAGE = [[Usage: /eotwforge <command> (open the town first)
  state      print your standing, access, lock and crafts at the Great Forge
  reset      forget your Forge standing and crafts (city admins)
  talk       play the negotiation now (needs a hero at home; reports its result)
  preview [defender|builder|stranger] [skip]
             play the first visit (opening + negotiation) as that standing,
             reporting nothing (default: your own standing); skip goes
             straight to the negotiation
  parse      parse the negotiation script and print its warnings]]

pcall(function()
    Commands.RegisterMacro{
        name = "eotwforge",
        summary = "dev: the built Great Forge (Giddlebrick, crafting)",
        doc = DEV_USAGE,
        command = function(str)
            if not (dmhub.GetSettingValue("dev") or dmhub.isAdminAccount) then
                print("EotW town: /eotwforge is a developer command")
                return
            end
            local verb = string.lower(string.match(str or "", "^%s*(%S+)") or "")
            if verb == "state" then
                EotwForge.Fetch(function(ok, s)
                    if not ok then
                        printf("EotW town (dev): forge-status failed: %s", tostring(s))
                        return
                    end
                    printf("EotW town (dev): built %s, standing %s, access %s, bonus %s, last interest %s, tries %s, locked for %ds",
                        tostring(s.built), tostring(s.standing), tostring(s.access), tostring(s.bonus), tostring(s.lastInterest),
                        tostring(s.tries), math.floor((tonumber(s.remainingMs) or 0) / 1000))
                    for _, craft in ipairs(s.crafts or {}) do
                        printf("  %s: %s %s/%s%s%s", tostring(craft.heroid), tostring(craft.itemName), tostring(craft.points),
                            tostring(craft.goal), cond(craft.completed, " done", ""), cond(craft.delivered, " collected", ""))
                    end
                end)
            elseif verb == "reset" then
                EotwForge.DevReset(function(ok, result)
                    if ok then
                        printf("EotW town (dev): Great Forge forgotten (%s rows)", tostring(result.deleted))
                    else
                        printf("EotW town (dev): reset refused: %s", tostring(result))
                    end
                end)
            elseif verb == "talk" then
                local host = m_host
                if host == nil or not host.valid then
                    print("EotW town (dev): open the built Great Forge once first")
                    return
                end
                EotwForge.Fetch(function(ok)
                    if ok then
                        EotwForge.ShowNegotiation(host, nil, function(forge)
                            printf("EotW town (dev): talk over; access %s", tostring(forge ~= nil and forge.access))
                        end)
                    end
                end)
            elseif verb == "preview" then
                local host = m_host
                if host == nil or not host.valid then
                    print("EotW town (dev): open the built Great Forge once first")
                    return
                end
                local standing, skip = nil, false
                for word in string.gmatch(string.lower(str or ""), "%S+") do
                    if ATTITUDE_BY_STANDING[word] ~= nil then
                        standing = word
                    elseif word == "skip" then
                        skip = true
                    end
                end
                if standing == nil then
                    local status = EotwForge.Status()
                    standing = (status ~= nil and status.standing) or "stranger"
                end
                if skip then
                    EotwForge.ShowNegotiation(host, { preview = standing }, function()
                    end)
                else
                    EotwForge.Preview(host, standing)
                end
            elseif verb == "parse" then
                m_beat = nil
                local beat = EotwForge.Beat()
                if beat ~= nil then
                    printf("EotW town (dev): %s: %d traits, %d arguments, %d offers", beat.name, #beat.traits, #beat.arguments, #beat.offers)
                end
            else
                print(DEV_USAGE)
            end
        end,
    }
end)

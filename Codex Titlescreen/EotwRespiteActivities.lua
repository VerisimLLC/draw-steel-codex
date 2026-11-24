local mod = dmhub.GetModLoading()

--Encounter of the Week: respite activities at the Blue Fish Inn.
--Design: EncounterOfTheWeek/EncounterOfTheWeek.md, "Respite activities at the inn".
--
--  * Any hero ability that costs the respite-activity resource
--    (CharacterResource.respiteActivityId: Sanctified Weapon, Revitalizing
--    Ritual, Mindlink...) can be used from the inn card, through one dialog
--    built from the ability's own data: who it targets, its modes, its cost.
--  * "As a respite activity" abilities cost one of the caster's Downtime
--    Activities (the City's respite-activity action charges it). The others
--    ("each time you finish a respite", "at the start of a respite") are free.
--  * Each ability is usable once per caster respite: the use is stamped with
--    the caster's longRestId, which every respite (creature:Rest) replaces.
--  * The town runs the ability itself: only "apply an ongoing effect" and
--    "grant temporary Stamina" behaviors are supported. An ability with any
--    other behavior (a roll, a script, a summon) is not offered.
--  * An effect ends when the hero who has it rests: until_rest effects are
--    removed by creature:Rest. Nothing is used while a respite is being
--    written, so a hero resting in that respite rests first and keeps it.

EotwRespiteActivities = {}

local T = UIText.T
local TP = UIText.Plural

local TEXT = "#efe4cc"
local DIM = "#c9bfa9"
local GOLD = "#d9b56a"
local AMBER = "#ffd38a"
local RED = "#ff8888"

--The caster's per-ability stamp: { [ability name] = longRestId when used }.
local USED_FIELD = "eotwRespiteUsed"
--What other heroes gave this hero: { [activityid] = { ability, caster, effects = {effectid...}, restid, at } }.
local GIFTS_FIELD = "eotwRespiteGifts"
--A use in flight, kept until every hero it touched is pushed (crash-safe).
local PENDING_KEY = "eotw:pendingRespiteActivity"

--{ [userid] = { activityid, casterid, ability, paid, targets, mode, charged, applied, pushed } }.
setting{
    id = PENDING_KEY,
    default = "",
    storage = "preference",
}

local m_busy = false

local function Bump()
    EotwDowntime.revision = EotwDowntime.revision + 1
end

local function RestId(tok)
    local id = nil
    pcall(function() id = tok.properties:try_get("longRestId") end)
    return id or "none"
end

local function HeroName(tok)
    return (tok ~= nil and tok.name) or T("inn.activity.hero_fallback")
end

--- which abilities -------------------------------------------------------------

--Can the town run this behavior? Only the two simple kinds.
local function BehaviorSupported(b)
    local typeName = b.typeName
    if typeName == "ActivatedAbilityApplyOngoingEffectBehavior" then
        return b:try_get("ongoingEffectSource", "specific") == "specific"
            and b:try_get("dc", "none") == "none"
            and b:try_get("ongoingEffect") ~= nil
            and dmhub.GetTable("characterOngoingEffects")[b.ongoingEffect] ~= nil
    end
    if typeName == "ActivatedAbilityGrantTemporaryStaminaBehavior" then
        return true
    end
    return false
end

local function AbilitySupported(ability)
    local behaviors = ability:try_get("behaviors", {})
    if #behaviors == 0 then
        return false
    end
    for _, b in ipairs(behaviors) do
        if not BehaviorSupported(b) then
            return false
        end
    end
    return true
end

--Does it cost a Downtime Activity? Only "as a respite activity" ones do;
--the rest happen as part of a respite ("each time you finish a respite").
local function IsPaid(ability)
    return string.find(string.lower(ability.description or ""), "as a respite activity", 1, true) ~= nil
end

--The hero's respite abilities the town can run: { {ability, paid}, ... }, by name.
function EotwRespiteActivities.AbilitiesOf(tok)
    local result = {}
    if tok == nil then
        return result
    end
    local seen = {}
    pcall(function()
        for _, ability in ipairs(tok.properties:GetActivatedAbilities{ bindCaster = true }) do
            if ability.actionResourceId == CharacterResource.respiteActivityId
                and ability.categorization ~= "Hidden"
                and not seen[ability.name]
                and AbilitySupported(ability) then
                seen[ability.name] = true
                result[#result+1] = { ability = ability, paid = IsPaid(ability) }
            end
        end
    end)
    table.sort(result, function(a, b) return a.ability.name < b.ability.name end)
    return result
end

--- availability --------------------------------------------------------------

--Heroes at home who can be a target: { {hero, tok}, ... } in roster order.
local function HeroesAtHome()
    local result = {}
    local away = EotwRoster.AwayHeroes()
    for _, hero in ipairs(EotwRoster.GetHeroes() or {}) do
        local tok = dmhub.GetCharacterById(hero.heroid)
        if tok ~= nil and away[hero.heroid] == nil and EotwRoster.IsInStep(hero.heroid) then
            result[#result+1] = { hero = hero, tok = tok }
        end
    end
    return result
end

--A respite being written, or one left half-written to finish on connect.
--Nothing is granted then: the rest would wipe it straight away.
local function RespitePending()
    if EotwDowntime.RespiteBusy() then
        return true
    end
    local _, pending = EotwDowntime.UI.LoadMine("eotw:pendingRespite")
    return type(pending) == "table"
end

local function UsedThisRespite(tok, abilityName)
    local used = nil
    pcall(function() used = tok.properties:try_get(USED_FIELD) end)
    return type(used) == "table" and used[abilityName] ~= nil and used[abilityName] == RestId(tok)
end

--Why this hero cannot use this ability now, or nil if they can.
function EotwRespiteActivities.Blocked(heroid, entry)
    if m_busy then
        return T("inn.activity.busy")
    end
    if RespitePending() then
        return T("inn.activity.resting")
    end
    local tok = dmhub.GetCharacterById(heroid)
    if tok == nil or not EotwRoster.IsInStep(heroid) then
        return T("inn.row.loading")
    end
    if EotwRoster.AwayHeroes()[heroid] ~= nil then
        return T("inn.activity.away")
    end
    if UsedThisRespite(tok, entry.ability.name) then
        return T("inn.activity.used")
    end
    if entry.paid and EotwRoster.GetDowntime(heroid) < 1 then
        return T("inn.activity.no_downtime")
    end
    return nil
end

--- targets ---------------------------------------------------------------------

--How the ability picks targets: "self", "all" or "choose", and how many.
local function TargetRule(ability, casterTok)
    local targetType = ability:try_get("targetType", "self")
    if targetType == "self" then
        return "self", 1
    end
    if targetType == "all" then
        return "all", 99
    end
    local count = 1
    local formula = ability:try_get("numTargets", "1")
    local n = tonumber(formula)
    if n == nil then
        pcall(function()
            n = tonumber(ExecuteGoblinScript(formula, casterTok.properties:LookupSymbol{}, 1, string.format("Targets for %s", ability.name)))
        end)
    end
    count = math.max(1, math.floor(n or 1))
    return "choose", count
end

--The heroes this ability may target from the caster.
local function Candidates(ability, casterTok)
    local rule = TargetRule(ability, casterTok)
    local result = {}
    for _, c in ipairs(HeroesAtHome()) do
        local isCaster = c.hero.heroid == casterTok.charid
        if rule == "self" then
            if isCaster then
                result[#result+1] = c
            end
        elseif isCaster then
            --"all" always includes the caster ("each of you").
            if rule == "all" or ability:try_get("selfTarget", false) then
                result[#result+1] = c
            end
        else
            result[#result+1] = c
        end
    end
    return result
end

--- running it ---------------------------------------------------------------

--The behaviors that run for the chosen mode (1-based; nil when the ability has none).
local function BehaviorsFor(ability, mode)
    local result = {}
    for _, b in ipairs(ability:try_get("behaviors", {})) do
        local modes = b:try_get("modesSelected")
        local applies = modes == nil or #modes == 0
        if not applies and mode ~= nil then
            for _, m in ipairs(modes) do
                if m == mode then
                    applies = true
                end
            end
        end
        if applies then
            result[#result+1] = b
        end
    end
    return result
end

--Apply the ability to one target's working copy, once per activity.
local function ApplyToTarget(targetTok, casterTok, ability, mode, activityid)
    local already = false
    pcall(function()
        local gifts = targetTok.properties:try_get(GIFTS_FIELD)
        already = type(gifts) == "table" and gifts[activityid] ~= nil
    end)
    if already then
        return
    end
    targetTok:ModifyProperties{
        description = ability.name,
        undoable = false,
        execute = function()
            local props = targetTok.properties
            local effects = {}
            for _, b in ipairs(BehaviorsFor(ability, mode)) do
                if b.typeName == "ActivatedAbilityApplyOngoingEffectBehavior" then
                    props:ApplyOngoingEffect(b.ongoingEffect, b:try_get("duration"), {
                        tokenid = casterTok.id,
                        abilityName = ability.name,
                    }, {
                        sourceDescription = string.format("%s (%s)", ability.name, HeroName(casterTok)),
                    })
                    effects[#effects+1] = b.ongoingEffect
                elseif b.typeName == "ActivatedAbilityGrantTemporaryStaminaBehavior" then
                    local amount = tonumber(dmhub.EvalGoblinScript(tostring(b.stamina), casterTok.properties:LookupSymbol{}, string.format("Temporary Stamina for %s", ability.name)))
                    if amount ~= nil and amount > 0 then
                        props:GrantTemporaryStamina(amount, nil, casterTok.id)
                    end
                end
            end
            --keep only gifts still in force, then add this one.
            local gifts = {}
            local old = props:try_get(GIFTS_FIELD)
            local restid = RestId(targetTok)
            if type(old) == "table" then
                for id, gift in pairs(old) do
                    if type(gift) == "table" and gift.restid == restid then
                        gifts[id] = gift
                    end
                end
            end
            gifts[activityid] = {
                ability = ability.name,
                caster = HeroName(casterTok),
                effects = effects,
                restid = restid,
                at = dmhub.serverTime,
            }
            props[GIFTS_FIELD] = gifts
        end,
    }
end

local function StampCaster(casterTok, abilityName)
    if UsedThisRespite(casterTok, abilityName) then
        return
    end
    casterTok:ModifyProperties{
        description = abilityName,
        undoable = false,
        execute = function()
            local props = casterTok.properties
            local used = {}
            local old = props:try_get(USED_FIELD)
            if type(old) == "table" then
                for k, v in pairs(old) do
                    used[k] = v
                end
            end
            used[abilityName] = RestId(casterTok)
            props[USED_FIELD] = used
        end,
    }
end

local function FindAbility(tok, name)
    for _, entry in ipairs(EotwRespiteActivities.AbilitiesOf(tok)) do
        if entry.ability.name == name then
            return entry
        end
    end
    return nil
end

--Carry a pending use forward: charge (paid ones), apply, push every hero it
--touched. Safe to call again at any stage. onDone(ok, message).
local function Continue(onDone)
    local _, pending = EotwDowntime.UI.LoadMine(PENDING_KEY)
    local function Finish(ok, message)
        m_busy = false
        Bump()
        if onDone ~= nil then
            onDone(ok, message)
        end
    end
    if type(pending) ~= "table" or type(pending.activityid) ~= "string" then
        Finish(true)
        return
    end
    m_busy = true
    local conn = EotwRoster.Connection()
    if conn == nil or not conn.connected then
        Finish(false, T("inn.respite.not_connected"))
        return
    end
    --after a reconnect the heroes' working copies may still be importing, so
    --wait for every token it needs before deciding the ability is gone.
    local casterTok = dmhub.GetCharacterById(pending.casterid)
    local missing = casterTok == nil
    if not pending.applied then
        for _, targetid in ipairs(pending.targets or {}) do
            if dmhub.GetCharacterById(targetid) == nil then
                missing = true
            end
        end
    end
    if missing then
        pending.tokenWaits = (pending.tokenWaits or 0) + 1
        if pending.tokenWaits <= 30 then
            dmhub.Schedule(1, function()
                if mod.unloaded then
                    return
                end
                Continue(onDone)
            end)
            return
        end
        pending.tokenWaits = 0
        pending.connectTries = (pending.connectTries or 0) + 1
        if pending.charged and pending.connectTries < 3 then
            --paid for: keep it, so the next connects try again.
            EotwDowntime.UI.SaveMine(PENDING_KEY, pending)
        else
            --nothing was paid, or the heroes never came back: let it go so
            --the inn is not blocked for good.
            EotwDowntime.UI.SaveMine(PENDING_KEY, nil)
        end
        Finish(false, T("inn.activity.gone"))
        return
    end
    pending.tokenWaits = nil
    local entry = FindAbility(casterTok, pending.ability)
    if entry == nil then
        EotwDowntime.UI.SaveMine(PENDING_KEY, nil)
        Finish(false, T("inn.activity.gone"))
        return
    end

    --1. a paid one is charged first; the City ignores an id it has seen.
    if pending.paid and not pending.charged then
        conn:Request{
            action = "respite-activity",
            args = { activityid = pending.activityid, heroid = pending.casterid, ability = pending.ability },
            success = function(result)
                if mod.unloaded then
                    return
                end
                EotwRoster.SetListedDowntime(pending.casterid, result.downtime)
                pending.charged = true
                EotwDowntime.UI.SaveMine(PENDING_KEY, pending)
                Continue(onDone)
            end,
            error = function(message)
                --refused (no Downtime left...): it will never be charged, so let it go.
                EotwDowntime.UI.SaveMine(PENDING_KEY, nil)
                Finish(false, tostring(message))
            end,
        }
        return
    end

    --2. the effects and the caster's stamp, on the working copies. A respite
    --resuming alongside goes first, so its rest cannot wipe what this grants.
    if not pending.applied and RespitePending() then
        pending.waits = (pending.waits or 0) + 1
        if pending.waits > 120 then
            --keep the entry: the next connect tries again.
            pending.waits = 0
            EotwDowntime.UI.SaveMine(PENDING_KEY, pending)
            Finish(false, T("inn.activity.resting"))
            return
        end
        EotwDowntime.UI.SaveMine(PENDING_KEY, pending)
        dmhub.Schedule(1, function()
            if mod.unloaded then
                return
            end
            Continue(onDone)
        end)
        return
    end
    if not pending.applied then
        for _, targetid in ipairs(pending.targets or {}) do
            local targetTok = dmhub.GetCharacterById(targetid)
            if targetTok ~= nil then
                ApplyToTarget(targetTok, casterTok, entry.ability, pending.mode, pending.activityid)
            end
        end
        StampCaster(casterTok, pending.ability)
        pending.applied = true
        pending.pushed = {}
        EotwDowntime.UI.SaveMine(PENDING_KEY, pending)
    end

    --3. push each hero it touched, one at a time.
    local touched = { pending.casterid }
    for _, targetid in ipairs(pending.targets or {}) do
        if targetid ~= pending.casterid then
            touched[#touched+1] = targetid
        end
    end
    pending.pushed = pending.pushed or {}
    for _, heroid in ipairs(touched) do
        if not pending.pushed[heroid] then
            --let the property writes land before the export, as the respite does.
            dmhub.Schedule(0.3, function()
                if mod.unloaded then
                    return
                end
                EotwRoster.PushHero(heroid, function(ok, message)
                    if not ok then
                        Finish(false, message)
                        return
                    end
                    pending.pushed[heroid] = true
                    EotwDowntime.UI.SaveMine(PENDING_KEY, pending)
                    Continue(onDone)
                end)
            end)
            return
        end
    end

    EotwDowntime.UI.SaveMine(PENDING_KEY, nil)
    EotwAnalytics.Track("eotw_downtime", { activity = "respite_activity", ability = pending.ability, heroid = pending.casterid, paid = pending.paid, targets = #(pending.targets or {}) })
    Finish(true)
end

--Use an ability: casterid's ability (by name) on targets (heroids), in mode
--(1-based or nil). onDone(ok, message).
function EotwRespiteActivities.Use(casterid, abilityName, targets, mode, onDone)
    local casterTok = dmhub.GetCharacterById(casterid)
    local entry = casterTok ~= nil and FindAbility(casterTok, abilityName) or nil
    if entry == nil then
        if onDone ~= nil then
            onDone(false, T("inn.activity.gone"))
        end
        return
    end
    local blocked = EotwRespiteActivities.Blocked(casterid, entry)
    if blocked ~= nil then
        if onDone ~= nil then
            onDone(false, blocked)
        end
        return
    end
    EotwDowntime.UI.SaveMine(PENDING_KEY, {
        activityid = dmhub.GenerateGuid(),
        casterid = casterid,
        ability = abilityName,
        paid = entry.paid,
        targets = targets,
        mode = mode,
    })
    Continue(onDone)
end

--Finish a use left over from a dropped connection. Called when the town connects.
function EotwRespiteActivities.ResumePending()
    local _, pending = EotwDowntime.UI.LoadMine(PENDING_KEY)
    if type(pending) == "table" and not m_busy then
        Continue(function(ok, message)
            if not ok then
                printf("EotW town: a respite activity left over from last time did not finish: %s", tostring(message))
            end
        end)
    end
end

--- what a hero has been given ------------------------------------------------

--Gifts still in force on this hero: { {ability, caster}, ... }. One whose
--effects are all gone (the hero rested) is not listed.
function EotwRespiteActivities.GiftsOn(tok)
    local result = {}
    if tok == nil then
        return result
    end
    pcall(function()
        local gifts = tok.properties:try_get(GIFTS_FIELD)
        if type(gifts) ~= "table" then
            return
        end
        local active = {}
        for _, effect in ipairs(tok.properties:ActiveOngoingEffects()) do
            active[effect.ongoingEffectid] = true
        end
        local restid = RestId(tok)
        for _, gift in pairs(gifts) do
            local live = false
            if type(gift.effects) == "table" and #gift.effects > 0 then
                for _, effectid in ipairs(gift.effects) do
                    if active[effectid] then
                        live = true
                    end
                end
            else
                live = gift.restid == restid
            end
            if live then
                result[#result+1] = { ability = gift.ability, caster = gift.caster, at = gift.at or 0 }
            end
        end
    end)
    table.sort(result, function(a, b) return a.at < b.at end)
    return result
end

--One line for the hero's inn row, or nil when they have been given nothing.
function EotwRespiteActivities.GiftLine(tok)
    local parts = {}
    for _, gift in ipairs(EotwRespiteActivities.GiftsOn(tok)) do
        if gift.caster == HeroName(tok) then
            parts[#parts+1] = gift.ability
        else
            parts[#parts+1] = T("inn.activity.gift_from", { ability = gift.ability, hero = gift.caster })
        end
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, ", ")
end

--- the dialog --------------------------------------------------------------------

local function Chip(text, selected, enabled, tok, press)
    return gui.Panel{
        width = "auto",
        height = 40,
        flow = "horizontal",
        hpad = 8,
        borderBox = true,
        hmargin = 3,
        vmargin = 3,
        bgimage = "panels/square.png",
        bgcolor = cond(selected, "#3a2e1a", "#1d1913"),
        borderWidth = cond(selected, 2, 1),
        borderColor = cond(selected, GOLD, "#5a4b33"),
        cornerRadius = 6,
        opacity = cond(enabled, 1, 0.45),
        press = function()
            if enabled then
                audio.FireSoundEvent("Mouse.Click")
                press()
            end
        end,
        tok ~= nil and EotwDowntime.UI.Portrait(tok, 24, 32) or nil,
        gui.Label{
            text = text,
            fontSize = 16,
            color = TEXT,
            width = "auto",
            height = "auto",
            valign = "center",
            hmargin = 6,
            interactable = false,
        },
    }
end

local function Heading(text)
    return gui.Label{
        text = text,
        fontSize = 15,
        color = DIM,
        width = "100%",
        height = "auto",
        tmargin = 14,
        bmargin = 4,
    }
end

--The dialog for one hero's ability: targets, mode, cost, Use.
function EotwRespiteActivities.ShowDialog(host, casterid, abilityName)
    local casterTok = dmhub.GetCharacterById(casterid)
    local entry = casterTok ~= nil and FindAbility(casterTok, abilityName) or nil
    if entry == nil then
        return
    end
    local ability = entry.ability
    local rule, count = TargetRule(ability, casterTok)
    local modes = {}
    if ability:try_get("multipleModes", false) then
        for i, m in ipairs(ability:try_get("modeList", {})) do
            modes[#modes+1] = { index = i, text = m.text or tostring(i), rules = m.rules }
        end
    end

    local state = {
        targets = {},
        mode = #modes > 0 and modes[1].index or nil,
        message = "",
        working = false,
    }
    --the default target: the caster when allowed, else the first hero.
    local first = Candidates(ability, casterTok)
    if rule == "choose" then
        for _, c in ipairs(first) do
            if c.hero.heroid == casterid then
                state.targets[casterid] = true
            end
        end
        if next(state.targets) == nil and first[1] ~= nil then
            state.targets[first[1].hero.heroid] = true
        end
    end

    local dlg = nil
    local body = nil
    local Render

    local function Close()
        if state.working then
            return
        end
        if dlg ~= nil and dlg.valid then
            dlg:DestroySelf()
        end
    end

    local function ChosenTargets()
        local result = {}
        for _, c in ipairs(Candidates(ability, casterTok)) do
            if rule ~= "choose" or state.targets[c.hero.heroid] then
                result[#result+1] = c.hero.heroid
            end
        end
        return result
    end

    local function Confirm()
        if state.working then
            return
        end
        local targets = ChosenTargets()
        if #targets == 0 then
            state.message = T("inn.activity.pick_target")
            Render()
            return
        end
        state.working = true
        state.message = ""
        Render()
        EotwRespiteActivities.Use(casterid, abilityName, targets, state.mode, function(ok, message)
            if mod.unloaded then
                return
            end
            state.working = false
            if not ok then
                state.message = tostring(message)
                Render()
                return
            end
            Close()
            local names = {}
            for _, heroid in ipairs(targets) do
                names[#names+1] = HeroName(dmhub.GetCharacterById(heroid))
            end
            EotwDowntime.UI.ShowBanner(host, ability.name, T("inn.activity.banner", { heroes = table.concat(names, ", ") }), nil, casterid)
        end)
    end

    Render = function()
        if body == nil or not body.valid then
            return
        end
        local children = {}
        local candidates = Candidates(ability, casterTok)

        if rule == "choose" then
            children[#children+1] = Heading(TP("inn.activity.choose_heroes", count))
            local chosen = 0
            for _, _ in pairs(state.targets) do
                chosen = chosen + 1
            end
            local chips = {}
            for _, c in ipairs(candidates) do
                local heroid = c.hero.heroid
                local selected = state.targets[heroid] == true
                chips[#chips+1] = Chip(HeroName(c.tok), selected, not state.working, c.tok, function()
                    if selected then
                        state.targets[heroid] = nil
                    elseif count == 1 then
                        state.targets = { [heroid] = true }
                    elseif chosen < count then
                        state.targets[heroid] = true
                    end
                    Render()
                end)
            end
            children[#children+1] = gui.Panel{ width = "100%", height = "auto", flow = "horizontal", wrap = true, children = chips }
        else
            local names = {}
            for _, c in ipairs(candidates) do
                names[#names+1] = HeroName(c.tok)
            end
            children[#children+1] = Heading(T("inn.activity.targets_heading"))
            children[#children+1] = gui.Label{ text = table.concat(names, ", "), fontSize = 16, color = TEXT, width = "100%", height = "auto" }
        end

        if #modes > 0 then
            children[#children+1] = Heading(T("inn.activity.mode_heading"))
            local chips = {}
            for _, m in ipairs(modes) do
                chips[#chips+1] = Chip(m.text, state.mode == m.index, not state.working, nil, function()
                    state.mode = m.index
                    Render()
                end)
            end
            children[#children+1] = gui.Panel{ width = "100%", height = "auto", flow = "horizontal", wrap = true, children = chips }
            for _, m in ipairs(modes) do
                if m.index == state.mode and m.rules ~= nil and m.rules ~= "" then
                    children[#children+1] = gui.Label{ text = m.rules, fontSize = 14, italics = true, color = DIM, width = "100%", height = "auto", tmargin = 4 }
                end
            end
        end

        --what it costs.
        local costText
        if entry.paid then
            costText = T("inn.activity.cost_paid", { hero = HeroName(casterTok), count = string.format("%d", EotwRoster.GetDowntime(casterid)) })
        else
            costText = T("inn.activity.cost_free")
        end
        children[#children+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 18,
            entry.paid and EotwDowntime.UI.HammerChip(1) or nil,
            gui.Label{ text = costText, fontSize = 15, color = TEXT, width = "auto", height = "auto", valign = "center", lmargin = 8 },
        }
        children[#children+1] = gui.Label{ text = state.message, fontSize = 15, color = RED, width = "100%", height = "auto", tmargin = 8 }
        body.children = children
    end

    dlg = gui.Panel{
        floating = true,
        width = 760,
        height = 560,
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
            local rev = EotwDowntime.revision + EotwRoster.revision * 100000
            if element.data.seen ~= rev and not state.working then
                element.data.seen = rev
                Render()
            end
        end,
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
                bmargin = 4,
                gui.Panel{
                    width = 30,
                    height = 30,
                    valign = "center",
                    rmargin = 10,
                    bgimage = "phosphor/sparkle-fill.png",
                    bgcolor = GOLD,
                },
                gui.Label{
                    text = ability.name,
                    fontSize = 28,
                    bold = true,
                    color = TEXT,
                    width = "auto",
                    height = "auto",
                    valign = "center",
                },
            },
            gui.Label{
                text = T("inn.activity.dialog_caster", { hero = HeroName(casterTok) }),
                fontSize = 15,
                color = DIM,
                width = "100%",
                height = "auto",
            },
            gui.Label{
                text = ability.description or "",
                fontSize = 16,
                italics = true,
                color = TEXT,
                width = "100%",
                height = "auto",
                tmargin = 8,
            },
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                create = function(element)
                    body = element
                    Render()
                end,
            },
        },
        gui.Panel{
            floating = true,
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "right",
            valign = "bottom",
            gui.Button{
                text = T("inn.activity.cancel_button"),
                fontSize = 20,
                width = 160,
                height = 46,
                hmargin = 6,
                click = function()
                    Close()
                end,
            },
            gui.Button{
                text = T("inn.activity.use_button"),
                fontSize = 20,
                width = 200,
                height = 46,
                hmargin = 6,
                click = function()
                    audio.FireSoundEvent("Mouse.Click")
                    Confirm()
                end,
            },
        },
    }
    host:AddChild(dlg)
end

--- the inn card's section --------------------------------------------------------

--Every respite ability of every hero in the roster, with why it cannot be used now.
local function Rows()
    local result = {}
    for _, hero in ipairs(EotwRoster.GetHeroes() or {}) do
        local tok = dmhub.GetCharacterById(hero.heroid)
        for _, entry in ipairs(EotwRespiteActivities.AbilitiesOf(tok)) do
            result[#result+1] = { hero = hero, tok = tok, entry = entry, blocked = EotwRespiteActivities.Blocked(hero.heroid, entry) }
        end
    end
    return result
end

--The inn card's Respite Activities section. Empty (no height) when no hero has one.
function EotwRespiteActivities.InnPanel(host)
    local function Row(r)
        local entry = r.entry
        local enabled = r.blocked == nil
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 8,
            pad = 8,
            borderBox = true,
            bgimage = "panels/square.png",
            bgcolor = "#1d1913",
            borderWidth = 1,
            borderColor = "#d9b56a55",
            cornerRadius = 6,
            gui.Panel{
                width = 22,
                height = 22,
                valign = "center",
                rmargin = 8,
                bgimage = "phosphor/sparkle-fill.png",
                bgcolor = AMBER,
            },
            gui.Panel{
                width = "100%-330",
                height = "auto",
                flow = "vertical",
                valign = "center",
                gui.Label{ text = entry.ability.name, fontSize = 16, bold = true, color = TEXT, width = "100%", height = "auto" },
                gui.Label{
                    text = cond(entry.paid, T("inn.activity.row_paid", { hero = HeroName(r.tok) }), T("inn.activity.row_free", { hero = HeroName(r.tok) })),
                    fontSize = 13,
                    color = DIM,
                    width = "100%",
                    height = "auto",
                },
            },
            gui.Panel{
                width = 60,
                height = "auto",
                valign = "center",
                entry.paid and EotwDowntime.UI.HammerChip(1) or nil,
            },
            --blocked: say why in place of the button (a dimmed button reads as live).
            (not enabled) and gui.Label{
                text = r.blocked or "",
                fontSize = 14,
                italics = true,
                color = DIM,
                width = 200,
                height = "auto",
                halign = "right",
                valign = "center",
                textAlignment = "right",
            } or nil,
            enabled and gui.Button{
                text = T("inn.activity.use_button"),
                fontSize = 17,
                width = 200,
                height = 38,
                halign = "right",
                valign = "center",
                click = function()
                    if EotwRespiteActivities.Blocked(r.hero.heroid, entry) ~= nil then
                        return
                    end
                    audio.FireSoundEvent("Mouse.Click")
                    EotwRespiteActivities.ShowDialog(host, r.hero.heroid, entry.ability.name)
                end,
            } or nil,
        }
    end

    local function Rebuild(element)
        local children = {}
        local rows = Rows()
        if #rows > 0 then
            children[#children+1] = gui.Label{
                text = T("inn.activity.heading"),
                fontSize = 14,
                bold = true,
                color = AMBER,
                width = "100%",
                height = "auto",
                tmargin = 14,
            }
            for _, r in ipairs(rows) do
                children[#children+1] = Row(r)
            end
        end
        element.children = children
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        data = { seen = -1 },
        thinkTime = 0.5,
        think = function(element)
            local rev = EotwDowntime.revision + EotwRoster.revision * 100000
            if element.data.seen ~= rev then
                element.data.seen = rev
                Rebuild(element)
            end
        end,
        create = function(element)
            Rebuild(element)
        end,
    }
end

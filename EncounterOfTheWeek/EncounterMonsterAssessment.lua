local mod = dmhub.GetModLoading()

--The Encounter of the Week monster assessment: in an authoring game, every
--bestiary entry says whether the monster is a good pick for an EotW
--encounter. These games have no Director, so whatever the Monster AI does
--not use never happens, and whatever the rules do not automate falls to the
--player host. Two analyses feed it, both run on the spot when the bestiary
--is looked at:
--  * Monster AI support (MonsterAI.AssessSupport, Monster AI/MonsterAISupport.lua):
--    the hand-written AI registered for the monster and where it lives, and
--    whether the generic AI can use each ability nothing hand-written covers.
--  * Automation: each ability's and the monster's implementation status.
--It shows as a badge on each bestiary row, a strip above the stat block in
--the row's hover view, a full report (strip button or right-click), and the
--search words ai:recommended / ai:care / ai:avoid.
--Reference: EOTW_MONSTER_ASSESSMENT_REFERENCE.md (parent repo).

EotwMonsterAssessment = {}

local g_verdicts = {
    recommended = { text = "Recommended", token = "@success", class = "success" },
    care = { text = "Use with care", token = "@warning", class = "warning" },
    avoid = { text = "Avoid", token = "@danger", class = "danger" },
}

--search words accepted after "ai:" for each verdict.
local g_searchWords = {
    recommended = { "recommended", "rec", "good", "yes" },
    care = { "care", "caution", "usewithcare", "maybe" },
    avoid = { "avoid", "no", "bad" },
}

local g_statusText = {
    tailored = "Hand-written AI",
    generic = "Shared AI move",
    squad = "Squad strike",
    synthesized = "Generic AI",
    automatic = "Automatic",
    narrative = "Narrative",
    unused = "Never used",
}

--How much an unused entry of each kind hurts, for ranking the issues.
local g_unusedSeverity = {
    ["Signature Ability"] = 100,
    ["Villain Action"] = 60,
    ["Heroic Ability"] = 50,
    ["Main Action"] = 45,
    ["Triggered Action"] = 40,
    ["Malice"] = 25,
    ["Maneuver"] = 20,
    ["Other Ability"] = 15,
}

--Active() is asked for every row and every node a search visits, so its
--answer is reused for a second.
local g_activeAt = nil
local g_active = false

--- True where the assessment shows: the Director of an EotW authoring game
--- (the EotW codemod is loaded but this is not a live EotW game, nor an
--- authoring test this client is playing as a hero).
--- @return boolean
function EotwMonsterAssessment.Active()
    local now = dmhub.Time()
    if g_activeAt ~= nil and now - g_activeAt < 1 then
        return g_active
    end
    g_activeAt = now

    g_active = false
    local eotw = rawget(_G, "EncounterOfTheWeekGame")
    local hasAssessment = false
    pcall(function() hasAssessment = MonsterAI.AssessBestiarySupport ~= nil end)
    if eotw ~= nil and hasAssessment and dmhub.isDM then
        local ok, live = pcall(eotw.IsEotwGame)
        g_active = ok and not live
    end
    return g_active
end

local function ImplementationName(level)
    return gui.ImplementationStatusValues[level] or "Not Automated"
end

local function Colored(token, text)
    return string.format("<color=%s>%s</color>", ThemeEngine.ResolveTokens(token), text)
end

local function LowerFirst(text)
    return (string.gsub(text, "^%u", string.lower))
end

--- @class EotwMonsterIssue
--- @field severity number
--- @field text string

--- @class EotwMonsterVerdict
--- @field monsterid string
--- @field name string
--- @field key string "recommended", "care" or "avoid"
--- @field verdict string
--- @field why string One line explaining the verdict.
--- @field automation number The monster's implementation status.
--- @field support MonsterAISupportAssessment
--- @field issues EotwMonsterIssue[] Most damaging first.

--- Assess a bestiary entry. fresh re-runs the AI analysis instead of using
--- a remembered one (the memo lives in MonsterAISupport.lua).
--- @param monsterid string
--- @param fresh? boolean
--- @return EotwMonsterVerdict|nil
function EotwMonsterAssessment.Assess(monsterid, fresh)
    if fresh then
        MonsterAI.InvalidateSupport(monsterid)
    end
    local support = MonsterAI.AssessBestiarySupport(monsterid)
    if support == nil then
        return nil
    end
    local asset = assets.monsters[monsterid]
    if asset == nil then
        return nil
    end

    local automation = gui.ImplementationStatus.Unimplemented
    pcall(function() automation = asset.properties:GetImplementationStatus() end)

    local name = support.monsterType
    if name == "" then
        name = creature.GetTokenDescription(asset.info) or "This monster"
    end

    local issues = {}
    local function Issue(severity, text)
        issues[#issues + 1] = { severity = severity, text = text }
    end

    local aiUsesUnautomatedSignature = false
    local aiUsesUnautomated = false
    local hasAttack = false
    for _, entry in ipairs(support.entries) do
        if entry.kind == "Signature Ability" or entry.kind == "Main Action" or entry.kind == "Heroic Ability" then
            hasAttack = true
        end
        local quoted = string.format("<b>%s</b>", entry.name)
        if entry.status == MonsterAI.supportStatus.unused then
            local base = g_unusedSeverity[entry.kind] or 15
            local text
            if entry.kind == "Triggered Action" then
                text = string.format("Triggered action %s never happens: %s", quoted, LowerFirst(entry.reason))
            elseif entry.kind == "Villain Action" then
                text = string.format("Villain action %s never happens: %s", quoted, LowerFirst(entry.reason))
            elseif entry.kind == "Malice" then
                text = string.format("Malice ability %s is never spent: no Malice AI is registered for it.", quoted)
            else
                text = string.format("%s %s is never used: %s", entry.kind, quoted, LowerFirst(entry.reason))
            end
            Issue(base, text)
        elseif entry.usable and entry.status ~= MonsterAI.supportStatus.automatic then
            if entry.implementation <= gui.ImplementationStatus.Unimplemented then
                aiUsesUnautomated = true
                if entry.kind == "Signature Ability" then
                    aiUsesUnautomatedSignature = true
                end
                Issue(entry.kind == "Signature Ability" and 95 or 70, string.format(
                    "The AI uses %s, but its effects are not automated: the player host would have to resolve them.", quoted))
            elseif entry.implementation == gui.ImplementationStatus.Bronze then
                Issue(35, string.format("The AI uses %s, but it is only partly automated: the host may have to adjudicate part of it.", quoted))
            end
            if entry.disabled then
                Issue(30, string.format("The AI move for %s is switched off in the Monster AI panel this session.", quoted))
            end
        end
    end

    if not hasAttack then
        Issue(99, "It has no actions of its own the AI can use: it will only make free strikes and move.")
    elseif not support.signatureUsable then
        Issue(99, "The AI cannot use its signature ability, so it will mostly make free strikes and advance.")
    end
    if automation <= gui.ImplementationStatus.Bronze then
        Issue(55, string.format("Its rules automation is only \"%s\": some of its kit needs a person to adjudicate.",
            ImplementationName(automation)))
    end

    table.sort(issues, function(a, b)
        if a.severity ~= b.severity then
            return a.severity > b.severity
        end
        return a.text < b.text
    end)

    local key, why
    if support.rank <= 1 then
        key = "avoid"
        why = "The AI can't use its main attack, and there is no Director to run it."
    elseif aiUsesUnautomatedSignature then
        key = "avoid"
        why = "The AI uses its signature ability, but the rules don't automate its effects."
    elseif support.rank >= 3 and automation >= gui.ImplementationStatus.Silver and not aiUsesUnautomated then
        key = "recommended"
        why = "The AI uses most of its kit and the rules handle it."
    else
        key = "care"
        why = "Playable, but parts of its kit won't happen or need adjudication."
    end

    return {
        monsterid = monsterid,
        name = name,
        key = key,
        verdict = g_verdicts[key].text,
        why = why,
        automation = automation,
        support = support,
        issues = issues,
    }
end

--One line: "AI: Capable (64%) - Automation: Mostly Automated".
local function SummaryLine(result)
    return string.format("AI: %s (%d%% of kit) - Automation: %s",
        result.support.level, math.floor(result.support.coverage * 100 + 0.5),
        ImplementationName(result.automation))
end

local function VerdictMarkup(result)
    return Colored(g_verdicts[result.key].token, string.format("<b>%s</b>", result.verdict))
end

local ShowReport

--- The strip shown above a monster's stat block in the bestiary hover view.
--- @param monsterid string
--- @return Panel|nil
function EotwMonsterAssessment.CreateEntryHeader(monsterid)
    local result = EotwMonsterAssessment.Assess(monsterid, true)
    if result == nil then
        return nil
    end

    local lines = {}
    for i = 1, math.min(3, #result.issues) do
        lines[#lines + 1] = gui.Label {
            width = "100%",
            height = "auto",
            fontSize = 14,
            textWrap = true,
            tmargin = 2,
            text = "- " .. result.issues[i].text,
        }
    end
    if #result.issues == 0 then
        lines[#lines + 1] = gui.Label {
            width = "100%",
            height = "auto",
            fontSize = 14,
            tmargin = 2,
            text = "No problems found: the AI uses its whole kit and the rules handle it.",
        }
    elseif #result.issues > 3 then
        lines[#lines + 1] = gui.Label {
            classes = { "fgMuted" },
            width = "100%",
            height = "auto",
            fontSize = 13,
            tmargin = 2,
            text = string.format("...and %d more in the full report.", #result.issues - 3),
        }
    end

    local children = {}
    children[#children + 1] = gui.Panel {
            width = "100%",
            height = "auto",
            flow = "horizontal",

            gui.Label {
                width = "auto",
                height = "auto",
                fontSize = 18,
                valign = "center",
                text = VerdictMarkup(result),
            },
            gui.Label {
                width = "auto",
                height = "auto",
                fontSize = 14,
                valign = "center",
                lmargin = 12,
                text = SummaryLine(result),
            },
            gui.Button {
                text = "Full report",
                width = "auto",
                height = 26,
                fontSize = 14,
                hpad = 10,
                borderBox = true,
                halign = "right",
                valign = "center",
                click = function(element)
                    ShowReport(monsterid)
                end,
            },
        }

    children[#children + 1] = gui.Label {
        classes = { "fgMuted" },
        width = "100%",
        height = "auto",
        fontSize = 13,
        tmargin = 2,
        text = "Encounter of the Week assessment: " .. result.why,
    }
    for _, line in ipairs(lines) do
        children[#children + 1] = line
    end

    return gui.Panel {
        styles = ThemeEngine.GetStyles(),
        classes = { "bordered" },
        width = 800,
        height = "auto",
        flow = "vertical",
        pad = 10,
        borderBox = true,
        bmargin = 8,
        children = children,
    }
end

--- The small round badge on a bestiary row, tinted by verdict.
--- @param monsterid string
--- @return Panel|nil
function EotwMonsterAssessment.CreateRowBadge(monsterid)
    local asset = assets.monsters[monsterid]
    local isMonster = false
    pcall(function() isMonster = asset ~= nil and asset.properties:IsMonster() end)
    if not isMonster then
        return nil
    end

    local function Refresh(element, fresh)
        if not EotwMonsterAssessment.Active() then
            element:SetClass("hidden", true)
            return
        end
        local result = EotwMonsterAssessment.Assess(monsterid, fresh)
        element:SetClass("hidden", result == nil)
        if result ~= nil then
            element.selfStyle.bgcolor = ThemeEngine.ResolveTokens(g_verdicts[result.key].token)
            element.data.result = result
        end
    end

    return gui.Panel {
        bgimage = "panels/square.png",
        width = 10,
        height = 10,
        cornerRadius = 5,
        hmargin = 2,
        valign = "center",
        data = { result = nil },
        create = function(element)
            Refresh(element, false)
        end,
        --the monster may have been edited: assess it afresh.
        refreshAssets = function(element)
            Refresh(element, true)
        end,
        hover = function(element)
            local result = element.data.result
            if result == nil then
                return
            end
            local text = string.format("%s\n%s\n%s", VerdictMarkup(result), SummaryLine(result), result.why)
            if #result.issues > 0 then
                text = text .. "\n\n- " .. result.issues[1].text
            end
            text = text .. "\n\n<i>Hover the row for details; right-click for the full report.</i>"
            gui.Tooltip { text = text, width = 360, halign = "right", valign = "center" }(element)
        end,
    }
end

--- @param monsterid string
--- @return {text: string, click: fun()}[]
function EotwMonsterAssessment.MenuItems(monsterid)
    local asset = assets.monsters[monsterid]
    local isMonster = false
    pcall(function() isMonster = asset ~= nil and asset.properties:IsMonster() end)
    if not isMonster then
        return {}
    end
    return {
        {
            text = "Encounter of the Week Assessment",
            click = function()
                ShowReport(monsterid)
            end,
        },
    }
end

--- Search filter for "ai:<word>".
--- @param value string
--- @param monsterid string
--- @return boolean
function EotwMonsterAssessment.SearchMatches(value, monsterid)
    value = string.lower(value or "")
    if value == "" then
        return true
    end
    local result = EotwMonsterAssessment.Assess(monsterid, false)
    if result == nil then
        return false
    end
    for _, word in ipairs(g_searchWords[result.key] or {}) do
        if string.sub(word, 1, #value) == value then
            return true
        end
    end
    --the AI level works too: ai:tailored, ai:capable, ai:basic, ai:minimal.
    local level = string.lower(result.support.level)
    return string.sub(level, 1, #value) == value
end

--A heading inside the report.
local function SectionTitle(text)
    return gui.Label {
        classes = { "fgStrong" },
        width = "100%",
        height = "auto",
        fontSize = 18,
        bold = true,
        tmargin = 14,
        bmargin = 4,
        text = text,
    }
end

local function BodyLabel(text, args)
    local params = {
        width = "100%",
        height = "auto",
        fontSize = 14,
        textWrap = true,
        tmargin = 2,
        text = text,
    }
    for k, v in pairs(args or {}) do
        params[k] = v
    end
    return gui.Label(params)
end

--One row of the kit table: name and kind, AI status, automation, reason.
local function KitRow(entry)
    local statusToken = "@success"
    if entry.status == MonsterAI.supportStatus.unused then
        statusToken = "@danger"
    elseif entry.status == MonsterAI.supportStatus.narrative then
        statusToken = "@fgMuted"
    elseif entry.status == MonsterAI.supportStatus.synthesized or entry.status == MonsterAI.supportStatus.generic then
        statusToken = "@info"
    end

    local reason = entry.reason
    if entry.source ~= nil and entry.status == MonsterAI.supportStatus.tailored then
        reason = string.format("%s <color=%s>%s</color>", reason, ThemeEngine.ResolveTokens("@fgMuted"), entry.source)
    end

    return gui.Panel {
        width = "100%",
        height = "auto",
        flow = "horizontal",
        tmargin = 3,

        gui.Label {
            width = 200,
            height = "auto",
            fontSize = 14,
            textWrap = true,
            valign = "top",
            text = string.format("<b>%s</b>\n<size=80%%>%s</size>", entry.name, entry.kind),
        },
        gui.Label {
            width = 120,
            height = "auto",
            fontSize = 14,
            valign = "top",
            text = Colored(statusToken, g_statusText[entry.status] or entry.status),
        },
        gui.Label {
            classes = { "implStatus" .. tostring(entry.implementation) },
            width = 130,
            height = "auto",
            fontSize = 14,
            valign = "top",
            text = ImplementationName(entry.implementation),
        },
        gui.Label {
            width = "100%-450",
            height = "auto",
            fontSize = 13,
            textWrap = true,
            valign = "top",
            text = reason,
        },
    }
end

--- The full report dialog for one monster.
--- @param monsterid string
ShowReport = function(monsterid)
    local result = EotwMonsterAssessment.Assess(monsterid, true)
    if result == nil then
        return
    end
    local support = result.support

    local children = {}
    local function Add(panel)
        children[#children + 1] = panel
    end

    Add(BodyLabel(string.format("%s  %s", VerdictMarkup(result), SummaryLine(result)), { fontSize = 16 }))
    Add(BodyLabel(result.why, { classes = { "fgMuted" } }))

    Add(SectionTitle("Issues"))
    if #result.issues == 0 then
        Add(BodyLabel("None: the AI uses its whole kit and the rules handle it."))
    end
    for _, issue in ipairs(result.issues) do
        Add(BodyLabel("- " .. issue.text))
    end

    Add(SectionTitle("Its kit"))
    if #support.entries == 0 then
        Add(BodyLabel("It has no abilities, Malice or triggered actions of its own."))
    end
    for _, entry in ipairs(support.entries) do
        Add(KitRow(entry))
    end
    if support.minion then
        Add(BodyLabel("Minions act as a squad: they move together and use their signature ability.", { classes = { "fgMuted" } }))
    end

    Add(SectionTitle("Hand-written AI"))
    if #support.registrations == 0 then
        Add(BodyLabel("None registered for this monster: anything it does comes from the generic AI and shared moves."))
    end
    for _, registration in ipairs(support.registrations) do
        local text = string.format("<b>%s</b> \"%s\"", registration.kind, registration.id)
        if registration.source ~= nil then
            text = text .. string.format("  <color=%s>%s</color>", ThemeEngine.ResolveTokens("@fgMuted"), registration.source)
        end
        if registration.description ~= "" then
            text = text .. "\n" .. registration.description
        end
        Add(BodyLabel(text))
    end

    if devmode() and #support.stale > 0 then
        Add(SectionTitle("Developer: stale AI registrations"))
        for _, stale in ipairs(support.stale) do
            Add(BodyLabel(string.format("%s \"%s\" names %s, which this monster does not have.", stale.kind, stale.id, stale.missing)))
        end
    end

    Add(SectionTitle("How this is worked out"))
    Add(BodyLabel(string.format([[It reads the Monster AI that is loaded now: hand-written moves, villain actions, Malice and trigger handlers registered for "%s" or its band, and, for each ability nothing hand-written covers, whether the generic AI can plan it from its targeting and effects. Automation is the same status the bestiary diamond shows.
AI levels: <b>Tailored</b> (hand-written AI, nearly the whole kit used), <b>Capable</b> (most of it, villain actions included), <b>Basic</b> (its signature works, much else doesn't), <b>Minimal</b> (it can't use its signature ability).
This says what the AI <i>can</i> use, not how well it plays: test the encounter (Game > Test Encounter) to see it.]], support.monsterType),
        { classes = { "fgMuted" }, fontSize = 13 }))

    local dialog
    dialog = gui.Panel {
        styles = ThemeEngine.GetStyles(),
        classes = { "dialog" },
        width = 900,
        height = "auto",
        flow = "vertical",
        pad = 20,
        borderBox = true,

        gui.Label {
            classes = { "modalTitle" },
            width = "100%",
            height = "auto",
            text = result.name,
        },
        BodyLabel("Encounter of the Week assessment", { classes = { "fgMuted" }, halign = "center", textAlignment = "center" }),

        gui.Panel {
            width = "100%",
            height = "auto",
            maxHeight = math.floor(dmhub.screenDimensionsBelowTitlebar.y * 0.7),
            vscroll = true,
            flow = "vertical",
            tmargin = 8,
            rpad = 12,
            borderBox = true,
            children = children,
        },

        gui.Button {
            text = "Close",
            width = 120,
            height = 36,
            halign = "center",
            tmargin = 14,
            escapeActivates = true,
            click = function(element)
                gui.CloseModal()
            end,
        },
    }

    gui.ShowModal(dialog)
end

if rawget(_G, "CharacterPanel") ~= nil and CharacterPanel.RegisterBestiaryExtension ~= nil then
    CharacterPanel.RegisterBestiaryExtension {
        id = "eotwMonsterAssessment",
        visible = EotwMonsterAssessment.Active,
        rowBadge = EotwMonsterAssessment.CreateRowBadge,
        entryHeader = EotwMonsterAssessment.CreateEntryHeader,
        menuItems = EotwMonsterAssessment.MenuItems,
        searchPrefix = "ai:",
        searchMatches = EotwMonsterAssessment.SearchMatches,
    }
end

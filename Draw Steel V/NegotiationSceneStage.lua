local mod = dmhub.GetModLoading()

--The negotiation screen for a NegotiationScene session (NegotiationScene.lua):
--the NPC speaks, the player picks who talks and what they say, and the session
--applies the book's rules. Arguments down the left, what the party has noticed
--and learned down the right, the deal on the table above the NPC, the heroes
--along the bottom (drag one onto an argument, or click a hero then an argument).
--
--This began as Lisa's Encounter of the Week negotiation stage, with
--everything that needed an EotW game passed in by the caller instead; the
--EotW game now mounts it too (EncounterMontageStage.lua, CreateNegotiationStage).
--It only reads the session's state and sends requests; with args.selfHosted it
--also runs the session's Tick, for a scene this client plays alone (the town).
--
--Use:
--  local panel = NegotiationSceneStage.Create{
--      session = NegotiationScene.LocalSession{ ... },
--      selfHosted = true,
--      figure = function() return <a panel showing the NPC> end,  --optional
--      createHeroCard = function(entry, opts) return <panel> end,  --optional
--      styles = { <extra rules, e.g. the hero card's> },           --optional
--      canAct = function(charid) return bool end,                  --optional
--      leave = true,          --a Leave button (and Escape) that ends the talk
--      onDone = function(result) end,  --the session is over (result may be nil)
--      heroRowHeight = 374,   --optional; the hero row's height (default 250)
--      monitorGame = path,    --optional; also refresh when this document changes
--      clueAffordable = function() return bool end,  --optional; may this player
--                             --pay for a hint? (the button shows only when the
--                             --session's CanSpendClue says one can be bought)
--  }
--Argument cards show "Your knack" / "You have an edge" from the session's
--rider verdict for the selected hero (verdict.gated, verdict.boons).
--
--Spoken lines type on. An argument plays as two lines: the hero says the
--argument's "PC:" line (while the dice are out, if it has a test), then the
--NPC answers. As each line starts the stage fires
--  "negotiationCast"(element, { heroid, heroName, speaker = "hero"|"npc"|nil, emote, emoteKey })
--down its tree, so a figure that wants to can bring the hero on and show the
--NPC's reaction (emote "pleased", "angry" or "alarmed"; emoteKey is new for
--each reaction). heroid is nil when no hero is on stage.

NegotiationSceneStage = rawget(_G, "NegotiationSceneStage") or {}

local T = UIText.T

local RAIL_WIDTH = 380
local SIDE_WIDTH = 320
local HEADER_HEIGHT = 156
local DEFAULT_HERO_ROW_HEIGHT = 250
local FIGURE_AREA_HEIGHT = 300
local SELECT_MODE = "negotiation"
--The speaker's portrait on the right of an argument card (a hero card's 3:4).
local CARD_PORTRAIT_WIDTH = 48
local CARD_PORTRAIT_HEIGHT = 64
--Spoken lines type on at this many characters a second (the EotW scenes' speed).
local TYPE_CPS = 45
--After the hero's line has typed out, the pause before the NPC answers.
local REPLY_PAUSE = 0.7

--The stage's own copies of the EotW stage's look (EncounterMontageStage
--StageRules), so it needs nothing from that file.
local g_rules = {
    { selectors = {"nsTitle"}, fontSize = 34, bold = true, color = "#ffffff", width = "auto", height = "auto", textAlignment = "center" },
    { selectors = {"nsSubtitle"}, fontSize = 16, color = "#d0d0d0", width = "auto", maxWidth = 1100, height = "auto", textAlignment = "center", textWrap = true },
    { selectors = {"nsRound"}, fontSize = 18, bold = true, color = "#ffd66b", width = "auto", height = "auto", textAlignment = "center" },
    { selectors = {"nsDesc"}, fontSize = 14, color = "#dcdcdc", width = "100%", height = "auto", textAlignment = "left", textWrap = true, tmargin = 4 },
    { selectors = {"nsPanel"}, bgcolor = "#0b0e12e0", border = 2, borderColor = "#ffffff30", cornerRadius = 10 },
    { selectors = {"nsText"}, fontSize = 16, color = "#e6e6e6", width = "100%", height = "auto", textAlignment = "center", textWrap = true, vmargin = 6 },
    { selectors = {"nsSpeech"}, fontSize = 18, color = "#ffffff", width = "100%", height = "auto", textAlignment = "left", textWrap = true, vmargin = 4 },
    { selectors = {"nsCard"}, bgcolor = "#161b22f0", border = 1, borderColor = "#ffffff30", cornerRadius = 6, transitionTime = 0.12 },
    { selectors = {"nsCard", "actionable", "hover"}, borderColor = "#ffffffc0", brightness = 1.2 },
    --a knack argument, in the montage's knack purple (EncounterMontageStage "unlocked").
    { selectors = {"nsCard", "knack"}, bgcolor = "#1d1626f0", borderColor = "#c58cffc0" },
    { selectors = {"nsCard", "knack", "actionable", "hover"}, borderColor = "#e2c6ffff" },
    { selectors = {"nsKnack"}, fontSize = 15, bold = true, color = "#d9b3ff", width = "100%", height = "auto", textAlignment = "left", textWrap = true, tmargin = 4 },
    { selectors = {"nsCard", "droppable"}, bgcolor = "#243018f2", borderColor = "#b8e04aff" },
    --the argument a dragged hero is over (the engine sets drag-target-hover),
    --in the selected hero's gold so it reads as "this one".
    { selectors = {"nsCard", "droppable", "drag-target-hover"}, bgcolor = "#3a4a1cf8", borderColor = "#ffd66bff", border = 3, brightness = 1.25 },
    { selectors = {"nsCard", "disabledCard"}, opacity = 0.6 },
    --a knack argument the selected hero cannot make.
    { selectors = {"nsCard", "notTheirs"}, opacity = 0.4 },
    { selectors = {"nsCardNote"}, fontSize = 16, bold = true, color = "#8ee08e", width = "100%", height = "auto", textAlignment = "center" },
    --a card's text, narrowed to make room for the speaker's portrait.
    { selectors = {"nsCardText"}, width = "100%" },
    { selectors = {"nsCardText", "withPortrait"}, width = string.format("100%%-%d", CARD_PORTRAIT_WIDTH + 8) },
    { selectors = {"nsCardPortrait"}, bgcolor = "#00000000", border = 1, borderColor = "#ffffff60", cornerRadius = 4 },
    { selectors = {"nsCardName"}, fontSize = 18, bold = true, color = "#ffffff", width = "100%", height = "auto", textAlignment = "left", textWrap = true },
    { selectors = {"nsSpeaker"}, fontSize = 21, bold = true, color = "#ffd66b", width = "auto", height = "auto", textAlignment = "left" },
    { selectors = {"nsPrompt"}, fontSize = 17, italics = true, color = "#ffd66b", width = "100%", height = "auto", textAlignment = "center", textWrap = true, bmargin = 10 },
    { selectors = {"nsSpoke"}, fontSize = 12, bold = true, color = "#b8e04a", width = 132, height = "auto", textAlignment = "center", tmargin = 4 },
    { selectors = {"nsHeroCard", "selected"}, borderColor = "#ffd66bff", border = 3, brightness = 1.15 },
    { selectors = {"nsHeroCard", "dragging"}, brightness = 1.2 },
    --the interest and patience meters: one cell per point, lit up to the
    --NPC's current value, each with a line under it saying what that means.
    { selectors = {"nsMeterName"}, fontSize = 14, bold = true, color = "#dcdcdc", width = 80, height = "auto", valign = "center", textAlignment = "right", rmargin = 10 },
    { selectors = {"nsMeterCell"}, bgcolor = "#ffffff10", border = 1, borderColor = "#ffffff38", cornerRadius = 3, transitionTime = 0.4 },
    { selectors = {"nsMeterCell", "patience", "filled"}, bgcolor = "#ffd66bff", borderColor = "#ffd66bff" },
    { selectors = {"nsMeterCell", "patience", "filled", "low"}, bgcolor = "#e0604aff", borderColor = "#e0604aff" },
    { selectors = {"nsMeterCell", "interest", "filled"}, bgcolor = "#7fd0e8ff", borderColor = "#7fd0e8ff" },
    { selectors = {"nsMeterCue"}, fontSize = 16, bold = true, width = "auto", height = "auto", textAlignment = "center", tmargin = 3 },
    { selectors = {"nsMeterCue", "patience"}, color = "#ffd66b" },
    { selectors = {"nsMeterCue", "interest"}, color = "#7fd0e8" },
}

--How many characters a line shows, tags not counted.
local function VisibleLength(markup)
    local plain = string.gsub(markup or "", "<[^>]*>", "")
    return utf8.len(plain) or #plain
end

--`markup` with only its first `count` characters visible. The rest is laid out
--but transparent, so the box does not grow as the line types.
local function RevealText(markup, count)
    local out = {}
    local shown, openColors = 0, 0
    local i, len = 1, #markup
    while i <= len and shown < count do
        local close = nil
        if string.sub(markup, i, i) == "<" then
            close = string.find(markup, ">", i, true)
        end
        if close ~= nil then
            local tag = string.sub(markup, i, close)
            if string.find(tag, "^<color") ~= nil then
                openColors = openColors + 1
            elseif string.find(tag, "^</color") ~= nil and openColors > 0 then
                openColors = openColors - 1
            end
            out[#out + 1] = tag
            i = close + 1
        else
            local nextChar = utf8.offset(markup, 2, i) or (i + 1)
            out[#out + 1] = string.sub(markup, i, nextChar - 1)
            shown = shown + 1
            i = nextChar
        end
    end
    if i <= len then
        for _ = 1, openColors do
            out[#out + 1] = "</color>"
        end
        local rest = string.gsub(string.sub(markup, i), "<[^>]*>", "")
        out[#out + 1] = "<color=#00000000>" .. rest .. "</color>"
    end
    return table.concat(out)
end

--The NPC's reaction to an argument (m.last), as an emote, or nil.
local function ReactionEmote(last)
    if last.track == "pitfall" or (tonumber(last.interest) or 0) < 0 then
        return "angry"
    elseif (tonumber(last.interest) or 0) > 0 then
        return "pleased"
    elseif (tonumber(last.patience) or 0) < 0 then
        return "alarmed"
    end
    return nil
end

local function PatienceCue(patience, npc)
    local keys = { [0] = "none", "one", "two", "three", "four", "five" }
    local key = keys[patience]
    if key == nil then
        return ""
    end
    return T("negscene.patience." .. key, { npc = npc })
end

local function InterestCue(interest, npc)
    local keys = { [0] = "none", "one", "two", "three", "four", "five" }
    local key = keys[interest]
    if key == nil then
        return ""
    end
    return T("negscene.interest." .. key, { npc = npc })
end

local function DefaultCanAct(charid)
    local tok = dmhub.GetCharacterById(charid)
    if tok == nil or not tok.valid then
        return false
    end
    local mine = false
    pcall(function() mine = tok.canControl end)
    return mine == true
end

local function TextRows(texts)
    local rows = {}
    for _, text in ipairs(texts) do
        rows[#rows + 1] = gui.Label{ classes = {"nsDesc"}, text = text, interactable = false }
    end
    return rows
end

--Build the stage. See the header for args.
---@param args table
---@return Panel
function NegotiationSceneStage.Create(args)
    local session = args.session
    local canActFn = args.canAct or DefaultCanAct
    local m_selectedHero = nil
    --the argument card a dragged hero is over (its portrait previews them).
    local m_previewTarget = nil
    local m_heroSignature = nil
    local m_cardSignature = nil
    local m_finished = false
    local heroRowHeight = args.heroRowHeight or DEFAULT_HERO_ROW_HEIGHT
    local stage

    local function CanAct(charid)
        local m = session:GetState()
        return m ~= nil and m.phase == "choosing" and canActFn(charid)
    end

    local function Broadcast(event, ...)
        if stage ~= nil and stage.valid then
            stage:FireEventTree(event, ...)
        end
    end

    local function SelectHero(charid, mode)
        m_selectedHero = charid
        Broadcast("selectHero", charid, mode)
    end

    local function Argue(argument, heroid)
        if heroid == nil or not CanAct(heroid) or not session:CanMakeArgument(heroid, argument) then
            return
        end
        audio.FireSoundEvent("Mouse.Click")
        SelectHero(nil)
        session:SendRequest("argue", { argumentId = argument.id, heroid = heroid })
    end

    --May the selected hero (if any) be dropped on this argument?
    local function SelectedMayMake(argument, heroid)
        return heroid == nil or session:CanMakeArgument(heroid, argument)
    end

    --A knack argument's line: what a hero needs to make it, then a small
    --token for each hero here who has it (their name on hover).
    local function KnackRow(argument, qualifiers)
        local needs = {}
        for _, rider in ipairs(argument.riders or {}) do
            if rider.effect == "allow" then
                needs[#needs + 1] = TestRiders.DisplayRequirementText(rider)
            end
        end
        local tokens = {}
        for _, hero in ipairs(qualifiers) do
            local tok = dmhub.GetCharacterById(hero.charid)
            if tok ~= nil and tok.valid then
                tokens[#tokens + 1] = gui.CreateTokenImage(tok, {
                    width = 28,
                    height = 28,
                    rmargin = 4,
                    halign = "left",
                    valign = "center",
                    linger = gui.Tooltip(hero.name),
                })
            end
        end
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            gui.Label{ classes = {"nsKnack"},
                text = T("negscene.argument.knack_for", { requirement = table.concat(needs, "; ") }), interactable = false },
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                wrap = true,
                tmargin = 4,
                children = tokens,
            },
        }
    end

    --A knack argument: `qualifiers` are the heroes ({charid, name}) who may make it.
    local function ArgumentCard(beat, m, argument, qualifiers)
        local known = argument.traitId ~= nil and (m.learned or {})[argument.traitId] == true
        local said = (m.usedArguments or {})[argument.id] == true
        local children = {
            gui.Label{ classes = {"nsCardName"}, text = argument.name, interactable = false },
        }
        local note = nil
        local trait = argument.traitId ~= nil and NegotiationScene.Trait(beat, argument.traitId) or nil
        if said then
            note = T("negscene.argument.said")
        elseif known and trait ~= nil and argument.kind == "pitfall" then
            note = T("negscene.argument.avoid", { trait = trait.name })
        elseif known and trait ~= nil and argument.kind == "motivation" then
            note = T("negscene.argument.appeal", { trait = trait.name })
        end
        if note ~= nil then
            children[#children + 1] = gui.Label{ classes = {"nsDesc"}, text = note, interactable = false }
        end
        if qualifiers ~= nil then
            children[#children + 1] = KnackRow(argument, qualifiers)
        end
        local edgeLabel = gui.Label{ classes = {"nsCardNote", "collapsed"}, text = "", interactable = false }
        children[#children + 1] = edgeLabel
        local classes = {"nsCard"}
        if qualifiers ~= nil then
            classes[#classes + 1] = "knack"
        end

        --Who is on this argument, shown as a portrait at the card's right: the
        --hero making it now, else whoever made it last.
        local speakerid = nil
        if m.turn ~= nil and m.turn.kind == "argue" and m.turn.argumentId == argument.id then
            speakerid = m.turn.heroid
        else
            for i = #(m.log or {}), 1, -1 do
                if m.log[i].argumentId == argument.id then
                    speakerid = m.log[i].heroid
                    break
                end
            end
        end
        local textColumn = gui.Panel{
            classes = {"nsCardText"},
            height = "auto",
            flow = "vertical",
            valign = "center",
            children = children,
        }
        local portrait = gui.Panel{
            classes = {"nsCardPortrait", "collapsed"},
            width = CARD_PORTRAIT_WIDTH,
            height = CARD_PORTRAIT_HEIGHT,
            lmargin = 8,
            valign = "center",
            bgimage = "panels/square.png",
            interactable = false,
        }
        --Show this hero's portrait (nil = none). Their art cropped as a hero
        --card crops it, or their token when they have no art.
        local m_portraitShown = false
        local function ShowPortrait(charid)
            local tok = charid ~= nil and dmhub.GetCharacterById(charid) or nil
            local shown = tok ~= nil and tok.valid
            if tok ~= nil and shown and charid ~= m_portraitShown then
                portrait.bgimage = "panels/square.png"
                portrait.selfStyle.bgcolor = "#00000000"
                portrait.selfStyle.imageRect = nil
                portrait.children = {}
                local art = false
                pcall(function() art = EotwHeroCard.ApplyPortrait(portrait, tok, CARD_PORTRAIT_WIDTH / CARD_PORTRAIT_HEIGHT) end)
                if not art then
                    portrait.children = { gui.CreateTokenImage(tok, {
                        width = CARD_PORTRAIT_WIDTH,
                        height = CARD_PORTRAIT_WIDTH,
                        halign = "center",
                        valign = "center",
                    }) }
                end
            end
            m_portraitShown = cond(shown, charid, false)
            portrait:SetClass("collapsed", not shown)
            textColumn:SetClass("withPortrait", shown)
        end

        --What depends on the selected hero is updated in place rather than by
        --rebuilding the list: selecting is the first thing a drag does, and a
        --rebuild mid-drag replaces the cards the engine took as drop targets.
        local function ApplySelection(element, heroid, mode)
            local notTheirs = not SelectedMayMake(argument, heroid)
            local verdict = heroid ~= nil and not notTheirs and session:Verdict(heroid, argument) or nil
            element:SetClass("notTheirs", notTheirs)
            element:SetClass("actionable", m.phase == "choosing" and not notTheirs)
            element:SetClass("disabledCard", m.phase ~= "choosing" or notTheirs)
            element:SetClass("droppable", heroid ~= nil and (mode or "") == SELECT_MODE and not notTheirs)
            --the edge says why: "Edge: your Wealth is 2+".
            local whys = {}
            for _, applied in ipairs(verdict ~= nil and (verdict.boons or 0) > 0 and verdict.applied or {}) do
                if TestRiders.Boons(applied.rider.effect) > 0 and applied.why ~= nil then
                    whys[#whys + 1] = applied.why
                end
            end
            if #whys > 0 then
                edgeLabel.text = T("negscene.argument.edge", { why = table.concat(whys, "; ") })
            end
            edgeLabel:SetClass("collapsed", #whys == 0)
        end

        return gui.Panel{
            classes = classes,
            width = "100%",
            height = "auto",
            --the text, then the speaker's portrait at the right.
            flow = "horizontal",
            pad = 8,
            borderBox = true,
            bmargin = 6,
            bgimage = "panels/square.png",
            dragTarget = true,
            dragTargetPriority = 10,
            data = { argument = argument },
            textColumn,
            portrait,
            create = function(element)
                ApplySelection(element, m_selectedHero, cond(m_selectedHero ~= nil, SELECT_MODE, nil))
                ShowPortrait(speakerid)
            end,
            --a hero dragged over this card previews as its speaker; off it
            --(or dropped), the card goes back to its own.
            previewSpeaker = function(element, target, charid)
                if target == element and charid ~= nil and SelectedMayMake(argument, charid) then
                    ShowPortrait(charid)
                else
                    ShowPortrait(speakerid)
                end
            end,
            press = function(element)
                Argue(argument, m_selectedHero)
            end,
            dragTargets = function(element, on, mode)
                element:SetClass("droppable", on == true and (mode or "") == SELECT_MODE and SelectedMayMake(argument, m_selectedHero))
            end,
            selectHero = function(element, heroid, mode)
                ApplySelection(element, heroid, mode)
            end,
        }
    end

    local function HeroColumn(hero)
        local charid = hero.charid
        local card = nil
        local opts = {
            halign = "center",
            draggable = CanAct(charid),
            click = function(element, openCharacterPanel)
                if CanAct(charid) then
                    audio.FireSoundEvent("Mouse.Click")
                    if m_selectedHero == charid then
                        SelectHero(nil)
                    else
                        SelectHero(charid, SELECT_MODE)
                    end
                    return
                end
                if openCharacterPanel ~= nil then
                    openCharacterPanel(element)
                end
            end,
            beginDrag = function(element)
                element:SetClass("dragging", true)
                SelectHero(charid, SELECT_MODE)
                Broadcast("dragTargets", true, SELECT_MODE)
            end,
            --every frame of the drag: the argument under it shows this hero.
            dragging = function(element, target)
                if target ~= m_previewTarget then
                    m_previewTarget = target
                    Broadcast("previewSpeaker", target, charid)
                end
            end,
            canDragOnto = function(element, target)
                return target:HasClass("nsCard") and CanAct(charid)
            end,
            drag = function(element, target)
                element:SetClass("dragging", false)
                Broadcast("dragTargets", false)
                m_previewTarget = nil
                Broadcast("previewSpeaker", nil, nil)
                if target ~= nil and target:HasClass("nsCard") then
                    Argue(target.data.argument, charid)
                end
            end,
        }
        if args.createHeroCard ~= nil then
            card = args.createHeroCard({ charid = charid, mine = false, name = hero.name }, opts)
        end
        if card == nil then
            card = gui.Label{
                width = 132,
                height = 176,
                text = hero.name,
                textAlignment = "center",
                bgimage = "panels/square.png",
                bgcolor = "#333333",
                press = function(element)
                    opts.click(element, nil)
                end,
            }
        end
        card:SetClass("nsHeroCard", true)
        --while dragged, the engine shows the dragged panel's cursor; without
        --one it falls through to the map's, "forbidden" with no map loaded.
        card.hoverCursor = "default"
        local spokeLabel = gui.Label{ classes = {"nsSpoke"}, text = "", halign = "center" }
        return gui.Panel{
            width = "auto",
            height = "auto",
            flow = "vertical",
            halign = "center",
            valign = "top",
            hmargin = 6,
            card,
            spokeLabel,
            --the EotW hero card repaints (portrait, stamina) on refreshCard;
            --nothing else fires it here, so do it once a second.
            thinkTime = 1,
            create = function(element)
                card:FireEventTree("refreshCard")
            end,
            think = function(element)
                card:FireEventTree("refreshCard")
            end,
            refreshNegotiation = function(element, m)
                local n = tonumber((m.spoke or {})[charid]) or 0
                card.draggable = CanAct(charid)
                card:SetClass("selected", m_selectedHero == charid)
                card:SetClass("acted", n > 0)
                local text = T("negscene.hero.quiet")
                if n == 1 then
                    text = T("negscene.hero.spoke_once")
                elseif n > 1 then
                    text = T("negscene.hero.spoke_many", { count = n })
                end
                spokeLabel.text = text
            end,
        }
    end

    local titleLabel = gui.Label{ classes = {"nsTitle"}, text = "", halign = "center" }
    local wantLabel = gui.Label{ classes = {"nsSubtitle"}, text = "", halign = "center" }
    --A meter ("interest" or "patience"): its name and one cell per point,
    --with the line saying what the value means under it. Set(value, cue)
    --lights the cells up to `value`.
    local function Meter(kind, name)
        local cells = {}
        local row = { gui.Label{ classes = {"nsMeterName"}, text = name, interactable = false } }
        for i = 1, NegotiationRules.MAX do
            cells[i] = gui.Panel{
                classes = {"nsMeterCell", kind},
                width = 64,
                height = 14,
                hmargin = 3,
                valign = "center",
                bgimage = "panels/square.png",
                interactable = false,
            }
            row[#row + 1] = cells[i]
        end
        --as wide as the name, so the cells sit centred over the cue.
        row[#row + 1] = gui.Panel{ width = 90, height = 1, interactable = false }
        local cue = gui.Label{ classes = {"nsMeterCue", kind}, text = "", halign = "center", interactable = false }
        local panel = gui.Panel{
            width = "auto",
            height = "auto",
            flow = "vertical",
            valign = "top",
            hmargin = 20,
            gui.Panel{ width = "auto", height = "auto", flow = "horizontal", halign = "center", children = row },
            cue,
        }
        return panel, function(value, text)
            for i, cell in ipairs(cells) do
                cell:SetClass("filled", i <= value)
                cell:SetClass("low", value <= 1)
            end
            cue.text = text
        end
    end
    local interestMeter, SetInterest = Meter("interest", T("negscene.interest_name"))
    local patienceMeter, SetPatience = Meter("patience", T("negscene.patience_name"))
    local header = gui.Panel{
        width = "100%",
        height = HEADER_HEIGHT,
        flow = "vertical",
        halign = "center",
        valign = "top",
        titleLabel,
        wantLabel,
        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "center",
            tmargin = 10,
            interestMeter,
            patienceMeter,
        },
    }

    local promptLabel = gui.Label{ classes = {"nsPrompt"}, text = "", vmargin = 2, valign = "top" }
    local cardList = gui.Panel{ width = "100%", height = "auto", flow = "vertical", valign = "top" }
    local readButton = gui.Button{
        width = "100%",
        height = 44,
        tmargin = 4,
        valign = "top",
        text = T("negscene.read"),
        click = function(element)
            local heroid = m_selectedHero
            if heroid ~= nil and CanAct(heroid) then
                SelectHero(nil)
                session:SendRequest("read", { heroid = heroid })
            end
        end,
    }
    local clueButton = gui.Button{
        width = "100%",
        height = 44,
        tmargin = 4,
        valign = "top",
        text = T("negscene.spend_clue"),
        classes = {"collapsed"},
        click = function(element)
            session:SendRequest("spendClue")
        end,
    }
    local leftRail = gui.Panel{
        classes = {"nsPanel"},
        width = RAIL_WIDTH,
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",
        bgimage = "panels/square.png",
        pad = 12,
        borderBox = true,
        vscroll = true,
        promptLabel,
        cardList,
        readButton,
        clueButton,
    }

    local offerShape = gui.Label{ classes = {"nsText"}, text = "", halign = "center" }
    local offerTerms = gui.Label{ classes = {"nsDesc"}, text = "", halign = "center", textAlignment = "center" }
    local offerPanel = gui.Panel{
        classes = {"nsPanel"},
        width = "90%",
        height = "auto",
        flow = "vertical",
        halign = "center",
        valign = "top",
        bgimage = "panels/square.png",
        pad = 8,
        borderBox = true,
        offerShape,
        offerTerms,
    }
    local figure = nil
    if args.figure ~= nil then
        figure = args.figure()
    end
    local speakerLabel = gui.Label{ classes = {"nsSpeaker"}, text = "", halign = "left" }
    local rollLabel = gui.Label{ classes = {"nsDesc"}, text = "" }
    local buttonRow = gui.Panel{ width = "auto", height = "auto", flow = "horizontal", halign = "right", tmargin = 6 }

    --The speech box plays lines one at a time. A line is
    --{ key, speaker, text, cast = <the negotiationCast table> }. Each key plays
    --once: a refresh asking for a line already played leaves it as it is.
    local m_played = {}
    local m_line = nil      --the line on screen
    local m_typing = nil    --{ start, total } while m_line is typing on
    local m_queued = nil    --{ line, at } the line to play after this one
    local m_heroOnStage = false
    local speechLabel

    local function StartLine(line, typeOn)
        m_played[line.key] = true
        m_line = line
        m_heroOnStage = line.cast ~= nil and line.cast.heroid ~= nil
        speakerLabel.text = line.speaker or ""
        if typeOn and VisibleLength(line.text) > 0 then
            m_typing = { start = dmhub.Time(), total = VisibleLength(line.text) }
            speechLabel.text = RevealText(line.text, 0)
            speechLabel.thinkTime = 0.03
        else
            m_typing = nil
            speechLabel.text = line.text
        end
        if line.cast ~= nil then
            Broadcast("negotiationCast", line.cast)
        end
    end

    local function FinishTyping()
        if m_typing ~= nil and m_line ~= nil then
            m_typing = nil
            speechLabel.text = m_line.text
            if m_queued ~= nil then
                m_queued.at = dmhub.Time() + REPLY_PAUSE
            end
        end
    end

    speechLabel = gui.Label{
        classes = {"nsSpeech"},
        text = "",
        think = function(element)
            if m_typing ~= nil and m_line ~= nil then
                local n = math.floor((dmhub.Time() - m_typing.start) * TYPE_CPS)
                if n >= m_typing.total then
                    FinishTyping()
                else
                    element.text = RevealText(m_line.text, n)
                end
                return
            end
            if m_queued ~= nil then
                if dmhub.Time() >= m_queued.at then
                    local line = m_queued.line
                    m_queued = nil
                    StartLine(line, true)
                end
                return
            end
            element.thinkTime = nil
        end,
    }

    --Show these lines, in order: any not played yet play one after another.
    --On the stage's first refresh only the last one plays, so a screen opened
    --mid-talk does not replay what was said before it.
    local function PlayLines(lines, firstRefresh)
        local todo = {}
        for _, line in ipairs(lines) do
            if not m_played[line.key] then
                todo[#todo + 1] = line
            end
        end
        if firstRefresh and #todo > 1 then
            todo = { todo[#todo] }
        end
        if #todo == 0 then
            --nothing new, but the words of the line on screen may have moved on
            --(a vote count); those change in place without typing.
            local current = lines[#lines]
            if current ~= nil and m_line ~= nil and current.key == m_line.key and m_typing == nil then
                speechLabel.text = current.text
            end
            return
        end
        local nextLine = todo[1]
        if m_typing ~= nil or (m_queued ~= nil and m_queued.line.key ~= nextLine.key) then
            --a line is still typing: the new one waits its turn.
            if m_typing == nil and m_queued ~= nil then
                StartLine(m_queued.line, false)
            end
            m_queued = { line = nextLine, at = math.huge }
            speechLabel.thinkTime = 0.03
            return
        end
        if m_queued ~= nil and m_queued.line.key == nextLine.key then
            return
        end
        StartLine(nextLine, true)
        if todo[2] ~= nil then
            m_queued = { line = todo[2], at = math.huge }
        end
    end

    local dialogBox = gui.Panel{
        classes = {"nsPanel"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "bottom",
        bgimage = "panels/square.png",
        pad = 14,
        borderBox = true,
        --a click finishes the line typing on, or brings on the one waiting.
        press = function(element)
            if m_typing ~= nil then
                FinishTyping()
            elseif m_queued ~= nil then
                m_queued.at = 0
            end
        end,
        speakerLabel,
        speechLabel,
        rollLabel,
        buttonRow,
    }
    local center = gui.Panel{
        width = string.format("100%%-%d", RAIL_WIDTH + SIDE_WIDTH + 24),
        height = "100%",
        flow = "vertical",
        halign = "center",
        valign = "top",
        hmargin = 12,
        offerPanel,
        gui.Panel{
            width = "100%",
            height = "100%-260",
            flow = "none",
            children = { figure },
        },
        dialogBox,
    }

    local clueList = gui.Panel{ width = "100%", height = "auto", flow = "vertical", valign = "top" }
    local learnedList = gui.Panel{ width = "100%", height = "auto", flow = "vertical", valign = "top" }
    local logList = gui.Panel{ width = "100%", height = "auto", flow = "vertical", valign = "top" }
    local rightRail = gui.Panel{
        classes = {"nsPanel"},
        width = SIDE_WIDTH,
        height = "100%",
        flow = "vertical",
        halign = "right",
        valign = "top",
        bgimage = "panels/square.png",
        pad = 12,
        borderBox = true,
        vscroll = true,
        gui.Label{ classes = {"nsPrompt"}, text = T("negscene.noticed"), vmargin = 2, valign = "top" },
        clueList,
        gui.Label{ classes = {"nsPrompt"}, text = T("negscene.learned"), vmargin = 2, tmargin = 10, valign = "top" },
        learnedList,
        gui.Label{ classes = {"nsPrompt"}, text = T("negscene.so_far"), vmargin = 2, tmargin = 10, valign = "top" },
        logList,
    }

    local body = gui.Panel{
        width = "100%-40",
        height = string.format("100%%-%d", HEADER_HEIGHT + heroRowHeight),
        flow = "horizontal",
        halign = "center",
        valign = "top",
        leftRail,
        center,
        rightRail,
    }
    local heroRow = gui.Panel{
        width = "auto",
        height = heroRowHeight,
        flow = "horizontal",
        halign = "center",
        valign = "bottom",
        tmargin = 10,
    }

    local function Leave()
        local m = session:GetState()
        if m == nil or m.phase == "done" then
            return
        end
        audio.FireSoundEvent("Mouse.Click")
        session:SendRequest("walkOut")
    end

    --What taking the deal now gets: the same two lines as the offer box at the
    --top ("On the table: Yes, but..." and the offer's line).
    local function DealTooltip()
        local m = session:GetState()
        local beat = session:Beat()
        if m == nil or beat == nil then
            return ""
        end
        local lines = { T("negscene.on_the_table", { shape = NegotiationRules.offerLabels[m.interest] or "" }) }
        local offer = beat.offers[m.interest + 1]
        if offer ~= nil and offer.text ~= "" then
            lines[#lines + 1] = offer.text
        end
        return table.concat(lines, "\n")
    end

    local function Buttons(m)
        local buttons = {}
        if not session:MayAct(dmhub.loginUserid, session:Heroes()) then
            return buttons
        end
        local function Add(text, fn, tooltip)
            buttons[#buttons + 1] = gui.Button{
                width = 200, height = 44, lmargin = 8, text = text, click = fn,
                --worked out on hover, so it always matches the bars.
                linger = tooltip ~= nil and function(element)
                    gui.Tooltip(tooltip())(element)
                end or nil,
            }
        end
        if session:CanTakeDeal(m) then
            Add(T("negscene.take_deal"), function() session:SendRequest("takeDeal") end, DealTooltip)
        elseif m.phase == "reply" or m.phase == "done" then
            Add(T("negscene.continue"), function() session:SendRequest("continue") end)
        elseif m.phase == "voting" then
            Add(T("negscene.vote_deal"), function() session:SendRequest("vote", { choice = "deal" }) end)
            Add(T("negscene.vote_talk"), function() session:SendRequest("vote", { choice = "talk" }) end)
        elseif m.phase == "final" then
            for _, option in ipairs(m.voteOptions or {}) do
                if option == "deal" then
                    Add(T("negscene.vote_deal"), function() session:SendRequest("vote", { choice = "deal" }) end)
                elseif option == "refuse" then
                    Add(T("negscene.vote_refuse"), function() session:SendRequest("vote", { choice = "refuse" }) end)
                end
            end
        end
        if args.leave and m.phase ~= "done" and m.phase ~= "final" then
            Add(T("negscene.leave"), Leave)
        end
        return buttons
    end

    local function HeroSignature(heroes)
        local parts = {}
        for _, hero in ipairs(heroes) do
            parts[#parts + 1] = hero.charid
        end
        return table.concat(parts, "|")
    end

    local function Refresh(element)
        local m = session:GetState()
        local beat = session:Beat()
        if m == nil or beat == nil then
            return
        end
        local npc = beat.name
        titleLabel.text = npc
        wantLabel.text = beat.want
        wantLabel:SetClass("collapsed", beat.want == "")

        SetInterest(m.interest, InterestCue(m.interest, npc))
        SetPatience(m.patience, PatienceCue(m.patience, npc))

        local offer = beat.offers[m.interest + 1]
        offerShape.text = T("negscene.on_the_table", { shape = NegotiationRules.offerLabels[m.interest] or "" })
        offerTerms.text = offer ~= nil and offer.text or ""
        offerTerms:SetClass("collapsed", offerTerms.text == "")

        --who is speaking: the NPC's reply, a read's result, or how it ended.
        --An argument is two lines, the hero's then the NPC's (see PlayLines).
        local npcCast = { speaker = "npc" }
        local lines = { { key = "opening", speaker = npc, text = beat.opening, cast = npcCast } }
        local roll = ""
        local last = m.last
        local replyKey = "reply|" .. tostring(m.replyAt)
        local argued = #(m.log or {})
        --the hero's line for an argument, or nil when the script gives none.
        local function HeroLine(argumentId, heroid, heroName, n)
            local argument = NegotiationScene.Argument(beat, argumentId)
            if argument == nil or (argument.say or "") == "" then
                return nil
            end
            return { key = "say|" .. n, speaker = heroName, text = argument.say,
                cast = { heroid = heroid, heroName = heroName, speaker = "hero" } }
        end
        if last ~= nil and last.kind == "clue" then
            --a hint bought with Intelligence (the host's SpendClue)
            local trait = last.found ~= nil and NegotiationScene.Trait(beat, last.found) or nil
            roll = T("negscene.clue_found", { trait = trait ~= nil and trait.name or "" })
        elseif last ~= nil and last.kind == "read" then
            local trait = last.found ~= nil and NegotiationScene.Trait(beat, last.found) or nil
            local speech
            if trait ~= nil then
                speech = T("negscene.read_found", { hero = last.heroName, trait = trait.name })
            elseif (tonumber(last.tier) or 1) <= 1 then
                speech = T("negscene.read_pushed", { hero = last.heroName, npc = npc })
            else
                speech = T("negscene.read_nothing", { hero = last.heroName })
            end
            lines = { { key = replyKey, speaker = last.heroName, text = speech,
                cast = { heroid = last.heroid, heroName = last.heroName, speaker = "hero" } } }
        elseif last ~= nil then
            lines = {}
            local said = HeroLine(last.argumentId, last.heroid, last.heroName, argued)
            if said ~= nil then
                lines[#lines + 1] = said
            end
            lines[#lines + 1] = { key = replyKey, speaker = npc, text = last.reply or "",
                cast = { heroid = said ~= nil and last.heroid or nil, heroName = last.heroName, speaker = "npc",
                    emote = ReactionEmote(last), emoteKey = replyKey } }
            local argument = NegotiationScene.Argument(beat, last.argumentId)
            if argument ~= nil then
                roll = T("negscene.argued", { hero = last.heroName, argument = argument.name })
            end
        end
        if m.phase == "rolling" and m.turn ~= nil then
            local t = m.turn
            local said = t.kind == "argue" and HeroLine(t.argumentId, t.heroid, t.heroName, argued + 1) or nil
            if said ~= nil then
                lines = { said }
            else
                lines = { { key = "rolling|" .. tostring(t.rollSeq), speaker = t.heroName, text = T("negscene.rolling"),
                    cast = { heroid = t.heroid, heroName = t.heroName, speaker = "hero" } } }
            end
            roll = ""
        elseif m.phase == "final" or m.phase == "voting" then
            roll = cond(m.phase == "final", T("negscene.final_offer"), T("negscene.voting"))
            local key = session:VoterKey(session:UserId(), session:Heroes())
            local mine = key ~= nil and (m.votes or {})[key] or nil
            if mine ~= nil then
                local said = cond(mine.choice == "deal", T("negscene.vote_deal"),
                    cond(mine.choice == "talk", T("negscene.vote_talk"), T("negscene.vote_refuse")))
                roll = T("negscene.vote_yours", { text = roll, choice = said })
            end
            --with one voter the only one waiting is you, which needs no saying.
            local waiting = session:PendingVoters(m)
            if #waiting > 0 and #session:Voters(session:Heroes()) > 1 then
                roll = T("negscene.vote_waiting", { text = roll, players = table.concat(waiting, ", ") })
            end
        elseif m.phase == "done" and m.result ~= nil then
            roll = cond(m.result.outcome == "nodeal", T("negscene.no_deal"),
                cond(m.result.outcome == "refused", T("negscene.refused"), T("negscene.deal")))
        end
        if m.split ~= nil and (m.phase == "choosing" or m.phase == "done") then
            roll = T("negscene.split", { player = m.split, text = roll })
        end
        PlayLines(lines, m_line == nil)
        --the hero steps off once the table is choosing again and the last
        --line has finished.
        if m_heroOnStage and m.phase ~= "rolling" and m.phase ~= "reply" and m_typing == nil and m_queued == nil then
            m_heroOnStage = false
            Broadcast("negotiationCast", { speaker = nil })
        end
        rollLabel.text = roll
        rollLabel:SetClass("collapsed", roll == "")

        promptLabel.text = cond(m.phase == "voting" or m.phase == "final", T("negscene.prompt_vote"),
            cond(m.phase ~= "choosing", T("negscene.prompt_wait"),
                cond(m_selectedHero ~= nil, T("negscene.prompt_argument"),
                    cond(#session:Voters(session:Heroes()) > 1, T("negscene.prompt_hero_party"), T("negscene.prompt_hero")))))
        readButton:SetClass("collapsed", m.phase ~= "choosing" or not m.canRead)
        clueButton:SetClass("collapsed", not session:CanSpendClue(m, beat)
            or not session:MayAct(dmhub.loginUserid, session:Heroes())
            or (args.clueAffordable ~= nil and not args.clueAffordable()))

        local clues, learned, log = {}, {}, {}
        for _, trait in ipairs(beat.traits) do
            if (m.learned or {})[trait.id] then
                learned[#learned + 1] = cond(trait.kind == "motivation",
                    T("negscene.learned_motivation", { trait = trait.name }),
                    T("negscene.learned_pitfall", { trait = trait.name }))
            elseif trait.clue ~= "" then
                clues[#clues + 1] = trait.clue
            end
        end
        for i = #(m.log or {}), math.max(1, #(m.log or {}) - 4), -1 do
            log[#log + 1] = T("negscene.log", { hero = m.log[i].heroName, argument = m.log[i].text })
        end

        local heroes = session:Heroes()
        --not the selected hero: the cards follow it in place (ApplySelection).
        local signature = string.format("%s|%s|%d|%d|%d|%s", tostring(m.seq), tostring(m.phase),
            #clues, #learned, #log, HeroSignature(heroes))
        if signature ~= m_cardSignature then
            m_cardSignature = signature
            local cards = {}
            for _, argument in ipairs(beat.arguments) do
                local secret = false
                for _, rider in ipairs(argument.riders or {}) do
                    secret = secret or rider.effect == "allow"
                end
                --a knack argument shows while anyone in the party can make it,
                --naming who.
                local qualifiers = nil
                if secret then
                    qualifiers = {}
                    for _, hero in ipairs(heroes) do
                        if session:CanMakeArgument(hero.charid, argument) then
                            qualifiers[#qualifiers + 1] = hero
                        end
                    end
                end
                if qualifiers == nil or #qualifiers > 0 then
                    cards[#cards + 1] = ArgumentCard(beat, m, argument, qualifiers)
                end
            end
            cardList.children = cards
            clueList.children = TextRows(clues)
            learnedList.children = TextRows(learned)
            logList.children = TextRows(log)
            buttonRow.children = Buttons(m)
        end

        local sig = HeroSignature(heroes)
        if sig ~= m_heroSignature then
            m_heroSignature = sig
            local columns = {}
            for _, hero in ipairs(heroes) do
                columns[#columns + 1] = HeroColumn(hero)
            end
            heroRow.children = columns
        end
        element:FireEventTree("refreshNegotiation", m)
    end

    local styles = {}
    for _, list in ipairs({ args.styles or {}, g_rules }) do
        for _, rule in ipairs(list) do
            styles[#styles + 1] = rule
        end
    end

    stage = gui.Panel{
        styles = ThemeEngine.MergeTokens(styles),
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        flow = "vertical",
        bgcolor = "#00000000",
        swallowPress = true,
        captureEscape = args.leave == true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            Leave()
        end,
        children = { header, body, heroRow },

        monitorGame = args.monitorGame,
        refreshGame = function(element)
            Refresh(element)
        end,
        create = function(element)
            Refresh(element)
        end,

        thinkTime = 0.1,
        think = function(element)
            if mod.unloaded then
                element:DestroySelf()
                return
            end
            if args.selfHosted and not m_finished then
                local ok, status = pcall(session.Tick, session)
                if not ok then
                    printf("Negotiation: tick failed: %s", tostring(status))
                elseif status == "done" or status == nil then
                    m_finished = true
                    local m = session:GetState()
                    if args.onDone ~= nil then
                        args.onDone(m ~= nil and m.result or nil)
                    end
                    return
                end
            end
            pcall(session.ClientTick, session)
            Refresh(element)
        end,
    }
    return stage
end

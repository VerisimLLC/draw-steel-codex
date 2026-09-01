local mod = dmhub.GetModLoading()

--- The negotiation in play. One body serves both sides: the Director's carries
--- the live scales and the eyes; the players' carries only what is revealed.
NEGRunPanel = RegisterGameType("NEGRunPanel")

--- A form label over its value, matching the configuration screen.
--- @param labelText string
--- @param width string
--- @param control Panel
--- @return Panel
local function Field(labelText, width, control)
    --Not formStackedRow: its lmargin 12 / bmargin 8 are far too loose for a
    --read-only strip of facts.
    return gui.Panel{
        width = width,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        bmargin = 4,

        gui.Label{
            classes = { "sizeS" },
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            text = labelText,
        },

        control,
    }
end

--- The value under a field label. Dim, and uniform across all of them.
--- @param args nil|table extra panel args, e.g. markdown or textWrap
--- @return Panel
local function FieldValue(args)
    local panelArgs = {
        classes = { "sizeS", "noBold", "fgMuted" },
        width = "98%",
        height = "auto",
        halign = "left",
        valign = "top",
        text = "",
    }

    for key, value in pairs(args or {}) do
        panelArgs[key] = value
    end

    return gui.Label(panelArgs)
end

--- One motivation or pitfall: the Director's eye, the trait, and its note.
--- @param entry table a NEGRun.Traits row
--- @param director boolean
--- @return Panel
local function TraitRow(entry, director)
    --The table gets one line of prose, not a row of controls.
    if not director then
        return gui.Label{
            classes = { "sizeS", "noBold", "fgMuted" },
            width = "98%",
            height = "auto",
            halign = "left",
            valign = "top",
            vmargin = 4,
            textWrap = true,
            markdown = true,
            text = string.format("**%s:** %s", entry.name, entry.note),
        }
    end

    local children = {
        NEGWidgets.EyeToggle{
            shown = entry.revealed,
            change = function(shown)
                NEGRun.SetTraitRevealed(entry.id, shown)
            end,
        },
    }

    children[#children + 1] = gui.Label{
        classes = { "sizeS" },
        width = "100% available",
        height = "auto",
        halign = "left",
        valign = "center",
        lmargin = cond(director, 6, 0),
        text = entry.name,
    }

    local rows = {
        gui.Panel{
            width = "100%",
            height = 22,
            flow = "horizontal",
            halign = "left",
            valign = "top",
            children = children,
        },
    }

    if trim(entry.note) ~= "" then
        rows[#rows + 1] = gui.Label{
            classes = { "sizeXs", "noBold", "fgMuted" },
            width = "100%-24",
            height = "auto",
            halign = "right",
            valign = "top",
            tmargin = 1,
            textWrap = true,
            text = entry.note,
        }
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        vmargin = 4,
        children = rows,
    }
end

--- One side of the traits pane, alphabetical by trait.
--- @param live NEGLive
--- @param kind string
--- @param title string
--- @param director boolean
--- @return Panel
local function TraitColumn(live, kind, title, director)
    local entries = NEGRun.Traits(live, kind)

    local children = {
        gui.Label{
            classes = { "sizeL" },
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            bmargin = 4,
            text = title,
        },
    }

    local shown = 0
    for _, entry in ipairs(entries) do
        if director or entry.revealed then
            shown = shown + 1
            children[#children + 1] = TraitRow(entry, director)
        end
    end

    if shown == 0 then
        children[#children + 1] = gui.Label{
            classes = { "sizeXs", "noBold", "fgMuted" },
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            vmargin = 6,
            textAlignment = "left",
            text = cond(director, "None yet.", "Nothing revealed."),
        }
    end

    return gui.Panel{
        width = NEGConstants.traitColumnWidth,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        rmargin = NEGConstants.traitColumnGap,
        children = children,
    }
end

--- One hero, and whether they are at this table.
--- @param p NEGParticipant
--- @param index number
--- @return Panel
local function ParticipantRow(p, index)
    local charid = p.charid
    local token = dmhub.GetCharacterById(charid)

    local children = {
        gui.Check{
            classes = { "sizeS" },
            text = "",
            width = 30,
            minWidth = 1,
            value = p:try_get("included", true),
            halign = "left",
            valign = "center",
            change = function(element)
                NEGRun.SetParticipantIncluded(charid, element.value)
            end,
        },
    }

    if token ~= nil then
        children[#children + 1] = gui.CreateTokenImage(token, {
            width = NEGConstants.participantImageSize,
            height = NEGConstants.participantImageSize,
            halign = "left",
            valign = "center",
        })
    end

    children[#children + 1] = gui.Label{
        classes = { "sizeS" },
        width = "auto",
        height = "auto",
        lmargin = 8,
        halign = "left",
        valign = "center",
        text = p:try_get("name", ""),
    }

    return gui.Panel{
        classes = { "row", cond(index % 2 == 1, "oddRow", "evenRow") },
        width = "100%",
        height = NEGConstants.participantRowHeight,
        flow = "horizontal",
        valign = "top",
        children = children,
    }
end

--- Who is at the table, and what that does to the NPC's patience. Nothing is
--- committed until Start.
--- @return {body: Panel, footer: table[]}
function NEGRunPanel.CreateSetup()
    local titleLabel = gui.Label{
        classes = { "sizeL" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        textWrap = true,
        text = "",
    }

    local openingLabel = gui.Label{
        classes = { "sizeS", "noBold", "fgMuted" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 4,
        textWrap = true,
        text = "",
    }

    local rosterPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
    }

    local body
    body = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",

        negotiationChanged = function(element)
            element:FireEvent("rebuild")
        end,

        rebuild = function()
            local live = NEGRun.Active()
            if live == nil then
                return
            end

            local npc = live:NpcName()
            titleLabel.text = cond(npc ~= "", npc, live:Name())

            local patience, bonus, speakers = NEGRun.PreviewOpening(live)
            local def = live:Definition()
            local language = NEGRules.LanguageName(
                def ~= nil and def:try_get("languageId", "") or "")

            if bonus > 0 then
                openingLabel.text = string.format(
                    "Opens at Interest %d, Patience %d. %d of them %s %s, for +%d patience.",
                    live.interest, patience, #speakers,
                    cond(#speakers == 1, "speaks", "speak"), language, bonus)
            elseif language ~= "" then
                openingLabel.text = string.format(
                    "Opens at Interest %d, Patience %d. Nobody here speaks %s.",
                    live.interest, patience, language)
            else
                openingLabel.text = string.format(
                    "Opens at Interest %d, Patience %d.", live.interest, patience)
            end

            local rows = {}
            for i, p in ipairs(live:try_get("participants", {})) do
                rows[#rows + 1] = ParticipantRow(p, i)
            end

            if #rows == 0 then
                rows[1] = gui.Label{
                    classes = { "sizeS", "noBold", "fgMuted" },
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    valign = "top",
                    vmargin = 8,
                    text = "No heroes found.",
                }
            end

            rosterPanel.children = rows
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        titleLabel,
        openingLabel,

        gui.Panel{
            width = NEGConstants.sectionWidth,
            height = "100% available",
            flow = "vertical",
            halign = "left",
            valign = "top",
            tmargin = 12,
            vscroll = true,

            NEGWidgets.SectionHeader{ text = "Who Is Negotiating" },
            rosterPanel,
        },
    }

    return {
        body = body,
        footer = {
            {
                slot = gui.Button{
                    classes = { "sizeL" },
                    text = "Cancel",
                    halign = "left",
                    valign = "center",
                    hover = gui.Tooltip("Back to the library. Nothing is kept."),
                    click = function()
                        NEGRun.Discard()
                    end,
                },
            },
            {},
            {
                slot = gui.Button{
                    classes = { "sizeL" },
                    text = "Start",
                    halign = "right",
                    valign = "center",
                    click = function(element)
                        NEGRun.Start()
                        NEGRun.PresentToPlayers(element)
                    end,
                },
            },
        },
    }
end

--- One track: its slots, pickers and die.
--- @param live NEGLive
--- @param args {track: string, title: string, slots: {key: string, label: string}[]}
--- @return Panel
local function TrackPanel(live, args)
    --A request belongs to ONE track. Read globally, an outstanding roll froze
    --both and left the idle track's die silently dead.
    local res = live:try_get("resolution")
    local rolling = res ~= nil and res.track == args.track
    local blocked = res ~= nil and res.track ~= args.track

    --The curtain only stops clicks; a drop target is a separate mechanism, so
    --the lockout has to make the slots inert as well.
    local locked = not args.director
        and args.track == NEGConstants.trackLearn
        and live:try_get("learnLocked", false)

    local sealed = rolling or locked
    local free = NEGRun.FreeHeroes(live)

    --Ready means a hero is standing there, nothing more. Whether a roll is
    --already out is TriggerRoll's business: it can tell a live request from a
    --dead one, and clear the dead one rather than stay disabled forever.
    local primary = args.slots[1].key
    local ready = NEGRun.Slot(live, primary) ~= nil

    --Asking for a roll is the Director's call, so the table gets no die. A
    --track whose roll is in swaps its die for a reset.
    local settled = false
    for _, slot in ipairs(args.slots) do
        if NEGRun.RollFor(live, slot.key) ~= nil then
            settled = true
        end
    end

    local slotKeys = {}
    for _, slot in ipairs(args.slots) do
        slotKeys[#slotKeys + 1] = slot.key
    end

    local dieButton
    if not args.director then
        dieButton = gui.Panel{
            width = 0,
            height = 0,
        }
    elseif settled then
        dieButton = gui.Button{
            classes = { "sizeXs" },
            icon = NEGConstants.iconReset,
            width = 22,
            height = 22,
            halign = "left",
            valign = "center",
            rmargin = 8,
            hover = gui.Tooltip("Clear this track. Whoever rolled goes back to the tray, spent."),
            click = function()
                NEGRun.ResetTrack(args.track, slotKeys)
            end,
        }
    elseif rolling then
        dieButton = gui.Button{
            classes = { "sizeXs" },
            icon = NEGConstants.iconRoll,
            width = 22,
            height = 22,
            halign = "left",
            valign = "center",
            rmargin = 8,
            hover = gui.Tooltip("Waiting on the roll. Press to take it back."),
            click = function()
                NEGRun.CancelRoll()
            end,
        }
    else
        dieButton = gui.Button{
            classes = { "sizeXs", cond(ready, nil, "disabled") },
            icon = NEGConstants.iconRoll,
            width = 22,
            height = 22,
            halign = "left",
            valign = "center",
            rmargin = 8,
            hover = gui.Tooltip(cond(blocked,
                "Waiting on the other track's roll",
                cond(ready,
                    "Request rolls",
                    string.format("Put a hero in the %s slot first", args.slots[1].label)))),
            click = function(element)
                if element:HasClass("disabled") then
                    return
                end
                NEGRun.TriggerRoll(args.track)
            end,
        }
    end

    --Fixed height, and the label sized in pixels. An auto-height label taking
    --"100% available" inside a horizontal flow resolves to something enormous.
    local children = {
        gui.Panel{
            width = "100%",
            height = 26,
            flow = "horizontal",
            halign = "left",
            valign = "top",
            bmargin = 2,

            dieButton,

            gui.Label{
                classes = { "sizeL" },
                width = "100%-30",
                height = "100%",
                halign = "left",
                valign = "center",
                text = args.title,
            },
        },
    }

    --Units share a line. The track's width is set by how many it holds, so a
    --unit is the same size in either track.
    local units = {}
    local unitWidth = string.format("%d%%", math.floor(100 / math.max(1, #args.slots)))

    for _, slot in ipairs(args.slots) do
        local slotKey = slot.key
        local entry = NEGRun.Slot(live, slotKey)

        local pickers = {}
        local roll = NEGRun.RollFor(live, slotKey)

        if roll ~= nil then
            --The choices are spent, so what they produced replaces them. Both
            --windows get this: the table watched the dice, they should see the
            --same numbers the Director is reading.
            local isAssist = slotKey == NEGConstants.slotAssist

            local parts = {}
            if isAssist then
                parts[#parts + 1] = string.format("Tier %d", roll.tier or 0)
            end

            parts[#parts + 1] = tostring(roll.total or 0)
            parts[#parts + 1] = string.format("Natural %d", roll.naturalRoll or 0)
            parts[#parts + 1] = string.format("%s %s",
                NEGRules.CharacteristicName(roll.attrId),
                NEGRules.SignedModifier(
                    NEGRules.CharacteristicModifier(roll.charid, roll.attrId)))

            if roll.skillId ~= nil and roll.skillId ~= "" then
                parts[#parts + 1] = NEGRules.SkillName(roll.skillId)
            else
                parts[#parts + 1] = "no skill"
            end

            local boons = roll.boons or 0
            local banes = roll.banes or 0
            if boons > 0 then
                parts[#parts + 1] = string.format("%d edge%s", boons, cond(boons == 1, "", "s"))
            elseif banes > 0 then
                parts[#parts + 1] = string.format("%d bane%s", banes, cond(banes == 1, "", "s"))
            end

            local verdict = string.format("Tier %d", roll.tier or 0)
            if isAssist then
                verdict = string.format("Grants %s",
                    string.gsub(NEGRun.AssistGrant(roll.tier or 1), "_", " "))
            end

            pickers[#pickers + 1] = gui.Label{
                classes = { "sizeS" },
                width = "98%",
                height = "auto",
                halign = "left",
                valign = "top",
                markdown = true,
                text = string.format("**%s**", verdict),
            }

            pickers[#pickers + 1] = gui.Label{
                classes = { "sizeXs", "noBold", "fgMuted" },
                width = "98%",
                height = "auto",
                halign = "left",
                valign = "top",
                textWrap = true,
                text = table.concat(parts, " | "),
            }

            --Withheld unless open: this is the tier read against the chosen
            --ladder, so a table that sees it can derive the NPC's motivations.
            local mayRead = args.director or live:try_get("open", false)

            if mayRead and roll.outcomeText ~= nil and roll.outcomeText ~= "" then
                pickers[#pickers + 1] = gui.Label{
                    classes = { "sizeXs", "noBold", "warning" },
                    width = "98%",
                    height = "auto",
                    halign = "left",
                    valign = "top",
                    tmargin = 2,
                    textWrap = true,
                    text = roll.outcomeText,
                }
            end
        elseif entry ~= nil then
            pickers[#pickers + 1] = gui.Dropdown{
                classes = { "formStacked", "sizeXs" },
                width = "98%",
                height = 24,
                halign = "left",
                valign = "center",
                vmargin = 1,
                options = NEGRules.CharacteristicOptions(),
                idChosen = entry.attrId,
                interactable = not sealed,
                change = function(element)
                    NEGRun.SetSlotField(slotKey, "attrId", element.idChosen)
                end,
            }

            pickers[#pickers + 1] = gui.Dropdown{
                classes = { "formStacked", "sizeXs" },
                width = "98%",
                height = 24,
                halign = "left",
                valign = "center",
                vmargin = 1,
                options = NEGRules.SkillOptionsFor(entry.charid),
                idChosen = entry.skillId or "",
                interactable = not sealed,
                change = function(element)
                    NEGRun.SetSlotField(slotKey, "skillId", element.idChosen)
                end,
            }

            --Only the lead argues. Set before the die goes out: it decides
            --which ladder the returned tier is read against.
            if slotKey == NEGConstants.slotLead and args.director then
                pickers[#pickers + 1] = gui.Check{
                    classes = { "sizeXs" },
                    text = "Motivation",
                    width = "98%",
                    height = 24,
                    halign = "left",
                    valign = "center",
                    vmargin = 1,
                    value = live:try_get("appealMotivation", false),
                    change = function(element)
                        NEGRun.SetAppealMotivation(element.value)
                    end,
                }
            end
        end

        units[#units + 1] = gui.Panel{
            width = unitWidth,
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "top",

            NEGWidgets.Slot{
                label = slot.label,
                charid = entry ~= nil and entry.charid or nil,
                name = entry ~= nil and NEGRun.ParticipantName(live, entry.charid) or "",
                inert = sealed,
                options = free,
                place = function(charid)
                    NEGRun.Stage(slotKey, charid)
                end,
                clear = function()
                    NEGRun.Unstage(slotKey)
                end,
            },

            gui.Panel{
                width = "96%-54",
                height = "auto",
                flow = "vertical",
                halign = "left",
                valign = "center",
                children = pickers,
            },
        }
    end

    children[#children + 1] = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        children = units,
    }

    --Appended last, which is what puts it on top. The Director's side stays
    --live: covering it would trap them behind their own request.
    if not args.director then
        local curtainText = nil

        if rolling then
            curtainText = "Rolling..."
        elseif args.track == NEGConstants.trackLearn
            and live:try_get("learnLocked", false) then
            curtainText = "Just Rolled"
        end

        if curtainText ~= nil then
            local curtain = NEGWidgets.Overlay(curtainText, "sizeL", 1, 0)
            curtain:SetClass("collapsed", false)
            children[#children + 1] = curtain
        end
    end

    return gui.Panel{
        width = args.width,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        rmargin = NEGConstants.traitColumnGap,
        children = children,
    }
end

--- @param args {director: boolean}
--- @return {body: Panel}
function NEGRunPanel.Create(args)
    local director = args.director == true

    local impressionLabel = FieldValue()

    --Read-only in play. The patience it earns was banked when the negotiation
    --opened, so there is nothing here for a change to act on.
    local languageLabel = FieldValue()

    local openCheck = gui.Check{
        classes = { "sizeS" },
        text = "Open",
        width = "100%",
        height = 24,
        halign = "left",
        valign = "center",
        hover = gui.Tooltip(
            "Show the table both scales, the offer, and the real tier outcomes on "
            .. "their roll dialogs. Motivations and pitfalls stay behind their eyes."),
        change = function(element)
            NEGRun.SetOpen(element.value)
        end,
    }

    local statsRow = gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",

        Field("Impression", "40%", impressionLabel),
        Field("Native Language", "30%", languageLabel),
        Field("Sharing", "20%", openCheck),
    }

    local summaryLabel = FieldValue{ textWrap = true, markdown = true }

    local summaryPanel = gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",

        Field("Scenario", "98%", summaryLabel),
    }

    local scalesPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        tmargin = 8,
    }

    local terminalLabel = gui.Label{
        classes = { "sizeS", "collapsed" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 4,
        textWrap = true,
        text = "",
    }

    --What the NPC is saying at this interest. The Director's to read out, so
    --it is never built into a player's window.
    --Holds a line's height even when empty, so a withheld offer reads as "not
    --yet" rather than as nothing to say.
    local offerLabel = FieldValue{
        textWrap = true,
        markdown = true,
        minHeight = 22,
    }

    --Lit means the table is looking at this offer right now. It goes dim the
    --moment interest moves, because that is a different offer.
    local shareButton = gui.Panel{
        classes = { "bgFgPending" },
        width = 20,
        height = 20,
        halign = "left",
        valign = "center",
        rmargin = 6,
        bgimage = NEGConstants.iconShare,
        press = function()
            NEGRun.SetOfferShared(not NEGRun.IsOfferShared())
        end,
    }

    local offerPanel = gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        tmargin = 6,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "top",

            shareButton,

            gui.Label{
                classes = { "sizeS" },
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                text = "Their Offer",
            },
        },

        offerLabel,
    }

    local tray = gui.Panel{
        classes = { "collapsed" },
        width = NEGConstants.sectionWidth,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
    }

    local tracksPanel = gui.Panel{
        classes = { "collapsed" },
        width = NEGConstants.sectionWidth,
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        tmargin = 8,
    }

    --No classes passed in: MCDMDivider copies the caller's options over its
    --own args, so a classes list here REPLACES {"mcdmDivider"} and the rule
    --loses the @border colour that makes it visible at all. Collapse it with
    --SetClass afterwards, which adds rather than replaces.
    local offerRule = gui.MCDMDivider{
        width = NEGConstants.sectionWidth,
        halign = "left",
        vmargin = 6,
    }
    offerRule:SetClass("collapsed", true)

    local tracksRule = gui.MCDMDivider{
        width = NEGConstants.sectionWidth,
        halign = "left",
        vmargin = 6,
    }
    tracksRule:SetClass("collapsed", true)

    local traitsPanel = gui.Panel{
        width = NEGConstants.sectionWidth,
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        tmargin = 6,
    }

    --Everything a player can be shown is behind an eye, so a table watching a
    --negotiation with everything closed needs telling that is deliberate.
    local watchingLabel = gui.Label{
        classes = { "sizeS", "noBold", "fgMuted", "collapsed" },
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "top",
        tmargin = 24,
        textAlignment = "center",
        textWrap = true,
        text = "The negotiation is under way.",
    }

    local workingColumn = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",

        statsRow,
        summaryPanel,
        scalesPanel,
        terminalLabel,
        offerPanel,
        offerRule,
        tray,
        tracksPanel,
        tracksRule,
        traitsPanel,
        watchingLabel,
    }

    --The NPC sits beside the board on the players' window: they are looking at
    --a person, not a form. The Director's window has no room for it and does
    --not need it - the NPC is named in the header.
    --Fills its column and takes its height from that width, so the 2:3 can
    --never push it outside the column it lives in. "image" keeps it
    --true-colour - the theme root tints a bare bgimage panel - and "bordered"
    --is the standard frame, so there is no hand-rolled border here.
    --Fills its column outright. The 2:3 comes from the column being two thirds
    --of the working area's height.
    local portrait = gui.Panel{
        classes = { "image", "bordered" },
        interactable = false,
        width = "100%",
        height = "100%",
        halign = "left",
        valign = "top",
    }

    local portraitColumn = gui.Panel{
        classes = { "collapsed" },
        width = NEGConstants.playerPortraitWidth,
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",
        rmargin = NEGConstants.playerPortraitGap,

        portrait,
    }

    --Two panels on one line: the NPC at a fixed width, the form taking the
    --rest.
    local endingVerdict = gui.Label{
        classes = { "sizeL" },
        width = "98%",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 8,
        textWrap = true,
        text = "",
    }

    local endingOffer = gui.Label{
        classes = { "sizeS", "noBold" },
        width = "98%",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 6,
        textWrap = true,
        markdown = true,
        text = "",
    }

    --Shown to the table when the negotiation closes. The final offer is theirs
    --to read whatever was shared during play.
    local endingPanel = gui.Panel{
        classes = { "collapsed" },
        width = "100% available",
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",

        gui.Label{
            classes = { "sizeL" },
            width = "98%",
            height = "auto",
            halign = "left",
            valign = "top",
            text = "The negotiation is over.",
        },

        endingVerdict,

        gui.MCDMDivider{
            width = NEGConstants.sectionWidth,
            halign = "left",
            vmargin = 10,
        },

        gui.Label{
            classes = { "sizeS" },
            width = "98%",
            height = "auto",
            halign = "left",
            valign = "top",
            text = "Their Final Offer",
        },

        endingOffer,
    }

    local liveBody
    if director then
        liveBody = workingColumn
    else
        workingColumn.selfStyle.width = "100% available"
        workingColumn.selfStyle.height = "100%"

        liveBody = gui.Panel{
            width = "100%",
            height = "100%",
            flow = "horizontal",
            halign = "left",
            valign = "top",

            portraitColumn,
            workingColumn,
            endingPanel,
        }
    end

    local idleNotice = NEGWidgets.Notice("No negotiation is running.")

    --- @param live NEGLive
    --- @return Panel[]
    local function BuildScales(live)
        local interest = live.interest
        local patience = live.patience
        local interestCaption, interestClass = NEGWidgets.InterestCaption(interest)

        if director then
            return {
                NEGWidgets.Scale{
                    which = NEGConstants.scaleInterest,
                    label = "Interest",
                    value = interest,
                    interactive = true,
                    caption = interestCaption,
                    captionClass = interestClass,
                    change = function(value)
                        NEGRun.SetScale(NEGConstants.scaleInterest, value)
                    end,
                    eye = {
                        shown = live:try_get("showInterest", false),
                        change = function(shown)
                            NEGRun.SetRevealed(NEGConstants.scaleInterest, shown)
                        end,
                    },
                },

                NEGWidgets.Scale{
                    which = NEGConstants.scalePatience,
                    label = "Patience",
                    value = patience,
                    interactive = true,
                    change = function(value)
                        NEGRun.SetScale(NEGConstants.scalePatience, value)
                    end,
                    eye = {
                        shown = live:try_get("showPatience", false),
                        change = function(shown)
                            NEGRun.SetRevealed(NEGConstants.scalePatience, shown)
                        end,
                    },
                },
            }
        end

        --A closed scale keeps its bubbles and turns them to question marks.
        local wideOpen = live:try_get("open", false)
        local interestOpen = wideOpen or live:try_get("showInterest", false)
        local patienceOpen = wideOpen or live:try_get("showPatience", false)

        return {
            NEGWidgets.Scale{
                which = NEGConstants.scaleInterest,
                label = "Interest",
                value = interest,
                interactive = false,
                unknown = not interestOpen,
                caption = cond(interestOpen, interestCaption, ""),
                captionClass = interestClass,
            },

            NEGWidgets.Scale{
                which = NEGConstants.scalePatience,
                label = "Patience",
                value = patience,
                interactive = false,
                unknown = not patienceOpen,
            },
        }
    end

    --- How many trait rows a player is allowed to see.
    --- @param live NEGLive
    --- @return number
    local function RevealedTraitCount(live)
        local count = 0
        for _, kind in ipairs({ "motivations", "pitfalls" }) do
            for _, entry in ipairs(NEGRun.Traits(live, kind)) do
                if entry.revealed then
                    count = count + 1
                end
            end
        end
        return count
    end

    local body
    --The table's board does not scroll: it is a thing to glance at, and a
    --scroll bar means somebody is missing half of it. The Director's does,
    --because their side carries the whole negotiation.
    body = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",
        vscroll = director,

        negotiationChanged = function(element)
            element:FireEvent("rebuild")
        end,

        rebuild = function()
            local live = NEGRun.Active()

            --A negotiation still in setup has not started.
            if live == nil then
                liveBody:SetClass("collapsed", true)
                idleNotice:SetClass("collapsed", false)
                return
            end

            local status = live:try_get("status")
            local onStage = director or status ~= NEGConstants.statusSetup

            liveBody:SetClass("collapsed", not onStage)
            idleNotice:SetClass("collapsed", onStage)

            if not onStage then
                return
            end

            --A closed negotiation gives the table its final offer and nothing
            --else to fiddle with.
            local finished = not director and status == NEGConstants.statusEnded
            if not director then
                endingPanel:SetClass("collapsed", not finished)
                workingColumn:SetClass("collapsed", finished)
            end

            if finished then
                local value = NEGConstants.Clamp(live.interest,
                    NEGConstants.scaleMin, NEGConstants.scaleMax)
                local caption, captionClass = NEGWidgets.InterestCaption(value)

                endingVerdict:SetClass("danger", captionClass == "danger")
                endingVerdict:SetClass("warning", captionClass == "warning")
                endingVerdict:SetClass("success", captionClass == "success")
                endingVerdict.text = string.format("%s  %s",
                    NEGRules.OfferName(value), caption:gsub("^%d+%s+", ""))
                endingOffer.text = live:OfferText()
                return
            end

            local def = live:Definition()
            local langid = def ~= nil and def:try_get("languageId", "") or ""

            statsRow:SetClass("collapsed", not director)
            summaryPanel:SetClass("collapsed", false)
            offerPanel:SetClass("collapsed", false)

            portraitColumn:SetClass("collapsed", director)

            local summary = def ~= nil and def:try_get("summary", "") or ""
            summaryLabel.text = summary
            summaryPanel:SetClass("collapsed", trim(summary) == "")

            local wideOpen = live:try_get("open", false)
            local shared = wideOpen or live:try_get("offerShared", false)
            shareButton:SetClass("collapsed", not director)
            shareButton:SetClass("bgAccent", director and shared)
            shareButton:SetClass("bgFgPending", director and not shared)

            --The label stands either way, so the table knows an offer exists
            --and is being held back rather than that there is none.
            offerLabel.text = cond(director or shared, live:OfferText(), "")

            openCheck.value = wideOpen

            if director then
                local impression = NEGConstants.impressionDefault
                if def ~= nil then
                    impression = def:try_get("impression", impression)
                end
                impressionLabel.text = NEGRules.ImpressionText(impression)

                local language = NEGRules.LanguageName(langid)
                languageLabel.text = cond(language ~= "", language, "None set")
            else
                local portraitid = def ~= nil and def:try_get("portraitid", "") or ""
                portrait:SetClass("collapsed", portraitid == "")
                if portraitid ~= "" then
                    portrait.bgimage = portraitid
                end
            end

            local scales = BuildScales(live)
            scalesPanel.children = scales

            local reason = live:TerminalReason()
            terminalLabel:SetClass("collapsed", not director or reason == "")
            terminalLabel:SetClass("warning", reason ~= "")
            terminalLabel.text = reason

            --The floor stands on both windows; the widgets decide whose token
            --this client may pick up.
            offerRule:SetClass("collapsed", false)
            tray:SetClass("collapsed", false)
            tracksPanel:SetClass("collapsed", false)
            tracksRule:SetClass("collapsed", false)

            tray.children = {
                NEGWidgets.Tray(NEGRun.FreeHeroes(live), function(charid)
                    for _, slot in ipairs({
                        NEGConstants.slotLead,
                        NEGConstants.slotAssist,
                        NEGConstants.slotLearn,
                    }) do
                        local entry = NEGRun.Slot(live, slot)
                        if entry ~= nil and entry.charid == charid then
                            NEGRun.Unstage(slot)
                            return
                        end
                    end
                end),
            }

            tracksPanel.children = {
                TrackPanel(live, {
                    track = NEGConstants.trackArgument,
                    title = "Make Argument",
                    width = NEGConstants.trackArgumentWidth,
                    director = director,
                    slots = {
                        { key = NEGConstants.slotLead, label = "Lead" },
                        { key = NEGConstants.slotAssist, label = "Assist" },
                    },
                }),

                TrackPanel(live, {
                    track = NEGConstants.trackLearn,
                    title = "Learn Motivation / Pitfall",
                    width = NEGConstants.trackLearnWidth,
                    director = director,
                    slots = {
                        { key = NEGConstants.slotLearn, label = "Reader" },
                    },
                }),
            }

            traitsPanel.children = {
                TraitColumn(live, "motivations", "Motivations", director),
                TraitColumn(live, "pitfalls", "Pitfalls", director),
            }

            watchingLabel:SetClass("collapsed", true)
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        liveBody,
        idleNotice,
    }

    return { body = body }
end
